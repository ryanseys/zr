# A nested map block — outer iteration allocates plenty of inner
# objects — can trigger a GC pass between pushes into the outer
# accumulator. The GC must keep the accumulator alive.
#
# Each .map below crosses the GC threshold mid-loop (each block
# iteration allocates a discarded scratch string alongside the
# kept result), so the outer accumulator must survive a
# collection.

# (1) Integer-array recv → String results (string-return block).
ints = []
i = 0
while i < 20000
  ints << i
  i += 1
end

r1 = ints.map do |x|
  _scratch = "scratch-#{x}-discarded-inner-allocation-padding"
  "kept-string-value-#{x}"
end
puts r1.length            # 20000
puts r1[0]                # kept-string-value-0
puts r1[19999][-3, 3]     # 999

# (2) Integer-array recv → Integer results (int-return block).
r2 = ints.map do |x|
  _scratch = "scratch-#{x}-discarded-inner-allocation-padding"
  x * 2
end
puts r2.length            # 20000
puts r2[0]                # 0
puts r2[19999]            # 39998

# (3) String-array recv → String results (string-return block).
strs = []
i = 0
while i < 20000
  strs << "src-#{i}"
  i += 1
end

r3 = strs.map do |s|
  _scratch = "scratch-#{s}-discarded-inner-allocation-padding"
  "out-#{s}"
end
puts r3.length            # 20000
puts r3[0]                # out-src-0
puts r3[19999][-3, 3]     # 999

# (4) String-array recv → Integer results (int-return block).
r4 = strs.map do |s|
  _scratch = "scratch-#{s}-discarded-inner-allocation-padding"
  s.length
end
puts r4.length            # 20000
puts r4[0]                # 5  (out-0 → "src-0")
puts r4[19999]            # 9  ("src-19999")
