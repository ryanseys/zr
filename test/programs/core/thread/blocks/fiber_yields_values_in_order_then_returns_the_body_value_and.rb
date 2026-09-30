f = Fiber.new do
  Fiber.yield 1
  Fiber.yield 2
  3
end
puts f.alive?
puts f.resume
puts f.resume
puts f.resume
puts f.alive?
