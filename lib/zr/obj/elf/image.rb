# frozen_string_literal: true

module Zr
  module Obj
    module Elf
      # A reader of 64-bit little-endian aarch64 ELF files: an object that
      # `cc -c` writes, or one that `cc -r` joins. It gives what the build
      # asks of a C extension's objects, as Obj::MachO::Image gives it of a
      # bundle: the names that it defines and imports, and its C strings.
      # Obj::Elf::Localize rewrites the symbols that it reads.
      class Image
        EM_AARCH64 = 183
        SHT_SYMTAB = 2
        SHT_STRTAB = 3
        SHT_SYMTAB_SHNDX = 18
        SHF_ALLOC = 0x2
        SHF_MERGE = 0x10
        SHF_STRINGS = 0x20
        STB_LOCAL = 0
        STB_GLOBAL = 1
        STB_WEAK = 2
        SHN_UNDEF = 0
        SHN_XINDEX = 0xFFFF
        SECTION_HEADER = "L<L<Q<Q<Q<Q<L<L<Q<Q<"
        SECTION_BYTES = 64
        SYMBOL = "L<CCS<Q<Q<"
        SYMBOL_BYTES = 24

        # A section header, with its name read; `name_at` is where the name
        # starts in the section names.
        # @rbs skip
        Section = Data.define(:name, :type, :flags, :addr, :offset, :size, :link, :info, :align, :entsize, :name_at)

        # A symbol of .symtab: `bind` and `type` split from st_info, and
        # `shndx` the section index, read through SHT_SYMTAB_SHNDX when the
        # object has more sections than a 16-bit index holds.
        # @rbs skip
        Symbol = Data.define(:name, :value, :size, :bind, :type, :other, :shndx, :name_at)

        class Symbol
          #: () -> bool
          def global? = bind == STB_GLOBAL || bind == STB_WEAK

          #: () -> bool
          def undefined? = shndx == SHN_UNDEF
        end

        attr_reader :bytes #: String
        attr_reader :sections #: Array[Section]
        attr_reader :symbols #: Array[Symbol]
        # The index of the section that holds the sections' names.
        attr_reader :names_index #: Integer

        #: (String bytes) -> Image
        def self.read(bytes) = new(bytes.b)

        # Whether `bytes` start as an ELF file.
        #: (String bytes) -> bool
        def self.elf?(bytes) = bytes.byteslice(0, 4) == "\x7FELF".b

        #: (String bytes) -> void
        def initialize(bytes)
          @bytes = bytes
          unless Image.elf?(bytes) && bytes.getbyte(4) == 2 && bytes.getbyte(5) == 1 && bytes.unpack1("S<", offset: 18) == EM_AARCH64
            raise ArgumentError, "not a 64-bit little-endian aarch64 ELF file"
          end

          @sections = read_sections
          @symbols = read_symbols
        end

        # The names, as C writes them, that the file uses and does not
        # define, sorted.
        #: () -> Array[String]
        def undefined = symbols.filter_map { |s| s.name if s.global? && s.undefined? && !s.name.empty? }.uniq.sort

        # The names that the file defines for others to use, sorted.
        #: () -> Array[String]
        def defined = symbols.filter_map { |s| s.name if s.global? && !s.undefined? }.uniq.sort

        # The C strings of the file: those of each section of merged
        # strings that the program loads (`.rodata.str1.1`), as Mach-O
        # keeps them in `__cstring`.
        #: () -> Array[String]
        def c_strings
          sections.select { |s| s.flags.allbits?(SHF_ALLOC | SHF_MERGE | SHF_STRINGS) && s.entsize <= 1 }
                  .flat_map { |s| contents(s).split("\0") }
        end

        # `name` as C writes it: ELF adds no prefix.
        #: (String name) -> String
        def c_name(name) = name

        # The bytes of section `section`.
        #: (Section section) -> String
        def contents(section) = bytes.byteslice(section.offset, section.size) #: String

        # The index of the section header table entry of .symtab, or nil.
        #: () -> Integer?
        def symtab_index = sections.index { |s| s.type == SHT_SYMTAB }

        private

        #: () -> Array[Section]
        def read_sections
          shoff = bytes.unpack1("Q<", offset: 40) #: Integer
          count, names_at = bytes.unpack("S<S<", offset: 60) #: [Integer, Integer]
          @names_index = 0
          return [] if shoff.zero?

          first = header(shoff, 0)
          # Extended numbering: the first header holds what does not fit.
          count = first[5] if count.zero?
          names_at = first[6] if names_at == SHN_XINDEX
          raw = (0...count).map { |i| header(shoff, i) }
          @names_index = names_at
          names = raw[names_at]
          raw.map { |r| Section.new(string(names[4], r[0]), *r.drop(1), r[0]) }
        end

        #: (Integer shoff, Integer index) -> Array[Integer]
        def header(shoff, index) = bytes.unpack(SECTION_HEADER, offset: shoff + (index * SECTION_BYTES)) #: Array[Integer]

        #: () -> Array[Symbol]
        def read_symbols
          table = sections.find { |s| s.type == SHT_SYMTAB } or return []
          names = sections.fetch(table.link)
          wide = sections.find { |s| s.type == SHT_SYMTAB_SHNDX && s.link == symtab_index }
          (0...(table.size / SYMBOL_BYTES)).map do |i|
            row = bytes.unpack(SYMBOL, offset: table.offset + (i * SYMBOL_BYTES)) #: [Integer, Integer, Integer, Integer, Integer, Integer]
            name, info, other, shndx, value, size = row
            if shndx == SHN_XINDEX && wide
              shndx = bytes.unpack1("L<", offset: wide.offset + (i * 4)) #: Integer
            end
            Symbol.new(string(names.offset, name), value, size, info >> 4, info & 0xF, other, shndx, name)
          end
        end

        #: (Integer table, Integer at) -> String
        def string(table, at) = bytes.unpack1("Z*", offset: table + at) #: String
      end
    end
  end
end
