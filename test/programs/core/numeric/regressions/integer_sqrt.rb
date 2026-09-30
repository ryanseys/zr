p Integer.sqrt(0)
p Integer.sqrt(1)
p Integer.sqrt(16)
p Integer.sqrt(99)
p Integer.sqrt(100)
p Integer.sqrt(101)
p Integer.sqrt(1_000_000)

# Large-integer precision — beyond the 53-bit double mantissa.
# A double-based sqrt would round and produce off-by-one results
# for values above ~2^53; the Newton-method helper stays exact.
p Integer.sqrt(2**53)
p Integer.sqrt(2**53 + 1)
p Integer.sqrt(2**60)
p Integer.sqrt(2**62 - 1)
