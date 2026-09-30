# Enumerable#member? is the documented alias of #include?. It works
# on Integer arrays and on String arrays.
puts [1,2,3].member?(2)
puts [1,2,3].member?(99)
puts ["a","b"].member?("a")
puts ["a","b"].member?("z")
