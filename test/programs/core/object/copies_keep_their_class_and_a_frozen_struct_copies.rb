# A copy of an instance of a Module subclass is of that subclass, and a
# frozen Struct whose initialize set no values copies.
tc = Class.new(Module)
o = tc.new
o.instance_variable_set(:@x, 1)
p o.dup.class == tc, o.clone.instance_variable_get(:@x)
st = Struct.new(:a) { def initialize = @t = 1 }
s = st.new
s.instance_variable_set(:@foo, 42)
s.freeze
s.object_id
d = s.dup
c = s.clone
p [d.frozen?, d.instance_variable_get(:@foo), d.a]
p [c.frozen?, c.instance_variable_get(:@foo), c.a]
