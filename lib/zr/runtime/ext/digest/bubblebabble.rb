# frozen_string_literal: true

# bubblebabble.c, in ruby: a digest spelled as syllables.
require "digest"

module Digest
  VOWELS = "aeiouy"
  CONSONANTS = "bcdfghklmnprstvzx"
  private_constant :VOWELS, :CONSONANTS

  def self.bubblebabble(str)
    bytes = Primitive.zr_str_operand(str).bytes
    out = +"x"
    seed = 1
    i = 0
    loop do
      if i >= bytes.size
        out << VOWELS[seed % 6] << CONSONANTS[16] << VOWELS[seed / 6]
        break
      end
      byte1 = bytes[i]
      i += 1
      out << VOWELS[(((byte1 >> 6) & 3) + seed) % 6] << CONSONANTS[(byte1 >> 2) & 15] << VOWELS[((byte1 & 3) + (seed / 6)) % 6]
      break if i >= bytes.size

      byte2 = bytes[i]
      i += 1
      out << CONSONANTS[(byte2 >> 4) & 15] << "-" << CONSONANTS[byte2 & 15]
      seed = ((seed * 5) + (byte1 * 7) + byte2) % 36
    end
    (out << "x").b
  end

  # rb_define_module_function: a private instance method too.
  def bubblebabble(str) = Digest.bubblebabble(str)
  private :bubblebabble

  module Instance
    def bubblebabble = Digest.bubblebabble(digest)
  end

  class Class
    def self.bubblebabble(*args) = Digest.bubblebabble(digest(*args))
  end
end
