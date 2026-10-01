module Zr::Kern
  # The parts of darwin's libc that ruby behavior shows. qsort_r sets the
  # order of equal elements in a sort. lib/zr/runtime/kernel/sort.rb copies
  # Libc's BSD qsort.
  sig [Ptr, Word] => Void
  def zr_os_sort(st, n)
    zr_sort_apple_all(st, n)
  end

  # The usable size of a malloc'd block. The heap counts it as payload.
  Libc.import :malloc_size, [Ptr] => Word

  sig [Ptr] => Word
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
  Libc.import :CC_SHA256_Update, [Ptr, Ptr, I32] => I32

  sig [Ptr, Ptr, Word] => Bool
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
      Machine.store64(h + (i * 8), 0, Machine.word(Machine.load32(ctx + 8 + (i * 4), 0)))
      i += 1
    end
    true
  end
end
