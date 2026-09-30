# String#to_i with an explicit base argument parses the digits in that
# base.
puts "ff".to_i(16)
puts "1010".to_i(2)
puts "777".to_i(8)
puts "z".to_i(36)
puts "-ff".to_i(16)
puts "1_0".to_i(16)
