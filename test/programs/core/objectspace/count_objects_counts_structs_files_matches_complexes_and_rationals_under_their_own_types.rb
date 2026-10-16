# ObjectSpace.count_objects counts each object under its CRuby type: a
# Struct, a Range and a Data under T_STRUCT, an IO under T_FILE, and a
# MatchData, a Complex and a Rational under their own, subclasses too.
# Each type with no objects is left out, and the keys keep CRuby's order.
class MyStruct < Struct.new(:a); end
class MyRange < Range; end
keep = [MyStruct.new(1), 1r, Complex(1, 2), /a/.match("a"), File.open(__FILE__), MyRange.new(1, 2),
        Data.define(:x).new(x: 1), $stdout]
before = ObjectSpace.count_objects
%i[T_STRUCT T_FILE T_MATCH T_COMPLEX T_RATIONAL].each { |type| p [type, before.fetch(type, 0) > 0] }
p before.keys - [:T_SYMBOL]
p before[:TOTAL] == before.values_at(*(before.keys - %i[TOTAL])).sum

# A new Struct and a new Rational count one more of their types.
GC.disable
from = ObjectSpace.count_objects
more = [MyStruct.new(2), Rational(3, 7)]
to = ObjectSpace.count_objects
GC.enable
p to[:T_STRUCT] - from[:T_STRUCT] >= 1, to[:T_RATIONAL] - from[:T_RATIONAL] >= 1
p keep.size + more.size
