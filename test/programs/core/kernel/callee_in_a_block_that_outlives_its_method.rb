# __callee__ in a block names the method as the call named it, also when
# the block runs after the method returned; __method__ names the def.
c = Class.new { def foo; proc { __callee__ }; end; alias alias_foo foo }
p c.new.alias_foo.call, c.new.foo.call
d = Class.new { def foo = [1].map { __callee__ }.first; alias bar foo }
p d.new.bar, d.new.foo
e = Class.new { def foo = lambda { [__method__, __callee__] }; alias baz foo }
p e.new.baz.call
f = Class.new { def foo = proc { proc { __callee__ } }; alias qux foo }
p f.new.qux.call.call
# Two calls by two names keep one name each.
g = Class.new { def one = proc { __callee__ }; alias two one }
first, second = g.new.one, g.new.two
p [second.call, first.call]
# A block with locals of its own, and one that a later block reads.
h = Class.new do
  def make
    x = 1
    proc { y = x; [__callee__, y] }
  end
  alias remake make
end
p h.new.remake.call
# define_method blocks keep their own names.
k = Class.new { define_method(:dm) { proc { __callee__ } }; alias dm2 dm }
p k.new.dm2.call
# At the top level, a block has none.
p proc { __callee__ }.call
