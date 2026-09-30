# A constant expression of integer literals whose value is more
# than the int32 maximum keeps its exact value. It must not wrap
# to a negative number. optcarrot has constants of this shape, for
# example `APU::Mixer::TND_1 = 100 * 24329 * 256 / 500`.

# Each chain straddles int32: max 2^31 - 1 = 2,147,483,647.
A = 24329 * 256 * 500           # 3,114,112,000
B = 100000 * 100000              # 10,000,000,000
C = 65535 * 65535                # 4,294,836,225
D = 2 ** 40                      # 1,099,511,627,776
E = 1_000_000_000 + 1_000_000_000 # 2,000,000,000 — sum overflow

puts A
puts B
puts C
puts D
puts E
