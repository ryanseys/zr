# frozen_string_literal: true

require "spec_helper"

describe "Time: formatting and inspection" do
  it "strftime, arithmetic and the epoch readers answer without a system ruby" do
    result = ze0(<<~'RUBY')
      # The time library is linked: parsing, arithmetic and formatting all work
      # without a system ruby.
      t = Time.at(1_700_000_000).utc
      puts t.strftime("%Y-%m-%d %H:%M:%S %Z")
      puts (t + 86_400).strftime("%A")
      puts t.to_i, t.usec
      puts Time.utc(2026, 9, 2).yday
    RUBY

    _(result).must_answer <<~'OUT'
      2023-11-14 22:13:20 UTC
      Wednesday
      1700000000
      0
      245
    OUT
  end

  it "Time.at takes a Rational or a Time, refuses what is not numeric, and Time.new parses a string" do
    result = ze0(<<~'RUBY')
      # Time.at with Rational / Time / non-numeric arguments, the 10-argument
      # reversed constructor form, and the string-parsing Time.new.

      # Time.at(Rational) is the exact fractional epoch, floored to the nanosecond
      p Time.at(Rational(1500, 1000)).nsec
      p Time.at(Rational(3, 2)).to_f
      p Time.at(Rational(-1, 3)).to_i
      p Time.at(Rational(-1, 3)).nsec
      p Time.at(Rational(7, 1)).nsec

      # Time.at(Time) copies the instant
      p Time.at(Time.at(55)).to_i
      p Time.at(Time.at(1.5)).nsec

      # non-numeric arguments raise CRuby's TypeError
      def at_it(x); Time.at(x); end
      begin; at_it("0"); rescue TypeError => e; puts "#{e.class}: #{e.message}"; end
      begin; Time.at(nil); rescue TypeError => e; puts "#{e.class}: #{e.message}"; end
      begin; Time.at(:sym); rescue TypeError => e; puts "#{e.class}: #{e.message}"; end

      # 10-argument reversed form (sec, min, hour, day, mon, year, wday, yday, isdst, tz)
      p Time.utc(1, 15, 20, 1, 1, 2000, 0, 0, 0, 0).inspect
      p Time.gm(30, 0, 12, 25, 12, 1999, 0, 0, 0, 0).inspect
      p Time.local(1, 15, 20, 1, 1, 2000, 0, 0, 0, 0).year

      # string-parsing Time.new
      t = Time.new("2021-12-25 10:00:00 +09:00")
      p t.month
      p t.utc_offset
      p t.inspect
      p t.hour
      u = Time.new("2021-12-25 10:00:00 UTC")
      p u.utc?
      p u.inspect
      n = Time.new("2021-12-25 10:00:00")
      p n.hour
      p n.min
      f = Time.new("2021-12-25 10:00:00.5 +00:00")
      p f.nsec
      p f.inspect

      # unparseable strings raise CRuby's ArgumentError messages
      def parse_it(s); Time.new(s); end
      begin; parse_it("garbage"); rescue ArgumentError => e; puts "#{e.class}: #{e.message}"; end
      begin; parse_it("2021-12-25"); rescue ArgumentError => e; puts "#{e.class}: #{e.message}"; end
    RUBY

    _(result).must_answer <<~'OUT'
      500000000
      1.5
      -1
      666666666
      0
      55
      500000000
      TypeError: can't convert String into an exact number
      TypeError: can't convert NilClass into an exact number
      TypeError: can't convert Symbol into an exact number
      "2000-01-01 20:15:01 UTC"
      "1999-12-25 12:00:30 UTC"
      2000
      12
      32400
      "2021-12-25 10:00:00 +0900"
      10
      true
      "2021-12-25 10:00:00 UTC"
      10
      0
      500000000
      "2021-12-25 10:00:00.5 +0000"
      ArgumentError: can't parse: "garbage"
      ArgumentError: no time information
    OUT
  end

  it "a UTC string and a numeric +00:00 render alike but disagree on #utc?" do
    result = ze0(<<~'RUBY')
      # Time.at(Time) copies the instant; the 10-arg to_a order; the string
      # form (offset / UTC / local / fractional); and UTC vs a numeric +00:00
      # (which render differently and disagree on #utc?).

      p Time.at(Time.at(55)).to_i
      p Time.at(Time.at(1.5)).nsec
      p Time.utc(1, 15, 20, 1, 1, 2000, 0, 0, 0, 0).inspect
      t = Time.new("2021-12-25 10:00:00 +09:00")
      p t.utc_offset
      p t.inspect
      u = Time.new("2021-12-25 10:00:00 UTC")
      p u.utc?
      p u.inspect
      f = Time.new("2021-12-25 10:00:00.5 +00:00")
      p f.nsec
      p f.utc?
      p f.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      55
      500000000
      "2000-01-01 20:15:01 UTC"
      32400
      "2021-12-25 10:00:00 +0900"
      true
      "2021-12-25 10:00:00 UTC"
      500000000
      false
      "2021-12-25 10:00:00.5 +0000"
    OUT
  end

  it "Time.utc's seventh argument is microseconds where Time.new's is a UTC offset" do
    result = ze0(<<~'RUBY')
      # The civil constructors disagree about their 7th argument on purpose:
      # `Time.utc`'s is MICROSECONDS, `Time.new`'s is a UTC OFFSET in seconds.
      # Both range-check it. Also: `inspect` renders an offset's seconds where
      # `to_s` doesn't.

      u = Time.utc(2007, 11, 1, 15, 25, 0, 123456)
      p u.usec
      p u.nsec
      puts u.inspect
      p u.utc?

      o = Time.new(2000, 1, 1, 0, 0, 0, 3600)
      p o.utc_offset
      p o.utc?
      puts o.to_s

      # An offset that is not a whole minute: to_s truncates, inspect does not.
      s = Time.new(2000, 1, 1, 0, 0, 0, 123)
      puts s.to_s
      puts s.inspect

      begin
        Time.utc(2000, 1, 1, 0, 0, 0, 1000000)
      rescue ArgumentError => e
        puts "usec: #{e.message}"
      end
      begin
        Time.new(2000, 1, 1, 0, 0, 0, 86400)
      rescue ArgumentError => e
        puts "offset: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      123456
      123456000
      2007-11-01 15:25:00.123456 UTC
      true
      3600
      false
      2000-01-01 00:00:00 +0100
      2000-01-01 00:00:00 +0002
      2000-01-01 00:00:00 +000203
      usec: subsecx out of range
      offset: utc_offset out of range
    OUT
  end

  it "inspect shows the sub-second digits with the trailing zeros trimmed, and to_s never does" do
    result = ze0(<<~'RUBY')
      # `inspect` shows sub-second digits (trailing zeros trimmed); `to_s` never
      # does.

      t = Time.at(1700000000.5).getutc
      puts t.inspect
      puts t.to_s
      puts Time.at(1700000000).getutc.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      2023-11-14 22:13:20.5 UTC
      2023-11-14 22:13:20 UTC
      2023-11-14 22:13:20 UTC
    OUT
  end

  it "the marshal wire format is the bit-packed civil words with the nano and zone ivars" do
    result = ze0(<<~'RUBY')
      # Time's marshal wire format, byte-for-byte (time.c time_mdump/mload): the
      # 8-byte bit-packed UTC civil words, the year-extension tail, and the
      # nano/submicro/offset/zone instance variables beside them.
      def hex(s) = s.unpack1("H*")

      p hex(Marshal.dump(Time.utc(2020, 1, 2, 3, 4, 5)))
      p hex(Marshal.dump(Time.new(2020, 1, 2, 3, 4, 5, 3600)))
      p hex(Marshal.dump(Time.utc(2020, 1, 2, 3, 4, 5.123456789r)))
      p hex(Marshal.dump(Time.utc(99_999, 1, 1)))
      p hex(Marshal.dump(Time.utc(1500, 6, 15, 12)))

      # The private pair itself.
      p Time.utc(2020, 1, 2, 3, 4, 5).send(:_dump).unpack1("H*")
      p Time.private_instance_methods(false).include?(:_dump)

      # Round-trips preserve instant, zone mode, and sub-second exactness.
      t = Marshal.load(Marshal.dump(Time.utc(2020, 1, 2, 3, 4, 5)))
      p [t, t.utc?, t.zone]
      t2 = Marshal.load(Marshal.dump(Time.new(2020, 1, 2, 3, 4, 5, 3600)))
      p [t2, t2.utc_offset, t2.zone, t2.utc?]
      t3 = Marshal.load(Marshal.dump(Time.utc(2020, 1, 2, 3, 4, 5.123456789r)))
      p [t3.nsec, t3.subsec]
      t4 = Marshal.load(Marshal.dump(Time.utc(99_999, 1, 1)))
      p [t4.year, t4.utc?]
      t5 = Marshal.load(Marshal.dump(Time.utc(1500, 6, 15, 12)))
      p [t5.year, t5.hour]

      # Cross-loading CRuby's own canonical bytes (a 4.0.6 dump of
      # 2020-01-02 03:04:05 UTC).
      bytes = ["040849753a0954696d650d43001ec000005010063a097a6f6e65492208555443063a064546"].pack("H*")
      p Marshal.load(bytes)

      # `_load` with garbage refuses with CRuby's message.
      begin
        Time.send(:_load, "short")
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "040849753a0954696d650d43001ec000005010063a097a6f6e65492208555443063a064546"
      "040849753a0954696d650d42001e8000005010073a0b6f66667365746902100e3a097a6f6e6530"
      "040849753a0954696d650d43001ec040e25110093a0d6e616e6f5f6e756d690215033a0d6e616e6f5f64656e69063a0d7375626d6963726f220778903a097a6f6e65492208555443063a064546"
      "040849753a0954696d651020c0ffff0000000007347f063a097a6f6e65492208555443063a064546"
      "040849753a0954696d6510ec1500c000000000079001063a097a6f6e65492208555443063a064546"
      "43001ec000005010"
      true
      [2020-01-02 03:04:05 UTC, true, "UTC"]
      [2020-01-02 03:04:05 +0100, 3600, nil, false]
      [123456789, (123456789/1000000000)]
      [99999, true]
      [1500, 12]
      2020-01-02 03:04:05 UTC
      marshaled time format differ
    OUT
  end

  it "utc and localtime convert in place, where the get forms answer a copy" do
    result = ze0(<<~'RUBY')
      # `utc`/`gmtime`/`localtime` convert the receiver IN PLACE and answer self;
      # the `get*` forms answer a copy and leave the receiver alone.

      t = Time.at(1700000000)
      u = t.getutc
      p u.utc?
      p t.utc?          # getutc did NOT mutate t
      t.utc
      p t.utc?          # ...but utc did
      puts t.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      2023-11-14 22:13:20 UTC
    OUT
  end

  it "a negative year pads to four digits after the sign" do
    result = ze0(<<~'RUBY')
      p Time.utc(-1).to_s
      p Time.gm(-1).to_s
      p Time.utc(-12).to_s
      p Time.utc(1).to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "-0001-01-01 00:00:00 UTC"
      "-0001-01-01 00:00:00 UTC"
      "-0012-01-01 00:00:00 UTC"
      "0001-01-01 00:00:00 UTC"
    OUT
  end

  it "Time.new tells an unparseable string from one carrying no time" do
    result = ze0(<<~'RUBY')
      [["garbage", "can't parse"], ["2021-12-25", "no time information"]].each do |s, _|
        begin
          Time.new(s)
        rescue ArgumentError => e
          puts "#{e.class}: #{e.message}"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: can't parse: "garbage"
      ArgumentError: no time information
    OUT
  end

  it "usec, nsec and subsec read the fraction, and two equal instants hash alike" do
    result = ze0(<<~'RUBY')
      # Time sub-second precision, fixed utc_offset construction, exact Float
      # shifts, and value-based hash.

      # usec through Time.utc's 7th argument
      t = Time.utc(2007, 11, 1, 15, 25, 0, 123456)
      p t.usec
      p t.nsec
      p t.subsec
      p t.inspect
      p t.to_s          # to_s never renders the fraction
      puts t            # puts uses to_s

      # subsec of a whole second is Integer 0
      p Time.utc(2020, 1, 1).subsec
      p Time.utc(2020, 1, 1).inspect

      # fraction rendering trims trailing zeros
      p Time.at(0.5).utc.inspect
      p Time.at(1.25).utc.inspect

      # usec range checks
      begin; Time.utc(2000, 1, 1, 0, 0, 0, 1000000); rescue ArgumentError => e; puts "#{e.class}: #{e.message}"; end
      begin; Time.utc(2000, 1, 1, 0, 0, 0, -1); rescue ArgumentError => e; puts "#{e.class}: #{e.message}"; end

      # Time.local also takes the usec argument (zone-independent accessors only)
      l = Time.local(1997, 11, 21, 9, 55, 6, 42)
      p l.usec
      p l.nsec

      # exact Float shifts: the double's binary value decides the nanosecond
      p (Time.at(100) + -1.3).usec
      p (Time.at(100) - 1.3).usec
      p (Time.at(0) + 0.5).nsec
      p (Time.at(10) + 2.25).to_f
      p Time.at(-0.5).to_i
      p Time.at(-0.5).nsec

      # shifts preserve the zone kind and the sub-second value
      s = Time.utc(2000, 1, 1, 0, 0, 0, 250000)
      p (s + 1).usec
      p (s + 1).utc?
      p (s + 1).inspect

      # Time.new with an explicit utc_offset (7th argument)
      o = Time.new(2000, 1, 1, 0, 0, 0, 123)
      p o.utc_offset
      p o.utc?
      p o.inspect
      p o.hour

      n = Time.new(2000, 1, 1, 12, 0, 0, "+09:00")
      p n.utc_offset
      p n.inspect
      p n.hour

      m = Time.new(2000, 1, 1, 12, 0, 0, -3600)
      p m.utc_offset
      p m.inspect

      # offset bounds
      begin; Time.new(2000, 1, 1, 0, 0, 0, 86400); rescue ArgumentError => e; puts "#{e.class}: #{e.message}"; end

      # equal instants hash equal; Time works as a Hash key
      a = Time.at(1234)
      b = Time.at(1234)
      p a.hash == b.hash
      p a.hash == Time.at(1235).hash
      u = Time.at(1.5)
      v = Time.at(1.5)
      p u.hash == v.hash
      h = { Time.at(99) => "x" }
      p h[Time.at(99)]
    RUBY

    _(result).must_answer <<~'OUT'
      123456
      123456000
      (1929/15625)
      "2007-11-01 15:25:00.123456 UTC"
      "2007-11-01 15:25:00 UTC"
      2007-11-01 15:25:00 UTC
      0
      "2020-01-01 00:00:00 UTC"
      "1970-01-01 00:00:00.5 UTC"
      "1970-01-01 00:00:01.25 UTC"
      ArgumentError: subsecx out of range
      ArgumentError: subsecx out of range
      42
      42000
      699999
      699999
      500000000
      12.25
      -1
      500000000
      250000
      true
      "2000-01-01 00:00:01.25 UTC"
      123
      false
      "2000-01-01 00:00:00 +000203"
      0
      32400
      "2000-01-01 12:00:00 +0900"
      12
      -3600
      "2000-01-01 12:00:00 -0100"
      ArgumentError: utc_offset out of range
      true
      false
      true
      "x"
    OUT
  end

  it "to_s renders YYYY-MM-DD HH:MM:SS +ZZZZ with no fraction" do
    result = ze0(<<~'RUBY')
      # Time#to_s renders the "YYYY-MM-DD HH:MM:SS +ZZZZ" form (no subsecond
      # fraction). Use .utc for a timezone-independent, deterministic string.
      t = Time.at(1700000000).utc
      puts t.to_s
      puts t.to_s.length > 0
    RUBY

    _(result).must_answer <<~'OUT'
      2023-11-14 22:13:20 UTC
      true
    OUT
  end

  it "a fixed instant read in UTC answers every civil field the same on any machine" do
    result = ze0(<<~'RUBY')
      # A fixed instant read in UTC -- zone-independent, so these are safe to
      # assert on any machine. Oracle-read for epoch 1700000000.

      t = Time.at(1700000000).getutc
      puts t.to_s
      p [t.year, t.month, t.day, t.hour, t.min, t.sec]
      p [t.wday, t.yday]
      p t.to_i
      p t.utc?
      p t.zone
      p t.utc_offset
      p [t.monday?, t.tuesday?]
      puts Time.at(0).getutc.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      2023-11-14 22:13:20 UTC
      [2023, 11, 14, 22, 13, 20]
      [2, 318]
      1700000000
      true
      "UTC"
      0
      [false, true]
      1970-01-01 00:00:00 UTC
    OUT
  end

  it "a year under four digits zero-pads in to_s, inspect and %Y alike" do
    result = ze0(<<~'RUBY')
      [[1, 1, 1], [9, 2, 3], [99, 3, 4], [999, 12, 31], [1000, 1, 1],
       [2024, 1, 1], [10000, 1, 1]].each do |y, m, d|
        t = Time.utc(y, m, d)
        puts [t.to_s, t.inspect, t.strftime("%Y"), t.year, t.strftime("%Y-%m-%d")].join(" | ")
      end

      t = Time.utc(1, 6, 15, 12, 30, 45)
      p t.to_s
      p t.strftime("%Y/%m/%d %H:%M:%S")

      p Time.utc(99, 1, 1).year
      p Time.utc(99, 1, 1).year.to_s

      p Time.utc(10000, 1, 1).strftime("%Y")

      p Time.utc(1, 1, 1, 0, 0, 0).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      0001-01-01 00:00:00 UTC | 0001-01-01 00:00:00 UTC | 0001 | 1 | 0001-01-01
      0009-02-03 00:00:00 UTC | 0009-02-03 00:00:00 UTC | 0009 | 9 | 0009-02-03
      0099-03-04 00:00:00 UTC | 0099-03-04 00:00:00 UTC | 0099 | 99 | 0099-03-04
      0999-12-31 00:00:00 UTC | 0999-12-31 00:00:00 UTC | 0999 | 999 | 0999-12-31
      1000-01-01 00:00:00 UTC | 1000-01-01 00:00:00 UTC | 1000 | 1000 | 1000-01-01
      2024-01-01 00:00:00 UTC | 2024-01-01 00:00:00 UTC | 2024 | 2024 | 2024-01-01
      10000-01-01 00:00:00 UTC | 10000-01-01 00:00:00 UTC | 10000 | 10000 | 10000-01-01
      "0001-06-15 12:30:45 UTC"
      "0001/06/15 12:30:45"
      99
      "99"
      "10000"
      "0001-01-01 00:00:00 UTC"
    OUT
  end

  it "utc offset holds a fraction of a second" do
    result = ze0(<<~'RUBY')
      # A utc_offset may hold a fraction of a second: the wall clock reads the
      # instant moved by the whole offset and shows whole seconds, and inspect
      # shows the offset's seconds, rounded, after its hours and minutes.
      t = Time.new(2020, 1, 1, 0, 0, 0, "+05:30")
      p t.utc_offset
      t2 = Time.at(0, in: 3600.5)
      p t2.utc_offset, t2.zone, t2.inspect
      t3 = Time.new(2000, 1, 1, 0, 0, 0, Rational(7201, 2))
      p t3.utc_offset, t3.inspect, t3.strftime("%z %:z")
      p((Time.at(0, in: 86400.5) rescue $!))

    RUBY

    _(result).must_answer <<~'OUT'
      19800
      (7201/2)
      nil
      "1970-01-01 01:00:00 +010001"
      (7201/2)
      "2000-01-01 00:00:00.5 +010001"
      "+0100 +01:00"
      #<ArgumentError: utc_offset out of range>
    OUT
  end
end
