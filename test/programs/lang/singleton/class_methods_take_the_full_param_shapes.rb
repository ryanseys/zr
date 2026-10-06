class P
  def self.m(a, b = 2, *rest, k: 9, **kw, &blk)
    [a, b, rest, k, kw, blk ? blk.call : nil]
  end
end
p P.m(1)
p P.m(1, 3, 4, 5, k: 0, z: 1) { "blk" }
