# frozen_string_literal: true

require "set"
require_relative "aarch64/codegen"
require_relative "aarch64/relocs"
require_relative "../obj/model"

module Ze0
  module Backend
    # The aarch64 backend: `Codegen` writes each function's machine code
    # over our own `Assembler`, `Relocs` patches what it records, and
    # `Stub` holds the functions no dialect can write.
    module Aarch64
      module_function

      # `functions` compiled, `raw` functions as they are, and `data`, as
      # one `Obj::Unit`. `export` makes every data object visible to the
      # link, for an object another refers to.
      def unit(functions, data, raw: [], export: false)
        out = Obj::Unit.new
        defined = (functions.map(&:name) + data.map(&:name) + raw.map(&:name)).to_set
        functions.each { |f| out.functions << assemble(f, defined) }
        raw.each { |r| out.functions << r }
        data.each { |d| out.data << (export ? exported(d) : d) }
        out
      end

      # One function's machine code. `defined` answers whether a symbol is
      # the unit's own.
      def assemble(function, defined)
        imported = function.callees.find(&:from)
        raise Refused, "#{imported.symbol} is a wasm import from #{imported.from}, which no native link has" if imported

        Codegen.new(function, defined: defined).compile
      end

      # The names a lowering gives what it makes: its entry, and every
      # name it spells from the entry. A unit assembled as it is lowered
      # knows its own symbols by these before it has made them all.
      Spelled = Data.define(:entry) do
        def include?(name) = name == entry || name.start_with?("#{entry}_")

        def to_set = self
      end

      def exported(d)
        d.linkage == :export ? d : Obj::Data.new(d.name, d.section, d.bytes, relocs: d.relocs, align: d.align, linkage: :export)
      end
    end
  end
end
