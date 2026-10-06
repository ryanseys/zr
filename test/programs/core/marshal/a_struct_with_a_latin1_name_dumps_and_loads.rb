# A Struct class and member named in ISO-8859-1, and a class whose ivar
# is named in it, dump and load, also when a value holds the object
# itself.
latin = Encoding::ISO_8859_1
klass = Struct.new("r\xe9sum\xe9".force_encoding(latin).intern)
Object.const_set("R\xe9sum\xe9".force_encoding(latin), klass)
a = klass.new(10)
b = Marshal.load(Marshal.dump(a))
p [b == a, b.class.equal?(klass)]
a.__send__("#{klass.members[0]}=", a)
b = Marshal.load(Marshal.dump(a))
p b.to_a[0].equal?(b)

holder = Class.new do
  attr_accessor "r\xe9sum\xe9".force_encoding(latin)
  eval("def initialize(x) @r\xe9sum\xe9 = x; end".force_encoding(latin))
end
Object.const_set("R\xe9sum\xe92".force_encoding(latin), holder)
c = Marshal.load(Marshal.dump(holder.new(10)))
p [c.class.equal?(holder), c.instance_variables.map { _1.encoding }, c.instance_variable_get(c.instance_variables[0])]
