# Float arithmetic with an INTEGER operand is a float operation. So `1.0 / 0`
# answers Infinity, the same as `1.0 / 0.0` or a variable divisor.
p(1.0 / 0)
p(-1.0 / 0)
p(0.0 / 0)
x = 1.0
p(x / 0)
p(1.0 / 2)
p(3 / 2.0)
p(1.0 + 2)
p(2 * 1.5)
p(7.5 - 2)
p(2.0 ** 3)
begin
  p(1 / 0)
rescue ZeroDivisionError => e
  p e.message
end
begin
  p(1.0 % 0)
rescue ZeroDivisionError => e
  p e.message
end
p(1.0 / 0 > 10 ** 100)
