# Method#super_method and UnboundMethod#super_method follow what `super`
# calls: from a refinement's method to another refinement of the same
# class that the method's definition uses, then to the refined method,
# then up the ancestors. The search uses the refinements where the method
# was written, not those of the caller.
def chain(m)
  out = []
  while m
    out << (m.owner.respond_to?(:target) ? [:refinement, m.owner.target] : m.owner)
    m = m.super_method
  end
  out
end

class A1
  def b = "A"
end

module M1
  R = refine(A1) { def b = "M#{super}" }
end

module N1
  using M1
  R = refine(A1) { def b = "N#{super}" }
end

module O1
  R = refine(A1) { def b = "O#{super}" }
end

module Use1
  using M1
  p [A1.new.b, chain(A1.new.method(:b)), chain(A1.instance_method(:b))]
  p A1.new.method(:b).super_method.owner == A1
end

module Use2
  using M1
  using N1
  m = A1.new.method(:b)
  p [A1.new.b, m.call, chain(m)]
  p m.owner == N1::R, m.super_method.owner == M1::R
end

module Use3
  using M1
  using O1
  p [A1.new.b, chain(A1.new.method(:b))]
end

# A def that uses a refinement of its superclass's method finds it; one
# that does not, finds the plain method, whatever the caller uses.
class B2 < A1
  def b = "B#{super}"
end

module Use4
  using M1
  p [B2.new.b, chain(B2.new.method(:b))]
end

module M2
  using M1
  class ::C2 < A1
    def b = "C#{super}"
  end
end
p [C2.new.b, chain(C2.new.method(:b))]

module Use5
  using N1
  p [C2.new.b, chain(C2.new.method(:b))]
end

# A refinement of a subclass whose block uses a refinement of the
# superclass.
module N3
  R = refine(B2) do
    using M1
    def b = "N#{super}"
  end
end

module Use6
  using N3
  p [B2.new.b, chain(B2.new.method(:b))]
end

# A define_method body.
class D4 < A1
  define_method(:b) { "D#{super()}" }
end

module Use7
  using M1
  p [D4.new.b, chain(D4.new.method(:b))]
end

# A refined module included in a class: each step goes on from the
# module's node.
module F5
  def f = [:F, *super]
end

class P5
  def f = [:P]
end

class Q5 < P5
  include F5
end

module R5
  refine(F5) { def f = [:R, *super] }
end

module Use8
  using R5
  m = Q5.new.method(:f)
  p [Q5.new.f, chain(m), chain(Q5.instance_method(:f))]
  p m.super_method.call, m.super_method.super_method.call
  p m.unbind.super_method == m.super_method.unbind
end
