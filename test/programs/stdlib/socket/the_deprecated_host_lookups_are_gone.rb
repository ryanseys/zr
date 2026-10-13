# Socket.gethostbyname, Socket.gethostbyaddr and TCPSocket.gethostbyname
# are gone (ruby 4.1, #17944); Addrinfo takes their place.
require "socket"

p Socket.respond_to?(:gethostbyname)
p Socket.respond_to?(:gethostbyaddr)
p TCPSocket.respond_to?(:gethostbyname)
p IPSocket.respond_to?(:gethostbyname)
[-> { Socket.gethostbyname("localhost") },
 -> { Socket.gethostbyaddr([127, 0, 0, 1].pack("C4")) },
 -> { TCPSocket.gethostbyname("localhost") }].each do |f|
  f.call
rescue NoMethodError => e
  p [e.class, e.message, e.name]
end

# What stays: the host's name, and Addrinfo's lookups.
p Socket.gethostname.is_a?(String)
p Addrinfo.getaddrinfo("127.0.0.1", nil, :INET, :STREAM).map(&:ip_address).uniq
p Addrinfo.tcp("127.0.0.1", 80).ip_address
p Socket.getservbyname("http")
p Socket.getservbyport(80)
