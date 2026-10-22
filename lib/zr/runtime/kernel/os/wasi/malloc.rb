module Zr::Kern
  # The module's allocator: size classes over the bump heap
  # (`zr_wasm_sbrk`, backend/wasm/shims.rb), with one free list for each
  # class. Without it, free did nothing, and a program that allocates
  # and drops more than 4 GiB in all (a GC test, a long loop) used up the
  # wasm32 address space.
  #
  # Each block has a 16-byte head before its payload: the payload's size
  # at -16, and at -8 0 for a block of malloc, or ALIGNED for a block of
  # posix_memalign. A free block keeps the next free block of its list in
  # its first word. A size class is a multiple of 16 up to 64, then four
  # steps between each two powers of two, so a block is at most a quarter
  # larger than its request.
  #
  # posix_memalign cuts its block from the bump at the next multiple of
  # its alignment, as musl's does, and the bytes before it (the gap) serve
  # later blocks of malloc. The heap's arenas take 4 MiB alignment, one in
  # each 4 MiB of the address space (zr_arena_of), so a block of
  # malloc(size + align) cost 5 MiB for each arena, and a test with 2
  # million cells ran out of its 1 GiB. A freed aligned block goes on a
  # list of its own, for the next posix_memalign.

  HEAD = 16
  # The word at -8 of a block of posix_memalign. A distance back is a
  # multiple of 16, so it is never 1.
  ALIGNED = 1
  # A class above SMALL_TOP has four steps between each two powers of two.
  SMALL_TOP = 64
  CLASSES = 112
  # The bump's largest request (Codegen::BUMP_MAX): a larger size would
  # wrap in a wasm32 address.
  HEAP_MAX = 4294901760
  WASI_ENOMEM = 48

  # The class of the smallest block that holds `n` bytes.
  #: (word) -> word
  def zr_wasi_class_up(n)
    if n <= SMALL_TOP
      return n == 0 ? 0 : ((n + 15) >> 4) - 1
    end
    m = n - 1
    k = 63 - Machine.clz(m)
    4 + (4 * (k - 6)) + ((m >> (k - 2)) & 3)
  end

  # The class of the largest block that `size` bytes hold, for a block of
  # posix_memalign whose size is no class.
  #: (word) -> word
  def zr_wasi_class_down(size)
    if size < SMALL_TOP + 16
      return (size >> 4) - 1
    end
    k = 63 - Machine.clz(size)
    j = (size >> (k - 2)) & 3
    j == 0 ? (4 * (k - 6)) + 3 : 4 + (4 * (k - 6)) + j - 1
  end

  # The payload size of class `c`.
  #: (word) -> word
  def zr_wasi_class_size(c)
    if c < 4
      return (c + 1) << 4
    end
    k = 6 + ((c - 4) >> 2)
    (1 << k) + ((((c - 4) & 3) + 1) << (k - 2))
  end

  #: (word) -> ptr
  def zr_wasi_bin(c)
    Machine.static(:wasi_bins, CLASSES * 8) + (c * 8)
  end

  #: (word) -> ptr
  def malloc(n)
    if n > HEAP_MAX - HEAD
      zr_os_set_errno(WASI_ENOMEM)
      return Machine.ptr(0)
    end
    c = zr_wasi_class_up(n)
    bin = zr_wasi_bin(c)
    p = Machine.ptr(Machine.load64(bin, 0))
    if p != 0
      Machine.store64(bin, 0, Machine.load64(p, 0))
      return p
    end
    size = zr_wasi_class_size(c)
    block = zr_wasi_gap_take(size + HEAD)
    if block == 0
      block = Machine.ptr(Libc.zr_wasm_sbrk(size + HEAD))
    end
    if block == 0
      zr_os_set_errno(WASI_ENOMEM)
      return Machine.ptr(0)
    end
    Machine.store64(block, 0, size)
    Machine.store64(block, 8, 0)
    block + HEAD
  end

  #: (ptr) -> void
  def free(p)
    if p == 0
      return
    end
    back = Machine.load64(p - HEAD, 8)
    if back == ALIGNED
      list = Machine.static(:wasi_aligned, 8)
      Machine.store64(p, 0, Machine.load64(list, 0))
      Machine.store64(list, 0, Machine.word(p))
      return
    end
    if back != 0
      p = p - back
    end
    bin = zr_wasi_bin(zr_wasi_class_down(Machine.load64(p - HEAD, 0)))
    Machine.store64(p, 0, Machine.load64(bin, 0))
    Machine.store64(bin, 0, Machine.word(p))
  end

  #: (ptr, word) -> ptr
  def realloc(p, n)
    if p == 0
      return malloc(n)
    end
    have = zr_os_malloc_size(p)
    if n <= have
      return p
    end
    q = malloc(n)
    if q != 0
      zr_memcpy(q, p, have)
      free(p)
    end
    q
  end

  # `n` bytes (a multiple of 16) from the gap before the last block of
  # posix_memalign, or 0 when the gap has fewer.
  #: (word) -> ptr
  def zr_wasi_gap_take(n)
    gap = Machine.static(:wasi_gap, 16)
    at = Machine.load64(gap, 0)
    if Machine.load64(gap, 8) - at < n
      return Machine.ptr(0)
    end
    Machine.store64(gap, 0, at + n)
    Machine.ptr(at)
  end

  # A block of `size` bytes at a multiple of `align`: a freed one that
  # fits, else one cut from the bump at the next multiple, after a gap
  # that later blocks of malloc take. The rest of the gap before it
  # becomes a free block.
  #: (ptr, word, word) -> i32
  def posix_memalign(slot, align, size)
    if align <= HEAD
      p = malloc(size)
      Machine.store64(slot, 0, Machine.word(p))
      return p == 0 ? Machine.i32(WASI_ENOMEM) : Machine.i32(0)
    end
    if size > HEAP_MAX - align - HEAD
      return Machine.i32(WASI_ENOMEM)
    end
    prev = Machine.static(:wasi_aligned, 8)
    p = Machine.ptr(Machine.load64(prev, 0))
    while p != 0
      if Machine.load64(p - HEAD, 0) >= size && (Machine.word(p) & (align - 1)) == 0
        Machine.store64(prev, 0, Machine.load64(p, 0))
        Machine.store64(slot, 0, Machine.word(p))
        return Machine.i32(0)
      end
      prev = p
      p = Machine.ptr(Machine.load64(p, 0))
    end
    payload = (size + 15) & (0 - 16)
    start = Machine.word(Libc.zr_wasm_sbrk(0))
    at = (start + HEAD + align - 1) & (0 - align)
    if Machine.ptr(Libc.zr_wasm_sbrk(at + payload - start)) == 0
      return Machine.i32(WASI_ENOMEM)
    end
    zr_wasi_gap_close()
    gap = Machine.static(:wasi_gap, 16)
    Machine.store64(gap, 0, start)
    Machine.store64(gap, 8, at - HEAD)
    Machine.store64(Machine.ptr(at - HEAD), 0, payload)
    Machine.store64(Machine.ptr(at - HEAD), 8, ALIGNED)
    Machine.store64(slot, 0, at)
    Machine.i32(0)
  end

  # The rest of the gap, when it holds a block, becomes a free block of
  # malloc, and the gap is empty.
  #: () -> void
  def zr_wasi_gap_close
    gap = Machine.static(:wasi_gap, 16)
    at = Machine.load64(gap, 0)
    left = Machine.load64(gap, 8) - at
    Machine.store64(gap, 0, 0)
    Machine.store64(gap, 8, 0)
    if left < HEAD + 16
      return
    end
    block = Machine.ptr(at)
    Machine.store64(block, 0, left - HEAD)
    Machine.store64(block, 8, 0)
    free(block + HEAD)
  end

  # The usable size of a block of malloc, which the heap counts as payload.
  #: (ptr) -> word
  def zr_os_malloc_size(p)
    Machine.load64(p - HEAD, 0)
  end
end
