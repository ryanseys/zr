# frozen_string_literal: true

# socket.c: Socket itself, a descriptor of any family and kind, and the
# resolver's and the address packer's class methods.
class Socket < BasicSocket
  # union_sockaddr's size, the most bytes an address may hold.
  SOCKADDR_MAX = 2048
  private_constant :SOCKADDR_MAX

  Primitive.zr_hidden_set(self, :tcp_fast_fallback, ENV["RUBY_TCP_NO_FAST_FALLBACK"].nil? || ENV["RUBY_TCP_NO_FAST_FALLBACK"] == "0")

  def initialize(domain, type, protocol = nil)
    domain = Socket.family_arg(domain)
    type = Socket.socktype_arg(type)
    fd = Socket.socket_fd(domain, type, Integer.send(:int_operand, protocol.nil? ? 0 : protocol))
    Socket.syserr_fail(-fd, "socket(2)") if fd.negative?

    Socket.init_sock(self, fd)
  end

  def connect(addr)
    sockaddr, addrinfo = Socket.sockaddr_string(addr)
    errno = connect_to(sockaddr.dup.freeze)
    Socket.syserr_fail_sockaddr(errno, "connect(2)", sockaddr, addrinfo) if errno

    0
  end

  def bind(addr)
    sockaddr, addrinfo = Socket.sockaddr_string(addr)
    result = Primitive.zr_sock_bind(descriptor, sockaddr)
    Socket.syserr_fail_sockaddr(-result, "bind(2)", sockaddr, addrinfo) if result.negative?

    0
  end

  def listen(backlog) = Socket.listen_on(self, backlog)

  def accept
    peer, sockaddr = accept_as(Socket)
    [peer, Socket.fd_socket_addrinfo(peer.fileno, sockaddr)]
  end

  def sysaccept
    fd, sockaddr = accept_as(nil)
    [fd, Socket.fd_socket_addrinfo(fd, sockaddr)]
  end

  def recvfrom(len, flags = nil, str = nil) = receive(:socket, len, flags, str)

  private

  def __connect_nonblock(addr, exception)
    sockaddr, addrinfo = Socket.sockaddr_string(addr)
    answer = Primitive.zr_sock_connect(descriptor, sockaddr)
    return 0 if answer.zero?

    errno = -answer
    if errno == Errno::EINPROGRESS::Errno
      return :wait_writable if exception == false

      Socket.wait_fail(errno, :writable, "connect(2) would block")
    end
    return 0 if errno == Errno::EISCONN::Errno && exception == false

    Socket.syserr_fail_sockaddr(errno, "connect(2)", sockaddr, addrinfo)
  end

  def __accept_nonblock(exception)
    answer = accept_nonblock_as(Socket, exception)
    return answer if answer.is_a?(Symbol)

    peer, sockaddr = answer
    [peer, Socket.fd_socket_addrinfo(peer.fileno, sockaddr)]
  end

  def __recvfrom_nonblock(len, flags, str, exception) = receive_nonblock(:socket, len, flags, str, exception)

  class << self
    def tcp_fast_fallback = Primitive.zr_hidden_get(Socket, :tcp_fast_fallback)

    def tcp_fast_fallback=(value)
      Primitive.zr_hidden_set(Socket, :tcp_fast_fallback, value)
    end

    def socketpair(domain, type, protocol = nil, &block) = Socket.make_pair(self, domain, type, protocol, &block)

    alias pair socketpair

    def gethostname
      name = Primitive.zr_sock_hostname
      Socket.syserr_fail(-name, "gethostname(3)") if name.is_a?(Integer)

      name
    end

    def gethostbyname(host)
      Socket.warning("Socket.gethostbyname is deprecated; use Addrinfo.getaddrinfo instead.")
      rows = Socket.resolve(host, nil, socktype: SOCK_STREAM, flags: AI_CANONNAME)
      Socket.make_hostent(host, rows) do |sockaddr|
        case Socket.sockaddr_family(sockaddr)
        when AF_INET then sockaddr.byteslice(4, 4)
        when AF_INET6 then sockaddr.byteslice(8, 16)
        else raise SocketError, "unknown socket family:#{Socket.sockaddr_family(sockaddr)}"
        end
      end
    end

    def gethostbyaddr(addr, family = nil)
      Socket.warning("Socket.gethostbyaddr is deprecated; use Addrinfo#getnameinfo instead.")
      addr = Primitive.zr_str_operand(addr)
      type = if family then Socket.family_arg(family)
             elsif addr.bytesize == 16 then AF_INET6
             else AF_INET
             end
      host = Primitive.zr_sock_host_by_addr(addr, type)
      raise SocketError, host if host.is_a?(String)

      host
    end

    def getservbyname(service, proto = nil)
      name = Socket.cstr(service)
      protocol = proto.nil? ? "tcp" : Socket.cstr(proto)
      port = Primitive.zr_sock_service_port(name, protocol)
      return port if port

      Socket.strtoul(name) or raise SocketError, "no such service #{name}/#{protocol}"
    end

    def getservbyport(port, proto = nil)
      number = Primitive.zr_index_operand_m(port)
      raise RangeError, "integer #{number} too #{number.positive? ? "big" : "small"} to convert into `int16_t'" unless number.between?(0, 0xffff)

      protocol = proto.nil? ? "tcp" : Socket.cstr(proto)
      Primitive.zr_sock_service_name(number, protocol) or raise SocketError, "no such service for port #{number}/#{protocol}"
    end

    def getaddrinfo(host, port, family = nil, socktype = nil, protocol = nil, flags = nil, reverse_lookup = nil)
      rows = Socket.resolve(host, port,
                             family: family.nil? ? PF_UNSPEC : Socket.family_arg(family),
                             socktype: socktype.nil? ? 0 : Socket.socktype_arg(socktype),
                             protocol: protocol.nil? ? 0 : Integer.send(:int_operand, protocol),
                             flags: flags.nil? ? 0 : Integer.send(:int_operand, flags))
      norevlookup = Socket.norevlookup_flag(reverse_lookup)
      norevlookup = BasicSocket.do_not_reverse_lookup if norevlookup.nil?
      rows.map do |af, kind, proto, sockaddr, canonical|
        row = Socket.ipaddr(sockaddr, norevlookup)
        row[2] = canonical if canonical
        row.push(af, kind, proto)
      end
    end

    def getnameinfo(sockaddr, flags = nil)
      flags = flags.nil? ? 0 : Integer.send(:int_operand, flags)
      text = sockaddr.is_a?(Addrinfo) ? sockaddr.to_sockaddr : String.try_convert(sockaddr)
      unless text.nil?
        raise TypeError, "sockaddr length too big" if text.bytesize > SOCKADDR_MAX
        raise TypeError, "sockaddr size differs - should not happen" unless text.bytesize >= 1 && text.getbyte(0) == text.bytesize

        return Socket.nameinfo(text, flags)
      end

      list = Array.try_convert(sockaddr)
      raise TypeError, "expecting String or Array" if list.nil?

      raise ArgumentError, "array size should be 3 or 4, #{list.size} given" if list.size < 3

      af, port, host = list
      hints = 0
      # A fourth element is the host as digits already, which needs no
      # resolving.
      if list.size >= 4 && !list[3].nil?
        host = list[3]
        hints = AI_NUMERICHOST
      end
      rows = Socket.resolve(host, port, family: af.nil? ? PF_UNSPEC : Socket.family_arg(af),
                                        socktype: (flags & NI_DGRAM).zero? ? SOCK_STREAM : SOCK_DGRAM, flags: hints)
      answer = Socket.nameinfo(rows[0][3], flags)
      rows.drop(1).each do |row|
        raise SocketError, "sockaddr resolved to multiple nodename" unless Socket.nameinfo(row[3], flags) == answer
      end
      answer
    end

    def pack_sockaddr_in(port, host) = Socket.resolve(host, port, socktype_hack: true)[0][3]

    alias sockaddr_in pack_sockaddr_in

    def unpack_sockaddr_in(addr)
      sockaddr, = Socket.sockaddr_string(addr)
      raise ArgumentError, "too short sockaddr" if sockaddr.bytesize < 2
      raise ArgumentError, "not an AF_INET/AF_INET6 sockaddr" unless [AF_INET, AF_INET6].include?(Socket.sockaddr_family(sockaddr))

      [sockaddr.byteslice(2, 2).unpack1("n"), Socket.make_ipaddr(sockaddr)]
    end

    def pack_sockaddr_un(path)
      path = Primitive.zr_str_operand(path)
      raise ArgumentError, "too long unix socket path (#{path.bytesize} bytes given but #{UNIX_PATH_MAX} bytes max)" if path.bytesize > UNIX_PATH_MAX

      Socket.pack_unix(path)
    end

    alias sockaddr_un pack_sockaddr_un

    def unpack_sockaddr_un(addr)
      sockaddr, = Socket.sockaddr_string(addr)
      raise ArgumentError, "too short sockaddr" if sockaddr.bytesize < 2
      raise ArgumentError, "not an AF_UNIX sockaddr" unless Socket.sockaddr_family(sockaddr) == AF_UNIX
      raise TypeError, "too long sockaddr_un - #{sockaddr.bytesize} longer than #{UNIX_PATH_MAX + 2}" if sockaddr.bytesize > UNIX_PATH_MAX + 2

      Socket.unixpath(sockaddr)
    end

    def ip_address_list
      Socket.ifaddr_rows.filter_map do |_, _, sockaddr|
        Socket.sockaddr_obj(sockaddr) if sockaddr && [AF_INET, AF_INET6].include?(Socket.sockaddr_family(sockaddr))
      end
    end

    # rsock_sock_listen, which Socket, TCPServer and UNIXServer share.
    def listen_on(socket, backlog)
      Primitive.attr! :hidden
      backlog = Integer.send(:int_operand, backlog)
      result = Primitive.zr_sock_listen(socket.__send__(:descriptor), backlog)
      Socket.syserr_fail(-result, "listen(2)") if result.negative?

      0
    end

    # rsock_sock_s_socketpair: two connected sockets of `klass`, which a
    # block has and both close after.
    def make_pair(klass, domain, type, protocol)
      Primitive.attr! :hidden
      domain = Socket.family_arg(domain)
      type = Socket.socktype_arg(type)
      fds = Primitive.zr_sock_socketpair(domain, type, Integer.send(:int_operand, protocol.nil? ? 0 : protocol))
      Socket.syserr_fail(-fds, "socketpair(2)") if fds.is_a?(Integer)

      pair = fds.map { |fd| Socket.new_sock(klass, fd) }
      return pair unless block_given?

      begin
        begin
          yield pair
        ensure
          Socket.close_quietly(pair[1])
        end
      ensure
        Socket.close_quietly(pair[0])
      end
    end

    # io_close: a close whose failure is no one's concern.
    def close_quietly(io)
      Primitive.attr! :hidden
      io.close
    rescue StandardError
      nil
    end

    # rb_warn.
    def warning(message)
      Primitive.attr! :hidden
      Warning.warn("#{Primitive.zr_warn_position}warning: #{message}\n") unless $VERBOSE.nil?
    end

    # strtoul(3) in base 0, as a service written as a number is read:
    # nil unless it reads to the end.
    def strtoul(text)
      Primitive.attr! :hidden
      match = /\A\s*([-+])?(?:0[xX](\h+)|(0[0-7]*)|([1-9]\d*))/.match(text)
      return (text.empty? ? 0 : nil) if match.nil?
      return nil unless match.post_match.empty?

      value = if match[2] then match[2].to_i(16)
              elsif match[3] then match[3].to_i(8)
              else match[4].to_i
              end
      match[1] == "-" ? -value : value
    end

    # rsock_make_hostent: [name, aliases, family, address...], each
    # address as the block writes it.
    def make_hostent(host, rows)
      Primitive.attr! :hidden
      canonical = rows[0][4]
      name = canonical || Socket.host_str(host)[0]
      aliases = canonical && canonical.bytesize < NI_MAXHOST ? Primitive.zr_sock_host_aliases(canonical) : nil
      [name, aliases || [], rows[0][0], *rows.map { |row| yield row[3] }]
    end

    # getifaddrs(3)'s rows, or its error.
    def ifaddr_rows
      Primitive.attr! :hidden
      rows = Primitive.zr_sock_ifaddrs
      Socket.syserr_fail(-rows, "getifaddrs") if rows.is_a?(Integer)

      rows
    end

    # sockaddr_obj: an interface's address as an Addrinfo. Under KAME a
    # link-local IPv6 address contains its scope in its second word, and
    # this moves it to the scope field.
    def sockaddr_obj(sockaddr)
      Primitive.attr! :hidden
      if KAME && sockaddr_family(sockaddr) == AF_INET6 && sockaddr.bytesize >= 28
        sockaddr = sockaddr.byteslice(0, 28)
        scope = sockaddr.byteslice(24, 4).unpack1("L")
        high, low = sockaddr.getbyte(10), sockaddr.getbyte(11)
        if sockaddr.getbyte(8) == 0xfe && (sockaddr.getbyte(9) & 0xc0) == 0x80 && scope.zero? && (high.nonzero? || low.nonzero?)
          sockaddr = sockaddr.byteslice(0, 10) + "\0\0" + sockaddr.byteslice(12, 12) + [(high << 8) | low].pack("L")
        end
      end
      Addrinfo.send(:build, sockaddr, sockaddr_family(sockaddr), 0, 0)
    end
  end
end
