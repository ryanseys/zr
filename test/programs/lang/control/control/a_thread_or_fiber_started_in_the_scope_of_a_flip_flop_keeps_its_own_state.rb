# A flip-flop keeps its state in the scope it is written in. A thread or
# a fiber whose block was written in that scope keeps a state of its own,
# from the start; any other thread shares the scope's state.
def in_threads
  ff = proc { |i| true if (i == 2)..(i == 3) }
  p((1..4).map { |i| Fiber.new { ff[i] }.resume })
  p((1..4).map { |i| Thread.new { ff[i] }.value })
  p((1..4).map { |i| ff[i] })
  p((1..4).map { |i| Thread.new { [1].map { ff[i] }[0] }.value })
  p(Thread.new { (1..4).map { |i| ff[i] } }.value)
  inner = proc { |i| true if (i == 2)...(i == 3) }
  p((1..4).map { |i| Thread.new { Thread.new { inner[i] }.value }.value })
  p((1..4).map { |i| Thread.new { inner[i]; inner[i + 1] }.value })
end
in_threads

# The proc's scope is not the one the thread's block was written in.
def threads_for(pr) = (1..4).map { |i| Thread.new { pr[i] }.value }
def flip_flop = proc { |i| true if (i == 2)..(i == 3) }
p threads_for(flip_flop)

top = proc { |i| true if (i == 2)..(i == 3) }
p((1..4).map { |i| Thread.new { top[i] }.value })
p((1..4).map { |i| top[i] })

# Two threads that step through one flip-flop in turns each see its own
# state, as CRuby's test_flip checks.
def in_turns
  ff = proc { |n| true if (n == 3)..(n == 5) }
  turn = true
  th = Thread.new do
    (1..9).select do |i|
      Thread.pass while turn
      ff[i].tap { turn = true }
    end
  end
  mine = (1..9).select do |i|
    Thread.pass until turn
    ff[i].tap { turn = false }
  end
  p [mine, th.value]
end
in_turns
