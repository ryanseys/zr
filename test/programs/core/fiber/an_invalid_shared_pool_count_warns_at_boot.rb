# ruby reads the fiber pool counts at boot. A value that does not read
# whole as a non-negative integer gets a warning, and the pool has no
# limit. A value with blanks before it, or a sign, reads.
p Array.new(5) { Fiber.new { Fiber.yield }.tap(&:resume) }.size
