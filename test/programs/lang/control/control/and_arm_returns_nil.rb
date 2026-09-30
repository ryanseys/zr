# A method whose body is `nil` returns nil. The call can sit in one arm of
# `&&` or `? :` beside an arm that holds an object: `a && a.analyze`,
# `a ? a.analyze : a` and `a ? a.analyze : nil` all answer nil.
class Att
  def analyze = nil
  def name = "n"
  def count = 3
end

class Holder
  attr_accessor :att
  def ensure_analyzed
    att && att.analyze     # what `att&.analyze` lowers to
  end
end

a = Att.new
p(a && a.analyze)
p(a ? a.analyze : a)
p(a ? a.analyze : nil)
p(nil && a.analyze)
p(a && a.name)
p(a && a.count)
p((a || a.analyze).name)

h = Holder.new
h.att = a
p h.ensure_analyzed
h.att = nil
p h.ensure_analyzed

s = "x"
p(s && a.analyze)
n = 5
p(n && a.analyze)
