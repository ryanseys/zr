# frozen_string_literal: true

require "digest/sha2"
require_relative "block"
require_relative "../../bytes"

module Zr
  module Obj
    module MachO
      # The base: the objects that every program of one runtime links
      # against (the runtime and eval support objects). They are linked
      # once, at fixed addresses, and kept in the cache.
      #
      # An image puts the base first: its code and constants in `__TEXT`
      # after the header page, its GOT in `__DATA_CONST`, and its data in
      # `__DATA`. The program's own parts go in `__PROGRAM` (code, after
      # `__TEXT`) and `__DATA_PROGRAM` (data, after `__DATA`).
      # `__DATA_CONST` always starts `RESERVE` bytes after the end of
      # `__TEXT`. Thus all base addresses and relocations are the same in
      # every image, and the program's code is within branch reach of the
      # base's code.
      #
      # Only the slots of the base's externals (`late`) change for each
      # program: a program can define them, or libSystem binds them. A slot
      # contains a chain entry. The chain on each page is the same in every
      # image, so only the entry's target changes.
      class Prelink
        # @rbs @addressed: Hash[String, Integer?]?
        # @rbs @indexed: Hash[String?, Integer]?
        # @rbs @searched: Integer?

        PAGE = 0x4000
        # A code signature hashes pages of this size.
        HASH_PAGE = 4096
        # The image address, above the 4 GB unmapped zero page that makes a
        # null dereference a fault.
        BASE = 0x1_0000_0000
        # The address space for `__PROGRAM` between `__TEXT` and
        # `__DATA_CONST`. A branch reaches 128 MB, so a program that links
        # cannot have more code than this.
        RESERVE = 0x4000_0000
        # The image section number (from one) of each part of the base:
        # three in `__TEXT`, three in `__PROGRAM`, the GOT in
        # `__DATA_CONST`, then three in `__DATA`.
        ORDINALS = { text: 1, stubs: 2, const: 3, got: 7, dconst: 8, data: 9, bss: 10 }.freeze
        MAGIC = "zr prelink 2\n".b
        SEGMENTS = %i[got data].freeze

        # A slot that contains an external's address: its segment, its
        # offset in the segment's bytes, the distance to the next slot's
        # entry, the name, and the addend.
        # @rbs skip -- typed in sig/zr/obj/macho/prelink.rbs
        Late = Data.define(:segment, :offset, :next, :name, :addend)

        # `parts`: the address, size and alignment of each part.
        attr_reader :parts #: Hash[Symbol, [Integer, Integer, Integer]]
        attr_reader :text_size #: Integer
        attr_reader :got_vm #: Integer
        attr_reader :got_size #: Integer
        attr_reader :data_vm #: Integer
        attr_reader :data_filesize #: Integer
        attr_reader :data_vmsize #: Integer
        attr_reader :externals #: Array[String]
        attr_reader :late #: Array[Late]
        attr_reader :starts #: Hash[Symbol, Array[Integer]]
        attr_reader :symbols #: String
        attr_reader :strings #: String
        attr_reader :names #: Array[String] | Names
        attr_reader :addresses #: Array[Integer]
        attr_reader :blobs #: Hash[Symbol, String]
        attr_reader :hashes #: Hash[Symbol, String]

        # Links the objects' bytes. Returns an empty base for no objects.
        #: (Array[String | ObjectFile::Read] objects) -> Prelink
        def self.build(objects)
          return new if objects.empty?

          block = Block.new(objects)
          at = BASE + PAGE
          %i[text stubs const].each { |part| at = place(block, part, at) }
          text_size = Bytes.align(at, PAGE) - BASE
          got_vm = BASE + text_size + RESERVE
          got_size = [Bytes.align(place(block, :got, got_vm) - got_vm, PAGE), PAGE].max
          data_vm = got_vm + got_size
          at = data_vm
          %i[dconst data].each { |part| at = place(block, part, at) }
          data_filesize = [Bytes.align(at - data_vm, PAGE), PAGE].max
          data_vmsize = [Bytes.align(place(block, :bss, at) - data_vm, PAGE), data_filesize].max
          block.addresses!

          spans = { text: [%i[text stubs const], BASE + PAGE, text_size - PAGE], got: [%i[got], got_vm, got_size],
                    data: [%i[dconst data], data_vm, data_filesize] } #: Hash[Symbol, [Array[Symbol], Integer, Integer]]
          blobs = spans.transform_values do |parts, start, size|
            image = parts.each_with_object(+"".b) do |part, out|
              bytes = block.bytes(part) #: String
              Bytes.pad(out, block.at(part) - start) << bytes
            end
            Bytes.pad(image, size)
          end
          # A slot must be in the file bytes. The zero-fill tail has no slots.
          bounds = { got: [got_vm, got_size], data: [data_vm, data_filesize] } #: Hash[Symbol, [Integer, Integer]]
          rows = block.fixups.group_by do |slot, *|
            SEGMENTS.find { |s| slot >= bounds[s][0] && slot < bounds[s][0] + bounds[s][1] } or
              raise Refused, "a fixup outside the data"
          end
          externals = block.externals
          late = [] #: Array[Late]
          starts = SEGMENTS.to_h do |segment|
            start, size = bounds[segment]
            slots = rows.fetch(segment, [])
            chain, nexts = Chains.thread(slots.map(&:first), start, size)
            slots.each do |slot, kind, target, addend|
              offset = slot - start
              if kind == :rebase
                Chains.put(blobs[segment], offset, Chains.rebase(target - BASE, nexts[slot]))
              else
                late << Late.new(segment, offset, nexts[slot], target, addend)
              end
            end
            [segment, chain]
          end
          # The names are in the order of the words. The base's table is
          # sorted by name, and a link uses the names to merge a program's
          # entries into it (`Executable#merged_symbols`).
          words, strings, names = block.symbols(ORDINALS, 0)
          addresses = block.exports.to_h
          globals = names.map { |name| [name, addresses.fetch(name)] }
          parts = Block::PARTS.to_h { |part| [part, [block.at(part), block.size(part), block.align(part)]] }
          new(parts: parts, text_size: text_size, got_vm: got_vm, got_size: got_size, data_vm: data_vm,
              data_filesize: data_filesize, data_vmsize: data_vmsize, externals: externals, late: late,
              starts: starts, symbols: words.pack("Q<*"), strings: strings, names: globals.map(&:first),
              addresses: globals.map(&:last), blobs: blobs, hashes: blobs.transform_values { |b| page_hashes(b) })
        end

        # Places `part` at the first aligned address at or after `at`.
        # Returns the end address.
        #: (Block block, Symbol part, Integer at) -> Integer
        def self.place(block, part, at)
          at = Bytes.align(at, 1 << block.align(part))
          block.place(part, at)
          at + block.size(part)
        end

        # The SHA-256 of each 4 KB page of `bytes`, one after another.
        #: (String bytes) -> String
        def self.page_hashes(bytes)
          (0...((bytes.bytesize + HASH_PAGE - 1) / HASH_PAGE)).each_with_object(+"".b) do |n, out|
            page = bytes.byteslice(n * HASH_PAGE, HASH_PAGE) #: String
            out << Digest::SHA256.digest(page)
          end
        end

        # Joins `strings`, each followed by a zero byte. Every part is
        # binary: in the compiled runtime, appending text of another
        # encoding to a long binary string scans the full string again.
        #: (Array[String] strings) -> String
        def self.joined(strings)
          strings.each_with_object(+"".b) { |string, out| out << string << "\0".b }
        end

        # @rbs parts: Hash[Symbol, [Integer, Integer, Integer]]
        # @rbs text_size: Integer
        # @rbs got_vm: Integer
        # @rbs got_size: Integer
        # @rbs data_vm: Integer
        # @rbs data_filesize: Integer
        # @rbs data_vmsize: Integer
        # @rbs externals: Array[String]
        # @rbs late: Array[Late]
        # @rbs starts: Hash[Symbol, Array[Integer]]
        # @rbs symbols: String
        # @rbs strings: String
        # @rbs names: Array[String] | Names
        # @rbs addresses: Array[Integer]
        # @rbs blobs: Hash[Symbol, String]
        # @rbs hashes: Hash[Symbol, String]
        # @rbs return: void
        def initialize(parts: {}, text_size: 0, got_vm: 0, got_size: 0, data_vm: 0, data_filesize: 0, data_vmsize: 0,
                       externals: [], late: [], starts: {}, symbols: "".b, strings: "".b, names: [], addresses: [],
                       blobs: {}, hashes: {})
          @parts = parts
          @text_size = text_size
          @got_vm = got_vm
          @got_size = got_size
          @data_vm = data_vm
          @data_filesize = data_filesize
          @data_vmsize = data_vmsize
          @externals = externals
          @late = late
          @starts = starts
          @symbols = symbols
          @strings = strings
          @names = names
          @addresses = addresses
          @blobs = blobs
          @hashes = hashes
        end

        #: () -> bool
        def empty? = @parts.empty?

        # The address of the global `name` ("_zr_send"), or nil.
        #
        # This caches each result, not a full table. A link calls this once
        # for each name that it defines or needs, and the runtime has about
        # 250,000 symbols. The search took 12% of a link, and the image stays
        # in memory for the next link, which looks up the same names. A full
        # table would add 33 ms to a single `zr build`, so only a link that
        # has searched `INDEXED_AFTER` names makes one (`search`).
        #: (String name) -> Integer?
        def global(name)
          addressed = @addressed ||= {} #: Hash[String, Integer?]
          addressed.fetch(name) { addressed[name] = search(name) }
        end

        # After this many searches, a Hash of every name is cheaper than
        # the binary searches still to come: a large program (bundler)
        # searches about a hundred thousand names.
        INDEXED_AFTER = 10_000

        #: (String name) -> Integer?
        def search(name)
          if (indexed = @indexed)
            n = indexed[name]
            return n && @addresses[n]
          end
          searched = @searched = (@searched || 0) + 1
          @indexed = @names.to_a.each_with_index.to_h if searched > INDEXED_AFTER
          n = @names.bsearch_index { |candidate| candidate >= name }
          n && @names[n] == name ? @addresses[n] : nil
        end

        #: () -> Integer
        def data_end = @data_vm + @data_vmsize

        # --- the cache ------------------------------------------------------

        # Returns the base as bytes: a magic line, then each field as its
        # size and its bytes.
        #: () -> String
        def dump
          layout = [@text_size, @got_vm, @got_size, @data_vm, @data_filesize, @data_vmsize] +
                   Block::PARTS.flat_map { |part| @parts.fetch(part) }
          late = @late.flat_map { |l| [SEGMENTS.index(l.segment), l.offset, l.next, @externals.index(l.name), l.addend] }
          fields = [layout.pack("q<*"), Prelink.joined(@externals), late.pack("q<*"),
                    @starts.fetch(:got).pack("S<*"), @starts.fetch(:data).pack("S<*"), @symbols, @strings,
                    *Names.dumped(@names), @addresses.pack("Q<*"),
                    *[:text, *SEGMENTS].flat_map { |b| [@blobs.fetch(b), @hashes.fetch(b)] }]
          fields.inject(MAGIC.dup) { |out, field| out << [field.bytesize].pack("Q<") << field }
        end

        # Reads a base that `dump` wrote. Returns nil for other bytes: a
        # truncated cache file or a file of another format is a cache miss.
        #: (String bytes) -> Prelink?
        def self.load(bytes)
          return nil unless bytes.start_with?(MAGIC)

          fields = [] #: Array[String]
          at = MAGIC.bytesize
          while at < bytes.bytesize
            return nil if at + 8 > bytes.bytesize

            head = bytes.byteslice(at, 8) #: String
            size = head.unpack1("Q<") #: Integer
            return nil if at + 8 + size > bytes.bytesize

            field = bytes.byteslice(at + 8, size) #: String
            fields << field
            at += 8 + size
          end
          return nil unless fields.size == 16

          layout = fields[0].unpack("q<*") #: Array[Integer]
          parts = Block::PARTS.each_with_index.to_h { |part, n| [part, layout[6 + (n * 3), 3]] } #: Hash[Symbol, [Integer, Integer, Integer]]
          externals = fields[1].split("\0")
          words = fields[2].unpack("q<*") #: Array[Integer]
          slots = words.each_slice(5) #: Enumerator[[Integer, Integer, Integer, Integer, Integer], Array[Integer]]
          late = slots.map do |segment, offset, nxt, name, addend|
            Late.new(SEGMENTS.fetch(segment), offset, nxt, externals.fetch(name), addend)
          end
          got = fields[3].unpack("S<*") #: Array[Integer]
          data = fields[4].unpack("S<*") #: Array[Integer]
          starts = fields[8].unpack("L<*") #: Array[Integer]
          addresses = fields[9].unpack("Q<*") #: Array[Integer]
          new(parts: parts, text_size: layout[0], got_vm: layout[1], got_size: layout[2], data_vm: layout[3],
              data_filesize: layout[4], data_vmsize: layout[5], externals: externals, late: late,
              starts: { got: got, data: data },
              symbols: fields[5], strings: fields[6], names: Names.new(fields[7], starts),
              addresses: addresses,
              blobs: { text: fields[10], got: fields[12], data: fields[14] },
              hashes: { text: fields[11], got: fields[13], data: fields[15] })
        rescue ArgumentError, IndexError # KeyError is an IndexError
          nil
        end

        # The sorted names of a loaded base, in one string. A link reads a
        # few thousand of them, and a split into 387,000 strings took half
        # of a load of eval support's base. A name is made when it is read.
        class Names
          # The joined names and the offset where each one starts.
          #: (Array[String] | Names names) -> [String, String]
          def self.dumped(names)
            return [names.joined, names.starts.pack("L<*")] if names.is_a?(Names)

            at = 0
            starts = names.map { |name| at.tap { at += name.bytesize + 1 } }
            [Prelink.joined(names), starts.pack("L<*")]
          end

          attr_reader :joined #: String
          attr_reader :starts #: Array[Integer]

          #: (String joined, Array[Integer] starts) -> void
          def initialize(joined, starts)
            @joined = joined
            @starts = starts
          end

          #: () -> Integer
          def size = @starts.size

          #: (Integer n) -> String?
          def [](n)
            return nil unless n >= 0 && n < @starts.size

            from = @starts[n]
            @joined.byteslice(from, (n + 1 < @starts.size ? @starts[n + 1] : @joined.bytesize) - from - 1)
          end

          #: () { (String?) -> bool } -> Integer?
          def bsearch_index(&) = (0...size).bsearch { |n| yield self[n] }

          #: () -> Array[String?]
          def to_a = Array.new(size) { |n| self[n] }
        end
      end
    end
  end
end
