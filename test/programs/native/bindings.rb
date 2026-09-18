# The program carries the compiler and writes its own code.
x = 100
b = binding

p b.class, b.frozen?, b.receiver.equal?(self)
p b.inspect.start_with?("#<Binding:0x"), b.to_s == b.inspect
p b.source_location.first.end_with?("bindings.rb"), b.source_location.last
p b.local_variables
p b.local_variable_get(:x), b.local_variable_defined?(:x), b.local_variable_defined?(:nope)

b.local_variable_set(:x, 5)
p x
x = 7
p b.local_variable_get(:x)
b.eval("x = 42")
p x, b.eval("x + 1")
p eval("x * 2", b)

def in_a_method(n)
  m = n * 2
  binding
end
inner = in_a_method(3)
p inner.local_variables, inner.local_variable_get(:m), inner.eval("n + m")

def with_a_block
  a = 1
  [0].map { |i| binding }.first
end
held = with_a_block
p held.local_variables.include?(:a), held.local_variable_get(:a), held.eval("a + 1")

begin
  b.local_variable_get(:nope)
rescue NameError => e
  p [e.class, e.message.sub(/0x\h+/, "0xADDR")]
end
begin
  b.local_variable_get(1)
rescue TypeError => e
  p [e.class, e.message]
end
begin
  Binding.new
rescue NoMethodError => e
  p [e.class, e.message]
end
begin
  eval("1", 2)
rescue TypeError => e
  p [e.class, e.message]
end

later = 9
p b.local_variable_get(:later)

b.local_variable_set(:added, 7)
p b.local_variable_get(:added)
b.eval("evaled = 3")
p b.local_variables, defined?(added)
p b.eval("evaled + added")

def make_proc
  a = 1
  proc { b = 2; a }
end
pb = make_proc.binding
p pb.class, pb.local_variables, pb.local_variable_get(:a), pb.receiver.class
begin
  :upcase.to_proc.binding
rescue ArgumentError => e
  p [e.class, e.message]
end

p TOPLEVEL_BINDING.class, TOPLEVEL_BINDING.receiver, TOPLEVEL_BINDING.source_location
