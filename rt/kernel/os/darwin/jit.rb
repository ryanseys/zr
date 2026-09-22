# darwin's half of loading code into this process: MAP_JIT mappings,
# the write-protect flip each write to one needs, and dlsym over every
# loaded image.
Machine.import "dlsym", [Ptr, Ptr] => Ptr
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

# The address a name already in this process answers to, or nil.
sig [Value] => Value
machine def zr_os_symbol(name)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_str(b, name)
  zr_buf_byte(b, 0)
  at = dlsym(Machine.ptr(RTLD_DEFAULT), Buf.ptr(b))
  zr_buf_free(b)
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
