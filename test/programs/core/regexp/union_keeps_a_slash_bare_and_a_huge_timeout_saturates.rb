# Regexp.union writes each Regexp part with no terminator, so a slash
# keeps no backslash; a timeout too large to keep saturates as ruby's
# rb_hrtime_t does.
re = Regexp.union(/\//, ""); p re.source, re.inspect, eval(re.inspect).source, re.to_s
Regexp.timeout = Float::INFINITY
p Regexp.timeout == ((1 << 64) - 1) / 1000000000.0
Regexp.timeout = 1e300
p Regexp.timeout == ((1 << 64) - 1) / 1000000000.0, Regexp.new("foo", timeout: Float::INFINITY).timeout == ((1 << 64) - 1) / 1e9
Regexp.timeout = 2.5
p Regexp.timeout
Regexp.timeout = nil
p Regexp.timeout
