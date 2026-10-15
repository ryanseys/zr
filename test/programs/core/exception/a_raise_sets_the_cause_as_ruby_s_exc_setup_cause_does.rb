# How `raise` sets a cause: `$!` only for an exception with no cause yet;
# an explicit cause replaces one, nil and the exception itself change
# nothing; a cause gets a nil cause of its own, so raising it again keeps
# that and closes no ring; a frozen exception takes a cause in a copy.
def chain(e)
  names = []
  while e && names.size < 6
    names << e.message
    e = e.cause
  end
  names.join(" <- ")
end

def caught
  yield
  :none
rescue Exception => e
  e
end

# Raised with no `$!`, an exception has no cause yet, so `$!` becomes its
# cause when it is raised again.
old = RuntimeError.new("old")
caught { raise old }
e = caught { begin; raise "handled"; rescue; raise old; end }
puts "unrelated: #{chain(e)}"

# The exception that a rescue handles becomes a cause, which gives it a
# nil cause; raising it again in a later rescue keeps that.
def work
  raise ArgumentError, "work failed"
rescue ArgumentError => original
  begin
    raise IOError, "cleanup failed"
  rescue IOError
    raise original
  end
end
puts "cleanup: #{chain(caught { work })}"

a = caught { raise "a" }
e = caught { begin; raise "b"; rescue; begin; raise "c"; rescue; raise a; end; end }
puts "three: #{chain(e)}"

again = RuntimeError.new("itself")
e = caught { begin; raise again; ensure; raise again; end }
puts "itself: #{chain(e)}"

# An explicit cause replaces the cause; nil and the exception itself keep it.
seed = RuntimeError.new("seed")
other = RuntimeError.new("other")
e = RuntimeError.new("e")
caught { raise e, cause: seed }
puts "explicit: #{chain(e)}"
caught { raise e, cause: other }
puts "replaced: #{chain(e)}"
caught { raise e, cause: nil }
puts "nil keeps: #{chain(e)}"
caught { raise e, cause: e }
puts "itself keeps: #{chain(e)}"

# An explicit nil sets nothing, so `$!` is the cause of a later raise.
fresh = RuntimeError.new("fresh")
caught { raise fresh, cause: nil }
e = caught { begin; raise "outer"; rescue; raise fresh; end }
puts "nil then $!: #{chain(e)}"

# A cause whose chain leads back to the exception is refused.
x = RuntimeError.new("x")
y = RuntimeError.new("y")
caught { raise y, cause: x }
e = caught { raise x, cause: y }
p [e.class, e.message, x.cause]
e = caught { raise x, cause: x }
p [e.message, e.cause]

# A frozen exception with a backtrace is raised as a copy that takes the
# cause; one without is raised as it is, with neither.
f = RuntimeError.new("frozen")
caught { raise f, cause: seed }
f.freeze
r = caught { raise f, cause: other }
p [r.equal?(f), r.cause&.message, f.cause&.message]
g = RuntimeError.new("bare").freeze
r = caught { begin; raise "outer"; rescue; raise g; end }
p [r.equal?(g), r.cause, r.backtrace]
r = caught { raise g, cause: other }
p [r.equal?(g), r.cause]

# Thread#raise resolves the cause now and replaces any, nil too.
t = Thread.new { Thread.stop; :done }
t.report_on_exception = false
Thread.pass until t.status == "sleep"
withcause = RuntimeError.new("thread")
caught { raise withcause, cause: seed }
t.raise(withcause, cause: nil)
r = caught { t.join }
p [r.message, r.cause]

# Many rings in a row stay short.
total = 0
100.times do |i|
  e = caught { begin; raise "first #{i}"; rescue => a; begin; raise "second"; rescue; raise a; end; end }
  total += 1 if e.cause.nil?
end
p total
