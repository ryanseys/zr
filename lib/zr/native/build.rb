# frozen_string_literal: true

require "digest/sha2"
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
require_relative "../config"
require_relative "parallel"

module Zr
  module Native
    # Turns IR functions and data into the output that a target runs. The
    # target selects the parts: its backend writes the machine code, its
    # object writer writes the object, and its linker writes the binary
    # (`Link::Darwin`, `Link::Static`). A wasm32 target has one module and
    # no link step.
    module Build
      module_function

      # A unit with fewer IR instructions than this assembles in this
      # process. For a program's own functions, a worker costs more than
      # it saves.
      PARALLEL_THRESHOLD = 200_000

      # The number of workers for a large unit: `ZR_JOBS`, else one per
      # core, at most six. More than six workers compete for memory. Time
      # to build the runtime object on a twelve-core M2 Pro with 16 GB:
      #
      #     jobs      2      4      6      8     12
      #     seconds  17.4   11.4    9.5   11.8   26.9
      #
      # This is the maximum. At fork time, `Parallel.afforded` lowers it
      # from the parent's memory, which is about 100 times larger for the
      # compiled compiler than for the compiler under ruby. `ZR_JOBS`
      # overrides both limits; the table above was measured with it.
      def jobs = Config.current.jobs

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

      # Returns nil, or the message of the step that refused. `objects` are
      # prebuilt objects to link with this one. `strip` removes code that
      # nothing calls. `linker` (`ZR_LINKER`) selects the linker when the
      # target has more than one.
      def binary(functions, data, out, work:, raw: [], assembled: [], objects: [], strip: false, linker: Config.current.linker, target: Target.default, jobs: Build.jobs)
        image = unit(functions, data, raw: raw, assembled: assembled, export: !objects.empty?, target: target, jobs: jobs)
        linker(target).link(image, out, work: work, objects: objects, strip: strip, linker: linker, target: target)
      rescue Backend::Refused => e
        e.message
      end

      # Links a `Zr::Program` into a binary. The runtime object comes from
      # the cache; this emits only the program's own functions and data.
      # A program that uses eval keeps all symbols, because its JIT finds
      # kernel functions by name. Functions that `assemble` already
      # assembled go in unchanged.
      def program(program, out, work:, jobs: Build.jobs)
        objects = [runtime_object(program.runtime, jobs: jobs)]
        objects << eval_support_object(program.evals, jobs: jobs) if program.evals
        functions, assembled = program.functions.partition { |f| f.is_a?(IR::Function) }
        Zr.clock("program object written and linked") do
          binary(functions, program.data, out, work: work, assembled: assembled, objects: objects, strip: !program.evals,
                                                           target: program.runtime.target, jobs: jobs)
        end
      end

      # Lowers a program for a binary. It assembles the functions of each
      # file after it lowers that file, so the full IR is never in memory
      # at one time. It builds the runtime object first and then releases
      # the runtime's IR, so on a cold cache the two are not in memory
      # together.
      def lower(source, file, target: Target.default, jobs: Build.jobs)
        runtime = Zr.runtime(target)
        runtime.description
        runtime_object(runtime, jobs: jobs)
        runtime.release
        Zr.program(source, file, target: target) { |f, entry| assemble(f, entry, target: target) }
      end

      # Prepares and assembles one function immediately after `Zr.program`
      # lowers it. `entry` gives the spelling of its symbols.
      def assemble(function, entry, target: Target.default)
        IR::Passes.prepare(function)
        backend(target).assemble(function, backend(target)::Spelled.new(entry))
      end

      # Links `objects` once, at the fixed addresses that every program
      # links against (`Obj::MachO::Prelink`). The name of a cached object
      # is the digest of its inputs, so the cache keeps its prelinked base
      # under those names. Objects that are not in the cache are linked
      # each time.
      def prelink(objects)
        path = prelink_path(objects)
        return Obj::MachO::Prelink.build(objects.map { |o| File.binread(o) }) unless path

        # Kept in memory for the life of the process, and on disk. Reading
        # and parsing the 25 MB image took 21% of a link, and a test tier
        # links thousands of times. A link never writes to it.
        kept = (@prelinks ||= {})[path] ||= File.exist?(path) && Obj::MachO::Prelink.load(File.binread(path))
        return kept if kept

        Zr.clock("objects prelinked") do
          Obj::MachO::Prelink.build(objects.map { |o| File.binread(o) }).tap { |base| Zr.write_cache(path, base.dump) }
        end
      end

      # Returns the cache path of the prelink of `objects`, or nil when the
      # objects are not in the cache. The object names are the digests of
      # their inputs. `Zr.link_digest` adds the other input of the image:
      # the linker's own files, which the object digests do not include
      # on purpose.
      def prelink_path(objects)
        cache = File.expand_path(Paths.cache)
        return nil if objects.empty? || objects.any? { |o| File.dirname(File.expand_path(o)) != cache }

        key = Digest::SHA256.hexdigest([*objects.map { |o| File.basename(o) }, Zr.link_digest].join("\n"))
        File.join(Paths.cache, "prelink-#{key}.bin")
      end

      # The cache path of the skeleton of `objects`, next to their prelink.
      def skeleton_path(objects) = prelink_path(objects)&.sub(/prelink-(\h+)\.bin\z/, 'skeleton-\1.bin')

      # Returns the path of the skeleton file for `objects`: the bytes that
      # every binary linked against them starts with (`Obj::MachO::Skeleton`).
      # It is in the cache, next to its prelink, and is written once per
      # prelink. Returns nil when the prelink is not in the cache.
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

      # The runtime's object, built once per digest (the digest includes
      # the target).
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

      # Writes functions and data to one object file. `export` makes all
      # data visible to the linker, for an object that other objects refer to.
      def object(functions, data, obj, raw: [], export: false, target: Target.default, jobs: Build.jobs)
        File.binwrite(obj, writer(target).write(unit(functions, data, raw: raw, export: export, target: target, jobs: jobs)))
        nil
      rescue Backend::Refused => e
        e.message
      end

      # Returns the same as an `Obj::Unit`, the input of an object writer
      # and of the JIT loader. Inlining needs the whole unit, so it runs
      # here. The passes and assembly of a function need only the function
      # and the unit's symbol names, so a large unit runs them in `jobs`
      # workers. `raw` names the raw functions (`Machine::RAW`), whose code
      # comes from the backend. `assembled` are functions that are already
      # machine code.
      def unit(functions, data, raw: [], assembled: [], export: false, target: Target.default, jobs: Build.jobs, floor: PARALLEL_THRESHOLD)
        IR::Passes.inline(functions)
        emitter = backend(target)
        code = assembled + raw.map { |name| emitter::Stub.function(name) }
        emitter.unit(functions, data, raw: code, export: export) do |all, defined|
          Parallel.map(all, jobs: jobs, weight: ->(f) { f.blocks.sum { |b| b.insts.size } }, floor: floor) do |f|
            IR::Passes.prepare(f)
            emitter.assemble(f, defined)
          end
        end
      end

      # Writes the same functions and data as one WASI module. A raw
      # function, or a libc call that neither the OS layer nor
      # `Backend::Wasm.libc_shims` supplies, has no wasm form. A stop
      # function is put in its place; it stops with the function's name
      # when called. Data from another library also has no wasm form: a
      # zero word is put in its place, because every call that reads it
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

      # Writes a `Zr::Program` as one WASI module. The runtime comes from
      # the cached prelude; this emits only the program's own functions.
      #
      # On wasm, eval support is the tree-walking interpreter
      # (lib/zr/eval/walk.rb): the front end and no backend. Wasm has no
      # second object to link, so a program that uses eval gets a prelude
      # that also contains eval support. Its 16,000 functions then compile
      # once for each cache, not once for each program (about 280 s).
      def wasm_program(program, out)
        pre = wasm_prelude(program.runtime, pending_for(program), program.evals || nil)
        functions = program.functions
        data = program.data.dup
        zero_words(functions, data, pre.data_at.keys)
        functions += stops(functions, [], data, pre.functions)
        IR::Passes.inline(functions).each { |f| IR::Passes.prepare(f) }
        File.binwrite(out, Backend::Wasm.emit(functions, data, prelude: pre))
        nil
      rescue Backend::Refused => e
        e.message
      end

      # The runtime symbols that `program` defines. The runtime's prelude
      # leaves these symbols pending.
      def pending_for(program)
        wants = program.runtime.wants
        { functions: wants[:functions] & program.functions.map(&:name), data: wants[:data] & program.data.map(&:name) }
      end

      # The runtime's wasm prelude, with eval support when `support` is
      # given. It is emitted once for each digest and set of pending
      # symbols, and kept in the cache.
      #
      # It is also kept in memory for the life of the process, as the
      # prelink is. The prelude is 41 MB of Marshal, and a test tier builds
      # one module for each example. A worker forked after the first build
      # shares the one copy. A build never writes to it.
      def wasm_prelude(runtime, pending, support = nil)
        key = Digest::SHA256.hexdigest("#{runtime.digest}\n#{support&.key}\n#{pending.inspect}")
        path = File.join(Paths.cache, "wasm-#{key}.marshal")
        kept = (@wasm_preludes ||= {})[path] ||= File.exist?(path) && Marshal.load(File.binread(path))
        return kept if kept

        functions = support ? runtime.functions + support.functions : runtime.functions
        data = support ? runtime.data + support.data : runtime.data.dup
        zero_words(functions, data, pending[:data])
        functions += stops(functions, runtime.raw, data, pending[:functions])
        IR::Passes.inline(functions).each { |f| IR::Passes.prepare(f) }
        pre = Backend::Wasm.prelude(functions, data, pending: pending)
        Zr.write_cache(path, Marshal.dump(pre))
        @wasm_preludes[path] = pre
      end

      # The data symbols that `functions` refer to and `data` does not define.
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

      # Stop functions for the raw functions and for each undefined callee
      # that is not a wasm import, not in `Backend::Wasm.libc_shims` and
      # not in `known`.
      def stops(functions, raw, data, known)
        out = raw.map do |name|
          r = Machine::RAW.fetch(name)
          stop(name, r.params.map { |t| Machine::TYPES.fetch(t) }, Machine::TYPES.fetch(r.ret), data)
        end
        defined = Set.new(functions.map(&:name) + out.map(&:name) + Backend::Wasm.libc_shims + known)
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
