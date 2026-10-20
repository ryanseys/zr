# frozen_string_literal: true

# Derived from the C of CRuby and of its gems (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ancdata.c: the control messages that sendmsg and recvmsg send and
# receive, and the two calls themselves. A cmsghdr here is 12 bytes, and
# its data is padded to a multiple of 4.
class Socket < BasicSocket
  class AncillaryData
    def initialize(family, level, type, data)
      family = Socket.family_arg(family)
      level = Socket.level_arg(family, level)
      assign(family, level, Socket.cmsg_type_arg(family, level, type), data)
    end

    def family = Integer.send(:int_operand, @family)

    def level = Integer.send(:int_operand, @level)

    def type = Integer.send(:int_operand, @type)

    def data = Primitive.zr_str_operand(@data)

    def cmsg_is?(level, type)
      family = self.family
      level = Socket.level_arg(family, level)
      type = Socket.cmsg_type_arg(family, level, type)
      self.level == level && self.type == type
    end

    def int
      bytes = data
      raise TypeError, "size differ.  expected as sizeof(int)=4 but #{bytes.bytesize}" unless bytes.bytesize == 4

      bytes.unpack1("i")
    end

    def unix_rights
      raise TypeError, "SCM_RIGHTS ancillary data expected" unless level == SOL_SOCKET && type == SCM_RIGHTS

      @unix_rights
    end

    def timestamp
      bytes = data
      raise TypeError, "timestamp ancillary data expected" unless level == SOL_SOCKET && type == SCM_TIMESTAMP && bytes.bytesize == 16

      seconds, microseconds = bytes.unpack("q<l<")
      Time.at(seconds, microseconds)
    end

    def ip_pktinfo
      bytes = data
      raise TypeError, "IP_PKTINFO ancillary data expected" unless level == IPPROTO_IP && type == IP_PKTINFO && bytes.bytesize == 12

      ifindex = bytes.unpack1("L")
      [AncillaryData.in_addrinfo(bytes.byteslice(8, 4)), ifindex, AncillaryData.in_addrinfo(bytes.byteslice(4, 4))]
    end

    def ipv6_pktinfo = [ipv6_pktinfo_addr, ipv6_pktinfo_ifindex]

    def ipv6_pktinfo_addr
      bytes = ipv6_pktinfo_bytes
      ifindex = bytes.byteslice(16, 4).unpack1("L")
      addr = bytes.byteslice(0, 16)
      scope = addr.getbyte(0) == 0xfe && (addr.getbyte(1) & 0xc0) == 0x80 ? ifindex : 0
      Addrinfo.send(:build, Socket.sockaddr_head(AF_INET6, 28) + [0, 0].pack("nN") + addr + [scope].pack("L"), PF_INET6, 0, 0)
    end

    def ipv6_pktinfo_ifindex = ipv6_pktinfo_bytes.byteslice(16, 4).unpack1("L")

    def inspect
      family = self.family
      level = self.level
      type = self.type
      bytes = data
      text = +"#<#{Primitive.zr_class_path(Primitive.zr_real_class(self))}:"
      text << ((name = Socket.intern(family, /\AAF_/, "AF_")) ? " #{name}" : " family:#{family}")
      if level == SOL_SOCKET
        text << " SOCKET" << ((name = Socket.intern(type, /\ASCM_/, "SCM_")) ? " #{name}" : " cmsg_type:#{type}")
      elsif Socket.ip_family?(family)
        text << ((name = Socket.intern(level, /\A(SOL_SOCKET\z|IPPROTO_)/, /\A(SOL_|IPPROTO_)/)) ? " #{name}" : " cmsg_level:#{level}")
        text << ((name = Option.send(:optname_name, level, type)) ? " #{name}" : " cmsg_type:#{type}")
      else
        text << " cmsg_level:#{level} cmsg_type:#{type}"
      end
      shown = AncillaryData.shown(level == SOL_SOCKET ? AF_UNSPEC : family, level, type, bytes)
      Primitive.zr_obj_form(text << (shown || " #{bytes.dump}") << ">")
    end

    class << self
      def int(family, level, type, integer)
        family = Socket.family_arg(family)
        level = Socket.level_arg(family, level)
        build(family, level, Socket.cmsg_type_arg(family, level, type), [Integer.send(:int_operand, integer)].pack("i"))
      end

      def unix_rights(*ios)
        ios.each { |io| raise TypeError, "IO expected" unless io.is_a?(IO) }
        result = build(AF_UNIX, SOL_SOCKET, SCM_RIGHTS, ios.map(&:fileno).pack("i*"))
        Primitive.zr_hidden_set(result, :unix_rights, ios)
        result
      end

      def ip_pktinfo(addr, ifindex, spec_dst = nil)
        addr, = Socket.sockaddr_string(addr)
        ifindex = Integer.send(:int_operand, ifindex) & 0xffffffff
        spec_dst = spec_dst.nil? ? addr : Socket.sockaddr_string(spec_dst)[0]
        raise ArgumentError, "addr size different to AF_INET sockaddr" unless addr.bytesize == 16
        raise ArgumentError, "addr is not AF_INET sockaddr" unless Socket.sockaddr_family(addr) == AF_INET
        raise ArgumentError, "spec_dat size different to AF_INET sockaddr" unless spec_dst.bytesize == 16
        raise ArgumentError, "spec_dst is not AF_INET sockaddr" unless Socket.sockaddr_family(spec_dst) == AF_INET

        build(AF_INET, IPPROTO_IP, IP_PKTINFO, [ifindex].pack("L") + spec_dst.byteslice(4, 4) + addr.byteslice(4, 4))
      end

      def ipv6_pktinfo(addr, ifindex)
        addr, = Socket.sockaddr_string(addr)
        ifindex = Integer.send(:int_operand, ifindex) & 0xffffffff
        raise ArgumentError, "addr size different to AF_INET6 sockaddr" unless addr.bytesize == 28
        raise ArgumentError, "addr is not AF_INET6 sockaddr" unless Socket.sockaddr_family(addr) == AF_INET6

        build(AF_INET6, IPPROTO_IPV6, IPV6_PKTINFO, addr.byteslice(8, 16) + [ifindex].pack("L"))
      end

      # An IPv4 address's four bytes in a sockaddr_in whose length byte
      # stays 0, as ancillary_ip_pktinfo builds it.
      def in_addrinfo(bytes)
        Primitive.attr! :hidden
        Addrinfo.send(:build, Socket.sockaddr_head(AF_INET, 0) + [0].pack("n") + bytes + ("\0" * 8), PF_INET, 0, 0)
      end

      # The message's value as ancillary_inspect writes the messages it
      # knows here, or nil for one it shows as bytes.
      def shown(family, level, type, bytes)
        Primitive.attr! :hidden
        case [family, level, type]
        when [AF_UNSPEC, SOL_SOCKET, SCM_TIMESTAMP]
          seconds, microseconds = bytes.unpack("q<l<")
          " #{Time.at(seconds).strftime("%Y-%m-%d %H:%M:%S")}.#{format("%06d", microseconds)}" if bytes.bytesize == 16
        when [AF_UNSPEC, SOL_SOCKET, SCM_RIGHTS]
          bytes.unpack("i*").map { |fd| " #{fd}" }.join if bytes.bytesize.positive? && (bytes.bytesize % 4).zero?
        when [AF_INET, IPPROTO_IP, IP_RECVDSTADDR], [AF_INET6, IPPROTO_IP, IP_RECVDSTADDR]
          " #{bytes.unpack("C4").join(".")}" if bytes.bytesize == 4
        when [AF_INET, IPPROTO_IP, IP_PKTINFO], [AF_INET6, IPPROTO_IP, IP_PKTINFO]
          if bytes.bytesize == 12
            ifindex = bytes.unpack1("L")
            name = Primitive.zr_sock_if_name(ifindex)
            " #{bytes.byteslice(8, 4).unpack("C4").join(".")} #{name || "ifindex:#{ifindex}"} spec_dst:#{bytes.byteslice(4, 4).unpack("C4").join(".")}"
          end
        when [AF_INET, IPPROTO_IPV6, IPV6_PKTINFO], [AF_INET6, IPPROTO_IPV6, IPV6_PKTINFO]
          if bytes.bytesize == 20
            ifindex = bytes.byteslice(16, 4).unpack1("L")
            name = Primitive.zr_sock_if_name(ifindex)
            " #{Option.send(:ipv6_text, bytes.byteslice(0, 16))} #{name || "ifindex:#{ifindex}"}"
          end
        end
      end

      # A message of a received control buffer: [level, type, data], and
      # where the next begins.
      def cmsgs(control)
        Primitive.attr! :hidden
        messages = []
        at = 0
        header = Socket.cmsg_header_size
        while at + header <= control.bytesize
          length, level, type = Socket.cmsg_header(control, at)
          raise TypeError, "invalid control message (cmsg_len == 0)" if length.zero?

          stop = [at + length, control.bytesize].min
          messages << [level, type, control.byteslice(at + header, [stop - at - header, 0].max)]
          at += Socket.cmsg_align(length)
          break if at + header > control.bytesize
        end
        messages
      end

      private

      def build(family, level, type, data)
        Primitive.attr! :hidden
        Primitive.zr_class_build(AncillaryData).__send__(:assign, family, level, type, data)
      end
    end

    private

    def assign(family, level, type, data)
      Primitive.attr! :hidden
      @family = family
      @level = level
      @type = type
      @data = Primitive.zr_str_operand(data)
      self
    end

    def ipv6_pktinfo_bytes
      Primitive.attr! :hidden
      bytes = data
      raise TypeError, "IPV6_PKTINFO ancillary data expected" unless level == IPPROTO_IPV6 && type == IPV6_PKTINFO && bytes.bytesize == 20

      bytes
    end

    # make_io_for_unix_rights: each descriptor in a message, as a
    # Socket when it is one and an IO otherwise.
    def take_rights
      Primitive.attr! :hidden
      return unless @level == SOL_SOCKET && @type == SCM_RIGHTS

      @unix_rights = @data.unpack("i*").map do |fd|
        rows = Primitive.zr_fstat_m(fd)
        raise SocketError, "invalid fd in SCM_RIGHTS" if rows.is_a?(Integer)

        Primitive.zr_io_cloexec(fd)
        kind = rows[2] & 0o170000
        next Socket.new_sock(Socket, fd) if kind == 0o140000

        # rb_io_fdopen opens it for reading and writing, whatever the
        # descriptor allows; a stream here keeps to what it allows.
        mode = %w[r w r+].fetch(Primitive.zr_io_flags(fd) & 3, "r+")
        kind == 0o100000 ? File.for_fd(fd, mode) : IO.for_fd(fd, mode)
      end.freeze
    end
  end

  class << self
    # discard_cmsg: closes the descriptors in an SCM_RIGHTS message,
    # because no caller asked for them.
    def discard_rights(control)
      Primitive.attr! :hidden
      AncillaryData.cmsgs(control).each do |level, type, data|
        data.unpack("i*").each { |fd| Primitive.zr_io_close(fd) } if level == SOL_SOCKET && type == SCM_RIGHTS
      end
    end
  end
end

class BasicSocket < IO
  private

  def __sendmsg(mesg, flags, dest_sockaddr, controls) = send_message(mesg, flags, dest_sockaddr, controls, true, false)

  def __sendmsg_nonblock(mesg, flags, dest_sockaddr, controls, exception) = send_message(mesg, flags, dest_sockaddr, controls, exception, true)

  def __recvmsg(dlen, flags, clen, scm_rights) = receive_message(dlen, flags, clen, scm_rights, true, false)

  def __recvmsg_nonblock(dlen, flags, clen, scm_rights, exception) = receive_message(dlen, flags, clen, scm_rights, exception, true)

  # bsock_sendmsg_internal.
  def send_message(mesg, flags, dest_sockaddr, controls, exception, nonblock)
    Primitive.attr! :hidden
    descriptor
    family = socket_family
    mesg = Primitive.zr_str_operand(mesg)
    controls = [] unless controls.is_a?(Array)
    control = nil
    unless controls.empty?
      control = "".b
      controls.each do |element|
        parts = Array.try_convert(element)
        if parts
          raise ArgumentError, "an element of controls should be 3-elements array" unless parts.size == 3

          level, type, data = parts
        else
          level = element.level
          type = element.type
          data = element.data
        end
        level = Socket.level_arg(family, level)
        type = Socket.cmsg_type_arg(family, level, type)
        data = Primitive.zr_str_operand(data)
        control << Socket.cmsg(level, type, data)
      end
    end
    flags = flags.nil? ? 0 : Integer.send(:int_operand, flags)
    flags |= Socket::MSG_DONTWAIT if nonblock
    dest_sockaddr, = Socket.sockaddr_string(dest_sockaddr) unless dest_sockaddr.nil?
    check_open
    loop do
      sent = Primitive.zr_sock_sendmsg(@fd, mesg, flags, dest_sockaddr, control)
      return sent unless sent.negative?

      errno = -sent
      if !nonblock && maybe_wait(errno, IO::WRITABLE)
        check_open
        next
      end
      if nonblock && errno == Errno::EAGAIN::Errno
        return :wait_writable if exception == false

        Socket.wait_fail(errno, :writable, "sendmsg(2) would block")
      end
      Socket.syserr_fail(errno, "sendmsg(2)")
    end
  end

  # bsock_recvmsg_internal. Without both lengths given, the call peeks
  # with buffers that grow until the message fits, and then takes it.
  def receive_message(dlen, flags, clen, scm_rights, exception, nonblock)
    Primitive.attr! :hidden
    maxdatlen = dlen.nil? ? 4096 : Primitive.zr_index_operand_m(dlen)
    maxctllen = clen.nil? ? 4096 : Primitive.zr_index_operand_m(clen)
    flags = Integer.send(:int_operand, flags)
    flags |= Socket::MSG_DONTWAIT if nonblock
    original = flags
    grow = dlen.nil? || clen.nil?
    descriptor
    raise IOError, "recvmsg for buffered IO" if buffered?

    collected = false
    loop do
      flags |= Socket::MSG_PEEK if grow
      check_open
      answer = Primitive.zr_sock_recvmsg(@fd, maxdatlen, flags, maxctllen)
      if answer.is_a?(Integer)
        errno = -answer
        next if !nonblock && maybe_wait(errno, IO::READABLE)

        if nonblock && errno == Errno::EAGAIN::Errno
          return :wait_readable if exception == false

          Socket.wait_fail(errno, :readable, "recvmsg(2) would block")
        end
        if !collected && [Errno::EMFILE::Errno, Errno::EMSGSIZE::Errno].include?(errno)
          GC.start
          collected = true
          next
        end
        Socket.syserr_fail(errno, "recvmsg(2)")
      end
      data, name, msg_flags, control = answer
      return nil if data.empty? && !dgram?

      if grow
        grown = false
        if dlen.nil? && data.bytesize == maxdatlen
          maxdatlen *= 2
          grown = true
        end
        if clen.nil? && (msg_flags & Socket::MSG_CTRUNC).nonzero?
          if maxctllen > 65_536 && control.bytesize < maxctllen - 65_536
            unless collected
              GC.start
              collected = true
              next
            end
          else
            maxctllen *= 2
            grown = true
          end
        end
        next if grown

        grow = false
        if flags != original
          flags = original
          next
        end
      end
      result = [data, Socket.fd_socket_addrinfo(@fd, name), msg_flags]
      family = socket_family
      Socket::AncillaryData.cmsgs(control).each do |level, type, bytes|
        message = Socket::AncillaryData.send(:build, family, level, type, bytes)
        if scm_rights
          message.__send__(:take_rights)
        elsif (flags & Socket::MSG_PEEK).zero? && level == Socket::SOL_SOCKET && type == Socket::SCM_RIGHTS
          bytes.unpack("i*").each { |fd| Primitive.zr_io_close(fd) }
        end
        result << message
      end
      return result
    end
  end
end
