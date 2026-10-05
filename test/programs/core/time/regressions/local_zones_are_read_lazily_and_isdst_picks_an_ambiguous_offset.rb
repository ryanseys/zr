# A local Time from `at` finds its zone when it is first read, with the
# TZ of that moment, and ceil, floor and round keep the zone kind.
ENV["TZ"] = "PST8PDT"
old = ENV["TZ"]
ENV["TZ"] = "JST-9"
t = Time.at 0, 1
ENV["TZ"] = old
p t.zone, t.ceil.zone, t.floor.zone, t.round.zone, t.ceil.utc_offset

# A Time read before the change keeps what it read.
ENV["TZ"] = "JST-9"
u = Time.at 0
p u.zone
ENV["TZ"] = old
p u.zone, u.utc_offset

# Time.local and Time.new fill the zone at once.
ENV["TZ"] = "JST-9"
v = Time.local(2000, 1, 1)
ENV["TZ"] = old
p v.zone, v.utc_offset

# The ten fields of Time#to_a: isdst picks the daylight reading of an
# hour that happens twice.
ENV["TZ"] = "America/New_York"
p Time.local(0, 30, 1, 30, 10, 2005, 0, 0, true, ENV["TZ"]).utc_offset
p Time.local(0, 30, 1, 30, 10, 2005, 0, 0, false, ENV["TZ"]).utc_offset
p Time.mktime(0, 30, 1, 30, 10, 2005, 0, 0, true, nil).utc_offset
p Time.local(0, 30, 1, 30, 7, 2005, 0, 0, false, nil).utc_offset
p Time.local(0, 30, 1, 30, 12, 2005, 0, 0, true, nil).utc_offset
p Time.local(2005, 10, 30, 1, 30).utc_offset
