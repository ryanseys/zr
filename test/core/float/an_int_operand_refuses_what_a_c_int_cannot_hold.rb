# A digits or exponent operand is a C int: CRuby's NUM2INT refuses one
# past it by name instead of clamping it.
def t = yield rescue [$!.class, $!.message]

p t { 1.5.round(2**32) }, t { 1.5.round(-2**32) }, t { 1.5.round(2**70) }
p t { 1.5.round(2**31 - 1) }, t { 1.5.round(-2**31) }, t { 1.25.round(1) }
p t { Math.ldexp(1.0, 2**40) }, t { Math.ldexp(1.0, -2**40) }
p t { Math.ldexp(1.0, 2**30) }, t { Math.ldexp(1.0, -2**30) }, t { Math.ldexp(3.0, 2) }

__END__
[RangeError, "integer 4294967296 too big to convert to 'int'"]
[RangeError, "integer -4294967296 too small to convert to 'int'"]
[RangeError, "bignum too big to convert into 'long'"]
1.5
0
1.3
[RangeError, "integer 1099511627776 too big to convert to 'int'"]
[RangeError, "integer -1099511627776 too small to convert to 'int'"]
Infinity
0.0
12.0
