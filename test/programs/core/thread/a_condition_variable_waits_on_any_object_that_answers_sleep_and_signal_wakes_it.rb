# ConditionVariable#wait takes any object that answers sleep, as
# Mutex_m's objects do: it sends sleep(timeout) to it, with the thread
# listed, so signal and broadcast wake the thread as they wake one in
# Mutex#sleep.
class Duck
  def initialize = @m = Thread::Mutex.new
  def synchronize(&) = @m.synchronize(&)

  def sleep(timeout = nil)
    @m.sleep(timeout)
  end
end

duck = Duck.new
cv = Thread::ConditionVariable.new
ready = Thread::Queue.new
done = false
waiter = Thread.new do
  duck.synchronize do
    ready << :waiting
    cv.wait(duck) until done
    :signalled
  end
end
ready.pop
# The waiter holds the lock until it sleeps, so it is listed by now.
duck.synchronize do
  done = true
  cv.signal
end
p waiter.value

go = false
waiters = Array.new(2) do |i|
  Thread.new do
    duck.synchronize do
      ready << i
      cv.wait(duck) until go
      i
    end
  end
end
2.times { ready.pop }
duck.synchronize do
  go = true
  cv.broadcast
end
p waiters.map(&:value)

p(duck.synchronize { cv.wait(duck, 0.01) })
