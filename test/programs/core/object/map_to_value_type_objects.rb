# `arr.map { Obj.new }` where Obj is a small class (no subclass, only
# scalar ivars that do not change). map gives an array of the new objects.
# The receiver can be an array or a range.
class Node
  attr_reader :tag
  def initialize(t = 0); @tag = t; end
end

ks = [1, 2, 3].map { |t| Node.new(t) }
puts ks.size
puts ks[0].tag
puts ks[2].tag
total = 0
ks.each { |n| total += n.tag }
puts total

rs = (1..3).map { |t| Node.new(t * 10) }
puts rs.size
puts rs.map(&:tag).inspect

es = (1...4).map { |t| Node.new(t) }
puts es.map(&:tag).inspect
