# darwin's half of the descriptor calls: where errno lives, the calls
# that take a variadic argument, and the layouts of struct dirent and
# struct stat.
Machine.import "__error", [] => Ptr
Machine.import "open", [Ptr, I32] => I32
Machine.import "dlsym", [Ptr, Ptr] => Ptr

sig [] => Word
machine def zr_os_errno
  Machine.word(Machine.load32(__error(), 0))
end

sig [Word] => Void
machine def zr_os_set_errno(n)
  Machine.store32(__error(), 0, Machine.i32(n))
end

EINTR = 4
EBADF = 9

# `fcntl` takes the argument of F_SETFL and F_SETFD variadically, and
# this platform passes a variadic argument on the stack, which this
# runtime makes no call for; `__fcntl` is the fixed-arity call that
# fcntl's own wrapper makes once it has read that argument.
Machine.import "__fcntl", [I32, I32, Word] => I32

sig [I32, I32, Word] => I32
machine def zr_os_fcntl(fd, command, argument)
  __fcntl(fd, command, argument)
end

# `ioctl` names its third argument variadically, so a fixed-arity call
# never reaches it: an ioctl that reads its argument answers EFAULT.
# `__ioctl` is the fixed-arity call that ioctl's own wrapper makes once
# it has read that argument.
Machine.import "__ioctl", [I32, Word, Ptr] => I32

sig [I32, Word, Ptr] => I32
machine def zr_os_ioctl(fd, request, argument)
  __ioctl(fd, request, argument)
end

# open(2) with two arguments, which is the whole call unless O_CREAT is
# set: the mode a creation takes is a variadic argument, and this
# platform passes those on the stack. A creation goes through fopen and
# then fchmod, which names the permissions exactly.
sig [Ptr, I32] => I32
machine def zr_os_open(path, flags)
  open(path, flags)
end

# realpath(3): a fresh buffer the caller frees, or 0.
sig [Ptr] => Ptr
machine def zr_os_realpath(path)
  realpath(path, 0)
end

O_NONBLOCK = 4
# Every flag but O_NONBLOCK, which takes the flag away again.
O_NONBLOCK_OFF = 4294967291
# Every descriptor ruby opens closes itself across an exec, which
# rb_sysopen asks for with O_CLOEXEC on the call itself.
O_CLOEXEC = 16777216
# O_RDWR | O_NOCTTY | O_CLOEXEC: the pair is not this task's terminal.
PTY_OPEN_FLAGS = 16_908_290

TIOCGWINSZ = 1074295912
TIOCSWINSZ = 2148037735
# struct termios: four flag words, twenty control characters, and then
# the two speeds. The bytes cross into ruby as they stand, because the
# flags a mode changes are ruby's to name.
TERMIOS_LEN = 72

# A directory entry's name: darwin's struct dirent has an 8-byte inode,
# an 8-byte seek offset, the record and name lengths as two shorts, and
# the type byte before it.
sig [Ptr] => Ptr
machine def zr_os_dirent_name(entry)
  entry + 21
end

# darwin's 64-bit-inode struct stat.
STAT_LEN = 160

# stat(2) as fixnums in an Array: dev, ino, mode, nlink, uid, gid, rdev,
# size, blksize, blocks, then atime, mtime and ctime as seconds and
# nanoseconds.
sig [Ptr] => Value
machine def zr_os_stat_rows(buf)
  out = zr_ary_new(16)
  zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(buf, 0))))
  zr_ary_push(out, zr_fix(Machine.load64(buf, 8)))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(buf, 4)) & 65535))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(buf, 4)) >> 16))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(buf, 16))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(buf, 20))))
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
  out
end

# st_size.
sig [Ptr] => Word
machine def zr_os_stat_size(buf)
  Machine.load64(buf, 96)
end

# st_mode, 16 bits at offset 4.
sig [Ptr] => Word
machine def zr_os_stat_mode(buf)
  Machine.word(Machine.load32(buf, 4)) & 65535
end

# Darwin's select(2) with no FD_SETSIZE limit, the one CRuby calls (it
# builds with _DARWIN_UNLIMITED_SELECT). Plain `select` refuses more
# than 1024 descriptors, and poll(2) here reports a pipe with data as
# priority-readable, so neither gives CRuby's answer.
Machine.sig :select_call, [I32, Ptr, Ptr, Ptr, Ptr] => I32

sig [] => Ptr
machine def zr_select_fn
  cell = Machine.static(:select_fn, 8)
  if Machine.load64(cell, 0) == 0
    Machine.store64(cell, 0, Machine.word(dlsym(Machine.ptr(RTLD_DEFAULT), Machine.bytes("select$DARWIN_EXTSN\0"))))
  end
  Machine.ptr(Machine.load64(cell, 0))
end

# select(2) on every descriptor of `fds` at once, each for the events
# its row of `events` names, which is how the thread scheduler waits for
# the threads parked on a descriptor: an Array of the events that came
# ready for each row, or the negated errno. A negative time waits for
# good.
sig [Value, Value, Value] => Value
machine def zr_os_wait_fds(fds, events, milliseconds)
  count = RArray.len(fds)
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
  memset(sets, Machine.i32(0), span * 3)
  i = 0
  while i < count
    n = zr_fix2long(zr_ary_at(fds, i))
    want = zr_fix2long(zr_ary_at(events, i))
    word = (n / 32) * 4
    bit = 1 << (n % 32)
    if (want & WAIT_READABLE) != 0
      Machine.store32(sets + word, 0, Machine.i32(Machine.word(Machine.load32(sets + word, 0)) | bit))
    end
    if (want & WAIT_WRITABLE) != 0
      Machine.store32(sets + span + word, 0, Machine.i32(Machine.word(Machine.load32(sets + span + word, 0)) | bit))
    end
    if (want & WAIT_PRIORITY) != 0
      Machine.store32(sets + (span * 2) + word, 0, Machine.i32(Machine.word(Machine.load32(sets + (span * 2) + word, 0)) | bit))
    end
    i += 1
  end
  tv = Machine.slot(16)
  ms = zr_fix2long(milliseconds)
  Machine.store64(tv, 0, ms / 1000)
  Machine.store32(tv, 8, Machine.i32((ms % 1000) * 1000))
  Machine.store32(tv, 12, Machine.i32(0))
  r = Machine.call(:select_call, zr_select_fn(), Machine.i32(top + 1), sets, sets + span, sets + (span * 2), ms < 0 ? 0 : tv)
  if r < Machine.i32(0)
    errno = zr_errno()
    free(sets)
    return zr_fix(0 - errno)
  end
  out = zr_ary_new(count)
  i = 0
  while i < count
    n = zr_fix2long(zr_ary_at(fds, i))
    want = zr_fix2long(zr_ary_at(events, i))
    word = (n / 32) * 4
    bit = 1 << (n % 32)
    ready = 0
    if (Machine.word(Machine.load32(sets + word, 0)) & bit) != 0
      ready = ready | WAIT_READABLE
    end
    if (Machine.word(Machine.load32(sets + span + word, 0)) & bit) != 0
      ready = ready | WAIT_WRITABLE
    end
    if (Machine.word(Machine.load32(sets + (span * 2) + word, 0)) & bit) != 0
      ready = ready | WAIT_PRIORITY
    end
    zr_ary_push(out, zr_fix(ready & want))
    i += 1
  end
  free(sets)
  out
end

# select(2) on one descriptor, which is what ruby itself waits with on
# this platform: the events that came ready, 0 when the time ran out, or
# the negated errno. A negative time waits for good. Each of the three
# sets holds as many bits as the descriptor needs, so any descriptor
# number fits.
sig [Value, Value, Value] => Value
machine def zr_os_wait_fd(fd, events, milliseconds)
  n = zr_fix2long(fd)
  if n < 0
    return zr_fix(0 - EBADF)
  end
  want = zr_fix2long(events)
  span = ((n / 32) + 1) * 4
  sets = zr_xmalloc(span * 3)
  memset(sets, Machine.i32(0), span * 3)
  word = (n / 32) * 4
  bit = 1 << (n % 32)
  if (want & WAIT_READABLE) != 0
    Machine.store32(sets + word, 0, Machine.i32(bit))
  end
  if (want & WAIT_WRITABLE) != 0
    Machine.store32(sets + span + word, 0, Machine.i32(bit))
  end
  if (want & WAIT_PRIORITY) != 0
    Machine.store32(sets + (span * 2) + word, 0, Machine.i32(bit))
  end
  tv = Machine.slot(16)
  ms = zr_fix2long(milliseconds)
  Machine.store64(tv, 0, ms / 1000)
  Machine.store32(tv, 8, Machine.i32((ms % 1000) * 1000))
  Machine.store32(tv, 12, Machine.i32(0))
  r = Machine.call(:select_call, zr_select_fn(), Machine.i32(n + 1), sets, sets + span, sets + (span * 2), ms < 0 ? 0 : tv)
  if r < Machine.i32(0)
    errno = zr_errno()
    free(sets)
    return zr_fix(0 - errno)
  end
  ready = 0
  if (Machine.word(Machine.load32(sets + word, 0)) & bit) != 0
    ready = ready | WAIT_READABLE
  end
  if (Machine.word(Machine.load32(sets + span + word, 0)) & bit) != 0
    ready = ready | WAIT_WRITABLE
  end
  if (Machine.word(Machine.load32(sets + (span * 2) + word, 0)) & bit) != 0
    ready = ready | WAIT_PRIORITY
  end
  free(sets)
  zr_fix(ready)
end
