# Parent fiber's storage is snapshot-copied into a child fiber at
# Fiber.new time. Subsequent writes on either side are independent
# (shallow copy).
Fiber[:user] = "alice"

f = Fiber.new do
  # Inherited at creation.
  puts Fiber[:user]
  # Local write — does not leak back to parent.
  Fiber[:user] = "bob"
  puts Fiber[:user]
end
f.resume

# Parent's value is unchanged by the child's write.
puts Fiber[:user]
