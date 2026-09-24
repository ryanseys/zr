# The native part of the ffi gem, as ext/ffi_c gives it: raw memory by
# address, dlopen and dlsym, and libffi calls. libffi is in its own
# image. The process opens it the first time that a program needs it, so
# a program that never calls C has no reference to it. An address goes
# across as an Integer. The bytes at an address go across as a binary
# String, which runtime/ext/ffi_c packs and unpacks.
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
Machine.sig :c_words, [Word, Word, Word, Word, Word, Word, Word, Word] => Word
Machine.sig :c_words_f64, [Word, Word, Word, Word, Word, Word, Word, F64] => Word

RTLD_LAZY = 1
# The callable that a closure runs, and the pending unwind that a
# callback left. The pending unwind waits until the C call that ran the
# callback returns.
G_FFI_CALLBACK = 58
G_FFI_UNWIND = 59
# The callable that the callback entries below run.
G_C_CALLBACK = 62
# sizeof(ffi_closure) on arm64.
FFI_CLOSURE_SIZE = 40

# Converts an address from runtime/ext/ffi_c: an Integer that fits a
# machine word.
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

# libffi's image. The process opens it only one time.
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

# Returns `len` bytes at `addr` as a binary String.
sig [Value, Value] => Value
machine def zr_ffi_read(addr, len)
  zr_str_set_index(zr_str_new(zr_ffi_ptr(addr), zr_fix2long(len)), ENC_BINARY)
end

# Writes `len` bytes of `str`, starting at `from`, to `addr`.
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

# Returns the number of bytes at `addr` before a NUL, and reads no more
# than `max` bytes. Returns `max` if there is no NUL. With a nil `max`,
# there is no limit.
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

# Returns the address of a String's bytes, which end in a NUL. A C call
# can read them at this address while the String does not change. Every
# String has one byte after its length for that NUL.
sig [Value] => Ptr
machine def zr_ffi_cstr(str)
  # C can write through the address. Thus the scan results for the bytes
  # and a MatchData copy that shares them are no longer valid.
  RBasic.set_flags(str, RBasic.flags(str) & FL_SCANS_CLEAR)
  Machine.store8(RString.ptr(str) + RString.len(str), 0, Machine.i8(0))
  RString.ptr(str)
end

sig [Value] => Value
machine def zr_ffi_str_addr(str)
  zr_ffi_addr(zr_ffi_cstr(str))
end

# dlopen of a path, or of the process itself for nil. Returns the
# handle, or nil. On nil, zr_ffi_dlerror gets dlerror's text (a snprintf
# of NULL writes it as "(null)").
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

# Returns the address of `name` in the image that `handle` opened, or 0.
sig [Value, Value] => Value
machine def zr_ffi_dlsym(handle, name)
  zr_ffi_addr(dlsym(zr_ffi_ptr(handle), zr_ffi_cstr(name)))
end

# Returns one of libffi's type descriptions by its symbol, for example
# `ffi_type_sint32`.
sig [Value] => Value
machine def zr_ffi_type(name)
  zr_ffi_addr(dlsym(zr_ffi_image(), zr_ffi_cstr(name)))
end

# Calls ffi_prep_cif on the cif at `cif` and returns libffi's status.
# For a variadic function, it calls ffi_prep_cif_var, with `nfixed` of
# the `nargs` arguments fixed. A negative `nfixed` means that the
# function is not variadic.
sig [Value, Value, Value, Value, Value, Value] => Value
machine def zr_ffi_prep(cif, abi, nfixed, nargs, rtype, atypes)
  if zr_fix2long(nfixed) < 0
    plain = zr_ffi_fn(Machine.static(:ffi_prep_cif_fn, 8), Machine.bytes("ffi_prep_cif\0"))
    return zr_fix(Machine.sword(Machine.call(:ffi_prep_cif, plain, zr_ffi_ptr(cif), Machine.i32(zr_fix2long(abi)), Machine.i32(zr_fix2long(nargs)), zr_ffi_ptr(rtype), zr_ffi_ptr(atypes))))
  end
  fn = zr_ffi_fn(Machine.static(:ffi_prep_cif_var_fn, 8), Machine.bytes("ffi_prep_cif_var\0"))
  zr_fix(Machine.sword(Machine.call(:ffi_prep_cif_var, fn, zr_ffi_ptr(cif), Machine.i32(zr_fix2long(abi)), Machine.i32(zr_fix2long(nfixed)), Machine.i32(zr_fix2long(nargs)), zr_ffi_ptr(rtype), zr_ffi_ptr(atypes))))
end

# Calls ffi_call and returns errno as it was when the function returned.
# If a callback raised, threw or broke out while C ran, it left a
# pending unwind. The unwind continues from here, after C is done. A C
# call inside that callback keeps its own pending unwind.
sig [Value, Value, Value, Value] => Value
machine def zr_ffi_call(cif, fn, rvalue, avalues)
  outer = zr_global(G_FFI_UNWIND)
  zr_set_global(G_FFI_UNWIND, Machine.value(QNIL))
  call = zr_ffi_fn(Machine.static(:ffi_call_fn, 8), Machine.bytes("ffi_call\0"))
  Machine.call(:ffi_call, call, zr_ffi_ptr(cif), zr_ffi_ptr(fn), zr_ffi_ptr(rvalue), zr_ffi_ptr(avalues))
  errno = zr_errno()
  if zr_ffi_resume(outer)
    return Machine.value(QUNDEF)
  end
  zr_fix(errno)
end

# After a C call: returns true when a callback left a pending unwind,
# and makes it the task's pending unwind. It restores the caller's value
# of the unwind slot.
sig [Value] => Bool
machine def zr_ffi_resume(outer)
  left = zr_global(G_FFI_UNWIND)
  zr_set_global(G_FFI_UNWIND, outer)
  if zr_special_p(left)
    return false
  end
  t = zr_task()
  Task.set_pending(t, zr_ary_at(left, 0))
  Task.set_throw_tag(t, zr_ary_at(left, 1))
  Task.set_pending_kind(t, zr_fix2long(zr_ary_at(left, 2)))
  Task.set_pending_home(t, Machine.ptr(zr_fix2long(zr_ary_at(left, 3))))
  Task.set_pending_site(t, zr_fix2long(zr_ary_at(left, 4)))
  true
end

# Inside a callback: moves the task's pending unwind into the unwind
# slot. It cannot unwind through C frames, so it waits there until the C
# call returns.
sig [] => Void
machine def zr_ffi_park
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

# Sets errno for the next C call.
sig [Value] => Value
machine def zr_ffi_set_errno(n)
  zr_os_set_errno(zr_fix2long(n))
  Machine.value(QNIL)
end

# Sets the callable that every closure runs. Its arguments are the
# closure's id, the address of the return value and the address of the
# argument pointers.
sig [Value] => Value
machine def zr_ffi_callback_set(callable)
  zr_set_global(G_FFI_CALLBACK, callable)
  Machine.value(QNIL)
end

# Makes a closure for the cif at `cif`. Returns [closure, code, status]:
# the block to free, the address that C calls, and libffi's status.
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

# The function that C calls through a closure. A pending unwind from the
# callable cannot go back through C frames, so it waits for
# zr_ffi_call.
sig [Ptr, Ptr, Ptr, Ptr] => Void
machine def zr_ffi_closure_run(cif, ret, args, user)
  Machine.gates_enter
  argv = Machine.slot(24)
  Machine.store64(argv, 0, Machine.word(zr_fix(Machine.word(user))))
  Machine.store64(argv, 8, Machine.word(zr_ffi_addr(ret)))
  Machine.store64(argv, 16, Machine.word(zr_ffi_addr(args)))
  r = zr_send(zr_global(G_FFI_CALLBACK), Machine.id(:call), 3, argv)
  if r == QUNDEF
    zr_ffi_park()
  end
end

# A direct C call, for a library whose functions take only integer and
# pointer arguments. arm64 passes the first eight in x0-x7, so a function
# with fewer arguments ignores the rest. `args` is an Array of at most
# eight Integers in the signed 64-bit range. The result is x0 as a signed
# Integer, and the caller narrows it to the declared type. A variadic
# function cannot use this path, because arm64 darwin passes the variadic
# part on the stack. As with zr_ffi_call, a raise in a callback while C
# ran raises here.
sig [Value, Value] => Value
machine def zr_c_call(fn, args)
  zr_c_invoke(fn, args, Machine.ptr(0))
end

# zr_c_call that returns [result, errno], with errno as it was when C
# returned.
sig [Value, Value] => Value
machine def zr_c_call_errno(fn, args)
  errno = Machine.slot(8)
  r = zr_c_invoke(fn, args, errno)
  if r == QUNDEF
    return r
  end
  out = zr_ary_new(2)
  zr_ary_push(out, r)
  zr_ary_push(out, zr_fix(Machine.sword(Machine.load64(errno, 0))))
  out
end

# zr_c_call for a function with one floating-point argument, which goes
# in d0 at any position among the others. `f` is a Float, with at most
# seven words.
sig [Value, Value, Value] => Value
machine def zr_c_call_f64(fn, args, f)
  words = Machine.slot(64)
  zr_c_words(args, words)
  outer = zr_global(G_FFI_UNWIND)
  zr_set_global(G_FFI_UNWIND, Machine.value(QNIL))
  r = Machine.call(:c_words_f64, zr_ffi_ptr(fn), Machine.load64(words, 0), Machine.load64(words, 8), Machine.load64(words, 16), Machine.load64(words, 24), Machine.load64(words, 32), Machine.load64(words, 40), Machine.load64(words, 48), zr_float_value(f))
  if zr_ffi_resume(outer)
    return Machine.value(QUNDEF)
  end
  zr_int_from_word(r)
end

# Writes the eight words for x0-x7 from `args` into `words`, with zero
# after the end of `args`.
sig [Value, Ptr] => Void
machine def zr_c_words(args, words)
  n = RArray.len(args)
  i = 0
  while i < 8
    w = 0
    if i < n
      w = Machine.word(zr_ffi_ptr(zr_ary_at(args, i)))
    end
    Machine.store64(words + i * 8, 0, w)
    i = i + 1
  end
end

sig [Value, Value, Ptr] => Value
machine def zr_c_invoke(fn, args, errno)
  words = Machine.slot(64)
  zr_c_words(args, words)
  outer = zr_global(G_FFI_UNWIND)
  zr_set_global(G_FFI_UNWIND, Machine.value(QNIL))
  r = Machine.call(:c_words, zr_ffi_ptr(fn), Machine.load64(words, 0), Machine.load64(words, 8), Machine.load64(words, 16), Machine.load64(words, 24), Machine.load64(words, 32), Machine.load64(words, 40), Machine.load64(words, 48), Machine.load64(words, 56))
  if Machine.word(errno) != 0
    Machine.store64(errno, 0, Machine.word(zr_errno()))
  end
  if zr_ffi_resume(outer)
    return Machine.value(QUNDEF)
  end
  zr_int_from_word(r)
end

# Sets the callable that every callback entry runs. Its arguments are
# the entry's number and an Array of its seven arguments.
sig [Value] => Value
machine def zr_c_callback_set(callable)
  zr_set_global(G_C_CALLBACK, callable)
  Machine.value(QNIL)
end

# Returns the address of callback entry `k`. It is a C function with at
# most seven integer or pointer arguments. It returns the callable's
# result for `k` if it is an Integer, and 0 for any other value.
sig [Value] => Value
machine def zr_c_callback_addr(k)
  n = zr_fix2long(k)
  if n == 0
    return zr_ffi_addr(Machine.addr(:zr_c_callback_0))
  end
  if n == 1
    return zr_ffi_addr(Machine.addr(:zr_c_callback_1))
  end
  if n == 2
    return zr_ffi_addr(Machine.addr(:zr_c_callback_2))
  end
  if n == 3
    return zr_ffi_addr(Machine.addr(:zr_c_callback_3))
  end
  if n == 4
    return zr_ffi_addr(Machine.addr(:zr_c_callback_4))
  end
  if n == 5
    return zr_ffi_addr(Machine.addr(:zr_c_callback_5))
  end
  if n == 6
    return zr_ffi_addr(Machine.addr(:zr_c_callback_6))
  end
  if n == 7
    return zr_ffi_addr(Machine.addr(:zr_c_callback_7))
  end
  if n == 8
    return zr_ffi_addr(Machine.addr(:zr_c_callback_8))
  end
  if n == 9
    return zr_ffi_addr(Machine.addr(:zr_c_callback_9))
  end
  if n == 10
    return zr_ffi_addr(Machine.addr(:zr_c_callback_10))
  end
  if n == 11
    return zr_ffi_addr(Machine.addr(:zr_c_callback_11))
  end
  if n == 12
    return zr_ffi_addr(Machine.addr(:zr_c_callback_12))
  end
  if n == 13
    return zr_ffi_addr(Machine.addr(:zr_c_callback_13))
  end
  if n == 14
    return zr_ffi_addr(Machine.addr(:zr_c_callback_14))
  end
  if n == 15
    return zr_ffi_addr(Machine.addr(:zr_c_callback_15))
  end
  if n == 16
    return zr_ffi_addr(Machine.addr(:zr_c_callback_16))
  end
  if n == 17
    return zr_ffi_addr(Machine.addr(:zr_c_callback_17))
  end
  if n == 18
    return zr_ffi_addr(Machine.addr(:zr_c_callback_18))
  end
  if n == 19
    return zr_ffi_addr(Machine.addr(:zr_c_callback_19))
  end
  if n == 20
    return zr_ffi_addr(Machine.addr(:zr_c_callback_20))
  end
  if n == 21
    return zr_ffi_addr(Machine.addr(:zr_c_callback_21))
  end
  if n == 22
    return zr_ffi_addr(Machine.addr(:zr_c_callback_22))
  end
  if n == 23
    return zr_ffi_addr(Machine.addr(:zr_c_callback_23))
  end
  if n == 24
    return zr_ffi_addr(Machine.addr(:zr_c_callback_24))
  end
  if n == 25
    return zr_ffi_addr(Machine.addr(:zr_c_callback_25))
  end
  if n == 26
    return zr_ffi_addr(Machine.addr(:zr_c_callback_26))
  end
  if n == 27
    return zr_ffi_addr(Machine.addr(:zr_c_callback_27))
  end
  if n == 28
    return zr_ffi_addr(Machine.addr(:zr_c_callback_28))
  end
  if n == 29
    return zr_ffi_addr(Machine.addr(:zr_c_callback_29))
  end
  if n == 30
    return zr_ffi_addr(Machine.addr(:zr_c_callback_30))
  end
  if n == 31
    return zr_ffi_addr(Machine.addr(:zr_c_callback_31))
  end
  Machine.value(QNIL)
end

sig [Word, Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback(k, a, b, c, d, e, f, g)
  Machine.gates_enter
  argv = Machine.slot(16)
  Machine.store64(argv, 0, Machine.word(zr_fix(k)))
  words = zr_ary_new(7)
  Machine.store64(argv, 8, Machine.word(words))
  zr_ary_push(words, zr_int_from_word(a))
  zr_ary_push(words, zr_int_from_word(b))
  zr_ary_push(words, zr_int_from_word(c))
  zr_ary_push(words, zr_int_from_word(d))
  zr_ary_push(words, zr_int_from_word(e))
  zr_ary_push(words, zr_int_from_word(f))
  zr_ary_push(words, zr_int_from_word(g))
  r = zr_send(zr_global(G_C_CALLBACK), Machine.id(:call), 2, argv)
  if r == QUNDEF
    zr_ffi_park()
    return 0
  end
  if zr_fixnum_p(r) || zr_big_p(r)
    return Machine.word(zr_ffi_ptr(r))
  end
  0
end

# The callback entries that C calls. There are thirty-two functions,
# which is the maximum number that a library port uses at one time. Each
# entry represents one C function.
sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_0(a, b, c, d, e, f, g)
  zr_c_callback(0, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_1(a, b, c, d, e, f, g)
  zr_c_callback(1, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_2(a, b, c, d, e, f, g)
  zr_c_callback(2, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_3(a, b, c, d, e, f, g)
  zr_c_callback(3, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_4(a, b, c, d, e, f, g)
  zr_c_callback(4, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_5(a, b, c, d, e, f, g)
  zr_c_callback(5, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_6(a, b, c, d, e, f, g)
  zr_c_callback(6, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_7(a, b, c, d, e, f, g)
  zr_c_callback(7, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_8(a, b, c, d, e, f, g)
  zr_c_callback(8, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_9(a, b, c, d, e, f, g)
  zr_c_callback(9, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_10(a, b, c, d, e, f, g)
  zr_c_callback(10, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_11(a, b, c, d, e, f, g)
  zr_c_callback(11, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_12(a, b, c, d, e, f, g)
  zr_c_callback(12, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_13(a, b, c, d, e, f, g)
  zr_c_callback(13, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_14(a, b, c, d, e, f, g)
  zr_c_callback(14, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_15(a, b, c, d, e, f, g)
  zr_c_callback(15, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_16(a, b, c, d, e, f, g)
  zr_c_callback(16, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_17(a, b, c, d, e, f, g)
  zr_c_callback(17, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_18(a, b, c, d, e, f, g)
  zr_c_callback(18, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_19(a, b, c, d, e, f, g)
  zr_c_callback(19, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_20(a, b, c, d, e, f, g)
  zr_c_callback(20, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_21(a, b, c, d, e, f, g)
  zr_c_callback(21, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_22(a, b, c, d, e, f, g)
  zr_c_callback(22, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_23(a, b, c, d, e, f, g)
  zr_c_callback(23, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_24(a, b, c, d, e, f, g)
  zr_c_callback(24, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_25(a, b, c, d, e, f, g)
  zr_c_callback(25, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_26(a, b, c, d, e, f, g)
  zr_c_callback(26, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_27(a, b, c, d, e, f, g)
  zr_c_callback(27, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_28(a, b, c, d, e, f, g)
  zr_c_callback(28, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_29(a, b, c, d, e, f, g)
  zr_c_callback(29, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_30(a, b, c, d, e, f, g)
  zr_c_callback(30, a, b, c, d, e, f, g)
end

sig [Word, Word, Word, Word, Word, Word, Word] => Word
machine def zr_c_callback_31(a, b, c, d, e, f, g)
  zr_c_callback(31, a, b, c, d, e, f, g)
end
