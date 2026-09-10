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

  COMPOUND = { "c" => "%a %b %e %H:%M:%S %Y", "D" => "%m/%d/%y", "x" => "%m/%d/%y",
               "F" => "%Y-%m-%d", "T" => "%H:%M:%S", "X" => "%H:%M:%S", "R" => "%H:%M",
               "r" => "%I:%M:%S %p", "v" => "%e-%^b-%4Y", "+" => "%a %b %e %H:%M:%S %Z %Y" }.freeze
  private_constant :COMPOUND

  # A directive's value, its default width and how it pads.
  PADDING = { zero: "0", space: " ", none: "" }.freeze
  private_constant :PADDING

  def strftime(format = "%F")
    out = +""
    scanner = 0
    while (at = format.index("%", scanner))
      out << format[scanner...at]
      scanner = expand(format, at, out)
    end
    out << format[scanner..]
    out
  end

  def to_s = strftime("%Y-%m-%d")

  def inspect = "#<#{self.class}: #{self} ((#{@jd}j,#{@df}s,#{@sf}n),#{format('%+d', @of)}s,#{start_text}j)>"

  def ctime = strftime("%a %b %e %H:%M:%S %Y")

  alias asctime ctime

  def iso8601 = strftime("%Y-%m-%d")

  alias xmlschema iso8601

  def rfc3339 = strftime("%Y-%m-%dT%H:%M:%S%:z")

  def rfc2822 = strftime("%a, %-d %b %Y %H:%M:%S %z")

  alias rfc822 rfc2822

  def httpdate = new_offset(0).strftime("%a, %d %b %Y %H:%M:%S GMT")

  def jisx0301 = jisx0301_date

  private

  def start_text
    return @sg.to_s if @sg.is_a?(Integer)

    @sg.infinite? ? (@sg.positive? ? "Inf" : "-Inf") : @sg.to_i.to_s
  end

  def jisx0301_date
    y, m, d = year, mon, mday
    era = ERAS.find { |ey, em, ed, _, _| ([y, m, d] <=> [ey, em, ed]) >= 0 }
    return strftime("%Y-%m-%d") unless era

    format("%s%02d.%02d.%02d", era[3], y - era[4], m, d)
  end

  # A fraction of a second as `digits` digits, which a caller may ask
  # any width of.
  def fraction(digits)
    text = format("%09d", @sf)
    digits <= 9 ? text[0, digits] : text + ("0" * (digits - 9))
  end

  def seconds = ((@jd - EPOCH_JD) * 86_400) + @df

  # The offset as text, with `colons` separators.
  def offset_text(colons)
    of = @of
    sign = of.negative? ? "-" : "+"
    of = of.abs
    h, m, s = of / 3600, (of % 3600) / 60, of % 60
    case colons
    when 0 then format("%s%02d%02d", sign, h, m)
    when 1 then format("%s%02d:%02d", sign, h, m)
    when 2 then format("%s%02d:%02d:%02d", sign, h, m, s)
    else
      return format("%s%02d", sign, h) if m.zero? && s.zero?
      return format("%s%02d:%02d", sign, h, m) if s.zero?

      format("%s%02d:%02d:%02d", sign, h, m, s)
    end
  end

  # One directive, `start` at its `%`. Answers where the scan goes on;
  # text that names no directive is copied as it stands.
  def expand(format, start, out)
    at = start + 1
    padding = nil
    upcase = false
    swapcase = false
    while (flag = format[at])
      case flag
      when "-" then padding = :none
      when "_" then padding = :space
      when "0" then padding = :zero
      when "^" then upcase = true
      when "#" then swapcase = true
      else break
      end
      at += 1
    end
    width = nil
    while format[at]&.match?(/\d/)
      width = ((width || 0) * 10) + format[at].to_i
      at += 1
    end
    at += 1 if modifier?(format, at)
    colons = 0
    while format[at] == ":"
      colons += 1
      at += 1
    end
    letter = format[at]
    text = letter && directive(letter, colons, width, padding)
    if text.nil?
      out << format[start..at]
      return at + 1
    end
    text = text.upcase if upcase
    text = text.match?(/[a-z]/) ? text.upcase : text.downcase if swapcase
    out << text
    at + 1
  end

  # "%E" and "%O" stand before a few letters only; before any other one
  # the whole directive is text.
  def modifier?(format, at)
    case format[at]
    when "E" then "cCxXyY".include?(format[at + 1].to_s)
    when "O" then "deHImMSuUVwWy".include?(format[at + 1].to_s)
    else false
    end
  end

  # A directive's text, or nil when nothing here names one.
  def directive(letter, colons, width, padding)
    return strftime(COMPOUND.fetch(letter)) if COMPOUND.key?(letter)

    case letter
    when "%" then "%"
    when "n" then "\n"
    when "t" then "\t"
    when "z" then offset_text(colons)
    when "Z" then zone
    when "A" then DAYNAMES[wday]
    when "a" then ABBR_DAYNAMES[wday]
    when "B" then MONTHNAMES[mon]
    when "b", "h" then ABBR_MONTHNAMES[mon]
    when "P" then hour < 12 ? "am" : "pm"
    when "p" then hour < 12 ? "AM" : "PM"
    when "L" then fraction(width || 3)
    when "N" then fraction(width || 9)
    else numeric(letter, width, padding)
    end
  end

  # The numeric directives, each with the width and padding it defaults
  # to when the format names none.
  def numeric(letter, width, padding)
    value, size, fill = case letter
                        when "Y" then [year, 4, :precision]
                        when "C" then [year / 100, 2, :zero]
                        when "y" then [year % 100, 2, :zero]
                        when "m" then [mon, 2, :zero]
                        when "d" then [mday, 2, :zero]
                        when "e" then [mday, 2, :space]
                        when "j" then [yday, 3, :zero]
                        when "H" then [hour, 2, :zero]
                        when "k" then [hour, 2, :space]
                        when "I" then [((hour + 11) % 12) + 1, 2, :zero]
                        when "l" then [((hour + 11) % 12) + 1, 2, :space]
                        when "M" then [min, 2, :zero]
                        when "S" then [sec, 2, :zero]
                        when "G" then [cwyear, 4, :precision]
                        when "g" then [cwyear % 100, 2, :zero]
                        when "V" then [cweek, 2, :zero]
                        when "U" then [(yday - 1 + 7 - wday) / 7, 2, :zero]
                        when "W" then [(yday - 1 + 7 - (wday.zero? ? 6 : wday - 1)) / 7, 2, :zero]
                        when "u" then [cwday, 1, :zero]
                        when "w" then [wday, 1, :zero]
                        when "s" then [seconds, 1, :zero]
                        when "Q" then [(seconds * 1000) + (@sf / 1_000_000), 1, :zero]
                        else return nil
                        end
    padded(value, width || size, padding || fill)
  end

  def padded(value, width, how)
    return value.to_s if how == :none
    return format("%.#{width}d", value) if how == :precision

    format("%#{how == :space ? '' : '0'}#{width}d", value)
  end
end

class DateTime < Date
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
