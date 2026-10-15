# A fiber that kills the main fiber, which resumed it, gets an empty
# RuntimeError; a second kill does nothing. The program ends as soon as
# control comes back to the main fiber.
$stdout.sync = true
at_exit { puts "at_exit" }
main = Fiber.current

inner = Fiber.new do
  begin
    main.kill
  rescue => e
    p [e.class, e.message]
  end
  p main.kill
  p main.alive?
  Fiber.yield :yielded
  puts "not reached"
end

begin
  p inner.resume
  puts "not reached"
ensure
  puts "main ensure"
end
