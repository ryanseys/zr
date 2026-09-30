# Positional parameter shapes: parenthesized destructuring, the auto-splat
# rule, post-parameter distribution, and the trailing-comma implicit rest.

def one(x) = yield x

# --- Block-local declarations -----------------------------------------------
# The names after the `;` are FRESH locals scoped to the block: they shadow
# any enclosing local of the same name, are reset to nil on every single
# invocation, and never write back out.
sum = 99
[1].each { |x; sum| sum = x }
p sum                              # 99 -- the outer one is untouched

# Reset per call, so this never accumulates -- `total` is nil again at the
# top of each iteration.
total = 42
[1, 2, 3].each { |x; total| total = (total || 0) + x }
p total                            # 42

# Several at once, and alongside ordinary params.
a = 1
b = 2
[0].each { |z; a, b| a = 7; b = 8 }
p [a, b]                           # [1, 2]

# A nested block's own block-local shadows without disturbing the outer
# block's variable.
r = 0
[5].each do |i|
  [9].each { |j; r| r = j }
  r = i
end
p r                                # 5
