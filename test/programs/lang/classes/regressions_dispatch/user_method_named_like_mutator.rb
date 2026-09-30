# A user class defines a method with the name of a Hash or Array
# mutator (`update`, `clear`, `concat`, `delete`, `each`, `pop`,
# `push`, `merge!`, ...). A call to it as the last expression gives
# its return value, also in the implicit `self.update(...)` form.
#
# `T_user_method_named_like_mutator_C.new.f(7)` returns 8, and
# `T_user_method_named_like_mutator_D.new.run(T_user_method_named_like_mutator_C.new)` returns 30.

class T_user_method_named_like_mutator_C
  def update(target)
    target
  end
  def f(n)
    update(n + 1)   # implicit self.update
  end
end

class T_user_method_named_like_mutator_D
  def run(c)
    c.update(30)    # explicit recv on user class
  end
end

puts T_user_method_named_like_mutator_C.new.f(7)
puts T_user_method_named_like_mutator_D.new.run(T_user_method_named_like_mutator_C.new)
