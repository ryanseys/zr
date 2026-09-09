# String methods written over the byte primitives. Every character
# method first checks the string is ASCII, so a multibyte string stops
# loudly instead of getting a byte answer.
class String
  include Comparable

  def [](index, length = nil)
    Primitive.zr_str_ascii_check(self)
    size = bytesize
    case index
    when Integer
      if length
        return nil if length < 0

        start = index < 0 ? index + size : index
        return nil if start < 0 || start > size

        length = size - start if start + length > size
        return byteslice_of(start, length)
      end
      byte = Primitive.zr_str_byte_at(self, index)
      byte && Primitive.zr_str_from_byte(byte)
    when Range
      start, length = range_span(index, size)
      start && byteslice_of(start, length)
    when String
      Primitive.zr_str_ascii_check(index)
      include?(index) ? index.dup : nil
    else
      raise TypeError, "no implicit conversion of #{index.class} into Integer" unless index.respond_to?(:to_int)

      self[index.to_int, *[length].compact]
    end
  end
  alias slice []

  def chars = each_char.to_a

  def each_char
    return to_enum(:each_char) { size } unless block_given?

    Primitive.zr_str_ascii_check(self)
    i = 0
    while i < bytesize
      yield Primitive.zr_str_from_byte(Primitive.zr_str_byte_at(self, i))
      i += 1
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

  def ord
    raise ArgumentError, "empty string" if empty?

    Primitive.zr_str_ascii_check(self)
    Primitive.zr_str_byte_at(self, 0)
  end

  def start_with?(*prefixes)
    prefixes.any? do |prefix|
      Primitive.zr_unimplemented("String#start_with? with a Regexp") unless prefix.is_a?(String)
      prefix.bytesize <= bytesize && byteslice_of(0, prefix.bytesize) == prefix
    end
  end

  def end_with?(*suffixes)
    suffixes.any? do |suffix|
      suffix.bytesize <= bytesize && byteslice_of(bytesize - suffix.bytesize, suffix.bytesize) == suffix
    end
  end

  def delete_prefix(prefix) = start_with?(prefix) ? byteslice_of(prefix.bytesize, bytesize - prefix.bytesize) : dup

  def delete_suffix(suffix) = end_with?(suffix) ? byteslice_of(0, bytesize - suffix.bytesize) : dup

  def replace(other) = Primitive.zr_str_replace(self, other)

  # `slice!`: the part `[]` would answer, cut out of the receiver.
  def slice!(*args)
    Primitive.zr_str_ascii_check(self)
    part = self[*args]
    return nil if part.nil?

    start = if args[0].is_a?(String) then index(args[0])
            elsif args[0].is_a?(Range) then range_span(args[0], bytesize)&.first
            else
              i = args[0]
              i += bytesize if i < 0
              i
            end
    replace(byteslice_of(0, start) + byteslice_of(start + part.bytesize, bytesize - start - part.bytesize))
    part
  end

  # `s[i] = t`, `s[start, len] = t`, `s[range] = t` and `s[sub] = t`:
  # the span leaves and `t` takes its place.
  def []=(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 2..3)" unless args.size == 2 || args.size == 3

    Primitive.zr_str_ascii_check(self)
    Primitive.zr_frozen_error(self) if frozen?
    value = args.pop
    raise TypeError, "no implicit conversion of #{value.class} into String" unless value.is_a?(String)

    index = args[0]
    size = bytesize
    case index
    when Integer
      start = index < 0 ? index + size : index
      raise IndexError, "index #{index} out of string" if start < 0 || start > size

      if args.size == 2
        length = args[1]
        raise IndexError, "negative length #{length}" if length < 0

        length = size - start if start + length > size
      else
        length = start == size ? 0 : 1
      end
    when Range
      start, length = range_span(index, size)
      raise RangeError, "#{index.inspect} out of range" unless start
    when String
      start = self.index(index)
      raise IndexError, "string not matched" unless start

      length = index.bytesize
    else
      raise TypeError, "no implicit conversion of #{index.class} into Integer"
    end
    replace(byteslice_of(0, start) + value + byteslice_of(start + length, size - start - length))
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
    index += bytesize + 1 if index < 0
    raise IndexError, "index #{index} out of string" if index < 0 || index > bytesize

    replace(byteslice_of(0, index) + other + byteslice_of(index, bytesize - index))
  end

  def swapcase
    Primitive.zr_str_ascii_check(self)
    out = +""
    each_byte do |b|
      if b >= 65 && b <= 90
        b += 32
      elsif b >= 97 && b <= 122
        b -= 32
      end
      out << Primitive.zr_str_from_byte(b)
    end
    out
  end

  # The bang forms answer nil when nothing changed.
  def upcase! = mutate(upcase)
  def downcase! = mutate(downcase)
  def capitalize! = mutate(capitalize)
  def swapcase! = mutate(swapcase)
  def reverse! = replace(reverse)
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

    byteslice_of(0, bytesize - 1)
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

  def lines(separator = "\n", chomp: false)
    Primitive.zr_unimplemented("String#lines with a separator") unless separator == "\n"

    out = []
    start = 0
    while start < bytesize
      stop = index("\n", start)
      stop = stop ? stop + 1 : bytesize
      line = byteslice_of(start, stop - start)
      out << (chomp ? line.chomp : line)
      start = stop
    end
    out
  end

  def each_line(separator = "\n", chomp: false, &block)
    return to_enum(:each_line, separator, chomp: chomp) unless block

    lines(separator, chomp: chomp).each(&block)
    self
  end

  def split(pattern = nil, limit = 0)
    Primitive.zr_unimplemented("String#split with a Regexp") unless pattern.nil? || pattern.is_a?(String)
    Primitive.zr_str_ascii_check(self)
    return split_words(limit) if pattern.nil? || pattern == " "
    return split_chars(limit) if pattern.empty?

    out = []
    start = 0
    while (limit <= 0 || out.size < limit - 1) && (i = index(pattern, start))
      out << byteslice_of(start, i - start)
      start = i + pattern.bytesize
    end
    out << byteslice_of(start, bytesize - start)
    out.pop while limit == 0 && !out.empty? && out.last.empty?
    out
  end

  def sub(pattern, replacement = nil, &block)
    Primitive.zr_unimplemented("String#sub with a Regexp") unless pattern.is_a?(String)
    i = index(pattern)
    return dup unless i

    with = block ? yield(pattern).to_s : replacement
    byteslice_of(0, i) + with + byteslice_of(i + pattern.bytesize, bytesize - i - pattern.bytesize)
  end

  def gsub(pattern, replacement = nil, &block)
    Primitive.zr_unimplemented("String#gsub with a Regexp") unless pattern.is_a?(String)
    return dup if pattern.empty?

    out = +""
    start = 0
    while (i = index(pattern, start))
      out << byteslice_of(start, i - start)
      out << (block ? yield(pattern).to_s : replacement)
      start = i + pattern.bytesize
    end
    out << byteslice_of(start, bytesize - start)
  end

  def sub!(pattern, replacement = nil, &block) = mutate(sub(pattern, replacement, &block))

  def gsub!(pattern, replacement = nil, &block) = mutate(gsub(pattern, replacement, &block))

  def index(needle, start = 0)
    Primitive.zr_unimplemented("String#index with a Regexp") unless needle.is_a?(String)
    Primitive.zr_str_ascii_check(self)
    start += bytesize if start < 0
    return nil if start < 0 || start > bytesize

    Primitive.zr_str_find_from(self, needle, start)
  end

  def rindex(needle, start = bytesize)
    Primitive.zr_unimplemented("String#rindex with a Regexp") unless needle.is_a?(String)
    Primitive.zr_str_ascii_check(self)
    start += bytesize if start < 0
    return nil if start < 0

    i = [start, bytesize - needle.bytesize].min
    while i >= 0
      return i if byteslice_of(i, needle.bytesize) == needle

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

  def tr_s(from, to) = translate(from, to, true)

  def upto(last, exclusive = false, &block)
    return to_enum(:upto, last, exclusive) unless block

    last = last.to_str
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
    current = dup
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
    at = index(sep)
    at ? [self[0, at], sep.dup, self[at + sep.bytesize..]] : [dup, "", ""]
  end

  def rpartition(sep)
    at = rindex(sep)
    at ? [self[0, at], sep.dup, self[at + sep.bytesize..]] : ["", "", dup]
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

    length = size - start if start + length > size
    byteslice_of(start, length)
  end

  def codepoints
    Primitive.zr_str_ascii_check(self)
    bytes
  end

  def scan(pattern)
    Primitive.zr_unimplemented("String#scan with a Regexp") unless pattern.is_a?(String)
    Primitive.zr_str_ascii_check(self)
    found = []
    at = 0
    while at <= bytesize && (hit = index(pattern, at))
      found << pattern.dup
      at = hit + [pattern.bytesize, 1].max
    end
    return found unless block_given?

    found.each { |m| yield m }
    self
  end

  DUMP_ESCAPES = { 7 => "\\a", 8 => "\\b", 9 => "\\t", 10 => "\\n", 11 => "\\v", 12 => "\\f", 13 => "\\r", 27 => "\\e", 34 => "\\\"", 92 => "\\\\" }.freeze
  private_constant :DUMP_ESCAPES

  # Every byte outside printable ASCII escaped, so the result reads
  # back as the same bytes.
  def dump
    Primitive.zr_str_ascii_check(self)
    out = +"\""
    bytes = each_byte.to_a
    bytes.each_with_index do |b, i|
      if DUMP_ESCAPES.key?(b)
        out << DUMP_ESCAPES[b]
      elsif b == 35 && [123, 36, 64].include?(bytes[i + 1])
        out << "\\#"
      elsif b < 32 || b >= 127
        out << format("\\x%02X", b)
      else
        out << Primitive.zr_str_from_byte(b)
      end
    end
    out << "\""
  end

  def undump = Primitive.zr_unimplemented("String#undump")

  def hex = lenient_integer(16)

  def oct = lenient_integer(-8)

  def center(width, pad = " ") = justify(width, pad, :center)

  def ljust(width, pad = " ") = justify(width, pad, :left)

  def rjust(width, pad = " ") = justify(width, pad, :right)

  def to_i(base = 10)
    Primitive.zr_unimplemented("String#to_i with a base other than 10") unless base == 10
    Primitive.zr_str_ascii_check(self)
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
    return other =~ self if other.respond_to?(:=~) && !other.is_a?(String)

    Primitive.zr_unimplemented("String#=~ with a Regexp")
  end

  def match?(other) = Primitive.zr_unimplemented("String#match?")

  def unpack(fmt) = Primitive.zr_unimplemented("String#unpack")

  def unpack1(fmt) = Primitive.zr_unimplemented("String#unpack1")

  def encoding = Primitive.zr_unimplemented("String#encoding")

  def force_encoding(enc) = Primitive.zr_unimplemented("String#force_encoding")

  def ascii_only?
    each_byte.all? { |b| b < 128 }
  end

  def valid_encoding? = ascii_only? || Primitive.zr_unimplemented("String#valid_encoding? on a non-ASCII string")

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
    Primitive.zr_str_ascii_check(self)
    text = lstrip
    i = 0
    sign = 1
    if text[i] == "-" || text[i] == "+"
      sign = -1 if text[i] == "-"
      i += 1
    end
    if text[i] == "0" && text[i + 1]
      prefix = text[i + 1].downcase
      chosen = { "x" => 16, "b" => 2, "o" => 8, "d" => 10 }[prefix]
      if chosen && (base < 0 || chosen == base)
        base = chosen
        i += 2
      end
    end
    base = -base if base < 0
    value = 0
    seen = false
    while i < text.bytesize
      ch = text[i]
      if ch == "_" && seen && text[i + 1] && !(text[i + 1] == "_")
        i += 1
        next
      end
      digit = ch.between?("0", "9") ? ch.ord - 48 : (ch.downcase.between?("a", "z") ? ch.downcase.ord - 87 : 99)
      break if digit >= base

      value = value * base + digit
      seen = true
      i += 1
    end
    sign * value
  end

  def mutate(result)
    return nil if result == self

    replace(result)
  end

  def space_byte?(b) = b == 32 || (b >= 9 && b <= 13) || b == 0

  def digit_byte?(b) = b >= 48 && b <= 57

  # The start and length a Range names in a string of `size` bytes,
  # or nil when it starts past the end.
  def range_span(range, size)
    first = range.begin || 0
    first += size if first < 0
    return nil if first < 0 || first > size

    last = range.end || size
    last += size if last < 0
    last -= 1 if range.exclude_end? && range.end
    length = last - first + 1
    length = 0 if length < 0
    length = size - first if first + length > size
    [first, length]
  end

  def split_words(limit)
    out = []
    i = 0
    i += 1 while i < bytesize && space_byte?(Primitive.zr_str_byte_at(self, i))
    while i < bytesize
      if limit > 0 && out.size == limit - 1
        out << byteslice_of(i, bytesize - i)
        return out
      end
      stop = i
      stop += 1 while stop < bytesize && !space_byte?(Primitive.zr_str_byte_at(self, stop))
      out << byteslice_of(i, stop - i)
      i = stop
      i += 1 while i < bytesize && space_byte?(Primitive.zr_str_byte_at(self, i))
    end
    out
  end

  def split_chars(limit)
    return chars if limit <= 0
    return [dup] if limit == 1

    out = chars.first(limit - 1)
    out << byteslice_of(limit - 1, bytesize - limit + 1) if limit - 1 < bytesize
    out
  end

  def justify(width, pad, side)
    raise ArgumentError, "zero width padding" if pad.empty?
    return dup if width <= bytesize

    fill = width - bytesize
    left = side == :left ? 0 : (side == :right ? fill : fill / 2)
    right = fill - left
    padding(left, pad) + self + padding(right, pad)
  end

  def padding(n, pad)
    out = +""
    out << pad while out.bytesize < n
    out.byteslice_of(0, n)
  end
end

class Symbol
  def [](*args) = to_s[*args]

  def length = to_s.length
  alias size length

  def upcase = to_s.upcase.to_sym
  def downcase = to_s.downcase.to_sym
  def capitalize = to_s.capitalize.to_sym
  def swapcase = to_s.swapcase.to_sym
  def succ = to_s.succ.to_sym

  def start_with?(*prefixes) = to_s.start_with?(*prefixes)
  def end_with?(*suffixes) = to_s.end_with?(*suffixes)
  def empty? = to_s.empty?
end

class Symbol
  def to_sym = self
  alias id2name to_s
  alias name to_s
end
