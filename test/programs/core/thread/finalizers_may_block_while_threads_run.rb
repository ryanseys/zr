# Finalizers that block -- sleep, lock a mutex, pass, pop a queue --
# run at exit after the other threads, each once, in the order they
# were defined.
lock = Mutex.new
queue = Queue.new
queue << :ready
worker = Thread.new { sleep }
Thread.pass until worker.stop?

def track(kind, &body)
  obj = Object.new
  ObjectSpace.define_finalizer(obj, proc { body.call; $stdout.puts kind; $stdout.flush })
  obj
end

KEEP = [
  track(:sleep) { sleep 0.01 },
  track(:mutex) { lock.synchronize { :held } },
  track(:pass) { Thread.pass },
  track(:queue) { queue.pop },
  track(:worker) { $stdout.puts worker.alive? }
]
puts "main ends"
