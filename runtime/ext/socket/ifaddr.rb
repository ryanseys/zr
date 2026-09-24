# frozen_string_literal: true

# ifaddr.c: one interface address getifaddrs(3) answered, its name,
# flags and addresses read when the list was.
class Socket < BasicSocket
  class Ifaddr
    Primitive.zr_undef_alloc(self)

    # The flags ifaddr_inspect_flags names, in its order.
    FLAG_NAMES = %i[UP BROADCAST DEBUG LOOPBACK POINTOPOINT RUNNING NOARP PROMISC NOTRAILERS ALLMULTI SIMPLEX MULTICAST].freeze
    private_constant :FLAG_NAMES

    def name = @name.dup

    def ifindex
      index = Primitive.zr_sock_if_index(@name)
      raise ArgumentError, "invalid interface name: #{@name}" if index.zero?

      index
    end

    attr_reader :flags

    def addr = @addr && Socket.sockaddr_obj(@addr)

    def netmask = @netmask && Socket.sockaddr_obj(@netmask)

    def broadaddr = (@flags & IFF_BROADCAST).nonzero? && @dstaddr ? Socket.sockaddr_obj(@dstaddr) : nil

    def dstaddr = (@flags & IFF_POINTOPOINT).nonzero? && @dstaddr ? Socket.sockaddr_obj(@dstaddr) : nil

    def inspect
      text = +"#<#{Primitive.zr_class_path(Primitive.zr_real_class(self))} #{@name}"
      text << Ifaddr.shown_flags(@flags) if @flags.nonzero?
      text << " " << Addrinfo.inspect_sockaddr(@addr) if @addr
      text << " netmask=" << Addrinfo.inspect_sockaddr(@netmask) if @netmask
      text << " broadcast=" << Addrinfo.inspect_sockaddr(@dstaddr) if (@flags & IFF_BROADCAST).nonzero? && @dstaddr
      text << " dstaddr=" << Addrinfo.inspect_sockaddr(@dstaddr) if (@flags & IFF_POINTOPOINT).nonzero? && @dstaddr
      Primitive.zr_obj_form(text << ">")
    end

    class << self
      # Every row as an Ifaddr.
      def list
        Primitive.attr! :hidden
        Socket.ifaddr_rows.map { |row| Primitive.zr_class_build(Ifaddr).__send__(:assign, *row) }
      end

      def shown_flags(flags)
        Primitive.attr! :hidden
        names = FLAG_NAMES.filter_map do |name|
          bit = Socket.const_get(:"IFF_#{name}")
          next if (flags & bit).zero?

          flags &= ~bit
          name
        end
        names << format("%#x", flags) if flags.nonzero?
        " #{names.join(",")}"
      end
    end

    private

    def assign(name, flags, addr, netmask, dstaddr)
      Primitive.attr! :hidden
      @name = name
      @flags = flags
      @addr = addr
      @netmask = netmask
      @dstaddr = dstaddr
      self
    end
  end

  def self.getifaddrs = Ifaddr.list
end
