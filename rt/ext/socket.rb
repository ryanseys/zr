# frozen_string_literal: true

# Sockets: a descriptor with an address family, so every stream socket
# reads and writes as an IO does. An address crosses into the kernel as
# a packed sockaddr, which this file builds and reads.

class SocketError < StandardError; end

class BasicSocket < IO
  class << self
    def for_fd(fd) = new(fd, "r+")

    def do_not_reverse_lookup = @do_not_reverse_lookup.nil? ? true : @do_not_reverse_lookup

    def do_not_reverse_lookup=(flag)
      @do_not_reverse_lookup = flag
    end
  end

  def do_not_reverse_lookup = BasicSocket.do_not_reverse_lookup

  def do_not_reverse_lookup=(flag)
    flag
  end

  def recv(length, flags = 0)
    answer = Primitive.zr_sock_recv(fileno, length, flags)
    raise SystemCallError.new(nil, -answer) if answer.is_a?(Integer)

    answer || +""
  end

  def recv_nonblock(length, flags = 0, exception: true) = recv(length, flags | Socket::MSG_DONTWAIT)

  def send(text, flags = 0, sockaddr = nil)
    answer = sockaddr ? Primitive.zr_sock_sendto(fileno, text.to_str, flags, sockaddr) : Primitive.zr_sock_send(fileno, text.to_str, flags)
    raise SystemCallError.new(nil, -answer) if answer.negative?

    answer
  end

  def shutdown(how = Socket::SHUT_RDWR)
    answer = Primitive.zr_sock_shutdown(fileno, shutdown_number(how))
    raise SystemCallError.new(nil, -answer) unless answer.zero?

    0
  end

  def close_read = shutdown(Socket::SHUT_RD)

  def close_write = shutdown(Socket::SHUT_WR)

  def setsockopt(level, name, value)
    value = [value ? 1 : 0].pack("i") if value == true || value == false
    value = [value].pack("i") if value.is_a?(Integer)
    answer = Primitive.zr_sock_setsockopt(fileno, level_number(level), option_number(name), value.to_str)
    raise SystemCallError.new(nil, -answer) unless answer.zero?

    0
  end

  def getsockopt(level, name)
    answer = Primitive.zr_sock_getsockopt(fileno, level_number(level), option_number(name), 256)
    raise SystemCallError.new(nil, -answer) if answer.is_a?(Integer)

    Socket::Option.new(:UNSPEC, level_number(level), option_number(name), answer)
  end

  def getsockname
    answer = Primitive.zr_sock_getsockname(fileno)
    raise SystemCallError.new(nil, -answer) if answer.is_a?(Integer)

    answer
  end

  def getpeername
    answer = Primitive.zr_sock_getpeername(fileno)
    raise SystemCallError.new(nil, -answer) if answer.is_a?(Integer)

    answer
  end

  def local_address = Addrinfo.new(getsockname)

  def remote_address = Addrinfo.new(getpeername)

  private

  def shutdown_number(how)
    return how if how.is_a?(Integer)

    { "SHUT_RD" => 0, "SHUT_WR" => 1, "SHUT_RDWR" => 2, "RD" => 0, "WR" => 1, "RDWR" => 2 }.fetch(how.to_s)
  end

  def level_number(level)
    return level if level.is_a?(Integer)

    { "SOL_SOCKET" => Socket::SOL_SOCKET, "SOCKET" => Socket::SOL_SOCKET,
      "IPPROTO_TCP" => Socket::IPPROTO_TCP, "TCP" => Socket::IPPROTO_TCP,
      "IPPROTO_IP" => Socket::IPPROTO_IP, "IP" => Socket::IPPROTO_IP,
      "IPPROTO_IPV6" => Socket::IPPROTO_IPV6, "IPV6" => Socket::IPPROTO_IPV6 }.fetch(level.to_s)
  end

  def option_number(name)
    return name if name.is_a?(Integer)

    text = name.to_s
    Socket::Constants.const_get(text.start_with?("SO_", "TCP_", "IP_", "IPV6_") ? text : "SO_#{text}")
  end
end

class Socket < BasicSocket
  module Constants
    AF_UNSPEC = 0
    AF_UNIX = 1
    AF_LOCAL = 1
    AF_INET = 2
    AF_INET6 = 30
    PF_UNSPEC = 0
    PF_UNIX = 1
    PF_INET = 2
    PF_INET6 = 30
    SOCK_STREAM = 1
    SOCK_DGRAM = 2
    SOCK_RAW = 3
    IPPROTO_IP = 0
    IPPROTO_ICMP = 1
    IPPROTO_TCP = 6
    IPPROTO_UDP = 17
    IPPROTO_IPV6 = 41
    SOL_SOCKET = 0xffff
    SO_DEBUG = 0x0001
    SO_REUSEADDR = 0x0004
    SO_KEEPALIVE = 0x0008
    SO_DONTROUTE = 0x0010
    SO_BROADCAST = 0x0020
    SO_LINGER = 0x0080
    SO_OOBINLINE = 0x0100
    SO_REUSEPORT = 0x0200
    SO_SNDBUF = 0x1001
    SO_RCVBUF = 0x1002
    SO_SNDTIMEO = 0x1005
    SO_RCVTIMEO = 0x1006
    SO_ERROR = 0x1007
    SO_TYPE = 0x1008
    TCP_NODELAY = 0x01
    IPV6_V6ONLY = 27
    SHUT_RD = 0
    SHUT_WR = 1
    SHUT_RDWR = 2
    MSG_OOB = 0x1
    MSG_PEEK = 0x2
    MSG_DONTROUTE = 0x4
    MSG_WAITALL = 0x40
    AI_PASSIVE = 0x00000001
    AI_CANONNAME = 0x00000002
    AI_NUMERICHOST = 0x00000004
    AI_NUMERICSERV = 0x00001000
    AI_ADDRCONFIG = 0x00000400
    NI_NUMERICHOST = 0x00000002
    NI_NUMERICSERV = 0x00000008
    NI_NAMEREQD = 0x00000004
    INADDR_ANY = 0
    SOMAXCONN = 128
    MSG_DONTWAIT = 0x80
  end

  # ruby names every constant on Socket itself as well, which is what
  # the singleton methods below read.
  include Constants
  Constants.constants.each { |name| const_set(name, Constants.const_get(name)) }

  # A sockaddr's own bytes, per family, the way BSD lays them out: a
  # length, a family, then the address itself.
  IN_SIZE = 16
  IN6_SIZE = 28
  UN_SIZE = 106
  private_constant :IN_SIZE, :IN6_SIZE, :UN_SIZE

  class << self
    def pack_sockaddr_in(port, host)
      host = "0.0.0.0" if host.nil? || host == ""
      address = ip_bytes(host)
      return [IN_SIZE, AF_INET, port.to_i].pack("CCn") + address + ("\0" * 8) if address.bytesize == 4

      [IN6_SIZE, AF_INET6, port.to_i, 0].pack("CCnN") + address + [0].pack("N")
    end

    alias sockaddr_in pack_sockaddr_in

    def unpack_sockaddr_in(sockaddr)
      sockaddr = sockaddr.to_str
      family = sockaddr.getbyte(1)
      port = sockaddr.byteslice(2, 2).unpack1("n")
      case family
      when AF_INET then [port, ip_text(sockaddr.byteslice(4, 4))]
      when AF_INET6 then [port, ip_text(sockaddr.byteslice(8, 16))]
      else raise ArgumentError, "not an AF_INET/AF_INET6 sockaddr"
      end
    end

    def pack_sockaddr_un(path)
      path = path.to_str
      raise ArgumentError, "too long unix socket path (#{path.bytesize} bytes given but #{UN_SIZE - 3} bytes max)" if path.bytesize > UN_SIZE - 3

      [UN_SIZE, AF_UNIX].pack("CC") + path + ("\0" * (UN_SIZE - 2 - path.bytesize))
    end

    alias sockaddr_un pack_sockaddr_un

    def unpack_sockaddr_un(sockaddr)
      sockaddr = sockaddr.to_str
      raise ArgumentError, "not an AF_UNIX sockaddr" unless sockaddr.getbyte(1) == AF_UNIX

      sockaddr.byteslice(2, sockaddr.bytesize - 2).sub(/\0.*\z/m, "")
    end

    # Every address a host and service stand for, as ruby's rows:
    # [family name, port, host name, address, family, socktype, protocol].
    def getaddrinfo(host, service, family = nil, socktype = nil, protocol = nil, flags = nil, reverse_lookup: nil)
      rows = resolve(host, service, family, socktype, protocol, flags)
      rows.map do |af, type, proto, sockaddr, canonical|
        port, address = unpack_sockaddr_in(sockaddr)
        name = reverse_lookup ? getnameinfo(sockaddr).first : (canonical || address)
        [family_name(af), port, name, address, af, type, proto]
      end
    end

    def gethostname
      answer = Primitive.zr_sock_hostname
      raise SystemCallError.new(nil, -answer) if answer.is_a?(Integer)

      answer
    end

    def getnameinfo(sockaddr, flags = 0)
      sockaddr = pack_sockaddr_in(sockaddr[1], sockaddr[2]) if sockaddr.is_a?(Array)
      answer = Primitive.zr_sock_getnameinfo(sockaddr, flags)
      raise ResolutionError.new("getnameinfo: #{Primitive.zr_sock_gai_message(answer)}", answer) if answer.is_a?(Integer)

      answer
    end

    def getaddress(host) = getaddrinfo(host, nil, nil, SOCK_STREAM).first[3]

    def ip_address_list = getaddrinfo(gethostname, nil).map { |row| Addrinfo.new(pack_sockaddr_in(0, row[3])) }

    def pair(domain = AF_UNIX, type = SOCK_STREAM, protocol = 0)
      ends = Primitive.zr_sock_socketpair(family_number(domain), type, protocol)
      raise SystemCallError.new(nil, -ends) if ends.is_a?(Integer)

      ends.map { |fd| new(domain, type, protocol, fd: fd) }
    end

    alias socketpair pair

    def open(*args, &block) = new(*args, &block)

    # The rows getaddrinfo(3) answers, or the resolver's own message.
    def resolve(host, service, family, socktype, protocol, flags)
      host = host.to_str if host.respond_to?(:to_str)
      service = service.is_a?(Integer) ? service.to_s : service&.to_str
      rows = Primitive.zr_sock_getaddrinfo(host, service, family_number(family), socktype.to_i, protocol.to_i, flags.to_i)
      raise ResolutionError.new("getaddrinfo: #{Primitive.zr_sock_gai_message(rows)}", rows) if rows.is_a?(Integer)

      rows
    end

    def family_number(family)
      return 0 if family.nil?
      return family if family.is_a?(Integer)

      { "AF_UNSPEC" => AF_UNSPEC, "AF_INET" => AF_INET, "AF_INET6" => AF_INET6, "AF_UNIX" => AF_UNIX,
        "PF_UNSPEC" => AF_UNSPEC, "PF_INET" => AF_INET, "PF_INET6" => AF_INET6, "PF_UNIX" => AF_UNIX,
        "UNSPEC" => AF_UNSPEC, "INET" => AF_INET, "INET6" => AF_INET6, "UNIX" => AF_UNIX,
      }.fetch(family.to_s) { raise SocketError, "unknown socket domain: #{family}" }
    end

    def family_name(family)
      { AF_INET => "AF_INET", AF_INET6 => "AF_INET6", AF_UNIX => "AF_UNIX" }.fetch(family, "AF_UNSPEC")
    end

    # An IPv4 or IPv6 address as its own bytes.
    def ip_bytes(host)
      host = host.to_str
      return [host].pack("H*") if host.empty?
      return host.split(".").map(&:to_i).pack("C4") if /\A\d+\.\d+\.\d+\.\d+\z/.match?(host)
      return ipv6_bytes(host) if host.include?(":")

      ip_bytes(getaddrinfo(host, nil, nil, SOCK_STREAM).first[3])
    end

    def ipv6_bytes(host)
      host = host.sub(/%.*\z/, "")
      head, tail = host.split("::", 2)
      groups = ->(text) { text.to_s.empty? ? [] : text.split(":").map { |g| g.to_i(16) } }
      left = groups.call(head)
      right = groups.call(tail)
      raise SocketError, "not a valid IPv6 address: #{host}" if tail.nil? && left.size != 8

      (left + Array.new(8 - left.size - right.size, 0) + right).pack("n8")
    end

    def ip_text(bytes)
      return bytes.unpack("C4").join(".") if bytes.bytesize == 4

      groups = bytes.unpack("n8").map { |g| g.to_s(16) }
      shorten(groups)
    end

    # The longest run of zero groups becomes "::", as inet_ntop does.
    def shorten(groups)
      best = nil
      run = nil
      groups.each_with_index do |group, i|
        if group == "0"
          run ||= [i, 0]
          run[1] += 1
          best = run if best.nil? || run[1] > best[1]
        else
          run = nil
        end
      end
      return groups.join(":") if best.nil? || best[1] < 2

      head = groups[0, best[0]].join(":")
      tail = groups[(best[0] + best[1])..].join(":")
      "#{head}::#{tail}"
    end

    private :resolve, :family_number, :family_name, :ip_bytes, :ipv6_bytes, :ip_text, :shorten
  end

  # What the resolver refused, and the code it refused with.
  class ResolutionError < SocketError
    attr_reader :error_code

    def initialize(message = nil, error_code = nil)
      super(message)
      @error_code = error_code
    end
  end

  # One socket option's own bytes, which a caller reads as a number or
  # a flag.
  class Option
    attr_reader :family, :level, :optname, :data

    def initialize(family, level, optname, data)
      @family = family
      @level = level
      @optname = optname
      @data = data
    end

    def int = @data.unpack1("i")

    def bool = int != 0

    def to_s = @data

    def inspect = "#<Socket::Option: #{@family} level:#{@level} optname:#{@optname} #{@data.inspect}>"
  end

  # A descriptor of the kind asked for, or the system's refusal.
  private_class_method def self.open_descriptor(domain, type, protocol)
    fd = Primitive.zr_sock_socket(domain, type, protocol)
    raise SystemCallError.new(nil, -fd) if fd.negative?

    fd
  end

  def initialize(domain = AF_INET, type = SOCK_STREAM, protocol = 0, fd: nil)
    fd ||= Socket.send(:open_descriptor, Socket.send(:family_number, domain), type, protocol)
    super(fd, "r+")
    @domain = Socket.send(:family_number, domain)
  end

  def bind(sockaddr) = check(Primitive.zr_sock_bind(fileno, sockaddr_of(sockaddr)))

  def connect(sockaddr) = check(Primitive.zr_sock_connect(fileno, sockaddr_of(sockaddr)))

  def listen(backlog = 5) = check(Primitive.zr_sock_listen(fileno, backlog))

  def accept
    answer = Primitive.zr_sock_accept(fileno)
    raise SystemCallError.new(nil, -answer) if answer.is_a?(Integer)

    [Socket.new(@domain, SOCK_STREAM, 0, fd: answer[0]), Addrinfo.new(answer[1])]
  end

  def sysaccept
    socket, address = accept
    [socket.fileno, address]
  end

  def recvfrom(length, flags = 0)
    answer = Primitive.zr_sock_recvfrom(fileno, length, flags)
    raise SystemCallError.new(nil, -answer) if answer.is_a?(Integer)

    [answer[0], Addrinfo.new(answer[1])]
  end

  def send(text, flags = 0, sockaddr = nil)
    answer = sockaddr ? Primitive.zr_sock_sendto(fileno, text.to_str, flags, sockaddr_of(sockaddr)) : Primitive.zr_sock_send(fileno, text.to_str, flags)
    raise SystemCallError.new(nil, -answer) if answer.negative?

    answer
  end

  private

  def sockaddr_of(address) = address.is_a?(Addrinfo) ? address.to_sockaddr : address.to_str

  def check(answer)
    raise SystemCallError.new(nil, -answer) unless answer.zero?

    0
  end
end

# One resolved address: its family, its socket kind and where it points.
class Addrinfo
  attr_reader :socktype, :protocol

  def initialize(sockaddr, family = nil, socktype = 0, protocol = 0)
    @sockaddr = sockaddr.is_a?(Array) ? Socket.pack_sockaddr_in(sockaddr[1], sockaddr[2]) : sockaddr.to_str
    @family = family || @sockaddr.getbyte(1)
    @socktype = socktype
    @protocol = protocol
  end

  def self.tcp(host, port) = new(Socket.pack_sockaddr_in(port, host), nil, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)

  def self.udp(host, port) = new(Socket.pack_sockaddr_in(port, host), nil, Socket::SOCK_DGRAM, Socket::IPPROTO_UDP)

  def self.unix(path, socktype = Socket::SOCK_STREAM) = new(Socket.pack_sockaddr_un(path), Socket::AF_UNIX, socktype)

  def afamily = @family

  def pfamily = @family

  def to_sockaddr = @sockaddr

  alias to_s to_sockaddr

  def ip? = [Socket::AF_INET, Socket::AF_INET6].include?(@family)

  def ipv4? = @family == Socket::AF_INET

  def ipv6? = @family == Socket::AF_INET6

  def unix? = @family == Socket::AF_UNIX

  def ip_address = Socket.unpack_sockaddr_in(@sockaddr).last

  def ip_port = Socket.unpack_sockaddr_in(@sockaddr).first

  def unix_path = Socket.unpack_sockaddr_un(@sockaddr)

  def getnameinfo(flags = 0) = Socket.getnameinfo(@sockaddr, flags)

  def inspect = "#<Addrinfo: #{inspect_sockaddr}>"

  def inspect_sockaddr
    return unix_path if unix?

    ipv6? ? "[#{ip_address}]:#{ip_port}" : "#{ip_address}:#{ip_port}"
  end
end

class IPSocket < BasicSocket
  def addr(reverse_lookup = nil) = address_row(getsockname, reverse_lookup)

  def peeraddr(reverse_lookup = nil) = address_row(getpeername, reverse_lookup)

  def self.getaddress(host) = Socket.getaddress(host)

  private

  def address_row(sockaddr, reverse_lookup)
    port, address = Socket.unpack_sockaddr_in(sockaddr)
    family = sockaddr.getbyte(1) == Socket::AF_INET6 ? "AF_INET6" : "AF_INET"
    name = reverse_lookup ? Socket.getnameinfo(sockaddr).first : address
    [family, port, name, address]
  end
end

class TCPSocket < IPSocket
  def initialize(host, port, local_host = nil, local_port = nil, fd: nil)
    return super(fd, "r+") if fd

    row = Socket.getaddrinfo(host, port, nil, Socket::SOCK_STREAM).first
    raise SocketError, "getaddrinfo: nodename nor servname provided, or not known" if row.nil?

    descriptor = Socket.send(:open_descriptor, row[4], Socket::SOCK_STREAM, 0)
    super(descriptor, "r+")
    bind_local(local_host, local_port) if local_host || local_port
    connect_to(Socket.pack_sockaddr_in(row[1], row[3]))
  end

  def self.open(*args, &block)
    socket = new(*args)
    return socket unless block

    begin
      block.call(socket)
    ensure
      socket.close unless socket.closed?
    end
  end

  private

  def bind_local(host, port)
    answer = Primitive.zr_sock_bind(fileno, Socket.pack_sockaddr_in(port.to_i, host || "0.0.0.0"))
    raise SystemCallError.new(nil, -answer) unless answer.zero?
  end

  def connect_to(sockaddr)
    answer = Primitive.zr_sock_connect(fileno, sockaddr)
    raise SystemCallError.new(nil, -answer) unless answer.zero?
  end
end

class TCPServer < TCPSocket
  def initialize(host, port = nil)
    host, port = nil, host if port.nil?
    row = Socket.getaddrinfo(host || "0.0.0.0", port, nil, Socket::SOCK_STREAM, nil, Socket::AI_PASSIVE).first
    descriptor = Socket.send(:open_descriptor, row[4], Socket::SOCK_STREAM, 0)
    super(nil, nil, fd: descriptor)
    setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    answer = Primitive.zr_sock_bind(descriptor, Socket.pack_sockaddr_in(row[1], row[3]))
    raise SystemCallError.new(nil, -answer) unless answer.zero?

    listen(Socket::SOMAXCONN)
  end

  def listen(backlog = 5)
    answer = Primitive.zr_sock_listen(fileno, backlog)
    raise SystemCallError.new(nil, -answer) unless answer.zero?

    0
  end

  def accept
    answer = Primitive.zr_sock_accept(fileno)
    raise SystemCallError.new(nil, -answer) if answer.is_a?(Integer)

    TCPSocket.new(nil, nil, fd: answer[0])
  end

  def sysaccept = accept.fileno
end

class UDPSocket < IPSocket
  def initialize(family = Socket::AF_INET)
    @family = Socket.send(:family_number, family)
    super(Socket.send(:open_descriptor, @family, Socket::SOCK_DGRAM, 0), "r+")
  end

  def bind(host, port)
    answer = Primitive.zr_sock_bind(fileno, Socket.pack_sockaddr_in(port, host))
    raise SystemCallError.new(nil, -answer) unless answer.zero?

    0
  end

  def connect(host, port)
    answer = Primitive.zr_sock_connect(fileno, Socket.pack_sockaddr_in(port, host))
    raise SystemCallError.new(nil, -answer) unless answer.zero?

    0
  end

  def send(text, flags = 0, host = nil, port = nil)
    return super(text, flags) if host.nil?

    sockaddr = port ? Socket.pack_sockaddr_in(port, host) : host
    answer = Primitive.zr_sock_sendto(fileno, text.to_str, flags, sockaddr)
    raise SystemCallError.new(nil, -answer) if answer.negative?

    answer
  end

  def recvfrom(length, flags = 0)
    answer = Primitive.zr_sock_recvfrom(fileno, length, flags)
    raise SystemCallError.new(nil, -answer) if answer.is_a?(Integer)

    port, address = Socket.unpack_sockaddr_in(answer[1])
    [answer[0], [answer[1].getbyte(1) == Socket::AF_INET6 ? "AF_INET6" : "AF_INET", port, address, address]]
  end
end

class UNIXSocket < BasicSocket
  # The path this end is bound to, which a socket that only connected
  # has none of.
  def path = Socket.unpack_sockaddr_un(getsockname)

  def initialize(path, fd: nil)
    return super(fd, "r+") if fd

    descriptor = Socket.send(:open_descriptor, Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
    super(descriptor, "r+")
    answer = Primitive.zr_sock_connect(descriptor, Socket.pack_sockaddr_un(path))
    raise SystemCallError.new(path, -answer) unless answer.zero?
  end

  def addr = ["AF_UNIX", Socket.unpack_sockaddr_un(getsockname)]

  def peeraddr = ["AF_UNIX", Socket.unpack_sockaddr_un(getpeername)]

  def self.pair(type = Socket::SOCK_STREAM, protocol = 0)
    ends = Primitive.zr_sock_socketpair(Socket::AF_UNIX, type, protocol)
    raise SystemCallError.new(nil, -ends) if ends.is_a?(Integer)

    ends.map { |fd| new(nil, fd: fd) }
  end

  class << self
    alias socketpair pair
  end
end

class UNIXServer < UNIXSocket
  def initialize(path)
    descriptor = Socket.send(:open_descriptor, Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
    super(path, fd: descriptor)
    answer = Primitive.zr_sock_bind(descriptor, Socket.pack_sockaddr_un(path))
    raise SystemCallError.new(path, -answer) unless answer.zero?

    listen(Socket::SOMAXCONN)
  end

  def listen(backlog = 5)
    answer = Primitive.zr_sock_listen(fileno, backlog)
    raise SystemCallError.new(nil, -answer) unless answer.zero?

    0
  end

  def accept
    answer = Primitive.zr_sock_accept(fileno)
    raise SystemCallError.new(nil, -answer) if answer.is_a?(Integer)

    UNIXSocket.new(nil, fd: answer[0])
  end
end
