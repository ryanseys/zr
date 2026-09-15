# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"
require_relative "../ir"
require_relative "../ir/verify"
require_relative "../target"
require_relative "link"
require_relative "link/darwin"
require_relative "link/static"
require_relative "../backend/aarch64"
require_relative "../backend/wasm"
require_relative "../obj/macho/object_file"
require_relative "../obj/elf/object_file"
require_relative "../machine/lower"
require_relative "../zr"

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
      def binary(functions, data, out, work:, raw: [], objects: [], strip: false, road: ROAD, target: Target.default)
        image = unit(functions, data, raw: raw, export: !objects.empty?, target: target)
        linker(target).link(image, out, work: work, objects: objects, strip: strip, road: road, target: target)
      rescue Backend::Refused => e
        e.message
      end

      # A `Zr::Program` to a binary: its runtime from the cache, its own
      # functions and data emitted now. A program that evals keeps every
      # symbol, since its JIT finds kernel functions by name.
      def program(program, out, work:)
        objects = [runtime_object(program.runtime)]
        objects << road_object(program.evals) if program.evals
        binary(program.functions, program.data, out, work: work, objects: objects, strip: !program.evals,
                                                         target: program.runtime.target)
      end

      # The compiler's object, built once per road.
      def road_object(road)
        obj = road.object_path
        return obj if File.exist?(obj)

        Dir.mktmpdir("ze0-road-") do |work|
          fresh = File.join(work, "road.o")
          why = object(road.functions, road.data, fresh, export: true, target: road.target)
          raise "the compiler did not build: #{why}" if why

          Zr.write_cache(obj, File.binread(fresh))
        end
        obj
      end

      # The runtime's object, built once per digest (which names the target).
      def runtime_object(runtime)
        obj = File.join(Zr::CACHE, "rt-#{runtime.digest}.o")
        return obj if File.exist?(obj)

        Dir.mktmpdir("ze0-rt-") do |work|
          fresh = File.join(work, "rt.o")
          why = object(runtime.functions, runtime.data, fresh, raw: runtime.raw, export: true, target: runtime.target)
          raise "the runtime did not build: #{why}" if why

          Zr.write_cache(obj, File.binread(fresh))
        end
        obj
      end

      # Functions and data to one object file. `export` makes every data
      # object visible to the link, for an object another refers to.
      def object(functions, data, obj, raw: [], export: false, target: Target.default)
        File.binwrite(obj, writer(target).write(unit(functions, data, raw: raw, export: export, target: target)))
        nil
      rescue Backend::Refused => e
        e.message
      end

      # The same, as an `Obj::Unit`: what an object writer and the JIT
      # loader both take.
      def unit(functions, data, raw: [], export: false, target: Target.default)
        functions.each { |f| IR::Verify.check(f) }
        backend(target).unit(functions, data, raw: raw, export: export)
      end

      # The same functions and data as one WASI module. A raw function,
      # or a libSystem call the module has no shim for, has no wasm form:
      # its place is taken by a function that stops by name when called.
      # Data another library defines (an oniguruma encoding) has none
      # either: its place is a zero word, since every call that reads it
      # is a stop.
      def wasm(functions, data, out, raw: [])
        data = data.dup
        zero_words(functions, data, [])
        functions += stops(functions, raw, data, [])
        functions.each { |f| IR::Verify.check(f) }
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
        functions.each { |f| IR::Verify.check(f) }
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
        functions.each { |f| IR::Verify.check(f) }
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
