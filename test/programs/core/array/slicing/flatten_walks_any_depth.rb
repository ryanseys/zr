# flatten walks with a stack of its own, as CRuby's does, so an Array
# nested far deeper than any call stack flattens; a level stops the walk
# where it says; an element answering to_ary is asked once; a recursive
# Array raises only when the walk would enter it again.
def t = yield rescue [$!.class, $!.message]

deep = [0]
100_000.times { |i| deep = [deep, i + 1] }
p t { deep.flatten.size }, t { deep.flatten.first(3) }, t { deep.flatten(1).size }, t { deep.flatten(2).size }

list = Class.new { def to_ary = [:x, [:y]] }
p t { [1, list.new, [2, [3]]].flatten }, t { [1, list.new].flatten(1) }, t { [[1, [2, [3, [4]]]]].flatten(2) }
p t { [1, [2]].flatten(0) }, t { [1, [2]].flatten(-1) }, t { [1, [2]].flatten(nil) }, t { [1, [2]].flatten(1.9) }

a = [1]
a << a
p t { a.flatten }, t { a.flatten(1).size }, t { [a].flatten(1).size }, t { [[a]].flatten(2).size }

b = [1, 2]
p t { b.flatten! }, t { [1, [2]].flatten! }, t { [1, [2]].flatten!(0) }, t { [[1]].freeze.flatten! }, t { [1].freeze.flatten! }
c = [1, [2]]
p t { c.flatten.equal?(c) }, t { [1, 2].flatten.equal?([1, 2]) }

