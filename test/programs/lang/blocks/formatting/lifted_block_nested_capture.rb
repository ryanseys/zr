# A block passed as a real &blk to a class/module method is lifted to a proc.
# When that lifted block captures an enclosing local -- directly, or through a
# further nested block -- and is invoked across a fiber/thread boundary, the
# capture must reach the enclosing frame. The example checks two shapes:
#
#   1. a block passed to a *class/module* method (`M.f { }`) writes to the
#      captured local, and the enclosing frame sees the write.
#   2. a compound assignment adds a value of unknown type (e.g. an element of
#      a mixed array) into a captured Integer accumulator.
#
# All deterministic here: each Thread is joined / Fiber resumed before the
# captured value is read, so there is no concurrent mutation.

# module method: lifted block captures `sum` directly, invoked from a thread
module M
  def self.run(&blk)
    t = Thread.new { blk.call(5) }
    t.join
  end
end
sum = 0
M.run { |i| sum += i }
puts sum                       # 5

# module method: capture through a NESTED block, int elements
total = 0
M.run { |i| [10, 20].each { |x| total += x } }
puts total                     # 30

# module method: nested block folding a POLY element (the coercion fix)
poly = 0
M.run { |i| [i].each { |x| poly += x } }
puts poly                      # 5

# instance method: capture through a nested block combining the arg + element
class C
  def run(&blk)
    t = Thread.new { blk.call(5) }
    t.join
  end
end
inst = 0
C.new.run { |i| [10, 20].each { |x| inst += x + i } }
puts inst                      # 40

# Fiber (not Thread): same lifted-block capture path
module F
  def self.run(&blk)
    fib = Fiber.new { blk.call(4) }
    fib.resume
  end
end
acc = 0
F.run { |i| 2.times { acc += i } }
puts acc                       # 8

# a simple worker-pool: several threads, each joined, accumulate distinct slots
module P
  def self.each_index(n, &blk)
    threads = []
    n.times { |i| threads << Thread.new(i) { |j| blk.call(j) } }
    threads.each(&:join)
  end
end
seen = []
P.each_index(3) { |i| seen << i }
puts seen.sort.inspect         # [0, 1, 2]
