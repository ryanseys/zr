# A class-method with `yield` inlined at two call sites whose blocks return
# DIFFERENT types: each call site gets the value of its own block, with that
# block's type. An Integer result is not read as a String.
class Box
  def initialize(s)
    @s = s
  end
  def content
    @s
  end
  def self.make(s)
    b = Box.new(s)
    if block_given?
      yield b
    else
      b
    end
  end
end

r = Box.make("foo") { |b| b.content }
n = Box.make("hello") { |b| b.content.length }
p r
p n
m = Box.make("tail")
p m.content
