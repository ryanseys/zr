# A fixed instant read in UTC -- zone-independent, so these are safe to
# assert on any machine. Oracle-read for epoch 1700000000.

t = Time.at(1700000000).getutc
puts t.to_s
p [t.year, t.month, t.day, t.hour, t.min, t.sec]
p [t.wday, t.yday]
p t.to_i
p t.utc?
p t.zone
p t.utc_offset
p [t.monday?, t.tuesday?]
puts Time.at(0).getutc.to_s
