# Hash#compare_by_identity? reports false for an ordinary (value-keyed) hash.
# The test checks only the predicate, on hashes that compare keys by value.
def s(x); x; end
p s({}).compare_by_identity?
p s({ "a" => 1 }).compare_by_identity?
h = {}
p h.compare_by_identity?
