r = Random.new(42)
p r.rand(100), r.rand(1..6), r.bytes(5), r.seed, r.rand(3...4), r.bytes(0), r.bytes(4)
p Random.new(2**40).rand(1000), Random.new(-5).rand(10), Random.new(5).rand(10), Random.new(0).rand(10)
r2 = Random.new(42)
p [1, 2, 3, 4, 5].shuffle(random: r2), [1, 2, 3, 4, 5].sample(random: r2), [1, 2, 3, 4, 5].sample(2, random: r2), [1, 2, 3, 4, 5].sample(3, random: r2)
p Random.new(1).rand(2**40), Random.new(1).rand(2**33), Random.new(1).rand(2**32), Random.new(1).rand(2**32 + 1)
begin; Random.new(3).rand(0); rescue => e; p e; end
begin; Random.new(3).rand(-1); rescue => e; p e; end
begin; Random.new(3).rand(5..1); rescue => e; p e; end
p Random.new_seed.class, Random.rand(10).class, rand(5).class, srand(4).class, srand(4), rand(100), Random.new(4).rand(100), Random.ancestors, Random.superclass
p Random.seed, Random.rand(1..3), Random.bytes(3).size
a = (1..100).to_a
r3 = Random.new(9)
p a.sample(4, random: r3), a.sample(10, random: r3), a.sample(11, random: r3), a.sample(50, random: r3), a.shuffle(random: r3).first(6)
big = (1..3000).to_a
r4 = Random.new(11)
p big.sample(11, random: r4), big.sample(12, random: r4)
p [].sample, [].sample(2), [1].sample(3), [1, 2].sample(0)
r5 = Random.new(7)
1000.times { r5.rand(1000) }
p r5.rand(1000), r5.rand(2**61)
begin; Random.new("x"); rescue => e; p e; end
p Random.new(7) == Random.new(7), Random.new(7) == Random.new(8)
p(("".b << 200), ("" << 200), ("" << 65), ("" << 0x20AC))
begin; "" << -1; rescue => e; p e; end
begin; "".b << 256; rescue => e; p e; end
begin; "" << 0x110000; rescue => e; p e; end
p "h\xC3\xA9llo", "h\xC3\xA9llo".b, "\xff".b, "\xffabc", "\xE2\x82\xAC".b + "a", ("a" + "\xff".b).b.size, "\xff".b.dup, "\xff".b.size, "\xff".b.bytes
