# A fiber and a thread as CRuby has them: kill unwinds a fiber through
# its ensure, raise carries an exception into it, a fiber resumed twice
# or from another thread says so, a thread's locals belong to the fiber
# that thread runs, and a frozen Mutex still locks.
def t = yield rescue [$!.class, $!.message]

Thread.report_on_exception = false

log = []
f = Fiber.new do
  Fiber.yield
ensure
  log << :ensured
end
f.resume
p t { [f.kill.class, f.alive?, log] }

g = Fiber.new do
  Fiber.yield
rescue StandardError => e
  :"rescued-#{e.message}"
end
g.resume
p t { g.raise("boom") }
p t { Fiber.new { :never }.raise("early") }
p t { Fiber.new { :never }.kill.alive? }

h = Fiber.new { Fiber.new { h.resume }.resume }
p t { h.resume }
k = Fiber.new { Fiber.yield }
k.resume
p t { Thread.new { k.resume }.value }

th = Thread.new { sleep 0.02; Thread.current[:a] }
th[:a] = 1
p t { th.value }, t { th.key?(:a) }, t { Thread.current[:a] }

m = Thread::Mutex.new.freeze
p t { [m.frozen?, m.lock.class, m.locked?, m.unlock.class] }
p t { Thread.current.priority = 3; Thread.current.priority }, t { Thread.current.native_thread_id.is_a?(Integer) }
p t { Thread.pending_interrupt? }, t { Thread.current.group.class }, t { ThreadGroup::Default.class }

__END__
[Fiber, false, [:ensured]]
:"rescued-boom"
[FiberError, "cannot raise exception on unborn fiber"]
false
[FiberError, "attempt to resume a resumed fiber (double resume)"]
[FiberError, "fiber called across threads"]
1
true
nil
[true, Thread::Mutex, true, Thread::Mutex]
3
true
false
ThreadGroup
ThreadGroup
