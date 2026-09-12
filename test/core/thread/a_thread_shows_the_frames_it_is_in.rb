# `Thread#backtrace`: the frames another thread stands in, innermost
# first, and nil once the thread has ended. A start past the outermost
# frame is nil as well, as `caller` answers.
def inner = sleep
def outer = inner

def shown(rows) = rows.map { |row| row.sub(%r{\A.*/}, "").sub(/:\d+/, ":L") }

t = Thread.new { outer }
sleep 0.05
rows = t.backtrace
p rows.class
p shown(rows)
p t.backtrace(1).size == rows.size - 1
p t.backtrace(0, 2).size
p t.backtrace(99)

where = t.backtrace_locations
p [where.class, where.first.class, where.first.lineno.is_a?(Integer), where.first.label]
p shown(where.map(&:to_s))

p Thread.current.backtrace.class
p Thread.main.backtrace.class

t.kill
t.join
p t.backtrace
p t.backtrace_locations

__END__
Array
["a_thread_shows_the_frames_it_is_in.rb:L:in 'Kernel#sleep'", "a_thread_shows_the_frames_it_is_in.rb:L:in 'Object#inner'", "a_thread_shows_the_frames_it_is_in.rb:L:in 'Object#outer'", "a_thread_shows_the_frames_it_is_in.rb:L:in 'block in <main>'"]
true
2
nil
[Array, Thread::Backtrace::Location, true, "Kernel#sleep"]
["a_thread_shows_the_frames_it_is_in.rb:L:in 'Kernel#sleep'", "a_thread_shows_the_frames_it_is_in.rb:L:in 'Object#inner'", "a_thread_shows_the_frames_it_is_in.rb:L:in 'Object#outer'", "a_thread_shows_the_frames_it_is_in.rb:L:in 'block in <main>'"]
Array
Array
nil
nil
