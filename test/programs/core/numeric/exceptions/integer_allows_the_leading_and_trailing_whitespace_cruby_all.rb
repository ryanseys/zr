# Integer(s) raises ArgumentError on unparseable input, as in CRuby.
# So `Integer(s) rescue 0` gives 0 for invalid input.
#
# The rescue fallbacks are Integers, the same type as the main
# value. With `rescue ArgumentError => e`, the test uses `puts e`.

# Whitespace handling per CRuby (leading/trailing whitespace ok).
# Includes \t \n \r \v \f, and Integer() skips all of them.
e = (Integer("  -7  ") rescue -1)
puts e
e_tab = (Integer("\t42\t") rescue -1)
puts e_tab
e_nl = (Integer("\n42\n") rescue -1)
puts e_nl
e_cr = (Integer("\r42\r") rescue -1)
puts e_cr
e_vt = (Integer("\v42\v") rescue -1)
puts e_vt
e_ff = (Integer("\f42\f") rescue -1)
puts e_ff
e_mix = (Integer("  \t\n -7 \r\f ") rescue -1)
puts e_mix

