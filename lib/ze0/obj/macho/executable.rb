# frozen_string_literal: true

require "digest/sha2"

require_relative "block"
require_relative "prelink"
require_relative "libsystem"
require_relative "skeleton"
require_relative "../../record"

module Ze0
  module Obj
    module MachO
      # A program's unit, linked beside a `Prelink`, to a complete, signed
      # `MH_EXECUTE` that runs: the link step, in Ruby, for a program whose
      # every import is libSystem's.
      #
      # Beside a base -- the runtime's objects, linked once -- the base
      # keeps the addresses it was linked at, and the program's parts go in
      # segments of their own: `__PROGRAM` after `__TEXT`, and
      # `__DATA_PROGRAM` after `__DATA`. Only the program is relocated here,
      # and only the base's external slots are written again; the base's
      # other pages keep the hashes they were kept with. Without a base the
      # unit is the whole image, in `__TEXT`, `__DATA_CONST` and `__DATA`.
      #
      # What is added is the Mach-O container, chained fixups so a
      # position-independent image can be rebased and bound, a symbol
      # table sorted by name, which a program's JIT searches in place for
      # the runtime's functions (`zr_os_symbol`) -- an exports trie over a
      # third of a million names was six megabytes and a second a link --
      # and the ad-hoc code signature Apple Silicon will not run a binary
      # without.
      #
      # It does not strip: nearly all of the runtime is reachable from its
      # dispatch tables, and `ld -dead_strip` removed less than one percent.
      #
      # It refuses rather than guesses. A symbol nothing defines and
      # libSystem does not define either would not be found by dyld, and
      # this says which symbol it is.
      class Executable
        PAGE = Prelink::PAGE
        HASH_PAGE = Prelink::HASH_PAGE
        BASE = Prelink::BASE
        # The main stack, which holds ruby frames as native frames. `ld`
        # writes this from `-stack_size`; nothing writes it for an image
        # that no linker touched, so this does, and the two roads give a
        # program the same room.
        STACK = 0x400_0000
        # The oldest macOS a binary loads on, and the SDK it says it was
        # built against, which is the same: no SDK is read.
        MIN_MACOS = (14 << 16) | (0 << 8)
        SDK = MIN_MACOS

        MH_MAGIC_64 = 0xFEEDFACF
        CPU_TYPE_ARM64 = 0x0100_000C
        MH_EXECUTE = 2
        FLAGS = 0x1 | 0x4 | 0x80 | 0x20_0000 # NOUNDEFS DYLDLINK TWOLEVEL PIE

        LC_SEGMENT_64 = 0x19
        LC_SYMTAB = 0x2
        LC_DYSYMTAB = 0xB
        LC_LOAD_DYLIB = 0xC
        LC_LOAD_DYLINKER = 0xE
        LC_UUID = 0x1B
        LC_CODE_SIGNATURE = 0x1D
        LC_BUILD_VERSION = 0x32
        LC_MAIN = 0x8000_0028
        LC_DYLD_CHAINED_FIXUPS = 0x8000_0034
        LC_DYLD_EXPORTS_TRIE = 0x8000_0033

        READ = 1
        WRITE = 2
        EXEC = 4
        SG_READ_ONLY = 0x10
        S_REGULAR = 0
        S_ZEROFILL = 1
        CODE = 0x8000_0000 | 0x0000_0400 # PURE_INSTRUCTIONS | SOME_INSTRUCTIONS

        DYLINKER = "/usr/lib/dyld"
        LIBSYSTEM = "/usr/lib/libSystem.B.dylib"

        # One 8-byte pointer a slot, threaded page by page: the only chained
        # format an ordinary arm64 image needs.
        PTR_64_OFFSET = 6
        IMPORT_FORMAT = 1

        # Each part's section: its name, and its flags.
        SECTIONS = { text: ["__text", CODE], stubs: ["__stubs", CODE], const: ["__const", S_REGULAR],
                     got: ["__got", S_REGULAR], dconst: ["__const", S_REGULAR], data: ["__data", S_REGULAR],
                     bss: ["__bss", S_ZEROFILL] }.freeze
        # The image sections a program's parts are beside a base: after
        # `__TEXT`'s three, `__PROGRAM`'s; after `__DATA`'s, `__DATA_PROGRAM`'s.
        TOP_ORDINALS = { text: 4, stubs: 5, const: 6, got: 11, dconst: 12, data: 13, bss: 14 }.freeze
        # The segments of an image without a base, and the parts in each.
        PLAIN = [["__TEXT", %i[text stubs const], READ | EXEC, 0],
                 ["__DATA_CONST", %i[got dconst], READ | WRITE, SG_READ_ONLY],
                 ["__DATA", %i[data bss], READ | WRITE, 0]].freeze

        # A segment of the image. `pieces` are its file bytes, one after
        # another, each `[bytes, hashes, dirty pages]`: `hashes` are the
        # pages' hashes kept with a base, and nil for bytes made here.
        class Segment < Ze0::Record
          FIELDS = %i[name vm vmsize fileoff filesize prot flags sections pieces starts].freeze
          attr_accessor :name, :vm, :vmsize, :fileoff, :filesize, :prot, :flags, :sections, :pieces, :starts

          def initialize(name: nil, vm: nil, vmsize: nil, fileoff: nil, filesize: nil, prot: nil, flags: nil, sections: nil,
                         pieces: nil, starts: nil)
            @name = name
            @vm = vm
            @vmsize = vmsize
            @fileoff = fileoff
            @filesize = filesize
            @prot = prot
            @flags = flags
            @sections = sections
            @pieces = pieces
            @starts = starts
          end

          def to_a = [@name, @vm, @vmsize, @fileoff, @filesize, @prot, @flags, @sections, @pieces, @starts]
        end
        # A section: its name, address, size, alignment and flags.
        class Section < Ze0::Record
          FIELDS = %i[name vm size align flags].freeze
          attr_accessor :name, :vm, :size, :align, :flags

          def initialize(name = nil, vm = nil, size = nil, align = nil, flags = nil)
            @name = name
            @vm = vm
            @size = size
            @align = align
            @flags = flags
          end

          def to_a = [@name, @vm, @size, @align, @flags]
        end

        Refused = MachO::Refused

        # Writes `out` from `unit` beside `prelink`, or beside the object
        # files `objects` (their bytes) linked now, and answers nil; or
        # answers why it cannot link them and writes nothing. `exports`
        # puts every global in the exports trie, where `dlsym` finds it.
        # `skeleton` is a file of the base's `Skeleton.bytes`, cloned and
        # written into rather than written whole where the system allows.
        def self.write(unit, out, objects: [], prelink: nil, stack: STACK, entry: "main", skeleton: nil)
          prelink ||= Prelink.build(objects)
          new(unit, prelink, out, stack: stack, entry: entry, skeleton: skeleton).write
        rescue Refused => e
          e.message
        end

        # Whether libSystem defines `name`. The answer comes from the
        # committed list, not from this host's libSystem, so it is the same
        # on every host; a name missing from the list is refused.
        def self.libsystem?(name) = LIBSYSTEM_NAMES.include?(name)

        def initialize(unit, prelink, out, stack: STACK, entry: "main", skeleton: nil)
          @base = prelink
          @out = out
          @stack = stack
          @entry = entry
          @skeleton = skeleton
          outside = prelink.empty? ? nil : ->(name) { prelink.global(name) }
          @top = Block.new([ObjectFile.of(unit)], outside: outside)
        end

        def write
          twice = @top.names.find { |name| @base.global(name) }
          raise Refused, "#{twice.delete_prefix("_")} is defined twice" if twice

          @imports = (@base.externals.reject { |name| @top.defines?("_#{name}") } + @top.externals).uniq.sort
          outside = @imports.reject { |name| self.class.libsystem?(name) }
          raise Refused, "#{outside.first} is not libSystem's" unless outside.empty?

          @ordinal = @imports.each_with_index.to_h
          @base.empty? ? plain : beside_base
          entry = @top.entry(@entry) || @base.global("_#{@entry}") or raise Refused, "nothing named #{@entry} to enter at"
          @entry_at = entry - BASE
          fill
          linkedit
          header
          signed = signature
          if @base.empty?
            File.open(@out, "wb") { |file| write_after(file, 0, signed) }
            File.chmod(0o755, @out)
          else
            # The first segment is the header page and the base's text:
            # what the file at `out`, or the skeleton, holds already.
            Skeleton.write_over(@out, @skeleton, @base.blobs.fetch(:text)) do |file, kept|
              file.write(@header)
              kept ? file.seek(@segments.first.filesize) : file.write(@base.blobs.fetch(:text))
              write_after(file, 1, signed)
            end
          end
          nil
        end

        private

        # The segments from the `first`th on, the linkedit and the signature.
        def write_after(file, first, signed)
          @segments.drop(first).each { |s| s.pieces.each { |bytes, _, _| file.write(bytes) } }
          file.write(@linkedit)
          file.write(signed)
        end

        # --- layout --------------------------------------------------------

        # Beside a base: the base's segments where it was linked, the
        # program's code at the end of `__TEXT` and its data at the end of
        # `__DATA`. The file holds the segments in address order.
        def beside_base
          b = @base
          code_at = BASE + b.text_size
          code_size = Patch.align(%i[text stubs const].inject(code_at) { |at, part| place(part, at) } - code_at, PAGE)
          raise Refused, "a program with no code" if code_size.zero?
          raise Refused, "#{code_size} bytes of code, past the room beside the runtime" if code_size > Prelink::RESERVE

          data_at = b.data_end
          file_end = %i[got dconst data].inject(data_at) { |at, part| place(part, at) }
          data_filesize = Patch.align(file_end - data_at, PAGE)
          data_vmsize = Patch.align(place(:bss, file_end) - data_at, PAGE)
          raise Refused, "a program with no data" if data_vmsize.zero?

          @top.addresses!
          @header = "\0".b * PAGE
          text = segment("__TEXT", BASE, b.text_size, 0, READ | EXEC, 0, base_sections(%i[text stubs const]),
                         [[@header, nil, []], [b.blobs[:text], b.hashes[:text], []]])
          code = segment("__PROGRAM", code_at, code_size, after(text), READ | EXEC, 0, top_sections(%i[text stubs const]),
                         [[top_bytes(%i[text stubs const], code_at, code_size), nil, []]])
          got = segment("__DATA_CONST", b.got_vm, b.got_size, after(code), READ | WRITE, SG_READ_ONLY,
                        base_sections(%i[got]), [[b.blobs[:got].dup, b.hashes[:got], []]])
          got.starts = b.starts[:got]
          data = segment("__DATA", b.data_vm, b.data_filesize, after(got), READ | WRITE, 0,
                         base_sections(%i[dconst data bss]), [[b.blobs[:data].dup, b.hashes[:data], []]])
          data.vmsize = b.data_vmsize
          data.starts = b.starts[:data]
          own = segment("__DATA_PROGRAM", data_at, data_filesize, after(data), READ | WRITE, 0,
                        top_sections(%i[got dconst data bss]), [[top_bytes(%i[got dconst data], data_at, data_filesize), nil, []]])
          own.vmsize = data_vmsize
          @segments = [text, code, got, data, own]
          @late = { got: got, data: data }
          @ordinals = TOP_ORDINALS
        end

        # Without a base: the unit is the image. The header shares the
        # first page with the code, so where the code starts depends on how
        # long the load commands are, which depends only on how many
        # segments and sections there are. A segment with nothing in it is
        # not written: an image with a zero-length one does not load.
        def plain
          groups = PLAIN.select { |name, parts, _, _| name == "__TEXT" || parts.any? { |part| @top.size(part).positive? } }
          at = BASE + Patch.align(32 + command_size(groups.size, groups.sum { |_, parts, _, _| parts.size }), 16)
          placed = groups.map do |name, parts, prot, flags|
            start = name == "__TEXT" ? BASE : at
            file_end = (parts - [:bss]).inject(at) { |a, part| place(part, a) }
            vm_end = parts.include?(:bss) ? place(:bss, file_end) : file_end
            filesize = Patch.align(file_end - start, PAGE)
            at = start + [Patch.align(vm_end - start, PAGE), filesize].max
            [name, parts, prot, flags, start, filesize, at - start]
          end
          # A part of a segment not written is empty, and has an address all
          # the same.
          (PLAIN.flat_map { |_, parts, _, _| parts } - placed.flat_map { |_, parts, *| parts }).each { |part| @top.place(part, at) }
          @top.addresses!
          @segments = placed.map do |name, parts, prot, flags, start, filesize, vmsize|
            s = segment(name, start, filesize, start - BASE, prot, flags, top_sections(parts),
                        [[top_bytes(parts - [:bss], start, filesize), nil, []]])
            s.vmsize = vmsize
            s
          end
          @header = @segments.first.pieces.first[0]
          @late = {}
          @ordinals = placed.flat_map { |_, parts, *| parts }.each_with_index.to_h { |part, n| [part, n + 1] }
        end

        # Places the program's `part` at the first address at or after `at`
        # its alignment allows, and answers where it ends.
        def place(part, at)
          at = Patch.align(at, 1 << @top.align(part))
          @top.place(part, at)
          at + @top.size(part)
        end

        def after(segment) = segment.fileoff + segment.filesize

        def segment(name, vm, filesize, fileoff, prot, flags, sections, pieces)
          Segment.new(name: name, vm: vm, vmsize: filesize, fileoff: fileoff, filesize: filesize, prot: prot,
                      flags: flags, sections: sections, pieces: pieces)
        end

        def base_sections(parts)
          parts.map do |part|
            name, flags = SECTIONS.fetch(part)
            vm, size, align = @base.parts.fetch(part)
            Section.new(name, vm, size, align, flags)
          end
        end

        def top_sections(parts)
          parts.map do |part|
            name, flags = SECTIONS.fetch(part)
            Section.new(name, @top.at(part), @top.size(part), @top.align(part), flags)
          end
        end

        # The program's `parts`, relocated, in `size` bytes from `start`.
        # The parts are in address order, so each is appended.
        def top_bytes(parts, start, size)
          out = parts.inject(+"".b) do |bytes, part|
            pad(bytes, @top.at(part) - start)
            bytes << @top.bytes(part)
          end
          pad(out, size)
          out
        end

        # --- fixups --------------------------------------------------------

        # The slots dyld writes: each of the base's externals, a rebase to
        # the program's definition or a bind; and every slot of the
        # program's own, threaded page by page in its segment.
        def fill
          @base.late.each do |slot|
            bytes, _, dirty = @late.fetch(slot.segment).pieces.first
            name = "_#{slot.name}"
            word = if @top.defines?(name)
                     Chains.rebase(@top.global(name) + slot.addend - BASE, slot.next)
                   else
                     bound(slot.name, slot.addend, slot.next)
                   end
            Chains.put(bytes, slot.offset, word)
            dirty << (slot.offset / HASH_PAGE)
          end
          # By index: a segment's hash would hash its bytes.
          own = @segments.select { |s| s.pieces.first[1].nil? && (s.prot & WRITE) != 0 }
          @top.fixups.group_by { |slot, *| own.index { |s| slot >= s.vm && slot < s.vm + s.filesize } }.each do |n, rows|
            raise Refused, "a fixup outside the data" unless n

            s = own[n]
            s.starts, nexts = Chains.thread(rows.map(&:first), s.vm, s.filesize)
            bytes = s.pieces.first[0]
            rows.each do |slot, kind, target, addend|
              word = kind == :rebase ? Chains.rebase(target - BASE, nexts[slot]) : bound(target, addend, nexts[slot])
              Chains.put(bytes, slot - s.vm, word)
            end
          end
        end

        def bound(name, addend, nxt)
          raise Refused, "an addend to #{name}, an import" unless addend.zero?

          Chains.bind(@ordinal.fetch(name), nxt)
        end

        # The `LC_DYLD_CHAINED_FIXUPS` blob: a header, one starts table a
        # segment, the imports, and the names they go by.
        def chained_fixups
          names = +"".b
          imports = @imports.map do |name|
            at = names.bytesize
            names << "_#{name}\0".b
            1 | (at << 9)
          end
          order = [nil, *@segments, nil]
          table = +"".b
          offsets = order.map do |s|
            next 0 unless s&.starts

            here = 4 + (order.size * 4) + table.bytesize
            # size, page_size, pointer_format, segment_offset,
            # max_valid_pointer, page_count: twenty-two bytes before the
            # array of page starts.
            table << [22 + (s.starts.size * 2), PAGE, PTR_64_OFFSET].pack("L<S<2")
            table << [s.vm - BASE].pack("Q<") << [0, s.starts.size].pack("L<S<") << s.starts.pack("S<*")
            table << ("\0".b * (-table.bytesize % 4))
            here
          end
          starts = [order.size].pack("L<") + offsets.pack("L<*") + table
          head = 28
          imports_at = head + starts.bytesize
          names_at = imports_at + (imports.size * 4)
          [0, head, imports_at, names_at, imports.size, IMPORT_FORMAT, 0].pack("L<7") + starts + imports.pack("L<*") + names
        end

        # --- __LINKEDIT ----------------------------------------------------

        # The fixups, the exports, the symbol table, and the names:
        # everything the loader reads and nothing the program runs. The
        # signature goes after it, and its size is fixed by where it starts.
        def linkedit
          @link_at = after(@segments.last)
          @link_vm = Patch.align(@segments.map { |s| s.vm + s.vmsize }.max, PAGE)
          fixups = chained_fixups
          trie = exports_trie
          words, strings, names = @top.symbols(@ordinals, @base.strings.bytesize)
          symbols = merged_symbols(words, names)
          strings = @base.strings + strings
          strings = "\0".b if strings.empty?
          strings += "\0".b * (-strings.bytesize % 8)
          @fixups_at = @link_at
          @fixups_size = fixups.bytesize
          @trie_at = Patch.align(@fixups_at + @fixups_size, 8)
          @trie_size = trie.bytesize
          @symoff = Patch.align(@trie_at + @trie_size, 8)
          @nsyms = symbols.bytesize / 16
          @stroff = @symoff + symbols.bytesize
          @strsize = strings.bytesize
          @sig_at = Patch.align(@stroff + @strsize, 16)
          @link_size = (@sig_at + signature_size) - @link_at

          out = +"".b
          out << fixups
          pad(out, @trie_at - @link_at)
          out << trie
          pad(out, @symoff - @link_at)
          out << symbols << strings
          pad(out, @sig_at - @link_at)
          @linkedit = out
        end

        # The program's symbol table entries merged into the base's, both
        # sorted by name (`Block#symbols`), so the image's whole table is:
        # the runtime finds any global in it by a binary search
        # (rt/kernel/os/darwin/jit.rb, `zr_os_symbol`). The base's names
        # are the table's order, and a program's name never equals one of
        # them (`write` refuses that first).
        def merged_symbols(words, names)
          out = +"".b
          at = 0
          names.each_with_index do |name, n|
            i = @base.names.bsearch_index { |candidate| candidate >= name } || @base.names.size
            out << @base.symbols.byteslice(at * 16, (i - at) * 16) if i > at
            out << words[n * 2, 2].pack("Q<2")
            at = i
          end
          out << @base.symbols.byteslice(at * 16, @base.symbols.bytesize - (at * 16))
        end

        # The exports trie: the image's own header at offset zero, which is
        # all `-no_exported_symbols` leaves behind; every other name is
        # found in the symbol table. Each node is its terminal (flags and
        # address, if a name ends there) and its edges, each an edge's
        # bytes and the offset of the node it leads to. An offset's size
        # depends on where the nodes land, so the layout runs until no
        # offset moves.
        def exports_trie
          entries = [["__mh_execute_header", 0]]
          nodes = []
          trie_node(entries, 0, entries.size, 0, nodes)
          # Each node's size less its offsets, which is all that moves.
          fixed = nodes.map do |address, edges|
            terminal = address ? 1 + uleb_size(address) : 0
            uleb_size(terminal) + terminal + 1 + edges.sum { |edge, _| edge.bytesize + 1 }
          end
          offsets = Array.new(nodes.size, 0)
          loop do
            at = 0
            moved = false
            nodes.each_with_index do |(_, edges), n|
              moved = true unless offsets[n] == at
              offsets[n] = at
              at += fixed[n]
              edges.each { |_, child| at += uleb_size(offsets[child]) }
            end
            break unless moved
          end
          out = +"".b
          nodes.each { |address, edges| trie_bytes(out, address, edges, offsets) }
          out << ("\0".b * (-out.bytesize % 8))
        end

        # The node for `entries[lo...hi]`, which share their first `depth`
        # bytes, added to `nodes` before the nodes under it: `[address or
        # nil, [[edge bytes, node index], ...]]`. The entries are sorted, so
        # a run of them that shares a next byte shares as much as its first
        # and last do.
        def trie_node(entries, lo, hi, depth, nodes)
          node = [nil, []]
          nodes << node
          if entries[lo][0].bytesize == depth
            node[0] = entries[lo][1]
            lo += 1
          end
          while lo < hi
            first = entries[lo][0]
            byte = first.getbyte(depth)
            run = lo + 1
            run += 1 while run < hi && entries[run][0].getbyte(depth) == byte
            last = entries[run - 1][0]
            len = depth + 1
            len += 1 while len < first.bytesize && len < last.bytesize && first.getbyte(len) == last.getbyte(len)
            node[1] << [first.byteslice(depth, len - depth), nodes.size]
            trie_node(entries, lo, run, len, nodes)
            lo = run
          end
          node
        end

        # One node onto `out`. A terminal is two ULEB128s, flags (none) and
        # the address, and its size fits in one byte.
        def trie_bytes(out, address, edges, offsets)
          if address
            out << (1 + uleb_size(address)) << 0
            uleb(out, address)
          else
            out << 0
          end
          out << edges.size
          edges.each do |edge, n|
            out << edge << 0
            uleb(out, offsets[n])
          end
        end

        def uleb_size(n) = n.zero? ? 1 : (n.bit_length + 6) / 7

        def uleb(out, n)
          while n >= 0x80
            out << ((n & 0x7F) | 0x80)
            n >>= 7
          end
          out << n
        end

        # --- load commands -------------------------------------------------

        # How long the load commands are with `segments` segments of
        # `sections` sections besides `__PAGEZERO` and `__LINKEDIT`: every
        # other command is the same size in every image.
        def command_size(segments, sections)
          others = [16, 16, 24, 80, 32, 24, 24, 24, 56, 16].sum
          (72 * (segments + 2)) + (80 * sections) + others
        end

        # The header and the load commands, at the start of the first page.
        def header
          blob = commands
          head = [MH_MAGIC_64, CPU_TYPE_ARM64, 0, MH_EXECUTE, @ncmds, blob.bytesize, FLAGS, 0].pack("L<8") + blob
          room = @base.empty? ? @top.at(:text) - BASE : PAGE
          raise Refused, "#{head.bytesize} bytes of load commands, past the #{room} before the code" if head.bytesize > room

          @header.bytesplice(0, head.bytesize, head)
        end

        def commands
          out = []
          out << segment_command("__PAGEZERO", 0, BASE, 0, 0, 0, 0, [])
          @segments.each { |s| out << segment_command(s.name, s.vm, s.vmsize, s.fileoff, s.filesize, s.prot, s.flags, s.sections) }
          out << segment_command("__LINKEDIT", @link_vm, Patch.align(@link_size, PAGE), @link_at, @link_size, READ, 0, [])
          out << command(LC_DYLD_CHAINED_FIXUPS, [@fixups_at, @fixups_size].pack("L<2"))
          out << command(LC_DYLD_EXPORTS_TRIE, [@trie_at, @trie_size].pack("L<2"))
          out << command(LC_SYMTAB, [@symoff, @nsyms, @stroff, @strsize].pack("L<4"))
          out << command(LC_DYSYMTAB, ([0, @nsyms, @nsyms, 0, @nsyms, 0] + ([0] * 12)).pack("L<18"))
          out << command(LC_LOAD_DYLINKER, [12].pack("L<") + "#{DYLINKER}\0".b)
          out << command(LC_BUILD_VERSION, [1, MIN_MACOS, SDK, 0].pack("L<4"))
          @uuid_at = 32 + out.sum(&:bytesize) + 8
          out << command(LC_UUID, "\0".b * 16)
          out << command(LC_MAIN, [@entry_at, @stack].pack("Q<2"))
          out << command(LC_LOAD_DYLIB, [24, 0, 1 << 16, 1 << 16].pack("L<4") + "#{LIBSYSTEM}\0".b)
          out << command(LC_CODE_SIGNATURE, [@sig_at, signature_size].pack("L<2"))
          @ncmds = out.size
          out.join
        end

        # A load command, padded to the eight bytes the next one starts on.
        def command(cmd, body)
          body += "\0".b * (-(body.bytesize + 8) % 8)
          [cmd, body.bytesize + 8].pack("L<2") + body
        end

        def segment_command(name, vmaddr, vmsize, fileoff, filesize, prot, flags, sections)
          body = [name].pack("a16") + [vmaddr, vmsize, fileoff, filesize].pack("Q<4")
          body += [prot, prot, sections.size, flags].pack("L<4")
          sections.each do |section|
            offset = section.flags == S_ZEROFILL ? 0 : fileoff + (section.vm - vmaddr)
            body += [section.name, name].pack("a16a16") + [section.vm, section.size].pack("Q<2") +
                    [offset, section.align, 0, 0, section.flags, 0, 0, 0].pack("L<8")
          end
          command(LC_SEGMENT_64, body)
        end

        # --- the stamps ----------------------------------------------------

        # The hash of every page before the signature. A base's pages keep
        # the hashes they were kept with, less the pages its external slots
        # were written into.
        def page_hashes
          hashes = +"".b
          @segments.each do |s|
            s.pieces.each do |bytes, kept, dirty|
              if kept
                pages = kept.dup
                dirty.uniq.each do |n|
                  pages.bytesplice(n * 32, 32, Digest::SHA256.digest(bytes.byteslice(n * HASH_PAGE, HASH_PAGE)))
                end
                hashes << pages
              else
                hashes << Prelink.page_hashes(bytes)
              end
            end
          end
          hashes << Prelink.page_hashes(@linkedit)
        end

        # The UUID is the hash of every page's hash, so two links of the
        # same program agree; `ld` gives every link a fresh one, which is
        # why `Obj::MachO::Stamps` blanks it. The signature then hashes the
        # header's page again, now that the UUID is in it.
        #
        # `CSMAGIC_EMBEDDED_SIGNATURE` over one ad-hoc `CodeDirectory`, all of
        # it big-endian.
        def signature
          hashes = page_hashes
          @header.bytesplice(@uuid_at, 16, Digest::SHA256.digest(hashes)[0, 16])
          hashes.bytesplice(0, 32, Digest::SHA256.digest(@header.byteslice(0, HASH_PAGE)))
          ident = "#{File.basename(@out)}\0".b
          cd = [0xFADE_0C02, 88 + ident.bytesize + hashes.bytesize, 0x20400, 0x2,
                88 + ident.bytesize, 88, 0, hashes.bytesize / 32, @sig_at].pack("L>9")
          cd += [32, 2, 0, 12].pack("C4") + ([0] * 4).pack("L>4")
          cd += [0, 0, @segments.first.filesize, 1].pack("Q>4") + ident + hashes
          [0xFADE_0CC0, 20 + cd.bytesize, 1, 0, 20].pack("L>5") + cd
        end

        def signature_size
          slots = (@sig_at + HASH_PAGE - 1) / HASH_PAGE
          20 + 88 + File.basename(@out).bytesize + 1 + (slots * 32)
        end

        def pad(bytes, to)
          bytes << ("\0".b * (to - bytes.bytesize)) if to > bytes.bytesize
        end
      end
    end
  end
end
