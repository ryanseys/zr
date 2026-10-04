# Process.spawn takes the environment through to_hash and refuses a
# name with = or a NUL, a trailing Hash is always the options, and a
# [program, argv0] pair has two Strings; the clocks CRuby emulates read
# to their own resolution.
def t
  pid = yield
  Process.wait(pid) if pid.is_a?(Integer)
  [$?.exitstatus]
rescue => e
  [e.class, e.message]
end
p t { Process.spawn({ "A=B" => "1" }, "true") }, t { Process.spawn({ "A\0" => "1" }, "true") }, t { Process.spawn({ "A" => "1\0" }, "true") }
p t { Process.spawn({}, {}) }, t { Process.spawn({}) }
e = Object.new
def e.to_hash = { "ZR_SPAWN_X" => "7" }
r, w = IO.pipe
p t { Process.spawn(e, "echo $ZR_SPAWN_X", out: w) }
w.close
p r.read
a = Object.new
def a.to_ary = ["true", "argv0"]
p t { Process.spawn(a) }, t { Process.spawn(["true"]) }, t { Process.spawn(["true", "x", "y"]) }, t { Process.spawn(["true", 1]) }
%i[GETTIMEOFDAY_BASED_CLOCK_REALTIME TIME_BASED_CLOCK_REALTIME GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID].each do |c|
  p [c, Process.clock_getres(c, :nanosecond), Process.clock_gettime(c).class, Process.clock_gettime(c, :nanosecond) % Process.clock_getres(c, :nanosecond)]
end
p Process.clock_gettime(Process::CLOCK_REALTIME, nil).class
