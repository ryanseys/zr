# Addrinfo's family predicates (`ipv4?`, `ipv6?`, `unix?`, `ip?`) answer by
# the address family, for each constructor and for a handle's own address.
require "socket"

v4 = Addrinfo.tcp("127.0.0.1", 80)
puts "#{v4.ipv4?} #{v4.ipv6?} #{v4.unix?} #{v4.ip?}"

v6 = Addrinfo.udp("::1", 53)
puts "#{v6.ipv4?} #{v6.ipv6?} #{v6.unix?} #{v6.ip?}"

un = Addrinfo.unix("/tmp/spinel_afp.sock")
puts "#{un.ipv4?} #{un.ipv6?} #{un.unix?} #{un.ip?}"

# through a handle's own address, not just the constructors
srv = TCPServer.new("127.0.0.1", 0)
la = srv.local_address
puts "#{la.ipv4?} #{la.ipv6?} #{la.unix?} #{la.ip?}"
srv.close
