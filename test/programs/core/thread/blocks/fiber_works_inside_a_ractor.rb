# The fiber table is thread-pinned and a Ractor is its own OS thread --
# create and drive entirely within it.

r = Ractor.new do
  f = Fiber.new do
    Fiber.yield 1
    2
  end
  a = f.resume
  b = f.resume
  a + b
end
puts r.value
