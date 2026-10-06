module M; def f = "M>" + super; end
module P; def f = "P>" + super; end
class B; def f = "B"; end
class C < B; include M; end
o = C.new
puts o.f
C.prepend P
puts o.f
class D < B; end
d = D.new
puts d.f
D.include M
puts d.f
D.prepend P
puts d.f
