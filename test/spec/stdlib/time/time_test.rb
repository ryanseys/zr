# frozen_string_literal: true

require "spec_helper"

describe "Time: the time library" do
  it "sym hash method dispatch" do
    result = zr(<<~'RUBY')
      require "time"  # Time#iso8601 is require-gated stdlib (matches CRuby)


      def t_sym_hash_method_dispatch
        # #510. `sym_str_hash` and `sym_poly_hash` got the right type
        # tag at analyze time but the codegen dispatch had no arms for
        # merge / fetch / dup / delete — every call emitted 0 with a
        # "cannot resolve call to '<m>' on sym_<x>_hash" warning.
        #
        # Fix: added codegen arms for the missing operations, with
        # matching runtime helpers (sp_SymStrHash_merge, sp_SymPolyHash_delete)
        # emitted alongside the existing sp_SymStrHash_* set / declared in
        # the runtime header. fetch's default value is boxed via
        # box_expr_to_poly so the ternary's arms agree on sp_RbVal type.
        # Analyze: fetch on sym_poly_hash / str_poly_hash returns poly
        # (so the receiving LV slot widens to sp_RbVal).

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
        # Issue #414. `Time#iso8601` and `Time#strftime` were unresolved on
        # a Time receiver -- spinel emitted a `cannot resolve call to ...
        # on time (emitting 0)` warning and the result fell back to int.
        # Downstream `.length` / string concat then either cascaded more
        # (emitting 0) warnings or surfaced as a C-compile error at any
        # typed-string sink.
        #
        # Fix:
        #   - Runtime: sp_time_iso8601(t) and sp_time_strftime(t, fmt) in
        #     lib/sp_runtime.h, both delegating to libc strftime against
        #     the local-time broken-down value. iso8601 splices a colon
        #     into the %z offset to match CRuby's "+HH:MM" form.
        #   - Inference: infer_method_name_type returns "string" when
        #     mname is "iso8601" / "strftime" AND recv is a Time.
        #   - Codegen: compile_object_method_expr's `recv_type == "time"`
        #     arm dispatches to the new runtime helpers.
        #
        # Coverage: shape rather than exact-string assertions, since the
        # output depends on the system clock + local-time offset. We
        # assert that both calls return a string of the expected length
        # and that the surrounding format characters land in the right
        # positions.
        #
        # The runtime computes the offset via mktime(gmtime(s)) - s rather
        # than strftime's %z, so the format is stable across libcs --
        # previous attempts relied on POSIX %z (±HHMM) but Windows MSVCRT
        # emits the timezone *name* instead, blowing past any reasonable
        # length cap.

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
        # Issue #418. `Time#utc` was unresolved on a Time receiver --
        # emitted a `cannot resolve call to 'utc' on time (emitting 0)`
        # warning and the result fell back to int. Sibling shape to #414
        # (iso8601 / strftime); ActiveRecord's `fill_timestamps` does
        # `Time.now.utc.iso8601` to produce UTC-suffixed timestamp
        # strings, and with iso8601 resolved post-#414 but utc still
        # unresolved, the chain broke one step earlier.
        #
        # Fix:
        #   - Runtime: sp_Time gains an `is_utc` flag (C99 compound
        #     literals zero-init the new field, so existing
        #     `(sp_Time){sec, nsec}` sites stay valid). sp_time_utc(t)
        #     returns the same instant with is_utc set; sp_time_iso8601
        #     and sp_time_strftime check the flag and dispatch through
        #     gmtime when it's set.
        #   - Codegen: compile_object_method_expr's recv_type=="time" arm
        #     dispatches `utc` to sp_time_utc.
        #   - Inference: infer_method_name_type returns "time" when mname
        #     is "utc" and recv resolves to time.
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

        # Local iso8601 still works (regression check on #414's path).
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
        # #553 (cielavenir). `N.times.map { block-returns-array }`
        # now collects into a sp_PtrArray rather than sp_IntArray.
        # Pre-fix codegen always built sp_IntArray for the outer
        # accumulator, then `sp_IntArray_push` was handed an sp_IntArray
        # pointer as its mrb_int second argument -- -Wint-conversion
        # warning at compile time, garbage values at runtime.
        #
        # The fix routes any block-returns-array shape (int_array,
        # str_array, float_array, sym_array, poly_array, or any
        # *_ptr_array nesting) through sp_PtrArray; analyze's
        # `<inner>_ptr_array` static type already existed for the
        # normal `recv.map { array }` arm and the inspect helpers
        # (sp_IntArrayPtrArray_inspect etc.) know how to format it.

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
        # main object, the same as inside an instance method. Spinel currently
        # emits `self->iv_x = ...` for ivar access but the script's top-level
        # function has no `self` parameter, so the C compiler errors with
        # `use of undeclared identifier 'self'`. The ivar read also falls
        # through type inference and gets defaulted to `int`, producing a
        # bogus "cannot resolve call to 'push' on int" warning before the
        # hard error.

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
      # A fixed-offset Time (is_utc kind 2) renders its CIVIL fields shifted by
      # utc_off. sp_time_vtm has always done that -- so #hour, #to_s and #inspect
      # were right -- but strftime / iso8601 / xmlschema read the 3-state kind as a
      # boolean and took the UTC branch, printing UTC clock fields under a %z that
      # correctly said otherwise.

      require "time"  # Time#iso8601 / #xmlschema are require-gated stdlib

      t = Time.at(1689676186).getlocal(-5 * 3600)

      # the accessors that already routed through sp_time_vtm
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

      # a fixed-offset time has no zone NAME, so %Z is empty. (CRuby's Time#zone
      # returns nil for this kind where spinel returns ""; making #zone nilable is a
      # return-type change, not a formatter one, so it is left alone here.)
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
