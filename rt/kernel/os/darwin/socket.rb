# darwin's half of the socket calls: the BSD sockaddr with its length
# byte, the layout of struct addrinfo, h_errno, and getpeereid.
Machine.import "getpeereid", [I32, Ptr, Ptr] => I32

# A connected datagram socket on this platform can refuse a send with
# EPROTOTYPE for a moment while it tears down, and ruby tries again.
EPROTOTYPE = 41
EAI_SYSTEM = 11

# A sockaddr's length as rsock_sockaddr_len reads it: its own length
# byte, else the size of its family's structure.
sig [Ptr] => Word
machine def zr_os_sockaddr_len(addr)
  n = Machine.word(Machine.load8(addr, 0))
  if n != 0
    return n
  end
  family = Machine.word(Machine.load8(addr, 1))
  if family == 2
    return 16
  end
  if family == 30
    return 28
  end
  family == 1 ? 106 : 2
end

# One resolver answer as [family, socktype, protocol, sockaddr,
# canonical name or nil]: darwin's addrinfo keeps the address's length
# at 16, the canonical name at 24 and the address at 32.
sig [Ptr] => Value
machine def zr_os_addrinfo_row(node)
  row = zr_ary_new(5)
  zr_ary_push(row, zr_fix(Machine.word(Machine.load32(node, 4))))
  zr_ary_push(row, zr_fix(Machine.word(Machine.load32(node, 8))))
  zr_ary_push(row, zr_fix(Machine.word(Machine.load32(node, 12))))
  zr_ary_push(row, zr_sock_bytes(Machine.ptr(Machine.load64(node, 32)), Machine.word(Machine.load32(node, 16))))
  zr_ary_push(row, zr_sock_cstr(Machine.ptr(Machine.load64(node, 24))))
  row
end

sig [Ptr] => Ptr
machine def zr_os_addrinfo_next(node)
  Machine.ptr(Machine.load64(node, 40))
end

# The resolver's last failure, which gethostbyaddr leaves in h_errno.
sig [] => Word
machine def zr_os_h_errno
  Machine.word(Machine.load32(Machine.extern(:h_errno), 0))
end

# The peer's effective user and group.
sig [Value] => Value
machine def zr_os_peereid(fd)
  ids = Machine.slot(8)
  if getpeereid(zr_sock_fd(fd), ids, ids + 4) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(ids, 0))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(ids, 4))))
  out
end
