# frozen_string_literal: true

require_relative "model"

module Ze0
  module Obj
    # A relocatable Mach-O 64 for arm64 (`MH_OBJECT`), from an `Obj::Unit`.
    # One unnamed segment holds `__TEXT,__text`, `__TEXT,__const`,
    # `__DATA,__const`, `__DATA,__data` and `__DATA,__bss`; then `LC_BUILD_VERSION`,
    # `LC_SYMTAB` and `LC_DYSYMTAB`. Symbols are ordered local, exported,
    # imported, each group by name, which is the order `ld` reads. The
    # layout follows <mach-o/loader.h>, <mach-o/nlist.h> and
    # <mach-o/arm64/reloc.h>.
    module MachO
      MH_MAGIC_64 = 0xFEEDFACF
      CPU_TYPE_ARM64 = 0x0100000C
      MH_OBJECT = 1
      MH_SUBSECTIONS_VIA_SYMBOLS = 0x2000
      LC_SEGMENT_64 = 0x19
      LC_SYMTAB = 0x2
      LC_DYSYMTAB = 0xB
      LC_BUILD_VERSION = 0x32
      PLATFORM_MACOS = 1
      S_REGULAR = 0
      S_ZEROFILL = 1
      S_ATTR_PURE_INSTRUCTIONS = 0x80000000
      S_ATTR_SOME_INSTRUCTIONS = 0x00000400
      N_UNDF = 0x0
      N_EXT = 0x1
      N_SECT = 0xE
      NO_SECT = 0

      # arm64 relocation types, and for each: pc-relative?, log2 length.
      RELOC = {
        abs64: [0, 0, 3],
        branch26: [2, 1, 2],
        page21: [3, 1, 2],
        pageoff12: [4, 0, 2],
        got_page21: [5, 1, 2],
        got_pageoff12: [6, 0, 2]
      }.freeze
      ARM64_RELOC_ADDEND = 10

      # The sections, in file order, with the `Obj` sections that land in each.
      SECTIONS = [
        ["__text", "__TEXT", S_REGULAR | S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS, [:function]],
        ["__const", "__TEXT", S_REGULAR, [:text_const]],
        ["__const", "__DATA", S_REGULAR, [:data_const]],
        ["__data", "__DATA", S_REGULAR, [:data]],
        ["__bss", "__DATA", S_ZEROFILL, [:bss]]
      ].freeze

      Placed = Struct.new(:item, :section, :addr)

      module_function

      # The file's bytes.
      def write(unit, minos: [14, 0, 0])
        items = unit.functions.map { |f| [:function, f] } + unit.data.map { |d| [d.section, d] }
        placed = []
        sections = SECTIONS.map do |name, seg, flags, kinds|
          { name: name, seg: seg, flags: flags, bytes: +"".b, size: 0, align: 0, items: [], relocs: [] }
        end
        # Place every item: addresses run through the segment, each section
        # aligned to the widest item it holds.
        addr = 0
        sections.each_with_index do |s, si|
          kinds = SECTIONS[si][3]
          mine = items.select { |kind, _| kinds.include?(kind) }
          s[:align] = mine.map { |_, i| Math.log2(i.align).ceil }.max || 0
          addr = align_up(addr, 1 << s[:align])
          s[:addr] = addr
          mine.each do |_, item|
            pad = align_up(s[:size], item.align) - s[:size]
            s[:bytes] << ("\0" * pad).b unless s[:flags] == S_ZEROFILL
            s[:size] += pad
            placed << Placed.new(item, si, addr + s[:size])
            s[:items] << [item, s[:size]]
            s[:bytes] << item.bytes unless s[:flags] == S_ZEROFILL
            s[:size] += item.size
          end
          addr += s[:size]
        end
        vmsize = addr

        symbols = symbol_table(unit, placed)
        index = symbols.each_with_index.to_h { |sym, i| [sym[:name], i] }
        sections.each do |s|
          s[:items].each do |item, at|
            item.relocs.each do |r|
              s[:relocs] << relocation(at + r.offset, r, index.fetch("_#{r.symbol}"))
            end
          end
          # Highest address first, an ADDEND entry ahead of its partner.
          s[:relocs] = s[:relocs].sort_by { |group| -group[0] }.flat_map { |group| group[1] }
        end

        header_size = 32
        segment_cmd = 72 + (80 * sections.size)
        build_version_cmd = 24
        symtab_cmd = 24
        dysymtab_cmd = 80
        ncmds = 4
        sizeofcmds = segment_cmd + build_version_cmd + symtab_cmd + dysymtab_cmd
        offset = align_up(header_size + sizeofcmds, 16)
        data_start = offset
        sections.each do |s|
          next if s[:flags] == S_ZEROFILL

          offset = align_up(offset, 1 << s[:align])
          s[:offset] = offset
          offset += s[:size]
        end
        data_end = offset
        offset = align_up(offset, 8)
        sections.each do |s|
          s[:reloff] = s[:relocs].empty? ? 0 : offset
          offset += s[:relocs].size * 8
        end
        symoff = offset
        offset += symbols.size * 16
        stroff = offset
        strtab = +"\0".b
        symbols.each do |sym|
          sym[:strx] = strtab.bytesize
          strtab << sym[:name].b << "\0".b
        end
        strsize = strtab.bytesize

        out = +"".b
        out << [MH_MAGIC_64, CPU_TYPE_ARM64, 0, MH_OBJECT, ncmds, sizeofcmds, MH_SUBSECTIONS_VIA_SYMBOLS, 0].pack("L<8")
        out << [LC_SEGMENT_64, segment_cmd].pack("L<2") << ("\0" * 16).b
        out << [0, vmsize, data_start, data_end - data_start, 7, 7, sections.size, 0].pack("Q<4L<4")
        sections.each do |s|
          out << pad16(s[:name]) << pad16(s[:seg])
          out << [s[:addr], s[:size], s[:flags] == S_ZEROFILL ? 0 : s[:offset], s[:align],
                  s[:reloff], s[:relocs].size, s[:flags], 0, 0, 0].pack("Q<2L<8")
        end
        out << [LC_BUILD_VERSION, build_version_cmd, PLATFORM_MACOS, version(minos), version(minos), 0].pack("L<6")
        out << [LC_SYMTAB, symtab_cmd, symoff, symbols.size, stroff, strsize].pack("L<6")
        groups = %i[local export import].map { |l| symbols.count { |sym| sym[:linkage] == l } }
        out << [LC_DYSYMTAB, dysymtab_cmd, 0, groups[0], groups[0], groups[1], groups[0] + groups[1], groups[2]].pack("L<8")
        out << ([0] * 12).pack("L<12")
        out << ("\0" * (data_start - out.bytesize)).b
        sections.each do |s|
          next if s[:flags] == S_ZEROFILL

          out << ("\0" * (s[:offset] - out.bytesize)).b
          out << s[:bytes]
        end
        out << ("\0" * (align_up(out.bytesize, 8) - out.bytesize)).b
        sections.each { |s| s[:relocs].each { |r| out << r } }
        symbols.each do |sym|
          out << [sym[:strx], sym[:type], sym[:sect], 0, sym[:value]].pack("L<CCS<Q<")
        end
        out << strtab
        out
      end

      # Every defined symbol, then every import, in the order `ld` wants.
      def symbol_table(unit, placed)
        defined = placed.map do |p|
          { name: "_#{p.item.name}", linkage: p.item.linkage, sect: p.section + 1, value: p.addr,
            type: N_SECT | (p.item.linkage == :export ? N_EXT : 0) }
        end
        imports = unit.imports.map do |name|
          { name: "_#{name}", linkage: :import, sect: NO_SECT, value: 0, type: N_UNDF | N_EXT }
        end
        %i[local export import].flat_map do |l|
          (defined + imports).select { |s| s[:linkage] == l }.sort_by { |s| s[:name] }
        end
      end

      # `[address, [entries]]`: the packed relocation_info rows for one
      # relocation, an ADDEND row first when the addend is not zero.
      def relocation(address, r, symbol)
        type, pcrel, length = RELOC.fetch(r.kind) { raise ArgumentError, "no arm64 relocation for #{r.kind}" }
        rows = []
        if r.addend != 0 && r.kind != :abs64
          rows << [address, (r.addend & 0xFFFFFF) | (ARM64_RELOC_ADDEND << 28)].pack("L<2")
        end
        rows << [address, symbol | (pcrel << 24) | (length << 25) | (1 << 27) | (type << 28)].pack("L<2")
        [address, rows]
      end

      def align_up(n, a)
        (n + a - 1) & ~(a - 1)
      end

      def pad16(s)
        s.b.ljust(16, "\0")
      end

      def version((x, y, z))
        (x << 16) | (y << 8) | z
      end
    end
  end
end
