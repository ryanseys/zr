# File descriptors: the libSystem calls the IO and File classes use.
# A failure answers the negated errno, which the core turns into the
# Errno class it names.
Machine.import "fopen", [Ptr, Ptr] => Ptr
Machine.import "fileno", [Ptr] => I32
Machine.import "fclose", [Ptr] => I32
Machine.import "read", [I32, Ptr, Word] => Word
Machine.import "pread", [I32, Ptr, Word, Word] => Word
Machine.import "pwrite", [I32, Ptr, Word, Word] => Word
Machine.import "close", [I32] => I32
Machine.import "dup", [I32] => I32
Machine.import "dup2", [I32, I32] => I32
Machine.import "fsync", [I32] => I32
Machine.import "lseek", [I32, Word, I32] => Word
Machine.import "unlink", [Ptr] => I32
Machine.import "rename", [Ptr, Ptr] => I32
Machine.import "isatty", [I32] => I32
Machine.import "fstat", [I32, Ptr] => I32
Machine.import "fchmod", [I32, I32] => I32
Machine.import "mkdir", [Ptr, I32] => I32
Machine.import "rmdir", [Ptr] => I32
Machine.import "chdir", [Ptr] => I32
Machine.import "opendir", [Ptr] => Ptr
Machine.import "fdopendir", [I32] => Ptr
Machine.import "fchdir", [I32] => I32
Machine.import "readdir", [Ptr] => Ptr
Machine.import "closedir", [Ptr] => I32
Machine.import "strerror", [I32] => Ptr

sig [] => Word
machine def zr_errno
  zr_os_errno()
end

# errno cleared, for a call whose answer cannot say by itself that it
# failed: only a failure of the call that follows sets it again.
sig [] => Void
machine def zr_clear_errno
  zr_os_set_errno(0)
end

sig [Word] => Value
machine def zr_io_failed(r)
  r < 0 ? zr_fix(0 - zr_errno()) : zr_fix(r)
end

# An int answer: 0 on success, -1 with errno set on failure.
sig [I32] => Value
machine def zr_io_status(r)
  r < Machine.i32(0) ? zr_fix(0 - zr_errno()) : zr_fix(0)
end

# F_GETFL: the descriptor's own status flags, which say what it was
# opened for. Every fcntl goes through `zr_os_fcntl`, which passes the
# argument fcntl reads variadically as each OS needs it.
F_GETFL = 3

sig [Value] => Value
machine def zr_io_flags(fd)
  zr_io_failed(Machine.sword(zr_os_fcntl(Machine.i32(zr_fix2long(fd)), Machine.i32(F_GETFL), 0)))
end

# A descriptor that answers EAGAIN instead of waiting.
F_SETFL = 4

sig [Value, Value] => Value
machine def zr_io_set_nonblock(fd, on)
  n = Machine.i32(zr_fix2long(fd))
  r = zr_os_fcntl(n, Machine.i32(F_GETFL), 0)
  if r < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  flags = Machine.word(r)
  if zr_fix2long(on) != 0
    return zr_io_status(zr_os_fcntl(n, Machine.i32(F_SETFL), flags | O_NONBLOCK))
  end
  zr_io_status(zr_os_fcntl(n, Machine.i32(F_SETFL), flags & O_NONBLOCK_OFF))
end

# F_SETFD and the one flag it carries.
F_SETFD = 2
FD_CLOEXEC = 1

# A descriptor that closes itself across an exec, which ruby asks for on
# every descriptor it hands out. An open(2) says so on the call itself;
# pipe(2) here has no flag of its own, so rb_cloexec_pipe sets it after
# the call, as this does.
sig [Value] => Value
machine def zr_io_cloexec(fd)
  zr_io_status(zr_os_fcntl(Machine.i32(zr_fix2long(fd)), Machine.i32(F_SETFD), Machine.word(FD_CLOEXEC)))
end

# ioctl(2) with the argument a command carries: a number the command
# reads as it stands, or the bytes of a String the command fills in. A
# String's address never crosses into ruby, so the two shapes are two
# calls rather than one that ruby would have to build a pointer for.
sig [Value, Value, Value] => Value
machine def zr_io_ioctl(fd, command, argument)
  zr_io_failed(Machine.sword(zr_os_ioctl(Machine.i32(zr_fix2long(fd)), Machine.word(zr_fix2long(command)),
                                     Machine.ptr(zr_fix2long(argument)))))
end

sig [Value, Value, Value] => Value
machine def zr_io_ioctl_buf(fd, command, bytes)
  zr_io_failed(Machine.sword(zr_os_ioctl(Machine.i32(zr_fix2long(fd)), Machine.word(zr_fix2long(command)),
                                     RString.ptr(bytes))))
end

# fcntl(2) with a command the program names itself, and the argument that
# command takes, through `zr_os_fcntl` as the non-blocking flag goes.
sig [Value, Value, Value] => Value
machine def zr_io_fcntl(fd, command, argument)
  zr_io_failed(Machine.sword(zr_os_fcntl(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(command)),
                                    Machine.word(zr_fix2long(argument)))))
end

# open(2) with no mode: a creation goes through fopen and then fchmod,
# which names the permissions exactly. Every descriptor ruby opens
# closes itself across an exec, which rb_sysopen asks for with O_CLOEXEC
# on the call itself.
sig [Value, Value] => Value
machine def zr_io_open_flags(path, flags)
  fd = zr_os_open(RString.ptr(path), Machine.i32(zr_fix2long(flags) | O_CLOEXEC))
  while fd < Machine.i32(0)
    failed = zr_io_retry()
    if failed != QNIL
      return failed
    end
    fd = zr_os_open(RString.ptr(path), Machine.i32(zr_fix2long(flags) | O_CLOEXEC))
  end
  zr_fix(Machine.sword(fd))
end

sig [Value, Value] => Value
machine def zr_io_chmod_fd(fd, mode)
  zr_io_status(fchmod(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(mode))))
end

# fopen(3), which is not variadic as open(2) is: the stream as a
# pointer, or the negated errno. The stream's descriptor is read and
# written directly; the stream only opens and closes it.
sig [Value, Value] => Value
machine def zr_io_open(path, mode)
  f = fopen(RString.ptr(path), RString.ptr(mode))
  if f == 0
    return zr_fix(0 - zr_errno())
  end
  zr_fix(Machine.word(f))
end

sig [Value] => Value
machine def zr_io_fileno(stream)
  zr_fix(Machine.sword(fileno(Machine.ptr(zr_fix2long(stream)))))
end

sig [Value] => Value
machine def zr_io_fclose(stream)
  zr_io_status(fclose(Machine.ptr(zr_fix2long(stream))))
end

# Up to `count` bytes: a String, nil at the end, or the negated errno.
sig [Value, Value] => Value
machine def zr_io_read(fd, count)
  n = zr_fix2long(count)
  buf = zr_xmalloc(n + 1)
  got = read(Machine.i32(zr_fix2long(fd)), buf, n)
  while got < 0
    failed = zr_io_retry()
    if failed != QNIL
      free(buf)
      return failed
    end
    got = read(Machine.i32(zr_fix2long(fd)), buf, n)
  end
  if got == 0
    free(buf)
    return Machine.value(QNIL)
  end
  s = zr_str_new(buf, got)
  free(buf)
  s
end

# pread(2) and pwrite(2): a read or a write at a named file position
# that leaves the descriptor's own position where it was.
sig [Value, Value, Value] => Value
machine def zr_io_pread(fd, count, at)
  n = zr_fix2long(count)
  buf = zr_xmalloc(n + 1)
  got = pread(Machine.i32(zr_fix2long(fd)), buf, n, zr_fix2long(at))
  if got < 0
    free(buf)
    return zr_fix(0 - zr_errno())
  end
  if got == 0
    free(buf)
    return Machine.value(QNIL)
  end
  s = zr_str_new(buf, got)
  free(buf)
  s
end

sig [Value, Value, Value] => Value
machine def zr_io_pwrite(fd, s, at)
  n = RString.len(s)
  done = 0
  while done < n
    w = pwrite(Machine.i32(zr_fix2long(fd)), RString.ptr(s) + done, n - done, zr_fix2long(at) + done)
    if w < 0
      return zr_fix(0 - zr_errno())
    end
    done += w
  end
  zr_fix(n)
end

# Every byte of `s`, in as many calls as the descriptor takes.
sig [Value, Value] => Value
machine def zr_io_write(fd, s)
  n = RString.len(s)
  done = 0
  while done < n
    w = write(Machine.i32(zr_fix2long(fd)), RString.ptr(s) + done, n - done)
    if w < 0
      failed = zr_io_retry()
      if failed != QNIL
        return failed
      end
      w = 0
    end
    done += w
  end
  zr_fix(n)
end

# One write(2) of at most `count` bytes from `from`: the caller loops,
# so a task that shares the process hands the turn on between the
# calls rather than wait inside one long write.
sig [Value, Value, Value, Value] => Value
machine def zr_io_write_some(fd, s, from, count)
  at = zr_fix2long(from)
  n = RString.len(s) - at
  if n > zr_fix2long(count)
    n = zr_fix2long(count)
  end
  w = write(Machine.i32(zr_fix2long(fd)), RString.ptr(s) + at, n)
  while w < 0
    failed = zr_io_retry()
    if failed != QNIL
      return failed
    end
    w = write(Machine.i32(zr_fix2long(fd)), RString.ptr(s) + at, n)
  end
  zr_fix(w)
end

sig [Value] => Value
machine def zr_io_close(fd)
  zr_io_status(close(Machine.i32(zr_fix2long(fd))))
end

# dup(2): a fresh descriptor onto the same open file, or the negated
# errno. dup2(2) puts `from`'s open file on the descriptor `to` names,
# closing whatever was there.
sig [Value] => Value
machine def zr_io_dup(fd)
  r = dup(Machine.i32(zr_fix2long(fd)))
  r < Machine.i32(0) ? zr_fix(0 - zr_errno()) : zr_fix(Machine.sword(r))
end

sig [Value, Value] => Value
machine def zr_io_dup2(from, to)
  zr_io_status(dup2(Machine.i32(zr_fix2long(from)), Machine.i32(zr_fix2long(to))))
end

sig [Value] => Value
machine def zr_io_fsync(fd)
  zr_io_status(fsync(Machine.i32(zr_fix2long(fd))))
end

sig [Value, Value, Value] => Value
machine def zr_io_seek(fd, offset, whence)
  zr_io_failed(lseek(Machine.i32(zr_fix2long(fd)), zr_fix2long(offset), Machine.i32(zr_fix2long(whence))))
end

sig [Value] => Value
machine def zr_io_tty_p(fd)
  zr_bool(Machine.word(isatty(Machine.i32(zr_fix2long(fd)))) != 0)
end

# The terminal calls io/console makes. An ioctl goes through
# `zr_os_ioctl`, which passes the argument ioctl reads variadically.
Machine.import "tcgetattr", [I32, Ptr] => I32
Machine.import "tcsetattr", [I32, I32, Ptr] => I32
Machine.import "tcflush", [I32, I32] => I32
Machine.import "ttyname", [I32] => Ptr

# struct winsize: four unsigned shorts, the rows and the columns first.
WINSIZE_LEN = 8

# The window size as its own bytes, or the negated errno.
sig [Value] => Value
machine def zr_io_winsize(fd)
  buf = Machine.slot(WINSIZE_LEN)
  if zr_os_ioctl(Machine.i32(zr_fix2long(fd)), TIOCGWINSZ, buf) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_str_new(buf, WINSIZE_LEN)
end

sig [Value, Value] => Value
machine def zr_io_set_winsize(fd, bytes)
  zr_io_status(zr_os_ioctl(Machine.i32(zr_fix2long(fd)), TIOCSWINSZ, RString.ptr(bytes)))
end

# The terminal's mode as its own bytes, or the negated errno.
sig [Value] => Value
machine def zr_io_termios(fd)
  buf = Machine.slot(TERMIOS_LEN)
  if tcgetattr(Machine.i32(zr_fix2long(fd)), buf) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_str_new(buf, TERMIOS_LEN)
end

sig [Value, Value, Value] => Value
machine def zr_io_set_termios(fd, action, bytes)
  zr_io_status(tcsetattr(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(action)),
                         RString.ptr(bytes)))
end

sig [Value, Value] => Value
machine def zr_io_tcflush(fd, queue)
  zr_io_status(tcflush(Machine.i32(zr_fix2long(fd)), Machine.i32(zr_fix2long(queue))))
end

# A pseudo-terminal pair, through the Unix98 calls ruby itself makes:
# posix_openpt for the master, then grantpt and unlockpt, then the name
# of the slave device, which ruby opens by that name.
Machine.import "posix_openpt", [I32] => I32
Machine.import "grantpt", [I32] => I32
Machine.import "unlockpt", [I32] => I32
Machine.import "ptsname", [I32] => Ptr

# The master descriptor and the slave's name, or the negated errno.
sig [] => Value
machine def zr_pty_open
  master = posix_openpt(Machine.i32(PTY_OPEN_FLAGS))
  if master < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  if grantpt(master) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  if unlockpt(master) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  name = ptsname(master)
  if Machine.word(name) == 0
    return zr_fix(0 - zr_errno())
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(Machine.sword(master)))
  zr_ary_push(out, zr_cstr_str(name))
  out
end

# The terminal's name, and nil for a descriptor that is not one.
sig [Value] => Value
machine def zr_io_ttyname(fd)
  name = ttyname(Machine.i32(zr_fix2long(fd)))
  Machine.word(name) == 0 ? Machine.value(QNIL) : zr_cstr_str(name)
end

sig [Value] => Value
machine def zr_io_unlink(path)
  zr_io_status(unlink(RString.ptr(path)))
end

sig [Value, Value] => Value
machine def zr_io_rename(from, to)
  zr_io_status(rename(RString.ptr(from), RString.ptr(to)))
end

sig [Value, Value] => Value
machine def zr_io_mkdir(path, mode)
  zr_io_status(mkdir(RString.ptr(path), Machine.i32(zr_fix2long(mode))))
end

sig [Value] => Value
machine def zr_io_rmdir(path)
  zr_io_status(rmdir(RString.ptr(path)))
end

sig [Value] => Value
machine def zr_io_chdir(path)
  zr_io_status(chdir(RString.ptr(path)))
end

# The names in a directory, `.` and `..` among them, in the order the
# file system answers; or the negated errno.
sig [Value] => Value
machine def zr_io_dir_names(path)
  d = opendir(RString.ptr(path))
  if d == 0
    return zr_fix(0 - zr_errno())
  end
  out = zr_ary_new(8)
  e = readdir(d)
  while e != 0
    name = zr_os_dirent_name(e)
    zr_ary_push(out, zr_str_new(name, zr_cstr_len(name)))
    e = readdir(d)
  end
  closedir(d)
  out
end

# The same names through a descriptor, which is the only way to them
# when a program holds one and not a path.
sig [Value] => Value
machine def zr_io_dir_names_fd(fd)
  d = fdopendir(Machine.i32(zr_fix2long(fd)))
  if d == 0
    return zr_fix(0 - zr_errno())
  end
  out = zr_ary_new(8)
  e = readdir(d)
  while e != 0
    name = zr_os_dirent_name(e)
    zr_ary_push(out, zr_str_new(name, zr_cstr_len(name)))
    e = readdir(d)
  end
  closedir(d)
  out
end

sig [Value] => Value
machine def zr_io_fchdir(fd)
  zr_io_status(fchdir(Machine.i32(zr_fix2long(fd))))
end

Machine.import "chroot", [Ptr] => I32

sig [Value] => Value
machine def zr_io_chroot(path)
  zr_io_status(chroot(RString.ptr(path)))
end

# The message strerror gives for errno `n`.
sig [Value] => Value
machine def zr_io_strerror(n)
  p = strerror(Machine.i32(zr_fix2long(n)))
  zr_str_new(p, zr_cstr_len(p))
end

# The size in bytes of the file at `path`, or the negated errno.
sig [Value] => Value
machine def zr_io_file_size(path)
  buf = Machine.slot(STAT_LEN)
  if stat(RString.ptr(path), buf) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_fix(zr_os_stat_size(buf))
end

Machine.import "lstat", [Ptr, Ptr] => I32
Machine.import "realpath", [Ptr, Ptr] => Ptr
Machine.import "chmod", [Ptr, I32] => I32
Machine.import "fchmod", [I32, I32] => I32
Machine.import "chown", [Ptr, I32, I32] => I32
Machine.import "lchown", [Ptr, I32, I32] => I32
Machine.import "lchmod", [Ptr, I32] => I32
Machine.import "link", [Ptr, Ptr] => I32
Machine.import "symlink", [Ptr, Ptr] => I32
Machine.import "readlink", [Ptr, Ptr, Word] => Word
Machine.import "mkfifo", [Ptr, I32] => I32
Machine.import "truncate", [Ptr, Word] => I32
Machine.import "ftruncate", [I32, Word] => I32
Machine.import "umask", [I32] => I32
Machine.import "utimes", [Ptr, Ptr] => I32
Machine.import "lutimes", [Ptr, Ptr] => I32
Machine.import "flock", [I32, I32] => I32

# One path and one small number: chown's owner, truncate's length, and
# the rest. `which` picks the call; the answer is 0 or a negative
# errno.
sig [Value, Value, Value, Value] => Value
machine def zr_fs_call(which, path, a, b)
  w = zr_fix2long(which)
  r = Machine.i32(0)
  if w == 0
    r = chown(RString.ptr(path), Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
  elsif w == 1
    r = lchown(RString.ptr(path), Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
  elsif w == 2
    r = link(RString.ptr(path), RString.ptr(a))
  elsif w == 3
    r = symlink(RString.ptr(path), RString.ptr(a))
  elsif w == 4
    r = mkfifo(RString.ptr(path), Machine.i32(zr_fix2long(a)))
  elsif w == 5
    r = truncate(RString.ptr(path), zr_fix2long(a))
  elsif w == 6
    r = ftruncate(Machine.i32(zr_fix2long(a)), zr_fix2long(b))
  elsif w == 7
    r = fchmod(Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
  elsif w == 8
    r = flock(Machine.i32(zr_fix2long(a)), Machine.i32(zr_fix2long(b)))
  elsif w == 9
    r = lchmod(RString.ptr(path), Machine.i32(zr_fix2long(a)))
  end
  zr_io_status(r)
end

# The two microsecond timevals utimes(2) takes.
sig [Value, Value, Value] => Value
machine def zr_utimes_m(path, atime_us, mtime_us)
  times = Machine.slot(32)
  Machine.store64(times, 0, zr_fix2long(atime_us) / 1000000)
  Machine.store64(times, 8, zr_fix2long(atime_us) % 1000000)
  Machine.store64(times, 16, zr_fix2long(mtime_us) / 1000000)
  Machine.store64(times, 24, zr_fix2long(mtime_us) % 1000000)
  zr_io_status(utimes(RString.ptr(path), times))
end

# The same two timevals, for the link itself rather than for what it
# points at.
sig [Value, Value, Value] => Value
machine def zr_lutimes_m(path, atime_us, mtime_us)
  times = Machine.slot(32)
  Machine.store64(times, 0, zr_fix2long(atime_us) / 1000000)
  Machine.store64(times, 8, zr_fix2long(atime_us) % 1000000)
  Machine.store64(times, 16, zr_fix2long(mtime_us) / 1000000)
  Machine.store64(times, 24, zr_fix2long(mtime_us) % 1000000)
  zr_io_status(lutimes(RString.ptr(path), times))
end

# umask(2): the mask that was in force, and the new one when `mask` is
# not nil.
sig [Value] => Value
machine def zr_umask_m(mask)
  if mask == QNIL
    was = umask(Machine.i32(0))
    umask(was)
    return zr_fix(Machine.word(was))
  end
  zr_fix(Machine.word(umask(Machine.i32(zr_fix2long(mask)))))
end

# readlink(2): where the symlink points, or a negative errno.
sig [Value] => Value
machine def zr_readlink_m(path)
  buf = zr_xmalloc(4096)
  n = readlink(RString.ptr(path), buf, 4095)
  if n < 0
    free(buf)
    return zr_fix(0 - zr_errno())
  end
  s = zr_str_new(buf, n)
  free(buf)
  s
end

# stat(2) (or lstat when `follow` is false) as fixnums in an Array:
# dev, ino, mode, nlink, uid, gid, rdev, size, blksize, blocks, then
# atime, mtime and ctime as seconds and nanoseconds; a negative errno
# on failure.
sig [Value, Value] => Value
machine def zr_stat_m(path, follow)
  buf = Machine.slot(STAT_LEN)
  r = follow == QFALSE ? lstat(RString.ptr(path), buf) : stat(RString.ptr(path), buf)
  if r < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_os_stat_rows(buf)
end

# fstat(2): the same rows for a descriptor, which is the only way to
# them when the stream was opened from one and has no path.
sig [Value] => Value
machine def zr_fstat_m(fd)
  buf = Machine.slot(STAT_LEN)
  if fstat(Machine.i32(zr_fix2long(fd)), buf) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_os_stat_rows(buf)
end

# realpath(3): the resolved path, or a negative errno.
sig [Value] => Value
machine def zr_realpath_m(path)
  p = realpath(RString.ptr(path), 0)
  if p == 0
    return zr_fix(0 - zr_errno())
  end
  s = zr_str_new(p, zr_cstr_len(p))
  free(p)
  s
end

sig [Value, Value] => Value
machine def zr_chmod_m(path, mode)
  if chmod(RString.ptr(path), Machine.i32(zr_fix2long(mode))) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_fix(0)
end

# access(2): whether the process may use the file as `mode` asks (4
# read, 2 write, 1 execute).
sig [Value, Value] => Value
machine def zr_path_access(path, mode)
  zr_bool(Machine.word(access(RString.ptr(path), Machine.i32(zr_fix2long(mode)))) == 0)
end

# The bits `events` carries: IO::READABLE, IO::PRIORITY, IO::WRITABLE.
WAIT_READABLE = 1
WAIT_PRIORITY = 2
WAIT_WRITABLE = 4

# One descriptor's wait: the events that came ready, 0 when the time
# ran out, or the negated errno. A negative time waits for good, and a
# signal that cuts the wait short runs its handlers first.
sig [Value, Value, Value] => Value
machine def zr_io_wait(fd, events, milliseconds)
  r = zr_os_wait_fd(fd, events, milliseconds)
  while r == zr_fix(0 - EINTR)
    if zr_trap_check() == QUNDEF
      return Machine.value(QUNDEF)
    end
    r = zr_os_wait_fd(fd, events, milliseconds)
  end
  r
end
