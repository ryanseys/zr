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

# a yield-method inlined INSIDE the recursive method: the callee's own yield
# splices its call-site block, while a yield in that spliced block still binds
# the enclosing method's proc (callee even shadows the &block name)
class SNode
  def each
    block = 5
    yield block
    nil
  end
end

class MixWalker
  def self.walk(depth, &block)
    yield depth
    SNode.new.each do |x|
      walk(depth - 1, &block) if depth > 0
    end
    nil
  end
end

MixWalker.walk(1) { |n| puts n + 50 }
