module Zr::Kern
  # darwin signals: the number of signals, and the layout of sigaction.
  Libc.import :sigaction, [I32, Ptr, Ptr] => I32

  # Darwin numbers its signals 1 to 31.
  NSIG = 32

  # Calls sigaction(2) for `signo` with the handler `fn` (0 is the default,
  # 1 is ignore), an empty mask and no flags. Returns 0 and stores the
  # previous handler at `old`, or returns -1 and sets errno. darwin's
  # struct sigaction is the handler, a 4-byte mask and 4 bytes of flags.
  sig [I32, Word, Ptr] => I32
  def zr_os_sigaction(signo, fn, old)
    act = Machine.slot(16)
    Machine.store64(act, 0, fn)
    Machine.store64(act, 8, 0)
    was = Machine.slot(16)
    r = Libc.sigaction(signo, act, was)
    Machine.store64(old, 0, Machine.load64(was, 0))
    r
  end
end
