# frozen_string_literal: true

require "json"
require_relative "../ir"
require_relative "../ir/arm64"
require_relative "../obj/macho"

module Ze0
  module Native
    # CLIF text and a data sidecar to a Mach-O object with nothing but
    # Ruby. `Build` goes straight from `IR::Function` to `IR::Arm64`; this
    # is the entry the hand-written `test/native/*.clif` fixtures take.
    module Ruby
      module_function

      # `clif` and `data` (a sidecar path, or nil) to the object `obj`.
      # Answers nil, or the refusal.
      def compile(clif, obj, data: nil)
        unit = unit_for(File.read(clif), data ? JSON.parse(File.read(data)) : {})
        File.binwrite(obj, Obj::MachO.write(unit))
        nil
      rescue IR::Arm64::Refused => e
        e.message
      end

      def unit_for(text, sidecar)
        functions = IR::ClifText.parse(text)
        unit = Obj::Unit.new
        defined = functions.map(&:name) + sidecar.fetch("data", []).map { |d| d["name"] }
        functions.each { |f| unit.functions << IR::Arm64.new(f, defined: defined).compile }
        sidecar.fetch("data", []).each do |d|
          section = d.fetch("section").to_sym
          bytes = section == :bss ? d.fetch("size") : [d.fetch("bytes")].pack("H*")
          relocs = d.fetch("relocs", []).map { |r| Obj::Reloc.new(r["offset"], r["kind"].to_sym, r["symbol"], r.fetch("addend", 0)) }
          unit.datum(d["name"], section, bytes, relocs: relocs, align: d.fetch("align", 1),
                                                linkage: d["export"] ? :export : :local)
        end
        unit
      end
    end
  end
end
