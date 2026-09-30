# A `while` loop is entered before its condition runs, so a `break` or
# `next` in the condition belongs to that loop: at the top level, in a
# method, and in a block, where it leaves the loop and not the block.
i = 0
p(while (i += 1; i < 3 or break :done); end)

def f
  j = 0
  while (j += 1; j < 5 or break j * 10); end
end
p f

k = 0
p [1].map { while (k += 1; k < 2 or break :inner); end }

n = 0
seen = []
while (n += 1; next if n == 2; seen << n; n < 4); end
p seen

m = 0
p(until (m += 1; m > 2 and break :stopped); end)

