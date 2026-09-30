begin
  Fiber.yield(1)
rescue FiberError => e
  puts e.send(:message)
end
