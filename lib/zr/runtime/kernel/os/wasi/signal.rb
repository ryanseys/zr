module Zr::Kern
  # WASI signals. wasi-libc defines 64 of them, with Linux's numbers. A
  # module receives none, but it keeps each signal's handler, so trap
  # returns the handler that it replaced, as on Linux. KILL and STOP
  # take no handler.
  NSIG = 65
  SIGNAL_KILL = 9
  SIGNAL_STOP = 19

  #: (i32, word, ptr) -> i32
  def zr_os_sigaction(signo, fn, old)
    if signo <= Machine.i32(0) || signo >= Machine.i32(NSIG) || signo == Machine.i32(SIGNAL_KILL) || signo == Machine.i32(SIGNAL_STOP)
      return zr_wasi_fail(WASI_EINVAL)
    end
    at = Machine.static(:wasi_signal_handlers, NSIG * 8) + (Machine.u32(signo) * 8)
    Machine.store64(old, 0, Machine.load64(at, 0))
    Machine.store64(at, 0, fn)
    Machine.i32(0)
  end

  # wasi-libc's numbers of the four fatal signals. A module receives
  # none of them.
  SIGNAL_ILL = 4
  SIGNAL_ABRT = 6
  SIGNAL_BUS = 7
  SIGNAL_SEGV = 11
  SIGNAL_PIPE = 13
  CRASH_NOTES = 0

  # open(2)'s flags: for the file of a report (O_WRONLY | O_CREAT | O_TRUNC),
  # and for a file that a report reads (O_RDONLY).
  CRASH_WRITE_FLAGS = 268472320
  CRASH_READ_FLAGS = 67108864

  # No handler runs, so this says it is not installed.
  #: (i32, word) -> i32
  def zr_os_fatal_action(signo, fn)
    Machine.i32(0 - 1)
  end

  #: (ptr, word) -> i32
  def zr_os_altstack(base, size)
    Machine.i32(0)
  end

  #: (ptr) -> word
  def zr_os_signal_sender(info)
    0 - 1
  end

  #: (ptr) -> word
  def zr_os_fault_address(info)
    0
  end

  #: (ptr, i32) -> word
  def zr_os_c_frames(buf, max)
    0
  end

  # A module starts no process, so a report goes to stderr or a file.
  #: (ptr, ptr) -> word
  def zr_os_crash_spawn(argv, child)
    0 - 1
  end

  # No command, so nothing to wait for.
  #: (word) -> void
  def zr_os_crash_wait(pid)
  end

  # A module has no symbol table to read at run time.
  #: (ptr, ptr) -> word
  def zr_os_symbol_of(pc, info)
    0
  end

  # A module ends with a trap.
  #: (i32) -> void
  def zr_os_crash_exit(signo)
    Libc.abort()
  end

  # A module has no signal mask.
  #: () -> void
  def zr_os_unblock_signals
  end
end
