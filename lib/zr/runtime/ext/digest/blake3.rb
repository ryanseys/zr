# frozen_string_literal: true

# blake3init.c, in ruby: Digest::BLAKE3 over a port of BLAKE3's portable
# C (blake3.c, blake3_portable.c) in its hash mode, with a 32-byte digest.
require "digest"

module Digest
  class BLAKE3 < Base
    # The BLAKE3 hash in its plain (unkeyed) mode. Its context is
    # [chaining values of the finished subtrees, the chunk's chaining
    # value, the chunk's counter, the bytes of the block in progress,
    # the count of the chunk's compressed blocks].
    module Hasher
      IV = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19].freeze
      PERMUTATION = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8].freeze
      CHUNK_START = 1
      CHUNK_END = 2
      PARENT = 4
      ROOT = 8
      BLOCK_LEN = 64
      CHUNK_LEN = 1024
      MASK = 0xffffffff

      module_function

      # blake3_hasher_init
      def init = [[], IV.dup, 0, "".b, 0]

      def copy(context)
        stack, cv, counter, block, blocks = context
        [stack.map(&:dup), cv.dup, counter, block.dup, blocks]
      end

      # blake3_hasher_update: the input in chunks of 1024 bytes. A full
      # chunk is compressed only when more input follows it.
      def update(context, input)
        at = 0
        while at < input.bytesize
          if chunk_length(context) == CHUNK_LEN
            done = chunk_output(context)
            counter = context[2] + 1
            push_chunk(context, chaining_value(*done), counter)
            context[1] = IV.dup
            context[2] = counter
            context[3] = "".b
            context[4] = 0
          end
          take = [CHUNK_LEN - chunk_length(context), input.bytesize - at].min
          chunk_update(context, input.byteslice(at, take))
          at += take
        end
        context
      end

      # blake3_hasher_finalize: the root's first 32 bytes.
      def finish(context)
        output = chunk_output(context)
        context[0].reverse_each { |left| output = parent_output(left, chaining_value(*output)) }
        cv, words, counter, length, flags = output
        compress(cv, words, counter, length, flags | ROOT)[0, 8].pack("V8")
      end

      def chunk_length(context) = (BLOCK_LEN * context[4]) + context[3].bytesize

      def start_flag(context) = context[4].zero? ? CHUNK_START : 0

      def chunk_update(context, input)
        at = 0
        while at < input.bytesize
          if context[3].bytesize == BLOCK_LEN
            context[1] = compress(context[1], context[3].unpack("V16"), context[2], BLOCK_LEN, start_flag(context))[0, 8]
            context[4] += 1
            context[3] = "".b
          end
          take = [BLOCK_LEN - context[3].bytesize, input.bytesize - at].min
          context[3] << input.byteslice(at, take)
          at += take
        end
      end

      # The chunk's last block, not yet compressed: [cv, words, counter,
      # length, flags].
      def chunk_output(context)
        block = context[3]
        words = (block + ("\0".b * (BLOCK_LEN - block.bytesize))).unpack("V16")
        [context[1], words, context[2], block.bytesize, start_flag(context) | CHUNK_END]
      end

      # hasher_push_cv: merge the subtrees that this chunk completes.
      def push_chunk(context, cv, total)
        stack = context[0]
        while total.even?
          cv = chaining_value(*parent_output(stack.pop, cv))
          total >>= 1
        end
        stack << cv
      end

      def parent_output(left, right) = [IV, left + right, 0, BLOCK_LEN, PARENT]

      def chaining_value(cv, words, counter, length, flags) = compress(cv, words, counter, length, flags)[0, 8]

      # blake3_compress_in_place: seven rounds over the state, then the
      # halves folded together.
      def compress(cv, words, counter, length, flags)
        state = [*cv, IV[0], IV[1], IV[2], IV[3], counter & MASK, (counter >> 32) & MASK, length, flags]
        m = words
        7.times do |round|
          mix(state, m)
          m = PERMUTATION.map { |i| m[i] } if round < 6
        end
        8.times do |i|
          state[i] ^= state[i + 8]
          state[i + 8] ^= cv[i]
        end
        state
      end

      def mix(s, m)
        g(s, 0, 4, 8, 12, m[0], m[1])
        g(s, 1, 5, 9, 13, m[2], m[3])
        g(s, 2, 6, 10, 14, m[4], m[5])
        g(s, 3, 7, 11, 15, m[6], m[7])
        g(s, 0, 5, 10, 15, m[8], m[9])
        g(s, 1, 6, 11, 12, m[10], m[11])
        g(s, 2, 7, 8, 13, m[12], m[13])
        g(s, 3, 4, 9, 14, m[14], m[15])
      end

      def g(s, a, b, c, d, x, y)
        s[a] = (s[a] + s[b] + x) & MASK
        s[d] = rotr(s[d] ^ s[a], 16)
        s[c] = (s[c] + s[d]) & MASK
        s[b] = rotr(s[b] ^ s[c], 12)
        s[a] = (s[a] + s[b] + y) & MASK
        s[d] = rotr(s[d] ^ s[a], 8)
        s[c] = (s[c] + s[d]) & MASK
        s[b] = rotr(s[b] ^ s[c], 7)
      end

      def rotr(x, n) = ((x >> n) | (x << (32 - n))) & MASK
    end
    private_constant :Hasher

    Primitive.zr_hidden_set(self, :metadata, Digest.send(:metadata, nil, 0, 32, 64, true, Hasher))

    # BLAKE3_VERSION_STRING, and the version of the library in use.
    VERSION = "1.8.5"
    LIBRARY_VERSION = VERSION
  end
end
