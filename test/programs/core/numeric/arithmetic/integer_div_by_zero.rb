# Integer division / modulo / divmod / ceildiv by zero raises
# ZeroDivisionError, and a rescue can catch it.
#
# The test uses `puts e`, which prints the message string.

# Bare / catches as ZeroDivisionError
begin
  x = 10 / 0
  puts "no raise: #{x}"
rescue ZeroDivisionError => e
  puts "caught div: #{e}"
end

# Bare % catches as ZeroDivisionError
begin
  x = 10 % 0
  puts "no raise: #{x}"
rescue ZeroDivisionError => e
  puts "caught mod: #{e}"
end

# divmod
begin
  10.divmod(0)
  puts "no raise"
rescue ZeroDivisionError => e
  puts "caught divmod: #{e}"
end

# ceildiv
begin
  x = 10.ceildiv(0)
  puts "no raise: #{x}"
rescue ZeroDivisionError => e
  puts "caught ceildiv: #{e}"
end

# pow with mod=0
begin
  x = 2.pow(10, 0)
  puts "no raise: #{x}"
rescue ZeroDivisionError => e
  puts "caught powmod: #{e}"
end

# /= compound assignment
begin
  x = 10
  x /= 0
  puts "no raise: #{x}"
rescue ZeroDivisionError => e
  puts "caught /=: #{e}"
end

# %= compound assignment
begin
  x = 10
  x %= 0
  puts "no raise: #{x}"
rescue ZeroDivisionError => e
  puts "caught %=: #{e}"
end

# Bare rescue also catches (no class filter at all).
begin
  10 / 0
rescue => e
  puts "bare-rescue: #{e}"
end

# Float division by zero is NOT affected — IEEE 754 returns
# Infinity / NaN, as in CRuby; no exception is raised.
puts (1.0 / 0.0).infinite?
puts (0.0 / 0.0).nan?
