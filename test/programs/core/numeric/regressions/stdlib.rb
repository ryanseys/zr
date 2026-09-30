# Array#join
arr = (1..5).to_a
puts arr.join(", ")

# Array#uniq
nums = (1..5).to_a
nums.push(3)
nums.push(1)
uniq = nums.uniq
puts uniq.length

# srand/rand
srand(0)
r = rand(100)
puts r >= 0

# ARGV.length
puts ARGV.length

puts "done"
