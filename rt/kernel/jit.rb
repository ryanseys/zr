# Machine code into this process, for an eval. The loader in `Obj::JIT`
# does the layout and the relocations; these are the system calls it
# stands on, and they are the same ones it makes through Fiddle when the
# compiler runs under CRuby.

Machine.import "dlsym", [Ptr, Ptr] => Ptr
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
machine def zr_jit_map(size, exec, hint)
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
machine def zr_jit_symbol(name)
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

sig [Value, Value] => Value
machine def zr_jit_write_data(at, bytes)
  zr_memcpy(Machine.ptr(zr_fix2long(at)), RString.ptr(bytes), RString.len(bytes))
  Machine.value(QNIL)
end

# The same write into the code mapping: unprotected, copied, protected
# again, and the instruction cache told what moved.
sig [Value, Value] => Value
machine def zr_jit_write_code(at, bytes)
  to = Machine.ptr(zr_fix2long(at))
  len = RString.len(bytes)
  pthread_jit_write_protect_np(Machine.i32(0))
  zr_memcpy(to, RString.ptr(bytes), len)
  pthread_jit_write_protect_np(Machine.i32(1))
  sys_icache_invalidate(to, len)
  Machine.value(QNIL)
end

# A loaded function called for the raw word it answers, which is what a
# loader shows of code it has just written.
sig [Value] => Value
machine def zr_jit_call(at)
  zr_fix(Machine.word(Machine.call(:top, Machine.ptr(zr_fix2long(at)))))
end

# An eval's toplevel takes the self and the cref it runs under.
Machine.sig :eval, [Value, Value] => Value

# The frame that asked for an eval. The compiler is reached from a
# method of the runtime's own, whose frame is on top, so the frame
# outside it is the one that wrote the call.
sig [] => Ptr
machine def zr_eval_caller
  Frame.prev(Task.top(zr_task()))
end

sig [] => Value
machine def zr_eval_self
  Frame.self(zr_eval_caller())
end

sig [] => Value
machine def zr_eval_cref
  Frame.cref(zr_eval_caller())
end

# `(eval at file:line)`: the name ruby gives an eval that names no file.
sig [] => Value
machine def zr_eval_source_name
  rec = zr_frame_with_file(zr_eval_caller())
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("(eval at "), 9)
  if rec != 0
    zr_buf_push(b, FrameMeta.file(Frame.meta(rec)), FrameMeta.file_len(Frame.meta(rec)))
    zr_buf_byte(b, 58)
    zr_buf_long(b, Frame.line(rec))
  end
  zr_buf_byte(b, 41)
  zr_buf_take(b)
end

# A cref an eval on a string runs under: the module alone, which is a
# lexical scope of its own, so `Module.nesting` there is `[mod]`.
sig [Value] => Value
machine def zr_eval_cref_of(mod)
  zr_cref_push(mod, zr_global(G_TOP_CREF))
end

# A loaded eval toplevel, run under `self_` with `cref` for its defs and
# its constants. `code` is the pair the compiler answers: the function
# and its FrameMeta, whose parent is written here so a backtrace row
# shows the label of the frame that asked.
sig [Value, Value, Value] => Value
machine def zr_eval_run(code, self_, cref)
  at = Machine.ptr(zr_fix2long(Machine.value(Machine.load64(RArray.ptr(code), 0))))
  meta = Machine.ptr(zr_fix2long(Machine.value(Machine.load64(RArray.ptr(code), 8))))
  FrameMeta.set_parent(meta, Frame.meta(zr_eval_caller()))
  Machine.call(:eval, at, self_, cref)
end
