# A Time is nanoseconds since the epoch, kept in UTC, plus the zone it
# shows itself in. The count is exact, as CRuby keeps it: an Integer, or
# a Rational when the Time was built from a Float or a Rational whose
# value falls between two nanoseconds. The zone is UTC, a fixed offset, or the local zone libSystem
# describes. Civil dates come from the proleptic Gregorian calendar
# through the days-from-civil algorithm.
class Time
  include Comparable

  NS = 1_000_000_000
  MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze
  MONTH_NAMES = %w[January February March April May June July August September October November December].freeze
  DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  SPACE = " \t\n\v\f\r"
  # time.c's compat tables: for each month and the weekday its first day
  # falls on, a year before 2038 whose month starts the same way.
  COMPAT_COMMON_YEARS = [
    [2034, 2035, 2036, 2031, 2032, 2027, 2033], [2026, 2027, 2033, 2034, 2035, 2030, 2031],
    [2026, 2032, 2033, 2034, 2035, 2030, 2036], [2035, 2030, 2036, 2026, 2032, 2033, 2034],
    [2033, 2034, 2035, 2030, 2036, 2026, 2032], [2036, 2026, 2032, 2033, 2034, 2035, 2030],
    [2035, 2030, 2036, 2026, 2032, 2033, 2034], [2032, 2033, 2034, 2035, 2030, 2036, 2026],
    [2030, 2036, 2026, 2032, 2033, 2034, 2035], [2034, 2035, 2030, 2036, 2026, 2032, 2033],
    [2026, 2032, 2033, 2034, 2035, 2030, 2036], [2030, 2036, 2026, 2032, 2033, 2034, 2035]
  ].freeze
  COMPAT_LEAP_YEARS = [2032, 2016, 2028, 2012, 2024, 2036, 2020].freeze
  private_constant :NS, :MONTHS, :MONTH_NAMES, :DAY_NAMES, :SPACE, :COMPAT_COMMON_YEARS, :COMPAT_LEAP_YEARS

  class << self
    def now(**options)
      at_ns(Primitive.zr_clock_ns(Process::CLOCK_REALTIME), options[:in])
    end

    def at(time, subsec = nil, unit = :microsecond, **options)
      zone = options[:in]
      if time.is_a?(Time)
        raise ArgumentError, "wrong number of arguments (given 2, expected 1)" unless subsec.nil?

        t = time.dup
        return zone.nil? ? t : t.localtime(zone)
      end

      ns = exact_ns(time, NS)
      unless subsec.nil?
        scale = case unit
                when :millisecond then 1_000_000
                when :usec, :microsecond then 1000
                when :nsec, :nanosecond then 1
                else raise ArgumentError, "unexpected unit: #{unit}"
                end
        ns += exact_ns(subsec, scale)
      end
      at_ns(ns, zone)
    end

    def utc(*args) = from_fields(args, :utc)

    alias gm utc

    def local(*args) = from_fields(args, nil)

    alias mktime local

    private

    def at_ns(ns, zone)
      t = allocate
      t.send(:set, ns, zone.nil? ? :local : parse_zone(zone))
      t
    end

    # A count of `scale` nanoseconds each, as an exact count of
    # nanoseconds: a Float counts by its exact binary value.
    def exact_ns(value, scale)
      case value
      when Integer then value * scale
      when Float, Rational then canonical(value.to_r * scale)
      else exact_ns(exact(value), scale)
      end
    end

    # num_exact: what `to_r` answers for a value that also has `to_int`,
    # else what `to_int` answers; a String, nil or anything else has no
    # exact number.
    def exact(value)
      if !value.nil? && !value.is_a?(String)
        if value.respond_to?(:to_r)
          if value.respond_to?(:to_int)
            number = value.to_r
            return number if number.is_a?(Integer) || number.is_a?(Rational)
          end
        elsif (number = Integer.try_convert(value))
          return number
        end
      end
      raise TypeError, "can't convert #{value.class} into an exact number"
    end

    # A Rational that holds a whole number is that Integer.
    def canonical(count) = count.is_a?(Rational) && count.denominator == 1 ? count.numerator : count

    # A zone argument: a fixed offset, `:utc`, or a local zone with
    # the offset the calendar time resolves to.
    def parse_zone(zone)
      case zone
      when :utc then :utc
      when Integer
        raise ArgumentError, "utc_offset out of range" if zone.abs >= 86400

        zone
      when String
        offset = zone_offset(zone)
        raise ArgumentError, "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: #{zone}" if offset.nil?

        offset
      else
        # utc_offset_arg: what to_str names, else an exact number of seconds.
        text = String.try_convert(zone)
        return parse_zone(text) if text

        seconds = exact(zone)
        Primitive.zr_unimplemented("a utc_offset of a fraction of a second") unless seconds.is_a?(Integer)

        parse_zone(seconds)
      end
    end

    def zone_offset(zone)
      return :utc if zone == "UTC" || zone == "Z"
      if zone.size == 1
        letter = zone.ord
        return :utc if letter == 90
        return (letter - 64) * 3600 if letter >= 65 && letter <= 73
        return (letter - 65) * 3600 if letter >= 75 && letter <= 77
        return -(letter - 77) * 3600 if letter >= 78 && letter <= 89

        return nil
      end
      sign = zone[0]
      return nil unless sign == "+" || sign == "-"

      digits = zone[1..]
      hh, mm, ss = case digits.size
                   when 2 then [digits, "00", "00"]
                   when 4 then [digits[0, 2], digits[2, 2], "00"]
                   when 5 then digits[2] == ":" ? [digits[0, 2], digits[3, 2], "00"] : nil
                   when 8 then digits[2] == ":" && digits[5] == ":" ? [digits[0, 2], digits[3, 2], digits[6, 2]] : nil
                   end
      return nil if hh.nil? || [hh, mm, ss].any? { |part| part.size != 2 || !part.chars.all? { |ch| ch.between?("0", "9") } }

      offset = hh.to_i * 3600 + mm.to_i * 60 + ss.to_i
      return nil if hh.to_i > 23 || mm.to_i > 59 || ss.to_i > 59

      sign == "-" ? -offset : offset
    end

    # `Time.new("2021-12-25 10:00:00 +09:00")`: CRuby's time_init_parse,
    # which reads an ISO-8601-shaped string and nothing else. A zone the
    # string carries takes the place of the one the caller named.
    def string_parts(str, zone, precision)
      raise ArgumentError, "time string should have ASCII compatible encoding" unless str.encoding.ascii_compatible?
      raise ArgumentError, "can't parse: #{str.inspect}" if !str.empty? && (space?(str[0]) || space?(str[-1]))

      year, pos = year_part(str)
      parts = []
      if pos < str.size
        parts, pos = date_parts(str, pos, precision || str.size)
        found, pos = zone_part(str, pos)
        raise ArgumentError, "can't parse at: #{str[pos..]}" if pos < str.size
        raise ArgumentError, "no time information" if found.empty? && parts.size < 5

        zone = found unless found.empty?
      end
      mon, mday, hour, min, sec = parts
      civil_parts(year, mon || 1, mday || 1, hour || 0, min || 0, sec || 0, zone)
    end

    # The year a time string opens with: a sign, then four digits or
    # more, and where it ends.
    def year_part(str)
      start = str.start_with?("+") || str.start_with?("-") ? 1 : 0
      digits = 0
      digits += 1 while digit?(str[start + digits])
      raise ArgumentError, "can't parse: #{str.inspect}" if digits.zero?
      raise ArgumentError, "year must be 4 or more digits: #{str[start, digits]}" if digits < 4

      [Integer(str[0, start + digits]), start + digits]
    end

    # What follows the year: `-mm-dd`, then `hh:mm:ss` and a fraction.
    # CRuby stops at the first part the string does not carry, and reads
    # what is left as the zone, so each part that is missing ends this.
    def date_parts(str, pos, precision)
      return [[], pos] unless str[pos] == "-"

      mon = two_digits(str, pos + 1, "mon")
      pos += 3
      return [[mon], pos] unless str[pos] == "-"

      mday = two_digits(str, pos + 1, "mday")
      pos += 3
      return [[mon, mday], pos] unless (str[pos] == " " || str[pos] == "T") && digit?(str[pos + 1])

      clock = pos + 1
      hour = two_digits(str, pos + 1, "hour")
      pos += 3
      whole_part(str, pos, clock, "hour")
      colon(str, pos, clock, "min")
      min = two_digits(str, pos + 1, "min")
      pos += 3
      whole_part(str, pos, clock, "min")
      colon(str, pos, clock, "sec")
      sec = two_digits(str, pos + 1, "sec")
      pos += 3
      return [[mon, mday, hour, min, sec], pos] unless str[pos] == "."

      fraction, pos = subsecond(str, pos + 1, clock, precision)
      [[mon, mday, hour, min, sec + fraction], pos]
    end

    # Two digits and no third, as CRuby's two_digits reads them; the
    # refusal names the part, then the text from its separator on.
    def two_digits(str, pos, name)
      unless digit?(str[pos]) && digit?(str[pos + 1]) && !digit?(str[pos + 2])
        after = " after '#{str[pos - 1]}'" if str[pos - 1] == "-" || str[pos - 1] == ":"
        raise ArgumentError, "two digits #{name} is expected#{after}: #{str[pos - 1, 11]}"
      end

      Integer(str[pos, 2])
    end

    # Only the second takes a fraction.
    def whole_part(str, pos, clock, name)
      raise ArgumentError, "fraction #{name} is not supported: #{str[clock, pos + 1 - clock]}" if str[pos] == "."
    end

    def colon(str, pos, clock, name)
      raise ArgumentError, "missing #{name} part: #{str[clock, pos + 1 - clock]}" unless str[pos] == ":"
    end

    # The fraction after the second's dot, as a Rational of a second:
    # `precision` digits at most, and any digit past that is dropped.
    def subsecond(str, pos, clock, precision)
      digits = 0
      digits += 1 while digits < precision && digit?(str[pos + digits])
      raise ArgumentError, "subsecond expected after dot: #{str[clock, pos - clock + (str[pos].nil? ? 0 : 1)]}" if digits.zero?

      value = Integer(str[pos, digits])
      pos += digits
      pos += 1 while digit?(str[pos])
      [Rational(value, 10**digits), pos]
    end

    # The zone the string ends with, and where the reading stopped: the
    # run of text after the clock, with the spaces on each side dropped.
    def zone_part(str, pos)
      pos += 1 while space?(str[pos])
      start = pos
      pos += 1 while pos < str.size && !space?(str[pos])
      found = str[start...pos]
      pos += 1 while space?(str[pos])
      [found, pos]
    end

    def space?(char) = !char.nil? && SPACE.include?(char)

    def digit?(char) = !char.nil? && char >= "0" && char <= "9"

    # `(year, month, day, hour, min, sec, usec)`, or the ten fields
    # `Time#to_a` gives, which name the same instant backwards.
    def from_fields(args, zone)
      if args.size == 10
        sec, min, hour, day, month, year = args
        return civil(year, month, day, hour, min, sec, zone)
      end
      year, month, day, hour, min, sec, usec = args
      civil(year, month, day, hour, min, sec, zone, usec)
    end

    # This moment, and the kind a zone argument names: what `Time.now`
    # and a bare `Time.new` both seat.
    def now_parts(zone)
      [Primitive.zr_clock_ns(Process::CLOCK_REALTIME), zone.nil? ? :local : parse_zone(zone)]
    end

    def civil(year, month, day, hour, min, sec, zone, usec = nil)
      t = allocate
      t.send(:set, *civil_parts(year, month, day, hour, min, sec, zone, usec))
      t
    end

    # The nanoseconds and the kind a civil date names, which the caller
    # seats in whichever Time it is filling.
    def civil_parts(year, month, day, hour, min, sec, zone, usec = nil)
      # obj2vint: a String reads as decimal digits, anything else as to_int.
      year = year.is_a?(String) ? Integer(year, 10) : to_integer(year)
      month = month_arg(month)
      day = int_arg(day, 1, 1, 31, "mday")
      hour = int_arg(hour, 0, 0, 24, "hour")
      min = int_arg(min, 0, 0, 59, "min")
      sec_ns = 0
      if sec.nil?
        sec = 0
      elsif sec.is_a?(Float) || sec.is_a?(Rational)
        raise ArgumentError, "sec out of range" if sec < 0 || sec >= 61

        sec_ns = exact_ns(sec - sec.floor, NS)
        sec = sec.floor
      else
        sec = int_arg(sec, 0, 0, 60, "sec")
      end
      raise ArgumentError, "argument out of range" if hour == 24 && (min != 0 || sec != 0)

      unless usec.nil?
        raise ArgumentError, "subsecx out of range" if usec < 0 || usec >= 1_000_000

        sec_ns += exact_ns(usec, 1000)
      end

      days = days_from_civil(year, month, day)
      local_ns = ((days * 86400 + hour * 3600 + min * 60 + sec) * NS) + sec_ns
      kind = zone.nil? ? :local : parse_zone(zone)
      case kind
      when :utc then [local_ns, :utc]
      when Integer then [local_ns - kind * NS, kind]
      else [local_ns - local_offset_for(local_ns.div(NS)) * NS, :local]
      end
    end

    def month_arg(month)
      return 1 if month.nil?

      if month.is_a?(String)
        index = MONTHS.index(month.downcase)
        return index + 1 if index

      end
      # obj2ubits: a String reads as decimal digits, anything else as
      # to_int.
      month = month.is_a?(String) ? Integer(month, 10) : implicit_integer(month)
      raise ArgumentError, "mon out of range" if month < 1 || month > 12

      month
    end

    def int_arg(value, default, low, high, name)
      return default if value.nil?

      value = value.is_a?(String) ? Integer(value, 10) : implicit_integer(value)
      raise ArgumentError, "#{name} out of range" if value < low || value > high

      value
    end

    # The local offset for a calendar time `secs` (its fields read as
    # if UTC): the one whose zone gives that calendar time back; when
    # two do, or none does, the smaller offset.
    def local_offset_for(secs)
      offsets = [secs - 86_400, secs, secs + 86_400].map { |at| zone_at(at)[0] }.uniq
      return offsets[0] if offsets.size == 1

      fitting = offsets.select { |offset| zone_at(secs - offset)[0] == offset }
      (fitting.empty? ? offsets : fitting).min
    end

    # The zone's offset, daylight flag and name at `secs`, as localtimew
    # finds them. On this platform rb_localtime_r answers only for a
    # time an int holds, and guess_local_offset stands in past that: no
    # zone kept daylight time before 1916, so an earlier time takes the
    # epoch's zone, and a time past 2038 the zone of the year before
    # 2038 whose month starts on the same day of the week.
    def zone_at(secs)
      return Primitive.zr_time_local(secs) if secs.between?(-0x8000_0000, 0x7fff_ffff)

      year, month, day = civil_from_days(secs.div(86_400))
      return Primitive.zr_time_local(0) if year < 1916

      weekday = (days_from_civil(year, month, 1) + 4) % 7
      leap = (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
      stand_in = month == 2 && leap ? COMPAT_LEAP_YEARS[weekday] : COMPAT_COMMON_YEARS[month - 1][weekday]
      Primitive.zr_time_local((days_from_civil(stand_in, month, day) * 86_400) + (secs % 86_400))
    end

    public

    def days_from_civil(y, m, d)
      y -= 1 if m <= 2
      era = y / 400
      yoe = y - era * 400
      doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
      doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
      era * 146_097 + doe - 719_468
    end

    def civil_from_days(z)
      z += 719_468
      era = z / 146_097
      doe = z - era * 146_097
      yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
      y = yoe + era * 400
      doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
      mp = (5 * doy + 2) / 153
      d = doy - (153 * mp + 2) / 5 + 1
      m = mp < 10 ? mp + 3 : mp - 9
      [m <= 2 ? y + 1 : y, m, d]
    end

    private :days_from_civil, :civil_from_days
  end

  # `Time.new(...)` is this row, as it is in CRuby: a program that reopens
  # Time with an initialize of its own takes this place, and `now`, `at`
  # and `utc` build their own instances without asking.
  # timev.rb's: no year is now, and a year alone may be a String to parse.
  def initialize(year = (now = true), mon = (str = year; nil), mday = nil, hour = nil, min = nil, sec = nil, zone = nil,
                 in: nil, precision: 9)
    Primitive.attr! :ruby
    raise TypeError, "already initialized Time" if Primitive.zr_hidden_get(self, :__built__)

    if zone
      raise ArgumentError, "timezone argument given as positional and keyword arguments" if Primitive.arg!(:in)
    else
      zone = Primitive.arg!(:in)
    end
    return set(*Time.send(:now_parts, zone)) if now

    text = str && String.try_convert(str)
    return set(*Time.send(:string_parts, text, zone, precision)) if text

    set(*Time.send(:civil_parts, year, mon, mday, hour, min, sec, zone))
  end

  def year = fields[0]
  def month = fields[1]
  alias mon month
  def day = fields[2]
  alias mday day
  def hour = fields[3]
  def min = fields[4]
  def sec = fields[5]
  def wday = fields[6]
  def yday = fields[7]

  def usec = ((ns % NS) / 1000).floor
  alias tv_usec usec
  def nsec = (ns % NS).floor
  alias tv_nsec nsec
  # The fraction of a second: 0 on a whole second, else a Rational.
  def subsec
    rest = ns % NS
    rest.zero? ? 0 : rest.quo(NS)
  end

  def to_i = ns.div(NS)
  alias tv_sec to_i
  def to_f = float_seconds(ns)
  def to_r = ns.quo(NS)

  def utc? = kind == :utc
  alias gmt? utc?

  def utc_offset
    case kind
    when :utc then 0
    when :local then local_offset
    else kind
    end
  end

  alias gmt_offset utc_offset
  alias gmtoff utc_offset

  # A zone name holds no character above ASCII, and ruby answers it in
  # the encoding that says so.
  def zone
    case kind
    when :utc then (+"UTC").force_encoding(Encoding::US_ASCII)
    when :local then local_zone
    end
  end

  def dst? = kind == :local && local_dst
  alias isdst dst?

  def to_a = [sec, min, hour, day, month, year, wday, yday, dst?, zone]

  def sunday? = wday == 0
  def monday? = wday == 1
  def tuesday? = wday == 2
  def wednesday? = wday == 3
  def thursday? = wday == 4
  def friday? = wday == 5
  def saturday? = wday == 6

  def utc
    set(ns, :utc)
    self
  end

  alias gmtime utc

  def getutc = dup.utc
  alias getgm getutc

  def localtime(zone = nil)
    set(ns, zone.nil? ? :local : Time.send(:parse_zone, zone))
    self
  end

  def getlocal(zone = nil) = dup.localtime(zone)

  def +(other)
    raise TypeError, "time + time?" if other.is_a?(Time)

    shifted(ns + Time.send(:exact_ns, other, NS))
  end

  def -(other)
    return float_seconds(ns - other.send(:ns)) if other.is_a?(Time)

    shifted(ns - Time.send(:exact_ns, other, NS))
  end

  def <=>(other)
    return nil unless other.is_a?(Time)

    ns <=> other.send(:ns)
  end

  def eql?(other) = other.is_a?(Time) && ns == other.send(:ns)

  def hash = ns.hash

  def round(digits = 0) = rounded(digits) { |ns, unit| (ns + unit.quo(2)).div(unit) * unit }

  def floor(digits = 0) = rounded(digits) { |ns, unit| ns.div(unit) * unit }

  def ceil(digits = 0) = rounded(digits) { |ns, unit| -(-ns).div(unit) * unit }

  # A whole count of nanoseconds shows as digits; a fraction between two
  # nanoseconds shows as the Rational of the second it is.
  def inspect
    text = strftime("%Y-%m-%d %H:%M:%S")
    rest = ns % NS
    if rest.is_a?(Rational)
      text = "#{text} #{rest / NS}"
    elsif rest != 0
      text = "#{text}.#{format("%09d", rest).sub(/0+\z/, "")}"
    end
    "#{text} #{utc? ? 'UTC' : offset_shown}"
  end

  def to_s
    utc? ? strftime("%Y-%m-%d %H:%M:%S UTC") : strftime("%Y-%m-%d %H:%M:%S %z")
  end

  def ctime = strftime("%a %b %e %H:%M:%S %Y")
  alias asctime ctime

  # ISO 8601: `Z` for UTC, the offset otherwise, and `digits` places of
  # the fraction when asked for.
  def iso8601(digits = 0)
    text = strftime("%Y-%m-%dT%H:%M:%S")
    text = "#{text}.#{format("%09d", nsec)[0, digits]}" if digits > 0
    "#{text}#{utc? ? 'Z' : strftime('%:z')}"
  end
  alias xmlschema iso8601

  def deconstruct_keys(keys)
    all = { year: year, month: month, day: day, yday: yday, wday: wday,
            hour: hour, min: min, sec: sec, subsec: subsec, dst: dst?, zone: zone }
    return all if keys.nil?

    all.slice(*keys)
  end

  def strftime(pattern)
    pattern = Primitive.zr_str_operand(pattern)
    out = +""
    i = 0
    n = pattern.size
    while i < n
      c = pattern[i]
      if c != "%"
        out << c
        i += 1
        next
      end
      i += 1
      flags = +""
      while i < n && "-_0^#".include?(pattern[i])
        flags << pattern[i]
        i += 1
      end
      width = nil
      while i < n && pattern[i] >= "0" && pattern[i] <= "9"
        width = (width || 0) * 10 + pattern[i].to_i
        i += 1
      end
      colons = 0
      while i < n && pattern[i] == ":"
        colons += 1
        i += 1
      end
      if i >= n
        out << "%" << flags << (width ? width.to_s : "") << ":" * colons
        break
      end
      directive = pattern[i]
      i += 1
      out << directive(directive, flags, width, colons)
    end
    out
  end

  private

  # A copy takes the instant of the Time it comes from, so a Time that
  # holds none cannot be copied, and one that already holds an instant
  # cannot take another.
  def initialize_copy(other)
    raise TypeError, "already initialized Time" if Primitive.zr_hidden_get(self, :__built__)
    raise TypeError, "uninitialized Time" unless Primitive.zr_hidden_get(other, :__built__)

    super
    Primitive.zr_hidden_set(self, :__built__, true)
  end

  # The instant and the zone it shows itself in. CRuby keeps both in a
  # struct, so a program sees no instance variable on a Time: these live
  # in hidden slots, and an `@ivar` on a Time is the program's own.
  def ns
    Primitive.attr! :hidden
    built!
    Primitive.zr_hidden_get(self, :__ns__)
  end

  def kind
    Primitive.attr! :hidden
    built!
    Primitive.zr_hidden_get(self, :__kind__)
  end

  def local_offset
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__offset__)
  end

  def local_dst
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__dst__)
  end

  def local_zone
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__zone__)
  end

  # `to_s` shows an offset as hours and minutes; `inspect` shows the
  # seconds of an offset that has them, run together, as time.c does.
  def offset_shown
    Primitive.attr! :hidden
    return strftime("%z") if utc_offset % 60 == 0

    offset = utc_offset
    sign = offset < 0 ? "-" : "+"
    offset = offset.abs
    format("%s%02d%02d%02d", sign, offset / 3600, (offset % 3600) / 60, offset % 60)
  end

  # A Time that no constructor filled holds no instant, and ruby says so
  # of every reader.
  def built!
    Primitive.attr! :hidden
    raise TypeError, "uninitialized Time" unless Primitive.zr_hidden_get(self, :__built__)
  end

  def set(at, of_kind)
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :__built__, true)
    Primitive.zr_hidden_set(self, :__ns__, Time.send(:canonical, at))
    Primitive.zr_hidden_set(self, :__kind__, of_kind)
    Primitive.zr_hidden_set(self, :__fields__, nil)
    if of_kind == :local
      offset, dst, name = Time.send(:zone_at, at.div(NS))
      Primitive.zr_hidden_set(self, :__offset__, offset)
      Primitive.zr_hidden_set(self, :__dst__, dst)
      Primitive.zr_hidden_set(self, :__zone__, name&.dup&.force_encoding(Encoding::US_ASCII))
    else
      Primitive.zr_hidden_set(self, :__offset__, nil)
      Primitive.zr_hidden_set(self, :__dst__, false)
      Primitive.zr_hidden_set(self, :__zone__, nil)
    end
    self
  end

  def shifted(at)
    Primitive.attr! :hidden
    t = dup
    t.send(:set, at, kind)
    t
  end

  def rounded(digits)
    Primitive.attr! :hidden
    raise ArgumentError, "negative ndigits given" if digits < 0

    unit = 10**(9 - digits)
    shifted(yield(ns, unit))
  end

  # year, month, day, hour, min, sec, wday, yday in the shown zone.
  def fields
    Primitive.attr! :hidden
    held = Primitive.zr_hidden_get(self, :__fields__)
    return held if held

    secs = ns.div(NS) + utc_offset
    days = secs.div(86400)
    rem = secs - days * 86400
    y, m, d = Time.send(:civil_from_days, days)
    row = [y, m, d, rem / 3600, (rem % 3600) / 60, rem % 60, (days + 4) % 7,
           days - Time.send(:days_from_civil, y, 1, 1) + 1]
    Primitive.zr_hidden_set(self, :__fields__, row)
    row
  end

  def directive(c, flags, width, colons)
    Primitive.attr! :hidden
    case c
    when "Y" then number(year, flags, width, year < 0 ? 5 : 4)
    when "C" then number(year.div(100), flags, width, 2)
    when "y" then number(year % 100, flags, width, 2)
    when "m" then number(month, flags, width, 2)
    when "d" then number(day, flags, width, 2)
    when "e" then number(day, flags, width, 2, " ")
    when "j" then number(yday, flags, width, 3)
    when "H" then number(hour, flags, width, 2)
    when "k" then number(hour, flags, width, 2, " ")
    when "I" then number(hour12, flags, width, 2)
    when "l" then number(hour12, flags, width, 2, " ")
    when "M" then number(min, flags, width, 2)
    when "S" then number(sec, flags, width, 2)
    when "L" then fraction(flags, width || 3)
    when "N" then fraction(flags, width || 9)
    when "z" then offset_text(flags, width, colons)
    when "Z" then text(zone || "", flags, width, :down)
    when "A" then text(DAY_NAMES[wday], flags, width)
    when "a" then text(DAY_NAMES[wday][0, 3], flags, width)
    when "B" then text(MONTH_NAMES[month - 1], flags, width)
    when "b", "h" then text(MONTH_NAMES[month - 1][0, 3], flags, width)
    when "p" then text(hour < 12 ? "AM" : "PM", flags, width, :down)
    when "P" then text(hour < 12 ? "am" : "pm", flags, width)
    when "u" then number(wday == 0 ? 7 : wday, flags, width, 1)
    when "w" then number(wday, flags, width, 1)
    when "s" then number(to_i, flags, width, 1)
    when "U" then number((yday - 1 + 7 - wday) / 7, flags, width, 2)
    when "W" then number((yday - 1 + 7 - (wday + 6) % 7) / 7, flags, width, 2)
    when "G" then number(iso_week[0], flags, width, 4)
    when "g" then number(iso_week[0] % 100, flags, width, 2)
    when "V" then number(iso_week[1], flags, width, 2)
    when "F" then text(strftime("%Y-%m-%d"), flags, width)
    when "T", "X" then text(strftime("%H:%M:%S"), flags, width)
    when "D", "x" then text(strftime("%m/%d/%y"), flags, width)
    when "R" then text(strftime("%H:%M"), flags, width)
    when "r" then text(strftime("%I:%M:%S %p"), flags, width)
    when "c" then text(strftime("%a %b %e %H:%M:%S %Y"), flags, width)
    when "n" then "\n"
    when "t" then "\t"
    when "%" then "%"
    else "%#{flags}#{width}#{':' * colons}#{c}"
    end
  end

  def hour12
    Primitive.attr! :hidden
    h = hour % 12
    h == 0 ? 12 : h
  end

  # A number padded to `digits` with `pad`, unless the flags say
  # otherwise; `width` widens the field.
  def number(value, flags, width, digits, pad = "0")
    Primitive.attr! :hidden
    pad = "0" if flags.include?("0")
    pad = " " if flags.include?("_")
    return value.to_s if flags.include?("-")

    text = value.abs.to_s
    size = width || digits
    text = pad * (size - text.size - (value < 0 ? 1 : 0)) + text if text.size < size
    value < 0 ? "-#{text}" : text
  end

  # A word, upcased by `^`; `#` changes its case the way `changed`
  # says.
  def text(value, flags, width, changed = :up)
    Primitive.attr! :hidden
    value = value.upcase if flags.include?("^")
    value = changed == :up ? value.upcase : value.downcase if flags.include?("#")
    return value if flags.include?("-")
    return value if width.nil? || value.size >= width

    (flags.include?("0") ? "0" : " ") * (width - value.size) + value
  end

  # The first `width` digits of the fraction of a second, cut, not
  # rounded.
  def fraction(flags, width)
    Primitive.attr! :hidden
    ((ns % NS) * 10**width / NS).floor.to_s.rjust(width, "0")
  end

  # A count of nanoseconds as a Float of seconds, divided as CRuby
  # divides it: a whole count by the Float scale, a fraction exactly.
  def float_seconds(count)
    Primitive.attr! :hidden
    count.is_a?(Rational) ? (count / NS).to_f : count / 1e9
  end

  def offset_text(flags, width, colons)
    Primitive.attr! :hidden
    offset = utc_offset
    sign = offset < 0 ? "-" : "+"
    offset = offset.abs
    hh = offset / 3600
    mm = (offset % 3600) / 60
    ss = offset % 60
    body = case colons
           when 0 then format("%02d%02d", hh, mm)
           when 1 then format("%02d:%02d", hh, mm)
           else format("%02d:%02d:%02d", hh, mm, ss)
           end
    text = sign + body
    return text if width.nil? || text.size >= width

    pad = flags.include?("_") ? " " : "0"
    pad == " " ? pad * (width - text.size) + text : sign + "0" * (width - text.size) + body
  end

  # The ISO 8601 week-numbering year and week.
  def iso_week
    Primitive.attr! :hidden
    monday_based = (wday + 6) % 7
    week = (yday - monday_based + 9) / 7
    if week < 1
      [year - 1, Time.send(:iso_weeks_in, year - 1)]
    elsif week > Time.send(:iso_weeks_in, year)
      [year + 1, 1]
    else
      [year, week]
    end
  end

  class << self
    private

    def iso_weeks_in(year)
      jan1 = (days_from_civil(year, 1, 1) + 4) % 7
      leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
      jan1 == 4 || (leap && jan1 == 3) ? 53 : 52
    end
  end
end

class Time
  # The wire format of time.c's time_mdump: two little-endian words of
  # the UTC civil time, a tail for a year outside 1900..1900+0xffff, and
  # the zone, the offset and the part under a microsecond beside them,
  # named on the payload itself.
  def _dump(_limit = -1)
    moment = getutc
    year = moment.year
    tail = nil
    if year > 1900 + 0xffff
      tail = year - (1900 + 0xffff)
      year = 1900 + 0xffff
    elsif year < 1900
      tail = 1900 - year
      year = 1900
    end
    rest = ns % NS
    whole = rest.floor
    word = (1 << 31) | ((utc? ? 1 : 0) << 30) | ((year - 1900) << 14) |
           ((moment.month - 1) << 10) | (moment.day << 5) | moment.hour
    second = (moment.min << 26) | (moment.sec << 20) | (whole / 1000)
    out = +"".b
    4.times { |i| out << ((word >> (8 * i)) & 0xff) }
    4.times { |i| out << ((second >> (8 * i)) & 0xff) }
    out << year_tail(tail) if tail
    # Under the microsecond: the exact rest as a pair, and its whole
    # nanoseconds again as the digits ruby 1.9.1 wrote.
    nano = rest - (whole - whole % 1000)
    unless nano.zero?
      Marshal.send(:extra_set, out, :nano_num, nano.numerator)
      Marshal.send(:extra_set, out, :nano_den, nano.denominator)
    end
    Marshal.send(:extra_set, out, :submicro, submicro_bytes(whole % 1000)) unless (whole % 1000).zero?
    Marshal.send(:extra_set, out, :offset, utc_offset) unless utc?
    Marshal.send(:extra_set, out, :zone, zone)
    out
  end

  private :_dump

  # A year outside the sixteen bits of the word: its distance from that
  # range, as a packed length and the bytes of the number.
  def year_tail(count)
    Primitive.attr! :hidden
    bytes = +"".b
    rest = count
    while rest > 0
      bytes << (rest & 0xff)
      rest >>= 8
    end
    bytes << 0 if bytes.empty?
    Marshal.send(:long_bytes, bytes.bytesize) + bytes
  end
  private :year_tail

  # The three digits under a microsecond, packed two to a byte. A last
  # digit of zero writes no byte of its own, as time_mdump trims it.
  def submicro_bytes(nano)
    Primitive.attr! :hidden
    out = +"".b
    out << (((nano / 100) << 4) | ((nano / 10) % 10))
    last = (nano % 10) << 4
    out << last unless last.zero?
    out
  end
  private :submicro_bytes

  # time_mload: the civil fields of the words, then the names beside
  # them. A payload too short for the words is not a marshalled Time.
  def self._load(text)
    text = String.try_convert(text)
    raise TypeError, "marshaled time format differ" if text.nil? || text.bytesize < 8

    extras = Marshal.send(:extras_of, text).to_h
    word = (0..3).sum { |i| text.getbyte(i) << (8 * i) }
    second = (4..7).sum { |i| text.getbyte(i) << (8 * ((i - 4))) }
    # The format ruby 1.8 wrote: the seconds and microseconds alone.
    return at(word, second) if (word & (1 << 31)).zero?

    word &= ~(1 << 31)
    year = ((word >> 14) & 0xffff) + 1900
    year = extended_year(year, text.byteslice(8..)) if text.bytesize > 8
    month = (word >> 10) & 0xf
    if month >= 12
      month -= 12
      year += 1
    end
    nano = second & 0xfffff
    nano = (nano * 1000) + sub_nanoseconds(extras)
    moment = utc(year, month + 1, (word >> 5) & 0x1f, word & 0x1f, (second >> 26) & 0x3f,
                 ((second >> 20) & 0x3f) + Rational(nano, NS))
    return moment if ((word >> 30) & 1) == 1

    moment.localtime(extras[:offset] || zone_at(moment.to_i).first)
  end

  private_class_method :_load

  # The year the tail names: its distance below 1900, or above the
  # highest year the word can hold.
  def self.extended_year(year, tail)
    size, rest = Marshal.send(:read_long_bytes, tail)
    raise TypeError, "marshaled time format differ" if size < 0 || size > rest.bytesize

    away = (0...size).sum { |i| rest.getbyte(i) << (8 * i) }
    year == 1900 ? year - away : year + away
  end
  private_class_method :extended_year

  # The nanoseconds under a microsecond: the exact pair where the dump
  # carries one, else the digits ruby 1.9.1 wrote.
  def self.sub_nanoseconds(extras)
    return Rational(extras[:nano_num], extras[:nano_den] || 1) if extras[:nano_num]

    digits = extras[:submicro]
    return 0 if digits.nil? || digits.empty?

    (digits.getbyte(0) >> 4) * 100 + (digits.getbyte(0) & 0xf) * 10 + (digits.getbyte(1).to_i >> 4)
  end
  private_class_method :sub_nanoseconds
end
