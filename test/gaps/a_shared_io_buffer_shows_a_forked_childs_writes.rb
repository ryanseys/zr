# An IO::Buffer made MAPPED | SHARED is anonymous shared memory in CRuby,
# so a forked child's writes show in the parent. zr keeps a buffer's
# bytes in a String of the process, so the parent sees zeros.
buffer = IO::Buffer.new(64, IO::Buffer::MAPPED | IO::Buffer::SHARED)
p buffer.shared?
pid = fork { buffer.set_string("Hello World") }
Process.wait(pid)
p buffer.get_string(0, 11)
