# `inspect` shows sub-second digits (trailing zeros trimmed); `to_s` never
# does.

t = Time.at(1700000000.5).getutc
puts t.inspect
puts t.to_s
puts Time.at(1700000000).getutc.inspect
