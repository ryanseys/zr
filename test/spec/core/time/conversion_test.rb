# frozen_string_literal: true

require "spec_helper"

describe "Time: conversion" do
  it "a sub-second argument past its unit's range carries into the whole seconds" do
    result = ze0(<<~'RUBY')
      p Time.at(1, 1_000_000).to_i
      p Time.at(1, 1_000_000).usec
      p Time.at(1, 1_500_000).to_i
      p Time.at(1, 1_500_000).usec
      p Time.at(0, 2500, :millisecond).to_f
      p Time.at(1, 500).usec
    RUBY

    _(result).must_answer <<~'OUT'
      2
      0
      2
      500000
      2.5
      500
    OUT
  end

  it "Time.at takes in: as a name, an offset string or a number of seconds, and refuses a bad one" do
    result = ze0(<<~'RUBY')
      p Time.at(0, in: "UTC").utc?
      p Time.at(0, in: 3600).utc_offset
      p Time.at(0, in: "Z").utc?
      r = (Time.at(0, in: "bogus") rescue $!.class); p r
      p Time.at(1, 2, in: "+09:00").to_i
      p Time.at(0, in: "+09:00").utc_offset
      p Time.at(Rational(3, 2), in: "+09:00").to_f
      p Time.at(1.5, in: "+09:00").to_f
    RUBY

    _(result).must_answer <<~'OUT'
      true
      3600
      true
      ArgumentError
      1
      32400
      1.5
      1.5
    OUT
  end

  it "asctime, to_a, to_r, round, floor, ceil and deconstruct_keys each answer in UTC" do
    result = ze0(<<~'RUBY')
      # Time#asctime/to_a/to_r/round/floor/ceil/xmlschema/deconstruct_keys.
      # All in UTC so the golden output is portable across build hosts.
      t = Time.at(1_700_000_000.5).utc
      puts t.asctime
      p t.to_a
      p t.to_r
      p Time.at(100).to_r                 # always Rational, even whole: (100/1)
      p t.round.subsec                    # 0
      p Time.at(1_700_000_000.7654321).round(3).subsec
      p Time.at(1_700_000_000.7654321).floor(2).subsec
      p Time.at(1_700_000_000.7654321).ceil(2).subsec
      p Time.at(-0.5).round.to_r          # half-up toward +Infinity => (0/1)
      puts t.xmlschema
      puts t.xmlschema(3)
      p t.deconstruct_keys([:year, :month, :day])
      p t.deconstruct_keys(nil)
    RUBY

    _(result).must_answer <<~'OUT'
      Tue Nov 14 22:13:20 2023
      [20, 13, 22, 14, 11, 2023, 2, 318, false, "UTC"]
      (3400000001/2)
      (100/1)
      0
      (153/200)
      (19/25)
      (77/100)
      (0/1)
      2023-11-14T22:13:20Z
      2023-11-14T22:13:20.500Z
      {year: 2023, month: 11, day: 14}
      {year: 2023, month: 11, day: 14, yday: 318, wday: 2, hour: 22, min: 13, sec: 20, subsec: (1/2), dst: false, zone: "UTC"}
    OUT
  end

  it "tv_sec and to_r answer on a Time read out of an array or a hash" do
    result = ze0(<<~'RUBY')
      a001 = [Time.utc(2020, 1, 2)]
      p a001[0].tv_sec
      p a001[0].to_r
      h003 = { k: Time.utc(2020, 1, 2) }
      p h003[:k].tv_sec
      t = Time.utc(2020, 1, 2)
      p t.tv_sec
      p t.to_r
      p a001[0].to_i
      p a001[0].year
    RUBY

    _(result).must_answer <<~'OUT'
      1577923200
      (1577923200/1)
      1577923200
      1577923200
      (1577923200/1)
      1577923200
      2020
    OUT
  end

  it "gmtime and localtime flip the presentation flag, leaving the instant alone" do
    result = ze0(<<~'RUBY')
      # Time#gmtime / #localtime (and the getutc / getlocal variants) flip the
      # UTC-presentation flag. The underlying instant is unchanged, so these
      # checks stay timezone-independent.
      t = Time.utc(2000, 1, 2, 3, 4, 5)

      # gmtime / getutc present the instant in UTC.
      p t.gmtime.year
      p t.gmtime.hour
      p t.getutc.hour
      p t.getutc.min

      # localtime changes the presentation, but flipping back to UTC restores
      # the original broken-down fields (the instant is preserved).
      p t.localtime.utc.hour
      p t.localtime.getutc.year

      # The epoch second is invariant across presentation flips.
      p t.to_i == t.localtime.to_i
      p t.to_i == t.gmtime.to_i
    RUBY

    _(result).must_answer <<~'OUT'
      2000
      3
      3
      4
      3
      2000
      true
      true
    OUT
  end

  it "Time + Time is a TypeError, and between? with a non-Time bound is an ArgumentError" do
    result = ze0(<<~'RUBY')
      # Time + Time is a TypeError and Time#between?/#clamp with non-Time bounds is
      # an ArgumentError; both read the operand as a number and did not build
      # (#3865).
      t = Time.utc(2020, 1, 2)
      u = Time.utc(2020, 1, 3)
      begin; p(t + t); rescue => e; p e.class; end
      begin; p t.between?(1, 2); rescue => e; p e.class; end
      begin; p t.clamp(1, 2); rescue => e; p e.class; end
      p((t + 60).to_i - t.to_i)
      p t.between?(Time.utc(2020, 1, 1), u)
      p((u - t).to_i)
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      ArgumentError
      ArgumentError
      60
      true
      86400
    OUT
  end

  it "utc?, usec, nsec and tv_sec read the fields the instant already holds" do
    result = ze0(<<~'RUBY')
      # Time instance accessors that read existing sp_Time fields:
      #   utc? / gmt?      -> the is_utc presentation flag (bool)
      #   tv_usec / usec   -> microsecond fraction (tv_nsec / 1000)
      #   tv_nsec / nsec   -> nanosecond fraction
      #   tv_sec           -> whole epoch seconds (alias of to_i)
      g = Time.utc(1997, 11, 21, 9, 55, 6)
      puts g.utc?
      puts g.gmt?

      l = Time.local(1997, 11, 21, 9, 55, 6)
      puts l.utc?

      a = Time.at(1.5)
      puts a.tv_sec
      puts a.tv_usec
      puts a.usec
      puts a.tv_nsec
      puts a.nsec
      puts a.utc?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      1
      500000
      500000
      500000000
      500000000
      false
    OUT
  end

  it "to_a answers the civil parts with the zone, and to_r the exact epoch" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 7, 16, 13, 45, 30)
      p t.to_a
      p t.to_r
    RUBY

    _(result).must_answer <<~'OUT'
      [30, 45, 13, 16, 7, 2026, 4, 197, false, "UTC"]
      (1784209530/1)
    OUT
  end
end
