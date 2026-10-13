# Under Warning[:deprecated], alias and alias_method warn (ruby 4.1) when
# a module's original is found only through the fallback to Object
# (#22276), and when a class's original is defined in a module prepended
# to it (#22273). The alias still works.
def Warning.warn(message, category: nil)
  print "[#{category.inspect}] #{message.sub(/\A.*?:(\d+): /, 'line \1: ')}"
end
Warning[:deprecated] = true

module N; alias x puts; end
module N2; alias_method :y, :puts; end
module N3; alias_method :z, :object_id; end
anon = Module.new
anon.send(:alias_method, :w, :frozen?)
p anon.instance_method(:w).owner == anon

# A module's own method, or one of a module that it includes, is no
# fallback.
module K; def own = :own; end
module N4; include K; alias own2 own; def mine = 1; alias mine2 mine; end
p N4.instance_method(:own2).owner

module P
  def q = :p
end
class C
  def q = :c
  prepend P
  alias r q
end
p C.new.r
class C2; prepend P; alias_method :r2, :q; end
p C2.new.r2

# The class's own method, after a prepend, and a superclass's method are
# no prepended original.
class D
  def own = :d
  prepend Module.new
  alias own2 own
  alias s2 to_s
end
p D.new.own2

# A singleton class with a prepended module.
o = Object.new
def o.hi = :hi
o.singleton_class.prepend(Module.new { def hi = :pre })
o.singleton_class.send(:alias_method, :hi2, :hi)
p o.hi2

# An anonymous prepended module and an anonymous class.
k = Class.new { prepend(Module.new { def t = :t }) }
k.send(:alias_method, :t2, :t)
p k.new.t2

# Without Warning[:deprecated], or with $VERBOSE nil, nothing prints.
Warning[:deprecated] = false
module N5; alias x puts; end
class C3; prepend P; alias r q; end
Warning[:deprecated] = true
$VERBOSE = nil
module N6; alias x puts; end
$VERBOSE = false
module N7; alias x puts; end

# A Warning.warn that raises stops the alias.
def Warning.warn(message, category: nil) = raise("stop: #{category}")
begin
  module N8; alias x puts; end
rescue => e
  p e.message
end
p N8.private_method_defined?(:x) || N8.method_defined?(:x)
