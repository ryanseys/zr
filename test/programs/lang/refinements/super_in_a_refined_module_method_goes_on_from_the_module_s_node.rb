# `super` in a module's method, reached by `super` from a refinement of
# that module, goes on from the module's own node in the receiver's
# ancestors, also when the module is there more than once (prepended to a
# class and to its subclass). defined?(super) agrees at each step. A
# refinement method's `super` first takes another refinement of the same
# class that its own definition uses, then the refined method.

# Included through a module, refined.
class BasicObject
  def a1 = (defined?(super) ? :wrong : "B")
end

module G1
  def a1 = "G#{defined?(super) && super}"
end

module F1
  include G1
  def a1 = "F#{defined?(super) && super}"
end

class A1
  def a1 = "A#{defined?(super) && super}"
end

class B1 < A1
  include F1
end

module R1
  refine F1 do
    def a1 = "R#{defined?(super) && super}"
  end
end
using R1
p B1.new.a1
p B1.new.method(:a1).call
p B1.instance_method(:a1).bind_call(B1.new)

# Prepended to a class and to its subclass.
module M2
  def m = [:M, defined?(super), *super]
end

module R2
  refine M2 do
    def m = [:R, defined?(super), *super]
  end
end
using R2

class C2
  prepend M2
  def m = [:C, defined?(super)]
end

class SC2 < C2
  prepend M2
  def m = [:SC, defined?(super), *super]
end
p SC2.new.m

# The same with the super in blocks, in a lambda, a thread and a fiber.
module M3
  def m = -> { Array.new(1) { [:M, *super] }.flatten }.call
end

module R3
  refine M3 do
    def m = [:R, *Thread.new { super }.value]
  end
end
using R3

class C3
  prepend M3
  def m = :C
end

class SC3 < C3
  prepend M3
  def m = [:SC, *Fiber.new { super }.resume]
end
p SC3.new.m

# define_method bodies, in the module and in its refinement.
module M4
  define_method(:m) { [:M, *super()] }
end

module R4
  refine M4 do
    define_method(:m) { [:R, defined?(super), *super()] }
  end
end
using R4

class C4
  prepend M4
  def m = [:C]
end

class SC4 < C4
  prepend M4
  def m = [:SC, *super]
end
p SC4.new.m

# Two refinements of one class: a refinement's super goes to the other
# one when its own definition uses it, else to the class.
class A5
  def b = "A"
end

module M5
  refine(A5) { def b = "M#{super}" }
end

module N5
  using M5
  refine(A5) { def b = "N#{super}" }
end

module O5
  refine(A5) { def b = "O#{super}" }
end

module Use5
  using M5
  using N5
  p A5.new.b
end

module Use5b
  using M5
  using O5
  p A5.new.b
end
