module Zr::Kern
  # The WASI part of the socket calls. WASI preview 1 has no sockets. The
  # constants are wasi-libc's values. The calls that read a resolver
  # result or a peer address find nothing.
  EPROTOTYPE = 67
  EAI_SYSTEM = 0 - 11
  # wasi-libc's struct msghdr. No call in this file fills it.
  MSGHDR_LEN = 28
  MSGHDR_FLAGS = 24

  # A sockaddr in the wasi-libc layout, which has no length byte. These are
  # the structure size for each family, and the family numbers: AF_INET 1,
  # AF_INET6 2 and AF_UNIX 3.
  #: (ptr) -> word
  def zr_os_sockaddr_len(addr)
    family = Machine.u8(Machine.load8(addr, 0)) | (Machine.u8(Machine.load8(addr, 1)) << 8)
    if family == 1
      return 16
    end
    if family == 2
      return 28
    end
    family == 3 ? 110 : 2
  end

  #: (ptr) -> value
  def zr_os_addrinfo_row(node)
    Machine.value(QNIL)
  end

  #: (ptr) -> ptr
  def zr_os_addrinfo_next(node)
    Machine.ptr(0)
  end

  #: () -> word
  def zr_os_h_errno
    0
  end

  #: (value) -> value
  def zr_os_peereid(fd)
    zr_notimplement(Machine.bytes("getpeereid"), 10)
  end
end
