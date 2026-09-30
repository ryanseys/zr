# Random / Kernel#rand semantics
srand(5)
p(srand(10))                 # returns previous seed (5)
p(rand(0).class)             # rand(0) -> Float
p(rand(-3).class)            # rand(neg) -> Integer
p(rand(-3) >= 0 && rand(-3) < 3)
p(rand(5...5))               # empty range -> nil
p(rand(5..3))                # reversed range -> nil
r = Random.new(42)
p(r.rand(1.0..2.0).class)    # Float range -> Float
p(r.seed)                    # 42
p(Random.new_seed.class)     # Integer
p(r.class)                   # Random
p(r == r)                    # true
p(r.equal?(r))               # true
p(Random.new(1) == Random.new(1))  # distinct objects -> false
Random.srand(7)
p(rand(100).class)           # Integer
p(Random.urandom(8).bytesize) # 8 bytes. NOT .length: the random bytes can
                              # make multi-byte UTF-8 chars, so .length
                              # can be less than 8
p(Random.urandom(8).class)
begin; rand(1..); rescue => e; p e.class; end   # Errno::EDOM
begin; rand(..5); rescue => e; p e.class; end
