# frozen_string_literal: true

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
  # The strftime directives that represent a format of other directives.
  COMPOUNDS = { "c" => "%a %b %e %H:%M:%S %Y", "x" => "%m/%d/%y", "X" => "%H:%M:%S", "D" => "%m/%d/%y",
                "r" => "%I:%M:%S %p", "R" => "%H:%M", "T" => "%H:%M:%S", "v" => "%e-%^b-%4Y", "F" => "%Y-%m-%d" }.freeze
  INT_MAX = 0x7fff_ffff
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
  private_constant :NS, :MONTHS, :MONTH_NAMES, :DAY_NAMES, :SPACE, :COMPOUNDS, :INT_MAX, :COMPAT_COMMON_YEARS, :COMPAT_LEAP_YEARS

  class << self
    def now(**options)
      at_ns(Primitive.zr_clock_ns(Process.send(:clock_id, Process::CLOCK_REALTIME, "clock_gettime")), options[:in])
    end

    # timev.rb's: a subsec of false is none.
    def at(time, subsec = false, unit = :microsecond, in: nil)
      Primitive.attr! :ruby
      zone = Primitive.arg!(:in)
      if time.is_a?(Time)
        # time_s_at: with a second argument the Time must be a number.
        raise TypeError, +"can't convert Time into an exact number" unless subsec == false

        # An instance of the receiver, a subclass too.
        t = allocate
        t.send(:set, time.send(:ns), time.send(:kind))
        return zone.nil? ? t : t.localtime(zone)
      end

      ns = exact_ns(time, NS)
      unless subsec == false
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

    # Helpers CRuby writes in C: no backtrace row and no method a
    # program can list.
    Primitive.attr! :hidden

    def at_ns(ns, zone)
      t = allocate
      kind = zone.nil? ? :local : parse_zone(zone)
      needs!(kind, :utc_to_local)
      t.send(:set, ns, kind)
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

    # num_exact: the value of `to_r` for a value that also has `to_int`,
    # else the value of `to_int`. A String, nil or any other object has no
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
      raise TypeError, cant_convert(value, "an exact number")
    end

    # A Rational that contains a whole number becomes that Integer.
    def canonical(count) = count.is_a?(Rational) && count.denominator == 1 ? count.numerator : count

    # A zone argument: a fixed offset, `:utc`, or a local zone with
    # the offset the calendar time resolves to.
    def parse_zone(zone)
      # A timezone object (one with local_to_utc or utc_to_local) is its
      # own kind: it gives the offset at each instant.
      return zone if zone_object?(zone)

      case zone
      when :utc then :utc
      when Integer
        raise ArgumentError, +"utc_offset out of range" if zone.abs >= 86400

        zone
      when String
        offset = zone_offset(zone)
        # find_timezone: a class that names zones finds one for a name.
        if offset.nil? && respond_to?(:find_timezone)
          found = find_timezone(zone)
          return found if zone_object?(found)
        end
        raise ArgumentError, "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: #{zone.encoding.ascii_compatible? ? zone : zone.inspect}" if offset.nil?
        raise ArgumentError, +"utc_offset out of range" if offset.is_a?(Integer) && offset.abs >= 86400

        offset
      else
        # utc_offset_arg: what to_str names, else an exact number of seconds.
        text = String.try_convert(zone)
        return parse_zone(text) if text

        seconds = canonical(exact(zone))
        return parse_zone(seconds) if seconds.is_a?(Integer)
        raise ArgumentError, +"utc_offset out of range" if seconds.abs >= 86400

        seconds
      end
    end

    # A timezone object that lacks the method a use calls is read as a
    # number of seconds, as CRuby falls back to num_exact.
    def needs!(zone, method)
      return unless zone_object?(zone) && !zone.respond_to?(method)

      raise TypeError, cant_convert(zone, "an exact number")
    end

    # Whether `zone` is a timezone object: not a name or a number, and with
    # local_to_utc or utc_to_local.
    def zone_object?(zone)
      return false if zone.nil? || zone.is_a?(String) || zone.is_a?(Integer) || zone.is_a?(Rational) || zone.is_a?(Symbol)

      zone.respond_to?(:local_to_utc) || zone.respond_to?(:utc_to_local)
    end

    # The Time::tm that a timezone object's methods take: UTC, with no
    # subsecond, at `secs` (tm_from_time).
    def zone_tm(secs)
      t = Time.allocate
      t.send(:set, secs * NS, :utc)
      TM.send(:kept, t)
    end

    # zone_localtime: the offset in seconds that `zone` gives at the instant
    # `secs`, from the wall clock that its utc_to_local returns.
    def zone_offset_at(zone, secs)
      offset = if zone.respond_to?(:utc_to_local)
                 zone_wall(zone.utc_to_local(zone_tm(secs))) - secs
               else
                 # Only local_to_utc: the wall clock less the instant it names.
                 result = zone.local_to_utc(zone_tm(secs))
                 secs - (result.is_a?(Integer) ? result : result.to_i)
               end
      raise ArgumentError, +"utc_offset out of range" if offset.abs >= 86400

      offset
    end

    # A wall clock as local seconds: an Integer as it is, a Time by its own
    # fields, any other value by its year to sec, or by to_i.
    def zone_wall(local)
      return local if local.is_a?(Integer)
      return local.to_i + local.utc_offset if local.is_a?(Time)
      return local.to_i unless local.respond_to?(:year)

      (days_from_civil(local.year, local.mon, local.mday) * 86400) + (local.hour * 3600) + (local.min * 60) + local.sec
    end

    # zone_timelocal: the instant whose wall clock in `zone` reads `local`
    # seconds. local_to_utc gives a Time (its instant counts) or anything
    # with to_i.
    def zone_utc_seconds(zone, local)
      return local - zone_offset_at(zone, local) unless zone.respond_to?(:local_to_utc)

      result = zone.local_to_utc(zone_tm(local))
      utc = result.is_a?(Integer) ? result : result.to_i
      raise ArgumentError, +"utc_offset out of range" if (local - utc).abs >= 86400

      utc
    end

    # utc_offset_arg: "Z" or a military letter, "UTC" in any case, or a
    # sign and two digits of hours, then minutes and seconds under 60,
    # with or without colons. A negative zero is UTC. nil for any other
    # text.
    def zone_offset(zone)
      return nil unless zone.encoding.ascii_compatible?

      text = zone.b
      case text.bytesize
      when 1
        letter = text.getbyte(0)
        return :utc if letter == 90
        return (letter - 64) * 3600 if letter >= 65 && letter <= 73
        return (letter - 65) * 3600 if letter >= 75 && letter <= 77
        return (77 - letter) * 3600 if letter >= 78 && letter <= 89

        return nil
      when 3
        return :utc if text.casecmp?("UTC")
      when 5 then min = 3
      when 6 then min = 4
      when 7 then min, sec = 3, 5
      when 9 then min, sec = 4, 7
      else return nil
      end
      return nil if min == 4 && text.getbyte(3) != 58
      return nil if sec == 7 && text.getbyte(6) != 58

      seconds = sec ? offset_digits(text, sec) : 0
      minutes = min ? offset_digits(text, min) : 0
      hours = offset_digits(text, 1)
      return nil if seconds.nil? || seconds >= 60 || minutes.nil? || minutes >= 60 || hours.nil?

      offset = (hours * 3600) + (minutes * 60) + seconds
      case text.getbyte(0)
      when 43 then offset
      when 45 then offset.zero? ? :utc : -offset
      end
    end

    # The number that the two ASCII digits at `i` spell, or nil.
    def offset_digits(text, i)
      high = text.getbyte(i)
      low = text.getbyte(i + 1)
      return nil unless high && high >= 48 && high <= 57 && low && low >= 48 && low <= 57

      ((high - 48) * 10) + low - 48
    end

    # `Time.new("2021-12-25 10:00:00 +09:00")`: CRuby's time_init_parse,
    # which reads only an ISO-8601-shaped string. A zone in the string
    # replaces the zone that the caller gave.
    def string_parts(str, zone, precision)
      raise ArgumentError, +"time string should have ASCII compatible encoding" unless str.encoding.ascii_compatible?
      raise ArgumentError, "can't parse: #{str.inspect}" if !str.empty? && (space?(str[0]) || space?(str[-1]))

      year, pos = year_part(str)
      parts = []
      if pos < str.size
        parts, pos = date_parts(str, pos, precision || str.size)
        found, pos = zone_part(str, pos)
        raise ArgumentError, "can't parse at: #{str[pos..]}" if pos < str.size
        raise ArgumentError, +"no time information" if found.empty? && parts.size < 5

        zone = found unless found.empty?
      end
      mon, mday, hour, min, sec = parts
      # time_init_parse checks each field's range before the fields
      # become a time.
      raise ArgumentError, +"mon out of range" if mon && !mon.between?(1, 12)
      raise ArgumentError, +"mday out of range" if mday && !mday.between?(1, 31)
      raise ArgumentError, +"hour out of range" if hour && hour > 24
      raise ArgumentError, +"min out of range" if min && min > 59
      raise ArgumentError, +"sec out of range" if sec && sec >= 61
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

      [Integer(str[0, start + digits], 10), start + digits]
    end

    # What follows the year: `-mm-dd`, then `hh:mm:ss` and a fraction.
    # CRuby stops at the first part that the string does not have, and
    # reads the rest as the zone, so each missing part ends this.
    def date_parts(str, pos, precision)
      return [[], pos] unless str[pos] == +"-"

      mon = two_digits(str, pos + 1, "mon")
      pos += 3
      return [[mon], pos] unless str[pos] == +"-"

      mday = two_digits(str, pos + 1, "mday")
      pos += 3
      return [[mon, mday], pos] unless (str[pos] == +" " || str[pos] == +"T") && digit?(str[pos + 1])

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
      return [[mon, mday, hour, min, sec], pos] unless str[pos] == +"."

      fraction, pos = subsecond(str, pos + 1, clock, precision)
      [[mon, mday, hour, min, sec + fraction], pos]
    end

    # Two digits and no third, as CRuby's two_digits reads them; the
    # refusal gives the part, then the text from its separator on.
    def two_digits(str, pos, name)
      unless digit?(str[pos]) && digit?(str[pos + 1]) && !digit?(str[pos + 2])
        after = " after '#{str[pos - 1]}'" if str[pos - 1] == +"-" || str[pos - 1] == +":"
        raise ArgumentError, "two digits #{name} is expected#{after}: #{str[pos - 1, 11]}"
      end

      Integer(str[pos, 2], 10)
    end

    # Only the second takes a fraction.
    def whole_part(str, pos, clock, name)
      raise ArgumentError, "fraction #{name} is not supported: #{str[clock, pos + 1 - clock]}" if str[pos] == +"."
    end

    def colon(str, pos, clock, name)
      raise ArgumentError, "missing #{name} part: #{str[clock, pos + 1 - clock]}" unless str[pos] == +":"
    end

    # The fraction after the second's dot, as a Rational of a second:
    # `precision` digits at most, and any digit past that is dropped.
    def subsecond(str, pos, clock, precision)
      digits = 0
      digits += 1 while digits < precision && digit?(str[pos + digits])
      raise ArgumentError, "subsecond expected after dot: #{str[clock, pos - clock + (str[pos].nil? ? 0 : 1)]}" if digits.zero?

      value = Integer(str[pos, digits], 10)
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

    def digit?(char) = !char.nil? && char >= +"0" && char <= +"9"

    # `(year, month, day, hour, min, sec, usec)`, or the ten fields
    # `Time#to_a` gives, which name the same instant backwards.
    def from_fields(args, zone)
      # time_arg: the ten fields of to_a, or one to eight.
      unless args.size == 10 || args.size.between?(1, 8)
        raise ArgumentError, wrong_arity(args.size, 1..8)
      end
      if args.size == 10
        sec, min, hour, day, month, year, _wday, _yday, dst = args
        return civil(year, month, day, hour, min, sec, zone, dst: dst ? true : false)
      end
      year, month, day, hour, min, sec, usec = args
      # time_arg: the seventh is microseconds only when there are seven;
      # of eight it is a zone, which is ignored. usec2subsecx reads a
      # String as decimal digits.
      usec = nil unless args.size == 7
      usec = Integer(usec, 10) if usec.is_a?(String)
      civil(year, month, day, hour, min, sec, zone, usec)
    end

    # This moment, and the kind a zone argument names: what `Time.now`
    # and a bare `Time.new` both seat.
    def now_parts(zone)
      needs!(zone, :utc_to_local)
      [Primitive.zr_clock_ns(Process.send(:clock_id, Process::CLOCK_REALTIME, "clock_gettime")), zone.nil? ? :local : parse_zone(zone)]
    end

    def civil(year, month, day, hour, min, sec, zone, usec = nil, dst: false)
      t = allocate
      t.send(:set, *civil_parts(year, month, day, hour, min, sec, zone, usec, dst:))
      t.send(:local_filled)
    end

    # The nanoseconds and the kind a civil date names, which the caller
    # seats in whichever Time it is filling.
    def civil_parts(year, month, day, hour, min, sec, zone, usec = nil, dst: false)
      # obj2vint: a String reads as decimal digits, anything else as to_int.
      year = year.is_a?(String) ? Integer(year, 10) : to_integer(year)
      month = month_arg(month)
      # time_arg reads each field into its bits, then validate_vtm checks
      # the values.
      day = day.nil? ? 1 : ubits(day, 5)
      hour = hour.nil? ? 0 : ubits(hour, 5)
      min = min.nil? ? 0 : ubits(min, 6)
      sec_ns = 0
      # obj2subsecx: any other object is read with num_exact.
      sec = exact_number(sec) unless sec.nil? || sec.is_a?(Integer) || sec.is_a?(Float) || sec.is_a?(Rational) || sec.is_a?(String)
      if sec.nil?
        sec = 0
      elsif sec.is_a?(Float) || sec.is_a?(Rational)
        sec_ns = exact_ns(sec - sec.floor, NS)
        sec = ubits(sec.floor, 6)
      else
        sec = ubits(sec, 6)
      end
      raise ArgumentError, +"mday out of range" if day < 1 || day > 31
      raise ArgumentError, +"hour out of range" if hour > 24
      raise ArgumentError, +"min out of range" if min > (hour == 24 ? 0 : 59)
      raise ArgumentError, +"sec out of range" if sec > (hour == 24 ? 0 : 60)

      unless usec.nil?
        raise ArgumentError, +"subsecx out of range" if usec < 0 || usec >= 1_000_000

        # time_arg: with microseconds given, the seconds' fraction is dropped.
        sec_ns = exact_ns(usec, 1000)
      end

      # time_init_vtm: :dst and :std name local time, and which of two
      # fitting offsets to take.
      if zone == :dst || zone == :std
        dst = zone == :dst
        zone = nil
      end
      days = days_from_civil(year, month, day)
      local_ns = ((days * 86400 + hour * 3600 + min * 60 + sec) * NS) + sec_ns
      kind = zone.nil? ? :local : parse_zone(zone)
      needs!(kind, :local_to_utc)
      case kind
      when :utc then [local_ns, :utc]
      when Integer, Rational then [local_ns - (kind * NS), kind]
      when :local then [local_ns - local_offset_for(local_ns.div(NS), dst) * NS, :local]
      else [(zone_utc_seconds(kind, local_ns.div(NS)) * NS) + (local_ns % NS), kind]
      end
    end

    def month_arg(month)
      return 1 if month.nil?

      # month_arg: anything with to_str reads as a String.
      month = String.try_convert(month) || month unless month.is_a?(Integer)
      if month.is_a?(String)
        index = MONTHS.index(month.downcase)
        return index + 1 if index

      end
      # obj2ubits: a String reads as decimal digits, anything else as
      # to_int.
      month = month.is_a?(String) ? Integer(month, 10) : implicit_integer(month)
      raise ArgumentError, +"mon out of range" if month < 1 || month > 12

      month
    end

    # num_exact: an Integer or a Rational from to_r, which an object must
    # also answer to_int to use; else what to_int gives.
    def exact_number(value)
      if value.respond_to?(:to_r)
        exact = value.to_r
        return exact if value.respond_to?(:to_int) && (exact.is_a?(Integer) || exact.is_a?(Rational))
      elsif value.respond_to?(:to_int)
        return implicit_integer(value)
      end
      raise TypeError, cant_convert(value, "an exact number")
    end

    # obj2ubits: a field that fits in `bits` bits, read from decimal
    # digits or from to_int.
    def ubits(value, bits)
      value = value.is_a?(String) ? Integer(value, 10) : implicit_integer(value)
      # NUM2INT: a long first, then an int.
      raise RangeError, +"bignum too big to convert into 'long'" if value.bit_length > 63
      raise RangeError, "integer #{value} too big to convert to 'int'" if value > 2_147_483_647
      raise RangeError, "integer #{value} too small to convert to 'int'" if value < -2_147_483_648
      raise ArgumentError, +"argument out of range" unless value >= 0 && value < (1 << bits)

      value
    end

    # The local offset for a calendar time `secs` (its fields read as
    # if UTC): the one whose zone gives that calendar time back; when
    # two do, or none does, the smaller offset. find_time_t takes the
    # daylight one of two that fit when `dst` (Time#to_a's isdst) is set.
    def local_offset_for(secs, dst = false)
      offsets = [secs - 86_400, secs, secs + 86_400].map { |at| zone_at(at)[0] }.uniq
      return offsets[0] if offsets.size == 1

      fitting = offsets.select { |offset| zone_at(secs - offset)[0] == offset }
      return fitting.max if dst && fitting.size > 1

      (fitting.empty? ? offsets : fitting).min
    end

    # The zone's offset, daylight flag and name at `secs`, as localtimew
    # finds them. On this platform rb_localtime_r works only for a time
    # that fits in an int, and guess_local_offset is used past that. No
    # zone kept daylight time before 1916, so an earlier time takes the
    # epoch's zone. A time past 2038 takes the zone of the year before
    # 2038 whose month starts on the same day of the week.
    def zone_at(secs)
      return Primitive.zr_time_local(secs) if secs >= -0x8000_0000 && secs <= 0x7fff_ffff

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
    raise TypeError, +"already initialized Time" if Primitive.zr_hidden_get(self, :__built__)

    if zone
      raise ArgumentError, +"timezone argument given as positional and keyword arguments" if Primitive.arg!(:in)
    else
      zone = Primitive.arg!(:in)
    end
    # The receiver's class parses the zone, so its find_timezone names one.
    return set(*self.class.send(:now_parts, zone)) if now

    text = str && String.try_convert(str)
    if text
      # NUM2SIZET: nil reads every digit, a Float truncates, and a negative
      # count wraps to no limit.
      digits = precision.nil? ? nil : Primitive.zr_index_operand_m(precision)
      digits = nil if digits&.negative?
      return set(*self.class.send(:string_parts, text, zone, digits)).send(:local_filled)
    end

    set(*self.class.send(:civil_parts, year, mon, mday, hour, min, sec, zone)).send(:local_filled)
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
    when Integer, Rational then kind
    else local_offset
    end
  end

  alias gmt_offset utc_offset
  alias gmtoff utc_offset

  # A zone name contains no character above ASCII, and ruby returns it
  # in the encoding that says so.
  def zone
    case kind
    when :utc then (+"UTC").force_encoding(Encoding::US_ASCII)
    else local_zone
    end
  end

  # zone_set_dst: a timezone object answers through its own dst?, which
  # takes the time in UTC; one without dst? is never daylight time.
  def dst?
    zone = kind
    return local_dst if zone == :local
    return false unless Time.send(:zone_object?, zone) && zone.respond_to?(:dst?)

    zone.dst?(Time.send(:zone_tm, ns.div(NS))) ? true : false
  end
  alias isdst dst?

  def to_a = [sec, min, hour, day, month, year, wday, yday, dst?, zone]

  def sunday? = wday == 0
  def monday? = wday == 1
  def tuesday? = wday == 2
  def wednesday? = wday == 3
  def thursday? = wday == 4
  def friday? = wday == 5
  def saturday? = wday == 6

  # time_gmtime: a Time that is already UTC is returned as it is,
  # before the frozen check.
  def utc
    return self if kind == :utc

    set(ns, :utc)
    self
  end

  alias gmtime utc

  def getutc = dup.utc
  alias getgm getutc

  # time_localtime returns a local Time as it is; with a zone,
  # time_zonelocal changes it, and a frozen one refuses.
  def localtime(zone = nil)
    return local_filled if zone.nil? && kind == :local

    kind = zone.nil? ? :local : self.class.send(:parse_zone, zone)
    Time.send(:needs!, kind, :utc_to_local)
    set(ns, kind)
    kind == :local ? local_filled : self
  end

  def getlocal(zone = nil) = dup.localtime(zone)

  def +(other)
    raise TypeError, +"time + time?" if other.is_a?(Time)

    shifted(ns + Time.send(:exact_ns, other, NS))
  end

  def -(other)
    return float_seconds(ns - other.send(:ns)) if other.is_a?(Time)

    shifted(ns - Time.send(:exact_ns, other, NS))
  end

  # rb_invcmp: a value that is no Time answers `other <=> self`, turned
  # around.
  def <=>(other)
    unless other.is_a?(Time)
      # rb_invcmp, a Numeric too: its <=> asks this Time for coerce.
      return nil unless other.respond_to?(:<=>)
      # invcmp_recursive: a value whose <=> asks this Time again gets nil.
      return nil if Primitive.zr_recursive_enter(self, :<=>)

      begin
        cmp = other <=> self
      ensure
        Primitive.zr_recursive_leave(self, :<=>)
      end
      return nil if cmp.nil?
      return -1 if cmp > 0

      return cmp < 0 ? 1 : 0
    end

    theirs = other.send(:ns)
    ns < theirs ? -1 : (ns > theirs ? 1 : 0)
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
    "#{text} #{utc? ? 'UTC' : offset_shown}".force_encoding(Encoding::US_ASCII)
  end

  # US-ASCII, as time_to_s writes it and time_inspect writes `inspect`.
  def to_s
    (utc? ? strftime("%Y-%m-%d %H:%M:%S UTC") : strftime("%Y-%m-%d %H:%M:%S %z")).force_encoding(Encoding::US_ASCII)
  end

  def ctime = strftime("%a %b %e %H:%M:%S %Y").force_encoding(Encoding::US_ASCII)
  alias asctime ctime

  # ISO 8601: `Z` for UTC, the offset otherwise, and `digits` places of
  # the fraction when requested.
  # Past nine digits the fraction comes from the exact subsecond, as
  # time_xmlschema writes it.
  def iso8601(digits = 0)
    text = strftime("%Y-%m-%dT%H:%M:%S")
    if digits > 9
      places = digits.to_i
      text = "#{text}.#{(subsec * (10**places)).floor.to_s.rjust(places, '0')}"
    elsif digits > 0
      text = "#{text}.#{format("%09d", nsec)[0, digits]}"
    end
    "#{text}#{utc? ? 'Z' : strftime('%:z')}".force_encoding(Encoding::US_ASCII)
  end
  alias xmlschema iso8601

  def deconstruct_keys(keys)
    raise TypeError, "wrong argument type #{keys.class} (expected Array or nil)" unless keys.nil? || keys.is_a?(Array)

    all = { year: year, month: month, day: day, yday: yday, wday: wday,
            hour: hour, min: min, sec: sec, subsec: subsec, dst: dst?, zone: zone }
    return all if keys.nil?

    all.slice(*keys)
  end

  # time_strftime: the format's directives rendered in its encoding.
  def strftime(format)
    built!
    format = Primitive.zr_str_operand(format)
    raise ArgumentError, +"format should have ASCII compatible encoding" unless format.encoding.ascii_compatible?

    if format.empty?
      Primitive.zr_warn_here_m("strftime called with empty format string") if $VERBOSE
      return String.new(encoding: format.encoding)
    end
    # The result's encoding: the format's, or the one a zone name moves
    # it to (see zone_word).
    box = [format.encoding]
    text = rendered(format.b, box) or raise ArgumentError, "invalid format: #{format}"
    text.force_encoding(box[0])
  end

  private

  # A copy takes the instant of its source Time, so a Time with no
  # instant cannot be copied, and one that already has an instant
  # cannot take another.
  def initialize_copy(other)
    raise TypeError, +"already initialized Time" if Primitive.zr_hidden_get(self, :__built__)
    raise TypeError, +"uninitialized Time" unless Primitive.zr_hidden_get(other, :__built__)

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
    local_filled
    Primitive.zr_hidden_get(self, :__offset__)
  end

  def local_dst
    Primitive.attr! :hidden
    local_filled
    Primitive.zr_hidden_get(self, :__dst__)
  end

  def local_zone
    Primitive.attr! :hidden
    local_filled
    Primitive.zr_hidden_get(self, :__zone__)
  end

  # A local Time from `now`, `at` or arithmetic finds its offset and zone
  # name when one is first read (tm_got), with the TZ of that moment. The
  # fill is a memo, so a frozen Time fills too.
  def local_filled
    Primitive.attr! :hidden
    return self unless Primitive.zr_hidden_get(self, :__offset__).nil? && kind == :local

    offset, dst, name = Time.send(:zone_at, ns.div(NS))
    Primitive.zr_state_set(self, :__offset__, offset)
    Primitive.zr_state_set(self, :__dst__, dst)
    Primitive.zr_state_set(self, :__zone__, name&.dup&.force_encoding(Encoding::US_ASCII))
    self
  end

  # `to_s` shows an offset as hours and minutes; `inspect` shows the
  # seconds of an offset that has them, run together, as time.c does.
  def offset_shown
    Primitive.attr! :hidden
    return strftime("%z") if utc_offset % 60 == 0

    offset = utc_offset
    sign = offset < 0 ? +"-" : +"+"
    offset = offset.abs.round
    format("%s%02d%02d%02d", sign, offset / 3600, (offset % 3600) / 60, offset % 60)
  end

  # A Time that no constructor filled has no instant, and every reader
  # raises an error that says so, as in ruby.
  def built!
    Primitive.attr! :hidden
    raise TypeError, +"uninitialized Time" unless Primitive.zr_hidden_get(self, :__built__)
  end

  def set(at, of_kind)
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :__built__, true)
    Primitive.zr_hidden_set(self, :__ns__, Time.send(:canonical, at))
    Primitive.zr_hidden_set(self, :__kind__, of_kind)
    Primitive.zr_hidden_set(self, :__fields__, nil)
    if Time.send(:zone_object?, of_kind)
      # zone_localtime: the object gives the offset; `zone` is the object.
      Primitive.zr_hidden_set(self, :__offset__, Time.send(:zone_offset_at, of_kind, at.div(NS)))
      Primitive.zr_hidden_set(self, :__dst__, false)
      Primitive.zr_hidden_set(self, :__zone__, of_kind)
    else
      Primitive.zr_hidden_set(self, :__offset__, nil)
      Primitive.zr_hidden_set(self, :__dst__, false)
      Primitive.zr_hidden_set(self, :__zone__, nil)
    end
    self
  end

  # A new Time, never the subclass, with the same kind of zone (+, -,
  # round, floor, ceil).
  # strftime's %Z for a zone that is no name: the timezone object's
  # abbr, else its name, else the object as text.
  def zone_abbreviation
    Primitive.attr! :hidden
    shown = zone
    return shown.to_s if shown.nil? || shown.is_a?(String)
    return shown.abbr(TM.from_time(self)).to_s if shown.respond_to?(:abbr)

    shown.respond_to?(:name) ? shown.name.to_s : shown.to_s
  end

  # TZMODE_COPY: a fixed offset keeps its zone name too.
  def shifted(at)
    Primitive.attr! :hidden
    t = Time.allocate
    t.send(:set, at, kind)
    if kind.is_a?(Integer) || kind.is_a?(Rational)
      Primitive.zr_hidden_set(t, :__zone__, Primitive.zr_hidden_get(self, :__zone__))
    end
    t
  end

  def rounded(digits)
    Primitive.attr! :hidden
    raise ArgumentError, +"negative ndigits given" if digits < 0

    unit = 10**(9 - digits)
    shifted(yield(ns, unit))
  end

  # year, month, day, hour, min, sec, wday, yday in the shown zone.
  def fields
    Primitive.attr! :hidden
    held = Primitive.zr_hidden_get(self, :__fields__)
    return held if held

    secs = (ns + (utc_offset * NS)).div(NS)
    days = secs.div(86400)
    rem = secs - days * 86400
    y, m, d = Time.send(:civil_from_days, days)
    row = [y, m, d, rem / 3600, (rem % 3600) / 60, rem % 60, (days + 4) % 7,
           days - Time.send(:days_from_civil, y, 1, 1) + 1]
    # The row is a memo and not the Time's value: a frozen Time still
    # reads its fields, as CRuby's fills `tm` in a frozen one.
    Primitive.zr_state_set(self, :__fields__, row)
    row
  end

  # strftime.c's rb_strftime_with_timespec: the bytes of `format` with
  # each directive rendered, or nil when a directive runs off its end.
  # `box` holds the result's encoding.
  def rendered(format, box = nil)
    Primitive.attr! :hidden
    out = "".b
    at = 0
    while at < format.bytesize
      percent = format.byteindex("%", at) || format.bytesize
      out << format.byteslice(at, percent - at)
      break if percent == format.bytesize

      at = directive(format, percent, out, box)
    end
    out if at <= format.bytesize
  end

  # One directive, from the `%` at `from`: flags, a width and colons,
  # each only where strftime.c accepts it, then the conversion. Returns
  # the position where the format continues. Text that is not a
  # directive is copied as it is written. A directive that runs off the
  # end returns a position past it.
  def directive(format, from, out, box = nil)
    Primitive.attr! :hidden
    width = -1
    padding = nil
    left = upper = swap = false
    colons = 0
    at = from
    loop do
      at += 1
      c = format.byteslice(at)
      case c
      when "-", "^", "#", "_"
        return verbatim(format, from, at, out) if width > 0

        case c
        when "-"
          left = true
          padding = nil
          width = 0
        when "^" then upper = true
        when "#" then swap = true
        else padding = +" "
        end
      when "0".."9"
        padding = +"0" if c == +"0"
        digits = format.byteslice(at, format.bytesize - at)[/\A\d+/]
        return verbatim(format, from, at, out) if digits.to_i > INT_MAX

        width = digits.to_i
        at += digits.bytesize - 1
      when ":"
        colons = 1
        colons += 1 while colons <= 3 && format.byteslice(at + colons) == +":"
        return verbatim(format, from, at, out) if colons <= 3 && format.byteslice(at + colons) != +"z"

        at += colons - 1
      when "E", "O"
        modified = format.byteslice(at + 1)
        return verbatim(format, from, at, out) unless modified && (c == +"E" ? "cCxXyY" : "deHkIlmMSuUVwWy").include?(modified)
      else
        break
      end
    end
    c = format.byteslice(at)
    case c
    when "%" then put_word(out, "%", width, padding, left)
    when "n" then put_word(out, "\n", width, padding, left)
    when "t" then put_word(out, "\t", width, padding, left)
    when "a" then put_word(out, DAY_NAMES[wday][0, 3], width, padding, left, (:up if upper || swap))
    when "A" then put_word(out, DAY_NAMES[wday], width, padding, left, (:up if upper || swap))
    when "b", "h" then put_word(out, MONTH_NAMES[month - 1][0, 3], width, padding, left, (:up if upper || swap))
    when "B" then put_word(out, MONTH_NAMES[month - 1], width, padding, left, (:up if upper || swap))
    when "p" then put_word(out, hour < 12 ? "AM" : "PM", width, padding, left, swap ? :down : (:up if upper))
    when "P" then put_word(out, hour < 12 ? "AM" : "PM", width, padding, left, upper ? :up : (:down unless swap))
    when "Z" then put_word(out, utc? ? "UTC" : zone_word(out, zone_abbreviation, box), width, padding, left, swap ? :down : (:up if upper))
    when "d" then put_number(out, day, "0", 2, width, padding, left)
    when "e" then put_number(out, day, " ", 2, width, padding, left)
    when "H" then put_number(out, hour, "0", 2, width, padding, left)
    when "k" then put_number(out, hour, " ", 2, width, padding, left)
    when "I" then put_number(out, (hour + 11) % 12 + 1, "0", 2, width, padding, left)
    when "l" then put_number(out, (hour + 11) % 12 + 1, " ", 2, width, padding, left)
    when "j" then put_number(out, yday, "0", 3, width, padding, left)
    when "m" then put_number(out, month, "0", 2, width, padding, left)
    when "M" then put_number(out, min, "0", 2, width, padding, left)
    when "S" then put_number(out, sec, "0", 2, width, padding, left)
    when "s" then put_number(out, to_i, "0", 1, width, padding, left)
    when "U" then put_number(out, (yday - 1 + 7 - wday) / 7, "0", 2, width, padding, left)
    when "W" then put_number(out, (yday - 1 + 7 - (wday + 6) % 7) / 7, "0", 2, width, padding, left)
    when "w" then put_number(out, wday, "0", 1, width, padding, left)
    when "u" then put_number(out, wday.zero? ? 7 : wday, "0", 1, width, padding, left)
    when "V" then put_number(out, iso_week[1], "0", 2, width, padding, left)
    when "Y" then put_number(out, year, "0", year.negative? && Primitive.zr_fixnum_p_m(year) ? 5 : 4, width, padding, left)
    when "G" then put_number(out, iso_week[0], "0", iso_week[0].negative? && Primitive.zr_fixnum_p_m(iso_week[0]) ? 5 : 4, width, padding, left)
    when "C" then put_number(out, year.div(100), "0", 2, width, padding, left)
    when "y" then put_number(out, year % 100, "0", 2, width, padding, left)
    when "g" then put_number(out, iso_week[0] % 100, "0", 2, width, padding, left)
    when "L", "N"
      width = c == +"L" ? 3 : 9 if width <= 0
      out << ((ns % NS) * 10**width).div(NS).to_s.rjust(width, "0")
    when "z"
      return verbatim(format, from, at - 1, out) if colons > 3

      put_offset(out, colons, width, padding, left)
    when "c", "x", "X", "D", "r", "R", "T", "v", "F"
      put_compound(out, COMPOUNDS.fetch(c), width, padding, upper, box)
    else
      return verbatim(format, from, at, out)
    end
    at + 1
  end

  # Text that is not a directive, from its `%` through `to`, as it is
  # written.
  def verbatim(format, from, to, out)
    Primitive.attr! :hidden
    out << format.byteslice(from, to - from + 1)
    to + 1
  end

  # FILL_PADDING and case_conv: a word right-aligned in `width`, unless
  # `-` leaves it bare.
  def put_word(out, word, width, padding, left, casing = nil)
    Primitive.attr! :hidden
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
  # another; `-` leaves it bare. A zero pad goes after the sign of a
  # fixnum, as printf puts it, and before the sign of a bignum.
  def put_number(out, value, pad, least, width, padding, left)
    Primitive.attr! :hidden
    width = left ? 1 : width <= 0 ? least : width
    text = value.to_s
    return out << text if text.bytesize >= width

    fill = padding || pad
    if fill == +"0" && value.negative? && Primitive.zr_fixnum_p_m(value)
      out << "-" << text.delete_prefix("-").rjust(width - 1, "0")
    else
      out << text.rjust(width, fill)
    end
  end

  # `%Z`'s name in the result (#22416): the result takes the encoding that
  # it and the name are compatible in, when that one is ASCII compatible;
  # else the name converts to the result's encoding, a character that
  # does not convert replaced.
  def zone_word(out, word, box)
    Primitive.attr! :hidden
    return word if box.nil?

    compat = Encoding.compatible?(out.dup.force_encoding(box[0]), word)
    if compat&.ascii_compatible?
      box[0] = compat
      return word.b
    end
    word.encode(box[0], invalid: :replace, undef: :replace).b
  end

  # STRFTIME: a directive that represents a format of other directives,
  # upcased by `^` and right-aligned in `width`.
  def put_compound(out, format, width, padding, upper, box = nil)
    Primitive.attr! :hidden
    text = rendered(format, box)
    text.upcase! if upper
    out << (padding || " ") * (width - text.bytesize) if width > text.bytesize
    out << text
  end

  # `%z`: the offset as hours and minutes, `:` between them and then the
  # seconds for each colon, or as few parts as lose nothing for three.
  # The width counts past the sign and the minutes. A UTC time with `-`
  # shows its offset as `-0000`.
  def put_offset(out, colons, width, padding, left)
    Primitive.attr! :hidden
    off = utc? ? 0 : utc_offset.round
    negative = off.negative? || (utc? && left)
    off = off.abs
    tail = case colons
           when 0 then 3
           when 1 then 4
           when 2 then 7
           else off % 3600 == 0 ? 1 : off % 60 == 0 ? 4 : 7
           end
    digits = width <= tail + 2 ? 2 : width - tail
    sign = negative ? "-" : "+"
    hours = (off / 3600).to_s
    out << (padding == +" " ? (sign + hours).rjust(digits + 1) : sign + hours.rjust(digits, "0"))
    off %= 3600
    return if colons == 3 && off.zero?

    out << ":" if colons >= 1
    out << format("%02d", off / 60)
    off %= 60
    return if colons == 3 && off.zero?

    out << ":" << format("%02d", off) if colons >= 2
  end

  # A count of nanoseconds as a Float of seconds, divided as CRuby
  # divides it: a whole count by the Float scale, a fraction exactly.
  def float_seconds(count)
    Primitive.attr! :hidden
    count.is_a?(Rational) ? (count / NS).to_f : count / 1e9
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
      Primitive.attr! :hidden
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
    # rb_copy_generic_ivar: the Time's own ivars go on the payload first.
    instance_variables.each { |name| out.instance_variable_set(name, instance_variable_get(name)) }
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
    # A timezone object is written by its name, as time_mdump does.
    shown = zone
    shown = shown.name.to_s unless shown.nil? || shown.is_a?(String)
    Marshal.send(:extra_set, out, :zone, shown)
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
    raise TypeError, +"marshaled time format differ" if text.nil? || text.bytesize < 8

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
    unless ((word >> 30) & 1) == 1
      # time_mload keeps an offset that validate_utc_offset takes and a
      # zone that is a C string; it drops anything else.
      offset = extras[:offset]
      offset = nil unless offset.is_a?(Numeric) && offset > -86_400 && offset < 86_400
      name = extras[:zone]
      name = nil unless name.is_a?(String) && !name.include?("\0")
      # With no offset the time is plain local time, whose zone the TZ
      # names.
      offset.nil? ? moment.localtime : moment.localtime(offset)
      # A class that finds zones by name rebuilds the zone object. A name
      # it does not know stays a String, as mload_zone rescues it.
      found = begin
        find_timezone(name) if name && respond_to?(:find_timezone)
      rescue StandardError
        nil
      end
      if found && zone_object?(found)
        moment.localtime(found)
      elsif name && offset
        # The zone name that was dumped stays, as time_mload sets it.
        Primitive.zr_hidden_set(moment, :__zone__, (+name).force_encoding(Encoding::US_ASCII))
      end
    end
    text.instance_variables.each { |name| moment.instance_variable_set(name, text.instance_variable_get(name)) }
    moment
  end

  private_class_method :_load

  # The year the tail names: its distance below 1900, or above the
  # highest year the word can hold.
  def self.extended_year(year, tail)
    Primitive.attr! :hidden
    size, rest = Marshal.send(:read_long_bytes, tail)
    raise TypeError, +"marshaled time format differ" if size < 0 || size > rest.bytesize

    away = (0...size).sum { |i| rest.getbyte(i) << (8 * i) }
    year == 1900 ? year - away : year + away
  end
  private_class_method :extended_year

  # The nanoseconds under a microsecond: the exact pair when the dump
  # contains one, else the digits that ruby 1.9.1 wrote.
  def self.sub_nanoseconds(extras)
    Primitive.attr! :hidden
    return Rational(extras[:nano_num], extras[:nano_den] || 1) if extras[:nano_num]

    digits = extras[:submicro]
    return 0 if digits.nil? || digits.empty?

    (digits.getbyte(0) >> 4) * 100 + (digits.getbyte(0) & 0xf) * 10 + (digits.getbyte(1).to_i >> 4)
  end
  private_class_method :sub_nanoseconds
end

class Time
  # Time::tm (Init_tm): the time that the methods of a timezone object
  # get, an Object, not a Time, that answers as a Time does through the
  # one it keeps. `from_time` keeps a UTC time with no subsecond, as
  # tm_from_time does. `new` keeps the instant of Time.utc of its fields
  # but answers in local time, as tm_initialize's time does; +, - and
  # #utc keep that zone.
  tm = Class.new do
    class << self
      def from_time(time)
        raise TypeError, "wrong argument type #{Primitive.zr_real_class(time)} (expected time)" unless time.is_a?(Time)

        kept(Time.at(time.to_i).utc)
      end

      private

      def kept(time)
        Primitive.attr! :hidden
        tm = allocate
        Primitive.zr_hidden_set(tm, :__time__, time)
        tm
      end
    end

    def initialize(*fields)
      raise ArgumentError, "wrong number of arguments (given #{fields.size}, expected 1..7)" unless fields.size.between?(1, 7)

      Primitive.zr_hidden_set(self, :__time__, Time.utc(*fields.first(6)).localtime)
    end

    %i[sec min hour mday day mon month year isdst dst? zone gmtoff gmt_offset utc_offset utc? gmt? to_s inspect to_a
       tv_sec tv_usec usec tv_nsec nsec subsec to_i to_f to_r].each do |name|
      define_method(name) { time.public_send(name) }
    end

    # time_add0 takes only a number, never a Time.
    def +(offset) = self.class.send(:kept, time + exact(offset))
    def -(offset) = self.class.send(:kept, time - exact(offset))

    # tm_to_time: a Time with this one's instant and zone.
    def utc = time.dup
    alias_method :to_time, :utc

    private

    def time
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__time__) || raise(TypeError, "uninitialized #{self.class}")
    end

    def exact(offset)
      Primitive.attr! :hidden
      raise TypeError, "can't convert #{Primitive.zr_real_class(offset)} into an exact number" if offset.is_a?(Time) || offset.is_a?(TM)

      offset
    end
  end
  # The class takes its name from the first constant: Time::tm.
  Primitive.zr_const_set_m(self, :tm, tm)
  TM = tm
  private_constant :TM
end
