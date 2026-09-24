# WASI's signals: wasi-libc numbers 64 of them, and a module takes
# none, so every one keeps the default handler it started with.
NSIG = 65

sig [I32, Word, Ptr] => I32
machine def zr_os_sigaction(signo, fn, old)
  Machine.store64(old, 0, 0)
  Machine.i32(0)
end
