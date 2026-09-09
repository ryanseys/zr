# The program's surroundings: its arguments, its name, the process
# environment and the working directory.
Machine.import "setenv", [Ptr, Ptr, I32] => I32
Machine.import "unsetenv", [Ptr] => I32
Machine.import "_NSGetEnviron", [] => Ptr
Machine.import "getcwd", [Ptr, Word] => Ptr

G_ARGV = 36
G_AT_EXIT = 37

# `ARGV` from the C arguments, the program's own name left out.
sig [I32, Ptr] => Void
machine def zr_args_init(argc, argv)
  args = zr_ary_new(4)
  i = 1
  while i < Machine.word(argc)
    arg = Machine.ptr(Machine.load64(argv + (i * 8), 0))
    zr_ary_push(args, zr_str_new(arg, zr_cstr_len(arg)))
    i += 1
  end
  zr_set_global(G_ARGV, args)
end

sig [Ptr] => Word
machine def zr_cstr_len(p)
  n = 0
  while Machine.word(Machine.load8(p + n, 0)) != 0
    n += 1
  end
  n
end

sig [] => Value
machine def zr_program_args
  zr_global(G_ARGV)
end

# `at_exit`: the handlers, run last first when the program ends.
sig [Value] => Value
machine def zr_at_exit_add(blk)
  hooks = zr_global(G_AT_EXIT)
  if zr_special_p(hooks)
    hooks = zr_ary_new(4)
    zr_set_global(G_AT_EXIT, hooks)
  end
  zr_ary_push(hooks, blk)
  blk
end

# The exit status of the program: the handlers run in reverse, each
# one's error printed and passed over; then the uncaught exception
# `exc`, if any, is printed, unless it is a SystemExit. A handler's
# own `exit` sets the status.
sig [Value] => Word
machine def zr_program_end(exc)
  status = 0
  if exc != QUNDEF
    status = zr_system_exit_p(exc) ? zr_exit_status(exc) : 1
  end
  hooks = zr_global(G_AT_EXIT)
  if !zr_special_p(hooks)
    while RArray.len(hooks) > 0
      blk = zr_ary_pop(hooks, 0, 0, Machine.value(QNIL), Machine.value(QNIL))
      r = zr_yield(blk, 0, 0)
      if r == QUNDEF
        raised = Task.pending(zr_task())
        Task.set_pending(zr_task(), Machine.value(QNIL))
        if zr_system_exit_p(raised)
          status = zr_exit_status(raised)
        else
          zr_error_print(raised)
        end
      end
    end
  end
  if exc != QUNDEF && !zr_system_exit_p(exc)
    zr_error_print(exc)
  end
  status
end

sig [Value] => Word
machine def zr_exit_status(exc)
  zr_fix2long(zr_send(exc, Machine.id(:status), 0, 0))
end

sig [Value] => Bool
machine def zr_system_exit_p(exc)
  !zr_special_p(exc) && zr_is_a(exc, zr_core_class(Machine.id(:SystemExit)))
end

# The program's entry: `$0` and `$PROGRAM_NAME` name its file.
sig [Ptr, Word] => Void
machine def zr_program_start(file, len)
  zr_gvar_set(Machine.id(:$0), zr_str_new(file, len))
end

sig [Value] => Value
machine def zr_environment_get(name)
  p = getenv(RString.ptr(name))
  if p == 0
    return Machine.value(QNIL)
  end
  zr_str_new(p, zr_cstr_len(p))
end

# `ENV[name] = value`, or the variable removed for nil.
sig [Value, Value] => Value
machine def zr_environment_set(name, value)
  if value == QNIL
    unsetenv(RString.ptr(name))
  else
    setenv(RString.ptr(name), RString.ptr(value), Machine.i32(1))
  end
  value
end

# Every `NAME=value` string of the environment.
sig [] => Value
machine def zr_environment_list
  out = zr_ary_new(8)
  table = Machine.ptr(Machine.load64(_NSGetEnviron(), 0))
  if table == 0
    return out
  end
  i = 0
  while Machine.load64(table + (i * 8), 0) != 0
    entry = Machine.ptr(Machine.load64(table + (i * 8), 0))
    zr_ary_push(out, zr_str_new(entry, zr_cstr_len(entry)))
    i += 1
  end
  out
end

# The working directory, or a stop where the host has none.
sig [] => Value
machine def zr_getcwd
  buf = malloc(4096)
  p = getcwd(buf, 4096)
  if p == 0
    zr_bug(Machine.bytes("the working directory is not available here\n"), 44)
  end
  s = zr_str_new(buf, zr_cstr_len(buf))
  free(buf)
  s
end

# The file of the frame that called the core method running now.
sig [] => Value
machine def zr_caller_file
  rec = zr_frame_with_file(Frame.prev(Task.top(zr_task())))
  if rec == 0
    return Machine.value(QNIL)
  end
  meta = Frame.meta(rec)
  zr_str_new(FrameMeta.file(meta), FrameMeta.file_len(meta))
end

Machine.import "getpid", [] => I32
Machine.import "arc4random", [] => I32

sig [] => Value
machine def zr_process_id
  zr_fix(Machine.word(getpid()))
end

# 62 random bits from the system, for a seed nobody chose.
sig [] => Value
machine def zr_random_seed
  high = Machine.word(arc4random()) & 4294967295
  low = Machine.word(arc4random()) & 4294967295
  zr_fix(((high << 30) | (low >> 2)) & 4611686018427387903)
end
