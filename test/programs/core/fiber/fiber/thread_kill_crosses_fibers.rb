# A kill of a thread that waits inside a fiber ends that fiber, its
# ensure running, and then the thread. Killing a thread's own fiber, from
# it or from a fiber it resumed, ends the thread. The main thread's fiber
# can't be resumed from another thread to kill it.
def wait_sleeping(t) = (Thread.pass until t.status == "sleep")

log = []
t = Thread.new do
  Fiber.new do
    Fiber.new do
      sleep
    ensure
      log << :inner
    end.resume
  ensure
    log << :outer
  end.resume
  log << :not_reached
ensure
  log << :thread
end
wait_sleeping(t)
t.kill
t.join
p log, t.status

th = Thread.new do
  Fiber.current.kill
  puts "not reached"
ensure
  puts "thread ensure"
end
p th.value

th = Thread.new do
  root = Fiber.current
  Fiber.new do
    Fiber.new { root.kill; puts "not reached" }.resume
  ensure
    puts "a ensure"
  end.resume
  puts "not reached"
rescue Exception
  puts "not rescued"
end
p th.value

th = Thread.new { Thread.current.kill; :not_reached }
p th.value

main = Fiber.current
p(Thread.new do
  main.kill
rescue FiberError => e
  e.message
end.value)

t = Thread.new { Fiber.new { begin; sleep; rescue => e; "fiber rescued #{e.message}"; end }.resume }
wait_sleeping(t)
t.raise("boom")
p t.value
