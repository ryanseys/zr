# A raise and then a kill: the exception arrives first, and ruby clears
# the thread's interrupt flag with it, so the kill waits in the queue for
# the thread's next blocking call. A thread that only computes runs on
# until the program ends, and its ensure clause has not run.
log = []
started = false
t = Thread.new do
  begin
    started = true
    loop { }
  rescue => e
    log << e.message
    n = 0
    loop { n += 1 }
  ensure
    log << :ensure
  end
end
Thread.pass until started
t.raise("first")
t.kill
p t.join(0.3)&.status
p log
