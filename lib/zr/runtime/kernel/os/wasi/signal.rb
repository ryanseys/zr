# WASI signals. wasi-libc defines 64 of them, but a module receives none,
# so each signal keeps its default handler.
NSIG = 65

sig [I32, Word, Ptr] => I32
machine def zr_os_sigaction(signo, fn, old)
  Machine.store64(old, 0, 0)
  Machine.i32(0)
end
