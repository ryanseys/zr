# CRuby runs a rescue clause in a frame of its own. A caller list from
# the clause shows that frame at the clause's line and hides the scope
# under it; a list that starts one level further shows the scope at the
# line of the clause's `begin` (or `def`).
def at_def
  raise
rescue
  p caller(0), caller(1), caller(1, 1), caller(2)
  p caller_locations(1, 1).map { |l| [l.lineno, l.label] }
end
at_def

def at_begin
  x = 1
  begin
    x += 1
    raise
  rescue
    p caller(1, 1), caller(0, 1)
  end
end
at_begin

# A normal ensure runs in the scope's own frame.
def ensured
  yield
ensure
  p caller(1, 1), caller(0, 1)
end
ensured { 1 }

def in_block
  [1].each do
    begin
      raise "x"
    rescue
      p caller(1, 2)
    end
  end
end
in_block

def do_block_rescue
  [1].each do
    raise "x"
  rescue
    p caller(0, 1), caller(1, 1)
  end
end
do_block_rescue

# Nested clauses take a level each.
def nested
  begin
    raise
  rescue
    begin
      raise
    rescue
      p caller(0, 3), caller(1, 2), caller(2, 1), caller(3, 1)
    end
  end
end
nested

def modifier = (raise rescue caller(0, 2) + caller(1, 1))
p modifier

def retried
  tries = 0
  begin
    tries += 1
    raise
  rescue
    retry if tries < 2
    p caller(1, 1)
  end
end
retried

def warns
  raise
rescue
  warn "from the rescue", uplevel: 1
end
warns

# After the clause, the scope is one level again.
def after
  begin
    raise
  rescue
    nil
  end
  p caller(1, 1)
end
after

begin
  raise
rescue
  p caller(0), caller(1)
end

class Body
  begin
    raise
  rescue
    p caller(1, 1)
  end
end

p eval("begin; raise; rescue; caller(1, 1); end", nil, "evaluated", 10)

# Another thread's backtrace counts the levels too.
ready = Queue.new
t = Thread.new do
  raise
rescue
  ready << 1
  sleep
end
ready.pop
Thread.pass until t.status == "sleep"
p t.backtrace(1, 2).map { |row| row.sub(/\A.*?:(\d+)/, 'line \1') }
t.kill.join

def errors
  raise "in"
rescue => e
  p e.backtrace_locations.size, e.backtrace.size
end
errors
