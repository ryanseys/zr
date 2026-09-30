p proc { |x, y| }.parameters
p lambda { |x, y| }.parameters
p proc { |a, b = 1, *c, d, k:, m: 2, **n, &blk| }.parameters
p ->(a, b) { }.parameters
p proc { |*| }.parameters
p proc { |**| }.parameters
