class Bare; end
f = Fiber.new { Bare.new.send(:nope) }
begin
  f.resume
rescue NoMethodError
  puts "rescued in resumer"
end
puts f.alive?
r = Ractor.new { Bare.new.send(:nope) }
begin
  r.value
rescue Ractor::RemoteError => e
  puts "rescued at value: #{e.cause.class}"
end
