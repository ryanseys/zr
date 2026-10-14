# frozen_string_literal: true
# shareable_constant_value: literal

module Prism
  module Ruby
    # constant_pool.c: every name the parser interns, numbered from 1 in
    # the order first seen. A constant is a slice of the source (shared),
    # bytes the parser made (owned), or a name from outside the source such
    # as an eval scope's local (constant). Only its bytes reach a result.
    #
    # Lookups go through a Hash. The C table's buckets matter only to a dump,
    # which writes each constant's bytes in bucket order, so `each_bucket`
    # replays the inserts through pm_constant_pool's own hash, sizing and
    # probing.
    class ConstantPool
      # The odd multiplier of pm_constant_pool_hash, from wyhash.
      SECRET = 0x517cc1b727220a95
      MASK64 = (1 << 64) - 1

      def initialize(source, capacity)
        @source = source
        @initial_capacity = @capacity = next_power_of_two(capacity)
        # The sizes at which an insert grew the C table, which it checks
        # before looking for the bytes, so a repeated name can grow it too.
        @resizes = []
        @ids = {}
        # The bytes of each constant, by id - 1.
        @constants = []
      end

      def size = @constants.size

      # pm_constant_pool_insert_shared
      def insert_shared(start, length) = insert(@source.byteslice(start, length))

      # pm_constant_pool_insert_owned
      def insert_owned(bytes) = insert(bytes.b)

      # pm_constant_pool_insert_constant
      def insert_constant(bytes) = insert(bytes.b)

      # pm_constant_pool_find: the id, or 0.
      def find(bytes) = @ids.fetch(bytes.b, 0)

      # The bytes of the constant numbered `id`.
      def bytes(id) = @constants[id - 1]

      # Each constant as `[id, bytes]`, in the order of the C table's
      # buckets.
      def each_bucket
        replay.each { |id| yield id, @constants[id - 1] unless id.nil? }
      end

      private

      def insert(bytes)
        if size >= @capacity / 4 * 3
          @resizes << size
          @capacity *= 2
        end

        @ids[bytes] ||= (@constants << bytes).size
      end

      # pm_constant_pool_hash: the length, then the bytes as little-endian
      # words, each mixed in with a multiply; a short name reads its first
      # and last four or eight bytes, which may overlap.
      def hash_of(bytes)
        length = bytes.bytesize
        hash = length
        if length <= 8
          if length >= 4
            hash ^= bytes.unpack1("L<") | (bytes.unpack1("L<", offset: length - 4) << 32)
          elsif length.positive?
            hash ^= bytes.getbyte(0) | (bytes.getbyte(length >> 1) << 8) | (bytes.getbyte(length - 1) << 16)
          end
          hash = (hash * SECRET) & MASK64
        else
          words = length <= 16 ? [0] : (0..(length - 8)).step(8).to_a
          words << length - 8 if length <= 16 || (length % 8).nonzero?
          words.each { |at| hash = ((hash ^ bytes.unpack1("Q<", offset: at)) * SECRET) & MASK64 }
        end
        (hash ^ (hash >> 32)) & 0xFFFF_FFFF
      end

      def next_power_of_two(value)
        return 1 if value.zero?

        1 << (value - 1).bit_length
      end

      # The bucket array the C inserts leave, grown where they grew it; a
      # resize walks the old buckets in index order.
      def replay
        buckets = Array.new(@initial_capacity)
        hashes = @constants.map { |bytes| hash_of(bytes) }
        resizes = @resizes.dup
        (0..@constants.size).each do |index|
          while resizes.first == index
            resizes.shift
            grown = Array.new(buckets.size * 2)
            buckets.each { |id| place(grown, hashes[id - 1], id) unless id.nil? }
            buckets = grown
          end
          place(buckets, hashes[index], index + 1) if index < @constants.size
        end
        buckets
      end

      def place(buckets, hash, id)
        mask = buckets.size - 1
        slot = hash & mask
        slot = (slot + 1) & mask until buckets[slot].nil?
        buckets[slot] = id
      end
    end
  end
end
