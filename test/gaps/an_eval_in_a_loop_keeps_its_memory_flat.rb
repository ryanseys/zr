# The same string, evaluated again and again, keeps the memory of the
# process flat in CRuby (test_method.rb, test_kwarg_eval_memory_leak).
# zr reuses the machine code of the first compile, but each eval still
# keeps about 0.7 KB, so 20,000 evals grow the process by about 13 MB.
def rss_kb = `ps -o rss= -p #{$$}`.to_i

obj = Object.new
def obj.test(**kwargs) = nil

2_000.times { eval("obj.test(foo: 123)") }
before = rss_kb
20_000.times { eval("obj.test(foo: 123)") }
p rss_kb - before < 4_096
