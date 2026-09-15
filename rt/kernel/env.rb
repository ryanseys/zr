# The program's surroundings: its arguments, its name, the process
# environment and the working directory.
Machine.import "setenv", [Ptr, Ptr, I32] => I32
Machine.import "unsetenv", [Ptr] => I32
Machine.import "getcwd", [Ptr, Word] => Ptr

G_ARGV = 36
G_AT_EXIT = 37
G_ARGV0 = 53

# `ARGV` from the C arguments, the program's own name left out.
sig [I32, Ptr] => Void
machine def zr_args_init(argc, argv)
  args = zr_ary_new(4)
  table = zr_os_argv(argc, argv)
  i = 1
  while table != 0 && Machine.load64(table, 0) != 0 && Machine.load64(table + (i * 8), 0) != 0
    arg = Machine.ptr(Machine.load64(table + (i * 8), 0))
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

# The exit status of the program. While the handlers run, last first,
# `$!` is the exception that ends it; a handler's error is printed and
# makes the status 1, a handler's `exit` sets it. Then the uncaught
# exception `exc`, if any, is printed, unless it is a SystemExit or a
# signal other than Interrupt. An uncaught SignalException ends the
# process by its signal.
sig [Value] => Word
machine def zr_program_end(exc)
  status = 0
  if exc != QUNDEF
    status = zr_system_exit_p(exc) ? zr_exit_status(exc) : 1
    zr_errinfo_set(exc)
  end
  # The main thread's fiber scheduler runs its fibers to their end
  # first, then the EXIT trap, as rb_vm_trap_exit runs before the
  # at_exit handlers.
  status = zr_program_end_hook(zr_send(zr_global(G_FIBER), Machine.id(:finalize_scheduler), 0, 0), status, exc)
  status = zr_program_end_hook(zr_send(zr_core_class(Machine.id(:Signal)), Machine.id(:exit_trap), 0, 0), status, exc)
  hooks = zr_global(G_AT_EXIT)
  if !zr_special_p(hooks)
    while RArray.len(hooks) > 0
      blk = zr_ary_pop(hooks, 0, 0, Machine.value(QNIL), Machine.value(QNIL))
      status = zr_program_end_hook(zr_yield(blk, 0, 0), status, exc)
    end
  end
  signo = 0
  if exc != QUNDEF && !zr_system_exit_p(exc)
    signo = zr_signal_of(exc)
    if signo == 0 || zr_is_a(exc, zr_core_class(Machine.id(:Interrupt)))
      zr_error_print(exc)
    end
  end
  # Whatever the streams hold is written now, as CRuby's teardown
  # writes it. `exit!` reaches none of this.
  if zr_send(zr_core_class(Machine.id(:IO)), Machine.id(:flush_pending), 0, 0) == QUNDEF
    Task.set_pending(zr_task(), Machine.value(QNIL))
  end
  zr_finalizers_at_exit()
  # A finalizer writes like anything else, so what it wrote waits in a
  # buffer of its own until now.
  if zr_send(zr_core_class(Machine.id(:IO)), Machine.id(:flush_pending), 0, 0) == QUNDEF
    Task.set_pending(zr_task(), Machine.value(QNIL))
  end
  if signo != 0
    zr_die_by_signal(signo)
  end
  status
end

# A handler at exit ran and answered `r`: a SystemExit it raised sets
# the status, and any other error is printed and makes the status 1.
sig [Value, Word, Value] => Word
machine def zr_program_end_hook(r, status, exc)
  if r != QUNDEF
    return status
  end
  raised = Task.pending(zr_task())
  Task.set_pending(zr_task(), Machine.value(QNIL))
  if zr_system_exit_p(raised)
    return zr_exit_status(raised)
  end
  zr_error_print_upto(raised, exc)
  1
end

# The signal an uncaught SignalException carries, or 0.
sig [Value] => Word
machine def zr_signal_of(exc)
  if zr_special_p(exc) || !zr_is_a(exc, zr_core_class(Machine.id(:SignalException)))
    return 0
  end
  n = zr_send(exc, Machine.id(:signo), 0, 0)
  if !zr_fixnum_p(n)
    Task.set_pending(zr_task(), Machine.value(QNIL))
    return 0
  end
  zr_fix2long(n)
end

# The process ends by `signo` itself: the signal's default action back
# in place, then the signal sent to this process, as CRuby's
# ruby_default_signal does.
sig [Word] => Void
machine def zr_die_by_signal(signo)
  signal(Machine.i32(signo), Machine.ptr(0))
  kill(getpid(), Machine.i32(signo))
end

sig [Value] => Word
machine def zr_exit_status(exc)
  zr_fix2long(zr_send(exc, Machine.id(:status), 0, 0))
end

sig [Value] => Bool
machine def zr_system_exit_p(exc)
  !zr_special_p(exc) && zr_is_a(exc, zr_core_class(Machine.id(:SystemExit)))
end

# The program's entry: `$0` and `$PROGRAM_NAME` name its file, in a
# frozen String that `Process.argv0` keeps when `$0` changes.
sig [Ptr, Word] => Void
machine def zr_program_start(file, len)
  name = zr_str_new(file, len)
  RBasic.set_flags(name, RBasic.flags(name) | FL_FREEZE)
  zr_set_global(G_ARGV0, name)
  zr_gvar_set(Machine.id(:$0), name)
end

sig [] => Value
machine def zr_program_name
  zr_global(G_ARGV0)
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
  table = zr_os_environ()
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
  buf = zr_xmalloc(4096)
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

sig [] => Value
machine def zr_process_id
  zr_fix(Machine.word(getpid()))
end

Machine.import "getuid", [] => I32
Machine.import "geteuid", [] => I32
Machine.import "getgid", [] => I32
Machine.import "getegid", [] => I32

# The process's ids: 0 uid, 1 euid, 2 gid, 3 egid.
sig [Value] => Value
machine def zr_process_ids(which)
  w = zr_fix2long(which)
  if w == 0
    return zr_fix(Machine.word(getuid()))
  elsif w == 1
    return zr_fix(Machine.word(geteuid()))
  elsif w == 2
    return zr_fix(Machine.word(getgid()))
  end
  zr_fix(Machine.word(getegid()))
end

# 62 random bits from the system, for a seed nobody chose.
sig [] => Value
machine def zr_random_seed
  high = zr_os_random()
  low = zr_os_random()
  zr_fix(((high << 30) | (low >> 2)) & 4611686018427387903)
end

Machine.sig :top, [] => Value

# The files the compiler's own eval road loaded, which the program did
# not ask for and so never sees in $LOADED_FEATURES.
G_HIDDEN_FEATURES = 50

sig [] => Value
machine def zr_hidden_features
  list = zr_global(G_HIDDEN_FEATURES)
  if zr_special_p(list)
    list = zr_ary_new(64)
    zr_set_global(G_HIDDEN_FEATURES, list)
  end
  list
end

# The real paths of the files the program required, as CRuby's
# loaded_features_realpaths holds them: a file reached again through a
# symlink or another spelling of its directory runs no second time.
G_REAL_FEATURES = 60

sig [] => Value
machine def zr_real_features
  list = zr_global(G_REAL_FEATURES)
  if zr_special_p(list)
    list = zr_ary_new(64)
    zr_set_global(G_REAL_FEATURES, list)
  end
  list
end

# realpath(3) of `path`, or `path` itself where no file is there, as for
# a unit the program was compiled with and runs away from its source.
sig [Value] => Value
machine def zr_feature_real_path(path)
  p = zr_os_realpath(RString.ptr(path))
  if p == 0
    return path
  end
  real = zr_str_new(p, zr_cstr_len(p))
  free(p)
  real
end

# `require`, `require_relative` (kind 0 and 1) and `load` (2) of the
# file at `path`, whose toplevel is `fn`: a require runs it once, as
# $LOADED_FEATURES records; a failed run leaves no record.
#
# Kind 3 is the eval road, which a program that evals carries: it, and
# every require made while it runs, is recorded in the hidden list
# instead. The program's own first require of one of those files runs
# nothing again; it records the file and answers true, as the first
# load would.
sig [Value, Ptr, Word] => Value
machine def zr_require(path, fn, kind)
  zr_require_run(path, fn, kind, true)
end

# The same for a require whose name the program computed: Kernel#require
# found the file and stands in its own frame, so the file's toplevel runs
# under that one. `fn` is the toplevel's address as an Integer.
sig [Value, Value, Value] => Value
machine def zr_require_computed(path, fn, kind)
  zr_require_run(path, Machine.ptr(zr_fix2long(fn)), zr_fix2long(kind), false)
end

sig [Value, Ptr, Word, Bool] => Value
machine def zr_require_run(path, fn, kind, framed)
  # A file the program was not compiled with has no toplevel to run.
  if Machine.word(fn) == 0
    return zr_load_error_in(kind == 1 ? Machine.id(:require_relative) : (kind == 2 ? Machine.id(:load) : Machine.id(:require)), RString.ptr(path), RString.len(path))
  end
  depth = Machine.static(:hidden_requires, 8)
  hidden = kind == 3 || Machine.load64(depth, 0) > 0
  visible = zr_gvar_get(Machine.id(:$LOADED_FEATURES))
  features = hidden ? zr_hidden_features() : visible
  real = Machine.value(QNIL)
  if kind != 2
    if zr_ary_has_string(visible, path) || (hidden && zr_ary_has_string(features, path))
      return Machine.value(QFALSE)
    end
    if !hidden && zr_ary_has_string(zr_hidden_features(), path)
      zr_ary_push(visible, path)
      return Machine.value(QTRUE)
    end
    if !hidden
      real = zr_feature_real_path(path)
      if zr_ary_has_string(zr_real_features(), real)
        return Machine.value(QFALSE)
      end
      zr_ary_push(zr_real_features(), real)
    end
    zr_ary_push(features, path)
  end
  if hidden
    Machine.store64(depth, 0, Machine.load64(depth, 0) + 1)
  end
  mid = 0
  if framed
    mid = kind == 1 ? Machine.id(:require_relative) : (kind == 2 ? Machine.id(:load) : Machine.id(:require))
  end
  r = zr_run_top(fn, mid)
  if hidden
    Machine.store64(depth, 0, Machine.load64(depth, 0) - 1)
  end
  if r == QUNDEF
    # The files it required on the way stay loaded.
    if kind != 2
      zr_ary_delete_string(features, path)
    end
    if real != QNIL
      zr_ary_delete_string(zr_real_features(), real)
    end
    return r
  end
  Machine.value(QTRUE)
end

# The file's toplevel, run under the frame of the Kernel method `mid`,
# as a backtrace through a require shows it; under the caller's frame
# when `mid` is 0.
sig [Ptr, Word] => Value
machine def zr_run_top(fn, mid)
  if mid == 0
    return Machine.call(:top, fn)
  end
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
  Frame.set_defined(rec, Machine.value(QNIL))
  Task.set_top(t, rec)
  r = Machine.call(:top, fn)
  Task.set_top(t, Frame.prev(rec))
  r
end

# What the compiler lays out for a require whose name the program
# computes (lib/ze0/zr.rb, `load_tables`): the count of files compiled
# in, their rows, and five (bytes, length) texts.
Machine.struct :LoadTable, units: Word, rows: Ptr, roots: Ptr, roots_len: Word, missing: Ptr, missing_len: Word,
                           preloaded: Ptr, preloaded_len: Word, ext: Ptr, ext_len: Word, spots: Ptr, spots_len: Word,
                           prefix: Ptr, prefix_len: Word

sig [] => Ptr
machine def zr_load_table
  Machine.ptr(Machine.load64(Machine.extern(:zr_load_tables), 0))
end

# The compiled toplevel of the program's file at `path`, as an Integer
# address, or nil: each row is (path bytes, length, toplevel), so a
# require whose name the program computes still finds a file compiled in.
sig [Value] => Value
machine def zr_unit_for(path)
  t = zr_load_table()
  i = 0
  while i < LoadTable.units(t)
    row = LoadTable.rows(t) + (i * 24)
    if zr_bytes_eq(Machine.ptr(Machine.load64(row, 0)), Machine.load64(row, 8), RString.ptr(path), RString.len(path))
      return zr_fix(Machine.load64(row, 16))
    end
    i += 1
  end
  Machine.value(QNIL)
end

# What a require whose name the program computes reads, one name a line:
# 0 for the library directories the program was compiled against, which
# it searches after $LOAD_PATH; 1 for the features ruby carries that this
# runtime has no file for; 2 for the features ruby loaded before the
# program; 3 for the directory of this runtime's native halves; 4 for
# error_highlight's spots; 5 for the compiling ruby's install layout.
sig [Value] => Value
machine def zr_load_names(which)
  t = zr_load_table()
  w = zr_fix2long(which)
  if w == 0
    return zr_str_new(LoadTable.roots(t), LoadTable.roots_len(t))
  elsif w == 1
    return zr_str_new(LoadTable.missing(t), LoadTable.missing_len(t))
  elsif w == 2
    return zr_str_new(LoadTable.preloaded(t), LoadTable.preloaded_len(t))
  elsif w == 4
    return zr_str_new(LoadTable.spots(t), LoadTable.spots_len(t))
  elsif w == 5
    return zr_str_new(LoadTable.prefix(t), LoadTable.prefix_len(t))
  end
  zr_str_new(LoadTable.ext(t), LoadTable.ext_len(t))
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

# `a` without the last String equal to `s`.
sig [Value, Value] => Void
machine def zr_ary_delete_string(a, s)
  i = RArray.len(a)
  while i > 0
    i -= 1
    e = zr_ary_at(a, i)
    if !zr_special_p(e) && zr_type(e) == T_STRING && zr_bytes_eq(RString.ptr(e), RString.len(e), RString.ptr(s), RString.len(s))
      zr_ary_splice(a, zr_fix(i), zr_fix(1), zr_ary_new(0))
      return
    end
  end
end

# A LoadError for a file nothing answers, with CRuby's message, raised
# under Kernel#require_relative's frame.
sig [Ptr, Word] => Value
machine def zr_load_error(path, len)
  zr_load_error_in(Machine.id(:require_relative), path, len)
end

# The same under the frame of Kernel's `mid`.
sig [Word, Ptr, Word] => Value
machine def zr_load_error_in(mid, path, len)
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
  Frame.set_defined(rec, Machine.value(QNIL))
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
# directory, 2 for a regular file, 3 for anything else.
sig [Value] => Value
machine def zr_path_kind(path)
  buf = zr_xmalloc(STAT_LEN)
  r = Machine.word(stat(RString.ptr(path), buf))
  mode = zr_os_stat_mode(buf) & S_IFMT
  free(buf)
  if r != 0
    return zr_fix(0)
  end
  if mode == S_IFDIR
    return zr_fix(1)
  end
  if mode == S_IFREG
    return zr_fix(2)
  end
  zr_fix(3)
end

# st_mode's file type bits, which POSIX names the same everywhere.
S_IFMT = 61440
S_IFDIR = 16384
S_IFREG = 32768

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

# The whole process sleeps `ns` nanoseconds, or until a signal comes:
# true when the time passed, false when a signal cut the sleep short
# and its handlers ran.
sig [Value] => Value
machine def zr_nanosleep(ns)
  n = zr_fix2long(ns)
  ts = Machine.slot(16)
  Machine.store64(ts, 0, n / 1000000000)
  Machine.store64(ts, 8, n % 1000000000)
  if nanosleep(ts, 0) == Machine.i32(0)
    return Machine.value(QTRUE)
  end
  if zr_trap_check() == QUNDEF
    return Machine.value(QUNDEF)
  end
  Machine.value(QFALSE)
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

Machine.import "getpwnam", [Ptr] => Ptr
Machine.import "getpwuid", [I32] => Ptr

# A user's home directory, or nil where no such user exists. A nil name
# asks for this process's.
sig [Value] => Value
machine def zr_home_dir(name)
  pw = name == QNIL ? getpwuid(getuid()) : getpwnam(RString.ptr(name))
  if pw == 0
    return Machine.value(QNIL)
  end
  dir = zr_os_passwd_dir(pw)
  if dir == 0
    return Machine.value(QNIL)
  end
  zr_str_new(dir, zr_cstr_len(dir))
end

Machine.import "getgrnam", [Ptr] => Ptr
Machine.import "getgrgid", [I32] => Ptr
Machine.import "setpwent", [] => Void
Machine.import "endpwent", [] => Void
Machine.import "getpwent", [] => Ptr
Machine.import "setgrent", [] => Void
Machine.import "endgrent", [] => Void
Machine.import "getgrent", [] => Ptr
Machine.import "sysconf", [I32] => Word
Machine.import "confstr", [I32, Ptr, Word] => Word
Machine.import "pathconf", [Ptr, I32] => Word
Machine.import "uname", [Ptr] => I32
Machine.import "getlogin", [] => Ptr

# A C string as a Ruby String, and a null pointer as nil.
sig [Ptr] => Value
machine def zr_cstr_str(text)
  if text == 0
    return Machine.value(QNIL)
  end
  zr_str_new(text, zr_cstr_len(text))
end

sig [Value] => Value
machine def zr_pw_name(name)
  zr_os_passwd_row(getpwnam(RString.ptr(name)))
end

sig [Value] => Value
machine def zr_pw_uid(uid)
  zr_os_passwd_row(getpwuid(Machine.i32(zr_fix2long(uid))))
end

sig [] => Value
machine def zr_pw_next
  zr_os_passwd_row(getpwent())
end

sig [] => Value
machine def zr_pw_rewind
  setpwent()
  Machine.value(QNIL)
end

sig [] => Value
machine def zr_pw_done
  endpwent()
  Machine.value(QNIL)
end

# The four fields of darwin's group: name at 0, password at 8, gid at 16,
# and a null-ended array of member names at 24.
sig [Ptr] => Value
machine def zr_gr_row(gr)
  if gr == 0
    return Machine.value(QNIL)
  end
  out = zr_ary_new(4)
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(gr, 0))))
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(gr, 8))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(gr, 16))))
  members = zr_ary_new(4)
  names = Machine.ptr(Machine.load64(gr, 24))
  if names != 0
    name = Machine.ptr(Machine.load64(names, 0))
    while name != 0
      zr_ary_push(members, zr_str_new(name, zr_cstr_len(name)))
      names = names + 8
      name = Machine.ptr(Machine.load64(names, 0))
    end
  end
  zr_ary_push(out, members)
  out
end

sig [Value] => Value
machine def zr_gr_name(name)
  zr_gr_row(getgrnam(RString.ptr(name)))
end

sig [Value] => Value
machine def zr_gr_gid(gid)
  zr_gr_row(getgrgid(Machine.i32(zr_fix2long(gid))))
end

sig [] => Value
machine def zr_gr_next
  zr_gr_row(getgrent())
end

sig [] => Value
machine def zr_gr_rewind
  setgrent()
  Machine.value(QNIL)
end

sig [] => Value
machine def zr_gr_done
  endgrent()
  Machine.value(QNIL)
end

sig [] => Value
machine def zr_nprocessors
  zr_fix(sysconf(Machine.i32(SC_NPROCESSORS_ONLN)))
end

# A sysconf or pathconf answer, and nil where the name has no limit.
sig [Value] => Value
machine def zr_sysconf(name)
  got = sysconf(Machine.i32(zr_fix2long(name)))
  if got == 0 - 1
    return Machine.value(QNIL)
  end
  zr_fix(got)
end

sig [Value, Value] => Value
machine def zr_pathconf(path, name)
  got = pathconf(RString.ptr(path), Machine.i32(zr_fix2long(name)))
  if got == 0 - 1
    return Machine.value(QNIL)
  end
  zr_fix(got)
end

# A confstr answer. The first call asks for the length, which is what
# confstr reports when the buffer is empty.
sig [Value] => Value
machine def zr_confstr(name)
  which = Machine.i32(zr_fix2long(name))
  len = confstr(which, Machine.ptr(0), 0)
  if len == 0
    return Machine.value(QNIL)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_reserve(b, len)
  confstr(which, Buf.ptr(b), len)
  Buf.set_len(b, len - 1)
  zr_buf_take(b)
end

sig [] => Value
machine def zr_login_name
  zr_cstr_str(getlogin())
end

# uname's first five fields: sysname, nodename, release, version and
# machine.
sig [] => Value
machine def zr_uname
  buf = Machine.slot(UTSNAME_LEN)
  if uname(buf) != 0
    return Machine.value(QNIL)
  end
  out = zr_ary_new(5)
  at = 0
  while at < UTSNAME_FIELD * 5
    zr_ary_push(out, zr_cstr_str(buf + at))
    at = at + UTSNAME_FIELD
  end
  out
end
