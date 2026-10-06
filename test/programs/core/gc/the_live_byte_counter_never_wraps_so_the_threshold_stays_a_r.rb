# The program makes many large arrays and keeps a few tiny pairs. GC.stat
# has no "threshold" key, as in CRuby, so the lookup gives nil and `>`
# raises NoMethodError.

N     = 20_000
ITERS = 400

live = []
ITERS.times do |i|
  s = Array.new(N, 0.0)
  sbin = Array.new(N, 0)
  cnt = Array.new(256, 0)
  j = 0
  while j < N
    b = (j & 255)
    sbin[j] = b
    s[j] = b * 0.5
    cnt[b] += 1
    j += 197
  end
  live.push([cnt[0], s[0]]) if (i % 64).zero?
end

g = GC.stat
puts "retained: " + live.length.to_s
puts "threshold positive: " + (g["threshold"] > 0 ? "yes" : "no")
puts "collector still running: " + (g["cycle"] > 8 ? "yes" : "no")
puts "heap bounded: " + (g["bytes"] < 400_000_000 ? "yes" : "no")
