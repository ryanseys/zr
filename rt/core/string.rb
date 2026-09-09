# String methods written over the byte primitives. Character indexes
# map to byte offsets through the kernel, which reads UTF-8; a binary
# string's bytes are its characters. Case mapping, succ and character
# sets stop on non-ASCII text.
class String
  include Comparable

  def [](index, length = nil)
    case index
    when Integer
      return Primitive.zr_str_char_slice(self, index, length) if length

      count = size
      index += count if index < 0
      return nil if index < 0 || index >= count

      Primitive.zr_str_char_slice(self, index, 1)
    when Range
      start, length = range_span(index, size)
      start && Primitive.zr_str_char_slice(self, start, length)
    when String
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
    part = self[*args]
    return nil if part.nil?

    start = if args[0].is_a?(String) then byte_index(args[0], 0)
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
    raise TypeError, "no implicit conversion of #{value.class} into String" unless value.is_a?(String)

    index = args[0]
    count = size
    case index
    when Integer
      start = index < 0 ? index + count : index
      raise IndexError, "index #{index} out of string" if start < 0 || start > count

      if args.size == 2
        length = args[1]
        raise IndexError, "negative length #{length}" if length < 0

        length = count - start if start + length > count
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
    else
      raise TypeError, "no implicit conversion of #{index.class} into Integer"
    end
    from = Primitive.zr_str_char_offset_m(self, start)
    to = Primitive.zr_str_char_offset_m(self, [start + length, count].min)
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

  def swapcase
    Primitive.zr_unimplemented("String#swapcase on a non-ASCII String") unless Primitive.zr_str_ascii_check(self)
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
    return split_words(limit) if pattern.nil? || pattern == " "
    return split_chars(limit) if pattern.empty?

    out = []
    start = 0
    while (limit <= 0 || out.size < limit - 1) && (i = byte_index(pattern, start))
      out << byteslice_of(start, i - start)
      start = i + pattern.bytesize
    end
    out << byteslice_of(start, bytesize - start)
    out.pop while limit == 0 && !out.empty? && out.last.empty?
    out
  end

  def sub(pattern, replacement = nil, &block)
    Primitive.zr_unimplemented("String#sub with a Regexp") unless pattern.is_a?(String)
    i = byte_index(pattern, 0)
    return dup unless i

    with = block ? yield(pattern).to_s : replacement
    byteslice_of(0, i) + with + byteslice_of(i + pattern.bytesize, bytesize - i - pattern.bytesize)
  end

  def gsub(pattern, replacement = nil, &block)
    Primitive.zr_unimplemented("String#gsub with a Regexp") unless pattern.is_a?(String)
    return dup if pattern.empty?

    out = +""
    start = 0
    while (i = byte_index(pattern, start))
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
    count = size
    start += count if start < 0
    return nil if start < 0 || start > count

    at = byte_index(needle, Primitive.zr_str_char_offset_m(self, start))
    at && Primitive.zr_str_byte_to_char(self, at)
  end

  def rindex(needle, start = size)
    Primitive.zr_unimplemented("String#rindex with a Regexp") unless needle.is_a?(String)
    count = size
    start += count if start < 0
    return nil if start < 0

    from = Primitive.zr_str_char_offset_m(self, [start, count].min)
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
    at = byte_index(sep, 0)
    at ? [byteslice_of(0, at), sep.dup, byteslice_of(at + sep.bytesize, bytesize - at - sep.bytesize)] : [dup, "", ""]
  end

  def rpartition(sep)
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

    length = size - start if start + length > size
    byteslice_of(start, length)
  end

  def codepoints = each_char.map(&:ord)

  def scan(pattern)
    Primitive.zr_unimplemented("String#scan with a Regexp") unless pattern.is_a?(String)
    found = []
    at = 0
    while at <= bytesize && (hit = byte_index(pattern, at))
      found << pattern.dup
      at = hit + [pattern.bytesize, 1].max
    end
    return found unless block_given?

    found.each { |m| yield m }
    self
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
  end

  def undump = Primitive.zr_unimplemented("String#undump")

  def hex = lenient_integer(16)

  def oct = lenient_integer(-8)

  def center(width, pad = " ") = justify(width, pad, :center)

  def ljust(width, pad = " ") = justify(width, pad, :left)

  def rjust(width, pad = " ") = justify(width, pad, :right)

  def to_i(base = 10)
    Primitive.zr_unimplemented("String#to_i with a base other than 10") unless base == 10
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

  def encoding = Encoding::KINDS[Primitive.zr_str_encoding_kind(self)]

  def force_encoding(encoding)
    encoding = Encoding.find(encoding) unless encoding.is_a?(Encoding)
    Primitive.zr_str_set_encoding(self, Encoding::KINDS.index(encoding))
  end

  # A copy in `target`: the same bytes when they read the same in
  # both, else an error for the first byte that does not.
  def encode(target = Encoding.default_internal || Encoding.default_external, *rest, **options)
    Primitive.zr_unimplemented("String#encode with a source encoding or options") unless rest.empty? && options.empty?
    target = Encoding.find(target) unless target.is_a?(Encoding)
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

  def unicode_normalize(*) = Primitive.zr_unimplemented("String#unicode_normalize")

  def each_grapheme_cluster(&block) = Primitive.zr_unimplemented("String#each_grapheme_cluster")

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
    rest = Primitive.zr_str_char_offset_m(self, limit - 1)
    out << byteslice_of(rest, bytesize - rest) if rest && rest < bytesize
    out
  end

  # The byte offset of `needle` at or after byte `start`, or nil.
  def byte_index(needle, start)
    Primitive.attr! :hidden
    return nil if start.nil? || start > bytesize

    Primitive.zr_str_find_from(self, needle, start)
  end

  def justify(width, pad, side)
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

# The encodings a String can be in: UTF-8 (the default), binary, and
# US-ASCII, kept as flags on the string.
class Encoding
  attr_reader :name, :names

  def initialize(name, *aliases)
    @name = name
    @names = [name, *aliases]
  end

  def to_s = @name

  def inspect = @name == "BINARY" ? "#<Encoding:BINARY (ASCII-8BIT)>" : "#<Encoding:#{@name}>"

  def ascii_compatible? = true

  def dummy? = false

  UTF_8 = new("UTF-8", "CP65001")
  BINARY = new("BINARY", "ASCII-8BIT")
  ASCII_8BIT = BINARY
  US_ASCII = new("US-ASCII", "ASCII", "ANSI_X3.4-1968", "646")
  KINDS = [UTF_8, BINARY, US_ASCII].freeze

  def self.list = KINDS.dup

  def self.name_list = KINDS.flat_map(&:names)

  def self.find(name)
    return name if name.is_a?(Encoding)

    name = name.to_str
    found = KINDS.find { |encoding| encoding.names.any? { |n| n.casecmp?(name) } }
    return found if found

    Primitive.zr_unimplemented("the #{name} encoding") if %w[ISO-8859-1 Shift_JIS EUC-JP UTF-16 UTF-16LE UTF-16BE UTF-32 Windows-1252 locale external filesystem].any? { |n| n.casecmp?(name) }
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
    return b.encoding if a.ascii_only?
    return a.encoding if b.ascii_only?

    nil
  end

  class CompatibilityError < EncodingError; end
  class UndefinedConversionError < EncodingError; end
  class InvalidByteSequenceError < EncodingError; end
  class ConverterNotFoundError < EncodingError; end
end

class Symbol
  def encoding = to_s.encoding
end
