# frozen_string_literal: true

require_relative "object_file"
require_relative "../patch"
require_relative "../../bytes"
require_relative "../relocs/aarch64"
require_relative "../../refused"

module Zr
  module Obj
    module MachO
      # zr's linker cannot link these objects. The message gives the reason.
      class Refused < StandardError
        include Zr::Refusal
      end

      # Objects linked together: the runtime and eval support objects in a
      # `Prelink`, or a program's own objects. Each input section goes into
      # the part of its kind, in input order. An undefined symbol resolves
      # to another input's global, to an address that `outside` returns, or
      # to an external. The block reaches an external through a stub and a
      # GOT slot, which the image binds or rebases.
      #
      # The caller places each part at an address, then reads its bytes.
      # The bytes have all relocations applied. The slots that dyld must
      # write are in `fixups`, as `[address, :rebase, target]` or
      # `[address, :external, name, addend]`.
      class Block
        # A link resolves to `[input, symbol]`, an address or an external's
        # name, so the links and the GOT keys are untyped.
        # @rbs @inputs: Array[ObjectFile::Read]
        # @rbs @outside: (^(String) -> Integer?)?
        # @rbs @at: Hash[Symbol, Integer]
        # @rbs @globals: Hash[String, [Integer, Integer]]
        # @rbs @links: Array[Hash[Integer, untyped]]
        # @rbs @got: Array[untyped]
        # @rbs @chunks: Hash[Symbol, Array[[Integer, Integer, Integer]]]
        # @rbs @sizes: Hash[Symbol, Integer]
        # @rbs @aligns: Hash[Symbol, Integer]
        # @rbs @part_of: Array[Array[Symbol?]]
        # @rbs @placed: Array[Array[Integer]]
        # @rbs @addr: Array[Array[Integer?]]
        # @rbs @stub_at: Hash[String, Integer]
        # @rbs @got_at: Hash[untyped, Integer]
        # @rbs @far: Array[Integer]
        # @rbs @islands: Array[Integer]
        # @rbs @island_at: Hash[Integer, Integer]
        # @rbs @code_size: Integer

        # <mach-o/nlist.h>: a symbol's type byte.
        N_STAB = 0xE0
        N_TYPE = 0x0E
        N_EXT = 0x01
        N_UNDF = 0x0
        N_SECT = 0xE

        # `adrp x16, got@PAGE; ldr x16, [x16, got@PAGEOFF]; br x16`
        STUB = 12
        # `adrp x16, target@PAGE; add x16, x16, target@PAGEOFF; br x16`: a
        # jump to an address that a branch cannot reach.
        ISLAND = 12
        # A branch reaches 128 MB before or after itself.
        BRANCH_REACH = 1 << 27

        # The relocation kind for each arm64 relocation type in an object.
        KINDS = ObjectFile::RELOC.to_h { |kind, (type, _, _)| [type, kind] }.freeze #: Hash[Integer, reloc_kind]
        ABS64 = ObjectFile::RELOC.fetch(:abs64).first #: Integer
        BRANCH26 = ObjectFile::RELOC.fetch(:branch26).first #: Integer
        GOT = ObjectFile::RELOC.fetch_values(:got_page21, :got_pageoff12).map(&:first).freeze #: Array[Integer]
        # Typed in sig/zr/obj/macho/block.rbs: inline RBS does not read a
        # multiple assignment.
        GOT_PAGE21, GOT_PAGEOFF12 = GOT
        ARM64_RELOC_ADDEND = ObjectFile::ARM64_RELOC_ADDEND
        # `r_extern` of a relocation: it names a symbol, not a section.
        EXTERN = 1 << 27

        # The parts, in image order, and the input sections that each part
        # contains. The block makes `stubs` and `got` itself.
        PARTS = %i[text stubs const got dconst data bss].freeze
        FROM = { %w[__TEXT __text] => :text, %w[__TEXT __const] => :const, %w[__DATA __const] => :dconst,
                 %w[__DATA __data] => :data, %w[__DATA __bss] => :bss }.freeze
        # The parts that can contain an absolute relocation. dyld writes
        # the relocation, and dyld writes only into data.
        WRITABLE = %i[got dconst data].freeze

        attr_reader :externals #: Array[String]
        attr_reader :fixups #: Array[Array[untyped]]

        # `objects` are object file bytes, or the result of
        # `ObjectFile.read` for them. `ObjectFile.of` builds that result from
        # a unit without writing an object. `outside` returns the address of
        # a name that no input defines, or nil.
        #: (Array[String | ObjectFile::Read] objects, ?outside: (^(String) -> Integer?)?) -> void
        def initialize(objects, outside: nil)
          @inputs = objects.map { |o| o.is_a?(String) ? ObjectFile.read(o) : o }
          @outside = outside
          @at = {}
          @fixups = []
          resolve
          got_slots
          chunks
          far_calls
        end

        #: () -> bool
        def empty? = PARTS.all? { |part| size(part).zero? }

        #: (Symbol part) -> Integer
        def size(part) = @sizes.fetch(part)

        # The part's alignment, as a power of two.
        #: (Symbol part) -> Integer
        def align(part) = @aligns.fetch(part)

        # Placing the text decides its islands, so the text's size can grow.
        #: (Symbol part, Integer address) -> Integer
        def place(part, address)
          islands(address) if part == :text
          @at[part] = address
        end

        #: (Symbol part) -> Integer
        def at(part) = @at.fetch(part)

        # Whether an input defines `name` ("_main") as a global.
        #: (String name) -> bool
        def defines?(name) = @globals.key?(name)

        # The names of every global the inputs define.
        #: () -> Array[String]
        def names = @globals.keys

        # The address of the global `name`, once placed.
        #: (String name) -> Integer?
        def global(name)
          i, s = @globals[name]
          i && @addr[i][s]
        end

        # Every global and its address, once placed.
        #: () -> Array[[String, Integer?]]
        def exports = @globals.map { |name, (i, s)| [name, @addr[i][s]] }

        # The address of the symbol `name` ("main"): a global, else a local.
        #: (String name) -> Integer?
        def entry(name)
          symbol = "_#{name}"
          return global(symbol) if defines?(symbol)

          @inputs.each_with_index do |o, i|
            o.count.times do |s|
              return @addr[i][s] if (o.type(s) & (N_STAB | N_TYPE)) == N_SECT && o.name(s) == symbol
            end
          end
          nil
        end

        # Every symbol's address, once every part is placed.
        #: () -> void
        def addresses!
          @placed = @inputs.map { |o| Array.new(o.sections.size) }
          @chunks.each do |part, chunks|
            chunks.each { |i, k, off| @placed[i][k] = at(part) + off }
          end
          @addr = @inputs.each_with_index.map do |o, i|
            Array.new(o.count) do |s|
              next unless (o.type(s) & (N_STAB | N_TYPE)) == N_SECT

              k = o.sect(s) - 1
              @placed[i][k] + o.value(s) - o.sections[k].addr
            end
          end
          @links.each_with_index do |links, i|
            links.each do |s, to|
              case to
              when Array then @addr[i][s] = @addr[to[0]][to[1]]
              when Integer then @addr[i][s] = to
              end
            end
          end
          @stub_at = @externals.each_with_index.to_h { |name, n| [name, at(:stubs) + (n * STUB)] }
          @got_at = @got.each_with_index.to_h { |key, n| [key, at(:got) + (n * 8)] }
          @island_at = @islands.each_with_index.to_h { |target, n| [target, at(:text) + @code_size + (n * ISLAND)] }
        end

        # A part's bytes, relocated; nil for `bss`, which has none.
        #: (Symbol part) -> String?
        def bytes(part)
          case part
          when :bss then nil
          when :stubs then stub_bytes
          when :got then got_bytes
          else
            out = +"".b
            @chunks.fetch(part).each do |i, k, off|
              Bytes.pad(out, off)
              # Only a zero-fill section has no bytes, and `bss` holds it.
              section_bytes = @inputs[i].sections[k].bytes #: String
              out << section_bytes
            end
            island_bytes(out) if part == :text
            Bytes.pad(out, size(part))
            @chunks.fetch(part).each { |i, k, off| relocate(part, out, off, i, @inputs[i].sections[k].relocs) }
            out
          end
        end

        # Returns three values:
        # - Every defined symbol as a local `nlist_64` (two words each), at
        #   its address, in the image section that `ordinals` gives for its
        #   part, **sorted by name**.
        # - The names: the string tables of the inputs, one after another,
        #   with offsets from `strings_at`.
        # - The names, in the order of the words.
        # The runtime searches the sorted table in place (`zr_os_symbol`),
        # so an image does not need an exports trie.
        #: (Hash[Symbol, Integer] ordinals, Integer strings_at) -> [Array[Integer?], String, Array[String]]
        def symbols(ordinals, strings_at)
          strings = +"".b
          rows = [] #: Array[[String, Integer, Integer?]]
          @inputs.each_with_index do |o, i|
            base = strings_at + strings.bytesize
            strings << o.strings
            o.count.times do |s|
              next unless (o.type(s) & (N_STAB | N_TYPE)) == N_SECT

              ordinal = ordinals.fetch(@part_of[i][o.sect(s) - 1])
              rows << [o.name(s), (o.strx(s) + base) | (N_SECT << 32) | (ordinal << 40), @addr[i][s]]
            end
          end
          rows.sort_by!(&:first)
          [rows.flat_map { |_, strx, address| [strx, address] }, strings, rows.map(&:first)]
        end

        private

        # Collects the globals that each input defines, then resolves each
        # undefined symbol to `[input, symbol]` (another input's global), an
        # address from `outside`, or an external's name. `@links[input]`
        # contains the result for each undefined symbol. A defined symbol
        # resolves to itself.
        #: () -> void
        def resolve
          @globals = {}
          undefined = [] #: Array[[Integer, Integer]]
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
          externals = {} #: Hash[String, String]
          @links = Array.new(@inputs.size) { {} }
          undefined.each do |i, s|
            name = @inputs[i].name(s)
            @links[i][s] = @globals[name] || @outside&.call(name) || (externals[name] = name.delete_prefix("_"))
          end
          @externals = externals.values.sort
        end

        # The resolved value of symbol `s` of input `i`: `[input, symbol]`,
        # an address, or an external's name.
        #: (Integer i, Integer s) -> untyped
        def meaning(i, s) = @links[i].fetch(s) { [i, s] }

        # One GOT slot for each external, then one for each other symbol
        # whose address some code loads through the GOT.
        #: () -> void
        def got_slots
          @got = @externals.dup
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

        # Finds the part of each input section and its offset in the part.
        # Each section starts at its own alignment. A part uses the largest
        # alignment of its sections.
        #: () -> void
        def chunks
          @chunks = {}
          FROM.each_value { |part| @chunks[part] = [] }
          @sizes = PARTS.to_h { |part| [part, 0] }
          @aligns = PARTS.to_h { |part| [part, 4] }
          @part_of = @inputs.map do |o|
            o.sections.map do |section|
              part = FROM[[section.segment, section.name]]
              if part.nil?
                next if section.size.zero?

                raise Refused, "a #{section.segment},#{section.name} section, which no part of the image holds"
              end
              part
            end
          end
          @inputs.each_with_index do |o, i|
            o.sections.each_with_index do |section, k|
              part = @part_of[i][k] or next
              @aligns[part] = [@aligns[part], section.align].max
              @sizes[part] = Bytes.align(@sizes[part], 1 << section.align) if section.size.positive?
              @chunks[part] << [i, k, @sizes[part]]
              @sizes[part] += section.size
            end
          end
          @sizes[:stubs] = @externals.size * STUB
          @sizes[:got] = @got.size * 8
          @code_size = @sizes[:text]
        end

        # Each address outside the block that a branch in the text calls:
        # the base's functions, which can be too far away for a branch.
        #: () -> void
        def far_calls
          far = {} #: Hash[Integer, bool]
          @inputs.each_with_index do |o, i|
            o.sections.each_with_index do |section, k|
              next unless @part_of[i][k] == :text

              words = section.relocs
              addend = 0
              j = 1
              while j < words.size
                info = words[j]
                j += 2
                type = info >> 28
                if type == ARM64_RELOC_ADDEND
                  addend = ((info & 0xFF_FFFF) ^ 0x80_0000) - 0x80_0000
                  next
                end
                to = @links[i][info & 0xFF_FFFF] if type == BRANCH26 && (info & EXTERN) != 0
                far[to + addend] = true if to.is_a?(Integer)
                addend = 0
              end
            end
          end
          @far = far.keys.sort
          @islands = []
        end

        # With the text at `address`, the far calls that a branch at the
        # far end of the text may not reach, each with an island after the
        # code. The text holds one island for each.
        #: (Integer address) -> void
        def islands(address)
          last = address + @code_size + (@far.size * ISLAND)
          @islands = @far.select { |target| last - target >= BRANCH_REACH || target - address >= BRANCH_REACH }
          @sizes[:text] = @code_size + (@islands.size * ISLAND)
        end

        # Appends the islands to the text's code in `out`.
        #: (String out) -> void
        def island_bytes(out)
          return if @islands.empty?

          Bytes.pad(out, @code_size)
          @islands.each_with_index do |target, n|
            here = at(:text) + @code_size + (n * ISLAND)
            page = ((target & ~0xFFF) - (here & ~0xFFF)) >> 12
            out << [0x9000_0010 | ((page & 3) << 29) | (((page >> 2) & 0x7FFFF) << 5),
                    0x9100_0210 | ((target & 0xFFF) << 10),
                    0xD61F_0200].pack("L<3")
          end
        end

        # Applies the relocations of one input section to its bytes at `off`
        # in `out`. A call to an external goes through its stub, and a GOT
        # load goes through its GOT slot. All other relocations use the
        # symbol's own address. An `abs64` slot becomes a fixup; its addend
        # is the value that the slot contained.
        #: (Symbol part, String out, Integer off, Integer i, Array[Integer] words) -> void
        def relocate(part, out, off, i, words)
          addr = @addr[i]
          base = at(part) + off
          addend = 0
          j = 0
          size = words.size
          while j < size
            at = words[j]
            info = words[j + 1]
            j += 2
            here = off + at
            place = base + at
            type = info >> 28
            if type == ARM64_RELOC_ADDEND
              addend = ((info & 0xFF_FFFF) ^ 0x80_0000) - 0x80_0000
              next
            end
            raise Refused, "a relocation that names a section, not a symbol" if (info & EXTERN).zero?

            s = info & 0xFF_FFFF
            target = addr[s]
            if type == ABS64
              raise Refused, "an absolute relocation in the #{part} part" unless WRITABLE.include?(part)

              held = word(out, here) | (word(out, here + 4) << 32)
              held -= 1 << 64 if held >= 1 << 63
              @fixups << (target ? [place, :rebase, target + held] : [place, :external, @links[i][s], held])
            else
              kind = KINDS[type] or raise Refused, "a relocation of type #{type}"
              if type == GOT_PAGE21 || type == GOT_PAGEOFF12
                target = @got_at.fetch(meaning(i, s))
              elsif type == BRANCH26
                target ||= @stub_at.fetch(@links[i][s])
              elsif target.nil?
                raise Refused, "#{@links[i][s]} has no place in the image"
              end
              patched = Relocs::Aarch64.encode(kind, word(out, here), target + addend, place)
              if patched.nil? && type == BRANCH26 && (island = @island_at[target + addend])
                patched = Relocs::Aarch64.encode(kind, word(out, here), island, place)
              end
              raise Refused, "a #{kind} to #{@inputs[i].name(s).delete_prefix("_")} is out of reach" unless patched

              # One byte at a time, unrolled: a block would cost more than
              # the write, a million times a link.
              out.setbyte(here, patched & 0xFF)
              out.setbyte(here + 1, (patched >> 8) & 0xFF)
              out.setbyte(here + 2, (patched >> 16) & 0xFF)
              out.setbyte(here + 3, (patched >> 24) & 0xFF)
            end
            addend = 0
          end
        end

        # The little-endian word at `at`. A link reads about a million of
        # these. `getbyte` does not allocate, but `unpack` does. In the
        # compiled compiler, each allocation makes the next collection of a
        # large heap occur sooner. RBS gives `getbyte` an `Integer?`; `at`
        # is always inside `bytes`.
        #: (String bytes, Integer at) -> Integer
        def word(bytes, at) # steep:ignore MethodBodyTypeMismatch
          bytes.getbyte(at) | (bytes.getbyte(at + 1) << 8) | (bytes.getbyte(at + 2) << 16) | (bytes.getbyte(at + 3) << 24) # steep:ignore NoMethod
        end

        # One stub for each external. The stub jumps through its GOT slot.
        #: () -> String
        def stub_bytes
          @externals.each_with_index.with_object(+"".b) do |(name, n), out|
            here = at(:stubs) + (n * STUB)
            got = @got_at.fetch(name)
            page = ((got & ~0xFFF) - (here & ~0xFFF)) >> 12
            out << [0x9000_0010 | ((page & 3) << 29) | (((page >> 2) & 0x7FFFF) << 5),
                    0xF940_0210 | (((got & 0xFFF) >> 3) << 10),
                    0xD61F_0200].pack("L<3")
          end
        end

        # One GOT slot for each external, which the image binds or rebases.
        # Then one rebase slot for each other symbol that code loads through
        # the GOT.
        #: () -> String
        def got_bytes
          @got.each_with_index do |key, n|
            slot = at(:got) + (n * 8)
            @fixups << case key
                       when String then [slot, :external, key, 0]
                       when Integer then [slot, :rebase, key]
                       else [slot, :rebase, @addr[key[0]][key[1]]]
                       end
          end
          "\0".b * size(:got)
        end
      end

      # Chained fixups. Each slot that dyld writes contains an entry. The
      # entry gives the next slot on the page and the value for this slot.
      module Chains
        PAGE = 0x4000
        STRIDE = 4
        START_NONE = 0xFFFF

        module_function

        # For the slot addresses `slots` in a segment at `start` with `size`
        # file bytes, returns the start of the chain on each page and the
        # distance (in strides) from each slot to the next. The starts cover
        # only the file bytes, not the zero-fill tail. dyld maps
        # `page_count` pages of the file for the kernel to fix up. A count
        # past the file maps the next segment's bytes over the tail, and the
        # kernel's pager then caches those bytes without fixups.
        #: (Array[Integer] slots, Integer start, Integer size) -> [Array[Integer], Hash[Integer, Integer]]
        def thread(slots, start, size)
          starts = Array.new(Bytes.align(size, PAGE) / PAGE, START_NONE)
          nexts = {} #: Hash[Integer, Integer]
          slots.sort.group_by { |slot| (slot - start) / PAGE }.each do |page, row|
            starts[page] = (row.first - start) % PAGE
            row.each_with_index { |slot, n| nexts[slot] = row[n + 1] ? (row[n + 1] - slot) / STRIDE : 0 }
          end
          [starts, nexts]
        end

        # The slot's target as an offset from the image base. The loader
        # adds the slide to it.
        #: (Integer offset, Integer nxt) -> Integer
        def rebase(offset, nxt) = (offset & ((1 << 36) - 1)) | (nxt << 51)

        #: (Integer ordinal, Integer nxt) -> Integer
        def bind(ordinal, nxt) = (ordinal & 0xFF_FFFF) | (nxt << 51) | (1 << 63)

        # Writes the eight-byte little-endian `word` at `at`, one byte at a
        # time. In the compiled runtime, `bytesplice` copies the full string.
        #: (String bytes, Integer at, Integer word) -> void
        def put(bytes, at, word)
          8.times { |n| bytes.setbyte(at + n, (word >> (8 * n)) & 0xFF) }
        end
      end
    end
  end
end
