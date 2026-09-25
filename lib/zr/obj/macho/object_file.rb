# frozen_string_literal: true

require_relative "../model"
require_relative "../../record"
require_relative "../../bytes"

module Zr
  module Obj
    module MachO
      # Writes a relocatable Mach-O 64 object for arm64 (`MH_OBJECT`) from
      # an `Obj::Unit`. One unnamed segment contains `__TEXT,__text`, `__TEXT,__const`,
      # `__DATA,__const`, `__DATA,__data` and `__DATA,__bss`; then `LC_BUILD_VERSION`,
      # `LC_SYMTAB` and `LC_DYSYMTAB`. The symbol order is local, exported,
      # imported, each group sorted by name, because `ld` reads that order. The
      # layout follows <mach-o/loader.h>, <mach-o/nlist.h> and
      # <mach-o/arm64/reloc.h>.
      module ObjectFile
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

        # The sections, in file order, with the `Obj` sections that go in each.
        SECTIONS = [
          ["__text", "__TEXT", S_REGULAR | S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS, [:function]],
          ["__const", "__TEXT", S_REGULAR, [:text_const]],
          ["__const", "__DATA", S_REGULAR, [:data_const]],
          ["__data", "__DATA", S_REGULAR, [:data]],
          ["__bss", "__DATA", S_ZEROFILL, [:bss]]
        ].freeze

        class Placed < Record
          FIELDS = %i[item section addr].freeze
          attr_accessor :item, :section, :addr

          def initialize(item = nil, section = nil, addr = nil)
            @item = item
            @section = section
            @addr = addr
          end

          def to_a = [@item, @section, @addr]
        end

        # An object as `read` returns it. `symbols` contains two words for
        # each symbol, packed as in `nlist_64`: the string offset, type,
        # section and description in the first word, the value in the
        # second. `strings` is the string table.
        class Read < Record
          FIELDS = %i[sections symbols strings].freeze
          attr_accessor :sections, :symbols, :strings

          def initialize(sections: nil, symbols: nil, strings: nil)
            @sections = sections
            @symbols = symbols
            @strings = strings
          end

          def to_a = [@sections, @symbols, @strings]

          def count = symbols.size / 2
          def strx(index) = symbols[index * 2] & 0xFFFF_FFFF
          def type(index) = (symbols[index * 2] >> 32) & 0xFF
          def sect(index) = (symbols[index * 2] >> 40) & 0xFF
          def value(index) = symbols[(index * 2) + 1]

          # A symbol's name. This splits the table once and keeps each name
          # by its offset. In the compiled runtime, a search for the end of
          # the name from the offset counts characters from the start of
          # the table, once for each of hundreds of thousands of symbols.
          def name(index)
            @names ||= begin
              table = {}
              at = 0
              strings.split("\0").each do |name|
                table[at] = name
                at += name.bytesize + 1
              end
              table
            end
            @names.fetch(strx(index))
          end
        end

        # A section as `read` returns it. `relocs` contains two words for
        # each `relocation_info`: the address and the packed other fields.
        class Section < Record
          FIELDS = %i[name segment addr size align flags bytes relocs].freeze
          attr_accessor :name, :segment, :addr, :size, :align, :flags, :bytes, :relocs

          def initialize(name: nil, segment: nil, addr: nil, size: nil, align: nil, flags: nil, bytes: nil, relocs: nil)
            @name = name
            @segment = segment
            @addr = addr
            @size = size
            @align = align
            @flags = flags
            @bytes = bytes
            @relocs = relocs
          end

          def to_a = [@name, @segment, @addr, @size, @align, @flags, @bytes, @relocs]
        end

        module_function

        # Reads back an object that this module wrote, and returns what a
        # link needs. It reads only the layout that `write` makes, and
        # refuses all others. It slices each field before it unpacks it,
        # because `unpack` in the compiled runtime copies the full string.
        def read(bytes)
          magic, cpu, _sub, type, ncmds = bytes.byteslice(0, 20).unpack("L<5")
          unless magic == MH_MAGIC_64 && cpu == CPU_TYPE_ARM64 && type == MH_OBJECT
            raise ArgumentError, "not an arm64 Mach-O object"
          end

          sections = []
          symbols = strings = nil
          at = 32
          ncmds.times do
            cmd, size = bytes.byteslice(at, 8).unpack("L<2")
            case cmd
            when LC_SEGMENT_64
              bytes.byteslice(at + 64, 4).unpack1("L<").times do |i|
                s = at + 72 + (i * 80)
                name, segment = bytes.byteslice(s, 32).unpack("a16a16").map { |n| n.delete("\0") }
                addr, size_, offset, align, reloff, nreloc, flags = bytes.byteslice(s + 32, 40).unpack("Q<2L<6")
                sections << Section.new(name: name, segment: segment, addr: addr, size: size_, align: align, flags: flags,
                                        bytes: flags == S_ZEROFILL ? nil : bytes.byteslice(offset, size_),
                                        relocs: nreloc.zero? ? [] : bytes.byteslice(reloff, nreloc * 8).unpack("L<*"))
              end
            when LC_SYMTAB
              symoff, nsyms, stroff, strsize = bytes.byteslice(at + 8, 16).unpack("L<4")
              symbols = nsyms.zero? ? [] : bytes.byteslice(symoff, nsyms * 16).unpack("Q<*")
              strings = bytes.byteslice(stroff, strsize)
            end
            at += size
          end
          Read.new(sections: sections, symbols: symbols || [], strings: strings || "\0".b)
        end

        # Returns a unit in the form that `read` returns, without writing an
        # object. The linker takes this form as input; writing and reading
        # the object instead costs 18% of a link. `read(write(unit))` must
        # equal `of(unit)`; `test/unit/macho_test.rb` checks this.
        def of(unit)
          laid = laid_out(unit)
          sections = laid.sections.map do |s|
            Section.new(name: s[:name], segment: s[:seg], addr: s[:addr], size: s[:size], align: s[:align],
                        flags: s[:flags], bytes: s[:flags] == S_ZEROFILL ? nil : s[:bytes], relocs: s[:relocs])
          end
          symbols = laid.symbols.flat_map { |sym| nlist_words(sym) }
          Read.new(sections: sections, symbols: symbols, strings: laid.strtab)
        end

        # One symbol as the two words of its `nlist_64`: n_strx, n_type,
        # n_sect and a zero n_desc in the first, n_value in the second.
        def nlist_words(sym) = [sym[:strx] | (sym[:type] << 32) | (sym[:sect] << 40), sym[:value]]

        # One symbol, packed as `nlist_64`.
        def nlist(sym) = nlist_words(sym).pack("Q<2")

        # Returns the bytes of the object file.
        def write(unit, minos: [14, 0, 0]) = bytes(laid_out(unit), minos)

        # The layout before any bytes are written: the sections and their
        # bytes, the symbol table, the relocations and the string table.
        # Both `write` and `of` start from this layout.
        class Laid < Record
          FIELDS = %i[sections symbols strtab vmsize data_start data_end symoff stroff sizeofcmds segment_cmd].freeze
          attr_accessor :sections, :symbols, :strtab, :vmsize, :data_start, :data_end, :symoff, :stroff, :sizeofcmds, :segment_cmd

          def initialize(sections: nil, symbols: nil, strtab: nil, vmsize: nil, data_start: nil, data_end: nil, symoff: nil,
                         stroff: nil, sizeofcmds: nil, segment_cmd: nil)
            @sections = sections
            @symbols = symbols
            @strtab = strtab
            @vmsize = vmsize
            @data_start = data_start
            @data_end = data_end
            @symoff = symoff
            @stroff = stroff
            @sizeofcmds = sizeofcmds
            @segment_cmd = segment_cmd
          end

          def to_a = [@sections, @symbols, @strtab, @vmsize, @data_start, @data_end, @symoff, @stroff, @sizeofcmds, @segment_cmd]
        end

        def laid_out(unit)
          items = unit.functions.map { |f| [:function, f] } + unit.data.map { |d| [d.section, d] }
          placed = []
          sections = SECTIONS.map do |name, seg, flags, _kinds|
            { name: name, seg: seg, flags: flags, bytes: +"".b, size: 0, align: 0, items: [], relocs: [] }
          end
          # Places every item. Addresses increase through the segment. Each
          # section uses the largest alignment of its items.
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
              s[:bytes] << with_addends(item) unless s[:flags] == S_ZEROFILL
              s[:size] += item.size
            end
            addr += s[:size]
          end
          vmsize = addr

          symbols = symbol_table(unit, placed)
          # Symbol index by the name in a relocation, without the leading `_`.
          index = {}
          symbols.each_with_index { |sym, i| index[sym[:bare]] = i }
          sections.each do |s|
            s[:items].each do |item, at|
              item.relocs.each do |r|
                s[:relocs] << relocation(at + r.offset, r, index.fetch(r.symbol))
              end
            end
            # The words of all relocation_info entries: highest address
            # first, each ADDEND entry before its paired entry.
            s[:relocs] = s[:relocs].sort_by { |group| -group[0] }.flat_map { |group| group[1] }
          end

          segment_cmd = 72 + (80 * sections.size)
          sizeofcmds = segment_cmd + 24 + 24 + 80
          offset = align_up(32 + sizeofcmds, 16)
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
            offset += s[:relocs].size * 4
          end
          symoff = offset
          offset += symbols.size * 16
          stroff = offset
          strtab = +"\0".b
          symbols.each do |sym|
            sym[:strx] = strtab.bytesize
            strtab << sym[:name].b << "\0".b
          end
          Laid.new(sections: sections, symbols: symbols, strtab: strtab, vmsize: vmsize, data_start: data_start,
                   data_end: data_end, symoff: symoff, stroff: stroff, sizeofcmds: sizeofcmds,
                   segment_cmd: segment_cmd)
        end

        # A laid-out unit as a Mach-O object file.
        def bytes(laid, minos)
          sections = laid.sections
          symbols = laid.symbols
          vmsize = laid.vmsize
          data_start = laid.data_start
          sizeofcmds = laid.sizeofcmds
          strsize = laid.strtab.bytesize
          ncmds = 4
          build_version_cmd = symtab_cmd = 24
          dysymtab_cmd = 80
          out = +"".b
          out << [MH_MAGIC_64, CPU_TYPE_ARM64, 0, MH_OBJECT, ncmds, sizeofcmds, MH_SUBSECTIONS_VIA_SYMBOLS, 0].pack("L<8")
          out << [LC_SEGMENT_64, laid.segment_cmd].pack("L<2") << ("\0" * 16).b
          out << [0, vmsize, data_start, laid.data_end - data_start, 7, 7, sections.size, 0].pack("Q<4L<4")
          sections.each do |s|
            out << pad16(s[:name]) << pad16(s[:seg])
            out << [s[:addr], s[:size], s[:flags] == S_ZEROFILL ? 0 : s[:offset], s[:align],
                    s[:reloff], s[:relocs].size / 2, s[:flags], 0, 0, 0].pack("Q<2L<8")
          end
          out << [LC_BUILD_VERSION, build_version_cmd, PLATFORM_MACOS, version(minos), version(minos), 0].pack("L<6")
          out << [LC_SYMTAB, symtab_cmd, laid.symoff, symbols.size, laid.stroff, strsize].pack("L<6")
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
          sections.each { |s| out << s[:relocs].pack("L<*") }
          symbols.each { |sym| out << nlist(sym) }
          out << laid.strtab
          out
        end

        # Every defined symbol, then every import, in the order that `ld` needs.
        def symbol_table(unit, placed)
          defined = placed.map do |p|
            { name: "_#{p.item.name}", bare: p.item.name, linkage: p.item.linkage, sect: p.section + 1, value: p.addr,
              type: N_SECT | (p.item.linkage == :export ? N_EXT : 0) }
          end
          imports = unit.imports.map do |name|
            { name: "_#{name}", bare: name, linkage: :import, sect: NO_SECT, value: 0, type: N_UNDF | N_EXT }
          end
          %i[local export import].flat_map do |l|
            (defined + imports).select { |s| s[:linkage] == l }.sort_by { |s| s[:name] }
          end
        end

        # Returns an item's bytes. An `abs64` relocation puts its addend in
        # the slot that it patches, because `ld` reads it there.
        def with_addends(item)
          sums = item.relocs.select { |r| r.kind == :abs64 && r.addend.to_i != 0 }
          return item.bytes if sums.empty?

          sums.each_with_object(item.bytes.dup) { |r, bytes| bytes[r.offset, 8] = [r.addend].pack("q<") }
        end

        # Returns `[address, words]`: the relocation_info entries for one
        # relocation, two 32-bit words each. An ADDEND entry comes first
        # when the addend is not zero.
        def relocation(address, r, symbol)
          type, pcrel, length = RELOC.fetch(r.kind) { raise ArgumentError, "no arm64 relocation for #{r.kind}" }
          rows = []
          if r.addend != 0 && r.kind != :abs64
            rows << address << ((r.addend & 0xFFFFFF) | (ARM64_RELOC_ADDEND << 28))
          end
          rows << address << (symbol | (pcrel << 24) | (length << 25) | (1 << 27) | (type << 28))
          [address, rows]
        end

        def align_up(n, a) = Bytes.align(n, a)

        def pad16(s)
          s.b.ljust(16, "\0")
        end

        def version((x, y, z))
          (x << 16) | (y << 8) | z
        end
      end
    end
  end
end
