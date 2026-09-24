# darwin's half of loading code into this process: MAP_JIT mappings,
# the write-protect flip each write to one needs, and a name's address
# from this image's own symbol table, then dlsym over every loaded image.
Machine.import "dlsym", [Ptr, Ptr] => Ptr
Machine.import "_dyld_get_image_header", [I32] => Ptr
Machine.import "_dyld_get_image_vmaddr_slide", [I32] => Word
Machine.import "strcmp", [Ptr, Ptr] => I32
Machine.import "mmap", [Ptr, Word, I32, I32, I32, Word] => Ptr
Machine.import "munmap", [Ptr, Word] => I32
Machine.import "pthread_jit_write_protect_np", [I32] => Void
Machine.import "sys_icache_invalidate", [Ptr, Word] => Void

PROT_READ_WRITE = 3
PROT_READ_WRITE_EXEC = 7
# MAP_PRIVATE | MAP_ANON, MAP_JIT for a mapping that holds code, and
# MAP_FIXED for one placed inside a reservation.
MAP_ANON_PRIVATE = 4098
MAP_FIXED = 16
MAP_JIT = 2048
PROT_NONE = 0
# dlsym's handle for every image this process has loaded.
RTLD_DEFAULT = 0 - 2

# A region of `size` bytes that nothing may touch, for the JIT to place
# its code and its data in at addresses it chose: the two must stay
# within adrp's 4 GiB of each other, and a hint alone did not hold them.
sig [Value] => Value
machine def zr_os_jit_reserve(size)
  at = mmap(Machine.ptr(0), zr_fix2long(size), Machine.i32(PROT_NONE), Machine.i32(MAP_ANON_PRIVATE), Machine.i32(0 - 1), 0)
  if Machine.word(at) == 0 || Machine.word(at) == 0 - 1
    return Machine.value(QNIL)
  end
  zr_fix(Machine.word(at))
end

# `size` bytes of a reservation given back, for a MAP_JIT mapping to
# take by hint: the kernel will not map one MAP_FIXED.
sig [Value, Value] => Value
machine def zr_os_jit_release(at, size)
  munmap(Machine.ptr(zr_fix2long(at)), zr_fix2long(size))
  Machine.value(QNIL)
end

# A mapping of `size` bytes: data at `at` exactly where it is not zero
# (the caller reserved it), code by `at` as a hint, else where the
# kernel puts it. Code needs MAP_JIT, which costs a write-protect flip
# on every write.
sig [Value, Value, Value] => Value
machine def zr_os_jit_map(size, exec, at)
  prot = PROT_READ_WRITE
  flags = MAP_ANON_PRIVATE
  want = zr_fix2long(at)
  if exec != QFALSE && exec != QNIL
    prot = PROT_READ_WRITE_EXEC
    flags = MAP_ANON_PRIVATE + MAP_JIT
  elsif want != 0
    flags = MAP_ANON_PRIVATE + MAP_FIXED
  end
  got = mmap(Machine.ptr(want), zr_fix2long(size), Machine.i32(prot), Machine.i32(flags), Machine.i32(0 - 1), 0)
  if Machine.word(got) == 0 || Machine.word(got) == 0 - 1
    return Machine.value(QNIL)
  end
  zr_fix(Machine.word(got))
end

# The address a name already in this process answers to, or nil: from
# this image's own symbol table, else from dlsym (a name of libSystem's,
# or an image `ld` linked, whose table is not sorted).
sig [Value] => Value
machine def zr_os_symbol(name)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  # The table's names carry the C underscore; dlsym's do not.
  zr_buf_byte(b, 95)
  zr_buf_str(b, name)
  zr_buf_byte(b, 0)
  at = zr_symtab_find(Buf.ptr(b))
  if at == 0
    at = Machine.word(dlsym(Machine.ptr(RTLD_DEFAULT), Buf.ptr(b) + 1))
  end
  zr_buf_free(b)
  if at == 0
    return Machine.value(QNIL)
  end
  zr_fix(at)
end

# The Mach-O of this image as dyld left it: the load commands after the
# 32-byte header, each its kind and size; LC_SEGMENT_64 with its name at
# 8, vmaddr at 24 and fileoff at 40; LC_SYMTAB with symoff, nsyms and
# stroff at 8, 12 and 16; an nlist_64 of 16 bytes, its name's offset
# first and its address at 8, unslid.
LC_SEGMENT_64 = 25
LC_SYMTAB = 2
# "__LINKEDIT" as the two little-endian words of a 16-byte segment name.
LINKEDIT_LOW = 0x44454B4E494C5F5F
LINKEDIT_HIGH = 0x5449

# The address `cname` (with its underscore) has in this image's symbol
# table, or 0. The table is sorted by name (`Obj::MachO::Executable`),
# so this is a binary search over a third of a million names; a table
# another linker wrote is in no order, and the search misses, which is
# what dlsym is left for.
sig [Ptr] => Word
machine def zr_symtab_find(cname)
  header = _dyld_get_image_header(Machine.i32(0))
  slide = _dyld_get_image_vmaddr_slide(Machine.i32(0))
  ncmds = Machine.word(Machine.load32(header, 16))
  cmd = header + 32
  link_vm = 0
  link_off = 0
  symoff = 0
  nsyms = 0
  stroff = 0
  i = 0
  while i < ncmds
    kind = Machine.word(Machine.load32(cmd, 0))
    if kind == LC_SEGMENT_64 && Machine.load64(cmd, 8) == LINKEDIT_LOW && Machine.load64(cmd, 16) == LINKEDIT_HIGH
      link_vm = Machine.load64(cmd, 24)
      link_off = Machine.load64(cmd, 40)
    elsif kind == LC_SYMTAB
      symoff = Machine.word(Machine.load32(cmd, 8))
      nsyms = Machine.word(Machine.load32(cmd, 12))
      stroff = Machine.word(Machine.load32(cmd, 16))
    end
    cmd += Machine.word(Machine.load32(cmd, 4))
    i += 1
  end
  if nsyms == 0 || link_vm == 0
    return 0
  end
  # A file offset in __LINKEDIT is that far past where the segment starts.
  linkedit = Machine.ptr(link_vm + slide - link_off)
  nlist = linkedit + symoff
  strings = linkedit + stroff
  lo = 0
  hi = nsyms
  while lo < hi
    mid = (lo + hi) / 2
    entry = nlist + (mid * 16)
    c = strcmp(strings + Machine.word(Machine.load32(entry, 0)), cname)
    if c == 0
      return Machine.load64(entry, 8) + slide
    elsif c < 0
      lo = mid + 1
    else
      hi = mid
    end
  end
  0
end

# The write into the code mapping: unprotected, copied, protected
# again, and the instruction cache told what moved.
sig [Value, Value] => Value
machine def zr_os_jit_write(at, bytes)
  to = Machine.ptr(zr_fix2long(at))
  len = RString.len(bytes)
  pthread_jit_write_protect_np(Machine.i32(0))
  zr_memcpy(to, RString.ptr(bytes), len)
  pthread_jit_write_protect_np(Machine.i32(1))
  sys_icache_invalidate(to, len)
  Machine.value(QNIL)
end

# The image libffi lives in, which the ffi gem's calls open the first
# time a program asks for one.
sig [] => Ptr
machine def zr_os_libffi_path
  Machine.bytes("/usr/lib/libffi.dylib\0")
end
