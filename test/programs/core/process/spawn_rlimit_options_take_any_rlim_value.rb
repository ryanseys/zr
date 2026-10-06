# A spawn's :rlimit_* option takes a limit, [limit] or [soft, hard];
# each limit is any rlim_t, up to RLIM_INFINITY.
def limits(**opts)
  IO.popen(["sh", "-c", "ulimit -Sc; ulimit -Hc; ulimit -St", **opts], &:read).split
end

max = Process.getrlimit(:CORE).last
shown = max == Process::RLIM_INFINITY ? "unlimited" : (max / 512).to_s
p limits(rlimit_core: max).first(2) == [shown, shown]
p limits(rlimit_core: [max]).first(2) == [shown, shown]
p limits(rlimit_core: [0, max]).first(2) == ["0", shown]
p limits(rlimit_core: [0, 0]).first(2)
p limits(rlimit_core: 0, rlimit_cpu: 3600)
p limits(rlimit_core: Process::RLIM_INFINITY)[0] == "unlimited" || max != Process::RLIM_INFINITY

[{ rlimit_foo: 0 }, { rlimit_NOFILE: 0 }, { rlimit_nofile: [] }, { rlimit_nofile: [1, 2, 3] },
 { rlimit_core: :INFINITY }, { rlimit_core: "1" }, { rlimit_core: -2**65 }].each do |opt|
  system("true", **opt)
rescue ArgumentError, TypeError, RangeError => e
  p [e.class, e.message]
end
