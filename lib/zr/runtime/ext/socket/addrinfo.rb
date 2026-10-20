# frozen_string_literal: true

# Derived from the C of CRuby and of its gems (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# raddrinfo.c's Addrinfo: an address's bytes with its protocol family,
# socket kind and protocol, the canonical name that the resolver gave,
# and the requested name as an inspect shows it.
class Addrinfo
  # union_sockaddr's size.
  SOCKADDR_MAX = 2048
  private_constant :SOCKADDR_MAX

  def initialize(sockaddr, family = nil, socktype = nil, protocol = nil)
    raise TypeError, "already initialized socket address" unless @sockaddr.nil?

    pfamily = family.nil? ? Socket::PF_UNSPEC : Socket.family_arg(family)
    socktype = socktype.nil? ? 0 : Socket.socktype_arg(socktype)
    protocol = protocol.nil? ? 0 : Integer.send(:int_operand, protocol)
    list = Array.try_convert(sockaddr)
    if list.nil?
      assign(Primitive.zr_str_operand(sockaddr), pfamily, socktype, protocol, nil, nil)
      return
    end

    name = Primitive.zr_str_operand(list[0])
    af = Socket.names(/\A(AF_|PF_)/, "AF_").fetch(name) { raise SocketError, "unknown address family: #{name}" }
    case af
    when Socket::AF_INET, Socket::AF_INET6
      service = Integer.send(:int_operand, list[1])
      nodename = list[2].nil? ? nil : Primitive.zr_str_operand(list[2])
      numericnode = Primitive.zr_str_operand(list[3])
      rows = Addrinfo.call_getaddrinfo(numericnode, service, pfamily.nonzero? || af, socktype, protocol,
                                       Socket::AI_NUMERICHOST | Socket::AI_NUMERICSERV, socktype_hack: true)
      inspectname = numericnode == nodename ? nil : Addrinfo.inspectname(nodename, service, rows[0][3])
      assign(rows[0][3], pfamily.nonzero? || af, socktype, protocol, rows[0][4]&.freeze, inspectname)
    when Socket::AF_UNIX
      assign_unix(Primitive.zr_str_operand(list[1]), Socket::SOCK_STREAM)
    else
      raise SocketError, "unexpected address family"
    end
  end

  def afamily = family_of(sockaddr_bytes)

  def pfamily
    checked
    @pfamily
  end

  def socktype
    checked
    @socktype
  end

  def protocol
    checked
    @protocol
  end

  def canonname
    checked
    @canonname
  end

  def to_sockaddr = sockaddr_bytes.dup

  alias to_s to_sockaddr

  def ip? = [Socket::AF_INET, Socket::AF_INET6].include?(afamily)

  def ipv4? = afamily == Socket::AF_INET

  def ipv6? = afamily == Socket::AF_INET6

  def unix? = afamily == Socket::AF_UNIX

  def getnameinfo(flags = nil)
    bytes = sockaddr_bytes
    flags = flags.nil? ? 0 : Integer.send(:int_operand, flags)
    flags |= Socket::NI_DGRAM if @socktype == Socket::SOCK_DGRAM
    Socket.nameinfo(bytes, flags)
  end

  def ip_unpack
    host, port = numeric_nameinfo
    [host, port.to_i]
  end

  def ip_address = numeric_nameinfo[0]

  def ip_port
    bytes = sockaddr_bytes
    case family_of(bytes)
    when Socket::AF_INET
      raise SocketError, "unexpected sockaddr size for IPv4" unless bytes.bytesize == 16
    when Socket::AF_INET6
      raise SocketError, "unexpected sockaddr size for IPv6" unless bytes.bytesize == 28
    else
      raise SocketError, "need IPv4 or IPv6 address"
    end
    bytes.byteslice(2, 2).unpack1("n")
  end

  def ipv4_private?
    return false unless ipv4?

    a = in_addr
    (a & 0xff000000) == 0x0a000000 || (a & 0xfff00000) == 0xac100000 || (a & 0xffff0000) == 0xc0a80000
  end

  def ipv4_loopback? = ipv4? && (in_addr & 0xff000000) == 0x7f000000

  def ipv4_multicast? = ipv4? && (in_addr & 0xf0000000) == 0xe0000000

  def ipv6_unspecified? = ipv6? && in6_addr.all?(0)

  def ipv6_loopback? = ipv6? && in6_addr == [0] * 15 + [1]

  def ipv6_multicast? = ipv6? && in6_addr[0] == 0xff

  def ipv6_linklocal? = ipv6? && in6_addr[0] == 0xfe && (in6_addr[1] & 0xc0) == 0x80

  def ipv6_sitelocal? = ipv6? && in6_addr[0] == 0xfe && (in6_addr[1] & 0xc0) == 0xc0

  def ipv6_unique_local? = ipv6? && [0xfc, 0xfd].include?(in6_addr[0])

  def ipv6_v4mapped? = ipv6? && in6_addr.first(12) == [0] * 10 + [0xff, 0xff]

  def ipv6_v4compat? = ipv6? && in6_addr.first(12).all?(0) && ![[0, 0, 0, 0], [0, 0, 0, 1]].include?(in6_addr.last(4))

  def ipv6_mc_nodelocal? = multicast_scope?(0x01)

  def ipv6_mc_linklocal? = multicast_scope?(0x02)

  def ipv6_mc_sitelocal? = multicast_scope?(0x05)

  def ipv6_mc_orglocal? = multicast_scope?(0x08)

  def ipv6_mc_global? = multicast_scope?(0x0e)

  def ipv6_to_ipv4
    return nil unless ipv6? && (ipv6_v4mapped? || ipv6_v4compat?)

    sockaddr = Socket.sockaddr_head(Socket::AF_INET, 16) + [0].pack("n") + @sockaddr.byteslice(20, 4) + ("\0" * 8)
    Addrinfo.build(sockaddr, Socket::PF_INET, @socktype, @protocol, @canonname, @inspectname)
  end

  def unix_path
    bytes = sockaddr_bytes
    raise SocketError, "need AF_UNIX address" unless family_of(bytes) == Socket::AF_UNIX

    length = Addrinfo.unix_path_length(bytes)
    raise SocketError, "too short AF_UNIX address: #{bytes.bytesize} bytes given for minimum 2 bytes." if length.negative?
    raise SocketError, "too long AF_UNIX path (#{length} bytes given but #{Socket.unix_path_max} bytes max)" if length > Socket.unix_path_max

    bytes.byteslice(2, length)
  end

  def inspect
    bytes = sockaddr_bytes
    text = +"#<#{Primitive.zr_class_path(Primitive.zr_real_class(self))}: "
    text << Addrinfo.inspect_sockaddr(bytes)
    if @pfamily.nonzero? && family_of(bytes) != @pfamily
      name = Socket.intern(@pfamily, /\APF_/)
      text << (name ? " #{name}" : " PF_???(#{@pfamily})")
    end
    internet = @pfamily == Socket::PF_INET || @pfamily == Socket::PF_INET6
    if internet && @socktype == Socket::SOCK_STREAM && (@protocol.zero? || @protocol == Socket::IPPROTO_TCP)
      text << " TCP"
    elsif internet && @socktype == Socket::SOCK_DGRAM && (@protocol.zero? || @protocol == Socket::IPPROTO_UDP)
      text << " UDP"
    else
      if @socktype.nonzero?
        name = Socket.intern(@socktype, /\ASOCK_/)
        text << (name ? " #{name}" : " SOCK_???(#{@socktype})")
      end
      if @protocol.nonzero?
        name = internet && Socket.intern(@protocol, /\AIPPROTO_/)
        text << (name ? " #{name}" : " UNKNOWN_PROTOCOL(#{@protocol})")
      end
    end
    text << " #{@canonname}" unless @canonname.nil?
    text << " (#{@inspectname})" unless @inspectname.nil?
    Primitive.zr_obj_form(text << ">")
  end

  def inspect_sockaddr = Addrinfo.inspect_sockaddr(sockaddr_bytes)

  def marshal_dump
    bytes = sockaddr_bytes
    afamily = family_of(bytes)
    pfamily = Socket.intern(@pfamily, /\APF_/) or raise SocketError, "unknown protocol family: #{@pfamily}"
    socktype = @socktype.zero? ? 0 : Socket.intern(@socktype, /\ASOCK_/) || raise(SocketError, "unknown socktype: #{@socktype}")
    protocol = if @protocol.zero? then 0
               elsif ip? then Socket.intern(@protocol, /\AIPPROTO_/) || raise(SocketError, "unknown IP protocol: #{@protocol}")
               else raise SocketError, "unknown protocol: #{@protocol}"
               end
    family = Socket.intern(afamily, /\AAF_/) or raise SocketError, "unknown address family: #{afamily}"
    sockaddr = if afamily == Socket::AF_UNIX
                 bytes.byteslice(2, Addrinfo.unix_path_length(bytes))
               else
                 Socket.nameinfo(bytes, Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV)
               end
    [family, sockaddr, pfamily, socktype, protocol, @canonname, @inspectname]
  end

  def marshal_load(ary)
    raise TypeError, "already initialized socket address" unless @sockaddr.nil?

    ary = Array.try_convert(ary) || raise(TypeError, no_implicit_conversion(ary, "Array"))
    families = Socket.names(/\A(AF_|PF_)/, "AF_")
    afamily = families.fetch(Primitive.zr_str_operand(ary[0])) { raise TypeError, "unexpected address family" }
    pfamily = families.fetch(Primitive.zr_str_operand(ary[2])) { raise TypeError, "unexpected protocol family" }
    socktype = ary[3] == 0 ? 0 : Socket.names(/\ASOCK_/, "SOCK_").fetch(Primitive.zr_str_operand(ary[3])) { raise TypeError, "unexpected socktype" }
    protocol = if ary[4] == 0 then 0
               else
                 name = Primitive.zr_str_operand(ary[4])
                 raise TypeError, "unexpected protocol" unless Socket.ip_family?(afamily)

                 Socket.names(/\AIPPROTO_/, "IPPROTO_").fetch(name) { raise TypeError, "unexpected protocol" }
               end
    canonname = ary[5].nil? ? nil : Primitive.zr_str_operand(ary[5])
    inspectname = ary[6].nil? ? nil : Primitive.zr_str_operand(ary[6])
    if afamily == Socket::AF_UNIX
      path = Primitive.zr_str_operand(ary[1])
      raise SocketError, "too long AF_UNIX path (#{path.bytesize} bytes given but #{Socket.unix_path_max} bytes max)" if path.bytesize > Socket.unix_path_max

      sockaddr = Socket.pack_unix(path)
    else
      pair = Array.try_convert(ary[1]) or raise TypeError, no_implicit_conversion(ary[1], "Array")
      sockaddr = Addrinfo.call_getaddrinfo(pair[0], pair[1], pfamily, socktype, protocol,
                                           Socket::AI_NUMERICHOST | Socket::AI_NUMERICSERV, socktype_hack: true)[0][3]
    end
    assign(sockaddr, pfamily, socktype, protocol, canonname, inspectname)
  end

  class << self
    def getaddrinfo(nodename, service, family = nil, socktype = nil, protocol = nil, flags = nil, timeout: nil)
      rows = call_getaddrinfo(nodename, service, family, socktype, protocol, flags)
      inspectname = inspectname(nodename, service, rows[0][3])
      rows.map { |af, kind, proto, sockaddr, canonical| build(sockaddr, af, kind, proto, canonical&.freeze, inspectname) }
    end

    # An address for a host alone, of no socket kind or protocol.
    def ip(host) = firstonly(host, nil, Socket::PF_UNSPEC, 0, 0, 0).__send__(:without_kind)

    def tcp(host, port) = firstonly(host, port, Socket::PF_UNSPEC, Socket::SOCK_STREAM, Socket::IPPROTO_TCP, 0)

    def udp(host, port) = firstonly(host, port, Socket::PF_UNSPEC, Socket::SOCK_DGRAM, Socket::IPPROTO_UDP, 0)

    def unix(path, socktype = nil)
      socktype = socktype.nil? ? Socket::SOCK_STREAM : Socket.socktype_arg(socktype)
      Primitive.zr_class_build(Addrinfo).__send__(:assign_unix, Primitive.zr_str_operand(path), socktype)
    end

    # rsock_addrinfo_new.
    def build(sockaddr, pfamily, socktype, protocol, canonname = nil, inspectname = nil)
      Primitive.attr! :hidden
      Primitive.zr_class_build(Addrinfo).__send__(:assign, sockaddr, pfamily, socktype, protocol, canonname, inspectname)
    end

    # call_getaddrinfo: the resolver's entries for these hints, each hint
    # nil or in a socket's form.
    def call_getaddrinfo(node, service, family, socktype, protocol, flags, socktype_hack: false)
      Primitive.attr! :hidden
      Socket.resolve(node, service,
                     family: family.nil? ? Socket::PF_UNSPEC : Socket.family_arg(family),
                     socktype: socktype.nil? ? 0 : Socket.socktype_arg(socktype),
                     protocol: protocol.nil? ? 0 : Integer.send(:int_operand, protocol),
                     flags: flags.nil? ? 0 : Integer.send(:int_operand, flags),
                     socktype_hack: socktype_hack)
    end

    # addrinfo_firstonly_new.
    def firstonly(node, service, family, socktype, protocol, flags)
      Primitive.attr! :hidden
      rows = call_getaddrinfo(node, service, family, socktype, protocol, flags)
      af, kind, proto, sockaddr, canonical = rows[0]
      build(sockaddr, af, kind, proto, canonical&.freeze, inspectname(node, service, sockaddr))
    end

    # make_inspectname: the host and the service as they were given,
    # each left out when it reads the same as the result.
    def inspectname(node, service, sockaddr)
      Primitive.attr! :hidden
      answer = Primitive.zr_sock_getnameinfo(sockaddr, Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV, 3)
      unless answer.is_a?(Integer)
        host, port = answer
        node = nil if node.is_a?(String) && host == node.b.sub(/\0.*/m, "")
        if service.is_a?(String)
          service = nil if port == service.b.sub(/\0.*/m, "")
        elsif Primitive.zr_fixnum_p_m(service) && Socket.send(:atoi, port) == Integer.send(:int_operand, service)
          service = nil
        end
      end
      name = node.is_a?(String) ? node.dup : nil
      if service.is_a?(String)
        name = name.nil? ? ":#{Socket.cstr(service)}" : name << ":#{Socket.cstr(service)}"
      elsif Primitive.zr_fixnum_p_m(service) && Integer.send(:int_operand, service).nonzero?
        name = name.nil? ? ":#{service}" : name << ":#{service}"
      end
      name&.freeze
    end

    # rsock_inspect_sockaddr: an address as an inspect shows it, even one
    # too short or too long for its family.
    def inspect_sockaddr(bytes)
      Primitive.attr! :hidden
      return "empty-sockaddr" if bytes.empty?
      return "too-short-sockaddr" if bytes.bytesize < 2

      family = Socket.sockaddr_family(bytes)
      case family
      when Socket::AF_UNSPEC then "UNSPEC"
      when Socket::AF_INET then inspect_in(bytes)
      when Socket::AF_INET6 then inspect_in6(bytes)
      when Socket::AF_UNIX then inspect_un(bytes)
      when Socket::AF_LINK then inspect_dl(bytes)
      else
        name = Socket.intern(family, /\AAF_/)
        name ? "#{name} address format unknown" : "unknown address family #{family}"
      end
    end

    def inspect_in(bytes)
      Primitive.attr! :hidden
      text = (0..3).map { |i| bytes.bytesize >= 5 + i ? bytes.getbyte(4 + i).to_s : "?" }.join(".")
      if bytes.bytesize > 4
        port = bytes.byteslice(2, 2).unpack1("n")
        text << ":#{port}" if port.nonzero?
      else
        text << ":?"
      end
      text << " (#{bytes.bytesize} bytes for 16 bytes sockaddr_in)" unless bytes.bytesize == 16
      text
    end

    def inspect_in6(bytes)
      Primitive.attr! :hidden
      return "too-short-AF_INET6-sockaddr #{bytes.bytesize} bytes" if bytes.bytesize < 28

      host = Socket.make_ipaddr(bytes)
      port = bytes.byteslice(2, 2).unpack1("n")
      text = port.zero? ? host.dup : "[#{host}]:#{port}"
      text << "(sockaddr #{bytes.bytesize - 28} bytes too long)" if bytes.bytesize > 28
      text
    end

    def inspect_un(bytes)
      Primitive.attr! :hidden
      length = unix_path_length(bytes)
      return "too-short-AF_UNIX-sockaddr" if length.negative?
      return "empty-path-AF_UNIX-sockaddr" if length.zero?

      path = bytes.byteslice(2, length)
      if path.each_byte.all? { |byte| byte > 0x20 && byte < 0x7f }
        path.start_with?("/") ? path : "UNIX #{path}"
      else
        "UNIX#{path.each_byte.map { |byte| format(":%02x", byte) }.join}"
      end
    end

    # A sockaddr_dl: the interface's name and its link address.
    def inspect_dl(bytes)
      Primitive.attr! :hidden
      size = bytes.bytesize
      parts = []
      name = nil
      if size > 8
        nlen = [bytes.getbyte(5), size - 8].min
        name = bytes.byteslice(8, nlen).sub(/\0.*/m, "")
      end
      parts << (name || "?")
      offset = size > 5 ? bytes.getbyte(5) : 0
      if 8 + offset < size
        alen = [bytes.getbyte(6), size - 8 - offset].min
        parts << bytes.byteslice(8 + offset, alen).unpack("C*").map { |byte| format("%02x", byte) }.join(":") if alen.positive?
      end
      needed = size >= 8 ? 8 + bytes.getbyte(5) + bytes.getbyte(6) + bytes.getbyte(7) : Float::INFINITY
      parts << "(#{size} bytes for 20 bytes sockaddr_dl)" if size < 8 || size < needed
      "LINK[#{parts.join(" ")}]"
    end

    # unixsocket_len: the path's bytes, trailing NULs left out.
    def unix_path_length(bytes)
      Primitive.attr! :hidden
      stop = bytes.bytesize
      stop -= 1 while stop > 2 && bytes.getbyte(stop - 1).zero?
      stop - 2
    end
  end

  private

  def assign(sockaddr, pfamily, socktype, protocol, canonname, inspectname)
    Primitive.attr! :hidden
    raise ArgumentError, "sockaddr string too big" if sockaddr.bytesize > SOCKADDR_MAX

    @sockaddr = sockaddr.b.freeze
    @pfamily = pfamily
    @socktype = socktype
    @protocol = protocol
    @canonname = canonname
    @inspectname = inspectname
    self
  end

  def without_kind
    Primitive.attr! :hidden
    @socktype = 0
    @protocol = 0
    self
  end

  # init_unix_addrinfo.
  def assign_unix(path, socktype)
    Primitive.attr! :hidden
    raise ArgumentError, "too long unix socket path (#{path.bytesize} bytes given but #{Socket.unix_path_max} bytes max)" if path.bytesize > Socket.unix_path_max

    assign(Socket.pack_unix(path), Socket::PF_UNIX, socktype, 0, nil, nil)
  end

  # get_addrinfo: the address's bytes, which an allocated Addrinfo has
  # none of yet.
  def sockaddr_bytes
    Primitive.attr! :hidden
    checked
    @sockaddr
  end

  def checked
    Primitive.attr! :hidden
    raise TypeError, "uninitialized socket address" if @sockaddr.nil?
  end

  # get_afamily: the family, when the address is long enough to have one.
  def family_of(bytes)
    Primitive.attr! :hidden
    Socket.sockaddr_family(bytes)
  end

  def numeric_nameinfo
    Primitive.attr! :hidden
    raise SocketError, "need IPv4 or IPv6 address" unless ip?

    Socket.nameinfo(@sockaddr, Socket::NI_NUMERICHOST | Socket::NI_NUMERICSERV)
  end

  # The IPv4 address, in host order.
  def in_addr
    Primitive.attr! :hidden
    @sockaddr.byteslice(4, 4).unpack1("N")
  end

  # The IPv6 address's sixteen bytes.
  def in6_addr
    Primitive.attr! :hidden
    @sockaddr.byteslice(8, 16).unpack("C*")
  end

  def multicast_scope?(scope)
    Primitive.attr! :hidden
    ipv6? && in6_addr[0] == 0xff && (in6_addr[1] & 0x0f) == scope
  end
end
