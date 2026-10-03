# frozen_string_literal: true

require_relative "obj/model"

module Zr
  # The symbol numbers of a program. A unit gives a name, and the link
  # gives its number, in the order of the program's data, so a program
  # always gets the same numbers. The kernel reads the names back from
  # `zr_symbol_names`.
  module SymbolNumbering
    module_function

    # The relocation kinds that the link numbers.
    NUMBERED = %i[symid symval symbit site].freeze

    # The value that the link writes into one of those words. A site is a
    # location, not a name, so it gets the next free slot.
    #: (Obj::Reloc reloc, Machine::Symbols symbols, Integer tag) -> Integer?
    def numbered(reloc, symbols, tag)
      return symbols.site if reloc.kind == :site

      id = symbols.id(reloc.symbol)
      case reloc.kind
      when :symid then id
      when :symval then Lower.symbol_value(id, tag)
      when :symbit then Lower.ivar_name_bit(id)
      end
    end

    # Sets the numbers of `data` and writes them into their words. After
    # this, no relocation of these kinds is left. Every object writer and
    # the wasm module rely on this.
    #: (Array[Obj::Datum] data, Machine::Symbols symbols, Integer tag) -> Array[Obj::Datum]
    def number(data, symbols, tag)
      data.each do |d|
        waiting, keep = d.relocs.partition { |r| NUMBERED.include?(r.kind) }
        next if waiting.empty?

        bytes = d.bytes.dup
        waiting.each { |r| bytes[r.offset, 8] = [numbered(r, symbols, tag)].pack("q<") }
        d.bytes = bytes
        d.relocs = keep
      end
    end

    # `number` on copies: the data with each number written, where `data`
    # keeps its relocations. A cache keeps a piece's data unnumbered, so
    # that another table can number it again.
    #: (Array[Obj::Datum] data, Machine::Symbols symbols, Integer tag) -> Array[Obj::Datum]
    def numbered_copies(data, symbols, tag)
      data.map { |d| d.relocs.any? { |r| NUMBERED.include?(r.kind) } ? d.dup : d }.tap { |copies| number(copies, symbols, tag) }
    end

    # `zr_symbol_names`: one (bytes, length) record per symbol id. The
    # bytes of all names are one read-only object, and each record points
    # into it (an addend). An object for each name made a program that
    # evals carry 18,000 more data items and symbols, which each link
    # read, laid out and wrote again.
    #: (Machine::Symbols symbols) -> Array[Obj::Datum]
    def names_table(symbols)
      names = symbols.names
      all = +"".b
      table = +"".b
      relocs = [] #: Array[Obj::Reloc]
      names.each_with_index do |name, i|
        # A pad has no bytes, and the tag SYM_PAD (lib/zr/runtime/kernel/symbol.rb).
        if name.nil?
          table << [0, 255 << 56].pack("Q<Q<")
          next
        end
        relocs << Obj::Reloc.new(i * 16, :abs64, "zr_symname_bytes", all.bytesize)
        table << [0, name.bytesize].pack("Q<Q<")
        all << name.b
      end
      [Obj::Datum.new("zr_symname_bytes", :text_const, all.empty? ? "\0".b : all, align: 1),
       Obj::Datum.new("zr_symbol_names", :data_const, table, relocs: relocs, align: 8, linkage: :export),
       Obj::Datum.new("zr_symbol_count", :data_const, [names.size].pack("Q<"), align: 8, linkage: :export),
       Obj::Datum.new("zr_site_count", :data_const, [symbols.sites].pack("Q<"), align: 8, linkage: :export)]
    end
  end
end
