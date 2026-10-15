module Zr::Kern
  # File descriptors: the libSystem calls that the IO and File classes
  # use. A failure returns the negated errno, and the core converts it to
  # the matching Errno class.

  #: () -> word
  def zr_errno
    zr_os_errno()
  end

  # Clears errno, for a call whose return value cannot show a failure.
  # After this, only a failure of the next call sets errno.
  #: () -> void
  def zr_clear_errno
    zr_os_set_errno(0)
  end

  #: (word) -> value
  def zr_io_failed(r)
    r < 0 ? zr_fix(0 - zr_errno()) : zr_fix(r)
  end

  # Converts an int result: 0 on success, or the negated errno when the
  # call returned -1.
  #: (i32) -> value
  def zr_io_status(r)
    r < Machine.i32(0) ? zr_fix(0 - zr_errno()) : zr_fix(0)
  end

  # F_GETFL: the status flags of the descriptor, which show the mode it
  # was opened with. Each fcntl goes through `zr_os_fcntl`, which passes
  # the variadic argument of fcntl as each OS needs it.
  F_GETFL = 3

  #: (value) -> value
  def zr_io_flags(fd)
    zr_io_failed(Machine.sword(zr_os_fcntl(Machine.i32(zr_fix2long(fd)), Machine.i32(F_GETFL), 0)))
  end

  # Makes a descriptor return EAGAIN instead of waiting.
  F_SETFL = 4

  #: (value, value) -> value
  def zr_io_set_nonblock(fd, on)
    n = Machine.i32(zr_fix2long(fd))
    r = zr_os_fcntl(n, Machine.i32(F_GETFL), 0)
    if r < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    flags = Machine.u32(r)
    if zr_fix2long(on) != 0
      return zr_io_status(zr_os_fcntl(n, Machine.i32(F_SETFL), flags | O_NONBLOCK))
    end
    zr_io_status(zr_os_fcntl(n, Machine.i32(F_SETFL), flags & O_NONBLOCK_OFF))
  end

  # F_SETFD and its one flag.
  F_SETFD = 2
  FD_CLOEXEC = 1

  # Makes a descriptor close across an exec. ruby does this for each
  # descriptor that it gives out. An open(2) sets it with a flag on the
  # call. pipe(2) here has no such flag, so rb_cloexec_pipe sets it after
  # the call, as this function does.
  #: (value) -> value
  def zr_io_cloexec(fd)
    zr_io_status(zr_os_fcntl(Machine.i32(zr_fix2long(fd)), Machine.i32(F_SETFD), Machine.word(FD_CLOEXEC)))
  end

  # ioctl(2) with the argument of a command: a number that the command
  # reads as is, or the bytes of a String that the command fills in. The
  # address of a String never goes into ruby, so there are two calls, not
  # one call for which ruby would have to make a pointer.
  #: (value, value, value) -> value
  def zr_io_ioctl(fd, command, argument)
    zr_io_failed(Machine.sword(zr_os_ioctl(Machine.i32(zr_fix2long(fd)), Machine.word(zr_fix2long(command)),
                                       Machine.ptr(zr_fix2long(argument)))))
  end

  #: (value, value, value) -> value
  def zr_io_ioctl_buf(fd, command, bytes)
    zr_io_failed(Machine.sword(zr_os_ioctl(Machine.i32(zr_fix2long(fd)), Machine.word(zr_fix2long(command)),
                                       RString[bytes].ptr)))
  end

  # fcntl(2) with a command that the program gives, and the argument of
  # that command, through `zr_os_fcntl` as for the non-blocking flag.
  #: (value, value, value) -> value
  def zr_io_fcntl(fd, command, argument)
    zr_io_failed(Machine.sword(zr_os_fcntl(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(command)),
                                      Machine.word(zr_fix2long(argument)))))
  end

  # fcntl(2) with a struct that the call reads or fills. The bytes of the
  # String are the struct, in place.
  #: (value, value, value) -> value
  def zr_io_fcntl_bytes(fd, command, bytes)
    zr_io_failed(Machine.sword(zr_os_fcntl(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(command)),
                                      Machine.word(RString[bytes].ptr))))
  end

  # rb_sysopen: open(2) with the flags, and the permissions for a new
  # file, minus the umask. Each descriptor that ruby opens closes across
  # an exec, so rb_sysopen adds O_CLOEXEC to the call.
  #: (value, value, value) -> value
  def zr_io_open_flags(path, flags, perm)
    fd = zr_os_open(RString[path].ptr, Machine.i32(zr_fix2long(flags) | O_CLOEXEC), Machine.i32(zr_fix2long(perm)))
    while fd < Machine.i32(0)
      failed = zr_io_retry()
      if failed != QNIL
        return failed
      end
      fd = zr_os_open(RString[path].ptr, Machine.i32(zr_fix2long(flags) | O_CLOEXEC), Machine.i32(zr_fix2long(perm)))
    end
    zr_fix(Machine.sword(fd))
  end

  # Reads up to `count` bytes. Returns a String, nil at the end, or the
  # negated errno.
  #: (value, value) -> value
  def zr_io_read(fd, count)
    n = zr_fix2long(count)
    buf = zr_xmalloc(n + 1)
    got = Libc.read(Machine.i32(zr_fix2long(fd)), buf, n)
    while got < 0
      failed = zr_io_retry()
      if failed != QNIL
        zr_xfree(buf)
        return failed
      end
      got = Libc.read(Machine.i32(zr_fix2long(fd)), buf, n)
    end
    if got == 0
      zr_xfree(buf)
      return Machine.value(QNIL)
    end
    s = zr_str_new(buf, got)
    zr_xfree(buf)
    s
  end

  # pread(2) and pwrite(2): a read or a write at a given file position.
  # The position of the descriptor does not change.
  #: (value, value, value) -> value
  def zr_io_pread(fd, count, at)
    n = zr_fix2long(count)
    buf = zr_xmalloc(n + 1)
    got = Libc.pread(Machine.i32(zr_fix2long(fd)), buf, n, zr_fix2long(at))
    if got < 0
      zr_xfree(buf)
      return zr_fix(0 - zr_errno())
    end
    if got == 0
      zr_xfree(buf)
      return Machine.value(QNIL)
    end
    s = zr_str_new(buf, got)
    zr_xfree(buf)
    s
  end

  #: (value, value, value) -> value
  def zr_io_pwrite(fd, s, at)
    n = RString[s].len
    done = 0
    while done < n
      w = Libc.pwrite(Machine.i32(zr_fix2long(fd)), RString[s].ptr + done, n - done, zr_fix2long(at) + done)
      if w < 0
        return zr_fix(0 - zr_errno())
      end
      done += w
    end
    zr_fix(n)
  end

  # Writes all bytes of `s`, in as many calls as necessary. The code reads
  # the String again after each call, because a retry runs the POSIX
  # signal handlers, which are Ruby and can change it.
  #: (value, value) -> value
  def zr_io_write(fd, s)
    done = 0
    while done < RString[s].len
      w = Libc.write(Machine.i32(zr_fix2long(fd)), RString[s].ptr + done, RString[s].len - done)
      if w < 0
        failed = zr_io_retry()
        if failed != QNIL
          return failed
        end
        w = 0
      end
      done += w
    end
    zr_fix(done)
  end

  # One write(2) of at most `count` bytes from `from`. The caller loops,
  # so a task that shares the process yields to the scheduler between the
  # calls, and does not wait inside one long write.
  #: (value, value, value, value) -> value
  def zr_io_write_some(fd, s, from, count)
    at = zr_fix2long(from)
    n = RString[s].len - at
    if n > zr_fix2long(count)
      n = zr_fix2long(count)
    end
    w = Libc.write(Machine.i32(zr_fix2long(fd)), RString[s].ptr + at, n)
    while w < 0
      failed = zr_io_retry()
      if failed != QNIL
        return failed
      end
      w = Libc.write(Machine.i32(zr_fix2long(fd)), RString[s].ptr + at, n)
    end
    zr_fix(w)
  end

  #: (value) -> value
  def zr_io_close(fd)
    zr_io_status(Libc.close(Machine.i32(zr_fix2long(fd))))
  end

  # dup(2): a new descriptor for the same open file, or the negated
  # errno. dup2(2) puts the open file of `from` on the descriptor `to`,
  # and closes the file that was there.
  #: (value) -> value
  def zr_io_dup(fd)
    r = Libc.dup(Machine.i32(zr_fix2long(fd)))
    r < Machine.i32(0) ? zr_fix(0 - zr_errno()) : zr_fix(Machine.sword(r))
  end

  #: (value, value) -> value
  def zr_io_dup2(from, to)
    zr_io_status(Libc.dup2(Machine.i32(zr_fix2long(from)), Machine.i32(zr_fix2long(to))))
  end

  #: (value) -> value
  def zr_io_fsync(fd)
    zr_io_status(Libc.fsync(Machine.i32(zr_fix2long(fd))))
  end

  # The new position, or the negated errno. An off_t past a fixnum is a
  # Bignum both ways: the offset, which the core checked fits 64 bits,
  # and the position.
  #: (value, value, value) -> value
  def zr_io_seek(fd, offset, whence)
    at = Machine.slot(8)
    if zr_fixnum_p(offset)
      Machine.store64(at, 0, zr_fix2long(offset))
    else
      zr_big_to_long(offset, at)
    end
    r = Libc.lseek(Machine.i32(zr_fix2long(fd)), Machine.load64(at, 0), Machine.i32(zr_fix2long(whence)))
    r < 0 ? zr_fix(0 - zr_errno()) : zr_int_from_word(r)
  end

  #: (value) -> value
  def zr_io_tty_p(fd)
    zr_bool(Machine.u32(Libc.isatty(Machine.i32(zr_fix2long(fd)))) != 0)
  end

  # The terminal calls that io/console makes. An ioctl goes through
  # `zr_os_ioctl`, which passes the variadic argument of ioctl.

  # struct winsize: four unsigned shorts. The rows and the columns are
  # first.
  WINSIZE_LEN = 8

  # The window size as raw bytes, or the negated errno.
  #: (value) -> value
  def zr_io_winsize(fd)
    buf = Machine.slot(WINSIZE_LEN)
    if zr_os_ioctl(Machine.i32(zr_fix2long(fd)), TIOCGWINSZ, buf) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_str_new(buf, WINSIZE_LEN)
  end

  #: (value, value) -> value
  def zr_io_set_winsize(fd, bytes)
    zr_io_status(zr_os_ioctl(Machine.i32(zr_fix2long(fd)), TIOCSWINSZ, RString[bytes].ptr))
  end

  # The mode of the terminal as raw bytes, or the negated errno.
  #: (value) -> value
  def zr_io_termios(fd)
    buf = Machine.slot(TERMIOS_LEN)
    if Libc.tcgetattr(Machine.i32(zr_fix2long(fd)), buf) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_str_new(buf, TERMIOS_LEN)
  end

  # The bytes of a struct termios, which an allocated IO::Console::Mode
  # holds as zeros (conmode_alloc).
  #: () -> value
  def zr_io_termios_len
    zr_fix(TERMIOS_LEN)
  end

  #: (value, value, value) -> value
  def zr_io_set_termios(fd, action, bytes)
    zr_io_status(Libc.tcsetattr(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(action)),
                           RString[bytes].ptr))
  end

  #: (value, value) -> value
  def zr_io_tcflush(fd, queue)
    zr_io_status(Libc.tcflush(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(queue))))
  end

  # A pseudo-terminal pair, through the Unix98 calls that ruby makes:
  # posix_openpt for the master, then grantpt and unlockpt, then the name
  # of the slave device. ruby opens the slave by that name.

  # The master descriptor and the name of the slave, or the negated errno.
  #: () -> value
  def zr_pty_open
    master = Libc.posix_openpt(Machine.i32(PTY_OPEN_FLAGS))
    if master < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    if Libc.grantpt(master) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    if Libc.unlockpt(master) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    name = Libc.ptsname(master)
    if Machine.word(name) == 0
      return zr_fix(0 - zr_errno())
    end
    out = zr_ary_new(2)
    zr_ary_push(out, zr_fix(Machine.sword(master)))
    zr_ary_push(out, zr_cstr_str(name))
    out
  end

  # The name of the terminal, or nil for a descriptor that is not a
  # terminal.
  #: (value) -> value
  def zr_io_ttyname(fd)
    name = Libc.ttyname(Machine.i32(zr_fix2long(fd)))
    Machine.word(name) == 0 ? Machine.value(QNIL) : zr_cstr_str(name)
  end

  #: (value) -> value
  def zr_io_unlink(path)
    zr_io_status(Libc.unlink(RString[path].ptr))
  end

  #: (value, value) -> value
  def zr_io_rename(from, to)
    zr_io_status(Libc.rename(RString[from].ptr, RString[to].ptr))
  end

  #: (value, value) -> value
  def zr_io_mkdir(path, mode)
    zr_io_status(Libc.mkdir(RString[path].ptr, Machine.i32(zr_fix2long(mode))))
  end

  #: (value) -> value
  def zr_io_rmdir(path)
    zr_io_status(Libc.rmdir(RString[path].ptr))
  end

  #: (value) -> value
  def zr_io_chdir(path)
    zr_io_status(Libc.chdir(RString[path].ptr))
  end

  # The names in a directory, including `.` and `..`, in the order of the
  # file system, or the negated errno.
  #: (value) -> value
  def zr_io_dir_names(path)
    d = Libc.opendir(RString[path].ptr)
    if d == 0
      return zr_fix(0 - zr_errno())
    end
    out = zr_ary_new(8)
    e = Libc.readdir(d)
    while e != 0
      name = zr_os_dirent_name(e)
      zr_ary_push(out, zr_path_str(zr_str_new(name, zr_cstr_len(name))))
      e = Libc.readdir(d)
    end
    Libc.closedir(d)
    out
  end

  # The names in a directory with the kind of each, as readdir's d_type
  # gives it (zr_os_dirent_kind), in pairs: name, kind, name, kind, ...
  # glob reads a directory this way, so it needs no lstat(2) for an entry
  # whose kind the directory already knows.
  #: (value) -> value
  def zr_io_dir_kinds(path)
    d = Libc.opendir(RString[path].ptr)
    if d == 0
      return zr_fix(0 - zr_errno())
    end
    out = zr_ary_new(16)
    e = Libc.readdir(d)
    while e != 0
      name = zr_os_dirent_name(e)
      zr_ary_push(out, zr_path_str(zr_str_new(name, zr_cstr_len(name))))
      zr_ary_push(out, zr_fix(zr_os_dirent_kind(e)))
      e = Libc.readdir(d)
    end
    Libc.closedir(d)
    out
  end

  # pathconf(2): the value of `name` for the file at `path`, or the
  # negated errno. A limit that the system does not have is -1 with no
  # errno, which answers nil.
  #: (value, value) -> value
  def zr_io_pathconf(path, name)
    zr_os_set_errno(0)
    r = Libc.pathconf(RString[path].ptr, Machine.i32(zr_fix2long(name)))
    if r < 0
      e = zr_errno()
      if e == 0
        return Machine.value(QNIL)
      end
      return zr_fix(0 - e)
    end
    zr_fix(r)
  end

  # fpathconf(3): pathconf for an open descriptor, with the same answers.
  #: (value, value) -> value
  def zr_io_fpathconf(fd, name)
    zr_os_set_errno(0)
    r = Libc.fpathconf(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(name)))
    if r < 0
      e = zr_errno()
      if e == 0
        return Machine.value(QNIL)
      end
      return zr_fix(0 - e)
    end
    zr_fix(r)
  end

  # The same names through a descriptor. This is the only way to get them
  # when a program has a descriptor and no path.
  #: (value) -> value
  def zr_io_dir_names_fd(fd)
    # closedir closes the descriptor it reads, so it reads a copy: the
    # Dir keeps its own until Dir#close, as fdopendir gives it.
    copy = Libc.dup(Machine.i32(zr_fix2long(fd)))
    if copy < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    d = Libc.fdopendir(copy)
    if d == 0
      e = zr_errno()
      Libc.close(copy)
      return zr_fix(0 - e)
    end
    out = zr_ary_new(8)
    e = Libc.readdir(d)
    while e != 0
      name = zr_os_dirent_name(e)
      zr_ary_push(out, zr_path_str(zr_str_new(name, zr_cstr_len(name))))
      e = Libc.readdir(d)
    end
    Libc.closedir(d)
    out
  end

  #: (value) -> value
  def zr_io_fchdir(fd)
    zr_io_status(Libc.fchdir(Machine.i32(zr_fix2long(fd))))
  end

  #: (value) -> value
  def zr_io_chroot(path)
    zr_io_status(Libc.chroot(RString[path].ptr))
  end

  # The message that strerror gives for errno `n`.
  #: (value) -> value
  def zr_io_strerror(n)
    p = Libc.strerror(Machine.i32(zr_fix2long(n)))
    zr_str_new(p, zr_cstr_len(p))
  end

  # The size in bytes of the file at `path`, or the negated errno.
  #: (value) -> value
  def zr_io_file_size(path)
    buf = Machine.slot(STAT_LEN)
    if Libc.stat(RString[path].ptr, buf) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_fix(zr_os_stat_size(buf))
  end

  # Calls that take one path and one small number: the owner for chown,
  # the length for truncate, and others. `which` selects the call. Returns
  # 0 or a negative errno.
  #: (value, value, value, value) -> value
  def zr_fs_call(which, path, a, b)
    w = zr_fix2long(which)
    r = Machine.i32(0)
    if w == 0
      r = Libc.chown(RString[path].ptr, Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
    elsif w == 1
      r = Libc.lchown(RString[path].ptr, Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
    elsif w == 2
      r = Libc.link(RString[path].ptr, RString[a].ptr)
    elsif w == 3
      r = Libc.symlink(RString[path].ptr, RString[a].ptr)
    elsif w == 4
      r = Libc.mkfifo(RString[path].ptr, Machine.i32(zr_fix2long(a)))
    elsif w == 5
      r = Libc.truncate(RString[path].ptr, zr_fix2long(a))
    elsif w == 6
      r = Libc.ftruncate(Machine.i32(zr_fix2long(a)), zr_fix2long(b))
    elsif w == 7
      r = Libc.fchmod(Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
    elsif w == 8
      r = Libc.flock(Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
    elsif w == 9
      r = Libc.lchmod(RString[path].ptr, Machine.i32(zr_fix2long(a)))
    end
    zr_io_status(r)
  end

  # utimensat(2) from the working directory. `times` is the access and
  # the modification time as [seconds, nanoseconds, seconds, nanoseconds],
  # or nil for now. `link` true sets the times of a link itself and not
  # of its target.
  #: (value, value, value) -> value
  def zr_utimens_m(path, times, link)
    spec = Machine.ptr(0)
    if times != QNIL
      spec = Machine.slot(32)
      Machine.store64(spec, 0, zr_fix2long(zr_ary_at(times, 0)))
      Machine.store64(spec, 8, zr_fix2long(zr_ary_at(times, 1)))
      Machine.store64(spec, 16, zr_fix2long(zr_ary_at(times, 2)))
      Machine.store64(spec, 24, zr_fix2long(zr_ary_at(times, 3)))
    end
    flags = 0
    if link == QTRUE
      flags = AT_SYMLINK_NOFOLLOW
    end
    zr_io_status(Libc.utimensat(Machine.i32(AT_FDCWD), RString[path].ptr, spec, Machine.i32(flags)))
  end

  # umask(2): returns the old mask, and sets the new one when `mask` is
  # not nil.
  #: (value) -> value
  def zr_umask_m(mask)
    if mask == QNIL
      was = Libc.umask(Machine.i32(0))
      Libc.umask(was)
      return zr_fix(Machine.u32(was))
    end
    zr_fix(Machine.u32(Libc.umask(Machine.i32(zr_fix2long(mask)))))
  end

  # readlink(2): the target of the symlink, or a negative errno.
  #: (value) -> value
  def zr_readlink_m(path)
    buf = zr_xmalloc(4096)
    n = Libc.readlink(RString[path].ptr, buf, 4095)
    if n < 0
      zr_xfree(buf)
      return zr_fix(0 - zr_errno())
    end
    s = zr_str_new(buf, n)
    zr_xfree(buf)
    s
  end

  # stat(2) (or lstat when `follow` is false) as fixnums in an Array:
  # dev, ino, mode, nlink, uid, gid, rdev, size, blksize, blocks, then
  # atime, mtime and ctime as seconds and nanoseconds. Returns a negative
  # errno on failure.
  #: (value, value) -> value
  def zr_stat_m(path, follow)
    buf = Machine.slot(STAT_LEN)
    r = follow == QFALSE ? Libc.lstat(RString[path].ptr, buf) : Libc.stat(RString[path].ptr, buf)
    if r < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_os_stat_rows(buf)
  end

  # fstat(2): the same fields for a descriptor. This is the only way to
  # get them when the stream was opened from a descriptor and has no path.
  #: (value) -> value
  def zr_fstat_m(fd)
    buf = Machine.slot(STAT_LEN)
    if Libc.fstat(Machine.i32(zr_fix2long(fd)), buf) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_os_stat_rows(buf)
  end

  # realpath(3): the resolved path, or a negative errno. The OS layer
  # gives ENOSYS where the system has no realpath (WASI).
  #: (value) -> value
  def zr_realpath_m(path)
    p = zr_os_realpath(RString[path].ptr)
    if p == 0
      return zr_fix(0 - zr_errno())
    end
    s = zr_str_new(p, zr_cstr_len(p))
    zr_xfree(p)
    s
  end

  #: (value, value) -> value
  def zr_chmod_m(path, mode)
    if Libc.chmod(RString[path].ptr, Machine.i32(zr_fix2long(mode))) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_fix(0)
  end

  # access(2): whether the process can use the file as `mode` gives (4
  # read, 2 write, 1 execute).
  #: (value, value) -> value
  def zr_path_access(path, mode)
    zr_bool(Machine.u32(Libc.access(RString[path].ptr, Machine.i32(zr_fix2long(mode)))) == 0)
  end

  # The bits in `events`: IO::READABLE, IO::PRIORITY, IO::WRITABLE.
  WAIT_READABLE = 1
  WAIT_PRIORITY = 2
  WAIT_WRITABLE = 4

  # The wait of the thread scheduler on all descriptors that suspended
  # threads wait for. Returns the ready events for each descriptor. They
  # are all zero when the time ends, or when a POSIX signal stops the wait
  # (after its handlers run). On failure, returns the negated errno.
  #: (value, value, value) -> value
  def zr_io_wait_fds(fds, events, milliseconds)
    r = zr_os_wait_fds(fds, events, milliseconds)
    if r == zr_fix(0 - EINTR)
      if zr_trap_check() == QUNDEF
        return Machine.value(QUNDEF)
      end
      r = zr_ary_new(RArray[fds].len)
      i = 0
      while i < RArray[fds].len
        zr_ary_push(r, zr_fix(0))
        i += 1
      end
    end
    r
  end

  # The wait on one descriptor. Returns the ready events, 0 when the time
  # ends, or the negated errno. A negative time waits with no limit. A
  # POSIX signal that stops the wait runs its handlers first.
  #: (value, value, value) -> value
  def zr_io_wait(fd, events, milliseconds)
    r = zr_os_wait_fd(fd, events, milliseconds)
    while r == zr_fix(0 - EINTR)
      if zr_trap_check() == QUNDEF
        return Machine.value(QUNDEF)
      end
      r = zr_os_wait_fd(fd, events, milliseconds)
    end
    r
  end
end
