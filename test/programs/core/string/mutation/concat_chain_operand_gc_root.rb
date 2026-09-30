# A chained string concat `a + b + c` (and `a+b+c+d`) joins all operands
# in one step. The operands must be rooted before the join:
# argument evaluation order is unspecified, so a fresh GC string
# produced by one operand can be collected while a sibling operand
# allocates. Here each tag() allocates and forces a GC, so a later
# operand's GC.start collects an earlier operand's unrooted result.
def tag(s)
  r = "[" + s + "]"   # fresh heap string
  GC.start            # collect; sibling operands still pending must survive
  r
end

three = tag("a") + "\n" + tag("b") + "\n" + tag("c")
four  = tag("w") + tag("x") + tag("y") + tag("z")
puts three
puts four
