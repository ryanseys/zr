# frozen_string_literal: true

# String methods written over the byte primitives. Character indexes
# map to byte offsets through the kernel, which reads UTF-8; a binary
# string's bytes are its characters. Case mapping, succ and character
# sets stop on non-ASCII text.
class String
  include Comparable

  # rb_str_aref_m: with two arguments, anything but a Regexp converts
  # both through to_int (a Range raises there); a nil length is given.
  def [](index, length = (absent = true; nil))
    index = Primitive.zr_index_operand_m(index) unless absent || index.is_a?(Integer) || index.is_a?(Regexp)
    case index
    when Integer
      index = Primitive.zr_index_operand_m(index) unless Primitive.zr_fixnum_p_m(index)
      unless absent
        # Both convert first, as NUM2LONG reads them. An index past the
        # fixnum range lies past either end, and a length past the end
        # reads to the end.
        len = Primitive.zr_index_operand_m(length)
        return nil if len < 0 || !Primitive.zr_fixnum_p_m(index)

        len = Primitive.zr_str_length_m(self) if len > Primitive.zr_str_length_m(self)
        return Primitive.zr_str_char_slice(self, index, len)
      end

      count = Primitive.zr_str_length_m(self)
      index += count if index < 0
      return nil if index < 0 || index >= count

      Primitive.zr_str_char_slice(self, index, 1)
    when Range
      start, length = range_span(index, Primitive.zr_str_length_m(self))
      start && Primitive.zr_str_char_slice(self, start, length)
    when Regexp
      match = index.send(:search, self, 0, false)
      Primitive.zr_backref_set(match)
      return nil unless match
      return match[0] if absent

      match[length]
    when String
      # str_duplicate(rb_cString, indx): a String, whatever its class.
      OWN[:include?].bind_call(self, index) ? String.new(index) : nil
    else
      OWN[:[]].bind_call(self, Primitive.zr_index_operand_m(index))
    end
  end
  alias slice []

  def chars(&block) = block ? OWN[:each_char].bind_call(self, &block) : characters.to_a

  def each_char
    return to_enum(:each_char) { Primitive.zr_str_length_m(self) } unless block_given?
    # rb_str_each_char walks a frozen copy, so the block can change the
    # receiver.
    unless frozen?
      String.new(self).freeze.each_char { |c| yield c }
      return self
    end

    i = 0
    while i < Primitive.zr_str_bytesize(self)
      n = Primitive.zr_str_char_len_at_m(self, i)
      yield byteslice_of(i, n)
      i += n
    end
    self
  end

  def bytes(&block)
    return OWN[:each_byte].bind_call(self, &block) if block

    out = []
    i = 0
    n = Primitive.zr_str_bytesize(self)
    while i < n
      out << Primitive.zr_str_byte_at(self, i)
      i += 1
    end
    out
  end

  def each_byte
    return to_enum(:each_byte) { Primitive.zr_str_bytesize(self) } unless block_given?

    i = 0
    while i < Primitive.zr_str_bytesize(self)
      yield Primitive.zr_str_byte_at(self, i)
      i += 1
    end
    self
  end

  def bytesize = Primitive.zr_str_bytesize(self)

  # The index converts as NUM2LONG converts one: a Float is truncated,
  # `to_int` is called, and a Bignum out of range is refused.
  def getbyte(i) = Primitive.zr_str_byte_at(self, Primitive.zr_index_operand_m(i))

  # The index converts as getbyte's index does and is checked first.
  # Then the byte converts as rb_to_int converts one, and its low eight
  # bits are written. The return value is the byte as it was given.
  def setbyte(i, byte)
    at = Primitive.zr_index_operand_m(i)
    size = Primitive.zr_str_bytesize(self)
    raise IndexError, "index #{at} out of string" if at >= size || at < -size

    Primitive.zr_str_setbyte(self, at, to_integer(byte) & 0xff)
    byte
  end

  def ord
    # rb_enc_codepoint_len: a byte above 127 is no US-ASCII character.
    if Encoding::US_ASCII.equal?(Encoding.at(Primitive.zr_str_encoding_index_m(self))) && Primitive.zr_str_bytesize(self) > 0 &&
       Primitive.zr_str_byte_at(self, 0) > 127
      raise ArgumentError, +"invalid byte sequence in US-ASCII"
    end

    Primitive.zr_str_ord(self)
  end

  # The arguments are walked without Array's own methods: the runtime
  # itself calls these two, so a program that redefines Array#each must
  # not change them.
  def start_with?(*prefixes)
    i = 0
    while i < Primitive.zr_ary_len_m(prefixes)
      prefix = Primitive.zr_ary_at_m(prefixes, i)
      if prefix.is_a?(Regexp)
        match = prefix.send(:match_at, self, 0)
        Primitive.zr_backref_set(match)
        return true if match
      else
        prefix = joined(Primitive.zr_str_operand(prefix))
        return true if char_boundary?(Primitive.zr_str_bytesize(prefix)) && Primitive.zr_str_bytes_at_m(self, 0, prefix)
      end
      i += 1
    end
    false
  end

  def end_with?(*suffixes)
    i = 0
    while i < Primitive.zr_ary_len_m(suffixes)
      suffix = joined(Primitive.zr_str_operand(Primitive.zr_ary_at_m(suffixes, i)))
      at = Primitive.zr_str_bytesize(self) - Primitive.zr_str_bytesize(suffix)
      return true if at >= 0 && char_boundary?(at) && Primitive.zr_str_bytes_at_m(self, at, suffix)

      i += 1
    end
    false
  end

  def delete_prefix(prefix)
    n = prefix_length(prefix)
    n > 0 ? byteslice_of(n, Primitive.zr_str_bytesize(self) - n) : copied
  end

  # deleted_prefix_length: the bytes of `prefix` that start the text, or
  # 0. A broken prefix in an ASCII-compatible text skips the encoding
  # check, and matches only a broken text where it ends a character.
  def prefix_length(prefix)
    Primitive.attr! :hidden
    prefix = Primitive.zr_str_operand(prefix)
    broken = !Primitive.zr_str_valid_p(prefix)
    unless broken && Encoding.at(Primitive.zr_str_encoding_index_m(self)).ascii_compatible? && prefix.encoding.ascii_compatible?
      Encoding.send(:incompatible, self, prefix) unless Encoding.compatible?(self, prefix)
    end
    n = prefix.bytesize
    return 0 if n == 0 || Primitive.zr_str_bytesize(self) < n

    i = 0
    while i < n
      return 0 if Primitive.zr_str_byte_at(self, i) != prefix.getbyte(i)

      i += 1
    end
    if broken
      return 0 if Primitive.zr_str_valid_p(self)

      at = 0
      OWN[:each_char].bind_call(self) do |c|
        break if at >= n

        at += c.bytesize
      end
      return 0 if at != n
    end
    n
  end

  def delete_suffix(suffix)
    suffix = Primitive.zr_str_operand(suffix)
    OWN[:end_with?].bind_call(self, suffix) ? byteslice_of(0, Primitive.zr_str_bytesize(self) - suffix.bytesize) : copied
  end

  # rb_str_replace: the frozen check comes before the conversion.
  def replace(other)
    Primitive.zr_frozen_error(self) if Primitive.zr_modify_frozen_m(self)
    Primitive.zr_str_replace(self, Primitive.zr_str_operand(other))
  end

  # `slice!`: removes the part that `[]` returns from the receiver.
  def slice!(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size == 1 || args.size == 2
    # str_modify_keep_cr: a frozen String raises, though nothing would change.
    Primitive.zr_frozen_error(self) if frozen?
    unless args[0].is_a?(String) || args[0].is_a?(Regexp) || args[0].is_a?(Range)
      args[0] = Primitive.zr_index_operand_m(args[0])
      args[1] = Primitive.zr_index_operand_m(args[1]) if args.size == 2
    end
    part = OWN[:[]].bind_call(self, *args)
    return nil if part.nil?

    start = if args[0].is_a?(String) then byte_index(args[0], 0)
            elsif args[0].is_a?(Regexp)
              group = args[1] || 0
              group += $~.size if group.is_a?(Integer) && group.negative?
              $~.byteoffset(group)[0]
            elsif args[0].is_a?(Range) then Primitive.zr_str_char_offset_m(self, range_span(args[0], Primitive.zr_str_length_m(self)).first)
            else
              Primitive.zr_str_char_offset_m(self, args[0])
            end
    Primitive.zr_str_replace(self, byteslice_of(0, start) + byteslice_of(start + part.bytesize, Primitive.zr_str_bytesize(self) - start - part.bytesize))
    part
  end

  # `s[i] = t`, `s[start, len] = t`, `s[range] = t` and `s[sub] = t`:
  # the span leaves and `t` takes its place.
  def []=(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 2..3)" unless args.size == 2 || args.size == 3

    Primitive.zr_frozen_error(self) if Primitive.zr_modify_frozen_m(self)
    value = args.pop

    # rb_str_aset_m: the replacement converts only after the place it
    # goes is found, as rb_str_subpat_set and rb_str_update check it.
    index = args[0]
    count = Primitive.zr_str_length_m(self)
    if Regexp === index
      match = index.send(:search, self, 0, false)
      raise IndexError, +"regexp not matched" unless match

      group = args.size == 2 ? args[1] : 0
      unless group.is_a?(String) || group.is_a?(Symbol)
        group = Primitive.zr_index_operand_m(group)
        groups = match.size
        raise IndexError, "index #{group} out of regexp" if group >= groups || (group.negative? && -group >= groups)

        group += groups if group.negative?
      end
      start = match.begin(group)
      raise IndexError, "regexp group #{group} not matched" if start.nil?

      length = match.end(group) - start
      value = Primitive.zr_str_operand(value)
    elsif args.size == 2
      index = Primitive.zr_index_operand_m(index)
      length = Primitive.zr_index_operand_m(args[1])
      raise IndexError, "negative length #{length}" if length < 0

      value = Primitive.zr_str_operand(value)
      # rb_str_update checks the encodings before the index.
      buf_incompatible(Encoding.at(Primitive.zr_str_encoding_index_m(self)), Encoding.at(Primitive.zr_str_encoding_index_m(value))) unless Encoding.compatible?(self, value)
      start = index < 0 ? index + count : index
      raise IndexError, "index #{index} out of string" if start < 0 || start > count

      length = count - start if length > count - start
    else
      case index
      when Integer
        value = Primitive.zr_str_operand(value)
        buf_incompatible(Encoding.at(Primitive.zr_str_encoding_index_m(self)), Encoding.at(Primitive.zr_str_encoding_index_m(value))) unless Encoding.compatible?(self, value)
        start = index < 0 ? index + count : index
        raise IndexError, "index #{index} out of string" if start < 0 || start > count

        length = start == count ? 0 : 1
      when Range
        start, length = range_span(index, count)
        raise RangeError, "#{index.inspect} out of range" unless start

        value = Primitive.zr_str_operand(value)
      when String
        start = OWN[:index].bind_call(self, index)
        raise IndexError, +"string not matched" unless start

        length = index.size
        value = Primitive.zr_str_operand(value)
      else
        return send(:[]=, Primitive.zr_index_operand_m(index), value)
      end
    end
    from = Primitive.zr_str_char_offset_m(self, start)
    to = Primitive.zr_str_char_offset_m(self, length > count - start ? count : start + length)
    Primitive.zr_str_splice(self, from, to - from, value)
    value
  end

  # A copy whose bytes are its characters (CRuby's ASCII-8BIT).
  def b = Primitive.zr_str_set_binary(copied)

  def clear = Primitive.zr_str_discard(self)

  def prepend(*others) = Primitive.zr_str_replace(self, others.map { |other| Primitive.zr_str_operand(other) }.join + self)

  def insert(index, other)
    index = Primitive.zr_index_operand_m(index)
    other = Primitive.zr_str_operand(other)
    count = Primitive.zr_str_length_m(self)
    index += count + 1 if index < 0
    raise IndexError, "index #{index} out of string" if index < 0 || index > count

    at = Primitive.zr_str_char_offset_m(self, index)
    Primitive.zr_str_splice(self, at, 0, Primitive.zr_str_operand(other))
  end

  # The four case mappings, each character through the Unicode tables.
  # `:ascii` leaves everything above 127 alone, `:turkic` gives the
  # dotted and dotless i their own rules, and `:fold` is downcasing
  # for comparison. `:lithuanian` reads as the plain mapping, as it
  # does in ruby.
  def upcase(*options) = mapped_case(:up, options)
  def downcase(*options) = mapped_case(:down, options)
  def capitalize(*options) = mapped_case(:title, options)
  def swapcase(*options) = mapped_case(:swap, options)

  # The bang forms return nil when nothing changed.
  def upcase!(*options) = mutate(OWN[:upcase].bind_call(self, *options))
  def downcase!(*options) = mutate(OWN[:downcase].bind_call(self, *options))
  def capitalize!(*options) = mutate(OWN[:capitalize].bind_call(self, *options))
  def swapcase!(*options) = mutate(OWN[:swapcase].bind_call(self, *options))
  def reverse! = Primitive.zr_str_replace(self, OWN[:reverse].bind_call(self))
  def delete!(*sets) = mutate(OWN[:delete].bind_call(self, *sets))
  def strip!(*selectors) = mutate(OWN[:strip].bind_call(self, *selectors))
  def lstrip!(*selectors) = mutate(OWN[:lstrip].bind_call(self, *selectors))
  def rstrip!(*selectors) = mutate(OWN[:rstrip].bind_call(self, *selectors))
  def chomp!(separator = $/) = mutate(OWN[:chomp].bind_call(self, separator))
  def chop! = mutate(OWN[:chop].bind_call(self))
  def squeeze!(*sets) = mutate(OWN[:squeeze].bind_call(self, *sets))

  # Whitespace and NUL off both ends, in one String. The end is found by
  # walking back over characters, which bytes that make none refuse, as
  # rstrip_offset has it. With `selectors`, the characters they pick come
  # off instead, as `delete` picks them.
  def strip(*selectors)
    return stripped(selectors, true, true) unless selectors.empty?

    dummy_check!
    return wide_stripped(true, true) if Primitive.zr_str_unit_m(self) != 0

    # rb_str_strip finds the start first, so its check comes first.
    start = lstrip_start
    broken_tail!
    stop = Primitive.zr_str_space_start(self, Primitive.zr_str_bytesize(self), true)
    byteslice_of(start, stop > start ? stop - start : 0)
  end

  def lstrip(*selectors)
    return stripped(selectors, true, false) unless selectors.empty?
    return wide_stripped(true, false) if Primitive.zr_str_unit_m(self) != 0

    start = lstrip_start
    byteslice_of(start, Primitive.zr_str_bytesize(self) - start)
  end

  # lstrip_offset: the byte after the leading spaces. It reads the first
  # character that is not a space, which must be a whole one in a
  # multibyte encoding.
  def lstrip_start
    Primitive.attr! :hidden
    start = Primitive.zr_str_space_end(self, 0, true)
    if !Primitive.zr_str_valid_p(self) && start < Primitive.zr_str_bytesize(self)
      enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
      if Regexp.encoder(enc).max_len > 1 && !byteslice_of(start, Primitive.zr_str_char_len_at_m(self, start)).valid_encoding?
        raise ArgumentError, "invalid byte sequence in #{enc}"
      end
    end
    start
  end

  def rstrip(*selectors)
    return stripped(selectors, false, true) unless selectors.empty?

    dummy_check!
    return wide_stripped(false, true) if Primitive.zr_str_unit_m(self) != 0

    broken_tail!
    byteslice_of(0, Primitive.zr_str_space_start(self, Primitive.zr_str_bytesize(self), true))
  end

  # rb_must_asciicompat: the methods that read ASCII digits refuse text
  # in UTF-16, UTF-32 or a dummy encoding. An ASCII-only text is in an
  # ASCII-compatible encoding.
  def ascii_compatible!
    Primitive.attr! :hidden
    return if Primitive.zr_str_ascii_only_m(self)

    enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{enc}" unless enc.ascii_compatible?
  end

  # rb_str_check_dummy_enc, as rstrip_offset calls it.
  def dummy_check!
    Primitive.attr! :hidden
    encoding = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    raise Encoding::CompatibilityError, "incompatible encoding with this operation: #{encoding}" if encoding.dummy?
  end

  # The characters `selectors` pick off the left end, the right end, or
  # both.
  def stripped(selectors, left, right)
    Primitive.attr! :hidden
    member = charset_test(selectors)
    chars = characters.to_a
    head = left ? chars.take_while { |c| member.call(c.ord) } : []
    tail = right ? chars.drop(head.size).reverse.take_while { |c| member.call(c.ord) } : []
    start = head.sum(&:bytesize)
    byteslice_of(start, Primitive.zr_str_bytesize(self) - start - tail.sum(&:bytesize))
  end

  # lstrip_offset and rstrip_offset over a text of UTF-16 or UTF-32,
  # which reads code points: NUL and ASCII whitespace come off.
  def wide_stripped(left, right)
    Primitive.attr! :hidden
    enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    bytes = OWN[:b].bind_call(self)
    onig = Regexp.encoder(enc)
    e = bytes.bytesize
    start = 0
    if left
      while start < e
        code, n = codepoint_len(bytes, start, onig, enc)
        break if code != 0 && !ascii_space?(code)

        start += n
      end
    end
    stop = e
    if right
      broken_tail!
      while (prev = onig.prev_char_head(bytes, start, stop, e))
        code, = codepoint_len(bytes, prev, onig, enc)
        break if code != 0 && !ascii_space?(code)

        stop = prev
      end
    end
    return copied if start == 0 && stop == e

    byteslice_of(start, stop - start)
  end

  # rb_enc_codepoint_len: [the code point at `at`, its byte length],
  # refused where no character starts.
  def codepoint_len(bytes, at, onig, enc)
    Primitive.attr! :hidden
    raise ArgumentError, +"empty string" if at >= bytes.bytesize

    n = onig.precise_mbclen(bytes, at)
    raise ArgumentError, "invalid byte sequence in #{enc}" unless n > 0

    [onig.mbc_to_code(bytes, at, bytes.bytesize), n]
  end

  # rb_isspace: ASCII's whitespace, over a code point.
  def ascii_space?(code)
    Primitive.attr! :hidden
    code == 0x20 || (code >= 0x09 && code <= 0x0D)
  end

  def broken_tail!
    Primitive.attr! :hidden
    raise Encoding::CompatibilityError, "invalid byte sequence in #{Encoding.at(Primitive.zr_str_encoding_index_m(self))}" unless (Primitive.zr_str_bytesize(self) == 0) || Primitive.zr_str_valid_p(self)
  end

  def chomp(separator = $/)
    separator = Primitive.zr_str_operand(separator) unless separator.nil?
    return copied if separator.nil? || (Primitive.zr_str_bytesize(self) == 0)
    return byteslice_of(0, chompped_length(separator)) if Primitive.zr_str_unit_m(self) != 0 || Primitive.zr_str_mb_p_m(self) || Primitive.zr_str_unit_m(separator) != 0

    if separator == +"\n"
      return byteslice_of(0, Primitive.zr_str_bytesize(self) - 2) if OWN[:end_with?].bind_call(self, "\r\n")
      return byteslice_of(0, Primitive.zr_str_bytesize(self) - 1) if OWN[:end_with?].bind_call(self, "\n", "\r")

      return copied
    end
    if separator.empty?
      s = self
      s = s.byteslice_of(0, s.bytesize - (s.end_with?("\r\n") ? 2 : 1)) while s.end_with?("\n")
      return s.equal?(self) ? copied : s
    end
    OWN[:end_with?].bind_call(self, separator) ? byteslice_of(0, Primitive.zr_str_bytesize(self) - separator.bytesize) : copied
  end

  def chop
    return byteslice_of(0, chopped_length) if Primitive.zr_str_bytesize(self) == 0 || Primitive.zr_str_unit_m(self) != 0 || Primitive.zr_str_mb_p_m(self)
    return byteslice_of(0, Primitive.zr_str_bytesize(self) - 2) if OWN[:end_with?].bind_call(self, "\r\n")

    byteslice_of(0, Primitive.zr_str_char_offset_m(self, -1))
  end

  # chompped_length: the bytes left once `rs` comes off the end. The
  # default separator takes a newline, a carriage return or both; ""
  # takes every trailing newline; another separator comes off only at a
  # character's start.
  def chompped_length(rs)
    Primitive.attr! :hidden
    len = Primitive.zr_str_bytesize(self)
    return 0 if len == 0

    bytes = OWN[:b].bind_call(self)
    return smart_chomp(bytes, len) if rs.equal?(String.default_rs)

    enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    onig = Regexp.encoder(enc)
    e = len
    if Primitive.zr_str_bytesize(rs) == 0
      min = onig.min_len
      if min > 1
        while e > 0
          pp = onig.left_adjust_char_head(bytes, 0, e - min, e)
          break unless pp >= 0 && onig.mbc_newline?(bytes, pp, e)

          e = pp
          pp -= min
          if pp >= 0
            pp = onig.left_adjust_char_head(bytes, 0, pp, e)
            e = pp if onig.ascget(bytes, pp, false)&.first == 0x0D
          end
        end
      else
        while e > 0 && bytes.getbyte(e - 1) == 0x0A
          e -= 1
          e -= 1 if e > 0 && bytes.getbyte(e - 1) == 0x0D
        end
      end
      return e
    end
    rslen = Primitive.zr_str_bytesize(rs)
    return len if rslen > len

    rs_bytes = OWN[:b].bind_call(rs)
    rs_onig = Regexp.encoder(Encoding.at(Primitive.zr_str_encoding_index_m(rs)))
    newline = rs_bytes.getbyte(rslen - 1)
    if rslen == rs_onig.min_len
      if rslen == 1
        return smart_chomp(bytes, e) if newline == 0x0A
      elsif rs_onig.mbc_newline?(rs_bytes, 0, rslen)
        return smart_chomp(bytes, e)
      end
    end
    enc = Encoding.compatible?(self, rs) || Encoding.incompatible(self, rs)
    return len unless Primitive.zr_str_valid_p(rs)

    pp = e - rslen
    if bytes.getbyte(len - 1) == newline && (rslen <= 1 || bytes.byteslice(pp, rslen) == rs_bytes)
      return len - rslen if Regexp.encoder(enc).left_adjust_char_head(bytes, 0, pp, e) == pp
    end
    len
  end

  # smart_chomp: a newline, a carriage return, or the two together.
  def smart_chomp(bytes, e)
    Primitive.attr! :hidden
    onig = Regexp.encoder(Encoding.at(Primitive.zr_str_encoding_index_m(self)))
    min = onig.min_len
    if min > 1
      pp = onig.left_adjust_char_head(bytes, 0, e - min, e)
      e = pp if pp >= 0 && onig.mbc_newline?(bytes, pp, e)
      pp = e - min
      if pp >= 0
        pp = onig.left_adjust_char_head(bytes, 0, pp, e)
        e = pp if onig.ascget(bytes, pp, false)&.first == 0x0D
      end
    else
      case bytes.getbyte(e - 1)
      when 0x0A
        e -= 1
        e -= 1 if e > 0 && bytes.getbyte(e - 1) == 0x0D
      when 0x0D
        e -= 1
      end
    end
    e
  end

  # chopped_length: the bytes before the last character, or before a
  # carriage return and newline together.
  def chopped_length
    Primitive.attr! :hidden
    e = Primitive.zr_str_bytesize(self)
    return 0 if e == 0

    enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    compat = enc.ascii_compatible?
    bytes = OWN[:b].bind_call(self)
    onig = Regexp.encoder(enc)
    p = onig.prev_char_head(bytes, 0, e, e)
    return 0 unless p

    if p > 0 && onig.ascget(bytes, p, compat)&.first == 0x0A
      p2 = onig.prev_char_head(bytes, 0, p, e)
      p = p2 if p2 && onig.ascget(bytes, p2, compat)&.first == 0x0D
    end
    p
  end

  # An empty String in the receiver's encoding, which a result built a
  # piece at a time keeps when every piece is plain ASCII or none is left.
  def empty_like
    Primitive.attr! :hidden
    OWN[:force_encoding].bind_call(+"", Encoding.at(Primitive.zr_str_encoding_index_m(self)))
  end

  def squeeze(*sets)
    raise ArgumentError, "invalid byte sequence in #{Encoding.at(Primitive.zr_str_encoding_index_m(self))}" unless Primitive.zr_str_valid_p(self)

    member = sets.empty? ? nil : charset_test(sets)
    out = empty_like
    last = nil
    kept = 0
    each_char_at do |i, n|
      cp = Primitive.zr_str_ord_at_m(self, i)
      if cp == last && (member.nil? || member.call(cp))
        out << byteslice_of(kept, i - kept) if i > kept
        kept = i + n
      end
      last = cp
    end
    out << byteslice_of(kept, Primitive.zr_str_bytesize(self) - kept) if Primitive.zr_str_bytesize(self) > kept
    out
  end

  # rb_default_rs: the separator `$/` until a program sets another.
  # Lines split at this object read it in the text's own encoding, so
  # a UTF-16 text splits at its own newline.
  # It is made on first use because the Encoding constants come later in this file.
  DEFAULT_RS = []
  private_constant :DEFAULT_RS

  def self.default_rs
    Primitive.attr! :hidden
    DEFAULT_RS[0] ||= "\n".b.force_encoding(Encoding::US_ASCII).freeze
  end

  # rb_str_enumerate_lines: the lines up to and including `separator`,
  # read a character at a time in the text's encoding. nil keeps the
  # whole text, "" splits paragraphs at blank lines, `chomp` strips
  # the separator.
  def lines(separator = $/, chomp: false, &block)
    return OWN[:each_line].bind_call(self, separator, chomp: chomp, &block) if block
    return [self] if separator.nil?
    return [] if Primitive.zr_str_bytesize(self) == 0

    rs = Primitive.zr_str_operand(separator)
    enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    Encoding.incompatible(self, rs) unless rs.equal?(String.default_rs) || (enc = Encoding.compatible?(self, rs))
    # A plain String is searched in place: the search and the encoder's
    # steps read bytes, whatever the encoding, so no copy of the whole
    # text is made for a walk over its lines. A subclass is read through
    # a copy, because the steps read bytes by String's methods, which a
    # subclass can redefine and ruby's C never calls.
    bytes = Primitive.zr_real_class(self).equal?(String) ? self : OWN[:b].bind_call(self)
    return paragraphs(bytes, enc, chomp) if Primitive.zr_str_bytesize(rs) == 0

    onig = Regexp.encoder(enc)
    rs_bytes = OWN[:b].bind_call(rs)
    newline = rs_bytes.bytesize == onig.min_len && onig.mbc_newline?(rs_bytes, 0, rs_bytes.bytesize)
    rs_bytes = OWN[:encode].bind_call(rs, enc).b if rs.equal?(String.default_rs) && !enc.ascii_compatible?
    rslen = rs_bytes.bytesize
    pend = Primitive.zr_str_bytesize(bytes)
    out = []
    at = 0
    while at < pend
      hit = Primitive.zr_str_find_from(bytes, rs_bytes, at)
      break unless hit

      adjusted = onig.right_adjust_char_head(bytes, at, hit, pend)
      if hit != adjusted
        at = adjusted
        next
      end
      stop = hit += rslen
      stop = newline ? chomp_newline(bytes, at, stop, onig, enc.ascii_compatible?) : stop - rslen if chomp
      out << byteslice_of(at, stop - at)
      at = hit
    end
    if at != pend
      if chomp
        if newline
          pend = chomp_newline(bytes, at, pend, onig, enc.ascii_compatible?)
        elsif pend - at >= rslen && Primitive.zr_str_find_from(bytes, rs_bytes, pend - rslen) == pend - rslen
          pend -= rslen
        end
      end
      out << byteslice_of(at, pend - at)
    end
    out
  end

  # The paragraph mode of rb_str_enumerate_lines: a line runs to the end
  # of the blank lines after it, and `chomp` keeps only its last newline
  # off.
  def paragraphs(bytes, enc, chomp)
    Primitive.attr! :hidden
    onig = Regexp.encoder(enc)
    compat = enc.ascii_compatible?
    pend = Primitive.zr_str_bytesize(bytes)
    out = []
    start = 0
    stop = 0
    eol = nil
    while stop < pend
      chomp_rslen = 0
      rslen = 0
      loop do
        c, n = onig.ascget(bytes, stop, compat)
        n = 0 if c != 0x0D
        rslen = n + onig.mbclen(bytes, stop + n)
        if onig.mbc_newline?(bytes, stop + n, pend)
          break if eol == stop

          stop += rslen
          if start
            eol = stop
            chomp_rslen = -rslen
          end
        else
          start ||= stop
          stop += rslen
        end
        rslen = 0
        break unless stop < pend
      end
      break unless start

      chomp_rslen = 0 if rslen == 0
      out << byteslice_of(start, stop - start + (chomp ? chomp_rslen : rslen))
      start = eol = nil
    end
    out
  end

  # chomp_newline: `stop` moved back over one newline, and a carriage
  # return before it.
  def chomp_newline(bytes, start, stop, onig, compat)
    Primitive.attr! :hidden
    prev = onig.prev_char_head(bytes, start, stop, stop)
    if onig.mbc_newline?(bytes, prev, stop)
      stop = prev
      prev = onig.prev_char_head(bytes, start, stop, stop)
      stop = prev if prev && onig.ascget(bytes.byteslice(0, stop), prev, compat)&.first == 0x0D
    end
    stop
  end

  def each_line(separator = (nosep = true), chomp: (nochomp = true), &block)
    separator = $/ if nosep
    chomp = false if nochomp
    unless block
      shown = nosep ? [] : [separator]
      return nochomp ? to_enum(:each_line, *shown) : to_enum(:each_line, *shown, chomp: chomp)
    end

    OWN[:lines].bind_call(self, separator, chomp: chomp).each(&block)
    self
  end

  # CRuby's four splits: awk (nil or " "), characters (""), a String
  # and a Regexp. A positive limit caps the pieces; a negative one keeps
  # trailing empty pieces; zero drops them.
  def split(pattern = nil, limit = 0)
    # The common splits, by a String's bytes or on blanks with no
    # limit, call nothing on the pattern on the way to the kernel.
    if Primitive.zr_fixnum_p_m(limit) && limit == 0 && Primitive.zr_str_valid_p(self) && Primitive.zr_str_unit_m(self) == 0 && (!(String === pattern) || Primitive.zr_str_unit_m(pattern) == 0)
      out = if Primitive.zr_str_plain_sep_p(pattern) then split_by_string(pattern, 0)
            elsif Primitive.zr_str_blank_sep_p(pattern) || (NilClass === pattern && $;.nil?) then Primitive.zr_str_split_words(self, 0)
            end
      if out
        return out unless block_given?

        yield_pieces(out) { |piece| yield piece }
        return self
      end
    end

    # NUM2INT: the bounds are written out, because Integer#** reaches
    # Rational, which the core does not have when its first split runs.
    limit = Primitive.zr_index_operand_m(limit)
    raise RangeError, "integer #{limit} too big to convert to 'int'" if limit > 2_147_483_647
    raise RangeError, "integer #{limit} too small to convert to 'int'" if limit < -2_147_483_648
    if limit == 1
      return (Primitive.zr_str_bytesize(self) == 0) ? [] : [copied] unless block_given?

      yield copied unless Primitive.zr_str_bytesize(self) == 0
      return self
    end
    if NilClass === pattern && !$;.nil?
      Warning.send(:deprecated, "$; is set to non-nil value")
      pattern = $;
    end
    # get_pat_quoted: rb_check_string_type, else a Regexp, else
    # TypeError; `===` reads a BasicObject too.
    unless NilClass === pattern || String === pattern || Regexp === pattern
      text = String.try_convert(pattern)
      raise TypeError, "wrong argument type #{conversion_name(pattern)} (expected Regexp)" if text.nil?

      pattern = text
    end
    # A split by words, characters or a String reads every character.
    raise ArgumentError, "invalid byte sequence in #{Encoding.at(Primitive.zr_str_encoding_index_m(self))}" unless pattern.is_a?(Regexp) || Primitive.zr_str_valid_p(self)

    out = if NilClass === pattern || (pattern.is_a?(String) && awk_pattern?(pattern)) then split_words(limit)
          elsif pattern.is_a?(Regexp) then split_by_regexp(pattern, limit)
          elsif !pattern.is_a?(String) then raise TypeError, "wrong argument type #{conversion_name(pattern)} (expected Regexp)"
          elsif pattern.empty? then split_chars(limit)
          else split_by_string(pattern, limit)
          end
    out.pop while limit == 0 && !out.empty? && out.last.empty?
    return out unless block_given?

    yield_pieces(out) { |piece| yield piece }
    self
  end

  # split's block: each piece in turn. A block that changes the receiver
  # stops the split, as str_mod_check does after each piece.
  def yield_pieces(out)
    Primitive.attr! :hidden
    size = Primitive.zr_str_bytesize(self)
    out.each do |piece|
      yield piece
      raise RuntimeError, +"string modified" if Primitive.zr_str_bytesize(self) != size
    end
  end

  # `sub`: replaces the first match with  `replacement` (with its `\1`,
  # `\k<name>`, `\0` and `\&` filled in), with the Hash's entry for the
  # match, or with the block's return value (with `$~` set).
  def sub(pattern, replacement = (none = true; nil), &block) = subbed(pattern, replacement, false, none, &block)

  # rb_str_sub_bang: a replacement that is not a Hash converts to a
  # String first, nil too when it was given (`none` when it was not). `sub` works on a copy, so a block that changes the
  # receiver does not change the result; `sub!` raises for that.
  def subbed(pattern, replacement, bang, none, &block)
    Primitive.attr! :hidden
    raise ArgumentError, +"wrong number of arguments (given 1, expected 2)" if none && block.nil?

    replacement = Hash.try_convert(replacement) || Primitive.zr_str_operand(replacement) unless none || replacement.is_a?(String)
    match = first_match(pattern, 0)
    Primitive.zr_backref_set(match)
    return copied unless match

    from = match.send(:begin_at, 0)
    to = match.send(:end_at, 0)
    size = Primitive.zr_str_bytesize(self)
    head = byteslice_of(0, from).b
    tail = byteslice_of(to, size - to).b
    own = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    repl = replacement_for(match, replacement, pattern.is_a?(Regexp) ? pattern : nil, &block)
    modified_check(size) if bang && !replacement.is_a?(String)
    # The encoding the text and the replacement share, or the
    # replacement's own where the text around the match is plain ASCII.
    enc = Encoding.compatible?(self, repl)
    unless enc
      unless own.ascii_compatible? && head.ascii_only? && tail.ascii_only?
        buf_incompatible(own, Encoding.at(Primitive.zr_str_encoding_index_m(repl)))
      end
      enc = Encoding.at(Primitive.zr_str_encoding_index_m(repl))
    end
    out = head << OWN[:b].bind_call(repl) << tail
    OWN[:force_encoding].bind_call(out, enc)
  end

  def gsub(pattern, replacement = (none = true; nil), &block)
    return to_enum(:gsub, pattern) if none && block.nil?

    # A replacement that was given converts, nil too, as in sub.
    replacement = Hash.try_convert(replacement) || Primitive.zr_str_operand(replacement) unless none || replacement.is_a?(String)
    regexp = pattern.is_a?(Regexp) ? pattern : nil
    # str_gsub: the text between matches and each replacement join onto a
    # buffer in the receiver's encoding, as rb_enc_str_buf_cat joins them.
    out = nil
    start = 0
    last = nil
    len = Primitive.zr_str_bytesize(self)
    while start <= Primitive.zr_str_bytesize(self) && (match = first_match(pattern, start))
      out ||= OWN[:force_encoding].bind_call(+"", Encoding.at(Primitive.zr_str_encoding_index_m(self)))
      last = match
      Primitive.zr_backref_set(match)
      from = match.send(:begin_at, 0)
      to = match.send(:end_at, 0)
      val = replacement_for(match, replacement, regexp, &block)
      # str_mod_check: a block or a Hash must leave the receiver as it was.
      modified_check(len) unless replacement.is_a?(String)
      cat_range(out, start, from - start) if from > start
      out.send(:buf_cat, val)
      start = to
      if to == from
        break if to >= Primitive.zr_str_bytesize(self)

        step = Primitive.zr_str_char_len_at_m(self, to)
        cat_range(out, to, step)
        start = to + step
      end
    end
    Primitive.zr_backref_set(last)
    return copied unless out

    cat_range(out, start, Primitive.zr_str_bytesize(self) - start) if Primitive.zr_str_bytesize(self) > start
    out
  end

  # Appends `n` bytes of the receiver from byte `at` to `out`, as
  # `buf_cat` appends them. In one encoding that is a copy of the bytes.
  def cat_range(out, at, n)
    Primitive.attr! :hidden
    return out.send(:buf_cat, byteslice_of(at, n)) unless Primitive.zr_str_encoding_index_m(out) == Primitive.zr_str_encoding_index_m(self)

    Primitive.zr_str_cat_range(out, self, at, n)
  end

  # A match makes the receiver the result and returns it, even when the
  # text comes out the same; `$~` tells whether there was one.
  def sub!(pattern, replacement = (none = true; nil), &block)
    Primitive.zr_frozen_error(self) if Primitive.zr_modify_frozen_m(self)
    result = subbed(pattern, replacement, true, none, &block)
    $~ ? replaced(result) : nil
  end

  def gsub!(pattern, replacement = (none = true; nil), &block)
    return to_enum(:gsub!, pattern) if none && block.nil?

    Primitive.zr_frozen_error(self) if Primitive.zr_modify_frozen_m(self)
    result = none ? gsub(pattern, &block) : gsub(pattern, replacement, &block)
    $~ ? replaced(result) : nil
  end

  # `include?`, and a String `[]`, search the way `index` does, so the
  # argument joins with the receiver before its bytes are read.
  def include?(other) = !byte_index(other, 0).nil?

  def index(needle, start = 0)
    start = Primitive.zr_index_operand_m(start)
    count = Primitive.zr_str_length_m(self)
    start += count if start < 0
    # rb_str_index_m: a start outside the string clears $~ for a Regexp.
    return Primitive.zr_backref_set(nil) if (start < 0 || start > count) && needle.is_a?(Regexp)
    return nil if start < 0 || start > count

    from = Primitive.zr_str_char_offset_m(self, start)
    if needle.is_a?(Regexp)
      match = needle.send(:search, self, from, false)
      Primitive.zr_backref_set(match)
      return match && match.begin(0)
    end
    at = byte_index(needle, from)
    at && Primitive.zr_str_byte_to_char(self, at)
  end

  def rindex(needle, start = Primitive.zr_str_length_m(self))
    start = Primitive.zr_index_operand_m(start)
    needle = Primitive.zr_str_operand(needle) unless needle.is_a?(Regexp)
    count = Primitive.zr_str_length_m(self)
    start += count if start < 0
    return Primitive.zr_backref_set(nil) if start < 0 && needle.is_a?(Regexp)
    return nil if start < 0

    from = Primitive.zr_str_char_offset_m(self, [start, count].min)
    if needle.is_a?(Regexp)
      match = needle.send(:search, self, from, true)
      Primitive.zr_backref_set(match)
      return match && match.begin(0)
    end
    needle = Primitive.zr_str_operand(needle)
    enc = Encoding.compatible?(self, needle) || Encoding.incompatible(self, needle)
    return nil unless Primitive.zr_str_valid_p(needle)

    slen = Primitive.zr_str_length_m(needle)
    return nil if count < slen

    pos = [start, count].min
    pos = count - slen if count - pos < slen
    return pos if count == 0

    sub = OWN[:b].bind_call(needle)
    if pos == 0
      return byteslice_of(0, sub.bytesize).b == sub ? 0 : nil
    end

    at = str_rindex(sub, Primitive.zr_str_char_offset_m(self, pos), enc)
    at && Primitive.zr_str_byte_to_char(self, at)
  end

  # str_rindex: the last start at or before byte `s` where `sub`'s bytes
  # sit at a character's start. A hit inside a character skips that
  # whole character, as CRuby's search does.
  def str_rindex(sub, s, enc)
    Primitive.attr! :hidden
    slen = sub.bytesize
    return s if slen == 0
    return s if byteslice_of(s, slen).b == sub

    bytes = OWN[:b].bind_call(self)
    onig = Regexp.encoder(enc)
    e = bytes.bytesize
    lead = sub.getbyte(0)
    searchlen = s + 1
    while searchlen > 0
      hit = searchlen - 1
      hit -= 1 while hit >= 0 && bytes.getbyte(hit) != lead
      break if hit < 0

      adjusted = onig.left_adjust_char_head(bytes, 0, hit, e)
      return hit if hit == adjusted && bytes.byteslice(hit, slen) == sub

      searchlen = adjusted
    end
    nil
  end

  # The characters are walked by byte offset and read as code points:
  # no String a character, as `rb_str_count` makes none.
  def count(*sets)
    raise ArgumentError, +"wrong number of arguments (given 0, expected 1+)" if sets.empty?

    member = charset_test(sets)
    n = 0
    each_char_at { |i, _| n += 1 if member.call(Primitive.zr_str_ord_at_m(self, i)) }
    n
  end

  # The runs of characters kept are copied whole: a delete that keeps
  # most of the text copies it in a few pieces.
  def delete(*sets)
    raise ArgumentError, +"wrong number of arguments (given 0, expected 1+)" if sets.empty?

    member = charset_test(sets)
    out = empty_like
    kept = 0
    each_char_at do |i, n|
      next unless member.call(Primitive.zr_str_ord_at_m(self, i))

      out << byteslice_of(kept, i - kept) if i > kept
      kept = i + n
    end
    out << byteslice_of(kept, Primitive.zr_str_bytesize(self) - kept) if Primitive.zr_str_bytesize(self) > kept
    out
  end

  # Each character's byte offset and length, in order.
  def each_char_at
    Primitive.attr! :hidden
    i = 0
    size = Primitive.zr_str_bytesize(self)
    while i < size
      n = Primitive.zr_str_char_len_at_m(self, i)
      yield i, n
      i += n
    end
  end

  def tr(from, to) = translate(from, to, false)

  # nil when no character of `from` occurs, even if nothing changed.
  def tr!(from, to)
    Primitive.zr_frozen_error(self) if Primitive.zr_modify_frozen_m(self)
    return nil unless OWN[:count].bind_call(self, from) > 0

    Primitive.zr_str_replace(self, translate(from, to, false))
  end

  def tr_s!(from, to)
    Primitive.zr_frozen_error(self) if Primitive.zr_modify_frozen_m(self)
    return nil unless OWN[:count].bind_call(self, from) > 0

    Primitive.zr_str_replace(self, translate(from, to, true))
  end

  # The next string: the rightmost run of letters or digits counts up
  # with carries, a carry past its start adds a first letter or digit;
  # with none, the last character moves on. Beyond ASCII a character
  # counts as a letter or digit by its Unicode class, and steps by
  # codepoint.
  def succ
    index = Primitive.zr_str_encoding_index_m(self)
    if index <= 2 && Primitive.zr_str_ascii_only_m(self)
      out = Primitive.zr_str_succ_ascii(self)
      return out if Primitive.zr_str_encoding_index_m(out) == index

      return OWN[:force_encoding].bind_call(out, Encoding.at(index))
    end

    enc = Encoding.at(index)
    bytes = OWN[:b].bind_call(self)
    e = bytes.bytesize
    return copied if e == 0

    onig = Regexp.encoder(enc)
    s = e
    last_alnum = nil
    found_alnum = false
    carry = "\x01".b
    carry_pos = 0
    carry_len = 1
    neighbor = :found
    while (s = onig.prev_char_head(bytes, 0, s, e))
      if neighbor == :not_char && last_alnum
        was = bytes.getbyte(last_alnum)
        now = bytes.getbyte(s)
        break if ascii_alpha?(was) ? ascii_digit?(now) : ascii_digit?(was) && ascii_alpha?(now)
      end
      l = onig.precise_mbclen(bytes, s)
      next unless l > 0

      char = bytes.byteslice(s, l)
      neighbor, wrapped = succ_alnum_char(char, onig)
      next if neighbor == :not_char

      bytes[s, l] = char
      return bytes.force_encoding(enc) if neighbor == :found

      carry = wrapped
      last_alnum = s
      found_alnum = true
      carry_pos = s
      carry_len = l
    end
    unless found_alnum
      s = e
      while (s = onig.prev_char_head(bytes, 0, s, e))
        l = onig.precise_mbclen(bytes, s)
        next unless l > 0

        char = bytes.byteslice(s, l)
        neighbor = succ_char(char, onig)
        bytes[s, l] = char unless neighbor == :not_char
        return bytes.force_encoding(enc) if neighbor == :found

        char = bytes.byteslice(s, l)
        if onig.precise_mbclen(char, 0) != l
          succ_char(char, onig)
          bytes[s, l] = char
        end
        unless enc.ascii_compatible?
          carry = bytes.byteslice(s, l)
          carry_len = l
        end
        carry_pos = s
      end
    end
    (bytes.byteslice(0, carry_pos) << carry.byteslice(0, carry_len) << bytes.byteslice(carry_pos, e - carry_pos)).force_encoding(enc)
  end

  alias next succ

  def succ!
    Primitive.zr_str_replace(self, OWN[:succ].bind_call(self))
  end

  alias next! succ!

  def ascii_alpha?(byte)
    Primitive.attr! :hidden
    (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
  end

  def ascii_digit?(byte)
    Primitive.attr! :hidden
    byte >= 0x30 && byte <= 0x39
  end

  # ONIGENC_CTYPE_ALPHA, _DIGIT and _PRINT (Regexp::Onig::CType).
  ONIG_ALPHA = 1
  ONIG_DIGIT = 4
  ONIG_PRINT = 7
  private_constant :ONIG_ALPHA, :ONIG_DIGIT, :ONIG_PRINT

  # enc_succ_char and enc_pred_char: the character `char` (a binary
  # String, changed in place) moved one on or back. A wide encoding
  # steps its code point; any other steps the bytes, carrying, until
  # they make a character of the same length. :found, :wrapped past the
  # last or first, or :not_char.
  def succ_char(char, onig, step = 1)
    Primitive.attr! :hidden
    len = char.bytesize
    if onig.min_len > 1
      return :not_char unless onig.precise_mbclen(char, 0) > 0

      code = onig.mbc_to_code(char, 0, len)
      return :not_char if step < 0 && code == 0

      code += step
      l = onig.code_to_mbclen(code)
      return :not_char if l == 0
      return :wrapped if l != len

      char.replace(onig.code_to_mbc(code))
      return onig.precise_mbclen(char, 0) > 0 ? :found : :not_char
    end
    wrap, fill = step > 0 ? [0xFF, 0] : [0, 0xFF]
    loop do
      i = len - 1
      while i >= 0 && char.getbyte(i) == wrap
        char.setbyte(i, fill)
        i -= 1
      end
      return :wrapped if i < 0

      char.setbyte(i, char.getbyte(i) + step)
      l = onig.precise_mbclen(char, 0)
      if l > 0
        return :found if l == len

        (l...len).each { |k| char.setbyte(k, wrap) }
      end
      next unless l == -1 && i < len - 1

      len2 = len - 1
      len2 -= 1 while len2 > 0 && onig.precise_mbclen(char.byteslice(0, len2), 0) == -1
      (len2 + 1...len).each { |k| char.setbyte(k, wrap) }
    end
  end

  # enc_succ_alnum_char: moves a letter or digit one step in its run of
  # letters or digits and returns [:found]. If it wraps to the first of
  # the run, it returns [:wrapped, carry]. It returns [:not_char] for any
  # other character, or for a run of one.
  def succ_alnum_char(char, onig)
    Primitive.attr! :hidden
    len = char.bytesize
    code = onig.mbc_to_code(char, 0, len)
    ctype = if onig.code_ctype?(code, ONIG_DIGIT) then ONIG_DIGIT
            elsif onig.code_ctype?(code, ONIG_ALPHA) then ONIG_ALPHA
            else return [:not_char]
            end
    save = char.dup
    # One gap is skipped, as U+03A2 lies between Greek capitals.
    2.times do
      return [:found] if succ_char(char, onig) == :found && onig.code_ctype?(onig.mbc_to_code(char, 0, len), ctype)
    end
    char.replace(save)
    range = 1
    loop do
      save = char.dup
      unless succ_char(char, onig, -1) == :found && onig.code_ctype?(onig.mbc_to_code(char, 0, len), ctype)
        char.replace(save)
        break
      end
      range += 1
    end
    return [:not_char] if range == 1

    carry = char.dup
    succ_char(carry, onig) if ctype == ONIG_DIGIT
    [:wrapped, carry]
  end

  def delete_prefix!(prefix)
    Primitive.zr_frozen_error(self) if Primitive.zr_modify_frozen_m(self)
    n = prefix_length(prefix)
    n > 0 ? mutate(byteslice_of(n, Primitive.zr_str_bytesize(self) - n)) : nil
  end

  def delete_suffix!(suffix)
    Primitive.zr_frozen_error(self) if Primitive.zr_modify_frozen_m(self)
    suffix = Primitive.zr_str_operand(suffix)
    OWN[:end_with?].bind_call(self, suffix) ? mutate(delete_suffix(suffix)) : nil
  end

  # Bytes and Strings appended as they are, whatever the encodings.
  def append_as_bytes(*parts)
    parts.each do |part|
      if part.is_a?(Integer)
        Primitive.zr_str_push_byte(self, part & 0xFF)
      elsif part.is_a?(String)
        part.each_byte { |b| Primitive.zr_str_push_byte(self, b) }
      else
        raise TypeError, "wrong argument type #{conversion_name(part)} (expected String or Integer)"
      end
    end
    self
  end

  def crypt(salt)
    # mustnot_wchar of the text, then of the salt.
    wide = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    raise ArgumentError, "wide char encoding: #{wide}" if Encoding.wide?(wide)
    salt = Primitive.zr_str_operand(salt)
    raise ArgumentError, "wide char encoding: #{salt.encoding}" if Encoding.wide?(salt.encoding)
    raise ArgumentError, +"salt too short (need >=2 bytes)" if salt.bytesize < 2
    raise ArgumentError, +"string contains null byte" if OWN[:include?].bind_call(self, "\0") || salt.include?("\0")

    Primitive.zr_str_set_binary(Primitive.zr_str_crypt(self, salt))
  end

  def each_codepoint(&block)
    return to_enum(:each_codepoint) { Primitive.zr_str_length_m(self) } unless block

    OWN[:each_char].bind_call(self) { |c| yield c.ord }
    self
  end

  alias dedup -@

  # The bytes from `start` (`length` of them, or a Range) replaced by
  # `text`'s, in place; the ends must sit on character boundaries.
  # rb_str_bytesplice: (range, str), (range, str, str_range),
  # (index, length, str) or (index, length, str, str_index, str_length).
  # Both sides are checked as str_check_beg_len checks them, on character
  # boundaries of each string.
  def bytesplice(*args)
    n = args.size
    raise ArgumentError, "wrong number of arguments (given #{n}, expected 2..5)" unless (2..5).cover?(n)
    raise ArgumentError, "wrong number of arguments (given #{n}, expected 2, 3, or 5)" if n == 4

    if n == 2 || (n == 3 && !args[0].is_a?(Integer))
      start, length = splice_range(args[0], Primitive.zr_str_bytesize(self))
      text = Primitive.zr_str_operand(args[1])
      from, count = n == 2 ? [0, text.bytesize] : splice_range(args[2], text.bytesize)
    else
      start = Primitive.zr_index_operand_m(args[0])
      length = Primitive.zr_index_operand_m(args[1])
      text = Primitive.zr_str_operand(args[2])
      from, count = n == 3 ? [0, text.bytesize] : [Primitive.zr_index_operand_m(args[3]), Primitive.zr_index_operand_m(args[4])]
    end
    start, length = splice_bounds(start, length)
    from, count = text.send(:splice_bounds, from, count)
    Primitive.zr_frozen_error(self) if frozen?
    unless encoding == text.encoding
      common = Encoding.compatible?(self, text)
      raise Encoding::CompatibilityError, "incompatible character encodings: #{Encoding.shown(encoding)} and #{Encoding.shown(text.encoding)}" unless common

      force_encoding(common)
    end
    Primitive.zr_str_splice(self, start, length, text.byteslice(from, count))
  end

  def self.try_convert(object)
    return object if String === object

    converted = Primitive.zr_check_call(object, :to_str)
    raise TypeError, "can't convert #{conversion_name(object)} to String (#{conversion_name(object)}#to_str gives #{conversion_name(converted)})" unless converted.nil? || String === converted

    converted
  end

  def tr_s(from, to) = translate(from, to, true)

  def upto(last, exclusive = false, &block)
    return to_enum(:upto, last, exclusive) unless block

    last = Primitive.zr_str_operand(last)
    # rb_str_upto_each: rb_enc_check of the two ends.
    Encoding.send(:incompatible, self, last) unless Encoding.compatible?(self, last)
    if Primitive.zr_str_bytesize(self) == 1 && last.bytesize == 1
      b = Primitive.zr_str_byte_at(self, 0)
      finish = last.getbyte(0)
      finish -= 1 if exclusive
      while b <= finish
        yield Primitive.zr_str_from_byte(b)
        b += 1
      end
      return self
    end
    if digits? && last.send(:digits?)
      n = to_i
      finish = last.to_i
      finish -= 1 if exclusive
      width = Primitive.zr_str_bytesize(self)
      while n <= finish
        text = n.to_s
        yield text.bytesize < width ? ("0" * (width - text.bytesize) + text).force_encoding(Encoding::US_ASCII) : text
        n += 1
      end
      return self
    end
    order = self <=> last
    return self if order > 0 || (exclusive && order == 0)

    after = last.succ
    current = copied
    until current == after
      following = exclusive || current != last ? current.succ : nil
      yield current
      break if following.nil?

      current = following
      break if exclusive && current == last
      break if current.bytesize > last.bytesize || current.empty?
    end
    self
  end

  def partition(sep)
    sep = Primitive.zr_str_operand(sep) unless sep.is_a?(Regexp)
    if sep.is_a?(Regexp)
      match = sep.send(:search, self, 0, false)
      Primitive.zr_backref_set(match)
      return [copied, empty_like, empty_like] unless match

      from = match.send(:begin_at, 0)

      to = match.send(:end_at, 0)
      return [byteslice_of(0, from), match[0], byteslice_of(to, Primitive.zr_str_bytesize(self) - to)]
    end
    at = byte_index(sep, 0)
    at ? [byteslice_of(0, at), sep.dup, byteslice_of(at + sep.bytesize, Primitive.zr_str_bytesize(self) - at - sep.bytesize)] : [copied, empty_like, empty_like]
  end

  def rpartition(sep)
    sep = Primitive.zr_str_operand(sep) unless sep.is_a?(Regexp)
    if sep.is_a?(Regexp)
      match = sep.send(:search, self, Primitive.zr_str_bytesize(self), true)
      Primitive.zr_backref_set(match)
      return [empty_like, empty_like, copied] unless match

      from = match.send(:begin_at, 0)

      to = match.send(:end_at, 0)
      return [byteslice_of(0, from), match[0], byteslice_of(to, Primitive.zr_str_bytesize(self) - to)]
    end
    at = OWN[:rindex].bind_call(self, sep)
    return [empty_like, empty_like, copied] unless at

    at = Primitive.zr_str_char_offset_m(self, at)
    [byteslice_of(0, at), sep.dup, byteslice_of(at + sep.bytesize, Primitive.zr_str_bytesize(self) - at - sep.bytesize)]
  end

  def sum(bits = 16)
    bits = Primitive.zr_index_operand_m(bits)
    total = 0
    OWN[:each_byte].bind_call(self) { |b| total += b }
    bits > 0 ? total & ((1 << bits) - 1) : total
  end

  def byteslice(start, length = (one = true; nil))
    size = Primitive.zr_str_bytesize(self)
    # str_byteslice: with two arguments, each is a C long, a Range too.
    unless one
      start = Primitive.zr_index_operand_m(start)
      length = Primitive.zr_index_operand_m(length)
    end
    if start.is_a?(Range)
      from, count = range_span(start, size)
      return from && byteslice_of(from, count)
    end
    start = Primitive.zr_index_operand_m(start)
    length = Primitive.zr_index_operand_m(length) unless length.nil?
    if length.nil?
      return nil if start >= size || start < -size

      return byteslice_of(start < 0 ? start + size : start, 1)
    end
    return nil if length < 0

    start += size if start < 0
    return nil if start < 0 || start > size

    length = size - start if length > size - start
    byteslice_of(start, length)
  end

  def codepoints
    return OWN[:each_char].bind_call(self) { |c| yield c.ord } if block_given?

    characters.map(&:ord)
  end

  # Each match in sequence, as rb_str_scan finds them: the whole match
  # when the pattern has no group, else the groups. An empty match steps
  # one character. The items are sliced from the offsets that a search
  # returns. A MatchData is made for each match only under a block,
  # which can read `$~`. Otherwise only the last match gets one, which
  # `$~` keeps.
  def scan(pattern)
    # get_pat_quoted: the pattern converts once, before the walk.
    pattern = Primitive.zr_str_operand(pattern) unless pattern.is_a?(Regexp) || pattern.is_a?(String) || !pattern.respond_to?(:to_str)
    found = []
    last = nil
    at = 0
    while at <= Primitive.zr_str_bytesize(self) && (offsets = match_offsets(pattern, at))
      last = offsets
      from = offsets[1]
      to = offsets[2]
      item = offsets.size > 3 ? (1...(offsets.size - 1) / 2).map { |i| slice_at(offsets[i * 2 + 1], offsets[i * 2 + 2]) } : slice_at(from, to)
      if block_given?
        Primitive.zr_backref_set(MatchData.send(:for, pattern, self, offsets))
        len = Primitive.zr_str_bytesize(self)
        yield item
        modified_check(len)
      else
        found << item
      end
      at = to == from ? to + (to < Primitive.zr_str_bytesize(self) ? Primitive.zr_str_char_len_at_m(self, to) : 1) : to
    end
    # The last match is $~ again after the block, as rb_str_scan sets it.
    Primitive.zr_backref_set(last && MatchData.send(:for, pattern, self, last))
    block_given? ? self : found
  end

  # str_mod_check: the RuntimeError of a block that changed the receiver
  # while scan or gsub walked it.
  def modified_check(len)
    Primitive.attr! :hidden
    raise RuntimeError, +"string modified" if Primitive.zr_str_bytesize(self) != len
  end

  # The bytes from `from` to `to`, or nil for a group that did not take
  # part (-1 for both).
  def slice_at(from, to)
    Primitive.attr! :hidden
    from < 0 ? nil : Primitive.zr_str_byteslice(self, from, to - from)
  end

  DUMP_ESCAPES = { 7 => "\\a", 8 => "\\b", 9 => "\\t", 10 => "\\n", 11 => "\\v", 12 => "\\f", 13 => "\\r", 27 => "\\e", 34 => "\\\"", 92 => "\\\\" }.freeze
  private_constant :DUMP_ESCAPES

  # Everything outside printable ASCII escaped, so the result reads
  # back as the same bytes: a whole character as \u, a stray byte as
  # \x.
  def dump
    return "#{OWN[:b].bind_call(self).dump}.dup.force_encoding(#{Encoding.at(Primitive.zr_str_encoding_index_m(self)).name.dump})" unless Encoding.at(Primitive.zr_str_encoding_index_m(self)).ascii_compatible?

    # A character past ASCII shows its code point in UTF-8 alone; any
    # other encoding shows its bytes.
    utf8 = Encoding.at(Primitive.zr_str_encoding_index_m(self)).equal?(Encoding::UTF_8)
    out = +"\""
    i = 0
    while i < Primitive.zr_str_bytesize(self)
      b = Primitive.zr_str_byte_at(self, i)
      n = utf8 ? Primitive.zr_str_char_len_at_m(self, i) : 1
      if n > 1
        cp = byteslice_of(i, n).ord
        out << (cp > 0xFFFF ? format("\\u{%X}", cp) : format("\\u%04X", cp))
      elsif DUMP_ESCAPES.key?(b)
        out << DUMP_ESCAPES[b]
      elsif b == 35 && [123, 36, 64].include?(Primitive.zr_str_byte_at(self, i + 1))
        out << "\\#"
      elsif b < 32 || b >= 127
        out << format("\\x%02X", b)
      else
        out << Primitive.zr_str_from_byte(b)
      end
      i += n
    end
    out << "\""
    out.force_encoding(Encoding.at(Primitive.zr_str_encoding_index_m(self)))
  end

  UNIT_ESCAPES = { 34 => "\\\"", 92 => "\\\\", 10 => "\\n", 9 => "\\t", 13 => "\\r", 27 => "\\e", 7 => "\\a", 8 => "\\b", 12 => "\\f", 11 => "\\v" }.freeze
  private_constant :UNIT_ESCAPES

  # What ruby_escaped_char writes for a control character.
  CONTROL_ESCAPES = { 0 => "\\0", 10 => "\\n", 13 => "\\r", 9 => "\\t", 12 => "\\f", 11 => "\\v", 8 => "\\b", 7 => "\\a", 27 => "\\e", 127 => "\\c?" }.freeze
  UNICODE_NAMES = %w[UTF-8 UTF8-MAC CESU-8 UTF-16BE UTF-16LE UTF-32BE UTF-32LE UTF-16 UTF-32].freeze
  private_constant :CONTROL_ESCAPES, :UNICODE_NAMES

  # rb_str_escape: an inspect past ASCII in an encoding other than the
  # default external one, as rb_inspect shows it -- printable ASCII as
  # it is and every other character escaped, in US-ASCII.
  def escape
    Primitive.attr! :hidden
    unicode = Primitive.zr_table_member_p(UNICODE_NAMES, Encoding.at(Primitive.zr_str_encoding_index_m(self)).name)
    plain = unicode || Encoding.at(Primitive.zr_str_encoding_index_m(self)).ascii_compatible?
    out = String.new(encoding: Encoding::US_ASCII)
    OWN[:each_char].bind_call(self) do |char|
      unless char.valid_encoding?
        char.each_byte { |byte| out << format("\\x%02X", byte) }
        next
      end
      code = char.ord
      out << if (shown = CONTROL_ESCAPES[code]) then shown
             elsif plain && code.between?(0x20, 0x7E) then code.chr
             elsif unicode then format(code < 0x10000 ? "\\u%04X" : "\\u{%X}", code)
             else format(code < 0x100 ? "\\x%02X" : "\\x{%X}", code)
             end
    end
    out
  end

  # A UTF-16 or UTF-32 String inspected as ruby writes one: ASCII as it
  # is, every other character as \u, and bytes that make no character
  # as \x. A dummy name has no characters to show, so every byte is \x,
  # except a control byte that has its own escape, such as \n.
  def unit_inspect
    Primitive.attr! :hidden
    return "\"#{OWN[:each_byte].bind_call(self).map { |byte| byte < 32 && DUMP_ESCAPES[byte] || format('\x%02X', byte) }.join}\"" unless Encoding.wide?(Encoding.at(Primitive.zr_str_encoding_index_m(self)))

    chars = characters.to_a
    out = +"\""
    chars.each_index do |i|
      char = chars[i]
      unless char.valid_encoding?
        char.each_byte { |byte| out << format("\\x%02X", byte) }
        next
      end
      point = char.ord
      after = chars[i + 1]
      out << if (escape = UNIT_ESCAPES[point]) then escape
             elsif point == 35 then after&.valid_encoding? && [123, 36, 64].include?(after.ord) ? "\\#" : "#"
             elsif point < 32 || point == 127 then format("\\u%04X", point)
             elsif point < 128 then Primitive.zr_str_from_byte(point)
             elsif point > 0xFFFF then format("\\u{%X}", point)
             else format("\\u%04X", point)
             end
    end
    out << "\""
  end

  # Whether inspect escapes this code point rather than showing it.
  # onigmo calls a code point with no category of its own unprintable.
  # The table contains those as runs of a first point and a length.
  def self.unprintable?(point)
    Primitive.attr! :hidden
    return false if point < 128

    low = 0
    high = (UNPRINTABLE_RUNS.size / 2) - 1
    while low <= high
      middle = (low + high) / 2
      first = UNPRINTABLE_RUNS[middle * 2]
      if point < first
        high = middle - 1
      elsif point >= first + UNPRINTABLE_RUNS[(middle * 2) + 1]
        low = middle + 1
      else
        return true
      end
    end
    false
  end
  private_class_method :unprintable?

  # A UTF-8 String inspected as ruby writes one: a character that has a
  # category of its own as it is, one that has none as \u, and bytes
  # that make no character as \x.
  def utf8_inspect
    Primitive.attr! :hidden
    # A character prints as itself only in the encoding that inspect
    # returns; UTF8-MAC and the carriers' UTF-8 show its code point.
    own = Primitive.zr_str_encoding_index_m(self) == Primitive.zr_inspect_index_m
    out = +"\""
    i = 0
    while i < Primitive.zr_str_bytesize(self)
      n = Primitive.zr_str_char_len_at_m(self, i)
      if n == 1
        byte = Primitive.zr_str_byte_at(self, i)
        out << if (escape = UNIT_ESCAPES[byte]) then escape
               elsif byte == 35 then [123, 36, 64].include?(Primitive.zr_str_byte_at(self, i + 1)) ? "\\#" : "#"
               elsif byte < 32 || byte == 127 then format("\\u%04X", byte)
               # A single byte above ASCII makes no character here, so
               # it represents itself, not a code point.
               elsif byte > 127 then format("\\x%02X", byte)
               else Primitive.zr_str_from_byte(byte)
               end
      else
        char = byteslice(i, n)
        if !char.valid_encoding?
          char.each_byte { |stray| out << format("\\x%02X", stray) }
        elsif !own || String.send(:unprintable?, char.ord)
          point = char.ord
          out << (point > 0xFFFF ? format("\\u{%X}", point) : format("\\u%04X", point))
        else
          out << char
        end
      end
      i += n
    end
    out << "\""
  end

  # A code point appended to a UTF-16 or UTF-32 String, as its code
  # units.
  def append_unit_point(point)
    Primitive.attr! :hidden
    raise RangeError, "#{point} out of char range" if point < 0
    raise RangeError, "invalid codepoint 0x#{format('%X', point)} in #{Encoding.at(Primitive.zr_str_encoding_index_m(self))}" if point > 0x10FFFF || (point >= 0xD800 && point <= 0xDFFF)

    self << [point].pack("U").encode(Encoding.at(Primitive.zr_str_encoding_index_m(self)))
  end

  # The text that `dump` wrote, read back; a trailing
  # `.force_encoding(...)` gives the encoding.
  # str_undump: the inverse of dump, byte by byte. Every error is a
  # RuntimeError, as CRuby raises them.
  def undump
    raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{encoding}" unless encoding.ascii_compatible?
    raise RuntimeError, +"non-ASCII character detected" unless Primitive.zr_str_ascii_only_m(self)
    raise RuntimeError, +"string contains null byte" if include?("\0")

    bytes = b
    invalid = +"invalid dumped string; not wrapped with '\"' nor '\"...\".force_encoding(\"...\")' form"
    raise RuntimeError, invalid if bytes.bytesize < 2 || bytes.getbyte(0) != 0x22

    out = +"".b
    state = { utf8: false, binary: false }
    target = encoding
    i = 1
    loop do
      raise RuntimeError, +"unterminated dumped string" if i >= bytes.bytesize

      byte = bytes.getbyte(i)
      if byte == 0x22
        rest = bytes.byteslice(i + 1, bytes.bytesize - i - 1)
        break if rest.empty?

        rest = rest.delete_prefix(".dup") if rest.bytesize > 4
        head = ".force_encoding(\""
        raise RuntimeError, invalid unless rest.bytesize > head.bytesize && rest.start_with?(head)
        raise RuntimeError, +"dumped string contained Unicode escape but used force_encoding" if state[:utf8]

        name = rest.byteslice(head.bytesize, rest.bytesize - head.bytesize)
        close = name.index("\"")
        raise RuntimeError, invalid unless close && name.bytesize - close == 2 && name.end_with?("\")")

        target = Encoding.find(name.byteslice(0, close)) rescue raise(RuntimeError, +"dumped string has unknown encoding name")
        break
      end
      if byte == 0x5C
        i += 1
        raise RuntimeError, +"invalid escape" if i >= bytes.bytesize

        i = undump_escape(bytes, i, out, state)
        target = Encoding::UTF_8 if state[:utf8]
      else
        out << byte
        i += 1
      end
    end
    out.force_encoding(target)
  end

  # undump_after_backslash: the escape at `i`, onto `out`. Returns the
  # index after it.
  def undump_escape(bytes, i, out, state)
    Primitive.attr! :hidden
    c = bytes.getbyte(i)
    case c
    when 0x5C, 0x22, 0x23 then out << c
    when 0x6E then out << 10
    when 0x72 then out << 13
    when 0x74 then out << 9
    when 0x66 then out << 12
    when 0x76 then out << 11
    when 0x62 then out << 8
    when 0x61 then out << 7
    when 0x65 then out << 27
    when 0x75
      raise RuntimeError, +"hex escape and Unicode escape are mixed" if state[:binary]

      state[:utf8] = true
      i += 1
      raise RuntimeError, +"invalid Unicode escape" if i >= bytes.bytesize
      return undump_braced(bytes, i + 1, out) if bytes.getbyte(i) == 0x7B

      hex = bytes.byteslice(i, 4)[/\A\h*/]
      raise RuntimeError, +"invalid Unicode escape" unless hex.bytesize == 4

      out << undump_point(hex.to_i(16))
      return i + 4
    when 0x78
      i += 1
      raise RuntimeError, +"invalid hex escape" if i >= bytes.bytesize

      hex = bytes.byteslice(i, 2)[/\A\h*/]
      raise RuntimeError, +"invalid hex escape" unless hex.bytesize == 2

      byte = hex.to_i(16)
      # Only a byte past ASCII makes the string binary.
      if byte >= 0x80
        raise RuntimeError, +"hex escape and Unicode escape are mixed" if state[:utf8]

        state[:binary] = true
      end
      out << byte
      return i + 2
    else
      out << 0x5C << c
    end
    i + 1
  end

  # The `\u{...}` form: code points apart by spaces, up to the brace.
  def undump_braced(bytes, i, out)
    Primitive.attr! :hidden
    loop do
      raise RuntimeError, +"unterminated Unicode escape" if i >= bytes.bytesize
      return i + 1 if bytes.getbyte(i) == 0x7D

      if [0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D].include?(bytes.getbyte(i))
        i += 1
        next
      end
      hex = bytes.byteslice(i, bytes.bytesize - i)[/\A\h*/]
      raise RuntimeError, +"invalid Unicode escape" if hex.empty? || hex.bytesize > 6

      point = hex.to_i(16)
      raise RuntimeError, +"invalid Unicode codepoint (too large)" if point > 0x10FFFF

      out << undump_point(point)
      i += hex.bytesize
    end
  end

  def undump_point(point)
    Primitive.attr! :hidden
    raise RuntimeError, +"invalid Unicode codepoint" if point.between?(0xD800, 0xDFFF)

    point.chr(Encoding::UTF_8).b
  end

  def hex
    ascii_compatible!
    lenient_integer(16)
  end

  def oct
    ascii_compatible!
    lenient_integer(-8)
  end

  def center(width, pad = (nopad = true)) = justify(width, nopad ? nil : pad, :center)

  def ljust(width, pad = (nopad = true)) = justify(width, nopad ? nil : pad, :left)

  def rjust(width, pad = (nopad = true)) = justify(width, nopad ? nil : pad, :right)

  def to_i(base = 10)
    ascii_compatible!
    base = Primitive.zr_index_operand_m(base)
    raise ArgumentError, "invalid radix #{base}" if base < 0 || base == 1 || base > 36
    if base == 10
      fast = Primitive.zr_str_to_i10(self)
      return fast unless fast.nil?
    end
    return lenient_integer(base == 0 ? -10 : base) if base != 10 || OWN[:include?].bind_call(self, "0d") || OWN[:include?].bind_call(self, "0D")

    i = 0
    i += 1 while i < Primitive.zr_str_bytesize(self) && space_byte?(Primitive.zr_str_byte_at(self, i))
    sign = 1
    if i < Primitive.zr_str_bytesize(self) && (Primitive.zr_str_byte_at(self, i) == 45 || Primitive.zr_str_byte_at(self, i) == 43)
      sign = -1 if Primitive.zr_str_byte_at(self, i) == 45
      i += 1
    end
    n = 0
    seen = false
    while i < Primitive.zr_str_bytesize(self)
      b = Primitive.zr_str_byte_at(self, i)
      if b == 95 && seen && i + 1 < Primitive.zr_str_bytesize(self) && digit_byte?(Primitive.zr_str_byte_at(self, i + 1))
        i += 1
        next
      end
      break unless digit_byte?(b)

      n = n * 10 + (b - 48)
      seen = true
      i += 1
    end
    sign * n
  end

  # `casecmp` folds ASCII only; `casecmp?` folds all of Unicode. Two
  # Strings with no encoding in common return nil, as str_casecmp does.
  def casecmp(other)
    other = String.try_convert(other)
    return nil unless other && Encoding.compatible?(self, other)

    OWN[:<=>].bind_call(OWN[:downcase].bind_call(self, :ascii), OWN[:downcase].bind_call(other, :ascii))
  end

  def casecmp?(other)
    other = String.try_convert(other)
    return nil unless other && Encoding.compatible?(self, other)

    OWN[:==].bind_call(OWN[:downcase].bind_call(self, :fold), OWN[:downcase].bind_call(other, :fold))
  end

  def chr = (Primitive.zr_str_bytesize(self) == 0) ? +"" : OWN[:[]].bind_call(self, 0)

  # Ruby runs `=~` as an instruction (opt_regexpmatch2), with no frame.
  def =~(other)
    Primitive.attr! :frameless
    raise TypeError, +"wrong argument type String (expected Regexp)" if other.is_a?(String)
    return other.send(:=~, self) if other.is_a?(Regexp)

    other =~ self
  end

  # rb_str_match_m: a call of the pattern's own `match`, which a program
  # may define, with every argument after the pattern.
  def match(*args, &block)
    raise ArgumentError, +"wrong number of arguments (given 0, expected 1..2)" if args.empty?

    String.send(:pattern_of, args[0]).__send__(:match, self, *args.drop(1), &block)
  end

  def match?(pattern, pos = 0) = String.send(:pattern_of, pattern).match?(self, pos)

  # get_pat: a Regexp, or a String compiled as one.
  def self.pattern_of(pattern)
    Primitive.attr! :hidden
    return pattern if pattern.is_a?(Regexp)

    text = String.try_convert(pattern)
    raise TypeError, "wrong argument type #{conversion_name(pattern)} (expected Regexp)" if text.nil?

    Regexp.new(text)
  end
  private_class_method :pattern_of

  def encoding = Encoding.at(Primitive.zr_str_encoding_index_m(self))

  def force_encoding(encoding)
    Primitive.zr_frozen_error(self) if Primitive.zr_modify_frozen_m(self)
    # Encoding.find gives nil only for "internal" while it is unset, an
    # alias of BINARY to force_encoding (enc_set_default_encoding).
    Primitive.zr_str_set_index_m(self, Encoding.carried(Encoding.find(encoding) || Encoding::BINARY))
  end

  # A copy of the receiver's characters written in `target`. Every pair
  # meets in UTF-8, so a conversion between two other encodings is two
  # steps and reads as one in its errors.
  # With no target, str_transcode0 converts to the default internal
  # encoding, replacing what it cannot write; with none set, only a
  # decorator converts, within the receiver's own encoding.
  def encode(target = (implicit = true; Encoding.default_internal), source = nil, **options)
    if implicit
      return copied if target.nil? && options.empty?

      target ||= Encoding.at(Primitive.zr_str_encoding_index_m(self))
      explicit = options[:invalid] == :replace
      options = { invalid: :replace, undef: :replace, **options }
    end
    Encoding.send(:check_options, options)
    from, target = Encoding.pair(source.nil? ? Encoding.at(Primitive.zr_str_encoding_index_m(self)) : source, target)
    options = Encoding.send(:one_newline, options, from, target)
    Encoding.send(:check_replacement, self, from, target, options)
    text = escaped(source.nil? ? plain : copied.force_encoding(from), options)
    # No conversion, but an `invalid: :replace` the caller wrote still
    # takes out the bytes that make no character; the one an encode with
    # no target implies does not (str_transcode0's
    # explicitly_invalid_replace).
    if from.equal?(target) && (!implicit || explicit) && options[:invalid] == :replace && !text.valid_encoding?
      text = text.scrub(Encoding.send(:replacement, target, options))
    end
    # The quotes around an attribute are characters of the text, so
    # they convert to the target with it. If they were written after the
    # conversion, they would contain the source's own bytes.
    text = "\"#{text}\"" if options[:xml] == :attr
    # ruby's newline decorators work on the ASCII side of the
    # conversion: before it when the source is ASCII-compatible, after
    # it when only the target is, and through UTF-8 between two wide
    # encodings.
    return Encoding.convert(text, target, options) unless options[:newline]
    return Encoding.convert(newlines(text, options), target, options) if text.encoding.ascii_compatible?
    return newlines(Encoding.convert(text, target, options), options) if target.ascii_compatible?

    Encoding.convert(newlines(Encoding.convert(text, Encoding::UTF_8, options), options), target, options)
  end

  # A code point appended to a String in a multibyte encoding: the bytes
  # that spell it, which the encoding must hold as one character.
  def append_mb_point(point)
    Primitive.attr! :hidden
    self << point.chr(Encoding.at(Primitive.zr_str_encoding_index_m(self)))
  end

  # A String in a multibyte encoding, as CRuby's rb_str_inspect writes
  # one. A character that represents no Unicode point prints as the
  # number of its own bytes. Bytes that make no character print one by
  # one. CESU-8's characters are Unicode's, and print as Unicode's.
  def mb_inspect
    Primitive.attr! :hidden
    index = Primitive.zr_str_encoding_index_m(self)
    encoding = Encoding.at(index)
    cesu = encoding.name == +"CESU-8"
    # In the result encoding, a printable character prints as itself.
    own = index == Primitive.zr_inspect_index_m
    out = own ? (+"\"").force_encoding(encoding) : +"\""
    run = +"".b
    OWN[:each_char].bind_call(self) do |char|
      if char.bytesize == 1 && char.getbyte(0) < 128
        run << char
        next
      end
      out << ascii_escaped(run, cesu)
      run = +"".b
      out << if own && char.valid_encoding? && char.match?(/[[:print:]]/)
               char
             elsif !char.valid_encoding?
               char.bytes.map { |byte| "\\x#{format('%02X', byte)}" }.join
             elsif cesu
               point = char.ord
               point > 0xFFFF ? format("\\u{%X}", point) : format("\\u%04X", point)
             elsif char.bytesize == 1
               # rb_str_buf_cat_escaped_char writes a one-byte
               # character as a byte.
               format("\\x%02X", char.getbyte(0))
             else
               "\\x{#{format('%X', char.ord)}}"
             end
    end
    out << ascii_escaped(run, cesu) << "\""
  end

  # An ASCII run escaped as any String is. The runtime's own inspect
  # returns this after the bytes are tagged as UTF-8.
  def ascii_escaped(run, unicode = false)
    Primitive.attr! :hidden
    return +"" if run.empty?

    shown = run.dup.force_encoding(Encoding::UTF_8).inspect
    shown = shown.byteslice(1, shown.bytesize - 2)
    return shown if unicode

    # An encoding that is not Unicode writes a control byte as a byte.
    shown.gsub(/\\(\\|u00([0-7][0-9A-F]))/) { $2 ? "\\x#{$2}" : $& }
  end

  # `xml: :text` writes the three characters XML reserves as entities,
  # and `:attr` the quote as well. A character the target has no room
  # for then becomes a numeric reference rather than an error.
  def escaped(text, options)
    Primitive.attr! :hidden
    marks = case options[:xml]
            when nil then return text
            when :text then { "&" => +"&amp;", "<" => +"&lt;", ">" => +"&gt;" }
            when :attr then { "&" => +"&amp;", "<" => +"&lt;", ">" => +"&gt;", "\"" => +"&quot;", "'" => +"&apos;" }
            else raise ArgumentError, "unexpected value for xml option: #{options[:xml]}"
            end
    pattern = /[#{Regexp.escape(marks.keys.join)}]/
    encoding = Encoding.at(Primitive.zr_str_encoding_index_m(text))
    return text.gsub(pattern, marks) unless encoding.ascii_compatible?

    # The escape reads bytes, as the converter does: a byte that is in no
    # character goes through as it is.
    text.b.gsub(pattern, marks).force_encoding(encoding)
  end

  # `newline:` and the older spellings of the same three choices
  # rewrite the line ends once the conversion is done.
  def newlines(text, options)
    Primitive.attr! :hidden
    case (kind = options[:newline])
    when nil then text
    when :universal, :lf then text.gsub(/\r\n|\r/, "\n")
    when :cr then text.gsub("\n", "\r")
    when :crlf then text.gsub("\n", "\r\n")
    else Encoding.send(:newline_decorator, kind) # refuses it, as a converter does
    end
  end

  # `String.new(source, encoding:, capacity:)`. The capacity is not
  # reserved: the buffer grows as the bytes arrive.
  #
  # With no source the String keeps its bytes, unless a capacity is
  # given, which discards the bytes. In both cases it keeps its
  # encoding. A new String is binary because `allocate` made it so.
  def initialize(source = (none = true), encoding: nil, capacity: nil)
    # A frozen String takes no argument, as CRuby's rb_str_init checks;
    # with none there is nothing to change.
    if frozen?
      return self if none && encoding.nil? && capacity.nil?

      Primitive.zr_frozen_error(self)
    end
    if capacity
      # A capacity no allocator can supply is a NoMemoryError, as ruby
      # reserves the capacity it is given.
      capacity = Primitive.zr_index_operand_m(capacity)
      raise NoMemoryError, +"failed to allocate memory" if capacity > 268_435_456 && !Primitive.zr_memory_for_p(capacity)
    end
    if none
      Primitive.zr_str_discard(self) if capacity
    else
      Primitive.zr_str_initialize_m(self, Primitive.zr_str_operand(source))
    end
    OWN[:force_encoding].bind_call(self, encoding) if encoding
    self
  end

  def encode!(*args, **options)
    Primitive.zr_str_replace(self, OWN[:encode].bind_call(self, *args, **options))
  end

  # UTF-16 and UTF-32 are never ASCII, not even empty.
  def ascii_only? = Primitive.zr_str_ascii_only_m(self)

  def valid_encoding? = Primitive.zr_str_valid_p(self)

  # Replaces every invalid byte with `replacement` (U+FFFD, or the
  # block's return value for the bad bytes).
  def scrub(replacement = nil)
    return copied if Primitive.zr_str_valid_p(self)

    encoding = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    replacement = scrub_replacement(replacement, encoding) unless replacement.nil?
    # U+FFFD in UTF-8 itself and in UTF-16 and UTF-32; "?" in every other
    # encoding, UTF8-MAC and CESU-8 as well.
    if replacement.nil? && !block_given?
      replacement = if Encoding.wide?(encoding) then "\uFFFD".encode(encoding)
                    elsif encoding.equal?(Encoding::UTF_8) then +"\uFFFD"
                    else +"?"
                    end
    end
    mb = Encoding.mb?(encoding)
    out = empty_like
    i = 0
    while i < Primitive.zr_str_bytesize(self)
      step = Primitive.zr_str_char_len_at_m(self, i)
      piece = byteslice(i, step)
      if piece.valid_encoding?
        out << piece
      else
        if mb
          piece = byteslice(i, step = mb_scrub_len(i))
        elsif encoding.equal?(Encoding::UTF_8)
          piece = byteslice(i, step = utf8_scrub_len(i))
        end
        out << (block_given? ? scrub_replacement(yield(piece), encoding) : replacement)
      end
      i += step
    end
    out
  end

  # rb_enc_str_scrub's run of broken bytes at `at` in a multibyte
  # encoding: the rest of the text when a character stops inside it,
  # else the longest start of a character shorter than the encoding's
  # longest, or one byte.
  def mb_scrub_len(at)
    Primitive.attr! :hidden
    size = Primitive.zr_str_bytesize(self)
    return size - at if Primitive.zr_str_mb_precise_len_m(self, at, size) < -1

    clen = [Primitive.zr_str_mb_max_len_m(self), size - at].min
    return 1 if clen <= 2

    clen -= 1
    clen -= 1 while clen > 1 && Primitive.zr_str_mb_precise_len_m(self, at, at + clen) == -1
    clen
  end

  # mb_scrub_len for UTF-8, over rb_enc_precise_mbclen's answer for the
  # bytes from `at` to `stop`: a whole character, a character cut off at
  # `stop` (:more), or bytes that start no character (:bad).
  def utf8_scrub_len(at)
    Primitive.attr! :hidden
    size = Primitive.zr_str_bytesize(self)
    return size - at if utf8_precise(at, size) == :more

    clen = [4, size - at].min
    return 1 if clen <= 2

    clen -= 1
    clen -= 1 while clen > 1 && utf8_precise(at, at + clen) == :bad
    clen
  end

  def utf8_precise(at, stop)
    Primitive.attr! :hidden
    lead = Primitive.zr_str_byte_at(self, at)
    need, low, high = if lead < 0x80 then [1, 0x80, 0xBF]
                      elsif lead.between?(0xC2, 0xDF) then [2, 0x80, 0xBF]
                      elsif lead == 0xE0 then [3, 0xA0, 0xBF]
                      elsif lead == 0xED then [3, 0x80, 0x9F]
                      elsif lead.between?(0xE1, 0xEF) then [3, 0x80, 0xBF]
                      elsif lead == 0xF0 then [4, 0x90, 0xBF]
                      elsif lead.between?(0xF1, 0xF3) then [4, 0x80, 0xBF]
                      elsif lead == 0xF4 then [4, 0x80, 0x8F]
                      else return :bad
                      end
    k = 1
    while k < need
      return :more if at + k >= stop

      byte = Primitive.zr_str_byte_at(self, at + k)
      return :bad unless k == 1 ? byte.between?(low, high) : byte.between?(0x80, 0xBF)

      k += 1
    end
    need
  end

  # str_compat_and_valid: a replacement that is whole, and in the
  # receiver's encoding, or plain ASCII where ASCII is one byte.
  def scrub_replacement(text, encoding)
    Primitive.attr! :hidden
    text = String.try_convert(text) or raise TypeError, "no implicit conversion of #{conversion_name(text)} into String"
    raise ArgumentError, "replacement must be valid byte sequence '#{text.inspect}'" unless text.valid_encoding?
    unless text.ascii_only? ? !Encoding.wide?(encoding) : text.encoding.equal?(encoding)
      raise Encoding::CompatibilityError, "incompatible character encodings: #{Encoding.shown(encoding)} and #{Encoding.shown(text.encoding)}"
    end

    text
  end

  def scrub!(replacement = nil, &block)
    # A valid String is left alone, frozen or not.
    return self if Primitive.zr_str_valid_p(self)

    mutate(OWN[:scrub].bind_call(self, replacement, &block))
    self
  end

  # Whether byte `at` starts a character (or ends the text). A
  # continuation byte is inside a character only when the nearest lead
  # byte before it, at most three back, starts a sequence that reaches it;
  # a stray one is a character of its own.
  def char_boundary?(at)
    Primitive.attr! :hidden
    head = Primitive.zr_str_char_head_m(self, at)
    return head unless head.nil?
    return true if at >= Primitive.zr_str_bytesize(self) || (Primitive.zr_str_byte_at(self, at) & 0xC0) != 0x80

    lead = at - 1
    lead -= 1 while lead > 0 && at - lead < 3 && (Primitive.zr_str_byte_at(self, lead) & 0xC0) == 0x80
    lead < 0 || Primitive.zr_str_char_len_at_m(self, lead) <= at - lead
  end

  def byteindex(needle, start = 0)
    start = Primitive.zr_index_operand_m(start)
    needle = Primitive.zr_str_operand(needle) unless needle.is_a?(Regexp)
    start += Primitive.zr_str_bytesize(self) if start < 0
    return Primitive.zr_backref_set(nil) if (start < 0 || start > Primitive.zr_str_bytesize(self)) && needle.is_a?(Regexp)
    return nil if start < 0 || start > Primitive.zr_str_bytesize(self)
    raise IndexError, "offset #{start} does not land on character boundary" unless char_boundary?(start)

    if needle.is_a?(Regexp)
      match = needle.send(:search, self, start, false)
      Primitive.zr_backref_set(match)
      return match && match.send(:begin_at, 0)
    end
    byte_index(needle, start)
  end

  def byterindex(needle, start = Primitive.zr_str_bytesize(self))
    start = Primitive.zr_index_operand_m(start)
    needle = Primitive.zr_str_operand(needle) unless needle.is_a?(Regexp)
    start += Primitive.zr_str_bytesize(self) if start < 0
    return Primitive.zr_backref_set(nil) if start < 0 && needle.is_a?(Regexp)
    return nil if start < 0

    start = Primitive.zr_str_bytesize(self) if start > Primitive.zr_str_bytesize(self)
    raise IndexError, "offset #{start} does not land on character boundary" unless char_boundary?(start)

    if needle.is_a?(Regexp)
      match = needle.send(:search, self, start, true)
      Primitive.zr_backref_set(match)
      return match && match.send(:begin_at, 0)
    end
    needle = joined(Primitive.zr_str_operand(needle))
    return nil unless needle.valid_encoding?

    i = [start, Primitive.zr_str_bytesize(self) - needle.bytesize].min
    i -= 1 while i >= 0 && !(char_boundary?(i) && byteslice_of(i, needle.bytesize) == needle)
    i >= 0 ? i : nil
  end

  # Ruby's own normalize.rb does the work. A program that calls one of
  # these methods by name arms its load, which runs on the first call.
  NORMALIZER = []
  private_constant :NORMALIZER

  def self.normalizer=(load)
    Primitive.attr! :hidden
    NORMALIZER[0] = load
  end

  def unicode_normalize(form = :nfc) = normalizer.normalize(self, form)

  def unicode_normalize!(form = :nfc) = Primitive.zr_str_replace(self, OWN[:unicode_normalize].bind_call(self, form))

  def unicode_normalized?(form = :nfc) = normalizer.normalized?(self, form)

  def normalizer
    Primitive.attr! :hidden
    unless NORMALIZER[1]
      Primitive.zr_unimplemented(+"String#unicode_normalize through a name the program never spells") unless NORMALIZER[0]
      NORMALIZER[0].call
      NORMALIZER[1] = ::UnicodeNormalize
    end
    NORMALIZER[1]
  end

  # A grapheme cluster is what the regex engine's `\\X` matches from
  # each place in turn, as rb_str_enumerate_grapheme_clusters takes them.
  def each_grapheme_cluster(&block)
    return to_enum(:each_grapheme_cluster) { OWN[:grapheme_clusters].bind_call(self).size } unless block

    OWN[:grapheme_clusters].bind_call(self).each(&block)
    self
  end

  # A byte that is in no character is a cluster by itself. An encoding
  # that is not Unicode has only characters.
  def grapheme_clusters(&block)
    if block
      OWN[:grapheme_clusters].bind_call(self).each(&block)
      return self
    end

    encoding = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    return characters unless Primitive.zr_table_member_p(GRAPHEMES, encoding.name)
    return wide_clusters unless encoding.ascii_compatible? && encoding.name != +"CESU-8"

    out = []
    at = 0
    size = Primitive.zr_str_bytesize(self)
    # get_reg_grapheme_cluster: `\X` compiled for the String's encoding.
    program = /\X/.send(:program_in, encoding)
    while at < size
      offsets = Primitive.zr_regexp_match_at(/\X/, program, self, at)
      break if offsets.nil? || offsets[2] <= at

      out << Primitive.zr_str_byteslice(self, at, offsets[2] - at)
      at = offsets[2]
    end
    out
  end

  # The clusters of a UTF-16, UTF-32 or CESU-8 string: the engine reads
  # none of them as Unicode, so the clusters are found in UTF-8 and the
  # characters of the receiver taken in those counts.
  def wide_clusters
    Primitive.attr! :hidden
    chars = engine_whole(characters)
    text = chars.map { |c| Primitive.zr_str_valid_p(c) ? c.encode(Encoding::UTF_8) : +"\uFFFD" }.join
    at = 0
    OWN[:grapheme_clusters].bind_call(text).map do |cluster|
      part = chars[at, Primitive.zr_str_length_m(cluster)].join
      at += Primitive.zr_str_length_m(cluster)
      part
    end
  end

  protected

  def byteslice_of(start, length)
    Primitive.attr! :hidden
    Primitive.zr_str_byteslice(self, start, length)
  end

  # The receiver's bytes and encoding in a new String, as rb_str_dup makes
  # one: never through String.new, which runs a program's initialize.
  def copied
    Primitive.attr! :hidden
    Primitive.zr_str_byteslice(self, 0, Primitive.zr_str_bytesize(self))
  end

  # The receiver as a plain String, which code written for String's own
  # bytes reads as the C reads a subclass's: never through its methods.
  def plain
    Primitive.attr! :hidden
    Primitive.zr_real_class(self).equal?(String) ? self : copied
  end

  # The characters as an Array, walked as each_char walks them, for the
  # methods that read them all: an Enumerator over the receiver would
  # call its each_char again.
  # The characters up to the first whose lead needs more bytes than
  # are left: the engine's `\X` does not match there, and ruby's clusters
  # end. (A lone lead surrogate in the middle of a UTF-16 string stays
  # one character here; ruby's engine splits its bytes.)
  def engine_whole(chars)
    Primitive.attr! :hidden
    name = Encoding.at(Primitive.zr_str_encoding_index_m(self)).name
    return chars if name == +"CESU-8"

    size = Primitive.zr_str_bytesize(self)
    at = 0
    chars.take_while do |c|
      lead = name.end_with?("LE") ? c.getbyte(1) : c.getbyte(0)
      want = name.start_with?("UTF-32") || (lead && lead & 0xFC == 0xD8) ? 4 : 2
      whole = at + want <= size
      at += Primitive.zr_str_bytesize(c)
      whole
    end
  end

  def characters
    Primitive.attr! :hidden
    out = []
    OWN[:each_char].bind_call(self) { |c| out << c }
    out
  end

  private

  # Membership in the intersection of `sets`, each a tr-style spec:
  # characters, `a-z` ranges, and a leading `^` for the complement.
  def charset_test(sets)
    Primitive.attr! :hidden
    tests = sets.map do |spec|
      ranges, negated = charset(joined(Primitive.zr_str_operand(spec)))
      negated ? ->(cp) { !charset_cover?(ranges, cp) } : ->(cp) { charset_cover?(ranges, cp) }
    end
    ->(cp) { tests.all? { |test| test.call(cp) } }
  end

  # The characters a tr spec names, as codepoint ranges in the order
  # they are written, and whether a leading `^` negates the set. A
  # range stays a range so that `"\\x00-\\x{10FFFF}"` costs one row.
  def charset(spec)
    Primitive.attr! :hidden
    cps = spec.codepoints
    negated = cps.size > 1 && cps[0] == 94
    cps.shift if negated
    ranges = []
    i = 0
    while i < cps.size
      if cps[i] == 92 && i + 1 < cps.size
        ranges << (cps[i + 1]..cps[i + 1])
        i += 2
      elsif i + 2 < cps.size && cps[i + 1] == 45
        raise ArgumentError, "invalid range \"#{char_of(cps[i], spec.encoding)}-#{char_of(cps[i + 2], spec.encoding)}\" in string transliteration" if cps[i] > cps[i + 2]

        ranges << (cps[i]..cps[i + 2])
        i += 3
      else
        ranges << (cps[i]..cps[i])
        i += 1
      end
    end
    [ranges, negated]
  end

  def charset_cover?(ranges, cp)
    Primitive.attr! :hidden
    ranges.any? { |range| cp >= range.begin && cp <= range.end }
  end

  # The place `cp` last takes in the expanded spec, or nil. A spec may
  # name a character twice, and ruby lets the later place win.
  def charset_index(ranges, cp)
    Primitive.attr! :hidden
    at = nil
    base = 0
    ranges.each do |range|
      at = base + cp - range.begin if cp >= range.begin && cp <= range.end
      base += range.end - range.begin + 1
    end
    at
  end

  # The codepoint at position `n` in the expanded spec. The last one
  # is used for every position past the end.
  def charset_at(ranges, n)
    Primitive.attr! :hidden
    base = 0
    ranges.each do |range|
      width = range.end - range.begin + 1
      return range.begin + n - base if n - base < width

      base += width
    end
    ranges.last.end
  end

  # tr: each character in `from` becomes the character at the same
  # place in `to`, the last one standing in for the rest; a negated
  # `from` maps every other character to the last of `to`. `squeeze`
  # collapses runs of one translated character.
  def translate(from, to, squeeze)
    Primitive.attr! :hidden
    source, negated = charset(joined(Primitive.zr_str_operand(from)))
    to = joined(Primitive.zr_str_operand(to))
    target, = charset(to)
    # tr_trans: the result takes the encoding that rb_enc_check gives the
    # receiver and the replacement, so an ASCII-only receiver can take
    # the replacement's.
    enc = Encoding.compatible?(self, to) || Encoding.at(Primitive.zr_str_encoding_index_m(self))
    out = OWN[:force_encoding].bind_call(+"", enc)
    last = nil
    changed = false
    OWN[:each_char].bind_call(self) do |c|
      at = charset_index(source, c.ord)
      unless at.nil? == negated
        out << c
        last = nil
        next
      end
      changed = true
      if target.empty?
        last = nil
        next
      end
      mapped = negated ? target.last.end : charset_at(target, at)
      out << char_of(mapped, enc) unless squeeze && mapped == last
      last = mapped
    end
    # tr_trans changes nothing when no character matched, so the copy
    # keeps the receiver's encoding.
    return copied unless changed

    OWN[:force_encoding].bind_call(out, enc)
  end

  def char_of(cp, enc)
    Primitive.attr! :hidden
    cp.chr(enc)
  end

  def digits?
    Primitive.attr! :hidden
    !(Primitive.zr_str_bytesize(self) == 0) && OWN[:each_byte].bind_call(self).all? { |b| b >= 48 && b <= 57 }
  end

  # The bytes that ISSPACE takes as space.
  SPACE_BYTES = [9, 10, 11, 12, 13, 32].freeze
  private_constant :SPACE_BYTES

  # An Integer read the way `hex` and `oct` read one: whitespace, a
  # sign, a base prefix, digits with single underscores, and nothing
  # past the first stray byte. A negative base means the prefix picks
  # the base.
  def lenient_integer(base)
    Primitive.attr! :hidden
    # rb_int_parse_cstr skips ASCII space bytes only, so bytes that make
    # no character after them are just not digits.
    start = 0
    start += 1 while start < Primitive.zr_str_bytesize(self) && SPACE_BYTES.include?(Primitive.zr_str_byte_at(self, start))
    text = byteslice_of(start, Primitive.zr_str_bytesize(self) - start)
    i = 0
    sign = 1
    if text.getbyte(i) == 45 || text.getbyte(i) == 43
      sign = -1 if text.getbyte(i) == 45
      i += 1
    end
    if text.getbyte(i) == 48 && text.getbyte(i + 1)
      chosen = { 120 => 16, 88 => 16, 98 => 2, 66 => 2, 111 => 8, 79 => 8, 100 => 10, 68 => 10 }[text.getbyte(i + 1)]
      if chosen && (base < 0 || chosen == base)
        base = chosen
        i += 2
      elsif base == -10
        base = 8
        i += 1
      end
    end
    base = -base if base < 0
    value = 0
    seen = false
    while i < text.bytesize
      b = text.getbyte(i)
      if b == 95 && seen && i + 1 < text.bytesize && text.getbyte(i + 1) != 95
        i += 1
        next
      end
      digit = if b >= 48 && b <= 57 then b - 48
              elsif b >= 97 && b <= 122 then b - 87
              elsif b >= 65 && b <= 90 then b - 55
              else 99
              end
      break if digit >= base

      value = value * base + digit
      seen = true
      i += 1
    end
    sign * value
  end

  def mutate(result)
    Primitive.attr! :hidden
    Primitive.zr_frozen_error(self) if Primitive.zr_modify_frozen_m(self)
    return nil if result == self

    Primitive.zr_str_replace(self, result)
  end

  # The receiver becomes `result`, the same text or not.
  def replaced(result)
    Primitive.attr! :hidden
    Primitive.zr_frozen_error(self) if Primitive.zr_modify_frozen_m(self)
    Primitive.zr_str_replace(self, result)
  end

  def space_byte?(b)
    Primitive.attr! :hidden
    b == 32 || (b >= 9 && b <= 13) || b == 0
  end

  def digit_byte?(b)
    Primitive.attr! :hidden
    b >= 48 && b <= 57
  end

  # The start and length a Range names in a string of `size` bytes,
  # or nil when it starts past the end.
  def range_span(range, size)
    Primitive.attr! :hidden
    first = range.begin.nil? ? 0 : Primitive.zr_index_operand_m(range.begin)
    first += size if first < 0
    return nil if first < 0 || first > size

    last = range.end.nil? ? size : Primitive.zr_index_operand_m(range.end)
    last += size if last < 0
    last -= 1 if range.exclude_end? && range.end
    length = last - first + 1
    length = 0 if length < 0
    length = size - first if first + length > size
    [first, length]
  end

  # awk-style words: runs of bytes between whitespace, which for split
  # leaves NUL out. The piece that would reach `limit`, and a last word
  # that runs to the end, are the tail.
  # literal_split_pattern: whether the pattern is one space, read in its
  # own encoding.
  def awk_pattern?(pattern)
    Primitive.attr! :hidden
    enc = Encoding.at(Primitive.zr_str_encoding_index_m(pattern))
    bytes = OWN[:b].bind_call(pattern)
    return bytes == +" " if enc.ascii_compatible?

    code, n = Regexp.encoder(enc).ascget(bytes, 0, false)
    code == 0x20 && n == bytes.bytesize
  end

  def split_words(limit)
    Primitive.attr! :hidden
    return wide_words(limit) if Primitive.zr_str_unit_m(self) != 0

    out = []
    beg = Primitive.zr_str_space_end(self, 0, false)
    while beg < Primitive.zr_str_bytesize(self)
      break if limit > 0 && limit <= out.size + 1

      stop = Primitive.zr_str_word_end(self, beg)
      break if stop == Primitive.zr_str_bytesize(self)

      out << byteslice_of(beg, stop - beg)
      beg = Primitive.zr_str_space_end(self, stop, false)
    end
    split_tail(out, beg, limit)
  end

  # The awk split of rb_str_split_m over code points, for a text of
  # UTF-16 or UTF-32.
  def wide_words(limit)
    Primitive.attr! :hidden
    enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    bytes = OWN[:b].bind_call(self)
    onig = Regexp.encoder(enc)
    e = bytes.bytesize
    out = []
    at = 0
    beg = 0
    stop = 0
    skip = true
    while at < e
      code, n = codepoint_len(bytes, at, onig, enc)
      at += n
      if skip
        if ascii_space?(code)
          beg = at
        else
          stop = at
          skip = false
          break if limit > 0 && limit <= out.size + 1
        end
      elsif ascii_space?(code)
        out << byteslice_of(beg, stop - beg)
        skip = true
        beg = at
      else
        stop = at
      end
    end
    split_tail(out, beg, limit)
  end

  def split_chars(limit)
    Primitive.attr! :hidden
    out = []
    beg = 0
    pieces = 1
    while beg < Primitive.zr_str_bytesize(self)
      step = Primitive.zr_str_char_len_at_m(self, beg)
      out << byteslice_of(beg, step)
      beg += step
      pieces += 1
      break if limit > 0 && limit <= pieces
    end
    split_tail(out, beg, limit)
  end

  def split_by_string(pattern, limit)
    Primitive.attr! :hidden
    pattern = joined(Primitive.zr_str_operand(pattern))
    raise ArgumentError, "invalid byte sequence in #{pattern.encoding}" unless Primitive.zr_str_valid_p(pattern)

    Primitive.zr_str_split_by(self, pattern, limit)
  end

  # The text after the last piece: kept under a limit, or when it is
  # not empty.
  def split_tail(out, beg, limit)
    Primitive.attr! :hidden
    out << byteslice_of(beg, Primitive.zr_str_bytesize(self) - beg) if Primitive.zr_str_bytesize(self) > 0 && (limit != 0 || Primitive.zr_str_bytesize(self) > beg)
    out
  end

  # The first match of a Regexp or String pattern at or after byte
  # `start`, as a MatchData; a String pattern matches its bytes.
  def first_match(pattern, start)
    Primitive.attr! :hidden
    offsets = match_offsets(pattern, start)
    offsets && MatchData.send(:for, pattern, self, offsets)
  end

  # The offsets of the first match of `pattern` at or after byte
  # `start` (`[position, begin, end, ...]`, as a search returns them),
  # or nil. A String pattern matches itself, with no group.
  def match_offsets(pattern, start)
    Primitive.attr! :hidden
    return Primitive.zr_regexp_search(pattern, pattern.send(:program_for, self), self, start, false) if pattern.is_a?(Regexp)
    unless pattern.is_a?(String)
      raise TypeError, "wrong argument type #{conversion_name(pattern)} (expected Regexp)" unless pattern.respond_to?(:to_str)

      pattern = Primitive.zr_str_operand(pattern)
    end
    # get_pat_quoted refuses a String that is not valid in its encoding,
    # with the error of the Regexp that it would make.
    Regexp.new(pattern) unless Primitive.zr_str_valid_p(pattern)

    at = byte_index(pattern, start)
    at && [at, at, at + pattern.bytesize]
  end

  # What replaces one match: the block's return value, the Hash's entry,
  # or the replacement text with its backreferences filled in by
  # rb_reg_regsub. `regexp` is nil for a String pattern.
  def replacement_for(match, replacement, regexp, &block)
    Primitive.attr! :hidden
    whole = Primitive.zr_match_nth(match, 0)
    # rb_obj_as_string: a to_s that gives no String falls back to the
    # default text of the object.
    return Primitive.zr_obj_as_string(yield(whole)) if block && replacement.nil?
    return Primitive.zr_obj_as_string(replacement[whole]) if replacement.is_a?(Hash)

    regsub(replacement.to_str, match, regexp)
  end

  # rb_reg_regsub: `repl` with each `\1`, `\k<name>`, `\0`, `\&`,
  # `` \` ``, `\'`, `\+` and `\\` filled in from the match on the
  # receiver. The replacement is read a character at a time in its own
  # encoding, so a UTF-16 backslash is one and a Shift_JIS trail byte is
  # not. The pieces join as rb_enc_str_buf_cat joins them.
  def regsub(repl, match, regexp)
    Primitive.attr! :hidden
    return repl unless Primitive.zr_str_find_from(repl, "\\", 0)

    bytes = OWN[:b].bind_call(repl)
    enc = Encoding.at(Primitive.zr_str_encoding_index_m(repl))
    compat = enc.ascii_compatible?
    onig = Regexp.encoder(enc)
    e = bytes.bytesize
    val = nil
    p = s = 0
    while s < e
      c, clen = onig.ascget(bytes, s, compat)
      if c.nil?
        s += onig.mbclen(bytes, s)
        next
      end
      ss = s
      s += clen
      next if c != 0x5C || s == e

      val ||= OWN[:force_encoding].bind_call(+"", Encoding::BINARY)
      val.send(:buf_cat, Primitive.zr_str_byteslice(repl, p, ss - p))
      c, clen = onig.ascget(bytes, s, compat)
      if c.nil?
        s += onig.mbclen(bytes, s)
        val.send(:buf_cat, Primitive.zr_str_byteslice(repl, ss, s - ss))
        p = s
        next
      end
      s += clen
      p = s
      case c
      when 0x31..0x39
        next unless regexp && regexp.send(:name_rows).empty?

        no = c - 0x30
      when 0x6B # k
        lt, lt_len = s < e ? onig.ascget(bytes, s, compat) : nil
        if lt != 0x3C
          val.send(:buf_cat, Primitive.zr_str_byteslice(repl, ss, s - ss))
          next
        end
        name = name_end = s + lt_len
        gt_len = 0
        while name_end < e
          gt, gt_len = onig.ascget(bytes, name_end, compat)
          break if gt == 0x3E

          name_end += gt.nil? ? onig.mbclen(bytes, name_end) : gt_len
        end
        raise RuntimeError, +"invalid group name reference format" unless name_end < e

        no = regsub_name_number(regexp, Primitive.zr_str_byteslice(repl, name, name_end - name), match)
        p = s = name_end + gt_len
      when 0x30, 0x26 # 0 &
        no = 0
      when 0x60 # `
        val.send(:buf_cat, byteslice_of(0, match.send(:begin_at, 0)))
        next
      when 0x27 # '
        to = match.send(:end_at, 0)
        val.send(:buf_cat, byteslice_of(to, Primitive.zr_str_bytesize(self) - to))
        next
      when 0x2B # +
        no = match.size - 1
        no -= 1 while no > 0 && match.byteoffset(no)[0].nil?
        next if no == 0
      when 0x5C
        val.send(:buf_cat, Primitive.zr_str_byteslice(repl, s - clen, clen))
        next
      else
        val.send(:buf_cat, Primitive.zr_str_byteslice(repl, ss, s - ss))
        next
      end
      next if no >= match.size

      from, to = match.byteoffset(no)
      val.send(:buf_cat, byteslice_of(from, to - from)) if from
    end
    return repl unless val

    val.send(:buf_cat, Primitive.zr_str_byteslice(repl, p, e - p)) if p < e
    val
  end

  # NAME_TO_NUMBER: the group `\k<name>` reads, the last of a repeated
  # name's groups that took part in the match. A String pattern has no
  # names, and a name whose encoding cannot meet the pattern's names
  # none.
  def regsub_name_number(regexp, name, match)
    Primitive.attr! :hidden
    if regexp && Encoding.compatible?(regexp.source, name)
      row = regexp.send(:name_rows).find { |n, _| n.b == name.b }
      return row[1].reverse.find { |g| match.byteoffset(g)[0] } || row[1].last if row
    end
    raise IndexError, "undefined group name reference: ".b << name.send(:quote_unprintable)
  end

  # rb_str_quote_unprintable: the text as it is when it is printable in
  # the encoding messages are shown in, else escaped.
  def quote_unprintable
    Primitive.attr! :hidden
    enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    shown = Encoding.default_internal || Encoding.default_external
    return escape if !enc.equal?(shown) && !(enc.ascii_compatible? && Primitive.zr_str_ascii_only_m(self))

    bytes = OWN[:b].bind_call(self)
    onig = Regexp.encoder(enc)
    at = 0
    while at < bytes.bytesize
      len = onig.precise_mbclen(bytes, at)
      return escape if len <= 0 || !onig.code_ctype?(onig.mbc_to_code(bytes, at, bytes.bytesize), ONIG_PRINT)

      at += len
    end
    self
  end

  # rb_enc_cr_str_buf_cat: appends `piece` to the receiver, a buffer
  # that only its caller can see. The buffer takes the piece's encoding
  # while it is empty and the two cannot share one, or while it is plain
  # ASCII and the piece is not. Two non-ASCII encodings raise.
  def buf_cat(piece)
    Primitive.attr! :hidden
    enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    other = Encoding.at(Primitive.zr_str_encoding_index_m(piece))
    unless enc.equal?(other)
      if !enc.ascii_compatible? || !other.ascii_compatible?
        return self if Primitive.zr_str_bytesize(piece) == 0

        buf_incompatible(enc, other) unless Primitive.zr_str_bytesize(self) == 0
        OWN[:force_encoding].bind_call(self, other)
      else
        mine = Primitive.zr_str_bytesize(self) == 0 || Primitive.zr_str_ascii_only_m(self)
        theirs = Primitive.zr_str_ascii_only_m(piece)
        buf_incompatible(enc, other) unless mine || theirs
        OWN[:force_encoding].bind_call(self, other) if mine && !theirs
      end
    end
    Primitive.zr_str_cat_bytes(self, piece)
  end

  def buf_incompatible(enc, other)
    Primitive.attr! :hidden
    raise Encoding::CompatibilityError, "incompatible character encodings: #{Encoding.shown(enc)} and #{Encoding.shown(other)}"
  end

  # split by a Regexp, as CRuby walks it: the text between matches with
  # the groups after each; an empty match at the search start skips one
  # character, and splits the next time it is seen there.
  def split_by_regexp(pattern, limit)
    Primitive.attr! :hidden
    out = []
    beg = 0
    start = 0
    last_null = false
    pieces = 1
    # The offsets of each match, as `scan` reads them: no MatchData.
    program = pattern.send(:program_for, self)
    while (offsets = Primitive.zr_regexp_search(pattern, program, self, start, false))
      from = offsets[1]
      to = offsets[2]
      if start == from && from == to
        if Primitive.zr_str_bytesize(self) == 0
          out << ""
          break
        elsif last_null
          out << byteslice_of(beg, Primitive.zr_str_char_len_at_m(self, beg))
          beg = start
        else
          start += start == Primitive.zr_str_bytesize(self) ? 1 : Primitive.zr_str_char_len_at_m(self, start)
          last_null = true
          next
        end
      else
        out << byteslice_of(beg, from - beg)
        beg = start = to
      end
      last_null = false
      group = 3
      while group < offsets.size
        out << slice_at(offsets[group], offsets[group + 1]) if offsets[group] >= 0
        group += 2
      end
      break if limit > 0 && limit <= (pieces += 1)
    end
    split_tail(out, beg, limit)
  end

  # The byte offset of `needle` at or after byte `start`, or nil.
  # A Range of byte offsets as [start, length] within the text.
  # rb_range_beg_len with err 2, for bytesplice: a Range's start and
  # length in `size` bytes, a RangeError past the ends, and a TypeError
  # for any other value.
  def splice_range(range, size)
    Primitive.attr! :hidden
    raise TypeError, "wrong argument type #{range.class} (expected Range)" unless range.is_a?(Range)

    first = range.begin.nil? ? 0 : Primitive.zr_index_operand_m(range.begin)
    last = range.end.nil? ? size : Primitive.zr_index_operand_m(range.end)
    first += size if first < 0
    last += size if last < 0
    raise RangeError, "#{range} out of range" if first < 0 || first > size

    last += 1 unless range.exclude_end? || range.end.nil?
    last = size if last > size
    [first, [last - first, 0].max]
  end

  # str_check_beg_len: a negative length, then an index outside the
  # string, raise; a length past the end is cut; both ends must fall on
  # character boundaries.
  def splice_bounds(start, length)
    Primitive.attr! :hidden
    size = Primitive.zr_str_bytesize(self)
    raise IndexError, "negative length #{length}" if length.negative?
    raise IndexError, "index #{start} out of string" if start > size || start + size < 0

    start += size if start.negative?
    length = size - start if length > size - start
    raise IndexError, "offset #{start} does not land on character boundary" unless char_boundary?(start)
    raise IndexError, "offset #{start + length} does not land on character boundary" unless char_boundary?(start + length)

    [start, length]
  end

  def byte_range(range)
    Primitive.attr! :hidden
    first = range.begin || 0
    first += Primitive.zr_str_bytesize(self) if first < 0
    raise RangeError, "#{range} out of range" if first < 0 || first > Primitive.zr_str_bytesize(self)

    last = range.end.nil? ? Primitive.zr_str_bytesize(self) - 1 : range.end
    last += Primitive.zr_str_bytesize(self) if last < 0
    last -= 1 if range.exclude_end? && !range.end.nil?
    last = Primitive.zr_str_bytesize(self) - 1 if last >= Primitive.zr_str_bytesize(self)
    [first, [last - first + 1, 0].max]
  end

  # The one option each case method takes, checked as ruby checks it.
  # `:lithuanian` has no mapping of its own.
  def case_mode(options, kind)
    Primitive.attr! :hidden
    raise ArgumentError, +"too many options" if options.size > 2

    if options.size == 2
      first, second = options
      raise ArgumentError, +"too many options" unless first == :turkic || first == :lithuanian
      raise ArgumentError, +"invalid second option" unless second == (first == :turkic ? :lithuanian : :turkic)

      return :turkic
    end

    mode = options.first
    return :full if options.empty? || mode == :lithuanian
    raise ArgumentError, +"option :fold only allowed for downcasing" if mode == :fold && kind != :down
    raise ArgumentError, +"invalid option" unless mode == :ascii || mode == :turkic || mode == :fold

    mode
  end

  # Each character mapped: the first through the title table for
  # `capitalize`, the rest through the lowercase one.
  def mapped_case(kind, options)
    Primitive.attr! :hidden
    mode = case_mode(options, kind)
    encoding = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    raise Encoding::CompatibilityError, "incompatible encoding with this operation: #{encoding}" if encoding.dummy?
    # UTF-16, UTF-32 and CESU-8 case as the same characters do in UTF-8.
    return OWN[:encode].bind_call(self, Encoding::UTF_8).send(:mapped_case, kind, options).encode(encoding) if Encoding.wide?(encoding) || encoding.name == +"CESU-8"
    # UTF8-MAC and the carriers' UTF-8 hold the same bytes UTF-8 does.
    return copied.force_encoding(Encoding::UTF_8).send(:mapped_case, kind, options).force_encoding(encoding) if Encoding.send(:utf8_like?, encoding)
    return recoded_case(kind, options) if Encoding.cased?(encoding) && !Primitive.zr_str_ascii_only_m(self)
    # The case-map pass reads every character of a multibyte encoding,
    # and says so of bytes that make none; ASCII mode reads none past
    # ASCII.
    unless mode == :ascii || Primitive.zr_str_valid_p(self) || Regexp.encoder(encoding).max_len == 1
      raise ArgumentError, +"input string invalid"
    end
    # An encoding with no case table of its own maps ASCII letters and
    # leaves every other byte (rb_str_ascii_casemap).
    return ascii_cased(kind, encoding) unless encoding.equal?(Encoding::UTF_8) || Encoding.cased?(encoding)
    return Primitive.zr_str_map_case_m(self, KERNEL_CASE[kind]) if mode != :turkic && KERNEL_CASE.key?(kind) && Primitive.zr_str_ascii_check(self)

    out = empty_like
    chars = characters
    chars.each_index do |i|
      char = chars[i]
      step = kind == :title ? (i.zero? ? :title : :down) : kind
      out << case_char(char, step, mode)
    end
    out
  end

  # A byte of a longer character is left alone, even where it spells an
  # ASCII letter, as a Shift_JIS trail byte may.
  def ascii_cased(kind, encoding)
    Primitive.attr! :hidden
    out = +"".b
    first = true
    OWN[:each_char].bind_call(self) do |char|
      byte = char.getbyte(0)
      if char.bytesize == 1
        upper = byte.between?(65, 90)
        lower = byte.between?(97, 122)
        up = case kind
             when :up then lower
             when :swap then lower
             when :title then first && lower
             else false
             end
        down = case kind
               when :down, :fold then upper
               when :swap then upper
               when :title then !first && upper
               else false
               end
        byte += up ? -32 : (down ? 32 : 0)
        out << byte
      else
        out << char.b
      end
      first = false
    end
    out.force_encoding(encoding)
  end

  # A single-byte encoding cases its characters as Unicode does, over
  # their code points. A character whose new case the encoding has no
  # byte for stays as it was, and so does a byte it never defined.
  def recoded_case(kind, options)
    Primitive.attr! :hidden
    target = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    out = +"".b
    chars = characters
    chars.each_index do |i|
      char = chars[i]
      step = kind == :title && !i.zero? ? :down : kind
      out << (recased_char(char, step, options, target) || char.b)
    end
    out.force_encoding(target)
  end

  def recased_char(char, kind, options, target)
    Primitive.attr! :hidden
    wide = char.encode(Encoding::UTF_8)
    wide.send(:mapped_case, kind, options).encode(target).b
  rescue Encoding::UndefinedConversionError
    nil
  end

  def case_char(char, kind, mode)
    Primitive.attr! :hidden
    return char if mode == :ascii && char.getbyte(0) > 127

    code = char.ord
    return TURKIC.fetch(kind).fetch(code).chr(Encoding::UTF_8) if mode == :turkic && TURKIC.fetch(kind).key?(code)

    kind = :fold if mode == :fold
    mapped = CASE_MULTI.fetch(kind)[code]
    return mapped.pack("U*") if mapped

    moved = case_delta(CASE_RUNS.fetch(kind), code)
    moved.zero? ? char : (code + moved).chr(Encoding::UTF_8)
  end

  # How far `code` moves in a table of (first, how many, how far)
  # triples, found by halving.
  def case_delta(runs, code)
    Primitive.attr! :hidden
    low = 0
    high = (runs.size / 3) - 1
    while low <= high
      middle = (low + high) / 2
      first = runs[middle * 3]
      if code < first
        high = middle - 1
      elsif code >= first + runs[(middle * 3) + 1]
        low = middle + 1
      else
        return runs[(middle * 3) + 2]
      end
    end
    0
  end

  # rb_enc_check: a String argument must join with the receiver before
  # its bytes can be read as characters of one encoding. Two strings of
  # one encoding always join, which is the common way in.
  def joined(other)
    Primitive.attr! :hidden
    return other if Encoding.at(Primitive.zr_str_encoding_index_m(self)).equal?(other.encoding) || Encoding.compatible?(self, other)

    Encoding.incompatible(self, other)
  end
  private :joined

  def byte_index(needle, start)
    Primitive.attr! :hidden
    needle = joined(Primitive.zr_str_operand(needle))
    return nil if start.nil? || start > Primitive.zr_str_bytesize(self)

    at = Primitive.zr_str_find_from(self, needle, start)
    return at if at.nil? || !Encoding.send(:mb?, Encoding.at(Primitive.zr_str_encoding_index_m(self)))

    # A match that starts inside a character of a multibyte encoding is
    # no match: the search goes on from the next character, as
    # rb_str_index tests the head of the character it lands in.
    while at
      char = Primitive.zr_str_byte_to_char(self, at)
      return at if Primitive.zr_str_char_offset_m(self, char) == at

      at = Primitive.zr_str_find_from(self, needle, Primitive.zr_str_char_offset_m(self, char + 1))
    end
    nil
  end

  # rb_str_justify: `pad` (nil for the one space byte) repeated on the
  # sides, whole copies and then the characters of it that fit.
  def justify(width, pad, side)
    Primitive.attr! :hidden
    enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    width = Primitive.zr_index_operand_m(width)
    if pad
      pad = Primitive.zr_str_operand(pad)
      enc = Encoding.compatible?(self, pad) || Encoding.incompatible(self, pad)
      fill = OWN[:b].bind_call(pad)
      fclen = Primitive.zr_str_length_m(pad)
      raise ArgumentError, +"zero width padding" if fill.empty? || fclen == 0
    else
      fill = " ".b
      fclen = 1
    end
    len = Primitive.zr_str_length_m(self)
    return copied if width < 0 || len >= width

    n = width - len
    llen = side == :left ? 0 : (side == :right ? n : n / 2)
    rlen = n - llen
    size = Primitive.zr_str_bytesize(self)
    llen2 = fill.bytesize > 1 ? Primitive.zr_str_char_offset_m(pad, llen % fclen) : 0
    rlen2 = fill.bytesize > 1 ? Primitive.zr_str_char_offset_m(pad, rlen % fclen) : 0
    raise ArgumentError, +"argument too big" if ((llen / fclen) + (rlen / fclen)) * fill.bytesize + llen2 + rlen2 + size >= 1 << 63

    out = padding(fill, llen, fclen, llen2) << OWN[:b].bind_call(self) << padding(fill, rlen, fclen, rlen2)
    OWN[:force_encoding].bind_call(out, enc)
    # The result keeps the text's coderange, and the pad's, unscanned:
    # a space byte in UTF-32 still reads as valid.
    Primitive.zr_str_mark_valid_m(out) if Primitive.zr_str_valid_p(self) && (pad.nil? || Primitive.zr_str_valid_p(pad))
    out
  end

  def padding(fill, n, fclen, tail)
    Primitive.attr! :hidden
    return fill * n if fill.bytesize <= 1

    fill * (n / fclen) << fill.byteslice(0, n % fclen > 0 ? tail : 0)
  end

  # The method entries as they are at boot, which String's own methods
  # call as the C calls its functions: a subclass's or a program's
  # redefinition of one does not change what another reaches.
  OWN = %i[[] each_char each_byte end_with? start_with? index rindex lstrip strip rstrip succ reverse capitalize
           downcase upcase swapcase delete squeeze chomp chop sub scrub tr tr_s count lines each_line scan include?
           unicode_normalize encode force_encoding b grapheme_clusters <=> ==].to_h { |name| [name, instance_method(name)] }.freeze
  # The encodings whose characters rb_enc_unicode_p says are Unicode.
  GRAPHEMES = %w[UTF-8 UTF-16BE UTF-16LE UTF-32BE UTF-32LE UTF8-MAC CESU-8 UTF8-DoCoMo UTF8-KDDI UTF8-SoftBank].freeze
  private_constant :OWN, :GRAPHEMES
end

class Symbol
  # The String method entries as they are at boot. Ruby reaches its own
  # C functions from here, so a prepend or a redefinition of a String
  # method does not change Symbol's.
  STRING = %i[[] length upcase downcase capitalize swapcase succ start_with? end_with? empty? casecmp casecmp?]
             .to_h { |name| [name, String.instance_method(name)] }.freeze
  private_constant :STRING

  def [](*args) = STRING[:[]].bind_call(to_s, *args)
  alias slice []

  def length = STRING[:length].bind_call(to_s)
  alias size length

  def =~(other) = to_s =~ other
  def match(*args, &block) = to_s.match(*args, &block)
  def match?(*args) = to_s.match?(*args)

  def upcase(*options) = STRING[:upcase].bind_call(to_s, *options).to_sym
  def downcase(*options) = STRING[:downcase].bind_call(to_s, *options).to_sym
  def capitalize(*options) = STRING[:capitalize].bind_call(to_s, *options).to_sym
  def swapcase(*options) = STRING[:swapcase].bind_call(to_s, *options).to_sym
  def succ = STRING[:succ].bind_call(to_s).to_sym
  alias next succ

  def start_with?(*prefixes) = STRING[:start_with?].bind_call(to_s, *prefixes)
  def end_with?(*suffixes) = STRING[:end_with?].bind_call(to_s, *suffixes)
  def empty? = STRING[:empty?].bind_call(to_s)
end

class Symbol
  include Comparable

  # A name that contains a character outside ASCII. If all its
  # characters have a category of their own, it shows as the runtime
  # writes it. If one needs an escape, the name is quoted and escaped.
  def utf8_inspect
    Primitive.attr! :hidden
    text = to_s
    shown = text.utf8_inspect
    plain = shown == "\"#{text}\""
    # sym_printable takes NEL as printable; String#inspect alone escapes
    # it. So a name that is plain but for NEL is bare.
    if plain || shown == "\"#{text.gsub("\u0085") { "\\u0085" }}\""
      bare = Primitive.zr_sym_inspect_bytes(self)
      return bare if plain || !bare.start_with?(":\"")
    end

    ":#{shown}"
  end

  # A name with a character outside ASCII in an encoding other than
  # UTF-8. It is bare only when its String prints as itself and the name
  # is plain with each such character taken as a letter
  # (rb_enc_symname_type).
  def mb_inspect
    Primitive.attr! :hidden
    text = to_s
    shown = text.inspect
    if shown.byteslice(1, shown.bytesize - 2) == text
      letters = text.each_char.map { |char| char.ascii_only? ? char : "a" }.join
      return ":#{text}" unless Primitive.zr_sym_inspect_bytes(letters.to_sym).start_with?(":\"")
    end
    ":#{shown}"
  end

  # The last characters that make Hash#inspect quote a key, as
  # symbol_key_needs_quote lists them.
  KEY_QUOTED_ENDS = %w[+ - * / ` % ^ & | \] < = > ~ @].freeze
  private_constant :KEY_QUOTED_ENDS

  # This symbol as Hash#inspect writes a key with a name outside ASCII:
  # bare when the name is plain, else quoted as its String inspects.
  def key_inspect
    Primitive.attr! :hidden
    shown = inspect
    text = to_s
    if shown.start_with?(":\"") || text.start_with?("@", "$", "!") || KEY_QUOTED_ENDS.include?(text[-1])
      text.inspect
    else
      shown.byteslice(1, shown.bytesize - 1)
    end
  end

  def to_sym = self

  def intern = self

  def casecmp(other) = other.is_a?(Symbol) ? STRING[:casecmp].bind_call(to_s, other.to_s) : nil

  def casecmp?(other) = other.is_a?(Symbol) ? STRING[:casecmp?].bind_call(to_s, other.to_s) : nil
  alias id2name to_s

  # Ruby keeps one frozen name String per symbol, so `name` returns the
  # same object each time.
  NAMES = Hash.new { |cache, symbol| cache[symbol] = symbol.to_s.freeze }
  private_constant :NAMES

  def name = NAMES[self]

  def self.all_symbols = Primitive.zr_all_symbols
end

# Every encoding that ruby registers is defined here. A String has one
# of the three that the runtime walks: UTF-8, ASCII-8BIT and US-ASCII.
class Encoding
  class CompatibilityError < EncodingError; end
  class ConverterNotFoundError < EncodingError; end

  # The two failures that a conversion can return give both of its ends,
  # and the character or the bytes where it stopped.
  class UndefinedConversionError < EncodingError
    def source_encoding_name = @names ? @names[0] : @source&.name

    def destination_encoding_name = @names ? @names[1] : @destination&.name

    def source_encoding = @source

    def destination_encoding = @destination

    def error_char = @char

    def setup(source, destination, char)
      Primitive.attr! :hidden
      @source = source
      @destination = destination
      @char = char
      self
    end

    # A step whose transcoder gives its ends separately from the encodings.
    def named(source, destination)
      Primitive.attr! :hidden
      @names = [source, destination]
      self
    end
    private :setup, :named
  end

  class InvalidByteSequenceError < EncodingError
    def source_encoding_name = @names ? @names[0] : @source&.name

    def destination_encoding_name = @names ? @names[1] : @destination&.name

    def source_encoding = @source

    def destination_encoding = @destination

    def error_bytes = @bytes

    def readagain_bytes = @again

    def incomplete_input? = @incomplete

    def setup(source, destination, bytes, again, incomplete)
      Primitive.attr! :hidden
      @source = source
      @destination = destination
      @bytes = bytes
      @again = again
      @incomplete = incomplete
      self
    end

    def named(source, destination)
      Primitive.attr! :hidden
      @names = [source, destination]
      self
    end
    private :setup, :named
  end

  # The two failures, built with all their attributes.
  def self.byte_error(message, source, destination, bytes, again, incomplete)
    Primitive.attr! :hidden
    InvalidByteSequenceError.new(message).send(:setup, source, destination, bytes.b, again&.b, incomplete)
  end

  def self.char_error(message, source, destination, char)
    Primitive.attr! :hidden
    UndefinedConversionError.new(message).send(:setup, source, destination, char)
  end

  attr_reader :names

  # Every name is a frozen US-ASCII String, the same object on each
  # call.
  def initialize(index, names, dummy, ascii, loaded, bytewise)
    Primitive.attr! :hidden
    @names = names.map { |name| Primitive.zr_str_usascii(name.dup).freeze }.freeze
    # The one field CRuby shows a program.
    Primitive.zr_hidden_set(self, :@name, @names.first)
    @index = index
    @dummy = dummy
    @ascii = ascii
    Primitive.zr_state_set(self, :__loaded__, loaded)
    @bytewise = bytewise
    # An encoding is frozen, as CRuby makes each one. Reading its table
    # later is state that freeze does not lock (zr_state_set).
    freeze
  end

  # Ruby's own index for this encoding in `Encoding.list`. A String
  # stores this number.
  def index
    Primitive.attr! :hidden
    @index
  end

  # Whether one byte is always one character, which is what the runtime
  # needs to walk a String in this encoding.
  def bytewise?
    Primitive.attr! :hidden
    @bytewise
  end

  def name = @names.first

  # The names the table lists, before `names` moves the default ones.
  def listed_names
    Primitive.attr! :hidden
    @names
  end
  private :listed_names
  alias to_s name

  # Marshal writes an encoding by name, as ruby does.
  def _dump(_limit = nil) = name.dup.force_encoding(Encoding::US_ASCII)

  # CRuby's `_load` returns the name; Marshal's own loader for
  # Encoding turns it into the encoding.
  def self._load(name) = name

  # BINARY is the name that the report shows, and ASCII-8BIT is the one
  # that `name` returns. A dummy encoding says so, and so does one whose
  # table a fresh ruby has not read, in that order, as enc_inspect writes them.
  def inspect
    shown = @names[1] == +"BINARY" ? +"BINARY (ASCII-8BIT)" : name
    "#<Encoding:#{shown}#{" (dummy)" if @dummy}#{" (autoload)" unless Primitive.zr_hidden_get(self, :__loaded__)}>".force_encoding(US_ASCII)
  end

  def ascii_compatible?
    Primitive.zr_state_set(self, :__loaded__, true)
    @ascii
  end

  def dummy?
    Primitive.zr_state_set(self, :__loaded__, true)
    @dummy
  end

  # A lookup of an encoding by name reads its table.
  def load
    Primitive.attr! :hidden
    Primitive.zr_state_set(self, :__loaded__, true)
    self
  end

  # Ruby cannot make an Encoding: the runtime builds each one once.
  Primitive.zr_undef_alloc(self)

  LIST = ROWS.each_with_index.map do |(names, dummy, ascii, loaded, bytewise), index|
    encoding = Primitive.zr_class_build(self)
    encoding.send(:initialize, index, names, dummy, ascii, loaded, bytewise)
    encoding
  end.freeze
  private_constant :LIST

  BY_NAME = LIST.each_with_object({}) { |encoding, out| encoding.names.each { |name| out[name] = encoding } }.freeze
  private_constant :BY_NAME

  CONSTANTS.each { |const, name| const_set(const, BY_NAME.fetch(name)) }

  def self.at(index)
    Primitive.attr! :hidden
    LIST[index]
  end

  # Whether this encoding gives every byte from 128 up a code point of
  # its own, which is what reading its characters needs.
  def self.tabled?(encoding)
    Primitive.attr! :hidden
    HIGH.key?(encoding.name)
  end

  # Whether this encoding cases its non-ASCII characters at all.
  def self.cased?(encoding)
    Primitive.attr! :hidden
    Primitive.zr_table_member_p(CASED, encoding.name)
  end

  # A String has a byte-oriented encoding, UTF-8, or UTF-16 or UTF-32.
  # The others need byte tables that this runtime does not have.
  def self.carried(encoding)
    Primitive.attr! :hidden
    unless encoding.bytewise? || encoding.equal?(UTF_8) || wide?(encoding) || mb?(encoding) || utf8_like?(encoding)
      Primitive.zr_unimplemented("a String in the #{encoding} encoding")
    end

    encoding.send(:load).index
  end

  # Whether a String in this encoding walks by the multibyte rules in
  # lib/zr/runtime/kernel/enc_mb.rb, or by UTF-8's own rules.
  def self.mb?(encoding)
    Primitive.attr! :hidden
    MB.key?(encoding.name)
  end

  def self.utf8_like?(encoding)
    Primitive.attr! :hidden
    Primitive.zr_table_member_p(MB_UTF8, encoding.name)
  end

  # Whether a conversion out of this multibyte encoding has entries to
  # read. Ruby has no converter for some of them. A String in one of
  # those is walked and never converted.
  def self.mb_converts?(encoding)
    Primitive.attr! :hidden
    mb?(encoding) && !MB.fetch(encoding.name).empty?
  end

  # The error that a String whose bytes make no character raises. The
  # runtime calls this, because the names are here.
  def self.invalid_bytes(text)
    Primitive.attr! :hidden
    raise ArgumentError, "invalid byte sequence in #{text.encoding.name}"
  end

  # A multibyte encoding's entries, unpacked on first use. They map the
  # bytes before a character's last byte to the result of converting each
  # last byte. A code point represents itself. A String is a character
  # that needs more than one code point. `true` is a character that the
  # encoding gives no code point. `:more` starts a longer character.
  # The kernel's own rules find where a character ends, because ruby's
  # converters are narrower than its character counts.
  MB_TABLES = {}
  MB_WRITERS = {}
  private_constant :MB_TABLES, :MB_WRITERS

  def self.mb_table(encoding)
    Primitive.attr! :hidden
    MB_TABLES[encoding.name] ||= mb_rows(encoding.name)
  end

  def self.mb_rows(name)
    Primitive.attr! :hidden
    multi = mb_multi(name)
    out = {}
    MB.fetch(name).each do |prefix, first, _count, id|
      row = {}
      packed = MB_ROWS[id].unpack1("m")
      key = prefix.b
      byte = first
      value = 0
      shift = 0
      at = 0
      point = 0
      while at < packed.bytesize
        piece = packed.getbyte(at)
        at += 1
        value |= (piece & 0x7F) << shift
        if piece >= 0x80
          shift += 7
          next
        end
        case value
        when 0 then nil
        when 1 then row[byte] = true
        when 2 then row[byte] = :more
        when 3 then row[byte] = multi.fetch(key + byte.chr).dup.force_encoding(UTF_8)
        else
          point += mb_signed(value - 4)
          row[byte] = point
        end
        byte += 1
        value = 0
        shift = 0
      end
      # The entries are written as literals, which have the source's own
      # encoding; a walk reaches them with bytes.
      out[key] = row
    end
    out
  end

  # The characters of an encoding that need more than one code point,
  # keyed by the bytes that a walk uses to reach them. The generated
  # table's own keys are source literals, which have the source's encoding.
  def self.mb_multi(name)
    Primitive.attr! :hidden
    rows = MB_MULTI[name]
    return nil if rows.nil?

    out = {}
    rows.each { |bytes, text| out[bytes.b] = text }
    out
  end

  # A number folded onto the positive ones, read back.
  def self.mb_signed(value)
    Primitive.attr! :hidden
    value.even? ? value / 2 : 0 - ((value + 1) / 2)
  end

  # From a code point to the bytes the encoding writes it as: the rows
  # read backwards, lowest sequence first, with the ones ruby writes
  # another way on top.
  def self.mb_writer(encoding)
    Primitive.attr! :hidden
    MB_WRITERS[encoding.name] ||= begin
      out = {}
      mb_table(encoding).each do |prefix, row|
        row.each do |byte, slot|
          next unless slot.is_a?(Integer)

          bytes = prefix + byte.chr
          # The shortest sequence represents the code point, with the
          # lowest bytes of that length, as ruby writes one.
          held = out[slot]
          if held.nil? || bytes.bytesize < held.bytesize || (bytes.bytesize == held.bytesize && bytes < held)
            out[slot] = bytes
          end
        end
      end
      packed = MB_ENCODE[encoding.name]
      if packed
        bytes = packed.unpack1("m")
        at = 0
        point = 0
        while at < bytes.bytesize
          delta, at = mb_varint(bytes, at)
          size, at = mb_varint(bytes, at)
          point += delta
          out[point] = bytes.byteslice(at, size)
          at += size
        end
      end
      out
    end
  end

  # One number of the packed rows, and where the next one starts.
  def self.mb_varint(bytes, at)
    Primitive.attr! :hidden
    value = 0
    shift = 0
    loop do
      piece = bytes.getbyte(at)
      at += 1
      value |= (piece & 0x7F) << shift
      break if piece < 0x80

      shift += 7
    end
    [value, at]
  end
  private_class_method :mb_varint
  private_class_method :mb_rows, :mb_signed

  # UTF-16 and UTF-32: the width of a code unit, and whether it is big
  # endian. The two dummy names write big endian after a byte-order
  # mark, and read the order off the mark.
  UNITS = {
    "UTF-16BE" => [2, true], "UTF-16LE" => [2, false], "UTF-32BE" => [4, true], "UTF-32LE" => [4, false],
    "UTF-16" => [2, nil], "UTF-32" => [4, nil]
  }.freeze
  private_constant :UNITS

  BOMS = { 2 => [[0xFE, 0xFF], [0xFF, 0xFE]], 4 => [[0, 0, 0xFE, 0xFF], [0xFF, 0xFE, 0, 0]] }.freeze
  private_constant :BOMS

  # Whether a String in this encoding walks by UTF-16 or UTF-32 code
  # units: the four named with a byte order.
  def self.wide?(encoding)
    Primitive.attr! :hidden
    UNITS.key?(encoding.name) && !encoding.bytewise?
  end

  # For each lead byte of a UTF-8 sequence: how many bytes follow, and
  # the range the first of them must fall in. Every later one is 80-BF.
  UTF8_LEADS = (0xC2..0xF4).to_h do |lead|
    rule = if lead < 0xE0 then [1, 0x80, 0xBF]
           elsif lead == 0xE0 then [2, 0xA0, 0xBF]
           elsif lead == 0xED then [2, 0x80, 0x9F]
           elsif lead < 0xF0 then [2, 0x80, 0xBF]
           elsif lead == 0xF0 then [3, 0x90, 0xBF]
           elsif lead == 0xF4 then [3, 0x80, 0x8F]
           else [3, 0x80, 0xBF]
           end
    [lead, rule]
  end.freeze
  private_constant :UTF8_LEADS

  # The message that a join of two encodings raises. The runtime calls
  # this because the names are here.
  def self.incompatible(a, b)
    Primitive.attr! :hidden
    raise CompatibilityError, "incompatible character encodings: #{shown(a.encoding)} and #{shown(b.encoding)}"
  end

  # BINARY shows as both its names when an error gives it.
  def self.shown(encoding)
    Primitive.attr! :hidden
    encoding.equal?(ASCII_8BIT) ? +"BINARY (ASCII-8BIT)" : encoding.name
  end

  # The code point that each byte from 128 up represents, or nil where
  # the encoding leaves the byte out. Bytes below 128 represent
  # themselves in every encoding that has a table.
  def points
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__points__) || Primitive.zr_state_set(self, :__points__, HIGH.fetch(name).scan(/..../).map { |hex| hex == +"----" ? nil : hex.to_i(16) })
  end

  # `text` written in `target`. UTF-8 is the meeting point, so a pair
  # with neither side in it converts twice, and its errors name both
  # steps.
  def self.convert(text, target, options)
    Primitive.attr! :hidden
    from = text.encoding
    target.send(:load)
    return text.dup.force_encoding(target) if from.equal?(target)
    # The stateless form of ISO-2022-JP converts on the paths of ruby's own
    # transcoders, which a converter takes one step at a time. (Its steps
    # never convert stateless text back through here.)
    return Converter.send(:transcode, text, target, options) if stateless?(from) || stateless?(target)
    return stateful_write(from.equal?(UTF_8) ? text : convert(text, UTF_8, options), target, options) if stateful?(target)
    if stateful?(from)
      text = stateful_read(text, options)
      return target.equal?(UTF_8) ? text : convert(text, target, options)
    end
    return ebcdic_write(from.equal?(UTF_8) ? text : convert(text, UTF_8, options), target, options) if target.name == +"IBM037"
    return convert(ebcdic_read(text), target, options) if from.name == +"IBM037"

    return hub_convert(text, from, target, options) if MB_HUBS.key?(from.name) || MB_HUBS.key?(target.name)
    # The carriers exchange their emoji with each other in one step.
    return exchange(text, target, [from, target], options) if carrier?(from) && carrier?(target)

    path = from.equal?(UTF_8) || target.equal?(UTF_8) ? [from, target] : [from, UTF_8, target]
    (1...path.size).each { |i| converter(path[i - 1], path[i], path, text.ascii_only?, decorators(options)) }
    text = to_utf8(text, path, options) unless from.equal?(UTF_8)
    text = from_utf8(text, target, path, options) unless target.equal?(UTF_8)
    text
  end

  def self.stateless?(encoding)
    Primitive.attr! :hidden
    encoding.name == "stateless-ISO-2022-JP"
  end
  private_class_method :stateless?

  # An encoding with no table gets past here, and so does a pair ruby
  # itself refuses to convert between. Plain ASCII crosses that second
  # one anyway, converter or none.
  def self.converter(a, b, path, ascii, decorators = [])
    Primitive.attr! :hidden
    [a, b].each do |encoding|
      next if encoding.equal?(UTF_8) || UNITS.key?(encoding.name) || mb_converts?(encoding) || utf8_like?(encoding)
      # Plain ASCII goes into an ASCII-compatible encoding with no table,
      # unless an option requests a decorator, which needs a converter.
      if ascii && !shaped?(encoding) && encoding.ascii_compatible? && !encoding.dummy?
        next if decorators.empty?

        raise ConverterNotFoundError, not_found(path, decorators)
      end
      # Ruby defines these encodings but has no converter for them.
      raise ConverterNotFoundError, not_found(path, decorators) if %w[UTF-7 ISO-2022-JP-2].include?(encoding.name)
      Primitive.zr_unimplemented("String#encode to the #{encoding} encoding") unless shaped?(encoding)
      raise ConverterNotFoundError, not_found(path, decorators) if shape_of(encoding).nil? && (!ascii || !decorators.empty?)
    end
  end

  def self.not_found(path, decorators)
    Primitive.attr! :hidden
    with = decorators.empty? ? +"" : " with #{decorators.join(",")}"
    "code converter not found (#{path.first.name} to #{path.last.name}#{with})"
  end
  private_class_method :not_found
  private_class_method :converter

  # The decorators that the options of an encode request, by ruby's names.
  def self.decorators(options)
    Primitive.attr! :hidden
    names = case options[:xml]
            when :text then [+"xml_text"]
            when :attr then %w[xml_attr_content xml_attr_quote]
            else []
            end
    names << "crlf_newline" if options[:newline] == :crlf
    names << "cr_newline" if options[:newline] == :cr
    names << "universal_newline" if options[:newline] == :universal
    names << "lf_newline" if options[:newline] == :lf
    names
  end
  private_class_method :decorators

  # How ruby words a failure for an encoding. The single-byte entries
  # and the multibyte ones give the same three facts.
  def self.shaped?(encoding)
    Primitive.attr! :hidden
    SHAPES.key?(encoding.name) || MB_SHAPES.key?(encoding.name)
  end

  def self.shape_of(encoding)
    Primitive.attr! :hidden
    SHAPES.key?(encoding.name) ? SHAPES[encoding.name] : MB_SHAPES[encoding.name]
  end
  private_class_method :shaped?, :shape_of

  # Each byte read as the code point its encoding gives it.
  def self.to_utf8(text, path, options)
    Primitive.attr! :hidden
    from = text.encoding
    return units_to_utf8(text, from, replacement(path.last, options), options) if UNITS.key?(from.name)
    return mb_to_utf8(text, from, path, options) if mb?(from)
    return utf8_like_read(text, from, path, options) if utf8_like?(from)

    out = +""
    text.each_byte do |byte|
      if byte < 128
        out << byte
      elsif from.equal?(ASCII_8BIT)
        undefined(byte_text(byte), from, UTF_8, path, options, byte.chr.dup.force_encoding(from)) { |mark| out << mark }
      elsif from.equal?(US_ASCII)
        # US-ASCII has no byte past 127: each one is invalid.
        options[:invalid] == :replace ? out << replacement(path.last, options) : invalid([byte], nil, false, from.name)
      elsif (point = from.send(:points)[byte - 128])
        out << point
      else
        undefined(byte_text(byte), from, UTF_8, path, options, byte.chr.dup.force_encoding(from)) { |mark| out << mark }
      end
    end
    out
  end
  private_class_method :to_utf8

  # Each character written as the bytes the target gives its code point.
  def self.from_utf8(text, target, path, options)
    Primitive.attr! :hidden
    return utf8_like_write(text, target, path, options) if utf8_like?(target)

    unit, big = UNITS[target.name]
    big = true if unit && big.nil?
    writer = mb?(target) ? mb_writer(target) : nil
    points = unit || writer || target.equal?(ASCII_8BIT) || target.equal?(US_ASCII) || text.ascii_only? ? nil : target.send(:points)
    out = []
    utf8_points(text, replacement(target, options), options, target) do |point|
      bytes = point_bytes(point, unit, big, points, writer)
      bytes ||= ruled_bytes(point, target) if ruled?(target)
      if bytes
        out.concat(bytes)
      elsif options[:xml]
        out.concat("&#x#{format('%X', point)};".bytes)
      else
        undefined("U+#{point.to_s(16).upcase.rjust(4, '0')}", UTF_8, target, path, options, point.chr(UTF_8)) do |mark|
          mark.each_char { |char| out.concat(point_bytes(char.ord, unit, big, points, writer) || char.bytes) }
        end
      end
    end
    # A dummy name marks the byte order before the first character.
    out.unshift(*point_bytes(0xFEFF, unit, true, nil)) if unit && UNITS[target.name][1].nil? && !out.empty?
    out.pack("C*").force_encoding(target)
  end
  private_class_method :from_utf8

  # The bytes of code point `point` in the target: its code units, or
  # the one byte a table or ASCII gives it; nil when it has none.
  def self.point_bytes(point, unit, big, points, writer = nil)
    Primitive.attr! :hidden
    if unit
      units = unit == 4 || point < 0x10000 ? [point] : [0xD800 + ((point - 0x10000) >> 10), 0xDC00 + ((point - 0x10000) & 0x3FF)]
      units.map do |code|
        bytes = Array.new(unit) { |k| (code >> (8 * k)) & 0xFF }
        big ? bytes.reverse : bytes
      end.flatten(1)
    elsif point < 128
      [point]
    elsif writer
      writer[point]&.bytes
    elsif points && (found = points.index(point))
      [found + 128]
    end
  end
  private_class_method :point_bytes

  # econv_opts and rb_econv_prepare_options: invalid: and undef: take
  # only :replace, and a replacement is whole in its own encoding.
  def self.check_options(options)
    Primitive.attr! :hidden
    raise ArgumentError, +"unknown value for invalid character option" unless options[:invalid].nil? || options[:invalid] == :replace
    raise ArgumentError, +"unknown value for undefined character option" unless options[:undef].nil? || options[:undef] == :replace
    xml = options[:xml]
    unless xml.nil? || xml == :text || xml == :attr
      raise ArgumentError, xml.is_a?(Symbol) ? "unexpected value for xml option: #{xml}" : +"unexpected value for xml option"
    end

    replace = options[:replace]
    return if replace.nil?

    replace = String.try_convert(replace) or raise TypeError, "no implicit conversion of #{conversion_name(options[:replace])} into String"
    raise ArgumentError, "replacement string is broken: #{replace.dump} as #{replace.encoding}" unless replace.valid_encoding?
  end
  private_class_method :check_options

  # A converter that opens takes the replacement in its target encoding,
  # and does not open when it cannot have one. str_transcode0 opens none
  # when there is nothing to convert: the same encoding, or ASCII text
  # between two encodings that contain ASCII, with no decorator.
  def self.check_replacement(text, from, target, options)
    Primitive.attr! :hidden
    replace = options[:replace]
    return if replace.nil? || from.equal?(target)
    return if decorators(options).empty? && from.ascii_compatible? && target.ascii_compatible? && text.ascii_only?

    convert(String.try_convert(replace), target, {})
  rescue EncodingError
    raise ConverterNotFoundError, "code converter not found (#{from} to #{target})"
  end
  private_class_method :check_replacement

  # What `invalid: :replace` writes: the caller's text, else U+FFFD into
  # a Unicode encoding and "?" into any other.
  def self.replacement(target, options)
    Primitive.attr! :hidden
    options[:replace] || (target.equal?(UTF_8) || UNITS.key?(target.name) ? +"�" : +"?")
  end
  private_class_method :replacement

  # Each code point of UTF-8 `text`, on its way to `target`. Bytes UTF-8
  # does not allow raise as ruby's decoder words them, or become `mark`
  # once under `invalid: :replace`.
  def self.utf8_points(text, mark, options, target, source = UTF_8)
    Primitive.attr! :hidden
    bytes = text.bytes
    i = 0
    while i < bytes.size
      point, length, kind = utf8_step(bytes, i)
      if point
        yield point
      elsif options[:invalid] == :replace
        mark.each_char { |char| yield char.ord }
      else
        invalid(bytes[i, length], kind == :bad ? [bytes[i + length]] : nil, kind == :ended, source.name, target)
      end
      i += length
    end
  end
  private_class_method :utf8_points

  # The character at byte `i`: [code point, length], or [nil, length of
  # the bad bytes, how they went bad]. A lead byte UTF-8 never uses is
  # bad alone; a byte out of place ends the bad bytes before it, to be
  # read again; the end of the input inside a sequence leaves it
  # incomplete.
  def self.utf8_step(bytes, i)
    Primitive.attr! :hidden
    lead = bytes[i]
    return [lead, 1] if lead < 0x80

    need, low, high = UTF8_LEADS[lead]
    return [nil, 1, :lead] unless need

    point = lead & (0x3F >> need)
    (1..need).each do |k|
      byte = bytes[i + k]
      return [nil, k, :ended] if byte.nil?
      return [nil, k, :bad] unless byte.between?(k == 1 ? low : 0x80, k == 1 ? high : 0xBF)

      point = (point << 6) | (byte & 0x3F)
    end
    [point, need + 1]
  end
  private_class_method :utf8_step

  # Each code unit of a UTF-16 or UTF-32 String read as its code point,
  # written as UTF-8. A lone or unpaired surrogate, a UTF-32 unit past
  # Unicode or a short tail raises as ruby's decoder words it, or
  # becomes `mark` once under `invalid: :replace`.
  def self.units_to_utf8(text, from, mark, options)
    Primitive.attr! :hidden
    unit, big = UNITS.fetch(from.name)
    bytes = text.bytes
    points = []
    bad = lambda do |error, again, ended|
      next points.concat(mark.each_char.map(&:ord)) if options[:invalid] == :replace

      invalid(error, again, ended, from.name)
    end
    i = 0
    if big.nil?
      return +"" if bytes.empty?
      return bad.(bytes, nil, true) && points.pack("U*") if bytes.size < unit

      big = BOMS.fetch(unit).index(bytes.first(unit))&.zero?
      invalid(bytes.first(unit), nil, false, from.name) if big.nil?
      i = unit
    end
    while i < bytes.size
      kind, a, b = unit_step(bytes, i, unit, big)
      case kind
      when :char
        points << a
        i += b
      when :incomplete
        bad.(bytes[i..], nil, true)
        break
      else
        bad.(bytes[i, a], b.zero? ? nil : bytes[i + a, b], false)
        i += a
      end
    end
    points.pack("U*")
  end
  private_class_method :units_to_utf8

  # One step of the from_UTF_16LE/BE and from_UTF_32LE/BE transcoders
  # (enc/trans/utf_16_32.trans) at byte `at`: [:char, code point,
  # length], [:incomplete] where the text ends inside a character, or
  # [:invalid, error length, read-again length]. A byte the table
  # refuses inside the first unit takes the rest of that unit with it.
  def self.unit_step(bytes, at, unit, big)
    Primitive.attr! :hidden
    rest = bytes.size - at
    b = ->(k) { bytes[at + k] }
    refuse = ->(len) { len <= unit ? [:invalid, [unit, rest].min, 0] : [:invalid, ((len - 1) / unit) * unit, len - ((len - 1) / unit) * unit] }
    if unit == 2
      hi = big ? 0 : 1
      return [:incomplete] if rest < 1 + hi
      return refuse.(1 + hi) if b.(hi).between?(0xDC, 0xDF)
      return [:incomplete] if rest < 2

      code = big ? (b.(0) << 8) | b.(1) : (b.(1) << 8) | b.(0)
      return [:char, code, 2] unless b.(hi).between?(0xD8, 0xDB)
      return [:incomplete] if rest < 3 + hi
      return refuse.(3 + hi) unless b.(2 + hi).between?(0xDC, 0xDF)
      return [:incomplete] if rest < 4

      low = big ? (b.(2) << 8) | b.(3) : (b.(3) << 8) | b.(2)
      return [:char, 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00), 4]
    end
    if big
      return refuse.(1) unless b.(0) == 0
      return [:incomplete] if rest < 2
      return refuse.(2) unless b.(1) <= 0x10
      return [:incomplete] if rest < 3
      return refuse.(3) if b.(1) == 0 && b.(2).between?(0xD8, 0xDF)
      return [:incomplete] if rest < 4

      return [:char, (b.(1) << 16) | (b.(2) << 8) | b.(3), 4]
    end
    return [:incomplete] if rest < 2
    return [:incomplete] if rest < 3
    return refuse.(3) unless b.(2) <= 0x10 && (b.(2) != 0 || !b.(1).between?(0xD8, 0xDF))
    return [:incomplete] if rest < 4
    return refuse.(4) unless b.(3) == 0

    [:char, (b.(2) << 16) | (b.(1) << 8) | b.(0), 4]
  end
  private_class_method :unit_step

  # Each character of a multibyte String read as its code point, written
  # as UTF-8. The entries show where a character ends: a slot that starts
  # a longer one continues the walk. A slot with no code point is a
  # character that this pair cannot convert. No slot at all is bytes
  # that make no character.
  def self.mb_to_utf8(text, from, path, options)
    Primitive.attr! :hidden
    table = mb_table(from)
    mark = replacement(UTF_8, options)
    bytes = text.bytes
    out = +""
    i = 0
    while i < bytes.size
      if bytes[i] < 0x80
        out << bytes[i]
        i += 1
        next
      end
      if ruled?(from) && (ruled = ruled_char(bytes, i, from, path, options))
        out << ruled[0]
        i += ruled[1]
        next
      end
      prefix = +"".b
      steps = 0
      slot = nil
      while (row = table[prefix]) && (at = bytes[i + steps]) && (slot = row[at]) == :more
        prefix << at
        steps += 1
      end
      # A partial encoding's rows stop at the characters every row of
      # which was read; the walk reaches the longer ones and says so.
      if row.nil? && steps.positive? && Primitive.zr_table_member_p(MB_PARTIAL, from.name)
        Primitive.zr_unimplemented("String#encode of a #{from} character of more than two bytes")
      end
      slot = nil unless row && bytes[i + steps]
      whole = bytes[i, steps + 1]
      if slot.is_a?(Integer) || slot.is_a?(String)
        out << slot
      elsif slot == true
        undefined(whole.pack("C*").dump, from, UTF_8, path, options,
                  whole.pack("C*").dup.force_encoding(from)) { |text_mark| out << text_mark }
      elsif options[:invalid] == :replace
        out << mark
        # The byte that broke the sequence is read again, as ruby's
        # decoder reads it: it may start a character of its own.
        i -= 1 if steps.positive? && bytes[i + steps]
      elsif steps.zero?
        invalid([bytes[i]], nil, false, from.name)
      else
        invalid(bytes[i, steps], bytes[i + steps] ? [bytes[i + steps]] : nil, bytes[i + steps].nil?, from.name)
      end
      i += steps + 1
    end
    out
  end
  private_class_method :mb_to_utf8

  # Whether the bytes from `at` start a character that the text ends
  # inside. A conversion in pieces keeps those bytes for the next piece
  # rather than refusing them.
  def self.incomplete_tail?(bytes, at, encoding)
    Primitive.attr! :hidden
    rest = bytes.bytesize - at
    return false if rest <= 0 || encoding.nil?

    if encoding.equal?(UTF_8) || utf8_like?(encoding)
      point, _length, kind = utf8_step(bytes.bytes, at)
      return point.nil? && kind == :ended
    end
    unit, = UNITS[encoding.name]
    if unit
      return true if rest < unit
      return false unless unit == 2 && rest < 4

      code = (bytes.getbyte(at) << 8) | bytes.getbyte(at + 1)
      code = ((code & 0xFF) << 8) | (code >> 8) unless UNITS[encoding.name][1]
      return code.between?(0xD800, 0xDBFF)
    end
    return false unless mb?(encoding)

    table = mb_table(encoding)
    prefix = +"".b
    steps = 0
    while (row = table[prefix]) && (byte = bytes.getbyte(at + steps)) && row[byte] == :more
      prefix << byte
      steps += 1
    end
    !row.nil? && bytes.getbyte(at + steps).nil?
  end

  # An encoding that writes its characters as UTF-8 writes them: only
  # the form parts. UTF8-MAC stores each one decomposed, which ruby
  # calls NFD, and reads it back composed.
  def self.utf8_like_read(text, from, path, options)
    Primitive.attr! :hidden
    return exchange(text, UTF_8, path, options) if carrier?(from)

    text = text.dup.force_encoding(UTF_8)
    unless text.valid_encoding?
      # ruby's UTF8-MAC decoder marks a bad byte "?"; without the option
      # the bad bytes stop as UTF-8's decoder words them.
      mark = options[:replace] || +"?"
      utf8_points(text, mark, options, UTF_8, from) { nil } unless options[:invalid] == :replace
      text = text.scrub(mark)
    end
    text.unicode_normalize(:nfc)
  end

  def self.utf8_like_write(text, target, path, options)
    Primitive.attr! :hidden
    return exchange(text, target, path, options) if carrier?(target)

    text.unicode_normalize(:nfd).dup.force_encoding(target)
  end

  # `text`, in UTF-8 or a carrier's encoding, into `target`, the other
  # of the two or another carrier's: each emoji the pair exchanges
  # becomes the target's own, and every other character stays as it is.
  def self.exchange(text, target, path, options)
    Primitive.attr! :hidden
    from = text.encoding
    table = emoji(from, target)
    out = +""
    utf8_points(text, replacement(target, options), options, target, from) do |point|
      if !table.key?(point)
        out << point
      elsif (points = table[point])
        points.each { |each| out << each }
      elsif options[:xml]
        out << "&#x#{format('%X', point)};"
      else
        char = point.chr(UTF_8)
        shown = from.equal?(UTF_8) ? "U+#{format('%04X', point)}" : char.b.dump
        undefined(shown, from, target, path, options, char.force_encoding(from)) { |mark| out << mark }
      end
    end
    out.force_encoding(target)
  end
  private_class_method :utf8_like_read, :utf8_like_write, :exchange

  # The transcoders' own names for the step between a carrier's
  # Shift_JIS or JIS and the carrier's UTF-8, which ruby's failures use.
  HUB_NAMES = {
    "SJIS-DoCoMo" => %w[SJIS-DOCOMO UTF8-DOCOMO], "SJIS-KDDI" => %w[SJIS-KDDI UTF8-KDDI],
    "SJIS-SoftBank" => %w[SJIS-SoftBank UTF8-SoftBank],
    "stateless-ISO-2022-JP-KDDI" => %w[stateless-ISO-2022-JP-KDDI UTF8-KDDI]
  }.freeze
  private_constant :HUB_NAMES

  # A carrier's Shift_JIS or JIS reads into the carrier's own UTF-8 and
  # writes out of it, as ruby's converters do: the carrier's emoji are
  # private-use code points there, and the exchange with Unicode or with
  # another carrier is a separate step. The path shows each hub step
  # with its transcoder's name.
  def self.hub_convert(text, from, target, options)
    Primitive.attr! :hidden
    read = MB_HUBS[from.name] && find(MB_HUBS[from.name])
    write = MB_HUBS[target.name] && find(MB_HUBS[target.name])
    start = read || from
    goal = write || target
    unicode = ->(encoding) { encoding.equal?(UTF_8) || carrier?(encoding) }
    between = if start.equal?(goal) then []
              elsif unicode[start] && unicode[goal] then [goal]
              else [UTF_8, goal]
              end
    path = [from]
    path << HUB_NAMES[from.name][1] if read
    path.concat(between)
    path << HUB_NAMES[target.name][0] if write

    text = hub_read(text, from, read, path, options) if read
    at = start
    between.each do |step|
      text = if unicode[at] && unicode[step] then exchange(text, step, path, options)
             elsif step.equal?(UTF_8) then convert(text, UTF_8, options)
             else from_utf8(text, step, path, options)
             end
      at = step
    end
    write ? hub_write(text, write, target, path, options) : text
  end

  def self.hub_read(text, from, hub, path, options)
    Primitive.attr! :hidden
    mb_to_utf8(text, from, path, options).force_encoding(hub)
  rescue InvalidByteSequenceError => e
    source, destination = HUB_NAMES[from.name]
    message = "#{e.message.delete_suffix(" on #{from.name}")} on #{source}"
    raise byte_error(message, from, hub, e.error_bytes, e.readagain_bytes, e.incomplete_input?).send(:named, source, destination)
  end

  # Each code point of the carrier's UTF-8 in the carrier's own bytes.
  def self.hub_write(text, hub, target, path, options)
    Primitive.attr! :hidden
    writer = mb_writer(target)
    source, destination = HUB_NAMES[target.name]
    out = []
    utf8_points(text, replacement(target, options), options, target, hub) do |point|
      if (bytes = point_bytes(point, nil, nil, nil, writer))
        out.concat(bytes)
        next
      end
      char = point.chr(UTF_8).force_encoding(hub)
      if options[:undef] == :replace
        out.concat(convert(options[:replace] || "?", target, {}).bytes)
      elsif (given = fallback(options[:fallback], char))
        written = begin
          given.encode(target)
        rescue EncodingError
          raise ArgumentError, +"too big fallback string"
        end
        out.concat(written.bytes)
      elsif options[:xml]
        out.concat("&#x#{format('%X', point)};".bytes)
      else
        named = path.map { |step| step.is_a?(String) ? step : step.name }.join(" to ")
        raise char_error("#{char.b.dump} to #{source} in conversion from #{named}", hub, target, char)
                .send(:named, destination, source)
      end
    end
    out.pack("C*").force_encoding(target)
  end
  private_class_method :hub_convert, :hub_read, :hub_write

  # Ruby's words for bytes that a decoder cannot read: `incomplete` when
  # the input ends inside them, else `followed by` the bytes it reads
  # again. The failure gives the ends of the step that read them: the
  # decoding into UTF-8, or from UTF-8 the one step to the target.
  def self.invalid(error, again, ended, name, destination = UTF_8)
    Primitive.attr! :hidden
    shown = error.pack("C*").dump
    text = if ended then "incomplete #{shown}"
           elsif again then "#{shown} followed by #{again.pack('C*').dump}"
           else shown
           end
    # The failure describes itself, as CRuby's does: it contains the
    # bytes where it stopped and the bytes it will read again.
    raise byte_error("#{text} on #{name}", find(name), destination, error.pack("C*"), again&.pack("C*"), ended)
  end
  private_class_method :invalid

  # A byte or a character the step cannot write: replaced when the
  # caller asked for that, else ruby's own error, worded for the whole
  # path.
  def self.undefined(shown, from, to, path, options, char = nil)
    Primitive.attr! :hidden
    if options[:undef] == :replace
      replacement = options[:replace] || (to.equal?(UTF_8) ? +"\uFFFD" : +"?")
      return yield(replacement)
    end
    if char && (text = fallback(options[:fallback], char))
      written = begin
        text.encode(to)
      rescue EncodingError
        raise ArgumentError, +"too big fallback string"
      end
      return yield(written.encode(UTF_8))
    end

    # The failure contains the character where it stopped, as CRuby's does.
    raise char_error(message(shown, from, to, path), from, to, char)
  end
  private_class_method :undefined

  # The text that a `fallback:` gives for a character the target cannot
  # encode, as transcode_loop calls it: a Proc or a Method is called,
  # and a Hash or any other object that responds to `[]` is indexed.
  # nil when there is no fallback, or when the option gives no usable object.
  def self.fallback(fallback, char)
    Primitive.attr! :hidden
    return nil if fallback.nil?

    fallback = Hash.try_convert(fallback) || fallback
    text = case fallback
           when Proc, Method then fallback.call(char)
           else
             return nil unless fallback.respond_to?(:[])

             fallback.public_send(:[], char)
           end
    return nil if text.nil?

    String.try_convert(text) || raise(TypeError, "no implicit conversion of #{text.class} into String")
  end
  private_class_method :fallback

  # `X from A to B` for a single step that ruby words that way, else the
  # chain form, which gives every encoding on the path.
  def self.message(shown, from, to, path)
    Primitive.attr! :hidden
    other = to.equal?(UTF_8) ? from : to
    row = shape_of(other)
    return "#{shown} from #{from.name} to #{to.name}" if path.size == 2 && (to.equal?(UTF_8) ? row[2] : row[0])

    step = to.equal?(UTF_8) ? +"UTF-8" : row[1]
    # A hub step shows in the path as its transcoder's own name.
    named = path.map { |encoding| encoding.is_a?(String) ? encoding : (encoding.equal?(to) ? step : encoding.name) }
    "#{shown} to #{step} in conversion from #{named.join(' to ')}"
  end
  private_class_method :message

  def self.byte_text(byte)
    Primitive.attr! :hidden
    "\"\\x#{format('%02X', byte)}\""
  end
  private_class_method :byte_text

  def self.list = LIST.dup

  # Every name, and `internal` for the encoding a read converts to.
  def self.name_list
    names = LIST.flat_map(&:names)
    default_internal ? names : names << "internal"
  end

  # Every name but the first of each encoding, pointing at the first.
  # `locale`, `external` and `filesystem` name the encodings they stand
  # for now, not the ones the table lists.
  def self.aliases
    names = LIST.each_with_object({}) { |encoding, out| encoding.names.drop(1).each { |name| out[name] = encoding.name } }
    names.merge("locale" => locale_encoding.name, "external" => default_external.name, "filesystem" => default_external.name)
  end

  # The codeset of the locale that the environment named as the program
  # started, as ruby's main sets it with setlocale(LC_CTYPE, ""). WASI
  # has no locale; there it is what wasi-libc, a musl, gives: "ASCII" for
  # the C locale and "UTF-8" for any other.
  def self.locale_charmap = LOCALE[0].dup

  # The locale's encoding (rb_locale_encindex): the charmap's encoding, or
  # UTF-8 for a name that no encoding has.
  def self.locale_encoding
    Primitive.attr! :hidden
    LOCALE[1] ||= by_name[LOCALE[0].upcase(:ascii)]&.send(:load) || UTF_8
  end

  def self.read_locale
    Primitive.attr! :hidden
    charmap = Primitive.zr_os_locale_charmap
    unless charmap
      name = %w[LC_ALL LC_CTYPE LANG].map { |var| Primitive.zr_environment_get(var) }.find { |value| value && !value.empty? }
      charmap = %w[C POSIX].include?(name) ? +"ASCII" : +"UTF-8"
    end
    Primitive.zr_str_usascii(charmap).freeze
  end

  # The charmap, read as the program starts, and its encoding once asked.
  LOCALE = [read_locale, nil]
  private_constant :LOCALE

  # A path that the system gives (a directory's entries, the working
  # directory, the program's name) is in the default external encoding,
  # as rb_filesystem_encoding is on a POSIX system. The kernel tags such
  # Strings (`zr_path_str`); under a UTF-8 locale it has nothing to do.
  # core/env.rb starts it, once every encoding's methods are defined.
  def self.follow_paths
    Primitive.attr! :hidden
    Primitive.zr_path_index_set(carried(default_external))
  end

  def self.find(name)
    return name if name.is_a?(Encoding)

    text = String.try_convert(name)
    raise TypeError, "no implicit conversion of #{conversion_name(name)} into String" if text.nil?
    # rb_to_encoding_index: a name must be in an ASCII-compatible encoding.
    raise ArgumentError, +"invalid encoding name (non ASCII)" unless text.encoding.ascii_compatible?
    if text.ascii_only?
      key = text.upcase(:ascii)
      # These follow the defaults: each is whatever its default is, nil too.
      return default_internal if key == +"INTERNAL"
      return default_external if key == +"EXTERNAL" || key == +"FILESYSTEM"
      return locale_encoding if key == +"LOCALE"
    end
    if (found = by_name[text])
      nil
    elsif key
      found = by_name[key]
    else
      found = LIST.find { |encoding| encoding.names.any? { |n| n.casecmp?(text) } }
    end
    return found.send(:load) if found

    raise ArgumentError, "unknown encoding name - #{text}"
  end

  # Each name of an encoding, as written and upper-cased, mapped to the
  # first encoding in the list that has it. This makes a lookup by an
  # ASCII name (every encoding name is ASCII) one step.
  def self.by_name
    Primitive.attr! :hidden
    @by_name ||= {}.tap do |index|
      LIST.each do |encoding|
        encoding.send(:listed_names).each do |name|
          index[name.upcase(:ascii)] ||= encoding
          index[name] ||= encoding
        end
      end
    end
  end

  # Both ends of a conversion. A name that matches no encoding is not an
  # ArgumentError here: ruby looks for a converter by the two names and
  # finds none.
  def self.pair(source, target)
    Primitive.attr! :hidden
    ends = [source, target].map do |name|
      find(name)
    rescue ArgumentError
      nil
    end
    return ends if ends.all?

    names = [source, target].zip(ends).map { |name, found| found ? found.name : name.to_s }
    raise ConverterNotFoundError, "code converter not found (#{names.join(' to ')})"
  end

  # The external and internal encodings a program set, nil for the ones
  # it did not: the locale's encoding and none.
  DEFAULTS = [nil, nil]
  private_constant :DEFAULTS

  def self.default_external = DEFAULTS[0] || locale_encoding

  def self.default_internal = DEFAULTS[1]

  # The external encoding is also the one "external" and "filesystem"
  # name, as enc_set_default_encoding moves both aliases.
  def self.default_external=(encoding)
    Warning.warn("#{Primitive.zr_warn_position}warning: setting Encoding.default_external\n") if $VERBOSE
    raise ArgumentError, +"default external can not be nil" if encoding.nil?

    DEFAULTS[0] = find(encoding)
    follow_paths
    inspect_target
    encoding
  end

  def self.default_internal=(encoding)
    Warning.warn("#{Primitive.zr_warn_position}warning: setting Encoding.default_internal\n") if $VERBOSE
    DEFAULTS[1] = encoding.nil? ? nil : find(encoding)
    inspect_target
    encoding
  end

  # Tells the kernel rb_str_inspect's result encoding: default_internal,
  # else default_external, and US-ASCII when that is not ASCII compatible.
  # A character prints as itself only when its String is in this encoding.
  def self.inspect_target
    Primitive.attr! :hidden
    target = default_internal || default_external
    Primitive.zr_inspect_index_set((target.ascii_compatible? ? target : US_ASCII).index)
  end

  # The names that follow the defaults, rather than one encoding.
  MOVING = %w[locale external filesystem internal].freeze
  private_constant :MOVING

  def names
    moving = []
    moving << "locale" if equal?(Encoding.locale_encoding)
    moving.push("external", "filesystem") if equal?(Encoding.default_external)
    moving << "internal" if equal?(Encoding.default_internal)
    return @names if moving == @names & MOVING

    (@names - MOVING + moving.map { |name| Primitive.zr_str_usascii(name.dup).freeze }).freeze
  end

  # The encodings a conversion passes through, ruby's own converter
  # pairs being the only steps it may take: the shortest way from one
  # name to the other.
  def self.convpath_for(source, destination, shown)
    Primitive.attr! :hidden
    ends = [source, destination].map { |name| LIST.find { |encoding| encoding.names.any? { |other| other.casecmp?(name) } } }
    if ends.all?
      queue = [[ends.first]]
      seen = { ends.first.name => true }
      until queue.empty?
        path = queue.shift
        return path if path.last.equal?(ends.last)

        CONVERTERS.each do |from, to|
          next unless from == path.last.name
          next if seen[to]

          seen[to] = true
          queue << (path + [find(to)])
        end
      end
    end
    raise ConverterNotFoundError, "code converter not found (#{source} to #{destination}#{shown})"
  end

  # econv_opts' line ends, by decorator name: `newline:` names one and
  # wins over the older booleans, which can name several, and the
  # conversion then finds no converter. A nil names none.
  NEWLINE_OPTIONS = %i[universal_newline crlf_newline cr_newline lf_newline].freeze
  private_constant :NEWLINE_OPTIONS

  def self.newline_decorators(options)
    Primitive.attr! :hidden
    given = NEWLINE_OPTIONS.reject { |name| options[name].nil? }
    if options[:newline].nil?
      given.select { |name| options[name] }
    else
      Primitive.zr_warn_here_m(":newline option precedes other newline options") if $VERBOSE && !given.empty?
      [newline_decorator(options[:newline])]
    end
  end

  # The options with their line end as one `newline:`, or none. Two line
  # ends are no conversion that ruby has.
  def self.one_newline(options, from, target)
    Primitive.attr! :hidden
    lines = newline_decorators(options)
    if lines.size > 1
      ends = from.equal?(target) ? +"" : "#{from} to #{target} with "
      raise ConverterNotFoundError, "code converter not found (#{ends}#{lines.join(',')})"
    end
    options = options.except(:newline, *NEWLINE_OPTIONS)
    lines.empty? ? options : options.merge(newline: lines.first.to_s.delete_suffix("_newline").to_sym)
  end

  # The decorator a `newline:` option names. A name that is no Symbol is
  # not shown, as CRuby's own check writes it.
  def self.newline_decorator(kind)
    Primitive.attr! :hidden
    case kind
    when :universal then :universal_newline
    when :crlf then :crlf_newline
    when :cr then :cr_newline
    when :lf then :lf_newline
    else raise ArgumentError, kind.is_a?(Symbol) ? "unexpected value for newline option: #{kind}" : +"unexpected value for newline option"
    end
  end

  # What writing a code point into `target` needs: the width and order
  # of its code units, its byte table, its multibyte entries, and whether
  # it writes UTF-8 or keeps a state between characters.
  def self.writing(target)
    Primitive.attr! :hidden
    unit, big = UNITS[target.name]
    big = true if unit && big.nil?
    writer = mb?(target) ? mb_writer(target) : nil
    points = unit || writer || target.equal?(ASCII_8BIT) || target.equal?(US_ASCII) || !tabled?(target) ? nil : target.send(:points)
    [unit, big, points, writer, target.equal?(UTF_8) || utf8_like?(target), target.name.start_with?("ISO-2022-JP", "CP5022")]
  end

  # ISO-2022-JP keeps a state: its characters are the bytes of
  # stateless-ISO-2022-JP with the high bit off, inside an escape that
  # says so, and the text ends back in ASCII.
  JIS_IN = "\e$B"
  JIS_OUT = "\e(B"
  private_constant :JIS_IN, :JIS_OUT

  # JIS X 0208's own entries, which are the set that the escape selects.
  # Ruby marks that set with a 0x92 byte in stateless-ISO-2022-JP, and
  # the two bytes after it are the character with their high bits on. A
  # character that never follows the marker is one ISO-2022-JP cannot write.
  JIS_0208 = []
  private_constant :JIS_0208

  def self.jis_writer
    Primitive.attr! :hidden
    JIS_0208[0] ||= begin
      out = {}
      mb_table(find("stateless-ISO-2022-JP")).each do |prefix, row|
        next unless prefix.bytesize == 2 && prefix.getbyte(0) == 0x92

        row.each do |byte, slot|
          next unless slot.is_a?(Integer)

          bytes = [prefix.getbyte(1) & 0x7F, byte & 0x7F].pack("C*")
          out[slot] = bytes if out[slot].nil? || bytes < out[slot]
        end
      end
      out
    end
  end

  def self.jis_bytes(point)
    Primitive.attr! :hidden
    jis_writer[point]
  end

  # enc_compatible_p: the encoding that two objects with encodings can
  # join in, or nil. A String, a Symbol, a Regexp, an IO and an Encoding
  # have one. A String's encoding is read from its own bytes, so a
  # subclass's encoding, empty? and ascii_only? are not called.
  def self.compatible?(a, b)
    ea = encoding_of(a) or return nil
    eb = encoding_of(b) or return nil
    return ea if ea == eb

    a_string = a.is_a?(String)
    b_string = b.is_a?(String)
    return ea if b_string && Primitive.zr_str_bytesize(b) == 0
    return ea.ascii_compatible? && Primitive.zr_str_ascii_only_m(b) ? ea : eb if a_string && b_string && Primitive.zr_str_bytesize(a) == 0
    return nil unless ea.ascii_compatible? && eb.ascii_compatible?
    # An object that is not a String has no bytes to check: only its encoding counts.
    return ea if !b_string && eb == US_ASCII
    return eb if !a_string && ea == US_ASCII
    # All ASCII, a String takes the other side's encoding; two Strings
    # that both are take the first one's.
    a_ascii = a_string && Primitive.zr_str_ascii_only_m(a)
    b_ascii = b_string && Primitive.zr_str_ascii_only_m(b)
    return ea if a_string && b_ascii
    return eb if a_ascii || b_ascii

    nil
  end

  # rb_enc_get_index: the encoding of `object`, or nil for an object
  # with no encoding. is_a? rather than case: String's own boot runs
  # before Module#=== is defined.
  def self.encoding_of(object)
    Primitive.attr! :hidden
    if object.is_a?(String)
      at(Primitive.zr_str_encoding_index_m(object))
    elsif object.is_a?(Symbol) || object.is_a?(Regexp)
      object.encoding
    elsif object.is_a?(Encoding)
      object
    elsif object.is_a?(IO)
      object.internal_encoding || object.external_encoding
    end
  end
end

class Symbol
  def encoding = to_s.encoding
end

# An empty namespace at boot, as CRuby defines it; ruby's normalize.rb
# fills it on String#unicode_normalize's first call.
module UnicodeNormalize
end
