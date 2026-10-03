module Zr::Kern
  # The darwin part of code loading into this process: MAP_JIT mappings,
  # the write-protect toggle that each write to them needs, and symbol
  # lookup in this image's own symbol table, then with dlsym in all
  # loaded images.
  Libc.import :dlsym, [Ptr, Ptr] => Ptr
  Libc.import :_dyld_get_image_header, [I32] => Ptr
  Libc.import :_dyld_get_image_vmaddr_slide, [I32] => Word
  Libc.import :strcmp, [Ptr, Ptr] => I32
  Libc.import :mmap, [Ptr, Word, I32, I32, I32, Word] => Ptr
  Libc.import :munmap, [Ptr, Word] => I32
  Libc.import :pthread_jit_write_protect_np, [I32] => Void
  Libc.import :sys_icache_invalidate, [Ptr, Word] => Void

  PROT_READ_WRITE = 3
  PROT_READ_WRITE_EXEC = 7
  # MAP_PRIVATE | MAP_ANON, MAP_JIT for a mapping that contains code, and
  # MAP_FIXED for a mapping inside a reservation.
  MAP_ANON_PRIVATE = 4098
  MAP_FIXED = 16
  MAP_JIT = 2048
  PROT_NONE = 0
  # dlsym's handle for all images that this process has loaded.
  RTLD_DEFAULT = 0 - 2

  # Reserves a region of `size` bytes with no access, where the JIT puts
  # its code and data at addresses that it selects. The code and the data
  # must be within the 4 GiB range of adrp, and a hint alone does not keep
  # them that near.
  #: (value) -> value
  def zr_os_jit_reserve(size)
    at = Libc.mmap(Machine.ptr(0), zr_fix2long(size), Machine.i32(PROT_NONE), Machine.i32(MAP_ANON_PRIVATE), Machine.i32(0 - 1), 0)
    if Machine.word(at) == 0 || Machine.word(at) == 0 - 1
      return Machine.value(QNIL)
    end
    zr_fix(Machine.word(at))
  end

  # Releases `size` bytes of a reservation, so that a MAP_JIT mapping can
  # use them through a hint. The kernel does not accept MAP_FIXED for a
  # MAP_JIT mapping.
  #: (value, value) -> value
  def zr_os_jit_release(at, size)
    Libc.munmap(Machine.ptr(zr_fix2long(at)), zr_fix2long(size))
    Machine.value(QNIL)
  end

  # Maps `size` bytes. Data goes exactly at `at` if it is not zero (the
  # caller reserved it). Code uses `at` as a hint. Else the kernel selects
  # the address. Code needs MAP_JIT, which adds a write-protect toggle to
  # each write.
  #: (value, value, value) -> value
  def zr_os_jit_map(size, exec, at)
    prot = PROT_READ_WRITE
    flags = MAP_ANON_PRIVATE
    want = zr_fix2long(at)
    if exec != QFALSE && exec != QNIL
      prot = PROT_READ_WRITE_EXEC
      flags = MAP_ANON_PRIVATE + MAP_JIT
    elsif want != 0
      flags = MAP_ANON_PRIVATE + MAP_FIXED
    end
    got = Libc.mmap(Machine.ptr(want), zr_fix2long(size), Machine.i32(prot), Machine.i32(flags), Machine.i32(0 - 1), 0)
    if Machine.word(got) == 0 || Machine.word(got) == 0 - 1
      return Machine.value(QNIL)
    end
    zr_fix(Machine.word(got))
  end

  # The address of a name that is already in this process, or nil. It
  # looks first in this image's own symbol table, then with dlsym (for a
  # libSystem name, or an image that `ld` linked, whose table is not
  # sorted).
  #: (value) -> value
  def zr_os_symbol(name)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    # The names in the table have the C underscore. dlsym names do not.
    zr_buf_byte(b, 95)
    zr_buf_str(b, name)
    zr_buf_byte(b, 0)
    at = zr_symtab_find(Buf.ptr(b))
    if at == 0
      at = Machine.word(Libc.dlsym(Machine.ptr(RTLD_DEFAULT), Buf.ptr(b) + 1))
    end
    zr_buf_free(b)
    if at == 0
      return Machine.value(QNIL)
    end
    zr_fix(at)
  end

  # The Mach-O layout of this image as dyld loads it. The load commands
  # follow the 32-byte header, and each starts with its kind and size.
  # LC_SEGMENT_64 has its name at 8, vmaddr at 24 and fileoff at 40.
  # LC_SYMTAB has symoff, nsyms and stroff at 8, 12 and 16. An nlist_64 is
  # 16 bytes: the name offset first, and the unslid address at 8.
  LC_SEGMENT_64 = 25
  LC_SYMTAB = 2
  # "__LINKEDIT" as the two little-endian words of a 16-byte segment name.
  LINKEDIT_LOW = 0x44454B4E494C5F5F
  LINKEDIT_HIGH = 0x5449

  # The address of `cname` (with its underscore) in this image's symbol
  # table, or 0. `Obj::MachO::Executable` sorts the table by name, so
  # this is a binary search over about 330,000 names. A table from a
  # different linker is not sorted, so the search fails, and dlsym does
  # the lookup.
  #: (ptr) -> word
  def zr_symtab_find(cname)
    header = Libc._dyld_get_image_header(Machine.i32(0))
    slide = Libc._dyld_get_image_vmaddr_slide(Machine.i32(0))
    ncmds = Machine.u32(Machine.load32(header, 16))
    cmd = header + 32
    link_vm = 0
    link_off = 0
    symoff = 0
    nsyms = 0
    stroff = 0
    i = 0
    while i < ncmds
      kind = Machine.u32(Machine.load32(cmd, 0))
      if kind == LC_SEGMENT_64 && Machine.load64(cmd, 8) == LINKEDIT_LOW && Machine.load64(cmd, 16) == LINKEDIT_HIGH
        link_vm = Machine.load64(cmd, 24)
        link_off = Machine.load64(cmd, 40)
      elsif kind == LC_SYMTAB
        symoff = Machine.u32(Machine.load32(cmd, 8))
        nsyms = Machine.u32(Machine.load32(cmd, 12))
        stroff = Machine.u32(Machine.load32(cmd, 16))
      end
      cmd += Machine.u32(Machine.load32(cmd, 4))
      i += 1
    end
    if nsyms == 0 || link_vm == 0
      return 0
    end
    # A file offset in __LINKEDIT is the same distance past the start of
    # the segment in memory.
    linkedit = Machine.ptr(link_vm + slide - link_off)
    nlist = linkedit + symoff
    strings = linkedit + stroff
    lo = 0
    hi = nsyms
    while lo < hi
      mid = (lo + hi) / 2
      entry = nlist + (mid * 16)
      c = Libc.strcmp(strings + Machine.u32(Machine.load32(entry, 0)), cname)
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

  # Writes into the code mapping. It removes the write protection, copies
  # the bytes, sets the protection again, and flushes the instruction
  # cache for the changed bytes.
  #: (value, value) -> value
  def zr_os_jit_write(at, bytes)
    to = Machine.ptr(zr_fix2long(at))
    len = RString.len(bytes)
    Libc.pthread_jit_write_protect_np(Machine.i32(0))
    zr_memcpy(to, RString.ptr(bytes), len)
    Libc.pthread_jit_write_protect_np(Machine.i32(1))
    Libc.sys_icache_invalidate(to, len)
    Machine.value(QNIL)
  end

  # The library that contains libffi. The ffi gem's calls open it the
  # first time a program uses one of them.
  #: () -> ptr
  def zr_os_libffi_path
    Machine.bytes("/usr/lib/libffi.dylib\0")
  end
end
