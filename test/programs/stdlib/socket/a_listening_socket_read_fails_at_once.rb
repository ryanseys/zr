require "socket"
srv = TCPServer.new("127.0.0.1", 0)
port = srv.addr[1]
t = Thread.new do
  d = TCPSocket.new("127.0.0.1", port)
  d.puts("This is the content")
  d.close
  :done
end
puts "accepting"; $stdout.flush
conn = srv.accept
puts "accepted"; $stdout.flush
p((srv.shutdown(Socket::SHUT_WR) rescue $!.class))
$stdout.flush
p((srv.read rescue $!.class))
$stdout.flush
p conn.read
p t.value
srv.close
