# frozen_string_literal: true

module Prism
  module Ruby
    # util/pm_constant_pool.c: every name the parser interns, numbered from 1
    # in the order first seen. A constant is a slice of the source (shared),
    # bytes the parser made (owned), or a name from outside the source such
    # as an eval scope's local (constant); a shared insert upgrades an owned
    # entry, and a constant insert upgrades an owned one too.
    #
    # Lookups go through a Hash. The C table's buckets matter only to a dump,
    # which writes owned bytes in bucket order, so `each_bucket` replays the
    # inserts through pm_constant_pool's own hash, sizing and probing.
    class ConstantPool
      SHARED = 0
      OWNED = 1
      CONSTANT = 2

      def initialize(source, capacity)
        @source = source
        @initial_capacity = @capacity = next_power_of_two(capacity)
        # The sizes at which an insert grew the C table, which it checks
        # before looking for the bytes, so a repeated name can grow it too.
        @resizes = []
        @ids = {}
        # [bytes, type, source offset]
        @constants = []
      end

      def size = @constants.size

      # pm_constant_pool_insert_shared
      def insert_shared(start, length)
        insert(@source.byteslice(start, length), SHARED, start)
      end

      # pm_constant_pool_insert_owned
      def insert_owned(bytes) = insert(bytes.b, OWNED, nil)

      # pm_constant_pool_insert_constant
      def insert_constant(bytes) = insert(bytes.b, CONSTANT, nil)

      # pm_constant_pool_find: the id, or 0.
      def find(bytes) = @ids.fetch(bytes.b, 0)

      # The bytes of the constant numbered `id`.
      def bytes(id) = @constants[id - 1][0]

      # Each constant as `[id, bytes, source offset or nil]`, in the order of
      # the C table's buckets.
      def each_bucket
        buckets = replay
        buckets.each do |id|
          next if id.nil?

          bytes, type, start = @constants[id - 1]
          yield id, bytes, type == SHARED ? start : nil
        end
      end

      private

      def insert(bytes, type, start)
        if size >= @capacity / 4 * 3
          @resizes << size
          @capacity *= 2
        end

        if (id = @ids[bytes])
          constant = @constants[id - 1]
          if type != OWNED && constant[1] == OWNED
            constant[1] = type
            constant[2] = start
          end
          return id
        end

        @constants << [bytes, type, start]
        @ids[bytes] = @constants.size
      end

      # pm_constant_pool_hash: djb2 over the bytes, in 32 bits.
      def hash_of(bytes)
        bytes.each_byte.reduce(5381) { |value, byte| ((value << 5) + value + byte) & 0xFFFF_FFFF }
      end

      def next_power_of_two(value)
        return 1 if value.zero?

        1 << (value - 1).bit_length
      end

      # The bucket array the C inserts leave, grown where they grew it; a
      # resize walks the old buckets in index order.
      def replay
        buckets = Array.new(@initial_capacity)
        hashes = @constants.map { |bytes, _, _| hash_of(bytes) }
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
