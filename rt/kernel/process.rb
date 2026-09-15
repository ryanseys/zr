# Child processes: `zr_os_spawn`, with a pipe for the output backticks
# collect, and waitpid for the status.
Machine.import "getrusage", [I32, Ptr] => I32
Machine.import "waitpid", [I32, Ptr, I32] => I32
Machine.import "pipe", [Ptr] => I32
Machine.import "getppid", [] => I32
Machine.import "kill", [I32, I32] => I32
Machine.import "signal", [I32, Ptr] => Ptr

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

# Child processes through posix_spawn, which is not variadic, where the
# OS has it: `zr_os_spawn` calls this with the OS's flags.
Machine.import "posix_spawnp", [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => I32
Machine.import "posix_spawn_file_actions_init", [Ptr] => I32
Machine.import "posix_spawn_file_actions_adddup2", [Ptr, I32, I32] => I32
Machine.import "posix_spawn_file_actions_addclose", [Ptr, I32] => I32
Machine.import "posix_spawn_file_actions_addchdir_np", [Ptr, Ptr] => I32
Machine.import "posix_spawn_file_actions_destroy", [Ptr] => I32
Machine.import "posix_spawnattr_init", [Ptr] => I32
Machine.import "posix_spawnattr_setflags", [Ptr, I32] => I32
Machine.import "posix_spawnattr_destroy", [Ptr] => I32

# Spawn `words` (an Array of Strings, the program first). `dups` is a
# flat Array of (child descriptor, source descriptor) pairs applied in
# order, `closes` the child's descriptors to shut, `env` the child's
# whole environment as "KEY=value" strings or nil to inherit it, and
# `chdir` the child's directory or nil; `flags` are the OS's own
# posix_spawnattr flags. The pid, or the negated errno.
sig [Value, Value, Value, Value, Value, Word] => Value
machine def zr_posix_spawn(words, dups, closes, env, chdir, flags)
  argv = zr_spawn_vector(words)
  actions = Machine.slot(SPAWN_ACTIONS_LEN)
  posix_spawn_file_actions_init(actions)
  attributes = Machine.slot(SPAWN_ATTR_LEN)
  posix_spawnattr_init(attributes)
  posix_spawnattr_setflags(attributes, Machine.i32(flags))
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
  envp = zr_os_environ()
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

Machine.import "execve", [Ptr, Ptr, Ptr] => I32

# The options posix_spawn cannot carry, applied to this process in
# rb_execarg_run_options's order: the process group (`pgroup` -1 leaves
# it, 0 makes a new one), the resource limits (`limits` holds resource,
# soft, hard triples), the umask (-1 leaves it), the descriptors and the
# directory, each a row of `options` in that order: `dups` and `closes`
# are zr_posix_spawn's. 0, or the errno. It allocates nothing, so a
# forked child may run it before its exec.
sig [Value] => Word
machine def zr_exec_options(options)
  dups = zr_ary_at(options, 0)
  closes = zr_ary_at(options, 1)
  chdir = zr_ary_at(options, 2)
  pgroup = zr_ary_at(options, 3)
  mask = zr_ary_at(options, 4)
  limits = zr_ary_at(options, 5)
  # A pty's child leads a session of its own with the slave as its
  # controlling terminal and its standard streams, as pty.c's chfunc
  # makes it, before any other option.
  if RArray.len(options) > 6
    zr_exec_tty(zr_ary_at(options, 6))
  end
  group = zr_fix2long(pgroup)
  if group >= 0 && setpgid(Machine.i32(0), Machine.i32(group)) < Machine.i32(0)
    return zr_errno()
  end
  pair = Machine.slot(16)
  i = 0
  while i < RArray.len(limits)
    Machine.store64(pair, 0, zr_fix2long(zr_ary_at(limits, i + 1)))
    Machine.store64(pair, 8, zr_fix2long(zr_ary_at(limits, i + 2)))
    if setrlimit(Machine.i32(zr_fix2long(zr_ary_at(limits, i))), pair) < Machine.i32(0)
      return zr_errno()
    end
    i += 3
  end
  if zr_fix2long(mask) >= 0
    umask(Machine.i32(zr_fix2long(mask)))
  end
  i = 0
  while i < RArray.len(dups)
    child = Machine.i32(zr_fix2long(zr_ary_at(dups, i)))
    source = Machine.i32(zr_fix2long(zr_ary_at(dups, i + 1)))
    # A descriptor duplicated onto itself only loses close-on-exec, as
    # posix_spawn_file_actions_adddup2 treats it.
    if child == source
      zr_os_fcntl(child, Machine.i32(F_SETFD), 0)
    elsif dup2(source, child) < Machine.i32(0)
      return zr_errno()
    end
    i += 2
  end
  i = 0
  while i < RArray.len(closes)
    close(Machine.i32(zr_fix2long(zr_ary_at(closes, i))))
    i += 1
  end
  if chdir != QNIL && chdir(RString.ptr(chdir)) < Machine.i32(0)
    return zr_errno()
  end
  0
end

# pty.c's start_new_session, obtain_ctty and drop_privilege for the
# [master, slave] pair `tty`: the errors each ignores stay ignored.
sig [Value] => Void
machine def zr_exec_tty(tty)
  master = Machine.i32(zr_fix2long(zr_ary_at(tty, 0)))
  slave = Machine.i32(zr_fix2long(zr_ary_at(tty, 1)))
  setsid()
  close(master)
  zr_os_ioctl(slave, TIOCSCTTY, Machine.ptr(0))
  dup2(slave, Machine.i32(0))
  dup2(slave, Machine.i32(1))
  dup2(slave, Machine.i32(2))
  if Machine.sword(slave) > 2
    close(slave)
  end
  zr_os_setid(zr_sym(Machine.id(:seteuid)), zr_fix(Machine.word(getuid())))
end

# A spawn through fork and execve, for the options posix_spawn cannot
# carry: the child applies them, then runs the program at `path`. A
# child that cannot start writes its errno to a pipe that an exec
# closes, and ends. The pid, or the negated errno.
sig [Value, Value, Value, Value] => Value
machine def zr_spawn_forked(path, words, env, options)
  ends = Machine.slot(8)
  if pipe(ends) < Machine.i32(0)
    return zr_fix(0 - zr_errno())
  end
  reader = Machine.load32(ends, 0)
  writer = Machine.load32(ends, 4)
  zr_io_cloexec(zr_fix(Machine.word(reader)))
  zr_io_cloexec(zr_fix(Machine.word(writer)))
  argv = zr_spawn_vector(words)
  envp = zr_os_environ()
  if env != QNIL
    envp = zr_spawn_vector(env)
  end
  pid = Machine.sword(fork())
  if pid == 0
    err = zr_exec_options(options)
    if err == 0
      execve(RString.ptr(path), argv, envp)
      err = zr_errno()
    end
    word = Machine.slot(8)
    Machine.store64(word, 0, err)
    write(writer, word, 8)
    _exit(Machine.i32(127))
  end
  failure = zr_errno()
  close(writer)
  free(argv)
  if env != QNIL
    free(envp)
  end
  if pid < 0
    close(reader)
    return zr_fix(0 - failure)
  end
  word = Machine.slot(8)
  got = read(reader, word, 8)
  close(reader)
  if got == 8
    status = Machine.slot(8)
    waitpid(Machine.i32(pid), status, Machine.i32(0))
    return zr_fix(0 - Machine.load64(word, 0))
  end
  zr_fix(pid)
end

# execve in this process after the options: answers only when it could
# not, with the negated errno.
sig [Value, Value, Value, Value] => Value
machine def zr_exec_with(path, words, env, options)
  err = zr_exec_options(options)
  if err != 0
    return zr_fix(0 - err)
  end
  argv = zr_spawn_vector(words)
  envp = zr_os_environ()
  if env != QNIL
    envp = zr_spawn_vector(env)
  end
  execve(RString.ptr(path), argv, envp)
  err = zr_errno()
  free(argv)
  if env != QNIL
    free(envp)
  end
  zr_fix(0 - err)
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
