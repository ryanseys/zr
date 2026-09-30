# A proc created inside an INLINED iterator block, capturing the block's param:
# each iteration captures a FRESH binding of the param.
fs = [1, 2, 3].map { |i| ->{ i * 10 } }
p fs[0].call
p fs[1].call
p fs[2].call
procs = []
[7, 8].each { |v| procs << ->{ v } }
p procs[0].call
p procs[1].call
# blocks that do not create capturing procs are left alone
p [1, 2].map { |x| x + 1 }
s = 0
[1, 2, 3].each { |x| s += x }
p s
