# rb_io_close_read on a duplex popen: the read end closes, and the write
# end takes the stream's place with its child, so the stream writes on.
IO.popen("cat", "r+") do |f|
  pid = f.pid
  f.close_read
  p f.closed?
  p f.pid == pid
  p f.write("foobarbaz")
  begin
    f.read
  rescue IOError => e
    p e.message
  end
  p f.close_read
  f.close_write
  p f.closed?
  p f.close_read
end

# The other order: the write end first, then the read end.
IO.popen("cat", "r+") do |f|
  f.write("abc")
  f.close_write
  p f.read
  f.close_read
  p f.closed?
end

# A copy of a duplex stream has its own two ends.
IO.popen("cat", "r+") do |f|
  g = f.dup
  f.puts "foo"
  g.puts "bar"
  f.close_write
  g.close_write
  p f.read
  p g.read
  g.close
end

# A stream that is only readable closes whole.
IO.popen("echo hi") do |f|
  f.close_read
  p f.closed?
end
r, w = IO.pipe
begin
  w.close_read
rescue IOError => e
  p e.message
end
r.close_read
p r.closed?
w.close
