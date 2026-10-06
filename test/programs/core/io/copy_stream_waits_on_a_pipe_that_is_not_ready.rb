# IO.copy_stream waits on a pipe that has no bytes yet, also on one that
# is non-blocking, rather than raising EAGAIN. The text is larger than a
# pipe holds, so each end must wait for the other.
require "io/nonblock"

text = "abc" * 400_000
[false, true].each do |nonblock|
  r1, w1 = IO.pipe
  r2, w2 = IO.pipe
  if nonblock
    r1.nonblock = true
    w2.nonblock = true
  end
  writer = Thread.new { w1 << text; w1.close }
  reader = Thread.new { r2.read }
  copier = Thread.new { IO.copy_stream(r1, w2).tap { w2.close } }
  p [nonblock, writer.value, reader.value == text, copier.value]
end
