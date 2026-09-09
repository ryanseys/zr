class A; private def f = 1; protected def g = 2; end
class B < A; def h(o) = o.g; def i = self.f; def j(o) = o.f; end
begin; A.new.f; rescue NoMethodError => e; puts e.message; end
begin; A.new.g; rescue NoMethodError => e; puts e.message; end
p B.new.h(B.new), B.new.i
begin; B.new.j(A.new); rescue NoMethodError => e; puts e.message; end
module M; module_function; def mf = :mf; end
p M.mf
class C; def x = 1; private :x; public; def y = 2; end
p C.private_instance_methods(false), C.public_instance_methods(false)
begin; C.new.x; rescue NoMethodError => e; puts e.message; end
p C.new.send(:x), C.new.respond_to?(:x), C.new.respond_to?(:x, true)
begin; C.new.public_send(:x); rescue NoMethodError => e; puts e.message; end
class D
  private
  def a = 1
  public
  def b = a
  private :b
  def c = b
end
p D.new.c, D.instance_methods(false), D.private_instance_methods(false)
class E; def initialize; end; end
begin; E.new.initialize; rescue NoMethodError => e; puts e.message; end
begin; A.f; rescue NoMethodError => e; puts e.message; end
begin; M.nope; rescue NoMethodError => e; puts e.message; end
p A.new.respond_to?(:f), A.new.respond_to?(:g), 5.respond_to?("+")
