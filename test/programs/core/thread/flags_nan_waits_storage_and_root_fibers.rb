# Thread and Fiber edges that answer as ruby's do.
def t
  p yield
rescue => e
  p [e.class, e.message]
end

# The exception flags read back as true or false.
th = Thread.new {}
th.join
th.report_on_exception = nil
t { th.report_on_exception }
th.report_on_exception = "yes"
t { th.report_on_exception }
th.abort_on_exception = 0
t { th.abort_on_exception }
was = Thread.abort_on_exception
Thread.abort_on_exception = 0
t { Thread.abort_on_exception }
Thread.abort_on_exception = was

# A NaN timeout is out of Time range.
nan = Float::NAN
t { sleep(nan) }
t { Mutex.new.tap(&:lock).sleep(nan) }
r, _w = IO.pipe
t { IO.select([r], nil, nil, nan) }
t { r.wait_readable(nan) }
t { m = Mutex.new; m.synchronize { ConditionVariable.new.wait(m, nan) } }
t { Queue.new.pop(timeout: nan) }

# Fiber storage is nil until a key is set, and a nil value removes it.
t { Fiber.new { Fiber.current.storage }.resume }
t { Fiber.new { Fiber[:a] = 1; Fiber[:gone] = 2; Fiber[:gone] = nil; Fiber.current.storage }.resume }
t { Fiber.new(storage: {a: 9}) { Fiber[:b] = nil; Fiber.current.storage }.resume }

# The current fiber cannot resume itself.
t { Fiber.current.resume }

# A SystemExit that ends a thread is no report.
Thread.report_on_exception = true
t { Thread.new { exit 3 }.join }
