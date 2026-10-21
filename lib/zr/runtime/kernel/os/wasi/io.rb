# The WASI part of the descriptor calls: errno in a word of the module,
# open(2) on top of path_open, WASI's filestat as the stat buffer, and
# the libc descriptor and path calls that the portable kernel imports.
# Each call returns what wasi-libc returns.

module Zr::Kern
  #: () -> word
  def zr_os_errno
    Machine.u32(Machine.load32(zr_os_errno_ptr(), 0))
  end

  # Where this thread's errno is (rb_errno_ptr).
  #: () -> ptr
  def zr_os_errno_ptr
    Machine.static(:errno, 8)
  end

  #: (word) -> void
  def zr_os_set_errno(n)
    Machine.store32(Machine.static(:errno, 8), 0, Machine.i32(n))
  end

  EINTR = 27
  EBADF = 8
  ENOEXEC = 45
  EAGAIN = 6
  EINVAL = 28
  ERANGE = 68

  # The *at calls' directory for the working directory, and their flag
  # for a link itself, as wasi-libc defines them.
  AT_FDCWD = 0 - 2
  AT_SYMLINK_NOFOLLOW = 0x1

  # wasi-libc's open flags. The file status flags are WASI's fdflags. The
  # creation flags are WASI's oflags, shifted up 12 bits. The access modes
  # have their own high bits.
  O_APPEND = 1
  O_NONBLOCK = 4
  O_NONBLOCK_OFF = 4294967291
  O_FDFLAGS = 31
  O_NOFOLLOW = 16777216
  O_RDONLY = 67108864
  O_WRONLY = 268435456
  # wasi-libc has no exec, so close-on-exec does nothing.
  O_CLOEXEC = 0
  PTY_OPEN_FLAGS = 335544320

  # musl's ioctl numbers. wasi-libc keeps them, but no call supports them.
  TIOCGWINSZ = 21523
  # TIOCSCTTY: makes the descriptor the session's controlling terminal.
  TIOCSCTTY = 21518
  TIOCSWINSZ = 21524
  TERMIOS_LEN = 60
  TERMIOS_VMIN = 17 + 6
  TERMIOS_VTIME = 17 + 5

  F_GETFD = 1

  # The rights that path_open grants for each access mode, as wasi-libc
  # requests them: all rights except read and write, plus the read rights
  # for O_RDONLY and the write rights for O_WRONLY.
  RIGHTS_READ = 16386
  RIGHTS_WRITE = 4194625
  RIGHTS_OTHER = 1073741823 - RIGHTS_READ - RIGHTS_WRITE
  FDSTAT_LEN = 24

  # WASI has no realpath, so this returns 0 with ENOSYS for every path. A
  # require then uses the path as written, and File.realpath walks the
  # path with lstat and readlink.
  #: (ptr) -> ptr
  def zr_os_realpath(path)
    zr_os_set_errno(WASI_ENOSYS)
    Machine.ptr(0)
  end

  # open(2) on top of path_open, in the preopened directory that contains
  # the path. A WASI file has no permission bits, so the mode is ignored.
  #: (ptr, i32, i32) -> i32
  def zr_os_open(path, flags, _mode)
    where = Machine.slot(16)
    dir = zr_wasi_resolve(path, where)
    if dir < Machine.i32(0)
      return dir
    end
    f = Machine.u32(flags)
    rights = RIGHTS_OTHER
    if (f & O_RDONLY) != 0
      rights = rights | RIGHTS_READ
    end
    if (f & O_WRONLY) != 0
      rights = rights | RIGHTS_WRITE
    end
    follow = (f & O_NOFOLLOW) != 0 ? 0 : 1
    stat = Machine.slot(FDSTAT_LEN)
    Libc.fd_fdstat_get(dir, zr_wasi_addr(stat))
    out = Machine.slot(8)
    r = Libc.path_open(dir, Machine.i32(follow), zr_wasi_rest(where), zr_wasi_rest_len(where), Machine.i32((f >> 12) & 15),
                  rights & Machine.load64(stat, 16), Machine.load64(stat, 16), Machine.i32(f & O_FDFLAGS), zr_wasi_addr(out))
    if zr_wasi_status(r) < Machine.i32(0)
      return Machine.i32(0 - 1)
    end
    Machine.load32(out, 0)
  end

  # F_SETFL sets the fdflags. F_GETFL reads them, with the access mode
  # from the rights. F_SETFD does nothing, because there is no exec. WASI
  # has no other commands.
  #: (i32, i32, word) -> i32
  def zr_os_fcntl(fd, command, argument)
    if command == Machine.i32(F_SETFL)
      return zr_wasi_status(Libc.fd_fdstat_set_flags(fd, Machine.i32(argument & O_FDFLAGS)))
    end
    if command == Machine.i32(F_SETFD)
      return Machine.i32(0)
    end
    # Each descriptor closes on exec, as ruby opens each one so: there is
    # no exec to keep it open for.
    if command == Machine.i32(F_GETFD)
      stat = Machine.slot(FDSTAT_LEN)
      if zr_wasi_status(Libc.fd_fdstat_get(fd, zr_wasi_addr(stat))) < Machine.i32(0)
        return Machine.i32(0 - 1)
      end
      return Machine.i32(FD_CLOEXEC)
    end
    if command != Machine.i32(F_GETFL)
      return zr_wasi_fail(WASI_EINVAL)
    end
    stat = Machine.slot(FDSTAT_LEN)
    if zr_wasi_status(Libc.fd_fdstat_get(fd, zr_wasi_addr(stat))) < Machine.i32(0)
      return Machine.i32(0 - 1)
    end
    rights = Machine.load64(stat, 8)
    flags = Machine.u32(Machine.load32(stat, 0)) >> 16
    if (rights & RIGHTS_READ) != 0
      flags = flags | O_RDONLY
    end
    if (rights & 64) != 0
      flags = flags | O_WRONLY
    end
    Machine.i32(flags)
  end

  # No descriptor here is a terminal or a device that an ioctl request
  # can reach.
  #: (i32, word, ptr) -> i32
  def zr_os_ioctl(fd, request, argument)
    zr_wasi_fail(WASI_ENOTTY)
  end

  # A terminal is a character device, which is filetype 2.
  #: (i32) -> i32
  def isatty(fd)
    stat = Machine.slot(FDSTAT_LEN)
    if zr_wasi_status(Libc.fd_fdstat_get(fd, zr_wasi_addr(stat))) < Machine.i32(0)
      return Machine.i32(0)
    end
    if Machine.load8(stat, 0) != Machine.i8(2)
      zr_os_set_errno(WASI_ENOTTY)
      return Machine.i32(0)
    end
    Machine.i32(1)
  end

  #: (i32, ptr, word) -> word
  def write(fd, buf, len)
    iov = Machine.slot(16)
    if zr_wasi_status(Libc.fd_write(fd, zr_wasi_iovec(iov, buf, len), Machine.i32(1), zr_wasi_addr(iov + 8))) < Machine.i32(0)
      return 0 - 1
    end
    Machine.u32(Machine.load32(iov, 8))
  end

  # A read of a directory fails with EISDIR, as read(2)'s does. WASI
  # gives EBADF, as a directory has no read right.
  #: (i32, ptr, word) -> word
  def read(fd, buf, len)
    iov = Machine.slot(16)
    if zr_wasi_status(Libc.fd_read(fd, zr_wasi_iovec(iov, buf, len), Machine.i32(1), zr_wasi_addr(iov + 8))) < Machine.i32(0)
      stat = Machine.slot(FDSTAT_LEN)
      if zr_os_errno() == EBADF && Libc.fd_fdstat_get(fd, zr_wasi_addr(stat)) == Machine.i32(0) && Machine.load8(stat, 0) == Machine.i8(3)
        zr_os_set_errno(WASI_EISDIR)
      end
      return 0 - 1
    end
    Machine.u32(Machine.load32(iov, 8))
  end

  #: (i32, ptr, word, word) -> word
  def pread(fd, buf, len, offset)
    iov = Machine.slot(16)
    if zr_wasi_status(Libc.fd_pread(fd, zr_wasi_iovec(iov, buf, len), Machine.i32(1), offset, zr_wasi_addr(iov + 8))) < Machine.i32(0)
      return 0 - 1
    end
    Machine.u32(Machine.load32(iov, 8))
  end

  #: (i32, ptr, word, word) -> word
  def pwrite(fd, buf, len, offset)
    iov = Machine.slot(16)
    if zr_wasi_status(Libc.fd_pwrite(fd, zr_wasi_iovec(iov, buf, len), Machine.i32(1), offset, zr_wasi_addr(iov + 8))) < Machine.i32(0)
      return 0 - 1
    end
    Machine.u32(Machine.load32(iov, 8))
  end

  #: (i32) -> i32
  def close(fd)
    zr_wasi_status(Libc.fd_close(fd))
  end

  #: (i32) -> i32
  def fsync(fd)
    zr_wasi_status(Libc.fd_sync(fd))
  end

  # SEEK_SET, SEEK_CUR and SEEK_END are also WASI's whence numbers.
  #: (i32, word, i32) -> word
  def lseek(fd, offset, whence)
    out = Machine.slot(8)
    if zr_wasi_status(Libc.fd_seek(fd, offset, whence, zr_wasi_addr(out))) < Machine.i32(0)
      return 0 - 1
    end
    Machine.load64(out, 0)
  end

  #: (i32, word) -> i32
  def ftruncate(fd, size)
    zr_wasi_status(Libc.fd_filestat_set_size(fd, size))
  end

  # WASI has no permission bits, so there is nothing to change.
  #: (i32, i32) -> i32
  def fchmod(fd, mode)
    Machine.i32(0)
  end

  # A module does not use the umask. Returns 022, the usual value in a
  # new shell.
  #: (i32) -> i32
  def umask(mask)
    Machine.i32(18)
  end

  # A stat buffer is WASI's filestat: the device at 0, the inode at 8, the
  # file type byte at 16, the link count at 24, the size at 32, and the
  # access, modification and change times at 40, 48 and 56, in
  # nanoseconds.
  STAT_LEN = 64

  # Gets a path's filestat. It follows a symlink at the end of the path,
  # or not.
  #: (ptr, ptr, i32) -> i32
  def zr_wasi_path_stat(path, buf, follow)
    where = Machine.slot(16)
    dir = zr_wasi_resolve(path, where)
    if dir < Machine.i32(0)
      return dir
    end
    zr_wasi_status(Libc.path_filestat_get(dir, follow, zr_wasi_rest(where), zr_wasi_rest_len(where), zr_wasi_addr(buf)))
  end

  #: (ptr, ptr) -> i32
  def stat(path, buf)
    zr_wasi_path_stat(path, buf, Machine.i32(1))
  end

  #: (ptr, ptr) -> i32
  def lstat(path, buf)
    zr_wasi_path_stat(path, buf, Machine.i32(0))
  end

  #: (i32, ptr) -> i32
  def fstat(fd, buf)
    zr_wasi_status(Libc.fd_filestat_get(fd, zr_wasi_addr(buf)))
  end

  # Whether the path exists. WASI has no permission checks.
  #: (ptr, i32) -> i32
  def access(path, mode)
    buf = Machine.slot(STAT_LEN)
    Libc.stat(path, buf)
  end

  # The st_mode type bits for WASI's file type, with the usual permission
  # bits of a new file of that type, because WASI has none.
  #: (ptr) -> word
  def zr_os_stat_mode(buf)
    type = Machine.u8(Machine.load8(buf, 16))
    if type == 3
      return 16877
    end
    if type == 1
      return 24996
    end
    if type == 2
      return 8630
    end
    if type == 5 || type == 6
      return 49572
    end
    if type == 7
      return 41471
    end
    33188
  end

  #: (ptr) -> word
  def zr_os_stat_size(buf)
    Machine.load64(buf, 32)
  end

  # The fields that zr_stat_m returns. The owner is root and the device
  # number is zero, because a module gets neither. A block is 512 bytes.
  #: (ptr) -> value
  def zr_os_stat_rows(buf)
    size = Machine.load64(buf, 32)
    out = zr_ary_new(16)
    zr_ary_push(out, zr_fix(Machine.load64(buf, 0)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 8)))
    zr_ary_push(out, zr_fix(zr_os_stat_mode(buf)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 24)))
    zr_ary_push(out, zr_fix(0))
    zr_ary_push(out, zr_fix(0))
    zr_ary_push(out, zr_fix(0))
    zr_ary_push(out, zr_fix(size))
    zr_ary_push(out, zr_fix(4096))
    zr_ary_push(out, zr_fix((size + 511) / 512))
    at = 40
    while at < 64
      zr_ary_push(out, zr_fix(Machine.load64(buf + at, 0) / 1000000000))
      zr_ary_push(out, zr_fix(Machine.load64(buf + at, 0) % 1000000000))
      at += 8
    end
    out
  end

  # The calls with one path. The call gives the host the descriptor of the
  # path's directory and the remaining part of the path.
  #: (ptr) -> i32
  def unlink(path)
    where = Machine.slot(16)
    dir = zr_wasi_resolve(path, where)
    if dir < Machine.i32(0)
      return dir
    end
    zr_wasi_status(Libc.path_unlink_file(dir, zr_wasi_rest(where), zr_wasi_rest_len(where)))
  end

  #: (ptr) -> i32
  def rmdir(path)
    where = Machine.slot(16)
    dir = zr_wasi_resolve(path, where)
    if dir < Machine.i32(0)
      return dir
    end
    zr_wasi_status(Libc.path_remove_directory(dir, zr_wasi_rest(where), zr_wasi_rest_len(where)))
  end

  #: (ptr, i32) -> i32
  def mkdir(path, mode)
    where = Machine.slot(16)
    dir = zr_wasi_resolve(path, where)
    if dir < Machine.i32(0)
      return dir
    end
    zr_wasi_status(Libc.path_create_directory(dir, zr_wasi_rest(where), zr_wasi_rest_len(where)))
  end

  #: (ptr, ptr, word) -> word
  def readlink(path, buf, len)
    where = Machine.slot(16)
    dir = zr_wasi_resolve(path, where)
    if dir < Machine.i32(0)
      return 0 - 1
    end
    used = Machine.slot(8)
    r = Libc.path_readlink(dir, zr_wasi_rest(where), zr_wasi_rest_len(where), zr_wasi_addr(buf), Machine.i32(len), zr_wasi_addr(used))
    if zr_wasi_status(r) < Machine.i32(0)
      return 0 - 1
    end
    Machine.u32(Machine.load32(used, 0))
  end

  # The calls with two paths.
  #: (ptr, ptr) -> i32
  def rename(from, to)
    a = Machine.slot(16)
    b = Machine.slot(16)
    da = zr_wasi_resolve(from, a)
    db = zr_wasi_resolve(to, b)
    if da < Machine.i32(0) || db < Machine.i32(0)
      return Machine.i32(0 - 1)
    end
    zr_wasi_status(Libc.path_rename(da, zr_wasi_rest(a), zr_wasi_rest_len(a), db, zr_wasi_rest(b), zr_wasi_rest_len(b)))
  end

  #: (ptr, ptr) -> i32
  def link(from, to)
    a = Machine.slot(16)
    b = Machine.slot(16)
    da = zr_wasi_resolve(from, a)
    db = zr_wasi_resolve(to, b)
    if da < Machine.i32(0) || db < Machine.i32(0)
      return Machine.i32(0 - 1)
    end
    zr_wasi_status(Libc.path_link(da, Machine.i32(0), zr_wasi_rest(a), zr_wasi_rest_len(a), db, zr_wasi_rest(b), zr_wasi_rest_len(b)))
  end

  # The host stores a symlink's target text as it is given.
  #: (ptr, ptr) -> i32
  def symlink(target, path)
    where = Machine.slot(16)
    dir = zr_wasi_resolve(path, where)
    if dir < Machine.i32(0)
      return dir
    end
    if Machine.u8(Machine.load8(target, 0)) == 47
      return zr_wasi_symlink_within(target, dir, where)
    end
    zr_wasi_status(Libc.path_symlink(zr_wasi_addr(target), Machine.i32(zr_cstr_len(target)), dir, zr_wasi_rest(where), zr_wasi_rest_len(where)))
  end

  # WASI refuses a link to an absolute path, as it could leave the
  # preopened directory. A target in the link's own preopened directory
  # is written relative to the link: a `../` for each directory above
  # the link, then the target's path in that directory.
  #: (ptr, i32, ptr) -> i32
  def zr_wasi_symlink_within(target, dir, where)
    at = Machine.slot(16)
    if zr_wasi_resolve(target, at) != dir
      return zr_wasi_fail(63)
    end
    rest = Machine.ptr(Machine.load64(where, 0))
    ups = 0
    i = 0
    while i < Machine.load64(where, 8)
      if Machine.u8(Machine.load8(rest + i, 0)) == 47
        ups += 1
      end
      i += 1
    end
    tlen = Machine.load64(at, 8)
    len = (ups * 3) + tlen
    text = zr_xmalloc(len + 1)
    i = 0
    while i < ups
      zr_memcpy(text + (i * 3), Machine.bytes("../"), 3)
      i += 1
    end
    zr_memcpy(text + (ups * 3), Machine.ptr(Machine.load64(at, 0)), tlen)
    r = zr_wasi_status(Libc.path_symlink(zr_wasi_addr(text), Machine.i32(len), dir, zr_wasi_rest(where), zr_wasi_rest_len(where)))
    zr_xfree(text)
    r
  end

  # A directory stream: its descriptor, the cookie of the next entry, and
  # the last entry that fd_readdir returned, with a NUL after its name.
  DIR_BUFFER = 4096

  #: (i32) -> ptr
  def fdopendir(fd)
    d = zr_xmalloc(16 + DIR_BUFFER + 1)
    Machine.store64(d, 0, Machine.u32(fd))
    Machine.store64(d, 8, 0)
    d
  end

  #: (ptr) -> ptr
  def opendir(path)
    fd = zr_os_open(path, Machine.i32(O_RDONLY | (2 << 12)), Machine.i32(0))
    if fd < Machine.i32(0)
      return Machine.ptr(0)
    end
    Libc.fdopendir(fd)
  end

  # Returns the next entry, which it reads one at a time from the cookie,
  # or 0 at the end. A dirent is 24 bytes, followed by the name.
  #: (ptr) -> ptr
  def readdir(d)
    buf = d + 16
    used = Machine.slot(8)
    r = Libc.fd_readdir(Machine.load32(d, 0), zr_wasi_addr(buf), Machine.i32(DIR_BUFFER), Machine.load64(d, 8), zr_wasi_addr(used))
    if zr_wasi_status(r) < Machine.i32(0) || Machine.u32(Machine.load32(used, 0)) < 24
      return Machine.ptr(0)
    end
    len = Machine.u32(Machine.load32(buf, 16))
    Machine.store64(d, 8, Machine.load64(buf, 0))
    Machine.store8(buf + 24 + len, 0, Machine.i8(0))
    buf
  end

  #: (ptr) -> ptr
  def zr_os_dirent_name(entry)
    entry + 24
  end

  # The entry's kind for glob: 0 unknown, 1 a directory, 2 a symbolic
  # link, 3 anything else. The filetype is the byte at 20: a directory is
  # 3, a symbolic link 7, unknown 0.
  #: (ptr) -> word
  def zr_os_dirent_kind(entry)
    t = Machine.u8(Machine.load8(entry, 20))
    if t == 0
      return 0
    end
    if t == 3
      return 1
    end
    if t == 7
      return 2
    end
    3
  end

  #: (ptr) -> i32
  def closedir(d)
    r = Libc.close(Machine.load32(d, 0))
    zr_xfree(d)
    r
  end

  # Calls poll_oneoff on all descriptors of `fds` at the same time. Each
  # waits for the events in its element of `events`. It also waits on the
  # clock when the wait has a timeout. Returns an Array of the ready events
  # for each element, or the negated errno. The userdata of each
  # subscription is its element index.
  #: (value, value, value) -> value
  def zr_os_wait_fds(fds, events, milliseconds)
    # @type var want: word
    count = RArray[fds].len
    ms = zr_fix2long(milliseconds)
    subs = zr_xmalloc(((count * 2) + 1) * 48)
    Libc.memset(subs, Machine.i32(0), ((count * 2) + 1) * 48)
    used = 0
    i = 0
    while i < count
      n = zr_fix2long(zr_ary_at(fds, i))
      want = zr_fix2long(zr_ary_at(events, i))
      if n < 0
        zr_xfree(subs)
        return zr_fix(0 - EBADF)
      end
      if (want & (WAIT_READABLE | WAIT_PRIORITY)) != 0
        Machine.store64(subs + (used * 48), 0, i)
        Machine.store8(subs + (used * 48), 8, Machine.i8(1))
        Machine.store32(subs + (used * 48), 16, Machine.i32(n))
        used += 1
      end
      if (want & WAIT_WRITABLE) != 0
        Machine.store64(subs + (used * 48), 0, i)
        Machine.store8(subs + (used * 48), 8, Machine.i8(2))
        Machine.store32(subs + (used * 48), 16, Machine.i32(n))
        used += 1
      end
      i += 1
    end
    if ms >= 0
      Machine.store64(subs + (used * 48), 0, count)
      Machine.store32(subs + (used * 48), 16, Machine.i32(1))
      Machine.store64(subs + (used * 48), 24, ms * 1000000)
      used += 1
    end
    got = zr_xmalloc(used * 32)
    nevents = Machine.slot(8)
    if zr_wasi_status(Libc.poll_oneoff(zr_wasi_addr(subs), zr_wasi_addr(got), Machine.i32(used), zr_wasi_addr(nevents))) < Machine.i32(0)
      errno = zr_errno()
      zr_xfree(subs)
      zr_xfree(got)
      return zr_fix(0 - errno)
    end
    out = zr_ary_new(count)
    i = 0
    while i < count
      zr_ary_push(out, zr_fix(0))
      i += 1
    end
    i = 0
    while i < Machine.u32(Machine.load32(nevents, 0))
      e = got + (i * 32)
      row = Machine.load64(e, 0)
      kind = Machine.u8(Machine.load8(e, 10))
      if row < count && kind != 0
        want = zr_fix2long(zr_ary_at(events, row))
        ready = zr_fix2long(zr_ary_at(out, row))
        ready = ready | (kind == 1 ? want & (WAIT_READABLE | WAIT_PRIORITY) : want & WAIT_WRITABLE)
        zr_ary_store(out, row, zr_fix(ready))
      end
      i += 1
    end
    zr_xfree(subs)
    zr_xfree(got)
    out
  end

  # Calls poll_oneoff on one descriptor, and on the clock when the wait
  # has a timeout. Returns the ready events, 0 on a timeout, or the negated
  # errno. A subscription is 48 bytes and an event is 32 bytes.
  #: (value, value, value) -> value
  def zr_os_wait_fd(fd, events, milliseconds)
    n = zr_fix2long(fd)
    if n < 0
      return zr_fix(0 - EBADF)
    end
    want = zr_fix2long(events)
    ms = zr_fix2long(milliseconds)
    subs = Machine.slot(144)
    Libc.memset(subs, Machine.i32(0), 144)
    count = 0
    if (want & (WAIT_READABLE | WAIT_PRIORITY)) != 0
      Machine.store8(subs + (count * 48), 8, Machine.i8(1))
      Machine.store32(subs + (count * 48), 16, Machine.i32(n))
      count += 1
    end
    if (want & WAIT_WRITABLE) != 0
      Machine.store8(subs + (count * 48), 8, Machine.i8(2))
      Machine.store32(subs + (count * 48), 16, Machine.i32(n))
      count += 1
    end
    if ms >= 0
      Machine.store32(subs + (count * 48), 16, Machine.i32(1))
      Machine.store64(subs + (count * 48), 24, ms * 1000000)
      count += 1
    end
    got = Machine.slot(96)
    nevents = Machine.slot(8)
    if zr_wasi_status(Libc.poll_oneoff(zr_wasi_addr(subs), zr_wasi_addr(got), Machine.i32(count), zr_wasi_addr(nevents))) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    ready = 0
    i = 0
    while i < Machine.u32(Machine.load32(nevents, 0))
      e = got + (i * 32)
      kind = Machine.u8(Machine.load8(e, 10))
      if (Machine.u32(Machine.load32(e, 8)) & 65535) != 0 && kind != 0
        return zr_fix(0 - (Machine.u32(Machine.load32(e, 8)) & 65535))
      end
      if kind == 1
        ready = ready | (want & (WAIT_READABLE | WAIT_PRIORITY))
      elsif kind == 2
        ready = ready | WAIT_WRITABLE
      end
      i += 1
    end
    zr_fix(ready)
  end

  # The messages of wasi-libc's strerror, one on each line, in WASI's
  # errno order.
  #: (i32) -> ptr
  def strerror(n)
    text = Machine.bytes(<<-MESSAGES)
No error information
Argument list too long
Permission denied
Address in use
Address not available
Address family not supported by protocol
Resource temporarily unavailable
Operation already in progress
Bad file descriptor
Bad message
Resource busy
Operation canceled
No child process
Connection aborted
Connection refused
Connection reset by peer
Resource deadlock would occur
Destination address required
Domain error
Quota exceeded
File exists
Bad address
File too large
Host is unreachable
Identifier removed
Illegal byte sequence
Operation in progress
Interrupted system call
Invalid argument
I/O error
Socket is connected
Is a directory
Symbolic link loop
No file descriptors available
Too many links
Message too large
Multihop attempted
Filename too long
Network is down
Connection reset by network
Network unreachable
Too many open files in system
No buffer space available
No such device
No such file or directory
Exec format error
No locks available
Link has been severed
Out of memory
No message of desired type
Protocol not available
No space left on device
Function not implemented
Socket not connected
Not a directory
Directory not empty
State not recoverable
Not a socket
Not supported
Not a tty
No such device or address
Value too large for data type
Previous owner died
Operation not permitted
Broken pipe
Protocol error
Protocol not supported
Protocol wrong type for socket
Result not representable
Read-only file system
Invalid seek
No such process
Stale file handle
Operation timed out
Text file busy
Cross-device link
Capabilities insufficient
  MESSAGES
  line = Machine.u32(n)
    if line > 76
      line = 0
    end
    at = text
    while line > 0
      if Machine.load8(at, 0) == Machine.i8(10)
        line -= 1
      end
      at += 1
    end
    # Copy the line into the C string, with a NUL at the end of the line.
    len = 0
    while Machine.load8(at + len, 0) != Machine.i8(10)
      len += 1
    end
    out = Machine.static(:strerror, 64)
    zr_memcpy(out, at, len)
    Machine.store8(out + len, 0, Machine.i8(0))
    out
  end

  # WASI has no working directory, so the module keeps one, as wasi-libc
  # does: an absolute path with no `.` or `..` part, empty for the root,
  # which contains every preopened directory. `zr_wasi_dir` puts it in
  # front of each relative path.
  CWD_MAX = 4096
  WASI_EISDIR = 31
  WASI_ENAMETOOLONG = 37
  WASI_ENOTDIR = 54

  #: () -> ptr
  def zr_wasi_cwd
    Machine.static(:wasi_cwd, CWD_MAX)
  end

  #: (ptr, word) -> ptr
  def getcwd(buf, size)
    cwd = zr_wasi_cwd()
    len = zr_cstr_len(cwd)
    if size < (len == 0 ? 2 : len + 1)
      zr_os_set_errno(ERANGE)
      return Machine.ptr(0)
    end
    if len == 0
      Machine.store8(buf, 0, Machine.i8(47))
      len = 1
    else
      zr_memcpy(buf, cwd, len)
    end
    Machine.store8(buf + len, 0, Machine.i8(0))
    buf
  end

  # Writes `path` below the working directory into `out` (CWD_MAX
  # bytes), with each `.` part dropped and each `..` part taking off the
  # part before it. Returns -1 with ENAMETOOLONG when it does not fit.
  #: (ptr, ptr) -> i32
  def zr_wasi_normalize(path, out)
    len = 0
    if Machine.u8(Machine.load8(path, 0)) != 47
      len = zr_cstr_len(zr_wasi_cwd())
      zr_memcpy(out, zr_wasi_cwd(), len)
    end
    at = 0
    while Machine.load8(path + at, 0) != Machine.i8(0)
      while Machine.u8(Machine.load8(path + at, 0)) == 47
        at += 1
      end
      part = at
      while Machine.load8(path + at, 0) != Machine.i8(0) && Machine.u8(Machine.load8(path + at, 0)) != 47
        at += 1
      end
      n = at - part
      first = n >= 1 ? Machine.u8(Machine.load8(path + part, 0)) : 0
      if n == 2 && first == 46 && Machine.u8(Machine.load8(path + part + 1, 0)) == 46
        while len > 0 && Machine.u8(Machine.load8(out + len - 1, 0)) != 47
          len -= 1
        end
        if len > 0
          len -= 1
        end
      elsif n > 1 || (n == 1 && first != 46)
        if len + n + 2 > CWD_MAX
          return zr_wasi_fail(WASI_ENAMETOOLONG)
        end
        Machine.store8(out + len, 0, Machine.i8(47))
        zr_memcpy(out + len + 1, path + part, n)
        len = len + n + 1
      end
    end
    Machine.store8(out + len, 0, Machine.i8(0))
    Machine.i32(0)
  end

  # Sets the working directory to a directory that exists.
  #: (ptr) -> i32
  def chdir(path)
    if Machine.load8(path, 0) == Machine.i8(0)
      return zr_wasi_fail(WASI_ENOENT)
    end
    next_cwd = Machine.slot(CWD_MAX)
    if zr_wasi_normalize(path, next_cwd) < Machine.i32(0)
      return Machine.i32(0 - 1)
    end
    buf = Machine.slot(STAT_LEN)
    if zr_wasi_path_stat(Machine.load8(next_cwd, 0) == Machine.i8(0) ? Machine.bytes("/\0") : next_cwd, buf, Machine.i32(1)) < Machine.i32(0)
      return Machine.i32(0 - 1)
    end
    if Machine.u8(Machine.load8(buf, 16)) != 3
      return zr_wasi_fail(WASI_ENOTDIR)
    end
    zr_memcpy(zr_wasi_cwd(), next_cwd, zr_cstr_len(next_cwd) + 1)
    Machine.i32(0)
  end

  # WASI maps no files: 0 tells IO::Buffer.map to read the file instead.
  #: (i32, word, word, word, word) -> ptr
  def zr_os_file_map(fd, bytes, offset, prot, flags)
    Machine.ptr(0)
  end

  # WASI has no fork and no shared memory.
  #: (word) -> ptr
  def zr_os_shared_map(bytes)
    Machine.ptr(0)
  end

  # WASI memory only grows: a page stays the program's.
  #: (ptr, word) -> void
  def zr_os_release_pages(at, bytes)
  end

  #: (ptr, word) -> void
  def zr_os_reuse_pages(at, bytes)
  end
end
