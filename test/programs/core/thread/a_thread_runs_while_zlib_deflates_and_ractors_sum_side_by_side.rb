require "zlib"
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ticks = 0
th = Thread.new { 50.times { ticks += 1; sleep 0.001 } }
data = Random.new(1).bytes(20_000_000)
Zlib::Deflate.deflate(data)
th.join
puts ticks
r = 4.times.map { |i| Ractor.new(i) { |n| s = 0; 3_000_000.times { s += n }; s } }.map(&:value)
puts r.sum
