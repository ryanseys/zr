mu = Mutex.new
r = mu.synchronize { break 5 }
puts r
puts mu.locked?
