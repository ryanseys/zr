# `C`: a subclass of a value builtin (String/Array) marshals its class
# symbol then the inherited body inline, `I`-wrapped for a string's
# encoding and any user ivars. Round-trips through the subclass.

def wire(x) = Marshal.dump(x).bytes.join(",")
def rt(x) = Marshal.load(Marshal.dump(x))
class MyStr < String; end
class Stack < Array; end
puts wire(MyStr.new("hi"))
s = MyStr.new("hi")
s.instance_variable_set(:@x, 5)
puts wire(s)
puts wire(Stack.new([1, 2]))
r = rt(MyStr.new("hi"))
puts "#{r.class} #{r} #{r.upcase}"
puts rt(s).instance_variable_get(:@x)
st = rt(Stack.new([1, 2]))
puts st.class
p st.to_a
