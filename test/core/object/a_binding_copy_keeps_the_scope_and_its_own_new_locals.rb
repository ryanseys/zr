# Binding#dup and #clone name the same scope, but a local set on the copy
# is its own, as binding_copy makes it. A Binding inspects as Kernel does.

x = 1
b = binding
c = b.dup
d = b.clone
c.local_variable_set(:x, 2)
p x, b.local_variable_get(:x), d.local_variable_get(:x)
c.local_variable_set(:y, 3)
p b.local_variable_defined?(:y), c.local_variable_defined?(:y), d.local_variable_defined?(:y)
p b.inspect.match?(/\A#<Binding:0x\h{16}>\z/), b.to_s == b.inspect
b.freeze
p b.clone.frozen?, b.dup.frozen?
p Binding.constants, Binding.instance_method(:dup).owner, Binding.instance_method(:clone).arity

__END__
2
2
2
false
true
false
true
true
true
false
[]
Binding
0
