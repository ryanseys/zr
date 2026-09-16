# Enumerable's methods read one value per element of `each`: the value
# yielded, or the Array of them when each yields several, or nil for
# none. Control flow in the caller's block, an each that keeps or
# passes its block on, and a yield of two values all answer as ruby's.
class Yielder
  include Enumerable
  def initialize(rows) = @rows = rows
  def each
    return to_enum(:each) unless block_given?
    @rows.each { |row| row.nil? ? yield : yield(*row) }
    self
  end
end
y = Yielder.new([[1], [2, 3], nil, [[4, 5]], [6]])
p y.to_a, y.select { |v| v }, y.reject { |v| v.is_a?(Array) }, y.find { |v| v == 6 }, y.count, y.include?(nil)
p y.min_by { |v| v.to_s }, y.sort_by { |v| v.to_s }, y.group_by { |v| v.class }, y.each_slice(2).to_a, y.take_while { |v| v }
p y.each_with_index.to_a, y.each_with_object([]) { |v, acc| acc << v }, y.inject { |a, b| [a, b] }, y.first(2), y.to_set.size
p y.each_entry.to_a, y.zip(y), y.partition { |v| v.nil? }, y.chunk_while { |a, b| !b.nil? }.to_a, y.tally
r = y.select { |v| break :broke if v == 6; true }
p r
def early(y) = y.each_with_index { |v, i| return [v, i] if i == 2 }
p early(y), y.map { |v| next :skipped if v.nil?; v }
class Keeper
  include Enumerable
  def each(&b)
    @kept = b
    [1, 2, 3].each(&b)
  end
  def again = [4].each(&@kept)
end
k = Keeper.new
p k.to_a, k.again, k.sort, k.select(&:even?), k.lazy.map { |v| v * 2 }.first(2)
h = { a: 1, b: 2 }
p h.select { |k, v| v > 1 }, h.map { |k, v| [k, v] }, h.min_by { |k, v| -v }, h.each_slice(1).to_a, h.find { |pair| pair[1] == 2 }
p (1..4).each_cons(2).to_a, (1..4).select(&:even?), (1..3).inject(:+), [[1, 2], [3, 4]].each_with_index.map { |(a, b), i| a + b + i }


__END__
[1, [2, 3], nil, [4, 5], 6]
[1, [2, 3], [4, 5], 6]
[1, nil, 6]
6
5
true
nil
[nil, 1, 6, [2, 3], [4, 5]]
{Integer => [1, 6], Array => [[2, 3], [4, 5]], NilClass => [nil]}
[[1, [2, 3]], [nil, [4, 5]], [6]]
[1, [2, 3]]
[[1, 0], [[2, 3], 1], [nil, 2], [[4, 5], 3], [6, 4]]
[1, [2, 3], nil, [4, 5], 6]
[[[[1, [2, 3]], nil], [4, 5]], 6]
[1, [2, 3]]
5
[1, [2, 3], nil, [4, 5], 6]
[[1, 1], [[2, 3], [2, 3]], [nil, nil], [[4, 5], [4, 5]], [6, 6]]
[[nil], [1, [2, 3], [4, 5], 6]]
[[1, [2, 3]], [nil, [4, 5], 6]]
{1 => 1, [2, 3] => 1, nil => 1, [4, 5] => 1, 6 => 1}
:broke
[nil, 2]
[1, 2, :skipped, [4, 5], 6]
[1, 2, 3, 4]
[4]
[1, 2, 3]
[2]
[2, 4]
{b: 2}
[[:a, 1], [:b, 2]]
[:b, 2]
[[[:a, 1]], [[:b, 2]]]
[:b, 2]
[[1, 2], [2, 3], [3, 4]]
[2, 4]
6
[3, 8]
