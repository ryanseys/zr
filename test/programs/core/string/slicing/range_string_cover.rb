# Range#include? / cover? / === on string ranges. The bounds compare
# as Strings.

puts ("a".."z").include?("m")
puts ("a".."z").cover?("m")
puts ("a".."z").include?("Z")
puts ("a".."z").cover?("a")
puts ("a".."z").cover?("z")
puts ("a"..."z").cover?("z")  # exclusive end
