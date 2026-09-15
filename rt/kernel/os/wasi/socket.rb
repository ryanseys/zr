# WASI's half of the socket calls, which preview 1 does not have: the
# numbers stay wasi-libc's, and the calls that would read a resolver's
# answer or a peer find none.
EPROTOTYPE = 67
EAI_SYSTEM = 0 - 11
# wasi-libc's struct msghdr, which no call here fills.
MSGHDR_LEN = 28
MSGHDR_FLAGS = 24

# A sockaddr as wasi-libc lays it out, with no length byte: the size of
# its family's structure, AF_INET 1, AF_INET6 2 and AF_UNIX 3.
sig [Ptr] => Word
machine def zr_os_sockaddr_len(addr)
  family = Machine.word(Machine.load8(addr, 0)) | (Machine.word(Machine.load8(addr, 1)) << 8)
  if family == 1
    return 16
  end
  if family == 2
    return 28
  end
  family == 3 ? 110 : 2
end

sig [Ptr] => Value
machine def zr_os_addrinfo_row(node)
  Machine.value(QNIL)
end

sig [Ptr] => Ptr
machine def zr_os_addrinfo_next(node)
  Machine.ptr(0)
end

sig [] => Word
machine def zr_os_h_errno
  0
end

sig [Value] => Value
machine def zr_os_peereid(fd)
  zr_notimplement(Machine.bytes("getpeereid"), 10)
end
