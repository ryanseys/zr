# frozen_string_literal: true

# Date and DateTime over a chronological Julian day number, a second of
# that day and a nanosecond, all in UTC, with the offset and the day the
# Gregorian calendar starts held beside them. Every conversion is exact
# integer arithmetic, so a date carries no float and never drifts.

class Date
  include Comparable

  ITALY = 2299161
  ENGLAND = 2361222
  JULIAN = Float::INFINITY
  GREGORIAN = -Float::INFINITY

  MONTHNAMES = [nil, "January", "February", "March", "April", "May", "June",
                "July", "August", "September", "October", "November", "December"].freeze
  DAYNAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  ABBR_MONTHNAMES = [nil, "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].freeze
  ABBR_DAYNAMES = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

  DAY = 86_400
  NANOSECOND = 1_000_000_000
  # The first and the last day a calendar reform can start on.
  REFORM_BEGIN_JD = 2_298_874
  REFORM_END_JD = 2_426_355
  private_constant :DAY, :NANOSECOND, :REFORM_BEGIN_JD, :REFORM_END_JD

  class Error < ArgumentError; end

  # A value larger, or smaller, than every date. Ranges of dates use it
  # for an open end.
  # The gem's lib/date.rb writes this in Ruby.
  class Infinity < Numeric
    def initialize(d = 1)
      @d = d <=> 0
    end

    def d = @d
    protected :d

    def zero? = false
    def finite? = false
    def infinite? = d.nonzero?
    def nan? = d.zero?
    def abs = self.class.new
    def -@ = self.class.new(-d)
    def +@ = self.class.new(+d)

    def <=>(other)
      case other
      when Infinity then d <=> other.d
      when Float::INFINITY then d <=> 1
      when -Float::INFINITY then d <=> -1
      when Numeric then d
      else
        begin
          l, r = other.coerce(self)
          l <=> r
        rescue NoMethodError
          nil
        end
      end
    end

    def coerce(other)
      case other
      when Numeric then [-d, d]
      else super
      end
    end

    def to_f
      return 0 if @d == 0

      @d > 0 ? Float::INFINITY : -Float::INFINITY
    end
  end

  class << self
    # The Julian day number of a civil date, with no validity check.
    def civil_jd(year, month, day, start)
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
      31.downto(1) do |day|
        jd = civil_jd(year, month, day, start)
        return jd if jd_civil(jd, start) == [year, month, day]
      end
      nil
    end

    def first_day_jd(year, start)
      1.upto(31) do |day|
        jd = civil_jd(year, 1, day, start)
        return jd if jd_civil(jd, start) == [year, 1, day]
      end
      nil
    end

    def valid_ordinal_jd(year, yday, start)
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
      first = first_day_jd(cwyear, start) + 3
      (first - jd_wday(first) - 7) + (7 * cweek) + cwday
    end

    def valid_commercial_jd(cwyear, cweek, cwday, start)
      cwday += 8 if cwday.negative?
      cweek += jd_commercial(commercial_jd(cwyear + 1, 1, 1, start) - 1, start)[1] + 1 if cweek.negative?
      return nil unless (1..7).cover?(cwday) && cweek.positive?

      jd = commercial_jd(cwyear, cweek, cwday, start)
      jd_commercial(jd, start) == [cwyear, cweek, cwday] ? jd : nil
    end

    def jd_commercial(jd, start)
      year = jd_civil(jd - 3, start).first
      year += 1 if jd >= commercial_jd(year + 1, 1, 1, start)
      week = 1 + ((jd - commercial_jd(year, 1, 1, start)) / 7)
      day = (jd + 1) % 7
      [year, week, day.zero? ? 7 : day]
    end

    def jd_wday(jd) = (jd + 1) % 7

    private :civil_jd, :jd_civil, :valid_civil_jd, :last_day_jd, :first_day_jd,
            :valid_ordinal_jd, :commercial_jd, :valid_commercial_jd, :jd_commercial, :jd_wday
  end

  # A date from its own parts, which no caller checks again. A simple
  # date holds a day and no time of day, as date_core.c's
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

  # date_initialize reads the parts last to first. A fraction of a day
  # is lost, as `new` answers the date it allocated and not the one the
  # fraction moved.
  def self.civil(year = -4712, month = 1, day = 1, start = ITALY)
    start = valid_start(start)
    day = numeric(day, "day").floor
    month = numeric(month, "month").to_i
    jd = send(:valid_civil_jd, integer(numeric(year, "year")), month, day, start)
    raise Error, "invalid date" unless jd

    at(jd, 0, 0, 0, start, simple: true)
  end

  class << self
    alias new civil
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

  def self.gregorian_leap?(year) = (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)

  class << self
    alias leap? gregorian_leap?
  end

  def self.julian_leap?(year) = (year % 4).zero?

  # check_numeric: each part of a date is a Numeric.
  def self.numeric(value, name)
    raise TypeError, "invalid #{name} (not numeric)" unless value.is_a?(Numeric)

    value
  end

  # A year as a whole number; one past every whole number names no date.
  def self.integer(value)
    raise Error, "invalid date" unless value.integer? || value.finite?

    value.to_i
  end

  # val2sg: the day the Gregorian calendar starts, as NUM2DBL reads it.
  # A day outside the years of the reform is ignored for ITALY.
  def self.valid_start(start)
    sg = case start
         when Float then start
         when nil, true, false then raise TypeError, "no implicit conversion to float from #{start.inspect}"
         when String then raise TypeError, "no implicit conversion to float from string"
         when Numeric then start.to_f
         else raise TypeError, "can't convert #{start.class} into Float"
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

  def parts
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__parts__)
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

  # A date with no time of day holds no fraction at all.
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

  def civil = self.class.send(:jd_civil, jd, reform)
  private :civil

  def year = civil[0]

  def mon = civil[1]

  alias month mon

  def mday = civil[2]

  alias day mday

  def yday = jd - self.class.send(:first_day_jd, year, reform) + 1

  def wday = self.class.send(:jd_wday, jd)

  def commercial = self.class.send(:jd_commercial, jd, reform)
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

  def infinite? = false

  # The time of day in the date's own offset: the hour, the minute and
  # the second.
  def clock
    Primitive.attr! :hidden
    second = local[1]
    [second / 3600, (second % 3600) / 60, second % 60]
  end
  private :clock

  # A Date has a clock only to answer zero from, privately.
  def hour = 0
  alias min hour
  alias minute hour
  alias sec hour
  alias second hour
  private :hour, :min, :minute, :sec, :second

  private_class_method def self.offset_string(of)
    sign = of.negative? ? "-" : "+"
    of = of.abs
    format("%s%02d:%02d", sign, of / 3600, (of % 3600) / 60)
  end

  # An offset as a count of seconds: a number of days, or "+HH:MM".
  private_class_method def self.seconds_of(offset)
    return (offset * DAY).round if offset.is_a?(Numeric)

    text = String.try_convert(offset) or raise TypeError, "no implicit conversion of #{conversion_name(offset)} into String"
    seconds = zone_seconds(text) or raise Error, "invalid offset"
    seconds
  end

  private_class_method def self.zone_seconds(text)
    return 0 if /\A(?:Z|UTC?|GMT)\z/i.match?(text)
    return nil unless (m = /\A([-+])(\d{1,2})(?::?(\d{2})(?::?(\d{2}))?)?\z/.match(text))

    seconds = (m[2].to_i * 3600) + (m[3].to_i * 60) + m[4].to_i
    m[1] == "-" ? -seconds : seconds
  end

  # Whole days move the day number; a fraction moves the nanosecond.
  def +(other)
    case other
    when Integer then days_later(other)
    when Numeric then add_nanoseconds((Rational(other) * DAY * NANOSECOND).round)
    else raise TypeError, "expected numeric"
    end
  end

  # Whole days keep a simple date simple.
  def days_later(count)
    Primitive.attr! :hidden
    jd, df, sf, of, sg, simple = parts
    self.class.send(:at, jd + count, df, sf, of, sg, simple: simple)
  end
  private :days_later

  # A fraction of a day makes a date that holds a time of day, unless
  # the time comes back to midnight in UTC.
  def add_nanoseconds(count)
    Primitive.attr! :hidden
    jd, df, sf, of, sg = parts
    total = (((jd * DAY) + df) * NANOSECOND) + sf + count
    jd, rest = total.divmod(DAY * NANOSECOND)
    df, sf = rest.divmod(NANOSECOND)
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
    jd = nil
    until (jd = self.class.send(:valid_civil_jd, y, m, d, reform))
      d -= 1
      raise Error, "invalid date" if d < 1
    end
    self + (jd - self.jd)
  end

  def <<(months) = self >> -months

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

  # Every date from here to `limit`, `step` days apart.
  def step(limit, step = 1)
    raise ArgumentError, "step can't be 0" if step.zero?
    return to_enum(:step, limit, step) unless block_given?

    date = self
    if step.positive?
      while (date <=> limit) <= 0
        yield date
        date += step
      end
    else
      while (date <=> limit) >= 0
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

  def to_time = Time.new(year, mon, mday)

  def deconstruct_keys(keys)
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
    raise FrozenError, "can't modify frozen #{self.class}: #{inspect}" if frozen?
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
class DateTime < Date
  def self.new(year = -4712, month = 1, day = 1, hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
    start = send(:valid_start, start)
    of = send(:seconds_of, offset)
    second = send(:numeric, second, "second")
    minute = send(:numeric, minute, "minute")
    hour = send(:numeric, hour, "hour")
    day = send(:numeric, day, "day").floor
    month = send(:numeric, month, "month").to_i
    jd = send(:valid_civil_jd, send(:integer, send(:numeric, year, "year")), month, day, start)
    raise Date::Error, "invalid date" unless jd

    df, sf = send(:time_of_day, hour, minute, second)
    send(:at, jd, df - of, sf, of, start).send(:carry)
  end

  class << self
    alias civil new
  end

  # The second of the day and its nanosecond, with a negative part
  # counting back from the end of the hour, minute or day.
  private_class_method def self.time_of_day(hour, minute, second)
    hour += 24 if hour.negative?
    minute += 60 if minute.negative?
    second += 60 if second.negative?
    raise Date::Error, "invalid date" unless (0..24).cover?(hour) && (0..59).cover?(minute) && (0..59).cover?(second)

    whole = second.to_i
    fraction = ((second - whole) * 1_000_000_000).round
    [(hour.to_i * 3600) + (minute.to_i * 60) + whole, fraction]
  end

  # A day number and second put back in range after the offset moved it.
  def carry
    jd, df, sf, of, sg = parts
    self.class.send(:at, jd + df.div(86_400), df % 86_400, sf, of, sg)
  end
  private :carry

  def self.now(start = Date::ITALY)
    now = Time.now
    new(now.year, now.month, now.day, now.hour, now.min, now.sec + Rational(now.nsec, 1_000_000_000), Rational(now.utc_offset, 86_400), start)
  end

  def self.jd(jd = 0, hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
    date = Date.jd(send(:numeric, jd, "jd").floor, start)
    new(date.year, date.mon, date.mday, hour, minute, second, offset, start)
  end

  def self.ordinal(year = -4712, yday = 1, hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
    date = Date.ordinal(year, yday, start)
    new(date.year, date.mon, date.mday, hour, minute, second, offset, start)
  end

  def self.commercial(cwyear = -4712, cweek = 1, cwday = 1, hour = 0, minute = 0, second = 0, offset = 0, start = Date::ITALY)
    date = Date.commercial(cwyear, cweek, cwday, start)
    new(date.year, date.mon, date.mday, hour, minute, second, offset, start)
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

  def to_time
    Time.new(year, mon, mday, hour, min, sec + sec_fraction, offset)
  end

  def deconstruct_keys(keys)
    all = super(nil).merge(hour: hour, min: min, sec: sec, sec_fraction: sec_fraction, zone: zone)
    keys.nil? ? all : all.slice(*keys)
  end
end

require_relative "date/format"
require_relative "date/parse"
require_relative "date/readers"
require_relative "date/strptime"
require_relative "date/frags"
