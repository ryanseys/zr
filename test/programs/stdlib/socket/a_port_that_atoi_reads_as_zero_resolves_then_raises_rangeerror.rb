# Socket resolves a numeric port that atoi reads as zero (a multiple of
# 2**32) as no service, as ruby_getaddrinfo__darwin does. The Addrinfo's
# name then reads the port as a C int, which raises RangeError. glibc
# does the same; musl's getaddrinfo refuses a port past 65535.
require "socket"

[80, 2**32 - 1, 2**32, 2**33, -(2**32), 2**62].each do |port|
  info = Addrinfo.getaddrinfo("127.0.0.1", port, nil, :STREAM).first
  p [port, info.ip_port, info.inspect]
rescue RangeError, TypeError, SocketError => e
  p [port, e.class, e.message]
end

begin
  Socket.tcp_server_sockets("127.0.0.1", 2**33)
rescue RangeError, SocketError => e
  p e.message
end
