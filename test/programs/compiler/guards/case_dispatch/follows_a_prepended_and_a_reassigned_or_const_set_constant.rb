class A; end
class B; end
class C; end
class D; end
class E; end
class F; end

def kind(x)
  case x
  when A then "A"
  when B then "B"
  when C then "C"
  when D then "D"
  when E then "E"
  when F then "F"
  else "else"
  end
end

a = A.new
b = B.new
e = E.new
5.times do |i|
  case i
  when 1
    $VERBOSE = nil
    Object.const_set(:A, B)
  when 2
    Object.const_set(:C, E)
  when 3
    C.singleton_class.prepend(Module.new { def ===(o) = false })
  end
  puts [kind(a), kind(b), kind(e)].join(" ")
end
