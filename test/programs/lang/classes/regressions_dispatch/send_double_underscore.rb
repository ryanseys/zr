# .__send__(:sym, args) and .__send__("sym", args) call .sym(args),
# the same as .send. CRuby gives __send__ as the alias of send that
# a class cannot easily override.

class T_send_double_underscore_Calc
  def add(a, b)
    a + b
  end

  def hello
    "hi"
  end
end

c = T_send_double_underscore_Calc.new

# Symbol arm: .__send__(:sym, args) -> .sym(args).
puts c.__send__(:add, 10, 20)   # 30
puts c.__send__(:hello)         # hi

# String arm: .__send__("sym", args) -> .sym(args).
puts c.__send__("add", 3, 4)    # 7
puts c.__send__("hello")        # hi

puts "done"
