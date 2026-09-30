# `a && b` where `a` is an ivar that held a String and then an
# Integer. Any value that is not nil or false is truthy.

class T_and_node_poly_operand_Holder
  def initialize
    @poly = "x"   # string first…
    @poly = 42    # …then an Integer
    @counter = 0
  end

  attr_reader :poly, :counter

  def chain
    if @poly && @counter == 0
      @counter = 1
    end
    @counter
  end
end

h = T_and_node_poly_operand_Holder.new
puts h.chain    # 1
