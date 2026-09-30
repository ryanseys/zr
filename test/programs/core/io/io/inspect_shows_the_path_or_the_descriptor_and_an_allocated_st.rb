# inspect shows the path, or the descriptor, which a closed stream no
# longer has; an allocated stream is any object, and closes with an error.
path = "/tmp/zr_spec_inspect.txt"
File.write(path, "x")
f = File.open(path)
f.close
p f.inspect
p IO.popen("true").tap(&:close).inspect
p IO.allocate.inspect.sub(/0x\h+/, "X")
p((IO.allocate.close rescue $!))
File.delete(path)
