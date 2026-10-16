# A socket's connect is non-blocking, so it waits for the connection in
# rb_io_wait, which hands a non-blocking fiber's wait to its scheduler's
# io_wait with READABLE | WRITABLE (wait_connectable). The wait's caller
# shows the program's frames only. Only connect's waits print: whether a
# read or an accept waits depends on how soon the bytes arrive.
# scheduler.rb is CRuby's test/fiber/scheduler.rb.
require "socket"
require_relative "scheduler"

class Recording < Scheduler
  def io_wait(io, events, timeout)
    frames = caller(1).grep_v(/scheduler\.rb/).map { |line| line[/'.*'/] }
    connecting = events == IO::READABLE | IO::WRITABLE
    puts "io_wait #{io.class} #{events} #{timeout.inspect} #{frames.first(3).inspect}" if connecting
    super
  end
end

Thread.new do
  Fiber.set_scheduler Recording.new
  Fiber.schedule do
    server = TCPServer.new("127.0.0.1", 0)
    client = TCPSocket.new("127.0.0.1", server.addr[1])
    peer = server.accept
    client.write("x")
    p peer.read(1)
    raw = Socket.new(:INET, :STREAM)
    p raw.connect(Socket.sockaddr_in(server.addr[1], "127.0.0.1"))
    server.accept.close
    [client, peer, raw, server].each(&:close)
  end
end.join
