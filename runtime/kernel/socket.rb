# Sockets over libSystem, with one call for each operation, as in the C
# part of ext/socket. An address goes across as the bytes of a sockaddr
# in a String, which runtime/ext/socket.so.rb builds and reads. A failed
# call returns the negated errno. A resolver failure returns its own code.
Machine.import "socket", [I32, I32, I32] => I32
Machine.import "socketpair", [I32, I32, I32, Ptr] => I32
Machine.import "bind", [I32, Ptr, I32] => I32
Machine.import "listen", [I32, I32] => I32
Machine.import "accept", [I32, Ptr, Ptr] => I32
Machine.import "connect", [I32, Ptr, I32] => I32
Machine.import "send", [I32, Ptr, Word, I32] => Word
Machine.import "sendto", [I32, Ptr, Word, I32, Ptr, I32] => Word
Machine.import "recvfrom", [I32, Ptr, Word, I32, Ptr, Ptr] => Word
Machine.import "sendmsg", [I32, Ptr, I32] => Word
Machine.import "recvmsg", [I32, Ptr, I32] => Word
Machine.import "shutdown", [I32, I32] => I32
Machine.import "getsockname", [I32, Ptr, Ptr] => I32
Machine.import "getpeername", [I32, Ptr, Ptr] => I32
Machine.import "getsockopt", [I32, I32, I32, Ptr, Ptr] => I32
Machine.import "setsockopt", [I32, I32, I32, Ptr, I32] => I32
Machine.import "getaddrinfo", [Ptr, Ptr, Ptr, Ptr] => I32
Machine.import "freeaddrinfo", [Ptr] => Void
Machine.import "gai_strerror", [I32] => Ptr
Machine.import "getnameinfo", [Ptr, I32, Ptr, I32, Ptr, I32, I32] => I32
Machine.import "gethostname", [Ptr, Word] => I32
Machine.import "gethostbyname", [Ptr] => Ptr
Machine.import "gethostbyaddr", [Ptr, I32, I32] => Ptr
Machine.import "hstrerror", [I32] => Ptr
Machine.import "getservbyname", [Ptr, Ptr] => Ptr
Machine.import "getservbyport", [I32, Ptr] => Ptr
Machine.import "getifaddrs", [Ptr] => I32
Machine.import "freeifaddrs", [Ptr] => Void
Machine.import "if_nametoindex", [Ptr] => I32
Machine.import "if_indextoname", [I32, Ptr] => Ptr
Machine.import "inet_pton", [I32, Ptr, Ptr] => I32

# The largest sockaddr, the size of union_sockaddr. A unix path fits in
# it, and so does each other family.
SOCKADDR_MAX = 256

# Makes a binary String from bytes or from a C string, as rb_str_new
# does. A null C string gives nil.
sig [Ptr, Word] => Value
machine def zr_sock_bytes(bytes, len)
  zr_str_set_index(zr_str_new(bytes, len), ENC_BINARY)
end

sig [Ptr] => Value
machine def zr_sock_cstr(text)
  if Machine.word(text) == 0
    return Machine.value(QNIL)
  end
  zr_sock_bytes(text, zr_cstr_len(text))
end

sig [Value] => I32
machine def zr_sock_fd(fd)
  Machine.i32(zr_fix2long(fd))
end

# Makes a descriptor as ruby makes each socket: close-on-exec and
# nonblocking (EAGAIN in place of a wait), so ruby does the wait itself.
sig [Word] => Void
machine def zr_sock_prepare(fd)
  zr_io_cloexec(zr_fix(fd))
  zr_io_set_nonblock(zr_fix(fd), zr_fix(1))
end

sig [Value, Value, Value] => Value
machine def zr_sock_socket(domain, type, protocol)
  fd = Machine.sword(socket(zr_sock_fd(domain), zr_sock_fd(type), zr_sock_fd(protocol)))
  if fd < 0
    return zr_fix(0 - zr_errno())
  end
  zr_sock_prepare(fd)
  zr_fix(fd)
end

# Two connected descriptors of the same kind.
sig [Value, Value, Value] => Value
machine def zr_sock_socketpair(domain, type, protocol)
  fds = Machine.slot(8)
  if socketpair(zr_sock_fd(domain), zr_sock_fd(type), zr_sock_fd(protocol), fds) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_sock_prepare(Machine.word(Machine.load32(fds, 0)))
  zr_sock_prepare(Machine.word(Machine.load32(fds, 4)))
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(fds, 0))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(fds, 4))))
  out
end

sig [Value, Value] => Value
machine def zr_sock_bind(fd, addr)
  zr_io_status(bind(zr_sock_fd(fd), RString.ptr(addr), Machine.i32(RString.len(addr))))
end

sig [Value, Value] => Value
machine def zr_sock_connect(fd, addr)
  zr_io_status(connect(zr_sock_fd(fd), RString.ptr(addr), Machine.i32(RString.len(addr))))
end

sig [Value, Value] => Value
machine def zr_sock_listen(fd, backlog)
  zr_io_status(listen(zr_sock_fd(fd), zr_sock_fd(backlog)))
end

sig [Value, Value] => Value
machine def zr_sock_shutdown(fd, how)
  zr_io_status(shutdown(zr_sock_fd(fd), zr_sock_fd(how)))
end

# The bytes of an address that a call filled in, no longer than the
# space it had. If the kernel gives a larger length, the address was
# truncated (cloexec_accept).
sig [Ptr, Ptr] => Value
machine def zr_sock_addr_str(addr, size)
  n = Machine.word(Machine.load32(size, 0))
  zr_sock_bytes(addr, n > SOCKADDR_MAX ? SOCKADDR_MAX : n)
end

# The accepted descriptor and the peer's address. If a POSIX signal
# interrupts the call, its handler runs and the call starts again.
sig [Value] => Value
machine def zr_sock_accept(fd)
  addr = Machine.slot(SOCKADDR_MAX)
  size = Machine.slot(8)
  Machine.store32(size, 0, Machine.i32(SOCKADDR_MAX))
  r = accept(zr_sock_fd(fd), addr, size)
  while r < Machine.i32(0)
    failed = zr_io_retry()
    if failed != QNIL
      return failed
    end
    Machine.store32(size, 0, Machine.i32(SOCKADDR_MAX))
    r = accept(zr_sock_fd(fd), addr, size)
  end
  zr_sock_prepare(Machine.word(r))
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(Machine.word(r)))
  zr_ary_push(out, zr_sock_addr_str(addr, size))
  out
end

# send(2), or sendto(2) if there is an address. Returns the count sent.
sig [Value, Value, Value, Value] => Value
machine def zr_sock_send(fd, text, flags, addr)
  r = 0
  while true
    if addr == QNIL
      r = send(zr_sock_fd(fd), RString.ptr(text), RString.len(text), zr_sock_fd(flags))
    else
      r = sendto(zr_sock_fd(fd), RString.ptr(text), RString.len(text), zr_sock_fd(flags), RString.ptr(addr), Machine.i32(RString.len(addr)))
    end
    if r >= 0 || zr_errno() != EPROTOTYPE
      return zr_io_failed(r)
    end
  end
  zr_fix(0)
end

# Up to `count` bytes and the sender's address. The address is empty if
# the call does not give one, as for a connected stream on this
# platform.
sig [Value, Value, Value] => Value
machine def zr_sock_recvfrom(fd, count, flags)
  n = zr_fix2long(count)
  buffer = zr_xmalloc(n + 1)
  addr = Machine.slot(SOCKADDR_MAX)
  size = Machine.slot(8)
  Machine.store32(size, 0, Machine.i32(SOCKADDR_MAX))
  r = recvfrom(zr_sock_fd(fd), buffer, n, zr_sock_fd(flags), addr, size)
  while r < 0
    failed = zr_io_retry()
    if failed != QNIL
      zr_xfree(buffer)
      return failed
    end
    Machine.store32(size, 0, Machine.i32(SOCKADDR_MAX))
    r = recvfrom(zr_sock_fd(fd), buffer, n, zr_sock_fd(flags), addr, size)
  end
  if Machine.word(Machine.load32(size, 0)) == SOCKADDR_MAX
    Machine.store32(size, 0, Machine.i32(0))
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_sock_bytes(buffer, r))
  zr_ary_push(out, zr_sock_addr_str(addr, size))
  zr_xfree(buffer)
  out
end

# The bytes of an address written as text, or nil if the text is not an
# address of the family (inet_pton).
sig [Value, Value] => Value
machine def zr_sock_inet_pton(family, text)
  buffer = Machine.slot(16)
  if inet_pton(zr_sock_fd(family), RString.ptr(text), buffer) != Machine.i32(1)
    return Machine.value(QNIL)
  end
  zr_sock_bytes(buffer, zr_fix2long(family) == 2 ? 4 : 16)
end

sig [Value, Value] => Value
machine def zr_sock_name(fd, peer)
  addr = Machine.slot(SOCKADDR_MAX)
  size = Machine.slot(8)
  Machine.store32(size, 0, Machine.i32(SOCKADDR_MAX))
  r = peer == QTRUE ? getpeername(zr_sock_fd(fd), addr, size) : getsockname(zr_sock_fd(fd), addr, size)
  if r < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_sock_addr_str(addr, size)
end

# The bytes of an option, in 256 bytes of space, as in bsock_getsockopt.
sig [Value, Value, Value] => Value
machine def zr_sock_getsockopt(fd, level, name)
  buffer = Machine.slot(256)
  size = Machine.slot(8)
  Machine.store32(size, 0, Machine.i32(256))
  if getsockopt(zr_sock_fd(fd), zr_sock_fd(level), zr_sock_fd(name), buffer, size) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_sock_bytes(buffer, Machine.word(Machine.load32(size, 0)))
end

sig [Value, Value, Value, Value] => Value
machine def zr_sock_setsockopt(fd, level, name, bytes)
  zr_io_status(setsockopt(zr_sock_fd(fd), zr_sock_fd(level), zr_sock_fd(name), RString.ptr(bytes), Machine.i32(RString.len(bytes))))
end

# The host name, up to the NI_MAXHOST length.
sig [] => Value
machine def zr_sock_hostname
  buffer = Machine.slot(1025)
  if gethostname(buffer, 1025) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_sock_cstr(buffer)
end

# A resolver failure: its code, or the negated errno of the system call
# that failed (EAI_SYSTEM).
sig [I32] => Value
machine def zr_sock_gai_failed(r)
  if Machine.sword(r) == EAI_SYSTEM && zr_errno() != 0
    return zr_fix(0 - zr_errno())
  end
  zr_fix(Machine.sword(r))
end

# All addresses for a host and a service. Each entry is [family,
# socktype, protocol, sockaddr, canonical name or nil], in the order
# that the resolver returns them.
sig [Value, Value, Value, Value, Value, Value] => Value
machine def zr_sock_getaddrinfo(host, service, family, socktype, protocol, flags)
  hints = Machine.slot(48)
  i = 0
  while i < 48
    Machine.store8(hints + i, 0, Machine.i8(0))
    i += 1
  end
  Machine.store32(hints, 0, zr_sock_fd(flags))
  Machine.store32(hints, 4, zr_sock_fd(family))
  Machine.store32(hints, 8, zr_sock_fd(socktype))
  Machine.store32(hints, 12, zr_sock_fd(protocol))
  head = Machine.slot(8)
  Machine.store64(head, 0, 0)
  zr_clear_errno()
  r = getaddrinfo(host == QNIL ? 0 : RString.ptr(host), service == QNIL ? 0 : RString.ptr(service), hints, head)
  if r != Machine.i32(0)
    return zr_sock_gai_failed(r)
  end
  out = zr_ary_new(4)
  node = Machine.ptr(Machine.load64(head, 0))
  while Machine.word(node) != 0
    zr_ary_push(out, zr_os_addrinfo_row(node))
    node = zr_os_addrinfo_next(node)
  end
  freeaddrinfo(Machine.ptr(Machine.load64(head, 0)))
  out
end

# The host and the service of an address, in 1024 bytes each, as in
# ruby. `want` selects which ones to get (1 the host, 2 the service).
sig [Value, Value, Value] => Value
machine def zr_sock_getnameinfo(addr, flags, want)
  host = Machine.slot(1024)
  service = Machine.slot(1024)
  w = zr_fix2long(want)
  zr_clear_errno()
  r = getnameinfo(RString.ptr(addr), Machine.i32(RString.len(addr)), (w & 1) != 0 ? host : 0, Machine.i32((w & 1) != 0 ? 1024 : 0),
                  (w & 2) != 0 ? service : 0, Machine.i32((w & 2) != 0 ? 1024 : 0), zr_sock_fd(flags))
  if r != Machine.i32(0)
    return zr_sock_gai_failed(r)
  end
  out = zr_ary_new(2)
  zr_ary_push(out, (w & 1) != 0 ? zr_sock_cstr(host) : Machine.value(QNIL))
  zr_ary_push(out, (w & 2) != 0 ? zr_sock_cstr(service) : Machine.value(QNIL))
  out
end

sig [Value] => Value
machine def zr_sock_gai_message(code)
  zr_sock_cstr(gai_strerror(zr_sock_fd(code)))
end

# The names in a NULL-terminated list of C strings.
sig [Ptr] => Value
machine def zr_sock_cstr_list(list)
  out = zr_ary_new(0)
  if Machine.word(list) == 0
    return out
  end
  while Machine.load64(list, 0) != 0
    zr_ary_push(out, zr_sock_cstr(Machine.ptr(Machine.load64(list, 0))))
    list = list + 8
  end
  out
end

# The aliases that gethostbyname(3) gives for a name, or nil.
sig [Value] => Value
machine def zr_sock_host_aliases(name)
  h = gethostbyname(RString.ptr(name))
  if Machine.word(h) == 0
    return Machine.value(QNIL)
  end
  zr_sock_cstr_list(Machine.ptr(Machine.load64(h, 8)))
end

# gethostbyaddr(3): [name, aliases, family, address bytes...], or the
# resolver's error message.
sig [Value, Value] => Value
machine def zr_sock_host_by_addr(addr, family)
  h = gethostbyaddr(RString.ptr(addr), Machine.i32(RString.len(addr)), zr_sock_fd(family))
  if Machine.word(h) == 0
    return zr_sock_cstr(hstrerror(Machine.i32(zr_os_h_errno())))
  end
  out = zr_ary_new(4)
  zr_ary_push(out, zr_sock_cstr(Machine.ptr(Machine.load64(h, 0))))
  zr_ary_push(out, zr_sock_cstr_list(Machine.ptr(Machine.load64(h, 8))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(h, 16))))
  length = Machine.word(Machine.load32(h, 20))
  list = Machine.ptr(Machine.load64(h, 24))
  while Machine.load64(list, 0) != 0
    zr_ary_push(out, zr_sock_bytes(Machine.ptr(Machine.load64(list, 0)), length))
    list = list + 8
  end
  out
end

# A service's port in host order, or nil.
sig [Value, Value] => Value
machine def zr_sock_service_port(name, protocol)
  s = getservbyname(RString.ptr(name), RString.ptr(protocol))
  if Machine.word(s) == 0
    return Machine.value(QNIL)
  end
  port = Machine.word(Machine.load32(s, 16))
  zr_fix(((port & 255) << 8) | ((port >> 8) & 255))
end

# The service for a port in host order, or nil.
sig [Value, Value] => Value
machine def zr_sock_service_name(port, protocol)
  p = zr_fix2long(port)
  s = getservbyport(Machine.i32(((p & 255) << 8) | ((p >> 8) & 255)), RString.ptr(protocol))
  if Machine.word(s) == 0
    return Machine.value(QNIL)
  end
  zr_sock_cstr(Machine.ptr(Machine.load64(s, 0)))
end

sig [Ptr] => Value
machine def zr_sock_addr_or_nil(addr)
  if Machine.word(addr) == 0
    return Machine.value(QNIL)
  end
  zr_sock_bytes(addr, zr_os_sockaddr_len(addr))
end

# All interface addresses. Each entry is [name, flags, address, netmask,
# broadcast or destination address], with nil for an absent address.
sig [] => Value
machine def zr_sock_ifaddrs
  head = Machine.slot(8)
  if getifaddrs(head) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  out = zr_ary_new(8)
  node = Machine.ptr(Machine.load64(head, 0))
  while Machine.word(node) != 0
    row = zr_ary_new(5)
    zr_ary_push(row, zr_sock_cstr(Machine.ptr(Machine.load64(node, 8))))
    zr_ary_push(row, zr_fix(Machine.word(Machine.load32(node, 16))))
    zr_ary_push(row, zr_sock_addr_or_nil(Machine.ptr(Machine.load64(node, 24))))
    zr_ary_push(row, zr_sock_addr_or_nil(Machine.ptr(Machine.load64(node, 32))))
    zr_ary_push(row, zr_sock_addr_or_nil(Machine.ptr(Machine.load64(node, 40))))
    zr_ary_push(out, row)
    node = Machine.ptr(Machine.load64(node, 0))
  end
  freeifaddrs(Machine.ptr(Machine.load64(head, 0)))
  out
end

sig [Value] => Value
machine def zr_sock_if_index(name)
  zr_fix(Machine.word(if_nametoindex(RString.ptr(name))))
end

# The interface name for an index, or nil.
sig [Value] => Value
machine def zr_sock_if_name(index)
  buffer = Machine.slot(32)
  if Machine.word(if_indextoname(zr_sock_fd(index), buffer)) == 0
    return Machine.value(QNIL)
  end
  zr_sock_cstr(buffer)
end

# sendmsg(2) of one piece of data, to an address if there is one, with
# the bytes of the control messages if there are any.
sig [Value, Value, Value, Value, Value] => Value
machine def zr_sock_sendmsg(fd, data, flags, addr, control)
  header = Machine.slot(MSGHDR_LEN)
  vector = Machine.slot(16)
  memset(header, Machine.i32(0), MSGHDR_LEN)
  Machine.store64(vector, 0, Machine.word(RString.ptr(data)))
  Machine.store64(vector, 8, RString.len(data))
  if addr != QNIL
    Machine.store64(header, 0, Machine.word(RString.ptr(addr)))
    Machine.store32(header, 8, Machine.i32(RString.len(addr)))
  end
  Machine.store64(header, 16, Machine.word(vector))
  Machine.store32(header, 24, Machine.i32(1))
  if control != QNIL
    Machine.store64(header, 32, Machine.word(RString.ptr(control)))
    Machine.store32(header, 40, Machine.i32(RString.len(control)))
  end
  zr_io_failed(sendmsg(zr_sock_fd(fd), header, zr_sock_fd(flags)))
end

# recvmsg(2) into `size` bytes of data and `room` bytes of control
# messages: [data, sender's address, msg_flags, control bytes].
sig [Value, Value, Value, Value] => Value
machine def zr_sock_recvmsg(fd, size, flags, room)
  n = zr_fix2long(size)
  c = zr_fix2long(room)
  data = zr_xmalloc(n + 1)
  control = zr_xmalloc(c + 1)
  name = Machine.slot(SOCKADDR_MAX)
  header = Machine.slot(MSGHDR_LEN)
  vector = Machine.slot(16)
  memset(header, Machine.i32(0), MSGHDR_LEN)
  Machine.store64(vector, 0, Machine.word(data))
  Machine.store64(vector, 8, n)
  Machine.store64(header, 0, Machine.word(name))
  Machine.store32(header, 8, Machine.i32(SOCKADDR_MAX))
  Machine.store64(header, 16, Machine.word(vector))
  Machine.store32(header, 24, Machine.i32(1))
  Machine.store64(header, 32, Machine.word(control))
  Machine.store32(header, 40, Machine.i32(c))
  r = recvmsg(zr_sock_fd(fd), header, zr_sock_fd(flags))
  if r < 0
    zr_xfree(data)
    zr_xfree(control)
    return zr_fix(0 - zr_errno())
  end
  namelen = Machine.word(Machine.load32(header, 8))
  out = zr_ary_new(4)
  zr_ary_push(out, zr_sock_bytes(data, r))
  zr_ary_push(out, zr_sock_bytes(name, namelen > SOCKADDR_MAX ? SOCKADDR_MAX : namelen))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(header, MSGHDR_FLAGS))))
  zr_ary_push(out, zr_sock_bytes(control, Machine.word(Machine.load32(header, 40))))
  zr_xfree(data)
  zr_xfree(control)
  out
end
