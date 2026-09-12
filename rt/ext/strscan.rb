# frozen_string_literal: true

# StringScanner: a position in a string and a match at it. Ruby ships
# this as a C extension with a small half in ruby; this is both halves
# over the same Regexp engine the runtime already carries.
#
# `pos` counts bytes, as ruby's does. A match is a byte range in the
# string, and the MatchData beside it when a pattern made it: a byte or a
# character taken on its own has a range and no groups, which is how
# `get_byte` answers a raw byte of a multibyte character.
#
# A scan matches the rest of the string from `pos`, so `\A`, `^` and `\G`
# all read the scan pointer as the start; `fixed_anchor: true` matches
# against the whole string at the pointer instead, where `\A` keeps the
# real beginning.
#
# CRuby keeps all of this in a C struct, so a program sees no instance
# variable on a scanner: the fields live in hidden slots, which leaves
# `instance_variables` for whatever the program itself writes.
class StringScanner
  Error = Class.new(StandardError)
  # The two names the C extension carries beside its error class.
  Version = "3.1.6"
  Id = "$Id$"

  def initialize(string, fixed_anchor: false)
    Primitive.zr_hidden_set(self, :__string__, string.to_str)
    Primitive.zr_hidden_set(self, :__anchor__, fixed_anchor)
    reset
  end

  def string = Primitive.zr_hidden_get(self, :__string__)

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

  alias clear terminate

  def string=(text)
    Primitive.zr_hidden_set(self, :__string__, text.to_str)
    reset
    string
  end

  def concat(more)
    Primitive.zr_hidden_set(self, :__string__, string + more.to_str)
    self
  end

  alias << concat

  def pos = Primitive.zr_hidden_get(self, :__pos__)

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

  def rest = string.byteslice(pos, string.bytesize - pos)

  def rest_size = string.bytesize - pos

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

  # The raw byte at the pointer, which is half a character where the
  # string holds a multibyte one.
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

  def matched? = !Primitive.zr_hidden_get(self, :__from__).nil?

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
  def [](index)
    return nil unless matched?
    return groups[group_index(index)] if groups

    group_index(index) == 0 ? matched : nil
  end

  def values_at(*indexes) = matched? ? indexes.map { |i| self[i] } : nil

  def captures
    return nil unless matched?

    groups ? groups.captures : []
  end

  def named_captures = groups ? groups.named_captures : {}

  # `#<StringScanner 5/11 "test " @ "strin...">`: the place, the text the
  # last scan took, and what waits. A scanner that has taken nothing
  # names no text, and one at the end says so alone.
  def inspect
    return "#<StringScanner fin>" if eos?
    return "#<StringScanner #{pos}/#{string.bytesize} @ #{after}>" if pos.zero?

    "#<StringScanner #{pos}/#{string.bytesize} #{before} @ #{after}>"
  end

  def fixed_anchor? = Primitive.zr_hidden_get(self, :__anchor__)

  private

  # `[+-]?\d+` and `[+-]?(0x)?[0-9a-fA-F]+`, which is what CRuby's own
  # rows scan for the two bases it takes.
  def scan_base10_integer
    text = scan(/[+-]?\d+/)
    text&.to_i
  end

  def scan_base16_integer
    text = scan(/[+-]?(?:0x)?[0-9a-fA-F]+/)
    return nil unless text

    sign = text.start_with?("-") ? -1 : 1
    digits = text.start_with?("+", "-") ? text[1..] : text
    digits = digits[2..] if digits.start_with?("0x", "0X")
    sign * digits.to_i(16)
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
    raise TypeError, "no implicit conversion of #{index.class} into Integer" unless index.respond_to?(:to_int)

    index.to_int
  end

  # `pattern` at the scan pointer (`anchored`) or anywhere past it. The
  # span runs from the pointer to the end of the match, which is what a
  # `_until` form answers; `answer` decides whether the bytes or their
  # count comes back, and `advance` whether the pointer moves past them.
  def run(pattern, anchored, answer, advance)
    if fixed_anchor?
      # The whole string is the subject, so `\A` means its real start and
      # `\G` holds the match at the pointer.
      m = matcher(pattern, anchored, "\\G").match(string, char_index(string, pos))
      base = 0
    else
      m = matcher(pattern, anchored, "\\A").match(rest, 0)
      base = pos
    end
    return clear_match unless m

    was = pos
    from = base + m.bytebegin(0)
    Primitive.zr_hidden_set(self, :__from__, from)
    Primitive.zr_hidden_set(self, :__len__, m.byteend(0) - m.bytebegin(0))
    Primitive.zr_hidden_set(self, :__groups__, m)
    Primitive.zr_hidden_set(self, :__prev__, was)
    span = from + match_len - was
    Primitive.zr_hidden_set(self, :__pos__, from + match_len) if advance
    answer ? string.byteslice(was, span) : span
  end

  def matcher(pattern, anchored, anchor)
    source = pattern.is_a?(Regexp) ? pattern.source : Regexp.escape(pattern)
    return Regexp.new("#{anchor}(?:#{source})", pattern.is_a?(Regexp) ? pattern.options : 0) if anchored
    return pattern if pattern.is_a?(Regexp)

    Regexp.new(source)
  end

  def char_index(text, byte) = byte.zero? ? 0 : text.byteslice(0, byte).length

  # A byte or a character taken on its own: a match of its own bytes,
  # with no groups behind it.
  def keep(at, len)
    Primitive.attr! :hidden
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

  # The five characters each side of the pointer, with the dots that
  # say more stands there, as ruby shows them.
  def before
    Primitive.attr! :hidden
    text = string.byteslice(0, pos)
    "#{"..." if text.length > 5}#{text[-5..] || text}".inspect
  end

  def after
    Primitive.attr! :hidden
    text = rest
    "#{text[0, 5]}#{"..." if text.length > 5}".inspect
  end
end
