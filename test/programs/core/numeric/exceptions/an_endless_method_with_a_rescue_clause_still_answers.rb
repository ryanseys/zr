# Integer(s) raises ArgumentError on unparseable input, as in CRuby.
# So `Integer(s) rescue 0` gives 0 for invalid input.
#
# The rescue fallbacks are Integers, the same type as the main
# value. With `rescue ArgumentError => e`, the test uses `puts e`.

# An endless method with a rescue modifier: Integer("abc") raises,
# and the rescue catches it and returns 0.
def parse_int(s) = Integer(s) rescue 0
puts parse_int("42")
puts parse_int("abc")
puts parse_int("0")
puts parse_int("-7")
