# An eval of the same string, again and again, behaves as a fresh eval
# each time, and a loop of evals does not grow (test_ast.rb's
# test_memory_leak runs eval("") a million times).
def rss_kb = Integer(IO.popen(["ps", "-o", "rss=", "-p", Process.pid.to_s], &:read).strip)

src = "s = 'abc'; s << 'd'; s"
p 3.times.map { eval(src) }, eval(src).equal?(eval(src))

def with_a(a) = eval("a + 1")
def with_b(b) = eval("defined?(a) ? a : b * 2")
p with_a(1), with_a(10), with_b(5)

x = 1
first = binding
x = 2
p first.eval("x"), binding.eval("y = 3; x + y"), (defined?(y) ? y : :none)

p eval("__ENCODING__"), eval("__ENCODING__".b), eval("[__FILE__, __LINE__]", nil, "f.rb", 7), eval("__LINE__", nil, "f.rb", 9)

def counter = eval("def tick = (@n = (@n || 0) + 1)")
counter
counter
p tick, tick

begin
  2.times { eval("raise 'boom'", nil, "boom.rb", 3) }
rescue => e
  p e.backtrace.first
end

200_000.times { eval("") }
before = rss_kb
500_000.times { eval("") }
p rss_kb - before < 20_000
