# frozen_string_literal: true

# The encodings whose longest characters follow a rule rather than a
# table: GB18030's four-byte characters, which count through Unicode in
# order, CESU-8's six-byte pairs of surrogates, and IBM037, which contains
# the bytes of ISO-8859-1 in EBCDIC order.
class Encoding
  RULED = ["GB18030", "CESU-8"].freeze

  # The tables of GB18030's runs and IBM037's bytes are generated, in
  # cjk.rb. EBCDIC holds IBM037's two tables once a conversion reads them.
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
