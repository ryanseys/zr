# In a child forked inside a fiber, that fiber is the root fiber, as
# rb_fiber_atfork makes it: a transferred fiber that ends in the child
# comes back to it (test_fiber.rb's test_fork_from_fiber).
pid = nil
Fiber.new do
  pid = fork do
    xpid = nil
    Fiber.new {
      xpid = fork do
        100.times do
          Fiber.new {}.transfer
          Fiber.new { Fiber.yield }
        end
        exit!(true)
      end
    }.transfer
    _, status = Process.waitpid2(xpid)
    exit!(status.success?)
  end
end.resume
_, status = Process.waitpid2(pid)
p status.success?

child = fork do
  Fiber.new { Fiber.new { :inner }.transfer }.transfer
  puts "back in the child's root"
  exit!(true)
end
Process.waitpid(child)
p $?.success?
