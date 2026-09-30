# A small def of the file -- required positionals, a body of reads of
# self's ivars, of readers and type questions of its arguments, fixnum
# arithmetic, branches and a return -- runs as a copy at each site
# whose cell holds it (Zr::Lower::Function::Inline): no frame, no call. Every
# guard the copy makes fails to the ordinary call, which runs the def
# from its start, so a redefinition, an operator past the fixnums, a
# receiver of another kind, a reader that is not one, and a missing
# method all answer as the call does, with the def's own frame in a
# backtrace.
class Node
  attr_accessor :left, :right, :red, :key
  def initialize(key) = (@key = key; @red = 1)
end
def is_red(node)
  return 0 if node.nil?
  node.red
end
def leaf?(n) = n.left.nil? && n.right.nil?
def add(a, b) = a + b
def lt(a, b) = a < b
def same(a, b) = a == b
def diff(a, b) = a != b
def kind(x) = x.is_a?(Node) ? :node : :other
def arm(x) = Node === x
def size_of(x) = x.size
def missing(x) = x.nope
def neg(x) = !x
class Node
  def depth = @depth
  def total = @key + (@left.nil? ? 0 : @left.total)
end
n = Node.new(5)
n.left = Node.new(3)
p [is_red(n), is_red(nil), is_red(n.left), leaf?(n), leaf?(n.left)]
p [add(1, 2), add(2**62, 2**62), add(1.5, 2), add("a", "b"), add([1], [2])]
p [lt(1, 2), lt(2, 1), lt(1.5, 2), (lt("a", 1) rescue $!.class), lt("a", "b")]
p [same(n, n), same(n, n.left), diff(n, n.left), same(1, 1), same(1, 1.0), diff(1, 2), same("a", "a"), diff("a", "a"), same(:a, :a)]
p [kind(n), kind(1), kind(nil), arm(n), arm(1), arm(nil)]
p [size_of([1, 2]), size_of("abc"), size_of({a: 1}), (size_of(1) rescue $!.class)]
p [neg(nil), neg(false), neg(true), neg(1), neg(n)]
p [n.depth, n.total, n.left.total]
p (missing(n) rescue [$!.class, $!.backtrace.first(2).map { |l| l[/:\d+:in.*/] }])
i = 0
s = 0
while i < 200_000
  s = add(s, is_red(n)) + (lt(i, 5) ? 1 : 0)
  i += 1
end
p s
# The copy's own guesses: an object of another shape, a frozen
# receiver, a class as the receiver.
class Other; attr_reader :red; def initialize = @red = :other; end
p [is_red(Other.new), is_red(Node.new(1).freeze), (is_red(Node) rescue $!.class)]
class Node; def red = :redefined; end
p is_red(n)
def is_red(node) = :again
p is_red(n)
class Node; def nil? = :never; end
p [leaf?(n.left), is_red(n)]
class Integer; def +(o) = :plus; end
p add(1, 2)
class Node; def ==(o) = :eq; end
p [same(n, n), diff(n, n)]
class Node; def is_a?(k) = :is; end
p kind(n)
def Node.===(o) = :eqq
p arm(n)
