# A method that does not use its block warns when it gets one, once for
# each kind of call: a literal block, a passed Proc, a Method's call. A
# call through send or super does not warn.
$VERBOSE = true
def foo = nil
foo {}
send(:foo) {}
__send__(:foo) {}
b = Proc.new {}
foo(&b)
foo(&b)
foo {}
2.times { foo {} }
method(:foo).call {}

class Parent
  def bar = nil
end

class Child < Parent
  def bar = super
end
Child.new.bar {}

def baz = nil
1.times { baz {} }
