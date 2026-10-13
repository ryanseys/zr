# bigdecimal 4.1.3: BigDecimal() refuses text in an ASCII-incompatible
# encoding and text with a NUL, and gives nil for one with exception:
# false. interpret_loosely (and String#to_d) reads up to the first NUL.
# A Complex with an imaginary part gives nil with exception: false.
require "bigdecimal"
require "bigdecimal/util"

def t(label)
  p [label, yield]
rescue Exception => e
  p [label, e.class, e.message]
end

p BigDecimal::VERSION
t(:nul) { BigDecimal("1\0" "2") }
t(:nul_quiet) { BigDecimal("1\0" "2", exception: false) }
t(:nul_first) { BigDecimal("\0") }
t(:utf16) { BigDecimal("1".encode("UTF-16LE")) }
t(:utf16_quiet) { BigDecimal("1".encode("UTF-16BE"), exception: false) }
t(:utf32) { BigDecimal("1".encode("UTF-32LE"), exception: false) }
t(:binary) { BigDecimal("1.5".b) }
t(:sjis) { BigDecimal("2.5".encode("Shift_JIS")) }
t(:to_str) { BigDecimal(Struct.new(:s) { def to_str = s }.new("3\0")) }
t(:to_str_quiet) { BigDecimal(Struct.new(:s) { def to_str = s }.new("3\0"), exception: false) }
t(:complex) { BigDecimal(Complex(1, 2)) }
t(:complex_quiet) { BigDecimal(Complex(1, 2), exception: false) }
t(:complex_real) { BigDecimal(Complex(2, 0)) }
t(:complex_float_zero) { BigDecimal(Complex(1.5, 0.0), 3) }
t(:complex_rational) { BigDecimal(Complex(Rational(1, 3), 0), 5) }
t(:complex_rational_noprec) { BigDecimal(Complex(Rational(1, 3), 0)) }
t(:loose_nul) { BigDecimal.interpret_loosely("12\0" "34") }
t(:loose_lead_nul) { BigDecimal.interpret_loosely("\0" "34") }
t(:loose_utf16) { BigDecimal.interpret_loosely("12".encode("UTF-16LE")) }
t(:loose_int) { BigDecimal.interpret_loosely(12) }
t(:loose_to_str) { BigDecimal.interpret_loosely(Struct.new(:s) { def to_str = s }.new("7.5x")) }
t(:to_d_nul) { "1.5\0" "9".to_d }
t(:to_d_utf16) { "1".encode("UTF-16LE").to_d }
t(:true) { BigDecimal(true) }
t(:true_quiet) { BigDecimal(true, exception: false) }
