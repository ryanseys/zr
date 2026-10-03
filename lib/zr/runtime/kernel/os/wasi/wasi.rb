module Zr::Kern
  # WASI preview 1: the calls that a wasm32-wasi module makes to its host,
  # and the helpers that the rest of this layer uses with them: errno,
  # iovecs, and the preopened directories that contain the paths. An
  # address goes to the host as its low 32 bits, which are all of a
  # wasm32 address.

  # WASI's errno numbers, with wasi-libc's E names.
  WASI_EBADF = 8
  WASI_EINVAL = 28
  WASI_ENOENT = 44
  WASI_ENOSYS = 52
  WASI_ENOTTY = 59

  # The low 32 bits of an address, which is the form a host call takes.
  #: (ptr) -> i32
  def zr_wasi_addr(p)
    Machine.i32(Machine.word(p))
  end

  # Converts a WASI call's errno to the libc result: 0, or -1 with errno set.
  #: (i32) -> i32
  def zr_wasi_status(errno)
    if errno == Machine.i32(0)
      return Machine.i32(0)
    end
    zr_os_set_errno(Machine.u32(errno))
    Machine.i32(0 - 1)
  end

  # Returns -1 and sets errno to `n`, for a call that fails before it gets
  # to the host.
  #: (word) -> i32
  def zr_wasi_fail(n)
    zr_os_set_errno(n)
    Machine.i32(0 - 1)
  end

  # Writes one iovec of `len` bytes at `buf` into the caller's slot. The
  # host reads two 32-bit words.
  #: (ptr, ptr, word) -> i32
  def zr_wasi_iovec(iov, buf, len)
    Machine.store32(iov, 0, zr_wasi_addr(buf))
    Machine.store32(iov, 4, Machine.i32(len))
    zr_wasi_addr(iov)
  end

  # The preopened directories, found one time. Each directory has an
  # entry of three words (descriptor, name address, name length). A zero
  # descriptor ends the entries. A name is kept as the host gives it,
  # without a leading `/` or `./`, so `.` and `/` both match all paths.
  PREOPENS = 32

  #: () -> ptr
  def zr_wasi_preopens
    cell = Machine.static(:wasi_preopens, 8)
    if Machine.load64(cell, 0) != 0
      return Machine.ptr(Machine.load64(cell, 0))
    end
    rows = zr_xmalloc((PREOPENS + 1) * 24)
    Machine.store64(rows, 0, 0)
    stat = Machine.slot(8)
    n = 0
    fd = 3
    while n < PREOPENS && Libc.fd_prestat_get(Machine.i32(fd), zr_wasi_addr(stat)) == Machine.i32(0)
      if Machine.load8(stat, 0) == Machine.i8(0)
        len = Machine.u32(Machine.load32(stat, 4))
        name = zr_xmalloc(len + 1)
        Libc.fd_prestat_dir_name(Machine.i32(fd), zr_wasi_addr(name), Machine.i32(len))
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

  # The number of bytes of leading `/` and `./` in a path.
  #: (ptr) -> word
  def zr_wasi_path_start(path)
    at = 0
    going = true
    while going
      c = Machine.u8(Machine.load8(path + at, 0))
      if c == 47
        at += 1
      elsif c == 46 && (Machine.u8(Machine.load8(path + at + 1, 0)) == 47 || Machine.u8(Machine.load8(path + at + 1, 0)) == 0)
        at += 1
      else
        going = false
      end
    end
    at
  end

  # Finds the preopened directory that contains `path`. The longest name
  # that is a prefix of whole components is the match. Returns its
  # descriptor and stores the rest of the path at `rest` (`.` for the
  # directory itself). Returns -1 with errno ENOENT if no directory
  # contains the path.
  #: (ptr, ptr) -> i32
  def zr_wasi_dir(path, rest)
    p = path + zr_wasi_path_start(path)
    rows = zr_wasi_preopens()
    best = 0 - 1
    best_len = 0
    i = 0
    while Machine.load64(rows + (i * 24), 0) != 0
      at = rows + (i * 24)
      name = Machine.ptr(Machine.load64(at, 8))
      len = Machine.load64(at, 16)
      after = Machine.u8(Machine.load8(p + len, 0))
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

  # Prepares a call on a path. Returns the descriptor of its directory and
  # stores the rest of the path in `where` (a 16-byte slot: the address,
  # then the length). Returns -1 with errno set on failure.
  #: (ptr, ptr) -> i32
  def zr_wasi_resolve(path, where)
    fd = zr_wasi_dir(path, where)
    if fd >= Machine.i32(0)
      Machine.store64(where, 8, zr_cstr_len(Machine.ptr(Machine.load64(where, 0))))
    end
    fd
  end

  #: (ptr) -> i32
  def zr_wasi_rest(where)
    Machine.i32(Machine.load64(where, 0))
  end

  #: (ptr) -> i32
  def zr_wasi_rest_len(where)
    Machine.i32(Machine.load64(where, 8))
  end
end
