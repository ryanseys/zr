# frozen_string_literal: true

require_relative "../model"
require_relative "../../record"

module Zr
  module Obj
    module Elf
      # A relocatable ELF64 for aarch64 (`ET_REL`), from an `Obj::Unit`: the
      # object `cc` links on an aarch64-linux host. Every function and data
      # object is a section of its own (`.text.<name>`, `.rodata.<name>`,
      # ...), so `--gc-sections` can leave out what nothing reaches.
      # Relocations are `SHT_RELA`, each with its addend in the row. Symbols
      # carry no prefix; locals come first, as the format requires. The
      # layout follows the System V gABI and the AArch64 ELF ABI.
      #
      # The runtime alone is tens of thousands of sections, so past
      # `SHN_LORESERVE` the file takes the gABI's extended numbering.
      module ObjectFile
        EM_AARCH64 = 183
        ET_REL = 1
        SHT_PROGBITS = 1
        SHT_SYMTAB = 2
        SHT_STRTAB = 3
        SHT_RELA = 4
        SHT_NOBITS = 8
        SHT_SYMTAB_SHNDX = 18
        SHF_WRITE = 0x1
        SHF_ALLOC = 0x2
        SHF_EXECINSTR = 0x4
        SHF_INFO_LINK = 0x40
        STB_LOCAL = 0
        STB_GLOBAL = 1
        STT_NOTYPE = 0
        STT_OBJECT = 1
        STT_FUNC = 2
        SHN_UNDEF = 0
        # From here up a section index does not fit its 16-bit field: the
        # header, section 0 and `.symtab_shndx` carry the real one.
        SHN_LORESERVE = 0xFF00
        SHN_XINDEX = 0xFFFF

        # The AArch64 relocation types for the kinds `Backend::Aarch64`
        # records.
        RELOC = {
          abs64: 257,          # R_AARCH64_ABS64
          branch26: 283,       # R_AARCH64_CALL26
          page21: 275,         # R_AARCH64_ADR_PREL_PG_HI21
          pageoff12: 277,      # R_AARCH64_ADD_ABS_LO12_NC
          got_page21: 311,     # R_AARCH64_ADR_GOT_PAGE
          got_pageoff12: 312   # R_AARCH64_LD64_GOT_LO12_NC
        }.freeze

        # Each `Obj` section's ELF name prefix, type and flags.
        SECTIONS = {
          function: [".text", SHT_PROGBITS, SHF_ALLOC | SHF_EXECINSTR],
          text_const: [".rodata", SHT_PROGBITS, SHF_ALLOC],
          data_const: [".data.rel.ro", SHT_PROGBITS, SHF_ALLOC | SHF_WRITE],
          data: [".data", SHT_PROGBITS, SHF_ALLOC | SHF_WRITE],
          bss: [".bss", SHT_NOBITS, SHF_ALLOC | SHF_WRITE]
        }.freeze

        class Section < ::Zr::Record
          FIELDS = %i[name type flags bytes size align link info entsize offset item].freeze
          attr_accessor :name, :type, :flags, :bytes, :size, :align, :link, :info, :entsize, :offset, :item

          def initialize(name: nil, type: nil, flags: nil, bytes: nil, size: nil, align: nil, link: nil, info: nil, entsize: nil,
                         offset: nil, item: nil)
            @name = name
            @type = type
            @flags = flags
            @bytes = bytes
            @size = size
            @align = align
            @link = link
            @info = info
            @entsize = entsize
            @offset = offset
            @item = item
          end

          def to_a = [@name, @type, @flags, @bytes, @size, @align, @link, @info, @entsize, @offset, @item]
        end

        module_function

        # The file's bytes.
        def write(unit)
          items = unit.functions.map { |f| [:function, f] } + unit.data.map { |d| [d.section, d] }
          sections = [Section.new(name: "", type: 0, flags: 0, bytes: "".b, size: 0, align: 0, link: 0, info: 0, entsize: 0)]
          items.each do |kind, item|
            prefix, type, flags = SECTIONS.fetch(kind) { raise ArgumentError, "no ELF section for #{kind}" }
            bytes = type == SHT_NOBITS ? "".b : item.bytes
            sections << Section.new(name: "#{prefix}.#{item.name}", type: type, flags: flags, bytes: bytes, size: item.size,
                                    align: item.align, link: 0, info: 0, entsize: 0, item: item)
          end
          item_sections = sections.drop(1)

          symbols = symbol_table(unit, item_sections)
          index = symbols.each_with_index.to_h { |sym, i| [sym[:name], i] }
          symtab_index = sections.size + item_sections.count { |s| !s.item.relocs.empty? } + 1
          extended = symbols.any? { |sym| sym[:shndx] >= SHN_LORESERVE }
          item_sections.each_with_index do |s, i|
            next if s.item.relocs.empty?

            rows = s.item.relocs.sort_by(&:offset).map do |r|
              type = RELOC.fetch(r.kind) { raise ArgumentError, "no AArch64 relocation for #{r.kind}" }
              [r.offset, (index.fetch(r.symbol) << 32) | type, r.addend.to_i].pack("Q<Q<q<")
            end.join
            sections << Section.new(name: ".rela#{s.name}", type: SHT_RELA, flags: SHF_INFO_LINK, bytes: rows, size: rows.bytesize,
                                    align: 8, link: symtab_index, info: i + 1, entsize: 24)
          end
          sections << Section.new(name: ".note.GNU-stack", type: SHT_PROGBITS, flags: 0, bytes: "".b, size: 0, align: 1, link: 0, info: 0, entsize: 0)

          strtab = +"\0".b
          symbols.each do |sym|
            sym[:strx] = sym[:name].empty? ? 0 : strtab.bytesize
            strtab << sym[:name].b << "\0".b unless sym[:name].empty?
          end
          locals = symbols.count { |sym| sym[:bind] == STB_LOCAL }
          symtab = symbols.map do |sym|
            shndx = sym[:shndx] >= SHN_LORESERVE ? SHN_XINDEX : sym[:shndx]
            [sym[:strx], (sym[:bind] << 4) | sym[:type], 0, shndx, sym[:value], sym[:size]].pack("L<CCS<Q<Q<")
          end.join
          strtab_index = sections.size + (extended ? 2 : 1)
          sections << Section.new(name: ".symtab", type: SHT_SYMTAB, flags: 0, bytes: symtab, size: symtab.bytesize,
                                  align: 8, link: strtab_index, info: locals, entsize: 24)
          raise ArgumentError, "the symbol table is not where the relocations say" unless sections.size - 1 == symtab_index

          if extended
            shndx = symbols.map { |sym| sym[:shndx] >= SHN_LORESERVE ? sym[:shndx] : 0 }.pack("L<*")
            sections << Section.new(name: ".symtab_shndx", type: SHT_SYMTAB_SHNDX, flags: 0, bytes: shndx, size: shndx.bytesize,
                                    align: 4, link: symtab_index, info: 0, entsize: 4)
          end

          sections << Section.new(name: ".strtab", type: SHT_STRTAB, flags: 0, bytes: strtab, size: strtab.bytesize, align: 1, link: 0, info: 0, entsize: 0)
          shstrtab = +"\0".b
          sections << Section.new(name: ".shstrtab", type: SHT_STRTAB, flags: 0, bytes: "".b, size: 0, align: 1, link: 0, info: 0, entsize: 0)
          names = sections.map do |s|
            next 0 if s.name.empty?

            at = shstrtab.bytesize
            shstrtab << s.name.b << "\0".b
            at
          end
          sections.last.bytes = shstrtab
          sections.last.size = shstrtab.bytesize

          out = +"".b
          out << ("\0" * 64).b
          sections.drop(1).each do |s|
            next if s.type == SHT_NOBITS

            out << ("\0" * (align_up(out.bytesize, [s.align, 1].max) - out.bytesize)).b
            s.offset = out.bytesize
            out << s.bytes
          end
          sections.select { |s| s.type == SHT_NOBITS }.each { |s| s.offset = out.bytesize }
          out << ("\0" * (align_up(out.bytesize, 8) - out.bytesize)).b
          shoff = out.bytesize
          shnum = sections.size
          shstrndx = shnum - 1
          # Section 0 holds the count and the names' index when the header
          # fields cannot.
          sections[0].size = shnum >= SHN_LORESERVE ? shnum : 0
          sections[0].link = shstrndx >= SHN_LORESERVE ? shstrndx : 0
          sections.each_with_index do |s, i|
            out << [names[i], s.type, s.flags, 0, s.offset.to_i, s.size, s.link, s.info, s.align, s.entsize].pack("L<L<Q<Q<Q<Q<L<L<Q<Q<")
          end
          out[0, 64] = header(shoff, shnum >= SHN_LORESERVE ? 0 : shnum, shstrndx >= SHN_LORESERVE ? SHN_XINDEX : shstrndx)
          out
        end

        # The null symbol, then locals, then globals and imports, each group
        # by name.
        def symbol_table(unit, item_sections)
          defined = item_sections.each_with_index.map do |s, i|
            item = s.item
            { name: item.name, bind: item.linkage == :export ? STB_GLOBAL : STB_LOCAL,
              type: item.is_a?(Obj::Function) ? STT_FUNC : STT_OBJECT,
              shndx: i + 1, value: 0, size: item.size }
          end
          imports = unit.imports.map { |name| { name: name, bind: STB_GLOBAL, type: STT_NOTYPE, shndx: SHN_UNDEF, value: 0, size: 0 } }
          null = { name: "", bind: STB_LOCAL, type: STT_NOTYPE, shndx: SHN_UNDEF, value: 0, size: 0 }
          locals = defined.select { |sym| sym[:bind] == STB_LOCAL }.sort_by { |sym| sym[:name] }
          globals = (defined.select { |sym| sym[:bind] == STB_GLOBAL } + imports).sort_by { |sym| sym[:name] }
          [null] + locals + globals
        end

        def header(shoff, shnum, shstrndx)
          ident = "\x7FELF".b + [2, 1, 1, 0].pack("C4") + ("\0" * 8).b
          ident + [ET_REL, EM_AARCH64, 1, 0, 0, shoff, 0, 64, 0, 0, 64, shnum, shstrndx].pack("S<S<L<Q<Q<Q<L<S<S<S<S<S<S<")
        end

        def align_up(n, a)
          (n + a - 1) & ~(a - 1)
        end
      end
    end
  end
end
