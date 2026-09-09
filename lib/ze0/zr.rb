# frozen_string_literal: true

require_relative "machine/lower"
require_relative "obj/model"
require_relative "hir"
require_relative "zr/lower"

module Ze0
  # The `zr` runtime: the kernel files, and the data the compiler lays
  # out beside them.
  module Zr
    KERNEL = Dir[File.join(__dir__, "../../rt/kernel/*.rb")].sort.freeze

    module_function

    # A Ruby program with the kernel as one unit: `[functions, data, raw]`
    # ready for `Native::Build`.
    def program(source, file)
      symbols = Machine::Symbols.new
      unit = Machine.unit(KERNEL, symbols: symbols)
      functions, data = Lower.new(Hir.build(source, file), unit, symbols).run
      [unit.functions + functions, unit.data + data + symbol_names(symbols), unit.raw]
    end

    # `zr_symbol_names`: a row of (bytes, length) per symbol id, the bytes
    # in their own read-only objects.
    def symbol_names(symbols)
      names = symbols.ids.keys
      bytes = names.each_with_index.map { |name, i| Obj::Data.new("zr_symname_#{i}", :text_const, name.b, align: 1) }
      table = +"".b
      relocs = []
      names.each_with_index do |name, i|
        relocs << Obj::Reloc.new(i * 16, :abs64, "zr_symname_#{i}")
        table << [0, name.bytesize].pack("Q<Q<")
      end
      bytes + [Obj::Data.new("zr_symbol_names", :data_const, table, relocs: relocs, align: 8, linkage: :export),
               Obj::Data.new("zr_symbol_count", :data_const, [names.size].pack("Q<"), align: 8, linkage: :export)]
    end
  end
end
