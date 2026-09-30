# Two subclasses each call `super` from `initialize` forwarding a
# differently-typed arg (a String and an Integer). The parent's
# param takes each one.

class T_super_arg_cross_class_cast_Box
  def initialize(v)
    @v = v
  end
end

class T_super_arg_cross_class_cast_StrBox < T_super_arg_cross_class_cast_Box
  def initialize(s)
    super
    @len = s.length
  end

  def len
    @len
  end
end

class T_super_arg_cross_class_cast_IntBox < T_super_arg_cross_class_cast_Box
  def initialize(n)
    super
    @doubled = n * 2
  end

  def doubled
    @doubled
  end
end

s = T_super_arg_cross_class_cast_StrBox.new("hello")
puts s.len

n = T_super_arg_cross_class_cast_IntBox.new(7)
puts n.doubled
