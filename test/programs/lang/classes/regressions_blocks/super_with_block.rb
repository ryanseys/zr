# `super { ... }` from a child method passes a literal block to the
# parent, so `yield` inside the parent body runs the block.
class T_super_with_block_Parent
  def test
    yield
  end
end

class T_super_with_block_Child < T_super_with_block_Parent
  def test
    super { puts "from child" }
  end
end

T_super_with_block_Child.new.test
