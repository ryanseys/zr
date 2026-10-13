# A count with blanks and a sign before it reads, as strtoul reads it:
# here the limit is 2. A negative minimum reads too, with no warning.
GC.disable
held = Array.new(2) { Fiber.new { Fiber.yield }.tap(&:resume) }
p((Fiber.new { 1 }.resume rescue $!.message))
held.each(&:resume)
p Fiber.new { 2 }.resume
