# A raise and then a kill: the exception arrives first, and the kill at
# the thread's next blocking call, though no other thread wants a turn.
log = []

# A thread that waits on a descriptor that is always ready.
r, w = IO.pipe
started = false
t = Thread.new do
  started = true
  begin
    IO.select(nil, [w])
  rescue => e
    log << e.message
    retry
  end while true
ensure
  log << :ensure
end
Thread.pass until started
t.raise("second")
t.kill
p t.join(5)&.status
p log.uniq

# A kill alone, with nothing to rescue.
t = Thread.new { loop { IO.select(nil, [w]) } }
Thread.pass
t.kill
p t.join(5)&.status
