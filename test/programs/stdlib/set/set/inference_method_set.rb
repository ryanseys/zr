# Parameter type inference must pick a class whose surface contains
# ALL methods called on the param, regardless of class definition
# order. A class that matches only one reader is not enough, so the
# order of Block and Cell does not change the result.

class Block
  attr_reader :x

  def initialize(x)
    @x = x
  end
end

class Cell
  attr_reader :x, :block

  def initialize
    @x = 0
  end

  def block=(block)
    @block = block
  end
end

def move_to(other)
  other.block = Block.new(other.x)
  other
end

c = Cell.new
move_to(c)
puts c.x         # 0
puts c.block.x   # 0
