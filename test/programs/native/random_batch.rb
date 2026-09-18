# Random draws and rules -- it needs urandom.
class Two
  def to_int = 2
end
srand(5)
p(srand(10))
p(rand(0).class, rand(-3).class, rand(5...5), rand(5..3))
r = Random.new(42)
p(r.rand(1.0..2.0).class, r.seed, Random.new_seed.class, r == r, Random.new(1) == Random.new(1))
begin; Random.new(1).rand(5...5); rescue ArgumentError => e; puts e.message; end
p Random.new(3.9).seed, Random.new(3.9).rand(1000), Random.new(-99).rand(1000)
begin; Random.new("3"); rescue TypeError => e; puts e.message; end
p Random.new(5).inspect.length, Random.new(5).to_s.start_with?("#<Random:0x")
r = Random.new(42)
p r.rand(100), r.rand(100), r.rand, Random.new(42).rand(1000000)
r = Random.new(5)
p r.rand(1), r.rand(2), r.rand(2.5), r.rand(2..9), r.rand(2...9), r.rand(1.0..2.0), r.rand(1.0...2.0)
p Random.new(5).bytes(16).unpack1("H*")
[0, 1, 7, 12345, 2**31, 2**32 - 1].each { |s| p [s, Random.new(s).rand(1000)] }
p Random.urandom(8).bytesize, Random.urandom(8).class, Random.random_number(3).class
p [1, 2, 3].combination(Two.new).to_a, [1, 2, 3].permutation(Two.new).to_a.size
