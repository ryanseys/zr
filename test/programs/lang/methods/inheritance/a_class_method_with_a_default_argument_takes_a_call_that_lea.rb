# A `def self.m` with a default argument accepts a call that omits
# it, on a module and on a class.

# Module form.
module M
  def self.greet(name, msg = "default")
    name + "/" + msg
  end
end

puts M.greet("a")            # a/default
puts M.greet("a", "world")   # a/world

# Class form.
class C
  def self.greet(name, msg = "fromcls")
    name + "/" + msg
  end
end

puts C.greet("b")            # b/fromcls
puts C.greet("b", "explicit")  # b/explicit

# A subclass inherits the class method and its default.
class Sub < C
end

puts Sub.greet("c")          # c/fromcls
