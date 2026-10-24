# A thread killed before its first turn can be collected at once: its
# OS thread, which waits for that turn, is done with the thread's state
# before the kill returns. 200 new threads at a time make some OS
# threads slow to wake.
50.times do
  Array.new(200) { Thread.new { sleep } }.each(&:kill)
  GC.start
end
p :ok
