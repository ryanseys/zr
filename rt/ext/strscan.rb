# frozen_string_literal: true

# StringScanner: a position in a string and a match at it. Ruby ships
# this as a C extension; this is its half in ruby, over the same Regexp
# engine the runtime already carries.
#
# `pos` counts bytes, as ruby's does. A scan matches the rest of the
# string from `pos`, so `\A`, `^` and `\G` all read the scan pointer as
# the start; `fixed_anchor: true` keeps `\A` on the real start instead.
class StringScanner
  Error = Class.new(StandardError)
  ScanError = Class.new(Error)

  attr_reader :string

  def initialize(string, fixed_anchor: false)
    @string = string.to_str
    @fixed_anchor = fixed_anchor
    reset
  end

  def reset
    @pos = 0
    @match = nil
    @match_at = 0
    @prev = 0
    self
  end

  def terminate
    @pos = @string.bytesize
    clear_match
    self
  end

  alias clear terminate

  def string=(string)
    @string = string.to_str
    reset
    @string
  end

  def concat(more)
    @string = @string + more.to_str
    self
  end

  alias << concat

  attr_reader :pos

  def pos=(byte)
    byte = byte.to_int
    byte += @string.bytesize if byte.negative?
    raise RangeError, "index out of range" if byte.negative? || byte > @string.bytesize

    @pos = byte
  end

  alias pointer pos
  alias pointer= pos=

  def charpos = @string.byteslice(0, @pos).length

  def eos? = @pos >= @string.bytesize

  def rest = @string.byteslice(@pos, @string.bytesize - @pos)

  def rest_size = @string.bytesize - @pos

  def rest? = !eos?

  def beginning_of_line?
    return true if @pos.zero?
    return false if @pos > @string.bytesize

    @string.getbyte(@pos - 1) == 0x0a
  end

  alias bol? beginning_of_line?

  def size = @match&.size

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

  def getch
    return nil if eos?

    char = rest[0]
    keep(char, @pos, char.bytesize)
  end

  def get_byte
    return nil if eos?

    keep(@string.byteslice(@pos, 1), @pos, 1)
  end

  def peek(len)
    len = len.to_int
    raise ArgumentError, "negative string size (or size too big)" if len.negative?

    @string.byteslice(@pos, len) || ""
  end

  def peek_byte
    @string.getbyte(@pos)
  end

  def unscan
    raise ScanError, "unscan failed: previous match record not exist" unless @match

    @pos = @prev
    clear_match
    self
  end

  def matched? = !@match.nil?

  def matched = @match && @match[0]

  def matched_size = @match && @match[0].bytesize

  def pre_match = @match && @string.byteslice(0, @match_at + @match.bytebegin(0))

  def post_match
    return nil unless @match

    at = @match_at + @match.byteend(0)
    @string.byteslice(at, @string.bytesize - at)
  end

  def [](index) = @match && @match[index]

  def values_at(*indexes) = @match && indexes.map { |i| @match[i] }

  def captures = @match&.captures

  def named_captures = @match ? @match.named_captures : {}

  def inspect
    return "#<StringScanner fin>" if eos?

    "#<StringScanner #{@pos}/#{@string.bytesize} #{before} @ #{after}>"
  end

  def fixed_anchor? = @fixed_anchor

  private

  # `pattern` at the scan pointer (`anchored`) or anywhere past it. The
  # span runs from the pointer to the end of the match, which is what a
  # `_until` form answers; `answer` decides whether the bytes or their
  # count comes back, and `advance` whether the pointer moves past them.
  def run(pattern, anchored, answer, advance)
    at = @fixed_anchor ? 0 : @pos
    text = @fixed_anchor ? @string : rest
    m = matcher(pattern, anchored).match(text, @fixed_anchor ? char_index(text, @pos) : 0)
    return clear_match unless m

    was = @pos
    @match = m
    @match_at = at
    @prev = was
    span = at + m.byteend(0) - was
    @pos = was + span if advance
    answer ? @string.byteslice(was, span) : span
  end

  def matcher(pattern, anchored)
    return Regexp.new("\\A(?:#{pattern.is_a?(Regexp) ? pattern.source : Regexp.escape(pattern)})", pattern.is_a?(Regexp) ? pattern.options : 0) if anchored
    return pattern if pattern.is_a?(Regexp)

    Regexp.new(Regexp.escape(pattern))
  end

  def char_index(text, byte) = byte.zero? ? 0 : text.byteslice(0, byte).length

  def keep(text, at, len)
    @prev = @pos
    @match = /\A(?:#{Regexp.escape(text)})/m.match(@string.byteslice(at, len))
    @match_at = at
    @pos = at + len
    text
  end

  def clear_match
    @match = nil
    nil
  end

  # The five characters each side of the pointer, with the dots that
  # say more stands there, as ruby shows them.
  def before
    text = @string.byteslice(0, @pos)
    "#{"..." if text.length > 5}#{text[-5..] || text}".inspect
  end

  def after
    text = rest
    "#{text[0, 5]}#{"..." if text.length > 5}".inspect
  end
end
