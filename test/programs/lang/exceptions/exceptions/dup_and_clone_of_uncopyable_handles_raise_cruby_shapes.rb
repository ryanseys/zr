# Duplicating or cloning an uncopyable handle raises a real, rescuable
# error, with every message verbatim from ruby 4.0.7. Fiber is the
# special one: CRuby's shallow copy succeeds but skips the machine
# stack, so the COPY is an uninitialized fiber (resume raises) while
# the original still runs. Concurrent join/value on one Thread hands
# every joiner the outcome.

begin; Thread.current.dup; rescue TypeError => e; puts "thread: #{e.message}"; end
begin; Queue.new.clone; rescue NoMethodError => e; puts "queue: #{e.message}"; end
begin; SizedQueue.new(1).dup; rescue NoMethodError => e; puts "sq: #{e.message}"; end
g = Fiber.new { 42 }.dup
begin; g.resume; rescue FiberError => e; puts "fiber: #{e.message}"; end
f = Fiber.new { 7 }
f.dup
puts "orig: #{f.resume}"
e = [1, 2].each
e.next
begin; e.dup; rescue TypeError => ex; puts "enum: #{ex.message}"; end
t = Thread.new { sleep 0.05; :done }
a = Thread.new { t.value }
b = Thread.new { t.value }
puts "joins: #{a.value} #{b.value}"
