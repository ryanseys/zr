# fdiv divides big Integers before it rounds, so a quotient in range
# comes out even when each side is past a double; Float#divmod coerces
# an operand it does not know, as every Float operator does.
def t = yield rescue [$!.class, $!.message]

p t { (10**400).fdiv(10**399) }, t { -(10**400).fdiv(10**399) }, t { (10**400).fdiv(3) }
p t { (2**100).fdiv(2**99) }, t { 1.fdiv(3) }, t { 10.fdiv(4) }, t { 1.fdiv(0) }
p t { (10**400).fdiv(1e300) }, t { 7.fdiv(2r) }, t { (3**200).fdiv(7**90) }

p t { 1.5.divmod(1r) }, t { -7.5.divmod(2r) }, t { 1.5.divmod(2) }
p t { 1.5.divmod("x") }, t { 1.5.div(1r) }

__END__
10.0
-10.0
Infinity
2.0
0.3333333333333333
2.5
Infinity
1.0e+100
3.5
2.3196760719186784e+19
[1, 0.5]
[-4, 0.5]
[0, 1.5]
[TypeError, "String can't be coerced into Float"]
1
