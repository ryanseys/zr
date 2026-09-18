# Date, its calendar arithmetic and ruby own loose reader.
require "date"

d = Date.new(2001, 2, 3)
dt = DateTime.new(2001, 2, 3, 4, 5, 6, "+07:00")
p d.to_s, d.inspect, d.jd, d.mjd, d.ajd, d.yday, d.wday, d.cwyear, d.cweek, d.cwday, d.leap?
p dt.to_s, dt.hour, dt.min, dt.sec, dt.offset, dt.zone, dt.new_offset("-05:00").to_s
p (d + 30).to_s, (d - 30).to_s, (d >> 13).to_s, (d << 2).to_s, (Date.new(2000, 1, 31) >> 1).to_s
p (Date.new(2000, 3, 1) - Date.new(2000, 1, 1)), d.step(d + 6, 2).map(&:to_s)
p d.strftime("%Y-%m-%d %H:%M:%S %j %U %W %V %G %u %w %C %y %e %A %B %s")
p dt.strftime("%FT%T%:z|%z|%N|%L|%p|%P|%c|%+")
p d.ctime, d.iso8601, d.rfc3339, d.rfc2822, d.httpdate, d.jisx0301
p dt.iso8601(6), dt.jisx0301, dt.httpdate

["2001-02-03", "3rd Feb 2001", "Feb 3 2001", "Sat, 3 Feb 2001 04:05:06 +0700",
 "H13.02.03", "2001-W05-6", "20010203T040506Z", "2/3/2001", "4:05:06 pm EST"].each do |text|
  p [text, Date._parse(text), Date.parse(text).to_s]
end
p Date._strptime("2001-02-03 04:05:06", "%Y-%m-%d %H:%M:%S")
p Date.strptime("02/03/01", "%m/%d/%y").to_s
p DateTime.strptime("2001-02-03T04:05:06+07:00", "%FT%T%z").to_s
p Date._iso8601("2001-034"), Date._rfc2822("Sat, 3 Feb 2001 04:05:06 +0700"), Date._httpdate("Sat, 03 Feb 2001 04:05:06 GMT")
p Date.valid_date?(2001, 2, 29), Date.valid_date?(2000, 2, 29), Date.leap?(1900), Date.julian_leap?(1900)
p Date.new(1582, 10, 4).to_s, Date.new(1582, 10, 15).to_s, Date.new(1582, 10, 5, Date::JULIAN).to_s
p Date.jd(0).to_s, Date.ordinal(2001, 34).to_s, Date.commercial(2001, 5, 6).to_s
p Marshal.load(Marshal.dump(dt)).to_s
begin
  Date.new(2001, 2, 30)
rescue Date::Error => e
  p [e.class, e.message]
end
p Date.today.is_a?(Date), Date.today.to_time.is_a?(Time)
