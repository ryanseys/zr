# POSIX signals. The system runs a handler between any two instructions
# of the program, where Ruby code cannot run. Thus the handler only
# counts the signals. The program runs the Ruby handlers at its next
# safe point: a loop's back edge, a blocking call that the signal
# interrupted, or a kill that the process sent to itself. CRuby divides
# the work in the same way, between sighandler and rb_signal_exec.

module Zr::Kern
  # How a POSIX signal is handled, as Signal.trap gives it: the system
  # default, ignored, counted for a Ruby handler, or caught and discarded.
  # ruby discards SIGPIPE and SIGSYS, so a write to a closed pipe fails
  # with EPIPE and does not end the process.
  SIGNAL_DEFAULT = 0
  SIGNAL_IGNORE = 1
  SIGNAL_RUBY = 2
  SIGNAL_NOTHING = 3
  SIGNAL_OTHER = 4

  # The system handler for a POSIX signal that Ruby handles. It adds one to
  # the count of `signo`. Only this handler changes the count, and it
  # only increases, so the program reads it without a lock. The program
  # reads it at the next safe point.
  #: (i32) -> void
  def zr_trap_caught(signo)
    Machine.gates_enter
    count = Machine.static(:signal_counts, NSIG * 8) + (Machine.u32(signo) * 8)
    Machine.store64(count, 0, Machine.load64(count, 0) + 1)
    Machine.store64(Machine.static(:signal_pending, 8), 0, 1)
    Machine.store64(Machine.static(:preempt_count, 8), 0, 1)
    zr_poll_set()
    zr_chld_note(signo)
  end

  # SIGCHLD with default handling while a thread waits for a child. The
  # handler only wakes the waiters, because the default does nothing else.
  #: (i32) -> void
  def zr_chld_caught(signo)
    Machine.gates_enter
    zr_chld_note(signo)
  end

  # A child changed state. The handler increases the count and writes a
  # byte to the waiters' pipe, so a thread blocked on it wakes. If the
  # pipe is full, the waiters wake already.
  #: (i32) -> void
  def zr_chld_note(signo)
    cell = Machine.static(:chld_pipe, 24)
    if Machine.load64(cell, 0) == 0 || Machine.u32(signo) != Machine.load64(cell, 16)
      return
    end
    counter = Machine.static(:chld_count, 8)
    Machine.store64(counter, 0, Machine.load64(counter, 0) + 1)
    byte = Machine.slot(8)
    Machine.store64(byte, 0, 1)
    Libc.write(Machine.i32(Machine.load64(cell, 8)), byte, 1)
  end

  # The read end of the pipe that SIGCHLD (`signo`) writes to. zr makes
  # it the first time a thread waits for a child while other threads run.
  # Both ends close on exec and never block. If the program does not
  # trap SIGCHLD, zr catches it only for the waiters.
  #: (value) -> value
  def zr_chld_fd(signo)
    cell = Machine.static(:chld_pipe, 24)
    if Machine.load64(cell, 0) != 0
      return zr_fix(Machine.load64(cell, 0) - 1)
    end
    fds = Machine.slot(8)
    if Libc.pipe(fds) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    read_end = zr_fix(Machine.u32(Machine.load32(fds, 0)))
    write_end = zr_fix(Machine.u32(Machine.load32(fds, 4)))
    zr_io_cloexec(read_end)
    zr_io_cloexec(write_end)
    zr_io_set_nonblock(read_end, zr_fix(1))
    zr_io_set_nonblock(write_end, zr_fix(1))
    Machine.store64(cell, 8, zr_fix2long(write_end))
    Machine.store64(cell, 16, zr_fix2long(signo))
    Machine.store64(cell, 0, zr_fix2long(read_end) + 1)
    old = Machine.slot(8)
    if zr_os_sigaction(Machine.i32(zr_fix2long(signo)), SIGNAL_DEFAULT, old) >= Machine.i32(0)
      fn = Machine.load64(old, 0)
      if fn == SIGNAL_DEFAULT
        fn = Machine.word(Machine.addr(:zr_chld_caught))
      end
      zr_os_sigaction(Machine.i32(zr_fix2long(signo)), fn, old)
    end
    read_end
  end

  # The number of SIGCHLDs since zr made the waiters' pipe.
  #: () -> value
  def zr_chld_count
    zr_fix(Machine.load64(Machine.static(:chld_count, 8), 0))
  end

  # Reads all bytes from the waiters' pipe, so that a blocked thread waits
  # for the next child.
  #: () -> value
  def zr_chld_drain
    cell = Machine.static(:chld_pipe, 24)
    if Machine.load64(cell, 0) == 0
      return Machine.value(QNIL)
    end
    buf = Machine.slot(64)
    # read(2) returns -1 (as a full-width word) when the pipe is empty.
    n = Libc.read(Machine.i32(Machine.load64(cell, 0) - 1), buf, 64)
    while n > 0 && n <= 64
      n = Libc.read(Machine.i32(Machine.load64(cell, 0) - 1), buf, 64)
    end
    Machine.value(QNIL)
  end

  #: (i32) -> void
  def zr_trap_dropped(signo)
  end

  # Calls sigaction(2) to handle `signo` as `how` gives. Returns the
  # previous handling, or the negated errno. The mask stays empty and no
  # call restarts, as in ruby_signal. Thus a POSIX signal interrupts a
  # blocking call, and its handler runs without a wait for the call.
  #: (value, value) -> value
  def zr_trap_handle(signo, how)
    h = zr_fix2long(how)
    fn = h
    if h == SIGNAL_RUBY
      fn = Machine.addr(:zr_trap_caught)
    elsif h == SIGNAL_NOTHING
      fn = Machine.addr(:zr_trap_dropped)
    elsif h == SIGNAL_DEFAULT && Machine.load64(Machine.static(:chld_pipe, 24), 16) == zr_fix2long(signo) && zr_fix2long(signo) != 0
      # Waiters still read SIGCHLD's pipe.
      fn = Machine.addr(:zr_chld_caught)
    end
    old = Machine.slot(8)
    if zr_os_sigaction(Machine.i32(zr_fix2long(signo)), fn, old) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    zr_fix(zr_trap_kind(Machine.load64(old, 0)))
  end

  #: (word) -> word
  def zr_trap_kind(fn)
    if fn == SIGNAL_DEFAULT || fn == SIGNAL_IGNORE
      return fn
    end
    if fn == Machine.addr(:zr_chld_caught)
      return SIGNAL_DEFAULT
    end
    if fn == Machine.addr(:zr_trap_caught)
      return SIGNAL_RUBY
    end
    if fn == Machine.addr(:zr_trap_dropped)
      return SIGNAL_NOTHING
    end
    SIGNAL_OTHER
  end

  # The next POSIX signal that is not handled yet, lowest number first, or
  # nil if none remain. This clears the pending mark before the scan and
  # sets it again when it finds a signal. Thus this call or the next one
  # finds a signal that comes during the scan.
  #: () -> value
  def zr_trap_next
    pending = Machine.static(:signal_pending, 8)
    if Machine.load64(pending, 0) == 0
      return Machine.value(QNIL)
    end
    Machine.store64(pending, 0, 0)
    counts = Machine.static(:signal_counts, NSIG * 8)
    taken = Machine.static(:signal_taken, NSIG * 8)
    signo = 1
    while signo < NSIG
      seen = taken + (signo * 8)
      if Machine.load64(seen, 0) != Machine.load64(counts + (signo * 8), 0)
        Machine.store64(seen, 0, Machine.load64(seen, 0) + 1)
        Machine.store64(pending, 0, 1)
        return zr_fix(signo)
      end
      signo += 1
    end
    Machine.value(QNIL)
  end

  # The largest signal number a SignalException takes (NSIG).
  #: () -> value
  def zr_signal_limit
    zr_fix(NSIG)
  end

  # Whether a signal other than `skip` (a number, or 0) came whose
  # handler has not run yet. The pending mark can stay set after the last
  # handler ran, until the next zr_trap_next finds nothing, so this
  # compares the counts.
  #: (value) -> value
  def zr_trap_pending(skip)
    if Machine.load64(Machine.static(:signal_pending, 8), 0) == 0
      return Machine.value(QFALSE)
    end
    counts = Machine.static(:signal_counts, NSIG * 8)
    taken = Machine.static(:signal_taken, NSIG * 8)
    skipped = zr_fix2long(skip)
    signo = 1
    while signo < NSIG
      if signo != skipped && Machine.load64(taken + (signo * 8), 0) != Machine.load64(counts + (signo * 8), 0)
        return Machine.value(QTRUE)
      end
      signo += 1
    end
    Machine.value(QFALSE)
  end

  # A signal whose handler has not run asks the next safe point again, for
  # the main thread, which runs the commands.
  #: () -> value
  def zr_trap_rearm
    if Machine.load64(Machine.static(:signal_pending, 8), 0) != 0
      zr_poll_set()
    end
    Machine.value(QNIL)
  end

  # A safe point: runs the Ruby handlers of all received POSIX signals.
  # Returns QUNDEF if a handler raised.
  #: () -> value
  def zr_trap_check
    if Machine.load64(Machine.static(:signal_pending, 8), 0) == 0
      return Machine.value(QNIL)
    end
    zr_send(zr_core_class(Machine.id(:Signal)), Machine.id(:deliver), 0, 0)
  end

  # A blocking call failed. If a POSIX signal interrupted it, the handlers
  # run and this returns nil, so the caller makes the call again. Else it
  # returns the caller's result: the negated errno, or QUNDEF if a
  # handler raised.
  #: () -> value
  def zr_io_retry
    errno = zr_errno()
    if errno != EINTR
      return zr_fix(0 - errno)
    end
    if zr_trap_check() == QUNDEF
      return Machine.value(QUNDEF)
    end
    Machine.value(QNIL)
  end
end
