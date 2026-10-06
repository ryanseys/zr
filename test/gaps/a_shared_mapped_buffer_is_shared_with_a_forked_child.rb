# IO::Buffer::SHARED with MAPPED is anonymous memory that mmap shares
# (MAP_SHARED): a forked child's write shows in the parent. zr keeps a
# buffer's bytes in a String, which the child has its own copy of.
message = "Hello World"
buffer = IO::Buffer.new(64, IO::Buffer::MAPPED | IO::Buffer::SHARED)
pid = fork { buffer.set_string(message) }
Process.wait(pid)
p buffer.get_string(0, message.bytesize)
