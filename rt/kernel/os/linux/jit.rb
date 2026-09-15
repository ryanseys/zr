# Linux's half of loading code into this process: plain executable
# mappings, and the instruction cache flushed after each write. A static
# binary has no dynamic symbol table, so no name in it can be looked up.
Machine.import "mmap", [Ptr, Word, I32, I32, I32, Word] => Ptr
Machine.import "__clear_cache", [Ptr, Ptr] => Void

PROT_READ_WRITE = 3
PROT_READ_WRITE_EXEC = 7
# MAP_PRIVATE | MAP_ANONYMOUS.
MAP_ANON_PRIVATE = 34
# dlsym's handle for every image this process has loaded.
RTLD_DEFAULT = 0

# A mapping of `size` bytes, near `hint` when it can be.
sig [Value, Value, Value] => Value
machine def zr_os_jit_map(size, exec, hint)
  prot = PROT_READ_WRITE
  if exec != QFALSE && exec != QNIL
    prot = PROT_READ_WRITE_EXEC
  end
  at = mmap(Machine.ptr(zr_fix2long(hint)), zr_fix2long(size), Machine.i32(prot), Machine.i32(MAP_ANON_PRIVATE), Machine.i32(0 - 1), 0)
  if Machine.word(at) == 0 || Machine.word(at) == 0 - 1
    return Machine.value(QNIL)
  end
  zr_fix(Machine.word(at))
end

# musl's dlsym in a static binary finds nothing, so the loader is refused
# by name before it would link against an address it does not have.
sig [Value] => Value
machine def zr_os_symbol(name)
  zr_notimplement(Machine.bytes("dlsym"), 5)
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
