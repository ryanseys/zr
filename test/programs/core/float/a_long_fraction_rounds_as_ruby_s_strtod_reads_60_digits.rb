# ruby_strtod reads at most 60 significant digits of a fraction
# (DBL_DIG * 4) and drops the later ones, so a number just above a
# halfway point, written out in full, rounds down. Every digit before the
# point counts, and leading zeros count for nothing.
def exact_decimal(r)
  k = 0
  k += 1 until (r * 2**k).denominator == 1
  d = (r * 10**k).to_i.to_s.rjust(k + 1, "0")
  k.zero? ? d : "#{d[0...-k]}.#{d[-k..]}"
end

max_mid = exact_decimal((Float::MAX.prev_float.to_r + Float::MAX.to_r) / 2)
tiny_half = exact_decimal(Rational(1, 2**1075))
min_mid = exact_decimal((Float::MIN.to_r + Float::MIN.prev_float.to_r) / 2)
one_mid = exact_decimal((1.0.to_r + 1.0.next_float.to_r) / 2)

cases = {
  "above MAX's midpoint" => max_mid + ".1",
  "above the smallest midpoint" => tiny_half + "1",
  "above MIN's midpoint" => min_mid + "1",
  "above 1.0's midpoint" => one_mid + "1",
  "the same, negative" => "-" + one_mid + "1",
  "with an exponent" => one_mid + "1e0",
  "with trailing text" => one_mid + "1xyz",
  "60 digits then a 9" => "0." + "1" * 60 + "9",
  "leading zeros" => "0." + "0" * 100 + "1" * 70,
  "a long integer part" => "1" * 70 + "." + "9" * 10,
  "short" => "2.5",
}
cases.each do |name, s|
  p [name, s.to_f, (Float(s) rescue :not_a_float)]
end
p "1_0.5".to_f, Float("1_0.5")
