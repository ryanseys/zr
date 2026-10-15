# Another thread cannot kill the main fiber: the kill raises FiberError.
# The main fiber is marked, though, so it ends the program at its next
# fiber switch.
$stdout.sync = true
at_exit { puts "at_exit" }
main = Fiber.current

p(Thread.new do
  main.kill
  :killed
rescue FiberError => e
  e.message
end.value)
p main.alive?
puts "still running"

begin
  p Fiber.new { :ran }.resume
  puts "not reached"
ensure
  puts "main ensure"
end
