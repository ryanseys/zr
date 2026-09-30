# .send(:sym, args) calls .sym(args).

class T_send_literal_symbol_Calc
  def add(a, b)
    a + b
  end

  def double(x)
    x * 2
  end

  def hello
    "hi"
  end

  # Returns the input length; the test passes args with parens in them.
  def length_of(s)
    s.length
  end
end

# 1. Basic shapes.
c = T_send_literal_symbol_Calc.new
puts c.send(:add, 3, 4)        # 7
puts c.send(:double, 21)       # 42
puts c.send(:hello)            # hi

# 2. Parens inside String args are part of the String.
puts c.send(:length_of, "a)b")     # 3
puts c.send(:length_of, "x(y)z")   # 5
puts c.send(:length_of, 'p)q')     # 3

# 3. Operator method `[]` via send calls the index operator.
arr = [10, 20, 30]
puts arr.send(:[], 0)          # 10
puts arr.send(:[], 2)          # 30

# 4. Operator method `[]=` via send calls .[]=(idx, val).
arr.send(:[]=, 1, 99)
puts arr[0]                    # 10
puts arr[1]                    # 99
puts arr[2]                    # 30

puts "done"
