threads = []
t = 0
while t < 4
  threads << Thread.new(t) do |tid|
    j = tid
    n = 0
    while j < 100_000
      s = "x" + j.to_s
      n += s.length
      j += 4
    end
    n
  end
  t += 1
end

total = 0
threads.each { |th| total += th.value }
puts total

# Four threads allocate many Strings while the GC runs. Each thread keeps
# its own state, so each loop finishes and the total is correct.
