# Hash#each_with_object — iterates k,v pairs and threads `memo`
# through the block. The destructured form `|(k,v), memo|` binds the
# pair's two elements. In the flat 3-param shape `|k, v, memo|`, k gets
# the pair, v gets the memo, and memo is nil.

h = {a: 1, b: 2, c: 3}
result = h.each_with_object([]) { |(k,v), memo| memo << v * 10 }
puts result.inspect

# Flat 3-param form
result2 = h.each_with_object([]) { |k, v, memo| memo << v * 100 }
puts result2.inspect
