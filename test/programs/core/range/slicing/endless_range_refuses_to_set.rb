# Range#to_set is Range's own row: an endless range raises before
# Enumerable's walk would run forever.

p (1..3).to_set, (1...3).to_set, ("a".."c").to_set
begin
  (1..).to_set
rescue RangeError => e
  p e
end
p Range.instance_method(:to_set).owner, Range.instance_method(:to_set).arity

