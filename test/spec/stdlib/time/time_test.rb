# frozen_string_literal: true

require "spec_helper"

describe "Time: the time library" do
  it "sym hash method dispatch" do
    result = zr(<<~'RUBY')
      require "time"  # Time#iso8601 is require-gated stdlib (matches CRuby)


      def t_sym_hash_method_dispatch
        # merge / fetch / dup / delete on a Symbol-keyed Hash with String
        # values, and on a Symbol-keyed Hash with values of mixed types.
        # fetch with a default answers the stored value or the default.

        # sym_str_hash.merge
        base = { href: "/path" }
        extra = { class: "btn" }
        puts base.merge(extra).length

        # sym_str_hash.dup
        h = { a: "1", b: "2" }
        d = h.dup
        puts d.length

        # sym_str_hash.delete
        h2 = { a: "1", b: "2", c: "3" }
        h2.delete(:b)
        puts h2.length

        # sym_poly_hash.fetch with default
        opts = { method: :delete, form_class: "btn-form", id: 42 }
        m = opts.fetch(:method, :nope)
        puts m
        n = opts.fetch(:missing, :fallback)
        puts n

        # sym_poly_hash.dup + delete
        od = opts.dup
        od.delete(:method)
        puts od.length
      end
      t_sym_hash_method_dispatch
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      2
      delete
      fallback
      2
    OUT
  end

  it "the broken-down accessors, utc_offset and zone all answer whatever the host zone is" do
    result = zr(<<~'RUBY')
      require "time"  # Time#iso8601 is require-gated stdlib (matches CRuby)


      def t_time_accessors
        # Local Time.new + broken-down accessors + scalar inspect +
        # utc_offset / zone. Accessors are checked against Time.at(0).utc
        # so the expected values are TZ-independent. Time.new is checked by
        # reading the constructed value back in the same local zone, which
        # also round-trips regardless of the host TZ.
        u = Time.at(0).utc
        puts u.year
        puts u.mon
        puts u.mday
        puts u.hour
        puts u.min
        puts u.sec
        puts u.wday
        puts u.yday
        puts u.utc_offset
        puts u.zone
        puts u.isdst
        puts u.dst?
        p u
        puts u

        t = Time.new(2026, 5, 16, 9, 30, 15)
        puts t.year
        puts t.mon
        puts t.mday
        puts t.hour
        puts t.min
        puts t.sec
        puts Time.new(2026).mon
        puts Time.new(2026).mday
        puts Time.new(2026).hour

        a = Time.at(0).utc
        b = Time.at(1).utc
        puts(a < b)
        puts(b > a)
        puts(a <= Time.at(0).utc)
        puts(a >= Time.at(0).utc)
        puts(a == Time.at(0).utc)
        puts(a != b)
        puts(a <=> b)
        puts(b <=> a)
        puts(a <=> Time.at(0).utc)
        puts(a == Time.at(0))
        puts((Time.at(0) + 60).to_i)
        puts((Time.at(100) - 40).to_i)
        puts((Time.at(0).utc + 1).zone)
        c = Time.at(1000) + 234
        puts c.to_i
        puts((Time.at(10) + 0.5).to_f)
        puts((Time.at(10) - 0.5).to_f)
        puts((Time.at(0) + 1.5).to_i)
        puts((Time.at(0) + 2.25).to_f)
        puts((Time.at(5) - 1.25).to_f)
      end
      t_time_accessors
    RUBY

    _(result).must_answer <<~'OUT'
      1970
      1
      1
      0
      0
      0
      4
      1
      0
      UTC
      false
      false
      1970-01-01 00:00:00 UTC
      1970-01-01 00:00:00 UTC
      2026
      5
      16
      9
      30
      15
      1
      1
      0
      true
      true
      true
      true
      true
      true
      -1
      1
      0
      true
      60
      60
      UTC
      1234
      10.5
      9.5
      1
      2.25
      3.75
    OUT
  end

  it "iso8601 and strftime resolve on a Time receiver and answer a String" do
    result = zr(<<~'RUBY')
      require "time"  # Time#iso8601 is require-gated stdlib (matches CRuby)


      def t_time_iso8601_strftime
        # `Time#iso8601` and `Time#strftime` on a Time receiver answer a
        # String. iso8601 writes the offset in CRuby's "+HH:MM" form.
        #
        # Coverage: shape rather than exact-string assertions, since the
        # output depends on the system clock + local-time offset. We
        # assert that both calls return a string of the expected length
        # and that the surrounding format characters land in the right
        # positions.
        #
        # The offset is always numeric, never a timezone *name*, so the
        # length is the same on each platform.

        t = Time.now
        iso = t.iso8601

        # iso8601 produces exactly "YYYY-MM-DDTHH:MM:SS[+-]HH:MM":
        # 19 chars for the date+time prefix + 6 chars for the offset = 25.
        puts iso.length == 25 ? "iso-len-ok" : "iso-len-bad"

        # Per-position shape: dashes at 4/7, T at 10, colons at 13/16,
        # sign at 19, colon at 22.
        puts iso[4] == "-" && iso[7] == "-" && iso[10] == "T" &&
             iso[13] == ":" && iso[16] == ":" &&
             (iso[19] == "+" || iso[19] == "-") && iso[22] == ":" ? "iso-shape-ok" : "iso-shape-bad"

        # strftime: a fixed-format that survives clock variation.
        ymd = t.strftime("%Y-%m-%d")
        puts ymd.length == 10 ? "ymd-len-ok" : "ymd-len-bad"
        puts ymd[4] == "-" && ymd[7] == "-" ? "ymd-shape-ok" : "ymd-shape-bad"

        # strftime year-only: 4 digits.
        yr = t.strftime("%Y")
        puts yr.length == 4 ? "yr-ok" : "yr-bad"
      end
      t_time_iso8601_strftime
    RUBY

    _(result).must_answer <<~'OUT'
      iso-len-ok
      iso-shape-ok
      ymd-len-ok
      ymd-shape-ok
      yr-ok
    OUT
  end

  it "utc resolves on a Time receiver, and chaining iso8601 onto it answers a Zulu string" do
    result = zr(<<~'RUBY')
      require "time"  # Time#iso8601 is require-gated stdlib (matches CRuby)


      def t_time_utc
        # `Time#utc` on a Time receiver answers the same instant in UTC.
        # ActiveRecord's `fill_timestamps` does `Time.now.utc.iso8601` to
        # make UTC-suffixed timestamp strings. iso8601 and strftime on a
        # UTC time use the UTC clock fields.
        #
        # Coverage:
        #   - Time.now.utc.iso8601 round-trip (the canonical chain) -- the
        #     output ends in "Z" rather than "+HH:MM".
        #   - Time.now.utc.strftime to verify the flag also reaches the
        #     strftime path.
        #   - utc-then-non-utc (no double-flip): subsequent .utc on an
        #     already-utc time keeps the same shape (idempotent).

        t = Time.now.utc
        iso = t.iso8601

        # UTC iso8601 form: "YYYY-MM-DDTHH:MM:SSZ" -- 20 chars, ends in Z.
        puts iso.length == 20 ? "utc-iso-len-ok" : "utc-iso-len-bad"
        puts iso[19] == "Z" ? "utc-iso-zulu-ok" : "utc-iso-zulu-bad"

        # strftime against UTC: %H is the hour-of-day, which differs from
        # local hour by the timezone offset (unless we're already in
        # UTC). We can't assert an exact value (depends on system clock),
        # but we can verify it's a 2-digit number.
        hh = t.strftime("%H")
        puts hh.length == 2 && hh[0] >= "0" && hh[0] <= "2" ? "utc-hh-ok" : "utc-hh-bad"

        # Idempotent: utc on an already-utc time keeps the same shape.
        iso2 = t.utc.iso8601
        puts iso2.length == 20 && iso2[19] == "Z" ? "utc-idempotent-ok" : "utc-idempotent-bad"

        # Local iso8601 still works.
        puts Time.now.iso8601.length == 25 ? "local-iso-still-ok" : "local-iso-broken"
      end
      t_time_utc
    RUBY

    _(result).must_answer <<~'OUT'
      utc-iso-len-ok
      utc-iso-zulu-ok
      utc-hh-ok
      utc-idempotent-ok
      local-iso-still-ok
    OUT
  end

  it "times map nested array" do
    result = zr(<<~'RUBY')
      require "time"  # Time#iso8601 is require-gated stdlib (matches CRuby)


      def t_times_map_nested_array
        # `N.times.map { block-returns-array }` answers an Array of
        # Arrays, and each inner Array keeps its elements.

        a = 2.times.map { (0..2).map { |i| i + 1 } }
        p a

        b = 3.times.map { [10, 20, 30] }
        p b
      end
      t_times_map_nested_array
    RUBY

    _(result).must_answer "[[1, 2, 3], [1, 2, 3]]\n[[10, 20, 30], [10, 20, 30], [10, 20, 30]]\n"
  end

  it "toplevel ivar array" do
    result = zr(<<~'RUBY')
      require "time"  # Time#iso8601 is require-gated stdlib (matches CRuby)


      def t_toplevel_ivar_array
        # Top-level instance variables: `@x` at script scope binds to the
        # main object, the same as inside an instance method. An ivar that
        # holds an Array takes `push` like any other Array.

        @n = 0
        @n = @n + 1
        @n = @n + 1
        puts @n

        @arr = []
        @arr.push(7)
        @arr.push(8)
        puts @arr.length
        @arr.each { |v| puts v }
      end
      t_toplevel_ivar_array
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      7
      8
    OUT
  end

  it "a fixed-offset Time keeps its own clock fields through strftime, iso8601 and xmlschema" do
    result = zr(<<~'RUBY')
      # A fixed-offset Time renders its CIVIL fields shifted by its UTC offset.
      # This is true for #hour, #to_s and #inspect, and also for strftime,
      # iso8601 and xmlschema. They do not print UTC clock fields.

      require "time"  # Time#iso8601 / #xmlschema are require-gated stdlib

      t = Time.at(1689676186).getlocal(-5 * 3600)

      # the plain accessors
      p t.hour
      p t.to_s

      # strftime: every field directive, not just %z
      p t.strftime("%Y-%m-%d %H:%M:%S %z")
      p t.strftime("%H:%M")
      p t.strftime("%a, %d %b %Y %H:%M:%S %z")  # RFC 2822, the RSS-feed shape
      p t.strftime("%j")                        # day-of-year crosses the date line
      p t.strftime("%s")                        # epoch stays zone-independent

      # iso8601 / xmlschema: civil fields AND the zone suffix
      p t.iso8601
      p t.xmlschema
      p t.iso8601(3)

      # a date that rolls back over midnight under the offset
      p Time.at(1689638400).getlocal(-5 * 3600).iso8601  # 2023-07-18T00:00:00Z

      # east of Greenwich, and the whole thing again through Time.new's 7th argument
      e = Time.at(1689676186).getlocal(9 * 3600)
      p e.strftime("%Y-%m-%d %H:%M:%S %z")
      p e.iso8601
      p Time.new(2000, 1, 1, 12, 0, 0, "+09:00").iso8601

      # a fixed-offset time has no zone NAME, so %Z is empty. (The example does
      # not check #zone, which CRuby answers nil for this kind.)
      p t.strftime("%Z")

      # the UTC and host-local kinds are unchanged
      u = Time.utc(2026, 7, 16, 13, 45, 30)
      p u.strftime("%Y-%m-%d %H:%M:%S %z")
      p u.strftime("%Z")
      p u.iso8601
      p u.iso8601(6)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      "2023-07-18 05:29:46 -0500"
      "2023-07-18 05:29:46 -0500"
      "05:29"
      "Tue, 18 Jul 2023 05:29:46 -0500"
      "199"
      "1689676186"
      "2023-07-18T05:29:46-05:00"
      "2023-07-18T05:29:46-05:00"
      "2023-07-18T05:29:46.000-05:00"
      "2023-07-17T19:00:00-05:00"
      "2023-07-18 19:29:46 +0900"
      "2023-07-18T19:29:46+09:00"
      "2000-01-01T12:00:00+09:00"
      ""
      "2026-07-16 13:45:30 +0000"
      "UTC"
      "2026-07-16T13:45:30Z"
      "2026-07-16T13:45:30.000000Z"
    OUT
  end

  it "Time.parse and its stricter siblings read every shape the gem builds on Date._parse" do
    result = zr(<<~'RUBY')
      # `Time.parse` and its stricter siblings, from the vendored `time` gem. All of
      # them delegate to `Date._parse` (see `tests/date_parse_heuristics.rb`); this
      # file pins what the gem builds on top of it.
      #
      # Every case names its zone explicitly and compares in UTC: a string with no
      # zone means LOCAL time, which is not the same answer on two machines.
      require "time"

      p Time.parse("2024-01-15 10:30:00 UTC").utc.to_s
      p Time.parse("2024-01-15T10:30:00Z").utc.to_s
      p Time.parse("2024-01-15T10:30:00+09:00").utc.to_s
      p Time.parse("2024-01-15T10:30:00-05:00").utc.to_s
      p Time.parse("Mon, 15 Jan 2024 10:30:00 +0900").utc.to_s
      p Time.parse("Fri, 15 Jan 2024 10:30:00 GMT").utc.to_s
      p Time.parse("15 Jan 2024 10:30:00 UTC").utc.to_s
      p Time.parse("2024-01-15T10:30:00.5Z").utc.usec

      # The format-specific parsers, which validate rather than guess.
      p Time.iso8601("2024-01-15T10:30:00Z").utc.to_s
      p Time.xmlschema("2024-01-15T10:30:00+09:00").utc.to_s
      p Time.rfc2822("Mon, 15 Jan 2024 10:30:00 +0900").utc.to_s
      p Time.rfc822("Mon, 15 Jan 2024 10:30:00 -0500").utc.to_s
      p Time.httpdate("Fri, 15 Jan 2024 10:30:00 GMT").utc.to_s

      # And the formatters that answer them.
      t = Time.utc(2024, 1, 15, 10, 30, 0)
      p t.iso8601
      p t.xmlschema
      p t.rfc2822
      p t.httpdate

      # A round trip through each format.
      p Time.iso8601(t.iso8601).utc == t
      p Time.rfc2822(t.rfc2822).utc == t
      p Time.httpdate(t.httpdate).utc == t

      # A string with no time in it at all, and one the strict parsers reject.
      begin
        Time.parse("garbage")
      rescue ArgumentError => e
        p [:parse, e.message]
      end
      begin
        Time.rfc2822("2024-01-15")
      rescue ArgumentError => e
        p [:rfc2822, e.message]
      end
      begin
        Time.httpdate("Mon Jan 15 2024")
      rescue ArgumentError => e
        p [:httpdate, e.message]
      end

      # `Time.zone_offset` reads the same zone names the scanner does.
      p Time.zone_offset("UTC")
      p Time.zone_offset("EST")
      p Time.zone_offset("+09:00")
      p Time.zone_offset("-0530")
      p Time.zone_offset("nowhere")
    RUBY

    _(result).must_answer <<~'OUT'
      "2024-01-15 10:30:00 UTC"
      "2024-01-15 10:30:00 UTC"
      "2024-01-15 01:30:00 UTC"
      "2024-01-15 15:30:00 UTC"
      "2024-01-15 01:30:00 UTC"
      "2024-01-15 10:30:00 UTC"
      "2024-01-15 10:30:00 UTC"
      500000
      "2024-01-15 10:30:00 UTC"
      "2024-01-15 01:30:00 UTC"
      "2024-01-15 01:30:00 UTC"
      "2024-01-15 15:30:00 UTC"
      "2024-01-15 10:30:00 UTC"
      "2024-01-15T10:30:00Z"
      "2024-01-15T10:30:00Z"
      "Mon, 15 Jan 2024 10:30:00 -0000"
      "Mon, 15 Jan 2024 10:30:00 GMT"
      true
      true
      true
      [:parse, "no time information in \"garbage\""]
      [:rfc2822, "not RFC 2822 compliant date: \"2024-01-15\""]
      [:httpdate, "not RFC 2616 compliant date: \"Mon Jan 15 2024\""]
      0
      -18000
      32400
      -19800
      nil
    OUT
  end
end
