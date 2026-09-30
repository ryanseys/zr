# Integer#nonzero? returns nil when receiver is 0, self otherwise.
puts 0.nonzero?.inspect
puts 42.nonzero?.inspect
puts(-5.nonzero? || "default")
