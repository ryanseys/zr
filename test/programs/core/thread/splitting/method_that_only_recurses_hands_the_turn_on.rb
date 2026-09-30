# A thread that only recurses has no loop, so no back edge of compiled
# Ruby and no kernel iterator: the poll at each method's entry is where
# it hands the turn on. The worker's five steps land before the burner
# is done, as they do under ruby's timer thread.

def burn(depth) = depth.zero? ? 1 : burn(depth - 1) + burn(depth - 1)

steps = []
burner = Thread.new { burn(25); steps << :done }
worker = Thread.new { 5.times { steps << :step; sleep 0.01 } }
worker.join
burner.join
p steps

