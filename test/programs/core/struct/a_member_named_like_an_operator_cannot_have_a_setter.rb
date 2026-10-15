# Struct.new refuses a member named like an operator other than [] and
# []=, as rb_id_attrset cannot make its setter: NameError, after a named
# struct's constant is set. Data has no setters, so it takes them.
%i[== foo? foo! + [] []= <=> ! != Foo @a $b a_b _x +@ -@ ~ ` === =~ !~ ** << >> & | ^ % / * < > <= >=].each do |m|
  Struct.new(m)
  print m, " ok  "
rescue NameError => e
  p [m, e.class, e.message, e.name]
end
puts
p((Struct.new(:==, :==) rescue $!.message), (Struct.new(:a, :==) rescue $!.message))
p((Struct.new("Opq", :==) rescue $!.message), Struct.const_defined?(:Opq))
p Data.define(:==).members, Data.define(:[]=, :<=).members
p((Data.define(:foo=) rescue $!.message), (Data.define("Bar=") rescue $!.message))
