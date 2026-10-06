# lib/socket.rb, as the gem ships it, over the C half: servers and
# clients of each family, the non-blocking calls, and a descriptor sent
# through a unix socket.
require "socket"
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
t("tcp_server_sockets") { socks = Socket.tcp_server_sockets("127.0.0.1", 0); r = socks.map { |s| [s.class, s.local_address.ipv4?] }; socks.each(&:close); r }
t("udp_server_sockets") { socks = Socket.udp_server_sockets("127.0.0.1", 0); r = socks.map(&:class); socks.each(&:close); r }
t("addrinfo bind/connect") do
  srv = Addrinfo.tcp("127.0.0.1", 0).listen
  port = srv.local_address.ip_port
  cl = Addrinfo.tcp("127.0.0.1", port).connect
  peer, peer_ai = srv.accept
  cl.write("x"); r = [peer.read(1), peer_ai.ipv4?, peer.class]
  [cl, peer, srv].each(&:close)
  r
end
t("nonblock connect/accept") do
  srv = Socket.new(:INET, :STREAM); srv.bind(Addrinfo.tcp("127.0.0.1", 0)); srv.listen(5)
  cl = Socket.new(:INET, :STREAM)
  st = cl.connect_nonblock(srv.local_address, exception: false)
  IO.select(nil, [cl], nil, 5)
  acc = srv.accept_nonblock(exception: false)
  acc = (IO.select([srv], nil, nil, 5); srv.accept_nonblock) if acc == :wait_readable
  r = [st, acc.class, acc[1].class, cl.connect_nonblock(srv.local_address, exception: false)]
  [cl, acc[0], srv].each(&:close)
  r
end
t("accept_nonblock empty") { srv = TCPServer.new("127.0.0.1", 0); r = [srv.accept_nonblock(exception: false)]; begin; srv.accept_nonblock; rescue IO::WaitReadable => e; r << e.class << e.message; end; srv.close; r }
t("sendmsg/recvmsg rights") do
  a, b = UNIXSocket.pair
  r, w = IO.pipe
  a.sendmsg("hey", 0, nil, Socket::AncillaryData.unix_rights(r))
  msg, from, flags, ctl = b.recvmsg(:scm_rights => true)
  io = ctl.unix_rights[0]
  w.write("pipe"); w.close
  res = [msg, from.inspect, flags, ctl.inspect.sub(/\d+>\z/, "N>"), io.class, io.read]
  [a, b, r].each(&:close)
  res
end
t("recvmsg nonblock") { a, b = UNIXSocket.pair; r = b.recvmsg_nonblock(exception: false); a.write("q"); r2 = b.recvmsg_nonblock(10); [a, b].each(&:close); [r, r2[0]] }
t("recvfrom unix") { a, b = UNIXSocket.pair; a.write("u"); r = b.recvfrom(5); [a, b].each(&:close); r }
t("socket recvfrom") { a, b = Socket.pair(:UNIX, :DGRAM); a.send("d", 0); r = b.recvfrom(5); [a, b].each(&:close); [r[0], r[1].class, r[1].inspect] }
t("unix_server_socket") { path = "/tmp/zr-us-#{$$}"; r = Socket.unix_server_socket(path) { |s| [s.class, s.local_address.unix_path == path] }; File.exist?(path) && File.delete(path); r }
t("Socket.unix") do
  path = "/tmp/zr-u2-#{$$}"
  srv = UNIXServer.new(path)
  th = Thread.new { c = srv.accept; c.write("ok"); c.close }
  r = Socket.unix(path) { |s| s.read }
  th.join; srv.close; File.delete(path)
  r
end
t("ipv6 loop") { srv = TCPServer.new("::1", 0); c = TCPSocket.new("::1", srv.addr[1]); a = srv.accept; r = [srv.addr[0], a.peeraddr[3], c.remote_address.inspect.sub(/\d+ TCP/, "P TCP")]; [c, a, srv].each(&:close); r }
t("udp connect send") { u = UDPSocket.new(:INET6); u.bind("::1", 0); v = UDPSocket.new(Socket::AF_INET6); v.connect("::1", u.addr[1]); v.send("six", 0); r = u.recvfrom(10); [u, v].each(&:close); [r[0], r[1][0]] }
t("getpeereid") { a, b = UNIXSocket.pair; r = a.getpeereid == [Process.euid, Process.egid]; [a, b].each(&:close); r }
t("local peercred") { a, b = UNIXSocket.pair; o = a.getsockopt(0, Socket::LOCAL_PEERCRED); [a, b].each(&:close); o.inspect.sub(/euid=\d+.*\(/, "euid=N (") }
t("so_error inspect") { s = Socket.new(:INET, :STREAM); o = s.getsockopt(:SOCKET, :ERROR); s.close; o.inspect }
t("getsockopt rcvbuf") { s = Socket.new(:INET, :DGRAM); o = s.getsockopt(:SOCKET, :RCVBUF); s.close; [o.int > 0, o.inspect.sub(/\d+>/, "N>")] }
t("closed ops") { s = Socket.new(:INET, :STREAM); s.close; s.getsockname }
t("instance vars") { s = Socket.new(:INET, :STREAM); r = s.instance_variables; s.close; r }
t("ip_address_list") { Socket.ip_address_list.map(&:afamily).uniq.sort }
t("tcp timeout") { srv = TCPServer.new("127.0.0.1", 0); s = Socket.tcp("127.0.0.1", srv.addr[1], connect_timeout: 1); r = s.remote_address.ip_port == srv.addr[1]; [s, srv].each(&:close); r }
t("tcpserver port only") { s = TCPServer.new(0); r = s.addr[0]; s.close; r }

