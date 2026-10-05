# A splat or a multiple assignment whose to_a or to_ary gives no Array
# names both classes, and Marshal refuses a cause that leads back to its
# exception (test_exception.rb).
def try
  yield
rescue Exception => e
  p [e.class, e.message[0, 120]]
end
class Ex; end
a = Ex.new
def x(a) = nil
def a.to_a = 1
try { x(*a) }
try { Marshal.load("\x04\bo:\x11RuntimeError\b:\tmesgI\"\berr\x06:\x06ET:\abt[\x00:\ncause@\x05") }
c = eval("Module.new do break class C\u{4032}; self; end; end")
o = c.new
try { ""[o] }
c.class_eval { def to_a; self; end }
try { [*o] }
obj = eval("class C\u{1f5ff}; self; end").new
try { Class.new { include obj } }
try { Warning.instance_method(:warn).owner }
p Warning.instance_methods(false).sort, Warning.singleton_class.include?(Warning)
b = Ex.new
def b.to_ary = 2
try { m, n = b }
inner = RuntimeError.new("inner")
outer = begin; begin; raise inner; rescue; raise "outer"; end; rescue => e; e; end
copy = Marshal.load(Marshal.dump(outer))
p [copy.message, copy.cause.message, copy.cause.cause]
