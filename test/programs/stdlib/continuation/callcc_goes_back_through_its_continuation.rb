# callcc returns the continuation, and a call goes back through it: from
# later in the same frame, after the method that captured it returned,
# and in the middle of a block. The warning callcc gives names the
# extension's own file, so stderr goes nowhere.
$stderr.reopen(IO::NULL)
require "continuation"
p defined?(callcc), Continuation
x = 0
c = callcc { |k| k }
x += 1
p [x, c.class]
c.call(:done) if c.is_a?(Continuation)
p c
def gen
  r = callcc { |k| return [k, 1] }
  [nil, r]
end
k, v = gen
p v
k.call(5) if k
arr = []
cont = nil
[1, 2, 3].each do |i|
  callcc { |cc| cont = cc } if i == 2
  arr << i
end
cont.call if arr.size < 5
p arr
p callcc { |cc| cc.call(1, 2) }

