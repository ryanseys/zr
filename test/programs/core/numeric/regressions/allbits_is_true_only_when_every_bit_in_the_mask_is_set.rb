# Basic, subset, zero mask, single bit, large value and a negative
# receiver -- the same matrix nobits? and anybits? are held to.

puts 255.allbits?(255)
puts 255.allbits?(128)
puts 0.allbits?(0)
puts 42.allbits?(0)
puts 5.allbits?(6)
puts 8.allbits?(3)
puts 4.allbits?(4)
puts 4.allbits?(2)
puts 0xFFFF.allbits?(0xFF00)
puts((-1).allbits?(255))
puts 0.allbits?(1)
