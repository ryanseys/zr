module Zr::Kern
  # The Linux part of the descriptor calls, as musl supplies them: the
  # location of errno, the calls with a variadic argument, and the layouts
  # of struct dirent and struct stat. AAPCS64 on Linux passes a variadic
  # argument in a register, the same as a fixed one. Thus fcntl, ioctl and
  # open take their last argument as a fixed third argument.

  #: () -> word
  def zr_os_errno
    Machine.u32(Machine.load32(Libc.__errno_location(), 0))
  end

  #: (word) -> void
  def zr_os_set_errno(n)
    Machine.store32(Libc.__errno_location(), 0, Machine.i32(n))
  end

  EINTR = 4
  EBADF = 9
  ENOEXEC = 8

  # The *at calls' directory for the working directory, and their flag
  # for a link itself.
  AT_FDCWD = 0 - 100
  AT_SYMLINK_NOFOLLOW = 0x100

  #: (i32, i32, word) -> i32
  def zr_os_fcntl(fd, command, argument)
    Libc.fcntl(fd, command, argument)
  end

  #: (i32, word, ptr) -> i32
  def zr_os_ioctl(fd, request, argument)
    Libc.ioctl(fd, request, argument)
  end

  # open(2), with the mode for a new file, less the umask.
  #: (ptr, i32, i32) -> i32
  def zr_os_open(path, flags, mode)
    Libc.open(path, flags, mode)
  end

  # realpath(3): returns a new buffer that the caller frees, or 0.
  #: (ptr) -> ptr
  def zr_os_realpath(path)
    Libc.realpath(path, 0)
  end

  O_NONBLOCK = 2048
  # All flags except O_NONBLOCK. A mask with it clears the flag.
  O_NONBLOCK_OFF = 4294965247
  O_CLOEXEC = 524288
  # O_RDWR | O_NOCTTY | O_CLOEXEC: the pty pair does not become this
  # process's controlling terminal.
  PTY_OPEN_FLAGS = 524546

  TIOCGWINSZ = 21523
  # TIOCSCTTY: makes the descriptor the session's controlling terminal.
  TIOCSCTTY = 21518
  TIOCSWINSZ = 21524
  # struct termios: four flag ints, the line discipline, 32 control
  # characters, and the two speeds.
  TERMIOS_LEN = 60

  # The name in a directory entry. Before the name, musl's struct dirent
  # has an 8-byte inode, an 8-byte seek offset, the record length as a
  # short, and the type byte.
  #: (ptr) -> ptr
  def zr_os_dirent_name(entry)
    entry + 19
  end

  # The entry's kind for glob: 0 unknown, 1 a directory, 2 a symbolic
  # link, 3 anything else. d_type is the byte at 18: DT_DIR is 4,
  # DT_LNK 10, DT_UNKNOWN 0.
  #: (ptr) -> word
  def zr_os_dirent_kind(entry)
    t = Machine.u8(Machine.load8(entry, 18))
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

  # The generic struct stat of aarch64 Linux.
  STAT_LEN = 128

  # Returns stat(2) as fixnums in an Array: dev, ino, mode, nlink, uid,
  # gid, rdev, size, blksize, blocks, then atime, mtime and ctime as
  # seconds and nanoseconds.
  #: (ptr) -> value
  def zr_os_stat_rows(buf)
    out = zr_ary_new(16)
    zr_ary_push(out, zr_fix(Machine.load64(buf, 0)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 8)))
    zr_ary_push(out, zr_fix(zr_os_stat_mode(buf)))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(buf, 20))))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(buf, 24))))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(buf, 28))))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 32)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 48)))
    zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(buf, 56))))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 64)))
    at = 72
    while at < 120
      zr_ary_push(out, zr_fix(Machine.load64(buf + at, 0)))
      at += 8
    end
    out
  end

  # st_size.
  #: (ptr) -> word
  def zr_os_stat_size(buf)
    Machine.load64(buf, 48)
  end

  # st_mode, 32 bits at offset 16.
  #: (ptr) -> word
  def zr_os_stat_mode(buf)
    Machine.u32(Machine.load32(buf, 16))
  end

  # The poll(2) result bits as thread.c reads them: the read set (POLLIN,
  # POLLRDNORM, POLLRDBAND, POLLHUP, POLLERR), the write set (POLLOUT,
  # POLLWRNORM, POLLWRBAND, POLLERR), the priority set, and the bit that
  # shows the descriptor is not open.
  POLLIN_SET = 217
  POLLOUT_SET = 780
  POLLEX_SET = 2
  POLLNVAL = 32

  # Calls poll(2) on all descriptors of `fds` at the same time, each for
  # the events in its entry of `events`. The thread scheduler uses this to
  # wait for the threads that are blocked on a descriptor. Returns an
  # Array of the ready events for each entry, or the negated errno. A
  # negative time waits with no limit.
  #: (value, value, value) -> value
  def zr_os_wait_fds(fds, events, milliseconds)
    count = RArray[fds].len
    entries = zr_xmalloc((count + 1) * 8)
    i = 0
    while i < count
      n = zr_fix2long(zr_ary_at(fds, i))
      if n < 0
        zr_xfree(entries)
        return zr_fix(0 - EBADF)
      end
      Machine.store32(entries + (i * 8), 0, Machine.i32(n))
      Machine.store32(entries + (i * 8), 4, Machine.i32(zr_fix2long(zr_ary_at(events, i))))
      i += 1
    end
    ms = zr_fix2long(milliseconds)
    r = Libc.poll(entries, count, Machine.i32(ms < 0 ? 0 - 1 : ms))
    if r < Machine.i32(0)
      errno = zr_errno()
      zr_xfree(entries)
      return zr_fix(0 - errno)
    end
    out = zr_ary_new(count)
    i = 0
    while i < count
      got = Machine.u32(Machine.load32(entries + (i * 8), 4)) >> 16
      ready = 0
      if (got & (POLLIN_SET | POLLNVAL)) != 0
        ready = ready | WAIT_READABLE
      end
      if (got & (POLLOUT_SET | POLLNVAL)) != 0
        ready = ready | WAIT_WRITABLE
      end
      if (got & POLLEX_SET) != 0
        ready = ready | WAIT_PRIORITY
      end
      zr_ary_push(out, zr_fix(ready & zr_fix2long(zr_ary_at(events, i))))
      i += 1
    end
    zr_xfree(entries)
    out
  end

  # Calls poll(2) on one descriptor. ruby uses poll to wait on Linux.
  # Returns the ready events, 0 if the time ends, or the negated errno.
  # The events that ruby requests are poll's own bits. A struct pollfd is
  # the descriptor, then the requested and returned events as two shorts.
  # A negative time waits with no limit.
  #: (value, value, value) -> value
  def zr_os_wait_fd(fd, events, milliseconds)
    n = zr_fix2long(fd)
    if n < 0
      return zr_fix(0 - EBADF)
    end
    want = zr_fix2long(events)
    ms = zr_fix2long(milliseconds)
    entry = Machine.slot(8)
    Machine.store32(entry, 0, Machine.i32(n))
    Machine.store32(entry, 4, Machine.i32(want))
    r = Libc.poll(entry, 1, Machine.i32(ms < 0 ? 0 - 1 : ms))
    if r < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    if r == Machine.i32(0)
      return zr_fix(0)
    end
    got = Machine.u32(Machine.load32(entry, 4)) >> 16
    if (got & POLLNVAL) != 0
      return zr_fix(0 - EBADF)
    end
    ready = 0
    if (got & POLLIN_SET) != 0
      ready = ready | WAIT_READABLE
    end
    if (got & POLLOUT_SET) != 0
      ready = ready | WAIT_WRITABLE
    end
    if (got & POLLEX_SET) != 0
      ready = ready | WAIT_PRIORITY
    end
    zr_fix(ready)
  end
end
