# Kernel#inspect shows the instance variables of an object of any type,
# as they were when it started, and writes a name in another encoding
# in the encoding of the text so far.
obj = Object.new
evil = Object.new
evil.define_singleton_method(:inspect) do
  obj.instance_variables.each { |v| obj.remove_instance_variable(v) }
  "evil"
end
obj.instance_variable_set(:@evil, evil)
3.times { |i| obj.instance_variable_set(:"@v#{i}", 0) }
puts obj.inspect.sub(/0x\h+/, "0xADDR")
inspect = Kernel.instance_method(:inspect)
[Class.new(String), Class.new(Array), Class.new(Hash), Struct.new(:x), Class.new(Thread::Mutex)].each do |klass|
  o = klass.new
  o.instance_variable_set(:@a, 1)
  o.instance_variable_set(:@b, 2)
  p inspect.bind_call(o).end_with?(" @a=1, @b=2>")
end
x = eval("class Inspect\u{3042}; def initialize = @\u{3044} = 42; new; end")
x.instance_variable_set("@\u{3046}".encode(Encoding::EUC_JP), 6)
s = x.inspect
p s.encoding, s.sub(/0x\h+/, "0xADDR")
y = Object.new
y.instance_variable_set("@\u{3046}".encode(Encoding::EUC_JP), 6)
y.instance_variable_set(:"@\u{3044}", 1)
s = y.inspect
p s.encoding, s.valid_encoding?, s.b.sub(/0x\h+/, "0xADDR")
