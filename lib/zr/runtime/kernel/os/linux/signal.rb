module Zr::Kern
  # Linux signals: the number of signals, and the layout of sigaction.
  Libc.import :sigaction, [I32, Ptr, Ptr] => I32

  # musl numbers its signals 1 to 64, the real-time ones included.
  NSIG = 65

  # Calls sigaction(2) for `signo` with the handler `fn` (0 is the default,
  # 1 is ignore), an empty mask and no flags. Returns 0 and stores the
  # previous handler at `old`, or returns -1 and sets errno. musl's struct
  # sigaction is 152 bytes: the handler, a 128-byte mask, the flags as an
  # int, and the restorer.
  SIGACTION_LEN = 152

  #: (i32, word, ptr) -> i32
  def zr_os_sigaction(signo, fn, old)
    act = Machine.slot(SIGACTION_LEN)
    Libc.memset(act, Machine.i32(0), SIGACTION_LEN)
    Machine.store64(act, 0, fn)
    was = Machine.slot(SIGACTION_LEN)
    r = Libc.sigaction(signo, act, was)
    Machine.store64(old, 0, Machine.load64(was, 0))
    r
  end
end
