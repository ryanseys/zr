# A flip-flop's state is a special variable of the frame, which each
# thread has apart, so two threads that call one Proc each see a range
# of their own.
ff = proc { |n| true if n == 3..n == 5 }
v = 1..9
a = true
th = Thread.new do
  v.select do |i|
    Thread.pass while a
    ff[i].tap { a = true }
  end
end
v1 = v.select do |i|
  Thread.pass until a
  ff[i].tap { a = false }
end
p v1, th.value

# A three-dot flip-flop in a Proc called from a fiber keeps its state too.
ff3 = proc { |n| true if n == 2...n == 2 }
f = Fiber.new { (1..4).map { |i| Fiber.yield(ff3[i]) } }
mine = (1..4).map { |i| [ff3[i], f.resume] }
p mine
