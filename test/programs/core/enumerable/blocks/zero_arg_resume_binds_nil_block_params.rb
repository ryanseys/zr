f = Fiber.new { |x| x.nil? }
puts f.resume
