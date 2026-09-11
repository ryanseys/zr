def try = (yield; :ok) rescue [$!.class, $!.message.sub(/0x\h+/, "0x")]

o = Object.new.freeze
p try { def o.x = 1 }
p try { o.singleton_class.define_method(:y) { 1 } }
p o.singleton_class.frozen?

q = Object.new
q.singleton_class
q.freeze
p q.singleton_class.frozen?, try { def q.z = 1 }

class Foo; prepend Comparable; end
Foo.freeze
p try { class Foo; def x; end; end }
p try { Foo.define_method(:z) { } }
p try { Foo.send(:private, :to_s) }
p try { Foo.send(:remove_method, :nope) }

Fz = Class.new.freeze
p Fz.singleton_class.frozen?
p try { Fz::X = 1 }
p try { Fz.const_set(:Y, 1) }
p try { Fz.class_variable_set(:@@a, 1) }
p try { Fz.send(:remove_const, :Nope) }
p try { Fz.remove_class_variable(:@@nope) }

class Fr; @@a = 1; end
Fr.freeze
p try { class Fr; @@a = 2; end }
p Fr.class_variable_get(:@@a)

__END__
[FrozenError, "can't modify frozen Object: #<Object:0x>"]
[FrozenError, "can't modify frozen Object: #<Object:0x>"]
true
true
[FrozenError, "can't modify frozen Object: #<Object:0x>"]
[FrozenError, "can't modify frozen Class: Foo"]
[FrozenError, "can't modify frozen Class: Foo"]
[FrozenError, "can't modify frozen Class: Foo"]
[FrozenError, "can't modify frozen Class: Foo"]
true
[FrozenError, "can't modify frozen Class: Fz"]
[FrozenError, "can't modify frozen Class: Fz"]
[FrozenError, "can't modify frozen Class: Fz"]
[FrozenError, "can't modify frozen Class: Fz"]
[FrozenError, "can't modify frozen Class: Fz"]
[FrozenError, "can't modify frozen Class: Fr"]
1
