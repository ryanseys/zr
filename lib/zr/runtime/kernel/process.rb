module Zr::Kern
  # Child processes: `zr_os_spawn`, a pipe for the output that backticks
  # collect, and waitpid for the status.

  # Makes a NULL-terminated char* vector from an Array of Strings, with
  # malloc.
  #: (value) -> ptr
  def zr_spawn_vector(words)
    n = RArray[words].len
    vector = zr_xmalloc((n + 1) * 8)
    i = 0
    while i < n
      Machine.store64(vector + (i * 8), 0, Machine.word(RString[zr_ary_at(words, i)].ptr))
      i += 1
    end
    Machine.store64(vector + (n * 8), 0, 0)
    vector
  end

  # The argv of /bin/sh running the file `path` with the arguments after
  # the first of the `n` words in `argv`: "sh", the path, then those.
  #: (value, ptr, word) -> ptr
  def zr_shell_vector(path, argv, n)
    vector = zr_xmalloc((n + 2) * 8)
    Machine.store64(vector, 0, Machine.word(Machine.bytes("sh\0")))
    Machine.store64(vector, 8, Machine.word(RString[path].ptr))
    i = 1
    while i < n
      Machine.store64(vector + ((i + 1) * 8), 0, Machine.load64(argv + (i * 8), 0))
      i += 1
    end
    Machine.store64(vector + ((n + 1) * 8), 0, 0)
    vector
  end

  # Starts child processes through posix_spawn (which is not variadic) on
  # an OS that has it. `zr_os_spawn` calls this with the OS's flags.

  # POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK, the same on darwin and
  # in musl.
  SPAWN_SIGNAL_FLAGS = 12

  # A child that ruby starts (disable_child_handler_fork_child) gets
  # SIGPIPE at its default action, even where the program ignores it, and
  # an empty signal mask. The exec puts each caught signal back to its
  # default, and keeps each ignored one. The set is the size of musl's
  # sigset_t; SIGPIPE's bit is the same in darwin's.
  #: (ptr) -> void
  def zr_spawn_signals(attributes)
    set = Machine.slot(128)
    Libc.memset(set, Machine.i32(0), 128)
    Libc.posix_spawnattr_setsigmask(attributes, set)
    Machine.store8(set + ((SIGNAL_PIPE - 1) / 8), 0, Machine.i8(1 << ((SIGNAL_PIPE - 1) % 8)))
    Libc.posix_spawnattr_setsigdefault(attributes, set)
  end

  # The same in a forked child, before its exec.
  #: () -> void
  def zr_child_signals
    old = Machine.slot(16)
    zr_os_sigaction(Machine.i32(SIGNAL_PIPE), SIGNAL_DEFAULT, old)
    zr_os_unblock_signals()
  end

  # Spawns `words` (an Array of Strings, program first). Returns the pid,
  # or the negated errno.
  # - `dups`: a flat Array of (child descriptor, source descriptor) pairs,
  #   applied in order.
  # - `closes`: the child's descriptors to close.
  # - `env`: the child's full environment as "KEY=value" strings, or nil
  #   to inherit it.
  # - `chdir`: the child's directory, or nil.
  # - `flags`: the OS's posix_spawnattr flags.
  #: (value, value, value, value, value, word) -> value
  def zr_posix_spawn(words, dups, closes, env, chdir, flags)
    argv = zr_spawn_vector(words)
    actions = Machine.slot(SPAWN_ACTIONS_LEN)
    Libc.posix_spawn_file_actions_init(actions)
    attributes = Machine.slot(SPAWN_ATTR_LEN)
    Libc.posix_spawnattr_init(attributes)
    Libc.posix_spawnattr_setflags(attributes, Machine.i32(flags | SPAWN_SIGNAL_FLAGS))
    zr_spawn_signals(attributes)
    n = RArray[dups].len
    i = 0
    while i < n
      from = zr_fix2long(zr_ary_at(dups, i + 1))
      to = zr_fix2long(zr_ary_at(dups, i))
      # A descriptor redirected to itself goes to the child even when it
      # is close-on-exec, as ruby clears the flag for it.
      if from == to && to > 2
        zr_os_spawn_keep(actions, to)
      else
        Libc.posix_spawn_file_actions_adddup2(actions, Machine.i32(from), Machine.i32(to))
      end
      # A child's standard stream blocks, as ruby makes it: a pipe from
      # IO.pipe is non-blocking, and a child that reads it before the
      # parent writes would get EAGAIN. The flag is on the open file, so
      # this clears it for the parent too, as in ruby.
      if zr_fix2long(zr_ary_at(dups, i)) <= 2
        zr_io_set_nonblock(zr_ary_at(dups, i + 1), zr_fix(0))
      end
      i += 2
    end
    n = RArray[closes].len
    i = 0
    while i < n
      Libc.posix_spawn_file_actions_addclose(actions, Machine.i32(zr_fix2long(zr_ary_at(closes, i))))
      i += 1
    end
    if chdir != QNIL
      Libc.posix_spawn_file_actions_addchdir_np(actions, RString[chdir].ptr)
    end
    envp = zr_os_environ()
    if env != QNIL
      envp = zr_spawn_vector(env)
    end
    pid = Machine.slot(8)
    Machine.store64(pid, 0, 0)
    r = Libc.posix_spawnp(pid, RString[zr_ary_at(words, 0)].ptr, actions, attributes, argv, envp)
    Libc.posix_spawn_file_actions_destroy(actions)
    Libc.posix_spawnattr_destroy(attributes)
    zr_xfree(argv)
    if env != QNIL
      zr_xfree(envp)
    end
    if r != Machine.i32(0)
      return zr_fix(0 - Machine.u32(r))
    end
    zr_fix(Machine.u32(Machine.load32(pid, 0)))
  end

  # Stores a limit that Process checked to fit an rlim_t, a Fixnum or a
  # Bignum such as RLIM_INFINITY, without an allocation.
  #: (word, value) -> void
  def zr_rlim_store(out, limit)
    if zr_fixnum_p(limit)
      Machine.store64(out, 0, zr_fix2long(limit))
    else
      zr_big_to_long(limit, out)
    end
  end

  # Where a pty's [master, slave] comes in the options of zr_exec_options,
  # after the eight that every spawn has.
  EXEC_TTY = 8

  # Applies to this process the options that posix_spawn cannot take, in
  # the order of rb_execarg_run_options: the process group (`pgroup` -1
  # keeps it, 0 makes a new one), the resource limits (`limits` contains
  # resource, soft, hard triples), the umask (-1 keeps it), the
  # descriptors, the directory, then the group and the user (-1 keeps
  # each). `options` is [dups, closes, chdir, pgroup, umask, limits, uid,
  # gid], and a pty's [master, slave] after them; `dups` and `closes` are
  # as for zr_posix_spawn.
  # Returns 0 or the errno. It allocates nothing, so a forked child can run
  # it before its exec.
  #: (value) -> word
  def zr_exec_options(options)
    dups = zr_ary_at(options, 0)
    closes = zr_ary_at(options, 1)
    chdir = zr_ary_at(options, 2)
    pgroup = zr_ary_at(options, 3)
    mask = zr_ary_at(options, 4)
    limits = zr_ary_at(options, 5)
    # A pty child starts its own session, with the slave as its
    # controlling terminal and its standard streams, as pty.c's chfunc
    # does. This occurs before all other options.
    if RArray[options].len > EXEC_TTY
      zr_exec_tty(zr_ary_at(options, EXEC_TTY))
    end
    group = zr_fix2long(pgroup)
    if group >= 0 && Libc.setpgid(Machine.i32(0), Machine.i32(group)) < Machine.i32(0)
      return zr_errno()
    end
    pair = Machine.slot(16)
    i = 0
    while i < RArray[limits].len
      zr_rlim_store(pair, zr_ary_at(limits, i + 1))
      zr_rlim_store(pair + 8, zr_ary_at(limits, i + 2))
      if Libc.setrlimit(Machine.i32(zr_fix2long(zr_ary_at(limits, i))), pair) < Machine.i32(0)
        return zr_errno()
      end
      i += 3
    end
    if zr_fix2long(mask) >= 0
      Libc.umask(Machine.i32(zr_fix2long(mask)))
    end
    i = 0
    while i < RArray[dups].len
      child = Machine.i32(zr_fix2long(zr_ary_at(dups, i)))
      source = Machine.i32(zr_fix2long(zr_ary_at(dups, i + 1)))
      # A dup of a descriptor onto itself only clears close-on-exec, as in
      # posix_spawn_file_actions_adddup2.
      if child == source
        zr_os_fcntl(child, Machine.i32(F_SETFD), 0)
      elsif Libc.dup2(source, child) < Machine.i32(0)
        return zr_errno()
      end
      # A standard stream blocks, as in zr_posix_spawn.
      if child <= Machine.i32(2)
        zr_io_set_nonblock(zr_ary_at(dups, i), zr_fix(0))
      end
      i += 2
    end
    i = 0
    while i < RArray[closes].len
      Libc.close(Machine.i32(zr_fix2long(zr_ary_at(closes, i))))
      i += 1
    end
    if chdir != QNIL && Libc.chdir(RString[chdir].ptr) < Machine.i32(0)
      return zr_errno()
    end
    if zr_fix2long(zr_ary_at(options, 7)) >= 0 && zr_os_setid(zr_sym(Machine.id(:setgid)), zr_ary_at(options, 7)) != zr_fix(0)
      return zr_errno()
    end
    if zr_fix2long(zr_ary_at(options, 6)) >= 0 && zr_os_setid(zr_sym(Machine.id(:setuid)), zr_ary_at(options, 6)) != zr_fix(0)
      return zr_errno()
    end
    0
  end

  # pty.c's start_new_session, obtain_ctty and drop_privilege for the
  # [master, slave] pair `tty`. It ignores the same errors that pty.c
  # ignores.
  #: (value) -> void
  def zr_exec_tty(tty)
    master = Machine.i32(zr_fix2long(zr_ary_at(tty, 0)))
    slave = Machine.i32(zr_fix2long(zr_ary_at(tty, 1)))
    Libc.setsid()
    Libc.close(master)
    zr_os_ioctl(slave, TIOCSCTTY, Machine.ptr(0))
    Libc.dup2(slave, Machine.i32(0))
    Libc.dup2(slave, Machine.i32(1))
    Libc.dup2(slave, Machine.i32(2))
    if Machine.sword(slave) > 2
      Libc.close(slave)
    end
    zr_os_setid(zr_sym(Machine.id(:seteuid)), zr_fix(Machine.u32(Libc.getuid())))
  end

  # A spawn through fork and execve, for the options that posix_spawn
  # cannot take. The child applies them, then runs the program at `path`.
  # If the child cannot start, it writes its errno to a pipe that an exec
  # closes, and exits. Returns the pid, or the negated errno.
  #: (value, value, value, value) -> value
  def zr_spawn_forked(path, words, env, options)
    ends = Machine.slot(8)
    if Libc.pipe(ends) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    reader = Machine.load32(ends, 0)
    writer = Machine.load32(ends, 4)
    zr_io_cloexec(zr_fix(Machine.u32(reader)))
    zr_io_cloexec(zr_fix(Machine.u32(writer)))
    argv = zr_spawn_vector(words)
    shell = zr_shell_vector(path, argv, RArray[words].len)
    envp = zr_os_environ()
    if env != QNIL
      envp = zr_spawn_vector(env)
    end
    pid = Machine.sword(Libc.fork())
    if pid == 0
      zr_child_signals()
      err = zr_exec_options(options)
      if err == 0
        Libc.execve(RString[path].ptr, argv, envp)
        err = zr_errno()
        # proc_exec_cmd: a file that is no executable format, such as a
        # script with no `#!` line, runs under /bin/sh.
        if err == ENOEXEC
          Libc.execve(Machine.bytes("/bin/sh\0"), shell, envp)
          err = zr_errno()
        end
      end
      word = Machine.slot(8)
      Machine.store64(word, 0, err)
      Libc.write(writer, word, 8)
      Libc._exit(Machine.i32(127))
    end
    failure = zr_errno()
    Libc.close(writer)
    # The parent closes a pty's slave now, as pty.c's establishShell does
    # after its fork, not after the child's exec: on darwin a slave that
    # this process still holds when the child exits loses what the child
    # wrote.
    if RArray[options].len > EXEC_TTY
      Libc.close(Machine.i32(zr_fix2long(zr_ary_at(zr_ary_at(options, EXEC_TTY), 1))))
    end
    zr_xfree(argv)
    zr_xfree(shell)
    if env != QNIL
      zr_xfree(envp)
    end
    if pid < 0
      Libc.close(reader)
      return zr_fix(0 - failure)
    end
    word = Machine.slot(8)
    got = Libc.read(reader, word, 8)
    Libc.close(reader)
    if got == 8
      status = Machine.slot(8)
      Libc.waitpid(Machine.i32(pid), status, Machine.i32(0))
      return zr_fix(0 - Machine.load64(word, 0))
    end
    zr_fix(pid)
  end

  # Applies the options, then calls execve in this process. It returns
  # only on failure, with the negated errno.
  #: (value, value, value, value) -> value
  def zr_exec_with(path, words, env, options)
    err = zr_exec_options(options)
    if err != 0
      return zr_fix(0 - err)
    end
    argv = zr_spawn_vector(words)
    envp = zr_os_environ()
    if env != QNIL
      envp = zr_spawn_vector(env)
    end
    Libc.execve(RString[path].ptr, argv, envp)
    err = zr_errno()
    zr_xfree(argv)
    if env != QNIL
      zr_xfree(envp)
    end
    zr_fix(0 - err)
  end

  # waitpid: returns [pid, raw status], or the negated errno.
  #: (value, value) -> value
  def zr_proc_wait(pid, flags)
    status = Machine.slot(8)
    Machine.store64(status, 0, 0)
    r = Libc.waitpid(Machine.i32(zr_fix2long(pid)), status, Machine.i32(zr_fix2long(flags)))
    while r < Machine.i32(0)
      failed = zr_io_retry()
      if failed != QNIL
        return failed
      end
      r = Libc.waitpid(Machine.i32(zr_fix2long(pid)), status, Machine.i32(zr_fix2long(flags)))
    end
    out = zr_ary_new(2)
    zr_ary_push(out, zr_fix(Machine.u32(r)))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(status, 0))))
    out
  end

  # Makes a pipe: returns [read end, write end], or the negated errno.
  #: () -> value
  def zr_io_pipe
    fds = Machine.slot(8)
    if Libc.pipe(fds) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    # Both ends are close-on-exec, as with rb_cloexec_pipe. If a write end
    # leaks into an unrelated child, the reader gets no end of file while
    # that child runs.
    read_end = zr_fix(Machine.u32(Machine.load32(fds, 0)))
    write_end = zr_fix(Machine.u32(Machine.load32(fds, 4)))
    zr_io_cloexec(read_end)
    zr_io_cloexec(write_end)
    out = zr_ary_new(2)
    zr_ary_push(out, read_end)
    zr_ary_push(out, write_end)
    out
  end

  # Returns the user and system time of `who` in seconds, as
  # `[utime, stime]`. These are the first two timevals of a rusage
  # (seconds, then microseconds).
  #: (value) -> value
  def zr_proc_rusage(who)
    ru = Machine.slot(144)
    Libc.getrusage(Machine.i32(zr_fix2long(who)), ru)
    out = zr_ary_new(2)
    zr_ary_push(out, zr_float_new(Machine.to_f64(Machine.load64(ru, 0)) + (Machine.to_f64(Machine.u32(Machine.load32(ru, 8))) / Machine.to_f64(1000000))))
    zr_ary_push(out, zr_float_new(Machine.to_f64(Machine.load64(ru, 16)) + (Machine.to_f64(Machine.u32(Machine.load32(ru, 24))) / Machine.to_f64(1000000))))
    out
  end

  #: () -> value
  def zr_proc_ppid
    zr_fix(Machine.u32(Libc.getppid()))
  end

  # `getpriority`: returns the niceness and the errno. A niceness of -1 is
  # a valid result, so the call clears errno first. Then only a failure of
  # this call sets it.
  #: (value, value) -> value
  def zr_proc_getpriority(which, who)
    zr_clear_errno()
    r = Machine.sword(Libc.getpriority(Machine.i32(zr_fix2long(which)), Machine.i32(zr_fix2long(who))))
    out = zr_ary_new(2)
    zr_ary_push(out, zr_fix(r))
    zr_ary_push(out, zr_fix(zr_errno()))
    out
  end

  #: (value, value, value) -> value
  def zr_proc_setpriority(which, who, priority)
    zr_io_status(Libc.setpriority(Machine.i32(zr_fix2long(which)), Machine.i32(zr_fix2long(who)), Machine.i32(zr_fix2long(priority))))
  end

  # The process group, the session and the groups. Each returns its id,
  # or the negated errno when the call fails.
  #: () -> value
  def zr_proc_getpgrp
    zr_io_failed(Machine.sword(Libc.getpgrp()))
  end

  #: (value) -> value
  def zr_proc_getpgid(pid)
    zr_io_failed(Machine.sword(Libc.getpgid(Machine.i32(zr_fix2long(pid)))))
  end

  #: (value, value) -> value
  def zr_proc_setpgid(pid, pgrp)
    zr_io_status(Libc.setpgid(Machine.i32(zr_fix2long(pid)), Machine.i32(zr_fix2long(pgrp))))
  end

  #: (value) -> value
  def zr_proc_getsid(pid)
    zr_io_failed(Machine.sword(Libc.getsid(Machine.i32(zr_fix2long(pid)))))
  end

  #: () -> value
  def zr_proc_setsid
    zr_io_failed(Machine.sword(Libc.setsid()))
  end

  # Returns the supplementary groups as an Array of ids, all of them: the
  # count comes first, as proc_getgroups asks getgroups(0, NULL).
  #: () -> value
  def zr_proc_groups
    n = zr_os_getgroups(0, Machine.ptr(0))
    if n < 0
      return zr_fix(0 - zr_errno())
    end
    list = zr_xmalloc((n + 1) * 4)
    n = zr_os_getgroups(n, list)
    if n < 0
      zr_xfree(list)
      return zr_fix(0 - zr_errno())
    end
    out = zr_ary_new(n)
    i = 0
    while i < n
      zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(list + (i * 4), 0))))
      i += 1
    end
    zr_xfree(list)
    out
  end

  #: (value, value) -> value
  def zr_proc_kill(pid, signal)
    zr_io_status(Libc.kill(Machine.i32(zr_fix2long(pid)), Machine.i32(zr_fix2long(signal))))
  end

  # Sends `signal` with kill(2) to every pid in `pids`, in one call as
  # rb_f_kill does. Thus a POSIX signal that this process sends to itself
  # is handled after all are sent. Returns 0, or the negated errno of the
  # first failure.
  #: (value, value) -> value
  def zr_proc_kill_all(pids, signal)
    i = 0
    while i < RArray[pids].len
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

  # `getrlimit`: returns `[cur, max]`, each rlim_t's bits as a signed
  # word, or the negated errno.
  #: (value) -> value
  def zr_proc_getrlimit(resource)
    limits = Machine.slot(16)
    if Libc.getrlimit(Machine.i32(zr_fix2long(resource)), limits) < Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    out = zr_ary_new(2)
    zr_ary_push(out, zr_int_from_word(Machine.load64(limits, 0)))
    zr_ary_push(out, zr_int_from_word(Machine.load64(limits, 8)))
    out
  end

  # `setrlimit`. Each limit is the signed word of its bits.
  #: (value, value, value) -> value
  def zr_proc_setrlimit(resource, cur, max)
    limits = Machine.slot(16)
    r = zr_index_operand(cur, limits)
    return r if r == QUNDEF
    r = zr_index_operand(max, limits + 8)
    return r if r == QUNDEF
    zr_io_status(Libc.setrlimit(Machine.i32(zr_fix2long(resource)), limits))
  end

  # `setreuid` (`group` false) or `setregid`. An id of -1 keeps the
  # current id. Returns 0, or the negated errno.
  #: (value, value, value) -> value
  def zr_proc_setreid(group, real, effective)
    r = Machine.i32(zr_fix2long(real))
    e = Machine.i32(zr_fix2long(effective))
    zr_io_status(group == QTRUE ? Libc.setregid(r, e) : Libc.setreuid(r, e))
  end

  # `setgroups` with an Array of group ids.
  #: (value) -> value
  def zr_proc_setgroups(ids)
    n = RArray[ids].len
    list = zr_xmalloc((n + 1) * 4)
    i = 0
    while i < n
      Machine.store32(list + (i * 4), 0, Machine.i32(zr_fix2long(zr_ary_at(ids, i))))
      i += 1
    end
    r = Libc.setgroups(Machine.i32(n), list)
    zr_xfree(list)
    zr_io_status(r)
  end

  #: (value, value) -> value
  def zr_proc_initgroups(user, gid)
    zr_io_status(Libc.initgroups(RString[user].ptr, Machine.i32(zr_fix2long(gid))))
  end

  # `fork`: returns the child's pid in the parent, 0 in the child, or the
  # negated errno.
  #: () -> value
  def zr_proc_fork
    zr_io_failed(Machine.sword(Libc.fork()))
  end

  # Ends a forked child, as CRuby's ruby_stop does. It runs the at_exit
  # handlers and flushes the streams as at the end of a program, then the
  # process exits. `exc` is the exception that the fork block raised, or
  # nil. The parent's frames below never see the exception.
  #: (value) -> value
  def zr_proc_child_exit(exc)
    Libc.exit(Machine.i32(zr_program_end(exc == QNIL ? Machine.value(QUNDEF) : exc)))
    Machine.value(QNIL)
  end

  # Runs the fork block `blk` in the child, then ends the child. A jump
  # out of the block (a `break`, `return` or `throw`) has no frame to go
  # to in the child. The exit handlers run, then the jump is reported
  # after `site` and the child exits 1, as rb_ec_cleanup does for a
  # TAG_BREAK.
  #: (value, value) -> value
  def zr_proc_child_run(blk, site)
    if zr_yield(blk, 0, 0) != QUNDEF
      return zr_proc_child_exit(Machine.value(QNIL))
    end
    t = zr_task()
    kind = Task[t].pending_kind
    pending = Task[t].pending
    Task[t].pending_kind = PENDING_RAISE
    Task[t].pending = Machine.value(QNIL)
    if kind == PENDING_RAISE
      return zr_proc_child_exit(pending)
    end
    zr_program_end(Machine.value(QUNDEF))
    zr_write_stderr(site)
    if kind == PENDING_BREAK
      zr_write_stderr(zr_str_new(Machine.bytes("unexpected break\n"), 17))
    elsif kind == PENDING_RETURN
      zr_write_stderr(zr_str_new(Machine.bytes("unexpected return\n"), 18))
    else
      zr_write_stderr(zr_str_new(Machine.bytes("unexpected throw\n"), 17))
    end
    Libc.exit(1)
    Machine.value(QNIL)
  end
end
