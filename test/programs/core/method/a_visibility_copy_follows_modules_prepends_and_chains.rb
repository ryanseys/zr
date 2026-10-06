# A visibility change of an inherited method follows the method above it
# through modules, prepends, chains of copies, undef and aliases.
def try = yield rescue "#{$!.class}: #{$!.message}"

module M
  def m = :m
end

module N
  include M
  private :m
end

class X
  include N
end
x = X.new
p try { x.m }, x.send(:m), N.private_instance_methods(false)
module M
  def m = :m2
end
p x.send(:m)
module M
  remove_method :m
end
p try { x.send(:m) }, N.private_instance_methods(false)
module M
  def m = :m3
end
p x.send(:m)

# A prepend after the copy moves it to the class's origin.
class P0
  def q = :p0
end

class P1 < P0
  private :q
end

module Pre
  def q = [:pre, super]
end
P1.prepend(Pre)
p P1.new.q, try { P1.new.send(:q) }
class P0
  def q = :p0b
end
p P1.new.q

# A singleton class's copy.
class S0
  def s(a, b = 2) = [a, b]
end
o = S0.new
o.singleton_class.send(:private, :s)
p try { o.s(1) }.sub(/#<S0:\h+x\h+>/, "#<S0>"), o.send(:s, 1)
class S0
  def s(a) = [:new, a]
end
p o.send(:s, 1), o.method(:s).arity

# A copy of a copy.
class Z0
  def z = :z0
end

class Z1 < Z0
  private :z
end

class Z2 < Z1
  public :z
end
p Z2.new.z, try { Z1.new.z }
class Z0
  def z = :z0b
end
p Z2.new.z
class Z1
  def z = :z1
end
p Z2.new.z, try { Z1.new.z }
class Z1
  remove_method :z
end
p Z2.new.z, Z1.new.send(:z)

# A def in the class itself ends its copy.
class Z2
  def z = :own
end

class Z0
  def z = :z0c
end
p Z2.new.z
class Z0
  undef_method :z
end
p try { Z1.new.send(:z) }, Z2.new.z

# An alias of a copy takes the method as it is at the alias.
class U0
  def u = :u
end

class U1 < U0
  private :u
  alias_method :u2, :u
end
p U1.new.send(:u2)
class U0
  def u = :new_u
end
p U1.new.send(:u2), U1.new.send(:u)
