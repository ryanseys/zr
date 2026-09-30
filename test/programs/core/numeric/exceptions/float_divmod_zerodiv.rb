# Float#divmod(0) / Float#divmod(0.0) raises ZeroDivisionError.
# Integer#divmod(0) raises the same error.
#
# The test uses `puts e`, which prints the message string.

# Sanity: divmod with non-zero divisor still works.
q, r = 5.0.divmod(2.0)
puts q
puts r

# Float / int divisor
begin
  1.0.divmod(0)
  puts "no raise"
rescue ZeroDivisionError => e
  puts "caught int divisor: #{e}"
end

# Float / float divisor
begin
  1.0.divmod(0.0)
  puts "no raise"
rescue ZeroDivisionError => e
  puts "caught float divisor: #{e}"
end

# Bare rescue catches it.
begin
  3.5.divmod(0.0)
rescue => e
  puts "bare-rescue: #{e}"
end

# NaN divisor → FloatDomainError("NaN").
nan = 0.0 / 0.0
begin
  1.0.divmod(nan)
  puts "no raise nan divisor"
rescue FloatDomainError => e
  puts "caught nan divisor: #{e}"
end

# NaN dividend → FloatDomainError("NaN").
begin
  nan.divmod(2.0)
  puts "no raise nan dividend"
rescue FloatDomainError => e
  puts "caught nan dividend: #{e}"
end
