# frozen_string_literal: true

require_relative "image"
require_relative "../../refused"

module Zr
  module Obj
    module Elf
      # Gives a static C extension a namespace of its own in an ELF binary,
      # as a bundle has on darwin. Its objects, joined into one by `cc -r`,
      # come in; the same object goes out with each name that it defines
      # made local, except its Init function, so two extensions (and the
      # program) can each have a `buffer_new`. Its imports stay global, and
      # the link binds them to zr's C API and to libc. Its weak definitions
      # stay global too: they are C++'s inline and template functions, in
      # COMDAT groups, which the linker keeps once for the whole binary. A
      # local copy would still take the group, and libstdc++.a's own calls
      # to that function would then find no definition.
      #
      # The object also gets the names that the program's require of the
      # extension reads (`zr_ext_embedded`, as Obj::MachO::Relink gives
      # them): `zr_ext_<Init>`, its Init function; `zr_ext_inits_<Init>`
      # and `zr_ext_inits_end_<Init>`, the bounds of its initializers,
      # which were its .init_array, renamed so that the binary's start
      # does not run them before zr is ready; and the bounds of the
      # offsets and the base, which ELF does not use (0, an empty range).
      #
      # The rewrite keeps every section and its index. It changes the
      # symbol table (the locals first, as ELF requires, then the
      # globals), the string tables that it adds names to, the symbol
      # numbers of the relocations and of the groups, and lays the
      # sections out again.
      module Localize
        SHT_PROGBITS = 1
        SHT_NOBITS = 8
        SHT_RELA = 4
        SHT_REL = 9
        SHT_INIT_ARRAY = 14
        SHT_GROUP = 17
        STT_NOTYPE = 0
        SHN_LORESERVE = 0xFF00
        SHN_ABS = 0xFFF1
        SHN_COMMON = 0xFFF2
        # The section that an extension's initializers move to.
        INITS = ".zr_ext_inits"

        module_function

        # The bytes of the object `bytes`, with only `init` (`Init_msgpack`)
        # left global of what it defines.
        #: (String bytes, String init) -> String
        def call(bytes, init)
          image = Image.read(bytes)
          table = image.symtab_index or raise Refused, "#{init}: the extension's object has no symbol table"
          entry = image.symbols.find { |symbol| symbol.name == init && symbol.global? && !symbol.undefined? }
          raise Refused, "the extension's objects define no #{init}" unless entry

          Rewrite.new(image, table, init, entry).bytes
        end

        # One rewrite of one object.
        class Rewrite
          # @rbs @image: Image
          # @rbs @table: Integer
          # @rbs @init: String
          # @rbs @entry: Image::Symbol
          # @rbs @sections: Array[Image::Section]
          # @rbs @contents: Hash[Integer, String]
          # @rbs @renamed: Hash[Integer, Integer]
          # @rbs @order: Array[Integer]

          #: (Image image, Integer table, String init, Image::Symbol entry) -> void
          def initialize(image, table, init, entry)
            @image = image
            @table = table
            @init = init
            @entry = entry
            @sections = image.sections
            @contents = {}
            @renamed = {}
            @order = []
          end

          #: () -> String
          def bytes
            if @sections.any? { |section| section.type == Image::SHT_SYMTAB_SHNDX }
              raise Refused, "#{@init}: the extension's object has more sections than zr rewrites"
            end

            inits = init_section
            symbols, @order = ordered_symbols
            symbols += added_symbols(inits)
            strings = @image.contents(@sections.fetch(@sections.fetch(@table).link)).dup
            @contents[@sections.fetch(@table).link] = strings
            @contents[@table] = symbols.map { |symbol| pack(symbol, strings) }.join
            remap_relocations(@order)
            layout(locals: symbols.count { |symbol| symbol.bind == Image::STB_LOCAL })
          end

          private

          # The index of the extension's .init_array, which moves to INITS
          # as plain data, or nil when it has no initializers. Initializers
          # with priorities (`.init_array.00100`) would need an order: zr
          # refuses them.
          #: () -> Integer?
          def init_section
            found = @sections.each_index.select { |i| @sections[i].type == SHT_INIT_ARRAY || @sections[i].name.start_with?(".init_array") }
            return nil if found.empty?
            raise Refused, "#{@init}: the extension has initializers with priorities, which zr cannot order" if found.size > 1

            names = @image.contents(@sections.fetch(@image.names_index)).dup
            @renamed[found.first] = names.bytesize
            names << INITS << "\0"
            @contents[@image.names_index] = names
            found.first
          end

          # The symbols, the locals first: the object's own locals, then
          # each name that it defined, now local, then its imports, Init,
          # its weak definitions and its common symbols (which cannot be
          # local). And `order`,
          # the new index of each old one.
          #: () -> [Array[Image::Symbol], Array[Integer]]
          def ordered_symbols
            symbols = @image.symbols
            localized = ->(s) { s.bind == Image::STB_GLOBAL && !s.undefined? && s.name != @init && s.shndx != SHN_COMMON }
            groups = [symbols.each_index.select { |i| symbols[i].bind == Image::STB_LOCAL },
                      symbols.each_index.select { |i| localized.call(symbols[i]) },
                      symbols.each_index.select { |i| symbols[i].global? && !localized.call(symbols[i]) }]
            sequence = groups.flatten
            order = Array.new(symbols.size) #: Array[Integer]
            sequence.each_with_index { |old, new| order[old] = new }
            out = sequence.map { |i| localized.call(symbols[i]) ? symbols[i].with(bind: Image::STB_LOCAL) : symbols[i] }
            [out, order]
          end

          # The names that zr_ext_embedded reads, all global.
          #: (Integer? inits) -> Array[Image::Symbol]
          def added_symbols(inits)
            shndx, start, finish = inits ? [inits, 0, @sections.fetch(inits).size] : [SHN_ABS, 0, 0]
            [global("zr_ext_#{@init}", @entry.shndx, @entry.value, type: @entry.type, size: @entry.size),
             global("zr_ext_inits_#{@init}", shndx, start),
             global("zr_ext_inits_end_#{@init}", shndx, finish),
             global("zr_ext_offsets_#{@init}", SHN_ABS, 0),
             global("zr_ext_offsets_end_#{@init}", SHN_ABS, 0),
             global("zr_ext_base_#{@init}", SHN_ABS, 0)]
          end

          # A global symbol that the rewrite adds, its name not yet in the
          # string table.
          #: (String name, Integer shndx, Integer value, ?type: Integer, ?size: Integer) -> Image::Symbol
          def global(name, shndx, value, type: STT_NOTYPE, size: 0)
            Image::Symbol.new(name, value, size, Image::STB_GLOBAL, type, 0, shndx, nil)
          end

          # A symbol's 24 bytes, its name added to `strings` when it is new.
          # An index past the 16-bit ones would need SHT_SYMTAB_SHNDX, which
          # an extension's object does not have.
          #: (Image::Symbol symbol, String strings) -> String
          def pack(symbol, strings)
            at = symbol.name_at || strings.bytesize.tap { strings << symbol.name << "\0" }
            if symbol.shndx >= SHN_LORESERVE && ![SHN_ABS, SHN_COMMON].include?(symbol.shndx)
              raise Refused, "#{@init}: the extension's object has more sections than zr rewrites"
            end

            [at, (symbol.bind << 4) | symbol.type, symbol.other, symbol.shndx, symbol.value, symbol.size].pack(Image::SYMBOL)
          end

          # Each relocation and group names its symbol by its index, which
          # `order` gives anew.
          #: (Array[Integer] order) -> void
          def remap_relocations(order)
            @sections.each_with_index do |section, i|
              next unless section.link == @table

              case section.type
              when SHT_RELA, SHT_REL
                width = section.type == SHT_RELA ? 24 : 16
                data = @image.contents(section).dup
                (0...(data.bytesize / width)).each do |n|
                  info = data.unpack1("Q<", offset: (n * width) + 8) #: Integer
                  data[(n * width) + 8, 8] = [(order.fetch(info >> 32) << 32) | (info & 0xFFFFFFFF)].pack("Q<")
                end
                @contents[i] = data
              end
            end
          end

          # The object laid out again: its header, each section's bytes at
          # its alignment, then the section headers, each with its new
          # offset and size; .symtab's info is the index of its first global,
          # and a group's info is its signature's new index.
          #: (locals: Integer) -> String
          def layout(locals:)
            out = @image.bytes.byteslice(0, 64).to_s.dup
            offsets = @sections.each_with_index.map do |section, i|
              if i.zero?
                0
              else
                data = @contents.fetch(i) { section.type == SHT_NOBITS ? "" : @image.contents(section) }
                out << ("\0" * ((-out.bytesize) % [section.align, 1].max))
                at = out.bytesize
                out << data
                at
              end
            end
            out << ("\0" * ((-out.bytesize) % 8))
            out[40, 8] = [out.bytesize].pack("Q<")
            @sections.each_with_index do |section, i|
              out << header(section, i, offsets.fetch(i), locals)
            end
            out
          end

          #: (Image::Section section, Integer i, Integer offset, Integer locals) -> String
          def header(section, i, offset, locals)
            return @image.bytes.byteslice(sections_at, Image::SECTION_BYTES).to_s if i.zero?

            size = @contents.key?(i) ? @contents.fetch(i).bytesize : section.size
            info = section.info
            info = locals if i == @table
            info = @order.fetch(section.info) if section.type == SHT_GROUP
            type = @renamed.key?(i) ? SHT_PROGBITS : section.type
            name = @renamed.fetch(i, section.name_at)
            [name, type, section.flags, section.addr, offset, size, section.link, info, section.align, section.entsize].pack(Image::SECTION_HEADER)
          end

          #: () -> Integer
          def sections_at = @image.bytes.unpack1("Q<", offset: 40) #: Integer
        end
      end
    end
  end
end
