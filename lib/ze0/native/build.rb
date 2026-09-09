# frozen_string_literal: true

require "json"
require_relative "../ir"
require_relative "../ir/verify"
require_relative "cranelift"
require_relative "ruby"
require_relative "../ir/wasm"
require_relative "../machine/lower"

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

      # Answers nil, or the message of the step that refused.
      def binary(functions, data, out, road:, work:, raw: [])
        functions.each { |f| IR::Verify.check(f) }
        obj = File.join(work, "unit.o")
        if road.is_a?(Ruby)
          unit = Obj::Unit.new
          defined = functions.map(&:name) + data.map(&:name) + raw.map(&:name)
          functions.each { |f| unit.functions << IR::Arm64.new(f, defined: defined).compile }
          raw.each { |r| unit.functions << r }
          data.each { |d| unit.data << d }
          File.binwrite(obj, Obj::MachO.write(unit))
        else
          clif = File.join(work, "unit.clif")
          sidecar = File.join(work, "unit.json")
          File.write(clif, functions.map { |f| IR::ClifText.render(f) }.join("\n"))
          rows = { "data" => data.map { |d| sidecar_row(d) },
                   "raw_functions" => raw.map { |r| { "name" => r.name, "bytes" => r.bytes.unpack1("H*"), "align" => r.align } } }
          File.write(sidecar, JSON.generate(rows))
          (why = road.compile(clif, obj, data: sidecar)) and return why
        end
        road.link([obj], out)
      end

      # The same functions and data as one WASI module. A raw function,
      # or a libSystem call the module has no shim for, has no wasm form:
      # its place is taken by a function that stops by name when called.
      def wasm(functions, data, out, raw: [])
        data = data.dup
        stops = raw.map { |r| params, ret = Machine::Stub::ALL.fetch(r.name); stop(r.name, params.map { |t| Machine::TYPES.fetch(t.to_s) }, Machine::TYPES.fetch(ret.to_s), data) }
        defined = functions.map(&:name) + stops.map(&:name) + IR::Wasm::SHIMS.keys
        functions.each do |f|
          f.callees.each do |c|
            next if defined.include?(c.symbol)

            sig = f.sigs.find { |x| x.sig == c.sig }
            stops << stop(c.symbol, sig.params, sig.ret, data)
            defined << c.symbol
          end
        end
        (functions + stops).each { |f| IR::Verify.check(f) }
        File.binwrite(out, IR::Wasm.new(functions + stops, data).emit)
        nil
      rescue IR::Wasm::Refused => e
        e.message
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

      def sidecar_row(d)
        row = { "name" => d.name, "section" => d.section.to_s, "align" => d.align, "export" => d.linkage == :export }
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
