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
        functions.each { |f| out.functions << Codegen.new(f, defined: defined).compile }
        raw.each { |r| out.functions << r }
        data.each { |d| out.data << (export ? exported(d) : d) }
        out
      end

      def exported(d)
        d.linkage == :export ? d : Obj::Data.new(d.name, d.section, d.bytes, relocs: d.relocs, align: d.align, linkage: :export)
      end
    end
  end
end
