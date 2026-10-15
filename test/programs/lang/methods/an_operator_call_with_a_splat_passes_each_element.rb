# An operator method called with a splat (`a.+(*rest)`, or a send that
# names one) takes the splat's elements as its arguments: one is the
# operand, none or two raise ArgumentError.
def try(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end

def add(a, *rest) = a.+(*rest)
def eq(a, *rest) = a.==(*rest)
def cmp(a, *rest) = a.<=>(*rest)
def lt(a, *rest) = a.<(*rest)
def between(a, *rest) = a.between?(*rest)
def shift(a, *rest) = a.<<(*rest)

try("add one") { add(3, 4) }
try("add strings") { add("a", "b") }
try("add none") { add(1) }
try("add two") { add(1, 2, 3) }
try("eq one") { eq(1, 1) }
try("eq none") { eq(1) }
try("cmp one") { cmp(2, 3) }
try("cmp none") { cmp(2) }
try("lt float") { lt(2.5, 3) }
try("lt two") { lt(2, 3, 4) }
try("between") { between(5, 1, 9) }
try("between one") { between(5, 1) }
try("shift") { shift([1], 2) }
try("shift none") { shift([1]) }
try("public_send") { 3.public_send(*[:+, 4]) }
try("send none") { 3.send(*[:+]) }
try("with a block") { 3.+(*[4]) { :ignored } }
rest = [10]
try("literal receiver") { 1.+(*rest) }
try("array literal splat") { 1.+(*[2, 3]) }
