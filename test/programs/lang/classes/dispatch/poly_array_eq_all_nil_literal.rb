# `<mixed array> == [nil, nil, ...]` shape. The RHS literal is an
# array of nils, not of zeros, and == compares elements. As in
# CRuby, `Array.new(N) == [nil] * N` is true.
p Array.new(3) == [nil, nil, nil]   # true
p Array.new(0) == []                # true (empty arrays)
p Array.new(2) == [nil, nil]        # true
p Array.new(3) != [nil, nil, nil]   # false
