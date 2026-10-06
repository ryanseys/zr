# A program's redefinition of a core method reaches its own code, not
# the compiler's.
class Hash
  alias_method :plain_fetch, :[]
  def [](key) = key == :probe ? :redefined : plain_fetch(key)
end
class Integer
  alias_method :plain_plus, :+
  def +(other) = other == 1000 ? :redefined : plain_plus(other)
end
p eval("{ a: 1 }[:a] + 1"), eval("{ a: 1 }[:probe]"), eval("1 + 1000")
p Object.new.instance_eval("self.class")
