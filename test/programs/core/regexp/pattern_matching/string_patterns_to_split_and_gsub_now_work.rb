# split and gsub take a String pattern as well as a Regexp, and match
# the String as literal text. Oracle-verified.

puts "a,b".split(",").inspect
puts "a,b".gsub(",", ";")
