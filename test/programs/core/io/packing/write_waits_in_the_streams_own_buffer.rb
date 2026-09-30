# A stream that is not a terminal holds what a program writes until the
# buffer fills, the program asks for a flush, or the program ends. CRuby's
# buffer is 8192 bytes: a write that would fill it writes what waits and
# the new text with it. A pipe's write end and a stream to a child are
# synchronised instead, so they write at once.
require "tmpdir"

Dir.mktmpdir do |dir|
  path = File.join(dir, "held.txt")
  File.open(path, "w") do |file|
    file.write("a" * 10)
    p [file.sync, File.size(path)]
    file.write("b" * 9000)
    p File.size(path)
    file.flush
    p File.size(path)
  end
  p File.size(path)
end

r, w = IO.pipe
p w.sync
w.write("x")
p r.readpartial(1)
w.close
r.close

IO.popen("cat", "r+") do |io|
  p io.sync
  io.write("through\n")
  p io.gets
end

