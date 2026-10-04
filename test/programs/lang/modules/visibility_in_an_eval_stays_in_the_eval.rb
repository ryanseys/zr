# private or module_function with no names inside an eval string sets the
# eval's own scope, not the class body around it, and public or private
# with an ancestor's method at its visibility makes no entry here.
$stderr = $stdout
class A
  eval "private"
  def foo = 1
end
p A.public_method_defined?(:foo)
module M
  eval "module_function"
  def bar = 2
end
p M.respond_to?(:bar), M.public_method_defined?(:bar)
class Par; def m = 1; end
class Chi < Par; public :m; end
p Chi.instance_methods(false)
class Chi2 < Par; private :m; end
p Chi2.private_instance_methods(false)
p [[1, 2], 3].each_slice(1).to_a.flat_map { _1 }
o = Object.new; def o.to_ary = [9, 8]
n = Object.new; def n.to_ary = nil
p [o, n, 5].flat_map { _1 }.size
p (1..6).slice_before(3..4).to_a, [1,2,3].slice_before(1).to_a, [1, true, 2].slice_before(true).to_a
a = [1]; a << a; b = [1]; b << b
p a.hash == b.hash
