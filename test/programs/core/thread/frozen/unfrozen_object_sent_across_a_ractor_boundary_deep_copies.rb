# CRuby's rule, now real here too: an unfrozen plain object crosses as
# a deep copy (dup + ivar rewrite -- `ractor::cross_graph`), so the
# receiver sees the value and later mutation of the source's graph
# never reaches it.

class Box
  def initialize(v)
    @v = v
  end
  attr_accessor :v
end
sink = Ractor.new do
  got = Ractor.receive
  got.v << "-seen"
  got.v
end
b = Box.new(+"payload")
sink.send(b)
out = sink.value
p [out, b.v]
