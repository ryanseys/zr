# frozen_string_literal: true

require "json"
require_relative "../ir"
require_relative "cranelift"
require_relative "ruby"

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
