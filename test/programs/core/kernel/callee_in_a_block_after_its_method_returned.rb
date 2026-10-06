# __callee__ and __method__ in a block whose method has returned still
# name the method.
c = Class.new do
  def foo = proc { [__method__, __callee__] }
  def nested = proc { [1].map { [__method__, __callee__] } }
end
p c.new.foo.call
p c.new.nested.call
p proc { __callee__ }.call
