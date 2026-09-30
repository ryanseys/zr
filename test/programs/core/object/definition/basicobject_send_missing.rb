# A blank-slate receiver has no #send / #public_send -- only __send__ is
# BasicObject's own. So `send` raises CRuby's NoMethodError, and __send__
# dispatches.
class BO < BasicObject
  def initialize(x = 0); @x = x; end
  def own; @x; end
end
a = BO.new(7)
r = (a.send(:own) rescue $!.class)
p r
r2 = (a.public_send(:own) rescue $!.class)
p r2
p a.__send__(:own)
# ordinary receivers keep the whole surface
class W; def hi(x); "hi:#{x}"; end; end
w = W.new
p w.send(:hi, 1)
p w.send("hi", 2)
p w.__send__(:hi, 3)
p 5.send(:+, 2)
