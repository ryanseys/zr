# Fiber storage is reached through `Fiber[]`, and a Fiber instance
# carries no `[]=` to alias it with.

Fiber.current[:via_current] = 100
puts Fiber[:via_current]
