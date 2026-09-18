# frozen_string_literal: true

require "digest"
require "etc"
require "json"
require "fileutils"
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
require_relative "../zr"
require_relative "../clock"
require_relative "parallel"

module Ze0
  module Native
    # IR functions and data to what a target runs. The target names the
    # pieces: its backend writes the machine code, its object writer the
    # object, and its linker the binary (`Link::Darwin`, `Link::Static`);
    # a wasm32 target has one module and no link.
    module Build
      module_function

      # Which linker writes a binary: `auto`, `ruby` or `cc`.
      ROAD = ENV.fetch("ZE0_LINK", "auto")

      # A unit of fewer IR instructions than this assembles in this
      # process: a worker costs more than a program's own functions do.
      PARALLEL_FLOOR = 200_000

      # How many workers a large unit assembles in: `ZE0_JOBS`, else one
      # per core up to six. Each worker holds half a gigabyte or more of
      # its own, and on a 16 GB machine eight took longer than six and
      # twelve as long as one.
      def jobs = Integer(ENV.fetch("ZE0_JOBS") { [Etc.nprocessors, 6].min })

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
      # nothing calls. `road` (`ZE0_LINK`) picks the linker where the
      # target has more than one.
      def binary(functions, data, out, work:, raw: [], objects: [], strip: false, road: ROAD, target: Target.default, jobs: Build.jobs)
        image = unit(functions, data, raw: raw, export: !objects.empty?, target: target, jobs: jobs)
        linker(target).link(image, out, work: work, objects: objects, strip: strip, road: road, target: target)
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
        objects << road_object(program.evals, jobs: jobs) if program.evals
        functions, raw = program.functions.partition { |f| f.is_a?(IR::Function) }
        Ze0.clock("program object written and linked") do
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
        cache = File.expand_path(Zr::CACHE)
        named = !objects.empty? && objects.all? { |o| File.dirname(File.expand_path(o)) == cache }
        return Obj::MachO::Prelink.build(objects.map { |o| File.binread(o) }) unless named

        path = File.join(Zr::CACHE, "prelink-#{Digest::SHA256.hexdigest(objects.map { |o| File.basename(o) }.join("\n"))}.bin")
        # Kept for the life of the process as well as on disk: reading
        # and parsing the 25 MB image was 21% of a link, and a check tier
        # links thousands of times. Nothing a link does writes to it.
        kept = (@prelinks ||= {})[path] ||= File.exist?(path) && Obj::MachO::Prelink.load(File.binread(path))
        return kept if kept

        Ze0.clock("objects prelinked") do
          Obj::MachO::Prelink.build(objects.map { |o| File.binread(o) }).tap { |base| Zr.write_cache(path, base.dump) }
        end
      end

      # The compiler's object, built once per road.
      def road_object(road, jobs: Build.jobs)
        obj = road.object_path
        return obj if File.exist?(obj)

        Dir.mktmpdir("ze0-road-") do |work|
          fresh = File.join(work, "road.o")
          why = Ze0.clock("eval road object assembled and written") { object(road.functions, road.data, fresh, export: true, target: road.target, jobs: jobs) }
          raise "the compiler did not build: #{why}" if why

          Zr.write_cache(obj, File.binread(fresh))
        end
        obj
      end

      # The runtime's object, built once per digest (which names the target).
      def runtime_object(runtime, jobs: Build.jobs)
        obj = File.join(Zr::CACHE, "rt-#{runtime.digest}.o")
        return obj if File.exist?(obj)

        Dir.mktmpdir("ze0-rt-") do |work|
          fresh = File.join(work, "rt.o")
          why = Ze0.clock("runtime object assembled and written") do
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
      def unit(functions, data, raw: [], export: false, target: Target.default, jobs: Build.jobs, floor: PARALLEL_FLOOR)
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
      def wasm_program(program, out)
        rt = program.runtime
        pending = { functions: rt.wants[:functions] & program.functions.map(&:name),
                    data: rt.wants[:data] & program.data.map(&:name) }
        pre = wasm_prelude(rt, pending)
        data = program.data.dup
        zero_words(program.functions, data, pre.data_at.keys)
        functions = program.functions + stops(program.functions, [], data, pre.functions)
        IR::Passes.inline(functions).each { |f| IR::Passes.prepare(f) }
        File.binwrite(out, Backend::Wasm.emit(functions, data, prelude: pre))
        nil
      rescue Backend::Refused => e
        e.message
      end

      # The runtime's wasm prelude, emitted once per digest and the
      # symbols it waits on, and kept under the cache.
      def wasm_prelude(runtime, pending)
        key = Digest::SHA256.hexdigest("#{runtime.digest}\n#{pending.inspect}")
        path = File.join(Zr::CACHE, "wasm-#{key}.marshal")
        return Marshal.load(File.binread(path)) if File.exist?(path)

        data = runtime.data.dup
        zero_words(runtime.functions, data, pending[:data])
        functions = runtime.functions + stops(runtime.functions, runtime.raw, data, pending[:functions])
        IR::Passes.inline(functions).each { |f| IR::Passes.prepare(f) }
        pre = Backend::Wasm.prelude(functions, data, pending: pending)
        Zr.write_cache(path, Marshal.dump(pre))
        pre
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
        defined = functions.map(&:name) + out.map(&:name) + Backend::Wasm.floor + known
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
        message = "ze0: #{name} has no wasm form\n"
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
