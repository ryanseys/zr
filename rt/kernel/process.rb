# Child processes: posix_spawn, which is not variadic, with a pipe
# for the output backticks collect, and waitpid for the status.
Machine.import "posix_spawnp", [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => I32
Machine.import "posix_spawn_file_actions_init", [Ptr] => I32
Machine.import "posix_spawn_file_actions_adddup2", [Ptr, I32, I32] => I32
Machine.import "posix_spawn_file_actions_addclose", [Ptr, I32] => I32
Machine.import "posix_spawn_file_actions_destroy", [Ptr] => I32
Machine.import "waitpid", [I32, Ptr, I32] => I32
Machine.import "pipe", [Ptr] => I32
Machine.import "getppid", [] => I32
Machine.import "kill", [I32, I32] => I32
Machine.import "execvp", [Ptr, Ptr] => I32

# Spawn `words` (an Array of Strings, the program first) with the
# parent's environment; `out` is a descriptor the child writes its
# stdout to, or nil. The child's pid, or the errno.
sig [Value, Value] => Value
machine def zr_proc_spawn(words, out)
  n = RArray.len(words)
  argv = malloc((n + 1) * 8)
  i = 0
  while i < n
    Machine.store64(argv + (i * 8), 0, Machine.word(RString.ptr(zr_ary_at(words, i))))
    i += 1
  end
  Machine.store64(argv + (n * 8), 0, 0)
  actions = Machine.slot(16)
  posix_spawn_file_actions_init(actions)
  if out != QNIL
    fd = Machine.i32(zr_fix2long(out))
    posix_spawn_file_actions_adddup2(actions, fd, Machine.i32(1))
    posix_spawn_file_actions_addclose(actions, fd)
  end
  pid = Machine.slot(8)
  Machine.store64(pid, 0, 0)
  envp = Machine.ptr(Machine.load64(_NSGetEnviron(), 0))
  r = posix_spawnp(pid, RString.ptr(zr_ary_at(words, 0)), actions, 0, argv, envp)
  posix_spawn_file_actions_destroy(actions)
  free(argv)
  if r != Machine.i32(0)
    return zr_fix(0 - Machine.word(r))
  end
  zr_fix(Machine.word(Machine.load32(pid, 0)))
end

# execvp: the process becomes the command; answers only when it could
# not, with the negated errno.
sig [Value] => Value
machine def zr_proc_exec(words)
  n = RArray.len(words)
  argv = malloc((n + 1) * 8)
  i = 0
  while i < n
    Machine.store64(argv + (i * 8), 0, Machine.word(RString.ptr(zr_ary_at(words, i))))
    i += 1
  end
  Machine.store64(argv + (n * 8), 0, 0)
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
  out = zr_ary_new(2)
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(fds, 0))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(fds, 4))))
  out
end

sig [] => Value
machine def zr_proc_ppid
  zr_fix(Machine.word(getppid()))
end

sig [Value, Value] => Value
machine def zr_proc_kill(pid, signal)
  zr_io_status(kill(Machine.i32(zr_fix2long(pid)), Machine.i32(zr_fix2long(signal))))
end
