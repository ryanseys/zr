# The binding of a Method's Proc is an empty scope whose self is the
# method's receiver.
class K
  def foo(a) = a
end
k = K.new
b = k.method(:foo).to_proc.binding
p b.receiver.equal?(k), b.local_variables, b.eval("self").equal?(k)
b = 1.method(:+).to_proc.binding
p b.receiver, b.local_variables
b.local_variable_set(:z, 3)
p b.local_variable_get(:z), b.local_variables
