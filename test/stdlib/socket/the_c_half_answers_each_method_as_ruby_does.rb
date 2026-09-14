# ext/socket's C half is ruby over the kernel's calls. Each row is one
# method of it, whose answer -- an inspect, an error's class and words,
# the bytes of an address -- is the one socket.so gives.
require "socket"
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
t("ai tcp") { Addrinfo.tcp("127.0.0.1", 80) }
t("ai list") { Addrinfo.getaddrinfo("127.0.0.1", 80) }
t("ai new arr") { Addrinfo.new(["AF_INET", 80, "localhost", "127.0.0.1"]) }
t("ai new arr2") { Addrinfo.new(["AF_INET", 80, nil, "127.0.0.1"], :INET, :STREAM) }
t("ai pf") { Addrinfo.new(Socket.sockaddr_in(80, "::1"), :INET) }
t("ai short") { Addrinfo.new("ab") }
t("ai short2") { Addrinfo.new("\x10\x02") }
t("ai v4mapped") { Addrinfo.ip("::ffff:1.2.3.4").ipv6_to_ipv4 }
t("ai marshal") { Marshal.load(Marshal.dump(Addrinfo.tcp("127.0.0.1", 80))) }
t("ai marshal dump") { Addrinfo.tcp("127.0.0.1", 80).marshal_dump }
t("ai unix rel") { Addrinfo.unix("rel path") }
t("ai unknown proto") { Addrinfo.new(Socket.sockaddr_in(0, "127.0.0.1"), :INET, :STREAM, 99) }
t("ai preds") { a = Addrinfo.ip("10.1.2.3"); [a.ipv4_private?, a.ipv4_loopback?, a.ipv6_linklocal?, Addrinfo.ip("fe80::1").ipv6_linklocal?, Addrinfo.ip("ff02::1").ipv6_mc_linklocal?] }
t("ai ip_unpack") { Addrinfo.udp("::1", 53).ip_unpack }
t("ai uninit") { Addrinfo.allocate.inspect }
t("ai unix_path") { Addrinfo.unix("/tmp/x").unix_path }
t("ai ivars") { Addrinfo.tcp("127.0.0.1", 80).instance_variables }
t("ai getnameinfo") { Addrinfo.tcp("127.0.0.1", 80).getnameinfo(Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV) }
t("ai family_addrinfo") { Addrinfo.tcp("127.0.0.1", 80).family_addrinfo("127.0.0.1", 81) }
t("sock getaddrinfo bad") { Socket.getaddrinfo("no such host.invalid", 80) }
t("resolution error code") { begin; Socket.getaddrinfo("no such host.invalid", 80); rescue SocketError => e; [e.class, e.respond_to?(:error_code) && e.error_code]; end }
t("newline") { Socket.getaddrinfo("localhost\n", 80) }
t("pack un") { Socket.sockaddr_un("/tmp/x").bytesize }
t("unpack un") { Socket.unpack_sockaddr_un(Socket.sockaddr_un("/tmp/x")) }
t("unpack in wrong") { Socket.unpack_sockaddr_in(Socket.sockaddr_un("/tmp/x")) }
t("getnameinfo arr") { Socket.getnameinfo(["AF_INET", 80, "127.0.0.1"], Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV) }
t("getnameinfo str") { Socket.getnameinfo(Socket.sockaddr_in(80, "127.0.0.1"), Socket::NI_NUMERICHOST) }
t("getnameinfo bad") { Socket.getnameinfo(1) }
t("servbyname") { [Socket.getservbyname("http"), Socket.getservbyname("domain", "udp"), Socket.getservbyname("0x10")] }
t("servbyname bad") { Socket.getservbyname("nope-nope") }
t("servbyport") { Socket.getservbyport(80) }
t("servbyport bad") { Socket.getservbyport(70000) }
t("option inspect") { [Socket::Option.linger(true, 5), Socket::Option.new(:INET, :SOCKET, :RCVTIMEO, [1, 5].pack("q<l<x4")), Socket::Option.new(:INET6, :IPV6, :JOIN_GROUP, [0xff02,0,0,0,0,0,0,1].pack("n8") + [1].pack("L")), Socket::Option.new(:INET, :IP, :ADD_MEMBERSHIP, [224,0,0,1,0,0,0,0].pack("C8")), Socket::Option.new(:INET, :SOCKET, :ERROR, [61].pack("i")), Socket::Option.new(:UNIX, 0, 1, "abc"), Socket::Option.new(:INET, :TCP, 999, "x"), Socket::Option.new(1234, 5, 6, "x")] }
t("option vals") { o = Socket::Option.linger(3, 5); [o.linger, Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, true).bool, Socket::Option.byte(:INET, :SOCKET, :KEEPALIVE, 300).byte, o.unpack("ii"), o.family, o.level, o.optname] }
t("option int size") { Socket::Option.linger(1, 2).int }
t("option bad name") { Socket::Option.int(:INET, :SOCKET, :NOPE, 1) }
t("option ivars") { Socket::Option.int(:INET, :SOCKET, :REUSEADDR, 1).instance_variables }
t("anc") { [Socket::AncillaryData.int(:UNIX, :SOCKET, :RIGHTS, 3), Socket::AncillaryData.new(:INET, :IP, :RECVDSTADDR, [127,0,0,1].pack("C4")), Socket::AncillaryData.ip_pktinfo(Addrinfo.ip("127.0.0.1"), 1), Socket::AncillaryData.ipv6_pktinfo(Addrinfo.ip("::1"), 1)] }
t("anc vals") { a = Socket::AncillaryData.ip_pktinfo(Addrinfo.ip("127.0.0.1"), 1); [a.ip_pktinfo, Socket::AncillaryData.ipv6_pktinfo(Addrinfo.ip("::1"), 1).ipv6_pktinfo, a.cmsg_is?(:IP, :PKTINFO)] }
t("ifaddrs") { Socket.getifaddrs.select { |i| i.name == "lo0" }.first(2) }
t("ip_address_list") { Socket.ip_address_list.select(&:ipv4_loopback?) }
t("hostname") { Socket.gethostname == `hostname`.chomp }
s = TCPServer.new("127.0.0.1", 0)
port = s.addr[1]
t("server addr") { s.addr.first(1) + [s.addr[2]] }
t("server inspect") { s.inspect.sub(/\d+>\z/, "PORT>").sub(/fd \d+/, "fd N") }
t("nonblock?") { s.nonblock? rescue :none }
t("sync binmode") { [s.sync, s.binmode?, s.external_encoding] }
c = TCPSocket.new("127.0.0.1", port)
a = s.accept
t("accepted class") { [a.class, a.remote_address.ip_address, c.peeraddr(:numeric)[3]] }
c.write("hello\n")
t("gets") { a.gets }
a.send("xyz", 0)
t("recv") { c.recv(10) }
t("getsockopt") { c.getsockopt(:SOCKET, :TYPE) }
t("setsockopt") { c.setsockopt(:TCP, :NODELAY, true); c.getsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY).bool }
t("recv_nonblock") { c.recv_nonblock(10, exception: false) }
t("recv_nonblock raise") { c.recv_nonblock(10) }
a.close_write
t("read eof") { c.read }
t("shutdown bad") { c.shutdown(:NOPE) }
c.close; a.close; s.close
t("refused") { begin; TCPSocket.new("127.0.0.1", port); rescue SystemCallError => e; e.message.sub(/port \d+/, "port N"); end }
t("closed addr") { s.addr }
u1 = UDPSocket.new; u1.bind("127.0.0.1", 0)
u2 = UDPSocket.new
u2.send("dgram", 0, "127.0.0.1", u1.addr[1])
t("udp recvfrom") { m, from = u1.recvfrom(10); [m, from[0], from[3]] }
u2.connect("127.0.0.1", u1.addr[1]); u2.send("two", 0)
t("udp recvfrom_nonblock") { u1.recvfrom_nonblock(10)[0] }
u1.close; u2.close
path = "/tmp/ze0-sock-#{$$}"
shown = ->(text) { text.gsub(path, "PATH") }
File.delete(path) if File.exist?(path)
us = UNIXServer.new(path)
uc = UNIXSocket.new(path)
ua = us.accept
t("unix addrs") { shown.call([us.path, uc.peeraddr, ua.addr, us.inspect].inspect) }
r, w = IO.pipe
uc.send_io(r)
t("recv_io") { io = ua.recv_io; [io.class, io.fileno > 2] }
w.write("through"); w.close
uc.sendmsg("msg", 0, nil, Socket::AncillaryData.int(:UNIX, :SOCKET, :RIGHTS, 1))
t("recvmsg") { m = ua.recvmsg(10, 0, nil); [m[0], m[1].class, m[3].class] rescue $! }
t("pair") { Socket.pair(:UNIX, :STREAM).map(&:class) }
t("unixpair block") { UNIXSocket.pair { |x, y| x.write("a"); y.read(1) } }
uc.close; ua.close; us.close; File.delete(path)
t("unix connect fail") { begin; UNIXSocket.new(path); rescue SystemCallError => e; shown.call(e.message); end }
t("Socket.new") { so = Socket.new(:INET, :STREAM); so.bind(Addrinfo.tcp("127.0.0.1", 0)); so.listen(5); r = [so.local_address.ipv4?, so.getsockname.bytesize]; so.close; r }
t("Socket.tcp") { srv = TCPServer.new("127.0.0.1", 0); th = Thread.new { srv.accept.tap { |x| x.write("hi"); x.close } }; r = Socket.tcp("127.0.0.1", srv.addr[1]) { |so| so.read }; th.join; srv.close; r }
t("for_fd bad") { BasicSocket.for_fd(0) }
t("dnrl") { [BasicSocket.do_not_reverse_lookup, TCPSocket.do_not_reverse_lookup] }
t("new basic") { BasicSocket.new(1) }

__END__
ai tcp: #<Addrinfo: 127.0.0.1:80 TCP>
ai list: [#<Addrinfo: 127.0.0.1:80 TCP>, #<Addrinfo: 127.0.0.1:80 UDP>, #<Addrinfo: 127.0.0.1:80 SOCK_RAW>]
ai new arr: #<Addrinfo: 127.0.0.1:80 (localhost)>
ai new arr2: #<Addrinfo: 127.0.0.1:80 TCP>
ai pf: #<Addrinfo: [::1]:80 PF_INET>
ai short: #<Addrinfo: unknown address family 98>
ai short2: #<Addrinfo: ?.?.?.?:? (2 bytes for 16 bytes sockaddr_in)>
ai v4mapped: #<Addrinfo: 1.2.3.4>
ai marshal: #<Addrinfo: 127.0.0.1:80 TCP>
ai marshal dump: ["AF_INET", ["127.0.0.1", "80"], "PF_INET", "SOCK_STREAM", "IPPROTO_TCP", nil, nil]
ai unix rel: #<Addrinfo: UNIX:72:65:6c:20:70:61:74:68 SOCK_STREAM>
ai unknown proto: #<Addrinfo: 127.0.0.1 SOCK_STREAM UNKNOWN_PROTOCOL(99)>
ai preds: [true, false, false, true, true]
ai ip_unpack: ["::1", 53]
ai uninit: TypeError: uninitialized socket address
ai unix_path: "/tmp/x"
ai ivars: []
ai getnameinfo: ["127.0.0.1", "80"]
ai family_addrinfo: #<Addrinfo: 127.0.0.1:81 TCP>
sock getaddrinfo bad: Socket::ResolutionError: getaddrinfo: nodename nor servname provided, or not known
resolution error code: [Socket::ResolutionError, 8]
newline: SocketError: newline at the end of hostname
pack un: 106
unpack un: "/tmp/x"
unpack in wrong: ArgumentError: not an AF_INET/AF_INET6 sockaddr
getnameinfo arr: ["127.0.0.1", "80"]
getnameinfo str: ["127.0.0.1", "http"]
getnameinfo bad: TypeError: expecting String or Array
servbyname: [80, 53, 16]
servbyname bad: SocketError: no such service nope-nope/tcp
servbyport: "http"
servbyport bad: RangeError: integer 70000 too big to convert into `int16_t'
option inspect: [#<Socket::Option: UNSPEC SOCKET LINGER on 5sec>, #<Socket::Option: INET SOCKET RCVTIMEO 1.000005sec>, #<Socket::Option: INET6 IPV6 JOIN_GROUP ff02::1 lo0>, #<Socket::Option: INET IP ADD_MEMBERSHIP 224.0.0.1 0.0.0.0>, #<Socket::Option: INET SOCKET ERROR Connection refused (61)>, #<Socket::Option: UNIX level:0 PEERCRED "abc">, #<Socket::Option: INET TCP optname:999 "x">, #<Socket::Option: family:1234 level:5 optname:6 "x">]
option vals: [[3, 5], true, 44, [3, 5], 0, 65535, 128]
option int size: TypeError: size differ.  expected as sizeof(int)=4 but 8
option bad name: SocketError: unknown socket level option name: NOPE
option ivars: []
anc: [#<Socket::AncillaryData: UNIX SOCKET RIGHTS 3>, #<Socket::AncillaryData: INET IP RECVDSTADDR 127.0.0.1>, #<Socket::AncillaryData: INET IP PKTINFO 127.0.0.1 lo0 spec_dst:127.0.0.1>, #<Socket::AncillaryData: INET6 IPV6 PKTINFO ::1 lo0>]
anc vals: [[#<Addrinfo: 127.0.0.1>, 1, #<Addrinfo: 127.0.0.1>], [#<Addrinfo: ::1>, 1], true]
ifaddrs: [#<Socket::Ifaddr lo0 UP,LOOPBACK,RUNNING,MULTICAST LINK[lo0]>, #<Socket::Ifaddr lo0 UP,LOOPBACK,RUNNING,MULTICAST 127.0.0.1 netmask=255.?.?.? (5 bytes for 16 bytes sockaddr_in)>]
ip_address_list: [#<Addrinfo: 127.0.0.1>, #<Addrinfo: 127.0.2.2>, #<Addrinfo: 127.0.2.3>]
hostname: true
server addr: ["AF_INET", "127.0.0.1"]
server inspect: "#<TCPServer:fd N, AF_INET, 127.0.0.1, PORT>"
nonblock?: :none
sync binmode: [true, true, #<Encoding:BINARY (ASCII-8BIT)>]
accepted class: [TCPSocket, "127.0.0.1", "127.0.0.1"]
gets: "hello\n"
recv: "xyz"
getsockopt: #<Socket::Option: INET SOCKET TYPE SOCK_STREAM>
setsockopt: true
recv_nonblock: :wait_readable
recv_nonblock raise: IO::EAGAINWaitReadable: Resource temporarily unavailable - recvfrom(2) would block
read eof: ""
shutdown bad: SocketError: unknown shutdown argument: NOPE
refused: "Connection refused - connect(2) for \"127.0.0.1\" port N"
closed addr: IOError: closed stream
udp recvfrom: ["dgram", "AF_INET", "127.0.0.1"]
udp recvfrom_nonblock: IO::EAGAINWaitReadable: Resource temporarily unavailable - recvfrom(2) would block
unix addrs: "[\"PATH\", [\"AF_UNIX\", \"PATH\"], [\"AF_UNIX\", \"PATH\"], \"#<UNIXServer:PATH>\"]"
recv_io: [IO, true]
recvmsg: ["msg", Addrinfo, Socket::AncillaryData]
pair: [Socket, Socket]
unixpair block: "a"
unix connect fail: "No such file or directory - connect(2) for PATH"
Socket.new: [true, 16]
Socket.tcp: "hi"
for_fd bad: Errno::EBADF: Bad file descriptor - not a socket file descriptor
dnrl: [true, true]
new basic: NoMethodError: undefined method 'initialize' for an instance of BasicSocket
