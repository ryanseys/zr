# Thread names, Thread.kill, handle_interrupt, fetch and a join limit
# check their arguments as CRuby does.
def try = yield rescue $!
t = Thread.start {}
p(try { t.name = "foo\0bar" })
p(try { t.name = "foo".encode(Encoding::UTF_32BE) })
t.join
p try { Thread.kill(nil) }, try { Thread.kill(Object.new) }
p try { Thread.handle_interrupt(RuntimeError => :immediate) }
p try { Thread.handle_interrupt(RuntimeError => :xyzzy) {} }
p try { Thread.handle_interrupt([]) {} }
t = Thread.new { sleep }
t["foo"] = "foo"
p t.fetch(:foo, 0), t.fetch("qux", 2), t.fetch(:qux) { 1 }
e = try { t.fetch(:qux) }
p e.class, e.message, e.key, e.receiver.equal?(t)
t.kill.join
u = Thread.new {}
Thread.pass while u.status
p try { u.join(:foo) }
limit = Struct.new(:to_f, :count).new(0.05)
p u.join(limit).equal?(u)
c = Class.new(Thread) { def initialize() self.name = "foo"; super; end }
p c.new { Thread.current.name }.value
