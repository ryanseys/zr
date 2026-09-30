# Integer(s) raises ArgumentError on unparseable input, as in CRuby.
# So `Integer(s) rescue 0` gives 0 for invalid input.
#
# The rescue fallbacks are Integers, the same type as the main
# value. With `rescue ArgumentError => e`, the test uses `puts e`.

# Edge magnitudes within the 64-bit range
ll_max = (Integer("9223372036854775807")  rescue -1); puts ll_max   # LLONG_MAX
ll_min = (Integer("-9223372036854775808") rescue -1); puts ll_min   # LLONG_MIN

