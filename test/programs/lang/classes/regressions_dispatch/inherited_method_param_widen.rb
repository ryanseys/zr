# A parent class's instance method param takes the values from
# subclass call sites too, not only from same-class call sites. A
# bare `bar(arg)` in a subclass calls the parent's `bar` with `arg`.

class T_inherited_method_param_widen_T
  def assert_eq(expected, actual)
    if expected == actual
      puts "ok"
    else
      puts "ng"
    end
  end
end

class T_inherited_method_param_widen_Article
  def initialize
    @id = 0
  end
  def write_str(s)
    @id = s   # @id now holds a String, not an Integer
  end
  def id
    @id
  end
end

class T_inherited_method_param_widen_T2 < T_inherited_method_param_widen_T
  def test_it
    a = T_inherited_method_param_widen_Article.new
    a.write_str("hi")
    # Bare call to inherited assert_eq, passing a.id, which can be
    # an Integer or a String. Here it is the String "hi".
    assert_eq("hi", a.id)
  end
end

T_inherited_method_param_widen_T2.new.test_it
