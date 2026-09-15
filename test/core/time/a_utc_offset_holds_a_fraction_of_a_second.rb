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

__END__
19800
(7201/2)
nil
"1970-01-01 01:00:00 +010001"
(7201/2)
"2000-01-01 00:00:00.5 +010001"
"+0100 +01:00"
#<ArgumentError: utc_offset out of range>
