# Reassigning an instance variable to a different Symbol. A read gives
# the new Symbol.

class T_symbol_ivar_reassign_C
  def initialize
    @s = :foo
  end

  def reset
    @s = :bar
  end

  def show
    @s
  end
end

c = T_symbol_ivar_reassign_C.new
puts c.show
c.reset
puts c.show
