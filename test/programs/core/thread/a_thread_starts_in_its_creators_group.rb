# A thread starts in the group of the thread that made it. A frozen
# group takes no thread, gives none up, and its threads make none.
group = ThreadGroup.new
inner = Thread.new do
  group.add(Thread.current)
  Thread.new { sleep 0.05 }
end.value
p inner.group.equal?(group)
inner.join

frozen = ThreadGroup.new
other = Thread.new { 1 }
Thread.new do
  frozen.add(Thread.current)
  frozen.freeze
  p((Thread.new { 1 }.join rescue $!))
  p((frozen.add(other) rescue $!))
  p((ThreadGroup.new.add(Thread.current) rescue $!))
end.join
other.join
p Thread.new { Thread.current.group }.value.equal?(ThreadGroup::Default)
