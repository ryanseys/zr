# A local read from a mixed array holds an Integer. A collection
# must keep its value.
class A; def v; 1; end; end
def churn(k); s = ""; i = 0; while i < k; s = s + i.to_s + ","; i += 1; end; s.length; end
arr = [A.new, 100 + 1]
x = arr[1]
GC.start
churn(8000)
GC.start
p x
