# frozen_string_literal: true

# StringScanner: a position in a string and a match at it. Ruby ships
# this as a C extension with a small part in ruby. This file is both
# parts, over the same Regexp engine that the runtime already includes.
#
# `pos` counts bytes, as ruby's does. A match is a byte range in the
# string, and the MatchData next to it when a pattern made it. A byte or
# a character taken on its own has a range and no groups. This is how
# `get_byte` returns a raw byte of a multibyte character.
#
# A scan gives the compiled pattern the string in place with the scan
# pointer as the text's start, as strscan.c's onig_match and onig_search
# do, so `\A`, `^` and `\G` all read the pointer as the start;
# `fixed_anchor: true` starts the text at the string's own beginning,
# where `\A` keeps the real beginning.
#
# CRuby keeps all of this in a C struct, so a program sees no instance
# variable on a scanner. The fields are in hidden slots, which leaves
# `instance_variables` for the program's own variables.
class StringScanner
  Error = Class.new(StandardError)
  # The two names that the C extension defines next to its error class.
  Version = "3.1.6"
  Id = "$Id$"

  # strscan.c also names its error class ScanError on Object, unless the
  # program has a ScanError already.
  Object.const_set(:ScanError, Error) unless Object.const_defined?(:ScanError)

  def initialize(string, fixed_anchor: false)
    Primitive.zr_hidden_set(self, :__string__, string.to_str)
    Primitive.zr_hidden_set(self, :__anchor__, fixed_anchor)
    reset
  end

  def self.must_C_version = self

  def string = scanner

  def reset
    Primitive.zr_hidden_set(self, :__pos__, 0)
    Primitive.zr_hidden_set(self, :__prev__, 0)
    clear_match
    self
  end

  def terminate
    Primitive.zr_hidden_set(self, :__pos__, string.bytesize)
    clear_match
    self
  end

  def string=(text)
    Primitive.zr_hidden_set(self, :__string__, text.to_str)
    reset
    string
  end

  # strscan_concat: the string itself grows, as rb_str_append grows it.
  def concat(more)
    scanner << Primitive.zr_str_operand(more)
    self
  end

  alias << concat

  def pos
    scanner
    Primitive.zr_hidden_get(self, :__pos__)
  end

  def pos=(byte)
    byte = byte.to_int
    byte += string.bytesize if byte.negative?
    raise RangeError, "index out of range" if byte.negative? || byte > string.bytesize

    Primitive.zr_hidden_set(self, :__pos__, byte)
    byte
  end

  alias pointer pos
  alias pointer= pos=

  def charpos = string.byteslice(0, pos).length

  def eos? = pos >= string.bytesize

  # Past the end of a string that shrank, the rest is empty.
  def rest = eos? ? +"" : string.byteslice(pos, string.bytesize - pos)

  def rest_size = eos? ? 0 : string.bytesize - pos

  def rest? = !eos?

  def beginning_of_line?
    return true if pos.zero?
    return false if pos > string.bytesize

    string.getbyte(pos - 1) == 0x0a
  end

  alias bol? beginning_of_line?

  def size
    return nil unless matched?

    groups ? groups.size : 1
  end

  def scan(pattern) = run(pattern, true, true, true)

  def check(pattern) = run(pattern, true, true, false)

  def skip(pattern) = run(pattern, true, false, true)

  def match?(pattern) = run(pattern, true, false, false)

  def scan_until(pattern) = run(pattern, false, true, true)

  def check_until(pattern) = run(pattern, false, true, false)

  def skip_until(pattern) = run(pattern, false, false, true)

  def exist?(pattern) = run(pattern, false, false, false)

  def scan_full(pattern, advance, answer) = run(pattern, true, answer, advance)

  def search_full(pattern, advance, answer) = run(pattern, false, answer, advance)

  # A number at the scan pointer, as ruby's own strscan.rb writes it.
  def scan_integer(base: 10)
    case base
    when 10 then scan_base10_integer
    when 16 then scan_base16_integer
    else
      raise ArgumentError, "Unsupported integer base: #{base.inspect}, expected 10 or 16"
    end
  end

  def getch
    return nil if eos?

    char = rest[0]
    keep(pos, char.bytesize)
  end

  # The raw byte at the pointer, which is part of a character when the
  # string contains a multibyte one.
  def get_byte
    return nil if eos?

    keep(pos, 1)
  end

  def peek(len)
    len = len.to_int
    raise ArgumentError, "negative string size (or size too big)" if len.negative?

    string.byteslice(pos, len) || ""
  end

  def peek_byte
    string.getbyte(pos)
  end

  # The byte at the scan pointer as an Integer, and the pointer past
  # it; nil at the end. The match is that byte, as get_byte's is.
  def scan_byte
    return nil if eos?

    byte = string.getbyte(pos)
    keep(pos, 1)
    byte
  end

  def unscan
    raise Error, "unscan failed: previous match record not exist" unless matched?

    Primitive.zr_hidden_set(self, :__pos__, Primitive.zr_hidden_get(self, :__prev__))
    clear_match
    self
  end

  def matched?
    scanner
    !Primitive.zr_hidden_get(self, :__from__).nil?
  end

  def matched
    return nil unless matched?

    string.byteslice(match_from, match_len)
  end

  def matched_size = matched? ? match_len : nil

  def pre_match = matched? ? string.byteslice(0, match_from) : nil

  def post_match
    return nil unless matched?

    at = match_from + match_len
    string.byteslice(at, string.bytesize - at)
  end

  # A group by number or by name. A match with no groups of its own —
  # a byte or a character taken alone — has the whole of itself at 0.
  # strscan_aref: a name reads only a Regexp's groups; a number counts
  # from the end where it is negative.
  def [](index)
    return nil unless matched?

    index = group_index(index)
    if index.is_a?(String) || index.is_a?(Symbol)
      raise IndexError, "undefined group name reference: #{index}" unless groups

      return groups[index]
    end

    count = groups ? groups.size : 1
    index += count if index.negative?
    return nil if index.negative? || index >= count

    groups ? groups[index] : matched
  end

  def values_at(*indexes) = matched? ? indexes.map { |i| self[i] } : nil

  def captures
    return nil unless matched?

    groups ? groups.captures : []
  end

  # The names of the last Regexp that a scan tried, matched or not.
  def named_captures
    scanner
    regex = Primitive.zr_hidden_get(self, :__regex__)
    return {} unless regex

    regex.names.to_h { |name| [name, self[name]] }
  end

  # `#<StringScanner 5/11 "test " @ "strin...">`: the position, the five
  # bytes on each side of the pointer, and the rest of the text. A
  # scanner that has taken nothing shows no text, and one at the end
  # says only that.
  def inspect
    return "#<#{self.class} (uninitialized)>" if Primitive.zr_hidden_get(self, :__string__).nil?
    return "#<#{self.class} fin>" if eos?
    return "#<#{self.class} #{pos}/#{string.bytesize} @ #{after}>" if pos.zero?

    "#<#{self.class} #{pos}/#{string.bytesize} #{before} @ #{after}>"
  end

  def fixed_anchor?
    scanner
    Primitive.zr_hidden_get(self, :__anchor__)
  end

  private

  # GET_SCANNER: the string, once initialize gave the scanner one.
  def scanner
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__string__) or raise ArgumentError, "uninitialized StringScanner object"
  end

  # `[+-]?\d+` and `[+-]?(0x)?[0-9a-fA-F]+`, which is what CRuby's own
  # rows scan for the two bases it takes.
  def scan_base10_integer
    ascii_compatible!
    text = scan(/[+-]?\d+/)
    text&.to_i
  end

  def scan_base16_integer
    ascii_compatible!
    text = scan(/[+-]?(?:0x)?[0-9a-fA-F]+/)
    return nil unless text

    sign = text.start_with?("-") ? -1 : 1
    digits = text.start_with?("+", "-") ? text[1..] : text
    digits = digits[2..] if digits.start_with?("0x", "0X")
    sign * digits.to_i(16)
  end

  # strscan_must_ascii_compat.
  def ascii_compatible!
    Primitive.attr! :hidden
    raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{string.encoding}" unless string.encoding.ascii_compatible?
  end

  # A copy scans the same string from the same place.
  def initialize_copy(other)
    %i[__string__ __anchor__ __pos__ __prev__ __from__ __len__ __groups__ __regex__].each do |slot|
      Primitive.zr_hidden_set(self, slot, Primitive.zr_hidden_get(other, slot))
    end
    self
  end

  # Where the last match sits in the string, how long it is, and the
  # MatchData beside it when a pattern made it: CRuby's struct fields.
  def match_from
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__from__)
  end

  def match_len
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__len__)
  end

  def groups
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__groups__)
  end

  def group_index(index)
    Primitive.attr! :hidden
    return index if index.is_a?(Integer) || index.is_a?(String) || index.is_a?(Symbol)
    raise TypeError, "no implicit conversion of #{conversion_name(index)} into Integer" unless index.respond_to?(:to_int)

    index.to_int
  end

  # strscan_do_scan: `pattern` at the scan pointer (`anchored`) or
  # anywhere past it. A Regexp runs in place over the string; a String
  # compares its bytes. The span runs from the pointer to the end of the
  # match, which is what a `_until` form returns. `answer` decides whether
  # the bytes or their count comes back, and `advance` whether the
  # pointer moves past them.
  def run(pattern, anchored, answer, advance)
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :__regex__, pattern.is_a?(Regexp) ? pattern : nil)
    unless pattern.is_a?(Regexp)
      pattern = String.try_convert(pattern) or raise TypeError, "no implicit conversion of #{conversion_name(pattern)} into String"
    end
    text = string
    clear_match
    return nil if pos > text.bytesize

    was = pos
    if pattern.is_a?(Regexp)
      m = pattern.send(:scan_in, text, fixed_anchor? ? 0 : was, was, !anchored)
      return nil unless m

      from = m.bytebegin(0)
      len = m.byteend(0) - from
    else
      len = pattern.bytesize
      if text.bytesize - was < len
        enc_check(text, pattern)
        return nil
      end
      if anchored
        enc_check(text, pattern)
        return nil unless text.byteslice(was, len).b == pattern.b

        from = was
      else
        Encoding.compatible?(text, pattern) or Encoding.send(:incompatible, text, pattern)
        from = Primitive.zr_str_find_from(text, pattern, was)
        return nil unless from
      end
      m = nil
    end
    Primitive.zr_hidden_set(self, :__from__, from)
    Primitive.zr_hidden_set(self, :__len__, len)
    Primitive.zr_hidden_set(self, :__groups__, m)
    Primitive.zr_hidden_set(self, :__prev__, was)
    span = from + len - was
    Primitive.zr_hidden_set(self, :__pos__, from + len) if advance
    answer ? text.byteslice(was, span) : span
  end

  # strscan_enc_check: two Strings of different encodings must be able
  # to meet.
  def enc_check(text, pattern)
    Primitive.attr! :hidden
    return if text.encoding == pattern.encoding

    Encoding.compatible?(text, pattern) or Encoding.send(:incompatible, text, pattern)
  end

  # A byte or a character taken on its own: a match of its own bytes,
  # with no groups behind it.
  def keep(at, len)
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :__regex__, nil)
    Primitive.zr_hidden_set(self, :__prev__, pos)
    Primitive.zr_hidden_set(self, :__from__, at)
    Primitive.zr_hidden_set(self, :__len__, len)
    Primitive.zr_hidden_set(self, :__groups__, nil)
    Primitive.zr_hidden_set(self, :__pos__, at + len)
    string.byteslice(at, len)
  end

  def clear_match
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :__from__, nil)
    Primitive.zr_hidden_set(self, :__len__, 0)
    Primitive.zr_hidden_set(self, :__groups__, nil)
    nil
  end

  # inspect1 and inspect2: the five bytes on each side of the pointer,
  # with the dots that show that there is more, dumped as bytes.
  def before
    Primitive.attr! :hidden
    text = pos > 5 ? "...".b + string.byteslice(pos - 5, 5).b : string.byteslice(0, pos).b
    text.dump
  end

  def after
    Primitive.attr! :hidden
    text = rest_size > 5 ? string.byteslice(pos, 5).b + "..." : rest.b
    text.dump
  end
end
