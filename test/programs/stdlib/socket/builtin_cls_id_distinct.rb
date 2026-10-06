# Each builtin class has its own class id. A boxed Addrinfo answers Addrinfo,
# not String. A boxed Socket::Option answers Socket::Option, not OpenStruct.
# A boxed Enumerator stays alive through GC.start and still answers `next`.
require "socket"

ai = Addrinfo.tcp("127.0.0.1", 8080)
p [ai][0].class

s = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
p [s.getsockopt(Socket::SOL_SOCKET, Socket::SO_TYPE)][0].class
s.close

held = [[1, 2, 3].each]
GC.start
p held[0].class
p held[0].next
p held[0].next
