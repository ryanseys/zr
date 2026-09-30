# Process.clock_gettime(Process::CLOCK_MONOTONIC) returns a Float.
# The test cannot assert an exact value. It checks that the call
# returns a Float that does not decrease across two samples.

t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# t1 and t2 are Floats, so arithmetic on them works.
diff = t2 - t1
if diff >= 0
  puts "monotonic"
end
