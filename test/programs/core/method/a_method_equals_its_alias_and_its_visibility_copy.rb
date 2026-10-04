# Method#== holds through an alias or a visibility change in a subclass
# or a singleton class, as CRuby resolves the entry to its original.
c = Class.new { class << self; alias_method :n, :new; end }
p c.method(:new) == c.method(:n), c.method(:n) == Class.instance_method(:new).bind(c)
c2 = Class.new { class << self; private :new; end }
p c2.method(:new) == Class.instance_method(:new).bind(c2)
c3 = Class.new { class << self; alias_method :n, :new; private :new; end }
p c3.method(:new) == c3.method(:n), c3.method(:n) == Class.instance_method(:new).bind(c3), c3.method(:new) == Class.instance_method(:new).bind(c3)
class M; def foo = 1; alias bar foo; end
p M.instance_method(:foo) == M.instance_method(:bar), M.new.method(:foo) == M.new.method(:bar)
class Pa; def foo; end; end
class C1 < Pa; end
class C2 < Pa; end
p Pa.instance_method(:foo) == C1.instance_method(:foo), C1.instance_method(:foo) == C2.instance_method(:foo)
p Pa.instance_method(:foo).hash == C1.instance_method(:foo).hash
class Pa; def bar = 1; end
class C1; def bar = 1; end
p Pa.instance_method(:bar) == C1.instance_method(:bar)
