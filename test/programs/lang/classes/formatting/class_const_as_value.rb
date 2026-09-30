# A class constant referenced as a value (not as the receiver of
# `.new` / a class method call) is a Class object:
#
#   c = Row
#   puts c.to_s   # Row
#
# The Class value goes through a local, and through an ivar.
#
# Other examples check the rest of the Class surface:
#   - `.name` / `.inspect` / `.==` / `.!=` on Class values.
#   - Module distinction (Module vs Class kind).
#   - Dispatch through a Class-typed local (`c.new(...)`).
#   - is_a?(Klass-typed-variable), case/when on Class values.
#   - Ancestors / .superclass / `.<` / `.<=`.

class Row
  attr_accessor :x
end

class Article < Row
end

# Local assignment from a class constant.
c = Row
puts c.to_s                   # Row

# Same shape with a subclass.
d = Article
puts d.to_s                   # Article

# Store a Class value in an ivar and read it back through an
# instance method.
class Holder
  attr_accessor :klass
end

h = Holder.new
h.klass = Row
puts h.klass.to_s             # Row
h.klass = Article
puts h.klass.to_s             # Article
