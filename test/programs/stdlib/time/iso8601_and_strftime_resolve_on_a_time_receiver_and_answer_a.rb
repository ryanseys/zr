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
