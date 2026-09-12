# Child processes: posix_spawn, which is not variadic, with a pipe
# for the output backticks collect, and waitpid for the status.
Machine.import "getrusage", [I32, Ptr] => I32
Machine.import "posix_spawnp", [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => I32
Machine.import "posix_spawn_file_actions_init", [Ptr] => I32
Machine.import "posix_spawn_file_actions_adddup2", [Ptr, I32, I32] => I32
Machine.import "posix_spawn_file_actions_addclose", [Ptr, I32] => I32
Machine.import "posix_spawn_file_actions_addchdir_np", [Ptr, Ptr] => I32
Machine.import "posix_spawn_file_actions_destroy", [Ptr] => I32
Machine.import "posix_spawnattr_init", [Ptr] => I32
Machine.import "posix_spawnattr_setflags", [Ptr, I32] => I32
Machine.import "posix_spawnattr_destroy", [Ptr] => I32
# POSIX_SPAWN_CLOEXEC_DEFAULT: every descriptor the parent holds stays
# behind, and only the file actions cross into the child. That is what
# CRuby reaches by opening each descriptor close-on-exec.
SPAWN_CLOEXEC_DEFAULT = 16384
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

# Spawn `words` (an Array of Strings, the program first). `dups` is a
# flat Array of (child descriptor, source descriptor) pairs applied in
# order, `closes` the child's descriptors to shut, `env` the child's
# whole environment as "KEY=value" strings or nil to inherit it, and
# `chdir` the child's directory or nil. The pid, or the negated errno.
sig [Value, Value, Value, Value, Value] => Value
machine def zr_proc_spawn(words, dups, closes, env, chdir)
  argv = zr_spawn_vector(words)
  actions = Machine.slot(16)
  posix_spawn_file_actions_init(actions)
  attributes = Machine.slot(16)
  posix_spawnattr_init(attributes)
  posix_spawnattr_setflags(attributes, Machine.i32(SPAWN_CLOEXEC_DEFAULT))
  n = RArray.len(dups)
  i = 0
  while i < n
    posix_spawn_file_actions_adddup2(actions, Machine.i32(zr_fix2long(zr_ary_at(dups, i + 1))), Machine.i32(zr_fix2long(zr_ary_at(dups, i))))
    i += 2
  end
  n = RArray.len(closes)
  i = 0
  while i < n
    posix_spawn_file_actions_addclose(actions, Machine.i32(zr_fix2long(zr_ary_at(closes, i))))
    i += 1
  end
  if chdir != QNIL
    posix_spawn_file_actions_addchdir_np(actions, RString.ptr(chdir))
  end
  envp = Machine.ptr(Machine.load64(_NSGetEnviron(), 0))
  if env != QNIL
    envp = zr_spawn_vector(env)
  end
  pid = Machine.slot(8)
  Machine.store64(pid, 0, 0)
  r = posix_spawnp(pid, RString.ptr(zr_ary_at(words, 0)), actions, attributes, argv, envp)
  posix_spawn_file_actions_destroy(actions)
  posix_spawnattr_destroy(attributes)
  free(argv)
  if env != QNIL
    free(envp)
  end
  if r != Machine.i32(0)
    return zr_fix(0 - Machine.word(r))
  end
  zr_fix(Machine.word(Machine.load32(pid, 0)))
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
  if r < Machine.i32(0)
    return zr_fix(0 - zr_errno())
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
  r = Machine.word(getpriority(Machine.i32(zr_fix2long(which)), Machine.i32(zr_fix2long(who))))
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
  zr_io_failed(Machine.word(getpgrp()))
end

sig [Value] => Value
machine def zr_proc_getpgid(pid)
  zr_io_failed(Machine.word(getpgid(Machine.i32(zr_fix2long(pid)))))
end

sig [Value, Value] => Value
machine def zr_proc_setpgid(pid, pgrp)
  zr_io_status(setpgid(Machine.i32(zr_fix2long(pid)), Machine.i32(zr_fix2long(pgrp))))
end

sig [Value] => Value
machine def zr_proc_getsid(pid)
  zr_io_failed(Machine.word(getsid(Machine.i32(zr_fix2long(pid)))))
end

sig [] => Value
machine def zr_proc_setsid
  zr_io_failed(Machine.word(setsid()))
end

# The supplementary groups, as an Array of ids.
sig [] => Value
machine def zr_proc_groups
  list = Machine.slot(256)
  n = Machine.word(getgroups(Machine.i32(64), list))
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
