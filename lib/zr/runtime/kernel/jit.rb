# Loads machine code into this process, for an eval. The loader in
# `Obj::JIT` does the layout and the relocations. It uses the system
# calls `zr_os_jit_map`, `zr_os_jit_write` and `zr_os_symbol`. Under
# CRuby, the compiler makes the same calls through Fiddle.

module Zr::Kern
  #: (value, value) -> value
  def zr_jit_write_data(at, bytes)
    zr_memcpy(Machine.ptr(zr_fix2long(at)), RString[bytes].ptr, RString[bytes].len)
    Machine.value(QNIL)
  end

  # Calls a loaded function and returns its raw word. A loader uses this
  # to test code that it wrote.
  #: (value) -> value
  def zr_jit_call(at)
    zr_fix(Machine.word(Top.call(Machine.ptr(zr_fix2long(at)))))
  end

  # The arguments of an eval's toplevel: its self and cref, the Env for its
  # locals, and the block of the scope that it runs in.
  module Eval
    #: (ptr, value, value, value, value) -> value
    def self.call(fn, v1, v2, v3, v4) = Machine.indirect
  end

  # The four words that the compiler returns for a string: the toplevel,
  # its FrameMeta, and the size and names of the Env for its own locals.
  #: (value, word) -> word
  def zr_code_word(code, i)
    zr_fix2long(Machine.value(Machine.load64(RArray[code].ptr + (i * 8), 0)))
  end

  # Makes the Env for an eval's own locals, one scope inside `parent`.
  #: (value, value) -> value
  def zr_code_env(code, parent)
    zr_env_new(parent, zr_code_word(code, 2), Machine.ptr(zr_code_word(code, 3)))
  end

  # Runs a loaded eval toplevel. `self_` is its self, `cref` is the scope
  # for its defs and constants, `env` contains its own locals, and `blk`
  # is the block for a `yield`. This function sets the parent of the
  # FrameMeta, so that a backtrace frame shows the label of the caller.
  #: (value, value, value, value, value) -> value
  def zr_eval_at(code, self_, cref, env, blk)
    FrameMeta[Machine.ptr(zr_code_word(code, 1))].parent = Frame[zr_eval_frame()].meta
    Eval.call(Machine.ptr(zr_code_word(code, 0)), self_, cref, env, blk)
  end

  #: (value, value, value, value, value) -> value
  def zr_eval_run(code, self_, cref, parent, blk)
    zr_eval_at(code, self_, cref, zr_code_env(code, parent), blk)
  end
end
