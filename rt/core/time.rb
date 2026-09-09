# A Time is nanoseconds since the epoch, kept in UTC, plus the zone it
# shows itself in: UTC, a fixed offset, or the local zone libSystem
# describes. Civil dates come from the proleptic Gregorian calendar
# through the days-from-civil algorithm.
class Time
  include Comparable

  NS = 1_000_000_000
  MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze
  MONTH_NAMES = %w[January February March April May June July August September October November December].freeze
  DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  private_constant :NS, :MONTHS, :MONTH_NAMES, :DAY_NAMES

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

    def new(year = nil, month = nil, day = nil, hour = nil, min = nil, sec = nil, zone = nil, **options)
      option = options[:in]
      raise ArgumentError, "timezone argument given as positional and keyword arguments" if zone && option

      return now(**options) if year.nil?
      return Primitive.zr_unimplemented("Time.new with a string") if year.is_a?(String)

      civil(year, month, day, hour, min, sec, zone || option)
    end

    def utc(year, month = nil, day = nil, hour = nil, min = nil, sec = nil, *rest)
      civil(year, month, day, hour, min, sec, :utc)
    end

    alias gm utc

    def local(year, month = nil, day = nil, hour = nil, min = nil, sec = nil, *rest)
      civil(year, month, day, hour, min, sec, nil)
    end

    alias mktime local

    private

    def at_ns(ns, zone)
      t = allocate
      t.send(:set, ns, zone.nil? ? :local : parse_zone(zone))
      t
    end

    # A count of `scale` nanoseconds each, as nanoseconds: a Float
    # counts by its exact binary value, rounded down.
    def exact_ns(value, scale)
      case value
      when Integer then value * scale
      when Float then float_ns(value, scale)
      else raise TypeError, "can't convert #{value.class} into an exact number"
      end
    end

    # floor(value * scale) for a Float, computed on the two 30-bit
    # halves of its fraction so no step rounds.
    def float_ns(value, scale)
      whole = value.floor
      fraction = value - whole
      high = (fraction * 1_073_741_824).floor
      low = ((fraction * 1_073_741_824 - high) * 1_073_741_824).floor
      a = high * scale
      b = low * scale
      whole * scale + (a >> 30) + ((((a & 1_073_741_823) << 30) + b) >> 60)
    end

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
        raise ArgumentError, "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: #{zone}"
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

    def civil(year, month, day, hour, min, sec, zone)
      year = Integer(year)
      month = month_arg(month)
      day = int_arg(day, 1, 1, 31, "mday")
      hour = int_arg(hour, 0, 0, 24, "hour")
      min = int_arg(min, 0, 0, 59, "min")
      sec_ns = 0
      if sec.nil?
        sec = 0
      elsif sec.is_a?(Float)
        raise ArgumentError, "sec out of range" if sec < 0 || sec >= 61

        sec_ns = float_ns(sec - sec.floor, NS)
        sec = sec.floor
      elsif sec.is_a?(Rational)
        raise ArgumentError, "sec out of range" if sec < 0 || sec >= 61

        sec_ns = ((sec - sec.floor) * NS).floor
        sec = sec.floor
      else
        sec = int_arg(sec, 0, 0, 60, "sec")
      end
      raise ArgumentError, "argument out of range" if hour == 24 && (min != 0 || sec != 0)

      days = days_from_civil(year, month, day)
      local_ns = ((days * 86400 + hour * 3600 + min * 60 + sec) * NS) + sec_ns
      kind = zone.nil? ? :local : parse_zone(zone)
      t = allocate
      case kind
      when :utc then t.send(:set, local_ns, :utc)
      when Integer then t.send(:set, local_ns - kind * NS, kind)
      else t.send(:set, local_ns - local_offset_for(local_ns / NS) * NS, :local)
      end
      t
    end

    def month_arg(month)
      return 1 if month.nil?

      if month.is_a?(String)
        index = MONTHS.index(month.downcase)
        return index + 1 if index

        month = Integer(month)
      end
      raise ArgumentError, "mon out of range" if month < 1 || month > 12

      month
    end

    def int_arg(value, default, low, high, name)
      return default if value.nil?

      value = Integer(value) unless value.is_a?(Integer)
      raise ArgumentError, "#{name} out of range" if value < low || value > high

      value
    end

    # The local offset for a calendar time `secs` (its fields read as
    # if UTC): the one whose zone gives that calendar time back; when
    # two do, or none does, the smaller offset.
    def local_offset_for(secs)
      offsets = [secs - 86_400, secs, secs + 86_400].map { |at| Primitive.zr_time_local(at)[0] }.uniq
      return offsets[0] if offsets.size == 1

      fitting = offsets.select { |offset| Primitive.zr_time_local(secs - offset)[0] == offset }
      (fitting.empty? ? offsets : fitting).min
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

  def usec = (@ns % NS) / 1000
  alias tv_usec usec
  def nsec = @ns % NS
  alias tv_nsec nsec
  # The fraction of a second: 0 on a whole second, else a Rational.
  def subsec
    rest = @ns % NS
    rest.zero? ? 0 : Rational(rest, NS)
  end

  def to_i = @ns.div(NS)
  alias tv_sec to_i
  def to_f = @ns.to_f / NS
  def to_r = Rational(@ns, NS)

  def utc? = @kind == :utc
  alias gmt? utc?

  def utc_offset
    case @kind
    when :utc then 0
    when :local then @offset
    else @kind
    end
  end

  alias gmt_offset utc_offset
  alias gmtoff utc_offset

  def zone
    case @kind
    when :utc then "UTC"
    when :local then @zone
    end
  end

  def dst? = @kind == :local && @dst
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
    set(@ns, :utc)
    self
  end

  alias gmtime utc

  def getutc = dup.utc
  alias getgm getutc

  def localtime(zone = nil)
    set(@ns, zone.nil? ? :local : Time.send(:parse_zone, zone))
    self
  end

  def getlocal(zone = nil) = dup.localtime(zone)

  def +(other)
    raise TypeError, "time + time?" if other.is_a?(Time)

    shifted(@ns + Time.send(:exact_ns, other, NS))
  end

  def -(other)
    return (@ns - other.instance_variable_get(:@ns)).to_f / NS if other.is_a?(Time)

    shifted(@ns - Time.send(:exact_ns, other, NS))
  end

  def <=>(other)
    return nil unless other.is_a?(Time)

    @ns <=> other.instance_variable_get(:@ns)
  end

  def eql?(other) = other.is_a?(Time) && @ns == other.instance_variable_get(:@ns)

  def hash = @ns.hash

  def round(digits = 0) = rounded(digits) { |ns, unit| (ns + unit / 2).div(unit) * unit }

  def floor(digits = 0) = rounded(digits) { |ns, unit| ns.div(unit) * unit }

  def ceil(digits = 0) = rounded(digits) { |ns, unit| -(-ns).div(unit) * unit }

  def inspect
    text = strftime("%Y-%m-%d %H:%M:%S")
    fraction = nsec
    unless fraction == 0
      digits = format("%09d", fraction)
      digits = digits[0, digits.size - 1] while digits.end_with?("0")
      text = "#{text}.#{digits}"
    end
    "#{text} #{utc? ? 'UTC' : strftime('%z')}"
  end

  def to_s
    utc? ? strftime("%Y-%m-%d %H:%M:%S UTC") : strftime("%Y-%m-%d %H:%M:%S %z")
  end

  def ctime = strftime("%a %b %e %H:%M:%S %Y")
  alias asctime ctime

  def strftime(pattern)
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

  # The hidden `__built__` mark stays behind on a copy, so only a Time
  # built by `set` refuses.
  def initialize_copy(other)
    raise TypeError, "already initialized Time" if Primitive.zr_hidden_get(self, :__built__)

    super
    Primitive.zr_hidden_set(self, :__built__, true)
  end

  def set(ns, kind)
    Primitive.zr_hidden_set(self, :__built__, true)
    @ns = ns
    @kind = kind
    @fields = nil
    if kind == :local
      @offset, @dst, @zone = Primitive.zr_time_local(ns.div(NS))
    else
      @offset = nil
      @dst = false
      @zone = nil
    end
  end

  def shifted(ns)
    t = dup
    t.send(:set, ns, @kind)
    t
  end

  def rounded(digits)
    raise ArgumentError, "negative ndigits given" if digits < 0
    return dup if digits >= 9

    unit = 10**(9 - digits)
    shifted(yield(@ns, unit))
  end

  # year, month, day, hour, min, sec, wday, yday in the shown zone.
  def fields
    Primitive.attr! :hidden
    @fields ||= begin
      secs = @ns.div(NS) + utc_offset
      days = secs.div(86400)
      rem = secs - days * 86400
      y, m, d = Time.send(:civil_from_days, days)
      [y, m, d, rem / 3600, (rem % 3600) / 60, rem % 60, (days + 4) % 7, days - Time.send(:days_from_civil, y, 1, 1) + 1]
    end
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

  def fraction(flags, width)
    Primitive.attr! :hidden
    digits = format("%09d", nsec)
    width <= 9 ? digits[0, width] : digits + "0" * (width - 9)
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
