# A stream that IO.allocate made has no descriptor: every write refuses,
# an empty one too, while a closed stream takes an empty write.
io = IO.allocate
[:print, :write, :puts, :<<, :syswrite].each do |name|
  io.public_send(name, "")
rescue IOError => e
  p [name, e.message]
end
begin
  io.write("x", "y")
rescue IOError => e
  p e.message
end
p io.inspect.sub(/0x\h+/, "X")

r, w = IO.pipe
w.close
p w.write("")
begin
  w.write("x")
rescue IOError => e
  p e.message
end
r.close
