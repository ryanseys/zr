h = Fiber.new do |a, b|
  a + b
end
puts h.resume(3, 4)
