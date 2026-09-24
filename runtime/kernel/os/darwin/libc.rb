# darwin's libc, where ruby shows it: qsort_r, whose order decides a
# sort's ties. Libc's BSD qsort is the one runtime/kernel/sort.rb follows.
sig [Ptr, Word] => Void
machine def zr_os_sort(st, n)
  zr_sort_range(st, 0, n)
end

# The bytes a malloc'd block holds, which the heap counts as payload.
Machine.import "malloc_size", [Ptr] => Word

sig [Ptr] => Word
machine def zr_os_malloc_size(p)
  malloc_size(p)
end

# SHA-256 of the whole blocks at `p`, `n` bytes of them, from and into
# the chaining words `h` (a 64-bit slot a word, as runtime/kernel/digest.rb
# keeps them), by CommonCrypto, which runs the CPU's own SHA-256
# instructions: some twenty times the portable compression's speed. A
# CC_SHA256_CTX is (count[2], hash[8], wbuf[16]) in 32-bit words; one
# whose count is 0 and whose hash is `h`, given whole blocks, compresses
# them in order and holds nothing back, which is all zr_sha256_block
# does a block.
Machine.import "CC_SHA256_Update", [Ptr, Ptr, I32] => I32

sig [Ptr, Ptr, Word] => Bool
machine def zr_os_sha256_blocks(h, p, n)
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
    CC_SHA256_Update(ctx, p + at, Machine.i32(take))
    at += take
  end
  i = 0
  while i < 8
    Machine.store64(h + (i * 8), 0, Machine.word(Machine.load32(ctx + 8 + (i * 4), 0)))
    i += 1
  end
  true
end
