class A; end
class B < A; end
c = B.clone
p A.subclasses.size, A.subclasses.include?(c), A.subclasses.include?(B)
p c.superclass
