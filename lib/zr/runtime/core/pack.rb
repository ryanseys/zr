# frozen_string_literal: true

# Array#pack and String#unpack: a template of directives, each with
# an optional count or `*`, over bytes. Integers are little-endian
# unless the directive or a `>` says otherwise; a double is packed
# from its bit halves, a single from those bits rounded to 24 bits.
module Packing
  Primitive.attr! :hidden

  INTEGERS = { "C" => [1, false], "c" => [1, true], "S" => [2, false], "s" => [2, true], "L" => [4, false], "l" => [4, true],
               "Q" => [8, false], "q" => [8, true], "J" => [8, false], "j" => [8, true], "I" => [4, false], "i" => [4, true],
               "n" => [2, false, :big], "N" => [4, false, :big], "v" => [2, false, :little], "V" => [4, false, :little] }.freeze
  BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".freeze
  private_constant :INTEGERS, :BASE64

  # The directives a template may name, the bytes a space is written
  # with, the modifiers that follow a directive, and the star and the
  # digits a count is written in.
  KNOWN = "CcSsLlQqJjIinNvVUwRraAZHhBbmMuxX@dDeEfFgGpP^".freeze
  SPACE = [32, 9, 10, 11, 12, 13].freeze
  NATIVE = "sSiIlLqQjJ".freeze
  MODIFIERS = [60, 62, 95, 33].freeze     # < > _ !
  STAR = 42
  LONG_MAX = 0x7FFF_FFFF_FFFF_FFFF
  DIGIT_0 = 48
  DIGIT_9 = 57
  private_constant :KNOWN, :SPACE, :NATIVE, :MODIFIERS, :STAR, :LONG_MAX, :DIGIT_0, :DIGIT_9

  # pack_alignof on this machine: the alignment of each type that `x!`
  # and `@!` take, and of a native `l` or `L` (a C long).
  ALIGNMENTS = { "c" => 1, "C" => 1, "s" => 2, "S" => 2, "i" => 4, "I" => 4, "l" => 4, "L" => 4, "q" => 8, "Q" => 8,
                 "j" => 8, "J" => 8, "n" => 2, "v" => 2, "N" => 4, "V" => 4, "f" => 4, "F" => 4, "e" => 4, "g" => 4,
                 "d" => 8, "D" => 8, "E" => 8, "G" => 8, "p" => 8, "P" => 8 }.freeze
  NATIVE_LONG = 8
  ULONG_MAX = 0xFFFF_FFFF_FFFF_FFFF
  private_constant :ALIGNMENTS, :NATIVE_LONG, :ULONG_MAX

  # The template as [directive, count, big?] triples; count is nil
  # for none, :all for `*`. `check` off keeps an unknown directive, so
  # a caller that reads the template as it goes refuses in ruby's
  # order.
  #
  # Read by its bytes, with one String cut of it a directive:
  # `template[i]` made one of every byte it looked at, and a program
  # packs the same short template again and again -- one build of the
  # compiler packs 555,616 times, mostly with `L<` and `Q<`.
  def self.directives(template, kind, check: true)
    # pack_pack and pack_unpack read the template as ASCII.
    raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{template.encoding}" unless template.encoding.ascii_compatible?

    out = []
    i = 0
    size = template.bytesize
    while i < size
      b = template.getbyte(i)
      i += 1
      next if Primitive.zr_table_member_p(SPACE, b)
      # skip_blank: `#` starts a comment to the end of the line.
      if b == 35
        i += 1 while i < size && template.getbyte(i) != 10
        next
      end

      # The directive's byte: a byte of a multibyte character is no directive.
      c = template.byteslice(i - 1, 1)
      # `x!` and `@!` (ruby 4.1) align the position to a number of bytes,
      # or to a type's alignment, and take no count.
      if (b == 120 || b == 64) && i < size && template.getbyte(i) == 33
        alignment, i = alignment_at(template, i + 1, size)
        out << [b == 120 ? +"x!" : +"@!", alignment, nil]
        next
      end
      big = nil
      native = false
      # pack_modifiers checks each modifier against the directive first.
      while i < size && Primitive.zr_table_member_p(MODIFIERS, template.getbyte(i))
        m = template.getbyte(i)
        raise ArgumentError, "'#{m.chr}' allowed only after types #{NATIVE}" unless NATIVE.include?(c)
        if m == 62 || m == 60
          raise RangeError, +"Can't use both '<' and '>'" unless big.nil?

          big = m == 62
        end
        native = true if m == 95 || m == 33
        i += 1
      end
      raise ArgumentError, +"% is not supported" if c == +"%"
      if check && !KNOWN.include?(c)
        raise ArgumentError, unknown_directive(kind, b, template)
      end
      c = c == +"L" ? +"Q" : +"q" if native && (c == +"L" || c == +"l")
      count = nil
      if i < size && template.getbyte(i) == STAR
        count = :all
        i += 1
      elsif i < size && template.getbyte(i) >= DIGIT_0 && template.getbyte(i) <= DIGIT_9
        count = 0
        while i < size && template.getbyte(i) >= DIGIT_0 && template.getbyte(i) <= DIGIT_9
          count = (count * 10) + (template.getbyte(i) - DIGIT_0)
          i += 1
        end
        # STRTOUL into a long: a count past LONG_MAX is out of range.
        raise RangeError, +"pack length too big" if count > LONG_MAX
      end
      out << [c, count, big]
    end
    out
  end

  # pack_alignment_size: the alignment after `x!` or `@!`, as digits or
  # as a type with its modifiers, and the index after it.
  def self.alignment_at(template, i, size)
    if i < size && template.getbyte(i) >= DIGIT_0 && template.getbyte(i) <= DIGIT_9
      n = 0
      while i < size && template.getbyte(i) >= DIGIT_0 && template.getbyte(i) <= DIGIT_9
        n = (n * 10) + (template.getbyte(i) - DIGIT_0)
        i += 1
      end
      raise RangeError, +"invalid alignment" if n.zero? || n > ULONG_MAX

      return [n, i]
    end
    raise ArgumentError, +"missing alignment" if i >= size

    type = template.getbyte(i)
    i += 1
    native = false
    endian = false
    while i < size && Primitive.zr_table_member_p(MODIFIERS, template.getbyte(i))
      m = template.getbyte(i)
      raise ArgumentError, "'#{m.chr}' allowed only after types #{NATIVE}" unless NATIVE.include?(type.chr)
      if m == 62 || m == 60
        raise RangeError, +"Can't use both '<' and '>'" if endian

        endian = true
      else
        native = true
      end
      i += 1
    end
    raise ArgumentError, +"endian modifier is not allowed for alignment" if endian

    alignment = native && (type == 108 || type == 76) ? NATIVE_LONG : ALIGNMENTS[type.chr]
    raise ArgumentError, unknown_directive("alignment", type, template) unless alignment

    [alignment, i]
  end

  # pack_align_pad: the bytes that move `pos` to the next multiple of
  # `alignment` counted from `base`.
  def self.align_pad(pos, base, alignment)
    return 0 if alignment <= 1
    raise RangeError, +"alignment too big" if alignment > LONG_MAX

    mod = (pos - base) % alignment
    mod.zero? ? 0 : alignment - mod
  end

  # The LEB128 bytes of `n` (R, r), as pack_pack writes them: as many
  # 7-bit groups as the magnitude takes, one more for a signed value
  # whose top group is full, in two's complement over the groups.
  def self.leb128(n, signed)
    raise ArgumentError, +"can't encode negative numbers in ULEB128" if !signed && n.negative?

    bits = n.abs.bit_length
    groups = (bits + 6) / 7
    if groups.zero?
      groups = 1
    elsif signed && (bits % 7).zero?
      groups += 1
    end
    value = n % (1 << (7 * groups))
    out = "".b
    groups.times do |g|
      byte = (value >> (7 * g)) & 0x7F
      out << (g < groups - 1 ? byte | 0x80 : byte)
    end
    out
  end

  # The value of the LEB128 bytes of `bytes` from `from` up to `to`.
  def self.leb128_value(bytes, from, to, signed)
    value = 0
    (from...to).each_with_index { |at, g| value |= (bytes.getbyte(at) & 0x7F) << (7 * g) }
    width = 7 * (to - from)
    signed && value[width - 1] == 1 ? value - (1 << width) : value
  end

  # NOT_BUFFER: a String to pack that is the buffer itself.
  def self.not_buffer(value, buffer)
    raise ArgumentError, +"cannot pack buffer object into itself" if buffer && value.equal?(buffer)

    value
  end

  # Quoted printable, as CRuby's qpencode writes it: a byte outside the
  # printable ASCII range, but for tab and newline, and `=` itself,
  # become `=XX`; a space or tab before a newline takes a soft break; a
  # line past `count` characters breaks after the one that passed it;
  # a last line with anything on it ends with a soft break.
  # unknown_directive: a printable directive as itself, any other byte as
  # `\xNN`; a template with an unprintable character quoted as
  # rb_str_quote_unprintable quotes it: as inspect does, but NUL as `\0`
  # and DEL as `\c?`.
  def self.unknown_directive(kind, byte, template)
    shown = byte.between?(32, 126) ? byte.chr : format("\\x%02x", byte)
    # A template in an encoding that a message cannot show is quoted too.
    foreign = !template.ascii_only? && template.encoding != (Encoding.default_internal || Encoding.default_external)
    if foreign || template.each_char.any? { |ch| !ch.match?(/[[:print:]]/) }
      template = template.inspect[1..-2].split("\\u0000", -1).join("\\0").split("\\u007F", -1).join("\\c?")
    end
    message = "unknown #{kind} directive '#{shown}' in '#{template}'"
    message.ascii_only? ? message.b : message
  end

  def self.quoted_printable(bytes, count)
    len = count.nil? || count == :all || count <= 1 ? 72 : count
    out = "".b
    n = 0
    prev = nil
    bytes.each_byte do |byte|
      if byte > 126 || (byte < 32 && byte != 10 && byte != 9) || byte == 61
        out << format("=%02X", byte)
        n += 3
        prev = nil
      elsif byte == 10
        out << "=\n" if prev == 32 || prev == 9
        out << "\n"
        n = 0
        prev = byte
      else
        out << byte.chr
        n += 1
        prev = byte
      end
      if n > len
        out << "=\n"
        n = 0
        prev = 10
      end
    end
    out << "=\n" if n > 0
    out
  end

  # unpack's `M`: `=XX` is a byte, `=` before a line end (LF or CRLF) a
  # soft break. At the first `=` that is neither, the rest of the text,
  # from that `=`, is kept as it is.
  def self.decode_quoted_printable(text)
    out = "".b
    size = text.bytesize
    i = 0
    kept = 0
    while i < size
      if text.getbyte(i) == 61
        i += 1
        break if i == size

        i += 1 if i + 1 < size && text.getbyte(i) == 13 && text.getbyte(i + 1) == 10
        if text.getbyte(i) != 10
          high = hex_digit(text.getbyte(i))
          break if high.nil?

          i += 1
          break if i == size

          low = hex_digit(text.getbyte(i))
          break if low.nil?

          out << ((high << 4) | low)
        end
      else
        out << text.getbyte(i)
      end
      i += 1
      kept = i
    end
    out << text.byteslice(kept, size - kept)
  end

  def self.hex_digit(b)
    n = b.chr.to_i(36)
    n = -1 if n.zero? && b != 48
    n.between?(0, 15) ? n : nil
  end
  private_class_method :quoted_printable, :decode_quoted_printable

  # The byte an unpack starts at. The directives read the String where
  # it is, from there on: a copy of a long String for each unpack1 at
  # an offset makes a reader of records quadratic.
  # A negative offset counts back from the end (ruby 4.1).
  def self.from(text, offset)
    offset += text.bytesize if offset < 0
    raise ArgumentError, +"offset outside of string" if offset < 0 || offset > text.bytesize

    offset
  end

  # `n` bytes of `bytes` from `at` as a binary String of their own.
  def self.chunk(bytes, at, n)
    (bytes.byteslice(at, n) || "".b).force_encoding(Encoding::BINARY)
  end

  # Uuencoding: a line contains `count` bytes rounded down to a multiple
  # of three, and starts with its own length; each three bytes become
  # four characters of six bits over a space, with a zero as a
  # backquote.
  def self.uuencode(bytes, count)
    line = count.nil? || count == :all || count <= 2 ? 45 : (count < 63 ? count : 63) / 3 * 3
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
    (value.zero? ? 0x60 : value + 0x20).chr
  end

  # pack.c's 'u': each line's length character, then groups of four
  # characters, until a byte that is no length character. A short group
  # reads as zeros; a checksum byte and the line end are skipped.
  # The decoded bytes, and how many bytes of `text` the decoding read.
  def self.uudecode(text)
    send = text.bytesize
    room = send * 3 / 4
    out = "".b
    total = 0
    s = 0
    uu = ->(byte) { byte && byte >= 0x20 && byte < 0x61 }
    while s < send && (c = text.getbyte(s)) > 0x20 && c < 0x61
      len = (c - 0x20) & 63
      s += 1
      total += len
      if total > room
        len -= total - room
        total = room
      end
      while len > 0
        mlen = len > 3 ? 3 : len
        a, b, c2, d = Array.new(4) do
          byte = s < send ? text.getbyte(s) : nil
          next 0 unless uu.(byte)

          s += 1
          (byte - 0x20) & 63
        end
        hunk = [((a << 2) | (b >> 4)) & 0xff, ((b << 4) | (c2 >> 2)) & 0xff, ((c2 << 6) | d) & 0xff]
        hunk.first(mlen).each { |byte| out << byte }
        len -= mlen
      end
      s += 1 if s < send && text.getbyte(s) != 13 && text.getbyte(s) != 10
      s += 1 if s < send && text.getbyte(s) == 13
      s += 1 if s < send && text.getbyte(s) == 10
    end
    [out, s]
  end
  private_class_method :uuencode, :uuchar, :uudecode

  # The result is US-ASCII while every directive writes ASCII (`m`, `M`,
  # `u` and none at all), UTF-8 once a `U` widens that, and binary as
  # soon as one directive writes arbitrary bytes.
  def self.pack(items, template, out = "".b, buffer = nil)
    at = 0
    # `x!` aligns from where a buffer's own bytes end.
    base = out.bytesize
    associates = nil
    list = directives(template, "pack", check: false)
    encoding = Encoding::US_ASCII
    list.each do |c, _, _|
      if c == +"U"
        encoding = Encoding::UTF_8 if encoding == Encoding::US_ASCII
      elsif !"mMu".include?(c)
        encoding = Encoding::BINARY
      end
    end
    # pack_pack: a conversion that changes the template stops the pack.
    template_size = template.bytesize
    list.each do |c, count, big|
      raise RuntimeError, +"format string modified" if template.bytesize != template_size

      case c
      when "x!", "@!"
        out << "\0" * align_pad(out.bytesize, c == +"@!" ? 0 : base, count)
      when "x"
        out << "\0" * (count == :all ? 0 : (count || 1))
      when "X"
        n = count == :all ? 0 : (count || 1)
        raise ArgumentError, +"X outside of string" if n > out.bytesize

        out = out.byteslice(0, out.bytesize - n)
      when "@"
        # As every directive, `@` with no count counts 1.
        n = count == :all ? 0 : (count || 1)
        out = n <= out.bytesize ? out.byteslice(0, n) : out + "\0" * (n - out.bytesize)
      when "a", "A", "Z"
        raise ArgumentError, +"too few arguments" if at >= Primitive.zr_ary_len_m(items)

        item = Primitive.zr_ary_at_m(items, at)
        at += 1
        # StringValue: nil is an empty String, anything else goes through to_str.
        item = item.nil? ? +"" : not_buffer(Primitive.zr_str_operand(item), buffer)

        out << pack_text(item.b, c, count)
      when "H", "h", "B", "b"
        raise ArgumentError, +"too few arguments" if at >= Primitive.zr_ary_len_m(items)

        # A String alone, or nil as an empty one, as CRuby's StringValue
        # takes it; `m` and `u` refuse nil too, and only `M` takes to_s.
        item = Primitive.zr_ary_at_m(items, at)
        item = not_buffer(Primitive.zr_str_operand(item.nil? ? +"" : item), buffer)
        at += 1
        out << (c == +"H" || c == +"h" ? pack_hex(item, c == +"H", count) : pack_bits(item, c == +"B", count))
      when "m"
        raise ArgumentError, +"too few arguments" if at >= Primitive.zr_ary_len_m(items)

        item = Primitive.zr_ary_at_m(items, at)
        at += 1
        out << base64(not_buffer(Primitive.zr_str_operand(item), buffer).b, count)
      when "M"
        raise ArgumentError, +"too few arguments" if at >= Primitive.zr_ary_len_m(items)

        item = Primitive.zr_ary_at_m(items, at)
        at += 1
        # rb_obj_as_string: a to_s that gives no String gives the default one.
        not_buffer(item, buffer)
        text = item.to_s
        text = Kernel.instance_method(:to_s).bind_call(item) unless text.is_a?(String)
        out << quoted_printable(text.b, count)
      when "u"
        raise ArgumentError, +"too few arguments" if at >= Primitive.zr_ary_len_m(items)

        item = Primitive.zr_ary_at_m(items, at)
        at += 1
        out << uuencode(not_buffer(Primitive.zr_str_operand(item), buffer).b, count)
      when "p", "P"
        # `P`'s count is the least width of the one String it points at.
        if c == +"P"
          raise ArgumentError, +"too few arguments" if at >= Primitive.zr_ary_len_m(items)

          width = count.is_a?(Integer) ? count : 1
          text = Primitive.zr_ary_at_m(items, at).nil? ? nil : not_buffer(Primitive.zr_str_operand(Primitive.zr_ary_at_m(items, at)), buffer)
          raise ArgumentError, "too short buffer for P(#{text.bytesize} for #{width})" if text && text.bytesize < width
        end
        n = c == +"P" ? 1 : count == :all ? Primitive.zr_ary_len_m(items) - at : (count || 1)
        n.times do
          raise ArgumentError, +"too few arguments" if at >= Primitive.zr_ary_len_m(items)

          text = Primitive.zr_ary_at_m(items, at).nil? ? nil : not_buffer(Primitive.zr_str_operand(Primitive.zr_ary_at_m(items, at)), buffer)
          at += 1
          (associates ||= []) << text
          push_integer(out, text.nil? ? 0 : Primitive.zr_str_bytes_address(text), 8, false)
        end
      when "U"
        each_item(items, at, count) { |item| out << utf8(integer_item(item)) }
        at += count == :all ? Primitive.zr_ary_len_m(items) - at : (count || 1)
      when "w"
        each_item(items, at, count) { |item| out << ber(integer_item(item)) }
        at += count == :all ? Primitive.zr_ary_len_m(items) - at : (count || 1)
      when "R", "r"
        each_item(items, at, count) { |item| out << leb128(integer_item(item), c == +"r") }
        at += count == :all ? Primitive.zr_ary_len_m(items) - at : (count || 1)
      when "d", "D", "E", "G"
        each_item(items, at, count) { |item| out << pack_double(float_item(item), c == +"G") }
        at += count == :all ? Primitive.zr_ary_len_m(items) - at : (count || 1)
      when "f", "F", "e", "g"
        each_item(items, at, count) { |item| out << pack_single(float_item(item), c == +"g") }
        at += count == :all ? Primitive.zr_ary_len_m(items) - at : (count || 1)
      else
        raise ArgumentError, unknown_directive("pack", c.getbyte(0), template) unless INTEGERS.key?(c)

        size, _, order = INTEGERS.fetch(c)
        big = order == :big if order
        n = count == :all ? Primitive.zr_ary_len_m(items) - at : (count || 1)
        raise ArgumentError, +"too few arguments" if at + n > Primitive.zr_ary_len_m(items)

        done = Primitive.zr_pack_ints(out, items, at, n, size, big == true)
        (at + done...at + n).each { |i| push_integer(out, integer_item(Primitive.zr_ary_at_m(items, i)), size, big) }
        at += n
      end
    end
    associate(out, associates) if associates
    out.force_encoding(encoding)
  end

  # A pointer `p` or `P` packs keeps the Strings it points at alive, on
  # the packed String, where `unpack` finds them again.
  def self.associate(text, strings) = Primitive.zr_hidden_set(text, :__associated__, strings)

  def self.associated(text) = Primitive.zr_hidden_get(text, :__associated__)

  # associated_pointer: the String whose bytes sit at `address`.
  def self.pointed(associates, address)
    associates&.find { |text| text.is_a?(String) && Primitive.zr_str_bytes_address(text) == address } or
      raise ArgumentError, +"no associated pointer"
  end

  # An item for an integer directive: a Numeric truncated to an Integer,
  # or the value of `to_int` for any other object that has one. An
  # Integer is used as it is. Kernel#Integer would need a base and a
  # keyword parameter to do this, a cost for every element of a `Q<*`.
  def self.integer_item(item)
    return item if item.is_a?(Integer)
    return Integer(item) if item.is_a?(Numeric)
    raise TypeError, no_implicit_conversion(item, "Integer") if item.nil? || !item.respond_to?(:to_int)

    int = item.to_int
    return int if int.is_a?(Integer)

    raise TypeError, cant_convert_gives(item, "Integer", :to_int, int)
  end

  # rb_to_float: a Numeric as a Float, and nothing else.
  def self.float_item(item)
    return item if item.is_a?(Float)
    # A Numeric that has no to_f of its own falls to the TypeError.
    return item.to_f if item.is_a?(Numeric) && item.respond_to?(:to_f)

    raise TypeError, cant_convert(item, "Float")
  end

  # rb_uv_to_utf8: a code point as UTF-8's bytes, in as many as six of
  # them, surrogates and all.
  def self.utf8(code)
    # NUM2LONG first: a value outside a long raises its RangeError.
    Primitive.zr_index_operand_m(code)
    raise RangeError, +"pack(U): value out of range" if code.negative? || code > 0x7fffffff
    return code.chr.b if code < 0x80

    size = [0x7ff, 0xffff, 0x1fffff, 0x3ffffff, 0x7fffffff].index { |top| code <= top } + 2
    tail = (1...size).map { |i| 0x80 | ((code >> (6 * (size - 1 - i))) & 0x3f) }
    [(0xff << (8 - size)) & 0xff | (code >> (6 * (size - 1))), *tail].pack("C*")
  end

  def self.each_item(items, at, count)
    n = count == :all ? Primitive.zr_ary_len_m(items) - at : (count || 1)
    n.times do |i|
      # An element's conversion may shorten the Array.
      raise ArgumentError, +"too few arguments" if at + i >= Primitive.zr_ary_len_m(items)

      yield Primitive.zr_ary_at_m(items, at + i)
    end
  end

  # The low `size` bytes of n in two's complement, appended to `out`; a
  # negative n is taken byte by byte so no shift leaves the fixnum
  # range. It appends rather than returning a new String, because the
  # packed String is available to write into. A new String per element
  # of a `Q<*` over a long Array would also make an Array of its bytes,
  # and a String per byte.
  def self.push_integer(out, n, size, big)
    first = out.bytesize
    i = 0
    while i < size
      out << (n & 255)
      n >>= 8
      i += 1
    end
    reverse_bytes(out, first, size) if big
    out
  end

  # The `n` bytes from `at` in the other order, in place.
  def self.reverse_bytes(out, at, n)
    i = 0
    while i < n / 2
      low = out.getbyte(at + i)
      out.setbyte(at + i, out.getbyte(at + n - 1 - i))
      out.setbyte(at + n - 1 - i, low)
      i += 1
    end
  end

  def self.pack_integer(n, size, big) = push_integer("".b, n, size, big)

  def self.pack_text(item, c, count)
    return item + (c == +"Z" ? "\0" : "") if count == :all

    n = count || 1
    item = item.byteslice(0, n)
    item + (c == +"A" ? " " : "\0") * (n - item.bytesize)
  end

  # pack_pack's `H` and `h`: two characters to a byte, and past the end
  # of the text the zero bytes the count still asks for.
  def self.pack_hex(text, high_first, count)
    len = count == :all ? text.bytesize : (count || 1)
    pad = 0
    if len > text.bytesize
      pad = (len + 1) / 2 - (text.bytesize + 1) / 2
      len = text.bytesize
    end
    out = +""
    i = 0
    while i < len
      first = hex_value(text.getbyte(i))
      second = i + 1 < len ? hex_value(text.getbyte(i + 1)) : 0
      out << (high_first ? (first << 4) | second : (second << 4) | first).chr
      i += 2
    end
    out << "\0" * pad
  end

  # A letter counts from 10 by its low four bits, as `a` to `f` do; any
  # other byte gives its own low four bits.
  def self.hex_value(b)
    alpha = (b | 32) >= 97 && (b | 32) <= 122
    alpha ? ((b & 15) + 9) & 15 : b & 15
  end

  # `B` and `b`: eight characters to a byte. Past the end of the text,
  # the C adds (count - length + 1) / 2 zero bytes.
  def self.pack_bits(text, high_first, count)
    len = count == :all ? text.bytesize : (count || 1)
    pad = 0
    if len > text.bytesize
      pad = (len - text.bytesize + 1) / 2
      len = text.bytesize
    end
    out = +""
    i = 0
    while i < len
      byte = 0
      8.times do |k|
        bit = i + k < len ? text.getbyte(i + k) & 1 : 0
        byte |= high_first ? bit << (7 - k) : bit << k
      end
      out << byte.chr
      i += 8
    end
    out << "\0" * pad
  end

  def self.base64(bytes, count)
    # A count of 0 writes one line; 1 and 2, as `*` and none, 45 bytes.
    line = if count == 0 then nil
           elsif count == :all || count.nil? || count <= 2 then 45
           else count / 3 * 3
           end
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
    raise ArgumentError, +"can't compress negative numbers" if n < 0

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

  # From byte `base` on; `@` and `X` count from the String's start, as
  # CRuby's do whatever the offset.
  # `padded` false leaves out the nils that stand for a value the bytes
  # run out before, as unpack with a block leaves them out
  # (PACK_ITEM_ADJUST). A directive moves the position over the bytes
  # that it read, never past the end, which `^` and `X` see.
  def self.unpack(bytes, template, single, associates = nil, base = 0, padded: true)
    out = []
    at = base
    # pack_unpack_internal reads the template as it goes: an unknown
    # directive raises where it is, and unpack1 stops before a later one.
    directives(template, "unpack", check: false).each do |c, count, big|
      case c
      when "x!", "@!"
        n = align_pad(at, c == +"@!" ? 0 : base, count)
        raise ArgumentError, c == +"@!" ? +"@ outside of string" : +"x outside of string" if n > bytes.bytesize - at

        at += n
      when "^"
        # The position so far, from the String's start (ruby 4.1).
        out << at
      when "x"
        n = count == :all ? bytes.bytesize - at : (count || 1)
        raise ArgumentError, +"x outside of string" if at + n > bytes.bytesize

        at += n
      when "X"
        # X* backs over what is left after the position, as pack_unpack does.
        n = count == :all ? bytes.bytesize - at : (count || 1)
        raise ArgumentError, +"X outside of string" if n > at

        at -= n
      when "@"
        n = count == :all ? bytes.bytesize - at : (count || 0)
        raise ArgumentError, +"@ outside of string" if n > bytes.bytesize

        at = n
      when "a", "A", "Z"
        n = count == :all ? bytes.bytesize - at : (count || 1)
        chunk = chunk(bytes, at, n)
        if c == +"Z"
          stop = chunk.index("\0")
          if stop
            chunk = chunk.byteslice(0, stop)
            n = count == :all ? stop + 1 : n
          end
        end
        if c == +"A"
          chunk = chunk.byteslice(0, chunk.bytesize - 1) while chunk.end_with?(" ") || chunk.end_with?("\0")
        end
        out << chunk
        at += at_most(n, bytes.bytesize - at)
      when "H", "h"
        n = count == :all ? (bytes.bytesize - at) * 2 : (count || 1)
        out << unpack_hex(bytes, at, n, c == +"H")
        at += (at_most(n, (bytes.bytesize - at) * 2) + 1) / 2
      when "B", "b"
        n = count == :all ? (bytes.bytesize - at) * 8 : (count || 1)
        out << unpack_bits(bytes, at, n, c == +"B")
        at += (at_most(n, (bytes.bytesize - at) * 8) + 7) / 8
      when "m"
        rest = chunk(bytes, at, bytes.bytesize - at)
        out << (count == 0 ? strict_base64(rest) : decode_base64(rest))
        at = bytes.bytesize
      when "M"
        rest = chunk(bytes, at, bytes.bytesize - at)
        out << decode_quoted_printable(rest)
        at = bytes.bytesize
      when "u"
        decoded, read = uudecode(chunk(bytes, at, bytes.bytesize - at))
        out << decoded
        at += read
      when "p"
        n = count == :all ? nil : (count || 1)
        while (n.nil? || n > 0) && bytes.bytesize - at >= 8
          address = unpack_integer(bytes.byteslice(at, 8), false, false)
          out << (address.zero? ? nil : pointed(associates, address))
          at += 8
          n -= 1 if n
        end
      when "P"
        # `P`'s count is the maximum number of bytes to return from the String.
        if bytes.bytesize - at >= 8
          width = count == :all ? bytes.bytesize - at : (count || 1)
          address = unpack_integer(bytes.byteslice(at, 8), false, false)
          at += 8
          text = address.zero? ? nil : pointed(associates, address)
          if text && width < text.bytesize
            text = text.byteslice(0, width).b
            associate(text, associates)
          end
          out << text
        end
      when "U"
        n = count == :all ? nil : (count || 1)
        while (n.nil? || n > 0) && at < bytes.bytesize
          value, len = utf8_to_uv(bytes, at)
          out << value
          at += len
          n -= 1 if n
        end
      when "w"
        # A value whose last byte still has the high bit set is left out.
        n = count == :all ? nil : (count || 1)
        value = 0
        while (n.nil? || n > 0) && at < bytes.bytesize
          b = bytes.getbyte(at)
          at += 1
          value = (value << 7) | (b & 127)
          next if b >= 128

          out << value
          value = 0
          n -= 1 if n
        end
      when "R", "r"
        # A value whose last byte still has the high bit set is nil, and
        # so is each one that a count asks for past the end.
        n = count == :all ? nil : (count || 1)
        start = at
        while (n.nil? || n > 0) && at < bytes.bytesize
          b = bytes.getbyte(at)
          at += 1
          next if b >= 128

          out << leb128_value(bytes, start, at, c == +"r")
          start = at
          n -= 1 if n
        end
        unless n.nil?
          if start != at && n > 0
            out << nil
            n -= 1
          end
          n.times { out << nil }
        end
      when "d", "D", "E", "G"
        each_slot(bytes, at, 8, count, out) { |chunk| unpack_double(chunk, c == +"G") }
        unpad(out, bytes, at, 8, count) unless padded
        at += 8 * at_most(count == :all ? bytes.bytesize : (count || 1), (bytes.bytesize - at) / 8)
      when "f", "F", "e", "g"
        each_slot(bytes, at, 4, count, out) { |chunk| single_value(unpack_integer(chunk, false, c == +"g")) }
        unpad(out, bytes, at, 4, count) unless padded
        at += 4 * at_most(count == :all ? bytes.bytesize : (count || 1), (bytes.bytesize - at) / 4)
      else
        raise ArgumentError, unknown_directive("unpack", c.getbyte(0), template) unless INTEGERS.key?(c)

        size, signed, order = INTEGERS.fetch(c)
        big = order == :big if order
        n = count == :all ? (bytes.bytesize - at) / size : (count || 1)
        Primitive.zr_unpack_ints(out, bytes, at, n, size, signed, big == true)
        unpad(out, bytes, at, size, count) unless padded
        at += size * at_most(n, (bytes.bytesize - at) / size)
      end
      break if single && !out.empty?
    end
    out
  end

  # The smaller of two Integers, by a comparison that a program's
  # Integer#<=> does not change, as Array#min would.
  def self.at_most(n, limit) = n < limit ? n : limit

  # Drops the nils that a fixed count of `size`-byte values pushed past
  # the end of the bytes.
  def self.unpad(out, bytes, at, size, count)
    return if count == :all

    short = (count || 1) - [(bytes.bytesize - at) / size, 0].max
    out.pop(short) if short > 0
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

  # The hex and bit directives return US-ASCII text, as CRuby's do.
  def self.unpack_hex(bytes, at, n, high_first)
    out = (+"").force_encoding(Encoding::US_ASCII)
    n.times do |i|
      b = bytes.getbyte(at + i / 2)
      break if b.nil?

      nibble = (i.even? == high_first) ? b >> 4 : b & 15
      out << nibble.to_s(16)
    end
    out
  end

  def self.unpack_bits(bytes, at, n, high_first)
    out = (+"").force_encoding(Encoding::US_ASCII)
    n.times do |i|
      b = bytes.getbyte(at + i / 8)
      break if b.nil?

      bit = high_first ? (b >> (7 - i % 8)) & 1 : (b >> (i % 8)) & 1
      out << bit.to_s
    end
    out
  end

  # `m`: the base64 characters, skipping all others, up to the first `=`
  # past two of a group.
  def self.decode_base64(text)
    out = "".b
    group = []
    text.each_byte do |b|
      break if b == 61 && group.size >= 2

      value = base64_value(b)
      next if value.nil?

      group << value
      next if group.size < 4

      a, b1, c, d = group
      out << ((a << 2 | b1 >> 4) & 255) << ((b1 << 4 | c >> 2) & 255) << ((c << 6 | d) & 255)
      group.clear
    end
    a, b1, c = group
    if group.size >= 2
      out << ((a << 2 | b1 >> 4) & 255)
      out << ((b1 << 4 | c >> 2) & 255) if c
    end
    out
  end

  # `m0`, RFC 4648: groups of four with no other byte, padding only at
  # the end, and no bits left over in the last character.
  def self.strict_base64(text)
    out = "".b
    size = text.bytesize
    i = 0
    bad = -> { raise ArgumentError, +"invalid base64" }
    while i < size
      a = base64_value(text.getbyte(i))
      i += 1
      bad.() if i >= size || a.nil?
      b = base64_value(text.getbyte(i))
      i += 1
      bad.() if i >= size || b.nil?
      if text.getbyte(i) == 61
        bad.() unless i + 2 == size && text.getbyte(i + 1) == 61
        bad.() if b & 0xf != 0
        return out << ((a << 2 | b >> 4) & 255)
      end
      c = base64_value(text.getbyte(i))
      i += 1
      bad.() if i >= size || c.nil?
      if i + 1 == size && text.getbyte(i) == 61
        bad.() if c & 0x3 != 0
        return out << ((a << 2 | b >> 4) & 255) << ((b << 4 | c >> 2) & 255)
      end
      d = base64_value(text.getbyte(i))
      i += 1
      bad.() if d.nil?
      out << ((a << 2 | b >> 4) & 255) << ((b << 4 | c >> 2) & 255) << ((c << 6 | d) & 255)
    end
    out
  end

  def self.base64_value(b) = b && BASE64.index(b.chr)

  # utf8_to_uv: the value of the UTF-8 character at `at`, and its length,
  # in the forms of up to six bytes that the C reads.
  def self.utf8_to_uv(bytes, at)
    lead = bytes.getbyte(at)
    return [lead, 1] if lead < 0x80
    raise ArgumentError, +"malformed UTF-8 character" if lead & 0x40 == 0

    n = [0x20, 0x10, 0x08, 0x04, 0x02].index { |bit| lead & bit == 0 }
    raise ArgumentError, +"malformed UTF-8 character" if n.nil?

    n += 2
    value = lead & (0x7f >> n)
    left = bytes.bytesize - at
    raise ArgumentError, "malformed UTF-8 character (expected #{n} bytes, given #{left} bytes)" if n > left

    (1...n).each do |k|
      c = bytes.getbyte(at + k)
      raise ArgumentError, +"malformed UTF-8 character" unless c & 0xc0 == 0x80

      value = (value << 6) | (c & 0x3f)
    end
    raise ArgumentError, +"redundant UTF-8 sequence" if value < [0, 0x80, 0x800, 0x10000, 0x200000, 0x4000000][n - 1]

    [value, n]
  end

  def self.unpack_double(chunk, big)
    low = unpack_integer(chunk.byteslice(big ? 4 : 0, 4), false, big)
    high = unpack_integer(chunk.byteslice(big ? 0 : 4, 4), false, big)
    Primitive.zr_float_of_halves(low, high)
  end

  # The double that a single's bits represent.
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

# A helper that CRuby has no module for: no program refers to it.
class Object
  private_constant :Packing
end

# CRuby writes these three in Ruby (its pack.rb), so they return their
# own parameters, under CRuby's names.
class Array
  def pack(fmt, buffer: nil)
    Primitive.attr! :ruby
    # The directives read the elements as the C does, never through a
    # subclass's size or [], and see a conversion that changes the Array.
    # With a buffer, packing starts at its bytes, so `@` counts from its
    # start, as CRuby packs into it; it keeps its encoding.
    unless buffer.nil?
      raise TypeError, "buffer must be String, not #{buffer.class}" unless buffer.is_a?(String)
      raise FrozenError.new("can't modify frozen String: #{buffer.inspect}", receiver: buffer) if buffer.frozen?
    end
    result = Packing.pack(self, Primitive.zr_str_operand(fmt), buffer ? buffer.b : "".b, buffer)
    return result unless buffer

    associates = Packing.associated(result)
    Packing.associate(buffer, associates) if associates
    encoding = buffer.encoding
    buffer.replace(result).force_encoding(encoding)
  end
end

class String
  # With a block, each value goes to it in sequence and the return value
  # is nil, as CRuby's unpack does.
  def unpack(fmt, offset: 0)
    Primitive.attr! :ruby
    bytes = plain
    values = Packing.unpack(bytes, Primitive.zr_str_operand(fmt), false, Packing.associated(self), Packing.from(bytes, offset), padded: !block_given?)
    return values unless block_given?

    values.each { |value| yield value }
    nil
  end

  def unpack1(fmt, offset: 0)
    Primitive.attr! :ruby
    bytes = plain
    Packing.unpack(bytes, Primitive.zr_str_operand(fmt), true, Packing.associated(self), Packing.from(bytes, offset)).first
  end
end
