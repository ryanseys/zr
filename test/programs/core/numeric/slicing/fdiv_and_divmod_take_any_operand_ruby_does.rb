# fdiv divides big Integers before it rounds, so a quotient in range
# comes out even when each side is past a double; Float#divmod coerces
# an operand it does not know, as every Float operator does.
def t = yield rescue [$!.class, $!.message]

p t { (10**400).fdiv(10**399) }, t { -(10**400).fdiv(10**399) }, t { (10**400).fdiv(3) }
p t { (2**100).fdiv(2**99) }, t { 1.fdiv(3) }, t { 10.fdiv(4) }, t { 1.fdiv(0) }
p t { (10**400).fdiv(1e300) }, t { 7.fdiv(2r) }, t { (3**200).fdiv(7**90) }

p t { 1.5.divmod(1r) }, t { -7.5.divmod(2r) }, t { 1.5.divmod(2) }
p t { 1.5.divmod("x") }, t { 1.5.div(1r) }

