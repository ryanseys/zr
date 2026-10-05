module M
  def foo_super = [:m, super]
end
class Parent
  def foo_super = :parent
end
class Child < Parent; end
p M.instance_method(:foo_super).bind_call(Child.new)
p M.instance_method(:foo_super).bind(Child.new).call
class Both < Parent
  include M
end
p M.instance_method(:foo_super).bind_call(Both.new)
