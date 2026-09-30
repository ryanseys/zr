# Integer#[i] with an out-of-range bit index: i >= 64 reads the sign fill
# and a negative index is 0. Literal receivers and indexes give the same
# result.
puts 5[100]
puts 5[64]
puts 5[63]
puts 5[-1]
puts 5[0]
puts 5[2]
puts(-1[100])
puts(-5[64])
i = 100
puts 5[i]
puts(-1[i])
