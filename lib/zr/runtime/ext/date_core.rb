# frozen_string_literal: true

# date_core, the C half of date 3.5.1, in Ruby. ruby's own date.rb
# requires it, then adds Date::VERSION, Date::Infinity and #infinite?.
#
# Date and DateTime keep a chronological Julian day number, a second of
# that day and a nanosecond, all in UTC, with the offset and the day the
# Gregorian calendar starts kept next to them. Every conversion is exact
# integer arithmetic, so a date contains no float and never drifts.

class Date
  include Comparable

  ITALY = 2299161
  ENGLAND = 2361222
  JULIAN = Float::INFINITY
  GREGORIAN = -Float::INFINITY

  # date_core.c makes the names US-ASCII.
  us_ascii = ->(names) { names.map { |name| name&.dup&.force_encoding(Encoding::US_ASCII)&.freeze }.freeze }
  MONTHNAMES = [nil, "January", "February", "March", "April", "May", "June",
                "July", "August", "September", "October", "November", "December"].then(&us_ascii)
  DAYNAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].then(&us_ascii)
  ABBR_MONTHNAMES = [nil, "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].then(&us_ascii)
  ABBR_DAYNAMES = %w[Sun Mon Tue Wed Thu Fri Sat].then(&us_ascii)

  DAY = 86_400
  NANOSECOND = 1_000_000_000
  # The first and the last day a calendar reform can start on.
  REFORM_BEGIN_JD = 2_298_874
  REFORM_END_JD = 2_426_355
  private_constant :DAY, :NANOSECOND, :REFORM_BEGIN_JD, :REFORM_END_JD

  class Error < ArgumentError; end

  class << self
    # The Julian day number of a civil date, with no validity check.
    def civil_jd(year, month, day, start)
      Primitive.attr! :hidden
      if month <= 2
        year -= 1
        month += 12
      end
      century = year / 100
      leap = 2 - century + (century / 4)
      jd = ((1461 * (year + 4716)) / 4) + ((306_001 * (month + 1)) / 10_000) + day + leap - 1524
      jd < start ? jd - leap : jd
    end

    # The year, month and day a Julian day number names.
    def jd_civil(jd, start)
      Primitive.attr! :hidden
      if jd < start
        a = jd
      else
        shift = ((4 * jd) - 7_468_865) / 146_097
        a = jd + 1 + shift - (shift / 4)
      end
      b = a + 1524
      c = ((20 * b) - 2442) / 7305
      d = (1461 * c) / 4
      e = (10_000 * (b - d)) / 306_001
      day = b - d - ((306_001 * e) / 10_000)
      e <= 13 ? [c - 4716, e - 1, day] : [c - 4715, e - 13, day]
    end

    # The Julian day number of a valid civil date, or nil. A negative
    # month or day counts back from the end of the year or the month.
    def valid_civil_jd(year, month, day, start)
      Primitive.attr! :hidden
      month += 13 if month.negative?
      return nil unless (1..12).cover?(month)

      if day.negative?
        last = last_day_jd(year, month, start) or return nil
        y2, m2, day = jd_civil(last + day + 1, start)
        return nil unless y2 == year && m2 == month
      end
      jd = civil_jd(year, month, day, start)
      jd_civil(jd, start) == [year, month, day] ? jd : nil
    end

    # The last day of a month, which the Gregorian reform can shorten.
    def last_day_jd(year, month, start)
      Primitive.attr! :hidden
      31.downto(1) do |day|
        jd = civil_jd(year, month, day, start)
        return jd if jd_civil(jd, start) == [year, month, day]
      end
      nil
    end

    def first_day_jd(year, start)
      Primitive.attr! :hidden
      1.upto(31) do |day|
        jd = civil_jd(year, 1, day, start)
        return jd if jd_civil(jd, start) == [year, 1, day]
      end
      nil
    end

    def valid_ordinal_jd(year, yday, start)
      Primitive.attr! :hidden
      first = first_day_jd(year, start) or return nil
      if yday.negative?
        last = first_day_jd(year + 1, start) or return nil
        jd = last + yday
      else
        jd = first + yday - 1
      end
      return nil if jd < first

      last = first_day_jd(year + 1, start)
      last && jd >= last ? nil : jd
    end

    def commercial_jd(cwyear, cweek, cwday, start)
      Primitive.attr! :hidden
      first = first_day_jd(cwyear, start) + 3
      (first - (first % 7)) + (7 * (cweek - 1)) + (cwday - 1)
    end

    def valid_commercial_jd(cwyear, cweek, cwday, start)
      Primitive.attr! :hidden
      cwday += 8 if cwday.negative?
      if cweek.negative?
        year, cweek, = jd_commercial(commercial_jd(cwyear + 1, 1, 1, start) + (cweek * 7), start)
        return nil unless year == cwyear
      end

      jd = commercial_jd(cwyear, cweek, cwday, start)
      jd_commercial(jd, start) == [cwyear, cweek, cwday] ? jd : nil
    end

    def jd_commercial(jd, start)
      Primitive.attr! :hidden
      year = jd_civil(jd - 3, start).first
      year += 1 if jd >= commercial_jd(year + 1, 1, 1, start)
      week = 1 + ((jd - commercial_jd(year, 1, 1, start)) / 7)
      day = (jd + 1) % 7
      [year, week, day.zero? ? 7 : day]
    end

    def jd_wday(jd)
      Primitive.attr! :hidden
      (jd + 1) % 7
    end

    private :civil_jd, :jd_civil, :valid_civil_jd, :last_day_jd, :first_day_jd,
            :valid_ordinal_jd, :commercial_jd, :valid_commercial_jd, :jd_commercial, :jd_wday
  end

  # A date from its own parts, which no caller checks again. A simple
  # date has a day and no time of day, as date_core.c's
  # SimpleDateData does; Date's own constructors make one.
  def self.at(jd, df, sf, of, start, simple: false)
    Primitive.attr! :hidden
    date = allocate
    date.send(:setup, jd, df, sf, of, start, simple)
    date
  end
  private_class_method :at

  def self.jd(jd = 0, start = ITALY)
    start = valid_start(start)
    jd = numeric(jd, "jd")
    date = at(jd.floor, 0, 0, 0, start, simple: true)
    jd.integer? ? date : date + (jd - jd.floor)
  end

  # date_s_civil: a date from its civil parts, moved on by the fraction
  # of its day. It never calls the initialize that a subclass defines.
  def self.civil(year = -4712, month = 1, day = 1, start = ITALY)
    jd, start = civil_day(year, month, day, start)
    date = at(jd, 0, 0, 0, start, simple: true)
    day.integer? ? date : date + (day - day.floor)
  end

  # date_initialize reads the parts last to first. A fraction of a day
  # is lost, because `new` returns the date it allocated and not the one
  # that the fraction moved.
  def self.civil_day(year, month, day, start)
    Primitive.attr! :hidden
    start = valid_start(start)
    day = numeric(day, "day").floor
    month = numeric(month, "month").to_i
    jd = send(:valid_civil_jd, integer(numeric(year, "year")), month, day, start)
    raise Error, "invalid date" unless jd

    [jd, start]
  end
  private_class_method :civil_day

  # Date.new: date_initialize, on the simple date that Date.allocate
  # makes. A DateTime's allocation is not simple.
  def initialize(year = -4712, month = 1, day = 1, start = ITALY)
    raise TypeError, "Date expected" unless parts[5]

    jd, start = Date.send(:civil_day, year, month, day, start)
    setup(jd, 0, 0, 0, start, true)
  end

  # d_lite_initialize_copy: a copy takes the other date's parts. A
  # simple date cannot take the parts of one with a time of day.
  def initialize_copy(date)
    Primitive.zr_frozen_error(self) if frozen?
    raise TypeError, "wrong argument type #{conversion_name(date)} (expected Date)" unless date.is_a?(Date)
    return self if equal?(date)

    jd, df, sf, of, sg, simple = date.send(:parts)
    raise ArgumentError, "cannot load complex into simple" if parts[5] && !simple

    setup(jd, df, sf, of, sg, simple && parts[5])
  end

  def self.ordinal(year = -4712, yday = 1, start = ITALY)
    start = valid_start(start)
    yday = numeric(yday, "yday")
    jd = send(:valid_ordinal_jd, integer(numeric(year, "year")), yday.floor, start)
    raise Error, "invalid date" unless jd

    date = at(jd, 0, 0, 0, start, simple: true)
    yday.integer? ? date : date + (yday - yday.floor)
  end

  def self.commercial(cwyear = -4712, cweek = 1, cwday = 1, start = ITALY)
    start = valid_start(start)
    cwday = numeric(cwday, "cwday")
    cweek = numeric(cweek, "cweek").to_i
    jd = send(:valid_commercial_jd, integer(numeric(cwyear, "year")), cweek, cwday.floor, start)
    raise Error, "invalid date" unless jd

    date = at(jd, 0, 0, 0, start, simple: true)
    cwday.integer? ? date : date + (cwday - cwday.floor)
  end

  def self.today(start = ITALY)
    now = Time.now
    civil(now.year, now.month, now.day, start)
  end

  def self.valid_jd?(jd, start = ITALY)
    return false unless jd.is_a?(Numeric)

    valid_start(start)
    true
  end

  def self.valid_civil?(year, month, day, start = ITALY)
    return false unless [year, month, day].all?(Numeric)

    !send(:valid_civil_jd, integer(year), month.to_i, day.to_i, valid_start(start)).nil?
  end

  class << self
    alias valid_date? valid_civil?
  end

  def self.valid_ordinal?(year, yday, start = ITALY)
    return false unless [year, yday].all?(Numeric)

    !send(:valid_ordinal_jd, integer(year), yday.to_i, valid_start(start)).nil?
  end

  def self.valid_commercial?(cwyear, cweek, cwday, start = ITALY)
    return false unless [cwyear, cweek, cwday].all?(Numeric)

    !send(:valid_commercial_jd, integer(cwyear), cweek.to_i, cwday.to_i, valid_start(start)).nil?
  end

  def self.gregorian_leap?(year)
    year = numeric(year, "year")
    (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
  end

  class << self
    alias leap? gregorian_leap?
  end

  def self.julian_leap?(year) = (numeric(year, "year") % 4).zero?

  # check_numeric: each part of a date is a Numeric.
  def self.numeric(value, name)
    Primitive.attr! :hidden
    raise TypeError, "invalid #{name} (not numeric)" unless value.is_a?(Numeric)

    value
  end

  # A year as a whole number; a year past every whole number is no date.
  def self.integer(value)
    Primitive.attr! :hidden
    raise Error, "invalid date" unless value.integer? || value.finite?

    value.to_i
  end

  # val2sg: the day the Gregorian calendar starts, as NUM2DBL reads it.
  # A day outside the years of the reform is ignored for ITALY.
  def self.valid_start(start)
    Primitive.attr! :hidden
    sg = case start
         when Float then start
         when nil, true, false, Symbol, String then raise TypeError, no_implicit_conversion(start, "Float")
         when Numeric then start.to_f
         else raise TypeError, cant_convert(start, "Float")
         end
    return sg if sg.infinite? || sg.between?(REFORM_BEGIN_JD, REFORM_END_JD)

    warn("invalid start is ignored", uplevel: 1) if $VERBOSE
    ITALY.to_f
  end

  private_class_method :numeric, :integer, :valid_start

  # date_core.c keeps a date in a C struct, so a program sees no
  # instance variable on one. Here its parts live in a hidden slot: the
  # UTC day number, the second of that day and its nanosecond, the
  # offset in seconds, the day the Gregorian calendar starts, and
  # whether the date is simple.
  def setup(jd, df, sf, of, start, simple)
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :__parts__, [jd, df, sf, of, start, simple].freeze)
    self
  end
  private :setup

  # An allocated date is day 0 of the Julian period, as
  # d_lite_s_alloc_simple and d_lite_s_alloc_complex leave one.
  def parts
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__parts__) || [0, 0, 0, 0, ITALY.to_f, !is_a?(DateTime)].freeze
  end
  private :parts

  def offset_seconds
    Primitive.attr! :hidden
    parts[3]
  end
  private :offset_seconds

  def reform
    Primitive.attr! :hidden
    parts[4]
  end
  private :reform

  # The local day and second, which the offset moves off the stored UTC.
  def local
    Primitive.attr! :hidden
    jd, df, _, of = parts
    seconds = df + of
    [jd + seconds.div(DAY), seconds % DAY]
  end
  private :local

  def jd = local.first

  def mjd = jd - 2_400_001

  def ld = jd - 2_299_160

  def ajd
    jd, df, sf = parts
    Rational((jd * DAY * NANOSECOND) - (DAY * NANOSECOND / 2) + (df * NANOSECOND) + sf, DAY * NANOSECOND)
  end

  def amjd = ajd - Rational(4_800_001, 2)

  # A date with no time of day has no fraction at all.
  def day_fraction
    return 0 if parts[5]

    _, df = local
    Rational((df * NANOSECOND) + parts[2], DAY * NANOSECOND)
  end

  def start = reform.to_f

  def julian? = jd < reform

  def gregorian? = !julian?

  def new_start(start = ITALY)
    jd, df, sf, of, _, simple = parts
    self.class.send(:at, jd, df, sf, of, self.class.send(:valid_start, start), simple: simple)
  end

  def italy = new_start(ITALY)

  def england = new_start(ENGLAND)

  def julian = new_start(JULIAN)

  def gregorian = new_start(GREGORIAN)

  def civil
    Primitive.attr! :hidden
    self.class.send(:jd_civil, jd, reform)
  end
  private :civil

  def year = civil[0]

  def mon = civil[1]

  alias month mon

  def mday = civil[2]

  alias day mday

  def yday = jd - self.class.send(:first_day_jd, year, reform) + 1

  def wday = self.class.send(:jd_wday, jd)

  def commercial
    Primitive.attr! :hidden
    self.class.send(:jd_commercial, jd, reform)
  end
  private :commercial

  def cwyear = commercial[0]

  def cweek = commercial[1]

  def cwday = commercial[2]

  DAYNAMES.each_with_index do |name, index|
    define_method(:"#{name.downcase}?") { wday == index }
  end

  def leap?
    y = year
    julian? ? self.class.julian_leap?(y) : self.class.gregorian_leap?(y)
  end

  # The time of day in the date's own offset: the hour, the minute and
  # the second.
  def clock
    Primitive.attr! :hidden
    second = local[1]
    [second / 3600, (second % 3600) / 60, second % 60]
  end
  private :clock

  # A Date has a clock only to return zero from, privately.
  def hour = 0
  alias min hour
  alias minute hour
  alias sec hour
  alias second hour
  private :hour, :min, :minute, :sec, :second

  private_class_method def self.offset_string(of)
    Primitive.attr! :hidden
    sign = of.negative? ? "-" : "+"
    of = of.abs
    format("%s%02d:%02d", sign, of / 3600, (of % 3600) / 60).force_encoding(Encoding::US_ASCII)
  end

  # val2off: an offset as a count of seconds, from a number of days or a
  # zone. One that is no offset within a day is 0, with a warning under
  # -w.
  private_class_method def self.seconds_of(offset)
    Primitive.attr! :hidden
    seconds = offset_to_sec(offset)
    return seconds if seconds

    Primitive.zr_warn_here_m(+"invalid offset is ignored") if $VERBOSE
    0
  end

  # offset_to_sec: the seconds, or nil for an offset past a day. An
  # Integer is a whole day; a Float or a Rational rounds to the second,
  # with a warning under -w when that drops a fraction. Another Numeric
  # is read through to_r, whose answer is read again by these rules; a
  # second to_r that gives no Rational is a TypeError.
  private_class_method def self.offset_to_sec(offset, again = true)
    Primitive.attr! :hidden
    case offset
    when Integer
      [-1, 0, 1].include?(offset) ? offset * DAY : nil
    when Float
      seconds = offset * DAY
      return nil if seconds < -DAY || seconds > DAY

      whole = seconds.round
      Primitive.zr_warn_here_m(+"fraction of offset is ignored") if $VERBOSE && whole != seconds
      whole
    when String
      seconds = zone_to_diff(offset)
      seconds.is_a?(Integer) && seconds.between?(-DAY, DAY) ? seconds : nil
    when Rational
      seconds = offset * DAY
      whole = seconds.round
      Primitive.zr_warn_here_m(+"fraction of offset is ignored") if $VERBOSE && whole != seconds
      whole.between?(-DAY, DAY) ? whole : nil
    else
      raise TypeError, "expected numeric" unless offset.is_a?(Numeric)

      days = offset.to_r
      return offset_to_sec(days) if days.is_a?(Rational)
      raise TypeError, "wrong argument type #{days.class} (expected Rational)" unless again

      offset_to_sec(days, false)
    end
  end

  # Whole days move the day number; a fraction moves the nanosecond.
  def +(other)
    case other
    when Integer then days_later(other)
    when Float then add_nanoseconds((Rational(other) * DAY * NANOSECOND).round)
    when Numeric then add_nanoseconds(exact(Rational(other) * DAY * NANOSECOND))
    else raise TypeError, "expected numeric"
    end
  end

  # A Rational step keeps its fraction of a nanosecond, as date_core.c
  # keeps a Rational sf; a whole one is an Integer again.
  def exact(count)
    Primitive.attr! :hidden
    count.denominator == 1 ? count.to_i : count
  end
  private :exact

  # Whole days keep a simple date simple.
  def days_later(count)
    Primitive.attr! :hidden
    jd, df, sf, of, sg, simple = parts
    self.class.send(:at, jd + count, df, sf, of, sg, simple: simple)
  end
  private :days_later

  # A fraction of a day makes a date that has a time of day, unless
  # the time comes back to midnight in UTC.
  def add_nanoseconds(count)
    Primitive.attr! :hidden
    jd, df, sf, of, sg = parts
    total = (((jd * DAY) + df) * NANOSECOND) + sf + count
    jd, rest = total.divmod(DAY * NANOSECOND)
    df, sf = rest.divmod(NANOSECOND)
    sf = exact(sf) if sf.is_a?(Rational)
    self.class.send(:at, jd, df, sf, of, sg, simple: df.zero? && sf.zero? && of.zero?)
  end
  private :add_nanoseconds

  def -(other)
    case other
    when Date then ajd - other.ajd
    when Integer then days_later(-other)
    when Numeric then add_nanoseconds(-(Rational(other) * DAY * NANOSECOND).round)
    else raise TypeError, "expected numeric"
    end
  end

  # A month later, kept inside the month it lands in.
  def >>(months)
    y, m, d = civil
    y, m = ((y * 12) + (m - 1) + months).divmod(12)
    m += 1
    until (jd = self.class.send(:valid_civil_jd, y, m, d, reform))
      d -= 1
      raise Error, "invalid date" if d < 1
    end
    self + (jd - self.jd)
  end

def <<(months)
  raise TypeError, "expected numeric" unless months.is_a?(Numeric)

  self >> -months
end

  def next_day(count = 1) = self + count

  def prev_day(count = 1) = self - count

  def next_month(count = 1) = self >> count

  def prev_month(count = 1) = self << count

  def next_year(count = 1) = self >> (count * 12)

  def prev_year(count = 1) = self << (count * 12)

  def succ = next_day

  alias next succ

  def <=>(other)
    case other
    when Date then ajd <=> other.ajd
    when Numeric then ajd <=> other
    else
      begin
        l, r = other.coerce(self)
        l <=> r
      rescue NoMethodError
        nil
      end
    end
  end

  def ===(other)
    case other
    when Date then jd == other.jd
    when Numeric then jd == other
    else false
    end
  end

  def eql?(other) = other.is_a?(Date) && (self <=> other).zero?

  def hash = ajd.hash

  # d_lite_step: every date from here to `limit`, `step` days apart. The
  # sign of the step comes from its own <=>, and a step of 0 yields this
  # date for good, as date_core.c, whose zero check is compiled out.
  def step(limit, step = (one = true; 1))
    unless block_given?
      return one ? to_enum(:step, limit) : to_enum(:step, limit, step)
    end

    date = self
    sign = Primitive.zr_cmpint(step <=> 0, step, 0)
    if sign.negative?
      while (date <=> limit) >= 0
        yield date
        date += step
      end
    elsif sign.zero?
      loop { yield date }
    else
      while (date <=> limit) <= 0
        yield date
        date += step
      end
    end
    self
  end

  def upto(limit, &block)
    return to_enum(:upto, limit) unless block

    step(limit, 1, &block)
  end

  def downto(limit, &block)
    return to_enum(:downto, limit) unless block

    step(limit, -1, &block)
  end

  def to_date = self

  # A simple date stays simple; another leaves its time of day behind.
  def to_datetime
    jd, _, _, of, sg, simple = parts
    return DateTime.send(:at, *parts.first(5), simple: true) if simple

    DateTime.send(:at, jd, 0, 0, of, sg)
  end

  # d_lite_to_time: a Julian date turns Gregorian first.
  def to_time
    date = julian? ? gregorian : self
    Time.local(date.year, date.mon, date.mday)
  end

  def deconstruct_keys(keys)
    unless keys.nil? || keys.is_a?(Array)
      raise TypeError, "wrong argument type #{keys.class} (expected Array or nil)"
    end

    all = { year: year, month: mon, day: mday, yday: yday, wday: wday }
    keys.nil? ? all : all.slice(*keys)
  end

  # d_lite_marshal_dump: the period count, the UTC day number, second
  # and nanosecond, the offset and the reform day as a Float.
  def marshal_dump
    jd, df, sf, of, sg = parts
    [0, jd, df, sf, of, sg.to_f]
  end

  # d_lite_marshal_load: this form, or the older one of an astronomical
  # day number, an offset in days and a reform day.
  def marshal_load(values)
    Primitive.zr_frozen_error(self) if frozen?
    raise TypeError, "expected an array" unless values.is_a?(Array)

    case values.size
    when 2, 3
      ajd, of, sg = values.size == 2 ? [values[0] - Rational(1, 2), 0, values[1]] : values
      sg = sg ? GREGORIAN : JULIAN unless sg.is_a?(Numeric)
      total = ((ajd + Rational(1, 2)) * DAY * NANOSECOND).round
      jd, rest = total.divmod(DAY * NANOSECOND)
      df, sf = rest.divmod(NANOSECOND)
      of = (of * DAY).round
    when 6
      _, jd, df, sf, of, sg = values
    else
      raise TypeError, "invalid size"
    end
    sg = sg.to_i if sg.is_a?(Float) && sg.finite?
    setup(jd, df, sf, of, sg, !is_a?(DateTime) && df.zero? && sf.zero? && of.zero?)
  end

  def self._load(text) = allocate.tap { |date| date.marshal_load(Marshal.load(text)) }
end

# DateTime: the same value, with the time of day and the offset shown.
# date_core.c undefines `today` on it: `now` gives its time of day.
class DateTime < Date
  class << self
    undef_method :today
  end

  def self.new(*args)
    raise ArgumentError, wrong_arity(args.size, 0..8) if args.size > 8

    year, month, day, hour, minute, second, offset, start = args
    argc = args.size
    start = argc > 7 ? send(:valid_start, start) : Date::ITALY
    of = argc > 6 ? send(:seconds_of, offset) : 0
    fraction = 0
    second, fraction = send(:whole_part, second, "second", 86_400, true, fraction) if argc > 5
    minute, fraction = send(:whole_part, minute, "minute", 1440, argc == 5, fraction) if argc > 4
    hour, fraction = send(:whole_part, hour, "hour", 24, argc == 4, fraction) if argc > 3
    day, fraction = send(:whole_part, day, "day", 1, argc == 3, fraction) if argc > 2
    month = argc > 1 ? send(:numeric, month, "month").to_i : 1
    year = argc.positive? ? send(:numeric, year, "year") : -4712
    jd = send(:valid_civil_jd, send(:integer, year), month, day || 1, start)
    raise Date::Error, "invalid date" unless jd

    df, fraction = send(:time_of_day, hour || 0, minute || 0, second || 0, fraction)
    nanoseconds = (((jd * DAY) + df - of) * NANOSECOND) + (fraction * DAY * NANOSECOND)
    jd, rest = nanoseconds.divmod(DAY * NANOSECOND)
    df, sf = rest.divmod(NANOSECOND)
    sf = sf.to_i if sf.is_a?(Rational) && sf.denominator == 1
    send(:at, jd, df.to_i, sf, of, start)
  end

  # num2int_with_frac: the whole part, and the fraction as a part of a
  # day. Only the last part given may have a fraction.
  private_class_method def self.whole_part(value, name, per_day, last, fraction)
    Primitive.attr! :hidden
    value = numeric(value, name)
    return [value.to_i, fraction] if value.integer? || (value.finite? && value == value.floor)

    raise Date::Error, "invalid fraction" unless last

    [value.floor, Rational(value - value.floor) / per_day]
  end

  class << self
    alias civil new
  end

  # The second of the day and its nanosecond, with a negative part
  # counting back from the end of the hour, minute or day.
  # c_valid_time_p. Hour 24 is midnight of the next day.
  private_class_method def self.time_of_day(hour, minute, second, fraction)
    Primitive.attr! :hidden
    hour += 24 if hour.negative?
    minute += 60 if minute.negative?
    second += 60 if second.negative?
    valid = hour.between?(0, 24) && minute.between?(0, 59) && second.between?(0, 59)
    raise Date::Error, "invalid date" unless valid && (hour < 24 || (minute.zero? && second.zero?))


    [(hour * 3600) + (minute * 60) + second, fraction]
  end

  def self.now(start = Date::ITALY)
    now = Time.now
    new(now.year, now.month, now.day, now.hour, now.min, now.sec + Rational(now.nsec, 1_000_000_000), Rational(now.utc_offset, 86_400), start)
  end

  # The time parts after the day keep their positions, so the fraction
  # rule of `new` sees the same last part. A day part that is last may
  # have a fraction, which moves the result on.
  def self.jd(jd = 0, *rest)
    jd, fraction = send(:whole_part, jd, "jd", 1, rest.empty?, 0)
    date = Date.jd(jd, rest.size > 4 ? rest[4] : Date::ITALY)
    send(:moved, new(date.year, date.mon, date.mday, *rest), fraction)
  end

  def self.ordinal(year = -4712, yday = 1, *rest)
    yday, fraction = send(:whole_part, yday, "yday", 1, rest.empty?, 0)
    date = Date.ordinal(year, yday, rest.size > 4 ? rest[4] : Date::ITALY)
    send(:moved, new(date.year, date.mon, date.mday, *rest), fraction)
  end

  def self.commercial(cwyear = -4712, cweek = 1, cwday = 1, *rest)
    cwday, fraction = send(:whole_part, cwday, "cwday", 1, rest.empty?, 0)
    date = Date.commercial(cwyear, cweek, cwday, rest.size > 4 ? rest[4] : Date::ITALY)
    send(:moved, new(date.year, date.mon, date.mday, *rest), fraction)
  end

  private_class_method def self.moved(date, fraction)
    Primitive.attr! :hidden
    fraction.zero? ? date : date + fraction
  end

  def hour = clock[0]

  def min = clock[1]

  alias minute min

  def sec = clock[2]

  alias second sec

  def sec_fraction = Rational(parts[2], NANOSECOND)

  alias second_fraction sec_fraction

  def offset = Rational(offset_seconds, DAY)

  def zone = Date.send(:offset_string, offset_seconds)

  def new_offset(offset = 0)
    jd, df, sf, _, sg = parts
    self.class.send(:at, jd, df, sf, self.class.send(:seconds_of, offset), sg)
  end

  def to_date = Date.send(:at, jd, 0, 0, 0, reform, simple: true)

  def to_datetime = self

  # datetime_to_time: a Julian date turns Gregorian first, and the
  # offset goes to Time.new in seconds.
  def to_time
    date = julian? ? gregorian : self
    Time.new(date.year, date.mon, date.mday, date.hour, date.min, date.sec + date.sec_fraction, date.send(:offset_seconds))
  end

  def deconstruct_keys(keys)
    unless keys.nil? || keys.is_a?(Array)
      raise TypeError, "wrong argument type #{keys.class} (expected Array or nil)"
    end

    all = super(nil).merge(hour: hour, min: min, sec: sec, sec_fraction: sec_fraction, zone: zone)
    keys.nil? ? all : all.slice(*keys)
  end
end

require_relative "date/format"
require_relative "date/parse"
# date_core.c's time_to_*: the proleptic Gregorian day of the time,
# which then takes the default day of the calendar reform.
class Time
  def to_time = self

  def to_date = Date.civil(year, mon, mday, Date::GREGORIAN).new_start

  # A leap second is the last second of its minute.
  def to_datetime
    DateTime.new(year, mon, mday, hour, min, [sec, 59].min + subsec, Rational(utc_offset, 86_400), Date::GREGORIAN).new_start
  end
end

require_relative "date/readers"
require_relative "date/strptime"
require_relative "date/frags"
