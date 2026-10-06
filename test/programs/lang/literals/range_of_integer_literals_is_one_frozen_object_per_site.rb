def ids = 3.times.map { yield.object_id }.uniq.size

p ids { (1..2) }
p ids { (1...2) }
p ids { (1..) }
p ids { (..-3) }
p ids { (nil..nil) }
p ids { (1..2**70) }
p (1..2).frozen?, (1..2).equal?(1..2)

x = 1
p ids { (x..2) }
p ids { ("a".."b") }
p ids { (1.0..2) }
p ids { (1..2.0) }
p ids { (:a..:b) }

def r = (3..4)
p r.equal?(r)
p Range.new(1, 2).frozen?, Range.new(1, 2).equal?(Range.new(1, 2))

