f = Fiber.new do
  3.times do |i|
    Fiber.yield i
  end
  :end
end
puts f.resume
puts f.resume
puts f.resume
puts f.resume
