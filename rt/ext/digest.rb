# frozen_string_literal: true

# The message digests ruby ships as a C extension, in ruby. Each class
# holds the message until it is asked for the digest, which is what the
# `Digest::Instance` protocol allows and what every caller here does.
module Digest
  module Instance
    def update(text)
      @buffer << text.to_str.b
      self
    end

    alias << update

    def reset
      @buffer = +"".b
      self
    end

    def digest(text = nil)
      return self.class.new.update(text).digest if text

      finish(@buffer)
    end

    def digest!
      out = digest
      reset
      out
    end

    def hexdigest(text = nil) = digest(text).unpack1("H*")

    def hexdigest!
      out = hexdigest
      reset
      out
    end

    alias to_s hexdigest

    def base64digest(text = nil) = [digest(text)].pack("m0")

    def length = digest_length

    alias size length

    def ==(other) = other.is_a?(Digest::Instance) ? digest == other.digest : to_s == other.to_s

    def inspect = "#<#{self.class.name}: #{hexdigest}>"

    def file(name)
      update(File.binread(name))
    end
  end

  class Class
    include Instance

    def initialize = reset

    def initialize_copy(other)
      super
      @buffer = other.buffer.dup
      self
    end

    protected

    attr_reader :buffer

    class << self
      def digest(text) = new.update(text).digest

      def hexdigest(text) = new.update(text).hexdigest

      def base64digest(text) = new.update(text).base64digest

      def file(name) = new.file(name)
    end
  end

  # The padding every one of these shares: a 1 bit, zeros, then the
  # message length in bits as a 64-bit word.
  module Pad
    module_function

    def big(text)
      len = text.bytesize
      text + "\x80".b + ("\0".b * ((55 - len) % 64)) + [len * 8].pack("Q>")
    end

    def little(text)
      len = text.bytesize
      text + "\x80".b + ("\0".b * ((55 - len) % 64)) + [len * 8].pack("Q<")
    end
  end

  MASK32 = 0xffffffff

  module_function

  def rotr(x, n) = ((x >> n) | (x << (32 - n))) & MASK32

  def rotl(x, n) = ((x << n) | (x >> (32 - n))) & MASK32

  class SHA2Base < Class
    K = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ].freeze

    def block_length = 64

    private

    def finish(text)
      h = self.class::INIT.dup
      Pad.big(text).unpack("N*").each_slice(16) { |block| h = round(h, block) }
      h.pack("N*").byteslice(0, digest_length)
    end

    def round(h, block)
      w = block.dup
      (16..63).each do |i|
        s0 = Digest.rotr(w[i - 15], 7) ^ Digest.rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
        s1 = Digest.rotr(w[i - 2], 17) ^ Digest.rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
        w << ((w[i - 16] + s0 + w[i - 7] + s1) & MASK32)
      end
      a, b, c, d, e, f, g, hh = h
      64.times do |i|
        s1 = Digest.rotr(e, 6) ^ Digest.rotr(e, 11) ^ Digest.rotr(e, 25)
        t1 = (hh + s1 + ((e & f) ^ (~e & g)) + K[i] + w[i]) & MASK32
        s0 = Digest.rotr(a, 2) ^ Digest.rotr(a, 13) ^ Digest.rotr(a, 22)
        t2 = (s0 + ((a & b) ^ (a & c) ^ (b & c))) & MASK32
        hh = g
        g = f
        f = e
        e = (d + t1) & MASK32
        d = c
        c = b
        b = a
        a = (t1 + t2) & MASK32
      end
      [a, b, c, d, e, f, g, hh].each_with_index.map { |v, i| (h[i] + v) & MASK32 }
    end
  end

  class SHA256 < SHA2Base
    INIT = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19].freeze

    def digest_length = 32
  end

  class SHA224 < SHA2Base
    INIT = [0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939, 0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4].freeze

    def digest_length = 28
  end

  class SHA1 < Class
    INIT = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0].freeze

    def digest_length = 20

    def block_length = 64

    private

    def finish(text)
      h = INIT.dup
      Pad.big(text).unpack("N*").each_slice(16) { |block| h = round(h, block) }
      h.pack("N*")
    end

    def round(h, block)
      w = block.dup
      (16..79).each { |i| w << Digest.rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1) }
      a, b, c, d, e = h
      80.times do |i|
        f, k = case i / 20
               when 0 then [(b & c) | (~b & d), 0x5a827999]
               when 1 then [b ^ c ^ d, 0x6ed9eba1]
               when 2 then [(b & c) | (b & d) | (c & d), 0x8f1bbcdc]
               else [b ^ c ^ d, 0xca62c1d6]
               end
        t = (Digest.rotl(a, 5) + f + e + k + w[i]) & MASK32
        e = d
        d = c
        c = Digest.rotl(b, 30)
        b = a
        a = t
      end
      [a, b, c, d, e].each_with_index.map { |v, i| (h[i] + v) & MASK32 }
    end
  end

  class MD5 < Class
    S = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
         5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
         4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
         6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21].freeze
    K = (0..63).map { |i| (Math.sin(i + 1).abs * (2**32)).floor & MASK32 }.freeze
    INIT = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476].freeze

    def digest_length = 16

    def block_length = 64

    private

    def finish(text)
      h = INIT.dup
      Pad.little(text).unpack("V*").each_slice(16) { |block| h = round(h, block) }
      h.pack("V*")
    end

    def round(h, w)
      a, b, c, d = h
      64.times do |i|
        f, g = case i / 16
               when 0 then [(b & c) | (~b & d), i]
               when 1 then [(d & b) | (~d & c), ((5 * i) + 1) % 16]
               when 2 then [b ^ c ^ d, ((3 * i) + 5) % 16]
               else [c ^ (b | (~d & MASK32)), (7 * i) % 16]
               end
        f = (f + a + K[i] + w[g]) & MASK32
        a = d
        d = c
        c = b
        b = (b + Digest.rotl(f, S[i])) & MASK32
      end
      [a, b, c, d].each_with_index.map { |v, i| (h[i] + v) & MASK32 }
    end
  end
end
