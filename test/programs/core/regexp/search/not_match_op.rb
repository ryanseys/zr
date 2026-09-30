# `str !~ /pattern/` returns true when no match and false when there is
# a match: `!~` is the negation of `=~`.

puts "hello" !~ /xyz/
puts "hello" !~ /llo/
puts "abc 123" !~ /\d+/
puts "abc" !~ /\d+/
