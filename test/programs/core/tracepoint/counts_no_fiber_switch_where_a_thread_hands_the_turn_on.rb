# A thread here runs on a fiber of its own, and the scheduler hands
# the turn on with the switch a fiber uses. CRuby's threads are the
# operating system's and fire nothing as they take turns, and
# neither does this: the fiber that heads a thread is that thread,
# not a fiber of the program's.
count = 0
tp = TracePoint.new(:fiber_switch) { count += 1 }
tp.enable(target_thread: nil)
3.times.map { Thread.new { 10.times { Thread.pass } } }.each(&:join)
tp.disable
p count
