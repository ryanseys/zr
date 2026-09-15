# WASI's half of the descriptor calls: errno in a word of the module's
# own, open(2) over path_open, WASI's filestat as the stat buffer, and
# the libc descriptor and path calls the portable kernel imports, each
# answered as wasi-libc answers it.

sig [] => Word
machine def zr_os_errno
  Machine.word(Machine.load32(Machine.static(:errno, 8), 0))
end

sig [Word] => Void
machine def zr_os_set_errno(n)
  Machine.store32(Machine.static(:errno, 8), 0, Machine.i32(n))
end

EINTR = 27
EBADF = 8

# wasi-libc's open flags: the file status flags are WASI's fdflags, the
# creation flags WASI's oflags shifted up 12 bits, and the access modes
# bits of their own high up.
O_APPEND = 1
O_NONBLOCK = 4
O_NONBLOCK_OFF = 4294967291
O_FDFLAGS = 31
O_NOFOLLOW = 16777216
O_RDONLY = 67108864
O_WRONLY = 268435456
# wasi-libc has no exec, so nothing closes itself across one.
O_CLOEXEC = 0
PTY_OPEN_FLAGS = 335544320

# musl's ioctl numbers, which wasi-libc keeps though nothing answers them.
TIOCGWINSZ = 21523
TIOCSWINSZ = 21524
TERMIOS_LEN = 60

F_GETFD = 1

# The rights path_open grants by access mode, as wasi-libc asks for
# them: every right but reading and writing, then the reads for
# O_RDONLY and the writes for O_WRONLY.
RIGHTS_READ = 16386
RIGHTS_WRITE = 4194625
RIGHTS_OTHER = 1073741823 - RIGHTS_READ - RIGHTS_WRITE
FDSTAT_LEN = 24

# open(2) over path_open, under the preopened directory the path is in.
sig [Ptr, I32] => I32
machine def zr_os_open(path, flags)
  where = Machine.slot(16)
  dir = zr_wasi_resolve(path, where)
  if dir < Machine.i32(0)
    return dir
  end
  f = Machine.word(flags)
  rights = RIGHTS_OTHER
  if (f & O_RDONLY) != 0
    rights = rights | RIGHTS_READ
  end
  if (f & O_WRONLY) != 0
    rights = rights | RIGHTS_WRITE
  end
  follow = (f & O_NOFOLLOW) != 0 ? 0 : 1
  stat = Machine.slot(FDSTAT_LEN)
  fd_fdstat_get(dir, zr_wasi_addr(stat))
  out = Machine.slot(8)
  r = path_open(dir, Machine.i32(follow), zr_wasi_rest(where), zr_wasi_rest_len(where), Machine.i32((f >> 12) & 15),
                rights & Machine.load64(stat, 16), Machine.load64(stat, 16), Machine.i32(f & O_FDFLAGS), zr_wasi_addr(out))
  if zr_wasi_status(r) < Machine.i32(0)
    return Machine.i32(0 - 1)
  end
  Machine.load32(out, 0)
end

# F_SETFL sets the fdflags; F_GETFL reads them back with the access
# mode the rights say; F_SETFD and F_GETFD have no close-on-exec to set
# or read; anything else is not a command WASI has.
sig [I32, I32, Word] => I32
machine def zr_os_fcntl(fd, command, argument)
  if command == Machine.i32(F_SETFL)
    return zr_wasi_status(fd_fdstat_set_flags(fd, Machine.i32(argument & O_FDFLAGS)))
  end
  if command == Machine.i32(F_SETFD) || command == Machine.i32(F_GETFD)
    return Machine.i32(0)
  end
  if command != Machine.i32(F_GETFL)
    return zr_wasi_fail(WASI_EINVAL)
  end
  stat = Machine.slot(FDSTAT_LEN)
  if zr_wasi_status(fd_fdstat_get(fd, zr_wasi_addr(stat))) < Machine.i32(0)
    return Machine.i32(0 - 1)
  end
  rights = Machine.load64(stat, 8)
  flags = Machine.word(Machine.load32(stat, 0)) >> 16
  if (rights & RIGHTS_READ) != 0
    flags = flags | O_RDONLY
  end
  if (rights & 64) != 0
    flags = flags | O_WRONLY
  end
  Machine.i32(flags)
end

# No descriptor here is a terminal or a device a request could reach.
sig [I32, Word, Ptr] => I32
machine def zr_os_ioctl(fd, request, argument)
  zr_wasi_fail(WASI_ENOTTY)
end

# A terminal is a character device, which is filetype 2.
sig [I32] => I32
machine def isatty(fd)
  stat = Machine.slot(FDSTAT_LEN)
  if zr_wasi_status(fd_fdstat_get(fd, zr_wasi_addr(stat))) < Machine.i32(0)
    return Machine.i32(0)
  end
  if Machine.load8(stat, 0) != Machine.i8(2)
    zr_os_set_errno(WASI_ENOTTY)
    return Machine.i32(0)
  end
  Machine.i32(1)
end

sig [I32, Ptr, Word] => Word
machine def write(fd, buf, len)
  iov = Machine.slot(16)
  if zr_wasi_status(fd_write(fd, zr_wasi_iovec(iov, buf, len), Machine.i32(1), zr_wasi_addr(iov + 8))) < Machine.i32(0)
    return 0 - 1
  end
  Machine.word(Machine.load32(iov, 8))
end

sig [I32, Ptr, Word] => Word
machine def read(fd, buf, len)
  iov = Machine.slot(16)
  if zr_wasi_status(fd_read(fd, zr_wasi_iovec(iov, buf, len), Machine.i32(1), zr_wasi_addr(iov + 8))) < Machine.i32(0)
    return 0 - 1
  end
  Machine.word(Machine.load32(iov, 8))
end

sig [I32, Ptr, Word, Word] => Word
machine def pread(fd, buf, len, offset)
  iov = Machine.slot(16)
  if zr_wasi_status(fd_pread(fd, zr_wasi_iovec(iov, buf, len), Machine.i32(1), offset, zr_wasi_addr(iov + 8))) < Machine.i32(0)
    return 0 - 1
  end
  Machine.word(Machine.load32(iov, 8))
end

sig [I32, Ptr, Word, Word] => Word
machine def pwrite(fd, buf, len, offset)
  iov = Machine.slot(16)
  if zr_wasi_status(fd_pwrite(fd, zr_wasi_iovec(iov, buf, len), Machine.i32(1), offset, zr_wasi_addr(iov + 8))) < Machine.i32(0)
    return 0 - 1
  end
  Machine.word(Machine.load32(iov, 8))
end

sig [I32] => I32
machine def close(fd)
  zr_wasi_status(fd_close(fd))
end

sig [I32] => I32
machine def fsync(fd)
  zr_wasi_status(fd_sync(fd))
end

# SEEK_SET, SEEK_CUR and SEEK_END are WASI's whence numbers as well.
sig [I32, Word, I32] => Word
machine def lseek(fd, offset, whence)
  out = Machine.slot(8)
  if zr_wasi_status(fd_seek(fd, offset, whence, zr_wasi_addr(out))) < Machine.i32(0)
    return 0 - 1
  end
  Machine.load64(out, 0)
end

sig [I32, Word] => I32
machine def ftruncate(fd, size)
  zr_wasi_status(fd_filestat_set_size(fd, size))
end

# WASI keeps no permission bits, so there are none to change.
sig [I32, I32] => I32
machine def fchmod(fd, mode)
  Machine.i32(0)
end

# The mask a module has no use for, as a fresh shell would set it.
sig [I32] => I32
machine def umask(mask)
  Machine.i32(18)
end

# A stat buffer is WASI's own filestat: the device at 0, the inode at 8,
# the file type byte at 16, the link count at 24, the size at 32, and
# the access, modification and change times at 40, 48 and 56 in
# nanoseconds.
STAT_LEN = 64

# One call on a path's filestat, following a last symlink or not.
sig [Ptr, Ptr, I32] => I32
machine def zr_wasi_path_stat(path, buf, follow)
  where = Machine.slot(16)
  dir = zr_wasi_resolve(path, where)
  if dir < Machine.i32(0)
    return dir
  end
  zr_wasi_status(path_filestat_get(dir, follow, zr_wasi_rest(where), zr_wasi_rest_len(where), zr_wasi_addr(buf)))
end

sig [Ptr, Ptr] => I32
machine def stat(path, buf)
  zr_wasi_path_stat(path, buf, Machine.i32(1))
end

sig [Ptr, Ptr] => I32
machine def lstat(path, buf)
  zr_wasi_path_stat(path, buf, Machine.i32(0))
end

sig [I32, Ptr] => I32
machine def fstat(fd, buf)
  zr_wasi_status(fd_filestat_get(fd, zr_wasi_addr(buf)))
end

# Whether the path is there: WASI answers no question of permission.
sig [Ptr, I32] => I32
machine def access(path, mode)
  buf = Machine.slot(STAT_LEN)
  stat(path, buf)
end

# st_mode's type bits for WASI's file type, with the permission bits a
# fresh file of that type usually carries, since WASI keeps none.
sig [Ptr] => Word
machine def zr_os_stat_mode(buf)
  type = Machine.word(Machine.load8(buf, 16))
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

sig [Ptr] => Word
machine def zr_os_stat_size(buf)
  Machine.load64(buf, 32)
end

# The rows zr_stat_m answers: an owner is root and a device number is
# zero, since a module is told neither, and a block is 512 bytes.
sig [Ptr] => Value
machine def zr_os_stat_rows(buf)
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

# The calls that name one path: its directory's descriptor and the
# rest go to the host.
sig [Ptr] => I32
machine def unlink(path)
  where = Machine.slot(16)
  dir = zr_wasi_resolve(path, where)
  if dir < Machine.i32(0)
    return dir
  end
  zr_wasi_status(path_unlink_file(dir, zr_wasi_rest(where), zr_wasi_rest_len(where)))
end

sig [Ptr] => I32
machine def rmdir(path)
  where = Machine.slot(16)
  dir = zr_wasi_resolve(path, where)
  if dir < Machine.i32(0)
    return dir
  end
  zr_wasi_status(path_remove_directory(dir, zr_wasi_rest(where), zr_wasi_rest_len(where)))
end

sig [Ptr, I32] => I32
machine def mkdir(path, mode)
  where = Machine.slot(16)
  dir = zr_wasi_resolve(path, where)
  if dir < Machine.i32(0)
    return dir
  end
  zr_wasi_status(path_create_directory(dir, zr_wasi_rest(where), zr_wasi_rest_len(where)))
end

sig [Ptr, Ptr, Word] => Word
machine def readlink(path, buf, len)
  where = Machine.slot(16)
  dir = zr_wasi_resolve(path, where)
  if dir < Machine.i32(0)
    return 0 - 1
  end
  used = Machine.slot(8)
  r = path_readlink(dir, zr_wasi_rest(where), zr_wasi_rest_len(where), zr_wasi_addr(buf), Machine.i32(len), zr_wasi_addr(used))
  if zr_wasi_status(r) < Machine.i32(0)
    return 0 - 1
  end
  Machine.word(Machine.load32(used, 0))
end

# The calls that name two paths.
sig [Ptr, Ptr] => I32
machine def rename(from, to)
  a = Machine.slot(16)
  b = Machine.slot(16)
  da = zr_wasi_resolve(from, a)
  db = zr_wasi_resolve(to, b)
  if da < Machine.i32(0) || db < Machine.i32(0)
    return Machine.i32(0 - 1)
  end
  zr_wasi_status(path_rename(da, zr_wasi_rest(a), zr_wasi_rest_len(a), db, zr_wasi_rest(b), zr_wasi_rest_len(b)))
end

sig [Ptr, Ptr] => I32
machine def link(from, to)
  a = Machine.slot(16)
  b = Machine.slot(16)
  da = zr_wasi_resolve(from, a)
  db = zr_wasi_resolve(to, b)
  if da < Machine.i32(0) || db < Machine.i32(0)
    return Machine.i32(0 - 1)
  end
  zr_wasi_status(path_link(da, Machine.i32(0), zr_wasi_rest(a), zr_wasi_rest_len(a), db, zr_wasi_rest(b), zr_wasi_rest_len(b)))
end

# A symlink's target is text the host stores as given.
sig [Ptr, Ptr] => I32
machine def symlink(target, path)
  where = Machine.slot(16)
  dir = zr_wasi_resolve(path, where)
  if dir < Machine.i32(0)
    return dir
  end
  zr_wasi_status(path_symlink(zr_wasi_addr(target), Machine.i32(zr_cstr_len(target)), dir, zr_wasi_rest(where), zr_wasi_rest_len(where)))
end

# A stream is only its descriptor, in a word of its own: fopen opens
# with the flags its mode names, as File.open_flags reads a mode.
O_CREAT = 4096
O_EXCL = 16384
O_TRUNC = 32768

sig [Ptr, Ptr] => Ptr
machine def fopen(path, mode)
  first = Machine.word(Machine.load8(mode, 0))
  flags = first == 114 ? O_RDONLY : O_WRONLY
  if first == 119
    flags = flags | O_CREAT | O_TRUNC
  elsif first == 97
    flags = flags | O_CREAT | O_APPEND
  end
  at = 1
  while Machine.load8(mode + at, 0) != Machine.i8(0)
    c = Machine.word(Machine.load8(mode + at, 0))
    if c == 43
      flags = flags | O_RDONLY | O_WRONLY
    elsif c == 120
      flags = flags | O_EXCL
    end
    at += 1
  end
  fd = zr_os_open(path, Machine.i32(flags))
  if fd < Machine.i32(0)
    return Machine.ptr(0)
  end
  stream = zr_xmalloc(8)
  Machine.store64(stream, 0, Machine.word(fd))
  stream
end

sig [Ptr] => I32
machine def fileno(stream)
  Machine.load32(stream, 0)
end

sig [Ptr] => I32
machine def fclose(stream)
  r = close(fileno(stream))
  free(stream)
  r
end

# A directory stream: its descriptor, the cookie of the next entry, and
# the one entry fd_readdir last answered, its name ended with a NUL.
DIR_BUFFER = 4096

sig [I32] => Ptr
machine def fdopendir(fd)
  d = zr_xmalloc(16 + DIR_BUFFER + 1)
  Machine.store64(d, 0, Machine.word(fd))
  Machine.store64(d, 8, 0)
  d
end

sig [Ptr] => Ptr
machine def opendir(path)
  fd = zr_os_open(path, Machine.i32(O_RDONLY | (2 << 12)))
  if fd < Machine.i32(0)
    return Machine.ptr(0)
  end
  fdopendir(fd)
end

# The next entry, read one at a time from the cookie on, or 0 at the
# end. A dirent is 24 bytes and then the name.
sig [Ptr] => Ptr
machine def readdir(d)
  buf = d + 16
  used = Machine.slot(8)
  r = fd_readdir(Machine.load32(d, 0), zr_wasi_addr(buf), Machine.i32(DIR_BUFFER), Machine.load64(d, 8), zr_wasi_addr(used))
  if zr_wasi_status(r) < Machine.i32(0) || Machine.word(Machine.load32(used, 0)) < 24
    return Machine.ptr(0)
  end
  len = Machine.word(Machine.load32(buf, 16))
  Machine.store64(d, 8, Machine.load64(buf, 0))
  Machine.store8(buf + 24 + len, 0, Machine.i8(0))
  buf
end

sig [Ptr] => Ptr
machine def zr_os_dirent_name(entry)
  entry + 24
end

sig [Ptr] => I32
machine def closedir(d)
  r = close(Machine.load32(d, 0))
  free(d)
  r
end

# poll_oneoff on one descriptor, and on the clock when the wait has an
# end: the events that came ready, 0 when the time ran out, or the
# negated errno. A subscription is 48 bytes and an event 32.
sig [Value, Value, Value] => Value
machine def zr_os_wait_fd(fd, events, milliseconds)
  n = zr_fix2long(fd)
  if n < 0
    return zr_fix(0 - EBADF)
  end
  want = zr_fix2long(events)
  ms = zr_fix2long(milliseconds)
  subs = Machine.slot(144)
  memset(subs, Machine.i32(0), 144)
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
  if zr_wasi_status(poll_oneoff(zr_wasi_addr(subs), zr_wasi_addr(got), Machine.i32(count), zr_wasi_addr(nevents))) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  ready = 0
  i = 0
  while i < Machine.word(Machine.load32(nevents, 0))
    e = got + (i * 32)
    kind = Machine.word(Machine.load8(e, 10))
    if (Machine.word(Machine.load32(e, 8)) & 65535) != 0 && kind != 0
      return zr_fix(0 - (Machine.word(Machine.load32(e, 8)) & 65535))
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

# The messages wasi-libc's strerror gives, one a line in WASI's errno
# order.
sig [I32] => Ptr
machine def strerror(n)
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
  line = Machine.word(n)
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
  # The line becomes the C string: a copy, ended where its line ends.
  len = 0
  while Machine.load8(at + len, 0) != Machine.i8(10)
    len += 1
  end
  out = Machine.static(:strerror, 64)
  zr_memcpy(out, at, len)
  Machine.store8(out + len, 0, Machine.i8(0))
  out
end

# A module is given no working directory: the root is the one every
# preopened directory stands under.
sig [Ptr, Word] => Ptr
machine def getcwd(buf, size)
  if size < 2
    zr_os_set_errno(68)
    return Machine.ptr(0)
  end
  Machine.store8(buf, 0, Machine.i8(47))
  Machine.store8(buf, 1, Machine.i8(0))
  buf
end
