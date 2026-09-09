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

  def chars = each_char.to_a

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

  def bytes = each_byte.to_a

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

  def start_with?(*prefixes)
    prefixes.any? do |prefix|
      if prefix.is_a?(Regexp)
        match = prefix.send(:match_at, self, 0)
        Primitive.zr_backref_set(match)
        next !match.nil?
      end
      prefix = Primitive.zr_str_operand(prefix)

      prefix.bytesize <= bytesize && byteslice_of(0, prefix.bytesize) == prefix
    end
  end

  def end_with?(*suffixes)
    suffixes.any? do |suffix|
      suffix = Primitive.zr_str_operand(suffix)
      suffix.bytesize <= bytesize && byteslice_of(bytesize - suffix.bytesize, suffix.bytesize) == suffix
    end
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

  def prepend(*others) = replace(others.join + self)

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
  def squeeze! = mutate(squeeze)

  def strip = lstrip.rstrip

  def lstrip
    i = 0
    i += 1 while i < bytesize && space_byte?(Primitive.zr_str_byte_at(self, i))
    byteslice_of(i, bytesize - i)
  end

  def rstrip
    i = bytesize
    i -= 1 while i > 0 && space_byte?(Primitive.zr_str_byte_at(self, i - 1))
    byteslice_of(0, i)
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
    member = sets.empty? ? nil : charset_test(sets)
    out = +""
    last = nil
    each_byte do |b|
      out << Primitive.zr_str_from_byte(b) unless b == last && (member.nil? || member.call(b))
      last = b
    end
    out
  end

  # The lines up to and including `separator`: nil keeps the whole
  # text, "" splits paragraphs at blank lines (extra blank lines are
  # dropped), `chomp` strips the separator.
  def lines(separator = $/, chomp: false)
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

  def each_line(separator = $/, chomp: false, &block)
    return to_enum(:each_line, separator, chomp: chomp) unless block

    lines(separator, chomp: chomp).each(&block)
    self
  end

  # CRuby's four splits: awk (nil or " "), characters (""), a String
  # and a Regexp. A positive limit caps the pieces; a negative one keeps
  # trailing empty pieces; zero drops them.
  def split(pattern = nil, limit = 0)
    limit = limit.to_int unless limit.is_a?(Integer)
    if limit == 1
      return block_given? ? (yield dup; self) : (empty? ? [] : [dup])
    end
    pattern = $; if pattern.nil?
    pattern = Primitive.zr_str_operand(pattern) if !pattern.nil? && !pattern.is_a?(String) && !pattern.is_a?(Regexp) && pattern.respond_to?(:to_str)
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
    i = [from, bytesize - needle.bytesize].min
    while i >= 0
      return Primitive.zr_str_byte_to_char(self, i) if byteslice_of(i, needle.bytesize) == needle

      i -= 1
    end
    nil
  end

  def count(*sets)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if sets.empty?

    member = charset_test(sets)
    each_byte.count { |b| member.call(b) }
  end

  def delete(*sets)
    raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if sets.empty?

    member = charset_test(sets)
    out = +""
    each_byte { |b| out << Primitive.zr_str_from_byte(b) unless member.call(b) }
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
      else
        Primitive.zr_str_operand(part).each_byte { |b| Primitive.zr_str_push_byte(self, b) }
      end
    end
    self
  end

  def crypt(salt)
    salt = Primitive.zr_str_operand(salt)
    raise ArgumentError, "salt too short (need >=2 bytes)" if salt.bytesize < 2
    raise ArgumentError, "string contains null byte" if include?("\0") || salt.include?("\0")

    Primitive.zr_str_crypt(self, salt)
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

  def codepoints = each_char.map(&:ord)

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

  # The text `dump` wrote, read back; a trailing `.force_encoding(...)`
  # names the encoding.
  def undump
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

  def casecmp(other)
    return nil unless other.is_a?(String)

    downcase <=> other.downcase
  end

  def casecmp?(other)
    return nil unless other.is_a?(String)

    downcase == other.downcase
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

  def encoding = Encoding.walked(Primitive.zr_str_encoding_kind(self))

  def force_encoding(encoding)
    encoding = Encoding.find(encoding) unless encoding.is_a?(Encoding)
    kind = Encoding.walked_index(encoding)
    Primitive.zr_unimplemented("a String in the #{encoding} encoding") if kind.nil?

    Primitive.zr_str_set_encoding(self, kind)
  end

  # A copy in `target`: the same bytes when they read the same in
  # both, else an error for the first byte that does not.
  def encode(target = Encoding.default_internal || Encoding.default_external, *rest, **options)
    Primitive.zr_unimplemented("String#encode with a source encoding or options") unless rest.empty? && options.empty?
    target = Encoding.find(target) unless target.is_a?(Encoding)
    Primitive.zr_unimplemented("String#encode to the #{target} encoding") if Encoding.walked_index(target).nil?

    copy = dup
    return copy if target == encoding || ascii_only?
    return copy.force_encoding(target) if target == Encoding::BINARY

    bad = each_byte.find { |b| b >= 128 }
    raise Encoding::UndefinedConversionError, "\"\\x#{format('%02X', bad)}\" from #{encoding} to #{target}" if encoding == Encoding::BINARY
    raise Encoding::UndefinedConversionError, "U+#{format('%04X', each_char.find { |c| c.ord >= 128 }.ord)} from UTF-8 to US-ASCII"
  end

  def ascii_only?
    each_byte.all? { |b| b < 128 }
  end

  def valid_encoding? = Primitive.zr_str_valid_p(self)

  # Every invalid byte replaced by `replacement` (U+FFFD, or the
  # block's answer for the bad bytes).
  def scrub(replacement = nil)
    return dup if valid_encoding?

    replacement = "\uFFFD" if replacement.nil? && !block_given?
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

  # Whether byte `at` starts a character (or ends the text).
  def char_boundary?(at)
    Primitive.attr! :hidden
    at >= bytesize || (getbyte(at) & 0xC0) != 0x80
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
    i = [start, bytesize - needle.bytesize].min
    i -= 1 while i >= 0 && byteslice_of(i, needle.bytesize) != needle
    i >= 0 ? i : nil
  end

  def unicode_normalize(form = :nfc) = Primitive.zr_unimplemented("String#unicode_normalize")

  def unicode_normalize!(form = :nfc) = Primitive.zr_unimplemented("String#unicode_normalize!")

  def unicode_normalized?(form = :nfc) = Primitive.zr_unimplemented("String#unicode_normalized?")

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
      spec = spec.to_str
      Primitive.zr_str_ascii_check(spec)
      chars, negated = charset(spec)
      negated ? ->(b) { !chars.include?(b) } : ->(b) { chars.include?(b) }
    end
    ->(b) { tests.all? { |test| test.call(b) } }
  end

  # The bytes a tr spec names, in order, and whether it is negated.
  def charset(spec)
    Primitive.attr! :hidden
    bytes = spec.bytes
    negated = bytes.size > 1 && bytes[0] == 94
    bytes.shift if negated
    out = []
    i = 0
    while i < bytes.size
      if bytes[i] == 92 && i + 1 < bytes.size
        out << bytes[i + 1]
        i += 2
      elsif i + 2 < bytes.size && bytes[i + 1] == 45
        raise ArgumentError, "invalid range \"#{Primitive.zr_str_from_byte(bytes[i])}-#{Primitive.zr_str_from_byte(bytes[i + 2])}\" in string transliteration" if bytes[i] > bytes[i + 2]

        (bytes[i]..bytes[i + 2]).each { |b| out << b }
        i += 3
      else
        out << bytes[i]
        i += 1
      end
    end
    [out, negated]
  end

  # tr: each byte in `from` becomes the byte at the same place in
  # `to`, the last one standing in for the rest; a negated `from`
  # maps every other byte to the last of `to`. `squeeze` collapses
  # runs of one translated byte.
  def translate(from, to, squeeze)
    Primitive.attr! :hidden
    Primitive.zr_str_ascii_check(self)
    source, negated = charset(from.to_str)
    target, _ = charset(to.to_str)
    out = +""
    last = nil
    each_byte do |b|
      at = source.index(b)
      hit = negated ? at.nil? : !at.nil?
      unless hit
        out << Primitive.zr_str_from_byte(b)
        last = nil
        next
      end
      if target.empty?
        last = nil
        next
      end
      at = source.rindex(b) unless negated
      mapped = negated ? target[-1] : (target[at] || target[-1])
      out << Primitive.zr_str_from_byte(mapped) unless squeeze && mapped == last
      last = mapped
    end
    out
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

  def split_words(limit)
    out = []
    beg = 0
    stop = 0
    skip = true
    pieces = 1
    i = 0
    while i < bytesize
      space = space_byte?(Primitive.zr_str_byte_at(self, i))
      i += 1
      if skip
        if space
          beg = i
        else
          stop = i
          skip = false
          break if limit > 0 && limit <= pieces
        end
      elsif space
        out << byteslice_of(beg, stop - beg)
        skip = true
        beg = i
        pieces += 1
      else
        stop = i
      end
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
    raise TypeError, "wrong argument type #{pattern.class} (expected Regexp)" unless pattern.is_a?(String)

    at = byte_index(pattern, start)
    at && MatchData.send(:for, pattern, self, [at, at, at + pattern.bytesize])
  end

  # What replaces one match: the block's answer, the Hash's entry, or
  # the replacement text with its backreferences filled in.
  def replacement_for(match, replacement, &block)
    Primitive.attr! :hidden
    return yield(match[0]).to_s if block
    return replacement[match[0]].to_s if replacement.is_a?(Hash)

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
      when "0", "&" then out << match[0]
      when "1".."9" then out << (numbered && d.to_i < match.size ? match[d.to_i].to_s : "")
      when "+" then out << match.send(:last_group).to_s
      when "\\" then out << "\\"
      when "`" then out << match.pre_match
      when "'" then out << match.post_match
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
    return Primitive.zr_str_map_case_m(self, KERNEL_CASE[kind]) if mode != :turkic && KERNEL_CASE.key?(kind) && Primitive.zr_str_ascii_check(self)

    out = +""
    each_char.with_index do |char, i|
      step = kind == :title ? (i.zero? ? :title : :down) : kind
      out << case_char(char, step, mode)
    end
    out
  end

  def case_char(char, kind, mode)
    Primitive.attr! :hidden
    code = char.ord
    return char if mode == :ascii && code > 127
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
    count = size
    return dup if width <= count

    fill = width - count
    left = side == :left ? 0 : (side == :right ? fill : fill / 2)
    right = fill - left
    padding(left, pad) + self + padding(right, pad)
  end

  def padding(n, pad)
    out = +""
    out << pad while out.size < n
    out[0, n]
  end
end

class Symbol
  def [](*args) = to_s[*args]
  alias slice []

  def length = to_s.length
  alias size length

  def =~(other) = to_s =~ other
  def match(*args, &block) = to_s.match(*args, &block)
  def match?(*args) = to_s.match?(*args)

  # The case mappings are String's own, past any a program adds to it.
  def upcase = Primitive.zr_str_map_case_m(to_s, 1).to_sym
  def downcase = Primitive.zr_str_map_case_m(to_s, 2).to_sym
  def capitalize = Primitive.zr_str_map_case_m(to_s, 3).to_sym
  def swapcase = String.instance_method(:swapcase).bind_call(to_s).to_sym
  def succ = to_s.succ.to_sym
  alias next succ

  def start_with?(*prefixes) = to_s.start_with?(*prefixes)
  def end_with?(*suffixes) = to_s.end_with?(*suffixes)
  def empty? = to_s.empty?
end

class Symbol
  include Comparable

  def to_sym = self

  def intern = self

  def casecmp(other) = other.is_a?(Symbol) ? to_s.casecmp(other.to_s) : nil

  def casecmp?(other) = other.is_a?(Symbol) ? to_s.casecmp?(other.to_s) : nil
  alias id2name to_s
  alias name to_s

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
    def initialize(*) = Primitive.zr_unimplemented("Encoding::Converter")

    def self.search_convpath(*) = Primitive.zr_unimplemented("Encoding::Converter.search_convpath")
    def self.asciicompat_encoding(*) = Primitive.zr_unimplemented("Encoding::Converter.asciicompat_encoding")
  end

  attr_reader :names

  def initialize(names, dummy, ascii, loaded)
    @names = names.freeze
    @dummy = dummy
    @ascii = ascii
    @loaded = loaded
  end

  def name = @names.first
  alias to_s name

  # BINARY is the name the report shows, ASCII-8BIT the one it answers.
  # An encoding whose table a fresh ruby has not read says so.
  def inspect
    shown = @names[1] == "BINARY" ? "BINARY (ASCII-8BIT)" : name
    @loaded ? "#<Encoding:#{shown}>" : "#<Encoding:#{shown} (autoload)>"
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

  LIST = ROWS.map { |names, dummy, ascii, loaded| new(names, dummy, ascii, loaded) }.freeze
  private_constant :LIST

  BY_NAME = LIST.each_with_object({}) { |encoding, out| encoding.names.each { |name| out[name] = encoding } }.freeze
  private_constant :BY_NAME

  CONSTANTS.each { |const, name| const_set(const, BY_NAME.fetch(name)) }

  # The three the runtime walks, by the number a String carries.
  WALKED = [UTF_8, ASCII_8BIT, US_ASCII].freeze
  private_constant :WALKED

  def self.walked(kind)
    Primitive.attr! :hidden
    WALKED[kind]
  end

  def self.walked_index(encoding)
    Primitive.attr! :hidden
    WALKED.index(encoding)
  end

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

    name = name.to_str
    found = LIST.find { |encoding| encoding.names.any? { |n| n.casecmp?(name) } }
    return found.send(:load) if found

    raise ArgumentError, "unknown encoding name - #{name}"
  end

  def self.default_external = UTF_8

  def self.default_internal = nil

  def self.default_external=(encoding)
    Primitive.zr_unimplemented("Encoding.default_external=")
  end

  def self.default_internal=(encoding)
    Primitive.zr_unimplemented("Encoding.default_internal=")
  end

  def self.compatible?(a, b)
    return nil unless a.is_a?(String) && b.is_a?(String)
    return a.encoding if a.encoding == b.encoding
    return a.encoding if b.ascii_only?
    return b.encoding if a.ascii_only?

    nil
  end
end

class Symbol
  def encoding = to_s.encoding
end
