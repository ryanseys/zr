# `slot OP= rhs` desugars to `slot = slot OP rhs`. When the slot
# holds an object and the class defines OP as a user method, the
# call goes to that method.

class Box
  def initialize(n)
    @n = n
    @arr = []
    @arr << n   # force heap layout, not value-type
  end
  attr_reader :n

  def +(other); Box.new(@n + other); end
  def -(other); Box.new(@n - other); end
end

# Instance-variable op-assign in stmt position.
class IvarStmt
  def initialize
    @b = Box.new(10)
    @b += 5
  end
  attr_reader :b
end
puts IvarStmt.new.b.n          # 15

# Local-variable op-assign in stmt position.
def local_stmt
  b = Box.new(20)
  b -= 3
  b.n
end
puts local_stmt                # 17
