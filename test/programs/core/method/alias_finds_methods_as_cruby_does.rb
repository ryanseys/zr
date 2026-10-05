# alias and alias_method look up the old name as CRuby does: a module
# also finds Object's methods, and a private or prepended copy that only
# changes visibility (a ZSUPER entry) is not a method to alias.
def show
  p yield
rescue NameError => e
  p [e.class, e.message.sub(/0x\h+/, "0x")]
end

m = Module.new do
  alias orig_to_s to_s
end
o = Object.new.extend(m)
p o.to_s == o.orig_to_s

show { Module.new { private :class }.alias_method :xyz, :class }
show { Module.new { prepend Module.new { private :class } }.alias_method :xyz, :class }
show { Class.new { private :class }.alias_method :xyz, :class }

# An aliased method is redefined with no warning, as alias counts.
$VERBOSE = true
class A
  def foo = 1
  alias foo foo
  def foo = 2
end
p A.new.foo
