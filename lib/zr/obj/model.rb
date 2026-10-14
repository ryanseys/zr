# frozen_string_literal: true

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
    # the program's symbols (`Zr::SymbolNumbering.number`):
    # - :symid writes the id that the program gives `symbol`.
    # - :symval writes that id as a tagged Symbol.
    # - :symbit writes the bit for the symbol in an ivar table's `names`.
    # - :site writes the slot of one literal site in the run-time table of
    #   literal objects.
    # A unit gives a name or requests a slot, and the link sets the number.
    # Thus a unit's code does not depend on what compiled before it. No
    # object writer sees these kinds.
    # @rbs skip -- typed in sig/zr/obj/model.rbs
    Reloc = Struct.new(:offset, :kind, :symbol, :addend)

    # The fields of a record are typed in sig/zr/obj/model.rbs, its
    # methods here, in a reopened class.
    class Reloc
      #: (Integer offset, reloc_kind kind, String symbol, ?Integer addend) -> void
      def initialize(offset, kind, symbol, addend = 0) = super
    end

    # The machine code of one function, as a backend assembled it.
    # `linkage`: :export (visible to the link), :local (this object only).
    # @rbs skip
    Code = Struct.new(:name, :bytes, :relocs, :align, :linkage)

    class Code
      #: (String name, String bytes, ?relocs: Array[Reloc], ?align: Integer, ?linkage: linkage) -> void
      def initialize(name, bytes, relocs: [], align: 4, linkage: :export) = super(name, bytes.b, relocs, align, linkage)

      #: () -> Integer
      def size
        bytes.bytesize
      end
    end

    # One item of data: a string, a table, or a static slot.
    # `section`: :text_const (pure bytes), :data_const (contains pointers,
    # read-only after the link), :data (writable), :bss (zeros; `bytes` is
    # then the size).
    # @rbs skip
    Datum = Struct.new(:name, :section, :bytes, :relocs, :align, :linkage)

    class Datum
      #: (String name, section section, untyped bytes, ?relocs: Array[Reloc], ?align: Integer, ?linkage: linkage) -> void
      def initialize(name, section, bytes, relocs: [], align: 8, linkage: :local)
        super(name, section, section == :bss ? bytes : bytes.b, relocs, align, linkage)
      end

      #: () -> Integer
      def size
        section == :bss ? bytes : bytes.bytesize
      end
    end

    # One object: its functions and data, in definition order. A symbol
    # that a relocation refers to and that this unit does not define is
    # an import.
    class Unit
      attr_reader :functions #: Array[Code]
      attr_reader :data #: Array[Datum]

      #: () -> void
      def initialize
        @functions = []
        @data = []
      end

      # `function` and `datum` add one item and return the unit, so a test
      # builds a unit in one expression (test/support/obj_unit.rb).
      #: (String name, String bytes, ?relocs: Array[Reloc], ?align: Integer, ?linkage: linkage) -> self
      def function(name, bytes, **options)
        @functions << Code.new(name, bytes, **options)
        self
      end

      #: (String name, section section, untyped bytes, ?relocs: Array[Reloc], ?align: Integer, ?linkage: linkage) -> self
      def datum(name, section, bytes, **options)
        @data << Datum.new(name, section, bytes, **options)
        self
      end

      # Each item with its kind, `:function` or the datum's section, the
      # functions first: what an object writer lays out.
      #: () -> Array[[Symbol, Code | Datum]]
      def items
        items = @functions.map { |f| [:function, f] } #$ [Symbol, Code | Datum]
        @data.each { |d| items << [d.section, d] }
        items
      end

      # A program has more than a million relocations, so this sees each
      # name once, in a Hash, and makes no array of all of them.
      #: () -> Array[String]
      def imports
        named = (@functions + @data).to_h { |d| [d.name, true] }
        found = {} #: Hash[String, bool]
        [@functions, @data].each do |items|
          items.each { |d| d.relocs.each { |r| found[r.symbol] = true unless named.key?(r.symbol) } }
        end
        found.keys
      end
    end
  end
end
