class A; end
class B; end
class C; end
class D; end
class E; end
class F; end

def kind(x)
  case x
  when A then :a
  when B then :b
  when C then :c
  when D then :d
  when E then :e
  when F then :f
  else :none
  end
end

objs = [A.new, B.new, C.new, D.new, E.new, F.new, 7]
out = []
6.times do |i|
  if i == 2
    class B
      def self.===(o) = o == 7
    end
  end
  if i == 4
    class Module
      alias_method :old_eqq, :===
      def ===(o) = name == "A" ? o.is_a?(E) : old_eqq(o)
    end
  end
  out << objs.map { |o| kind(o) }.join(",")
end
puts out
