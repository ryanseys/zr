# A thread writes 512 MiB into a pipe while the main thread reads it
# Tests: IO.pipe, a write and a readpartial that wait, handoffs between them

r, w = IO.pipe
chunk = "x" * 65_536
writer = Thread.new do
  8192.times { w.write(chunk) }
  w.close
end

total = 0
buf = +""
begin
  loop { total += r.readpartial(65_536, buf).bytesize }
rescue EOFError
  nil
end
writer.join
puts total
