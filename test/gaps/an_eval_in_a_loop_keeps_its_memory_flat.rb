# The same string, evaluated again and again, keeps the memory of the
# process flat in CRuby (test_method.rb, test_kwarg_eval_memory_leak).
# zr reuses the machine code of the first compile, and its live objects
# stay flat, but the first eval loads the compiler and grows the heap.
# Allocation then touches the heap's free pages one by one until all are
# resident (about 8,000 evals here), and zr gives no empty page back to
# the system after a sweep, so the process grows by about 13 MB first.
def rss_kb = `ps -o rss= -p #{$$}`.to_i

obj = Object.new
def obj.test(**kwargs) = nil

2_000.times { eval("obj.test(foo: 123)") }
before = rss_kb
20_000.times { eval("obj.test(foo: 123)") }
p rss_kb - before < 4_096
