# darwin's signals: how many there are, and the layout sigaction takes.
Machine.import "sigaction", [I32, Ptr, Ptr] => I32

# Darwin numbers its signals 1 to 31.
NSIG = 32

# sigaction(2) for `signo` with the handler `fn` (0 the default, 1
# ignore), an empty mask and no flags: 0 with the handler it had before
# stored at `old`, or -1 with errno set. darwin's struct sigaction is
# the handler, then a 4-byte mask and 4 bytes of flags.
sig [I32, Word, Ptr] => I32
machine def zr_os_sigaction(signo, fn, old)
  act = Machine.slot(16)
  Machine.store64(act, 0, fn)
  Machine.store64(act, 8, 0)
  was = Machine.slot(16)
  r = sigaction(signo, act, was)
  Machine.store64(old, 0, Machine.load64(was, 0))
  r
end
