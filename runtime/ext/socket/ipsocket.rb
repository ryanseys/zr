# frozen_string_literal: true

# ipsocket.c, tcpsocket.c, tcpserver.c and udpsocket.c: the sockets of
# the Internet families. A TCP client resolves its host and tries each
# address in the order the resolver answers, as init_inetsock_internal
# tries them.
class IPSocket < BasicSocket
  undef_method :getpeereid

  def inspect
    text = super
    return text if @fd.nil? || @closed

    sockaddr = Primitive.zr_sock_name(@fd, false)
    return text if sockaddr.is_a?(Integer) || sockaddr.bytesize < 2

    family = Socket.intern(Socket.sockaddr_family(sockaddr), /\AAF_/)
    return text if family.nil?

    shown = text.end_with?(">") ? text.byteslice(0, text.bytesize - 1) : text.dup
    shown << ", " << family
    answer = Primitive.zr_sock_getnameinfo(sockaddr, Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV, 3)
    shown << ", " << answer[0] << ", " << answer[1] unless answer.is_a?(Integer)
    text.end_with?(">") ? shown << ">" : shown
  end

  def addr(*args) = ip_address(false, args)

  def peeraddr(*args) = ip_address(true, args)

  def recvfrom(len, flags = nil, str = nil) = receive(:ip, len, flags, str)

  def self.getaddress(host) = Socket.make_ipaddr(Socket.resolve(host, nil, socktype: Socket::SOCK_STREAM)[0][3])

  private

  def ip_address(peer, args)
    Primitive.attr! :hidden
    norevlookup = args.empty? ? nil : Socket.norevlookup_flag(args[0])
    norevlookup = @norevlookup if norevlookup.nil?
    sockaddr = Primitive.zr_sock_name(descriptor, peer)
    Socket.syserr_fail(-sockaddr, peer ? "getpeername(2)" : "getsockname(2)") if sockaddr.is_a?(Integer)

    Socket.ipaddr(sockaddr, norevlookup)
  end

  # rsock_init_inetsock: this socket, connected to the remote host, or
  # for a server bound to it and listening.
  def init_inetsock(remote_host, remote_serv, local_host, local_serv, server, resolv_timeout = nil, connect_timeout = nil, open_timeout = nil)
    Primitive.attr! :hidden
    if !open_timeout.nil? && (!resolv_timeout.nil? || !connect_timeout.nil?)
      raise ArgumentError, "Cannot specify open_timeout along with connect_timeout or resolv_timeout"
    end

    starts_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    remote = Socket.resolve(remote_host, remote_serv, socktype: Socket::SOCK_STREAM, flags: server ? Socket::AI_PASSIVE : 0)
    local = Socket.resolve(local_host, local_serv, socktype: Socket::SOCK_STREAM) if !server && (!local_host.nil? || !local_serv.nil?)
    opened = false
    status = 0
    local_status = 0
    error = 0
    syscall = nil
    begin
      remote.each_with_index do |(family, socktype, protocol, sockaddr), i|
        bound = nil
        if local
          bound = local.find { |row| row[0] == family }
          if bound.nil?
            next if i < remote.size - 1 || status.negative?

            bound = local[0]
          end
        end
        status = Socket.socket_fd(family, socktype, protocol)
        syscall = "socket(2)"
        if status.negative?
          error = -status
          next
        end
        Socket.init_sock(self, status)
        opened = true
        if server
          Primitive.zr_sock_setsockopt(@fd, Socket::SOL_SOCKET, Socket::SO_REUSEADDR, [1].pack("i"))
          status = Primitive.zr_sock_bind(@fd, sockaddr)
          syscall = "bind(2)"
        else
          if bound
            Primitive.zr_sock_setsockopt(@fd, Socket::SOL_SOCKET, Socket::SO_REUSEADDR, [1].pack("i"))
            status = local_status = Primitive.zr_sock_bind(@fd, bound[3])
            syscall = "bind(2)"
          end
          timeout = connect_timeout
          unless open_timeout.nil?
            timeout = open_timeout - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - starts_at)
            raise IO::TimeoutError, "user specified timeout for #{Addrinfo.send(:build, sockaddr, Socket::PF_UNSPEC, 0, 0).inspect_sockaddr}" if timeout.negative?
          end
          if status >= 0
            errno = connect_to(sockaddr, timeout)
            status = errno ? -errno : 0
            syscall = "connect(2)"
          end
        end
        if status.negative?
          error = -status
          close
          opened = false
          next
        end
        break
      end
      if status.negative?
        host, port = local_status.negative? ? [local_host, local_serv] : [remote_host, remote_serv]
        Socket.syserr_fail_host_port(error, syscall, host, port)
      end
      if server && opened
        result = Primitive.zr_sock_listen(@fd, Socket::SOMAXCONN)
        if result.negative?
          close
          opened = false
          Socket.syserr_fail(-result, "listen(2)")
        end
      end
      opened = false
      self
    ensure
      close if opened
    end
  end
end

class TCPSocket < IPSocket
  def initialize(remote_host, remote_serv, local_host = nil, local_serv = nil, resolv_timeout: nil, connect_timeout: nil, open_timeout: nil, fast_fallback: nil, test_mode_settings: nil)
    init_inetsock(remote_host, remote_serv, local_host, local_serv, false, resolv_timeout, connect_timeout, open_timeout)
  end

  def self.gethostbyname(host)
    Socket.warning("TCPSocket.gethostbyname is deprecated; use Addrinfo.getaddrinfo instead.")
    rows = Socket.resolve(host, nil, socktype: Socket::SOCK_STREAM, flags: Socket::AI_CANONNAME)
    Socket.make_hostent(host, rows) { |sockaddr| Socket.make_ipaddr(sockaddr) }
  end
end

class TCPServer < TCPSocket
  def initialize(hostname = nil, port)
    init_inetsock(hostname, port, nil, nil, true)
  end

  def accept = accept_as(TCPSocket)[0]

  def sysaccept = accept_as(nil)[0]

  def listen(backlog) = Socket.listen_on(self, backlog)

  private

  def __accept_nonblock(exception)
    answer = accept_nonblock_as(TCPSocket, exception)
    answer.is_a?(Symbol) ? answer : answer[0]
  end
end

class UDPSocket < IPSocket
  def initialize(family = nil)
    family = family.nil? ? Socket::AF_INET : Socket.family_arg(family)
    fd = Socket.socket_fd(family, Socket::SOCK_DGRAM, 0)
    Socket.syserr_fail(-fd, "socket(2) - udp") if fd.negative?

    Socket.init_sock(self, fd)
  end

  def connect(host, port)
    rows = Socket.resolve(host, port, family: descriptor_family, socktype: Socket::SOCK_DGRAM, socktype_hack: true)
    error = nil
    rows.each do |row|
      error = connect_to(row[3])
      return 0 if error.nil?
    end
    Socket.syserr_fail_host_port(error, "connect(2)", host, port)
  end

  def bind(host, port)
    rows = Socket.resolve(host, port, family: descriptor_family, socktype: Socket::SOCK_DGRAM, socktype_hack: true)
    error = nil
    rows.each do |row|
      result = Primitive.zr_sock_bind(descriptor, row[3])
      return 0 unless result.negative?

      error = -result
    end
    Socket.syserr_fail_host_port(error, "bind(2)", host, port)
  end

  def send(*args)
    return super if args.size == 2 || args.size == 3
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 4)" unless args.size == 4

    mesg, flags, host, port = args
    mesg = Primitive.zr_str_operand(mesg)
    fd = descriptor
    flags = Integer.send(:int_operand, flags)
    rows = Socket.resolve(host, port, family: descriptor_family, socktype: Socket::SOCK_DGRAM, socktype_hack: true)
    error = nil
    rows.each do |row|
      loop do
        check_open
        sent = Primitive.zr_sock_send(fd, mesg, flags, row[3])
        return sent unless sent.negative?

        error = -sent
        break unless maybe_wait(error, IO::WRITABLE)
      end
    end
    Socket.syserr_fail_host_port(error, "sendto(2)", host, port)
  end

  private

  def __recvfrom_nonblock(len, flags, str, exception) = receive_nonblock(:ip, len, flags, str, exception)

  # rsock_fd_family: the family of the socket's own address, AF_UNSPEC
  # when it has none to ask.
  def descriptor_family
    Primitive.attr! :hidden
    sockaddr = @fd.nil? ? -1 : Primitive.zr_sock_name(@fd, false)
    sockaddr.is_a?(Integer) ? Socket::AF_UNSPEC : Socket.sockaddr_family(sockaddr)
  end
end
