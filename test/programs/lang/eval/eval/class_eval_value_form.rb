# The value forms of class_eval / class_exec / module_eval / module_exec: the
# block runs with self set to the receiver, its value is the call's value,
# and class_exec's args bind the block params. A body of only `def`s reopens
# the class.
class C; end
module M; end
r = C.class_eval { 40 + 2 }
p r
p(C.class_exec(5) { |n| n * 2 })
r2 = C.class_eval do
  x = 10
  y = x * 2
  "#{self}/#{y}"
end
p r2
p(M.module_eval { 7 })
p(M.module_exec(3, 4) { |a, b| a + b })
base = 100
p(C.class_exec(5) { |n| base + n })
class D; end
D.class_eval do
  def hi; "hi"; end
end
p D.new.hi
