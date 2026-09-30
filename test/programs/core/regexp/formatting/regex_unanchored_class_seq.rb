# Unanchored class-sequence patterns (e.g. /\w\w/, /(.)(.)/ ) can
# match at position 0. Ruby picks the match that starts first, and
# the longest one of those that start at the same position.
puts ("abc" =~ /\w\w/).inspect
puts ("abc def" =~ /\w\w/).inspect
puts "abc def".scan(/(.)(.)/).inspect

# Greedy still works.
puts ("aaabbb" =~ /a+/).inspect
puts "aaabbb".scan(/a+/).inspect
puts "aaa-bbb-ccc".scan(/\w+/).inspect
