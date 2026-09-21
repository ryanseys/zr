# frozen_string_literal: true

require "spec_helper"

describe "Time: regressions" do
  it "Time.at keeps the fraction of a Float epoch" do
    result = ze0(<<~'RUBY')
      c = Time.at(1_600_000_000.5)
      p c.utc.to_f
    RUBY

    _(result).must_answer "1600000000.5\n"
  end

  it "Time#deconstruct_keys answers every field, or only the ones asked for" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 7, 16, 13, 45, 30)
      p t.deconstruct_keys(nil)
      p t.deconstruct_keys([:zone])
    RUBY

    _(result).must_answer <<~'OUT'
      {year: 2026, month: 7, day: 16, yday: 197, wday: 4, hour: 13, min: 45, sec: 30, subsec: 0, dst: false, zone: "UTC"}
      {zone: "UTC"}
    OUT
  end

  it "floor, ceil and round take the number of sub-second digits to keep" do
    result = ze0(<<~'RUBY')
      t = Time.at(1234567890.123456789)
      p t.floor(1).nsec
      p t.floor(3).nsec
      p t.ceil(3).nsec
      p t.round(3).nsec
      p t.round(0).nsec
      p t.round(0).sec
      p t.ceil(0).sec
      p t.floor(2).class
      u = Time.at(1000000000.9999999)
      p u.ceil(1).nsec
      p u.round(6).nsec
    RUBY

    _(result).must_answer <<~'OUT'
      100000000
      123000000
      124000000
      123000000
      0
      30
      31
      Time
      0
      0
    OUT
  end

  it "strftime takes the - and _ flags to trim or pad a field" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2001, 2, 3, 4, 5, 6)
      puts t.strftime("%-d/%-m")
      puts t.strftime("%_d")
      puts t.strftime("%-H:%-M:%-S")
      puts t.strftime("%_m")
      puts t.strftime("%d/%m")
      t2 = Time.utc(2001, 12, 25, 14, 0, 0)
      puts t2.strftime("%-d %-m %-H")
      puts t2.strftime("%-M")
    RUBY

    _(result).must_answer "3/2\n 3\n4:5:6\n 2\n03/02\n25 12 14\n0\n"
  end

  it "the Time constructors take a Rational number of seconds" do
    result = ze0(<<~'RUBY')
      p Time.utc(2020,1,1,0,0,0, Rational(1,2)).nsec
      p Time.utc(2020,1,1,0,0,0, Rational(1,4)).nsec
      p Time.gm(2020,1,1,0,0,0, Rational(3,2)).nsec
      p Time.local(2020,1,1,0,0,0, Rational(1,2)).nsec
      p Time.utc(2020,1,1,0,0,0, Rational(1,2))
    RUBY

    _(result).must_answer <<~'OUT'
      500
      250
      1500
      500
      2020-01-01 00:00:00.0000005 UTC
    OUT
  end

  it "the Time constructors take a fractional number of microseconds" do
    result = ze0(<<~'RUBY')
      puts Time.utc(2001,2,3,4,5,6,500.5).nsec
      puts Time.gm(2001,2,3,4,5,6,250000.5).nsec
      puts Time.utc(2001,2,3,4,5,6,500).nsec
      u = 123.5
      puts Time.utc(2001,2,3,4,5,6,u).nsec
    RUBY

    _(result).must_answer <<~'OUT'
      500500
      250000500
      500000
      123500
    OUT
  end

  it "getlocal and localtime take an offset as seconds or as +HH:MM" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2001, 2, 3, 4, 5, 6)
      puts t.getlocal(3600).utc_offset
      puts t.getlocal(3600).hour
      puts t.getlocal("+09:00").utc_offset
      puts t.getlocal("+09:00").hour
      puts t.getlocal("-05:00").utc_offset
      puts t.getlocal(-18000).hour
      l = t.localtime(7200)
      puts l.utc_offset
      puts l.hour
    RUBY

    _(result).must_answer <<~'OUT'
      3600
      5
      32400
      13
      -18000
      23
      7200
      6
    OUT
  end

  it "xmlschema takes the number of fractional digits to print" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2001, 2, 3, 4, 5, 6, 500000)
      puts t.xmlschema
      puts t.xmlschema(3)
      puts t.xmlschema(6)
    RUBY

    _(result).must_answer <<~'OUT'
      2001-02-03T04:05:06Z
      2001-02-03T04:05:06.500Z
      2001-02-03T04:05:06.500000Z
    OUT
  end

  it "iso8601 takes the number of fractional digits to print" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2001, 2, 3, 4, 5, 6, 500000)
      puts t.iso8601
      puts t.iso8601(3)
      puts t.iso8601(6)
      t2 = Time.utc(2001, 2, 3, 4, 5, 6, 123456)
      puts t2.iso8601(3)
      puts t2.iso8601(9)
    RUBY

    _(result).must_answer <<~'OUT'
      2001-02-03T04:05:06Z
      2001-02-03T04:05:06.500Z
      2001-02-03T04:05:06.500000Z
      2001-02-03T04:05:06.123Z
      2001-02-03T04:05:06.123456000Z
    OUT
  end

  it "the Time constructors refuse a field outside its range, but roll a leap second over" do
    result = ze0(<<~'RUBY')
      def cls; begin; yield; rescue => e; e.class; end; end
      p(cls { Time.utc(2020,13,1) })
      p(cls { Time.utc(2020,1,32) })
      p Time.utc(2020,2,30).month
      p(cls { Time.utc(2020,1,1,25) })
      p Time.utc(2020,12,31,23,59,60).year
      p(cls { Time.local(2020,0,1) })
      p Time.utc(2020,2,29).day
      p Time.new(2020,6,15,10,30,0).hour
      p(cls { Time.utc(2020,1,1,23,60) })
      p(cls { Time.utc(2020,1,1,23,59,61) })
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      ArgumentError
      3
      ArgumentError
      2021
      ArgumentError
      29
      10
      ArgumentError
      ArgumentError
    OUT
  end

  it "min, sort and sort_by order Times read out of a container" do
    result = ze0(<<~'RUBY')
      p(Time.new(2026, 1, 2) <=> Time.new(2026, 1, 1))
      a = [Time.new(2026, 1, 2), Time.new(2026, 1, 1)]
      p(a[0] <=> a[1])
      r1 = (a.min.day rescue $!.class); p r1
      r2 = (a.sort.map(&:day) rescue $!.class); p r2
      r3 = (a.sort_by { |t| t }.map(&:day) rescue $!.class); p r3
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      1
      [1, 2]
      [1, 2]
    OUT
  end

  it "a frozen Time answers utc when it is already UTC, and names itself when a change is refused" do
    result = ze0(<<~'RUBY')
      t = Time.at(0).utc.freeze
      p t.utc.equal?(t), t.gmtime.equal?(t), t.year, t.inspect
      begin; t.localtime; rescue => e; p e.class, e.message; end
      l = Time.at(0).localtime("+09:00").freeze
      begin; l.localtime("+09:00"); rescue => e; p e.class, e.message; end
      begin; l.utc; rescue => e; p e.class, e.message; end
      p l.hour, l.to_a.size, l.strftime("%Y")
      u = Time.utc(2000, 1, 2).freeze
      p u.utc.year, u.getlocal("+01:00").hour, (u + 1).frozen?, u.round.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      1970
      "1970-01-01 00:00:00 UTC"
      FrozenError
      "can't modify frozen Time: 1970-01-01 00:00:00 UTC"
      FrozenError
      "can't modify frozen Time: 1970-01-01 09:00:00 +0900"
      FrozenError
      "can't modify frozen Time: 1970-01-01 09:00:00 +0900"
      9
      10
      "1970"
      2000
      1
      false
      false
    OUT
  end
end
