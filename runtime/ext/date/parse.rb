# frozen_string_literal: true

# Date._parse: ruby own loose reader, ported from date_parse.c. It tries
# one shape after another, blanking what it reads, so the first shape
# that fits wins and later ones see only what is left.

require_relative "zones"

class Date
  ABBR_DAYS = "sun|mon|tue|wed|thu|fri|sat"
  ABBR_MONS = "jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"
  NUMBER = '(?<!\d)\d'
  ERA = '(c(?:e|\.e\.)|b(?:ce|\.c\.e\.)|a(?:d|\.d\.)|b(?:c|\.c\.))'
  private_constant :ABBR_DAYS, :ABBR_MONS, :NUMBER, :ERA

  BLANK_RE = %r{[^-+',./:@[:alnum:]\[\]]+}
  DAY_RE = %r{\b(#{ABBR_DAYS})[^-/\d\s]*}i
  TIME_RE = /
    (
      #{NUMBER}+\s*
      (?:
        (?:
          :\s*\d+(?:\s*:\s*\d+(?:[,.]\d*)?)?
        |
          h(?:\s*\d+m?(?:\s*\d+s?)?)?
        )
        (?:\s*[ap](?:m\b|\.m\.))?
      |
        [ap](?:m\b|\.m\.)
      )
    )
    (?:
      \s*
      (
        (?:gmt|utc?)?[-+]\d+(?:[,.:]\d+(?::\d+)?)?
      |
        (?-i:[[:alpha:].\s]+)(?:standard|daylight)\stime\b
      |
        (?-i:[[:alpha:]]+)(?:\sdst)?\b
      )
    )?
  /ix
  TIME2_RE = /\A(\d+)h?(?:\s*:?\s*(\d+)m?(?:\s*:?\s*(\d+)(?:[,.](\d+))?s?)?)?(?:\s*([ap])(?:m\b|\.m\.))?/i
  EU_RE = /('?#{NUMBER}+)[^-\d\s]*\s*(#{ABBR_MONS})[^-\d\s']*(?:\s*(?:\b#{ERA}(?!(?<!\.)[a-z]))?\s*('?-?\d+(?:(?:st|nd|rd|th)\b)?))?/i
  US_RE = /\b(#{ABBR_MONS})[^-\d\s']*\s*('?\d+)[^-\d\s']*(?:\s*+,?\s*+#{ERA}?\s*('?-?\d+))?/i
  ISO_RE = /('?[-+]?#{NUMBER}+)-(\d+)-('?-?\d+)/
  JIS_RE = /\b([mtshr])(\d+)\.(\d+)\.(\d+)/i
  VMS11_RE = %r{('?-?#{NUMBER}+)-(#{ABBR_MONS})[^-/.]*-('?-?\d+)}i
  VMS12_RE = %r{\b(#{ABBR_MONS})[^-/.]*-('?-?\d+)(?:-('?-?\d+))?}i
  SLA_RE = %r{('?-?#{NUMBER}+)/\s*('?\d+)(?:\D\s*('?-?\d+))?}i
  DOT_RE = /('?-?#{NUMBER}+)\.\s*('?\d+)\.\s*('?-?\d+)/i
  ISO21_RE = /\b(\d{2}|\d{4})?-?w(\d{2})(?:-?(\d))?\b/i
  ISO22_RE = /-w-(\d)\b/i
  ISO23_RE = /--(\d{2})?-(\d{2})\b/
  ISO24_RE = /--(\d{2})(\d{2})?\b/
  ISO25_BAR_RE = /[,.](\d{2}|\d{4})-\d{3}\b/
  ISO25_RE = /\b(\d{2}|\d{4})-(\d{3})\b/
  ISO26_BAR_RE = /\d-\d{3}\b/
  ISO26_RE = /\b-(\d{3})\b/
  YEAR_RE = /'(\d+)\b/
  MON_RE = /\b(#{ABBR_MONS})\S*/i
  MDAY_RE = /(#{NUMBER}+)(st|nd|rd|th)\b/i
  DDD_RE = /([-+]?)(#{NUMBER}{2,14})(?:\s*t?\s*(\d{2,6})?(?:[,.](\d*))?)?(?:\s*(z\b|[-+]\d{1,4}\b|\[[-+]?\d[^\]]*\]))?/i
  BC_RE = /\b(bc\b|bce\b|b\.c\.|b\.c\.e\.)/i
  FRAG_RE = /\A\s*(\d{1,2})\s*\z/i
  private_constant :BLANK_RE, :DAY_RE, :TIME_RE, :TIME2_RE, :EU_RE, :US_RE, :ISO_RE, :JIS_RE,
                   :VMS11_RE, :VMS12_RE, :SLA_RE, :DOT_RE, :ISO21_RE, :ISO22_RE, :ISO23_RE,
                   :ISO24_RE, :ISO25_BAR_RE, :ISO25_RE, :ISO26_BAR_RE, :ISO26_RE, :YEAR_RE,
                   :MON_RE, :MDAY_RE, :DDD_RE, :BC_RE, :FRAG_RE

  GENGO = { "m" => 1867, "t" => 1911, "s" => 1925, "h" => 1988, "r" => 2018 }.freeze
  private_constant :GENGO

  class << self
    # Every element a loose string names, as far as the reader gets.
    def _parse(text, comp = true)
      str = +text_of(text).gsub(BLANK_RE, " ")
      found = { _comp: comp }
      parse_day(str, found) if ascii?(str, :alpha)
      parse_time(str, found) if ascii?(str, :digit)
      parse_date(str, found)
      parse_bc(str, found) if ascii?(str, :alpha)
      parse_frag(str, found) if ascii?(str, :digit)
      complete_era(found)
      complete_century(found) if found.delete(:_comp)
      found[:offset] = zone_to_diff(found[:zone]) if found[:zone] && !found.key?(:offset)
      found
    end

    private

    # The date shapes, in the order that ruby tries them: the first that
    # fits wins, and the others never see the text it read.
    def parse_date(str, found)
      return if ascii?(str, :alpha, :digit) && (parse_eu(str, found) || parse_us(str, found))
      return if ascii?(str, :digit, :dash) && parse_iso(str, found)
      return if ascii?(str, :digit, :dot) && parse_jis(str, found)
      return if ascii?(str, :alpha, :digit, :dash) && parse_vms(str, found)
      return if ascii?(str, :digit, :slash) && parse_sla(str, found)
      return if ascii?(str, :digit, :dot) && parse_dot(str, found)
      return if ascii?(str, :digit) && parse_iso2(str, found)
      return if ascii?(str, :digit) && parse_quoted_year(str, found)
      return if ascii?(str, :alpha) && parse_mon(str, found)
      return if ascii?(str, :digit) && parse_mday(str, found)

      parse_ddd(str, found) if ascii?(str, :digit)
    end

    def text_of(text)
      text = String.try_convert(text) or raise TypeError, "no implicit conversion of #{conversion_name(text)} into String"
      raise ArgumentError, "string should have ASCII compatible encoding" unless text.encoding.ascii_compatible?

      text
    end

    # The character classes that ruby's own reader checks. It reads them
    # as bytes, so only ASCII counts.
    def ascii?(str, *kinds)
      kinds.all? do |kind|
        case kind
        when :alpha then str.match?(/[A-Za-z]/)
        when :digit then str.match?(/[0-9]/)
        when :dash then str.include?("-")
        when :dot then str.include?(".")
        else str.include?("/")
        end
      end
    end

    # Reads one shape and blanks what it read.
    def subs(str, pattern)
      m = pattern.match(str) or return false
      str[m.begin(0), m.end(0) - m.begin(0)] = " "
      yield(m)
      true
    end

    def day_num(text) = ABBR_DAYS.split("|").index { |name| name.casecmp?(text[0, 3]) } || 7

    def mon_num(text) = (ABBR_MONS.split("|").index { |name| name.casecmp?(text[0, 3]) } || 12) + 1

    def digit_span(text, from)
      length = 0
      length += 1 while text[from + length]&.match?(/[0-9]/)
      length
    end

    # The year, month and day three loose texts name, put in the order
    # their own shapes imply.
    def s3e(found, y, m, d, bc)
      m = m.to_s unless m.nil? || m.is_a?(String)
      y, m, d = d, y, m if y && m && d.nil?
      if y.nil? && d && (d.length > 2 || d.start_with?("'"))
        y = d
        d = nil
      end
      if y && (at = y.index(/[-+0-9]/))
        stop = at + (y[at].match?(/[-+]/) ? 1 : 0)
        stop += digit_span(y, stop)
        if stop < y.length
          y, d = d, y[at...stop]
        end
      end
      y, m, d = m, d, y if m && (m.start_with?("'") || m.length > 2)
      y, d = d, y if d && (d.start_with?("'") || d.length > 2)

      comp = nil
      if y && (at = y.index(/[-+0-9]/))
        start = at
        signed = y[at].match?(/[-+]/)
        at += 1 if signed
        comp = false if signed
        span = digit_span(y, at)
        comp = false if span > 2
        found[:year] = y[start...(at + span)].to_i
      end
      found[:_bc] = true if bc
      found[:mon] = digits_in(m) if m && digits_in(m)
      found[:mday] = digits_in(d) if d && digits_in(d)
      found[:_comp] = comp unless comp.nil?
    end

    def digits_in(text)
      at = text.index(/[0-9]/) or return nil

      text[at, digit_span(text, at)].to_i
    end

    def parse_day(str, found)
      subs(str, DAY_RE) { |m| found[:wday] = day_num(m[1]) }
    end

    def parse_time(str, found)
      subs(str, TIME_RE) do |m|
        found[:zone] = m[2] if m[2]
        time = TIME2_RE.match(m[1]) or next

        hour = time[1].to_i
        hour = (int_hour(hour) % 12) + (time[5].casecmp?("p") ? 12 : 0) if time[5]
        found[:hour] = hour
        found[:min] = time[2].to_i if time[2]
        found[:sec] = time[3].to_i if time[3]
        found[:sec_fraction] = Rational(time[4].to_i, 10**time[4].length) if time[4]
      end
    end

    # The half day that an "am" or a "pm" gives is counted in a machine
    # int, so an hour past its range has no result.
    def int_hour(hour)
      raise RangeError, "integer #{hour} too big to convert to 'int'" unless (-2**31...2**31).cover?(hour)

      hour
    end

    def parse_eu(str, found)
      subs(str, EU_RE) { |m| s3e(found, m[4], mon_num(m[2]), m[1], m[3]&.downcase&.start_with?("b")) }
    end

    def parse_us(str, found)
      subs(str, US_RE) { |m| s3e(found, m[4], mon_num(m[1]), m[2], m[3]&.downcase&.start_with?("b")) }
    end

    def parse_iso(str, found)
      subs(str, ISO_RE) { |m| s3e(found, m[1], m[2], m[3], false) }
    end

    def parse_jis(str, found)
      subs(str, JIS_RE) do |m|
        found[:year] = m[2].to_i + GENGO.fetch(m[1].downcase, 0)
        found[:mon] = m[3].to_i
        found[:mday] = m[4].to_i
      end
    end

    def parse_vms(str, found)
      subs(str, VMS11_RE) { |m| s3e(found, m[3], mon_num(m[2]), m[1], false) } ||
        subs(str, VMS12_RE) { |m| s3e(found, m[3], mon_num(m[1]), m[2], false) }
    end

    def parse_sla(str, found)
      subs(str, SLA_RE) { |m| s3e(found, m[1], m[2], m[3], false) }
    end

    def parse_dot(str, found)
      subs(str, DOT_RE) { |m| s3e(found, m[1], m[2], m[3], false) }
    end

    def parse_iso2(str, found)
      return true if subs(str, ISO21_RE) do |m|
        found[:cwyear] = m[1].to_i if m[1]
        found[:cweek] = m[2].to_i
        found[:cwday] = m[3].to_i if m[3]
      end
      return true if subs(str, ISO22_RE) { |m| found[:cwday] = m[1].to_i }
      return true if subs(str, ISO23_RE) do |m|
        found[:mon] = m[1].to_i if m[1]
        found[:mday] = m[2].to_i
      end
      return true if subs(str, ISO24_RE) do |m|
        found[:mon] = m[1].to_i
        found[:mday] = m[2].to_i if m[2]
      end
      unless ISO25_BAR_RE.match?(str)
        return true if subs(str, ISO25_RE) do |m|
          found[:year] = m[1].to_i
          found[:yday] = m[2].to_i
        end
      end
      return false if ISO26_BAR_RE.match?(str)

      subs(str, ISO26_RE) { |m| found[:yday] = m[1].to_i }
    end

    def parse_quoted_year(str, found)
      subs(str, YEAR_RE) { |m| found[:year] = m[1].to_i }
    end

    def parse_mon(str, found)
      subs(str, MON_RE) { |m| found[:mon] = mon_num(m[1]) }
    end

    def parse_mday(str, found)
      subs(str, MDAY_RE) { |m| found[:mday] = m[1].to_i }
    end

    # A run of digits with no separators. How many there are says what
    # they name, and a fraction with no time before it means a clock.
    def parse_ddd(str, found)
      subs(str, DDD_RE) do |m|
        ddd_digits(found, m[2], m[1] == "-", m[3].nil? && !m[4].nil?)
        ddd_time(found, m[3], m[4]) if m[3]
        found[:sec_fraction] = Rational(m[4].to_i, 10**m[4].length) if m[4]
        ddd_zone(found, m[5]) if m[5]
      end
    end

    def ddd_digits(found, digits, negative, clock)
      size = digits.length
      return clock_tail(found, digits, size) if clock

      case size
      when 2 then found[:mday] = digits[0, 2].to_i
      when 3 then found[:yday] = digits[0, 3].to_i
      when 4 then found.merge!(mon: digits[0, 2].to_i, mday: digits[2, 2].to_i)
      when 5 then found.merge!(year: signed(digits[0, 2].to_i, negative), yday: digits[2, 3].to_i)
      when 6 then found.merge!(year: signed(digits[0, 2].to_i, negative), mon: digits[2, 2].to_i, mday: digits[4, 2].to_i)
      when 7 then found.merge!(year: signed(digits[0, 4].to_i, negative), yday: digits[4, 3].to_i)
      when 8, 10, 12, 14
        found.merge!(year: signed(digits[0, 4].to_i, negative), mon: digits[4, 2].to_i, mday: digits[6, 2].to_i)
        found[:hour] = digits[8, 2].to_i if size >= 10
        found[:min] = digits[10, 2].to_i if size >= 12
        found[:sec] = digits[12, 2].to_i if size >= 14
        found[:_comp] = false
      end
    end

    # The same digits read from the right, as a clock.
    def clock_tail(found, digits, size)
      case size
      when 2 then found[:sec] = digits[-2, 2].to_i
      when 3 then found.merge!(sec: digits[-2, 2].to_i, min: digits[-3, 1].to_i)
      when 4 then found.merge!(sec: digits[-2, 2].to_i, min: digits[-4, 2].to_i)
      when 5 then found.merge!(sec: digits[-2, 2].to_i, min: digits[-4, 2].to_i, hour: digits[-5, 1].to_i)
      when 6 then found.merge!(sec: digits[-2, 2].to_i, min: digits[-4, 2].to_i, hour: digits[-6, 2].to_i)
      when 7 then found.merge!(sec: digits[-2, 2].to_i, min: digits[-4, 2].to_i, hour: digits[-6, 2].to_i, mday: digits[-7, 1].to_i)
      when 8, 10, 12, 14
        found.merge!(sec: digits[-2, 2].to_i, min: digits[-4, 2].to_i, hour: digits[-6, 2].to_i, mday: digits[-8, 2].to_i)
        found[:mon] = digits[-10, 2].to_i if size >= 10
        found[:year] = digits[-12, 2].to_i if size == 12
        found.merge!(year: digits[-14, 4].to_i, _comp: false) if size == 14
      end
    end

    def ddd_time(found, time, fraction)
      return unless [2, 4, 6].include?(time.length)

      return clock_tail(found, time, time.length) if fraction

      found[:hour] = time[0, 2].to_i
      found[:min] = time[2, 2].to_i if time.length >= 4
      found[:sec] = time[4, 2].to_i if time.length >= 6
    end

    # A zone in brackets contains an offset, and after a colon its name.
    def ddd_zone(found, text)
      found[:zone] = text
      return unless text.start_with?("[")

      inner = text[1..-2]
      if (at = inner.index(":"))
        found[:zone] = inner[(at + 1)..]
        source = inner[0, at + 1]
      else
        found[:zone] = inner
        source = inner.match?(/\A\d/) ? "+#{inner}" : inner
      end
      found[:offset] = zone_to_diff(source)
    end

    def signed(value, negative) = negative ? -value : value

    def parse_bc(str, found)
      subs(str, BC_RE) { found[:_bc] = true }
    end

    # A lone one or two digit number beside a time is a day, and beside
    # a day it is an hour.
    def parse_frag(str, found)
      subs(str, FRAG_RE) do |m|
        number = m[1].to_i
        found[:mday] = number if found[:hour] && !found[:mday] && (1..31).cover?(number)
        found[:hour] = number if found[:mday] && !found[:hour] && (0..24).cover?(number)
      end
    end

    def complete_era(found)
      return unless found.delete(:_bc)

      found[:cwyear] = -found[:cwyear] + 1 if found[:cwyear]
      found[:year] = -found[:year] + 1 if found[:year]
    end

    # A two digit year is this century when it is under 69.
    def complete_century(found)
      %i[cwyear year].each do |key|
        value = found[key]
        found[key] = value + (value >= 69 ? 1900 : 2000) if value && (0..99).cover?(value)
      end
    end
  end
end
