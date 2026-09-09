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
Machine.import "access", [Ptr, I32] => I32
Machine.import "stat", [Ptr, Ptr] => I32
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

Machine.sig :top, [] => Value

# `require`, `require_relative` (kind 0 and 1) and `load` (2) of the
# file at `path`, whose toplevel is `fn`: a require runs it once, as
# $LOADED_FEATURES records; a failed run leaves no record.
sig [Value, Ptr, Word] => Value
machine def zr_require(path, fn, kind)
  features = zr_gvar_get(Machine.id(:$LOADED_FEATURES))
  if kind != 2
    if zr_ary_has_string(features, path)
      return Machine.value(QFALSE)
    end
    zr_ary_push(features, path)
  end
  r = zr_run_top(fn, kind == 0 ? Machine.id(:require) : (kind == 1 ? Machine.id(:require_relative) : Machine.id(:load)))
  if r == QUNDEF
    if kind != 2
      zr_ary_pop(features, 0, 0, Machine.value(QNIL), Machine.value(QNIL))
    end
    return r
  end
  Machine.value(QTRUE)
end

# The file's toplevel, run under the frame of the Kernel method `mid`,
# as a backtrace through a require shows it.
sig [Ptr, Word] => Value
machine def zr_run_top(fn, mid)
  e = zr_find_method(zr_global(G_KERNEL), mid)
  rec = Machine.slot(Frame.size)
  t = zr_task()
  Frame.set_prev(rec, Task.top(t))
  Frame.set_meta(rec, MEntry.meta(e))
  Frame.set_line(rec, 0)
  Frame.set_serial(rec, 0)
  Frame.set_self(rec, zr_global(G_MAIN))
  Frame.set_cref(rec, Machine.value(QNIL))
  Frame.set_blk(rec, Machine.value(QNIL))
  Frame.set_nvalues(rec, 0)
  Frame.set_mid(rec, 0)
  Frame.set_svar(rec, Machine.value(QNIL))
  Frame.set_lastline(rec, Machine.value(QNIL))
  Task.set_top(t, rec)
  r = Machine.call(:top, fn)
  Task.set_top(t, Frame.prev(rec))
  r
end

sig [Value, Value] => Bool
machine def zr_ary_has_string(a, s)
  i = 0
  while i < RArray.len(a)
    e = zr_ary_at(a, i)
    if !zr_special_p(e) && zr_type(e) == T_STRING && zr_bytes_eq(RString.ptr(e), RString.len(e), RString.ptr(s), RString.len(s))
      return true
    end
    i += 1
  end
  false
end

# A LoadError for a file nothing answers, with CRuby's message, raised
# under Kernel#require_relative's frame.
sig [Ptr, Word] => Value
machine def zr_load_error(path, len)
  e = zr_find_method(zr_global(G_KERNEL), Machine.id(:require_relative))
  rec = Machine.slot(Frame.size)
  t = zr_task()
  Frame.set_prev(rec, Task.top(t))
  Frame.set_meta(rec, MEntry.meta(e))
  Frame.set_line(rec, 0)
  Frame.set_serial(rec, 0)
  Frame.set_self(rec, zr_global(G_MAIN))
  Frame.set_cref(rec, Machine.value(QNIL))
  Frame.set_blk(rec, Machine.value(QNIL))
  Frame.set_nvalues(rec, 0)
  Frame.set_mid(rec, 0)
  Frame.set_svar(rec, Machine.value(QNIL))
  Frame.set_lastline(rec, Machine.value(QNIL))
  Task.set_top(t, rec)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("cannot load such file -- "), 25)
  zr_buf_push(b, path, len)
  exc = zr_exc_new(zr_core_class(Machine.id(:LoadError)), zr_buf_take(b))
  zr_ivar_set(exc, Machine.id(:@path), zr_str_new(path, len))
  r = zr_raise(exc)
  Task.set_top(t, Frame.prev(rec))
  r
end

# Whether a path exists, and what it is: 0 for nothing, 1 for a
# directory, 2 for a regular file, 3 for anything else. Darwin's stat
# keeps st_mode as 16 bits at offset 4.
sig [Value] => Value
machine def zr_path_kind(path)
  buf = malloc(256)
  r = Machine.word(stat(RString.ptr(path), buf))
  mode = Machine.word(Machine.load8(buf + 5, 0)) & 240
  free(buf)
  if r != 0
    return zr_fix(0)
  end
  if mode == 64
    return zr_fix(1)
  end
  if mode == 128
    return zr_fix(2)
  end
  zr_fix(3)
end

Machine.import "clock_gettime", [I32, Ptr] => I32
Machine.import "clock_getres", [I32, Ptr] => I32
Machine.import "crypt", [Ptr, Ptr] => Ptr
Machine.import "nanosleep", [Ptr, Ptr] => I32

# Nanoseconds on the clock `id` names (darwin: 0 real time, 6
# monotonic).
sig [Value] => Value
machine def zr_clock_ns(id)
  ts = Machine.slot(16)
  clock_gettime(Machine.i32(zr_fix2long(id)), ts)
  zr_fix(Machine.load64(ts, 0) * 1000000000 + Machine.load64(ts, 8))
end

# The clock's resolution in nanoseconds.
sig [Value] => Value
machine def zr_clock_res_ns(id)
  ts = Machine.slot(16)
  clock_getres(Machine.i32(zr_fix2long(id)), ts)
  zr_fix(Machine.load64(ts, 0) * 1000000000 + Machine.load64(ts, 8))
end

# crypt(3) of the text with the salt.
sig [Value, Value] => Value
machine def zr_str_crypt(text, salt)
  out = crypt(RString.ptr(text), RString.ptr(salt))
  if out == 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("invalid salt"), 12)
  end
  zr_str_new(out, zr_cstr_len(out))
end

# The whole process sleeps `ns` nanoseconds.
sig [Value] => Value
machine def zr_nanosleep(ns)
  n = zr_fix2long(ns)
  ts = Machine.slot(16)
  Machine.store64(ts, 0, n / 1000000000)
  Machine.store64(ts, 8, n % 1000000000)
  nanosleep(ts, 0)
  Machine.value(QNIL)
end

Machine.import "tzset", [] => Void
Machine.import "localtime_r", [Ptr, Ptr] => Ptr

# The local zone at `secs` since the epoch: its offset east of UTC in
# seconds, whether daylight time is in effect, and its abbreviation.
sig [Value] => Value
machine def zr_time_local(secs)
  tzset()
  t = Machine.slot(8)
  Machine.store64(t, 0, zr_fix2long(secs))
  tm = Machine.slot(64)
  localtime_r(t, tm)
  out = zr_ary_new(3)
  zr_ary_push(out, zr_fix(Machine.load64(tm, 40)))
  zr_ary_push(out, zr_bool(Machine.word(Machine.load32(tm, 32)) > 0))
  zone = Machine.ptr(Machine.load64(tm, 48))
  zr_ary_push(out, zr_str_new(zone, zr_cstr_len(zone)))
  out
end

Machine.import "_exit", [I32] => Void

# `exit!`: the process ends now, with no handler run.
sig [Value] => Value
machine def zr_exit_now(status)
  _exit(Machine.i32(zr_fix2long(status)))
  Machine.value(QNIL)
end
