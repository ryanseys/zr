# Two user classes define `write` with different arities. Heater#write
# takes 2 args and Buzzer#write takes 1. A 2-arg call on an ivar that
# holds a Heater calls Heater#write.

class T_poly_dispatch_arity_truncate_Heater
  def initialize
    @v = 0
  end
  def write(addr, data)
    @v = addr + data
  end
  attr_reader :v
end

class T_poly_dispatch_arity_truncate_Buzzer
  def initialize
    @v = 0
  end
  def write(addr)        # one fewer arg than T_poly_dispatch_arity_truncate_Heater#write
    @v = addr
  end
  attr_reader :v
end

class T_poly_dispatch_arity_truncate_Box
  def initialize
    @poly = nil
    @poly = "x"
    @poly = T_poly_dispatch_arity_truncate_Heater.new   # the last of three writes of mixed classes
  end

  attr_reader :poly

  def call_write(addr, data)
    @poly.write(addr, data)   # Heater and Buzzer both define write
  end
end

b = T_poly_dispatch_arity_truncate_Box.new
b.call_write(7, 5)
puts b.poly.v   # 12  (T_poly_dispatch_arity_truncate_Heater: addr + data)
