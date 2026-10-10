# frozen_string_literal: true

module Zr
  module Obj
    module MachO
      # Reads a linked arm64 Mach-O image: a bundle (a C extension), a
      # dylib or an executable, or for its symbols a compiler's object
      # file. It gives what zr needs to link or load one:
      # its segments, the dylibs it loads, the symbols it defines and the
      # ones it imports, and each pointer that dyld fixes, as one `Rebase`
      # or `Bind` record whether the image keeps them as `LC_DYLD_INFO`
      # opcodes or as chained fixups. A fat file gives its arm64 slice. The
      # layout follows <mach-o/loader.h>, <mach-o/nlist.h>,
      # <mach-o/fixup-chains.h> and dyld's opcode readers.
      class Image
        MH_MAGIC_64 = 0xFEEDFACF
        FAT_MAGIC = 0xCAFEBABE
        CPU_TYPE_ARM64 = 0x0100000C
        MH_OBJECT = 1
        MH_EXECUTE = 2
        MH_DYLIB = 6
        MH_BUNDLE = 8
        FILETYPES = { MH_OBJECT => :object, MH_EXECUTE => :execute, MH_DYLIB => :dylib, MH_BUNDLE => :bundle }.freeze #: Hash[Integer, ::Symbol]

        LC_REQ_DYLD = 0x80000000
        LC_SYMTAB = 0x2
        LC_LOAD_DYLIB = 0xC
        LC_ID_DYLIB = 0xD
        LC_SEGMENT_64 = 0x19
        LC_UUID = 0x1B
        LC_LAZY_LOAD_DYLIB = 0x20
        LC_DYLD_INFO = 0x22
        LC_DYLD_INFO_ONLY = 0x22 | LC_REQ_DYLD
        LC_LOAD_WEAK_DYLIB = 0x18 | LC_REQ_DYLD
        LC_REEXPORT_DYLIB = 0x1F | LC_REQ_DYLD
        LC_LOAD_UPWARD_DYLIB = 0x23 | LC_REQ_DYLD
        LC_DYLD_EXPORTS_TRIE = 0x33 | LC_REQ_DYLD
        LC_DYLD_CHAINED_FIXUPS = 0x34 | LC_REQ_DYLD
        # The commands that name a dylib that the image loads, in the order
        # that gives each its ordinal.
        DYLIB_COMMANDS = [LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_LOAD_UPWARD_DYLIB, LC_LAZY_LOAD_DYLIB].freeze #: Array[Integer]

        N_EXT = 0x01
        N_TYPE = 0x0E
        N_UNDF = 0x0
        N_STAB = 0xE0

        # The ordinals of a bind that do not name one of the image's dylibs.
        SELF = 0
        MAIN_EXECUTABLE = -1
        FLAT_LOOKUP = -2
        WEAK_LOOKUP = -3

        EXPORT_REEXPORT = 0x08
        EXPORT_STUB_AND_RESOLVER = 0x10

        # A segment, with its sections.
        # @rbs skip
        Segment = Data.define(:name, :vmaddr, :vmsize, :fileoff, :filesize, :maxprot, :initprot, :flags, :sections)
        # A section. `offset` is its place in the file, or 0 for zero fill.
        # @rbs skip
        Section = Data.define(:name, :segment, :addr, :size, :offset, :align, :flags)
        # One entry of the symbol table, an `nlist_64`.
        # @rbs skip
        Nlist = Data.define(:name, :type, :sect, :desc, :value)
        # A pointer at `address` that holds an address in the image, and
        # that moves with the image: dyld adds the slide. `target` is the
        # address that it holds before the slide.
        # @rbs skip
        Rebase = Data.define(:address, :target)
        # A pointer at `address` that dyld sets to the address of the
        # symbol `name`, plus `addend`. `library` is a dylib's ordinal
        # (1 is the first `dylibs` entry) or SELF, MAIN_EXECUTABLE,
        # FLAT_LOOKUP or WEAK_LOOKUP. `lazy` binds are the ones that a stub
        # resolves on its first call.
        # @rbs skip
        Bind = Data.define(:address, :name, :library, :addend, :weak, :lazy)
        # A symbol that the image exports, at `address` from the image's
        # Mach header (`base`). A re-export has no address; it names a
        # dylib's ordinal.
        # @rbs skip
        Export = Data.define(:name, :address, :flags, :reexport)
        # The place of one of dyld's streams in the file.
        # @rbs skip
        Span = Data.define(:offset, :size)

        attr_reader :filetype #: ::Symbol
        attr_reader :segments #: Array[Segment]
        attr_reader :dylibs #: Array[String]
        attr_reader :symbols #: Array[Nlist]
        attr_reader :uuid #: String?
        attr_reader :install_name #: String?
        # The image's bytes: its arm64 slice of a fat file.
        attr_reader :bytes #: String

        # Reads `bytes`, a thin arm64 image or a fat file with an arm64
        # slice.
        #: (String bytes) -> Image
        def self.read(bytes) = new(arm64_slice(bytes))

        # The arm64 image in `bytes`: the bytes themselves, or the slice of
        # a fat file. A fat header is big-endian.
        #: (String bytes) -> String
        def self.arm64_slice(bytes)
          return bytes unless bytes.unpack1("N") == FAT_MAGIC

          count = bytes.unpack1("N", offset: 4) #: Integer
          count.times do |i|
            cpu, _sub, offset, size = bytes.unpack("N4", offset: 8 + (i * 20)) #: [Integer, Integer, Integer, Integer]
            next unless cpu == CPU_TYPE_ARM64

            return bytes.byteslice(offset, size) || raise(ArgumentError, "a fat slice past the end")
          end
          raise ArgumentError, "a fat file with no arm64 slice"
        end

        #: (String bytes) -> void
        def initialize(bytes)
          @bytes = bytes
          magic, cpu, _sub, type, ncmds = bytes.unpack("L<5") #: [Integer, Integer, Integer, Integer, Integer]
          raise ArgumentError, "not an arm64 Mach-O image" unless magic == MH_MAGIC_64 && cpu == CPU_TYPE_ARM64

          @filetype = FILETYPES.fetch(type) { raise ArgumentError, "Mach-O file type #{type} is not an image" }
          @segments = []
          @dylibs = []
          @symbols = []
          @uuid = nil
          @install_name = nil
          @dyld_info = nil
          @exports_trie = nil
          @chained_fixups = nil
          read_commands(ncmds)
        end

        # Each section of each segment.
        #: () -> Array[Section]
        def sections = segments.flat_map(&:sections)

        # The names of the symbols that the image takes from elsewhere,
        # from its symbol table, sorted. A common symbol (an object's
        # `int counter;`, undefined with a size) is the image's own.
        #: () -> Array[String]
        def undefined = external.select { |s| s.type & N_TYPE == N_UNDF && s.value.zero? }.map(&:name).sort

        # The names of the external symbols that the image defines, from
        # its symbol table, sorted: common symbols too.
        #: () -> Array[String]
        def defined = external.reject { |s| s.type & N_TYPE == N_UNDF && s.value.zero? }.map(&:name).sort

        # `name` as C writes it: Mach-O puts `_` before each C name.
        #: (String name) -> String
        def c_name(name) = name.delete_prefix("_")

        # The C strings of the image, from its `__cstring` sections.
        #: () -> Array[String]
        def c_strings
          sections.select { |section| section.name == "__cstring" }
                  .flat_map { |section| bytes.byteslice(section.offset, section.size).to_s.split("\0") }
        end

        # Every pointer that dyld rebases, from the opcodes or the chains.
        #: () -> Array[Rebase]
        def rebases = fixups[0]

        # Every pointer that dyld binds, from the opcodes or the chains,
        # lazy ones included.
        #: () -> Array[Bind]
        def binds = fixups[1]

        # The weak definitions that dyld coalesces with another image's
        # definition of the same name (C++ inline functions and type info),
        # from `LC_DYLD_INFO`'s weak bind stream. They are not imports: the
        # image holds a definition of each. Their library is WEAK_LOOKUP.
        #: () -> Array[Bind]
        def weak_binds = fixups[2]

        # The exports trie of `LC_DYLD_EXPORTS_TRIE` or `LC_DYLD_INFO`.
        #: () -> Array[Export]
        def exports
          @exports ||= begin
            trie = @exports_trie || (dyld_info(4) if @dyld_info)
            trie ? Trie.new(@bytes, trie).exports : []
          end
        end

        # The vm address of the image's first byte, its Mach header: where
        # the segment that starts the file is. An executable's `__PAGEZERO`
        # comes before it, with no bytes in the file.
        #: () -> Integer
        def base = segments.find { |s| s.fileoff.zero? && s.filesize.positive? }&.vmaddr || 0

        # The segment that holds the vm address `address`.
        #: (Integer address) -> Segment?
        def segment_at(address) = segments.find { |s| address >= s.vmaddr && address < s.vmaddr + s.vmsize }

        # The 8 bytes at the vm address `address`, as a little-endian word.
        #: (Integer address) -> Integer
        def word_at(address)
          segment = segment_at(address) || raise(ArgumentError, format("no segment holds 0x%x", address))
          @bytes.unpack1("Q<", offset: segment.fileoff + (address - segment.vmaddr)) #: Integer
        end

        private

        # The symbol table's external entries, debug entries left out.
        #: () -> Array[Nlist]
        def external = symbols.select { |s| s.type & N_STAB == 0 && s.type & N_EXT != 0 }

        #: (Integer ncmds) -> void
        def read_commands(ncmds)
          at = 32
          ncmds.times do
            cmd, size = @bytes.unpack("L<2", offset: at) #: [Integer, Integer]
            case cmd
            when LC_SEGMENT_64 then @segments << segment(at)
            when LC_SYMTAB then @symbols = symbol_table(at)
            when *DYLIB_COMMANDS then @dylibs << dylib_name(at)
            when LC_ID_DYLIB then @install_name = dylib_name(at)
            when LC_UUID then @uuid = (@bytes.byteslice(at + 8, 16) || "").unpack1("H*").to_s
            when LC_DYLD_INFO, LC_DYLD_INFO_ONLY then @dyld_info = at
            when LC_DYLD_EXPORTS_TRIE then @exports_trie = linkedit(at)
            when LC_DYLD_CHAINED_FIXUPS then @chained_fixups = linkedit(at)
            end
            at += size
          end
        end

        # The data that a `linkedit_data_command` at `at` points to.
        #: (Integer at) -> Span
        def linkedit(at)
          offset, size = @bytes.unpack("L<2", offset: at + 8) #: [Integer, Integer]
          Span.new(offset: offset, size: size)
        end

        #: (Integer at) -> Segment
        def segment(at)
          name = cstring(at + 8, limit: 16)
          fields = @bytes.unpack("Q<4L<4", offset: at + 24) #: [Integer, Integer, Integer, Integer, Integer, Integer, Integer, Integer]
          vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, flags = fields
          sections = Array.new(nsects) do |i|
            s = at + 72 + (i * 80)
            words = @bytes.unpack("Q<2L<5", offset: s + 32) #: [Integer, Integer, Integer, Integer, Integer, Integer, Integer]
            addr, size, offset, align, _reloff, _nreloc, sflags = words
            Section.new(name: cstring(s, limit: 16), segment: cstring(s + 16, limit: 16), addr: addr, size: size, offset: offset,
                        align: align, flags: sflags)
          end
          Segment.new(name: name, vmaddr: vmaddr, vmsize: vmsize, fileoff: fileoff, filesize: filesize, maxprot: maxprot,
                      initprot: initprot, flags: flags, sections: sections)
        end

        #: (Integer at) -> Array[Nlist]
        def symbol_table(at)
          symoff, nsyms, stroff, _strsize = @bytes.unpack("L<4", offset: at + 8) #: [Integer, Integer, Integer, Integer]
          Array.new(nsyms) do |i|
            strx, type, sect, desc, value = @bytes.unpack("L<CCS<Q<", offset: symoff + (i * 16)) #: [Integer, Integer, Integer, Integer, Integer]
            Nlist.new(name: cstring(stroff + strx), type: type, sect: sect, desc: desc, value: value)
          end
        end

        # A `dylib_command`'s name, at the offset its `lc_str` gives.
        #: (Integer at) -> String
        def dylib_name(at)
          offset = @bytes.unpack1("L<", offset: at + 8) #: Integer
          cstring(at + offset)
        end

        # The NUL-ended string at `at`, at most `limit` bytes: a name in a
        # load command fills its field with no NUL.
        #: (Integer at, ?limit: Integer?) -> String
        def cstring(at, limit: nil)
          stop = @bytes.index("\0", at) || @bytes.bytesize
          stop = at + limit if limit && stop > at + limit
          @bytes.byteslice(at, stop - at) || ""
        end

        # One of `dyld_info_command`'s five streams: 0 rebase, 1 bind,
        # 2 weak bind, 3 lazy bind, 4 export.
        #: (Integer stream) -> Span
        def dyld_info(stream)
          at = @dyld_info || raise(ArgumentError, "the image has no LC_DYLD_INFO")
          linkedit(at + (stream * 8))
        end

        # The rebases, the binds and the weak binds.
        #: () -> [Array[Rebase], Array[Bind], Array[Bind]]
        def fixups
          @fixups ||= if (chained = @chained_fixups)
                        Chains.new(self, @bytes, chained).fixups
                      elsif @dyld_info
                        opcodes = Opcodes.new(self, @bytes)
                        [opcodes.rebases(dyld_info(0)),
                         opcodes.binds(dyld_info(1)) + opcodes.binds(dyld_info(3), lazy: true),
                         opcodes.binds(dyld_info(2), coalesce: true)]
                      else
                        [[], [], []]
                      end
        end

        # A reader of the LEB128 numbers and strings that dyld's streams
        # are made of.
        class Cursor
          # @rbs @bytes: String
          # @rbs @stop: Integer

          attr_reader :at #: Integer

          #: (String bytes, Integer at, Integer stop) -> void
          def initialize(bytes, at, stop)
            @bytes = bytes
            @at = at
            @stop = stop
          end

          # A cursor over the stream `span`.
          #: (String bytes, Span span) -> Cursor
          def self.over(bytes, span) = new(bytes, span.offset, span.offset + span.size)

          #: () -> bool
          def more? = @at < @stop

          #: () -> Integer
          def byte
            b = @bytes.getbyte(@at) || raise(ArgumentError, "a dyld stream past the end of the file")
            @at += 1
            b
          end

          #: () -> Integer
          def uleb
            n = 0
            shift = 0
            loop do
              b = byte
              n |= (b & 0x7F) << shift
              shift += 7
              return n if b < 0x80
            end
          end

          #: () -> Integer
          def sleb
            n = 0
            shift = 0
            loop do
              b = byte
              n |= (b & 0x7F) << shift
              shift += 7
              return b.anybits?(0x40) ? n - (1 << shift) : n if b < 0x80
            end
          end

          #: () -> String
          def cstring
            stop = @bytes.index("\0", @at) || raise(ArgumentError, "a string past the end of a dyld stream")
            s = @bytes.byteslice(@at, stop - @at) || ""
            @at = stop + 1
            s
          end

          #: (Integer at) -> void
          def seek(at)
            @at = at
          end
        end

        # The rebase and bind opcode streams of `LC_DYLD_INFO`.
        class Opcodes
          # @rbs @image: Image
          # @rbs @bytes: String

          REBASE_DONE = 0x00
          REBASE_SET_TYPE_IMM = 0x10
          REBASE_SET_SEGMENT_AND_OFFSET_ULEB = 0x20
          REBASE_ADD_ADDR_ULEB = 0x30
          REBASE_ADD_ADDR_IMM_SCALED = 0x40
          REBASE_DO_REBASE_IMM_TIMES = 0x50
          REBASE_DO_REBASE_ULEB_TIMES = 0x60
          REBASE_DO_REBASE_ADD_ADDR_ULEB = 0x70
          REBASE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB = 0x80

          BIND_DONE = 0x00
          BIND_SET_DYLIB_ORDINAL_IMM = 0x10
          BIND_SET_DYLIB_ORDINAL_ULEB = 0x20
          BIND_SET_DYLIB_SPECIAL_IMM = 0x30
          BIND_SET_SYMBOL_TRAILING_FLAGS_IMM = 0x40
          BIND_SET_TYPE_IMM = 0x50
          BIND_SET_ADDEND_SLEB = 0x60
          BIND_SET_SEGMENT_AND_OFFSET_ULEB = 0x70
          BIND_ADD_ADDR_ULEB = 0x80
          BIND_DO_BIND = 0x90
          BIND_DO_BIND_ADD_ADDR_ULEB = 0xA0
          BIND_DO_BIND_ADD_ADDR_IMM_SCALED = 0xB0
          BIND_DO_BIND_ULEB_TIMES_SKIPPING_ULEB = 0xC0
          BIND_SYMBOL_FLAGS_WEAK_IMPORT = 0x1

          # dyld adds to an address as a 64-bit word, so a large ULEB steps
          # back.
          WORD = (1 << 64) - 1

          #: (Image image, String bytes) -> void
          def initialize(image, bytes)
            @image = image
            @bytes = bytes
          end

          # The pointers of the rebase stream `span`.
          #: (Span span) -> Array[Rebase]
          def rebases(span)
            out = [] #: Array[Rebase]
            c = Cursor.over(@bytes, span)
            address = 0
            rebase = ->(at) { out << Rebase.new(address: at, target: @image.word_at(at)) }
            while c.more?
              op = c.byte
              imm = op & 0x0F
              case op & 0xF0
              when REBASE_DONE then break
              when REBASE_SET_TYPE_IMM then nil
              when REBASE_SET_SEGMENT_AND_OFFSET_ULEB then address = @image.segments.fetch(imm).vmaddr + c.uleb
              when REBASE_ADD_ADDR_ULEB then address = (address + c.uleb) & WORD
              when REBASE_ADD_ADDR_IMM_SCALED then address = (address + (imm * 8)) & WORD
              when REBASE_DO_REBASE_IMM_TIMES, REBASE_DO_REBASE_ULEB_TIMES
                (op & 0xF0 == REBASE_DO_REBASE_IMM_TIMES ? imm : c.uleb).times do
                  rebase.call(address)
                  address += 8
                end
              when REBASE_DO_REBASE_ADD_ADDR_ULEB
                rebase.call(address)
                address = (address + 8 + c.uleb) & WORD
              when REBASE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB
                count = c.uleb
                skip = c.uleb
                count.times do
                  rebase.call(address)
                  address = (address + 8 + skip) & WORD
                end
              else raise ArgumentError, format("rebase opcode 0x%02x", op)
              end
            end
            out
          end

          # The pointers of the bind stream `span`. A lazy stream has one
          # bind per entry, each ended by BIND_DONE. The weak bind stream
          # (`coalesce`) names no library: its binds are WEAK_LOOKUP.
          #: (Span span, ?lazy: bool, ?coalesce: bool) -> Array[Bind]
          def binds(span, lazy: false, coalesce: false)
            out = [] #: Array[Bind]
            c = Cursor.over(@bytes, span)
            address = 0
            library = coalesce ? WEAK_LOOKUP : SELF
            name = ""
            addend = 0
            weak = false
            bind = lambda do |at|
              out << Bind.new(address: at, name: name, library: library, addend: addend, weak: weak, lazy: lazy)
            end
            while c.more?
              op = c.byte
              imm = op & 0x0F
              case op & 0xF0
              when BIND_DONE then lazy ? next : break
              when BIND_SET_DYLIB_ORDINAL_IMM then library = imm
              when BIND_SET_DYLIB_ORDINAL_ULEB then library = c.uleb
              when BIND_SET_DYLIB_SPECIAL_IMM then library = imm.zero? ? SELF : imm - 16
              when BIND_SET_SYMBOL_TRAILING_FLAGS_IMM
                weak = imm.anybits?(BIND_SYMBOL_FLAGS_WEAK_IMPORT)
                name = c.cstring
              when BIND_SET_TYPE_IMM then nil
              when BIND_SET_ADDEND_SLEB then addend = c.sleb
              when BIND_SET_SEGMENT_AND_OFFSET_ULEB then address = @image.segments.fetch(imm).vmaddr + c.uleb
              when BIND_ADD_ADDR_ULEB then address = (address + c.uleb) & WORD
              when BIND_DO_BIND
                bind.call(address)
                address += 8
              when BIND_DO_BIND_ADD_ADDR_ULEB
                bind.call(address)
                address = (address + 8 + c.uleb) & WORD
              when BIND_DO_BIND_ADD_ADDR_IMM_SCALED
                bind.call(address)
                address = (address + 8 + (imm * 8)) & WORD
              when BIND_DO_BIND_ULEB_TIMES_SKIPPING_ULEB
                count = c.uleb
                skip = c.uleb
                count.times do
                  bind.call(address)
                  address = (address + 8 + skip) & WORD
                end
              else raise ArgumentError, format("bind opcode 0x%02x", op)
              end
            end
            out
          end
        end

        # The chained fixups of `LC_DYLD_CHAINED_FIXUPS`: a chain of
        # pointers in each page, each pointer a rebase or a bind, with the
        # imports in a table. Only arm64's formats (no pointer
        # authentication) are read.
        class Chains
          # @rbs @image: Image
          # @rbs @bytes: String
          # @rbs @at: Integer

          PTR_64 = 2
          PTR_64_OFFSET = 6
          IMPORT = 1
          IMPORT_ADDEND = 2
          IMPORT_ADDEND64 = 3
          PAGE_START_NONE = 0xFFFF
          PAGE_START_MULTI = 0x8000

          #: (Image image, String bytes, Span span) -> void
          def initialize(image, bytes, span)
            @image = image
            @bytes = bytes
            @at = span.offset
          end

          # The rebases, the binds, and no weak binds: chained fixups keep
          # weak definitions in the exports, not in a stream of their own.
          #: () -> [Array[Rebase], Array[Bind], Array[Bind]]
          def fixups
            header = @bytes.unpack("L<7", offset: @at) #: [Integer, Integer, Integer, Integer, Integer, Integer, Integer]
            _version, starts, imports_at, symbols_at, count, format, _symbols_format = header
            imports = imports(@at + imports_at, @at + symbols_at, count, format)
            rebases = [] #: Array[Rebase]
            binds = [] #: Array[Bind]
            segment_starts(@at + starts).each do |start|
              walk(start) do |address, word|
                if word[63] == 1
                  import = imports.fetch(word & 0xFF_FFFF)
                  binds << import.with(address: address, addend: import.addend + ((word >> 24) & 0xFF))
                else
                  rebases << Rebase.new(address: address, target: target(start, word))
                end
              end
            end
            [rebases, binds, []]
          end

          private

          # The `dyld_chained_starts_in_segment` offsets of the segments
          # that have chains.
          #: (Integer at) -> Array[Integer]
          def segment_starts(at)
            count = @bytes.unpack1("L<", offset: at) #: Integer
            offsets = @bytes.unpack("L<#{count}", offset: at + 4) #: Array[Integer]
            offsets.reject(&:zero?).map { |o| at + o }
          end

          # Yields the address and word of each pointer in the chains of one
          # segment.
          #: (Integer start) { (Integer, Integer) -> void } -> void
          def walk(start)
            fields = @bytes.unpack("L<S<S<Q<L<S<", offset: start) #: [Integer, Integer, Integer, Integer, Integer, Integer]
            _size, page_size, format, segment_offset, _max, page_count = fields
            raise ArgumentError, "chained pointer format #{format}" unless format == PTR_64 || format == PTR_64_OFFSET

            page_starts = @bytes.unpack("S<#{page_count}", offset: start + 22) #: Array[Integer]
            page_starts.each_with_index do |offset, page|
              next if offset == PAGE_START_NONE
              raise ArgumentError, "chained fixups with several starts in a page" if offset.anybits?(PAGE_START_MULTI)

              address = @image.base + segment_offset + (page * page_size) + offset
              loop do
                word = @image.word_at(address)
                yield address, word
                step = (word >> 51) & 0xFFF
                break if step.zero?

                address += step * 4
              end
            end
          end

          # The address that a rebase pointer holds: a vm address in
          # PTR_64, an offset from the image's start in PTR_64_OFFSET, with
          # its top byte in `high8`.
          #: (Integer start, Integer word) -> Integer
          def target(start, word)
            format = @bytes.unpack1("S<", offset: start + 6) #: Integer
            low = word & 0xF_FFFF_FFFF
            high = ((word >> 36) & 0xFF) << 56
            (format == PTR_64_OFFSET ? @image.base : 0) + low + high
          end

          # The import table, as binds with no address yet.
          #: (Integer at, Integer names, Integer count, Integer format) -> Array[Bind]
          def imports(at, names, count, format)
            Array.new(count) do |i|
              case format
              when IMPORT
                word = @bytes.unpack1("L<", offset: at + (i * 4)) #: Integer
                import(names, word & 0xFF, weak: word[8] == 1, name_at: word >> 9, addend: 0, bits: 8)
              when IMPORT_ADDEND
                word, addend = @bytes.unpack("L<l<", offset: at + (i * 8)) #: [Integer, Integer]
                import(names, word & 0xFF, weak: word[8] == 1, name_at: word >> 9, addend: addend, bits: 8)
              when IMPORT_ADDEND64
                word, addend = @bytes.unpack("Q<q<", offset: at + (i * 16)) #: [Integer, Integer]
                import(names, word & 0xFFFF, weak: word[16] == 1, name_at: word >> 32, addend: addend, bits: 16)
              else raise ArgumentError, "chained import format #{format}"
              end
            end
          end

          # One import. The ordinal field is unsigned, its top values
          # standing for the special ordinals.
          #: (Integer names, Integer ordinal, weak: bool, name_at: Integer, addend: Integer, bits: Integer) -> Bind
          def import(names, ordinal, weak:, name_at:, addend:, bits:)
            library = ordinal >= (1 << bits) - 15 ? ordinal - (1 << bits) : ordinal
            name = Cursor.new(@bytes, names + name_at, @bytes.bytesize).cstring
            Bind.new(address: 0, name: name, library: library, addend: addend, weak: weak, lazy: false)
          end
        end

        # The exports trie: from the root, each node may end a name (with
        # its flags and address), and gives the edges to its children.
        class Trie
          # @rbs @bytes: String
          # @rbs @span: Span

          #: (String bytes, Span span) -> void
          def initialize(bytes, span)
            @bytes = bytes
            @span = span
          end

          #: () -> Array[Export]
          def exports
            return [] if @span.size.zero?

            out = [] #: Array[Export]
            pending = [[0, +""]] #: Array[[Integer, String]]
            while (node, prefix = pending.pop)
              c = Cursor.new(@bytes, @span.offset + node, @span.offset + @span.size)
              info = c.uleb
              children = c.at + info
              out << export(c, prefix) if info.positive?
              c.seek(children)
              c.byte.times do
                edge = c.cstring
                pending << [c.uleb, prefix + edge]
              end
            end
            out.sort_by(&:name)
          end

          private

          # The export that ends at the node under `c`, named `name`.
          #: (Cursor c, String name) -> Export
          def export(c, name)
            flags = c.uleb
            return Export.new(name: name, address: nil, flags: flags, reexport: c.uleb) if flags.anybits?(EXPORT_REEXPORT)

            # A resolver's address follows a stub's; the export is the stub.
            address = c.uleb
            c.uleb if flags.anybits?(EXPORT_STUB_AND_RESOLVER)
            Export.new(name: name, address: address, flags: flags, reexport: nil)
          end
        end
      end
    end
  end
end
