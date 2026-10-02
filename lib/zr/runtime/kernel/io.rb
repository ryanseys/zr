module Zr::Kern
  # File descriptors: the libSystem calls that the IO and File classes
  # use. A failure returns the negated errno, and the core converts it to
  # the matching Errno class.
  Libc.import :read, [I32, Ptr, Word] => Word
  Libc.import :pread, [I32, Ptr, Word, Word] => Word
  Libc.import :pwrite, [I32, Ptr, Word, Word] => Word
  Libc.import :close, [I32] => I32
  Libc.import :dup, [I32] => I32
  Libc.import :dup2, [I32, I32] => I32
  Libc.import :fsync, [I32] => I32
  Libc.import :lseek, [I32, Word, I32] => Word
  Libc.import :unlink, [Ptr] => I32
  Libc.import :rename, [Ptr, Ptr] => I32
  Libc.import :isatty, [I32] => I32
  Libc.import :fstat, [I32, Ptr] => I32
  Libc.import :fchmod, [I32, I32] => I32
  Libc.import :mkdir, [Ptr, I32] => I32
  Libc.import :rmdir, [Ptr] => I32
  Libc.import :chdir, [Ptr] => I32
  Libc.import :opendir, [Ptr] => Ptr
  Libc.import :fdopendir, [I32] => Ptr
  Libc.import :fchdir, [I32] => I32
  Libc.import :readdir, [Ptr] => Ptr
  Libc.import :closedir, [Ptr] => I32
  Libc.import :strerror, [I32] => Ptr

  sig [] => Word
  def zr_errno
    zr_os_errno()
  end

  # Clears errno, for a call whose return value cannot show a failure.
  # After this, only a failure of the next call sets errno.
  sig [] => Void
  def zr_clear_errno
    zr_os_set_errno(0)
  end

  sig [Word] => Value
  def zr_io_failed(r)
    r < 0 ? zr_fix(0 - zr_errno()) : zr_fix(r)
  end

  # Converts an int result: 0 on success, or the negated errno when the
  # call returned -1.
  sig [I32] => Value
  def zr_io_status(r)
    r < Machine.i32(0) ? zr_fix(0 - zr_errno()) : zr_fix(0)
  end

  # F_GETFL: the status flags of the descriptor, which show the mode it
  # was opened with. Each fcntl goes through `zr_os_fcntl`, which passes
  # the variadic argument of fcntl as each OS needs it.
  F_GETFL = 3

  sig [Value] => Value
  def zr_io_flags(fd)
    zr_io_failed(Machine.sword(zr_os_fcntl(Machine.i32(zr_fix2long(fd)), Machine.i32(F_GETFL), 0)))
  end

  # Makes a descriptor return EAGAIN instead of waiting.
  F_SETFL = 4

  sig [Value, Value] => Value
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
  sig [Value] => Value
  def zr_io_cloexec(fd)
    zr_io_status(zr_os_fcntl(Machine.i32(zr_fix2long(fd)), Machine.i32(F_SETFD), Machine.word(FD_CLOEXEC)))
  end

  # ioctl(2) with the argument of a command: a number that the command
  # reads as is, or the bytes of a String that the command fills in. The
  # address of a String never goes into ruby, so there are two calls, not
  # one call for which ruby would have to make a pointer.
  sig [Value, Value, Value] => Value
  def zr_io_ioctl(fd, command, argument)
    zr_io_failed(Machine.sword(zr_os_ioctl(Machine.i32(zr_fix2long(fd)), Machine.word(zr_fix2long(command)),
                                       Machine.ptr(zr_fix2long(argument)))))
  end

  sig [Value, Value, Value] => Value
  def zr_io_ioctl_buf(fd, command, bytes)
    zr_io_failed(Machine.sword(zr_os_ioctl(Machine.i32(zr_fix2long(fd)), Machine.word(zr_fix2long(command)),
                                       RString.ptr(bytes))))
  end

  # fcntl(2) with a command that the program gives, and the argument of
  # that command, through `zr_os_fcntl` as for the non-blocking flag.
  sig [Value, Value, Value] => Value
  def zr_io_fcntl(fd, command, argument)
    zr_io_failed(Machine.sword(zr_os_fcntl(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(command)),
                                      Machine.word(zr_fix2long(argument)))))
  end

  # fcntl(2) with a struct that the call reads or fills. The bytes of the
  # String are the struct, in place.
  sig [Value, Value, Value] => Value
  def zr_io_fcntl_bytes(fd, command, bytes)
    zr_io_failed(Machine.sword(zr_os_fcntl(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(command)),
                                      Machine.word(RString.ptr(bytes)))))
  end

  # rb_sysopen: open(2) with the flags, and the permissions for a new
  # file, minus the umask. Each descriptor that ruby opens closes across
  # an exec, so rb_sysopen adds O_CLOEXEC to the call.
  sig [Value, Value, Value] => Value
  def zr_io_open_flags(path, flags, perm)
    fd = zr_os_open(RString.ptr(path), Machine.i32(zr_fix2long(flags) | O_CLOEXEC), Machine.i32(zr_fix2long(perm)))
    while fd < Machine.i32(0)
      failed = zr_io_retry()
      if failed != QNIL
        return failed
      end
      fd = zr_os_open(RString.ptr(path), Machine.i32(zr_fix2long(flags) | O_CLOEXEC), Machine.i32(zr_fix2long(perm)))
    end
    zr_fix(Machine.sword(fd))
  end

  # Reads up to `count` bytes. Returns a String, nil at the end, or the
  # negated errno.
  sig [Value, Value] => Value
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
  sig [Value, Value, Value] => Value
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

  sig [Value, Value, Value] => Value
  def zr_io_pwrite(fd, s, at)
    n = RString.len(s)
    done = 0
    while done < n
      w = Libc.pwrite(Machine.i32(zr_fix2long(fd)), RString.ptr(s) + done, n - done, zr_fix2long(at) + done)
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
  sig [Value, Value] => Value
  def zr_io_write(fd, s)
    done = 0
    while done < RString.len(s)
      w = Libc.write(Machine.i32(zr_fix2long(fd)), RString.ptr(s) + done, RString.len(s) - done)
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
  sig [Value, Value, Value, Value] => Value
  def zr_io_write_some(fd, s, from, count)
    at = zr_fix2long(from)
    n = RString.len(s) - at
    if n > zr_fix2long(count)
      n = zr_fix2long(count)
    end
    w = Libc.write(Machine.i32(zr_fix2long(fd)), RString.ptr(s) + at, n)
    while w < 0
      failed = zr_io_retry()
      if failed != QNIL
        return failed
      end
      w = Libc.write(Machine.i32(zr_fix2long(fd)), RString.ptr(s) + at, n)
    end
    zr_fix(w)
  end

  sig [Value] => Value
  def zr_io_close(fd)
    zr_io_status(Libc.close(Machine.i32(zr_fix2long(fd))))
  end

  # dup(2): a new descriptor for the same open file, or the negated
  # errno. dup2(2) puts the open file of `from` on the descriptor `to`,
  # and closes the file that was there.
  sig [Value] => Value
  def zr_io_dup(fd)
    r = Libc.dup(Machine.i32(zr_fix2long(fd)))
    r < Machine.i32(0) ? zr_fix(0 - zr_errno()) : zr_fix(Machine.sword(r))
  end

  sig [Value, Value] => Value
  def zr_io_dup2(from, to)
    zr_io_status(Libc.dup2(Machine.i32(zr_fix2long(from)), Machine.i32(zr_fix2long(to))))
  end

  sig [Value] => Value
  def zr_io_fsync(fd)
    zr_io_status(Libc.fsync(Machine.i32(zr_fix2long(fd))))
  end

  sig [Value, Value, Value] => Value
  def zr_io_seek(fd, offset, whence)
    zr_io_failed(Libc.lseek(Machine.i32(zr_fix2long(fd)), zr_fix2long(offset), Machine.i32(zr_fix2long(whence))))
  end

  sig [Value] => Value
  def zr_io_tty_p(fd)
    zr_bool(Machine.u32(Libc.isatty(Machine.i32(zr_fix2long(fd)))) != 0)
  end

  # The terminal calls that io/console makes. An ioctl goes through
  # `zr_os_ioctl`, which passes the variadic argument of ioctl.
  Libc.import :tcgetattr, [I32, Ptr] => I32
  Libc.import :tcsetattr, [I32, I32, Ptr] => I32
  Libc.import :tcflush, [I32, I32] => I32
  Libc.import :ttyname, [I32] => Ptr

  # struct winsize: four unsigned shorts. The rows and the columns are
  # first.
  WINSIZE_LEN = 8

  # The window size as raw bytes, or the negated errno.
  sig [Value] => Value
  def zr_io_winsize(fd)
    buf = Machine.slot(WINSIZE_LEN)
    if zr_os_ioctl(Machine.i32(zr_fix2long(fd)), TIOCGWINSZ, buf) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_str_new(buf, WINSIZE_LEN)
  end

  sig [Value, Value] => Value
  def zr_io_set_winsize(fd, bytes)
    zr_io_status(zr_os_ioctl(Machine.i32(zr_fix2long(fd)), TIOCSWINSZ, RString.ptr(bytes)))
  end

  # The mode of the terminal as raw bytes, or the negated errno.
  sig [Value] => Value
  def zr_io_termios(fd)
    buf = Machine.slot(TERMIOS_LEN)
    if Libc.tcgetattr(Machine.i32(zr_fix2long(fd)), buf) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_str_new(buf, TERMIOS_LEN)
  end

  sig [Value, Value, Value] => Value
  def zr_io_set_termios(fd, action, bytes)
    zr_io_status(Libc.tcsetattr(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(action)),
                           RString.ptr(bytes)))
  end

  sig [Value, Value] => Value
  def zr_io_tcflush(fd, queue)
    zr_io_status(Libc.tcflush(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(queue))))
  end

  # A pseudo-terminal pair, through the Unix98 calls that ruby makes:
  # posix_openpt for the master, then grantpt and unlockpt, then the name
  # of the slave device. ruby opens the slave by that name.
  Libc.import :posix_openpt, [I32] => I32
  Libc.import :grantpt, [I32] => I32
  Libc.import :unlockpt, [I32] => I32
  Libc.import :ptsname, [I32] => Ptr

  # The master descriptor and the name of the slave, or the negated errno.
  sig [] => Value
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
  sig [Value] => Value
  def zr_io_ttyname(fd)
    name = Libc.ttyname(Machine.i32(zr_fix2long(fd)))
    Machine.word(name) == 0 ? Machine.value(QNIL) : zr_cstr_str(name)
  end

  sig [Value] => Value
  def zr_io_unlink(path)
    zr_io_status(Libc.unlink(RString.ptr(path)))
  end

  sig [Value, Value] => Value
  def zr_io_rename(from, to)
    zr_io_status(Libc.rename(RString.ptr(from), RString.ptr(to)))
  end

  sig [Value, Value] => Value
  def zr_io_mkdir(path, mode)
    zr_io_status(Libc.mkdir(RString.ptr(path), Machine.i32(zr_fix2long(mode))))
  end

  sig [Value] => Value
  def zr_io_rmdir(path)
    zr_io_status(Libc.rmdir(RString.ptr(path)))
  end

  sig [Value] => Value
  def zr_io_chdir(path)
    zr_io_status(Libc.chdir(RString.ptr(path)))
  end

  # The names in a directory, including `.` and `..`, in the order of the
  # file system, or the negated errno.
  sig [Value] => Value
  def zr_io_dir_names(path)
    d = Libc.opendir(RString.ptr(path))
    if d == 0
      return zr_fix(0 - zr_errno())
    end
    out = zr_ary_new(8)
    e = Libc.readdir(d)
    while e != 0
      name = zr_os_dirent_name(e)
      zr_ary_push(out, zr_str_new(name, zr_cstr_len(name)))
      e = Libc.readdir(d)
    end
    Libc.closedir(d)
    out
  end

  # The names in a directory with the kind of each, as readdir's d_type
  # gives it (zr_os_dirent_kind), in pairs: name, kind, name, kind, ...
  # glob reads a directory this way, so it needs no lstat(2) for an entry
  # whose kind the directory already knows.
  sig [Value] => Value
  def zr_io_dir_kinds(path)
    d = Libc.opendir(RString.ptr(path))
    if d == 0
      return zr_fix(0 - zr_errno())
    end
    out = zr_ary_new(16)
    e = Libc.readdir(d)
    while e != 0
      name = zr_os_dirent_name(e)
      zr_ary_push(out, zr_str_new(name, zr_cstr_len(name)))
      zr_ary_push(out, zr_fix(zr_os_dirent_kind(e)))
      e = Libc.readdir(d)
    end
    Libc.closedir(d)
    out
  end

  # pathconf(2): the value of `name` for the file at `path`, or the
  # negated errno. A limit that the system does not have is -1 with no
  # errno, which answers nil.
  sig [Value, Value] => Value
  def zr_io_pathconf(path, name)
    zr_os_set_errno(0)
    r = Libc.pathconf(RString.ptr(path), Machine.i32(zr_fix2long(name)))
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
  sig [Value, Value] => Value
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
  sig [Value] => Value
  def zr_io_dir_names_fd(fd)
    d = Libc.fdopendir(Machine.i32(zr_fix2long(fd)))
    if d == 0
      return zr_fix(0 - zr_errno())
    end
    out = zr_ary_new(8)
    e = Libc.readdir(d)
    while e != 0
      name = zr_os_dirent_name(e)
      zr_ary_push(out, zr_str_new(name, zr_cstr_len(name)))
      e = Libc.readdir(d)
    end
    Libc.closedir(d)
    out
  end

  sig [Value] => Value
  def zr_io_fchdir(fd)
    zr_io_status(Libc.fchdir(Machine.i32(zr_fix2long(fd))))
  end

  Libc.import :chroot, [Ptr] => I32

  sig [Value] => Value
  def zr_io_chroot(path)
    zr_io_status(Libc.chroot(RString.ptr(path)))
  end

  # The message that strerror gives for errno `n`.
  sig [Value] => Value
  def zr_io_strerror(n)
    p = Libc.strerror(Machine.i32(zr_fix2long(n)))
    zr_str_new(p, zr_cstr_len(p))
  end

  # The size in bytes of the file at `path`, or the negated errno.
  sig [Value] => Value
  def zr_io_file_size(path)
    buf = Machine.slot(STAT_LEN)
    if Libc.stat(RString.ptr(path), buf) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_fix(zr_os_stat_size(buf))
  end

  Libc.import :lstat, [Ptr, Ptr] => I32
  Libc.import :realpath, [Ptr, Ptr] => Ptr
  Libc.import :chmod, [Ptr, I32] => I32
  Libc.import :fchmod, [I32, I32] => I32
  Libc.import :chown, [Ptr, I32, I32] => I32
  Libc.import :lchown, [Ptr, I32, I32] => I32
  Libc.import :lchmod, [Ptr, I32] => I32
  Libc.import :link, [Ptr, Ptr] => I32
  Libc.import :symlink, [Ptr, Ptr] => I32
  Libc.import :readlink, [Ptr, Ptr, Word] => Word
  Libc.import :mkfifo, [Ptr, I32] => I32
  Libc.import :truncate, [Ptr, Word] => I32
  Libc.import :ftruncate, [I32, Word] => I32
  Libc.import :umask, [I32] => I32
  Libc.import :utimensat, [I32, Ptr, Ptr, I32] => I32
  Libc.import :flock, [I32, I32] => I32

  # Calls that take one path and one small number: the owner for chown,
  # the length for truncate, and others. `which` selects the call. Returns
  # 0 or a negative errno.
  sig [Value, Value, Value, Value] => Value
  def zr_fs_call(which, path, a, b)
    w = zr_fix2long(which)
    r = Machine.i32(0)
    if w == 0
      r = Libc.chown(RString.ptr(path), Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
    elsif w == 1
      r = Libc.lchown(RString.ptr(path), Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
    elsif w == 2
      r = Libc.link(RString.ptr(path), RString.ptr(a))
    elsif w == 3
      r = Libc.symlink(RString.ptr(path), RString.ptr(a))
    elsif w == 4
      r = Libc.mkfifo(RString.ptr(path), Machine.i32(zr_fix2long(a)))
    elsif w == 5
      r = Libc.truncate(RString.ptr(path), zr_fix2long(a))
    elsif w == 6
      r = Libc.ftruncate(Machine.i32(zr_fix2long(a)), zr_fix2long(b))
    elsif w == 7
      r = Libc.fchmod(Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
    elsif w == 8
      r = Libc.flock(Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
    elsif w == 9
      r = Libc.lchmod(RString.ptr(path), Machine.i32(zr_fix2long(a)))
    end
    zr_io_status(r)
  end

  # utimensat(2) from the working directory. `times` is the access and
  # the modification time as [seconds, nanoseconds, seconds, nanoseconds],
  # or nil for now. `link` true sets the times of a link itself and not
  # of its target.
  sig [Value, Value, Value] => Value
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
    zr_io_status(Libc.utimensat(Machine.i32(AT_FDCWD), RString.ptr(path), spec, Machine.i32(flags)))
  end

  # umask(2): returns the old mask, and sets the new one when `mask` is
  # not nil.
  sig [Value] => Value
  def zr_umask_m(mask)
    if mask == QNIL
      was = Libc.umask(Machine.i32(0))
      Libc.umask(was)
      return zr_fix(Machine.u32(was))
    end
    zr_fix(Machine.u32(Libc.umask(Machine.i32(zr_fix2long(mask)))))
  end

  # readlink(2): the target of the symlink, or a negative errno.
  sig [Value] => Value
  def zr_readlink_m(path)
    buf = zr_xmalloc(4096)
    n = Libc.readlink(RString.ptr(path), buf, 4095)
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
  sig [Value, Value] => Value
  def zr_stat_m(path, follow)
    buf = Machine.slot(STAT_LEN)
    r = follow == QFALSE ? Libc.lstat(RString.ptr(path), buf) : Libc.stat(RString.ptr(path), buf)
    if r < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_os_stat_rows(buf)
  end

  # fstat(2): the same fields for a descriptor. This is the only way to
  # get them when the stream was opened from a descriptor and has no path.
  sig [Value] => Value
  def zr_fstat_m(fd)
    buf = Machine.slot(STAT_LEN)
    if Libc.fstat(Machine.i32(zr_fix2long(fd)), buf) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_os_stat_rows(buf)
  end

  # realpath(3): the resolved path, or a negative errno.
  sig [Value] => Value
  def zr_realpath_m(path)
    p = Libc.realpath(RString.ptr(path), 0)
    if p == 0
      return zr_fix(0 - zr_errno())
    end
    s = zr_str_new(p, zr_cstr_len(p))
    zr_xfree(p)
    s
  end

  sig [Value, Value] => Value
  def zr_chmod_m(path, mode)
    if Libc.chmod(RString.ptr(path), Machine.i32(zr_fix2long(mode))) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_fix(0)
  end

  # access(2): whether the process can use the file as `mode` gives (4
  # read, 2 write, 1 execute).
  sig [Value, Value] => Value
  def zr_path_access(path, mode)
    zr_bool(Machine.u32(Libc.access(RString.ptr(path), Machine.i32(zr_fix2long(mode)))) == 0)
  end

  # The bits in `events`: IO::READABLE, IO::PRIORITY, IO::WRITABLE.
  WAIT_READABLE = 1
  WAIT_PRIORITY = 2
  WAIT_WRITABLE = 4

  # The wait of the thread scheduler on all descriptors that suspended
  # threads wait for. Returns the ready events for each descriptor. They
  # are all zero when the time ends, or when a POSIX signal stops the wait
  # (after its handlers run). On failure, returns the negated errno.
  sig [Value, Value, Value] => Value
  def zr_io_wait_fds(fds, events, milliseconds)
    r = zr_os_wait_fds(fds, events, milliseconds)
    if r == zr_fix(0 - EINTR)
      if zr_trap_check() == QUNDEF
        return Machine.value(QUNDEF)
      end
      r = zr_ary_new(RArray.len(fds))
      i = 0
      while i < RArray.len(fds)
        zr_ary_push(r, zr_fix(0))
        i += 1
      end
    end
    r
  end

  # The wait on one descriptor. Returns the ready events, 0 when the time
  # ends, or the negated errno. A negative time waits with no limit. A
  # POSIX signal that stops the wait runs its handlers first.
  sig [Value, Value, Value] => Value
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
