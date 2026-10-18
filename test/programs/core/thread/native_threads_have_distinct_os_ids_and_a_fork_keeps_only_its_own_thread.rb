# Each thread has an OS thread of its own (ZR_THREADS=native in the
# .env): its native_thread_id is the OS's id, distinct from every other
# live thread's, the same while it lives, and nil once it is dead.
main_id = Thread.main.native_thread_id
p main_id.is_a?(Integer), main_id == Thread.current.native_thread_id

q = Queue.new
threads = 3.times.map { Thread.new { q.pop; Thread.current.native_thread_id } }
before = threads.map(&:native_thread_id)
3.times { q << :go }
after = threads.map(&:value)
p before.all?(Integer), before == after
p (before + [main_id]).uniq.size
p threads.map(&:native_thread_id)

# A thread killed before its first turn ends, with its OS thread.
fresh = Thread.new { :never }
fresh.kill
fresh.join
p fresh.status, fresh.native_thread_id

# Many threads start and end, each on an OS thread of its own.
ids = 50.times.map { Thread.new { Thread.current.native_thread_id } }.map(&:value)
p ids.all?(Integer), ids.include?(main_id)

# A forked child keeps only the thread that forked, with a new id.
r, w = IO.pipe
worker = Thread.new { sleep }
pid = fork do
  r.close
  w.puts [Thread.list.size, Thread.current.native_thread_id != main_id, Thread.new { 1 + 1 }.value].inspect
  w.close
end
w.close
puts r.read
Process.wait(pid)
p $?.success?
worker.kill
worker.join
p Thread.list.size
