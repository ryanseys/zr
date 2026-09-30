# Integer(s) raises ArgumentError on unparseable input, as in CRuby.
# So `Integer(s) rescue 0` gives 0 for invalid input.
#
# The rescue fallbacks are Integers, the same type as the main
# value. With `rescue ArgumentError => e`, the test uses `puts e`.

# Leading-junk variants
lead_junk    = (Integer("x42") rescue -1);    puts lead_junk
lead_ws_junk = (Integer(" x 42") rescue -1);  puts lead_ws_junk

