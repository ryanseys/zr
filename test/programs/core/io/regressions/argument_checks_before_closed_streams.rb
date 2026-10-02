# IO, File and Dir check their arguments before the stream, as ruby's
# do.
require "tmpdir"

def t
  p yield
rescue => e
  p [e.class, e.message]
end

Dir.mktmpdir do |dir|
  path = File.join(dir, "f.txt")
  File.write(path, "abcdef")

  f = File.open(path)
  f.read(1)
  t { f.sysseek("1") }
  t { f.seek("1") }
  t { f.pos = "1" }
  f.close
  t { f.read(-1) }
  t { f.readpartial(-1) }
  t { f.read_nonblock(-1) }
  t { f.close_read }
  t { f.close_write }
  t { f.read(1) }

  d = Dir.new(dir)
  d.close
  %i[rewind tell pos read fileno].each { |name| t { d.public_send(name) } }
  t { d.seek(0) }
  t { d.pos = 0 }

  # A blocking flock waits as a green thread: the other threads run.
  lock = File.join(dir, "lock")
  File.write(lock, "")
  a = File.open(lock)
  b = File.open(lock)
  a.flock(File::LOCK_EX)
  ran = []
  waiter = Thread.new { b.flock(File::LOCK_EX); ran << :locked }
  sleep 0.05
  ran << :main
  a.flock(File::LOCK_UN)
  waiter.join
  t { ran }
end
