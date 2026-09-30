# Integer(s) raises ArgumentError on unparseable input, as in CRuby.
# So `Integer(s) rescue 0` gives 0 for invalid input.
#
# The rescue fallbacks are Integers, the same type as the main
# value. With `rescue ArgumentError => e`, the test uses `puts e`.

# Valid inputs unchanged
a = (Integer("42") rescue -1)
puts a
b = (Integer("0") rescue -1)
puts b
c = (Integer("-7") rescue -1)
puts c
d = (Integer("+5") rescue -1)
puts d

