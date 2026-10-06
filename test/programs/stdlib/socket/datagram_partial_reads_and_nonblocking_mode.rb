require "socket"
require "io/nonblock"
r = Socket.new(:INET, :DGRAM)
w = Socket.new(:INET, :DGRAM)
r.bind(Socket.pack_sockaddr_in(0, "127.0.0.1"))
w.send("aaa", 0, r.getsockname)
r.nonblock = false
IO.select([r], nil, nil, 2)
p r.read_nonblock(1), r.nonblock?
w.send("bbb", 0, r.getsockname)
IO.select([r], nil, nil, 2)
p r.read_nonblock(3)
w.send("ccc", 0, r.getsockname)
p r.readpartial(10)
d = Socket::AncillaryData.new(:INET, :IP, :TTL, "")
p((d.cmsg_is?(:IPV6, :RIGHTS) rescue $!), d.cmsg_is?(:IP, :TTL))
rd, wr = IO.pipe
wr.write("hello world")
p rd.readpartial(5), rd.readpartial(100), rd.nonblock?
wr.write_nonblock("x"); p wr.nonblock?, rd.read_nonblock(5)
