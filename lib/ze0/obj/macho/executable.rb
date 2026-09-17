# frozen_string_literal: true

require "digest"

require_relative "../model"
require_relative "../patch"
require_relative "../../backend/aarch64/relocs"
require_relative "object_file"
require_relative "libsystem"

module Ze0
  module Obj
    module MachO
      # Objects to a complete, signed `MH_EXECUTE` that runs: the link
      # step, in Ruby, for a program whose every import is libSystem's.
      #
      # It links the objects `ObjectFile` writes -- a program's own, the
      # runtime's and the eval road's, all read back with
      # `ObjectFile.read` -- and nothing else. Each input section goes
      # into the output section of its kind, in input order. A symbol
      # one object leaves undefined is another object's global, or an
      # import from libSystem. Each import gets a stub and a GOT slot,
      # and every relocation is applied here. What is added is the
      # Mach-O container, chained fixups so a position-independent image
      # can be rebased and bound, an exports trie for a program whose
      # JIT finds symbols by name, and the ad-hoc code signature Apple
      # Silicon will not run a binary without.
      #
      # It does not strip: nearly all of the runtime is reachable from its
      # dispatch tables, and `ld -dead_strip` removed less than one percent.
      #
      # It refuses rather than guesses. A symbol no object defines and
      # libSystem does not define either would not be found by dyld, and
      # this says which symbol it is.
      class Executable
        PAGE = 0x4000
        # Where the image goes, above the four unmapped gigabytes that make
        # a null dereference a fault.
        BASE = 0x1_0000_0000
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

        # <mach-o/nlist.h>: a symbol's type byte.
        N_STAB = 0xE0
        N_TYPE = 0x0E
        N_EXT = 0x01
        N_UNDF = 0x0
        N_SECT = 0xE

        DYLINKER = "/usr/lib/dyld"
        LIBSYSTEM = "/usr/lib/libSystem.B.dylib"

        # One 8-byte pointer a slot, threaded page by page: the only chained
        # format an ordinary arm64 image needs.
        PTR_64_OFFSET = 6
        IMPORT_FORMAT = 1
        START_NONE = 0xFFFF
        STRIDE = 4
        # `adrp x16, got@PAGE; ldr x16, [x16, got@PAGEOFF]; br x16`
        STUB = 12

        # The relocation kind of each arm64 relocation type an object holds.
        KINDS = ObjectFile::RELOC.to_h { |kind, (type, _, _)| [type, kind] }.freeze
        ABS64 = ObjectFile::RELOC.fetch(:abs64).first
        BRANCH26 = ObjectFile::RELOC.fetch(:branch26).first
        GOT = ObjectFile::RELOC.values_at(:got_page21, :got_pageoff12).map(&:first).freeze

        # A section of the image. `chunks` are the input sections in it, each
        # `[input, section index, offset]`; `__stubs` and `__got` have none.
        Part = Struct.new(:name, :segment, :flags, :from, :chunks, :size, :align, :at, :fixups, keyword_init: true)

        # These objects are not ones this links, and here is why.
        class Refused < StandardError; end

        # Writes `out` from `unit` and the object files `objects` (their
        # bytes), and answers nil; or answers why it cannot link them and
        # writes nothing. `exports` puts every global in the exports trie,
        # where `dlsym` finds it.
        def self.write(unit, out, objects: [], exports: false, stack: STACK, entry: "main")
          new([ObjectFile.write(unit), *objects], out, exports: exports, stack: stack, entry: entry).write
        rescue Refused => e
          e.message
        end

        # Whether libSystem defines `name`. The answer comes from the
        # committed list, not from this host's libSystem, so it is the same
        # on every host; a name missing from the list is refused.
        def self.libsystem?(name) = LIBSYSTEM_NAMES.include?(name)

        def initialize(objects, out, exports: false, stack: STACK, entry: "main")
          @inputs = objects.map { |bytes| ObjectFile.read(bytes) }
          @out = out
          @exports = exports
          @stack = stack
          @entry = entry
          @fixups = []
        end

        def write
          resolve
          outside = @imports.reject { |name| self.class.libsystem?(name) }
          raise Refused, "#{outside.first} is not libSystem's" unless outside.empty?

          @entry_symbol = entry_symbol or raise Refused, "nothing named #{@entry} to enter at"
          got_slots
          lay_out
          File.binwrite(@out, stamped(assemble))
          File.chmod(0o755, @out)
          nil
        end

        private

        # --- symbols -------------------------------------------------------

        # Every global each input defines, then what each undefined symbol
        # is: `[input, symbol]` for another input's global, or the name of
        # an import. `@links[input]` holds the answer for each undefined
        # symbol; a defined symbol is its own.
        def resolve
          @globals = {}
          undefined = []
          @inputs.each_with_index do |o, i|
            o.count.times do |s|
              type = o.type(s)
              next unless (type & N_STAB).zero? && (type & N_EXT) != 0

              if (type & N_TYPE) == N_SECT
                name = o.name(s)
                raise Refused, "#{name.delete_prefix("_")} is defined twice" if @globals.key?(name)

                @globals[name] = [i, s]
              elsif (type & N_TYPE) == N_UNDF
                undefined << [i, s]
              end
            end
          end
          imports = {}
          @links = Array.new(@inputs.size) { {} }
          undefined.each do |i, s|
            name = @inputs[i].name(s)
            @links[i][s] = @globals[name] || (imports[name] = name.delete_prefix("_"))
          end
          @imports = imports.values.sort
          @import_index = @imports.each_with_index.to_h
        end

        # `[input, symbol]` of the entry: a global, else a local of that name.
        def entry_symbol
          name = "_#{@entry}"
          return @globals[name] if @globals.key?(name)

          @inputs.each_with_index do |o, i|
            o.count.times do |s|
              return [i, s] if (o.type(s) & (N_STAB | N_TYPE)) == N_SECT && o.name(s) == name
            end
          end
          nil
        end

        # What symbol `s` of input `i` stands for: an import's name, or the
        # `[input, symbol]` that defines it.
        def meaning(i, s) = @links[i].fetch(s) { [i, s] }

        # One GOT slot an import, then one a defined symbol some code loads
        # an address of through the GOT: dyld rebases that slot, so the code
        # loads the symbol's address, never its bytes.
        def got_slots
          @got = @imports.dup
          seen = @got.to_h { |name| [name, true] }
          @inputs.each_with_index do |o, i|
            o.sections.each do |section|
              words = section.relocs
              j = 1
              while j < words.size
                info = words[j]
                j += 2
                next unless GOT.include?(info >> 28)

                key = meaning(i, info & 0xFF_FFFF)
                next if seen[key]

                seen[key] = true
                @got << key
              end
            end
          end
        end

        # --- layout --------------------------------------------------------

        # Every section's place. A section's address is its file offset
        # above the image base, so the two never have to be reasoned about
        # apart; `__bss` is the one exception, and it has no file bytes.
        def lay_out
          @parts = [
            part("__text", "__TEXT", CODE, %w[__TEXT __text]),
            part("__stubs", "__TEXT", CODE, nil, size: @imports.size * STUB),
            part("__const", "__TEXT", S_REGULAR, %w[__TEXT __const]),
            part("__got", "__DATA_CONST", S_REGULAR, nil, size: @got.size * 8, fixups: true),
            part("__const", "__DATA_CONST", S_REGULAR, %w[__DATA __const], fixups: true),
            part("__data", "__DATA", S_REGULAR, %w[__DATA __data], fixups: true),
            part("__bss", "__DATA", S_ZEROFILL, %w[__DATA __bss])
          ]
          stray = @inputs.flat_map(&:sections).find { |s| s.size.positive? && @parts.none? { |p| p.from == [s.segment, s.name] } }
          raise Refused, "a #{stray.segment},#{stray.name} section, which no part of the image holds" if stray

          # A section with nothing in it is not written, and a segment whose
          # sections are all empty is not a segment: an image with a
          # zero-length one does not load.
          @parts.reject! { |p| p.size.zero? }
          @segments = ["__PAGEZERO", *@parts.map(&:segment).uniq, "__LINKEDIT"]
          head = Patch.align(32 + commands.bytesize, 16)
          at = head
          @parts.each_with_index do |p, i|
            at = Patch.align(at, PAGE) if i.positive? && p.segment != @parts[i - 1].segment
            p.at = Patch.align(at, 1 << p.align)
            at = p.at + p.size
          end
          @text_size = Patch.align(segment_end("__TEXT"), PAGE)
          last = @parts.last.segment
          bss = part_named("__bss", "__DATA")&.size.to_i
          @link_at = Patch.align(segment_end(last) - bss, PAGE)
          @link_vm = Patch.align(BASE + segment_end(last), PAGE)
          addresses
        end

        # A section of the image. `from` names the input sections that land
        # in it, and a section with none -- `__stubs`, `__got` -- is given
        # its size instead. Each input's section starts at its own
        # alignment, and the whole section at the widest of them.
        def part(name, segment, flags, from, size: nil, fixups: false)
          chunks = nil
          align = 4
          if from
            chunks = []
            size = 0
            @inputs.each_with_index do |o, i|
              o.sections.each_with_index do |section, k|
                next unless [section.segment, section.name] == from

                align = [align, section.align].max
                size = Patch.align(size, 1 << section.align) if section.size.positive?
                chunks << [i, k, size]
                size += section.size
              end
            end
          end
          Part.new(name: name, segment: segment, flags: flags, from: from, chunks: chunks, size: size, align: align, fixups: fixups)
        end

        def part_named(name, segment) = @parts.find { |p| p.name == name && p.segment == segment }
        def in_segment(name) = @parts.select { |p| p.segment == name }
        def segment_start(name) = in_segment(name).first.at.to_i
        def segment_end(name) = in_segment(name).then { |ps| ps.last.at.to_i + ps.last.size }

        # Every symbol's address: an input section's symbols move with it,
        # and an undefined one is where its definition went.
        def addresses
          # Per input, each section's address in the image and the ordinal
          # of the image section that holds it.
          @placed = @inputs.map { |o| Array.new(o.sections.size) }
          @ordinal = @inputs.map { |o| Array.new(o.sections.size) }
          @parts.each_with_index do |p, n|
            p.chunks&.each do |i, k, off|
              @placed[i][k] = BASE + p.at + off
              @ordinal[i][k] = n + 1
            end
          end
          @addr = @inputs.each_with_index.map do |o, i|
            Array.new(o.count) do |s|
              next unless (o.type(s) & (N_STAB | N_TYPE)) == N_SECT

              # A section no bytes were placed for puts its symbols at the base.
              k = o.sect(s) - 1
              (@placed[i][k] || BASE) + o.value(s) - o.sections[k].addr
            end
          end
          @links.each_with_index do |links, i|
            links.each { |s, to| @addr[i][s] = @addr[to[0]][to[1]] if to.is_a?(Array) }
          end
          # A program with no imports has neither table.
          stubs = part_named("__stubs", "__TEXT")&.at
          got = part_named("__got", "__DATA_CONST")&.at
          @stub_at = @imports.each_with_index.to_h { |n, i| [n, BASE + stubs + (i * STUB)] }
          @got_at = @got.each_with_index.to_h { |key, i| [key, BASE + got + (i * 8)] }
          @entry_at = @addr[@entry_symbol[0]][@entry_symbol[1]] - BASE
        end

        # --- bytes ---------------------------------------------------------

        # The body first, because patching it is what finds the fixups;
        # then the chains, which decide the size of __LINKEDIT; then the
        # commands, which name all of it. A fixup slot holds a chain entry
        # and not an address, so those eight bytes are written last.
        def assemble
          body = @parts.to_h { |p| [p, bytes_of(p)] }
          thread
          @linkedit = linkedit
          blob = commands
          file = +"".b
          file << [MH_MAGIC_64, CPU_TYPE_ARM64, 0, MH_EXECUTE, @ncmds, @cmdsize, FLAGS, 0].pack("L<8")
          file << blob
          @parts.each do |p|
            next if p.flags == S_ZEROFILL

            pad(file, p.at)
            file << body.fetch(p)
          end
          pad(file, @link_at)
          file << @linkedit
          @chain.each { |at, word| file[at, 8] = [word].pack("Q<") }
          file
        end

        # A section's bytes: the two tables build themselves, and every
        # other section is its inputs' bytes, relocated, with the gaps
        # between them zero. `__bss` has no bytes at all -- that is what it
        # is.
        def bytes_of(part)
          return "".b if part.flags == S_ZEROFILL
          return stub_bytes(part) if part.name == "__stubs"
          return got_bytes(part) if part.name == "__got"

          out = +"".b
          part.chunks.each do |i, k, off|
            pad(out, off)
            out << @inputs[i].sections[k].bytes
          end
          part.chunks.each { |i, k, off| relocate(part, out, off, i, @inputs[i].sections[k].relocs) }
          out
        end

        # Applies one input section's relocations to its bytes at `off` in
        # `out`. A call reaches an import through its stub and an address
        # through its GOT slot; everything else is at its own place in the
        # image. An `abs64` slot holds a chain entry rather than the
        # address, so it is recorded here and overwritten once the chains
        # are threaded; its addend is what the slot held.
        def relocate(part, out, off, i, words)
          addr = @addr[i]
          base = BASE + part.at + off
          addend = 0
          j = 0
          while j < words.size
            at = words[j]
            info = words[j + 1]
            j += 2
            type = info >> 28
            if type == ObjectFile::ARM64_RELOC_ADDEND
              addend = ((info & 0xFF_FFFF) ^ 0x80_0000) - 0x80_0000
              next
            end
            raise Refused, "a relocation that names a section, not a symbol" if info[27].zero?

            s = info & 0xFF_FFFF
            here = off + at
            place = base + at
            target = addr[s]
            if type == ABS64
              raise Refused, "an absolute relocation in #{part.segment},#{part.name}" unless part.fixups

              held = out.unpack1("q<", offset: here)
              if target
                @fixups << [part.segment, place - BASE, :rebase, target + held - BASE]
              else
                raise Refused, "an addend to #{@links[i][s]}, an import" unless held.zero?

                @fixups << [part.segment, place - BASE, :bind, @import_index.fetch(@links[i][s])]
              end
            else
              kind = KINDS[type] or raise Refused, "a relocation of type #{type}"
              if GOT.include?(type)
                target = @got_at.fetch(meaning(i, s))
              elsif type == BRANCH26
                target ||= @stub_at.fetch(@links[i][s])
              elsif target.nil?
                raise Refused, "#{@links[i][s]} has no place in the image"
              end
              word = Backend::Aarch64::Relocs.encode(kind, out.unpack1("L<", offset: here), target + addend, place)
              raise Refused, "a #{kind} to #{@inputs[i].name(s).delete_prefix("_")} is out of reach" unless word

              out.bytesplice(here, 4, [word].pack("L<"))
            end
            addend = 0
          end
        end

        # One stub an import, jumping through the GOT slot dyld binds.
        def stub_bytes(part)
          @imports.each_with_index.inject(+"".b) do |out, (name, i)|
            here = BASE + part.at + (i * STUB)
            got = @got_at.fetch(name)
            page = ((got & ~0xFFF) - (here & ~0xFFF)) >> 12
            out << [0x9000_0010 | ((page & 3) << 29) | (((page >> 2) & 0x7FFFF) << 5),
                    0xF940_0210 | (((got & 0xFFF) >> 3) << 10),
                    0xD61F_0200].pack("L<3")
          end
        end

        # A GOT slot an import, each one a bind for dyld to fill in; then
        # one a defined symbol the code reaches through the GOT, each a
        # rebase of that symbol's address.
        def got_bytes(part)
          @got.each_with_index do |key, n|
            at = part.at + (n * 8)
            @fixups << if key.is_a?(String)
                         [part.segment, at, :bind, @import_index.fetch(key)]
                       else
                         [part.segment, at, :rebase, @addr[key[0]][key[1]] - BASE]
                       end
          end
          "\0".b * (@got.size * 8)
        end

        # --- chained fixups ------------------------------------------------

        # Every slot dyld has to write, threaded into one chain a page. The
        # slot itself holds the chain entry: where the next one is, and
        # either an address to rebase or an import to bind.
        def thread
          @chain = {}
          @starts = {}
          @fixups.group_by(&:first).each do |segment, rows|
            at = segment_start(segment)
            pages = Patch.align(segment_end(segment) - at, PAGE) / PAGE
            starts = Array.new(pages, START_NONE)
            rows.map { |(_, off, kind, target)| [off, kind, target] }.sort_by(&:first)
                .group_by { |(off, _, _)| (off - at) / PAGE }.each do |page, slots|
              starts[page] = (slots.first[0] - at) % PAGE
              slots.each_with_index do |(off, kind, target), i|
                nxt = slots[i + 1] ? (slots[i + 1][0] - off) / STRIDE : 0
                @chain[off] = kind == :rebase ? rebase(target, nxt) : bind(target, nxt)
              end
            end
            @starts[segment] = starts
          end
        end

        # Where the slot points, as an offset from the image base: what the
        # loader adds the slide to.
        def rebase(target, nxt) = (target & ((1 << 36) - 1)) | (nxt << 51)

        def bind(ordinal, nxt)
          (ordinal & 0xFF_FFFF) | (nxt << 51) | (1 << 63)
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
          order = @segments
          starts = [order.size].pack("L<")
          table = +"".b
          offsets = order.map do |segment|
            rows = @starts[segment]
            next 0 unless rows

            here = 4 + (order.size * 4) + table.bytesize
            # size, page_size, pointer_format, segment_offset,
            # max_valid_pointer, page_count: twenty-two bytes before the
            # array of page starts.
            table << [22 + (rows.size * 2), PAGE, PTR_64_OFFSET].pack("L<S<2")
            table << [segment_start(segment)].pack("Q<") << [0, rows.size].pack("L<S<") << rows.pack("S<*")
            table << ("\0".b * (-table.bytesize % 4))
            here
          end
          starts += offsets.pack("L<*") + table
          head = 28
          imports_at = head + starts.bytesize
          names_at = imports_at + (imports.size * 4)
          blob = [0, head, imports_at, names_at, imports.size, IMPORT_FORMAT, 0].pack("L<7")
          blob + starts + imports.pack("L<*") + names
        end

        # --- __LINKEDIT ----------------------------------------------------

        # The fixups, the exports, the symbol table, and the names:
        # everything the loader reads and nothing the program runs. The
        # signature goes after it, and its size is fixed by where it starts.
        def linkedit
          fixups = chained_fixups
          trie = exports_trie
          @fixups_at = @link_at
          @fixups_size = fixups.bytesize
          @trie_at = Patch.align(@fixups_at + @fixups_size, 8)
          @trie_size = trie.bytesize
          @symoff = Patch.align(@trie_at + @trie_size, 8)
          symbols, strings = symbol_table
          @nsyms = symbols.bytesize / 16
          @stroff = @symoff + symbols.bytesize
          @strsize = strings.bytesize
          @sig_at = Patch.align(@stroff + @strsize, 16)
          @sig_size = signature_size
          @link_size = (@sig_at + @sig_size) - @link_at

          out = +"".b
          out << fixups
          pad(out, @trie_at - @link_at)
          out << trie
          pad(out, @symoff - @link_at)
          out << symbols << strings
          pad(out, @sig_at - @link_at)
          out
        end

        # The exports trie: the image's own header at offset zero, which is
        # all `-no_exported_symbols` leaves behind, and with `exports` every
        # global besides. Each node is its terminal (flags and address, if a
        # name ends there) and its edges, each an edge's bytes and the
        # offset of the node it leads to. An offset's size depends on where
        # the nodes land, so the layout runs until no offset moves.
        def exports_trie
          names = { "__mh_execute_header" => 0 }
          @globals.each { |name, (i, s)| names[name] = @addr[i][s] - BASE } if @exports
          entries = names.sort_by(&:first)
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

        # Every symbol an input defines, as a local symbol at its address in
        # the image: `nm` can read the binary, and the exports trie says
        # what is exported. The names are the inputs' own string tables, one
        # after another.
        def symbol_table
          strings = +"".b
          words = []
          @inputs.each_with_index do |o, i|
            base = strings.bytesize
            strings << o.strings
            o.count.times do |s|
              next unless (o.type(s) & (N_STAB | N_TYPE)) == N_SECT && @ordinal[i][o.sect(s) - 1]

              words << ((o.strx(s) + base) | (N_SECT << 32) | (@ordinal[i][o.sect(s) - 1] << 40))
              words << @addr[i][s]
            end
          end
          strings = "\0".b if strings.empty?
          [words.pack("Q<*"), strings + ("\0".b * (-strings.bytesize % 8))]
        end

        # --- load commands -------------------------------------------------

        # Built twice: once to learn how long they are, which decides where
        # the code goes, and once with the numbers that follow from that.
        # Their size depends only on how many of each there are, so the two
        # agree.
        def commands
          out = []
          out << segment("__PAGEZERO", 0, BASE, 0, 0, 0, [])
          out << segment("__TEXT", BASE, @text_size.to_i, 0, @text_size.to_i, READ | EXEC, in_segment("__TEXT"))
          out << data_segment("__DATA_CONST", READ | WRITE, SG_READ_ONLY) if in_segment("__DATA_CONST").any?
          out << data_segment("__DATA", READ | WRITE, 0) if in_segment("__DATA").any?
          out << segment("__LINKEDIT", @link_vm.to_i, Patch.align(@link_size.to_i, PAGE),
                         @link_at.to_i, @link_size.to_i, READ, [])
          out << command(LC_DYLD_CHAINED_FIXUPS, [@fixups_at.to_i, @fixups_size.to_i].pack("L<2"))
          out << command(LC_DYLD_EXPORTS_TRIE, [@trie_at.to_i, @trie_size.to_i].pack("L<2"))
          out << command(LC_SYMTAB, [@symoff.to_i, @nsyms.to_i, @stroff.to_i, @strsize.to_i].pack("L<4"))
          out << command(LC_DYSYMTAB, ([0, @nsyms.to_i, @nsyms.to_i, 0, @nsyms.to_i, 0] + ([0] * 12)).pack("L<18"))
          out << command(LC_LOAD_DYLINKER, [12].pack("L<") + name(DYLINKER))
          out << command(LC_BUILD_VERSION, [1, MIN_MACOS, SDK, 0].pack("L<4"))
          @uuid_at = 32 + out.sum(&:bytesize) + 8
          out << command(LC_UUID, "\0".b * 16)
          out << command(LC_MAIN, [@entry_at.to_i, @stack].pack("Q<2"))
          out << command(LC_LOAD_DYLIB, [24, 0, 1 << 16, 1 << 16].pack("L<4") + name(LIBSYSTEM))
          out << command(LC_CODE_SIGNATURE, [@sig_at.to_i, @sig_size.to_i].pack("L<2"))
          @ncmds = out.size
          @cmdsize = out.sum(&:bytesize)
          out.join
        end

        # A load command, padded to the eight bytes the next one starts on.
        def command(cmd, body)
          body += "\0".b * (-(body.bytesize + 8) % 8)
          [cmd, body.bytesize + 8].pack("L<2") + body
        end

        def name(path) = "#{path}\0".b

        def segment(name, vmaddr, vmsize, fileoff, filesize, prot, parts, flags: 0)
          body = [name.ljust(16, "\0")].pack("a16") + [vmaddr, vmsize, fileoff, filesize].pack("Q<4")
          body += [prot, prot, parts.size, flags].pack("L<4")
          parts.each { |p| body += section(p) }
          command(LC_SEGMENT_64, body)
        end

        # A writable segment: its virtual size covers `__bss`, which has no
        # bytes in the file, so the two sizes differ by exactly that much.
        def data_segment(name, prot, flags)
          parts = in_segment(name)
          at = parts.first.at.to_i
          zerofill = parts.select { |p| p.flags == S_ZEROFILL }.sum(&:size)
          segment(name, BASE + at, Patch.align(segment_end(name) - at, PAGE), at,
                  segment_end(name) - zerofill - at, prot, parts, flags: flags)
        end

        def section(part)
          [part.name.ljust(16, "\0"), part.segment.ljust(16, "\0")].pack("a16a16") +
            [BASE + part.at.to_i, part.size].pack("Q<2") +
            [part.flags == S_ZEROFILL ? 0 : part.at.to_i, part.align, 0, 0, part.flags, 0, 0, 0].pack("L<8")
        end

        # --- the stamps ----------------------------------------------------

        # The UUID is the image's own hash, so two links of the same program
        # agree; `ld` gives every link a fresh one, which is why
        # `Obj::MachO::Stamps` had to blank it. Then the signature, over everything
        # the UUID is already in.
        def stamped(file)
          file[@uuid_at, 16] = Digest::SHA256.digest(file)[0, 16]
          file + signature(file)
        end

        def signature_size
          slots = (@sig_at + 4095) / 4096
          20 + 88 + identifier.bytesize + 1 + (slots * 32)
        end

        def identifier = File.basename(@out)

        # `CSMAGIC_EMBEDDED_SIGNATURE` over one ad-hoc `CodeDirectory`, all
        # of it big-endian, hashing every 4 KB page of what comes before it.
        def signature(file)
          slots = (@sig_at + 4095) / 4096
          hashes = (0...slots).map { |i| Digest::SHA256.digest(file.byteslice(i * 4096, 4096)) }.join
          ident = "#{identifier}\0".b
          cd = [0xFADE_0C02, 88 + ident.bytesize + hashes.bytesize, 0x20400, 0x2,
                88 + ident.bytesize, 88, 0, slots, @sig_at].pack("L>9")
          cd += [32, 2, 0, 12].pack("C4") + ([0] * 4).pack("L>4")
          cd += [0, 0, @text_size, 1].pack("Q>4") + ident + hashes
          [0xFADE_0CC0, 20 + cd.bytesize, 1, 0, 20].pack("L>5") + cd
        end

        def pad(bytes, to)
          bytes << ("\0".b * (to - bytes.bytesize)) if to > bytes.bytesize
        end
      end
    end
  end
end
