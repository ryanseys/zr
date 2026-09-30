# Integer(s) raises ArgumentError on unparseable input, as in CRuby.
# So `Integer(s) rescue 0` gives 0 for invalid input.
#
# The rescue fallbacks are Integers, the same type as the main
# value. With `rescue ArgumentError => e`, the test uses `puts e`.

# Invalid inputs raise (caught by rescue, returns -1)
f = (Integer("xyz") rescue -1); puts f
g = (Integer("") rescue -1); puts g
h = (Integer("   ") rescue -1); puts h
ii = (Integer("12abc") rescue -1); puts ii
j = (Integer("12.5") rescue -1); puts j

