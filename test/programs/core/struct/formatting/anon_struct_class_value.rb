# `Struct.new(:a)` can be a VALUE that no name holds: printed, passed, or put
# in an array.
#
# Such a class is anonymous: CRuby shows it in the address form. #name
# answers nil, and #to_s and #inspect give the address form.
def anon?(s) = s.start_with?("#<Class:0x") && s.end_with?(">")

p anon?(Struct.new.to_s)
p anon?(Struct.new(:a).to_s)
p anon?(Struct.new(:a).inspect)
p anon?(Data.define(:x).to_s)
p Struct.new(:a).name
p Data.define(:x).name

s = Struct.new(:a, :b)
p anon?(s.to_s)
p s.name
p s.new(1, 2).to_a
p s.members

# a NAMED one keeps its name
S = Struct.new(:a)
p S.to_s
p S.name
p S.new(3).a

D = Data.define(:x)
p D.name
p D.new(x: 4).x

# and the chained forms that already worked
p Struct.new(:a).new(1).a
p Struct.new(:a).members
p [Struct.new(:a), Struct.new(:b)].size
p Struct.new(:a).new(7).class.name
