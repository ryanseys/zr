# The program's surroundings: its arguments, its name, the process
# environment and the working directory.
Machine.import "setenv", [Ptr, Ptr, I32] => I32
Machine.import "unsetenv", [Ptr] => I32
Machine.import "_NSGetEnviron", [] => Ptr
Machine.import "getcwd", [Ptr, Word] => Ptr

G_ARGV = 36

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

sig [] => Value
machine def zr_process_id
  zr_fix(Machine.word(getpid()))
end
