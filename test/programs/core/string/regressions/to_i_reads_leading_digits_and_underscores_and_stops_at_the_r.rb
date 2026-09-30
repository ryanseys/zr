# CRuby's `String#to_i` accepts `_` between consecutive digits and
# stops at the first non-digit, so "1_2_3asdf" gives 123, not 1.

p("1_2_3asdf".to_i)
p("-5_0".to_i)
p("hello".to_i)
p("  42  trailing".to_i)
p("".to_i)
p("0xFF".to_i)   # CRuby: 0 (only base-10 digits)
