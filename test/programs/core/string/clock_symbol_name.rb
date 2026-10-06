# `Process.clock_gettime` takes a clock as a SYMBOL name.
#
# The symbol spelling is the portable one -- a constant the platform does
# not define is a `NameError` at the read, where the symbol form is a
# rescuable `Errno::EINVAL` -- so it is the shape a library actually
# writes. The name is looked up against `Process`'s own `CLOCK_*`
# constants, so the two cannot drift.
#
# A constant or a raw id also works, as does `Process.clock_getres`.

p Process.clock_gettime(:CLOCK_MONOTONIC).class
p Process.clock_gettime(Process::CLOCK_MONOTONIC).class
p Process.clock_gettime(:CLOCK_REALTIME).class
p Process.clock_gettime(:CLOCK_MONOTONIC, :nanosecond).class
p Process.clock_gettime(:CLOCK_MONOTONIC, :millisecond).class
p Process.clock_getres(:CLOCK_MONOTONIC).class
p Process.clock_gettime(:CLOCK_REALTIME) > 0
p Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID) >= 0
