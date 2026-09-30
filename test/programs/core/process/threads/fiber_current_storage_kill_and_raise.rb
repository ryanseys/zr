p Fiber.current.equal?(Fiber.current)
Fiber[:level] = "outer"
seen = []
f = Fiber.new do
  seen << Fiber[:level]
  Fiber[:level] = "inner"
  seen << Fiber[:level]
  Fiber.yield
end
f.resume
p seen
p Fiber[:level]
p Fiber.current.storage
other = Fiber.new { Fiber.yield }
other.resume
begin
  other.storage
rescue ArgumentError => e
  puts e.message
end
k = Fiber.new { Fiber.yield 1; Fiber.yield 2 }
p k.resume
p k.kill.equal?(k)
p k.alive?
r = Fiber.new do
  begin
    Fiber.yield "one"
  rescue => e
    Fiber.yield "rescued: #{e.message}"
  end
end
p r.resume
p r.raise("boom")
