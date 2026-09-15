# Linux's half of the descriptor calls, as musl answers them: where errno
# lives, the calls that take a variadic argument, and the layouts of
# struct dirent and struct stat. AAPCS64 on Linux passes a variadic
# argument in a register as it passes a fixed one, so fcntl, ioctl and
# open take their last argument as a fixed third one.
Machine.import "__errno_location", [] => Ptr
Machine.import "fcntl", [I32, I32, Word] => I32
Machine.import "ioctl", [I32, Word, Ptr] => I32
Machine.import "open", [Ptr, I32, I32] => I32
Machine.import "poll", [Ptr, Word, I32] => I32

sig [] => Word
machine def zr_os_errno
  Machine.word(Machine.load32(__errno_location(), 0))
end

sig [Word] => Void
machine def zr_os_set_errno(n)
  Machine.store32(__errno_location(), 0, Machine.i32(n))
end

EINTR = 4
EBADF = 9

sig [I32, I32, Word] => I32
machine def zr_os_fcntl(fd, command, argument)
  fcntl(fd, command, argument)
end

sig [I32, Word, Ptr] => I32
machine def zr_os_ioctl(fd, request, argument)
  ioctl(fd, request, argument)
end

# A creation takes the mode fopen gives, 0666 less the umask; ruby names
# the permissions exactly afterwards with fchmod.
OPEN_MODE = 438

sig [Ptr, I32] => I32
machine def zr_os_open(path, flags)
  open(path, flags, Machine.i32(OPEN_MODE))
end

O_NONBLOCK = 2048
# Every flag but O_NONBLOCK, which takes the flag away again.
O_NONBLOCK_OFF = 4294965247
O_CLOEXEC = 524288
# O_RDWR | O_NOCTTY | O_CLOEXEC: the pair is not this task's terminal.
PTY_OPEN_FLAGS = 524546

TIOCGWINSZ = 21523
TIOCSWINSZ = 21524
# struct termios: four flag ints, the line discipline, 32 control
# characters, and then the two speeds.
TERMIOS_LEN = 60

# A directory entry's name: musl's struct dirent has an 8-byte inode, an
# 8-byte seek offset, the record length as a short, and the type byte
# before it.
sig [Ptr] => Ptr
machine def zr_os_dirent_name(entry)
  entry + 19
end

# The generic struct stat that aarch64 Linux has.
STAT_LEN = 128

# stat(2) as fixnums in an Array: dev, ino, mode, nlink, uid, gid, rdev,
# size, blksize, blocks, then atime, mtime and ctime as seconds and
# nanoseconds.
sig [Ptr] => Value
machine def zr_os_stat_rows(buf)
  out = zr_ary_new(16)
  zr_ary_push(out, zr_fix(Machine.load64(buf, 0)))
  zr_ary_push(out, zr_fix(Machine.load64(buf, 8)))
  zr_ary_push(out, zr_fix(zr_os_stat_mode(buf)))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(buf, 20))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(buf, 24))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(buf, 28))))
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
sig [Ptr] => Word
machine def zr_os_stat_size(buf)
  Machine.load64(buf, 48)
end

# st_mode, 32 bits at offset 16.
sig [Ptr] => Word
machine def zr_os_stat_mode(buf)
  Machine.word(Machine.load32(buf, 16))
end

# poll(2)'s answers as thread.c reads them back: the read set (POLLIN,
# POLLRDNORM, POLLRDBAND, POLLHUP, POLLERR), the write set (POLLOUT,
# POLLWRNORM, POLLWRBAND, POLLERR), the priority set, and the answer that
# the descriptor is not open.
POLLIN_SET = 217
POLLOUT_SET = 780
POLLEX_SET = 2
POLLNVAL = 32

# poll(2) on one descriptor, which is what ruby itself waits with on
# Linux: the events that came ready, 0 when the time ran out, or the
# negated errno. The events ruby asks for are poll's own bits, and a
# struct pollfd is the descriptor, then the events and the answer as two
# shorts. A negative time waits for good.
sig [Value, Value, Value] => Value
machine def zr_os_wait_fd(fd, events, milliseconds)
  n = zr_fix2long(fd)
  if n < 0
    return zr_fix(0 - EBADF)
  end
  want = zr_fix2long(events)
  ms = zr_fix2long(milliseconds)
  entry = Machine.slot(8)
  Machine.store32(entry, 0, Machine.i32(n))
  Machine.store32(entry, 4, Machine.i32(want))
  r = poll(entry, 1, Machine.i32(ms < 0 ? 0 - 1 : ms))
  if r < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  if r == Machine.i32(0)
    return zr_fix(0)
  end
  got = Machine.word(Machine.load32(entry, 4)) >> 16
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
