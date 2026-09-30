# `case arr in [a, b, c]` binds each local variable to the element at
# the matching index, with the element type of the scrutinee.

case [1, 2, 3]
in [a, b, c]
  puts "matched: #{a}, #{b}, #{c}"
end

# String array
case ["x", "y", "z"]
in [p, q, r]
  puts "matched: #{p}, #{q}, #{r}"
end

# Non-match arm: fall through to else
case [1, 2]
in [a, b, c]
  puts "wrong"
in [a, b]
  puts "two: #{a}, #{b}"
end
