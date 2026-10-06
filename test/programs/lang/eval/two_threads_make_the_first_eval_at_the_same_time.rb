# Two threads make the program's first eval at the same time. Each one
# gets its value, and neither sees a compiler that is only partly loaded.
threads = 4.times.map do |i|
  Thread.new { eval("#{i} * 10 + [1, 2].sum") }
end
p threads.map(&:value)

# After the first eval, more threads eval the same and other strings.
more = 3.times.map do |i|
  Thread.new { [eval("#{i} + 1"), eval("'x' * #{i}")] }
end
p more.map(&:value)
