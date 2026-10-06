d = Fiber.new { :done }
d.resume
begin
  d.resume
rescue FiberError => e
  puts e.send(:message)
end
