# Test send(:literal_symbol)
x = [1,2,3]
puts x.length

class T_send_Adder
  def initialize(n)
    @n = n
  end
  def add(x)
    @n + x
  end
end
a = T_send_Adder.new(10)
puts a.add(5)
