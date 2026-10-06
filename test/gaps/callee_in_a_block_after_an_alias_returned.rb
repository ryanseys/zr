# __callee__ in a block whose method returned is the name of the call,
# which the method's environment keeps. zr has only the def's name then.
c = Class.new do
  def foo = proc { __callee__ }
  alias alias_foo foo
end
p c.new.alias_foo.call
