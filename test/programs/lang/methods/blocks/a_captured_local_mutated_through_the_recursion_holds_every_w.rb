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

# a captured local mutated through the recursion
total = 0
Walker.walk(3) { |n| total += n }
puts total

