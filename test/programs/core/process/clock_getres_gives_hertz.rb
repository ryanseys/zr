# Process.clock_getres takes :hertz, the ticks per second, which is the
# reciprocal of the resolution in seconds.
p Process.clock_getres(:TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID, :hertz)
p Process.clock_getres(:CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID, :hertz)
p Process.clock_getres(:GETTIMEOFDAY_BASED_CLOCK_REALTIME, :hertz)
