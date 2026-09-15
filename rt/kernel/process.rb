# Child processes: `zr_os_spawn`, with a pipe for the output backticks
# collect, and waitpid for the status.
Machine.import "getrusage", [I32, Ptr] => I32
Machine.import "waitpid", [I32, Ptr, I32] => I32
Machine.import "pipe", [Ptr] => I32
Machine.import "getppid", [] => I32
Machine.import "kill", [I32, I32] => I32
Machine.import "signal", [I32, Ptr] => Ptr
Machine.import "execvp", [Ptr, Ptr] => I32

# A NULL-ended char* vector of an Array of Strings, malloc'd.
sig [Value] => Ptr
machine def zr_spawn_vector(words)
  n = RArray.len(words)
  vector = zr_xmalloc((n + 1) * 8)
  i = 0
  while i < n
    Machine.store64(vector + (i * 8), 0, Machine.word(RString.ptr(zr_ary_at(words, i))))
    i += 1
  end
  Machine.store64(vector + (n * 8), 0, 0)
  vector
end

# execvp: the process becomes the command; answers only when it could
# not, with the negated errno.
sig [Value] => Value
machine def zr_proc_exec(words)
  argv = zr_spawn_vector(words)
  execvp(RString.ptr(zr_ary_at(words, 0)), argv)
  free(argv)
  zr_fix(0 - zr_errno())
end

# waitpid: [pid, raw status], or the negated errno.
sig [Value, Value] => Value
machine def zr_proc_wait(pid, flags)
  status = Machine.slot(8)
  Machine.store64(status, 0, 0)
  r = waitpid(Machine.i32(zr_fix2long(pid)), status, Machine.i32(zr_fix2long(flags)))
  while r < Machine.i32(0)
    failed = zr_io_retry()
    if failed != QNIL
      return failed
    end
    r = waitpid(Machine.i32(zr_fix2long(pid)), status, Machine.i32(zr_fix2long(flags)))
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(Machine.word(r)))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(status, 0))))
  out
end

# A pipe: [read end, write end], or the negated errno.
sig [] => Value
machine def zr_io_pipe
  fds = Machine.slot(8)
  if pipe(fds) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  # Both ends close themselves across an exec, as rb_cloexec_pipe asks:
  # a write end that leaked into an unrelated child would hold the
  # reader's end of file open for as long as that child lived.
  read_end = zr_fix(Machine.word(Machine.load32(fds, 0)))
  write_end = zr_fix(Machine.word(Machine.load32(fds, 4)))
  zr_io_cloexec(read_end)
  zr_io_cloexec(write_end)
  out = zr_ary_new(2)
  zr_ary_push(out, read_end)
  zr_ary_push(out, write_end)
  out
end

# `who`'s user and system time in seconds, `[utime, stime]`: a
# rusage's two leading timevals (seconds, then microseconds).
sig [Value] => Value
machine def zr_proc_rusage(who)
  ru = Machine.slot(144)
  getrusage(Machine.i32(zr_fix2long(who)), ru)
  out = zr_ary_new(2)
  zr_ary_push(out, zr_float_new(Machine.to_f64(Machine.load64(ru, 0)) + (Machine.to_f64(Machine.word(Machine.load32(ru, 8))) / Machine.to_f64(1000000))))
  zr_ary_push(out, zr_float_new(Machine.to_f64(Machine.load64(ru, 16)) + (Machine.to_f64(Machine.word(Machine.load32(ru, 24))) / Machine.to_f64(1000000))))
  out
end

sig [] => Value
machine def zr_proc_ppid
  zr_fix(Machine.word(getppid()))
end

Machine.import "getpgrp", [] => I32
Machine.import "getpgid", [I32] => I32
Machine.import "setpgid", [I32, I32] => I32
Machine.import "getsid", [I32] => I32
Machine.import "setsid", [] => I32
Machine.import "getgroups", [I32, Ptr] => I32
Machine.import "getpriority", [I32, I32] => I32
Machine.import "setpriority", [I32, I32, I32] => I32

# `getpriority`: the niceness, and the errno beside it. A niceness of
# -1 is a real answer, so errno is cleared first and only a failure of
# this call sets it.
sig [Value, Value] => Value
machine def zr_proc_getpriority(which, who)
  zr_clear_errno()
  r = Machine.sword(getpriority(Machine.i32(zr_fix2long(which)), Machine.i32(zr_fix2long(who))))
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(r))
  zr_ary_push(out, zr_fix(zr_errno()))
  out
end

sig [Value, Value, Value] => Value
machine def zr_proc_setpriority(which, who, priority)
  zr_io_status(setpriority(Machine.i32(zr_fix2long(which)), Machine.i32(zr_fix2long(who)), Machine.i32(zr_fix2long(priority))))
end

# The process group, the session and the groups: each answers its id,
# or the errno as a negative where the call fails.
sig [] => Value
machine def zr_proc_getpgrp
  zr_io_failed(Machine.sword(getpgrp()))
end

sig [Value] => Value
machine def zr_proc_getpgid(pid)
  zr_io_failed(Machine.sword(getpgid(Machine.i32(zr_fix2long(pid)))))
end

sig [Value, Value] => Value
machine def zr_proc_setpgid(pid, pgrp)
  zr_io_status(setpgid(Machine.i32(zr_fix2long(pid)), Machine.i32(zr_fix2long(pgrp))))
end

sig [Value] => Value
machine def zr_proc_getsid(pid)
  zr_io_failed(Machine.sword(getsid(Machine.i32(zr_fix2long(pid)))))
end

sig [] => Value
machine def zr_proc_setsid
  zr_io_failed(Machine.sword(setsid()))
end

# The supplementary groups, as an Array of ids.
sig [] => Value
machine def zr_proc_groups
  list = Machine.slot(256)
  n = Machine.sword(getgroups(Machine.i32(64), list))
  if n < 0
    return zr_fix(0 - zr_errno())
  end
  out = zr_ary_new(n)
  i = 0
  while i < n
    zr_ary_push(out, zr_fix(Machine.word(Machine.load32(list + (i * 4), 0))))
    i += 1
  end
  out
end

sig [Value, Value] => Value
machine def zr_proc_kill(pid, signal)
  zr_io_status(kill(Machine.i32(zr_fix2long(pid)), Machine.i32(zr_fix2long(signal))))
end

# kill(2) of `signal` to every pid in `pids`, in one call as rb_f_kill
# makes them, so that a signal this process sends itself is handled
# once all are sent: 0, or the negated errno of the first that failed.
sig [Value, Value] => Value
machine def zr_proc_kill_all(pids, signal)
  i = 0
  while i < RArray.len(pids)
    r = zr_proc_kill(zr_ary_at(pids, i), signal)
    if r != zr_fix(0)
      return r
    end
    i += 1
  end
  if zr_trap_check() == QUNDEF
    return Machine.value(QUNDEF)
  end
  zr_fix(0)
end

Machine.import "getrlimit", [I32, Ptr] => I32
Machine.import "setrlimit", [I32, Ptr] => I32

# `getrlimit`: `[cur, max]`, each rlim_t's bits as a signed word, or the
# errno as a negative.
sig [Value] => Value
machine def zr_proc_getrlimit(resource)
  limits = Machine.slot(16)
  if getrlimit(Machine.i32(zr_fix2long(resource)), limits) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  out = zr_ary_new(2)
  zr_ary_push(out, zr_int_from_word(Machine.load64(limits, 0)))
  zr_ary_push(out, zr_int_from_word(Machine.load64(limits, 8)))
  out
end

# `setrlimit`, each limit given as the signed word of its bits.
sig [Value, Value, Value] => Value
machine def zr_proc_setrlimit(resource, cur, max)
  limits = Machine.slot(16)
  r = zr_index_operand(cur, limits)
  return r if r == QUNDEF
  r = zr_index_operand(max, limits + 8)
  return r if r == QUNDEF
  zr_io_status(setrlimit(Machine.i32(zr_fix2long(resource)), limits))
end

Machine.import "setreuid", [I32, I32] => I32
Machine.import "setregid", [I32, I32] => I32
Machine.import "setgroups", [I32, Ptr] => I32
Machine.import "initgroups", [Ptr, I32] => I32

# `setreuid` (`group` false) or `setregid`, where -1 leaves an id as it
# is: 0, or the errno as a negative.
sig [Value, Value, Value] => Value
machine def zr_proc_setreid(group, real, effective)
  r = Machine.i32(zr_fix2long(real))
  e = Machine.i32(zr_fix2long(effective))
  zr_io_status(group == QTRUE ? setregid(r, e) : setreuid(r, e))
end

# `setgroups` over an Array of group ids.
sig [Value] => Value
machine def zr_proc_setgroups(ids)
  n = RArray.len(ids)
  list = zr_xmalloc((n + 1) * 4)
  i = 0
  while i < n
    Machine.store32(list + (i * 4), 0, Machine.i32(zr_fix2long(zr_ary_at(ids, i))))
    i += 1
  end
  r = setgroups(Machine.i32(n), list)
  free(list)
  zr_io_status(r)
end

sig [Value, Value] => Value
machine def zr_proc_initgroups(user, gid)
  zr_io_status(initgroups(RString.ptr(user), Machine.i32(zr_fix2long(gid))))
end

Machine.import "fork", [] => I32

# `fork`: the child's pid in the parent, 0 in the child, or the errno as
# a negative.
sig [] => Value
machine def zr_proc_fork
  zr_io_failed(Machine.sword(fork()))
end

# A forked child's end, as CRuby's ruby_stop ends it: the at_exit
# handlers and the streams as a program's end runs them, with `exc` the
# exception its block raised, or nil, and then the process exits. The
# parent's frames below never see the exception.
sig [Value] => Value
machine def zr_proc_child_exit(exc)
  exit(Machine.i32(zr_program_end(exc == QNIL ? Machine.value(QUNDEF) : exc)))
  Machine.value(QNIL)
end
