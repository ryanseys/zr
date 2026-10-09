module Zr::Kern
  # The parts of darwin's libc that ruby behavior shows. qsort_r sets the
  # order of equal elements in a sort. lib/zr/runtime/kernel/sort.rb copies
  # Libc's BSD qsort.
  #: (ptr, word) -> void
  def zr_os_sort(st, n)
    zr_sort_apple_all(st, n)
  end

  # ruby_qsort: sorts `nel` records of `size` bytes at `base` with C's
  # `cmp(a, b, data)`, as ruby does on darwin: with libc's BSD qsort_r,
  # so equal records end in ruby's order. BSD's comparator takes its
  # data first; zr_darwin_qsort_cmp passes the call on in C's order.
  #: (ptr, word, word, ptr, word) -> void
  def zr_os_c_qsort(base, nel, size, cmp, data)
    thunk = Machine.slot(16)
    Machine.store64(thunk, 0, Machine.word(cmp))
    Machine.store64(thunk, 8, data)
    Libc.qsort_r(base, nel, size, thunk, Machine.addr(:zr_darwin_qsort_cmp))
  end

  # qsort_r calls this C-entry def. A C comparator that raises unwinds
  # out of the sort, as its longjmp does in ruby.
  #: (ptr, ptr, ptr) -> i32
  def zr_darwin_qsort_cmp(thunk, a, b)
    Machine.gates_enter
    zr_c_entered()
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(a))
    Machine.store64(argv, 8, Machine.word(b))
    Machine.store64(argv, 16, Machine.load64(thunk, 8))
    if !zr_call_c_returned(Machine.ptr(Machine.load64(thunk, 0)), argv, 3)
      zr_c_unwind()
    end
    Machine.i32(Machine.load64(argv, 0))
  end

  # fdopen(3): a stdio FILE on the descriptor `fd`. darwin's headers bind
  # the name to fdopen$DARWIN_EXTSN, which dlsym finds, as zr_select_fn
  # finds select's.
  module FdopenCall
    #: (ptr, i32, ptr) -> ptr
    def self.call(fn, fd, mode) = Machine.indirect
  end

  #: (i32, ptr) -> ptr
  def zr_os_fdopen(fd, mode)
    cell = Machine.static(:fdopen_fn, 8)
    if Machine.load64(cell, 0) == 0
      Machine.store64(cell, 0, Machine.word(Libc.dlsym(Machine.ptr(RTLD_DEFAULT), Machine.bytes("fdopen$DARWIN_EXTSN\0"))))
    end
    FdopenCall.call(Machine.ptr(Machine.load64(cell, 0)), fd, mode)
  end

  # The usable size of a malloc'd block. The heap counts it as payload.
  #: (ptr) -> word
  def zr_os_malloc_size(p)
    Libc.malloc_size(p)
  end

  # SHA-256 of the `n` bytes of whole blocks at `p`. It reads and updates
  # the chaining words `h` (one 64-bit slot for each word, as
  # lib/zr/runtime/kernel/digest.rb keeps them). CommonCrypto uses the CPU's
  # SHA-256 instructions, which are about twenty times faster than the
  # portable compression. A CC_SHA256_CTX is (count[2], hash[8], wbuf[16])
  # in 32-bit words. With count 0 and hash `h`, it compresses whole blocks
  # in order and keeps no bytes back. That is the same as zr_sha256_block
  # for each block.
  #: (ptr, ptr, word) -> bool
  def zr_os_sha256_blocks(h, p, n)
    ctx = Machine.slot(104)
    Machine.store64(ctx, 0, 0)
    i = 0
    while i < 8
      Machine.store32(ctx + 8 + (i * 4), 0, Machine.i32(Machine.load64(h + (i * 8), 0)))
      i += 1
    end
    at = 0
    while at < n
      take = n - at
      if take > 1073741824
        take = 1073741824
      end
      Libc.CC_SHA256_Update(ctx, p + at, Machine.i32(take))
      at += take
    end
    i = 0
    while i < 8
      Machine.store64(h + (i * 8), 0, Machine.u32(Machine.load32(ctx + 8 + (i * 4), 0)))
      i += 1
    end
    true
  end
end
