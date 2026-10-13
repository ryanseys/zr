# Without a fiber scheduler, a fiber that locks a Mutex that another
# fiber of its own thread holds can never get it: Mutex#lock raises
# ThreadError at once, as ruby's do_mutex_lock does. The same fiber that
# locks again gets the recursive locking error, and a fiber of another
# thread waits.
$stdout.sync = true
def try(label)
  p [label, yield]
rescue ThreadError => e
  p [label, e.class, e.message]
end

m = Mutex.new
m.lock
try(:other_fiber) { Fiber.new { m.lock }.resume }
try(:same_fiber) { m.lock }
try(:synchronize) { Fiber.new { m.synchronize { 1 } }.resume }
try(:try_lock) { Fiber.new { m.try_lock }.resume }
m.unlock

f1 = Fiber.new do
  m.lock
  Fiber.yield
  m.unlock
  :released
end
f2 = Fiber.new { m.lock; :locked }
f1.resume
try(:second_fiber) { f2.resume }
try(:owned_after) { m.owned? }
try(:release) { f1.resume }
try(:free) { Fiber.new { m.lock; m.unlock; :ok }.resume }

m.lock
t = Thread.new { m.synchronize { :from_thread } }
Thread.pass until t.status == "sleep"
m.unlock
try(:other_thread) { t.value }
