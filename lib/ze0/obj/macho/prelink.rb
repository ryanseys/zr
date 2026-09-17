# frozen_string_literal: true

require "digest"
require_relative "block"

module Ze0
  module Obj
    module MachO
      # The objects every program of one runtime links beside -- the
      # runtime's, and the eval road's -- linked once at addresses that no
      # program moves, and kept in the cache.
      #
      # An image puts the base first: its code and constants in `__TEXT`
      # after a page for the header, its GOT in `__DATA_CONST` and its data
      # in `__DATA`. A program's own parts go in segments of their own,
      # `__PROGRAM` for code after `__TEXT` and `__DATA_PROGRAM` for data
      # after `__DATA`. `__DATA_CONST` starts `RESERVE` bytes after
      # `__TEXT` ends, whatever the program's size, so every address in
      # the base is the same in every image, and so is every relocation
      # inside it. The program's code sits next to the base's, within a
      # branch's reach of it.
      #
      # What does change from program to program is kept here to write
      # again: the slots of the base's externals (`late`), which a program
      # may define or libSystem binds. A slot holds a chain entry, and the
      # chain through each page is the same in every image, so only the
      # entry's target changes.
      class Prelink
        PAGE = 0x4000
        # A code signature hashes pages of this size.
        HASH_PAGE = 4096
        # Where the image goes, above the four unmapped gigabytes that make
        # a null dereference a fault.
        BASE = 0x1_0000_0000
        # The address space `__PROGRAM` has between `__TEXT` and
        # `__DATA_CONST`. A branch reaches 128 MB, so no program that links
        # fits more code than this.
        RESERVE = 0x4000_0000
        # The image sections the base's parts are, counting from one:
        # `__TEXT`'s three, `__PROGRAM`'s three, then `__DATA_CONST`'s GOT
        # and `__DATA`'s three.
        ORDINALS = { text: 1, stubs: 2, const: 3, got: 7, dconst: 8, data: 9, bss: 10 }.freeze
        MAGIC = "ze0 prelink 1\n".b
        SEGMENTS = %i[got data].freeze

        # A slot that holds an external's address: in which segment, where
        # in its bytes, the distance to the next slot's entry, the name,
        # and the addend.
        Late = Struct.new(:segment, :offset, :next, :name, :addend)

        attr_reader :parts, :text_size, :got_vm, :got_size, :data_vm, :data_filesize, :data_vmsize,
                    :externals, :late, :starts, :symbols, :strings, :names, :addresses, :blobs, :hashes

        # The objects' bytes, linked. Answers an empty base for no objects.
        def self.build(objects)
          return new if objects.empty?

          block = Block.new(objects)
          at = BASE + PAGE
          %i[text stubs const].each { |part| at = place(block, part, at) }
          text_size = Patch.align(at, PAGE) - BASE
          got_vm = BASE + text_size + RESERVE
          got_size = [Patch.align(place(block, :got, got_vm) - got_vm, PAGE), PAGE].max
          data_vm = got_vm + got_size
          at = data_vm
          %i[dconst data].each { |part| at = place(block, part, at) }
          data_filesize = [Patch.align(at - data_vm, PAGE), PAGE].max
          data_vmsize = [Patch.align(place(block, :bss, at) - data_vm, PAGE), data_filesize].max
          block.addresses!

          blobs = { text: [%i[text stubs const], BASE + PAGE, text_size - PAGE], got: [%i[got], got_vm, got_size],
                    data: [%i[dconst data], data_vm, data_filesize] }.transform_values do |parts, start, size|
            parts.inject(+"".b) { |out, part| pad(out, block.at(part) - start) << block.bytes(part) }.then { |out| pad(out, size) }
          end
          bounds = { got: [got_vm, got_size], data: [data_vm, data_vmsize] }
          rows = block.fixups.group_by do |slot, *|
            SEGMENTS.find { |s| slot >= bounds[s][0] && slot < bounds[s][0] + bounds[s][1] } or
              raise Refused, "a fixup outside the data"
          end
          externals = block.externals
          late = []
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
          words, strings = block.symbols(ORDINALS, 0)
          globals = block.exports.sort_by(&:first)
          parts = Block::PARTS.to_h { |part| [part, [block.at(part), block.size(part), block.align(part)]] }
          new(parts: parts, text_size: text_size, got_vm: got_vm, got_size: got_size, data_vm: data_vm,
              data_filesize: data_filesize, data_vmsize: data_vmsize, externals: externals, late: late,
              starts: starts, symbols: words.pack("Q<*"), strings: strings, names: globals.map(&:first),
              addresses: globals.map(&:last), blobs: blobs, hashes: blobs.transform_values { |b| page_hashes(b) })
        end

        # Places `part` at the first address at or after `at` its alignment
        # allows, and answers where it ends.
        def self.place(block, part, at)
          at = Patch.align(at, 1 << block.align(part))
          block.place(part, at)
          at + block.size(part)
        end

        def self.pad(bytes, to)
          bytes << ("\0".b * (to - bytes.bytesize)) if to > bytes.bytesize
          bytes
        end

        # The SHA-256 of each 4 KB page of `bytes`, one after another.
        def self.page_hashes(bytes)
          (0...((bytes.bytesize + HASH_PAGE - 1) / HASH_PAGE)).each_with_object(+"".b) do |n, out|
            out << Digest::SHA256.digest(bytes.byteslice(n * HASH_PAGE, HASH_PAGE))
          end
        end

        # `strings` one after another, each ended by a zero byte. Every piece
        # is binary: in the compiled runtime, text of another encoding
        # appended to a long binary string reads the whole string again.
        def self.joined(strings)
          strings.each_with_object(+"".b) { |string, out| out << string << "\0".b }
        end

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

        def empty? = @parts.empty?

        # The address of the global `name` ("_zr_send"), or nil.
        def global(name)
          n = @names.bsearch_index { |candidate| candidate >= name }
          n && @names[n] == name ? @addresses[n] : nil
        end

        def data_end = @data_vm + @data_vmsize

        # --- the cache ------------------------------------------------------

        # The base as bytes: a magic line, then each field as its size and
        # its bytes.
        def dump
          layout = [@text_size, @got_vm, @got_size, @data_vm, @data_filesize, @data_vmsize] +
                   Block::PARTS.flat_map { |part| @parts.fetch(part) }
          late = @late.flat_map { |l| [SEGMENTS.index(l.segment), l.offset, l.next, @externals.index(l.name), l.addend] }
          fields = [layout.pack("q<*"), Prelink.joined(@externals), late.pack("q<*"),
                    @starts.fetch(:got).pack("S<*"), @starts.fetch(:data).pack("S<*"), @symbols, @strings,
                    Prelink.joined(@names), @addresses.pack("Q<*"),
                    *SEGMENTS.dup.unshift(:text).flat_map { |b| [@blobs.fetch(b), @hashes.fetch(b)] }]
          fields.inject(MAGIC.dup) { |out, field| out << [field.bytesize].pack("Q<") << field }
        end

        # A base `dump` wrote, or nil for bytes that are not one: a cache
        # file cut short or of another format is a miss, never a guess.
        def self.load(bytes)
          return nil unless bytes.start_with?(MAGIC)

          fields = []
          at = MAGIC.bytesize
          while at < bytes.bytesize
            return nil if at + 8 > bytes.bytesize

            size = bytes.byteslice(at, 8).unpack1("Q<")
            return nil if at + 8 + size > bytes.bytesize

            fields << bytes.byteslice(at + 8, size)
            at += 8 + size
          end
          return nil unless fields.size == 15

          layout = fields[0].unpack("q<*")
          parts = Block::PARTS.each_with_index.to_h { |part, n| [part, layout[6 + (n * 3), 3]] }
          externals = fields[1].split("\0")
          late = fields[2].unpack("q<*").each_slice(5).map do |segment, offset, nxt, name, addend|
            Late.new(SEGMENTS.fetch(segment), offset, nxt, externals.fetch(name), addend)
          end
          new(parts: parts, text_size: layout[0], got_vm: layout[1], got_size: layout[2], data_vm: layout[3],
              data_filesize: layout[4], data_vmsize: layout[5], externals: externals, late: late,
              starts: { got: fields[3].unpack("S<*"), data: fields[4].unpack("S<*") },
              symbols: fields[5], strings: fields[6], names: fields[7].split("\0"), addresses: fields[8].unpack("Q<*"),
              blobs: { text: fields[9], got: fields[11], data: fields[13] },
              hashes: { text: fields[10], got: fields[12], data: fields[14] })
        rescue ArgumentError, IndexError, KeyError
          nil
        end
      end
    end
  end
end
