module Zr::Kern
  # WASI signals. wasi-libc defines 64 of them, but a module receives none,
  # so each signal keeps its default handler.
  NSIG = 65

  #: (i32, word, ptr) -> i32
  def zr_os_sigaction(signo, fn, old)
    Machine.store64(old, 0, 0)
    Machine.i32(0)
  end

  # wasi-libc's numbers of the four fatal signals. A module receives
  # none of them.
  SIGNAL_ILL = 4
  SIGNAL_ABRT = 6
  SIGNAL_BUS = 7
  SIGNAL_SEGV = 11
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

  # A module ends with a trap.
  #: (i32) -> void
  def zr_os_crash_exit(signo)
    Libc.abort()
  end
end
