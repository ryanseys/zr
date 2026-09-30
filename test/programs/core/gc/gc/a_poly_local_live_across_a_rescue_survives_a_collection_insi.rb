# A local that can hold an A or a B is live across a rescue, and a
# collection runs inside the begin body. The local keeps its object.
class A; def v=(x); @v = x; end; def v; @v; end; end
class B; def v=(x); @v = x; end; def v; @v; end; end
def pick(n); n == 0 ? A.new : B.new; end
def churn(k); s = ""; i = 0; while i < k; s = s + i.to_s + ","; i += 1; end; s.length; end
obj = pick(1)
obj.v = "keep_" + 9.to_s
begin
  GC.start
  churn(8000)
  raise "boom"
rescue => e
  GC.start
end
puts obj.v
