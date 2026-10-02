# frozen_string_literal: true

require "digest/sha2"

require_relative "block"
require_relative "prelink"
require_relative "libsystem"
require_relative "skeleton"
require_relative "../../bytes"
require_relative "../../timing"
require_relative "../../target"

module Zr
  module Obj
    module MachO
      # The link step, in Ruby. It links a program's unit against a
      # `Prelink` into a complete, signed `MH_EXECUTE`. All imports of the
      # program must come from libSystem.
      #
      # With a base (the runtime's objects, linked once), the base keeps its
      # link addresses. The program's parts go in their own segments:
      # `__PROGRAM` after `__TEXT`, and `__DATA_PROGRAM` after `__DATA`.
      # This relocates only the program and writes only the base's external
      # slots again; the other base pages keep their stored hashes. Without
      # a base, the unit is the full image, in `__TEXT`, `__DATA_CONST` and
      # `__DATA`.
      #
      # This adds the Mach-O container, chained fixups (so dyld can rebase
      # and bind the position-independent image), a symbol table sorted by
      # name, and the ad-hoc code signature that Apple Silicon requires. A
      # program's JIT searches the sorted table in place for runtime
      # functions (`zr_os_symbol`). An exports trie for about 330,000 names
      # is 6 MB and adds one second to each link.
      #
      # It does not strip: the dispatch tables reach almost all of the
      # runtime, and `ld -dead_strip` removed less than 1%.
      #
      # It refuses a symbol that no input and no libSystem entry defines,
      # because dyld cannot find it. The message gives the symbol.
      class Executable
        PAGE = Prelink::PAGE
        HASH_PAGE = Prelink::HASH_PAGE
        BASE = Prelink::BASE
        # The main stack size. Ruby frames are native frames on this stack.
        # `ld` writes this value from `-stack_size`. This linker writes the
        # same value, so the stack size is the same with both linkers.
        STACK = 0x400_0000
        # The oldest macOS that a binary loads on. The SDK version is the
        # same value, because this linker reads no SDK. The target holds it.
        MIN_MACOS = Target::AARCH64_DARWIN.min_os_parts.then { |x, y, z| (x << 16) | (y << 8) | z }
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

        # One 8-byte pointer for each slot, chained page by page. An
        # ordinary arm64 image needs only this chained format.
        PTR_64_OFFSET = 6
        IMPORT_FORMAT = 1

        # The bytes of the load commands that are the same in every image.
        OTHER_COMMANDS = [16, 16, 24, 80, 32, 24, 24, 24, 56, 16].sum

        # The section name and flags for each part.
        SECTIONS ={ text: ["__text", CODE], stubs: ["__stubs", CODE], const: ["__const", S_REGULAR],
                     got: ["__got", S_REGULAR], dconst: ["__const", S_REGULAR], data: ["__data", S_REGULAR],
                     bss: ["__bss", S_ZEROFILL] }.freeze
        # The image sections of a program's parts when there is a base: the
        # `__PROGRAM` sections after the three `__TEXT` sections, and the
        # `__DATA_PROGRAM` sections after the `__DATA` sections.
        TOP_ORDINALS = { text: 4, stubs: 5, const: 6, got: 11, dconst: 12, data: 13, bss: 14 }.freeze
        # The segments of an image without a base, and the parts in each.
        PLAIN = [["__TEXT", %i[text stubs const], READ | EXEC, 0],
                 ["__DATA_CONST", %i[got dconst], READ | WRITE, SG_READ_ONLY],
                 ["__DATA", %i[data bss], READ | WRITE, 0]].freeze

        # A segment of the image. `pieces` are its file bytes, in order,
        # each `[bytes, hashes, dirty pages]`. `hashes` are the page hashes
        # stored with a base, or nil for bytes that this linker makes.
        # @rbs skip -- typed in sig/zr/obj/macho/executable.rbs
        Segment = Struct.new(:name, :vm, :vmsize, :fileoff, :filesize, :prot, :flags, :sections, :pieces, :starts,
                             keyword_init: true)
        # A section: its name, address, size, alignment and flags.
        # @rbs skip -- typed in sig/zr/obj/macho/executable.rbs
        Section = Data.define(:name, :vm, :size, :align, :flags)

        Refused = MachO::Refused

        # Writes `out` from `unit`, linked against `prelink` or against the
        # object files `objects` (their bytes), and returns nil. When it
        # cannot link, it writes nothing and returns the reason.
        # `skeleton` is a file of the base's `Skeleton.bytes`. When the
        # system allows, this clones it and writes into the clone.
        def self.write(unit, out, objects: [], prelink: nil, stack: STACK, entry: "main", skeleton: nil)
          prelink ||= Prelink.build(objects)
          Timing.phase("link: program read") { new(unit, prelink, out, stack: stack, entry: entry, skeleton: skeleton) }.write
        rescue Refused => e
          e.message
        end

        # Checks whether libSystem defines `name`. It reads the committed
        # list, not this host's libSystem, so the result is the same on
        # every host. The link refuses a name that is not in the list.
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
          twice = defined_twice
          raise Refused, "#{twice.delete_prefix("_")} is defined twice" if twice

          @imports = (@base.externals.reject { |name| @top.defines?("_#{name}") } + @top.externals).uniq.sort
          outside = @imports.reject { |name| self.class.libsystem?(name) }
          raise Refused, "#{outside.first} is not libSystem's" unless outside.empty?

          @ordinal = @imports.each_with_index.to_h
          Timing.phase("link: laid out") { @base.empty? ? plain : beside_base }
          entry = @top.entry(@entry) || @base.global("_#{@entry}") or raise Refused, "nothing named #{@entry} to enter at"
          @entry_at = entry - BASE
          Timing.phase("link: filled") { fill }
          Timing.phase("link: linkedit") { linkedit }
          header
          signed = Timing.phase("link: signed") { signature }
          if @base.empty?
            File.open(@out, "wb") { |file| write_after(file, 0, signed) }
            File.chmod(0o755, @out)
          else
            # The first segment is the header page and the base's text.
            # The file at `out`, or the skeleton, already contains it.
            Timing.phase("link: written") { Skeleton.write_over(@out, @skeleton, @base.blobs.fetch(:text)) do |file, kept|
              file.write(@header)
              kept ? file.seek(@segments.first.filesize) : file.write(@base.blobs.fetch(:text))
              write_after(file, 1, signed)
            end }
          end
          nil
        end

        # For each of the sorted `names`, the index of the first name in
        # `sorted` that is not less than it (`sorted.size` for none). Each
        # search starts where the last one ended: it doubles its step until
        # it passes the name, then halves the window. With some thousand
        # program names among the runtime's 250,000, a search reads a few
        # names, where a binary search from the start reads 18 through a
        # block.
        def self.insertion_points(sorted, names)
          size = sorted.size
          at = 0
          names.map do |name|
            reach = 0
            reach += 1 while at + (1 << reach) - 1 < size && sorted[at + (1 << reach) - 1] < name
            left = reach.zero? ? at : at + (1 << (reach - 1))
            right = [at + (1 << reach) - 1, size].min
            while left < right
              mid = (left + right) >> 1
              if sorted[mid] < name
                left = mid + 1
              else
                right = mid
              end
            end
            at = left
          end
        end

        private

        # The first program global (in the order of the program) that the
        # base defines too, or nil. The sorted names walk the base's sorted
        # names once (`insertion_points`): a binary search for each name
        # took 8% of a `zr run` after an edit to a program that evals.
        def defined_twice
          names = @top.names.sort
          base = @base.names
          points = Executable.insertion_points(base, names)
          both = names.each_index.filter_map { |n| names[n] if base[points[n]] == names[n] }
          return nil if both.empty?

          both = both.to_set
          @top.names.find { |name| both.include?(name) }
        end

        # Writes the segments from index `first`, the linkedit and the signature.
        def write_after(file, first, signed)
          @segments.drop(first).each { |s| s.pieces.each { |bytes, _, _| file.write(bytes) } }
          file.write(@linkedit)
          file.write(signed)
        end

        # --- layout --------------------------------------------------------

        # Layout with a base: the base's segments at their link addresses,
        # the program's code after `__TEXT` and its data after `__DATA`.
        # The file contains the segments in address order.
        def beside_base
          b = @base
          code_at = BASE + b.text_size
          code_size = Bytes.align(%i[text stubs const].inject(code_at) { |at, part| place(part, at) } - code_at, PAGE)
          raise Refused, "a program with no code" if code_size.zero?
          raise Refused, "#{code_size} bytes of code, past the room beside the runtime" if code_size > Prelink::RESERVE

          data_at = b.data_end
          file_end = %i[got dconst data].inject(data_at) { |at, part| place(part, at) }
          data_filesize = Bytes.align(file_end - data_at, PAGE)
          data_vmsize = Bytes.align(place(:bss, file_end) - data_at, PAGE)
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

        # Layout without a base: the unit is the image. The header and the
        # code share the first page. Thus the code start depends on the
        # size of the load commands, which depends only on the number of
        # segments and sections. This does not write an empty segment,
        # because an image with a zero-length segment does not load.
        def plain
          groups = PLAIN.select { |name, parts, _, _| name == "__TEXT" || parts.any? { |part| @top.size(part).positive? } }
          at = BASE + Bytes.align(32 + command_size(groups.size, groups.sum { |_, parts, _, _| parts.size }), 16)
          placed = groups.map do |name, parts, prot, flags|
            start = name == "__TEXT" ? BASE : at
            file_end = (parts - [:bss]).inject(at) { |a, part| place(part, a) }
            vm_end = parts.include?(:bss) ? place(:bss, file_end) : file_end
            filesize = Bytes.align(file_end - start, PAGE)
            at = start + [Bytes.align(vm_end - start, PAGE), filesize].max
            [name, parts, prot, flags, start, filesize, at - start]
          end
          # A part of a segment that is not written is empty, but it still
          # has an address.
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

        # Places the program's `part` at the first aligned address at or
        # after `at`. Returns the end address.
        def place(part, at)
          at = Bytes.align(at, 1 << @top.align(part))
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

        # Returns the program's `parts`, relocated, in `size` bytes from
        # `start`. The parts are in address order, so this appends each one.
        def top_bytes(parts, start, size)
          out = parts.each_with_object(+"".b) do |part, bytes|
            Bytes.pad(bytes, @top.at(part) - start)
            bytes << @top.bytes(part)
          end
          Bytes.pad(out, size)
          out
        end

        # --- fixups --------------------------------------------------------

        # Fills the slots that dyld writes. Each external of the base
        # becomes a rebase to the program's definition, or a bind. Each slot
        # of the program is chained page by page in its segment.
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
          # Group by index, not by segment: a segment's hash hashes all its bytes.
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

        # The `LC_DYLD_CHAINED_FIXUPS` blob: a header, one starts table for
        # each segment, the imports, and their names.
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
            # max_valid_pointer, page_count: 22 bytes before the array of
            # page starts.
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

        # The fixups, the exports, the symbol table and the names: data for
        # the loader, not code for the program. The signature comes after
        # it; the start of the signature sets its size.
        def linkedit
          @link_at = after(@segments.last)
          @link_vm = Bytes.align(@segments.map { |s| s.vm + s.vmsize }.max, PAGE)
          fixups = chained_fixups
          trie = exports_trie
          words, strings, names = @top.symbols(@ordinals, @base.strings.bytesize)
          symbols = merged_symbols(words, names)
          strings = @base.strings + strings
          strings = "\0".b if strings.empty?
          strings += "\0".b * (-strings.bytesize % 8)
          @fixups_at = @link_at
          @fixups_size = fixups.bytesize
          @trie_at = Bytes.align(@fixups_at + @fixups_size, 8)
          @trie_size = trie.bytesize
          @symoff = Bytes.align(@trie_at + @trie_size, 8)
          @nsyms = symbols.bytesize / 16
          @stroff = @symoff + symbols.bytesize
          @strsize = strings.bytesize
          @sig_at = Bytes.align(@stroff + @strsize, 16)
          @link_size = (@sig_at + signature_size) - @link_at

          out = +"".b
          out << fixups
          Bytes.pad(out, @trie_at - @link_at)
          out << trie
          Bytes.pad(out, @symoff - @link_at)
          out << symbols << strings
          Bytes.pad(out, @sig_at - @link_at)
          @linkedit = out
        end

        # Merges the program's symbol table entries into the base's. Both
        # are sorted by name (`Block#symbols`), so the merged table is also
        # sorted. The runtime finds a global in it with a binary search
        # (lib/zr/runtime/kernel/os/darwin/jit.rb, `zr_os_symbol`). The base's
        # names give the order. A program name never equals a base name,
        # because `write` refuses that first.
        def merged_symbols(words, names)
          out = +"".b
          at = 0
          points = Executable.insertion_points(@base.names, names)
          names.each_index do |n|
            i = points[n]
            out << @base.symbols.byteslice(at * 16, (i - at) * 16) if i > at
            out << words[n * 2, 2].pack("Q<2")
            at = i
          end
          out << @base.symbols.byteslice(at * 16, @base.symbols.bytesize - (at * 16))
        end

        # The exports trie. It contains only the image header at offset
        # zero, as `-no_exported_symbols` gives; all other names are in the
        # symbol table. Each node has a terminal (flags and address, if a
        # name ends there) and its edges (the edge bytes and the offset of
        # the child node). The size of an offset depends on the node
        # positions, so the layout repeats until no offset changes.
        def exports_trie
          entries = [["__mh_execute_header", 0]]
          nodes = []
          trie_node(entries, 0, entries.size, 0, nodes)
          # Each node's size without its offsets. Only the offsets change.
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

        # Adds the node for `entries[lo...hi]` to `nodes`, before its child
        # nodes. These entries share their first `depth` bytes. A node is
        # `[address or nil, [[edge bytes, node index], ...]]`. The entries
        # are sorted, so a run with the same next byte has the same common
        # prefix as its first and last entries.
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

        # Appends one node to `out`. A terminal is two ULEB128s, the flags
        # (none) and the address, and its size fits in one byte.
        def trie_bytes(out, address, edges, offsets)
          if address
            out << (1 + uleb_size(address)) << 0
            out << Bytes.uleb(address)
          else
            out << 0
          end
          out << edges.size
          edges.each do |edge, n|
            out << edge << 0
            out << Bytes.uleb(offsets[n])
          end
        end

        def uleb_size(n) = Bytes.uleb_size(n)

        # --- load commands -------------------------------------------------

        # The size of the load commands for `segments` segments with
        # `sections` sections, in addition to `__PAGEZERO` and
        # `__LINKEDIT`. All other commands have the same size in every image.
        def command_size(segments, sections)
          (72 * (segments + 2)) + (80 * sections) + OTHER_COMMANDS
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
          out << segment_command("__LINKEDIT", @link_vm, Bytes.align(@link_size, PAGE), @link_at, @link_size, READ, 0, [])
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

        # A load command, padded so that the next one starts on 8 bytes.
        def command(cmd, body)
          body += "\0".b * (-(body.bytesize + 8) % 8)
          [cmd, body.bytesize + 8].pack("L<2") + body
        end

        def segment_command(name, vmaddr, vmsize, fileoff, filesize, prot, flags, sections)
          body = [name].pack("a16") + [vmaddr, vmsize, fileoff, filesize].pack("Q<4")
          body << [prot, prot, sections.size, flags].pack("L<4")
          sections.each do |section|
            offset = section.flags == S_ZEROFILL ? 0 : fileoff + (section.vm - vmaddr)
            body << [section.name, name].pack("a16a16") << [section.vm, section.size].pack("Q<2") <<
              [offset, section.align, 0, 0, section.flags, 0, 0, 0].pack("L<8")
          end
          command(LC_SEGMENT_64, body)
        end

        # --- UUID and signature --------------------------------------------

        # The hash of every page before the signature. A base's pages use
        # their stored hashes, except the pages where this wrote external
        # slots.
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

        # The UUID is the hash of all page hashes, so two links of the same
        # program give the same UUID. (`ld` gives every link a new UUID, so
        # `Obj::MachO::Stamps` ignores it.) The signature then hashes the
        # header page again, because the UUID is now in it.
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
      end
    end
  end
end
