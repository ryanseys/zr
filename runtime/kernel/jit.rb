# Machine code into this process, for an eval. The loader in `Obj::JIT`
# does the layout and the relocations; the system calls it stands on are
# `zr_os_jit_map`, `zr_os_jit_write` and `zr_os_symbol`, the same ones
# it makes through Fiddle when the compiler runs under CRuby.

sig [Value, Value] => Value
machine def zr_jit_write_data(at, bytes)
  zr_memcpy(Machine.ptr(zr_fix2long(at)), RString.ptr(bytes), RString.len(bytes))
  Machine.value(QNIL)
end

# A loaded function called for the raw word it answers, which is what a
# loader shows of code it has just written.
sig [Value] => Value
machine def zr_jit_call(at)
  zr_fix(Machine.word(Machine.call(:top, Machine.ptr(zr_fix2long(at)))))
end

# An eval's toplevel takes the self and the cref it runs under, the Env
# it keeps its locals in, and the block of the scope it runs in.
Machine.sig :eval, [Value, Value, Value, Value] => Value

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
# its constants, over `env` for its own locals, with `blk` for a `yield`.
# The FrameMeta's parent is written here so a backtrace row shows the
# label of the frame that asked.
sig [Value, Value, Value, Value, Value] => Value
machine def zr_eval_at(code, self_, cref, env, blk)
  FrameMeta.set_parent(Machine.ptr(zr_code_word(code, 1)), Frame.meta(zr_eval_frame()))
  Machine.call(:eval, Machine.ptr(zr_code_word(code, 0)), self_, cref, env, blk)
end

sig [Value, Value, Value, Value, Value] => Value
machine def zr_eval_run(code, self_, cref, parent, blk)
  zr_eval_at(code, self_, cref, zr_code_env(code, parent), blk)
end
