# Two independent draws must differ, and -- unlike Kernel#rand -- srand must
# NOT make SecureRandom reproducible (it reads the OS CSPRNG, not the seedable
# generator). A clock-seeded generator would fail this check.

require "securerandom"
puts(SecureRandom.hex(16) != SecureRandom.hex(16))
srand(42); a = SecureRandom.hex(16)
srand(42); b = SecureRandom.hex(16)
puts(a != b)
# Random.urandom itself: correct bytesize, drawn fresh each call.
puts Random.urandom(24).bytesize
puts(Random.urandom(8) != Random.urandom(8))
