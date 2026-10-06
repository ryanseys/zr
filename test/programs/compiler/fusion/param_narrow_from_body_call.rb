# Body-side type narrowing: if a method's parameter is referenced in the
# body via `param.<m>` where `<m>` is defined on exactly one user class
# (and isn't a common operator / built-in-overlap method like
# `length`/`each`/`+`/...), the param gets the type of that class.
#
# This matters for methods that are only called through a receiver whose
# type is known only at run time (e.g. through `obj.method(:m)` or a call
# on an element of a mixed Array). Then no call site gives the type.

class CPU
  def peek_a(addr); addr * 2 + 1; end
  def cycles_advance(n); n + 100; end
end

# Two separate methods that each take a CPU param. The narrow comes
# from the body's method-call shapes.

def fetch(cpu, addr)
  cpu.peek_a(addr)        # peek_a is only on CPU → narrow cpu to CPU
end

def step(cpu, n)
  cpu.cycles_advance(n)   # cycles_advance only on CPU → narrow
end

c = CPU.new
puts fetch(c, 7)          # 15
puts step(c, 3)           # 103
