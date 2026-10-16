# debug_deadlock_check adds " mutex:N cond:M" to a thread that waits to
# lock a Mutex: N is the serial of the fiber that holds it (each fiber
# and thread counts from the main fiber's 1, in the order they are made)
# and M is how many wait for it.
held = Mutex.new
Fiber.new { 1 }.resume
[1].each.next
queue = Queue.new
owner = Thread.new { held.lock; queue.pop }
Thread.pass until owner.status == "sleep"
waiters = Array.new(2) { Thread.new { held.lock } }
Thread.pass until waiters.all? { |t| t.status == "sleep" }
mine = Mutex.new.tap(&:lock)
late = Thread.new { mine.lock }
Thread.pass until late.status == "sleep"
begin
  owner.join
rescue Exception => e
  puts e.message.gsub(/0x\h+/, "0xADDR")
end
