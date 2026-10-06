# A handle read out of a container arrives boxed, and the boxed value keeps
# all its methods: each Addrinfo and Socket::Option reader works on it. Each
# of these names belongs to exactly one builtin handle class, so the name
# alone identifies the receiver. The runtime class is checked first, so a
# value of any other kind still raises.
require "socket"

a = [Addrinfo.tcp("127.0.0.1", 8080)]
p a[0].class
p a[0].ip_port
p a[0].ip_address
p a[0].ipv4?
p a[0].ipv6?
p a[0].socktype == Socket::SOCK_STREAM

s = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
o = [s.getsockopt(Socket::SOL_SOCKET, Socket::SO_TYPE)]
p o[0].class
p o[0].int == Socket::SOCK_STREAM
s.close

# a value of another kind reaching one of these names still raises, naming
# its own class -- the face never dereferences on the strength of the name
begin
  [42][0].ip_port
rescue NoMethodError
  puts "NoMethodError"
end

# and a user class that defines the name keeps it
class Opt
  def level = "mine"
end
p [Opt.new][0].level
