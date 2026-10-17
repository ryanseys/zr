module Zr::Kern
  # The darwin part of the descriptor calls: the location of errno, the
  # calls with a variadic argument, and the layouts of struct dirent and
  # struct stat.

  #: () -> word
  def zr_os_errno
    Machine.u32(Machine.load32(zr_os_errno_ptr(), 0))
  end

  # Where this thread's errno is (rb_errno_ptr).
  #: () -> ptr
  def zr_os_errno_ptr
    Libc.__error()
  end

  #: (word) -> void
  def zr_os_set_errno(n)
    Machine.store32(Libc.__error(), 0, Machine.i32(n))
  end

  EINTR = 4
  EBADF = 9
  ENOEXEC = 8
  EAGAIN = 35
  EINVAL = 22
  ERANGE = 34

  # The *at calls' directory for the working directory, and their flag
  # for a link itself.
  AT_FDCWD = 0 - 2
  AT_SYMLINK_NOFOLLOW = 0x20

  # `fcntl` takes the argument of F_SETFL and F_SETFD as a variadic
  # argument. This platform passes a variadic argument on the stack, and
  # this runtime cannot make such a call. `__fcntl` is the fixed-arity
  # call that fcntl's wrapper makes after it reads that argument.
  #: (i32, i32, word) -> i32
  def zr_os_fcntl(fd, command, argument)
    Libc.__fcntl(fd, command, argument)
  end

  # `ioctl` declares its third argument as variadic, so a fixed-arity call
  # never supplies it: an ioctl that reads its argument returns EFAULT.
  # `__ioctl` is the fixed-arity call that ioctl's wrapper makes after it
  # reads that argument.
  #: (i32, word, ptr) -> i32
  def zr_os_ioctl(fd, request, argument)
    Libc.__ioctl(fd, request, argument)
  end

  # open(2), with the mode for a new file, less the umask.
  #: (ptr, i32, i32) -> i32
  def zr_os_open(path, flags, mode)
    Libc.__open(path, flags, mode)
  end

  # realpath(3): returns a new buffer that the caller frees, or 0.
  #: (ptr) -> ptr
  def zr_os_realpath(path)
    Libc.realpath(path, 0)
  end

  O_NONBLOCK = 4
  # All flags except O_NONBLOCK. A mask with it clears the flag.
  O_NONBLOCK_OFF = 4294967291
  # Each descriptor that ruby opens is close-on-exec. rb_sysopen sets
  # O_CLOEXEC in the open call itself.
  O_CLOEXEC = 16777216
  # O_RDWR | O_NOCTTY | O_CLOEXEC: the pty pair does not become this
  # process's controlling terminal.
  PTY_OPEN_FLAGS = 16_908_290

  TIOCGWINSZ = 1074295912
  # TIOCSCTTY: makes the descriptor the session's controlling terminal.
  TIOCSCTTY = 536900705
  TIOCSWINSZ = 2148037735
  # struct termios: four flag words, twenty control characters, and the
  # two speeds. ruby gets the bytes without change, because ruby selects
  # the flags that a mode changes.
  TERMIOS_LEN = 72
  # c_cc[VMIN] and c_cc[VTIME]: after the four 8-byte flag words,
  # control characters 16 and 17.
  TERMIOS_VMIN = 32 + 16
  TERMIOS_VTIME = 32 + 17

  # The name in a directory entry. Before the name, darwin's struct dirent
  # has an 8-byte inode, an 8-byte seek offset, the record and name
  # lengths as two shorts, and the type byte.
  #: (ptr) -> ptr
  def zr_os_dirent_name(entry)
    entry + 21
  end

  # The entry's kind for glob: 0 unknown, 1 a directory, 2 a symbolic
  # link, 3 anything else. d_type is the byte at 20: DT_DIR is 4,
  # DT_LNK 10, DT_UNKNOWN 0.
  #: (ptr) -> word
  def zr_os_dirent_kind(entry)
    t = Machine.u8(Machine.load8(entry, 20))
    if t == 0
      return 0
    end
    if t == 4
      return 1
    end
    if t == 10
      return 2
    end
    3
  end

  # darwin's 64-bit-inode struct stat.
  STAT_LEN = 160

  # Returns stat(2) as fixnums in an Array: dev, ino, mode, nlink, uid,
  # gid, rdev, size, blksize, blocks, then atime, mtime, ctime and the
  # birth time as seconds and nanoseconds.
  #: (ptr) -> value
  def zr_os_stat_rows(buf)
    out = zr_ary_new(18)
    zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(buf, 0))))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 8)))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(buf, 4)) & 65535))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(buf, 4)) >> 16))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(buf, 16))))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(buf, 20))))
    zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(buf, 24))))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 96)))
    zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(buf, 112))))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 104)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 32)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 40)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 48)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 56)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 64)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 72)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 80)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 88)))
    out
  end

  # st_size.
  #: (ptr) -> word
  def zr_os_stat_size(buf)
    Machine.load64(buf, 96)
  end

  # st_mode, 16 bits at offset 4.
  #: (ptr) -> word
  def zr_os_stat_mode(buf)
    Machine.u32(Machine.load32(buf, 4)) & 65535
  end

  # Darwin's select(2) with no FD_SETSIZE limit, which CRuby calls (it
  # builds with _DARWIN_UNLIMITED_SELECT). Plain `select` refuses more
  # than 1024 descriptors, and poll(2) on darwin reports a pipe with data
  # as priority-readable. Thus neither one gives CRuby's result.
  module SelectCall
    #: (ptr, i32, ptr, ptr, ptr, ptr) -> i32
    def self.call(fn, i, p1, p2, p3, p4) = Machine.indirect
  end

  #: () -> ptr
  def zr_select_fn
    cell = Machine.static(:select_fn, 8)
    if Machine.load64(cell, 0) == 0
      Machine.store64(cell, 0, Machine.word(Libc.dlsym(Machine.ptr(RTLD_DEFAULT), Machine.bytes("select$DARWIN_EXTSN\0"))))
    end
    Machine.ptr(Machine.load64(cell, 0))
  end

  # Calls select(2) on all descriptors of `fds` at the same time, each for
  # the events in its entry of `events`. The thread scheduler uses this to
  # wait for the threads that are blocked on a descriptor. Returns an
  # Array of the ready events for each entry, or the negated errno. A
  # negative time waits with no limit.
  #: (value, value, value) -> value
  def zr_os_wait_fds(fds, events, milliseconds)
    # @type var n: word
    # @type var bit: word
    # @type var want: word
    # @type var at: word
    count = RArray[fds].len
    top = 0
    i = 0
    while i < count
      n = zr_fix2long(zr_ary_at(fds, i))
      if n < 0
        return zr_fix(0 - EBADF)
      end
      if n > top
        top = n
      end
      i += 1
    end
    span = ((top / 32) + 1) * 4
    sets = zr_xmalloc(span * 3)
    Libc.memset(sets, Machine.i32(0), span * 3)
    i = 0
    while i < count
      n = zr_fix2long(zr_ary_at(fds, i))
      want = zr_fix2long(zr_ary_at(events, i))
      at = (n / 32) * 4
      bit = 1 << (n % 32)
      if (want & WAIT_READABLE) != 0
        Machine.store32(sets + at, 0, Machine.i32(Machine.u32(Machine.load32(sets + at, 0)) | bit))
      end
      if (want & WAIT_WRITABLE) != 0
        Machine.store32(sets + span + at, 0, Machine.i32(Machine.u32(Machine.load32(sets + span + at, 0)) | bit))
      end
      if (want & WAIT_PRIORITY) != 0
        Machine.store32(sets + (span * 2) + at, 0, Machine.i32(Machine.u32(Machine.load32(sets + (span * 2) + at, 0)) | bit))
      end
      i += 1
    end
    tv = Machine.slot(16)
    ms = zr_fix2long(milliseconds)
    # A negative timeout waits with no limit, and passes no timeval.
    if ms >= 0
      Machine.store64(tv, 0, ms / 1000)
      Machine.store32(tv, 8, Machine.i32((ms % 1000) * 1000))
      Machine.store32(tv, 12, Machine.i32(0))
    end
    r = SelectCall.call(zr_select_fn(), Machine.i32(top + 1), sets, sets + span, sets + (span * 2), ms < 0 ? 0 : tv)
    if r < Machine.i32(0)
      errno = zr_errno()
      zr_xfree(sets)
      return zr_fix(0 - errno)
    end
    out = zr_ary_new(count)
    i = 0
    while i < count
      n = zr_fix2long(zr_ary_at(fds, i))
      want = zr_fix2long(zr_ary_at(events, i))
      at = (n / 32) * 4
      bit = 1 << (n % 32)
      ready = 0
      if (Machine.u32(Machine.load32(sets + at, 0)) & bit) != 0
        ready = ready | WAIT_READABLE
      end
      if (Machine.u32(Machine.load32(sets + span + at, 0)) & bit) != 0
        ready = ready | WAIT_WRITABLE
      end
      if (Machine.u32(Machine.load32(sets + (span * 2) + at, 0)) & bit) != 0
        ready = ready | WAIT_PRIORITY
      end
      zr_ary_push(out, zr_fix(ready & want))
      i += 1
    end
    zr_xfree(sets)
    out
  end

  # Calls select(2) on one descriptor. ruby uses select to wait on this
  # platform. Returns the ready events, 0 if the time ends, or the negated
  # errno. A negative time waits with no limit. Each of the three sets has
  # as many bits as the descriptor needs, so all descriptor numbers fit.
  #: (value, value, value) -> value
  def zr_os_wait_fd(fd, events, milliseconds)
    n = zr_fix2long(fd)
    if n < 0
      return zr_fix(0 - EBADF)
    end
    want = zr_fix2long(events)
    span = ((n / 32) + 1) * 4
    sets = zr_xmalloc(span * 3)
    Libc.memset(sets, Machine.i32(0), span * 3)
    at = (n / 32) * 4
    bit = 1 << (n % 32)
    if (want & WAIT_READABLE) != 0
      Machine.store32(sets + at, 0, Machine.i32(bit))
    end
    if (want & WAIT_WRITABLE) != 0
      Machine.store32(sets + span + at, 0, Machine.i32(bit))
    end
    if (want & WAIT_PRIORITY) != 0
      Machine.store32(sets + (span * 2) + at, 0, Machine.i32(bit))
    end
    tv = Machine.slot(16)
    ms = zr_fix2long(milliseconds)
    # A negative timeout waits with no limit, and passes no timeval.
    if ms >= 0
      Machine.store64(tv, 0, ms / 1000)
      Machine.store32(tv, 8, Machine.i32((ms % 1000) * 1000))
      Machine.store32(tv, 12, Machine.i32(0))
    end
    r = SelectCall.call(zr_select_fn(), Machine.i32(n + 1), sets, sets + span, sets + (span * 2), ms < 0 ? 0 : tv)
    if r < Machine.i32(0)
      errno = zr_errno()
      zr_xfree(sets)
      return zr_fix(0 - errno)
    end
    ready = 0
    if (Machine.u32(Machine.load32(sets + at, 0)) & bit) != 0
      ready = ready | WAIT_READABLE
    end
    if (Machine.u32(Machine.load32(sets + span + at, 0)) & bit) != 0
      ready = ready | WAIT_WRITABLE
    end
    if (Machine.u32(Machine.load32(sets + (span * 2) + at, 0)) & bit) != 0
      ready = ready | WAIT_PRIORITY
    end
    zr_xfree(sets)
    zr_fix(ready)
  end

  # PROT_READ | PROT_WRITE, and MAP_SHARED | MAP_ANON.
  SHARED_PROT = 3
  SHARED_MAP_FLAGS = 4097

  # Maps `bytes` of the file `fd` from `offset`, with mmap's `prot` and
  # `flags`. Returns MAP_FAILED (-1) on failure, with errno set.
  #: (i32, word, word, word, word) -> ptr
  def zr_os_file_map(fd, bytes, offset, prot, flags)
    Libc.mmap(0, bytes, Machine.i32(prot), Machine.i32(flags), fd, offset)
  end

  # Maps `bytes` of zeroed memory that a fork shares. Returns 0 on failure.
  #: (word) -> ptr
  def zr_os_shared_map(bytes)
    at = Libc.mmap(0, bytes, Machine.i32(SHARED_PROT), Machine.i32(SHARED_MAP_FLAGS), -1, 0)
    if Machine.word(at) == 0 - 1
      return Machine.ptr(0)
    end
    at
  end

  # A new private mapping over pages the process holds: MAP_FIXED,
  # MAP_PRIVATE and MAP_ANON, read and write.
  RELEASE_MAP_FLAGS = 4114
  RELEASE_PROT = 3

  # Gives the whole pages of `bytes` at `at` back to the system. Their
  # bytes are not kept. Darwin's madvise leaves a freed page resident until
  # the system needs memory, so a new mapping takes its place: the pages
  # leave the process at once, and read as zeros at their next touch, as
  # the munmap of CRuby's heap_page_free does.
  #: (ptr, word) -> void
  def zr_os_release_pages(at, bytes)
    Libc.mmap(at, bytes, Machine.i32(RELEASE_PROT), Machine.i32(RELEASE_MAP_FLAGS), -1, 0)
  end

  # A released page comes back at its first touch.
  #: (ptr, word) -> void
  def zr_os_reuse_pages(at, bytes)
  end
end
