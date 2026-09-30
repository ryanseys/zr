# `[a, b, c, d].map { (0...M).map { (0..N).map { ... } } }` builds a
# 3-level Array<Array<Array<Integer>>>. The outer .map's receiver is an
# array literal. The GC must keep that receiver alive while the block
# body's nested allocations run collections. `TBL.length` is 4, and
# each `TBL[X]` is its own row.
#
# The test also covers `recv[start, len] = src` where recv is a mixed
# array and src has an unknown type (e.g. `@bg_pixels[xfine, 8] =
# @bg_pattern_lut[idx]`). The slice assignment replaces `len` elements
# with src, not `recv[start] = len`.

# Inner range is sized large enough (>= ~272) that an inner GC
# triggers during the outer .map's iteration. The reads of
# TBL[a][b][c] use indices in variables, not literal indices.
TBL = [10, 20, 30, 40].map do |a|
  (0...500).map do |i|
    (0..7).map do |j|
      a + i + j
    end
  end
end

puts TBL.length          # 4
puts TBL[0].length       # 500

a0 = 0
a1 = 1
a2 = 2
a3 = 3
i0 = 0
i499 = 499
j0 = 0
j7 = 7

puts TBL[a0].length        # 500
puts TBL[a0][i0].length    # 8
puts TBL[a0][i0][j0]       # 10
puts TBL[a1][i0][j0]       # 20
puts TBL[a3][i0][j7]       # 47
puts TBL[a2][i499][j0]     # 529
puts TBL[a3][i499][j7]     # 546

# Slice assign with a mixed-array recv and a src of unknown type --
# the `@buf[start, len] = @table[a][i]` shape of @bg_pixels in
# optcarrot. @table[a][i] is an Integer array, and @buf is sized via
# `[nil] * N`. The assignment replaces the slice with the src
# elements, not only `@buf[start]`.
class Slicer
  def initialize
    @table = [10, 20, 30].map { |a| (0...4).map { |i| (0..3).map { |j| a + i + j } } }
    @buf = [nil] * 7
    @buf[0] = -1; @buf[1] = -1; @buf[2] = -1; @buf[3] = -1
    @buf[4] = -1; @buf[5] = -1; @buf[6] = -1
  end
  def fill(a, i); @buf[1, 4] = @table[a][i]; end
  def get(k); @buf[k]; end
end

s = Slicer.new
s.fill(2, 1)
puts s.get(0)            # -1
puts s.get(1)            # 31
puts s.get(2)            # 32
puts s.get(3)            # 33
puts s.get(4)            # 34
puts s.get(5)            # -1
s.fill(0, 0)
puts s.get(1)            # 10
puts s.get(4)            # 13
