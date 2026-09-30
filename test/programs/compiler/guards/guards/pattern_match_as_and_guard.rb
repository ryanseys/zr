# Pattern-match `=> var` binding and `if` guard clause. A capture
# binds the variable to the matched value at body entry. A guard
# must be true as well as the pattern for the branch to match.

# array pattern with `=> arr` capture
case [1, 2, 3]
in [1, *] => arr
  puts arr.inspect
end

# guard clause with bound variable
case 10
in n if n > 5
  puts "big: " + n.to_s
in n
  puts "small: " + n.to_s
end

# guard's else branch
case 3
in n if n > 5
  puts "big: " + n.to_s
in n
  puts "small: " + n.to_s
end

# object capture
case 42
in Integer => v
  puts "int: " + v.to_s
end
