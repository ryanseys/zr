# frozen_string_literal: true

module Ze0
  # The backend-neutral object model: what every native road produces and
  # every object writer or loader consumes. A function is its machine code
  # with the relocations the code needs; a data object is bytes in a
  # section; a relocation names a symbol and how to patch for it.
  module Obj
    # `kind`: :branch26, :page21, :pageoff12, :got_page21, :got_pageoff12,
    # :abs64. `offset` is from the start of the owning function or data.
    Reloc = Struct.new(:offset, :kind, :symbol, :addend) do
      def initialize(offset, kind, symbol, addend = 0)
        super
      end
    end

    # `linkage`: :export (visible to the link), :local (this object only).
    Function = Struct.new(:name, :bytes, :relocs, :align, :linkage) do
      def initialize(name, bytes, relocs: [], align: 4, linkage: :export)
        super(name, bytes.b, relocs, align, linkage)
      end

      def size
        bytes.bytesize
      end
    end

    # `section`: :text_const (pure bytes), :data_const (holds pointers,
    # read-only after the link), :data (writable), :bss (zeros; `bytes` is
    # then the size).
    Data = Struct.new(:name, :section, :bytes, :relocs, :align, :linkage) do
      def initialize(name, section, bytes, relocs: [], align: 8, linkage: :local)
        super(name, section, section == :bss ? bytes : bytes.b, relocs, align, linkage)
      end

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
