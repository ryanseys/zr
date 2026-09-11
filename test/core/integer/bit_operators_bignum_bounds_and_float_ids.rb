# A bit operator coerces as CRuby's bit_coerce does and names a Float
# by inspect; upto and downto walk toward a Bignum bound; a Float's
# object_id is an Integer whatever word it has.
def t = yield rescue [$!.class, $!.message]

p t { 1 & 1e300 }, t { 1 | 1e300 }, t { 1 ^ 2.5 }, t { 1 & 1.5 }, t { 1 & 2r }, t { (2**70) & 1.5 }
p t { 1.upto(2**64) { break } }, t { n = 0; 5.upto(2**64) { |i| n = i; break if i > 7 }; n }, t { 3.downto(-(2**64)) { break :b } }
p t { (2**64).downto(2**64 - 2).to_a }, t { 1.upto(-(2**64)).to_a }, t { 1.upto(2**64).size }, t { 5.downto(-(2**64)).first(2) }
p t { 1e20.object_id.class }, t { x = 1e20; x.object_id == x.object_id }, t { 1e300.object_id.class }, t { y = 1e300; y.object_id == y.object_id }, t { 0.5.object_id.class }

__END__
[TypeError, "1.0e+300 can't be coerced into Integer"]
[TypeError, "1.0e+300 can't be coerced into Integer"]
[TypeError, "2.5 can't be coerced into Integer"]
[TypeError, "1.5 can't be coerced into Integer"]
[TypeError, "Rational can't be coerced into Integer"]
[TypeError, "1.5 can't be coerced into Integer"]
nil
8
:b
[18446744073709551616, 18446744073709551615, 18446744073709551614]
[]
18446744073709551616
[5, 4]
Integer
true
Integer
true
Integer
