# String#partition with a regex splits at the first match, and
# `puts <tuple>` with a partition result prints each element.
puts "hello world".partition(" ")
puts "hello world".partition(/o/).inspect
puts "hello,world".partition(",").inspect
puts "no-sep".partition(",").inspect
