require "date"
p Date.civil(2010, 1, 1).cweek, Date.civil(2007, 12, 31).cweek
d = Date.commercial(2004, 1, 1); p [d.year, d.month, d.day, d.cwyear]
[[2004, 53, 1], [2004, 53, 0], [2004, 54, 1], [2003, 52, 1], [2003, 53, 1]].each { |a| p((Date.commercial(*a) rescue $!.class)) }
p Date.valid_commercial?(1582, -12, -4), Date.valid_commercial?(2007, -44, -2), Date.valid_commercial?(1999, -53, -1)
p((Date.today.deconstruct_keys(1) rescue $!), (DateTime.now.deconstruct_keys(1) rescue $!))
p((Date.today << "a" rescue $!))
p((DateTime.new(-4712, 1, 1, 1.5, 0, 0, 0) rescue $!), (DateTime.new(-4712, 1, 1, 1 + 1/2r, 0) rescue $!))
p DateTime.new(2001, 2, 3, 1.5), DateTime.new(2001, 2, 3, 4, 5, 59.5).sec, DateTime.new(2001, 2, 3, 24)
p((DateTime.parse("2012-11-08T15:43:61") rescue $!), DateTime.parse("2012-11-08T15:43:60"))
p DateTime.new(2000, 4, 6, 0, 0, Rational(999999999999, 1000_000_000_000)).strftime("%12N")
t = Time.utc(3, 12, 31, 23, 58, 59); p t.to_datetime.to_time.utc == t
p DateTime.civil(1582, 10, 4, 23, 58, 59).to_time.utc
p DateTime.new(2012, 12, 24, 12, 23, 0, "+03:00").to_time.utc_offset
p (DateTime.now.to_time - Time.now).abs < 2
p DateTime.jd(2451944, 1.5), DateTime.ordinal(2001, 34, 4, 5, 6.5), DateTime.commercial(2001, 5, 6, 4, 5, 6, "+7")
