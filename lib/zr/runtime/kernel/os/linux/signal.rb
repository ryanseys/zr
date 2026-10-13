module Zr::Kern
  # Linux signals: the number of signals, and the layout of sigaction.

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

  SIGNAL_PIPE = 13

  # The four signals that end the process with ruby's bug report.
  SIGNAL_ILL = 4
  SIGNAL_ABRT = 6
  SIGNAL_BUS = 7
  SIGNAL_SEGV = 11

  # Whether a bug report tells where the system keeps its own crash
  # report. Only macOS has one.
  CRASH_NOTES = 0

  # open(2)'s flags: for the file of a report (O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC),
  # and for a file that a report reads (O_RDONLY | O_CLOEXEC).
  CRASH_WRITE_FLAGS = 524865
  CRASH_READ_FLAGS = 524288

  # SA_SIGINFO | SA_ONSTACK | SA_NODEFER: the handler of a fatal signal
  # gets the siginfo_t, runs on the alternate stack, and can take a
  # second signal.
  FATAL_FLAGS = 1207959556

  # sigaction(2) for a fatal signal: `fn` takes (signo, info, context).
  # The flags are the int after the 128-byte mask.
  #: (i32, word) -> i32
  def zr_os_fatal_action(signo, fn)
    act = Machine.slot(SIGACTION_LEN)
    Libc.memset(act, Machine.i32(0), SIGACTION_LEN)
    Machine.store64(act, 0, fn)
    Machine.store64(act, 136, FATAL_FLAGS)
    was = Machine.slot(SIGACTION_LEN)
    Libc.sigaction(signo, act, was)
  end

  # sigaltstack(2). Linux's stack_t is the base, the flags, then the
  # size.
  #: (ptr, word) -> i32
  def zr_os_altstack(base, size)
    ss = Machine.slot(24)
    Machine.store64(ss, 0, Machine.word(base))
    Machine.store64(ss, 8, 0)
    Machine.store64(ss, 16, size)
    Libc.sigaltstack(ss, Machine.ptr(0))
  end

  # The pid in a siginfo_t that a process sent (SI_USER, SI_QUEUE or
  # SI_TKILL), or -1 for a signal that the system raised. si_code is at 8
  # and si_pid at 16.
  #: (ptr) -> word
  def zr_os_signal_sender(info)
    code = Machine.u32(Machine.load32(info, 8))
    if code != 0 && code != 4294967295 && code != 4294967290
      return 0 - 1
    end
    Machine.u32(Machine.load32(info, 16))
  end

  # si_addr, at 16.
  #: (ptr) -> word
  def zr_os_fault_address(info)
    Machine.load64(info, 16)
  end

  # musl has no backtrace(3), so a report has no native frames.
  #: (ptr, i32) -> word
  def zr_os_c_frames(buf, max)
    0
  end

  # The report's command (`zr_crash_spawn`): its pipe's write end, or -1.
  #: (ptr, ptr) -> word
  def zr_os_crash_spawn(argv, child)
    zr_crash_spawn(argv, child)
  end

  # Waits for the report's command to end.
  #: (word) -> void
  def zr_os_crash_wait(pid)
    status = Machine.slot(8)
    Libc.waitpid(Machine.i32(pid), status, Machine.i32(0))
  end

  # dladdr(3): the file and the symbol of the code at `pc`, into `info`.
  # Returns 0 when it finds none.
  #: (ptr, ptr) -> word
  def zr_os_symbol_of(pc, info)
    Machine.u32(Libc.dladdr(pc, info))
  end

  # ruby_default_signal: the signal's default action ends the process.
  # abort(3) with the default SIGABRT is the last resort.
  #: (i32) -> void
  def zr_os_crash_exit(signo)
    old = Machine.slot(8)
    zr_os_sigaction(signo, SIGNAL_DEFAULT, old)
    Libc.raise(signo)
    zr_os_sigaction(Machine.i32(SIGNAL_ABRT), SIGNAL_DEFAULT, old)
    Libc.abort()
  end

  # sigprocmask's SIG_SETMASK.
  SIG_SETMASK = 2

  # Clears the signal mask, as rb_enable_interrupt does when ruby
  # starts and disable_child_handler_fork_child does in a child: a
  # signal that the parent blocked reaches the handlers here. The
  # empty set is the size of musl's sigset_t, the larger one.
  #: () -> void
  def zr_os_unblock_signals
    set = Machine.slot(128)
    Libc.memset(set, Machine.i32(0), 128)
    Libc.sigprocmask(Machine.i32(SIG_SETMASK), set, Machine.ptr(0))
  end
end
