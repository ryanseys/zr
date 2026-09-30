# Call sites pass values of different classes (String and Integer)
# for the same parameter. Each call works, for a self-call inside the
# class and for a call on an object.

class T_method_param_unify_to_poly_CPU
  def feed(x, val)
    val
  end
  # Self-call (no receiver).
  def boot
    feed("hello", 1)
    feed(20, 2)
    feed("world", 3)
  end
end

class T_method_param_unify_to_poly_User
  def initialize(cpu)
    @cpu = cpu
  end
  # Call on an object.
  def reset
    @cpu.feed(100, 10)
    @cpu.feed("via_user", 20)
    @cpu.feed(500, 30)
  end
end

cpu = T_method_param_unify_to_poly_CPU.new
puts cpu.boot
puts T_method_param_unify_to_poly_User.new(cpu).reset
