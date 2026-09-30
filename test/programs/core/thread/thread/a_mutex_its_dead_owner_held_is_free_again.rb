m = Mutex.new
Thread.new { m.lock }.join
p [m.locked?, m.try_lock, m.owned?]
