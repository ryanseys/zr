# frozen_string_literal: true

# basicsocket.c, and the receives, sends, accepts and connects that
# init.c makes for every socket class. A socket's descriptor returns
# EAGAIN rather than waiting, so each call that would wait waits here
# first, which lets another green thread run in the meantime.
class BasicSocket < IO
  # As rb_undef_method, a second load of this file undefines nothing.
  undef_method :initialize if private_method_defined?(:initialize)

  class << self
    # rsock_do_not_reverse_lookup, one flag for every socket class.
    def do_not_reverse_lookup = !Primitive.zr_hidden_get(BasicSocket, :reverse_lookup)

    def do_not_reverse_lookup=(flag)
      Primitive.zr_hidden_set(BasicSocket, :reverse_lookup, !flag)
      flag
    end

    # bsock_s_for_fd: a socket over a descriptor that must be one.
    def for_fd(descriptor)
      fd = Integer.send(:int_operand, descriptor)
      rows = Primitive.zr_fstat_m(fd)
      Socket.syserr_fail(-rows, "fstat(2)") if rows.is_a?(Integer)
      Socket.syserr_fail(Errno::EBADF::Errno, "not a socket file descriptor") unless rows[2] & 0o170000 == 0o140000

      Socket.new_sock(self, fd)
    end
  end

  def shutdown(how = nil)
    how = how.nil? ? Socket::SHUT_RDWR : Socket.shutdown_how_arg(how)
    raise ArgumentError, "`how' should be either :SHUT_RD, :SHUT_WR, :SHUT_RDWR" unless [Socket::SHUT_WR, Socket::SHUT_RD, Socket::SHUT_RDWR].include?(how)

    result = Primitive.zr_sock_shutdown(descriptor, how)
    Socket.syserr_fail(-result, "shutdown(2)") if result.negative?

    0
  end

  # A socket is one descriptor both ways: closing one way shuts that way
  # down, and closing the last way closes the socket.
  def close_read
    Primitive.zr_sock_shutdown(descriptor, Socket::SHUT_RD)
    return close unless @writable

    @readable = false
    nil
  end

  def close_write
    fd = descriptor
    return close unless @readable

    # bsock_close_write flushes the buffered output first, so the peer gets
    # it and a later close has nothing to write to the shut down side.
    write_pending
    Primitive.zr_sock_shutdown(fd, Socket::SHUT_WR)
    @writable = false
    nil
  end

  def setsockopt(*args)
    if args.size == 1
      option = args[0]
      level = option.level
      optname = option.optname
      value = option.data
    else
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 3)" unless args.size == 3

      level, optname, value = args
    end
    fd = descriptor
    family = socket_family
    level = Socket.level_arg(family, level)
    optname = Socket.optname_arg(family, level, optname)
    bytes = case value
            when true then [1].pack("i")
            when false then [0].pack("i")
            else Primitive.zr_fixnum_p_m(value) ? [Integer.send(:int_operand, value)].pack("i") : Primitive.zr_str_operand(value)
            end
    check_open
    result = Primitive.zr_sock_setsockopt(fd, level, optname, bytes)
    Socket.syserr_fail_path(-result, "setsockopt(2)", @path) if result.negative?

    0
  end

  def getsockopt(level, optname)
    fd = descriptor
    family = socket_family
    level = Socket.level_arg(family, level)
    optname = Socket.optname_arg(family, level, optname)
    check_open
    data = Primitive.zr_sock_getsockopt(fd, level, optname)
    Socket.syserr_fail_path(-data, "getsockopt(2)", @path) if data.is_a?(Integer)

    Socket::Option.send(:build, family, level, optname, data)
  end

  def getsockname = own_address(false, "getsockname(2)")

  def getpeername = own_address(true, "getpeername(2)")

  def getpeereid
    ids = Primitive.zr_os_peereid(descriptor)
    Socket.syserr_fail(-ids, "getpeereid(3)") if ids.is_a?(Integer)

    ids
  end

  def local_address = Socket.fd_socket_addrinfo(@fd, getsockname)

  def remote_address = Socket.fd_socket_addrinfo(@fd, getpeername)

  # rsock_bsock_send: the whole message, to an address when one is given.
  def send(mesg, flags, to = nil)
    mesg = Primitive.zr_str_operand(mesg)
    to, = Socket.sockaddr_string(to) unless to.nil?
    fd = descriptor
    flags = Integer.send(:int_operand, flags)
    loop do
      sent = Primitive.zr_sock_send(fd, mesg, flags, to)
      return sent unless sent.negative?
      next if maybe_wait(-sent, IO::WRITABLE)

      Socket.syserr_fail(-sent, to.nil? ? "send(2)" : "sendto(2)")
    end
  end

  def do_not_reverse_lookup
    descriptor
    @norevlookup
  end

  def do_not_reverse_lookup=(flag)
    descriptor
    @norevlookup = flag ? true : false
  end

  def recv(len, flags = nil, str = nil) = receive(:recv, len, flags, str)

  private

  def __recv_nonblock(len, flags, str, exception) = receive_nonblock(:recv, len, flags, str, exception)

  # rsock_getfamily: the family the socket's own address has, kept once
  # it is one of the three common ones.
  def socket_family
    Primitive.attr! :hidden
    return @family if @family

    sockaddr = Primitive.zr_sock_name(@fd, false)
    return Socket::AF_UNSPEC if sockaddr.is_a?(Integer) || sockaddr.bytesize < 2

    family = Socket.sockaddr_family(sockaddr)
    @family = family if [Socket::AF_UNIX, Socket::AF_INET, Socket::AF_INET6].include?(family)
    family
  end

  def own_address(peer, call)
    Primitive.attr! :hidden
    sockaddr = Primitive.zr_sock_name(descriptor, peer)
    Socket.syserr_fail(-sockaddr, call) if sockaddr.is_a?(Integer)

    sockaddr
  end

  # rsock_is_dgram.
  def dgram?
    Primitive.attr! :hidden
    type = Primitive.zr_sock_getsockopt(@fd, Socket::SOL_SOCKET, Socket::SO_TYPE)
    Socket.syserr_fail(-type, "getsockopt(SO_TYPE)") if type.is_a?(Integer)

    type.unpack1("i") == Socket::SOCK_DGRAM
  end

  # rsock_strbuf: the buffer a receive fills, a new one when none is
  # given.
  def receive_buffer(str)
    Primitive.attr! :hidden
    return nil if str.nil?

    str = Primitive.zr_str_operand(str)
    Primitive.zr_frozen_error(str) if str.frozen?
    str
  end

  # What a receive returns: the data, in the given buffer if any, and
  # for `recvfrom` the sender, as the socket's class represents one.
  def received(from, data, sockaddr, buffer)
    Primitive.attr! :hidden
    if buffer
      encoding = buffer.encoding
      data = buffer.replace(data).force_encoding(encoding)
    end
    case from
    when :recv then data
    when :ip then [data, sockaddr.empty? ? nil : Socket.ipaddr(sockaddr, @norevlookup)]
    when :unix then [data, Socket.unixaddr(sockaddr)]
    else [data, Socket.fd_socket_addrinfo(@fd, sockaddr)]
    end
  end

  # rsock_s_recvfrom.
  def receive(from, len, flags, str)
    Primitive.attr! :hidden
    flags = flags.nil? ? 0 : Integer.send(:int_operand, flags)
    length = Integer.send(:int_operand, len)
    buffer = receive_buffer(str)
    descriptor
    raise IOError, "recv for buffered IO" if buffered?

    loop do
      check_open
      answer = Primitive.zr_sock_recvfrom(@fd, length, flags)
      if answer.is_a?(Integer)
        next if maybe_wait(-answer, IO::READABLE)

        Socket.syserr_fail(-answer, "recvfrom(2)")
      end
      data, sockaddr = answer
      return nil if data.empty? && !dgram?

      return received(from, data, sockaddr, buffer)
    end
  end

  # rsock_s_recvfrom_nonblock.
  def receive_nonblock(from, len, flags, str, exception)
    Primitive.attr! :hidden
    flags = Integer.send(:int_operand, flags) | Socket::MSG_DONTWAIT
    length = Integer.send(:int_operand, len)
    buffer = receive_buffer(str)
    descriptor
    raise IOError, "recvfrom for buffered IO" if buffered?

    answer = Primitive.zr_sock_recvfrom(@fd, length, flags)
    if answer.is_a?(Integer)
      errno = -answer
      if errno == Errno::EAGAIN::Errno
        return :wait_readable if exception == false

        Socket.wait_fail(errno, :readable, "recvfrom(2) would block")
      end
      Socket.syserr_fail(errno, "recvfrom(2)")
    end
    data, sockaddr = answer
    return nil if data.empty? && !dgram?

    received(from, data, sockaddr, buffer)
  end

  # rsock_s_accept: the connection waiting on this server, as a socket
  # of `klass` or, with none, its descriptor; and the peer's address.
  def accept_as(klass)
    Primitive.attr! :hidden
    retried = false
    loop do
      answer = Primitive.zr_sock_accept(descriptor)
      unless answer.is_a?(Integer)
        fd, sockaddr = answer
        return [klass ? Socket.new_sock(klass, fd) : fd, sockaddr]
      end
      errno = -answer
      if [Errno::EMFILE::Errno, Errno::ENFILE::Errno, Errno::ENOMEM::Errno].include?(errno)
        unless retried
          GC.start
          retried = true
          next
        end
      elsif maybe_wait(errno, IO::READABLE)
        retried = false
        next
      end
      Socket.syserr_fail(errno, "accept(2)")
    end
  end

  # rsock_s_accept_nonblock.
  def accept_nonblock_as(klass, exception)
    Primitive.attr! :hidden
    answer = Primitive.zr_sock_accept(descriptor)
    unless answer.is_a?(Integer)
      fd, sockaddr = answer
      return [Socket.new_sock(klass, fd), sockaddr]
    end
    errno = -answer
    if [Errno::EAGAIN::Errno, Errno::ECONNABORTED::Errno, Errno::EPROTO::Errno].include?(errno)
      return :wait_readable if exception == false

      Socket.wait_fail(errno, :readable, "accept(2) would block")
    end
    Socket.syserr_fail(errno, "accept(2)")
  end

  # rsock_connect: nil once connected, else the errno the connection
  # failed with. A connection still under way is waited for, as long as
  # `timeout` allows.
  def connect_to(sockaddr, timeout = nil)
    Primitive.attr! :hidden
    answer = Primitive.zr_sock_connect(descriptor, sockaddr)
    return nil if answer.zero?

    errno = -answer
    return errno unless [Errno::EINTR::Errno, Errno::EAGAIN::Errno, Errno::EINPROGRESS::Errno].include?(errno)

    wait_connectable(sockaddr, timeout)
  end

  # wait_connectable.
  def wait_connectable(sockaddr, timeout)
    Primitive.attr! :hidden
    errno = pending_error
    return errno if [Errno::EALREADY::Errno, Errno::EISCONN::Errno, Errno::ECONNREFUSED::Errno, Errno::EHOSTUNREACH::Errno].include?(errno)

    unless wait_ready(IO::READABLE | IO::WRITABLE, timeout.nil? ? @timeout : timeout)
      raise IO::TimeoutError, "user specified timeout for #{Addrinfo.send(:build, sockaddr, Socket::PF_UNSPEC, 0, 0).inspect_sockaddr}"
    end

    errno = pending_error
    [0, Errno::EINTR::Errno, Errno::EAGAIN::Errno, Errno::EINPROGRESS::Errno, Errno::EALREADY::Errno, Errno::EISCONN::Errno].include?(errno) ? nil : errno
  end

  # SO_ERROR: what a connection under way failed with, or the errno of
  # asking.
  def pending_error
    Primitive.attr! :hidden
    bytes = Primitive.zr_sock_getsockopt(@fd, Socket::SOL_SOCKET, Socket::SO_ERROR)
    bytes.is_a?(Integer) ? -bytes : bytes.unpack1("i")
  end
end
