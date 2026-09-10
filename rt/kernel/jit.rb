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
Machine.sig :eval, [Value, Value, Value] => Value

# The four words the compiler answers for a string: the toplevel, its
# FrameMeta, and the size and names of the Env it runs its own locals in.
sig [Value, Word] => Word
machine def zr_code_word(code, i)
  zr_fix2long(Machine.value(Machine.load64(RArray.ptr(code) + (i * 8), 0)))
end

# The Env an eval keeps its own locals in, one scope inside `parent`.
sig [Value, Value] => Value
machine def zr_code_env(code, parent)
  zr_env_new(parent, zr_code_word(code, 2), Machine.ptr(zr_code_word(code, 3)))
end

# A loaded eval toplevel, run under `self_` with `cref` for its defs and
# its constants, over `env` for its own locals. The FrameMeta's parent is
# written here so a backtrace row shows the label of the frame that
# asked.
sig [Value, Value, Value, Value] => Value
machine def zr_eval_at(code, self_, cref, env)
  FrameMeta.set_parent(Machine.ptr(zr_code_word(code, 1)), Frame.meta(zr_caller_frame()))
  Machine.call(:eval, Machine.ptr(zr_code_word(code, 0)), self_, cref, env)
end

sig [Value, Value, Value, Value] => Value
machine def zr_eval_run(code, self_, cref, parent)
  zr_eval_at(code, self_, cref, zr_code_env(code, parent))
end
