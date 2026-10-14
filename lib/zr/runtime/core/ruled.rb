# frozen_string_literal: true

# The encodings whose longest characters follow a rule rather than a
# table: GB18030's four-byte characters, which count through Unicode in
# order, CESU-8's six-byte pairs of surrogates, and IBM037, which contains
# the bytes of ISO-8859-1 in EBCDIC order.
class Encoding
  RULED = ["GB18030", "CESU-8"].freeze

  # The runs of BMP characters GB18030 writes in four bytes: each run's
  # first code point, the four-byte count it starts at, and its length.
  # Generated from ruby's own GB18030 converter.
  GB18030_RUNS = [
    128, 0, 36, 165, 36, 2, 169, 38, 7, 178, 45, 5, 184, 50, 31, 216, 81, 8,
    226, 89, 6, 235, 95, 1, 238, 96, 4, 244, 100, 3, 248, 103, 1, 251, 104, 1,
    253, 105, 4, 258, 109, 17, 276, 126, 7, 284, 133, 15, 300, 148, 24, 325, 172, 3,
    329, 175, 4, 334, 179, 29, 364, 208, 98, 463, 306, 1, 465, 307, 1, 467, 308, 1,
    469, 309, 1, 471, 310, 1, 473, 311, 1, 475, 312, 1, 477, 313, 28, 506, 341, 87,
    594, 428, 15, 610, 443, 101, 712, 544, 1, 716, 545, 13, 730, 558, 183, 930, 741, 1,
    938, 742, 7, 962, 749, 1, 970, 750, 55, 1026, 805, 14, 1104, 819, 1, 1106, 820, 7102,
    8209, 7922, 2, 8215, 7924, 1, 8218, 7925, 2, 8222, 7927, 7, 8231, 7934, 9, 8241, 7943, 1,
    8244, 7944, 1, 8246, 7945, 5, 8252, 7950, 112, 8365, 8062, 86, 8452, 8148, 1, 8454, 8149, 3,
    8458, 8152, 12, 8471, 8164, 10, 8482, 8174, 62, 8556, 8236, 4, 8570, 8240, 22, 8596, 8262, 2,
    8602, 8264, 110, 8713, 8374, 6, 8720, 8380, 1, 8722, 8381, 3, 8726, 8384, 4, 8731, 8388, 2,
    8737, 8390, 2, 8740, 8392, 1, 8742, 8393, 1, 8748, 8394, 2, 8751, 8396, 5, 8760, 8401, 5,
    8766, 8406, 10, 8777, 8416, 3, 8781, 8419, 5, 8787, 8424, 13, 8802, 8437, 2, 8808, 8439, 6,
    8816, 8445, 37, 8854, 8482, 3, 8858, 8485, 11, 8870, 8496, 25, 8896, 8521, 82, 8979, 8603, 333,
    9322, 8936, 10, 9372, 8946, 100, 9548, 9046, 4, 9588, 9050, 13, 9616, 9063, 3, 9622, 9066, 10,
    9634, 9076, 16, 9652, 9092, 8, 9662, 9100, 8, 9672, 9108, 3, 9676, 9111, 2, 9680, 9113, 18,
    9702, 9131, 31, 9735, 9162, 2, 9738, 9164, 54, 9793, 9218, 1, 9795, 9219, 2110, 11906, 11329, 2,
    11909, 11331, 3, 11913, 11334, 2, 11917, 11336, 10, 11928, 11346, 15, 11944, 11361, 2, 11947, 11363, 3,
    11951, 11366, 4, 11956, 11370, 2, 11960, 11372, 3, 11964, 11375, 14, 11979, 11389, 293, 12284, 11682, 4,
    12292, 11686, 1, 12312, 11687, 5, 12319, 11692, 2, 12330, 11694, 20, 12351, 11714, 2, 12436, 11716, 7,
    12447, 11723, 2, 12535, 11725, 5, 12543, 11730, 6, 12586, 11736, 246, 12842, 11982, 7, 12850, 11989, 113,
    12964, 12102, 234, 13200, 12336, 12, 13215, 12348, 2, 13218, 12350, 34, 13253, 12384, 9, 13263, 12393, 2,
    13267, 12395, 2, 13270, 12397, 113, 13384, 12510, 43, 13428, 12553, 298, 13727, 12851, 111, 13839, 12962, 11,
    13851, 12973, 765, 14617, 13738, 85, 14703, 13823, 96, 14801, 13919, 14, 14816, 13933, 147, 14964, 14080, 218,
    15183, 14298, 287, 15471, 14585, 113, 15585, 14698, 885, 16471, 15583, 264, 16736, 15847, 471, 17208, 16318, 116,
    17325, 16434, 4, 17330, 16438, 43, 17374, 16481, 248, 17623, 16729, 373, 17997, 17102, 20, 18018, 17122, 193,
    18212, 17315, 5, 18218, 17320, 82, 18301, 17402, 16, 18318, 17418, 441, 18760, 17859, 50, 18811, 17909, 2,
    18814, 17911, 4, 18820, 17915, 1, 18823, 17916, 20, 18844, 17936, 3, 18848, 17939, 22, 18872, 17961, 703,
    19576, 18664, 39, 19620, 18703, 111, 19738, 18814, 148, 19887, 18962, 81, 40870, 19043, 14426, 59244, 33469, 1,
    59336, 33470, 1, 59367, 33471, 13, 59413, 33484, 1, 59417, 33485, 5, 59423, 33490, 7, 59431, 33497, 4,
    59437, 33501, 4, 59443, 33505, 8, 59452, 33513, 7, 59460, 33520, 16, 59478, 33536, 14, 59493, 33550, 4295,
    63789, 37845, 76, 63866, 37921, 27, 63894, 37948, 81, 63976, 38029, 9, 63986, 38038, 26, 64016, 38064, 1,
    64018, 38065, 1, 64021, 38066, 3, 64025, 38069, 6, 64034, 38075, 1, 64037, 38076, 2, 64042, 38078, 1030,
    65074, 39108, 1, 65093, 39109, 4, 65107, 39113, 1, 65112, 39114, 1, 65127, 39115, 1, 65132, 39116, 149,
    65375, 39265, 129, 65510, 39394, 26
  ].each_slice(3).to_a.freeze
  # The four-byte count of U+10000, where the supplementary planes start.
  GB18030_PLANES = 189_000

  # The ISO-8859-1 byte that each IBM037 byte represents, by position, in hex: the core
  # library reads this file before Array#pack is defined.
  EBCDIC_HEX = ("000102039c09867f978d8e0b0c0d0e0f101112139d8508871819928f1c1d1e1f"             "80818283840a171b88898a8b8c050607909116939495960498999a9b14159e1a"             "20a0e2e4e0e1e3e5e7f1a22e3c282b7c26e9eaebe8edeeefecdf21242a293bac"             "2d2fc2c4c0c1c3c5c7d1a62c255f3e3ff8c9cacbc8cdcecfcc603a2340273d22"             "d8616263646566676869abbbf0fdfeb1b06a6b6c6d6e6f707172aabae6b8c6a4"             "b57e737475767778797aa1bfd0dddeae5ea3a5b7a9a7b6bcbdbe5b5dafa8b4d7"             "7b414243444546474849adf4f6f2f3f57d4a4b4c4d4e4f505152b9fbfcf9faff"             "5cf7535455565758595ab2d4d6d2d3d530313233343536373839b3dbdcd9da9f").freeze
  EBCDIC = []
  private_constant :RULED, :GB18030_RUNS, :GB18030_PLANES, :EBCDIC_HEX, :EBCDIC

  def self.ruled?(encoding)
    Primitive.attr! :hidden
    Primitive.zr_table_member_p(RULED, encoding.name)
  end

  # The character at `at` that the rule reads, as [UTF-8 text, width],
  # or nil where the rows read those bytes.
  def self.ruled_char(bytes, at, from, path, options)
    Primitive.attr! :hidden
    read = -> { from.name == +"GB18030" ? gb18030_char(bytes, at, from, path, options) : cesu8_char(bytes, at, from) }
    return read.call unless options[:invalid] == :replace

    begin
      read.call
    rescue InvalidByteSequenceError => e
      # The bytes the error names become the mark; the ones it would
      # read again stay to be read.
      [send(:replacement, UTF_8, options), e.error_bytes.bytesize]
    end
  end

  def self.gb18030_char(bytes, at, from, path, options)
    Primitive.attr! :hidden
    return nil unless bytes[at].between?(0x81, 0xFE) && bytes[at + 1]&.between?(0x30, 0x39)

    ruled_bytes_or_stop(bytes, at, 4, from) { |byte, i| i.even? ? byte.between?(0x81, 0xFE) : byte.between?(0x30, 0x39) }
    first, second, third, fourth = bytes[at, 4]
    count = (((((first - 0x81) * 10) + (second - 0x30)) * 126 + (third - 0x81)) * 10) + (fourth - 0x30)
    point = if count >= GB18030_PLANES
              count - GB18030_PLANES + 0x10000
            else
              run = GB18030_RUNS.find { |_start, from_count, length| count >= from_count && count < from_count + length }
              run && run[0] + count - run[1]
            end
    return [point.chr(UTF_8), 4] if point && point <= 0x10FFFF

    whole = bytes[at, 4].pack("C*")
    send(:undefined, whole.dump, from, UTF_8, path, options, whole.dup.force_encoding(from)) { |mark| return [mark, 4] }
  end

  # A CESU-8 character of three bytes: a BMP character as UTF-8 writes
  # it, or a high surrogate that a low one of three more bytes follows.
  def self.cesu8_char(bytes, at, from)
    Primitive.attr! :hidden
    first = bytes[at]
    return nil unless first.between?(0xE0, 0xEF)

    second = bytes[at + 1]
    send(:invalid, [first], [second], false, from.name) if second && first == 0xED && second.between?(0xB0, 0xBF)
    ruled_bytes_or_stop(bytes, at, 3, from) { |byte, i| i.zero? || byte.between?(first == 0xE0 && i == 1 ? 0xA0 : 0x80, 0xBF) }
    point = ((first & 0x0F) << 12) | ((bytes[at + 1] & 0x3F) << 6) | (bytes[at + 2] & 0x3F)
    return [point.chr(UTF_8), 3] unless point.between?(0xD800, 0xDBFF)

    low = bytes[at + 3]
    send(:invalid, bytes[at, 3], nil, true, from.name) if low.nil?
    send(:invalid, bytes[at, 3], [low], false, from.name) unless low == 0xED
    ruled_bytes_or_stop(bytes, at + 3, 3, from) { |byte, i| i.zero? || byte.between?(i == 1 ? 0xB0 : 0x80, 0xBF) }
    rest = ((bytes[at + 4] & 0x3F) << 6) | (bytes[at + 5] & 0x3F)
    [(0x10000 + ((point - 0xD800) << 10) + (rest & 0x3FF)).chr(UTF_8), 6]
  end

  # The `width` bytes at `at`, each of which the block takes, or ruby's
  # stop where one is missing or wrong.
  def self.ruled_bytes_or_stop(bytes, at, width, from)
    Primitive.attr! :hidden
    width.times do |i|
      byte = bytes[at + i]
      send(:invalid, bytes[at, i], nil, true, from.name) if byte.nil?
      send(:invalid, bytes[at, i], [byte], false, from.name) unless yield(byte, i)
    end
  end

  # The bytes the rule writes for `point`, or nil where it writes none.
  def self.ruled_bytes(point, target)
    Primitive.attr! :hidden
    return cesu8_bytes(point) if target.name == +"CESU-8"

    count = if point >= 0x10000
              point - 0x10000 + GB18030_PLANES
            else
              run = GB18030_RUNS.find { |start, _count, length| point >= start && point < start + length }
              run && run[1] + point - run[0]
            end
    return nil if count.nil?

    fourth = (count % 10) + 0x30
    count /= 10
    third = (count % 126) + 0x81
    count /= 126
    [(count / 10) + 0x81, (count % 10) + 0x30, third, fourth]
  end

  # A BMP character as UTF-8 writes it; any other as its two surrogates,
  # three bytes each.
  def self.cesu8_bytes(point)
    Primitive.attr! :hidden
    return point.chr(UTF_8).bytes if point < 0x10000

    offset = point - 0x10000
    [0xD800 + (offset >> 10), 0xDC00 + (offset & 0x3FF)].map do |unit|
      [0xE0 | (unit >> 12), 0x80 | ((unit >> 6) & 0x3F), 0x80 | (unit & 0x3F)]
    end.flatten(1)
  end

  # IBM037 as ISO-8859-1 in EBCDIC order: UTF-8 `text` into IBM037
  # through ISO-8859-1, and IBM037 `text` back into ISO-8859-1.
  def self.ebcdic_write(text, target, options)
    Primitive.attr! :hidden
    latin = send(:from_utf8, text, ISO_8859_1, [UTF_8, ISO_8859_1, target], options)
    latin.bytes.map { |byte| ebcdic[1].getbyte(byte) }.pack("C*").force_encoding(target)
  end

  def self.ebcdic_read(text)
    Primitive.attr! :hidden
    text.bytes.map { |byte| ebcdic[0].getbyte(byte) }.pack("C*").force_encoding(ISO_8859_1)
  end

  # The two tables: ISO-8859-1's byte by IBM037's, and back.
  def self.ebcdic
    Primitive.attr! :hidden
    EBCDIC[0] ||= begin
      bytes = [EBCDIC_HEX].pack("H*")
      codes = bytes.bytes
      order = Array.new(codes.size) { |i| i }.sort! { |a, b| [codes[a], a] <=> [codes[b], b] }
      [bytes, order.pack("C*")]
    end
  end
  private_class_method :ruled?, :ruled_char, :gb18030_char, :cesu8_char, :ruled_bytes_or_stop, :ruled_bytes, :cesu8_bytes,
                       :ebcdic_write, :ebcdic_read, :ebcdic
end
