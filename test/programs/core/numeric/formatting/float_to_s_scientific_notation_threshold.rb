# Fixed for decpt in -3..=15, else scientific -- matches CRuby's Float#to_s.

puts 999999999999999.0
puts 1000000000000000.0
puts 6402373705728000.0
puts 0.0001
puts 0.00009
