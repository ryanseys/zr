# Array#pack and String#unpack: a template of directives, each with
# an optional count or `*`, over bytes. Integers are little-endian
# unless the directive or a `>` says otherwise; a double is packed
# from its bit halves, a single from those bits rounded to 24 bits.
module Packing
  INTEGERS = { "C" => [1, false], "c" => [1, true], "S" => [2, false], "s" => [2, true], "L" => [4, false], "l" => [4, true],
               "Q" => [8, false], "q" => [8, true], "J" => [8, false], "j" => [8, true], "I" => [4, false], "i" => [4, true],
               "n" => [2, false, :big], "N" => [4, false, :big], "v" => [2, false, :little], "V" => [4, false, :little] }.freeze
  BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".freeze
  private_constant :INTEGERS, :BASE64

  # The template as [directive, count, big?] triples; count is nil
  # for none, :all for `*`.
  def self.directives(template, kind)
    out = []
    i = 0
    while i < template.bytesize
      c = template[i]
      i += 1
      next if c == " " || c == "\n" || c == "\t"

      raise ArgumentError, "unknown #{kind} directive '#{c}' in '#{template}'" unless "CcSsLlQqJjIinNvVUwaAZHhBbmMuxX@dDeEfFgGpP".include?(c)

      big = nil
      native = false
      while i < template.bytesize && "<>_!".include?(template[i])
        big = template[i] == ">" if template[i] == ">" || template[i] == "<"
        native = true if template[i] == "_" || template[i] == "!"
        i += 1
      end
      c = c == "L" ? "Q" : "q" if native && (c == "L" || c == "l")
      count = nil
      if i < template.bytesize && template[i] == "*"
        count = :all
        i += 1
      elsif i < template.bytesize && template[i] >= "0" && template[i] <= "9"
        count = 0
        while i < template.bytesize && template[i] >= "0" && template[i] <= "9"
          count = count * 10 + template[i].to_i
          i += 1
        end
      end
      out << [c, count, big]
    end
    out
  end

  # Quoted printable: a byte outside the printable ASCII range, and
  # `=` itself, become `=XX`; a newline passes through and starts the
  # line again; each line takes `count + 1` characters and ends with a
  # soft break, as does the whole text.
  def self.quoted_printable(bytes, count)
    Primitive.attr! :hidden
    width = (count.nil? || count == :all || count <= 1 ? 72 : count) + 1
    out = "".b
    column = 0
    bytes.each_byte do |byte|
      if byte == 10
        out << "\n"
        column = 0
        next
      end

      piece = byte == 61 || byte < 32 || byte > 126 ? format("=%02X", byte) : byte.chr
      if column + piece.bytesize > width
        out << "=\n"
        column = 0
      end
      out << piece
      column += piece.bytesize
    end
    out << "=\n"
  end

  def self.decode_quoted_printable(text)
    Primitive.attr! :hidden
    out = "".b
    i = 0
    while i < text.bytesize
      if text.getbyte(i) != 61
        out << text.getbyte(i).chr
        i += 1
      elsif text.byteslice(i + 1, 1) == "\n"
        i += 2
      elsif text.byteslice(i + 1, 2) =~ /\A\h\h\z/
        out << text.byteslice(i + 1, 2).to_i(16).chr
        i += 3
      else
        out << "="
        i += 1
      end
    end
    out
  end
  private_class_method :quoted_printable, :decode_quoted_printable

  # The bytes an unpack reads, from `offset` on.
  def self.from(text, offset)
    raise ArgumentError, "offset can't be negative" if offset < 0
    raise ArgumentError, "offset outside of string" if offset > text.bytesize

    text.b.byteslice(offset, text.bytesize - offset) || "".b
  end

  # Uuencoding: a line holds `count` bytes rounded down to a multiple
  # of three, and starts with its own length; each three bytes become
  # four characters of six bits over a space, with a zero as a
  # backquote.
  def self.uuencode(bytes, count)
    Primitive.attr! :hidden
    line = count.nil? || count == :all || count <= 2 ? 45 : [count, 63].min / 3 * 3
    out = +""
    i = 0
    while i < bytes.bytesize
      chunk = bytes.byteslice(i, line)
      out << uuchar(chunk.bytesize)
      j = 0
      while j < chunk.bytesize
        a = chunk.getbyte(j)
        b = chunk.getbyte(j + 1) || 0
        c = chunk.getbyte(j + 2) || 0
        out << uuchar(a >> 2) << uuchar(((a & 3) << 4) | (b >> 4)) << uuchar(((b & 15) << 2) | (c >> 6)) << uuchar(c & 63)
        j += 3
      end
      out << "\n"
      i += line
    end
    out
  end

  def self.uuchar(value)
    Primitive.attr! :hidden
    (value.zero? ? 0x60 : value + 0x20).chr
  end

  def self.uudecode(text)
    Primitive.attr! :hidden
    out = "".b
    text.each_line do |line|
      want = (line.getbyte(0).to_i - 0x20) & 63
      break if want.zero?

      body = line.byteslice(1, line.bytesize - 1).delete("\n")
      j = 0
      while j < body.bytesize && out.bytesize < want
        values = (0..3).map { |k| ((body.getbyte(j + k) || 0x60) - 0x20) & 63 }
        [(values[0] << 2) | (values[1] >> 4), ((values[1] & 15) << 4) | (values[2] >> 2), ((values[2] & 3) << 6) | values[3]].each do |byte|
          out << byte.chr if out.bytesize < want
        end
        j += 4
      end
    end
    out
  end
  private_class_method :uuencode, :uuchar, :uudecode

  # The result is US-ASCII while every directive writes ASCII (`m`, `M`,
  # `u` and none at all), UTF-8 once a `U` widens that, and binary as
  # soon as one directive writes arbitrary bytes.
  def self.pack(items, template)
    out = "".b
    at = 0
    list = directives(template, "pack")
    encoding = list.reduce(Encoding::US_ASCII) do |so_far, (c, _, _)|
      if "mMu".include?(c) then so_far
      elsif c == "U" then so_far == Encoding::US_ASCII ? Encoding::UTF_8 : so_far
      else Encoding::BINARY
      end
    end
    list.each do |c, count, big|
      case c
      when "x"
        out << "\0" * (count == :all ? 0 : (count || 1))
      when "X"
        n = count == :all ? 0 : (count || 1)
        raise ArgumentError, "X outside of string" if n > out.bytesize

        out = out.byteslice(0, out.bytesize - n)
      when "@"
        n = count == :all ? 0 : (count || 0)
        out = n <= out.bytesize ? out.byteslice(0, n) : out + "\0" * (n - out.bytesize)
      when "a", "A", "Z"
        raise ArgumentError, "too few arguments" if at >= items.size

        item = items[at]
        at += 1
        item = "" if item.nil?
        raise TypeError, "no implicit conversion of #{item.class} into String" unless item.is_a?(String)

        out << pack_text(item.b, c, count)
      when "H", "h", "B", "b"
        raise ArgumentError, "too few arguments" if at >= items.size

        item = items[at].to_s
        at += 1
        out << (c == "H" || c == "h" ? pack_hex(item, c == "H", count) : pack_bits(item, c == "B", count))
      when "m"
        raise ArgumentError, "too few arguments" if at >= items.size

        item = items[at]
        at += 1
        out << base64(item.to_s.b, count)
      when "M"
        raise ArgumentError, "too few arguments" if at >= items.size

        item = items[at]
        at += 1
        out << quoted_printable(item.to_s.b, count)
      when "u"
        raise ArgumentError, "too few arguments" if at >= items.size

        item = items[at]
        at += 1
        out << uuencode(item.to_s.b, count)
      when "p", "P"
        raise ArgumentError, "too few arguments" if at >= items.size

        item = items[at]
        at += 1
        out << (item.nil? ? "\0" * 8 : [Primitive.zr_str_bytes_address(Primitive.zr_str_operand(item))].pack("J"))
      when "U"
        each_item(items, at, count) { |item| out << (+"" << Integer(item)).b }
        at += count == :all ? items.size - at : (count || 1)
      when "w"
        each_item(items, at, count) { |item| out << ber(Integer(item)) }
        at += count == :all ? items.size - at : (count || 1)
      when "d", "D", "E", "G"
        each_item(items, at, count) { |item| out << pack_double(Float(item), c == "G") }
        at += count == :all ? items.size - at : (count || 1)
      when "f", "F", "e", "g"
        each_item(items, at, count) { |item| out << pack_single(Float(item), c == "g") }
        at += count == :all ? items.size - at : (count || 1)
      else
        size, _, order = INTEGERS.fetch(c)
        big = order == :big if order
        each_item(items, at, count) do |item|
          raise TypeError, "no implicit conversion of #{item.nil? ? 'nil' : item.class} into Integer" unless item.is_a?(Numeric)

          out << pack_integer(Integer(item), size, big)
        end
        at += count == :all ? items.size - at : (count || 1)
      end
    end
    out.force_encoding(encoding)
  end

  def self.each_item(items, at, count)
    n = count == :all ? items.size - at : (count || 1)
    raise ArgumentError, "too few arguments" if at + n > items.size

    n.times { |i| yield items[at + i] }
  end

  # The low `size` bytes of n in two's complement; a negative n is
  # taken byte by byte so no shift leaves the fixnum range.
  def self.pack_integer(n, size, big)
    bytes = []
    size.times do
      bytes << (n & 255)
      n >>= 8
    end
    bytes.reverse! if big
    out = "".b
    bytes.each { |b| out << b.chr }
    out
  end

  def self.pack_text(item, c, count)
    return item + (c == "Z" ? "\0" : "") if count == :all

    n = count || 1
    item = item.byteslice(0, n)
    item + (c == "A" ? " " : "\0") * (n - item.bytesize)
  end

  def self.pack_hex(text, high_first, count)
    n = count == :all ? text.bytesize : (count || 1)
    out = +""
    i = 0
    while i < n
      first = i < text.bytesize ? hex_value(text.getbyte(i)) : 0
      second = i + 1 < n && i + 1 < text.bytesize ? hex_value(text.getbyte(i + 1)) : 0
      out << (high_first ? (first << 4) | second : (second << 4) | first).chr
      i += 2
    end
    out
  end

  def self.hex_value(b)
    return b - 48 if b >= 48 && b <= 57
    return (b | 32) - 87 if (b | 32) >= 97 && (b | 32) <= 102

    b & 15
  end

  def self.pack_bits(text, high_first, count)
    n = count == :all ? text.bytesize : (count || 1)
    out = +""
    i = 0
    while i < n
      byte = 0
      8.times do |k|
        bit = i + k < n && i + k < text.bytesize ? text.getbyte(i + k) & 1 : 0
        byte |= high_first ? bit << (7 - k) : bit << k
      end
      out << byte.chr
      i += 8
    end
    out
  end

  def self.base64(bytes, count)
    line = count == :all || count.nil? ? 45 : (count == 0 ? nil : count / 3 * 3)
    line = 3 if line == 0
    out = +""
    i = 0
    while i < bytes.bytesize
      chunk = line ? bytes.byteslice(i, line) : bytes
      encoded = +""
      j = 0
      while j < chunk.bytesize
        a = chunk.getbyte(j)
        b = chunk.getbyte(j + 1)
        c = chunk.getbyte(j + 2)
        encoded << BASE64[a >> 2] << BASE64[((a & 3) << 4) | ((b || 0) >> 4)]
        encoded << (b ? BASE64[((b & 15) << 2) | ((c || 0) >> 6)] : "=")
        encoded << (c ? BASE64[c & 63] : "=")
        j += 3
      end
      out << encoded
      out << "\n" if line
      i += line || bytes.bytesize
    end
    out
  end

  def self.ber(n)
    raise ArgumentError, "can't compress negative numbers" if n < 0

    bytes = [n & 127]
    n >>= 7
    while n > 0
      bytes.unshift((n & 127) | 128)
      n >>= 7
    end
    bytes.map(&:chr).join.b
  end

  def self.pack_double(x, big)
    low, high = Primitive.zr_float_halves(x)
    big ? pack_integer(high, 4, true) + pack_integer(low, 4, true) : pack_integer(low, 4, false) + pack_integer(high, 4, false)
  end

  def self.pack_single(x, big)
    pack_integer(single_bits(x), 4, big)
  end

  # A double's bits rounded to IEEE single precision, half to even.
  def self.single_bits(x)
    low, high = Primitive.zr_float_halves(x)
    sign = high >> 31
    exponent = (high >> 20) & 0x7FF
    mantissa = ((high & 0xFFFFF) << 32) | low
    return (sign << 31) | 0x7F800000 | (mantissa == 0 ? 0 : 0x400000) if exponent == 0x7FF

    e = exponent - 1023 + 127
    if exponent == 0
      return sign << 31
    elsif e >= 255
      return (sign << 31) | 0x7F800000
    end
    full = mantissa | (1 << 52)
    shift = 29
    if e <= 0
      shift += 1 - e
      e = 0
      return sign << 31 if shift > 53 + 1
    end
    kept = full >> shift
    rest = full & ((1 << shift) - 1)
    half = 1 << (shift - 1)
    kept += 1 if rest > half || (rest == half && kept.odd?)
    if e == 0
      return (sign << 31) | kept
    end
    kept -= 1 << 23
    if kept >= 1 << 23
      kept -= 1 << 23
      e += 1
      return (sign << 31) | 0x7F800000 if e >= 255
    end
    (sign << 31) | (e << 23) | kept
  end

  def self.unpack(bytes, template, single)
    out = []
    at = 0
    directives(template, "unpack").each do |c, count, big|
      case c
      when "x"
        n = count == :all ? bytes.bytesize - at : (count || 1)
        raise ArgumentError, "x outside of string" if at + n > bytes.bytesize

        at += n
      when "X"
        n = count == :all ? 0 : (count || 1)
        raise ArgumentError, "X outside of string" if n > at

        at -= n
      when "@"
        n = count == :all ? 0 : (count || 0)
        raise ArgumentError, "@ outside of string" if n > bytes.bytesize

        at = n
      when "a", "A", "Z"
        n = count == :all ? bytes.bytesize - at : (count || 1)
        chunk = bytes.byteslice(at, n) || "".b
        if c == "Z"
          stop = chunk.index("\0")
          if stop
            chunk = chunk.byteslice(0, stop)
            n = count == :all ? stop + 1 : n
          end
        end
        if c == "A"
          chunk = chunk.byteslice(0, chunk.bytesize - 1) while chunk.end_with?(" ") || chunk.end_with?("\0")
        end
        out << chunk
        at += n
      when "H", "h"
        n = count == :all ? (bytes.bytesize - at) * 2 : (count || 1)
        out << unpack_hex(bytes, at, n, c == "H")
        at += (n + 1) / 2
      when "B", "b"
        n = count == :all ? (bytes.bytesize - at) * 8 : (count || 1)
        out << unpack_bits(bytes, at, n, c == "B")
        at += (n + 7) / 8
      when "m"
        rest = bytes.byteslice(at, bytes.bytesize - at) || "".b
        out << decode_base64(rest, count == 0)
        at = bytes.bytesize
      when "M"
        rest = bytes.byteslice(at, bytes.bytesize - at) || "".b
        out << decode_quoted_printable(rest)
        at = bytes.bytesize
      when "u"
        rest = bytes.byteslice(at, bytes.bytesize - at) || "".b
        out << uudecode(rest)
        at = bytes.bytesize
      when "p", "P"
        Primitive.zr_unimplemented("String#unpack with the '#{c}' directive, which reads a pointer")
      when "U"
        n = count == :all ? nil : (count || 1)
        text = bytes.dup.force_encoding("UTF-8")
        while (n.nil? || n > 0) && at < bytes.bytesize
          len = Primitive.zr_str_char_len_at_m(text, at)
          char = text.byteslice(at, len)
          raise ArgumentError, "malformed UTF-8 character" if len == 1 && bytes.getbyte(at) >= 128

          out << char.ord
          at += len
          n -= 1 if n
        end
      when "w"
        n = count == :all ? nil : (count || 1)
        while (n.nil? || n > 0) && at < bytes.bytesize
          value = 0
          loop do
            b = bytes.getbyte(at)
            at += 1
            value = (value << 7) | (b & 127)
            break if b < 128 || at >= bytes.bytesize
          end
          out << value
          n -= 1 if n
        end
      when "d", "D", "E", "G"
        each_slot(bytes, at, 8, count, out) { |chunk| unpack_double(chunk, c == "G") }
        at += 8 * (count == :all ? (bytes.bytesize - at) / 8 : (count || 1))
      when "f", "F", "e", "g"
        each_slot(bytes, at, 4, count, out) { |chunk| single_value(unpack_integer(chunk, false, c == "g")) }
        at += 4 * (count == :all ? (bytes.bytesize - at) / 4 : (count || 1))
      else
        size, signed, order = INTEGERS.fetch(c)
        big = order == :big if order
        each_slot(bytes, at, size, count, out) { |chunk| unpack_integer(chunk, signed, big) }
        at += size * (count == :all ? (bytes.bytesize - at) / size : (count || 1))
      end
      break if single && !out.empty?
    end
    out
  end

  def self.each_slot(bytes, at, size, count, out)
    n = count == :all ? (bytes.bytesize - at) / size : (count || 1)
    n.times do |i|
      chunk = bytes.byteslice(at + i * size, size)
      out << (chunk && chunk.bytesize == size ? yield(chunk) : nil)
    end
  end

  def self.unpack_integer(chunk, signed, big)
    size = chunk.bytesize
    n = 0
    i = 0
    while i < size
      n = (n << 8) | chunk.getbyte(big ? i : size - 1 - i)
      i += 1
    end
    n -= 1 << (size * 8) if signed && n >= 1 << (size * 8 - 1)
    n
  end

  def self.unpack_hex(bytes, at, n, high_first)
    out = +""
    n.times do |i|
      b = bytes.getbyte(at + i / 2)
      break if b.nil?

      nibble = (i.even? == high_first) ? b >> 4 : b & 15
      out << nibble.to_s(16)
    end
    out
  end

  def self.unpack_bits(bytes, at, n, high_first)
    out = +""
    n.times do |i|
      b = bytes.getbyte(at + i / 8)
      break if b.nil?

      bit = high_first ? (b >> (7 - i % 8)) & 1 : (b >> (i % 8)) & 1
      out << bit.to_s
    end
    out
  end

  def self.decode_base64(text, strict)
    raise ArgumentError, "invalid base64" if strict && (text.bytesize % 4 != 0 || text.include?("\n"))

    out = "".b
    bits = 0
    have = 0
    text.each_byte do |b|
      value = BASE64.index(b.chr)
      if value.nil?
        raise ArgumentError, "invalid base64" if strict && b != 61
        next
      end
      bits = (bits << 6) | value
      have += 6
      if have >= 8
        have -= 8
        out << ((bits >> have) & 255).chr
        bits &= (1 << have) - 1
      end
    end
    out
  end

  def self.unpack_double(chunk, big)
    low = unpack_integer(chunk.byteslice(big ? 4 : 0, 4), false, big)
    high = unpack_integer(chunk.byteslice(big ? 0 : 4, 4), false, big)
    Primitive.zr_float_of_halves(low, high)
  end

  # The double a single's bits stand for.
  def self.single_value(bits)
    sign = bits >> 31
    exponent = (bits >> 23) & 255
    mantissa = bits & 0x7FFFFF
    if exponent == 255
      high = (sign << 31) | 0x7FF00000 | (mantissa == 0 ? 0 : 0x80000)
      return Primitive.zr_float_of_halves(0, high)
    end
    if exponent == 0
      return Primitive.zr_float_of_halves(0, sign << 31) if mantissa == 0

      exponent = 1
      while mantissa & 0x800000 == 0
        mantissa <<= 1
        exponent -= 1
      end
      mantissa &= 0x7FFFFF
    end
    e = exponent - 127 + 1023
    high = (sign << 31) | (e << 20) | (mantissa >> 3)
    low = (mantissa & 7) << 29
    Primitive.zr_float_of_halves(low, high)
  end
end

class Array
  def pack(template, buffer: nil)
    result = Packing.pack(self, template.to_str)
    buffer ? buffer << result : result
  end
end

class String
  def unpack(template, offset: 0)
    Packing.unpack(Packing.from(self, offset), template.to_str, false)
  end

  def unpack1(template, offset: 0)
    Packing.unpack(Packing.from(self, offset), template.to_str, true).first
  end
end
