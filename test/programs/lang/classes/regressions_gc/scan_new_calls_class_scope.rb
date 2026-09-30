# `Bar.new(@x, ...)` inside `Foo#initialize` passes the object in
# `@x`, so Bar#initialize's first param gets that object.

class T_scan_new_calls_class_scope_A
  attr_reader :n
  def initialize(n)
    @n = n
  end
end

class T_scan_new_calls_class_scope_B
  attr_reader :a
  def initialize(a_arg)
    @a = a_arg
  end
end

class T_scan_new_calls_class_scope_C
  attr_reader :b
  def initialize
    @inner = T_scan_new_calls_class_scope_A.new(7)
    @b = T_scan_new_calls_class_scope_B.new(@inner)
  end
end

c = T_scan_new_calls_class_scope_C.new
puts c.b.a.n   # 7
