# A method that drives its block (yield or block.call) and calls itself
# recursively compiles as a real function with a proc-materialized block
# instead of hitting the inline depth cap: the &block param rides as an
# sp_Proc * and the self-call forwards it, so the recursion is plain C
# recursion.

# class method, block.call + &block self-forward
class Walker
  def self.walk(depth, &block)
    block.call(depth)
    walk(depth - 1, &block) if depth > 0
  end
end

# recursion through a receiver's own yielding method (the tree-walk shape)
class TNode
  def initialize(depth)
    @depth = depth
  end

  def leaf?
    @depth <= 0
  end

  def each
    yield TNode.new(@depth - 1)
    yield TNode.new(@depth - 2)
    nil
  end
end

class TreeWalker
  def self.walk(node, &block)
    return block.call(node) if node.leaf?

    node.each do |child| walk(child, &block) end
  end
end

TreeWalker.walk(TNode.new(2)) { |n| puts "leaf" }

