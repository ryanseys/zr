# The binding of a Method's Proc is where the method is defined, and it
# has the method's receiver, its constants, and no locals until one is
# set.
def source_location_test(a = 1)
  a
end
b = method(:source_location_test).to_proc.binding
file, line = b.source_location
p [File.basename(file), line, b.receiver.equal?(self), b.local_variables]
p method(:puts).to_proc.binding.source_location
class C
  D = "Const_D"
  def foo = nil
end
b = C.new.method(:foo).to_proc.binding
p b.local_variables, b.eval("D")
p((b.local_variable_get(:foo) rescue $!.class))
p b.local_variable_set(:foo, 123), b.local_variable_set(:bar, 456), b.local_variables.sort
