# frozen_string_literal: true

# Linux's socket structures, as musl lays them out: a sockaddr starts
# with its family as 16 bits and records no length, a sockaddr_un has
# 108 bytes of path, and a cmsghdr is a word-wide length and two ints,
# each control message padded to 8 bytes.
class Socket < BasicSocket
  UNIX_PATH_MAX = 108
  CMSG_HEADER = 16
  CMSG_HEADER_PACK = "Q<ii"
  CMSG_ALIGN = 8
  KAME = false
  private_constant :UNIX_PATH_MAX, :CMSG_HEADER, :CMSG_HEADER_PACK, :CMSG_ALIGN, :KAME

  class << self
    # The two bytes a sockaddr of `family` starts with; Linux keeps no
    # `length`.
    def sockaddr_head(family, _length)
      Primitive.attr! :hidden
      [family].pack("S<")
    end

    # The family a sockaddr names, or AF_UNSPEC when it is too short to
    # name one.
    def sockaddr_family(bytes)
      Primitive.attr! :hidden
      bytes.bytesize < 2 ? AF_UNSPEC : bytes.unpack1("S<")
    end
  end
end
