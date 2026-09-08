def opt(a, b = 10, c = b + 1)
  [a, b, c]
end

def rest(a, *r)
  [a, r]
end

def post(a, *m, z)
  [a, m, z]
end

def kw(a:, b: 5)
  [a, b]
end

def kwrest(a, **o)
  [a, o]
end

def blockp(a, &b)
  b.nil? ? :none : b.call(a)
end

def everything(a, b = 2, *m, z, k:, j: 9, **o, &blk)
  [a, b, m, z, k, j, o, blk.nil?]
end

class Box
  def initialize(value, label: "box")
    @value = value
    @label = label
  end

  def to_s
    "#{@label}=#{@value}"
  end

  def with(*extra, **opts)
    [@value, extra, opts]
  end

  def each_pair
    @value.each { |v| yield(v, @label) }
  end
end

p opt(1)
p opt(1, 2)
p opt(1, 2, 3)
p rest(1)
p rest(1, 2, 3)
p post(1, 9)
p post(1, 2, 3, 9)
p kw(a: 1)
p kw(a: 1, b: 2)
p kwrest(1)
p kwrest(1, x: 2, y: 3)
p blockp(4)
p blockp(4) { |n| n * 2 }
p everything(1, 2, 3, 4, 5, k: 6)
p everything(1, 2, 3, k: 6, j: 7, extra: 8) { }

p method(:opt).parameters
p method(:everything).parameters
p method(:opt).arity
p method(:everything).arity

p [1, 2, 3].map { |x, y = 10| [x, y] }
p [[1, 2], [3, 4]].map { |a, *r| [a, r] }

double = ->(x) { x * 2 }
p double.call(5)
p double.(6)
p double[7]
p double.lambda?
p double.arity
p double.parameters
p [1, 2, 3].map(&double)
p ["a", "b"].map(&:upcase)

add = ->(a, b = 1) { a + b }
p add.call(2)
p add.call(2, 3)
p add.arity

# A `->` closes over a name the same way a block does: one shared cell,
# not a copy taken where the lambda was written.
tally = 0
count = ->(n) { tally += n }
count.call(3)
count.call(4)
p tally

pr = proc { |a, b = 1| [a, b] }
p pr.call(7)
p pr.arity
p lambda { |a, b = 1| }.arity
p proc { |a, *r| }.arity

puts Box.new(1)
puts Box.new(2, label: "two")
p Box.new(3).with(4, 5, a: 6)
Box.new([7, 8], label: "n").each_pair { |v, l| puts "#{l}:#{v}" }

# `_1`/`_2` and `it` are that many required positionals, under the names
# ruby gives them, so they answer a block's ordinary arity.
p [1, 2].map { _1 * 2 }
p({ "a" => 1 }.map { _1 + _2.to_s })
p [1, 2].map { it * 2 }
p proc { _1 + _2 }.arity
p proc { it }.arity
__END__
[1, 10, 11]
[1, 2, 3]
[1, 2, 3]
[1, []]
[1, [2, 3]]
[1, [], 9]
[1, [2, 3], 9]
[1, 5]
[1, 2]
[1, {}]
[1, {x: 2, y: 3}]
:none
8
[1, 2, [3, 4], 5, 6, 9, {}, true]
[1, 2, [], 3, 6, 7, {extra: 8}, false]
[[:req, :a], [:opt, :b], [:opt, :c]]
[[:req, :a], [:opt, :b], [:rest, :m], [:req, :z], [:keyreq, :k], [:key, :j], [:keyrest, :o], [:block, :blk]]
-2
-4
[[1, 10], [2, 10], [3, 10]]
[[1, [2]], [3, [4]]]
10
12
14
true
1
[[:req, :x]]
[2, 4, 6]
["A", "B"]
3
5
-2
7
[7, 1]
1
-2
-2
box=1
two=2
[3, [4, 5], {a: 6}]
n:7
n:8
[2, 4]
["a1"]
[2, 4]
2
1
