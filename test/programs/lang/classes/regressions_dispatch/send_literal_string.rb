# .send("sym", args) with a plain string literal calls .sym(args), the
# same as the :symbol form.

class T_send_literal_string_Calc
  def add(a, b)
    a + b
  end

  def hello
    "hi"
  end
end

c = T_send_literal_string_Calc.new
puts c.send("add", 2, 3)       # 5
puts c.send("hello")           # hi

puts "done"
