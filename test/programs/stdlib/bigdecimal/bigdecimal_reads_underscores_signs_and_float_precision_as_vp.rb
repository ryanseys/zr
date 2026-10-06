# BigDecimal() reads an underscore only between digits or after the
# last, a sign only before Infinity, and a Float to at most 16 digits.
require "bigdecimal"
%w[1_000 1__2 _1 1_ 1.2_3 1_.5 1_e2 1e2_0 -NaN +NaN -Infinity +Infinity].each do |s|
  p [s, (BigDecimal(s) rescue $!)]
end
p((BigDecimal(1.0 / 3, 17) rescue $!), BigDecimal(1.0 / 3, 16))
