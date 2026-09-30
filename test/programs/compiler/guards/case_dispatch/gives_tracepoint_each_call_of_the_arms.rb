class A; end
class B; end
class C; end
class D; end
class E; end
class F; end

def kind(y)
  case y
  when A then 1
  when B then 2
  when C then 3
  when D then 4
  when E then 5
  when F then 6
  end
end

3.times { kind(D.new) }
calls = []
tp = TracePoint.new(:c_call) { |t| calls << t.method_id if t.method_id == :=== }
tp.enable
kind(D.new)
kind(1)
tp.disable
p calls.size
