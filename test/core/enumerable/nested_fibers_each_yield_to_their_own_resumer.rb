# The exact shape a fiber save/restore discipline exists for: after the
# inner fiber yields, the OUTER fiber's own Fiber.yield must suspend the
# outer one, not touch the inner's suspended yielder. The inner fiber is
# CREATED outside the outer's block (captured via an ordinary local)
# because a block literal escaping from inside another escaping block is a
# PRE-existing scope-cut unrelated to fibers.

inner = Fiber.new do
  Fiber.yield :from_inner
  :inner_done
end
outer = Fiber.new do
  got = inner.resume
  Fiber.yield got
  inner.resume
end
puts outer.resume
puts outer.resume
__END__
from_inner
inner_done
