# frozen_string_literal: true

# strftime and the fixed-shape readers and writers: ISO 8601, RFC 3339,
# RFC 2822, HTTP dates and JIS X 0301.

class Date
  EPOCH_JD = 2_440_588
  private_constant :EPOCH_JD

  # The Japanese eras a JIS X 0301 date names, newest first.
  ERAS = [[2019, 5, 1, "R", 2018], [1989, 1, 8, "H", 1988], [1926, 12, 25, "S", 1925],
          [1912, 7, 30, "T", 1911], [1873, 1, 1, "M", 1867]].freeze
  private_constant :ERAS

  # The directives that stand for a format of others.
  COMPOUNDS = { "c" => "%a %b %e %H:%M:%S %Y", "D" => "%m/%d/%y", "x" => "%m/%d/%y", "F" => "%Y-%m-%d",
                "T" => "%H:%M:%S", "X" => "%H:%M:%S", "R" => "%H:%M", "r" => "%I:%M:%S %p", "v" => "%e-%^b-%Y",
                "+" => "%a %b %e %H:%M:%S %Z %Y" }.freeze
  INT_MAX = 0x7fff_ffff
  private_constant :COMPOUNDS, :INT_MAX

  # date_strftime_internal: the format's directives rendered in its
  # encoding. A NUL byte ends what the C renderer reads, so each run
  # between NUL bytes renders apart.
  def strftime(format = "%F")
    format = String(format) unless format.is_a?(String)
    raise TypeError, "no implicit conversion of #{format.class} into String" unless format.is_a?(String)
    raise ArgumentError, "format should have ASCII compatible encoding" unless format.encoding.ascii_compatible?

    out = format.b.split(/(\0+)/).sum("".b) { |part| part.start_with?("\0") ? part : rendered(part) }
    out.force_encoding(format.encoding)
  end

  def to_s = strftime("%Y-%m-%d")

  def inspect
    jd, df, sf, of = parts
    "#<#{self.class}: #{self} ((#{jd}j,#{df}s,#{sf}n),#{format('%+d', of)}s,#{start_text}j)>"
  end

  def ctime = strftime("%a %b %e %H:%M:%S %Y")

  alias asctime ctime

  def iso8601 = strftime("%Y-%m-%d")

  alias xmlschema iso8601

  def rfc3339 = strftime("%Y-%m-%dT%H:%M:%S%:z")

  def rfc2822 = strftime("%a, %-d %b %Y %H:%M:%S %z")

  alias rfc822 rfc2822

  def httpdate
    jd, df, sf, _, sg = parts
    self.class.send(:at, jd, df, sf, 0, sg).strftime("%a, %d %b %Y %H:%M:%S GMT")
  end

  def jisx0301 = jisx0301_date

  private

  def start_text
    return reform.to_s if reform.is_a?(Integer)

    reform.infinite? ? (reform.positive? ? "Inf" : "-Inf") : reform.to_i.to_s
  end

  def jisx0301_date
    y, m, d = year, mon, mday
    era = ERAS.find { |ey, em, ed, _, _| ([y, m, d] <=> [ey, em, ed]) >= 0 }
    return strftime("%Y-%m-%d") unless era

    format("%s%02d.%02d.%02d", era[3], y - era[4], m, d)
  end

  def seconds
    jd, df = parts
    ((jd - EPOCH_JD) * 86_400) + df
  end

  # date_strftime_with_tmx: the bytes of `format` with each directive
  # rendered.
  def rendered(format)
    out = "".b
    at = 0
    while at < format.bytesize
      percent = format.byteindex("%", at) || format.bytesize
      out << format.byteslice(at, percent - at)
      break if percent == format.bytesize

      at = directive(format, percent, out)
    end
    out
  end

  # One directive, from the `%` at `from`: flags, a width, a locale
  # modifier and colons, each only where date_strftime.c accepts it,
  # then the conversion. Returns the position where the format continues.
  # Text that is not a directive, including a directive cut short by the
  # end, is copied as it is written.
  def directive(format, from, out)
    width = -1
    padding = nil
    left = upper = swap = modified = false
    colons = 0
    at = from
    loop do
      at += 1
      c = format.byteslice(at)
      case c
      when nil then return verbatim(format, from, at - 1, out)
      when "-", "^", "#", "_", "0"
        return verbatim(format, from, at, out) if width > 0 || modified || colons > 0

        case c
        when "-" then left = true
        when "^" then upper = true
        when "#" then swap = true
        when "_" then padding = " "
        else
          padding = "0"
          width, at = width_at(format, at)
        end
      when "1".."9" then width, at = width_at(format, at)
      when "E", "O"
        modified = true
        after = format.byteslice(at + 1)
        return verbatim(format, from, at, out) unless after && (c == "E" ? "cCxXyY" : "deHkIlmMSuUVwWy").include?(after)
      when ":"
        run = format.byteslice(at, format.bytesize - at)[/\A:+/].bytesize
        return verbatim(format, from, at, out) unless format.byteslice(at + run) == "z"

        colons = run
        at += run - 1
      else break
      end
    end
    c = format.byteslice(at)
    case c
    when "%" then put_word(out, "%", width, padding, left)
    when "n" then put_word(out, "\n", width, padding, left)
    when "t" then put_word(out, "\t", width, padding, left)
    when "a" then put_word(out, ABBR_DAYNAMES[wday], width, padding, left, (:up if upper || swap))
    when "A" then put_word(out, DAYNAMES[wday], width, padding, left, (:up if upper || swap))
    when "b", "h" then put_word(out, ABBR_MONTHNAMES[mon], width, padding, left, (:up if upper || swap))
    when "B" then put_word(out, MONTHNAMES[mon], width, padding, left, (:up if upper || swap))
    when "p" then put_word(out, clock[0] < 12 ? "AM" : "PM", width, padding, left, swap ? :down : (:up if upper))
    when "P" then put_word(out, clock[0] < 12 ? "AM" : "PM", width, padding, left, upper ? :up : (:down unless swap))
    when "Z" then put_word(out, Date.send(:offset_string, offset_seconds), width, padding, left, swap ? :down : (:up if upper))
    when "C" then put_number(out, year.div(100), "0", 2, width, padding, left)
    when "d" then put_number(out, mday, "0", 2, width, padding, left)
    when "e" then put_number(out, mday, " ", 2, width, padding, left)
    when "Y" then put_number(out, year, "0", year.negative? && Primitive.zr_fixnum_p_m(year) ? 5 : 4, width, padding, left)
    when "G" then put_number(out, cwyear, "0", cwyear.negative? && Primitive.zr_fixnum_p_m(cwyear) ? 5 : 4, width, padding, left)
    when "y" then put_number(out, year % 100, "0", 2, width, padding, left)
    when "g" then put_number(out, cwyear % 100, "0", 2, width, padding, left)
    when "H" then put_number(out, clock[0], "0", 2, width, padding, left)
    when "k" then put_number(out, clock[0], " ", 2, width, padding, left)
    when "I" then put_number(out, (clock[0] + 11) % 12 + 1, "0", 2, width, padding, left)
    when "l" then put_number(out, (clock[0] + 11) % 12 + 1, " ", 2, width, padding, left)
    when "j" then put_number(out, yday, "0", 3, width, padding, left)
    when "M" then put_number(out, clock[1], "0", 2, width, padding, left)
    when "m" then put_number(out, mon, "0", 2, width, padding, left)
    when "S" then put_number(out, clock[2], "0", 2, width, padding, left)
    when "s" then put_number(out, seconds, "0", 1, width, padding, left)
    when "Q" then put_number(out, (seconds * 1000) + (parts[2] / 1_000_000), "0", 1, width, padding, left)
    when "U" then put_number(out, (yday - 1 + 7 - wday) / 7, "0", 2, width, padding, left)
    when "W" then put_number(out, (yday - 1 + 7 - (wday + 6) % 7) / 7, "0", 2, width, padding, left)
    when "u" then put_number(out, cwday, "0", 1, width, padding, left)
    when "V" then put_number(out, cweek, "0", 2, width, padding, left)
    when "w" then put_number(out, wday, "0", 1, width, padding, left)
    when "L", "N"
      width = c == "L" ? 3 : 9 if width <= 0
      out << (parts[2] * 10**width).div(NANOSECOND).to_s.rjust(width, "0")
    when "z"
      return verbatim(format, from, at - 1, out) if colons > 3

      put_offset(out, colons, width, padding, left)
    else
      return verbatim(format, from, at, out) unless COMPOUNDS.key?(c)

      put_compound(out, COMPOUNDS.fetch(c), width, padding, left, upper)
    end
    at + 1
  end

  # What names no directive, from its `%` through `to`, as it is
  # written.
  def verbatim(format, from, to, out)
    out << format.byteslice(from, to - from + 1)
    to + 1
  end

  # A width, from its first digit at `at`, and where its digits end. A
  # width the C renderer has no room for is a range error.
  def width_at(format, at)
    digits = format.byteslice(at, format.bytesize - at)[/\A\d+/]
    raise Errno::ERANGE, format if digits.to_i > INT_MAX

    [digits.to_i, at + digits.bytesize - 1]
  end

  # FILL_PADDING and the case change: a word right-aligned in `width`,
  # unless `-` leaves it bare.
  def put_word(out, word, width, padding, left, casing = nil)
    return if word.empty?

    out << (padding || " ") * (width - word.bytesize) if !left && width > word.bytesize
    out << case casing
           when :up then word.upcase
           when :down then word.downcase
           else word
           end
  end

  # FMT and FMTV: a number right-aligned in `width`, or in the
  # directive's own `least`, with its own `pad` unless a flag names
  # another, as sprintf pads it; `-` leaves it bare.
  def put_number(out, value, pad, least, width, padding, left)
    width = least if width <= 0
    width = 1 if left
    out << ((padding || pad) == "0" ? format("%0*d", width, value) : format("%*d", width, value))
  end

  # STRFTIME: a directive that represents a format of other directives,
  # upcased by `^` and right-aligned in `width` unless `-` leaves it bare.
  def put_compound(out, format, width, padding, left, upper)
    text = rendered(format)
    text.upcase! if upper
    out << (padding || " ") * (width - text.bytesize) if !left && width > text.bytesize
    out << text
  end

  # `%z`: the offset as hours and minutes, `:` between them and then the
  # seconds for each colon, or as few parts as lose nothing for three.
  # The width counts past the sign and the minutes; `-` lets an hour
  # under ten stand as one digit, and `_` pads before the sign.
  def put_offset(out, colons, width, padding, left)
    off = offset_seconds
    aoff = off.abs
    short = aoff / 3600 < 10 ? 1 : 2
    hours = left && short == 1 ? 1 : 2
    tail = case colons
           when 0 then 3
           when 1 then 4
           when 2 then 7
           else aoff % 3600 == 0 ? 1 : aoff % 60 == 0 ? 4 : 7
           end
    width = width <= tail + hours ? hours : width - tail
    if padding == " " && width > short
      out << " " * (width - short)
      width = short
    end
    out << (off.negative? ? "-" : "+") << (aoff / 3600).to_s.rjust(width, "0")
    aoff %= 3600
    return if colons == 3 && aoff.zero?

    out << ":" if colons >= 1
    out << format("%02d", aoff / 60)
    aoff %= 60
    return if colons == 3 && aoff.zero?

    out << ":" << format("%02d", aoff) if colons >= 2
  end
end

class DateTime < Date
  def strftime(format = "%FT%T%:z") = super

  def to_s = strftime("%Y-%m-%dT%H:%M:%S%:z")

  # ISO 8601, with `digits` of a second when the caller asks for them.
  def iso8601(digits = 0)
    return strftime("%Y-%m-%dT%H:%M:%S%:z") if digits.zero?

    strftime("%Y-%m-%dT%H:%M:%S.%#{digits}N%:z")
  end

  alias xmlschema iso8601

  alias rfc3339 iso8601

  def jisx0301(digits = 0)
    "#{send(:jisx0301_date)}T#{iso8601(digits).split('T').last}"
  end
end
