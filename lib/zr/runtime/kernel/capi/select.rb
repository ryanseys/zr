module Zr::Kern
  # Waits of C on descriptors that no stream wraps, and ruby's sets of
  # descriptors (rb_fdset_t) that its select takes. Every wait goes to
  # the core's `IO.wait_fds`, so other threads run while C waits, as
  # ruby lets them run in rb_thread_fd_select.

  # rb_fdset_t: the count of descriptors that the bit set covers (an int,
  # which zr_capi_fd_max reads), and the set, an fd_set that grows past
  # FD_SETSIZE. A set's descriptor n is bit n % 8 of byte n / 8 on each
  # OS that zr runs C on.
  class FdSet < Layout
    attr_accessor :maxfd #: word
    attr_accessor :fdset #: ptr
  end

  # sizeof(fd_set): FD_SETSIZE (1024) bits.
  FD_SET_BYTES = 128

  # The RB_WAITFD_* events, which are poll(2)'s.
  WAITFD_IN = 1
  WAITFD_PRI = 2
  WAITFD_OUT = 4

  # rb_fd_init: an empty set.
  #: (ptr) -> void
  def rb_fd_init(set)
    Machine.gates_enter
    zr_c_entered()
    Machine.store32(set, 0, Machine.i32(0))
    FdSet[set].fdset = zr_xmalloc(FD_SET_BYTES)
    Libc.memset(FdSet[set].fdset, Machine.i32(0), FD_SET_BYTES)
  end

  # rb_fd_term: frees the set's bits.
  #: (ptr) -> void
  def rb_fd_term(set)
    Machine.gates_enter
    zr_c_entered()
    zr_xfree(FdSet[set].fdset)
    Machine.store32(set, 0, Machine.i32(0))
    FdSet[set].fdset = 0
  end

  # rb_fd_zero: clears every bit.
  #: (ptr) -> void
  def rb_fd_zero(set)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fd_zero(set)
  end

  # rb_fd_set: adds `fd`, growing the set to reach it.
  #: (i32, ptr) -> void
  def rb_fd_set(fd, set)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fd_add(Machine.sword(fd), set)
  end

  # rb_fd_clr: removes `fd`.
  #: (i32, ptr) -> void
  def rb_fd_clr(fd, set)
    Machine.gates_enter
    zr_c_entered()
    n = Machine.sword(fd)
    if n < zr_capi_fd_max(set)
      at = FdSet[set].fdset + (n >> 3)
      Machine.store8(at, 0, Machine.i8(Machine.u8(Machine.load8(at, 0)) & (255 - (1 << (n & 7)))))
    end
  end

  # rb_fd_isset: whether `fd` is in the set, as 1 or 0.
  #: (i32, ptr) -> i32
  def rb_fd_isset(fd, set)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fd_isset(Machine.sword(fd), set) ? Machine.i32(1) : Machine.i32(0)
  end

  # rb_fd_copy: the set becomes a copy of the first `max` descriptors of
  # the fd_set `src`.
  #: (ptr, ptr, i32) -> void
  def rb_fd_copy(dst, src, max)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fd_assign(dst, src, Machine.sword(max))
  end

  # rb_fd_dup: the set becomes a copy of the set `src`.
  #: (ptr, ptr) -> void
  def rb_fd_dup(dst, src)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fd_assign(dst, FdSet[src].fdset, zr_capi_fd_max(src))
  end

  # rb_fd_select and rb_thread_fd_select: select(2) over the first `n`
  # descriptors of the three sets (each may be NULL), for up to the
  # timeval at `tv` (NULL: on). Each set keeps the descriptors that came
  # ready. The count of their bits, 0 when the time ran out, or -1 with
  # errno set.
  #: (i32, ptr, ptr, ptr, ptr) -> i32
  def rb_fd_select(n, rfds, wfds, efds, tv)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fd_select(Machine.sword(n), rfds, wfds, efds, tv)
  end

  #: (i32, ptr, ptr, ptr, ptr) -> i32
  def rb_thread_fd_select(n, rfds, wfds, efds, tv)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fd_select(Machine.sword(n), rfds, wfds, efds, tv)
  end

  # rb_wait_for_single_fd: waits for the RB_WAITFD_* `events` of `fd`, up
  # to the timeval at `tv`. The events that came ready, 0 when the time
  # ran out, or -1 with errno set.
  #: (i32, i32, ptr) -> i32
  def rb_wait_for_single_fd(fd, events, tv)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_wait_fd(Machine.sword(fd), Machine.sword(events), zr_capi_timeval_usec(tv))
  end

  # rb_thread_wait_fd: waits until `fd` can be read.
  #: (i32) -> void
  def rb_thread_wait_fd(fd)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_wait_fd(Machine.sword(fd), WAITFD_IN, Machine.value(QNIL))
  end

  # rb_thread_fd_writable: waits until `fd` can be written; 1.
  #: (i32) -> i32
  def rb_thread_fd_writable(fd)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_wait_fd(Machine.sword(fd), WAITFD_OUT, Machine.value(QNIL))
    Machine.i32(1)
  end

  # rb_io_wait_readable and rb_io_wait_writable: after a read or a write
  # on `fd` failed, whether to try again. errno says: EINTR is 1 at once,
  # EAGAIN is 1 after `fd` came ready, and any other is 0.
  #: (i32) -> i32
  def rb_io_wait_readable(fd)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_wait_again(Machine.sword(fd), WAITFD_IN)
  end

  #: (i32) -> i32
  def rb_io_wait_writable(fd)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_wait_again(Machine.sword(fd), WAITFD_OUT)
  end

  #: (word, word) -> i32
  def zr_capi_wait_again(fd, events)
    errno = zr_os_errno()
    if errno == EINTR
      return Machine.i32(1)
    end
    if errno != EAGAIN
      return Machine.i32(0)
    end
    zr_capi_wait_fd(fd, events, Machine.value(QNIL))
    Machine.i32(1)
  end

  # The wait for one descriptor: its ready events, 0 when `usec`
  # microseconds passed (nil: on), or -1 with errno set.
  #: (word, word, value) -> i32
  def zr_capi_wait_fd(fd, events, usec)
    fds = zr_ary_new(1)
    zr_ary_push(fds, zr_fix(fd))
    wanted = zr_ary_new(1)
    zr_ary_push(wanted, zr_fix(events))
    ready = zr_capi_wait_fds(fds, wanted, usec)
    if ready == QUNDEF
      return Machine.i32(0 - 1)
    end
    Machine.i32(zr_fix2long(zr_ary_at(ready, 0)))
  end

  # `IO.wait_fds(fds, events, usec)`: the events each descriptor came
  # ready for, or undef with errno set when the wait failed.
  #: (value, value, value) -> value
  def zr_capi_wait_fds(fds, events, usec)
    args = Machine.slot(24)
    Machine.store64(args, 0, Machine.word(fds))
    Machine.store64(args, 8, Machine.word(events))
    Machine.store64(args, 16, Machine.word(usec))
    ready = zr_c_result(zr_send(zr_core_class(Machine.id(:IO)), Machine.id(:wait_fds), 3, args))
    if zr_fixnum_p(ready)
      zr_os_set_errno(0 - zr_fix2long(ready))
      return Machine.value(QUNDEF)
    end
    ready
  end

  # The timeval at `tv` in microseconds, or nil for NULL. tv_usec is an
  # int on darwin and a long on linux; either one's low half holds it.
  #: (ptr) -> value
  def zr_capi_timeval_usec(tv)
    if tv == 0
      return Machine.value(QNIL)
    end
    zr_int_from_word((Machine.load64(tv, 0) * 1000000) + Machine.sword(Machine.load32(tv, 8)))
  end

  #: (word, ptr, ptr, ptr, ptr) -> i32
  def zr_capi_fd_select(n, rfds, wfds, efds, tv)
    fds = zr_ary_new(8)
    events = zr_ary_new(8)
    fd = 0
    while fd < n
      wanted = 0
      if zr_capi_fd_isset(fd, rfds)
        wanted |= WAITFD_IN
      end
      if zr_capi_fd_isset(fd, wfds)
        wanted |= WAITFD_OUT
      end
      if zr_capi_fd_isset(fd, efds)
        wanted |= WAITFD_PRI
      end
      if wanted != 0
        zr_ary_push(fds, zr_fix(fd))
        zr_ary_push(events, zr_fix(wanted))
      end
      fd += 1
    end
    ready = zr_capi_wait_fds(fds, events, zr_capi_timeval_usec(tv))
    if ready == QUNDEF
      return Machine.i32(0 - 1)
    end
    zr_capi_fd_zero(rfds)
    zr_capi_fd_zero(wfds)
    zr_capi_fd_zero(efds)
    count = 0
    i = 0
    while i < RArray[fds].len
      fd = zr_fix2long(zr_ary_at(fds, i))
      got = zr_fix2long(zr_ary_at(ready, i))
      count += zr_capi_fd_mark(fd, rfds, got & WAITFD_IN)
      count += zr_capi_fd_mark(fd, wfds, got & WAITFD_OUT)
      count += zr_capi_fd_mark(fd, efds, got & WAITFD_PRI)
      i += 1
    end
    Machine.i32(count)
  end

  # Adds `fd` to the set (NULL: none) when `ready` is not 0; the count of
  # bits it set.
  #: (word, ptr, word) -> word
  def zr_capi_fd_mark(fd, set, ready)
    if set == 0 || ready == 0
      return 0
    end
    zr_capi_fd_add(fd, set)
    1
  end

  # The count of descriptors that the set covers: its `maxfd`, an int.
  #: (ptr) -> word
  def zr_capi_fd_max(set)
    Machine.sword(Machine.load32(set, 0))
  end

  #: (word, ptr) -> bool
  def zr_capi_fd_isset(fd, set)
    if set == 0 || fd >= zr_capi_fd_max(set)
      return false
    end
    (Machine.u8(Machine.load8(FdSet[set].fdset + (fd >> 3), 0)) & (1 << (fd & 7))) != 0
  end

  #: (word, ptr) -> void
  def zr_capi_fd_add(fd, set)
    zr_capi_fd_grow(set, fd + 1)
    at = FdSet[set].fdset + (fd >> 3)
    Machine.store8(at, 0, Machine.i8(Machine.u8(Machine.load8(at, 0)) | (1 << (fd & 7))))
  end

  #: (ptr) -> void
  def zr_capi_fd_zero(set)
    if set != 0 && FdSet[set].fdset != 0
      Libc.memset(FdSet[set].fdset, Machine.i32(0), zr_capi_fd_bytes(zr_capi_fd_max(set)))
    end
  end

  # Makes the set cover `n` descriptors, its new bits clear.
  #: (ptr, word) -> void
  def zr_capi_fd_grow(set, n)
    had = zr_capi_fd_bytes(zr_capi_fd_max(set))
    need = zr_capi_fd_bytes(n)
    if need > had
      FdSet[set].fdset = zr_capi_realloc(FdSet[set].fdset, need)
      Libc.memset(FdSet[set].fdset + had, Machine.i32(0), need - had)
    end
    if n > zr_capi_fd_max(set)
      Machine.store32(set, 0, Machine.i32(n))
    end
  end

  # The bytes of a set of `n` descriptors: whole 64-bit words, at least
  # an fd_set.
  #: (word) -> word
  def zr_capi_fd_bytes(n)
    bytes = ((n + 63) >> 6) * 8
    bytes < FD_SET_BYTES ? FD_SET_BYTES : bytes
  end

  # The set becomes a copy of the first `max` descriptors at `bits`.
  #: (ptr, ptr, word) -> void
  def zr_capi_fd_assign(set, bits, max)
    bytes = zr_capi_fd_bytes(max)
    FdSet[set].fdset = zr_capi_realloc(FdSet[set].fdset, bytes)
    zr_memcpy(FdSet[set].fdset, bits, bytes)
    Machine.store32(set, 0, Machine.i32(max))
  end
end
