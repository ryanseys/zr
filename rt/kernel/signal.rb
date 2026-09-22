# Signals. The system runs a handler between any two instructions of
# the program, where no Ruby may run, so the handler only counts what
# came. The program runs the Ruby handlers at its next safe point: a
# loop's back edge, a blocking call the signal cut short, or a kill the
# process sent to itself. That is CRuby's own split between sighandler
# and rb_signal_exec.

# How a signal is handled, as Signal.trap names it: the system's
# default, ignored, counted for a Ruby handler, or caught and dropped
# (ruby's handler for SIGPIPE and SIGSYS, so a write to a closed pipe
# fails with EPIPE instead of ending the process).
SIGNAL_DEFAULT = 0
SIGNAL_IGNORE = 1
SIGNAL_RUBY = 2
SIGNAL_NOTHING = 3
SIGNAL_OTHER = 4

# The system's handler for a signal Ruby handles: one more of `signo`
# came. The count only grows, and only here, so the program reads it
# without a lock. The next safe point is where the program asks.
sig [I32] => Void
machine def zr_trap_caught(signo)
  Machine.gates_enter
  count = Machine.static(:signal_counts, NSIG * 8) + (Machine.word(signo) * 8)
  Machine.store64(count, 0, Machine.load64(count, 0) + 1)
  Machine.store64(Machine.static(:signal_pending, 8), 0, 1)
  Machine.store64(Machine.static(:preempt_count, 8), 0, 1)
  zr_poll_set()
  zr_chld_note(signo)
end

# SIGCHLD under its default handling while a thread waits for a child:
# the signal only tells the waiters, as the default does nothing else.
sig [I32] => Void
machine def zr_chld_caught(signo)
  Machine.gates_enter
  zr_chld_note(signo)
end

# A child changed state: the count grows and the waiters' pipe takes a
# byte, so a thread parked on it wakes. A full pipe already wakes them.
sig [I32] => Void
machine def zr_chld_note(signo)
  cell = Machine.static(:chld_pipe, 24)
  if Machine.load64(cell, 0) == 0 || Machine.word(signo) != Machine.load64(cell, 16)
    return
  end
  counter = Machine.static(:chld_count, 8)
  Machine.store64(counter, 0, Machine.load64(counter, 0) + 1)
  byte = Machine.slot(8)
  Machine.store64(byte, 0, 1)
  write(Machine.i32(Machine.load64(cell, 8)), byte, 1)
end

# The read end of the pipe SIGCHLD (`signo`) writes to, made the first
# time a thread waits for a child among others: both ends close across
# an exec and never block, and a SIGCHLD the program does not trap is
# caught for the waiters alone.
sig [Value] => Value
machine def zr_chld_fd(signo)
  cell = Machine.static(:chld_pipe, 24)
  if Machine.load64(cell, 0) != 0
    return zr_fix(Machine.load64(cell, 0) - 1)
  end
  fds = Machine.slot(8)
  if pipe(fds) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  read_end = zr_fix(Machine.word(Machine.load32(fds, 0)))
  write_end = zr_fix(Machine.word(Machine.load32(fds, 4)))
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

# How many SIGCHLDs came since the waiters' pipe was made.
sig [] => Value
machine def zr_chld_count
  zr_fix(Machine.load64(Machine.static(:chld_count, 8), 0))
end

# The bytes the waiters' pipe holds, taken, so a parked thread waits
# for the next child.
sig [] => Value
machine def zr_chld_drain
  cell = Machine.static(:chld_pipe, 24)
  if Machine.load64(cell, 0) == 0
    return Machine.value(QNIL)
  end
  buf = Machine.slot(64)
  # read(2) answers -1 as the widest word once the pipe is empty.
  n = read(Machine.i32(Machine.load64(cell, 0) - 1), buf, 64)
  while n > 0 && n <= 64
    n = read(Machine.i32(Machine.load64(cell, 0) - 1), buf, 64)
  end
  Machine.value(QNIL)
end

sig [I32] => Void
machine def zr_trap_dropped(signo)
end

# sigaction(2) for `signo`, handled as `how` says. Answers how it was
# handled before, or the negated errno. The mask stays empty and no
# call restarts, as ruby_signal asks: a blocking call a signal cuts
# short comes back, so its handler runs without waiting on the call.
sig [Value, Value] => Value
machine def zr_trap_handle(signo, how)
  h = zr_fix2long(how)
  fn = h
  if h == SIGNAL_RUBY
    fn = Machine.addr(:zr_trap_caught)
  elsif h == SIGNAL_NOTHING
    fn = Machine.addr(:zr_trap_dropped)
  elsif h == SIGNAL_DEFAULT && Machine.load64(Machine.static(:chld_pipe, 24), 16) == zr_fix2long(signo) && zr_fix2long(signo) != 0
    # Waiters still listen on SIGCHLD's pipe.
    fn = Machine.addr(:zr_chld_caught)
  end
  old = Machine.slot(8)
  if zr_os_sigaction(Machine.i32(zr_fix2long(signo)), fn, old) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  zr_fix(zr_trap_kind(Machine.load64(old, 0)))
end

sig [Word] => Word
machine def zr_trap_kind(fn)
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

# The next signal that came and is not yet handled, the lowest number
# first; nil when none is left. The pending mark is cleared before the
# scan and set again with an answer, so a signal that comes during the
# scan is found by this call or by the next.
sig [] => Value
machine def zr_trap_next
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

# A safe point: the Ruby handlers of whatever came run now. QUNDEF when
# one of them raised.
sig [] => Value
machine def zr_trap_check
  if Machine.load64(Machine.static(:signal_pending, 8), 0) == 0
    return Machine.value(QNIL)
  end
  zr_send(zr_core_class(Machine.id(:Signal)), Machine.id(:deliver), 0, 0)
end

# A blocking call failed. When a signal cut it short the handlers run
# and the answer is nil, so the caller makes the call again; otherwise
# the answer is the caller's own: the negated errno, or QUNDEF when a
# handler raised.
sig [] => Value
machine def zr_io_retry
  errno = zr_errno()
  if errno != EINTR
    return zr_fix(0 - errno)
  end
  if zr_trap_check() == QUNDEF
    return Machine.value(QUNDEF)
  end
  Machine.value(QNIL)
end
