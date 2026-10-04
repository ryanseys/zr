# Thread#raise and Fiber#raise make the exception as Kernel#raise does,
# with the cause from the calling context, and Thread#raise returns nil.
Thread.report_on_exception = false
def caught
  yield
rescue Exception => e
  [e.class, e.message, e.cause&.message]
end

def in_thread(*args, **opts)
  t = Thread.new { Thread.stop; :done }
  Thread.pass until t.stop?
  r = begin
    raise "outer"
  rescue
    t.raise(*args, **opts)
  end
  [r, caught { t.value }]
end

p in_thread
p in_thread(ArgumentError, "a")
p in_thread(ArgumentError, "b", cause: nil)
p in_thread(ArgumentError, "c", cause: StandardError.new("given"))
[[nil], [true], [Object.new], ["a", "b"], [ArgumentError, "x", ["bt"], 1]].each do |args|
  t = Thread.new { sleep }
  Thread.pass until t.stop?
  p caught { t.raise(*args) }
  t.kill
end
t = Thread.new { sleep }
Thread.pass until t.stop?
p caught { t.raise(cause: nil) }
t.kill; t.join
p t.raise("dead")
e = RuntimeError.new("loop")
p caught { Thread.current.raise(e, cause: e) }
p caught { Thread.current.raise(RuntimeError, "m", cause: e) }

f = Fiber.new { Fiber.yield 1; :end }
f.resume
p caught {
  begin
    raise "outer"
  rescue
    f.raise(ArgumentError, "fib")
  end
}
g = Fiber.new { Fiber.yield 1 }
g.resume
p caught { g.raise(["bt"]) }, caught { g.raise(1) }
# A raise on a fiber that is resuming another goes to the fiber that it
# resumed: here, the current one.
f2 = nil
f1 = Fiber.new { f2.raise(RuntimeError, "on parent") }
f2 = Fiber.new { f1.resume }
p caught { f2.resume }
def locs = caller_locations
l = locs
p caught { raise ArgumentError, "with locations", l }
begin
  raise ArgumentError, "kept", l
rescue => e
  p e.backtrace_locations.map(&:to_s) == l.map(&:to_s)
end
