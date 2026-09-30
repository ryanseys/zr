# Sibling fibers have independent storage. A write in one does not
# affect the other even if they share a parent.
Fiber[:tag] = "parent"

a = Fiber.new do
  Fiber[:tag] = "a"
  puts Fiber[:tag]
end

b = Fiber.new do
  # b was created BEFORE a ran, so it inherited "parent", not "a".
  puts Fiber[:tag]
  Fiber[:tag] = "b"
  puts Fiber[:tag]
end

a.resume
b.resume

# Parent's storage still reads "parent" — neither child leaked back.
puts Fiber[:tag]
