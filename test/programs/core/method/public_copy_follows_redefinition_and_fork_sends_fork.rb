class ParentPrivateMethodRedef
  private
  def private_method_redefined = :before_redefinition
end
class ChildPrivateMethodMadePublic < ParentPrivateMethodRedef
  public :private_method_redefined
end
class ParentPrivateMethodRedef
  def private_method_redefined = :after_redefinition
end
p ChildPrivateMethodMadePublic.new.private_method_redefined
p ChildPrivateMethodMadePublic.public_method_defined?(:private_method_redefined)
p ParentPrivateMethodRedef.new.private_method_redefined
class A; def m = :a; end
class B < A; alias_method :n, :m; end
class A; def m = :a2; end
p B.new.n
def Process._fork = 42
p Process.fork {}
