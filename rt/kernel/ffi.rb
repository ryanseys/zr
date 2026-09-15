# The ffi gem's native reach, as ext/ffi_c makes it: raw memory by
# address, dlopen and dlsym, and libffi's calls. libffi lives in its own
# image, which the process opens the first time a program asks for it,
# so a program that never calls C carries no reference to it. An address
# crosses as an Integer; the bytes behind it cross as a binary String,
# which rt/ext/ffi_c packs and unpacks.
Machine.import "dlopen", [Ptr, I32] => Ptr
Machine.import "dlsym", [Ptr, Ptr] => Ptr
Machine.import "dlerror", [] => Ptr
Machine.import "memchr", [Ptr, I32, Word] => Ptr

Machine.sig :ffi_prep_cif, [Ptr, I32, I32, Ptr, Ptr] => I32
Machine.sig :ffi_prep_cif_var, [Ptr, I32, I32, I32, Ptr, Ptr] => I32
Machine.sig :ffi_call, [Ptr, Ptr, Ptr, Ptr] => Void
Machine.sig :ffi_closure_alloc, [Word, Ptr] => Ptr
Machine.sig :ffi_prep_closure_loc, [Ptr, Ptr, Ptr, Ptr, Ptr] => I32
Machine.sig :ffi_closure_free, [Ptr] => Void

RTLD_LAZY = 1
# The callable a closure runs, and what a callback left unfinished: the
# signal it raised, held until the C call that ran it returns.
G_FFI_CALLBACK = 58
G_FFI_UNWIND = 59
# sizeof(ffi_closure) on arm64.
FFI_CLOSURE_SIZE = 40

# An address from rt/ext/ffi_c: an Integer a machine word holds.
sig [Value] => Ptr
machine def zr_ffi_ptr(addr)
  if zr_fixnum_p(addr)
    return Machine.ptr(zr_fix2long(addr))
  end
  out = Machine.slot(8)
  zr_big_to_long(addr, out)
  Machine.ptr(Machine.load64(out, 0))
end

sig [Ptr] => Value
machine def zr_ffi_addr(p)
  zr_int_from_word(Machine.word(p))
end

# libffi's image, opened once.
sig [] => Ptr
machine def zr_ffi_image
  cell = Machine.static(:ffi_image, 8)
  if Machine.load64(cell, 0) == 0
    Machine.store64(cell, 0, Machine.word(dlopen(zr_os_libffi_path(), Machine.i32(RTLD_LAZY))))
  end
  Machine.ptr(Machine.load64(cell, 0))
end

sig [Ptr, Ptr] => Ptr
machine def zr_ffi_fn(cell, name)
  if Machine.load64(cell, 0) == 0
    Machine.store64(cell, 0, Machine.word(dlsym(zr_ffi_image(), name)))
  end
  Machine.ptr(Machine.load64(cell, 0))
end

# The bytes at `addr`, `len` of them, in binary.
sig [Value, Value] => Value
machine def zr_ffi_read(addr, len)
  zr_str_set_index(zr_str_new(zr_ffi_ptr(addr), zr_fix2long(len)), ENC_BINARY)
end

# `len` bytes of `str` from `from` written at `addr`.
sig [Value, Value, Value, Value] => Value
machine def zr_ffi_write(addr, str, from, len)
  zr_memcpy(zr_ffi_ptr(addr), RString.ptr(str) + zr_fix2long(from), zr_fix2long(len))
  Machine.value(QNIL)
end

sig [Value, Value, Value] => Value
machine def zr_ffi_fill(addr, byte, len)
  memset(zr_ffi_ptr(addr), Machine.i32(zr_fix2long(byte)), zr_fix2long(len))
  Machine.value(QNIL)
end

sig [Value, Value, Value] => Value
machine def zr_ffi_copy(to, from, len)
  zr_memcpy(zr_ffi_ptr(to), zr_ffi_ptr(from), zr_fix2long(len))
  Machine.value(QNIL)
end

# How many bytes at `addr` come before a NUL, looking at no more than
# `max`: `max` itself when none does. A nil `max` looks as far as it
# takes.
sig [Value, Value] => Value
machine def zr_ffi_strlen(addr, max)
  p = zr_ffi_ptr(addr)
  if max == QNIL
    return zr_fix(zr_cstr_len(p))
  end
  n = zr_fix2long(max)
  if n <= 0
    return zr_fix(0)
  end
  at = memchr(p, Machine.i32(0), n)
  if Machine.word(at) == 0
    return zr_fix(n)
  end
  zr_fix(at - p)
end

# Where a String keeps its bytes, which end in a NUL: the address a C
# call reads them at while the String stays as it is. Every String holds
# a byte past its length for that NUL.
sig [Value] => Ptr
machine def zr_ffi_cstr(str)
  Machine.store8(RString.ptr(str) + RString.len(str), 0, Machine.i8(0))
  RString.ptr(str)
end

sig [Value] => Value
machine def zr_ffi_str_addr(str)
  zr_ffi_addr(zr_ffi_cstr(str))
end

# dlopen of a path, or of the process itself for nil: the handle, or
# nil with dlerror's text left for zr_ffi_dlerror, which a snprintf of
# NULL writes as (null).
sig [Value, Value] => Value
machine def zr_ffi_dlopen(name, flags)
  path = Machine.ptr(0)
  if name != QNIL
    path = zr_ffi_cstr(name)
  end
  handle = dlopen(path, Machine.i32(zr_fix2long(flags)))
  if Machine.word(handle) == 0
    return Machine.value(QNIL)
  end
  zr_ffi_addr(handle)
end

sig [] => Value
machine def zr_ffi_dlerror
  text = dlerror()
  if Machine.word(text) == 0
    text = Machine.bytes("(null)\0")
  end
  zr_str_set_index(zr_str_new(text, zr_cstr_len(text)), ENC_BINARY)
end

# The address `name` has in the image `handle` opened, or 0.
sig [Value, Value] => Value
machine def zr_ffi_dlsym(handle, name)
  zr_ffi_addr(dlsym(zr_ffi_ptr(handle), zr_ffi_cstr(name)))
end

# One of libffi's own type descriptions, by its symbol: `ffi_type_sint32`.
sig [Value] => Value
machine def zr_ffi_type(name)
  zr_ffi_addr(dlsym(zr_ffi_image(), zr_ffi_cstr(name)))
end

# ffi_prep_cif into the cif at `cif`, the status libffi answers; for a
# variadic function ffi_prep_cif_var, with `nfixed` of the `nargs`
# arguments fixed. A negative `nfixed` says the function is not variadic.
sig [Value, Value, Value, Value, Value, Value] => Value
machine def zr_ffi_prep(cif, abi, nfixed, nargs, rtype, atypes)
  if zr_fix2long(nfixed) < 0
    plain = zr_ffi_fn(Machine.static(:ffi_prep_cif_fn, 8), Machine.bytes("ffi_prep_cif\0"))
    return zr_fix(Machine.sword(Machine.call(:ffi_prep_cif, plain, zr_ffi_ptr(cif), Machine.i32(zr_fix2long(abi)), Machine.i32(zr_fix2long(nargs)), zr_ffi_ptr(rtype), zr_ffi_ptr(atypes))))
  end
  fn = zr_ffi_fn(Machine.static(:ffi_prep_cif_var_fn, 8), Machine.bytes("ffi_prep_cif_var\0"))
  zr_fix(Machine.sword(Machine.call(:ffi_prep_cif_var, fn, zr_ffi_ptr(cif), Machine.i32(zr_fix2long(abi)), Machine.i32(zr_fix2long(nfixed)), Machine.i32(zr_fix2long(nargs)), zr_ffi_ptr(rtype), zr_ffi_ptr(atypes))))
end

# ffi_call, answering errno as it stood when the function returned. A
# callback that raised, threw or broke out while C ran left its signal
# behind, and it goes on from here, once C is done; a call made inside
# that callback keeps its own.
sig [Value, Value, Value, Value] => Value
machine def zr_ffi_call(cif, fn, rvalue, avalues)
  outer = zr_global(G_FFI_UNWIND)
  zr_set_global(G_FFI_UNWIND, Machine.value(QNIL))
  call = zr_ffi_fn(Machine.static(:ffi_call_fn, 8), Machine.bytes("ffi_call\0"))
  Machine.call(:ffi_call, call, zr_ffi_ptr(cif), zr_ffi_ptr(fn), zr_ffi_ptr(rvalue), zr_ffi_ptr(avalues))
  errno = zr_errno()
  left = zr_global(G_FFI_UNWIND)
  zr_set_global(G_FFI_UNWIND, outer)
  if !zr_special_p(left)
    t = zr_task()
    Task.set_pending(t, zr_ary_at(left, 0))
    Task.set_throw_tag(t, zr_ary_at(left, 1))
    Task.set_pending_kind(t, zr_fix2long(zr_ary_at(left, 2)))
    Task.set_pending_home(t, Machine.ptr(zr_fix2long(zr_ary_at(left, 3))))
    Task.set_pending_site(t, zr_fix2long(zr_ary_at(left, 4)))
    return Machine.value(QUNDEF)
  end
  zr_fix(errno)
end

# errno as a C call finds it.
sig [Value] => Value
machine def zr_ffi_set_errno(n)
  zr_os_set_errno(zr_fix2long(n))
  Machine.value(QNIL)
end

# The callable every closure runs: called with the closure's id, the
# address of the return value and the address of the argument pointers.
sig [Value] => Value
machine def zr_ffi_callback_set(callable)
  zr_set_global(G_FFI_CALLBACK, callable)
  Machine.value(QNIL)
end

# A closure over the cif at `cif`: [closure, code], the block to free and
# the address C calls.
sig [Value, Value] => Value
machine def zr_ffi_closure(cif, id)
  code = Machine.slot(8)
  alloc = zr_ffi_fn(Machine.static(:ffi_closure_alloc_fn, 8), Machine.bytes("ffi_closure_alloc\0"))
  closure = Machine.call(:ffi_closure_alloc, alloc, FFI_CLOSURE_SIZE, code)
  if Machine.word(closure) == 0
    return Machine.value(QNIL)
  end
  prep = zr_ffi_fn(Machine.static(:ffi_prep_closure_loc_fn, 8), Machine.bytes("ffi_prep_closure_loc\0"))
  status = Machine.call(:ffi_prep_closure_loc, prep, closure, zr_ffi_ptr(cif), Machine.addr(:zr_ffi_closure_run), Machine.ptr(zr_fix2long(id)), Machine.ptr(Machine.load64(code, 0)))
  out = zr_ary_new(3)
  zr_ary_push(out, zr_ffi_addr(closure))
  zr_ary_push(out, zr_int_from_word(Machine.load64(code, 0)))
  zr_ary_push(out, zr_fix(Machine.sword(status)))
  out
end

sig [Value] => Value
machine def zr_ffi_closure_free(closure)
  free_fn = zr_ffi_fn(Machine.static(:ffi_closure_free_fn, 8), Machine.bytes("ffi_closure_free\0"))
  Machine.call(:ffi_closure_free, free_fn, zr_ffi_ptr(closure))
  Machine.value(QNIL)
end

# What C calls through a closure. An unwind the callable leaves has no
# way back through C's frames, so it waits for zr_ffi_call.
sig [Ptr, Ptr, Ptr, Ptr] => Void
machine def zr_ffi_closure_run(cif, ret, args, user)
  argv = Machine.slot(24)
  Machine.store64(argv, 0, Machine.word(zr_fix(Machine.word(user))))
  Machine.store64(argv, 8, Machine.word(zr_ffi_addr(ret)))
  Machine.store64(argv, 16, Machine.word(zr_ffi_addr(args)))
  r = zr_send(zr_global(G_FFI_CALLBACK), Machine.id(:call), 3, argv)
  if r == QUNDEF
    t = zr_task()
    left = zr_ary_new(5)
    zr_ary_push(left, Task.pending(t))
    zr_ary_push(left, Task.throw_tag(t))
    zr_ary_push(left, zr_fix(Task.pending_kind(t)))
    zr_ary_push(left, zr_fix(Machine.word(Task.pending_home(t))))
    zr_ary_push(left, zr_fix(Task.pending_site(t)))
    Task.set_pending(t, Machine.value(QNIL))
    Task.set_throw_tag(t, Machine.value(QNIL))
    zr_set_global(G_FFI_UNWIND, left)
  end
end
