module Zr::Kern
  # The Linux part of code loading into this process: plain executable
  # mappings, an instruction cache flush after each write, and symbol
  # lookup in the binary's own symbol table.

  PROT_READ_WRITE = 3
  PROT_READ_WRITE_EXEC = 7
  # MAP_PRIVATE | MAP_ANONYMOUS.
  MAP_ANON_PRIVATE = 34
  # dlsym's handle for all images that this process has loaded.
  RTLD_DEFAULT = 0

  # A static binary is at a low address, where the kernel puts a mapping
  # only on request. The JIT reaches the program's data with adrp, which has
  # a range of 4 GiB. Thus a mapping with no hint goes 1 GiB above the
  # program, past the space for its heap, and each next mapping follows
  # the one before. MAP_FIXED_NOREPLACE uses the address only if it is
  # free; else the kernel selects an address.
  MAP_FIXED_NOREPLACE = 1048576
  JIT_GAP = 1073741824
  PAGE_MASK = 0 - 4096

  # No reservation is necessary: the mapping cursor keeps the mappings
  # next to each other.
  #: (value) -> value
  def zr_os_jit_reserve(size)
    Machine.value(QNIL)
  end

  #: (value, value) -> value
  def zr_os_jit_release(at, size)
    Machine.value(QNIL)
  end

  # Maps `size` bytes, near `hint` if possible.
  #: (value, value, value) -> value
  def zr_os_jit_map(size, exec, hint)
    prot = PROT_READ_WRITE
    if exec != QFALSE && exec != QNIL
      prot = PROT_READ_WRITE_EXEC
    end
    bytes = (zr_fix2long(size) + 4095) & PAGE_MASK
    cursor = Machine.static(:linux_jit_cursor, 8)
    if Machine.load64(cursor, 0) == 0
      Machine.store64(cursor, 0, (Machine.word(Machine.addr(:zr_os_jit_map)) & PAGE_MASK) + JIT_GAP)
    end
    want = zr_fix2long(hint)
    if want == 0
      want = Machine.load64(cursor, 0)
    end
    at = Libc.mmap(Machine.ptr(want), bytes, Machine.i32(prot), Machine.i32(MAP_ANON_PRIVATE | MAP_FIXED_NOREPLACE), Machine.i32(0 - 1), 0)
    if Machine.word(at) == 0 - 1
      at = Libc.mmap(Machine.ptr(0), bytes, Machine.i32(prot), Machine.i32(MAP_ANON_PRIVATE), Machine.i32(0 - 1), 0)
    end
    if Machine.word(at) == 0 || Machine.word(at) == 0 - 1
      return Machine.value(QNIL)
    end
    Machine.store64(cursor, 0, Machine.word(at) + bytes)
    zr_fix(Machine.word(at))
  end

  # The program's own symbol table. musl's dlsym finds nothing in a static
  # binary, and glibc's finds only the names that the binary exports. But the binary keeps its ELF .symtab (the linker links all of a
  # program that evals), and a non-PIE link puts each symbol at its own
  # value. Thus zr maps /proc/self/exe one time and finds the table from
  # its section headers. The slot contains the first symbol entry, the
  # entry count and the string table. The count is -1 if zr cannot read
  # the binary.
  ELF_SHOFF = 40
  ELF_SHENTSIZE = 58
  ELF_SHNUM = 60
  SHT_SYMTAB = 2
  SYM_LEN = 24
  PROT_READ = 1
  MAP_PRIVATE = 2
  SEEK_END = 2

  #: () -> ptr
  def zr_linux_symtab
    cell = Machine.static(:linux_symtab, 24)
    if Machine.load64(cell, 8) != 0
      return cell
    end
    Machine.store64(cell, 8, 0 - 1)
    fd = zr_os_open(Machine.bytes("/proc/self/exe\0"), Machine.i32(O_CLOEXEC), Machine.i32(0))
    if fd < Machine.i32(0)
      return cell
    end
    size = Libc.lseek(fd, 0, Machine.i32(SEEK_END))
    image = Libc.mmap(0, size, Machine.i32(PROT_READ), Machine.i32(MAP_PRIVATE), fd, 0)
    Libc.close(fd)
    if Machine.word(image) == 0 - 1
      return cell
    end
    headers = image + Machine.load64(image, ELF_SHOFF)
    width = Machine.u32(Machine.load32(image, ELF_SHENTSIZE)) & 65535
    count = Machine.u32(Machine.load32(image, ELF_SHNUM)) & 65535
    i = 0
    while i < count
      header = headers + (i * width)
      if Machine.u32(Machine.load32(header, 4)) == SHT_SYMTAB
        strings = headers + (Machine.u32(Machine.load32(header, 40)) * width)
        Machine.store64(cell, 0, Machine.word(image) + Machine.load64(header, 24))
        Machine.store64(cell, 16, Machine.word(image) + Machine.load64(strings, 24))
        Machine.store64(cell, 8, Machine.load64(header, 32) / SYM_LEN)
      end
      i += 1
    end
    cell
  end

  # The address of a name that is already in this process, or nil. The
  # name must be a defined global or weak symbol.
  #: (value) -> value
  def zr_os_symbol(name)
    cell = zr_linux_symtab()
    rows = Machine.load64(cell, 8)
    if rows == 0 - 1
      return zr_notimplement(Machine.bytes("dlsym"), 5)
    end
    table = Machine.ptr(Machine.load64(cell, 0))
    strings = Machine.ptr(Machine.load64(cell, 16))
    want = RString[name].ptr
    len = RString[name].len
    i = 0
    while i < rows
      row = table + (i * SYM_LEN)
      # st_info has the binding in its high nibble. Then come st_other and
      # the section index, which is 0 for a name defined in a different
      # object.
      info = Machine.u32(Machine.load32(row, 4))
      bind = (info & 255) >> 4
      shown = strings + Machine.u32(Machine.load32(row, 0))
      if (bind == 1 || bind == 2) && (info >> 16) != 0 && zr_bytes_eq(shown, len, want, len) && Machine.load8(shown + len, 0) == Machine.i8(0)
        return zr_fix(Machine.load64(row, 8))
      end
      i += 1
    end
    zr_os_symbol_loaded(name)
  end

  # Writes into the code mapping, then flushes the instruction cache for
  # the changed bytes.
  #: (value, value) -> value
  def zr_os_jit_write(at, bytes)
    to = Machine.ptr(zr_fix2long(at))
    len = RString[bytes].len
    zr_memcpy(to, RString[bytes].ptr, len)
    zr_os_jit_flush(to, len)
    Machine.value(QNIL)
  end

  # libffi's shared library. dlopen cannot open it in a static binary, so
  # the ffi gem's first call returns dlopen's error.
  #: () -> ptr
  def zr_os_libffi_path
    Machine.bytes("libffi.so.8\0")
  end
end
