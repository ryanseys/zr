# The threads live in an Array, so `join`/`value` are called on each
# element that the Array gives.

threads = 3.times.map { |i| Thread.new { i * 10 } }
threads.each(&:join)
p threads.map(&:value)
