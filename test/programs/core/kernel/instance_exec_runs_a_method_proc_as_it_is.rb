# instance_exec and instance_eval with a Proc made from a Method or a
# Symbol: the Proc runs as it is, and its self does not change.
p 3.instance_exec(4, &5.method(:+))
class Holder
  def foo(a, b = 1) = [self.class, a, b]
end
p Object.new.instance_exec(2, &Holder.new.method(:foo))
p "x".instance_exec("abc", &:upcase)
def meth(arg) = arg
obj = Object.new
p obj.instance_eval(&method(:meth)).equal?(obj)
p Class.new.class_exec(7, &Holder.new.method(:foo))
