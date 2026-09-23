# frozen_string_literal: true

require_relative "../record"

module Ze0
  # The backend-neutral object model: what every native road produces and
  # every object writer or loader consumes. A function is its machine code
  # with the relocations the code needs; a data object is bytes in a
  # section; a relocation names a symbol and how to patch for it.
  module Obj
    # `kind`: :branch26, :page21, :pageoff12, :got_page21, :got_pageoff12,
    # :abs64. `offset` is from the start of the owning function or data.
    #
    # Three more kinds stand only in data, and only until the link
    # numbers the program's symbols: :symid writes the id the program
    # gives `symbol`, :symval writes that id as a tagged Symbol, and
    # :symbit the bit an ivar table's `names` keeps for it, and :site
    # the slot the program gives one literal site in the run-time table
    # of literal objects. A unit spells a name, or asks for a slot, and
    # leaves the number to the link, so that its code does not depend
    # on what was compiled before it; no object writer ever sees one of
    # these (`Zr.number_symbols`).
    class Reloc < Ze0::Record
      FIELDS = %i[offset kind symbol addend].freeze
      attr_accessor :offset, :kind, :symbol, :addend

      def initialize(offset, kind, symbol, addend = 0)
        @offset = offset
        @kind = kind
        @symbol = symbol
        @addend = addend
      end

      def to_a = [@offset, @kind, @symbol, @addend]
    end

    # `linkage`: :export (visible to the link), :local (this object only).
    class Function < Ze0::Record
      FIELDS = %i[name bytes relocs align linkage].freeze
      attr_accessor :name, :bytes, :relocs, :align, :linkage

      def initialize(name, bytes, relocs: [], align: 4, linkage: :export)
        @name = name
        @bytes = bytes.b
        @relocs = relocs
        @align = align
        @linkage = linkage
      end

      def to_a = [@name, @bytes, @relocs, @align, @linkage]

      def size
        bytes.bytesize
      end
    end

    # `section`: :text_const (pure bytes), :data_const (holds pointers,
    # read-only after the link), :data (writable), :bss (zeros; `bytes` is
    # then the size).
    class Data < Ze0::Record
      FIELDS = %i[name section bytes relocs align linkage].freeze
      attr_accessor :name, :section, :bytes, :relocs, :align, :linkage

      def initialize(name, section, bytes, relocs: [], align: 8, linkage: :local)
        @name = name
        @section = section
        @bytes = section == :bss ? bytes : bytes.b
        @relocs = relocs
        @align = align
        @linkage = linkage
      end

      def to_a = [@name, @section, @bytes, @relocs, @align, @linkage]

      def size
        section == :bss ? bytes : bytes.bytesize
      end
    end

    # One object: its functions and data, in definition order. Every
    # symbol a relocation names and nothing here defines is an import.
    class Unit
      attr_reader :functions, :data

      def initialize
        @functions = []
        @data = []
      end

      def function(name, bytes, **opts)
        @functions << Function.new(name, bytes, **opts)
        self
      end

      def datum(name, section, bytes, **opts)
        @data << Data.new(name, section, bytes, **opts)
        self
      end

      def defined_names
        (@functions + @data).map(&:name)
      end

      def imports
        named = defined_names
        (@functions + @data).flat_map { |d| d.relocs.map(&:symbol) }.uniq - named
      end
    end
  end
end
