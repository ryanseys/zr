# frozen_string_literal: true

require "spec_helper"

describe "Date: formatting and inspection" do
  it "every Date and DateTime field answers what ruby answers, without reading the machine's zone" do
    result = ze0(<<~'RUBY')
      # The whole `Date`/`DateTime` surface, field by field, against ruby 4.0.6.
      # Nothing here reads the machine's zone: `to_time` appears only through
      # fields that a local Time renders identically everywhere.
      require "date"

      d  = Date.new(2024, 2, 29)
      dt = DateTime.new(2024, 1, 2, 3, 4, 5, "+09:00")

      FIELDS = %i[
        year month mon day mday wday yday jd mjd ld ajd amjd day_fraction
        cwday cweek cwyear leap? julian? gregorian? start infinite?
        to_s inspect iso8601 xmlschema rfc3339 rfc2822 httpdate jisx0301
        ctime asctime marshal_dump
        sunday? monday? tuesday? wednesday? thursday? friday? saturday?
      ].freeze

      [d, dt].each do |x|
        FIELDS.each { |m| p [x.class.name, m, x.public_send(m)] }
      end

      # The clock half is PRIVATE on Date and public on DateTime.
      %i[hour min minute sec second sec_fraction second_fraction offset zone].each do |m|
        p [:datetime, m, dt.public_send(m)]
        begin
          d.public_send(m)
          p [:date, m, :public]
        rescue NoMethodError
          p [:date, m, :not_public]
        end
      end

      # Conversions. `Date#to_datetime` keeps the SIMPLE representation, so its
      # day fraction is the Integer zero rather than a Rational.
      p d.to_date.to_s, d.to_datetime.to_s, d.to_datetime.day_fraction
      p dt.to_date.to_s, dt.to_datetime.to_s
      p dt.new_offset("+00:00").to_s, dt.new_offset(0).to_s
      p dt.iso8601(3), dt.rfc3339(6), dt.jisx0301(3), dt.xmlschema(0)
      p d.deconstruct_keys(nil)
      p dt.deconstruct_keys(nil)

      # Navigation and iteration.
      p (d >> 1).to_s, (d << 1).to_s, (d >> 12).to_s
      p Date.new(2024, 1, 31).next_month.to_s, Date.new(2024, 1, 31).next_month(2).to_s
      p d.prev_year(3).to_s, d.next.to_s, d.succ.to_s
      p d.step(Date.new(2024, 3, 10), 3).map(&:to_s)
      p d.upto(Date.new(2024, 3, 2)).map(&:to_s)
      p Date.new(2024, 3, 2).downto(d).map(&:to_s)
      p d.step(Date.new(2024, 2, 25), -2).map(&:to_s)
      p d.upto(Date.new(2024, 2, 25)).to_a

      # Constructors and validators.
      p Date.commercial(2024, 9, 4).to_s, Date.ordinal(2024, 60).to_s
      p Date.commercial(2024, -1, -1).to_s, Date.ordinal(2024, -1).to_s
      p Date.new(2024, -1, -1).to_s, Date.new(2024, 2, -1).to_s
      p Date.valid_date?(2024, 2, 29), Date.valid_date?(2024, 2, 30)
      p Date.valid_ordinal?(2024, 366), Date.valid_ordinal?(2024, 367)
      p Date.valid_commercial?(2024, 9, 4), Date.valid_commercial?(2024, 53, 7)
      p Date.valid_jd?(2460370)
      p Date.leap?(2024), Date.gregorian_leap?(1900), Date.julian_leap?(1900)
      p Date.jd(2460370).to_s
      p Date.parse("2024-02-29").to_s, Date.strptime("29/02/2024", "%d/%m/%Y").to_s
      p DateTime.parse("2024-01-02T03:04:05+09:00").to_s
      p DateTime.strptime("2024-01-02 03:04:05", "%Y-%m-%d %H:%M:%S").to_s
      p DateTime.jd(2460370, 3, 4, 5).to_s

      # The calendar reform: `Date::ITALY` is the default start, so 1582-10-05
      # through 1582-10-14 do not exist and earlier dates are Julian.
      p Date.new(1582, 10, 4).to_s, Date.new(1582, 10, 15).to_s, Date.new(1, 1, 1).jd
      p Date.jd(2299160).to_s, Date.jd(2299161).to_s
      p d.england.to_s, d.italy.to_s, d.julian.to_s, d.julian.julian?
      p d.new_start(Date::JULIAN).to_s, d.gregorian.to_s
      p Date.new(1752, 9, 2, Date::ENGLAND).to_s

      # Ordering, equality and hashing.
      p (d <=> Date.new(2024, 3, 1)), (d <=> 2460370), (d <=> "x")
      p (d == Date.new(2024, 2, 29)), (d === Date.new(2024, 2, 29)), (d === 2460370)
      p d.eql?(Date.new(2024, 2, 29)), (d.hash == Date.new(2024, 2, 29).hash)
      p [Date.new(2024, 3, 1), Date.new(2024, 1, 1)].sort.map(&:to_s)
      p (d + 1).to_s, (d - 1).to_s, (d - Date.new(2024, 1, 1))
      p (d + Rational(1, 2)).day_fraction, (d + 1.5).to_s

      # strftime, including the directives only `date` has.
      p d.strftime("%c %x %X %v %+ %r %R %T %D %F")
      p d.strftime("%G %V %U %W %u %w %P %p %I %l %k %C %y %j")
      p d.strftime("%H:%M:%S %z %:z %Z %s %Q %L %N")
      p dt.strftime("%Y %H:%M:%S %z %:z %Z")

      # Constants.
      p Date::DAYNAMES, Date::ABBR_DAYNAMES
      p Date::MONTHNAMES, Date::ABBR_MONTHNAMES
      p Date::ITALY, Date::ENGLAND, Date::JULIAN, Date::GREGORIAN

      # Errors.
      begin; Date.new(2024, 13, 1); rescue => e; p [e.class.ancestors.include?(ArgumentError), e.message]; end
      begin; Date.new("x"); rescue => e; p [e.class, e.message]; end
      begin; Date.new(2024, 2, 29, "x"); rescue => e; p [e.class, e.message]; end
      begin; d >> "x"; rescue => e; p [e.class, e.message]; end
      begin; d + "x"; rescue => e; p [e.class, e.message]; end
      begin; d - "x"; rescue => e; p [e.class, e.message]; end
    RUBY

    _(result).must_answer <<~'OUT'
      ["Date", :year, 2024]
      ["Date", :month, 2]
      ["Date", :mon, 2]
      ["Date", :day, 29]
      ["Date", :mday, 29]
      ["Date", :wday, 4]
      ["Date", :yday, 60]
      ["Date", :jd, 2460370]
      ["Date", :mjd, 60369]
      ["Date", :ld, 161210]
      ["Date", :ajd, (4920739/2)]
      ["Date", :amjd, (60369/1)]
      ["Date", :day_fraction, 0]
      ["Date", :cwday, 4]
      ["Date", :cweek, 9]
      ["Date", :cwyear, 2024]
      ["Date", :leap?, true]
      ["Date", :julian?, false]
      ["Date", :gregorian?, true]
      ["Date", :start, 2299161.0]
      ["Date", :infinite?, false]
      ["Date", :to_s, "2024-02-29"]
      ["Date", :inspect, "#<Date: 2024-02-29 ((2460370j,0s,0n),+0s,2299161j)>"]
      ["Date", :iso8601, "2024-02-29"]
      ["Date", :xmlschema, "2024-02-29"]
      ["Date", :rfc3339, "2024-02-29T00:00:00+00:00"]
      ["Date", :rfc2822, "Thu, 29 Feb 2024 00:00:00 +0000"]
      ["Date", :httpdate, "Thu, 29 Feb 2024 00:00:00 GMT"]
      ["Date", :jisx0301, "R06.02.29"]
      ["Date", :ctime, "Thu Feb 29 00:00:00 2024"]
      ["Date", :asctime, "Thu Feb 29 00:00:00 2024"]
      ["Date", :marshal_dump, [0, 2460370, 0, 0, 0, 2299161.0]]
      ["Date", :sunday?, false]
      ["Date", :monday?, false]
      ["Date", :tuesday?, false]
      ["Date", :wednesday?, false]
      ["Date", :thursday?, true]
      ["Date", :friday?, false]
      ["Date", :saturday?, false]
      ["DateTime", :year, 2024]
      ["DateTime", :month, 1]
      ["DateTime", :mon, 1]
      ["DateTime", :day, 2]
      ["DateTime", :mday, 2]
      ["DateTime", :wday, 2]
      ["DateTime", :yday, 2]
      ["DateTime", :jd, 2460312]
      ["DateTime", :mjd, 60311]
      ["DateTime", :ld, 161152]
      ["DateTime", :ajd, (42514178449/17280)]
      ["DateTime", :amjd, (1042169809/17280)]
      ["DateTime", :day_fraction, (2209/17280)]
      ["DateTime", :cwday, 2]
      ["DateTime", :cweek, 1]
      ["DateTime", :cwyear, 2024]
      ["DateTime", :leap?, true]
      ["DateTime", :julian?, false]
      ["DateTime", :gregorian?, true]
      ["DateTime", :start, 2299161.0]
      ["DateTime", :infinite?, false]
      ["DateTime", :to_s, "2024-01-02T03:04:05+09:00"]
      ["DateTime", :inspect, "#<DateTime: 2024-01-02T03:04:05+09:00 ((2460311j,65045s,0n),+32400s,2299161j)>"]
      ["DateTime", :iso8601, "2024-01-02T03:04:05+09:00"]
      ["DateTime", :xmlschema, "2024-01-02T03:04:05+09:00"]
      ["DateTime", :rfc3339, "2024-01-02T03:04:05+09:00"]
      ["DateTime", :rfc2822, "Tue, 2 Jan 2024 03:04:05 +0900"]
      ["DateTime", :httpdate, "Mon, 01 Jan 2024 18:04:05 GMT"]
      ["DateTime", :jisx0301, "R06.01.02T03:04:05+09:00"]
      ["DateTime", :ctime, "Tue Jan  2 03:04:05 2024"]
      ["DateTime", :asctime, "Tue Jan  2 03:04:05 2024"]
      ["DateTime", :marshal_dump, [0, 2460311, 65045, 0, 32400, 2299161.0]]
      ["DateTime", :sunday?, false]
      ["DateTime", :monday?, false]
      ["DateTime", :tuesday?, true]
      ["DateTime", :wednesday?, false]
      ["DateTime", :thursday?, false]
      ["DateTime", :friday?, false]
      ["DateTime", :saturday?, false]
      [:datetime, :hour, 3]
      [:date, :hour, :not_public]
      [:datetime, :min, 4]
      [:date, :min, :not_public]
      [:datetime, :minute, 4]
      [:date, :minute, :not_public]
      [:datetime, :sec, 5]
      [:date, :sec, :not_public]
      [:datetime, :second, 5]
      [:date, :second, :not_public]
      [:datetime, :sec_fraction, (0/1)]
      [:date, :sec_fraction, :not_public]
      [:datetime, :second_fraction, (0/1)]
      [:date, :second_fraction, :not_public]
      [:datetime, :offset, (3/8)]
      [:date, :offset, :not_public]
      [:datetime, :zone, "+09:00"]
      [:date, :zone, :not_public]
      "2024-02-29"
      "2024-02-29T00:00:00+00:00"
      0
      "2024-01-02"
      "2024-01-02T03:04:05+09:00"
      "2024-01-01T18:04:05+00:00"
      "2024-01-01T18:04:05+00:00"
      "2024-01-02T03:04:05.000+09:00"
      "2024-01-02T03:04:05.000000+09:00"
      "R06.01.02T03:04:05.000+09:00"
      "2024-01-02T03:04:05+09:00"
      {year: 2024, month: 2, day: 29, yday: 60, wday: 4}
      {year: 2024, month: 1, day: 2, yday: 2, wday: 2, hour: 3, min: 4, sec: 5, sec_fraction: (0/1), zone: "+09:00"}
      "2024-03-29"
      "2024-01-29"
      "2025-02-28"
      "2024-02-29"
      "2024-03-31"
      "2021-02-28"
      "2024-03-01"
      "2024-03-01"
      ["2024-02-29", "2024-03-03", "2024-03-06", "2024-03-09"]
      ["2024-02-29", "2024-03-01", "2024-03-02"]
      ["2024-03-02", "2024-03-01", "2024-02-29"]
      ["2024-02-29", "2024-02-27", "2024-02-25"]
      []
      "2024-02-29"
      "2024-02-29"
      "2024-12-29"
      "2024-12-31"
      "2024-12-31"
      "2024-02-29"
      true
      false
      true
      false
      true
      false
      true
      true
      false
      true
      "2024-02-29"
      "2024-02-29"
      "2024-02-29"
      "2024-01-02T03:04:05+09:00"
      "2024-01-02T03:04:05+00:00"
      "2024-02-29T03:04:05+00:00"
      "1582-10-04"
      "1582-10-15"
      1721424
      "1582-10-04"
      "1582-10-15"
      "2024-02-29"
      "2024-02-29"
      "2024-02-16"
      true
      "2024-02-16"
      "2024-02-29"
      "1752-09-02"
      -1
      -1
      nil
      true
      true
      true
      true
      true
      ["2024-01-01", "2024-03-01"]
      "2024-03-01"
      "2024-02-28"
      (59/1)
      (1/2)
      "2024-03-01"
      "Thu Feb 29 00:00:00 2024 02/29/24 00:00:00 29-FEB-2024 Thu Feb 29 00:00:00 +00:00 2024 12:00:00 AM 00:00 00:00:00 02/29/24 2024-02-29"
      "2024 09 08 09 4 4 am AM 12 12  0 20 24 060"
      "00:00:00 +0000 +00:00 +00:00 1709164800 1709164800000 000 000000000"
      "2024 03:04:05 +0900 +09:00 +09:00"
      ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
      ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
      [nil, "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
      [nil, "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
      2299161
      2361222
      Infinity
      -Infinity
      [true, "invalid date"]
      [TypeError, "invalid year (not numeric)"]
      [TypeError, "no implicit conversion to float from string"]
      [TypeError, "String can't be coerced into Integer"]
      [TypeError, "expected numeric"]
      [TypeError, "expected numeric"]
    OUT
  end

  it "the proleptic-Gregorian fields, day arithmetic, ordering and Julian day all answer" do
    result = ze0(<<~'RUBY')
      require "date"

      # Construction and field access on the proleptic-Gregorian calendar.
      d = Date.new(2024, 3, 15)
      p [d.year, d.month, d.day]
      p d.wday          # 0=Sunday .. 6=Saturday
      p d.yday          # day of the year
      p d.leap?
      p d.to_s

      # strftime with common calendar directives.
      p d.strftime("%A, %B %-d, %Y")
      p d.strftime("%a %b %d")

      # Day arithmetic: + / - integers, and date - date -> Rational days.
      p (d + 30).to_s
      p (d - 15).to_s
      p (Date.new(2024, 12, 31) - Date.new(2024, 1, 1))
      p d.next.to_s

      # Ordering (Comparable) and equality.
      p (Date.new(2024, 1, 1) < Date.new(2024, 6, 1))
      p (d == Date.new(2024, 3, 15))
      p [Date.new(2024, 3, 1), Date.new(2024, 1, 1), Date.new(2024, 2, 1)].sort.map(&:to_s)

      # Julian day and parsing.
      p Date.jd(2460385).to_s
      p Date.parse("2025-07-04").to_s
      p Date.valid_date?(2024, 2, 29)
    RUBY

    _(result).must_answer <<~'OUT'
      [2024, 3, 15]
      5
      75
      true
      "2024-03-15"
      "Friday, March 15, 2024"
      "Fri Mar 15"
      "2024-04-14"
      "2024-02-29"
      (365/1)
      "2024-03-16"
      true
      true
      ["2024-01-01", "2024-02-01", "2024-03-01"]
      "2024-03-15"
      "2025-07-04"
      true
    OUT
  end

  it "next_month off the 31st lands on the last day the month has" do
    result = ze0(<<~'RUBY')
      require "date"

      d = Date.new(2024, 1, 31)
      p d.next_month.to_s
      p d.prev_month.to_s
      p d.next_year.to_s
      p d.prev_year.to_s
      p d.next_month(2).to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "2024-02-29"
      "2023-12-31"
      "2025-01-31"
      "2023-01-31"
      "2024-03-31"
    OUT
  end

  it "julian?, gregorian? and start report the reform day the date was built with" do
    result = ze0(<<~'RUBY')
      require "date"

      d = Date.new(2024, 2, 29)
      p d.julian?
      p d.gregorian?
      p d.start
      p Date::ENGLAND
      p Date::ITALY
      p d.england.to_s
      p d.italy.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      2299161.0
      2361222
      2299161
      "2024-02-29"
      "2024-02-29"
    OUT
  end

  it "to_date, to_datetime and to_time each keep the day they were given" do
    result = ze0(<<~'RUBY')
      require "date"

      d = Date.new(2024, 2, 29)
      p d.to_date.to_s
      p d.to_datetime.to_s
      p d.to_time.strftime("%Y-%m-%d %H:%M:%S")
    RUBY

    _(result).must_answer <<~'OUT'
      "2024-02-29"
      "2024-02-29T00:00:00+00:00"
      "2024-02-29 00:00:00"
    OUT
  end

  it "upto, downto and step walk the days between two dates" do
    result = ze0(<<~'RUBY')
      require "date"

      d = Date.new(2024, 2, 27)
      p d.upto(Date.new(2024, 3, 1)).map(&:to_s)
      p Date.new(2024, 3, 1).downto(d).map(&:to_s)
      p d.step(Date.new(2024, 3, 4), 2).map(&:to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      ["2024-02-27", "2024-02-28", "2024-02-29", "2024-03-01"]
      ["2024-03-01", "2024-02-29", "2024-02-28", "2024-02-27"]
      ["2024-02-27", "2024-02-29", "2024-03-02", "2024-03-04"]
    OUT
  end

  it ">> and << move whole months, clamping to the last day the month has" do
    result = ze0(<<~'RUBY')
      require "date"

      d = Date.new(2024, 1, 31)
      p (d >> 1).to_s
      p (d >> 12).to_s
      p (d << 1).to_s
      p (d << 13).to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "2024-02-29"
      "2025-01-31"
      "2023-12-31"
      "2022-12-31"
    OUT
  end

  it "Date._parse records the fields in the order its cascade finds them" do
    result = ze0(<<~'RUBY')
      # `Date._parse` -- the heuristic scanner `Date.parse`, `DateTime.parse` and
      # `Time.parse` all read their fields out of. Every line here is oracle-verified
      # against ruby 4.0.6, including the KEY ORDER: the hash records fields in the
      # order the cascade found them (weekday, then clock and zone, then the date),
      # so the order is part of the answer.
      #
      # Known divergence: a string with no date in it raises ArgumentError here where
      # ruby raises `Date::Error`, a subclass of it that zeo does not model (the date
      # extension is native, with no Ruby half to declare the class in).
      require "date"

      # ISO 8601, in the shapes a timestamp actually arrives in.
      p Date._parse("2024-01-15")
      p Date._parse("2024-01-15T10:30:00Z")
      p Date._parse("2024-01-15T10:30:00+09:00")
      p Date._parse("2024-01-15T10:30:00.123456+09:00")
      p Date._parse("2024-01-15 10:30:00 UTC")
      p Date._parse("2024-01-15T10:30")
      p Date._parse("2001-02-03T04:05:06.123456789")
      p Date._parse("2024-01-15T10:30:00,5Z")

      # RFC 2822 and HTTP-date, whose weekday name is recorded and then ignored.
      p Date._parse("Mon, 15 Jan 2024 10:30:00 +0900")
      p Date._parse("Fri, 15 Jan 2024 10:30:00 GMT")
      p Date._parse("Sat, 03 Feb 2024 04:05:06 -0000")
      p Date._parse("Thu Nov 29 14:33:20 2001")
      p Date._parse("Wed, 15 May 2024")

      # The month-NAME forms, in either order and with or without a year.
      p Date._parse("15 Jan 2024")
      p Date._parse("Jan 15 2024")
      p Date._parse("January 15, 2024")
      p Date._parse("15-Jan-2024")
      p Date._parse("Aug 31")
      p Date._parse("Aug 2000")
      p Date._parse("Aug 3rd 2000")
      p Date._parse("Jan '99")
      p Date._parse("'99 Jan 15")
      p Date._parse("Aug")

      # Separator forms. A dot date reads year-first or day-first depending on which
      # end carries the four-digit year.
      p Date._parse("2024/01/15")
      p Date._parse("2024.01.15")
      p Date._parse("5.6.2024")
      p Date._parse("31.12.99")
      p Date._parse("7/23")
      p Date._parse("2024/1")
      p Date._parse("12/2024")
      p Date._parse("1/2/3")

      # A bare digit run is read by its LENGTH, with no validation at all.
      p Date._parse("20240115")
      p Date._parse("20240115T103000Z")
      p Date._parse("20240115103000")
      p Date._parse("2000")
      p Date._parse("24")
      p Date._parse("012")
      p Date._parse("12345")
      p Date._parse("1234567")
      p Date._parse("3rd")
      p Date._parse("15th")

      # A clock on its own, with a meridian marker or a zone.
      p Date._parse("10:30")
      p Date._parse("10:30:00.5")
      p Date._parse("12:00 pm")
      p Date._parse("12:00 am")
      p Date._parse("1:30pm")
      p Date._parse("23:59:60")
      p Date._parse("10:30 JST")
      p Date._parse("10:30 -0530")
      p Date._parse("10:30 gmt-3")
      p Date._parse("10:30 Eastern Standard Time")
      p Date._parse("10:30 EST5EDT")

      # The other calendars ISO 8601 spells: a week date and an ordinal date.
      p Date._parse("2024-W03-1")
      p Date._parse("2024-015")

      # A two-digit year widens only when the caller asked for a COMPLETE date.
      p Date._parse("68-01-15")
      p Date._parse("69-01-15")
      p Date._parse("01-10-31")
      p Date._parse("01-10-31", false)
      p Date._parse("-4712-01-01")

      # Nothing recognisable answers an empty hash rather than raising -- which is
      # what lets `Time.parse` report its own error.
      p Date._parse("")
      p Date._parse("garbage")
      p Date._parse("Sat")
      p Date._parse("sunday")

      # Commentary in parentheses is dropped, as RFC 2822 allows.
      p Date._parse("2024-01-15 (a comment) 10:30")
      p Date._parse("  2024-01-15  ")

      # `Date.parse` completes the fields: everything ABOVE the most significant one
      # given is unknown, and everything below it takes its minimum.
      p Date.parse("2024-01-15").to_s
      p Date.parse("2024-015").to_s
      p Date.parse("2024-W03-1").to_s
      p Date.parse("Aug 2000").to_s
      p Date.parse("2024-01-15T10:30:00Z").to_s
      p Date.parse("15-Jan-2024").to_s
      begin
        Date.parse("10:30")
      rescue ArgumentError => e
        p [:no_date, e.message]
      end
      begin
        Date.parse("2024")
      rescue ArgumentError => e
        p [:not_a_day, e.message]
      end

      # The zone table `:offset` is filled from, exercised through the scanner (CRuby
      # keeps `zone_to_diff` to itself, so there is no public row to call directly).
      ["+09:00", "-0530", "UTC", "PST", "CEST", "A", "Y", "nowhere"].each do |z|
        p [z, Date._parse("10:30 #{z}")[:offset]]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      {year: 2024, mon: 1, mday: 15}
      {zone: "Z", hour: 10, min: 30, sec: 0, year: 2024, mon: 1, mday: 15, offset: 0}
      {zone: "+09:00", hour: 10, min: 30, sec: 0, year: 2024, mon: 1, mday: 15, offset: 32400}
      {zone: "+09:00", hour: 10, min: 30, sec: 0, sec_fraction: (1929/15625), year: 2024, mon: 1, mday: 15, offset: 32400}
      {zone: "UTC", hour: 10, min: 30, sec: 0, year: 2024, mon: 1, mday: 15, offset: 0}
      {hour: 10, min: 30, year: 2024, mon: 1, mday: 15}
      {hour: 4, min: 5, sec: 6, sec_fraction: (123456789/1000000000), year: 2001, mon: 2, mday: 3}
      {zone: "Z", hour: 10, min: 30, sec: 0, sec_fraction: (1/2), year: 2024, mon: 1, mday: 15, offset: 0}
      {wday: 1, zone: "+0900", hour: 10, min: 30, sec: 0, year: 2024, mon: 1, mday: 15, offset: 32400}
      {wday: 5, zone: "GMT", hour: 10, min: 30, sec: 0, year: 2024, mon: 1, mday: 15, offset: 0}
      {wday: 6, zone: "-0000", hour: 4, min: 5, sec: 6, year: 2024, mon: 2, mday: 3, offset: 0}
      {wday: 4, hour: 14, min: 33, sec: 20, year: 2001, mon: 11, mday: 29}
      {wday: 3, year: 2024, mon: 5, mday: 15}
      {year: 2024, mon: 1, mday: 15}
      {year: 2024, mon: 1, mday: 15}
      {year: 2024, mon: 1, mday: 15}
      {year: 2024, mon: 1, mday: 15}
      {mon: 8, mday: 31}
      {year: 2000, mon: 8}
      {year: 2000, mon: 8, mday: 3}
      {year: 1999, mon: 1}
      {year: 1999, mon: 1, mday: 15}
      {mon: 8}
      {year: 2024, mon: 1, mday: 15}
      {year: 2024, mon: 1, mday: 15}
      {year: 2024, mon: 6, mday: 5}
      {year: 2031, mon: 12, mday: 99}
      {mon: 7, mday: 23}
      {year: 2024, mon: 1}
      {year: 2024, mon: 12}
      {year: 2001, mon: 2, mday: 3}
      {year: 2024, mon: 1, mday: 15}
      {year: 2024, mon: 1, mday: 15, hour: 10, min: 30, sec: 0, zone: "Z", offset: 0}
      {year: 2024, mon: 1, mday: 15, hour: 10, min: 30, sec: 0}
      {mon: 20, mday: 0}
      {mday: 24}
      {yday: 12}
      {year: 2012, yday: 345}
      {year: 1234, yday: 567}
      {mday: 3}
      {mday: 15}
      {hour: 10, min: 30}
      {hour: 10, min: 30, sec: 0, sec_fraction: (1/2)}
      {hour: 12, min: 0}
      {hour: 0, min: 0}
      {hour: 13, min: 30}
      {hour: 23, min: 59, sec: 60}
      {zone: "JST", hour: 10, min: 30, offset: 32400}
      {zone: "-0530", hour: 10, min: 30, offset: -19800}
      {zone: "gmt-3", hour: 10, min: 30, offset: -10800}
      {zone: "Eastern Standard Time", hour: 10, min: 30, offset: -18000}
      {hour: 10, min: 30}
      {cwyear: 2024, cweek: 3, cwday: 1}
      {year: 2024, yday: 15}
      {year: 2068, mon: 1, mday: 15}
      {year: 1969, mon: 1, mday: 15}
      {year: 2001, mon: 10, mday: 31}
      {year: 1, mon: 10, mday: 31}
      {year: -4712, mon: 1, mday: 1}
      {}
      {}
      {wday: 6}
      {wday: 0}
      {hour: 10, min: 30, year: 2024, mon: 1, mday: 15}
      {year: 2024, mon: 1, mday: 15}
      "2024-01-15"
      "2024-01-15"
      "2024-01-15"
      "2000-08-01"
      "2024-01-15"
      "2024-01-15"
      [:no_date, "invalid date"]
      [:not_a_day, "invalid date"]
      ["+09:00", 32400]
      ["-0530", -19800]
      ["UTC", 0]
      ["PST", -28800]
      ["CEST", 7200]
      ["A", 3600]
      ["Y", -43200]
      ["nowhere", nil]
    OUT
  end

  it "rfc3339, httpdate, xmlschema and jisx0301 each render the same day their own way" do
    result = ze0(<<~'RUBY')
      require "date"

      d = Date.new(2024, 2, 29)
      p d.rfc3339
      p d.httpdate
      p d.xmlschema
      p d.jisx0301
    RUBY

    _(result).must_answer <<~'OUT'
      "2024-02-29T00:00:00+00:00"
      "Thu, 29 Feb 2024 00:00:00 GMT"
      "2024-02-29"
      "R06.02.29"
    OUT
  end

  it "Date._strptime keys its answer in the order the directives matched" do
    result = ze0(<<~'RUBY')
      # `Date._strptime` is the format-DIRECTED scanner behind `Date.strptime`,
      # `DateTime.strptime` and the `time` gem's `Time.strptime`. aws-sigv4's
      # `presign_url` reaches it through the last of those.
      #
      # The answered hash's key order IS the order the directives matched, so these
      # are compared as printed.
      require "date"
      require "time"

      p Date._strptime("2000-10-31", "%Y-%m-%d")
      p Date._strptime("2013-05-24T00:00:00Z", "%Y-%m-%dT%H:%M:%S%Z")

      # `%Y` is unbounded, EXCEPT when digits follow it in the format -- otherwise it
      # swallows the month and day too (CRuby's `NUM_PATTERN_P`).
      p Date._strptime("20130524T000000Z", "%Y%m%dT%H%M%S%Z")
      p Date._strptime("2013-05-24", "%Y-%m-%d")

      # A format the input does not match is nil, not a partial answer.
      p Date._strptime("nope", "%Y-%m-%d")
      p Date._strptime("2000-13-31", "%Y-%m-%d")
      p Date._strptime("", "%Y")

      # Input left OVER is fine and is reported.
      p Date._strptime("2000-10-31 extra", "%Y-%m-%d")

      # Fractions are exact Rationals, not floats.
      p Date._strptime("2024-01-02 03:04:05.678 +0530", "%Y-%m-%d %H:%M:%S.%L %z")
      p Date._strptime("01.123456789", "%S.%N")

      p Date._strptime("1369353600", "%s")
      p Date._strptime("24/12/99", "%d/%m/%y")
      p Date._strptime("24/12/68", "%d/%m/%y")
      p Date._strptime("15 Jan 2024", "%d %b %Y")
      p Date._strptime("15 January 2024", "%d %B %Y")
      p Date._strptime("Tuesday", "%A")
      p Date._strptime("07:30 PM", "%I:%M %p")
      p Date._strptime("07:30 am", "%I:%M %p")
      p Date._strptime("2024-01-02", "%F")
      p Date._strptime("03:04:05", "%T")
      p Date._strptime("50%", "%d%%")

      # What the gems actually call. `DateTime.strptime` is deliberately absent
      # here: zeo's DateTime does not model sub-day fields at all, which predates
      # this scanner -- see tests/gaps/a_datetime_keeps_its_time_of_day.rb.
      p Date.strptime("2000-10-31", "%Y-%m-%d").to_s
      p Time.strptime("2013-05-24T00:00:00Z", "%Y-%m-%dT%H:%M:%S%Z").utc.iso8601
    RUBY

    _(result).must_answer <<~'OUT'
      {year: 2000, mon: 10, mday: 31}
      {year: 2013, mon: 5, mday: 24, hour: 0, min: 0, sec: 0, zone: "Z", offset: 0}
      {year: 2013, mon: 5, mday: 24, hour: 0, min: 0, sec: 0, zone: "Z", offset: 0}
      {year: 2013, mon: 5, mday: 24}
      nil
      nil
      nil
      {year: 2000, mon: 10, mday: 31, leftover: " extra"}
      {year: 2024, mon: 1, mday: 2, hour: 3, min: 4, sec: 5, sec_fraction: (339/500), zone: "+0530", offset: 19800}
      {sec: 1, sec_fraction: (123456789/1000000000)}
      {seconds: 1369353600}
      {mday: 24, mon: 12, year: 1999}
      {mday: 24, mon: 12, year: 2068}
      {mday: 15, mon: 1, year: 2024}
      {mday: 15, mon: 1, year: 2024}
      {wday: 2}
      {hour: 19, min: 30}
      {hour: 7, min: 30}
      {year: 2024, mon: 1, mday: 2}
      {hour: 3, min: 4, sec: 5}
      nil
      "2000-10-31"
      "2013-05-24T00:00:00Z"
    OUT
  end

  it "a DateTime keeps its clock through parse, strptime and new" do
    result = ze0(<<~'RUBY')
      require "date"

      p DateTime.parse("2024-01-02T03:04:05+00:00").to_s
      p DateTime.strptime("2024-01-02T03:04:05+00:00", "%Y-%m-%dT%H:%M:%S%z").to_s
      p DateTime.new(2024, 1, 2, 3, 4, 5).to_s
      p DateTime.parse("2024-01-02T03:04:05+00:00").hour
    RUBY

    _(result).must_answer <<~'OUT'
      "2024-01-02T03:04:05+00:00"
      "2024-01-02T03:04:05+00:00"
      "2024-01-02T03:04:05+00:00"
      3
    OUT
  end

  it "nilable time strftime" do
    result = ze0(<<~'RUBY')
      # A nilable Time (`created_at : Time?`) is held as a poly value, so calling
      # strftime on it used to lower to the unresolved-call raise even for a real
      # Time. The poly dispatch now gives strftime a Time arm: a genuine Time
      # formats, nil (or any other class) raises NoMethodError -- matching CRuby.
      # Regression for issue #2457 (the family2 nilable value-method dispatch gap).
      class Note
        def initialize(t); @t = t; end
        def created_at; @t; end          # @t is Time-or-nil => Time?
      end
      def raw(s); s; end
      def fmt(a, b); "#{a}=#{b}"; end

      t = Note.new(Time.at(0).utc)
      Note.new(nil)                       # this call makes created_at nilable

      # real Time formats through several result slots
      io = String.new
      io << t.created_at.strftime("%Y-%m-%d")
      puts io
      puts raw(t.created_at.strftime("%Y-%m-%d"))
      puts fmt("day", t.created_at.strftime("%Y-%m-%d"))
      puts "at #{t.created_at.strftime("%H:%M:%S")}"

      # nil raises NoMethodError
      n = Note.new(nil)
      begin
        puts n.created_at.strftime("%F")
      rescue NoMethodError
        puts "raised"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1970-01-01
      1970-01-01
      day=1970-01-01
      at 00:00:00
      raised
    OUT
  end

  it "reopened builtin operators" do
    result = ze0(<<~'RUBY')
      # An operator redefined on a reopened builtin.
      #
      # zeo rejected this for EVERY builtin, on the reasoning that a native operator
      # fast path at the call site would silently bypass the override. Only `Int` and
      # `Float` have such a path: `codegen::call::dispatch` emits the four
      # `ops::{INT,FLOAT}_{BINARY,UNARY}_OPS` arms and then the reopened-builtin arm,
      # which sits deliberately ahead of the collection, Proc, Regexp and String fast
      # paths so that a user redefinition wins there.
      #
      # The gems: activesupport reopens `DateTime#<=>`, fast_gettext `String#%`,
      # strscan's own truffleruby shim `StringScanner#<<`, celluloid `Set#<<`.

      require "set"
      require "strscan"
      require "date"

      class String
        def %(other)
          "formatted(#{other})"
        end
      end

      class Set
        def <<(x)
          add(x.to_s)
        end
      end

      class StringScanner
        def <<(s)
          string + s
        end
      end

      class DateTime
        def <=>(_other)
          7
        end
      end

      # A statically-typed receiver, which is the arm the old guard was protecting.
      p("x" % 1)
      p(StringScanner.new("ab") << "cd")

      s = Set.new
      s << 3
      p s.to_a

      p(DateTime.new(2020, 1, 1) <=> DateTime.new(2021, 1, 1))

      # A Poly receiver. zeo never infers a parameter's type from its call sites, so
      # these reach the runtime-checked fallback -- which matches `Int`/`Float` and
      # sends every other shape through `send_value_in`'s MRO walk, where the
      # reopened row lives.
      def apply(a, b)
        a % b
      end

      def push(coll, x)
        coll << x
      end

      p apply("y", 2)
      p push(StringScanner.new("q"), "z")

      t = Set.new
      push(t, 5)
      p t.to_a

      # Integer and Float stay rejected, and so does anything else on their MRO
      # (`Numeric`, `Comparable`, `Object`, `Kernel`, `BasicObject`) -- a statically
      # `Int`-typed receiver consults all of them.
      p 1 + 2
      p 1.5 * 2
    RUBY

    _(result).must_answer <<~'OUT'
      "formatted(1)"
      "abcd"
      ["3"]
      7
      "formatted(2)"
      "qz"
      ["5"]
      3
      3.0
    OUT
  end

  it "strftime width and vms date" do
    result = ze0(<<~'RUBY')
      # Two strftime divergences left after the flag work, both about the part of a
      # directive that is NOT a flag.
      #
      # 1. An explicit WIDTH is ignored by every non-numeric directive. Ruby pads a
      #    string directive to the field width like any other; zeo's `num_pad` is the
      #    only reader of `width`, so `%10a` answers the bare day name.
      #
      #        Time.at(0).utc.strftime("%10a")   ruby "       Thu"   zeo "Thu"
      #
      #    Numeric directives already honour width (`%5Y` is `01970` in both), which
      #    is what makes this specifically the string half.
      #
      # 2. `%v` (the VMS date, `%e-%^b-%4Y`) is not implemented, so it emits verbatim.
      #
      # A width after a COLON flag is a third shape: ruby rejects `%:5z` outright and
      # emits it verbatim, where zeo renders the offset and drops the width.
      #
      # Found by a 13,800-case directive x flag x width sweep while fixing
      # `tests/strftime_zone_offset_flags.rb`; every case NOT in the three shapes
      # above matches, including all 84 `%z` flag spellings.

      t = Time.at(0).utc

      # Width on a string directive.
      p [t.strftime("%10a"), t.strftime("%10A"), t.strftime("%10b"), t.strftime("%10p")]
      p [t.strftime("%5u"), t.strftime("%5n").inspect, t.strftime("%3w")]
      p [t.strftime("%10z"), t.strftime("%10Z")]

      # The VMS date.
      p t.strftime("%v")
      p t.strftime("%^v")

      # A width after a colon flag is invalid, and stays verbatim.
      p [t.strftime("%:5z"), t.strftime("%::1z")]

      # Already correct: width on a numeric directive, and every flag spelling.
      p [t.strftime("%5Y"), t.strftime("%-5Y"), t.strftime("%_5Y"), t.strftime("%05Y")]
      p [t.strftime("%z"), t.strftime("%-z"), t.strftime("%_z"), t.strftime("%:z")]
    RUBY

    _(result).must_answer <<~'OUT'
      ["       Thu", "  Thursday", "       Jan", "        AM"]
      ["00004", "\"    \\n\"", "004"]
      ["+000000000", "       UTC"]
      " 1-JAN-1970"
      " 1-JAN-1970"
      ["%:5z", "%::1z"]
      ["01970", "1970", " 1970", "01970"]
      ["+0000", "-0000", " +000", "+00:00"]
    OUT
  end

  it "time strftime long format" do
    result = ze0(<<~'RUBY')
      # strftime output longer than the old fixed 256-byte buffer was silently
      # dropped to "". A roomier buffer now handles realistic long formats
      # (lots of literal text, repeated or wide directives). A pathological
      # field width still does not fit and yields "" gracefully (no crash);
      # that case isn't asserted here because CRuby raises Errno::ERANGE for it.
      t = Time.at(0).utc

      # %Y-%m-%d rather than %F: MinGW's libc strftime doesn't implement the
      # C99 %F directive (it returns ""), and this helper calls strftime(3)
      # directly. The buffer fix is what this test exercises, not %F.
      puts t.strftime("%Y-%m-%d")
      puts t.strftime("%Y-%m-%d %H:%M:%S")

      # ~500 bytes of output from a repeated directive
      puts t.strftime("%Y-" * 100).length

      # ~304 bytes: long literal run followed by a directive
      puts t.strftime("x" * 300 + "%Y").length

      # empty format stays empty
      p t.strftime("")
    RUBY

    _(result).must_answer <<~'OUT'
      1970-01-01
      1970-01-01 00:00:00
      500
      304
      ""
    OUT
  end

  it "a truncated document answers at every position one can be cut" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Three self-referential documents: a sequence that aliases itself, a mapping that aliases itself, and the `a` / `b` pair where `c: *a` closes the ring.
      # At exit: cycle leak: 4 objects (Hash x3, Array x1)
      # Every hostile shape the YAML loader has to survive, as ANSWERS rather
      # than as a promise. The point of the file is that none of these ends the
      # process: each row is either a value or a Ruby exception, and the golden
      # pins which.
      #
      # Written when the loader was reworked to read the anchor id and the tag
      # that the parser's events always carried, and it found real defects rather
      # than confirming a design -- see `yaml_parser_stress.rb` for the generated
      # half.
      #
      # ONE GROUP IS NOT HERE: the documents the two yaml engines disagree
      # about the legality of, which is a decided divergence recorded in
      # `tests/yaml_backend_accepts_a_different_dialect.rb`.

      require "yaml"
      require "date"

      def show(name)
        r = yield
        puts "#{name}\t#{r.inspect}"
      rescue Exception => e
        puts "#{name}\t#{e.class}"
      end

      # --- Truncation, at every position a document has ------------------------
      [
        "", " ", "---", "--- ", "-", "- ", "a:", "a: ", "{", "}", "[", "]",
        "{a", "{a:", "[1", "'", "\"", "\"a", "'a", "&", "&a", "*", "*a", "!",
        "!!", "!!str", "? ", "|", ">", "a: &", "a: *", "%YAML", "%YAML 1.1",
        "---\n..."
      ].each do |frag|
        show("truncated #{frag.inspect}") { YAML.unsafe_load(frag) }
      end

    RUBY

    _(result).must_answer <<~'OUT'
      truncated ""	false
      truncated " "	false
      truncated "---"	nil
      truncated "--- "	nil
      truncated "-"	[nil]
      truncated "- "	[nil]
      truncated "a:"	{"a" => nil}
      truncated "a: "	{"a" => nil}
      truncated "{"	Psych::SyntaxError
      truncated "}"	Psych::SyntaxError
      truncated "["	Psych::SyntaxError
      truncated "]"	Psych::SyntaxError
      truncated "{a"	Psych::SyntaxError
      truncated "{a:"	Psych::SyntaxError
      truncated "[1"	Psych::SyntaxError
      truncated "'"	Psych::SyntaxError
      truncated "\""	Psych::SyntaxError
      truncated "\"a"	Psych::SyntaxError
      truncated "'a"	Psych::SyntaxError
      truncated "&"	Psych::SyntaxError
      truncated "&a"	nil
      truncated "*"	Psych::SyntaxError
      truncated "*a"	Psych::AnchorNotDefined
      truncated "!"	nil
      truncated "!!"	Psych::SyntaxError
      truncated "!!str"	""
      truncated "? "	{nil => nil}
      truncated "|"	""
      truncated ">"	""
      truncated "a: &"	Psych::SyntaxError
      truncated "a: *"	Psych::SyntaxError
      truncated "%YAML"	Psych::SyntaxError
      truncated "%YAML 1.1"	Psych::SyntaxError
      truncated "---\n..."	nil
    OUT
  end

  it "an anchor and its alias name one object" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Three self-referential documents: a sequence that aliases itself, a mapping that aliases itself, and the `a` / `b` pair where `c: *a` closes the ring.
      # At exit: cycle leak: 4 objects (Hash x3, Array x1)
      # Every hostile shape the YAML loader has to survive, as ANSWERS rather
      # than as a promise. The point of the file is that none of these ends the
      # process: each row is either a value or a Ruby exception, and the golden
      # pins which.
      #
      # Written when the loader was reworked to read the anchor id and the tag
      # that the parser's events always carried, and it found real defects rather
      # than confirming a design -- see `yaml_parser_stress.rb` for the generated
      # half.
      #
      # ONE GROUP IS NOT HERE: the documents the two yaml engines disagree
      # about the legality of, which is a decided divergence recorded in
      # `tests/yaml_backend_accepts_a_different_dialect.rb`.

      require "yaml"
      require "date"

      def show(name)
        r = yield
        puts "#{name}\t#{r.inspect}"
      rescue Exception => e
        puts "#{name}\t#{e.class}"
      end

      # --- Anchors and aliases -------------------------------------------------
      show("simple alias") { YAML.unsafe_load("a: &x 1\nb: *x") }
      show("container alias") { YAML.unsafe_load("a: &x [1]\nb: *x") }
      show("alias shares identity") do
        v = YAML.unsafe_load("a: &x [1]\nb: *x")
        v["a"].equal?(v["b"])
      end
      show("self-referential seq") do
        v = YAML.unsafe_load("--- &1\n- *1\n")
        [v.size, v.first.equal?(v)]
      end
      show("self-referential map") do
        v = YAML.unsafe_load("--- &1\na: *1\n")
        v["a"].equal?(v)
      end
      show("mutual") do
        v = YAML.unsafe_load("a: &a\n  b: &b\n    c: *a\n")
        v["a"]["b"]["c"].equal?(v["a"])
      end
      show("anchor reused") { YAML.unsafe_load("a: &x 1\nb: &x 2\nc: *x") }
      show("undefined anchor") { YAML.unsafe_load("b: *nope") }
      show("anchor on nothing") { YAML.unsafe_load("a: &x\nb: *x") }
      show("alias without option") { YAML.safe_load("a: &x 1\nb: *x") }
      show("many aliases") { YAML.unsafe_load("a: &x [1]\n" + (0...50).map { |i| "k#{i}: *x" }.join("\n")).size }

    RUBY

    _(result).must_answer <<~'OUT'
      simple alias	{"a" => 1, "b" => 1}
      container alias	{"a" => [1], "b" => [1]}
      alias shares identity	true
      self-referential seq	[1, true]
      self-referential map	true
      mutual	true
      anchor reused	{"a" => 1, "b" => 2, "c" => 2}
      undefined anchor	Psych::AnchorNotDefined
      anchor on nothing	{"a" => nil, "b" => nil}
      alias without option	Psych::AliasesNotEnabled
      many aliases	51
    OUT
  end

  it "a merge key splices the mapping it names" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Three self-referential documents: a sequence that aliases itself, a mapping that aliases itself, and the `a` / `b` pair where `c: *a` closes the ring.
      # At exit: cycle leak: 4 objects (Hash x3, Array x1)
      # Every hostile shape the YAML loader has to survive, as ANSWERS rather
      # than as a promise. The point of the file is that none of these ends the
      # process: each row is either a value or a Ruby exception, and the golden
      # pins which.
      #
      # Written when the loader was reworked to read the anchor id and the tag
      # that the parser's events always carried, and it found real defects rather
      # than confirming a design -- see `yaml_parser_stress.rb` for the generated
      # half.
      #
      # ONE GROUP IS NOT HERE: the documents the two yaml engines disagree
      # about the legality of, which is a decided divergence recorded in
      # `tests/yaml_backend_accepts_a_different_dialect.rb`.

      require "yaml"
      require "date"

      def show(name)
        r = yield
        puts "#{name}\t#{r.inspect}"
      rescue Exception => e
        puts "#{name}\t#{e.class}"
      end

      # --- Merge keys ----------------------------------------------------------
      show("merge") { YAML.unsafe_load("b: &b {x: 1}\nc:\n  <<: *b\n  y: 2") }
      show("merge overrides") { YAML.unsafe_load("b: &b {x: 1}\nc:\n  <<: *b\n  x: 9") }
      show("merge list") { YAML.unsafe_load("a: &a {x: 1}\nb: &b {x: 2, y: 3}\nc:\n  <<: [*a, *b]") }
      show("merge inline") { YAML.unsafe_load("c:\n  <<: {x: 1}") }
      show("merge quoted key") { YAML.unsafe_load("c:\n  !!str '<<': 1") }
      show("merge of a scalar") { YAML.unsafe_load("c:\n  <<: 1") }
      show("merge of a seq of scalars") { YAML.unsafe_load("c:\n  <<: [1, 2]") }
      show("merge twice") { YAML.unsafe_load("a: &a {x: 1}\nb: &b {y: 2}\nc:\n  <<: *a\n  <<: *b") }
      show("merge self") { YAML.unsafe_load("c: &c\n  <<: *c\n  x: 1") }

    RUBY

    _(result).must_answer <<~'OUT'
      merge	{"b" => {"x" => 1}, "c" => {"x" => 1, "y" => 2}}
      merge overrides	{"b" => {"x" => 1}, "c" => {"x" => 9}}
      merge list	{"a" => {"x" => 1}, "b" => {"x" => 2, "y" => 3}, "c" => {"x" => 1, "y" => 3}}
      merge inline	{"c" => {"x" => 1}}
      merge quoted key	{"c" => {"<<" => 1}}
      merge of a scalar	{"c" => {"<<" => 1}}
      merge of a seq of scalars	{"c" => {"<<" => [1, 2]}}
      merge twice	{"a" => {"x" => 1}, "b" => {"y" => 2}, "c" => {"x" => 1, "y" => 2}}
      merge self	{"c" => {"x" => 1}}
    OUT
  end

  it "a tag decides the type of the scalar under it" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Three self-referential documents: a sequence that aliases itself, a mapping that aliases itself, and the `a` / `b` pair where `c: *a` closes the ring.
      # At exit: cycle leak: 4 objects (Hash x3, Array x1)
      # Every hostile shape the YAML loader has to survive, as ANSWERS rather
      # than as a promise. The point of the file is that none of these ends the
      # process: each row is either a value or a Ruby exception, and the golden
      # pins which.
      #
      # Written when the loader was reworked to read the anchor id and the tag
      # that the parser's events always carried, and it found real defects rather
      # than confirming a design -- see `yaml_parser_stress.rb` for the generated
      # half.
      #
      # ONE GROUP IS NOT HERE: the documents the two yaml engines disagree
      # about the legality of, which is a decided divergence recorded in
      # `tests/yaml_backend_accepts_a_different_dialect.rb`.

      require "yaml"
      require "date"

      def show(name)
        r = yield
        puts "#{name}\t#{r.inspect}"
      rescue Exception => e
        puts "#{name}\t#{e.class}"
      end

      # --- Tags ----------------------------------------------------------------
      show("tag str on a number") { YAML.unsafe_load("v: !!str 017")["v"] }
      show("tag int on text") { YAML.unsafe_load("v: !!int '42'")["v"] }
      show("tag int on garbage") { YAML.unsafe_load("v: !!int 'zz'")["v"] }
      show("tag float on int") { YAML.unsafe_load("v: !!float 3")["v"] }
      show("tag float on garbage") { YAML.unsafe_load("v: !!float 'zz'")["v"] }
      show("tag bool") { YAML.unsafe_load("v: !!bool yes")["v"] }
      show("tag binary") { YAML.unsafe_load("v: !!binary aGk=")["v"] }
      show("tag binary garbage") { YAML.unsafe_load("v: !!binary '@@@'")["v"] }
      show("tag binary empty") { YAML.unsafe_load("v: !!binary ''")["v"] }
      show("tag omap") { YAML.unsafe_load("v: !!omap\n- a: 1\n- b: 2")["v"] }
      show("tag set") { YAML.unsafe_load("v: !!set\n  ? a\n  ? b")["v"] }
      show("tag unknown") { YAML.unsafe_load("v: !whatever 42")["v"] }
      show("tag ruby symbol") { YAML.unsafe_load("v: !ruby/symbol foo")["v"] }
      show("tag on a seq") { YAML.unsafe_load("v: !!seq [1]")["v"] }

    RUBY

    _(result).must_answer <<~'OUT'
      tag str on a number	"017"
      tag int on text	42
      tag int on garbage	"zz"
      tag float on int	3.0
      tag float on garbage	ArgumentError
      tag bool	true
      tag binary	"hi"
      tag binary garbage	""
      tag binary empty	""
      tag omap	{"a" => 1, "b" => 2}
      tag set	{"a" => nil, "b" => nil}
      tag unknown	42
      tag ruby symbol	:foo
      tag on a seq	[1]
    OUT
  end

  it "a stream of several documents loads one at a time or all at once" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Three self-referential documents: a sequence that aliases itself, a mapping that aliases itself, and the `a` / `b` pair where `c: *a` closes the ring.
      # At exit: cycle leak: 4 objects (Hash x3, Array x1)
      # Every hostile shape the YAML loader has to survive, as ANSWERS rather
      # than as a promise. The point of the file is that none of these ends the
      # process: each row is either a value or a Ruby exception, and the golden
      # pins which.
      #
      # Written when the loader was reworked to read the anchor id and the tag
      # that the parser's events always carried, and it found real defects rather
      # than confirming a design -- see `yaml_parser_stress.rb` for the generated
      # half.
      #
      # ONE GROUP IS NOT HERE: the documents the two yaml engines disagree
      # about the legality of, which is a decided divergence recorded in
      # `tests/yaml_backend_accepts_a_different_dialect.rb`.

      require "yaml"
      require "date"

      def show(name)
        r = yield
        puts "#{name}\t#{r.inspect}"
      rescue Exception => e
        puts "#{name}\t#{e.class}"
      end

      # --- Documents -----------------------------------------------------------
      show("two documents") { YAML.unsafe_load("--- 1\n--- 2\n") }
      show("load_stream") { YAML.load_stream("--- 1\n--- 2\n") }
      show("empty document") { YAML.unsafe_load("---\n") }
      show("only a comment") { YAML.unsafe_load("# nothing\n") }
      show("directive") { YAML.unsafe_load("%YAML 1.1\n--- 1\n") }
      show("explicit end") { YAML.unsafe_load("--- 1\n...\n") }

    RUBY

    _(result).must_answer <<~'OUT'
      two documents	1
      load_stream	[1, 2]
      empty document	nil
      only a comment	false
      directive	1
      explicit end	1
    OUT
  end

  it "a duplicate key, a complex key and a nested flow each load" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Three self-referential documents: a sequence that aliases itself, a mapping that aliases itself, and the `a` / `b` pair where `c: *a` closes the ring.
      # At exit: cycle leak: 4 objects (Hash x3, Array x1)
      # Every hostile shape the YAML loader has to survive, as ANSWERS rather
      # than as a promise. The point of the file is that none of these ends the
      # process: each row is either a value or a Ruby exception, and the golden
      # pins which.
      #
      # Written when the loader was reworked to read the anchor id and the tag
      # that the parser's events always carried, and it found real defects rather
      # than confirming a design -- see `yaml_parser_stress.rb` for the generated
      # half.
      #
      # ONE GROUP IS NOT HERE: the documents the two yaml engines disagree
      # about the legality of, which is a decided divergence recorded in
      # `tests/yaml_backend_accepts_a_different_dialect.rb`.

      require "yaml"
      require "date"

      def show(name)
        r = yield
        puts "#{name}\t#{r.inspect}"
      rescue Exception => e
        puts "#{name}\t#{e.class}"
      end

      # --- Structure -----------------------------------------------------------
      show("duplicate keys") { YAML.unsafe_load("a: 1\na: 2") }
      show("complex key") { YAML.unsafe_load("? [1, 2]\n: 3") }
      show("nested flow") { YAML.unsafe_load("[{a: [1, {b: 2}]}]") }
      show("empty flow") { YAML.unsafe_load("[[], {}, [{}]]") }
      show("mixed indent") { YAML.unsafe_load("a:\n  b: 1\n   c: 2") }
      show("deep but legal") { YAML.unsafe_load("[" * 50 + "]" * 50).flatten.size }

    RUBY

    _(result).must_answer <<~'OUT'
      duplicate keys	{"a" => 2}
      complex key	{[1, 2] => 3}
      nested flow	[{"a" => [1, {"b" => 2}]}]
      empty flow	[[], {}, [{}]]
      mixed indent	Psych::SyntaxError
      deep but legal	0
    OUT
  end

  it "a very long scalar survives whole" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Three self-referential documents: a sequence that aliases itself, a mapping that aliases itself, and the `a` / `b` pair where `c: *a` closes the ring.
      # At exit: cycle leak: 4 objects (Hash x3, Array x1)
      # Every hostile shape the YAML loader has to survive, as ANSWERS rather
      # than as a promise. The point of the file is that none of these ends the
      # process: each row is either a value or a Ruby exception, and the golden
      # pins which.
      #
      # Written when the loader was reworked to read the anchor id and the tag
      # that the parser's events always carried, and it found real defects rather
      # than confirming a design -- see `yaml_parser_stress.rb` for the generated
      # half.
      #
      # ONE GROUP IS NOT HERE: the documents the two yaml engines disagree
      # about the legality of, which is a decided divergence recorded in
      # `tests/yaml_backend_accepts_a_different_dialect.rb`.

      require "yaml"
      require "date"

      def show(name)
        r = yield
        puts "#{name}\t#{r.inspect}"
      rescue Exception => e
        puts "#{name}\t#{e.class}"
      end

      # --- Bytes ---------------------------------------------------------------
      show("long scalar") { YAML.unsafe_load("v: #{'x' * 200_000}")["v"].size }

    RUBY

    _(result).must_answer <<~'OUT'
      long scalar	200000
    OUT
  end

  it "every value round-trips through dump and load" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Three self-referential documents: a sequence that aliases itself, a mapping that aliases itself, and the `a` / `b` pair where `c: *a` closes the ring.
      # At exit: cycle leak: 4 objects (Hash x3, Array x1)
      # Every hostile shape the YAML loader has to survive, as ANSWERS rather
      # than as a promise. The point of the file is that none of these ends the
      # process: each row is either a value or a Ruby exception, and the golden
      # pins which.
      #
      # Written when the loader was reworked to read the anchor id and the tag
      # that the parser's events always carried, and it found real defects rather
      # than confirming a design -- see `yaml_parser_stress.rb` for the generated
      # half.
      #
      # ONE GROUP IS NOT HERE: the documents the two yaml engines disagree
      # about the legality of, which is a decided divergence recorded in
      # `tests/yaml_backend_accepts_a_different_dialect.rb`.

      require "yaml"
      require "date"

      def show(name)
        r = yield
        puts "#{name}\t#{r.inspect}"
      rescue Exception => e
        puts "#{name}\t#{e.class}"
      end

      # --- Round trips ---------------------------------------------------------
      [
        { "a" => 1 },
        { "a" => [1, 2, { "b" => nil }] },
        [1.5, -0.0, true, false, nil, "x"],
        { "s" => "l1\nl2\n" },
        { "s" => "l1\nl2" },
        { nil => 1 },
        { :sym => :other },
        "héllo",
        ["", " x", "x ", "017", "true", "a: b"],
        1..3
      ].each_with_index do |v, i|
        show("round trip #{i}") { YAML.unsafe_load(YAML.dump(v)) == v }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      round trip 0	true
      round trip 1	true
      round trip 2	true
      round trip 3	true
      round trip 4	true
      round trip 5	true
      round trip 6	true
      round trip 7	true
      round trip 8	true
      round trip 9	true
    OUT
  end
end
