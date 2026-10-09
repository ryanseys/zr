# frozen_string_literal: true

# darwin's socket structures, as BSD lays them out: a sockaddr starts
# with its own length byte and then its family byte, a sockaddr_un has
# 104 bytes of path, and a cmsghdr is three 32-bit words, each control
# message padded to 4 bytes. The IPv6 stack is KAME's.
class Socket < BasicSocket
  UNIX_PATH_MAX = 104
  CMSG_HEADER = 12
  CMSG_HEADER_PACK = "Lii"
  CMSG_ALIGN = 4
  KAME = true
  # Whether a sockaddr records its own length (sa_len).
  SA_LEN = true
  private_constant :UNIX_PATH_MAX, :CMSG_HEADER, :CMSG_HEADER_PACK, :CMSG_ALIGN, :KAME, :SA_LEN

  class << self
    # The two bytes a sockaddr of `family` starts with, `length` bytes in
    # all.
    def sockaddr_head(family, length)
      Primitive.attr! :hidden
      [length, family].pack("CC")
    end

    # The family a sockaddr names, or AF_UNSPEC when it is too short to
    # name one.
    def sockaddr_family(bytes)
      Primitive.attr! :hidden
      bytes.bytesize < 2 ? AF_UNSPEC : bytes.getbyte(1)
    end
  end
end
