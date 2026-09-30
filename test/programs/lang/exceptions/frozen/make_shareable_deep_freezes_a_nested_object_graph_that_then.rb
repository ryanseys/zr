# The plan's own listed scenario: object -> array -> object, every node
# frozen by one make_shareable, the whole graph then crossing a Ractor
# boundary by reference and dispatching on the far side.

class Node
  def initialize(v, child)
    @v = v
    @child = child
  end
  def v; @v; end
end
leaf = Node.new(3, nil)
root = Node.new(1, [leaf])
Ractor.make_shareable(root)
puts root.frozen?
puts leaf.frozen?
puts Ractor.shareable?(root)
sink = Ractor.new do
  got = Ractor.receive
  got.send(:v)
end
sink.send(root)
puts sink.value
