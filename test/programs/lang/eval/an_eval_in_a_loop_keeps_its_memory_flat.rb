# The same string, evaluated again and again, keeps the memory of the
# process flat, as in CRuby (test_method.rb, test_kwarg_eval_memory_leak).
# The first eval loads the compiler, and the heap that it grows keeps
# free bytes for the live set of the whole heap, not of each size of cell.
def rss_kb = `ps -o rss= -p #{$$}`.to_i

obj = Object.new
def obj.test(**kwargs) = nil

2_000.times { eval("obj.test(foo: 123)") }
before = rss_kb
20_000.times { eval("obj.test(foo: 123)") }
p rss_kb - before < 4_096
