# Two phases of allocation: the first keeps a small live set, and the second
# makes many large arrays that live a short time. GC.stat has no
# "full_runs" key, as in CRuby, so the lookup gives nil and `>` raises
# NoMethodError.

RETAIN = 1_000
WARM   = 20_000
N      = 8_000
HOLD   = 16
ITERS  = 40

retained = []
RETAIN.times { |i| retained.push(Array.new(64, i * 1.0)) }
WARM.times { Array.new(64, 0.0) }

ITERS.times do |i|
  bufs = []
  HOLD.times { |h| bufs.push(Array.new(N, h * 1.0)) }
  j = 0
  while j < N
    bufs[j % HOLD][j] += 1.0
    j += 397
  end
  bufs = nil
end

# The live set is about 1 MB.

g = GC.stat
puts "live set: " + retained.length.to_s
puts "full sweeps kept running: " + (g["full_runs"] > 6 ? "yes" : "no")
puts "old generation bounded: " + (g["old_bytes"] < 10_000_000 ? "yes" : "no")
