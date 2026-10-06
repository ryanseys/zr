Warning[:experimental] = false

main_group = Thread.current.group
p main_group.equal?(ThreadGroup::Default)

ids = Ractor.new do
  group = Thread.current.group
  inner = Thread.new { Thread.current.group }.value
  default = begin
    ThreadGroup::Default
  rescue Ractor::IsolationError => e
    e.message
  end
  [default, inner.equal?(group), group.class, group.list.size]
end.value
p ids

# Each ractor gets a group of its own.
a = Ractor.new { Thread.current.group.object_id }.value
b = Ractor.new { Thread.current.group.object_id }.value
p a == b
p [a == main_group.object_id, b == main_group.object_id]

# The main ractor's threads are still in the default group.
p Thread.new { Thread.current.group.equal?(ThreadGroup::Default) }.value

# A fork outside the main ractor raises IsolationError.
p(Ractor.new do
  Process.fork
rescue Ractor::IsolationError => e
  [e.class, e.message]
end.value)
p(Ractor.new do
  fork { exit! 0 }
rescue Ractor::IsolationError => e
  [e.class, e.message]
end.value)
