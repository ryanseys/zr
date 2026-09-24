# Linux's half of the socket calls: a sockaddr that starts with a 16-bit
# family, the layouts of struct addrinfo and struct msghdr, h_errno, and
# the peer's credentials.
Machine.import "__h_errno_location", [] => Ptr

EPROTOTYPE = 91
EAI_SYSTEM = 0 - 11

# struct msghdr: the name and its length, the iovecs and their count,
# the control buffer and its length as 32 bits at 40, and the flags at
# 48.
MSGHDR_LEN = 56
MSGHDR_FLAGS = 48

# A sockaddr's length as rsock_sockaddr_len reads it: the size of its
# family's structure. AF_UNIX is 1, AF_INET 2, AF_INET6 10, and an
# AF_PACKET (17) address is as long as its hardware address says.
sig [Ptr] => Word
machine def zr_os_sockaddr_len(addr)
  family = Machine.word(Machine.load32(addr, 0)) & 65535
  if family == 2
    return 16
  end
  if family == 10
    return 28
  end
  if family == 1
    return 110
  end
  if family == 17
    return 12 + Machine.word(Machine.load8(addr, 11))
  end
  2
end

# One resolver answer as [family, socktype, protocol, sockaddr,
# canonical name or nil]: musl's addrinfo keeps the address's length at
# 16, the address at 24 and the canonical name at 32.
sig [Ptr] => Value
machine def zr_os_addrinfo_row(node)
  row = zr_ary_new(5)
  zr_ary_push(row, zr_fix(Machine.word(Machine.load32(node, 4))))
  zr_ary_push(row, zr_fix(Machine.word(Machine.load32(node, 8))))
  zr_ary_push(row, zr_fix(Machine.word(Machine.load32(node, 12))))
  zr_ary_push(row, zr_sock_bytes(Machine.ptr(Machine.load64(node, 24)), Machine.word(Machine.load32(node, 16))))
  zr_ary_push(row, zr_sock_cstr(Machine.ptr(Machine.load64(node, 32))))
  row
end

sig [Ptr] => Ptr
machine def zr_os_addrinfo_next(node)
  Machine.ptr(Machine.load64(node, 40))
end

# The resolver's last failure, which gethostbyaddr leaves in h_errno.
sig [] => Word
machine def zr_os_h_errno
  Machine.word(Machine.load32(__h_errno_location(), 0))
end

# SO_PEERCRED at SOL_SOCKET: a struct ucred of the peer's pid, uid and
# gid, as ruby's getpeereid reads it on Linux.
SOL_SOCKET = 1
SO_PEERCRED = 17

# The peer's effective user and group.
sig [Value] => Value
machine def zr_os_peereid(fd)
  cred = Machine.slot(16)
  size = Machine.slot(8)
  Machine.store32(size, 0, Machine.i32(12))
  if getsockopt(zr_sock_fd(fd), Machine.i32(SOL_SOCKET), Machine.i32(SO_PEERCRED), cred, size) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(cred, 4))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(cred, 8))))
  out
end
