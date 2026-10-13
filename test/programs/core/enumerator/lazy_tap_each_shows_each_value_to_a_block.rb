# ruby 4.1's Enumerator::Lazy#tap_each (Feature #21520): the block sees
# each value, packed when the source yields more than one, and the value
# goes on unchanged. The lazy has no size, and a block is required.
seen = []
l = (1..).lazy.tap_each { |x| seen << x }.select(&:even?)
p l.first(3), seen
p [1, 2, 3].lazy.tap_each { |x| }.size, [1, 2, 3].lazy.map { _1 }.tap_each { }.size
p [1, 2, 3].lazy.tap_each { }
p((begin; [1].lazy.tap_each; rescue => e; [e.class, e.message]; end))
got = []
p({ a: 1, b: 2 }.lazy.tap_each { |*x| got << x }.to_a, got)
got = []
def yields2
  return to_enum(:yields2) unless block_given?
  yield 1, 2
  yield 3
end
p yields2.lazy.tap_each { |x| got << x }.to_a, got
got = []
p yields2.lazy.tap_each { |a, b| got << [a, b] }.map { |a, b| [b, a] }.to_a, got
p [1, 2].lazy.tap_each { |x| next 99 }.to_a
p Enumerator::Lazy.instance_method(:tap_each).arity
p [3, 4].lazy.tap_each { }.eager.class, [3, 4].lazy.tap_each { }.with_index.to_a
