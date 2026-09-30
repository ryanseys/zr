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
