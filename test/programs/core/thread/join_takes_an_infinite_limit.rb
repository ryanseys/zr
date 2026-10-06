# Thread#join with an infinite limit waits for the thread. A limit of
# zero or less, negative infinity included, does not wait.
t = Thread.new { sleep 0.05; :done }
p t.join(Float::INFINITY).equal?(t)
p t.value

slow = Thread.new { sleep 0.2 }
p slow.join(-Float::INFINITY)
p slow.join(0)
p slow.join(-1)
p slow.join(Float::INFINITY).equal?(slow)
