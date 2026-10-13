# ruby 4.1: Rational() and String#to_r read an `r` or `R` after a number
# in place of an exponent. An exponent and an `r` together do not parse.
def t(label)
  p [label, yield]
rescue Exception => e
  p [label, e.class, e.message]
end

t(:pair) { Rational("3.0r", "2.4R") }
t(:whole) { Rational("3r") }
t(:negative) { Rational("-1.5R") }
t(:fraction) { Rational("1/2r") }
t(:spaces) { Rational(" 1r ") }
t(:underscore) { Rational("1_0r") }
t(:after_exponent) { Rational("2.4e1r") }
t(:before_exponent) { Rational("2.4re1") }
t(:alone) { Rational("r") }
t(:twice) { Rational("1rr") }
t(:hex) { Rational("0x1r") }
t(:to_r_slash) { "3.0r/2.4R".to_r }
t(:to_r_trailing) { "1.5rx".to_r }
t(:to_r_exponent) { "2e1r".to_r }
t(:to_r_twice) { "1rr".to_r }
t(:to_r_numerator) { "1r/2".to_r }
t(:to_c) { "3r".to_c }
t(:complex) { Complex("3r") }
