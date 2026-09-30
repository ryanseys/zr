# `arr.map { Obj.new }` over a typed-array receiver collects the
# constructed objects into an Array. Node has a subclass.
class Node
  attr_reader :tag
  def initialize(t = 0); @tag = t; end
end
class Sub < Node; end
ks = [10, 20, 30].map { |t| Node.new(t) }
puts ks.size
puts ks[0].tag
puts ks[2].tag
total = 0
ks.each { |n| total += n.tag }
puts total
