# An escaping closure capturing the param of an INLINED `.times` block.
# The `.times` body shares the enclosing scope, so the param is
# cell-wrapped per iteration -- fresh each turn, matching Ruby -- and the
# nested closure shares that cell, exactly like a real block param.
# a=1: {1}, {1+0}, {1+1}; a=2: {2}, {2+0}, {2+1}

store = []
[1, 2].each do |a|
  store << ->() { a }
  2.times do |b|
    store << ->() { a + b }
  end
end
store.each { |p| puts p.call }
