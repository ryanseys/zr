# frozen_string_literal: true

require_relative "../record"

module Zr
  # The backend-neutral object model. Every native backend produces it,
  # and every object writer and loader reads it. A function is machine
  # code plus the relocations that the code needs. A data object is bytes
  # in a section. A relocation gives a symbol and how to patch for it.
  module Obj
    # `kind`: :branch26, :page21, :pageoff12, :got_page21, :got_pageoff12,
    # :abs64. `offset` is from the start of the owning function or data.
    #
    # Four more kinds occur only in data, and only until the link numbers
    # the program's symbols (`Zr.number_symbols`):
    # - :symid writes the id that the program gives `symbol`.
    # - :symval writes that id as a tagged Symbol.
    # - :symbit writes the bit for the symbol in an ivar table's `names`.
    # - :site writes the slot of one literal site in the run-time table of
    #   literal objects.
    # A unit gives a name or requests a slot, and the link sets the number.
    # Thus a unit's code does not depend on what compiled before it. No
    # object writer sees these kinds.
    class Reloc < Record
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
    class Function < Record
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

    # `section`: :text_const (pure bytes), :data_const (contains pointers,
    # read-only after the link), :data (writable), :bss (zeros; `bytes` is
    # then the size).
    class Data < Record
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

    # One object: its functions and data, in definition order. A symbol
    # that a relocation refers to and that this unit does not define is
    # an import.
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
