# A value-typed object used directly as a condition is truthy. The
# condition expression still runs, so its side effects happen.

class Value
  def initialize(x)
    @x = x
  end
end

# Direct constructor in postfix-if predicate
puts "1 ok" if Value.new(0)

# Value-typed local in if-statement
v = Value.new(1)
puts "2 ok" if v

# Inside a loop
i = 0
while i < 1
  puts "3 ok" if Value.new(0)
  i += 1
end

# Ternary if-expression
puts (Value.new(2) ? "4 yes" : "4 no")

# unless: value-type is always truthy, so the body must be skipped
puts "5 not run" unless Value.new(3)
puts "5 done"
