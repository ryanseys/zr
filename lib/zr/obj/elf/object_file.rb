# frozen_string_literal: true

require_relative "../model"
require_relative "../../bytes"
require_relative "../string_table"

module Zr
  module Obj
    module Elf
      # Writes a relocatable ELF64 object for aarch64 (`ET_REL`) from an
      # `Obj::Unit`, for `cc` to link on an aarch64-linux host. Each function
      # and data object has its own section (`.text.<name>`,
      # `.rodata.<name>`, ...), so `--gc-sections` can remove what nothing
      # refers to. Relocations are `SHT_RELA`, each with its addend in the
      # entry. Symbols have no prefix; locals come first, as the format
      # requires. The layout follows the System V gABI and the AArch64 ELF ABI.
      #
      # The runtime alone has tens of thousands of sections, so at
      # `SHN_LORESERVE` and above the file uses the gABI's extended numbering.
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
        # A section index at or above this does not fit its 16-bit field.
        # The header, section 0 and `.symtab_shndx` contain the real index.
        SHN_LORESERVE = 0xFF00
        SHN_XINDEX = 0xFFFF

        # The AArch64 relocation type for each kind that `Backend::Aarch64`
        # records.
        RELOC = {
          abs64: 257,          # R_AARCH64_ABS64
          branch26: 283,       # R_AARCH64_CALL26
          page21: 275,         # R_AARCH64_ADR_PREL_PG_HI21
          pageoff12: 277,      # R_AARCH64_ADD_ABS_LO12_NC
          got_page21: 311,     # R_AARCH64_ADR_GOT_PAGE
          got_pageoff12: 312   # R_AARCH64_LD64_GOT_LO12_NC
        }.freeze #: Hash[reloc_kind, Integer]

        # Each `Obj` section's ELF name prefix, type and flags.
        SECTIONS = {
          function: [".text", SHT_PROGBITS, SHF_ALLOC | SHF_EXECINSTR],
          text_const: [".rodata", SHT_PROGBITS, SHF_ALLOC],
          data_const: [".data.rel.ro", SHT_PROGBITS, SHF_ALLOC | SHF_WRITE],
          data: [".data", SHT_PROGBITS, SHF_ALLOC | SHF_WRITE],
          bss: [".bss", SHT_NOBITS, SHF_ALLOC | SHF_WRITE]
        }.freeze #: Hash[Symbol, [String, Integer, Integer]]

        # @rbs skip -- typed in sig/zr/obj/elf/object_file.rbs
        Section = Struct.new(:name, :type, :flags, :bytes, :size, :align, :link, :info, :entsize, :offset, :item,
                             keyword_init: true)

        # One `Elf64_Sym`. `strx` is the name's offset in the string table;
        # `write` sets it after it builds that table.
        # @rbs skip -- typed in sig/zr/obj/elf/object_file.rbs
        Sym = Struct.new(:name, :bind, :type, :shndx, :value, :size, :strx, keyword_init: true)

        module_function

        # Returns the bytes of the object file.
        #: (Unit unit) -> String
        def write(unit)
          items = unit.items
          sections = [Section.new(name: "", type: 0, flags: 0, bytes: "".b, size: 0, align: 0, link: 0, info: 0, entsize: 0)]
          items.each do |kind, item|
            prefix, type, flags = SECTIONS.fetch(kind) { raise ArgumentError, "no ELF section for #{kind}" }
            bytes = type == SHT_NOBITS ? "".b : item.bytes
            sections << Section.new(name: "#{prefix}.#{item.name}", type: type, flags: flags, bytes: bytes, size: item.size,
                                    align: item.align, link: 0, info: 0, entsize: 0, item: item)
          end
          item_sections = sections.drop(1)

          symbols = symbol_table(unit, item_sections)
          index = symbols.each_with_index.to_h { |sym, i| [sym.name, i] }
          symtab_index = sections.size + item_sections.count { |s| !s.item.relocs.empty? } + 1
          extended = symbols.any? { |sym| sym.shndx >= SHN_LORESERVE }
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

          table = StringTable.new(blank: 0)
          symbols.each { |sym| sym.strx = table.add(sym.name) }
          strtab = table.bytes
          locals = symbols.count { |sym| sym.bind == STB_LOCAL }
          symtab = symbols.map do |sym|
            shndx = sym.shndx >= SHN_LORESERVE ? SHN_XINDEX : sym.shndx
            [sym.strx, (sym.bind << 4) | sym.type, 0, shndx, sym.value, sym.size].pack("L<CCS<Q<Q<")
          end.join
          strtab_index = sections.size + (extended ? 2 : 1)
          sections << Section.new(name: ".symtab", type: SHT_SYMTAB, flags: 0, bytes: symtab, size: symtab.bytesize,
                                  align: 8, link: strtab_index, info: locals, entsize: 24)
          raise ArgumentError, "the symbol table is not where the relocations say" unless sections.size - 1 == symtab_index

          if extended
            shndx = symbols.map { |sym| sym.shndx >= SHN_LORESERVE ? sym.shndx : 0 }.pack("L<*")
            sections << Section.new(name: ".symtab_shndx", type: SHT_SYMTAB_SHNDX, flags: 0, bytes: shndx, size: shndx.bytesize,
                                    align: 4, link: symtab_index, info: 0, entsize: 4)
          end

          sections << Section.new(name: ".strtab", type: SHT_STRTAB, flags: 0, bytes: strtab, size: strtab.bytesize,
                                  align: 1, link: 0, info: 0, entsize: 0)
          section_names = StringTable.new(blank: 0)
          sections << Section.new(name: ".shstrtab", type: SHT_STRTAB, flags: 0, bytes: "".b, size: 0, align: 1, link: 0, info: 0, entsize: 0)
          names = sections.map { |s| section_names.add(s.name) }
          shstrtab = section_names.bytes
          sections.last.bytes = shstrtab
          sections.last.size = shstrtab.bytesize

          out = +"".b
          out << ("\0" * 64).b
          sections.drop(1).each do |s|
            next if s.type == SHT_NOBITS

            Bytes.pad_align(out, [s.align, 1].max)
            s.offset = out.bytesize
            out << s.bytes
          end
          sections.select { |s| s.type == SHT_NOBITS }.each { |s| s.offset = out.bytesize }
          Bytes.pad_align(out, 8)
          shoff = out.bytesize
          shnum = sections.size
          shstrndx = shnum - 1
          # Section 0 contains the section count and the index of the
          # section names when the header fields are too small.
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
        #: (Unit unit, Array[Section] item_sections) -> Array[Sym]
        def symbol_table(unit, item_sections)
          defined = item_sections.each_with_index.map do |s, i|
            item = s.item
            Sym.new(name: item.name, bind: item.linkage == :export ? STB_GLOBAL : STB_LOCAL,
                    type: item.is_a?(Obj::Code) ? STT_FUNC : STT_OBJECT,
                    shndx: i + 1, value: 0, size: item.size)
          end
          imports = unit.imports.map do |name|
            Sym.new(name: name, bind: STB_GLOBAL, type: STT_NOTYPE, shndx: SHN_UNDEF, value: 0, size: 0)
          end
          null = Sym.new(name: "", bind: STB_LOCAL, type: STT_NOTYPE, shndx: SHN_UNDEF, value: 0, size: 0)
          locals = defined.select { |sym| sym.bind == STB_LOCAL }.sort_by(&:name)
          globals = (defined.select { |sym| sym.bind == STB_GLOBAL } + imports).sort_by(&:name)
          [null] + locals + globals
        end

        #: (Integer shoff, Integer shnum, Integer shstrndx) -> String
        def header(shoff, shnum, shstrndx)
          ident = "\x7FELF".b + [2, 1, 1, 0].pack("C4") + ("\0" * 8).b
          ident + [ET_REL, EM_AARCH64, 1, 0, 0, shoff, 0, 64, 0, 0, 64, shnum, shstrndx].pack("S<S<L<Q<Q<Q<L<S<S<S<S<S<S<")
        end
      end
    end
  end
end
