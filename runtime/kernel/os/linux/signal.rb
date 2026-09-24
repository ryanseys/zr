# Linux's signals: how many there are, and the layout sigaction takes.
Machine.import "sigaction", [I32, Ptr, Ptr] => I32

# musl numbers its signals 1 to 64, the real-time ones included.
NSIG = 65

# sigaction(2) for `signo` with the handler `fn` (0 the default, 1
# ignore), an empty mask and no flags: 0 with the handler it had before
# stored at `old`, or -1 with errno set. musl's struct sigaction is the
# handler, a 128-byte mask, the flags as an int and the restorer: 152
# bytes.
SIGACTION_LEN = 152

sig [I32, Word, Ptr] => I32
machine def zr_os_sigaction(signo, fn, old)
  act = Machine.slot(SIGACTION_LEN)
  memset(act, Machine.i32(0), SIGACTION_LEN)
  Machine.store64(act, 0, fn)
  was = Machine.slot(SIGACTION_LEN)
  r = sigaction(signo, act, was)
  Machine.store64(old, 0, Machine.load64(was, 0))
  r
end
