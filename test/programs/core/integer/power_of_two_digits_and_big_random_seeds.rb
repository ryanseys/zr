# to_s in a base that is a power of two reads the bits, in time linear in
# the length, and a Random seeded with a huge number splits it into words
# the same way: both give ruby's values, and the huge seed is quick.
nums = [2**64, 2**64 - 1, -(2**64), 2**100 + 12345, -(3**80), 2**30, 2**31 - 1, 2**90 + 2**60 + 1, (2**200 - 1) / 7]
[2, 4, 8, 16, 32].each { |b| p nums.map { _1.to_s(b) } }
p nums.map { _1.to_s(36) }
p (2**130).digits(2**32).size, (-(2**129)).to_s(2).size
[2**64 + 5, 2**200 + 7, 2**1000 - 1].each do |seed|
  r = Random.new(seed)
  p [r.rand(2**70), r.rand(0x100000000), r.rand(2**65 + 3), r.seed == seed]
end
srand(2**300 + 1)
p rand(2**80)
t = Time.now
r = Random.new(2**1000000 - 1)
p r.rand(0x100000000), r.rand(2**1000)
$stderr.puts "big seed in time: #{Time.now - t < 10}"
