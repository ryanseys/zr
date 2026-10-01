# frozen_string_literal: true

# init.c and constants.c: the error classes, the socket every class
# opens over a descriptor, and the conversions every method shares. What
# the C half keeps in static functions lives here as Socket's hidden
# singleton methods, which no program sees.

class SocketError < StandardError; end

class Socket < BasicSocket
  # sock_define_const writes every name twice, on Socket and on
  # Socket::Constants, and includes that module nowhere.
  Constants.constants.each { |name| const_set(name, Constants.const_get(name)) }

  class ResolutionError < SocketError
    attr_reader :error_code
  end

  class << self
    # rsock_raise_resolution_error: the resolver's result, in its own
    # words; a failure in a system call is that call's error.
    def resolution_error(reason, code)
      Primitive.attr! :hidden
      raise SystemCallError.new(reason, -code) if code.negative?

      error = ResolutionError.new("#{reason}: #{Primitive.zr_sock_gai_message(code)}")
      Primitive.zr_hidden_set(error, :error_code, code)
      raise error
    end

    # rb_syserr_fail_str: the errno's error, with `message`.
    def syserr_fail(errno, message)
      Primitive.attr! :hidden
      raise SystemCallError.new(message, errno)
    end

    # rsock_syserr_fail_host_port: a failure named with where it was
    # aimed; a connection that timed out is IO's timeout instead.
    def syserr_fail_host_port(errno, message, host, port)
      Primitive.attr! :hidden
      text = "#{message} for #{host.inspect} port #{port}"
      raise IO::TimeoutError, text if errno == Errno::ETIMEDOUT::Errno

      syserr_fail(errno, text)
    end

    # rsock_syserr_fail_path: a failure named with the path, when there
    # is one.
    def syserr_fail_path(errno, message, path)
      Primitive.attr! :hidden
      syserr_fail(errno, path.is_a?(String) ? "#{message} for #{path}" : message)
    end

    # rsock_syserr_fail_raddrinfo_or_sockaddr: a failure named with the
    # address, as Addrinfo shows it.
    def syserr_fail_sockaddr(errno, message, sockaddr, addrinfo = nil)
      Primitive.attr! :hidden
      addrinfo ||= Addrinfo.send(:build, sockaddr, PF_UNSPEC, 0, 0)
      syserr_fail(errno, "#{message} for #{addrinfo.inspect_sockaddr}")
    end

    # rb_readwrite_syserr_fail: the errno's error, as the wait it names.
    def wait_fail(errno, event, message)
      Primitive.attr! :hidden
      wait = event == :readable ? IO::WaitReadable : IO::WaitWritable
      case errno
      when Errno::EAGAIN::Errno then raise wait == IO::WaitReadable ? IO::EAGAINWaitReadable : IO::EAGAINWaitWritable, message
      when Errno::EINPROGRESS::Errno then raise wait == IO::WaitReadable ? IO::EINPROGRESSWaitReadable : IO::EINPROGRESSWaitWritable, message
      end
      raise SystemCallError.new(message, errno).extend(wait)
    end

    # constant_arg: a Symbol or a String is the name of a constant in
    # `table`, and any other value is its number.
    def constant_arg(arg, table, message)
      Primitive.attr! :hidden
      arg = arg.to_s if arg.is_a?(Symbol)
      text = String.try_convert(arg)
      return Integer.send(:int_operand, arg) if text.nil?

      table.fetch(text) { raise SocketError, "#{message}: #{text}" }
    end

    def family_arg(domain)
      Primitive.attr! :hidden
      constant_arg(domain, names(/\A(AF_|PF_)/, "AF_"), "unknown socket domain")
    end

    def socktype_arg(type)
      Primitive.attr! :hidden
      constant_arg(type, names(/\ASOCK_/, "SOCK_"), "unknown socket type")
    end

    def shutdown_how_arg(how)
      Primitive.attr! :hidden
      constant_arg(how, names(/\ASHUT_/, "SHUT_"), "unknown shutdown argument")
    end

    def level_arg(family, level)
      Primitive.attr! :hidden
      return constant_arg(level, names(/\A(SOL_SOCKET\z|IPPROTO_)/, /\A(SOL_|IPPROTO_)/), "unknown protocol level") if ip_family?(family)

      constant_arg(level, names(/\ASOL_SOCKET\z/, "SOL_"), "unknown protocol level")
    end

    OPTNAMES = {
      SOL_SOCKET: [/\ASO_/, "SO_", "unknown socket level option name"],
      IPPROTO_IP: [/\AIP_/, "IP_", "unknown IP level option name"],
      IPPROTO_IPV6: [/\AIPV6_/, "IPV6_", "unknown IPv6 level option name"],
      IPPROTO_TCP: [/\ATCP_/, "TCP_", "unknown TCP level option name"],
      IPPROTO_UDP: [/\AUDP_/, "UDP_", "unknown UDP level option name"]
    }.freeze
    private_constant :OPTNAMES

    def optname_arg(family, level, optname)
      Primitive.attr! :hidden
      level_arg_of(family, level, optname, OPTNAMES)
    end

    CMSG_TYPES = {
      SOL_SOCKET: [/\ASCM_/, "SCM_", "unknown UNIX control message"],
      IPPROTO_IP: [/\AIP_/, "IP_", "unknown IP control message"],
      IPPROTO_IPV6: [/\AIPV6_/, "IPV6_", "unknown IPv6 control message"],
      IPPROTO_TCP: [/\ATCP_/, "TCP_", "unknown TCP control message"],
      IPPROTO_UDP: [/\AUDP_/, "UDP_", "unknown UDP control message"]
    }.freeze
    private_constant :CMSG_TYPES

    def cmsg_type_arg(family, level, type)
      Primitive.attr! :hidden
      level_arg_of(family, level, type, CMSG_TYPES)
    end

    # An option or a control message named for its level: every level an
    # IP socket knows, and the socket level alone for anything else.
    def level_arg_of(family, level, arg, rows)
      Primitive.attr! :hidden
      level_name = rows.keys.find { |name| const_get(name) == level }
      level_name = nil unless ip_family?(family) || level_name == :SOL_SOCKET
      return Integer.send(:int_operand, arg) if level_name.nil?

      pattern, prefix, message = rows.fetch(level_name)
      constant_arg(arg, names(pattern, prefix), message)
    end

    def ip_family?(family)
      Primitive.attr! :hidden
      family == AF_INET || family == AF_INET6
    end

    # The names mkconstants.rb makes a lookup of, each to its number: the
    # names `pattern` matches, and with a prefix those names without it.
    def names(pattern, prefix = nil)
      Primitive.attr! :hidden
      @names ||= {}
      @names[[pattern, prefix]] ||= begin
        matched = constant_names.grep(pattern)
        table = matched.to_h { |name| [name.to_s, const_get(name)] }
        prefix = /\A#{Regexp.escape(prefix)}/ if prefix.is_a?(String)
        matched.each { |name| table[name.to_s.sub(prefix, "")] = const_get(name) if prefix&.match?(name) }
        table.freeze
      end
    end

    # The name mkconstants.rb shows a number by: the first name `pattern`
    # matches that has it, and with a prefix the first such name without
    # the prefix, which wins over every whole one.
    def intern(value, pattern, prefix = nil)
      Primitive.attr! :hidden
      @interns ||= {}
      table = @interns[[pattern, prefix]] ||= begin
        matched = constant_names.grep(pattern)
        rows = matched.reverse.map { |name| [const_get(name), name.to_s.freeze] }
        if prefix
          prefix = /\A#{Regexp.escape(prefix)}/ if prefix.is_a?(String)
          rows.concat(matched.reverse.filter_map { |name| [const_get(name), name.to_s.sub(prefix, "").freeze] if prefix.match?(name) })
        end
        rows.to_h.freeze
      end
      table[value]
    end

    # rsock_init_sock: `sock`, opened over `fd` for reading and writing,
    # in binary and synchronous, and not reverse looking up its addresses
    # while BasicSocket says so.
    def init_sock(sock, fd)
      Primitive.attr! :hidden
      sock.__send__(:open_socket, fd)
    end

    # rb_obj_alloc and rsock_init_sock: a new socket of `klass`, which no
    # `initialize` of its own runs for.
    def new_sock(klass, fd)
      Primitive.attr! :hidden
      init_sock(Primitive.zr_class_build(klass), fd)
    end

    # rsock_socket: a descriptor of the requested kind, or the errno.
    def socket_fd(domain, type, protocol)
      Primitive.attr! :hidden
      Primitive.zr_sock_socket(domain, type, protocol)
    end

    # raddrinfo_host_str: the host to give the resolver, and the flags
    # that say it is already numeric.
    def host_str(host)
      Primitive.attr! :hidden
      return [nil, 0] if host.nil?
      if host.is_a?(Integer)
        raise RangeError, "integer #{host} too #{host.negative? ? "small" : "big"} to convert to 'unsigned int'" unless host.between?(-2**31, 2**32 - 1)

        return [inet_text([host & 0xffffffff].pack("N")), AI_NUMERICHOST]
      end

      name = cstr(host)
      return ["0.0.0.0", AI_NUMERICHOST] if name.empty? || name == "<any>"
      return ["255.255.255.255", AI_NUMERICHOST] if name == "<broadcast>"
      raise ArgumentError, "hostname too long (#{name.bytesize})" if name.bytesize >= NI_MAXHOST

      [name, 0]
    end

    # raddrinfo_port_str: the service to give the resolver.
    def port_str(port)
      Primitive.attr! :hidden
      return [nil, 0] if port.nil?
      return [port.to_s, AI_NUMERICSERV] if Primitive.zr_fixnum_p_m(port)

      name = cstr(port)
      raise ArgumentError, "service name too long (#{name.bytesize})" if name.bytesize >= NI_MAXSERV

      [name, 0]
    end

    # StringValueCStr.
    def cstr(value)
      Primitive.attr! :hidden
      text = Primitive.zr_str_operand(value)
      raise ArgumentError, "string contains null byte" if text.include?("\0")

      text
    end

    # An IPv4 address's four bytes as getnameinfo writes them.
    def inet_text(bytes)
      Primitive.attr! :hidden
      make_ipaddr(sockaddr_head(AF_INET, 16) + [0].pack("n") + bytes + ("\0" * 8))
    end

    # str_is_number: digits strtoul reads to the end.
    def number?(text)
      Primitive.attr! :hidden
      !text.nil? && text.match?(/\A\s*[-+]?\d+\z/)
    end

    NUMERIC_SOCKTYPES = [[SOCK_STREAM, IPPROTO_TCP], [SOCK_DGRAM, IPPROTO_UDP], [SOCK_RAW, 0]].freeze
    private_constant :NUMERIC_SOCKTYPES

    # numeric_getaddrinfo: an address written as digits resolves without
    # the resolver, one row a socket kind the hints allow.
    def numeric_getaddrinfo(node, service, family, socktype, protocol)
      Primitive.attr! :hidden
      return nil if node.nil? || !(service.nil? || (service.match?(/\A\d*\z/) && service.to_i < 0x10000))

      port = service.to_i
      if (family == PF_UNSPEC || family == PF_INET6) && node.match?(/\A[0-9a-fA-F.:]*\z/) && (bytes = Primitive.zr_sock_inet_pton(AF_INET6, node))
        sockaddr = sockaddr_head(AF_INET6, 28) + [port, 0].pack("nN") + bytes + "\0\0\0\0"
        af = PF_INET6
      elsif (family == PF_UNSPEC || family == PF_INET) && node.match?(/\A[0-9.]*\z/) && (bytes = Primitive.zr_sock_inet_pton(AF_INET, node))
        sockaddr = sockaddr_head(AF_INET, 16) + [port].pack("n") + bytes + ("\0" * 8)
        af = PF_INET
      else
        return nil
      end
      rows = NUMERIC_SOCKTYPES.filter_map do |kind, proto|
        next unless (socktype.zero? || socktype == kind) && (protocol.zero? || proto.zero? || protocol == proto)

        [af, kind, protocol.zero? ? proto : protocol, sockaddr, nil]
      end
      rows.empty? ? nil : rows
    end

    # rsock_getaddrinfo: every row a host and a service resolve to, each
    # [family, socktype, protocol, sockaddr, canonical name].
    def resolve(host, port, family: PF_UNSPEC, socktype: 0, protocol: 0, flags: 0, socktype_hack: false)
      Primitive.attr! :hidden
      node, host_flags = host_str(host)
      service, port_flags = port_str(port)
      socktype = SOCK_DGRAM if socktype_hack && socktype.zero? && number?(service)
      flags |= host_flags | port_flags
      rows = numeric_getaddrinfo(node, service, family, socktype, protocol)
      return rows if rows

      # rb_scheduler_getaddrinfo: a non-blocking fiber's scheduler names
      # the addresses, each read as a number.
      scheduler = Fiber.current_scheduler
      if node && !flags.anybits?(AI_NUMERICHOST) && scheduler.respond_to?(:address_resolve)
        rows = Array(scheduler.address_resolve(host)).flat_map do |address|
          numeric_getaddrinfo(host_str(address).first, service, family, socktype, protocol) || []
        end
        return rows unless rows.empty?

        resolution_error("getaddrinfo", EAI_NONAME)
      end

      rows = darwin_getaddrinfo(node, service, family, socktype, protocol, flags)
      return rows unless rows.is_a?(Integer)

      raise SocketError, "newline at the end of hostname" if node&.end_with?("\n")

      resolution_error("getaddrinfo", rows)
    end

    # ruby_getaddrinfo__darwin: a service of port 0 is given as no
    # service, and an entry with no kind or protocol takes the hint's.
    def darwin_getaddrinfo(node, service, family, socktype, protocol, flags)
      Primitive.attr! :hidden
      if node && service && number?(service) && service.to_i.zero?
        service = nil
        flags &= ~AI_NUMERICSERV unless flags.zero?
      end
      rows = Primitive.zr_sock_getaddrinfo(node, service, family, socktype, protocol, flags)
      return rows if rows.is_a?(Integer)

      rows.each do |row|
        row[1] = socktype if row[1].zero?
        row[2] = { SOCK_DGRAM => IPPROTO_UDP, SOCK_STREAM => IPPROTO_TCP }.fetch(row[1], 0) if row[2].zero?
      end
    end

    # rb_getnameinfo, raising the resolver's error.
    def nameinfo(sockaddr, flags, want = 3)
      Primitive.attr! :hidden
      answer = Primitive.zr_sock_getnameinfo(sockaddr, flags, want)
      resolution_error("getnameinfo", answer) if answer.is_a?(Integer)

      answer
    end

    # rsock_make_ipaddr: the address's host as digits.
    def make_ipaddr(sockaddr)
      Primitive.attr! :hidden
      nameinfo(sockaddr, NI_NUMERICHOST, 1)[0]
    end

    # rsock_ipaddr: [family name, port, host, host as digits], the host
    # looked up by name unless `norevlookup`.
    def ipaddr(sockaddr, norevlookup)
      Primitive.attr! :hidden
      af = sockaddr_family(sockaddr)
      family = intern(af, /\AAF_/) || "unknown:#{af}"
      name = nil
      unless norevlookup
        answer = Primitive.zr_sock_getnameinfo(sockaddr, 0, 1)
        name = answer[0] unless answer.is_a?(Integer)
      end
      host, service = nameinfo(sockaddr, NI_NUMERICHOST | NI_NUMERICSERV)
      [family.dup, service.to_i, name || host, host]
    end

    # rsock_unixpath_str: a unix address's path, its trailing NULs gone.
    def unixpath(sockaddr)
      Primitive.attr! :hidden
      return "".b if sockaddr.bytesize < 2

      sockaddr.byteslice(2, sockaddr.bytesize - 2).sub(/\0+\z/, "")
    end

    def unixaddr(sockaddr)
      Primitive.attr! :hidden
      ["AF_UNIX", unixpath(sockaddr)]
    end

    # INIT_SOCKADDR_UN: a unix address for `path`, as long as the
    # structure, as rsock_unix_sockaddr_len makes it here.
    def pack_unix(path)
      Primitive.attr! :hidden
      sockaddr_head(AF_UNIX, UNIX_PATH_MAX + 2) + path.b + ("\0" * (UNIX_PATH_MAX - path.bytesize))
    end

    # The maximum number of path bytes that a sockaddr_un contains.
    def unix_path_max
      Primitive.attr! :hidden
      UNIX_PATH_MAX
    end

    # CMSG_LEN and CMSG_SPACE: the length a control message of `size`
    # bytes of data records, and the room it takes with its padding.
    def cmsg_len(size)
      Primitive.attr! :hidden
      CMSG_HEADER + size
    end

    def cmsg_space(size)
      Primitive.attr! :hidden
      cmsg_align(CMSG_HEADER) + cmsg_align(size)
    end

    def cmsg_align(size)
      Primitive.attr! :hidden
      (size + CMSG_ALIGN - 1) & -CMSG_ALIGN
    end

    # One control message: the header, the data, and its padding.
    def cmsg(level, type, data)
      Primitive.attr! :hidden
      [cmsg_len(data.bytesize), level, type].pack(CMSG_HEADER_PACK) + data.b + ("\0" * (cmsg_space(data.bytesize) - cmsg_len(data.bytesize)))
    end

    # A control message's header at `at`: its length, level and type.
    def cmsg_header(control, at)
      Primitive.attr! :hidden
      control.byteslice(at, CMSG_HEADER).unpack(CMSG_HEADER_PACK)
    end

    # The bytes of a cmsghdr.
    def cmsg_header_size
      Primitive.attr! :hidden
      CMSG_HEADER
    end

    # SockAddrStringValueWithAddrinfo: an address's bytes, from an
    # Addrinfo or a String, and the Addrinfo it came from.
    def sockaddr_string(value)
      Primitive.attr! :hidden
      return [value.to_sockaddr, value] if value.is_a?(Addrinfo)

      [Primitive.zr_str_operand(value), nil]
    end

    # rsock_fd_socket_addrinfo: an Addrinfo for an address a descriptor
    # sent or received, of the descriptor's own kind.
    def fd_socket_addrinfo(fd, sockaddr)
      Primitive.attr! :hidden
      type = Primitive.zr_sock_getsockopt(fd, SOL_SOCKET, SO_TYPE)
      syserr_fail(-type, "getsockopt(SO_TYPE)") if type.is_a?(Integer)

      Addrinfo.send(:build, sockaddr, sockaddr_family(sockaddr), type.unpack1("i"), 0)
    end

    # rsock_revlookup_flag: the value that a reverse_lookup argument
    # selects, or nil for none.
    def norevlookup_flag(revlookup)
      Primitive.attr! :hidden
      case revlookup
      when true then false
      when false then true
      when nil then nil
      else
        raise TypeError, "wrong argument type #{Primitive.zr_class_path(Primitive.zr_real_class(revlookup))} (expected Symbol)" unless revlookup.is_a?(Symbol)
        return true if revlookup == :numeric
        return false if revlookup == :hostname

        raise ArgumentError, "invalid reverse_lookup flag: :#{revlookup}"
      end
    end
  end
end

class BasicSocket < IO
  private

  # rsock_init_sock, on the socket itself.
  def open_socket(fd)
    Primitive.attr! :hidden
    IO.instance_method(:initialize).bind_call(self, fd, "r+", binmode: true)
    @sync = true
    @nonblock = true
    @norevlookup = BasicSocket.do_not_reverse_lookup
    self
  end

  # GetOpenFile: the open descriptor.
  def descriptor
    Primitive.attr! :hidden
    check_open
    @fd
  end

  # rb_io_maybe_wait: whether a call that failed with `errno` goes round
  # again, once the descriptor is ready for `event`.
  def maybe_wait(errno, event)
    Primitive.attr! :hidden
    return true if errno == Errno::EINTR::Errno
    return false unless errno == Errno::EAGAIN::Errno

    raise IO::TimeoutError, "Blocking operation timed out!" unless wait_ready(event, @timeout)

    true
  end

  # rb_io_wait_readable and rb_io_wait_writable: whether a call that
  # failed with `errno` goes round again, waiting as long as it takes.
  def wait_io?(errno, event)
    Primitive.attr! :hidden
    return true if errno == Errno::EINTR::Errno
    return false unless errno == Errno::EAGAIN::Errno

    wait_ready(event, nil)
  end

  # rb_io_wait: whether the descriptor came ready for `events` before
  # `timeout` seconds ran out. Another green thread runs meanwhile.
  def wait_ready(events, timeout)
    Primitive.attr! :hidden
    deadline = timeout && Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (timeout * 1e9).round
    ready = Thread.current.send(:wait_io, @fd, events, deadline)
    raise SystemCallError.new(nil, -ready, "io_wait") if ready.negative?

    ready.positive?
  end
end
