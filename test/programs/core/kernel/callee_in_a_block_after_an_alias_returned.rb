# __callee__ in a block whose method returned is the name of the call,
# which the method's environment keeps; __method__ stays the def's name.
c = Class.new do
  def foo = proc { [__callee__, __method__] }
  alias alias_foo foo
  alias_method :other_foo, :foo
end
o = c.new
p o.alias_foo.call
p o.other_foo.call
p o.foo.call
