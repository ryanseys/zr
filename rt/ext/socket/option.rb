# frozen_string_literal: true

# option.c: one socket option's family, level, name and bytes, which
# read back as the number, the flag or the structure the option holds.
class Socket < BasicSocket
  class Option
    def initialize(family, level, optname, data)
      family = Socket.family_arg(family)
      level = Socket.level_arg(family, level)
      assign(family, level, Socket.optname_arg(family, level, optname), data)
    end

    def family = @family

    def level = Integer.send(:int_operand, @level)

    def optname = Integer.send(:int_operand, @optname)

    def data = Primitive.zr_str_operand(@data)

    alias to_s data

    def unpack(template) = data.unpack(template)

    def int = sized(4, "sizeof(int)").unpack1("i")

    def byte = sized(1, "sizeof(char)").unpack1("C")

    def bool
      bytes = data
      return bytes.getbyte(0) != 0 if bytes.bytesize == 1

      sized(4, "sizeof(int)").unpack1("i") != 0
    end

    def linger
      raise TypeError, "linger socket option expected" unless level == SOL_SOCKET && optname == SO_LINGER

      onoff, secs = sized(8, "sizeof(struct linger)").unpack("ii")
      state = case onoff
              when 0 then false
              when 1 then true
              else onoff
              end
      [state, secs]
    end

    def ipv4_multicast_loop = ipv4_int(IP_MULTICAST_LOOP, "ipv4_multicast_loop")

    def ipv4_multicast_ttl = ipv4_int(IP_MULTICAST_TTL, "ipv4_multicast_ttl")

    def inspect
      family = Integer.send(:int_operand, self.family)
      level = self.level
      optname = self.optname
      bytes = data
      text = +"#<#{Primitive.zr_class_path(Primitive.zr_real_class(self))}:"
      text << ((name = Socket.intern(family, /\AAF_/, "AF_")) ? " #{name}" : " family:#{family}")
      if level == SOL_SOCKET
        text << " SOCKET" << ((name = Socket.intern(optname, /\ASO_/, "SO_")) ? " #{name}" : " optname:#{optname}")
      elsif family == AF_UNIX
        text << " level:#{level}" << ((name = Socket.intern(optname, /\ALOCAL_/, "LOCAL_")) ? " #{name}" : " optname:#{optname}")
      elsif Socket.ip_family?(family)
        text << ((name = Socket.intern(level, /\A(SOL_SOCKET\z|IPPROTO_)/, /\A(SOL_|IPPROTO_)/)) ? " #{name}" : " level:#{level}")
        text << ((name = Option.send(:optname_name, level, optname)) ? " #{name}" : " optname:#{optname}")
      else
        text << " level:#{level} optname:#{optname}"
      end
      shown = Option.send(:shown, level == SOL_SOCKET ? AF_UNSPEC : family, level, optname, bytes)
      Primitive.zr_obj_form(text << (shown || " #{bytes.dump}") << ">")
    end

    class << self
      def int(family, level, optname, value) = packed(family, level, optname, [Integer.send(:int_operand, value)].pack("i"))

      def byte(family, level, optname, value) = packed(family, level, optname, [Integer.send(:int_operand, value) & 0xff].pack("C"))

      def bool(family, level, optname, value) = packed(family, level, optname, [value ? 1 : 0].pack("i"))

      def linger(onoff, secs)
        onoff = Integer.try_convert(onoff) || (onoff ? 1 : 0)
        build(AF_UNSPEC, SOL_SOCKET, SO_LINGER, [Integer.send(:int_operand, onoff), Integer.send(:int_operand, secs)].pack("ii"))
      end

      def ipv4_multicast_loop(value) = build(AF_INET, IPPROTO_IP, IP_MULTICAST_LOOP, [Integer.send(:int_operand, value)].pack("i"))

      def ipv4_multicast_ttl(value) = build(AF_INET, IPPROTO_IP, IP_MULTICAST_TTL, [Integer.send(:int_operand, value)].pack("i"))

      private

      # rsock_sockopt_new: an option of these numbers, as a socket answers
      # one.
      def build(family, level, optname, data)
        Primitive.attr! :hidden
        Primitive.zr_class_build(Option).__send__(:assign, family, level, optname, data)
      end

      def packed(family, level, optname, bytes)
        Primitive.attr! :hidden
        family = Socket.family_arg(family)
        level = Socket.level_arg(family, level)
        build(family, level, Socket.optname_arg(family, level, optname), bytes)
      end

      # optname_to_sym: an IP level's option by name.
      def optname_name(level, optname)
        Primitive.attr! :hidden
        case level
        when SOL_SOCKET then Socket.intern(optname, /\ASO_/, "SO_")
        when IPPROTO_IP then Socket.intern(optname, /\AIP_/, "IP_")
        when IPPROTO_IPV6 then Socket.intern(optname, /\AIPV6_/, "IPV6_")
        when IPPROTO_TCP then Socket.intern(optname, /\ATCP_/, "TCP_")
        when IPPROTO_UDP then Socket.intern(optname, /\AUDP_/, "UDP_")
        end
      end

      # The option's value as sockopt_inspect writes the options it knows
      # here, or nil for one it shows as bytes.
      def shown(family, level, optname, bytes)
        Primitive.attr! :hidden
        case [family, level]
        when [AF_UNSPEC, SOL_SOCKET]
          case optname
          when SO_DEBUG, SO_ACCEPTCONN, SO_BROADCAST, SO_REUSEADDR, SO_KEEPALIVE, SO_OOBINLINE, SO_SNDBUF, SO_RCVBUF, SO_DONTROUTE, SO_RCVLOWAT, SO_SNDLOWAT
            shown_int(bytes)
          when SO_ERROR
            " #{Primitive.zr_io_strerror(bytes.unpack1("i"))} (#{bytes.unpack1("i")})" if bytes.bytesize == 4
          when SO_TYPE
            " #{Socket.intern(bytes.unpack1("i"), /\ASOCK_/) || bytes.unpack1("i")}" if bytes.bytesize == 4
          when SO_LINGER then shown_linger(bytes)
          when SO_RCVTIMEO, SO_SNDTIMEO
            format(" %d.%06dsec", *bytes.unpack("q<l<")) if bytes.bytesize == 16
          end
        when [AF_INET, IPPROTO_IP], [AF_INET6, IPPROTO_IP]
          case optname
          when IP_ADD_MEMBERSHIP, IP_DROP_MEMBERSHIP
            " #{ipv4_text(bytes.byteslice(0, 4))} #{ipv4_text(bytes.byteslice(4, 4))}" if bytes.bytesize == 8
          when IP_MULTICAST_LOOP, IP_MULTICAST_TTL then shown_int(bytes)
          end
        when [AF_INET, IPPROTO_IPV6], [AF_INET6, IPPROTO_IPV6]
          case optname
          when IPV6_MULTICAST_HOPS, IPV6_UNICAST_HOPS, IPV6_V6ONLY then shown_int(bytes)
          when IPV6_MULTICAST_LOOP then " #{bytes.unpack1("L")}" if bytes.bytesize == 4
          when IPV6_MULTICAST_IF then interface(" ", " ", bytes.unpack1("L")) if bytes.bytesize == 4
          when IPV6_JOIN_GROUP, IPV6_LEAVE_GROUP
            " #{ipv6_text(bytes.byteslice(0, 16))}#{interface(" ", " interface:", bytes.byteslice(16, 4).unpack1("L"))}" if bytes.bytesize == 20
          end
        when [AF_INET, IPPROTO_TCP], [AF_INET6, IPPROTO_TCP]
          shown_int(bytes) if optname == TCP_NODELAY
        when [AF_UNIX, 0]
          shown_xucred(bytes) if optname == LOCAL_PEERCRED
        end
      end

      def shown_int(bytes)
        Primitive.attr! :hidden
        " #{bytes.unpack1("i")}" if bytes.bytesize == 4
      end

      def shown_linger(bytes)
        Primitive.attr! :hidden
        return nil unless bytes.bytesize == 8

        onoff, secs = bytes.unpack("ii")
        state = case onoff
                when 0 then "off"
                when 1 then "on"
                else "on(#{onoff})"
                end
        " #{state} #{secs}sec"
      end

      # struct xucred: its version, its user and its groups.
      def shown_xucred(bytes)
        Primitive.attr! :hidden
        return nil unless bytes.bytesize == 76

        version, uid, count = bytes.unpack("LLs")
        return nil unless version.zero?

        groups = bytes.byteslice(12, 64).unpack("L16").first(count)
        " version=#{version} euid=#{uid}#{" groups=#{groups.join(",")}" unless groups.empty?} (xucred)"
      end

      def ipv4_text(bytes)
        Primitive.attr! :hidden
        bytes.unpack("C4").join(".")
      end

      def ipv6_text(bytes)
        Primitive.attr! :hidden
        Socket.make_ipaddr([28, AF_INET6, 0, 0].pack("CCnN") + bytes + "\0\0\0\0")
      end

      # rb_if_indextoname: the interface an index names, after one prefix,
      # or the index after the other when it names none.
      def interface(named, unnamed, index)
        Primitive.attr! :hidden
        name = Primitive.zr_sock_if_name(index)
        name ? "#{named}#{name}" : "#{unnamed}#{index}"
      end
    end

    private

    def assign(family, level, optname, data)
      Primitive.attr! :hidden
      @family = family
      @level = level
      @optname = optname
      @data = Primitive.zr_str_operand(data)
      self
    end

    # check_size: the bytes, which must be `size` of them.
    def sized(size, spelled)
      Primitive.attr! :hidden
      bytes = data
      raise TypeError, "size differ.  expected as #{spelled}=#{size} but #{bytes.bytesize}" unless bytes.bytesize == size

      bytes
    end

    def ipv4_int(name, spelled)
      Primitive.attr! :hidden
      raise TypeError, "#{spelled} socket option expected" unless Integer.send(:int_operand, family) == AF_INET && level == IPPROTO_IP && optname == name

      int
    end
  end
end
