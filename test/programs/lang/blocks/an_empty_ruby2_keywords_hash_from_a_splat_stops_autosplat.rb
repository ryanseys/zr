# A flagged Hash at the end of a yield's splat is keywords, also when it
# is empty, so a block that takes keywords spreads no lone Array
# (Bug #19759). A block that takes none still spreads it.
def yielder(splat) = yield(*splat)
p yielder([[:a, :b]]) { |a, b, **| [a, b] }
p yielder([[:a, :b], Hash.ruby2_keywords_hash({})]) { |a, b, **| [a, b] }
p yielder([[:a, :b], Hash.ruby2_keywords_hash({c: 1})]) { |a, b, **| [a, b] }
p yielder([[:a, :b], Hash.ruby2_keywords_hash({})]) { |a, b| [a, b] }
p yielder([[:a, :b], Hash.ruby2_keywords_hash({})]) { |a, b, k: 1| [a, b] }
pr = proc { |a, b, **| [a, b] }
p pr.call(*[[:a, :b], Hash.ruby2_keywords_hash({})])
def y2(*a) = yield(*a, **{})
p y2([:a, :b]) { |a, b, **| [a, b] }
