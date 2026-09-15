# Linux's half of loading code into this process: plain executable
# mappings, the instruction cache flushed after each write, and names
# looked up in the binary's own symbol table.
Machine.import "mmap", [Ptr, Word, I32, I32, I32, Word] => Ptr
Machine.import "__clear_cache", [Ptr, Ptr] => Void

PROT_READ_WRITE = 3
PROT_READ_WRITE_EXEC = 7
# MAP_PRIVATE | MAP_ANONYMOUS.
MAP_ANON_PRIVATE = 34
# dlsym's handle for every image this process has loaded.
RTLD_DEFAULT = 0

# A static binary sits low, where no mapping lands unasked, and the JIT
# reaches the program's data with adrp, which spans 4 GiB. So a mapping
# with no hint of its own goes 1 GiB above the program, past room for its
# heap, and each takes the address after the one before. MAP_FIXED_NOREPLACE
# takes the address only when nothing holds it; else the kernel picks.
MAP_FIXED_NOREPLACE = 1048576
JIT_GAP = 1073741824
PAGE_MASK = 0 - 4096

# A mapping of `size` bytes, near `hint` when it can be.
sig [Value, Value, Value] => Value
machine def zr_os_jit_map(size, exec, hint)
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
  at = mmap(Machine.ptr(want), bytes, Machine.i32(prot), Machine.i32(MAP_ANON_PRIVATE | MAP_FIXED_NOREPLACE), Machine.i32(0 - 1), 0)
  if Machine.word(at) == 0 - 1
    at = mmap(Machine.ptr(0), bytes, Machine.i32(prot), Machine.i32(MAP_ANON_PRIVATE), Machine.i32(0 - 1), 0)
  end
  if Machine.word(at) == 0 || Machine.word(at) == 0 - 1
    return Machine.value(QNIL)
  end
  Machine.store64(cursor, 0, Machine.word(at) + bytes)
  zr_fix(Machine.word(at))
end

# The program's own symbol table. musl's dlsym finds nothing in a
# static binary, but the binary keeps its ELF .symtab (a program that
# evals is linked whole), and a non-PIE link puts every symbol at its own
# value. So /proc/self/exe is mapped once, and its section headers name
# the table: the cell holds the table's first row, the row count and the
# string table, or the row count -1 where the binary cannot be read.
ELF_SHOFF = 40
ELF_SHENTSIZE = 58
ELF_SHNUM = 60
SHT_SYMTAB = 2
SYM_LEN = 24
PROT_READ = 1
MAP_PRIVATE = 2
SEEK_END = 2

sig [] => Ptr
machine def zr_linux_symtab
  cell = Machine.static(:linux_symtab, 24)
  if Machine.load64(cell, 8) != 0
    return cell
  end
  Machine.store64(cell, 8, 0 - 1)
  fd = zr_os_open(Machine.bytes("/proc/self/exe\0"), Machine.i32(O_CLOEXEC))
  if fd < Machine.i32(0)
    return cell
  end
  size = lseek(fd, 0, Machine.i32(SEEK_END))
  image = mmap(0, size, Machine.i32(PROT_READ), Machine.i32(MAP_PRIVATE), fd, 0)
  close(fd)
  if Machine.word(image) == 0 - 1
    return cell
  end
  headers = image + Machine.load64(image, ELF_SHOFF)
  width = Machine.word(Machine.load32(image, ELF_SHENTSIZE)) & 65535
  count = Machine.word(Machine.load32(image, ELF_SHNUM)) & 65535
  i = 0
  while i < count
    header = headers + (i * width)
    if Machine.word(Machine.load32(header, 4)) == SHT_SYMTAB
      strings = headers + (Machine.word(Machine.load32(header, 40)) * width)
      Machine.store64(cell, 0, Machine.word(image) + Machine.load64(header, 24))
      Machine.store64(cell, 16, Machine.word(image) + Machine.load64(strings, 24))
      Machine.store64(cell, 8, Machine.load64(header, 32) / SYM_LEN)
    end
    i += 1
  end
  cell
end

# The address a name already in this process answers to, or nil: a
# defined global or weak symbol of that name.
sig [Value] => Value
machine def zr_os_symbol(name)
  cell = zr_linux_symtab()
  rows = Machine.load64(cell, 8)
  if rows == 0 - 1
    return zr_notimplement(Machine.bytes("dlsym"), 5)
  end
  table = Machine.ptr(Machine.load64(cell, 0))
  strings = Machine.ptr(Machine.load64(cell, 16))
  want = RString.ptr(name)
  len = RString.len(name)
  i = 0
  while i < rows
    row = table + (i * SYM_LEN)
    # st_info's binding in its high nibble, then st_other, then the
    # section index, which is 0 for a name defined elsewhere.
    info = Machine.word(Machine.load32(row, 4))
    bind = (info & 255) >> 4
    shown = strings + Machine.word(Machine.load32(row, 0))
    if (bind == 1 || bind == 2) && (info >> 16) != 0 && zr_bytes_eq(shown, len, want, len) && Machine.load8(shown + len, 0) == Machine.i8(0)
      return zr_fix(Machine.load64(row, 8))
    end
    i += 1
  end
  Machine.value(QNIL)
end

# The write into the code mapping, and the instruction cache told what
# moved.
sig [Value, Value] => Value
machine def zr_os_jit_write(at, bytes)
  to = Machine.ptr(zr_fix2long(at))
  len = RString.len(bytes)
  zr_memcpy(to, RString.ptr(bytes), len)
  __clear_cache(to, to + len)
  Machine.value(QNIL)
end

# libffi's shared image, which dlopen cannot open in a static binary: the
# ffi gem's first call answers dlopen's refusal.
sig [] => Ptr
machine def zr_os_libffi_path
  Machine.bytes("libffi.so.8\0")
end
