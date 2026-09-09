# native only: local time comes from libSystem
ENV["TZ"] = "America/New_York"
t = Time.at(1_700_000_000)
p t, t.to_s, t.to_i, t.to_f, t.utc?, t.zone, t.utc_offset, t.year, t.month, t.day, t.hour, t.min, t.sec, t.usec, t.nsec, t.wday, t.yday, t.dst?, t.mon, t.mday, t.gmt_offset
u = t.utc
p u, u.equal?(t), t.utc?, u.zone, u.utc_offset, u.hour, u.to_a, u.inspect, u.gmtime.equal?(u), u.getlocal, u.getlocal.utc?, u.getutc.equal?(u)
p Time.at(0).utc, Time.at(0, 500, :millisecond).utc, Time.at(0, 500).utc, Time.at(0, 500, :usec).utc, Time.at(0, 123456789, :nsec).utc, Time.at(1.5).utc, Time.at(0, in: "+09:00"), Time.at(0, in: "UTC"), Time.at(0, in: "Z"), Time.at(0, in: 3600), Time.at(0, in: "-05:30")
f = Time.at(1_700_000_000, 123456789, :nsec).utc
p f, f.inspect, f.to_s, f.usec, f.nsec, f.to_f, f.round, f.round(3), f.round(6), f.floor(2), f.ceil(1), Time.at(1_700_000_000, 999_999_999, :nsec).utc.round, Time.at(0, 500_000).utc.round, Time.at(0, 1_500_000).utc.round
n = Time.new(2024, 2, 29, 13, 5, 9, "+02:00")
p n, n.utc_offset, n.zone, n.utc, n.to_i, n.wday, n.yday, n.month, Time.new(2024, 2, 29, 13, 5, 9, "+02:00").utc?, Time.new(2024, 2, 29, 13, 5, 9, in: "-03:00"), Time.new(2024, 12, 31, 23, 59, 59.5, "Z"), Time.new(2000), Time.new(2000, 6), Time.new(2000, 6, 15), Time.new(2000, 6, 15, 12)
loc = Time.new(2024, 7, 4, 12, 0, 0)
p loc, loc.zone, loc.utc_offset, loc.dst?, loc.utc?, loc.utc.hour, Time.new(2024, 1, 4, 12, 0, 0).zone, Time.new(2024, 1, 4, 12, 0, 0).utc_offset, Time.local(2024, 1, 4, 12), Time.mktime(2024, 1, 4), Time.utc(2024, 1, 4, 12, 30), Time.gm(2024, 1, 4), Time.utc(2024, 1, 4, 12, 30, 15.25)
p Time.utc(2024, "jan", 4), Time.utc(2024, "Feb", 4), Time.utc(2024, 3, 4, 5, 6, 7).to_a, Time.utc(1969, 12, 31, 23, 59, 59), Time.utc(1969, 12, 31, 23, 59, 59).to_i, Time.utc(1900, 1, 1), Time.utc(2100, 2, 28).yday, Time.utc(2000, 12, 31).yday, Time.utc(2001, 12, 31).yday
a = Time.utc(2024, 1, 1, 0, 0, 0)
b = a + 86400 * 1.5
p b, a + 0.5, (b - a), (b - a).class, a - 1, b > a, a < b, a == Time.utc(2024, 1, 1), a.eql?(Time.utc(2024, 1, 1)), a.hash == Time.utc(2024, 1, 1).hash, a <=> b, b <=> a, a <=> a, a <=> 1, a == 1, [b, a].sort == [a, b], [b, a].min == a, a.between?(a - 1, b)
p a == Time.new(2024, 1, 1, 9, 0, 0, "+09:00"), a.eql?(Time.new(2024, 1, 1, 9, 0, 0, "+09:00")), Time.new(2024, 1, 1, 9, 0, 0, "+09:00"), a.getlocal("+09:00"), a.getlocal("+09:00").zone, a.getlocal(-3600), a.localtime("+01:00"), a.utc?, a.getutc, a.localtime.utc?
p a.monday?, a.sunday?, a.saturday?, Time.utc(2024, 1, 6).saturday?, Time.utc(2024, 1, 7).sunday?, Time.utc(2024, 1, 2).tuesday?, Time.utc(2024, 1, 3).wednesday?, Time.utc(2024, 1, 4).thursday?, Time.utc(2024, 1, 5).friday?
s = Time.new(2024, 3, 9, 8, 7, 6.5, "+05:30")
p s.strftime("%Y-%m-%d %H:%M:%S"), s.strftime("%y %C %e %-d %-m %j %k %l %I %p %P"), s.strftime("%a %A %b %B %h %u %w"), s.strftime("%z %:z %::z %Z"), s.strftime("%L %N %3N %6N %9N %s"), s.strftime("%F %T %D %R %r %c %x %X"), s.strftime("%% %n%t|%U %W %G %V %g"), s.strftime("%^a %^b %#p %_d %_m %05d %-H %10Y %-y %^B|%10B|%-10B|")
p Time.utc(2024, 12, 30).strftime("%G-%V %U %W"), Time.utc(2024, 1, 1).strftime("%G-%V %U %W %j"), Time.utc(2021, 1, 3).strftime("%G-%V %U %W"), Time.utc(2020, 12, 31).strftime("%G-%V"), Time.utc(2024, 1, 1, 0, 0, 0).strftime("%I %l %p"), Time.utc(2024, 1, 1, 12).strftime("%I %l %p"), Time.utc(2024, 1, 1, 23).strftime("%I %l %P")
p loc.strftime("%Z %z %c"), Time.utc(2024, 6, 1).strftime("%Z %z"), Time.new(2024, 6, 1, 0, 0, 0, "-00:30").strftime("%z %:z %Z"), Time.at(0, in: "+00:00").zone, Time.at(0, in: "+00:00").utc?, Time.at(0, in: "UTC").utc?, Time.at(0, in: "UTC").zone
p Time.utc(2024, 1, 1) + 0.25, (Time.utc(2024, 1, 1) + 0.25).nsec, Time.at(1, 1, :nsec).utc.nsec, Time.at(1, 1, :nsec).utc - Time.at(1).utc, Time.utc(2024, 1, 1).to_f, Time.at(1.1).utc.nsec, Time.at(0.1).utc.to_f, Time.utc(2024, 1, 1) - Time.utc(2023, 1, 1)
begin
  Time.utc(2024, 13, 1)
rescue ArgumentError => e
  p e.message
end
begin
  Time.utc(2024, 2, 30)
rescue ArgumentError => e
  p e.message
end
begin
  Time.new(2024, 1, 1, 25)
rescue ArgumentError => e
  p e.message
end
begin
  Time.new(2024, 1, 1, 0, 0, 0, "bogus")
rescue ArgumentError => e
  p e.message
end
begin
  Time.at("x")
rescue TypeError => e
  p e.message
end
begin
  Time.utc(2024, 1, 1) + Time.utc(2024, 1, 1)
rescue TypeError => e
  p e.message
end
begin
  Time.utc(2024, 1, 1) - "1"
rescue TypeError => e
  p e.message
end
p Time.utc(2024, 2, 29) + 86400 * 366, Time.utc(2023, 3, 12, 6, 59, 59).getlocal, Time.utc(2023, 3, 12, 7, 0, 0).getlocal, Time.utc(2023, 11, 5, 5, 30).getlocal, Time.utc(2023, 11, 5, 6, 30).getlocal, Time.new(2023, 11, 5, 1, 30, 0).utc, Time.new(2023, 3, 12, 2, 30, 0)
ENV["TZ"] = "Asia/Tokyo"
p Time.at(0), Time.at(0).zone, Time.at(0).utc_offset, Time.new(2024, 1, 1).utc, Time.now.class, Time.now.year >= 2026, (Time.now - Time.now).abs < 1, Time.now.utc_offset, Time.now.zone
ENV["TZ"] = "UTC"
p Time.at(0), Time.at(0).zone, Time.at(0).utc?, Time.new(2024, 5, 6, 7, 8, 9), Time.local(2024, 5, 6).utc?
p Time.utc(2024, 5, 6, 7, 8, 9).ctime, Time.utc(2024, 5, 6, 7, 8, 9).asctime, Time.utc(2024, 5, 6).to_date rescue p $!.class
p Time.utc(2024, 5, 6, 7, 8, 9).succ rescue p $!.class
p Time.utc(2024, 5, 6, 7, 8, 9).hash.class, Time.utc(2024, 5, 6).frozen?, Time.utc(2024, 5, 6).dup == Time.utc(2024, 5, 6), Time.utc(2024, 5, 6).class, Time.ancestors.include?(Comparable), Time.utc(2024, 5, 6).localtime.utc_offset
gc = 20.times.map { |i| Time.utc(2000 + i, 1, 1) + i * 0.001 }
GC.start
p gc.map(&:year).sum, gc.last.nsec, gc.map(&:to_i).minmax
