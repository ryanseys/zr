module Zr::Kern
  # The module's allocator: size classes over the bump heap
  # (`zr_wasm_sbrk`, backend/wasm/shims.rb), with one free list for each
  # class. Without it, free did nothing, and a program that allocates
  # and drops more than 4 GiB in all (a GC test, a long loop) used up the
  # wasm32 address space.
  #
  # Each block has a 16-byte head before its payload: the payload's size
  # at -16, and at -8 the distance back to the start of the block that
  # posix_memalign cut it from (0 for a block of malloc). A free block
  # keeps the next free block of its list in its first word. A size class
  # is a multiple of 16 up to 64, then four steps between each two powers
  # of two, so a block is at most a quarter larger than its request.

  HEAD = 16
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
    block = Machine.ptr(Libc.zr_wasm_sbrk(size + HEAD))
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

  # A block of `size` bytes at a multiple of `align`, cut from a block of
  # malloc. Its own head gives its size and the distance back, so free and
  # malloc_size see the block that malloc gave.
  #: (ptr, word, word) -> i32
  def posix_memalign(slot, align, size)
    if align <= HEAD
      p = malloc(size)
      Machine.store64(slot, 0, Machine.word(p))
      return p == 0 ? Machine.i32(WASI_ENOMEM) : Machine.i32(0)
    end
    if size > HEAP_MAX - align
      return Machine.i32(WASI_ENOMEM)
    end
    p = malloc(size + align)
    if p == 0
      return Machine.i32(WASI_ENOMEM)
    end
    at = (Machine.word(p) + align - 1) & (0 - align)
    back = at - Machine.word(p)
    if back != 0
      Machine.store64(Machine.ptr(at - HEAD), 0, Machine.load64(p - HEAD, 0) - back)
      Machine.store64(Machine.ptr(at - HEAD), 8, back)
    end
    Machine.store64(slot, 0, at)
    Machine.i32(0)
  end

  # The usable size of a block of malloc, which the heap counts as payload.
  #: (ptr) -> word
  def zr_os_malloc_size(p)
    Machine.load64(p - HEAD, 0)
  end
end
