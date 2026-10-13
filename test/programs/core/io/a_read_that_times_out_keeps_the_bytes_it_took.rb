# IO#timeout bounds a blocking read or write: past it, IO::TimeoutError.
# The bytes a read took before the timeout go back to the buffer (ruby
# 4.1, #19053), so the next read gets them. timeout= takes nil, false or
# a time interval.
$stdout.sync = true
IO.pipe do |r, w|
  w.write("Hello")
  r.timeout = 0.0001
  p((r.read(10) rescue $!.class))
  p r.read_nonblock(5)
end
IO.pipe do |r, w|
  w.write("abc")
  r.timeout = 0.01
  p((r.read rescue $!.class))
  w.write("def")
  w.close
  r.timeout = 1
  p r.read
end
IO.pipe do |r, w|
  r.timeout = 0.01
  p((r.read(3) rescue $!.class))
end
# A timeout with bytes already in the buffer, and the bytes after them.
IO.pipe do |r, w|
  w.write("line1\nline2")
  r.timeout = 0.01
  p r.gets
  p((r.read(20) rescue $!.class))
  p r.read_nonblock(20)
  p((r.read rescue $!.class))
  w.write("xyz")
  w.close
  p r.read
end
IO.pipe do |r, w|
  r.timeout = 0.01
  p r.timeout
  w.write("ok")
  w.close
  p r.read(2), r.read
end
IO.pipe do |r, w|
  w.timeout = 0.01
  p((w.write("x" * 1_000_000) rescue [$!.class, $!.message]))
  p r.read_nonblock(10).size
end
IO.pipe do |r, w|
  w.timeout = 0.01
  w.sync = false
  begin
    w.write("x" * 1_000_000)
    w.flush
  rescue => e
    p [e.class, e.message]
  end
end
r, w = IO.pipe
[nil, 1, 0.5, 0, 1r, "1", -1, Object.new].each do |v|
  r.timeout = v
  p r.timeout
rescue => e
  p [e.class, e.message.sub(/0x\h+/, "XX")]
end
p (r.timeout = nil)
