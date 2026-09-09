# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"
require_relative "../ir"
require_relative "../ir/verify"
require_relative "cranelift"
require_relative "ruby"
require_relative "../deps"
require_relative "../ir/wasm"
require_relative "../machine/lower"
require_relative "../zr"

module Ze0
  module Native
    # IR functions and data objects to a binary, on the road named: the
    # Ruby road assembles in process; the Cranelift road renders the text
    # and a sidecar for `clif2obj`. Both end in `cc`.
    module Build
      module_function

      ROADS = { "ruby" => Ruby, "cranelift" => Cranelift }.freeze

      def road(name, root)
        ROADS.fetch(name) { raise ArgumentError, "no native road named #{name.inspect} (ruby, cranelift)" }.new(root)
      end

      # Answers nil, or the message of the step that refused. `objects`
      # are prebuilt objects linked in beside this one.
      def binary(functions, data, out, road:, work:, raw: [], objects: [])
        obj = File.join(work, "unit.o")
        (why = object(functions, data, obj, road: road, raw: raw, export: !objects.empty?)) and return why
        road.link(objects + [obj], out, archives: Deps.build(road.root))
      end

      # A `Zr::Program` to a binary: its runtime from the cache, its own
      # functions and data emitted now.
      def program(program, out, road:, work:)
        rt = runtime_object(program.runtime, road)
        binary(program.functions, program.data, out, road: road, work: work, objects: [rt])
      end

      # The runtime's object on `road`, built once per digest.
      def runtime_object(runtime, road)
        obj = File.join(Zr::CACHE, "#{road.class.name.split("::").last.downcase}-#{runtime.digest}.o")
        return obj if File.exist?(obj)

        Dir.mktmpdir("ze0-rt-") do |work|
          fresh = File.join(work, "rt.o")
          why = object(runtime.functions, runtime.data, fresh, road: road, raw: runtime.raw, export: true)
          raise "the runtime did not build: #{why}" if why

          Zr.write_cache(obj, File.binread(fresh))
        end
        obj
      end

      # Functions and data to one object file. `export` makes every data
      # object visible to the link, for an object another refers to.
      def object(functions, data, obj, road:, raw: [], export: false)
        functions.each { |f| IR::Verify.check(f) }
        if road.is_a?(Ruby)
          unit = Obj::Unit.new
          defined = functions.map(&:name) + data.map(&:name) + raw.map(&:name)
          functions.each { |f| unit.functions << IR::Arm64.new(f, defined: defined).compile }
          raw.each { |r| unit.functions << r }
          data.each { |d| unit.data << (export ? exported(d) : d) }
          File.binwrite(obj, Obj::MachO.write(unit))
          nil
        else
          work = File.dirname(obj)
          clif = File.join(work, "unit.clif")
          sidecar = File.join(work, "unit.json")
          File.write(clif, functions.map { |f| IR::ClifText.render(f) }.join("\n"))
          rows = { "data" => data.map { |d| sidecar_row(d, export: export) },
                   "raw_functions" => raw.map { |r| { "name" => r.name, "bytes" => r.bytes.unpack1("H*"), "align" => r.align } } }
          File.write(sidecar, JSON.generate(rows))
          road.compile(clif, obj, data: sidecar)
        end
      end

      def exported(d)
        d.linkage == :export ? d : Obj::Data.new(d.name, d.section, d.bytes, relocs: d.relocs, align: d.align, linkage: :export)
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
        File.binwrite(out, IR::Wasm.new(functions, data).emit)
        nil
      rescue IR::Wasm::Refused => e
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
        File.binwrite(out, IR::Wasm.new(functions, data, prelude: pre).emit)
        nil
      rescue IR::Wasm::Refused => e
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
        pre = IR::Wasm.new(functions, data, pending: pending).prelude
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
      # callee that is not a shim and not in `known`.
      def stops(functions, raw, data, known)
        out = raw.map { |r| params, ret = Machine::Stub::ALL.fetch(r.name); stop(r.name, params.map { |t| Machine::TYPES.fetch(t.to_s) }, Machine::TYPES.fetch(ret.to_s), data) }
        defined = functions.map(&:name) + out.map(&:name) + IR::Wasm::SHIMS.keys + known
        functions.each do |f|
          f.callees.each do |c|
            next if defined.include?(c.symbol)

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

      def sidecar_row(d, export: false)
        row = { "name" => d.name, "section" => d.section.to_s, "align" => d.align, "export" => export || d.linkage == :export }
        if d.section == :bss
          row["size"] = d.size
        else
          row["bytes"] = d.bytes.unpack1("H*")
        end
        row["relocs"] = d.relocs.map { |r| { "offset" => r.offset, "kind" => r.kind.to_s, "symbol" => r.symbol, "addend" => r.addend } }
        row
      end
    end
  end
end
