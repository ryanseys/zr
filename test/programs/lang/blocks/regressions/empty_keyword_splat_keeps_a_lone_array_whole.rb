# Keywords at a yield or a Proc#call, even an empty `**h`, keep a lone
# Array whole for a block that ruby does not count as simple (one with
# more than leading required parameters), as setup_parameters_complex
# allows no autosplat with keywords. A simple block still spreads it.
e = {}
h = { z: 2 }
def y1(h) = yield([1], **h)
p(y1(e) { |a, b, **kw| [a, b, kw] })
p(y1(e) { |a, b, k: 0| [a, b, k] })
p(y1(e) { |a, b = 5, **kw| [a, b, kw] })
p(y1(e) { |a, b, **nil| [a, b] })
p(y1(e) { |a, *r| [a, r] })
p(y1(e) { |a, b| [a, b] })
p(y1(e) { |a, | a })
p(y1(e) { |a, b, &blk| [a, b] })
p(y1(h) { |a, b, **kw| [a, b, kw] })
def y3 = yield([1, 2], **{})
p(y3 { |a, *r, **kw| [a, r, kw] })

f = proc { |a, *r| [a, r] }
p f.call([1, 2], **e), f.yield([1, 2], **e), f.call([1, 2])
f = proc { |a, b| [a, b] }
p f.call([1, 2], **e)
f = proc { |a, b, k: 0| [a, b, k] }
p f.call([1, 2], **e), f.call([1, 2])

def none = yield(**{})
begin
  none
rescue LocalJumpError => e
  p e.message
end
p "after".size
