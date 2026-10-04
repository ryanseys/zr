# An eval string can forward the method's anonymous *, **, & and ...,
# and runs under the refinements in use where eval or binding is called.
# A using whose value is assigned activates and returns self.
$stderr = $stdout
o = Object.new
def o.foo(a, b, c) = [a, b, c]
def o.bar(*) = eval("foo(*)")
p((o.bar(1, 2, 3) rescue $!))
def o.kfoo(a:, b:) = [a, b]
def o.kbar(**) = eval("kfoo(**)")
p((o.kbar(a: 1, b: 2) rescue $!))
def o.bfoo(&b) = b.call
def o.bbar(&) = eval("bfoo(&)")
p((o.bbar { :blk } rescue $!))
def o.dfoo(a, b:, &blk) = [a, b, blk.call]
def o.dbar(...) = eval("dfoo(...)")
p((o.dbar(1, b: 2) { 3 } rescue $!))
class A; def foo = "foo"; end
refinery = Module.new { refine(A) { def foo = "bar" } }
r = nil
Module.new do
  using refinery
  r = eval "A.new.foo"
end
p r
b = nil
Module.new do
  using refinery
  b = binding
end
p eval("A.new.foo", b)
refinement = Module.new { refine(String) { def to_s = "hello from refinement" } }
result = nil
mod = Module.new do
  result = using refinement
  p "1".to_s
end
p result.equal?(mod)
rec = []
Module.new do
  Class.new do
    rec << "1".to_s
    using refinement
    rec << "1".to_s
  end
  rec << "1".to_s
end
p rec
r = []
klass = Class.new do
  using refinement
  r << "1".to_s
end
klass.class_eval { r << "1".to_s }
p r
Module.new do
  if false
    using refinement
  end
  p "1".to_s
end
