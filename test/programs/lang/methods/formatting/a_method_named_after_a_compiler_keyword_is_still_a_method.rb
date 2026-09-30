# Ruby names that collide with the compiler's own vocabulary must not leak
# into the generated program: a class named after a builtin type, a method
# named after a keyword, and Ruby's `_` local, which the generated program
# has no named binding for. All are mangled on the way out, and none of the
# mangling is observable from Ruby.

# --- Methods named after compiler keywords --------------------------------

class Keywords
  def type = "a type"
  def match = "a match"
  def loop = "a loop"
  def fn = "an fn"
  def impl = "an impl"
  def move = "a move"
  def ref = "a ref"
  def struct = "a struct"
end
k = Keywords.new
p k.type
p k.match
p k.loop
p k.fn
p k.impl
p k.send(:type)
p k.respond_to?(:match)

# Predicate/bang/setter suffixes.
class Suffixes
  def initialize = @saved = false
  def empty? = false
  def save! = @saved = true
  def value=(v)
    @value = v
  end
  def value = @value
  def saved? = @saved
end
s = Suffixes.new
p s.empty?
s.save!
p s.saved?
s.value = 42
p s.value

