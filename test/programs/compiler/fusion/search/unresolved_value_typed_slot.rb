# An unresolved name raises NameError at run time. The program still builds
# when that name is the value for a slot of a definite type. Two such slots:
# a String operand of a string concat (the name is inside parentheses) and
# an object ivar written through an attr writer.
class Frame
  attr_reader :n
  def initialize(n); @n = n; end
end

class Holder
  attr_accessor :frame
  def initialize; @frame = Frame.new(1); end
end

# concat: the unresolved call is the right operand of `+`, written with the
# parentheses that hid the raising token from the coercion's text match
def concat_unresolved(a, b)
  "" + (Missing.build(a.to_f, b.to_i))
end

begin
  puts concat_unresolved("1.5", "2")
rescue NameError => e
  p e.class
end

def concat_unresolved_bare(a)
  "" + Absent.build(a.to_i)
end

begin
  puts concat_unresolved_bare("3")
rescue NameError => e
  p e.class
end

# object-pointer slot: an attr writer taking an unresolved name
h = Holder.new
p h.frame.n
begin
  h.frame = missing_frame
rescue NameError => e
  p e.class
end
p h.frame.n

# a resolvable value still goes into the same slot unchanged
h.frame = Frame.new(7)
p h.frame.n
p ("" + "ok")
