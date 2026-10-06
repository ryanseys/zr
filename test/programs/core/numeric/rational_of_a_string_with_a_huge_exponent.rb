# A String whose exponent is past a fixnum reads as a Float, as parse_rat
# gives one: a tiny value is zero, which Rational() makes (0/1) and to_r
# keeps, and a huge one is FloatDomainError. A fixnum exponent too large
# for a power of ten is ArgumentError, with no warning.
$VERBOSE = true
["1e-99999999999999999999", "-1e-99999999999999999999", "2e99999999999999999999", "-2e99999999999999999999", "1/1e99999999999999999999",
 "3e-4611686018427387904", "1e-100", "1.5e30", "0e99999999999999999999", "1e-9999999999"].each do |s|
  p [s, (Rational(s) rescue $!), (s.to_r rescue $!), (Rational(s, exception: false) rescue $!)]
end
