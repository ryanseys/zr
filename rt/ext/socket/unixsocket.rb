# frozen_string_literal: true

# unixsocket.c and unixserver.c: sockets named by a path, which can also
# hand a descriptor to the process at the other end.
class UNIXSocket < BasicSocket
  # The bytes of a cmsghdr here, and of one that carries one int, which
  # CMSG_LEN and CMSG_SPACE agree on.
  CMSG_HEADER = 12
  CMSG_INT = 16
  private_constant :CMSG_HEADER, :CMSG_INT

  def initialize(path)
    init_unixsock(path, false)
  end

  def path
    fd = descriptor
    if @path.nil?
      sockaddr = Primitive.zr_sock_name(fd, false)
      Socket.syserr_fail_path(-sockaddr, "getsockname(2)", @path) if sockaddr.is_a?(Integer)

      @path = Socket.unixpath(sockaddr).freeze
    end
    @path.dup
  end

  def addr = unix_address(false, "getsockname(2)")

  def peeraddr = unix_address(true, "getpeername(2)")

  def recvfrom(len, flags = nil, str = nil) = receive(:unix, len, flags, str)

  # unix_send_io: one byte of data, and the descriptor in SCM_RIGHTS.
  def send_io(io)
    fd = if io.is_a?(IO) then io.fileno
         elsif Primitive.zr_fixnum_p_m(io) then Integer.send(:int_operand, io)
         else raise TypeError, "neither IO nor file descriptor"
         end
    own = descriptor
    control = [CMSG_INT, Socket::SOL_SOCKET, Socket::SCM_RIGHTS, fd].pack("Liii")
    loop do
      sent = Primitive.zr_sock_sendmsg(own, "\0".b, 0, nil, control)
      return nil unless sent.negative?
      next if wait_io?(-sent, IO::WRITABLE)

      Socket.syserr_fail_path(-sent, "sendmsg(2)", @path)
    end
  end

  # unix_recv_io: the descriptor the other end sent, as `klass.for_fd`
  # makes it, or as a number when `klass` is nil.
  def recv_io(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

    klass = args.empty? ? IO : args[0]
    mode = args[1]
    retried = []
    loop do
      answer = Primitive.zr_sock_recvmsg(descriptor, 1, 0, CMSG_INT)
      if answer.is_a?(Integer)
        errno = -answer
        if errno == Errno::EMSGSIZE::Errno || errno == Errno::ENOMEM::Errno
          unless retried.include?(errno)
            retried << errno
            GC.start
            next
          end
        end
        next if wait_io?(errno, IO::READABLE)

        Socket.syserr_fail_path(errno, "recvmsg(2)", @path)
      end
      control = answer[3]
      if control.bytesize < CMSG_HEADER
        unless retried.include?(:truncate)
          retried << :truncate
          GC.start
          next
        end
        raise SocketError, "file descriptor was not passed (msg_controllen=#{control.bytesize} smaller than sizeof(struct cmsghdr)=#{CMSG_HEADER})"
      end
      length, level, type = control.unpack("Lii")
      raise SocketError, "file descriptor was not passed (cmsg_level=#{level}, #{Socket::SOL_SOCKET} expected)" unless level == Socket::SOL_SOCKET
      raise SocketError, "file descriptor was not passed (cmsg_type=#{type}, #{Socket::SCM_RIGHTS} expected)" unless type == Socket::SCM_RIGHTS
      raise SocketError, "file descriptor was not passed (msg_controllen=#{control.bytesize} smaller than CMSG_LEN(sizeof(int))=#{CMSG_INT})" if control.bytesize < CMSG_INT
      raise SocketError, "file descriptor was not passed (msg_controllen=#{control.bytesize} bigger than CMSG_SPACE(sizeof(int))=#{CMSG_INT})" if control.bytesize > CMSG_INT

      unless length == CMSG_INT
        Socket.discard_rights(control)
        raise SocketError, "file descriptor was not passed (cmsg_len=#{length}, #{CMSG_INT} expected)"
      end
      fd = control.byteslice(CMSG_HEADER, 4).unpack1("i")
      Primitive.zr_io_cloexec(fd)
      return fd if klass.nil?

      return mode.nil? ? klass.for_fd(fd) : klass.for_fd(fd, mode)
    end
  end

  class << self
    def socketpair(*args, &block)
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

      type = args.empty? ? Socket::SOCK_STREAM : args[0]
      protocol = args.size <= 1 ? 0 : args[1]
      Socket.make_pair(self, Socket::PF_UNIX, type, protocol, &block)
    end

    alias pair socketpair
  end

  private

  def unix_address(peer, call)
    Primitive.attr! :hidden
    sockaddr = Primitive.zr_sock_name(descriptor, peer)
    Socket.syserr_fail_path(-sockaddr, call, @path) if sockaddr.is_a?(Integer)

    Socket.unixaddr(sockaddr)
  end

  # rsock_init_unixsock: this socket, connected to the path, or for a
  # server bound to it and listening.
  def init_unixsock(path, server)
    Primitive.attr! :hidden
    path = File.path(path)
    raise ArgumentError, "too long unix socket path (#{path.bytesize}bytes given but 104bytes max)" if path.bytesize > 104

    sockaddr = Socket.pack_unix(path)
    fd = Socket.socket_fd(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
    Socket.syserr_fail_path(-fd, "socket(2)", path) if fd.negative?

    Socket.init_sock(self, fd)
    errno = if server
              result = Primitive.zr_sock_bind(fd, sockaddr)
              result.negative? ? -result : nil
            else
              begin
                connect_to(sockaddr)
              rescue Exception # rubocop:disable Lint/RescueException
                close
                raise
              end
            end
    if errno
      close
      Socket.syserr_fail_path(errno, "connect(2)", path)
    end
    return self unless server

    result = Primitive.zr_sock_listen(fd, Socket::SOMAXCONN)
    if result.negative?
      close
      Socket.syserr_fail_path(-result, "listen(2)", path)
    end
    @path = path.dup.freeze
    self
  end
end

class UNIXServer < UNIXSocket
  def initialize(path)
    init_unixsock(path, true)
  end

  def accept = accept_as(UNIXSocket)[0]

  def sysaccept = accept_as(nil)[0]

  def listen(backlog) = Socket.listen_on(self, backlog)

  private

  def __accept_nonblock(exception)
    answer = accept_nonblock_as(UNIXSocket, exception)
    answer.is_a?(Symbol) ? answer : answer[0]
  end
end
