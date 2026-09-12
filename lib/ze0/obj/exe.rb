# frozen_string_literal: true

require "digest"

require_relative "model"
require_relative "patch"

module Ze0
  module Obj
    # An `Obj::Unit` to a complete, signed `MH_EXECUTE` that runs: the
    # link step, in Ruby, for a program whose every import is libSystem's.
    #
    # `Obj::JIT` already solved the interesting half -- lay code and data
    # out, give each import a stub and a GOT slot, apply every relocation
    # -- and `Obj::Patch` is that engine, shared by both. What is added
    # here is the Mach-O container, chained fixups so a position-
    # independent image can be rebased and bound, and the ad-hoc code
    # signature Apple Silicon will not run a binary without.
    #
    # It refuses rather than guesses. A symbol libSystem does not define
    # belongs to one of the vendored archives, and reading an archive is a
    # real linker; `Native::Link` keeps those programs, and this says
    # which symbol sent them there.
    class Exe
      PAGE = 0x4000
      # Where the image goes, above the four unmapped gigabytes that make
      # a null dereference a fault.
      BASE = 0x1_0000_0000
      # The main stack, which holds ruby frames as native frames. `ld`
      # writes this from `-stack_size`; nothing writes it for an image
      # that no linker touched, so this does, and the two roads give a
      # program the same room.
      STACK = 0x400_0000
      MIN_MACOS = (14 << 16) | (0 << 8)

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

      # A section of the image, and where its bytes came from.
      Part = Struct.new(:name, :segment, :flags, :items, :size, :at, :fixups, keyword_init: true)

      # This unit is one `ld` has to link, and here is why.
      class Refused < StandardError; end

      # Writes `out` and answers nil, or answers the reason `ld` is needed
      # and writes nothing.
      def self.write(unit, out, stack: STACK, entry: "main")
        new(unit, out, stack: stack, entry: entry).write
      rescue Refused => e
        e.message
      end

      # Whether libSystem defines `name`. One it does not is a vendored
      # archive's, and dyld would not find it either.
      def self.libsystem?(name)
        (@handle ||= begin
          require "fiddle"
          ::Fiddle::Handle.new(LIBSYSTEM)
        end)[name]
        true
      rescue LoadError, StandardError
        false
      end

      def initialize(unit, out, stack: STACK, entry: "main")
        @unit = unit
        @out = out
        @stack = stack
        @entry = entry
        @addr = {}
        @fixups = []
      end

      def write
        @imports = @unit.imports.sort
        outside = @imports.reject { |name| self.class.libsystem?(name) }
        raise Refused, "#{outside.first} is not libSystem's" unless outside.empty?
        raise Refused, "nothing named #{@entry} to enter at" unless @unit.functions.any? { |f| f.name == @entry }

        lay_out
        File.binwrite(@out, stamped(assemble))
        File.chmod(0o755, @out)
        nil
      end

      private

      # --- layout --------------------------------------------------------

      # Every section's place. A section's address is its file offset
      # above the image base, so the two never have to be reasoned about
      # apart; `__bss` is the one exception, and it has no file bytes.
      def lay_out
        @parts = [
          part("__text", "__TEXT", CODE, :function),
          part("__stubs", "__TEXT", CODE, nil, size: @imports.size * STUB),
          part("__const", "__TEXT", S_REGULAR, :text_const),
          part("__got", "__DATA_CONST", S_REGULAR, nil, size: @imports.size * 8, fixups: true),
          part("__const", "__DATA_CONST", S_REGULAR, :data_const, fixups: true),
          part("__data", "__DATA", S_REGULAR, :data, fixups: true),
          part("__bss", "__DATA", S_ZEROFILL, :bss)
        ]
        # A section with nothing in it is not written, and a segment whose
        # sections are all empty is not a segment: an image with a
        # zero-length one does not load.
        @parts.reject! { |p| p.size.zero? }
        @segments = ["__PAGEZERO", *@parts.map(&:segment).uniq, "__LINKEDIT"]
        head = Patch.align(32 + commands.bytesize, 16)
        at = head
        @parts.each_with_index do |p, i|
          at = Patch.align(at, PAGE) if i.positive? && p.segment != @parts[i - 1].segment
          p.at = Patch.align(at, 16)
          at = p.at + p.size
        end
        @text_size = Patch.align(segment_end("__TEXT"), PAGE)
        last = @parts.last.segment
        bss = part_named("__bss", "__DATA")&.size.to_i
        @link_at = Patch.align(segment_end(last) - bss, PAGE)
        @link_vm = Patch.align(BASE + segment_end(last), PAGE)
        addresses
      end

      # A section. `section` names the `Obj` items that land in it, and a
      # section with no items -- `__stubs`, `__got` -- is given its size
      # instead.
      def part(name, segment, flags, section, size: nil, fixups: false)
        items = case section
                when nil then nil
                when :function then Patch.layout(@unit.functions, 4)
                else Patch.layout(@unit.data.select { |d| d.section == section }, 8)
                end
        Part.new(name: name, segment: segment, flags: flags, items: items,
                 size: size || items[:size], fixups: fixups)
      end

      def part_named(name, segment) = @parts.find { |p| p.name == name && p.segment == segment }
      def in_segment(name) = @parts.select { |p| p.segment == name }
      def segment_start(name) = in_segment(name).first.at.to_i
      def segment_end(name) = in_segment(name).then { |ps| ps.last.at.to_i + ps.last.size }

      def addresses
        @parts.each do |p|
          next unless p.items

          p.items[:at].each { |item, off| @addr[item.name] = BASE + p.at + off }
        end
        # A program with no imports has neither section, and needs
        # neither table.
        stubs = part_named("__stubs", "__TEXT")&.at
        got = part_named("__got", "__DATA_CONST")&.at
        @stub_at = @imports.each_with_index.to_h { |n, i| [n, BASE + stubs + (i * STUB)] }
        @got_at = @imports.each_with_index.to_h { |n, i| [n, BASE + got + (i * 8)] }
        @entry_at = @addr.fetch(@entry) - BASE
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
      # other section is its items with the gaps between them zero.
      # `__bss` has no bytes at all -- that is what it is.
      def bytes_of(part)
        return "".b if part.flags == S_ZEROFILL
        return stub_bytes(part) if part.name == "__stubs"
        return got_bytes(part) if part.name == "__got"

        part.items[:at].inject(+"".b) do |out, (item, off)|
          pad(out, off)
          out << patched(item, BASE + part.at + off, part)
        end
      end

      # `item` with every relocation applied. A call reaches an import
      # through its stub and an address through its GOT slot; everything
      # else is at its own place in the image. An `abs64` slot holds a
      # chain entry rather than the address, so it is recorded here and
      # overwritten once the chains are threaded.
      def patched(item, base, part)
        Patch.apply(item, base) do |r|
          case r.kind
          when :abs64
            raise Refused, "an absolute relocation in #{part.name}" unless part.fixups

            here = base + r.offset - BASE
            at = @addr[r.symbol]
            @fixups << [part.segment, here, at ? :rebase : :bind, at ? at - BASE : @imports.index(r.symbol)]
            at || @got_at.fetch(r.symbol)
          when :got_page21, :got_pageoff12
            @addr[r.symbol] || @got_at.fetch(r.symbol)
          when :branch26
            @addr[r.symbol] || @stub_at.fetch(r.symbol)
          else
            @addr[r.symbol] or raise Refused, "#{r.symbol} has no place in the image"
          end
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

      # A GOT slot an import, each one a bind for dyld to fill in.
      def got_bytes(part)
        @imports.each_index { |i| @fixups << [part.segment, part.at + (i * 8), :bind, i] }
        "\0".b * (@imports.size * 8)
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

      # The fixups, the symbol table, and the names: everything the loader
      # reads and nothing the program runs. The signature goes after it,
      # and its size is fixed by where it starts.
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

      # The one symbol an executable exports: its own header, at offset
      # zero, which is what `-no_exported_symbols` leaves behind. A root
      # node holding one terminal child spelled "__mh_execute_header".
      def exports_trie
        leaf = [2, 0, 0, 0].pack("C4")
        root = [0, 1].pack("C2") + "__mh_execute_header\0".b
        root += [root.bytesize + 1].pack("C")
        (root + leaf).then { |t| t + ("\0".b * (-t.bytesize % 8)) }
      end

      # Every name this image defines, as a local symbol: `nm` can read
      # the binary, and nothing is exported.
      def symbol_table
        strings = +"\0".b
        rows = +"".b
        @parts.each_with_index do |p, i|
          next unless p.items

          p.items[:at].each do |item, off|
            rows << [strings.bytesize].pack("L<") << [N_SECT, i + 1, 0].pack("CCS<")
            rows << [BASE + p.at + off].pack("Q<")
            strings << "_#{item.name}\0".b
          end
        end
        [rows, strings + ("\0".b * (-strings.bytesize % 8))]
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
        out << command(LC_BUILD_VERSION, [1, MIN_MACOS, MIN_MACOS, 0].pack("L<4"))
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
          [part.flags == S_ZEROFILL ? 0 : part.at.to_i, 4, 0, 0, part.flags, 0, 0, 0].pack("L<8")
      end

      # --- the stamps ----------------------------------------------------

      # The UUID is the image's own hash, so two links of the same program
      # agree; `ld` gives every link a fresh one, which is why
      # `Obj::Stamps` had to blank it. Then the signature, over everything
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
