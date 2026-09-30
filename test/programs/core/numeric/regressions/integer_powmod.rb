# basic
puts 2.pow(10, 1000)
puts 5.pow(2, 3)
puts 3.pow(3, 8)

# exp zero
puts 2.pow(0, 5)
puts 0.pow(0, 5)

# mod one — always zero
puts 2.pow(100, 1)
puts 999.pow(999, 1)

# negative base
puts((-2).pow(3, 5))
puts((-3).pow(2, 7))

# large exponent
puts 2.pow(20, 1000000)
puts 7.pow(15, 100)

# base larger than mod
puts 100.pow(3, 7)

# base zero
puts 0.pow(5, 3)

# base one
puts 1.pow(999, 7)

# mod two
puts 7.pow(3, 2)

# exp one
puts 5.pow(1, 3)

# negative mod
puts 2.pow(2, -3)
puts 2.pow(3, -5)

# one-arg pow
puts 2.pow(10)
puts 3.pow(3)
