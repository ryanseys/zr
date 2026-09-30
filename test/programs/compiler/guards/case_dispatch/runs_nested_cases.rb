class A; end
class B; end
class C; end
class D; end
class E; end
class F; end

def inner(y)
  case y
  when A then 1
  when B then 2
  when C then 3
  when D then 4
  when E then 5
  when F then 6
  end
end

def outer(x, y)
  case x
  when A then [:a, inner(y)]
  when B then [:b, inner(y)]
  when C then [:c, inner(y)]
  when D then [:d, case y when A, B, C, D, E, F then :any end]
  when E then [:e, inner(y)]
  when F then [:f, inner(y)]
  else [:none, inner(y)]
  end
end

objs = [A.new, B.new, C.new, D.new, E.new, F.new, 0]
3.times do
  p objs.map { |x| outer(x, objs[(objs.index(x) + 3) % objs.size]) }
end
