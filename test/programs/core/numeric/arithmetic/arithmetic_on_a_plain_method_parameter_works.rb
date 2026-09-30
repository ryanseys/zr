# The operands are method params, not literals or locals, so their
# types are known only at run time.

class Adder
  def add(a, b)
    a + b
  end
end
puts Adder.new.add(3, 4)
