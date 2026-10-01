# Anonymous `*`, `**`, `&` and `...` forward into `super(...)` with
# explicit arguments, into calls that take a block, and from inside a
# block body (the block has no anonymous parameters of its own).

class Base
  def m(a = :a, *r, k: :k, **kw, &b)
    [a, r, k, kw, b ? b.call : :noblock]
  end
end

class Splats < Base
  def m(*, **) = super(*, **)
end

class SplatsAndBlock < Base
  def m(*, **, &) = super(*, **, &)
end

class Dots < Base
  def m(...) = super(...)
end

class Leading < Base
  def m(x, *) = super(x, :extra, *)
end

p Splats.new.m
p Splats.new.m(1, 2, k: 3, z: 4)
# `super` with explicit arguments and no `&` still passes the block on.
p Splats.new.m(1) { :implicit }
p SplatsAndBlock.new.m(1, k: 2) { :blk }
p SplatsAndBlock.new.m
p Dots.new.m(1, 2, z: 3) { :dots }
p Dots.new.m
p Leading.new.m(7)
p Leading.new.m(7, 8, k: 9)

# A `&` forwards the block into a call that takes a block, and `*`
# fills its positional arguments.
def each_twice(*, &) = [*].each_with_index.map(&)
p each_twice(:a, :b) { |x, i| "#{i}:#{x}" }

def fold(*, &) = [*].inject(&)
p fold(1, 2, 3) { |s, x| s + x }

# Without a block, the bare `&` forwards nil and the callee sees no block.
def has_block(&b) = !b.nil?
def ask(&) = has_block(&)
p ask, ask {}

# Anonymous parameters used from inside a block of the method body.
def show(*a, **k) = [a, k]
def in_block(*, **) = [1, 2].map { |i| show(i, *, **) }
p in_block
p in_block(:x, y: 3)

def dots_in_block(...) = [0].map { show(...) }
p dots_in_block(5, z: 6)
