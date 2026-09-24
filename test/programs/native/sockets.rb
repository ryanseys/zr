# Sockets over libSystem, on the loopback address only.
# no stress
require "socket"

p Socket::AF_INET, Socket::SOCK_STREAM, Socket::SOL_SOCKET
p Socket.pack_sockaddr_in(80, "127.0.0.1").bytes
p Socket.unpack_sockaddr_in(Socket.pack_sockaddr_in(80, "127.0.0.1"))
p Socket.unpack_sockaddr_in(Socket.pack_sockaddr_in(443, "::1"))
p Socket.unpack_sockaddr_in(Socket.pack_sockaddr_in(0, "2001:db8::1"))
p Socket.unpack_sockaddr_un(Socket.pack_sockaddr_un("/tmp/zr.sock"))
p Socket.getaddrinfo("127.0.0.1", 80, nil, Socket::SOCK_STREAM)
p Socket.getaddrinfo("localhost", "http", Socket::AF_INET, Socket::SOCK_STREAM).map { |r| r[0, 4] }
p Socket.getnameinfo(Socket.pack_sockaddr_in(80, "127.0.0.1"), Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV)
p Socket.gethostname.is_a?(String)

server = TCPServer.new("127.0.0.1", 0)
port = server.addr[1]
p server.addr[0], server.addr[3], port.is_a?(Integer)
client = TCPSocket.new("127.0.0.1", port)
peer = server.accept
client.write("hello over tcp\n")
p peer.gets
peer.write("and back\n")
p client.gets
p client.peeraddr[0], client.peeraddr[3]
p peer.local_address.ip_address, peer.local_address.ip_port == port
p client.getsockopt(Socket::SOL_SOCKET, Socket::SO_TYPE).int == Socket::SOCK_STREAM
client.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
p client.getsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY).bool
client.close
peer.close
server.close

a = UDPSocket.new
a.bind("127.0.0.1", 0)
aport = a.addr[1]
b = UDPSocket.new
b.send("datagram", 0, "127.0.0.1", aport)
text, from = a.recvfrom(64)
p text, from[0], from[2]
a.close
b.close

left, right = UNIXSocket.pair
left.write("over a pair\n")
p right.gets
left.close
right.close

path = File.join(ENV["TMPDIR"] || "/tmp", "zr-socket-#{Process.pid}")
listener = UNIXServer.new(path)
talker = UNIXSocket.new(path)
accepted = listener.accept
talker.write("over a path\n")
p accepted.gets, talker.path == path
[talker, accepted, listener].each(&:close)
File.delete(path)

begin
  TCPSocket.new("127.0.0.1", 1)
rescue SystemCallError => e
  p e.class
end
begin
  Socket.getaddrinfo("no-such-host.invalid", nil)
rescue SocketError => e
  p e.class
end
