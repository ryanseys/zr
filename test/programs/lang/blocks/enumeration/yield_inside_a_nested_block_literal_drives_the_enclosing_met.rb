# `yield`/`block_given?` lexically inside a block literal refers to the
# ENCLOSING METHOD's own block (a block has no implicit block of its
# own). The inner block yields to the block of the method call.
# Oracle-verified.

class Foo
  def helper(x)
    yield x
  end
  def bar
    helper(1) { yield }
  end
  def baz
    [1, 2].map { |v| yield v }
  end
  def has_block
    [1].each { return block_given? }
  end
end
p(Foo.new.bar { "from-outer" })
p(Foo.new.baz { |v| v * 10 })
p Foo.new.has_block
p(Foo.new.has_block {})
