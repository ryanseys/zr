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
        MAGIC = "zr prelink 1\n".b
        SEGMENTS = %i[got data].freeze

        # A slot that contains an external's address: its segment, its
        # offset in the segment's bytes, the distance to the next slot's
        # entry, the name, and the addend.
        Late = ::Data.define(:segment, :offset, :next, :name, :addend)

        attr_reader :parts, :text_size, :got_vm, :got_size, :data_vm, :data_filesize, :data_vmsize,
                    :externals, :late, :starts, :symbols, :strings, :names, :addresses, :blobs, :hashes

        # Links the objects' bytes. Returns an empty base for no objects.
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

          blobs = { text: [%i[text stubs const], BASE + PAGE, text_size - PAGE], got: [%i[got], got_vm, got_size],
                    data: [%i[dconst data], data_vm, data_filesize] }.transform_values do |parts, start, size|
            parts.inject(+"".b) { |out, part| Bytes.pad(out, block.at(part) - start) << block.bytes(part) }.then { |out| Bytes.pad(out, size) }
          end
          # A slot must be in the file bytes. The zero-fill tail has no slots.
          bounds = { got: [got_vm, got_size], data: [data_vm, data_filesize] }
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
        def self.place(block, part, at)
          at = Bytes.align(at, 1 << block.align(part))
          block.place(part, at)
          at + block.size(part)
        end

        # The SHA-256 of each 4 KB page of `bytes`, one after another.
        def self.page_hashes(bytes)
          (0...((bytes.bytesize + HASH_PAGE - 1) / HASH_PAGE)).each_with_object(+"".b) do |n, out|
            out << Digest::SHA256.digest(bytes.byteslice(n * HASH_PAGE, HASH_PAGE))
          end
        end

        # Joins `strings`, each followed by a zero byte. Every part is
        # binary: in the compiled runtime, appending text of another
        # encoding to a long binary string scans the full string again.
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
        #
        # This caches each result, not a full table. A link calls this once
        # for each name that it defines or needs, and the runtime has about
        # 250,000 symbols. The search took 12% of a link, and the image stays
        # in memory for the next link, which looks up the same names. A full
        # table would add 33 ms to a single `zr build`.
        def global(name)
          @addressed ||= {}
          @addressed.fetch(name) { @addressed[name] = search(name) }
        end

        def search(name)
          n = @names.bsearch_index { |candidate| candidate >= name }
          n && @names[n] == name ? @addresses[n] : nil
        end

        def data_end = @data_vm + @data_vmsize

        # --- the cache ------------------------------------------------------

        # Returns the base as bytes: a magic line, then each field as its
        # size and its bytes.
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

        # Reads a base that `dump` wrote. Returns nil for other bytes: a
        # truncated cache file or a file of another format is a cache miss.
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
        rescue ArgumentError, IndexError # KeyError is an IndexError
          nil
        end
      end
    end
  end
end
