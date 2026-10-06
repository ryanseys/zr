# Bigint division / modulo by zero raises ZeroDivisionError.
#
# `a = a * 2` inside a `while` loop grows the local: 50 steps make
# `a` a large value before the / 0 expression runs. The division and
# the modulo raise ZeroDivisionError, as Integer division does.

a = 1
i = 0
while i < 50
  a = a * 2
  i = i + 1
end

# `a` is now 2^50.

begin
  x = a / 0
  puts "no raise"
rescue ZeroDivisionError => e
  puts "caught bigint div: #{e}"
end

begin
  x = a % 0
  puts "no raise"
rescue ZeroDivisionError => e
  puts "caught bigint mod: #{e}"
end

# Bare rescue also catches.
begin
  a / 0
rescue => e
  puts "bare-rescue: #{e}"
end
