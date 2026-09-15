# darwin's half of loading code into this process: MAP_JIT mappings,
# the write-protect flip each write to one needs, and dlsym over every
# loaded image.
Machine.import "dlsym", [Ptr, Ptr] => Ptr
Machine.import "mmap", [Ptr, Word, I32, I32, I32, Word] => Ptr
Machine.import "pthread_jit_write_protect_np", [I32] => Void
Machine.import "sys_icache_invalidate", [Ptr, Word] => Void

PROT_READ_WRITE = 3
PROT_READ_WRITE_EXEC = 7
# MAP_PRIVATE | MAP_ANON, and MAP_JIT for a mapping that holds code.
MAP_ANON_PRIVATE = 4098
MAP_JIT = 2048
# dlsym's handle for every image this process has loaded.
RTLD_DEFAULT = 0 - 2

# A mapping of `size` bytes, near `hint` when it can be. Code needs
# MAP_JIT, which costs a write-protect flip on every write.
sig [Value, Value, Value] => Value
machine def zr_os_jit_map(size, exec, hint)
  prot = PROT_READ_WRITE
  flags = MAP_ANON_PRIVATE
  if exec != QFALSE && exec != QNIL
    prot = PROT_READ_WRITE_EXEC
    flags = MAP_ANON_PRIVATE + MAP_JIT
  end
  at = mmap(Machine.ptr(zr_fix2long(hint)), zr_fix2long(size), Machine.i32(prot), Machine.i32(flags), Machine.i32(0 - 1), 0)
  if Machine.word(at) == 0 || Machine.word(at) == 0 - 1
    return Machine.value(QNIL)
  end
  zr_fix(Machine.word(at))
end

# The address a name already in this process answers to, or nil.
sig [Value] => Value
machine def zr_os_symbol(name)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_str(b, name)
  zr_buf_byte(b, 0)
  at = dlsym(Machine.ptr(RTLD_DEFAULT), Buf.ptr(b))
  free(Buf.ptr(b))
  if Machine.word(at) == 0
    return Machine.value(QNIL)
  end
  zr_fix(Machine.word(at))
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
