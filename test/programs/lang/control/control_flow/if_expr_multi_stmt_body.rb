# When an `if` expression's value is consumed (assignment, return,
# ternary slot, etc.) and a branch holds multiple statements, each
# leading statement runs for its side effect, and the last one gives
# the value of the branch.
#
# Coverage:
# - Multi-stmt then- and else-branches assigned to a local
# - Elsif chain recursion (multi-stmt branches inside the else slot)
# - Nested if-expression used as a method argument
# - Mixed branch lengths (single-stmt then, multi-stmt else)
# - Empty/missing else
#
# Out of scope:
# - Branches of mixed concrete types (Integer and String).

x = if true
      puts "a"
      1
    else
      puts "z"
      0
    end
puts x

y = if false
      puts "skipped"
      99
    else
      puts "b"
      puts "c"
      42
    end
puts y

# Elsif chain recursion.
z = if false
      1
    elsif true
      puts "elsif"
      2
    else
      3
    end
puts z

# Nested if-expression as a method argument.
puts(if true
       puts "nested"
       10
     end)

# Mixed branch lengths.
m = if false
      99
    else
      puts "else-multi"
      100
    end
puts m

# Empty/missing else.
n = if true
      puts "no-else"
      77
    end
puts n
