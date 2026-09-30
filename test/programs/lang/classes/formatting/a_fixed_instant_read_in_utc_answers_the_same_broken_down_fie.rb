# The P-B core classes: File, Dir, Time, Process, ENV.
#
# Everything here is zone- and machine-independent on purpose: Time uses a
# fixed epoch read in UTC, paths are built under a scratch directory this
# script creates, and nothing prints a real pid/clock/environment value --
# only facts about them. That is what lets the output be diffed against real
# ruby at all.

# --- Time: a fixed instant, read in UTC ------------------------------------
t = Time.at(1700000000).getutc
puts t.to_s
puts t.inspect
p [t.year, t.month, t.day, t.hour, t.min, t.sec]
p [t.wday, t.yday]
p t.to_i
p t.utc?
p t.zone
p t.utc_offset
p t.monday?, t.tuesday?

# strftime -- the directive table, including Ruby's own padding flags.
puts t.strftime("%Y-%m-%d %H:%M:%S")
puts t.strftime("%F %T")
puts t.strftime("%a %A %b %B")
puts t.strftime("%j %u %w %p %I")
puts t.strftime("%z %Z")
puts t.strftime("100%% literal")
jan = Time.at(1704067200).getutc  # 2024-01-01, a single-digit month
puts jan.strftime("%m|%-m|%_m")

# Arithmetic: `t + n` is a Time, `t - other_time` is a Float of seconds.
p (t + 60).to_i
p (t - 60).to_i
p (Time.at(100) - Time.at(40))
p (Time.at(100) - Time.at(40)).class

# A Float epoch is kept EXACTLY -- `subsec` answers the double's true
# fraction, and `nsec` is the truncated view of it.
p Time.at(0.5).subsec
p Time.at(10.8).subsec
p Time.at(10.8).nsec
p (Time.at(10.8) - 0.9).nsec
p Time.at(1.25).to_f
p Time.at(-0.5).to_i           # floored: second -1 ...
p Time.at(-0.5).nsec           # ... plus a positive remainder

# Time includes Comparable, so the whole ordering surface follows from <=>.
p Time.at(5) < Time.at(6)
p Time.at(5).between?(Time.at(1), Time.at(9))
p Time.at(1).clamp(Time.at(2), Time.at(5)).to_i
p [Time.at(3), Time.at(1), Time.at(2)].sort.map(&:to_i)
p Time.at(5) == Time.at(5)
p Time.at(5).getutc == Time.at(5)   # equality is by instant, not by zone
p({ Time.at(99) => "found" }[Time.at(99)])

# The civil constructors. `Time.utc`'s 7th argument is MICROSECONDS...
u = Time.utc(2007, 11, 1, 15, 25, 0, 123456)
p u.usec
p u.nsec
puts u.inspect
# ...while `Time.new`'s is a UTC OFFSET in seconds.
o = Time.new(2000, 1, 1, 0, 0, 0, 3600)
p o.utc_offset
p o.utc?
puts o.to_s

