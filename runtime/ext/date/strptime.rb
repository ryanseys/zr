# frozen_string_literal: true

# Date._strptime: the format walks the text, and each directive takes
# from it what it names. Anything the format does not name is left over.

class Date
  STRPTIME_ZONE_RE = /\A((?:gmt|utc?)?[-+]\d+(?:[,.:]\d+(?::\d+)?)?|(?-i:[[:alpha:].\s]+)(?:standard|daylight)\s+time\b|(?-i:[[:alpha:]]+)(?:\s+dst)?\b)/i
  NUMERIC_DIRECTIVES = "CDdeFGgHIjkLlMmNQRrSsTUuVvWwXxYy"
  COMPOUND_DIRECTIVES = { "c" => "%a %b %e %H:%M:%S %Y", "D" => "%m/%d/%y", "x" => "%m/%d/%y",
                          "F" => "%Y-%m-%d", "n" => " ", "t" => " ", "R" => "%H:%M",
                          "r" => "%I:%M:%S %p", "T" => "%H:%M:%S", "X" => "%H:%M:%S",
                          "v" => "%e-%b-%Y", "+" => "%a %b %e %H:%M:%S %Z %Y" }.freeze
  private_constant :STRPTIME_ZONE_RE, :NUMERIC_DIRECTIVES, :COMPOUND_DIRECTIVES

  # One run of a format over a text. The reader keeps its position,
  # so a compound directive continues from where the last one stopped.
  class Reader
    def initialize(text, found)
      @text = text
      @found = found
      @at = 0
      @failed = false
    end

    attr_reader :at

    def failed? = @failed

    def run(format)
      fi = 0
      while fi < format.length
        if format[fi].match?(/\s/)
          @at += 1 while @text[@at]&.match?(/\s/)
          fi += 1 while fi < format.length && format[fi].match?(/\s/)
          next
        end
        return refuse if @at >= @text.length

        fi = format[fi] == "%" ? directive(format, fi) : literal(format, fi)
        return if @failed
      end
    end

    private

    def refuse
      @failed = true
      nil
    end

    def literal(format, fi)
      return refuse if @text[@at] != format[fi]

      @at += 1
      fi + 1
    end

    # The directive at `fi`, which starts with a `%`. Returns the position
    # where the format continues.
    def directive(format, fi)
      start = fi
      fi += 1
      fi += 1 while modifier?(format, fi)
      letter = format[fi]
      return literal(format, start) if letter.nil?
      return unknown(format, start, fi) unless take(letter, format, fi)

      fi + 1
    end

    # "%E" and "%O" come before only a few letters, and "%:z" has up
    # to three colons; anything else leaves the "%" as it is.
    def modifier?(format, fi)
      case format[fi]
      when "E" then "cCxXyY".include?(format[fi + 1].to_s)
      when "O" then "deHImMSuUVwWy".include?(format[fi + 1].to_s)
      when ":" then format[fi..(fi + 2)].to_s.match?(/\A:{0,2}z/)
      else false
      end
    end

    # A directive with no meaning wants its own text, "%" and all.
    def unknown(format, start, fi)
      return refuse if @text[@at] != "%"

      @at += 1
      return refuse if @text[@at] != format[fi]

      @at += 1
      fi + 1
    end

    def take(letter, format, fi)
      return run_compound(COMPOUND_DIRECTIVES.fetch(letter)) if COMPOUND_DIRECTIVES.key?(letter)

      case letter
      when "A", "a" then name_of(DAYNAMES) { |i| @found[:wday] = i }
      when "B", "b", "h" then name_of(MONTHNAMES.drop(1)) { |i| @found[:mon] = i + 1 }
      when "C" then set(:_cent, wide(format, fi, 2))
      when "d", "e" then ranged(:mday, spaced(2), 1, 31)
      when "G" then set(:cwyear, wide(format, fi, 4))
      when "g" then two_digit_year(:cwyear)
      when "H", "k" then ranged(:hour, spaced(2), 0, 24)
      when "I", "l" then ranged(:hour, spaced(2), 1, 12)
      when "j" then ranged(:yday, digits(3), 1, 366)
      when "L", "N" then fraction(format, fi, letter == "L" ? 3 : 9)
      when "M" then ranged(:min, digits(2), 0, 59)
      when "m" then ranged(:mon, digits(2), 1, 12)
      when "P", "p" then meridian
      when "Q" then seconds_since_epoch(1000)
      when "S" then ranged(:sec, digits(2), 0, 60)
      when "s" then seconds_since_epoch(1)
      when "U", "W" then ranged(letter == "U" ? :wnum0 : :wnum1, digits(2), 0, 53)
      when "u" then ranged(:cwday, digits(1), 1, 7)
      when "V" then ranged(:cweek, digits(2), 1, 53)
      when "w" then ranged(:wday, digits(1), 0, 6)
      when "Y" then signed_year(format, fi)
      when "y" then two_digit_year(:year)
      when "Z", "z" then zone
      when "%" then percent
      end
    end

    def run_compound(format)
      run(format)
      !@failed
    end

    def set(key, value)
      return false if value.nil?

      @found[key] = value
      true
    end

    def ranged(key, value, low, high)
      return false if value.nil? || !(low..high).cover?(value)

      @found[key] = value
      true
    end

    # A width of two, unless a space is in place of the leading digit.
    def spaced(width)
      return digits(width) unless @text[@at] == " "

      @at += 1
      digits(1)
    end

    def digits(width)
      length = 0
      length += 1 while length < width && @text[@at + length]&.match?(/[0-9]/)
      return nil if length.zero?

      value = @text[@at, length].to_i
      @at += length
      value
    end

    # A directive next to another number reads a fixed width; alone it
    # reads every digit it can.
    def wide(format, fi, width) = digits(number_next?(format, fi) ? width : @text.length)

    def number_next?(format, fi)
      rest = format[(fi + 1)..].to_s
      return true if rest[0]&.match?(/[0-9]/)
      return false unless rest[0] == "%"

      at = "EO".include?(rest[1].to_s) ? 2 : 1
      letter = rest[at]
      !letter.nil? && (NUMERIC_DIRECTIVES.include?(letter) || letter.match?(/[0-9]/))
    end

    def name_of(names)
      names.each_with_index do |name, index|
        length = [name.length, 3].find { |l| @text[@at, l]&.casecmp?(name[0, l]) } or next

        @at += length
        yield(index)
        return true
      end
      false
    end

    def signed_year(format, fi)
      sign = sign_ahead
      value = wide(format, fi, 4)
      return false if value.nil?

      @found[:year] = sign * value
      true
    end

    def two_digit_year(key)
      value = digits(2)
      return false if value.nil? || !(0..99).cover?(value)

      @found[key] = value
      @found[:_cent] = value >= 69 ? 19 : 20 unless @found.key?(:_cent)
      true
    end

    def fraction(format, fi, width)
      sign = sign_ahead
      start = @at
      value = wide(format, fi, width)
      return false if value.nil?

      @found[:sec_fraction] = Rational(sign * value, 10**(@at - start))
      true
    end

    def seconds_since_epoch(divisor)
      sign = @text[@at] == "-" ? -1 : 1
      @at += 1 if sign.negative?
      value = digits(@text.length)
      return false if value.nil?

      @found[:seconds] = divisor == 1 ? sign * value : Rational(sign * value, divisor)
      true
    end

    def sign_ahead
      return 1 unless "+-".include?(@text[@at].to_s)

      sign = @text[@at] == "-" ? -1 : 1
      @at += 1
      sign
    end

    # "am", "AM", "a.m." and the rest, which set the half of the day.
    def meridian
      return false if @text.length - @at < 2

      letter = @text[@at]
      half = "Pp".include?(letter) ? 12 : 0
      return false if half.zero? && !"Aa".include?(letter)

      letter = @text[@at + 1]
      if letter == "."
        return false if @text.length - @at < 4 || @text[@at + 3] != "."

        @at += 2
        letter = @text[@at]
      end
      return false unless "Mm".include?(letter.to_s)

      @at += 2
      @found[:_merid] = half
      true
    end

    def zone
      m = STRPTIME_ZONE_RE.match(@text[@at..]) or return false

      @found[:zone] = m[1]
      @found[:offset] = Date.send(:zone_to_diff, m[1])
      @at += m.end(0)
      true
    end

    def percent
      return false if @text[@at] != "%"

      @at += 1
      true
    end
  end
  private_constant :Reader

  class << self
    # Every element the format names, plus what was left over, or nil
    # when the text does not fit the format.
    def _strptime(text, format = "%F")
      found = {}
      text = text_of(text)
      reader = Reader.new(text, found)
      reader.run(text_of(format))
      found[:leftover] = text[reader.at..] if reader.at < text.length
      return nil if reader.failed?

      complete_century_frag(found)
      complete_meridian(found)
      found
    end

    private

    def complete_century_frag(found)
      cent = found.delete(:_cent) or return

      found[:cwyear] += cent * 100 if found[:cwyear]
      found[:year] += cent * 100 if found[:year]
    end

    def complete_meridian(found)
      half = found.delete(:_merid) or return

      found[:hour] = (found[:hour] % 12) + half if found[:hour]
    end
  end
end
