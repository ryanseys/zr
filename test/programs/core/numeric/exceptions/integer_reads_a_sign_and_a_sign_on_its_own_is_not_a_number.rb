# Integer(s) raises ArgumentError on unparseable input, as in CRuby.
# So `Integer(s) rescue 0` gives 0 for invalid input.
#
# The rescue fallbacks are Integers, the same type as the main
# value. With `rescue ArgumentError => e`, the test uses `puts e`.

# Sign handling
sign_pos_zero = (Integer("+0") rescue -1); puts sign_pos_zero
sign_neg_zero = (Integer("-0") rescue -1); puts sign_neg_zero
sign_plus_sp  = (Integer("+ 7") rescue -1); puts sign_plus_sp   # space between sign and digit → invalid
sign_minus_sp = (Integer("- 7") rescue -1); puts sign_minus_sp
sign_double   = (Integer("++7") rescue -1); puts sign_double    # double-sign → invalid
sign_bare     = (Integer("+")   rescue -1); puts sign_bare      # bare sign → invalid

