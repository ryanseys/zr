# frozen_string_literal: true

require "digest/sha2"
require "etc"
require "json"
require_relative "../ir"
require_relative "../ir/passes"
require_relative "../target"
require_relative "link"
require_relative "link/darwin"
require_relative "link/static"
require_relative "../backend/aarch64"
require_relative "../backend/wasm"
require_relative "../obj/macho/object_file"
require_relative "../obj/elf/object_file"
require_relative "../obj/macho/prelink"
require_relative "../machine/lower"
require_relative "../runtime"
require_relative "../clock"
require_relative "parallel"

module Zr
  module Native
    # IR functions and data to what a target runs. The target names the
    # pieces: its backend writes the machine code, its object writer the
    # object, and its linker the binary (`Link::Darwin`, `Link::Static`);
    # a wasm32 target has one module and no link.
    module Build
      module_function

      # Which linker writes a binary (`ZR_LINKER`): `auto` (zr's own, and
      # cc for what it cannot link), `ruby` (zr's own only) or `cc`.
      LINKERS = %w[auto ruby cc].freeze
      LINKER = (ENV["ZR_LINKER"].to_s.empty? ? "auto" : ENV["ZR_LINKER"]).tap do |name|
        raise ArgumentError, "ZR_LINKER=#{name}: use #{LINKERS.join(", ")}" unless LINKERS.include?(name)
      end

      # A unit of fewer IR instructions than this assembles in this
      # process: a worker costs more than a program's own functions do.
      PARALLEL_THRESHOLD = 200_000

      # How many workers a large unit assembles in: `ZR_JOBS`, else one
      # per core up to six. Past six they take the memory from each
      # other. The runtime object, timed on a twelve-core M2 Pro with
      # 16 GB:
      #
      #     jobs      2      4      6      8     12
      #     seconds  17.4   11.4    9.5   11.8   26.9
      #
      # This is the ceiling. `Parallel.afforded` lowers it at the moment
      # of the fork by what the parent holds, which is what one more
      # worker costs and is a hundredfold apart between the compiler
      # under ruby and the compiled compiler.
      #
      # `ZR_JOBS` overrules both, which is how that row was measured.
      def jobs = Integer(ENV.fetch("ZR_JOBS") { [Etc.nprocessors, 6].min })

      # The native backend for `target`.
      def backend(target)
        { aarch64: Backend::Aarch64 }.fetch(target.arch) { raise ArgumentError, "no native backend for #{target}" }
      end

      # The object writer for `target`.
      def writer(target)
        writers = { macho: Obj::MachO::ObjectFile, elf: Obj::Elf::ObjectFile }
        writers.fetch(target.object_format) { raise ArgumentError, "no object writer for #{target}" }
      end

      # The linker for `target`.
      def linker(target)
        { darwin: Link::Darwin, static: Link::Static }.fetch(target.link) { raise ArgumentError, "no linker for #{target}" }
      end

      # Answers nil, or the message of the step that refused. `objects` are
      # prebuilt objects linked in beside this one; `strip` leaves out what
      # nothing calls. `road` (`ZR_LINKER`) picks the linker where the
      # target has more than one.
      def binary(functions, data, out, work:, raw: [], objects: [], strip: false, linker: LINKER, target: Target.default, jobs: Build.jobs)
        image = unit(functions, data, raw: raw, export: !objects.empty?, target: target, jobs: jobs)
        linker(target).link(image, out, work: work, objects: objects, strip: strip, linker: linker, target: target)
      rescue Backend::Refused => e
        e.message
      end

      # A `Zr::Program` to a binary: its runtime from the cache, its own
      # functions and data emitted now. A program that evals keeps every
      # symbol, since its JIT finds kernel functions by name.
      #
      # Functions already assembled (`assemble`) go in as they are.
      def program(program, out, work:, jobs: Build.jobs)
        objects = [runtime_object(program.runtime, jobs: jobs)]
        objects << eval_support_object(program.evals, jobs: jobs) if program.evals
        functions, raw = program.functions.partition { |f| f.is_a?(IR::Function) }
        Zr.clock("program object written and linked") do
          binary(functions, program.data, out, work: work, raw: raw, objects: objects, strip: !program.evals,
                                                           target: program.runtime.target, jobs: jobs)
        end
      end

      # A program lowered for a binary, its functions assembled as each
      # file is lowered so its IR never stands all at once. The runtime's
      # object is made first and the runtime's IR let go, so on a cold
      # cache the two never stand in memory together either.
      def lower(source, file, target: Target.default, jobs: Build.jobs)
        runtime = Zr.runtime(target)
        runtime.description
        runtime_object(runtime, jobs: jobs)
        runtime.release
        Zr.program(source, file, target: target) { |f, entry| assemble(f, entry, target: target) }
      end

      # One function of a program as `Zr.program` lowers it, checked and
      # assembled at once, its own symbols the ones `entry` spells.
      def assemble(function, entry, target: Target.default)
        IR::Passes.prepare(function)
        backend(target).assemble(function, backend(target)::Spelled.new(entry))
      end

      # `objects` linked once, at the addresses every program links beside
      # (`Obj::MachO::Prelink`). Objects in the cache are named by the
      # digest of what made them, so their base is kept under the names;
      # other objects are linked each time.
      def prelink(objects)
        path = prelink_path(objects)
        return Obj::MachO::Prelink.build(objects.map { |o| File.binread(o) }) unless path

        # Kept for the life of the process as well as on disk: reading
        # and parsing the 25 MB image was 21% of a link, and a check tier
        # links thousands of times. Nothing a link does writes to it.
        kept = (@prelinks ||= {})[path] ||= File.exist?(path) && Obj::MachO::Prelink.load(File.binread(path))
        return kept if kept

        Zr.clock("objects prelinked") do
          Obj::MachO::Prelink.build(objects.map { |o| File.binread(o) }).tap { |base| Zr.write_cache(path, base.dump) }
        end
      end

      # Where the prelink of `objects` is kept, or nil for objects that
      # are not the cache's. The objects name themselves after the digest
      # of what lowered them, and `Zr.link_digest` is the rest of what
      # the image depends on: the linker's own files, which that digest
      # leaves out on purpose.
      def prelink_path(objects)
        cache = File.expand_path(Zr.cache)
        return nil if objects.empty? || objects.any? { |o| File.dirname(File.expand_path(o)) != cache }

        key = Digest::SHA256.hexdigest([*objects.map { |o| File.basename(o) }, Zr.link_digest].join("\n"))
        File.join(Zr.cache, "prelink-#{key}.bin")
      end

      # Where the skeleton of `objects` is kept, beside their prelink.
      def skeleton_path(objects) = prelink_path(objects)&.sub(/prelink-(\h+)\.bin\z/, 'skeleton-\1.bin')

      # The skeleton of a binary linked beside `objects` -- the bytes every
      # such binary begins with (`Obj::MachO::Skeleton`) -- as a file under
      # the cache, beside the prelink it is cut from; nil where the prelink
      # is not a cached one. Written once per prelink and kept.
      def skeleton(objects)
        path = skeleton_path(objects) or return nil
        (@skeletons ||= {})[path] ||= File.exist?(path) ? path : Zr.write_cache(path, Obj::MachO::Skeleton.bytes(prelink(objects)))
      end

      # The eval support object, built once for each key.
      def eval_support_object(support, jobs: Build.jobs)
        obj = support.object_path
        return obj if File.exist?(obj)

        Paths.tmpdir("zr-eval-") do |work|
          fresh = File.join(work, "eval.o")
          why = Zr.clock("eval support object assembled and written") { object(support.functions, support.data, fresh, export: true, target: support.target, jobs: jobs) }
          raise "the compiler did not build: #{why}" if why

          Zr.write_cache(obj, File.binread(fresh))
        end
        obj
      end

      # The runtime's object, built once per digest (which names the target).
      def runtime_object(runtime, jobs: Build.jobs)
        obj = runtime.object_path
        return obj if File.exist?(obj)

        Paths.tmpdir("zr-runtime-") do |work|
          fresh = File.join(work, "runtime.o")
          why = Zr.clock("runtime object assembled and written") do
            object(runtime.functions, runtime.data, fresh, raw: runtime.raw, export: true, target: runtime.target, jobs: jobs)
          end
          raise "the runtime did not build: #{why}" if why

          Zr.write_cache(obj, File.binread(fresh))
        end
        obj
      end

      # Functions and data to one object file. `export` makes every data
      # object visible to the link, for an object another refers to.
      def object(functions, data, obj, raw: [], export: false, target: Target.default, jobs: Build.jobs)
        File.binwrite(obj, writer(target).write(unit(functions, data, raw: raw, export: export, target: target, jobs: jobs)))
        nil
      rescue Backend::Refused => e
        e.message
      end

      # The same, as an `Obj::Unit`: what an object writer and the JIT
      # loader both take. The inlining sees the whole unit, so it runs
      # here; each function's passes and assembly need only the function
      # and the unit's names, so a large unit runs them in `jobs` workers.
      def unit(functions, data, raw: [], export: false, target: Target.default, jobs: Build.jobs, floor: PARALLEL_THRESHOLD)
        IR::Passes.inline(functions)
        emitter = backend(target)
        emitter.unit(functions, data, raw: raw, export: export) do |all, defined|
          Parallel.map(all, jobs: jobs, weight: ->(f) { f.blocks.sum { |b| b.insts.size } }, floor: floor) do |f|
            IR::Passes.prepare(f)
            emitter.assemble(f, defined)
          end
        end
      end

      # The same functions and data as one WASI module. A raw function,
      # or a libc call neither the OS layer nor the floor answers, has no
      # wasm form:
      # its place is taken by a function that stops by name when called.
      # Data another library defines has none
      # either: its place is a zero word, since every call that reads it
      # is a stop.
      def wasm(functions, data, out, raw: [])
        data = data.dup
        zero_words(functions, data, [])
        functions += stops(functions, raw, data, [])
        IR::Passes.inline(functions).each { |f| IR::Passes.prepare(f) }
        File.binwrite(out, Backend::Wasm.emit(functions, data))
        nil
      rescue Backend::Refused => e
        e.message
      end

      # A `Zr::Program` as one WASI module, its runtime from the cached
      # prelude: only the program's own functions are emitted now.
      #
      # A program that evals carries a road, and the module holds it as the
      # binary does: there is no second object to link on wasm, so the
      # road's functions and data go in beside the program's own. The road
      # a wasm program carries is the walk (lib/zr/eval/walk.rb) -- the
      # front end and no backend -- so what it adds is the parser and the
      # tree it builds.
      def wasm_program(program, out)
        rt = program.runtime
        support = program.evals
        functions = support ? program.functions + support.functions : program.functions
        data = support ? program.data + support.data : program.data
        pre = wasm_prelude(rt, pending_for(program))
        data = data.dup
        zero_words(functions, data, pre.data_at.keys)
        functions += stops(functions, [], data, pre.functions)
        IR::Passes.inline(functions).each { |f| IR::Passes.prepare(f) }
        File.binwrite(out, Backend::Wasm.emit(functions, data, prelude: pre))
        nil
      rescue Backend::Refused => e
        e.message
      end

      # The symbols of the runtime's that `program` (with its road)
      # defines: what the runtime's prelude waits on.
      def pending_for(program)
        rt = program.runtime
        support = program.evals
        functions = support ? program.functions + support.functions : program.functions
        data = support ? program.data + support.data : program.data
        { functions: rt.wants[:functions] & functions.map(&:name), data: rt.wants[:data] & data.map(&:name) }
      end

      # The runtime's wasm prelude, emitted once per digest and the
      # symbols it waits on, and kept under the cache.
      #
      # Kept for the life of the process as well, as the prelink is: the
      # prelude is 41 MB of Marshal, and a check tier that builds a
      # module a row read and rebuilt it every time. A worker forked
      # after the first build shares the one copy. Nothing a build does
      # writes to it.
      def wasm_prelude(runtime, pending)
        key = Digest::SHA256.hexdigest("#{runtime.digest}\n#{pending.inspect}")
        path = File.join(Zr.cache, "wasm-#{key}.marshal")
        kept = (@wasm_preludes ||= {})[path] ||= File.exist?(path) && Marshal.load(File.binread(path))
        return kept if kept

        data = runtime.data.dup
        zero_words(runtime.functions, data, pending[:data])
        functions = runtime.functions + stops(runtime.functions, runtime.raw, data, pending[:functions])
        IR::Passes.inline(functions).each { |f| IR::Passes.prepare(f) }
        pre = Backend::Wasm.prelude(functions, data, pending: pending)
        Zr.write_cache(path, Marshal.dump(pre))
        @wasm_preludes[path] = pre
      end

      # The data symbols `functions` name that `data` does not define.
      def foreign(functions, data)
        named = data.map(&:name)
        functions.flat_map { |f| f.globals.reject(&:colocated).map(&:symbol) }.uniq - named
      end

      # A zero word into `data` for each foreign data symbol not in `known`.
      def zero_words(functions, data, known)
        (foreign(functions, data) - known).each do |symbol|
          data << Obj::Data.new(symbol, :data_const, "\0".b * 8, align: 8)
        end
      end

      # Stop functions for the raw functions and for every undefined
      # callee that is not a wasm import, not in the module's floor and
      # not in `known`.
      def stops(functions, raw, data, known)
        out = raw.map do |r|
          params, ret = Backend::Aarch64::Stub::ALL.fetch(r.name)
          stop(r.name, params.map { |t| Machine::TYPES.fetch(t.to_s) }, Machine::TYPES.fetch(ret.to_s), data)
        end
        defined = functions.map(&:name) + out.map(&:name) + Backend::Wasm.libc_shims + known
        functions.each do |f|
          f.callees.each do |c|
            next if c.from || defined.include?(c.symbol)

            sig = f.sigs.find { |x| x.sig == c.sig }
            out << stop(c.symbol, sig.params, sig.ret, data)
            defined << c.symbol
          end
        end
        out
      end

      def stop(name, params, ret, data)
        message = "zr: #{name} has no wasm form\n"
        bytes = "zr_stop_#{name}"
        data << Obj::Data.new(bytes, :text_const, message.b, align: 1)
        f = IR::Function.new(name, params, ret)
        f.call(f.callee("write", %w[i32 i64 i64], "i64", colocated: false), [f.iconst("i32", 2), f.symbol_value(f.symbol(bytes)), f.iconst("i64", message.bytesize)])
        f.call(f.callee("abort", [], nil, colocated: false), [])
        f.ret(ret.nil? ? nil : (ret == "f64" ? f.bitcast("f64", f.iconst("i64", 0)) : f.iconst(ret, 0)))
        f
      end
    end
  end
end
