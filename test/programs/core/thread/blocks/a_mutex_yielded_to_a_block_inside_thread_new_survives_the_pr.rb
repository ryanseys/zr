# A Mutex yielded to a block from inside Thread.new. A block argument can be
# any runtime handle (Mutex, IO, Thread, Queue, Dir, ...), not only a string,
# array, hash or object. The block gets the same handle, and the value of
# Mutex#synchronize (with its ensure) comes back as the block's value.
def race(label)
  h = { "a" => 0 }
  lock = Mutex.new
  ts = 2.times.map do
    Thread.new do
      yield(lock, h)
    end
  end
  ts.each(&:join)
  puts "#{label}: #{h["a"]}"
end

race("counter") { |lock, h| lock.synchronize { h["a"] += 1 } }

# the same handle yielded WITHOUT a thread still works
def direct
  lock = Mutex.new
  yield(lock)
end
direct { |l| puts l.class.to_s }

# other handle kinds through the same path
def with_queue
  q = Queue.new
  yield(q)
  q.size
end
puts with_queue { |q| q.push(1); q.push(2) }
