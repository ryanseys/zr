# String methods written over the byte primitives. Character indexes
# map to byte offsets through the kernel, which reads UTF-8; a binary
# string's bytes are its characters. Case mapping, succ and character
# sets stop on non-ASCII text.
class String
  include Comparable

  def [](index, length = nil)
    case index
    when Integer
      raise RangeError, "bignum too big to convert into 'long'" unless Primitive.zr_fixnum_p_m(index)
      return Primitive.zr_str_char_slice(self, index, Primitive.zr_index_operand_m(length)) if length

      count = size
      index += count if index < 0
      return nil if index < 0 || index >= count

      Primitive.zr_str_char_slice(self, index, 1)
    when Range
      start, length = range_span(index, size)
      start && Primitive.zr_str_char_slice(self, start, length)
    when Regexp
      match = index.send(:search, self, 0, false)
      Primitive.zr_backref_set(match)
      return nil unless match
      return match[0] if length.nil?

      match[length]
    when String
      include?(index) ? index.dup : nil
    else
      self[Primitive.zr_index_operand_m(index), *[length].compact]
    end
  end
  alias slice []

  def chars(&block) = block ? each_char(&block) : each_char.to_a

  def each_char
    return to_enum(:each_char) { size } unless block_given?

    i = 0
    while i < bytesize
      n = Primitive.zr_str_char_len_at_m(self, i)
      yield byteslice_of(i, n)
      i += n
    end
    self
  end

  def bytes(&block)
    return each_byte(&block) if block

    out = []
    i = 0
    n = bytesize
    while i < n
      out << Primitive.zr_str_byte_at(self, i)
      i += 1
    end
    out
  end

  def each_byte
    return to_enum(:each_byte) { bytesize } unless block_given?

    i = 0
    while i < bytesize
      yield Primitive.zr_str_byte_at(self, i)
      i += 1
    end
    self
  end

  def bytesize = Primitive.zr_str_bytesize(self)

  def getbyte(i) = Primitive.zr_str_byte_at(self, i)

  def setbyte(i, byte) = Primitive.zr_str_setbyte(self, i, byte)

  def ord = Primitive.zr_str_ord(self)

  # The arguments are walked without Array's own methods: the runtime
  # itself asks these two, so a program that redefines Array#each must
  # not take them with it.
  def start_with?(*prefixes)
    i = 0
    while i < Primitive.zr_ary_len_m(prefixes)
      prefix = Primitive.zr_ary_at_m(prefixes, i)
      if prefix.is_a?(Regexp)
        match = prefix.send(:match_at, self, 0)
        Primitive.zr_backref_set(match)
        return true if match
      else
        prefix = Primitive.zr_str_operand(prefix)
        return true if prefix.bytesize <= bytesize && char_boundary?(prefix.bytesize) && byteslice_of(0, prefix.bytesize) == prefix
      end
      i += 1
    end
    false
  end

  def end_with?(*suffixes)
    i = 0
    while i < Primitive.zr_ary_len_m(suffixes)
      suffix = Primitive.zr_str_operand(Primitive.zr_ary_at_m(suffixes, i))
      return true if suffix.bytesize <= bytesize && char_boundary?(bytesize - suffix.bytesize) && byteslice_of(bytesize - suffix.bytesize, suffix.bytesize) == suffix

      i += 1
    end
    false
  end

  def delete_prefix(prefix) = start_with?(prefix) ? byteslice_of(prefix.bytesize, bytesize - prefix.bytesize) : dup

  def delete_suffix(suffix) = end_with?(suffix) ? byteslice_of(0, bytesize - suffix.bytesize) : dup

  def replace(other) = Primitive.zr_str_replace(self, other)

  # `slice!`: the part `[]` would answer, cut out of the receiver.
  def slice!(*args)
    part = self[*args]
    return nil if part.nil?

    start = if args[0].is_a?(String) then byte_index(args[0], 0)
            elsif args[0].is_a?(Regexp) then $~.byteoffset(args[1] || 0)[0]
            elsif args[0].is_a?(Range) then Primitive.zr_str_char_offset_m(self, range_span(args[0], size).first)
            else
              Primitive.zr_str_char_offset_m(self, args[0])
            end
    replace(byteslice_of(0, start) + byteslice_of(start + part.bytesize, bytesize - start - part.bytesize))
    part
  end

  # `s[i] = t`, `s[start, len] = t`, `s[range] = t` and `s[sub] = t`:
  # the span leaves and `t` takes its place.
  def []=(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 2..3)" unless args.size == 2 || args.size == 3

    Primitive.zr_frozen_error(self) if frozen?
    value = args.pop
    value = Primitive.zr_str_operand(value)

    index = args[0]
    count = size
    case index
    when Integer
      start = index < 0 ? index + count : index
      raise IndexError, "index #{index} out of string" if start < 0 || start > count

      if args.size == 2
        length = args[1]
        raise IndexError, "negative length #{length}" if length < 0

        length = count - start if length > count - start
      else
        length = start == count ? 0 : 1
      end
    when Range
      start, length = range_span(index, count)
      raise RangeError, "#{index.inspect} out of range" unless start
    when String
      start = self.index(index)
      raise IndexError, "string not matched" unless start

      length = index.size
    when Regexp
      match = index.send(:search, self, 0, false)
      raise IndexError, "regexp not matched" unless match

      group = args.size == 2 ? args[1] : 0
      start = match.begin(group)
      raise IndexError, "regexp group #{group} not matched" if start.nil?

      length = match.end(group) - start
    else
      args[0] = Primitive.zr_index_operand_m(index)
      return send(:[]=, *args, value)
    end
    from = Primitive.zr_str_char_offset_m(self, start)
    to = Primitive.zr_str_char_offset_m(self, length > count - start ? count : start + length)
    replace(byteslice_of(0, from) + value + byteslice_of(to, bytesize - to))
    value
  end

  # A copy whose bytes are its characters (CRuby's ASCII-8BIT).
  def b = Primitive.zr_str_set_binary(dup)

  def clear = replace("")

  def concat(*others)
    others.each { |o| self << o }
    self
  end

  def prepend(*others) = replace(others.map { |other| Primitive.zr_str_operand(other) }.join + self)

  def insert(index, other)
    count = size
    index += count + 1 if index < 0
    raise IndexError, "index #{index} out of string" if index < 0 || index > count

    at = Primitive.zr_str_char_offset_m(self, index)
    replace(byteslice_of(0, at) + other + byteslice_of(at, bytesize - at))
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

  # The bang forms answer nil when nothing changed.
  def upcase!(*options) = mutate(upcase(*options))
  def downcase!(*options) = mutate(downcase(*options))
  def capitalize!(*options) = mutate(capitalize(*options))
  def swapcase!(*options) = mutate(swapcase(*options))
  def reverse! = replace(reverse)
  def delete!(*sets) = mutate(delete(*sets))
  def strip! = mutate(strip)
  def lstrip! = mutate(lstrip)
  def rstrip! = mutate(rstrip)
  def chomp!(separator = "\n") = mutate(chomp(separator))
  def chop! = mutate(chop)
  def squeeze!(*sets) = mutate(squeeze(*sets))

  # Whitespace and NUL off both ends, in one String. The end is found by
  # walking back over characters, which bytes that make none refuse, as
  # rstrip_offset has it.
  def strip
    broken_tail!
    stop = Primitive.zr_str_space_start(self, bytesize, true)
    start = stop.zero? ? 0 : Primitive.zr_str_space_end(self, 0, true)
    byteslice_of(start, stop - start)
  end

  def lstrip
    start = Primitive.zr_str_space_end(self, 0, true)
    byteslice_of(start, bytesize - start)
  end

  def rstrip
    broken_tail!
    byteslice_of(0, Primitive.zr_str_space_start(self, bytesize, true))
  end

  def broken_tail!
    Primitive.attr! :hidden
    raise Encoding::CompatibilityError, "invalid byte sequence in #{encoding}" unless empty? || valid_encoding?
  end

  def chomp(separator = "\n")
    return dup if separator.nil? || empty?

    if separator == "\n"
      return byteslice_of(0, bytesize - 2) if end_with?("\r\n")
      return byteslice_of(0, bytesize - 1) if end_with?("\n", "\r")

      return dup
    end
    if separator.empty?
      s = self
      s = s.byteslice_of(0, s.bytesize - (s.end_with?("\r\n") ? 2 : 1)) while s.end_with?("\n")
      return s.equal?(self) ? dup : s
    end
    end_with?(separator) ? byteslice_of(0, bytesize - separator.bytesize) : dup
  end

  def chop
    return "" if empty?
    return byteslice_of(0, bytesize - 2) if end_with?("\r\n")

    byteslice_of(0, Primitive.zr_str_char_offset_m(self, -1))
  end

  def squeeze(*sets)
    raise ArgumentError, "invalid byte sequence in #{encoding}" unless valid_encoding?

    member = sets.empty? ? nil : charset_test(sets)
    out = +""
    last = nil
    each_char do |c|
      out << c unless c == last && (member.nil? || member.call(c.ord))
      last = c
    end
    out
  end

  # The lines up to and including `separator`: nil keeps the whole
  # text, "" splits paragraphs at blank lines (extra blank lines are
  # dropped), `chomp` strips the separator.
  def lines(separator = $/, chomp: false, &block)
    return each_line(separator, chomp: chomp, &block) if block
    return [] if empty?
    return [dup] if separator.nil?

    separator = Primitive.zr_str_operand(separator)
    paragraph = separator.empty?
    separator = "\n\n" if paragraph
    out = []
    start = 0
    while start < bytesize
      stop = byte_index(separator, start)
      if stop.nil?
        out << (chomp && !paragraph ? byteslice_of(start, bytesize - start).chomp(separator == "\n" ? nil : separator) : byteslice_of(start, bytesize - start))
        break
      end
      stop += separator.bytesize
      line = byteslice_of(start, chomp ? stop - start - separator.bytesize : stop - start)
      line = line.chomp if chomp && separator == "\n" && line.end_with?("\r")
      out << line
      stop += 1 while paragraph && stop < bytesize && getbyte(stop) == 10
      start = stop
    end
    out
  end

  def each_line(separator = (nosep = true), chomp: (nochomp = true), &block)
    separator = $/ if nosep
    chomp = false if nochomp
    unless block
      shown = nosep ? [] : [separator]
      return nochomp ? to_enum(:each_line, *shown) : to_enum(:each_line, *shown, chomp: chomp)
    end

    lines(separator, chomp: chomp).each(&block)
    self
  end

  # CRuby's four splits: awk (nil or " "), characters (""), a String
  # and a Regexp. A positive limit caps the pieces; a negative one keeps
  # trailing empty pieces; zero drops them.
  def split(pattern = nil, limit = 0)
    limit = Primitive.zr_index_operand_m(limit)
    if limit == 1
      return block_given? ? (yield dup; self) : (empty? ? [] : [dup])
    end
    pattern = $; if pattern.nil?
    pattern = Primitive.zr_str_operand(pattern) if !pattern.nil? && !pattern.is_a?(String) && !pattern.is_a?(Regexp) && pattern.respond_to?(:to_str)
    # A split by words, characters or a String reads every character.
    raise ArgumentError, "invalid byte sequence in #{encoding}" unless pattern.is_a?(Regexp) || valid_encoding?

    out = if pattern.nil? || pattern == " " then split_words(limit)
          elsif pattern.is_a?(Regexp) then split_by_regexp(pattern, limit)
          elsif !pattern.is_a?(String) then raise TypeError, "wrong argument type #{pattern.class} (expected Regexp)"
          elsif pattern.empty? then split_chars(limit)
          else split_by_string(pattern, limit)
          end
    out.pop while limit == 0 && !out.empty? && out.last.empty?
    return out unless block_given?

    out.each { |piece| yield piece }
    self
  end

  # `sub`: the first match replaced by `replacement` with its `\1`,
  # `\k<name>`, `\0` and `\&` filled in, by the Hash's entry for the
  # match, or by what the block answers with `$~` set.
  def sub(pattern, replacement = nil, &block)
    raise ArgumentError, "wrong number of arguments (given 1, expected 2)" if replacement.nil? && block.nil?

    match = first_match(pattern, 0)
    Primitive.zr_backref_set(match)
    return dup unless match

    at = match.byteoffset(0)
    byteslice_of(0, at[0]) + replacement_for(match, replacement, &block) + byteslice_of(at[1], bytesize - at[1])
  end

  def gsub(pattern, replacement = nil, &block)
    return to_enum(:gsub, pattern) if replacement.nil? && block.nil?

    out = +""
    start = 0
    last = nil
    while start <= bytesize && (match = first_match(pattern, start))
      last = match
      Primitive.zr_backref_set(match)
      from, to = match.byteoffset(0)
      out << byteslice_of(start, from - start) << replacement_for(match, replacement, &block)
      start = to
      if to == from
        break if to >= bytesize

        step = Primitive.zr_str_char_len_at_m(self, to)
        out << byteslice_of(to, step)
        start = to + step
      end
    end
    Primitive.zr_backref_set(last)
    out << byteslice_of(start, bytesize - start) if bytesize > start
    out
  end

  def sub!(pattern, replacement = nil, &block) = mutate(sub(pattern, replacement, &block))

  def gsub!(pattern, replacement = nil, &block) = mutate(gsub(pattern, replacement, &block))

  def index(needle, start = 0)
    count = size
    start += count if start < 0
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

  def rindex(needle, start = size)
    count = size
    start += count if start < 0
    return nil if start < 0

    from = Primitive.zr_str_char_offset_m(self, [start, count].min)
    if needle.is_a?(Regexp)
      match = needle.send(:search, self, from, true)
      Primitive.zr_backref_set(match)
      return match && match.begin(0)
    end
    needle = Primitive.zr_str_operand(needle)
    return nil unless needle.valid_encoding?

    i = [from, bytesize - needle.bytesize].min
    while i >= 0
      return Primitive.zr_str_byte_to_char(self, i) if char_boundary?(i) && byteslice_of(i, needle.bytesize) == needle

      i -= 1
    end
    nil
  end

  def count(*sets)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if sets.empty?

    member = charset_test(sets)
    each_char.count { |c| member.call(c.ord) }
  end

  def delete(*sets)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if sets.empty?

    member = charset_test(sets)
    out = +""
    each_char { |c| out << c unless member.call(c.ord) }
    out
  end

  def tr(from, to) = translate(from, to, false)

  # nil when no character of `from` occurs, even if nothing changed.
  def tr!(from, to)
    return nil unless count(from) > 0

    replace(translate(from, to, false))
  end

  def tr_s!(from, to)
    return nil unless count(from) > 0

    replace(translate(from, to, true))
  end

  # The next string: the rightmost run of letters or digits counts up
  # with carries, a carry past its start adds a first letter or digit;
  # with none, the last character moves on. Beyond ASCII a character
  # counts as a letter or digit by its Unicode class, and steps by
  # codepoint.
  def succ
    return Primitive.zr_str_succ_ascii(self) if ascii_only?

    chars = self.chars
    carry_at = nil
    carry = nil
    last = nil
    i = chars.size - 1
    while i >= 0
      c = chars[i]
      break if last && ascii_kind(last) && ascii_kind(c) && ascii_kind(last) != ascii_kind(c)

      if c.match?(/[[:alnum:]]/)
        stepped, wrapped = step_alnum(c)
        chars[i] = stepped
        return chars.join unless wrapped

        carry_at = i
        carry = stepped
        last = c
      end
      i -= 1
    end
    if last.nil?
      chars[-1] = (chars[-1].ord + 1).chr(Encoding::UTF_8)
    else
      chars.insert(carry_at, carry)
    end
    chars.join
  end

  alias next succ

  def succ!
    replace(succ)
  end

  alias next! succ!

  def ascii_kind(c)
    Primitive.attr! :hidden
    return nil if c.ord >= 128

    c.match?(/[[:digit:]]/) ? :digit : (c.match?(/[[:alpha:]]/) ? :alpha : nil)
  end
  private :ascii_kind

  # A letter or digit stepped once: the next of its kind, or its
  # kind's first with a carry.
  def step_alnum(c)
    Primitive.attr! :hidden
    case c
    when "z" then ["a", true]
    when "Z" then ["A", true]
    when "9" then ["0", true]
    else
      return [(c.ord + 1).chr, false] if c.ord < 128

      kind = c.match?(/[[:digit:]]/) ? /[[:digit:]]/ : /[[:alpha:]]/
      stepped = (c.ord + 1).chr(Encoding::UTF_8)
      return [stepped, false] if stepped.match?(kind)

      first = c.ord
      first -= 1 while first > 0 && (first - 1).chr(Encoding::UTF_8).match?(kind)
      [first.chr(Encoding::UTF_8), true]
    end
  end
  private :step_alnum

  def delete_prefix!(prefix)
    start_with?(prefix) ? mutate(delete_prefix(prefix)) : nil
  end

  def delete_suffix!(suffix)
    end_with?(suffix) ? mutate(delete_suffix(suffix)) : nil
  end

  # Bytes and Strings appended as they are, whatever the encodings.
  def append_as_bytes(*parts)
    parts.each do |part|
      if part.is_a?(Integer)
        Primitive.zr_str_push_byte(self, part & 0xFF)
      elsif part.is_a?(String)
        part.each_byte { |b| Primitive.zr_str_push_byte(self, b) }
      else
        raise TypeError, "wrong argument type #{part.class} (expected String or Integer)"
      end
    end
    self
  end

  def crypt(salt)
    salt = Primitive.zr_str_operand(salt)
    raise ArgumentError, "salt too short (need >=2 bytes)" if salt.bytesize < 2
    raise ArgumentError, "string contains null byte" if include?("\0") || salt.include?("\0")

    Primitive.zr_str_set_binary(Primitive.zr_str_crypt(self, salt))
  end

  def each_codepoint(&block)
    return to_enum(:each_codepoint) { size } unless block

    each_char { |c| yield c.ord }
    self
  end

  def dedup = -self

  # The bytes from `start` (`length` of them, or a Range) replaced by
  # `text`'s, in place; the ends must sit on character boundaries.
  def bytesplice(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 2..5)" unless (2..5).cover?(args.size)

    if args[0].is_a?(Range)
      start, length = byte_range(args[0])
      text = args[1]
      rest = args[2..]
    else
      start, length, text = args[0], args[1], args[2]
      rest = args[3..]
      raise IndexError, "index #{start} out of string" if start > bytesize || start < -bytesize
      start += bytesize if start < 0
      raise IndexError, "negative length #{length}" if length < 0
      length = bytesize - start if start + length > bytesize
    end
    text = Primitive.zr_str_operand(text)
    unless rest.empty?
      if rest[0].is_a?(Range)
        from, count = text.send(:byte_range, rest[0])
      else
        from, count = rest[0], rest[1]
        from += text.bytesize if from < 0
        count = text.bytesize - from if from + count > text.bytesize
      end
      text = text.byteslice(from, count)
    end
    raise IndexError, "offset #{start} does not land on character boundary" unless char_boundary?(start)
    raise IndexError, "offset #{start + length} does not land on character boundary" unless char_boundary?(start + length)

    mutate(byteslice_of(0, start) + text + byteslice_of(start + length, bytesize - start - length))
  end

  def self.try_convert(object)
    return object if object.is_a?(String)
    return nil unless object.respond_to?(:to_str)

    converted = object.to_str
    raise TypeError, "can't convert #{object.class} to String (#{object.class}#to_str gives #{converted.class})" unless converted.nil? || converted.is_a?(String)

    converted
  end

  def tr_s(from, to) = translate(from, to, true)

  def upto(last, exclusive = false, &block)
    return to_enum(:upto, last, exclusive) unless block

    last = Primitive.zr_str_operand(last)
    if bytesize == 1 && last.bytesize == 1
      b = getbyte(0)
      finish = last.getbyte(0)
      finish -= 1 if exclusive
      while b <= finish
        yield Primitive.zr_str_from_byte(b)
        b += 1
      end
      return self
    end
    return self if bytesize > last.bytesize
    if digits? && last.send(:digits?)
      n = to_i
      finish = last.to_i
      finish -= 1 if exclusive
      width = bytesize
      while n <= finish
        text = n.to_s
        yield text.bytesize < width ? "0" * (width - text.bytesize) + text : text
        n += 1
      end
      return self
    end
    order = self <=> last
    return self if order > 0 || (exclusive && order == 0)

    after = last.succ
    current = String.new(self)
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
    if sep.is_a?(Regexp)
      match = sep.send(:search, self, 0, false)
      Primitive.zr_backref_set(match)
      return [dup, "", ""] unless match

      from, to = match.byteoffset(0)
      return [byteslice_of(0, from), match[0], byteslice_of(to, bytesize - to)]
    end
    at = byte_index(sep, 0)
    at ? [byteslice_of(0, at), sep.dup, byteslice_of(at + sep.bytesize, bytesize - at - sep.bytesize)] : [dup, "", ""]
  end

  def rpartition(sep)
    if sep.is_a?(Regexp)
      match = sep.send(:search, self, bytesize, true)
      Primitive.zr_backref_set(match)
      return ["", "", dup] unless match

      from, to = match.byteoffset(0)
      return [byteslice_of(0, from), match[0], byteslice_of(to, bytesize - to)]
    end
    at = rindex(sep)
    return ["", "", dup] unless at

    at = Primitive.zr_str_char_offset_m(self, at)
    [byteslice_of(0, at), sep.dup, byteslice_of(at + sep.bytesize, bytesize - at - sep.bytesize)]
  end

  def sum(bits = 16)
    total = 0
    each_byte { |b| total += b }
    bits > 0 ? total & ((1 << bits) - 1) : total
  end

  def byteslice(start, length = nil)
    size = bytesize
    if start.is_a?(Range)
      from, count = range_span(start, size)
      return from && byteslice_of(from, count)
    end
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
    return each_char { |c| yield c.ord } if block_given?

    each_char.map(&:ord)
  end

  # Every match in turn: the matched text, or the groups when the
  # pattern has any; an empty match steps one character.
  def scan(pattern)
    found = []
    last = nil
    at = 0
    while at <= bytesize && (match = first_match(pattern, at))
      last = match
      item = match.size > 1 ? match.captures : match[0]
      from, to = match.byteoffset(0)
      if block_given?
        Primitive.zr_backref_set(match)
        yield item
      else
        found << item
      end
      at = to == from ? to + (to < bytesize ? Primitive.zr_str_char_len_at_m(self, to) : 1) : to
    end
    Primitive.zr_backref_set(last)
    block_given? ? self : found
  end

  DUMP_ESCAPES = { 7 => "\\a", 8 => "\\b", 9 => "\\t", 10 => "\\n", 11 => "\\v", 12 => "\\f", 13 => "\\r", 27 => "\\e", 34 => "\\\"", 92 => "\\\\" }.freeze
  private_constant :DUMP_ESCAPES

  # Everything outside printable ASCII escaped, so the result reads
  # back as the same bytes: a whole character as \u, a stray byte as
  # \x.
  def dump
    return "#{b.dump}.dup.force_encoding(#{encoding.name.dump})" unless encoding.ascii_compatible?

    out = +"\""
    i = 0
    while i < bytesize
      b = getbyte(i)
      n = Primitive.zr_str_char_len_at_m(self, i)
      if n > 1
        cp = byteslice_of(i, n).ord
        out << (cp > 0xFFFF ? format("\\u{%X}", cp) : format("\\u%04X", cp))
      elsif DUMP_ESCAPES.key?(b)
        out << DUMP_ESCAPES[b]
      elsif b == 35 && [123, 36, 64].include?(getbyte(i + 1))
        out << "\\#"
      elsif b < 32 || b >= 127
        out << format("\\x%02X", b)
      else
        out << Primitive.zr_str_from_byte(b)
      end
      i += n
    end
    out << "\""
    out.force_encoding(encoding)
  end

  UNIT_ESCAPES = { 34 => "\\\"", 92 => "\\\\", 10 => "\\n", 9 => "\\t", 13 => "\\r", 27 => "\\e", 7 => "\\a", 8 => "\\b", 12 => "\\f", 11 => "\\v" }.freeze
  private_constant :UNIT_ESCAPES

  # A UTF-16 or UTF-32 String inspected as ruby writes one: ASCII as it
  # is, every other character as \u, and bytes that make no character
  # as \x. A dummy name has no characters to show, so every byte is \x.
  def unit_inspect
    Primitive.attr! :hidden
    return "\"#{each_byte.map { |byte| format('\\x%02X', byte) }.join}\"" unless Encoding.wide?(encoding)

    chars = each_char.to_a
    out = +"\""
    chars.each_with_index do |char, i|
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

  # A code point appended to a UTF-16 or UTF-32 String, as its code
  # units.
  def append_unit_point(point)
    Primitive.attr! :hidden
    raise RangeError, "#{point} out of char range" if point < 0
    raise RangeError, "invalid codepoint 0x#{format('%X', point)} in #{encoding}" if point > 0x10FFFF || (point >= 0xD800 && point <= 0xDFFF)

    self << [point].pack("U").encode(encoding)
  end

  # The text `dump` wrote, read back; a trailing `.force_encoding(...)`
  # names the encoding.
  def undump
    raise RuntimeError, "non-ASCII character detected" unless ascii_only?

    text = self
    encoding = nil
    if (m = /\A(".*")\.force_encoding\("([^"]+)"\)\z/m.match(text))
      text = m[1]
      encoding = m[2]
    end
    raise RuntimeError, "invalid dumped string; not wrapped with '\"' nor '\"...\".force_encoding(\"...\")' form" unless text.size >= 2 && text.start_with?("\"") && text.end_with?("\"")

    out = "".b
    i = 1
    stop = text.bytesize - 1
    while i < stop
      b = text.getbyte(i)
      if b != 92
        raise RuntimeError, "invalid dumped string; not wrapped with '\"' nor '\"...\".force_encoding(\"...\")' form" if b == 34

        out << b
        i += 1
        next
      end
      raise RuntimeError, "invalid escape" if i + 1 >= stop

      c = text.getbyte(i + 1)
      i += 2
      case c
      when 110 then out << 10
      when 116 then out << 9
      when 114 then out << 13
      when 101 then out << 27
      when 97 then out << 7
      when 98 then out << 8
      when 102 then out << 12
      when 118 then out << 11
      when 120
        hex = text.byteslice(i, 2)
        raise RuntimeError, "invalid hex escape" unless hex.match?(/\A[0-9a-fA-F]{1,2}\z/)

        out << hex.to_i(16)
        i += hex.size
      when 117
        if text.getbyte(i) == 123
          close = text.index("}", i)
          raise RuntimeError, "unterminated Unicode escape" if close.nil?

          text[(i + 1)...close].split.each { |code| out << code.to_i(16).chr(Encoding::UTF_8).b }
          i = close + 1
        else
          out << text.byteslice(i, 4).to_i(16).chr(Encoding::UTF_8).b
          i += 4
        end
      else
        out << c
      end
    end
    out.force_encoding(encoding || self.encoding)
  end

  def hex = lenient_integer(16)

  def oct = lenient_integer(-8)

  def center(width, pad = " ") = justify(width, pad, :center)

  def ljust(width, pad = " ") = justify(width, pad, :left)

  def rjust(width, pad = " ") = justify(width, pad, :right)

  def to_i(base = 10)
    base = Primitive.zr_index_operand_m(base)
    raise ArgumentError, "invalid radix #{base}" if base < 0 || base == 1 || base > 36
    return lenient_integer(base == 0 ? -10 : base) if base != 10 || include?("0d") || include?("0D")

    i = 0
    i += 1 while i < bytesize && space_byte?(Primitive.zr_str_byte_at(self, i))
    sign = 1
    if i < bytesize && (Primitive.zr_str_byte_at(self, i) == 45 || Primitive.zr_str_byte_at(self, i) == 43)
      sign = -1 if Primitive.zr_str_byte_at(self, i) == 45
      i += 1
    end
    n = 0
    seen = false
    while i < bytesize
      b = Primitive.zr_str_byte_at(self, i)
      if b == 95 && seen && i + 1 < bytesize && digit_byte?(Primitive.zr_str_byte_at(self, i + 1))
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

  # `casecmp` folds ASCII alone; `casecmp?` folds all of Unicode. Two
  # Strings with no encoding in common answer nil, as str_casecmp does.
  def casecmp(other)
    return nil unless other.is_a?(String) && Encoding.compatible?(self, other)

    downcase(:ascii) <=> other.downcase(:ascii)
  end

  def casecmp?(other)
    return nil unless other.is_a?(String) && Encoding.compatible?(self, other)

    downcase(:fold) == other.downcase(:fold)
  end

  def chr = empty? ? "" : self[0]

  def =~(other)
    raise TypeError, "wrong argument type String (expected Regexp)" if other.is_a?(String)
    return other.send(:=~, self) if other.is_a?(Regexp)

    other =~ self
  end

  def match(pattern, pos = 0, &block)
    pattern = Regexp.new(pattern) unless pattern.is_a?(Regexp)
    pattern.match(self, pos, &block)
  end

  def match?(pattern, pos = 0)
    pattern = Regexp.new(pattern) unless pattern.is_a?(Regexp)
    pattern.match?(self, pos)
  end

  def encoding = Encoding.at(Primitive.zr_str_encoding_index_m(self))

  def force_encoding(encoding)
    Primitive.zr_frozen_error(self) if frozen?
    Primitive.zr_str_set_index_m(self, Encoding.carried(Encoding.find(encoding)))
  end

  # A copy of the receiver's characters written in `target`. Every pair
  # meets in UTF-8, so a conversion between two other encodings is two
  # steps and reads as one in its errors.
  def encode(target = Encoding.default_internal || Encoding.default_external, source = nil, **options)
    from, target = Encoding.pair(source.nil? ? encoding : source, target)
    text = escaped(source.nil? ? self : dup.force_encoding(from), options)
    text = newlines(Encoding.convert(text, target, options), options)
    options[:xml] == :attr ? "\"#{text}\"" : text
  end

  # `xml: :text` writes the three characters XML reserves as entities,
  # and `:attr` the quote as well. A character the target has no room
  # for then becomes a numeric reference rather than an error.
  def escaped(text, options)
    Primitive.attr! :hidden
    marks = case options[:xml]
            when nil then return text
            when :text then { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;" }
            when :attr then { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;" }
            else raise ArgumentError, "unexpected value for xml option: #{options[:xml]}"
            end
    text.gsub(/[#{Regexp.escape(marks.keys.join)}]/, marks)
  end

  # `newline:` and the older spellings of the same three choices
  # rewrite the line ends once the conversion is done.
  def newlines(text, options)
    Primitive.attr! :hidden
    kind = options[:newline]
    kind = :cr if options[:cr_newline]
    kind = :crlf if options[:crlf_newline]
    kind = :lf if options[:universal_newline]

    case kind
    when nil then text
    when :universal, :lf then text.gsub(/\r\n|\r/, "\n")
    when :cr then text.gsub("\n", "\r")
    when :crlf then text.gsub("\n", "\r\n")
    else raise ArgumentError, "unexpected value for newline option: #{kind}"
    end
  end

  # `String.new(source, encoding:, capacity:)`. The room asked for is
  # not held: the buffer grows as the bytes arrive.
  def initialize(source = (none = true), encoding: nil, capacity: nil)
    # A frozen String takes no argument, as CRuby's rb_str_init checks;
    # with none there is nothing to change.
    if frozen?
      return self if none && encoding.nil? && capacity.nil?

      Primitive.zr_frozen_error(self)
    end
    Primitive.zr_str_initialize_m(self, none ? nil : Primitive.zr_str_operand(source))
    Primitive.zr_str_set_binary(self) if none && encoding.nil?
    force_encoding(encoding) if encoding
    self
  end

  def encode!(*args, **options)
    replace(encode(*args, **options))
  end

  # UTF-16 and UTF-32 are never ASCII, not even empty.
  def ascii_only?
    encoding.ascii_compatible? && each_byte.all? { |b| b < 128 }
  end

  def valid_encoding? = Primitive.zr_str_valid_p(self)

  # Every invalid byte replaced by `replacement` (U+FFFD, or the
  # block's answer for the bad bytes).
  def scrub(replacement = nil)
    return dup if valid_encoding?

    replacement = (Encoding.wide?(encoding) ? "\uFFFD".encode(encoding) : "\uFFFD") if replacement.nil? && !block_given?
    out = +""
    i = 0
    while i < bytesize
      step = Primitive.zr_str_char_len_at_m(self, i)
      piece = byteslice(i, step)
      if piece.valid_encoding?
        out << piece
      else
        out << (block_given? ? yield(piece) : replacement)
      end
      i += step
    end
    out
  end

  def scrub!(replacement = nil, &block)
    mutate(scrub(replacement, &block))
    self
  end

  # Whether byte `at` starts a character (or ends the text). A
  # continuation byte is inside a character only when the nearest lead
  # byte before it, at most three back, starts a sequence that reaches it;
  # a stray one is a character of its own.
  def char_boundary?(at)
    Primitive.attr! :hidden
    return true if at >= bytesize || (getbyte(at) & 0xC0) != 0x80

    lead = at - 1
    lead -= 1 while lead > 0 && at - lead < 3 && (getbyte(lead) & 0xC0) == 0x80
    lead < 0 || Primitive.zr_str_char_len_at_m(self, lead) <= at - lead
  end

  def byteindex(needle, start = 0)
    start += bytesize if start < 0
    return nil if start < 0 || start > bytesize
    raise IndexError, "offset #{start} does not land on character boundary" unless char_boundary?(start)

    if needle.is_a?(Regexp)
      match = needle.send(:search, self, start, false)
      return match && match.byteoffset(0)[0]
    end
    byte_index(needle, start)
  end

  def byterindex(needle, start = bytesize)
    start += bytesize if start < 0
    return nil if start < 0

    start = bytesize if start > bytesize
    raise IndexError, "offset #{start} does not land on character boundary" unless char_boundary?(start)

    if needle.is_a?(Regexp)
      match = needle.send(:search, self, start, true)
      return match && match.byteoffset(0)[0]
    end
    needle = Primitive.zr_str_operand(needle)
    return nil unless needle.valid_encoding?

    i = [start, bytesize - needle.bytesize].min
    i -= 1 while i >= 0 && !(char_boundary?(i) && byteslice_of(i, needle.bytesize) == needle)
    i >= 0 ? i : nil
  end

  # Ruby's own normalize.rb does the work. A program that names one of
  # these methods arms its load, which runs on the first call.
  NORMALIZER = []
  private_constant :NORMALIZER

  def self.normalizer=(load)
    Primitive.attr! :hidden
    NORMALIZER[0] = load
  end

  def unicode_normalize(form = :nfc) = normalizer.normalize(self, form)

  def unicode_normalize!(form = :nfc) = replace(unicode_normalize(form))

  def unicode_normalized?(form = :nfc) = normalizer.normalized?(self, form)

  def normalizer
    Primitive.attr! :hidden
    unless NORMALIZER[1]
      Primitive.zr_unimplemented("String#unicode_normalize through a name the program never spells") unless NORMALIZER[0]
      NORMALIZER[0].call
      NORMALIZER[1] = ::UnicodeNormalize
    end
    NORMALIZER[1]
  end

  # A grapheme cluster is what the regex engine's `\\X` matches, which
  # is how ruby reads them too.
  def each_grapheme_cluster(&block)
    return to_enum(:each_grapheme_cluster) { grapheme_clusters.size } unless block

    grapheme_clusters.each(&block)
    self
  end

  def grapheme_clusters = scan(/\X/)

  protected

  def byteslice_of(start, length) = Primitive.zr_str_byteslice(self, start, length)

  private

  # Membership in the intersection of `sets`, each a tr-style spec:
  # characters, `a-z` ranges, and a leading `^` for the complement.
  def charset_test(sets)
    Primitive.attr! :hidden
    tests = sets.map do |spec|
      ranges, negated = charset(Primitive.zr_str_operand(spec))
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

  # The codepoint at place `n` in the expanded spec. The last one
  # stands in for every place past the end.
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
    source, negated = charset(Primitive.zr_str_operand(from))
    target, = charset(Primitive.zr_str_operand(to))
    out = +""
    last = nil
    each_char do |c|
      at = charset_index(source, c.ord)
      unless at.nil? == negated
        out << c
        last = nil
        next
      end
      if target.empty?
        last = nil
        next
      end
      mapped = negated ? target.last.end : charset_at(target, at)
      out << char_of(mapped, encoding) unless squeeze && mapped == last
      last = mapped
    end
    out
  end

  def char_of(cp, enc)
    Primitive.attr! :hidden
    cp.chr(enc)
  end

  def digits?
    Primitive.attr! :hidden
    !empty? && each_byte.all? { |b| b >= 48 && b <= 57 }
  end

  # An Integer read the way `hex` and `oct` read one: whitespace, a
  # sign, a base prefix, digits with single underscores, and nothing
  # past the first stray byte. A negative base means the prefix picks
  # the base.
  def lenient_integer(base)
    Primitive.attr! :hidden
    text = lstrip
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
    Primitive.zr_frozen_error(self) if frozen?
    return nil if result == self

    replace(result)
  end

  def space_byte?(b) = b == 32 || (b >= 9 && b <= 13) || b == 0

  def digit_byte?(b) = b >= 48 && b <= 57

  # The start and length a Range names in a string of `size` bytes,
  # or nil when it starts past the end.
  def range_span(range, size)
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
  def split_words(limit)
    out = []
    beg = Primitive.zr_str_space_end(self, 0, false)
    while beg < bytesize
      break if limit > 0 && limit <= out.size + 1

      stop = Primitive.zr_str_word_end(self, beg)
      break if stop == bytesize

      out << byteslice_of(beg, stop - beg)
      beg = Primitive.zr_str_space_end(self, stop, false)
    end
    split_tail(out, beg, limit)
  end

  def split_chars(limit)
    out = []
    beg = 0
    pieces = 1
    while beg < bytesize
      step = Primitive.zr_str_char_len_at_m(self, beg)
      out << byteslice_of(beg, step)
      beg += step
      pieces += 1
      break if limit > 0 && limit <= pieces
    end
    split_tail(out, beg, limit)
  end

  def split_by_string(pattern, limit)
    out = []
    beg = 0
    pieces = 1
    while (i = byte_index(pattern, beg))
      break if limit > 0 && limit <= pieces

      out << byteslice_of(beg, i - beg)
      beg = i + pattern.bytesize
      pieces += 1
    end
    split_tail(out, beg, limit)
  end

  # The text after the last piece: kept under a limit, or when it is
  # not empty.
  def split_tail(out, beg, limit)
    Primitive.attr! :hidden
    out << byteslice_of(beg, bytesize - beg) if bytesize > 0 && (limit != 0 || bytesize > beg)
    out
  end

  # The first match of a Regexp or String pattern at or after byte
  # `start`, as a MatchData; a String pattern matches its bytes.
  def first_match(pattern, start)
    Primitive.attr! :hidden
    return pattern.send(:search, self, start, false) if pattern.is_a?(Regexp)
    unless pattern.is_a?(String)
      raise TypeError, "wrong argument type #{pattern.class} (expected Regexp)" unless pattern.respond_to?(:to_str)

      pattern = Primitive.zr_str_operand(pattern)
    end

    at = byte_index(pattern, start)
    at && MatchData.send(:for, pattern, self, [at, at, at + pattern.bytesize])
  end

  # What replaces one match: the block's answer, the Hash's entry, or
  # the replacement text with its backreferences filled in, read from
  # the match's registers as CRuby's rb_reg_regsub reads them.
  def replacement_for(match, replacement, &block)
    Primitive.attr! :hidden
    whole = Primitive.zr_match_nth(match, 0)
    return yield(whole).to_s if block
    return replacement[whole].to_s if replacement.is_a?(Hash)

    text = replacement.to_str
    return text unless text.include?("\\")

    numbered = !match.regexp.is_a?(Regexp) || match.regexp.names.empty?
    out = +""
    i = 0
    while i < text.bytesize
      c = text[i]
      if c != "\\" || i + 1 >= text.bytesize
        out << c
        i += 1
        next
      end
      d = text[i + 1]
      i += 2
      case d
      when "0", "&" then out << whole
      when "1".."9" then out << (numbered ? Primitive.zr_match_nth(match, d.to_i).to_s : "")
      when "+" then out << Primitive.zr_match_last(match).to_s
      when "\\" then out << "\\"
      when "`" then out << Primitive.zr_match_pre(match)
      when "'" then out << Primitive.zr_match_post(match)
      when "k"
        close = text.index(">", i)
        if text[i] == "<" && close
          out << match[text[i + 1...close]].to_s
          i = close + 1
        else
          out << "\\k"
        end
      else out << "\\" << d
      end
    end
    out
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
    while (match = pattern.send(:search, self, start, false))
      from, to = match.byteoffset(0)
      if start == from && from == to
        if bytesize == 0
          out << ""
          break
        elsif last_null
          out << byteslice_of(beg, Primitive.zr_str_char_len_at_m(self, beg))
          beg = start
        else
          start += start == bytesize ? 1 : Primitive.zr_str_char_len_at_m(self, start)
          last_null = true
          next
        end
      else
        out << byteslice_of(beg, from - beg)
        beg = start = to
      end
      last_null = false
      match.captures.each { |c| out << c unless c.nil? }
      break if limit > 0 && limit <= (pieces += 1)
    end
    split_tail(out, beg, limit)
  end

  # The byte offset of `needle` at or after byte `start`, or nil.
  # A Range of byte offsets as [start, length] within the text.
  def byte_range(range)
    Primitive.attr! :hidden
    first = range.begin || 0
    first += bytesize if first < 0
    raise RangeError, "#{range} out of range" if first < 0 || first > bytesize

    last = range.end.nil? ? bytesize - 1 : range.end
    last += bytesize if last < 0
    last -= 1 if range.exclude_end? && !range.end.nil?
    last = bytesize - 1 if last >= bytesize
    [first, [last - first + 1, 0].max]
  end

  # The one option each case method takes, checked as ruby checks it.
  # `:lithuanian` names no mapping of its own.
  def case_mode(options, kind)
    Primitive.attr! :hidden
    raise ArgumentError, "too many options" if options.size > 2

    if options.size == 2
      first, second = options
      raise ArgumentError, "too many options" unless first == :turkic || first == :lithuanian
      raise ArgumentError, "invalid second option" unless second == (first == :turkic ? :lithuanian : :turkic)

      return :turkic
    end

    mode = options.first
    return :full if mode.nil? || mode == :lithuanian
    raise ArgumentError, "option :fold only allowed for downcasing" if mode == :fold && kind != :down
    raise ArgumentError, "invalid option" unless mode == :ascii || mode == :turkic || mode == :fold

    mode
  end

  # Each character mapped: the first through the title table for
  # `capitalize`, the rest through the lowercase one.
  def mapped_case(kind, options)
    Primitive.attr! :hidden
    mode = case_mode(options, kind)
    # UTF-16 and UTF-32 case as the same characters do in UTF-8.
    return encode(Encoding::UTF_8).send(:mapped_case, kind, options).encode(encoding) if Encoding.wide?(encoding)
    # The case-fold pass reads every character, and says so of bytes
    # that make none; ASCII mode reads none past ASCII.
    raise ArgumentError, "input string invalid" unless mode == :ascii || valid_encoding?
    return recoded_case(kind, options) if Encoding.cased?(encoding) && !ascii_only?
    return Primitive.zr_str_map_case_m(self, KERNEL_CASE[kind]) if mode != :turkic && KERNEL_CASE.key?(kind) && Primitive.zr_str_ascii_check(self)

    out = +""
    each_char.with_index do |char, i|
      step = kind == :title ? (i.zero? ? :title : :down) : kind
      out << case_char(char, step, mode)
    end
    out
  end

  # A single-byte encoding cases its characters as Unicode does, over
  # their code points. A character whose new case the encoding has no
  # byte for stays as it was, and so does a byte it never defined.
  def recoded_case(kind, options)
    Primitive.attr! :hidden
    target = encoding
    out = +"".b
    each_char.with_index do |char, i|
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

  def byte_index(needle, start)
    Primitive.attr! :hidden
    needle = Primitive.zr_str_operand(needle)
    return nil if start.nil? || start > bytesize

    Primitive.zr_str_find_from(self, needle, start)
  end

  def justify(width, pad, side)
    width = Primitive.zr_index_operand_m(width)
    pad = Primitive.zr_str_operand(pad)
    raise ArgumentError, "zero width padding" if pad.empty?

    joined = Encoding.compatible?(self, pad)
    Encoding.incompatible(self, pad) if joined.nil?
    count = size
    return dup if width <= count

    fill = width - count
    left = side == :left ? 0 : (side == :right ? fill : fill / 2)
    right = fill - left
    (padding(left, pad) + self + padding(right, pad)).force_encoding(joined)
  end

  def padding(n, pad)
    out = +""
    out << pad while out.size < n
    out[0, n]
  end
end

class Symbol
  # The String rows as they stand at boot. Ruby reaches its own C
  # functions from here, so a prepend or a redefinition of a String
  # method is not one of Symbol's.
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

  def to_sym = self

  def intern = self

  def casecmp(other) = other.is_a?(Symbol) ? STRING[:casecmp].bind_call(to_s, other.to_s) : nil

  def casecmp?(other) = other.is_a?(Symbol) ? STRING[:casecmp?].bind_call(to_s, other.to_s) : nil
  alias id2name to_s

  # Ruby holds one frozen name String per symbol, so `name` answers the
  # same object every time it is asked.
  NAMES = Hash.new { |cache, symbol| cache[symbol] = symbol.to_s.freeze }
  private_constant :NAMES

  def name = NAMES[self]

  def self.all_symbols = Primitive.zr_all_symbols
end

# Every encoding ruby registers is named here; a String carries one of
# the three the runtime walks: UTF-8, ASCII-8BIT and US-ASCII.
class Encoding
  class CompatibilityError < EncodingError; end
  class UndefinedConversionError < EncodingError; end
  class InvalidByteSequenceError < EncodingError; end
  class ConverterNotFoundError < EncodingError; end

  # Transcoding between two encodings is not written yet.
  class Converter
    # A pair with no converter says so before the stop that the rest
    # of the Converter still is.
    def initialize(source, destination, *)
      Encoding.pair(source, destination)
      Primitive.zr_unimplemented("Encoding::Converter")
    end

    def self.search_convpath(*) = Primitive.zr_unimplemented("Encoding::Converter.search_convpath")
    def self.asciicompat_encoding(*) = Primitive.zr_unimplemented("Encoding::Converter.asciicompat_encoding")
  end

  attr_reader :names

  def initialize(index, names, dummy, ascii, loaded, bytewise)
    @index = index
    @names = names.freeze
    @dummy = dummy
    @ascii = ascii
    @loaded = loaded
    @bytewise = bytewise
  end

  # Ruby's own place for this encoding in `Encoding.list`, which is the
  # number a String carries.
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
  alias to_s name

  # Marshal carries an encoding by name, as ruby does.
  def _dump(_limit) = name.dup.force_encoding(Encoding::US_ASCII)

  # CRuby's `_load` hands back the name; Marshal's own loader for
  # Encoding turns it into the encoding.
  def self._load(name) = name

  # BINARY is the name the report shows, ASCII-8BIT the one it answers.
  # A dummy encoding says so, and so does one whose table a fresh ruby
  # has not read, in that order, as enc_inspect writes them.
  def inspect
    shown = @names[1] == "BINARY" ? "BINARY (ASCII-8BIT)" : name
    "#<Encoding:#{shown}#{" (dummy)" if @dummy}#{" (autoload)" unless @loaded}>"
  end

  def ascii_compatible?
    @loaded = true
    @ascii
  end

  def dummy?
    @loaded = true
    @dummy
  end

  # Asking for an encoding by name is what reads its table.
  def load
    Primitive.attr! :hidden
    @loaded = true
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
    CASED.include?(encoding.name)
  end

  # A String carries a byte-oriented encoding, UTF-8, or UTF-16 or
  # UTF-32. The rest need byte tables this runtime does not have.
  def self.carried(encoding)
    Primitive.attr! :hidden
    Primitive.zr_unimplemented("a String in the #{encoding} encoding") unless encoding.bytewise? || encoding.equal?(UTF_8) || wide?(encoding)

    encoding.send(:load).index
  end

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

  # The message a join of two encodings raises, which the runtime asks
  # for because the names live here.
  def self.incompatible(a, b)
    Primitive.attr! :hidden
    raise CompatibilityError, "incompatible character encodings: #{shown(a.encoding)} and #{shown(b.encoding)}"
  end

  # BINARY reads as both its names where an error names it.
  def self.shown(encoding)
    Primitive.attr! :hidden
    encoding.equal?(ASCII_8BIT) ? "BINARY (ASCII-8BIT)" : encoding.name
  end

  # The code point each byte from 128 up stands for, nil where the
  # encoding leaves the byte out. Bytes below 128 stand for themselves
  # in every encoding that has a table.
  def points
    Primitive.attr! :hidden
    @points ||= HIGH.fetch(name).scan(/..../).map { |hex| hex == "----" ? nil : hex.to_i(16) }
  end

  # `text` written in `target`. UTF-8 is the meeting point, so a pair
  # with neither side in it converts twice, and its errors name both
  # steps.
  def self.convert(text, target, options)
    Primitive.attr! :hidden
    from = text.encoding
    target.send(:load)
    return text.dup.force_encoding(target) if from.equal?(target)

    path = from.equal?(UTF_8) || target.equal?(UTF_8) ? [from, target] : [from, UTF_8, target]
    path.each_cons(2) { |a, b| converter(a, b, path, text.ascii_only?) }
    text = to_utf8(text, path, options) unless from.equal?(UTF_8)
    text = from_utf8(text, target, path, options) unless target.equal?(UTF_8)
    text
  end

  # An encoding with no table gets past here, and so does a pair ruby
  # itself refuses to convert between. Plain ASCII crosses that second
  # one anyway, converter or none.
  def self.converter(a, b, path, ascii)
    Primitive.attr! :hidden
    [a, b].each do |encoding|
      next if encoding.equal?(UTF_8) || UNITS.key?(encoding.name)
      # Plain ASCII crosses an ASCII-compatible encoding with no table.
      next if ascii && !SHAPES.key?(encoding.name) && encoding.ascii_compatible? && !encoding.dummy?
      Primitive.zr_unimplemented("String#encode to the #{encoding} encoding") unless SHAPES.key?(encoding.name)
      raise ConverterNotFoundError, "code converter not found (#{path.first.name} to #{path.last.name})" if SHAPES[encoding.name].nil? && !ascii
    end
  end
  private_class_method :converter

  # Each byte read as the code point its encoding gives it.
  def self.to_utf8(text, path, options)
    Primitive.attr! :hidden
    from = text.encoding
    return units_to_utf8(text, from, replacement(path.last, options), options) if UNITS.key?(from.name)

    out = +""
    text.each_byte do |byte|
      if byte < 128
        out << byte
      elsif from.equal?(ASCII_8BIT)
        undefined(byte_text(byte), from, UTF_8, path, options) { |mark| out << mark }
      elsif (point = from.send(:points)[byte - 128])
        out << point
      else
        undefined(byte_text(byte), from, UTF_8, path, options) { |mark| out << mark }
      end
    end
    out
  end
  private_class_method :to_utf8

  # Each character written as the bytes the target gives its code point.
  def self.from_utf8(text, target, path, options)
    Primitive.attr! :hidden
    unit, big = UNITS[target.name]
    big = true if unit && big.nil?
    points = unit || target.equal?(ASCII_8BIT) || target.equal?(US_ASCII) || text.ascii_only? ? nil : target.send(:points)
    out = []
    utf8_points(text, replacement(target, options), options) do |point|
      bytes = point_bytes(point, unit, big, points)
      if bytes
        out.concat(bytes)
      elsif options[:xml]
        out.concat("&#x#{format('%X', point)};".bytes)
      else
        undefined("U+#{format('%04X', point)}", UTF_8, target, path, options) do |mark|
          mark.each_char { |char| out.concat(point_bytes(char.ord, unit, big, points) || char.bytes) }
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
  def self.point_bytes(point, unit, big, points)
    Primitive.attr! :hidden
    if unit
      units = unit == 4 || point < 0x10000 ? [point] : [0xD800 + ((point - 0x10000) >> 10), 0xDC00 + ((point - 0x10000) & 0x3FF)]
      units.flat_map do |code|
        bytes = (0...unit).map { |k| (code >> (8 * k)) & 0xFF }
        big ? bytes.reverse : bytes
      end
    elsif point < 128
      [point]
    elsif points && (found = points.index(point))
      [found + 128]
    end
  end
  private_class_method :point_bytes

  # What `invalid: :replace` writes: the caller's text, else U+FFFD into
  # a Unicode encoding and "?" into any other.
  def self.replacement(target, options)
    Primitive.attr! :hidden
    options[:replace] || (target.equal?(UTF_8) || UNITS.key?(target.name) ? "�" : "?")
  end
  private_class_method :replacement

  # Each code point of UTF-8 `text`. Bytes UTF-8 does not allow raise
  # as ruby's decoder words them, or become `mark` once under `invalid:
  # :replace`.
  def self.utf8_points(text, mark, options)
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
        invalid(bytes[i, length], kind == :bad ? [bytes[i + length]] : nil, kind == :ended, "UTF-8")
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
    read = ->(at) { (big ? bytes[at, unit] : bytes[at, unit].reverse).inject(0) { |code, byte| (code << 8) | byte } }
    while i < bytes.size
      if bytes.size - i < unit
        bad.(bytes[i..], nil, true)
        break
      end
      code = read.(i)
      if unit == 4
        code > 0x10FFFF || code.between?(0xD800, 0xDFFF) ? bad.(bytes[i, 4], nil, false) : points << code
        i += 4
      elsif code.between?(0xDC00, 0xDFFF)
        bad.(bytes[i, 2], nil, false)
        i += 2
      elsif code.between?(0xD800, 0xDBFF)
        if bytes.size - i < 4
          bad.(bytes[i..], nil, true)
          break
        end
        low = read.(i + 2)
        if low.between?(0xDC00, 0xDFFF)
          points << (0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00))
          i += 4
        else
          bad.(bytes[i, 2], bytes[i + 2, 2], false)
          i += 2
        end
      else
        points << code
        i += 2
      end
    end
    points.pack("U*")
  end
  private_class_method :units_to_utf8

  # Ruby's words for bytes a decoder cannot read: `incomplete` when the
  # input ends inside them, else `followed by` the bytes it reads again.
  def self.invalid(error, again, ended, name)
    Primitive.attr! :hidden
    shown = error.pack("C*").dump
    text = if ended then "incomplete #{shown}"
           elsif again then "#{shown} followed by #{again.pack('C*').dump}"
           else shown
           end
    raise InvalidByteSequenceError, "#{text} on #{name}"
  end
  private_class_method :invalid

  # A byte or a character the step cannot write: replaced when the
  # caller asked for that, else ruby's own error, worded for the whole
  # path.
  def self.undefined(shown, from, to, path, options)
    Primitive.attr! :hidden
    if options[:undef] == :replace || options[:invalid] == :replace
      replacement = options[:replace] || (to.equal?(UTF_8) ? "\uFFFD" : "?")
      return yield(replacement)
    end

    raise UndefinedConversionError, message(shown, from, to, path)
  end
  private_class_method :undefined

  # `X from A to B` for a single step ruby words that way, else the
  # chain form, which names every encoding on the path.
  def self.message(shown, from, to, path)
    Primitive.attr! :hidden
    other = to.equal?(UTF_8) ? from : to
    row = SHAPES.fetch(other.name)
    return "#{shown} from #{from.name} to #{to.name}" if path.size == 2 && (to.equal?(UTF_8) ? row[2] : row[0])

    step = to.equal?(UTF_8) ? "UTF-8" : row[1]
    named = path.map { |encoding| encoding.equal?(to) ? step : encoding.name }
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
  def self.name_list = LIST.flat_map(&:names) << "internal"

  # Every name but the first of each encoding, pointing at the first.
  def self.aliases
    LIST.each_with_object({}) { |encoding, out| encoding.names.drop(1).each { |name| out[name] = encoding.name } }
  end

  def self.locale_charmap = "UTF-8"

  def self.find(name)
    return name if name.is_a?(Encoding)

    text = String.try_convert(name)
    raise TypeError, "no implicit conversion of #{name.class} into String" if text.nil?
    # `internal` names no row: it is whatever default_internal is, nil too.
    return default_internal if text.casecmp?("internal")

    found = LIST.find { |encoding| encoding.names.any? { |n| n.casecmp?(text) } }
    return found.send(:load) if found

    raise ArgumentError, "unknown encoding name - #{text}"
  end

  # Both ends of a conversion. A name no encoding answers to is not an
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

  def self.default_external = UTF_8

  def self.default_internal = nil

  def self.default_external=(encoding)
    Primitive.zr_unimplemented("Encoding.default_external=")
  end

  def self.default_internal=(encoding)
    Primitive.zr_unimplemented("Encoding.default_internal=")
  end

  # rb_enc_compatible for two Strings: an empty side gives way, and
  # UTF-16 or UTF-32 joins nothing else.
  def self.compatible?(a, b)
    return nil unless a.is_a?(String) && b.is_a?(String)
    return a.encoding if a.encoding == b.encoding || b.empty?
    return a.encoding.ascii_compatible? && b.ascii_only? ? a.encoding : b.encoding if a.empty?
    return nil unless a.encoding.ascii_compatible? && b.encoding.ascii_compatible?
    return a.encoding if b.ascii_only?
    return b.encoding if a.ascii_only?

    nil
  end
end

class Symbol
  def encoding = to_s.encoding
end

# An empty namespace at boot, as CRuby defines it; ruby's normalize.rb
# fills it on String#unicode_normalize's first call.
module UnicodeNormalize
end
