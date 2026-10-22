# Process::CLOCK_MONOTONIC / CLOCK_REALTIME are values, usable beyond a
# direct clock_gettime argument. They are Integers on macOS and Linux, and
# Symbols on WASI, as ruby's WASI build defines them.
x = Process::CLOCK_MONOTONIC
puts x.nil?
puts Process::CLOCK_MONOTONIC.nil?
realtime = Process::CLOCK_REALTIME
puts Process.clock_gettime(realtime).is_a?(Float)
clk = Process::CLOCK_MONOTONIC
puts Process.clock_gettime(clk).is_a?(Float)
