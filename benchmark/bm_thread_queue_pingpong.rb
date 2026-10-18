# Two threads pass a number back and forth through two Queues
# Tests: Thread, Queue#push and #pop, a handoff at each pop that waits

ping = Queue.new
pong = Queue.new
n = 100_000
echo = Thread.new do
  n.times { pong << (ping.pop + 1) }
end

sum = 0
n.times do |i|
  ping << i
  sum += pong.pop
end
echo.join
puts sum
