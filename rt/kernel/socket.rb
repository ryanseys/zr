# Sockets over libSystem. The kernel does the calls with byte buffers;
# the address structures are built and read in ruby, so a sockaddr
# crosses this line as a String.
Machine.import "socket", [I32, I32, I32] => I32
Machine.import "bind", [I32, Ptr, I32] => I32
Machine.import "listen", [I32, I32] => I32
Machine.import "accept", [I32, Ptr, Ptr] => I32
Machine.import "connect", [I32, Ptr, I32] => I32
Machine.import "send", [I32, Ptr, Word, I32] => Word
Machine.import "sendto", [I32, Ptr, Word, I32, Ptr, I32] => Word
Machine.import "recv", [I32, Ptr, Word, I32] => Word
Machine.import "recvfrom", [I32, Ptr, Word, I32, Ptr, Ptr] => Word
Machine.import "shutdown", [I32, I32] => I32
Machine.import "getsockname", [I32, Ptr, Ptr] => I32
Machine.import "getpeername", [I32, Ptr, Ptr] => I32
Machine.import "getsockopt", [I32, I32, I32, Ptr, Ptr] => I32
Machine.import "setsockopt", [I32, I32, I32, Ptr, I32] => I32
Machine.import "socketpair", [I32, I32, I32, Ptr] => I32
Machine.import "getaddrinfo", [Ptr, Ptr, Ptr, Ptr] => I32
Machine.import "freeaddrinfo", [Ptr] => I32
Machine.import "gai_strerror", [I32] => Ptr
Machine.import "getnameinfo", [Ptr, I32, Ptr, I32, Ptr, I32, I32] => I32
Machine.import "gethostname", [Ptr, Word] => I32

# The largest sockaddr, which holds a unix path as well as IPv6.
SOCKADDR_MAX = 128

sig [Value, Value, Value] => Value
machine def zr_sock_socket(domain, type, protocol)
  zr_io_failed(Machine.sword(socket(Machine.i32(zr_fix2long(domain)), Machine.i32(zr_fix2long(type)), Machine.i32(zr_fix2long(protocol)))))
end

sig [Value, Value] => Value
machine def zr_sock_bind(fd, addr)
  zr_io_status(bind(Machine.i32(zr_fix2long(fd)), RString.ptr(addr), Machine.i32(RString.len(addr))))
end

sig [Value, Value] => Value
machine def zr_sock_connect(fd, addr)
  zr_io_status(connect(Machine.i32(zr_fix2long(fd)), RString.ptr(addr), Machine.i32(RString.len(addr))))
end

sig [Value, Value] => Value
machine def zr_sock_listen(fd, backlog)
  zr_io_status(listen(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(backlog))))
end

sig [Value, Value] => Value
machine def zr_sock_shutdown(fd, how)
  zr_io_status(shutdown(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(how))))
end

# The descriptor and the peer's address, or the negated errno.
sig [Value] => Value
machine def zr_sock_accept(fd)
  addr = Machine.slot(SOCKADDR_MAX)
  size = Machine.slot(8)
  Machine.store32(size, 0, Machine.i32(SOCKADDR_MAX))
  r = accept(Machine.i32(zr_fix2long(fd)), addr, size)
  while r < Machine.i32(0)
    failed = zr_io_retry()
    if failed != QNIL
      return failed
    end
    r = accept(Machine.i32(zr_fix2long(fd)), addr, size)
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(Machine.word(r)))
  zr_ary_push(out, zr_str_new(addr, Machine.word(Machine.load32(size, 0))))
  out
end

sig [Value, Value, Value] => Value
machine def zr_sock_send(fd, text, flags)
  zr_io_failed(send(Machine.i32(zr_fix2long(fd)), RString.ptr(text), RString.len(text), Machine.i32(zr_fix2long(flags))))
end

sig [Value, Value, Value, Value] => Value
machine def zr_sock_sendto(fd, text, flags, addr)
  zr_io_failed(sendto(Machine.i32(zr_fix2long(fd)), RString.ptr(text), RString.len(text),
                      Machine.i32(zr_fix2long(flags)), RString.ptr(addr), Machine.i32(RString.len(addr))))
end

# Up to `count` bytes: a String, nil at the end, or the negated errno.
sig [Value, Value, Value] => Value
machine def zr_sock_recv(fd, count, flags)
  n = zr_fix2long(count)
  buffer = zr_xmalloc(n)
  r = recv(Machine.i32(zr_fix2long(fd)), buffer, n, Machine.i32(zr_fix2long(flags)))
  while r < 0
    failed = zr_io_retry()
    if failed != QNIL
      free(buffer)
      return failed
    end
    r = recv(Machine.i32(zr_fix2long(fd)), buffer, n, Machine.i32(zr_fix2long(flags)))
  end
  if r == 0
    free(buffer)
    return QNIL
  end
  out = zr_str_new(buffer, r)
  free(buffer)
  out
end

# The bytes and the sender's address, nil at the end, or the errno.
sig [Value, Value, Value] => Value
machine def zr_sock_recvfrom(fd, count, flags)
  n = zr_fix2long(count)
  buffer = zr_xmalloc(n)
  addr = Machine.slot(SOCKADDR_MAX)
  size = Machine.slot(8)
  Machine.store32(size, 0, Machine.i32(SOCKADDR_MAX))
  r = recvfrom(Machine.i32(zr_fix2long(fd)), buffer, n, Machine.i32(zr_fix2long(flags)), addr, size)
  while r < 0
    failed = zr_io_retry()
    if failed != QNIL
      free(buffer)
      return failed
    end
    r = recvfrom(Machine.i32(zr_fix2long(fd)), buffer, n, Machine.i32(zr_fix2long(flags)), addr, size)
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_str_new(buffer, r))
  zr_ary_push(out, zr_str_new(addr, Machine.word(Machine.load32(size, 0))))
  free(buffer)
  out
end

sig [Value] => Value
machine def zr_sock_getsockname(fd)
  addr = Machine.slot(SOCKADDR_MAX)
  size = Machine.slot(8)
  Machine.store32(size, 0, Machine.i32(SOCKADDR_MAX))
  if getsockname(Machine.i32(zr_fix2long(fd)), addr, size) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_str_new(addr, Machine.word(Machine.load32(size, 0)))
end

sig [Value] => Value
machine def zr_sock_getpeername(fd)
  addr = Machine.slot(SOCKADDR_MAX)
  size = Machine.slot(8)
  Machine.store32(size, 0, Machine.i32(SOCKADDR_MAX))
  if getpeername(Machine.i32(zr_fix2long(fd)), addr, size) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_str_new(addr, Machine.word(Machine.load32(size, 0)))
end

sig [Value, Value, Value, Value] => Value
machine def zr_sock_getsockopt(fd, level, name, size)
  n = zr_fix2long(size)
  buffer = zr_xmalloc(n)
  length = Machine.slot(8)
  Machine.store32(length, 0, Machine.i32(n))
  r = getsockopt(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(level)), Machine.i32(zr_fix2long(name)), buffer, length)
  if r < Machine.i32(0)
    free(buffer)
    return zr_fix(0 - zr_errno())
  end
  out = zr_str_new(buffer, Machine.word(Machine.load32(length, 0)))
  free(buffer)
  out
end

sig [Value, Value, Value, Value] => Value
machine def zr_sock_setsockopt(fd, level, name, text)
  zr_io_status(setsockopt(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(level)),
                          Machine.i32(zr_fix2long(name)), RString.ptr(text), Machine.i32(RString.len(text))))
end

# Two connected descriptors of the same kind.
sig [Value, Value, Value] => Value
machine def zr_sock_socketpair(domain, type, protocol)
  fds = Machine.slot(8)
  if socketpair(Machine.i32(zr_fix2long(domain)), Machine.i32(zr_fix2long(type)), Machine.i32(zr_fix2long(protocol)), fds) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(fds, 0))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(fds, 4))))
  out
end

sig [] => Value
machine def zr_sock_hostname
  buffer = Machine.slot(256)
  if gethostname(buffer, 256) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_cstr_str(buffer)
end

# Every address a host and service name stand for, each row
# [family, socktype, protocol, sockaddr, canonical name]. A resolver
# failure answers its own message, so a caller can name it.
sig [Value, Value, Value, Value, Value, Value] => Value
machine def zr_sock_getaddrinfo(host, service, family, socktype, protocol, flags)
  hints = Machine.slot(48)
  i = 0
  while i < 48
    Machine.store8(hints + i, 0, 0)
    i += 1
  end
  Machine.store32(hints, 0, Machine.i32(zr_fix2long(flags)))
  Machine.store32(hints, 4, Machine.i32(zr_fix2long(family)))
  Machine.store32(hints, 8, Machine.i32(zr_fix2long(socktype)))
  Machine.store32(hints, 12, Machine.i32(zr_fix2long(protocol)))
  head = Machine.slot(8)
  Machine.store64(head, 0, 0)
  r = getaddrinfo(host == QNIL ? 0 : RString.ptr(host), service == QNIL ? 0 : RString.ptr(service), hints, head)
  if r != Machine.i32(0)
    return zr_fix(Machine.word(r))
  end
  out = zr_ary_new(4)
  node = Machine.ptr(Machine.load64(head, 0))
  while Machine.word(node) != 0
    row = zr_ary_new(5)
    zr_ary_push(row, zr_fix(Machine.word(Machine.load32(node, 4))))
    zr_ary_push(row, zr_fix(Machine.word(Machine.load32(node, 8))))
    zr_ary_push(row, zr_fix(Machine.word(Machine.load32(node, 12))))
    zr_ary_push(row, zr_str_new(Machine.ptr(Machine.load64(node, 32)), Machine.word(Machine.load32(node, 16))))
    canon = Machine.ptr(Machine.load64(node, 24))
    zr_ary_push(row, Machine.word(canon) == 0 ? QNIL : zr_cstr_str(canon))
    zr_ary_push(out, row)
    node = Machine.ptr(Machine.load64(node, 40))
  end
  freeaddrinfo(Machine.ptr(Machine.load64(head, 0)))
  out
end

# The host and service name an address stands for, or the resolver's
# own message.
sig [Value, Value] => Value
machine def zr_sock_getnameinfo(addr, flags)
  host = Machine.slot(1025)
  service = Machine.slot(64)
  r = getnameinfo(RString.ptr(addr), Machine.i32(RString.len(addr)), host, Machine.i32(1025),
                  service, Machine.i32(64), Machine.i32(zr_fix2long(flags)))
  if r != Machine.i32(0)
    return zr_fix(Machine.word(r))
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_cstr_str(host))
  zr_ary_push(out, zr_cstr_str(service))
  out
end

# What the resolver calls a failure code.
sig [Value] => Value
machine def zr_sock_gai_message(code)
  zr_cstr_str(gai_strerror(Machine.i32(zr_fix2long(code))))
end
