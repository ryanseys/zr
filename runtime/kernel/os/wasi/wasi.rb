# WASI preview 1: the calls a wasm32-wasi module makes of its host, and
# what the rest of this layer shares over them: errno, iovecs, and the
# preopened directories a path resolves under. An address crosses as
# its low 32 bits, which is the whole of a wasm32 address.
Machine.import "args_sizes_get", [I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "args_get", [I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "environ_sizes_get", [I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "environ_get", [I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "clock_res_get", [I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "clock_time_get", [I32, Word, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_close", [I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_fdstat_get", [I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_fdstat_set_flags", [I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_filestat_get", [I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_filestat_set_size", [I32, Word] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_pread", [I32, I32, I32, Word, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_prestat_get", [I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_prestat_dir_name", [I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_pwrite", [I32, I32, I32, Word, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_read", [I32, I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_readdir", [I32, I32, I32, Word, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_seek", [I32, Word, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_sync", [I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "fd_write", [I32, I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "path_create_directory", [I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "path_filestat_get", [I32, I32, I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "path_link", [I32, I32, I32, I32, I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "path_open", [I32, I32, I32, I32, I32, Word, Word, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "path_readlink", [I32, I32, I32, I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "path_remove_directory", [I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "path_rename", [I32, I32, I32, I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "path_symlink", [I32, I32, I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "path_unlink_file", [I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "poll_oneoff", [I32, I32, I32, I32] => I32, from: "wasi_snapshot_preview1"
Machine.import "proc_exit", [I32] => Void, from: "wasi_snapshot_preview1"
Machine.import "random_get", [I32, I32] => I32, from: "wasi_snapshot_preview1"

# WASI's errno numbers, which wasi-libc gives its E names.
WASI_EBADF = 8
WASI_EINVAL = 28
WASI_ENOENT = 44
WASI_ENOSYS = 52
WASI_ENOTTY = 59

# The low 32 bits of an address, as a call to the host takes it.
sig [Ptr] => I32
machine def zr_wasi_addr(p)
  Machine.i32(Machine.word(p))
end

# A WASI call's errno as libc answers it: 0, or -1 with errno set.
sig [I32] => I32
machine def zr_wasi_status(errno)
  if errno == Machine.i32(0)
    return Machine.i32(0)
  end
  zr_os_set_errno(Machine.word(errno))
  Machine.i32(0 - 1)
end

# -1 with errno set to `n`, for a call that fails before the host sees it.
sig [Word] => I32
machine def zr_wasi_fail(n)
  zr_os_set_errno(n)
  Machine.i32(0 - 1)
end

# The same failure where the answer is a count.
sig [Word] => Word
machine def zr_wasi_fail_count(n)
  zr_os_set_errno(n)
  0 - 1
end

# One iovec of `len` bytes at `buf`, in a slot of the caller's: the
# host reads two 32-bit words.
sig [Ptr, Ptr, Word] => I32
machine def zr_wasi_iovec(iov, buf, len)
  Machine.store32(iov, 0, zr_wasi_addr(buf))
  Machine.store32(iov, 4, Machine.i32(len))
  zr_wasi_addr(iov)
end

# The preopened directories, found once: a row of (descriptor, name
# address, name length) words per directory, a zero descriptor ending
# the rows. A name is kept as the host gave it, less any leading `/`
# and `./`, so that `.` and `/` both stand for every path.
PREOPENS = 32

sig [] => Ptr
machine def zr_wasi_preopens
  cell = Machine.static(:wasi_preopens, 8)
  if Machine.load64(cell, 0) != 0
    return Machine.ptr(Machine.load64(cell, 0))
  end
  rows = zr_xmalloc((PREOPENS + 1) * 24)
  Machine.store64(rows, 0, 0)
  stat = Machine.slot(8)
  n = 0
  fd = 3
  while n < PREOPENS && fd_prestat_get(Machine.i32(fd), zr_wasi_addr(stat)) == Machine.i32(0)
    if Machine.load8(stat, 0) == Machine.i8(0)
      len = Machine.word(Machine.load32(stat, 4))
      name = zr_xmalloc(len + 1)
      fd_prestat_dir_name(Machine.i32(fd), zr_wasi_addr(name), Machine.i32(len))
      Machine.store8(name + len, 0, Machine.i8(0))
      skip = zr_wasi_path_start(name)
      at = rows + (n * 24)
      Machine.store64(at, 0, fd)
      Machine.store64(at, 8, Machine.word(name) + skip)
      Machine.store64(at, 16, zr_cstr_len(name + skip))
      n += 1
      Machine.store64(rows + (n * 24), 0, 0)
    end
    fd += 1
  end
  Machine.store64(cell, 0, Machine.word(rows))
  rows
end

# How many bytes of leading `/` and `./` a path starts with.
sig [Ptr] => Word
machine def zr_wasi_path_start(path)
  at = 0
  going = true
  while going
    c = Machine.word(Machine.load8(path + at, 0))
    if c == 47
      at += 1
    elsif c == 46 && (Machine.word(Machine.load8(path + at + 1, 0)) == 47 || Machine.word(Machine.load8(path + at + 1, 0)) == 0)
      at += 1
    else
      going = false
    end
  end
  at
end

# The preopened directory `path` resolves under, the longest name that
# is a whole-component prefix of it winning; its descriptor, with the
# rest of the path at `rest` (`.` for the directory itself), or -1 with
# errno ENOENT when no directory holds it.
sig [Ptr, Ptr] => I32
machine def zr_wasi_dir(path, rest)
  p = path + zr_wasi_path_start(path)
  rows = zr_wasi_preopens()
  best = 0 - 1
  best_len = 0
  i = 0
  while Machine.load64(rows + (i * 24), 0) != 0
    at = rows + (i * 24)
    name = Machine.ptr(Machine.load64(at, 8))
    len = Machine.load64(at, 16)
    after = Machine.word(Machine.load8(p + len, 0))
    fits = len == 0 || (zr_bytes_eq(p, len, name, len) && (after == 0 || after == 47))
    if fits && (best < 0 || len > best_len)
      best = Machine.load64(at, 0)
      best_len = len
    end
    i += 1
  end
  if best < 0
    return zr_wasi_fail(WASI_ENOENT)
  end
  tail = p + best_len
  tail = tail + zr_wasi_path_start(tail)
  if Machine.load8(tail, 0) == Machine.i8(0)
    tail = Machine.bytes(".\0")
  end
  Machine.store64(rest, 0, Machine.word(tail))
  Machine.i32(best)
end

# A call on a path: its directory's descriptor and the path under it in
# `where` (a 16-byte slot: the rest's address, then its length), or -1
# with errno set.
sig [Ptr, Ptr] => I32
machine def zr_wasi_resolve(path, where)
  fd = zr_wasi_dir(path, where)
  if fd >= Machine.i32(0)
    Machine.store64(where, 8, zr_cstr_len(Machine.ptr(Machine.load64(where, 0))))
  end
  fd
end

sig [Ptr] => I32
machine def zr_wasi_rest(where)
  Machine.i32(Machine.load64(where, 0))
end

sig [Ptr] => I32
machine def zr_wasi_rest_len(where)
  Machine.i32(Machine.load64(where, 8))
end
