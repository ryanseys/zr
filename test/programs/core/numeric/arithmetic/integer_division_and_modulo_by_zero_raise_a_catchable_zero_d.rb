# Integer division or modulo by zero raises a catchable
# `ZeroDivisionError`, as in real Ruby. This is true for literal
# operands and for method-parameter operands.

begin
  puts(5 % 0)
rescue ZeroDivisionError
  puts "mod zero div"
end
class Calc
  def divide(a, b)
    a / b
  end
end
begin
  puts Calc.new.divide(10, 0)
rescue ZeroDivisionError
  puts "param zero div"
end
