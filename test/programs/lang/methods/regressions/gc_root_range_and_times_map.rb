# `Range#map` and `N.times.map` build a fresh accumulator
# (of Integers, Strings or Floats) and push each block result.
# When the block allocates inside (e.g. string interpolation), a
# GC pass can run mid-loop. The GC must keep the accumulator
# alive.
#
# The "gc root map accumulator" test covers Array receivers. This
# one covers `Range#map` and `N.times.map`.

# (1) Range#map with string-allocating block.
r1 = (0..3000).map { |i| "padded-string-#{i}-with-some-extra-text" }
puts r1.length          # 3001
puts r1[0][0, 6]        # padded
puts r1[3000][-3, 3]    # ext

# (2) Range#map with int block (heap pressure from inner allocations).
r2 = (0...3000).map do |i|
  _scratch = "scratch-#{i}-discarded-inner-allocation-padding"
  i * 2
end
puts r2.length          # 3000
puts r2[0]              # 0
puts r2[2999]           # 5998

# (3) N.times.map.
r3 = 3000.times.map { |i| "kept-#{i}-with-extra-padding-text" }
puts r3.length          # 3000
puts r3[0]              # kept-0-with-extra-padding-text
puts r3[2999][-3, 3]    # ext

# (4) N.times.map with int block + scratch allocations.
r4 = 3000.times.map do |i|
  _scratch = "scratch-#{i}-discarded-inner-allocation-padding"
  i + 1
end
puts r4.length          # 3000
puts r4[0]              # 1
puts r4[2999]           # 3000
