# Integer#gcd / #lcm / #gcdlcm take an Integer; anything else is CRuby's
# "not an integer" TypeError. A String, nil, a Float, a Symbol and an Array
# all raise it.
p((5.gcd("x") rescue $!.message))
p((5.lcm(nil) rescue $!.message))
p((5.gcd(1.5) rescue $!.message))
p((5.gcd(:a) rescue $!.message))
p((5.lcm([1]) rescue $!.message))
p(5.gcd(10))
p(4.lcm(6))
p(4.gcdlcm(6))
