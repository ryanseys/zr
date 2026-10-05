require "bigdecimal"
p BigDecimal(Float::NAN), BigDecimal(Float::INFINITY, 15), BigDecimal(-Float::INFINITY)
p BigDecimal("1") > Float::INFINITY, BigDecimal("1") <=> Float::INFINITY
[[:ceil], [:floor], [:truncate], [:round], [:round, 2], [:ceil, 1]].each { |m, *a| [BigDecimal("NaN"), BigDecimal("Infinity")].each { |v| p [m, a, v.send(m, *a)] rescue p [m, a, $!.class, $!.message] } }
p BigDecimal("Infinity").split, BigDecimal("-Infinity").split, BigDecimal("NaN").split
p((BigDecimal("1").add(BigDecimal("1"), nil) rescue $!), (BigDecimal("1").add(1, -10) rescue $!))
BigDecimal.limit(2); p BigDecimal("0.888").add(BigDecimal(0), 1); BigDecimal.limit(1); p BigDecimal("0.888").add(BigDecimal(0), 3), BigDecimal("0.888").mult(1, 3), BigDecimal("0.888").sub(0, 2), BigDecimal("0.888") + 0; BigDecimal.limit(0)
m = Object.new; def m.coerce(o) = [o, BigDecimal("123")]
p BigDecimal("Infinity") <=> m, BigDecimal("1") <=> m, BigDecimal("1") <=> "x"
p BigDecimal("1E11111111111111111111"), BigDecimal("1E1000000000000000000")**10, BigDecimal("1E-9300000000000000000")
module Over; def to_s(*) = "cheese"; end
BigDecimal.prepend Over
p BigDecimal("44.44").to_s, BigDecimal("44.44").inspect
