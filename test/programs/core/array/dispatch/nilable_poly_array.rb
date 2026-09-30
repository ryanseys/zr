# A method whose value is a mixed-element array or nil still gives an array, so
# array methods work on the result.
def gen(x)
  if x > 0
    [:begin, :a, :b]
  end          # implicit nil branch makes the return nilable
end

g = gen(5)
p g                          # [:begin, :a, :b]
p g.reject { _1 == :begin }  # [:a, :b]
p g.map { |e| e.to_s }       # ["begin", "a", "b"]
p g.join("-")                # "begin-a-b"
