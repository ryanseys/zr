# An IO::Buffer made MAPPED | SHARED is anonymous memory that mmap
# shares (MAP_SHARED), so a forked child's writes show in the parent:
# through set_string, set_value, a slice and a copy. A buffer that is
# only MAPPED, and a dup of a shared one, keep their own bytes.
message = "Hello World"
shared = IO::Buffer.new(64, IO::Buffer::MAPPED | IO::Buffer::SHARED)
p shared.shared?, shared.mapped?, shared.internal?
p shared.get_string(0, 4)

copy = shared.dup
plain = IO::Buffer.new(64, IO::Buffer::MAPPED)
pid = fork do
  shared.set_string(message)
  shared.set_value(:U32, 16, 0xDEADBEEF)
  shared.slice(20, 4).set_string("tail")
  shared.copy(IO::Buffer.for("xy"), 30)
  copy.set_string("copied")
  plain.set_string(message)
end
Process.wait(pid)
p shared.get_string(0, message.bytesize)
p shared.get_value(:U32, 16).to_s(16)
p shared.get_string(20, 4), shared.get_string(30, 2)
p copy.get_string(0, 6), copy.shared?
p plain.get_string(0, 4)

# The parent's writes reach a child too.
shared.set_string("from parent", 40)
reader, writer = IO.pipe
pid = fork do
  reader.close
  writer.write(shared.get_string(40, 11))
  writer.close
end
writer.close
p reader.read
Process.wait(pid)

# A slice keeps only the read-only flag. A resize copies the bytes into
# memory of its own, which a child no longer shares.
p shared.slice(0, 8).shared?
shared.resize(128)
p shared.size, shared.get_string(0, message.bytesize), shared.shared?, shared.internal?
pid = fork { shared.set_string("z") }
Process.wait(pid)
p shared.get_string(0, 1)
p shared.free.null?
