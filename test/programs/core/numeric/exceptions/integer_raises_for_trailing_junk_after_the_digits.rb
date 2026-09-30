# Integer(s) raises ArgumentError on unparseable input, as in CRuby.
# So `Integer(s) rescue 0` gives 0 for invalid input.
#
# The rescue fallbacks are Integers, the same type as the main
# value. With `rescue ArgumentError => e`, the test uses `puts e`.

# Trailing-junk variants
trail_junk      = (Integer("42x") rescue -1);          puts trail_junk
trail_junk_ws   = (Integer("42 x") rescue -1);         puts trail_junk_ws       # whitespace then junk
trail_nl_junk   = (Integer("42\n garbage") rescue -1); puts trail_nl_junk
trail_only_ws   = (Integer("42 ") rescue -1);          puts trail_only_ws       # bare trailing whitespace OK

