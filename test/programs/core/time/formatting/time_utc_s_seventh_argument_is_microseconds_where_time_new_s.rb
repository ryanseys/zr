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
