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
