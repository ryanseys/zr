# frozen_string_literal: true

require_relative "../model"
require_relative "../../bytes"
require_relative "../string_table"
require_relative "../../target"

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
        }.freeze #: Hash[reloc_kind, [Integer, Integer, Integer]]
        ARM64_RELOC_ADDEND = 10

        # The sections, in file order, with the `Obj` sections that go in each.
        SECTIONS = [
          ["__text", "__TEXT", S_REGULAR | S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS, [:function]],
          ["__const", "__TEXT", S_REGULAR, [:text_const]],
          ["__const", "__DATA", S_REGULAR, [:data_const]],
          ["__data", "__DATA", S_REGULAR, [:data]],
          ["__bss", "__DATA", S_ZEROFILL, [:bss]]
        ].freeze #: Array[[String, String, Integer, Array[Symbol]]]

        # The fields of this file's records are typed in
        # sig/zr/obj/macho/object_file.rbs, their methods here.
        # @rbs skip
        Placed = Data.define(:item, :section, :addr)

        # An object as `read` returns it. `symbols` contains two words for
        # each symbol, packed as in `nlist_64`: the string offset, type,
        # section and description in the first word, the value in the
        # second. `strings` is the string table.
        # @rbs skip
        Read = Struct.new(:sections, :symbols, :strings, keyword_init: true)

        class Read
          # @rbs @names: Hash[Integer, String]?

          #: () -> Integer
          def count = symbols.size / 2

          #: (Integer index) -> Integer
          def strx(index) = symbols[index * 2] & 0xFFFF_FFFF

          #: (Integer index) -> Integer
          def type(index) = (symbols[index * 2] >> 32) & 0xFF

          #: (Integer index) -> Integer
          def sect(index) = (symbols[index * 2] >> 40) & 0xFF

          #: (Integer index) -> Integer
          def value(index) = symbols[(index * 2) + 1]

          # A symbol's name. This splits the table once and keeps each name
          # by its offset. In the compiled runtime, a search for the end of
          # the name from the offset counts characters from the start of
          # the table, once for each of hundreds of thousands of symbols.
          #: (Integer index) -> String
          def name(index)
            names = @names ||= begin
              table = {} #: Hash[Integer, String]
              at = 0
              strings.split("\0").each do |name|
                table[at] = name
                at += name.bytesize + 1
              end
              table
            end
            names.fetch(strx(index))
          end
        end

        # A section as `read` returns it. `relocs` contains two words for
        # each `relocation_info`: the address and the packed other fields.
        # @rbs skip
        Section =Struct.new(:name, :segment, :addr, :size, :align, :flags, :bytes, :relocs, keyword_init: true)

        module_function

        # Reads back an object that this module wrote, and returns what a
        # link needs. It reads only the layout that `write` makes, and
        # refuses all others. It slices each field before it unpacks it,
        # because `unpack` in the compiled runtime copies the full string.
        #: (String bytes) -> Read
        def read(bytes)
          # Each slice is in the bytes, so it is a String, and each `L`
          # and `Q` field is an Integer.
          head = bytes.byteslice(0, 20) #: String
          magic, cpu, _sub, type, ncmds = head.unpack("L<5") #: [Integer, Integer, Integer, Integer, Integer]
          unless magic == MH_MAGIC_64 && cpu == CPU_TYPE_ARM64 && type == MH_OBJECT
            raise ArgumentError, "not an arm64 Mach-O object"
          end

          sections = [] #: Array[Section]
          symbols = nil #: Array[Integer]?
          strings = nil #: String?
          at = 32
          ncmds.times do
            command = bytes.byteslice(at, 8) #: String
            cmd, size = command.unpack("L<2") #: [Integer, Integer]
            case cmd
            when LC_SEGMENT_64
              nsects = bytes.byteslice(at + 64, 4) #: String
              count = nsects.unpack1("L<") #: Integer
              count.times do |i|
                s = at + 72 + (i * 80)
                names = bytes.byteslice(s, 32) #: String
                padded = names.unpack("a16a16") #: [String, String]
                name = padded[0].delete("\0")
                segment = padded[1].delete("\0")
                fields = bytes.byteslice(s + 32, 40) #: String
                words = fields.unpack("Q<2L<6") #: [Integer, Integer, Integer, Integer, Integer, Integer, Integer]
                addr, size_, offset, align, reloff, nreloc, flags = words
                relocs = if nreloc.zero?
                           [] #: Array[Integer]
                         else
                           table = bytes.byteslice(reloff, nreloc * 8) #: String
                           table.unpack("L<*") #: Array[Integer]
                         end
                sections << Section.new(name: name, segment: segment, addr: addr, size: size_, align: align, flags: flags,
                                        bytes: flags == S_ZEROFILL ? nil : bytes.byteslice(offset, size_), relocs: relocs)
              end
            when LC_SYMTAB
              symtab = bytes.byteslice(at + 8, 16) #: String
              symoff, nsyms, stroff, strsize = symtab.unpack("L<4") #: [Integer, Integer, Integer, Integer]
              symbols = if nsyms.zero?
                          [] #: Array[Integer]
                        else
                          table = bytes.byteslice(symoff, nsyms * 16) #: String
                          table.unpack("Q<*") #: Array[Integer]
                        end
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
        #: (Unit unit) -> Read
        def of(unit)
          laid = laid_out(unit)
          sections = laid.sections.map do |s|
            Section.new(name: s.name, segment: s.seg, addr: s.addr, size: s.size, align: s.align,
                        flags: s.flags, bytes: s.flags == S_ZEROFILL ? nil : s.bytes, relocs: s.relocs)
          end
          symbols = laid.symbols.flat_map { |sym| nlist_words(sym) }
          Read.new(sections: sections, symbols: symbols, strings: laid.strtab)
        end

        # One symbol as the two words of its `nlist_64`: n_strx, n_type,
        # n_sect and a zero n_desc in the first, n_value in the second.
        #: (Sym sym) -> [Integer, Integer]
        def nlist_words(sym) = [sym.strx | (sym.type << 32) | (sym.sect << 40), sym.value]

        # One symbol, packed as `nlist_64`.
        #: (Sym sym) -> String
        def nlist(sym) = nlist_words(sym).pack("Q<2")

        # Returns the bytes of the object file.
        #: (Unit unit, ?minos: Array[Integer]) -> String
        def write(unit, minos: Target::AARCH64_DARWIN.min_os_parts) = bytes(laid_out(unit), minos)

        # The layout before any bytes are written: the sections and their
        # bytes, the symbol table, the relocations and the string table.
        # Both `write` and `of` start from this layout.
        # @rbs skip
        Laid = Data.define(:sections, :symbols, :strtab, :vmsize, :data_start, :data_end, :symoff, :stroff, :sizeofcmds,
                           :segment_cmd)

        # A section while `laid_out` builds it. `addr`, `offset` and `reloff`
        # stay zero until the layout reaches them; `items` holds each item
        # with its offset in the section.
        # @rbs skip
        SectionBuild = Struct.new(:name, :seg, :flags, :bytes, :size, :align, :items, :relocs, :addr, :offset, :reloff,
                                  keyword_init: true)

        # A symbol while `laid_out` builds it. `bare` is the name without the
        # leading `_`. `strx` stays nil until the string table exists.
        # @rbs skip
        Sym = Struct.new(:name, :bare, :linkage, :sect, :value, :type, :strx, keyword_init: true)

        #: (Unit unit) -> Laid
        def laid_out(unit)
          functions = unit.functions.map { |f| [:function, f] } #$ [Symbol, Code | Datum]
          data = unit.data.map { |d| [d.section, d] } #$ [Symbol, Code | Datum]
          items = functions + data
          placed = [] #: Array[Placed]
          sections = SECTIONS.map do |name, seg, flags, _kinds|
            SectionBuild.new(name: name, seg: seg, flags: flags, bytes: +"".b, size: 0, align: 0, items: [], relocs: [],
                             addr: 0, offset: 0, reloff: 0)
          end
          # Places every item. Addresses increase through the segment. Each
          # section uses the largest alignment of its items.
          addr = 0
          sections.each_with_index do |s, si|
            kinds = SECTIONS[si][3]
            mine = items.select { |item| kinds.include?(item.first) }
            s.align = mine.map { |_, i| Math.log2(i.align).ceil }.max || 0
            addr = Bytes.align(addr, 1 << s.align)
            s.addr = addr
            mine.each do |_, item|
              pad = Bytes.align(s.size, item.align) - s.size
              s.bytes << ("\0" * pad).b unless s.flags == S_ZEROFILL
              s.size += pad
              placed << Placed.new(item, si, addr + s.size)
              s.items << [item, s.size]
              s.bytes << with_addends(item) unless s.flags == S_ZEROFILL
              s.size += item.size
            end
            addr += s.size
          end
          vmsize = addr

          symbols = symbol_table(unit, placed)
          # Symbol index by the name in a relocation, without the leading `_`.
          index = {} #: Hash[String, Integer]
          symbols.each_with_index { |sym, i| index[sym.bare] = i }
          sections.each do |s|
            s.items.each do |item, at|
              item.relocs.each do |r|
                s.relocs << relocation(at + r.offset, r, index.fetch(r.symbol))
              end
            end
            # The words of all relocation_info entries: highest address
            # first, each ADDEND entry before its paired entry.
            s.relocs = s.relocs.sort_by { |group| -group[0] }.flat_map { |group| group[1] }
          end

          segment_cmd = 72 + (80 * sections.size)
          sizeofcmds = segment_cmd + 24 + 24 + 80 #: Integer
          offset = Bytes.align(32 + sizeofcmds, 16)
          data_start = offset
          sections.each do |s|
            next if s.flags == S_ZEROFILL

            offset = Bytes.align(offset, 1 << s.align)
            s.offset = offset
            offset += s.size
          end
          data_end = offset
          offset = Bytes.align(offset, 8)
          sections.each do |s|
            s.reloff = s.relocs.empty? ? 0 : offset
            offset += s.relocs.size * 4
          end
          symoff = offset
          offset += symbols.size * 16
          stroff = offset
          table = StringTable.new
          symbols.each { |sym| sym.strx = table.add(sym.name) }
          strtab = table.bytes
          Laid.new(sections: sections, symbols: symbols, strtab: strtab, vmsize: vmsize, data_start: data_start,
                   data_end: data_end, symoff: symoff, stroff: stroff, sizeofcmds: sizeofcmds,
                   segment_cmd: segment_cmd)
        end

        # A laid-out unit as a Mach-O object file.
        #: (Laid laid, Array[Integer] minos) -> String
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
            out << pad16(s.name) << pad16(s.seg)
            out << [s.addr, s.size, s.flags == S_ZEROFILL ? 0 : s.offset, s.align,
                    s.reloff, s.relocs.size / 2, s.flags, 0, 0, 0].pack("Q<2L<8")
          end
          out << [LC_BUILD_VERSION, build_version_cmd, PLATFORM_MACOS, version(minos), version(minos), 0].pack("L<6")
          out << [LC_SYMTAB, symtab_cmd, laid.symoff, symbols.size, laid.stroff, strsize].pack("L<6")
          groups = %i[local export import].map { |l| symbols.count { |sym| sym.linkage == l } }
          out << [LC_DYSYMTAB, dysymtab_cmd, 0, groups[0], groups[0], groups[1], groups[0] + groups[1], groups[2]].pack("L<8")
          out << ([0] * 12).pack("L<12")
          out << ("\0" * (data_start - out.bytesize)).b
          sections.each do |s|
            next if s.flags == S_ZEROFILL

            out << ("\0" * (s.offset - out.bytesize)).b
            out << s.bytes
          end
          out << ("\0" * (Bytes.align(out.bytesize, 8) - out.bytesize)).b
          sections.each { |s| out << s.relocs.pack("L<*") }
          symbols.each { |sym| out << nlist(sym) }
          out << laid.strtab
          out
        end

        # Every defined symbol, then every import, in the order that `ld` needs.
        #: (Unit unit, Array[Placed] placed) -> Array[Sym]
        def symbol_table(unit, placed)
          defined = placed.map do |p|
            Sym.new(name: "_#{p.item.name}", bare: p.item.name, linkage: p.item.linkage, sect: p.section + 1, value: p.addr,
                    type: N_SECT | (p.item.linkage == :export ? N_EXT : 0))
          end
          imports = unit.imports.map do |name|
            Sym.new(name: "_#{name}", bare: name, linkage: :import, sect: NO_SECT, value: 0, type: N_UNDF | N_EXT)
          end
          %i[local export import].flat_map do |l|
            (defined + imports).select { |s| s.linkage == l }.sort_by(&:name)
          end
        end

        # Returns an item's bytes. An `abs64` relocation puts its addend in
        # the slot that it patches, because `ld` reads it there.
        #: (Code | Datum item) -> String
        def with_addends(item)
          sums = item.relocs.select { |r| r.kind == :abs64 && r.addend.to_i != 0 }
          return item.bytes if sums.empty?

          sums.each_with_object(item.bytes.dup) { |r, bytes| bytes[r.offset, 8] = [r.addend].pack("q<") }
        end

        # Returns `[address, words]`: the relocation_info entries for one
        # relocation, two 32-bit words each. An ADDEND entry comes first
        # when the addend is not zero.
        #: (Integer address, Reloc r, Integer symbol) -> [Integer, Array[Integer]]
        def relocation(address, r, symbol)
          type, pcrel, length = RELOC.fetch(r.kind) { raise ArgumentError, "no arm64 relocation for #{r.kind}" }
          rows = [] #: Array[Integer]
          if r.addend != 0 && r.kind != :abs64
            rows << address << ((r.addend & 0xFFFFFF) | (ARM64_RELOC_ADDEND << 28))
          end
          rows << address << (symbol | (pcrel << 24) | (length << 25) | (1 << 27) | (type << 28))
          [address, rows]
        end

        #: (String s) -> String
        def pad16(s)
          s.b.ljust(16, "\0")
        end

        # Steep 2.1 cannot type a destructured parameter, so this has no
        # annotation: `(Array[Integer]) -> Integer`.
        def version((x, y, z))
          (x << 16) | (y << 8) | z
        end
      end
    end
  end
end
