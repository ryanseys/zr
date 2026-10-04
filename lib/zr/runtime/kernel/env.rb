module Zr::Kern
  # The program's context: its arguments, its name, the process
  # environment and the working directory.

  G_ARGV = 36
  G_AT_EXIT = 37
  G_ARGV0 = 53

  # Makes `ARGV` from the C arguments, without the program's name.
  #: (i32, ptr) -> void
  def zr_args_init(argc, argv)
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

  #: (ptr) -> word
  def zr_cstr_len(p)
    n = 0
    while Machine.u8(Machine.load8(p + n, 0)) != 0
      n += 1
    end
    n
  end

  #: () -> value
  def zr_program_args
    zr_global(G_ARGV)
  end

  # `at_exit`: adds a handler. The handlers run in reverse order when the
  # program ends.
  #: (value) -> value
  def zr_at_exit_add(blk)
    blk = zr_block_proc(blk)
    hooks = zr_global(G_AT_EXIT)
    if zr_special_p(hooks)
      hooks = zr_ary_new(4)
      zr_set_global(G_AT_EXIT, hooks)
    end
    zr_ary_push(hooks, blk)
    blk
  end

  # Returns the exit status of the program. The handlers run in reverse
  # order, with `$!` set to the exception that ends the program. A
  # handler's error is printed and sets the status to 1. A handler's `exit`
  # sets the status. Then the uncaught exception `exc`, if there is one, is
  # printed, unless it is a SystemExit or a POSIX signal other than
  # Interrupt. An uncaught SignalException ends the process by its POSIX
  # signal.
  #: (value) -> word
  def zr_program_end(exc)
    status = 0
    if exc != QUNDEF
      status = zr_system_exit_p(exc) ? zr_exit_status(exc) : 1
      zr_errinfo_set(exc)
    end
    # First the main thread's fiber scheduler runs its fibers to their
    # end. Then the EXIT trap runs, because rb_vm_trap_exit runs before
    # the at_exit handlers.
    status = zr_program_end_hook(zr_send(zr_global(G_FIBER), Machine.id(:finalize_scheduler), 0, 0), status, exc)
    status = zr_program_end_hook(zr_send(zr_core_class(Machine.id(:Signal)), Machine.id(:exit_trap), 0, 0), status, exc)
    hooks = zr_global(G_AT_EXIT)
    if !zr_special_p(hooks)
      while RArray[hooks].len > 0
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
    # Flush all stream buffers, as CRuby's teardown does. `exit!` skips
    # all of this.
    if zr_send(zr_core_class(Machine.id(:IO)), Machine.id(:flush_pending), 0, 0) == QUNDEF
      Task[zr_task()].pending = Machine.value(QNIL)
    end
    zr_finalizers_at_exit()
    # A finalizer's output also goes to a buffer, so flush again.
    if zr_send(zr_core_class(Machine.id(:IO)), Machine.id(:flush_pending), 0, 0) == QUNDEF
      Task[zr_task()].pending = Machine.value(QNIL)
    end
    if signo != 0
      zr_die_by_signal(signo)
    end
    status
  end

  # Handles the result `r` of an exit handler. A SystemExit that it raised
  # sets the status. Any other error is printed and sets the status to 1.
  #: (value, word, value) -> word
  def zr_program_end_hook(r, status, exc)
    if r != QUNDEF
      return status
    end
    raised = Task[zr_task()].pending
    Task[zr_task()].pending = Machine.value(QNIL)
    if zr_system_exit_p(raised)
      return zr_exit_status(raised)
    end
    zr_error_print_upto(raised, exc)
    1
  end

  # Returns the POSIX signal number of an uncaught SignalException, or 0.
  #: (value) -> word
  def zr_signal_of(exc)
    if zr_special_p(exc) || !zr_is_a(exc, zr_core_class(Machine.id(:SignalException)))
      return 0
    end
    n = zr_send(exc, Machine.id(:signo), 0, 0)
    if !zr_fixnum_p(n)
      Task[zr_task()].pending = Machine.value(QNIL)
      return 0
    end
    zr_fix2long(n)
  end

  # Ends the process by the POSIX signal `signo`. It restores the signal's
  # default action, then sends the signal to this process, as CRuby's
  # ruby_default_signal does.
  #: (word) -> void
  def zr_die_by_signal(signo)
    Libc.signal(Machine.i32(signo), Machine.ptr(0))
    Libc.kill(Libc.getpid(), Machine.i32(signo))
  end

  #: (value) -> word
  def zr_exit_status(exc)
    zr_fix2long(zr_send(exc, Machine.id(:status), 0, 0))
  end

  #: (value) -> bool
  def zr_system_exit_p(exc)
    !zr_special_p(exc) && zr_is_a(exc, zr_core_class(Machine.id(:SystemExit)))
  end

  # The program's entry. `$0` and `$PROGRAM_NAME` get its file name, in a
  # frozen String that `Process.argv0` keeps when `$0` changes. `traced`
  # is 1 when the program's code fires trace events (`zr_trace_built_m`).
  #: (ptr, word, word) -> void
  def zr_program_start(file, len, traced)
    Machine.store64(Machine.static(:trace_built, 8), 0, traced)
    name = zr_str_new(file, len)
    RBasic[name].flags = RBasic[name].flags | FL_FREEZE
    zr_set_global(G_ARGV0, name)
    zr_gvar_set(Machine.id(:$0), name)
  end

  #: () -> value
  def zr_program_name
    zr_global(G_ARGV0)
  end

  #: (value) -> value
  def zr_environment_get(name)
    p = Libc.getenv(RString[name].ptr)
    if p == 0
      return Machine.value(QNIL)
    end
    zr_str_new(p, zr_cstr_len(p))
  end

  # `ENV[name] = value`. A nil value removes the variable.
  #: (value, value) -> value
  def zr_environment_set(name, value)
    if value == QNIL
      Libc.unsetenv(RString[name].ptr)
    elsif Libc.setenv(RString[name].ptr, RString[value].ptr, Machine.i32(1)) != Machine.i32(0)
      return zr_fix(0 - zr_errno())
    end
    value
  end

  # Returns each `NAME=value` string of the environment.
  #: () -> value
  def zr_environment_list
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

  # Returns the working directory, or the negated errno when the host has
  # none (it was removed). The core raises that errno, as ruby does.
  #: () -> value
  def zr_getcwd
    buf = zr_xmalloc(4096)
    p = Libc.getcwd(buf, 4096)
    if p == 0
      zr_xfree(buf)
      return zr_fix(0 - zr_errno())
    end
    s = zr_str_new(buf, zr_cstr_len(buf))
    zr_xfree(buf)
    s
  end

  # Returns the file of the frame that called the current core method.
  #: () -> value
  def zr_caller_file
    rec = zr_frame_with_file(Frame[Task[zr_task()].top].prev)
    if rec == 0
      return Machine.value(QNIL)
    end
    meta = Frame[rec].meta
    zr_str_new(FrameMeta[meta].file, FrameMeta[meta].file_len)
  end

  #: () -> value
  def zr_process_id
    zr_fix(Machine.u32(Libc.getpid()))
  end

  # Returns one of the process's ids: 0 uid, 1 euid, 2 gid, 3 egid.
  #: (value) -> value
  def zr_process_ids(which)
    w = zr_fix2long(which)
    if w == 0
      return zr_fix(Machine.u32(Libc.getuid()))
    elsif w == 1
      return zr_fix(Machine.u32(Libc.geteuid()))
    elsif w == 2
      return zr_fix(Machine.u32(Libc.getgid()))
    end
    zr_fix(Machine.u32(Libc.getegid()))
  end

  # Returns 62 random bits from the system, for a default seed.
  #: () -> value
  def zr_random_seed
    high = zr_os_random()
    low = zr_os_random()
    zr_fix(((high << 30) | (low >> 2)) & 4611686018427387903)
  end

  module Top
    #: (ptr) -> value
    def self.call(fn) = Machine.indirect
  end

  # The files that the runtime loaded hidden from the program. They are not
  # in $LOADED_FEATURES. Each file has a record of three slots: its path,
  # the hidden file that was loading when it started (nil for a root that
  # eval support loads), and an Array (or nil) of what it defined: the id
  # of each of Object's constants that it defined or reopened, and a pair
  # of the class and the id for each method that it defined on a class of
  # the program. When the program requires one
  # of these files, the file becomes visible, with all that it loaded and
  # defined.
  G_HIDDEN_FEATURES = 50
  HIDDEN_ROW = 3

  #: () -> value
  def zr_hidden_features
    zr_global_list(G_HIDDEN_FEATURES)
  end

  # The real paths of the files that the program required, as in CRuby's
  # loaded_features_realpaths. A file found again through a symlink or a
  # different spelling of its directory does not run a second time.
  G_REAL_FEATURES = 60

  #: () -> value
  def zr_real_features
    zr_global_list(G_REAL_FEATURES)
  end

  # Returns the Array in the global `g`. The first read makes it.
  #: (word) -> value
  def zr_global_list(g)
    list = zr_global(g)
    if zr_special_p(list)
      list = zr_ary_new(64)
      zr_set_global(g, list)
    end
    list
  end

  # The file that is loading now, or 0: the innermost require or load in
  # progress.
  #: () -> ptr
  def zr_loading
    Machine.static(:loading, 8)
  end

  # The hidden file that is loading now, or 0. While a hidden file loads,
  # the constants that it defines on Object stay hidden, and the files
  # that it requires also stay hidden.
  #: () -> ptr
  def zr_hidden_loader
    Machine.static(:hidden_loader, 8)
  end

  #: () -> bool
  def zr_loading_hidden
    Machine.load64(zr_hidden_loader(), 0) != 0
  end

  # The tree-walking interpreter (lib/zr/eval/walk.rb) runs the program's
  # code inside its own files, which are hidden from the program. While it
  # runs, the program is the caller. Thus a constant that the evaluated
  # string defines on Object belongs to the program and is never hidden.
  # A require in the string is the program's require. The eval compiler
  # does not need this, because its code runs in its own frames, which
  # already belong to the program.
  #: () -> ptr
  def zr_walking
    Machine.static(:walking, 8)
  end

  #: () -> bool
  def zr_walking_now
    Machine.load64(zr_walking(), 0) != 0
  end

  #: () -> value
  def zr_walk_enter
    Machine.store64(zr_walking(), 0, Machine.load64(zr_walking(), 0) + 1)
    Machine.value(QNIL)
  end

  #: () -> value
  def zr_walk_leave
    Machine.store64(zr_walking(), 0, Machine.load64(zr_walking(), 0) - 1)
    Machine.value(QNIL)
  end

  # Returns the path of the hidden file that is loading now, or nil.
  #: () -> value
  def zr_hidden_loading_path
    loader = Machine.load64(zr_hidden_loader(), 0)
    Machine.value(loader == 0 ? QNIL : loader)
  end

  # Whether the current load belongs to the runtime and is hidden from the
  # program. This is true when a hidden file is loading, or when the
  # calling code is in a file that only eval support loads and the program
  # did not require. Lazy requires in eval support are the second case.
  # A file of eval support that the program requires itself is visible:
  # it is in $LOADED_FEATURES before its body runs. The Ruby part of a
  # native extension has no file of its own there, so it is visible when
  # it is the file that is loading now.
  #: () -> bool
  def zr_hidden_now
    if zr_loading_hidden()
      return true
    end
    if zr_walking_now()
      return false
    end
    rec = zr_asking_frame()
    if rec == 0 || FrameMeta[Frame[rec].meta].hidden == 0
      return false
    end
    meta = Frame[rec].meta
    if FrameMeta[meta].file_len == 0
      return !zr_loading_internal()
    end
    !zr_ary_has_bytes(zr_gvar_get(Machine.id(:$LOADED_FEATURES)), FrameMeta[meta].file, FrameMeta[meta].file_len)
  end

  # Returns the frame of the code that requests a load or writes a
  # constant. The core library's frames are skipped, so their caller is
  # used.
  #: () -> ptr
  def zr_asking_frame
    rec = Task[zr_task()].top
    while rec != 0
      meta = Frame[rec].meta
      if FrameMeta[meta].hidden != 0 || (FrameMeta[meta].kind != KIND_BUILTIN && FrameMeta[meta].kind != KIND_HIDDEN)
        return rec
      end
      rec = Frame[rec].prev
    end
    0
  end

  # Whether the file that is loading now is the Ruby part of a native
  # extension, in the runtime's directory for them.
  #: () -> bool
  def zr_loading_internal
    loading = Machine.load64(zr_loading(), 0)
    if loading == 0
      return false
    end
    path = Machine.value(loading)
    t = zr_load_table()
    n = LoadTable[t].ext_len
    RString[path].len > n && zr_bytes_eq(RString[path].ptr, n, LoadTable[t].ext, n)
  end

  # Returns the index of the record for `path` in the hidden files, or -1.
  #: (value) -> word
  def zr_hidden_row(path)
    rows = zr_hidden_features()
    i = RArray[rows].len
    while i > 0
      i -= HIDDEN_ROW
      if zr_string_of(zr_ary_at(rows, i), path)
        return i
      end
    end
    -1
  end

  #: (value) -> bool
  def zr_hidden_p(path)
    zr_hidden_row(path) >= 0
  end

  # Records that `path` starts to load hidden, under the hidden file that
  # is loading now.
  #: (value) -> void
  def zr_hidden_add(path)
    rows = zr_hidden_features()
    zr_ary_push(rows, path)
    zr_ary_push(rows, zr_hidden_loading_path())
    zr_ary_push(rows, Machine.value(QNIL))
  end

  # Removes `path` from the hidden list, because its run failed.
  #: (value) -> void
  def zr_hidden_forget(path)
    i = zr_hidden_row(path)
    if i >= 0
      zr_ary_splice(zr_hidden_features(), zr_fix(i), zr_fix(HIDDEN_ROW), zr_ary_new(0))
    end
  end

  # Records that the hidden file that is loading now defined or reopened
  # Object's constant `id`. A later require of the file makes the constant
  # visible.
  #: (word) -> void
  def zr_hidden_defined(id)
    path = zr_hidden_loading_path()
    if path == QNIL
      return
    end
    i = zr_hidden_row(path)
    if i < 0
      return
    end
    rows = zr_hidden_features()
    ids = zr_ary_at(rows, i + 2)
    if ids == QNIL
      ids = zr_ary_new(4)
      zr_ary_store(rows, i + 2, ids)
    end
    zr_ary_push(ids, zr_fix(id))
  end

  # Records that the hidden file that is loading now defined the method
  # `mid` on `klass`, a class of the program. A later require of the file
  # makes the method visible.
  #: (value, word) -> void
  def zr_hidden_defined_method(klass, mid)
    path = zr_hidden_loading_path()
    if path == QNIL
      return
    end
    i = zr_hidden_row(path)
    if i < 0
      return
    end
    rows = zr_hidden_features()
    defined = zr_ary_at(rows, i + 2)
    if defined == QNIL
      defined = zr_ary_new(4)
      zr_ary_store(rows, i + 2, defined)
    end
    pair = zr_ary_new(2)
    zr_ary_push(pair, klass)
    zr_ary_push(pair, zr_fix(mid))
    zr_ary_push(defined, pair)
  end

  # Records that the hidden file that is loading now set the constant `id`
  # of `klass`, a module other than Object. A later require of the file
  # makes the constant visible. The record has three items; a method's
  # record (zr_hidden_defined_method) has two.
  #: (value, word) -> void
  def zr_hidden_defined_const(klass, id)
    path = zr_hidden_loading_path()
    if path == QNIL
      return
    end
    i = zr_hidden_row(path)
    if i < 0
      return
    end
    rows = zr_hidden_features()
    defined = zr_ary_at(rows, i + 2)
    if defined == QNIL
      defined = zr_ary_new(4)
      zr_ary_store(rows, i + 2, defined)
    end
    entry = zr_ary_new(3)
    zr_ary_push(entry, klass)
    zr_ary_push(entry, zr_fix(id))
    zr_ary_push(entry, Machine.value(QNIL))
    zr_ary_push(defined, entry)
  end

  # The program required `path`, which the runtime loaded hidden. The file
  # and its constants become visible and go into $LOADED_FEATURES. The
  # same occurs for each file that it loaded, because one ruby require
  # loads all of them.
  #: (value) -> void
  def zr_feature_reveal(path)
    visible = zr_gvar_get(Machine.id(:$LOADED_FEATURES))
    zr_ary_push(visible, path)
    zr_ary_push(zr_real_features(), zr_feature_real_path(path))
    rows = zr_hidden_features()
    ids = zr_ary_at(rows, zr_hidden_row(path) + 2)
    i = 0
    while ids != QNIL && i < RArray[ids].len
      item = zr_ary_at(ids, i)
      if zr_fixnum_p(item)
        zr_const_reveal(zr_fix2long(item))
      elsif RArray[item].len == 3
        zr_const_reveal_in(zr_ary_at(item, 0), zr_fix2long(zr_ary_at(item, 1)))
      else
        zr_method_reveal(zr_ary_at(item, 0), zr_fix2long(zr_ary_at(item, 1)))
      end
      i += 1
    end
    i = 0
    while i < RArray[rows].len
      if zr_string_of(zr_ary_at(rows, i + 1), path) && !zr_ary_has_string(visible, zr_ary_at(rows, i))
        zr_feature_reveal(zr_ary_at(rows, i))
      end
      i += HIDDEN_ROW
    end
  end

  # Returns realpath(3) of `path`, or `path` itself when no file is there.
  # That occurs for a compiled-in unit when the program runs away from its
  # source.
  #: (value) -> value
  def zr_feature_real_path(path)
    p = zr_os_realpath(RString[path].ptr)
    if p == 0
      return path
    end
    real = zr_str_new(p, zr_cstr_len(p))
    zr_xfree(p)
    real
  end

  # `require`, `require_relative` (kind 0 and 1) and `load` (kind 2) of the
  # file at `path`, whose toplevel is `fn`. A require runs the file one
  # time, as recorded in $LOADED_FEATURES. A failed run leaves no record.
  #
  # Kind 3 is eval support, which a program that uses eval links in. Its
  # files, and each require made while they run, go in the hidden list
  # instead. When the program first requires one of those files itself,
  # nothing runs again. The file is recorded and the call returns true, as
  # the first load does.
  #: (value, ptr, word) -> value
  def zr_require(path, fn, kind)
    zr_require_run(path, fn, kind, true)
  end

  # The same, for a require with a name that the program computed.
  # Kernel#require found the file and has its own frame, so the file's
  # toplevel runs under that frame. `fn` is the toplevel's address as an
  # Integer.
  #: (value, value, value) -> value
  def zr_require_computed(path, fn, kind)
    zr_require_run(path, Machine.ptr(zr_fix2long(fn)), zr_fix2long(kind), false)
  end

  # Eval support's own copy of a library that the program loads from a
  # gem instead: the path of the gem's file, which a require of the copy
  # runs in its place, so one copy loads, as in ruby. A require reaches a
  # copy from eval support's own files, and from the prebuilt files that
  # every program shares with it (a port's `require "json/common"`)
  # (`LoadTables#redirects`, one `copy<TAB>gem file` line each). nil for
  # any other path.
  #: (value) -> value
  def zr_require_redirect(path)
    t = zr_load_table()
    text = LoadTable[t].redirects
    size = LoadTable[t].redirects_len
    at = 0
    while at < size
      tab = at
      while tab < size && Machine.load8(text + tab, 0) != 9
        tab += 1
      end
      eol = tab
      while eol < size && Machine.load8(text + eol, 0) != 10
        eol += 1
      end
      if eol > tab && zr_bytes_eq(text + at, tab - at, RString[path].ptr, RString[path].len)
        return zr_str_new(text + tab + 1, eol - tab - 1)
      end
      at = eol + 1
    end
    Machine.value(QNIL)
  end

  #: (value, ptr, word, bool) -> value
  def zr_require_run(path, fn, kind, framed)
    if kind != 2
      gem_file = zr_require_redirect(path)
      if gem_file != QNIL
        path = gem_file
        fn = Machine.ptr(zr_fix2long(zr_unit_for(gem_file)))
      end
    end
    # A file that is not compiled into the program has no toplevel to run.
    if Machine.word(fn) == 0
      return zr_load_error_in(kind == 1 ? Machine.id(:require_relative) : (kind == 2 ? Machine.id(:load) : Machine.id(:require)), RString[path].ptr, RString[path].len)
    end
    hidden = kind == 3 || zr_hidden_now()
    visible = zr_gvar_get(Machine.id(:$LOADED_FEATURES))
    real = Machine.value(QNIL)
    if kind != 2
      if zr_ary_has_string(visible, path) || (hidden && zr_hidden_p(path))
        return Machine.value(QFALSE)
      end
      if hidden
        zr_hidden_add(path)
      else
        if zr_hidden_p(path)
          zr_feature_reveal(path)
          zr_autoload_provided(Machine.value(QNIL), path)
          return Machine.value(QTRUE)
        end
        real = zr_feature_real_path(path)
        if zr_ary_has_string(zr_real_features(), real)
          return Machine.value(QFALSE)
        end
        zr_ary_push(zr_real_features(), real)
        zr_ary_push(visible, path)
      end
    end
    # The file is compiled and about to run, where ruby fires
    # `:script_compiled`. A file that only the runtime loads is hidden from
    # the program, so it fires nothing.
    if !hidden
      r = zr_trace_required(path, kind)
      return r if r == QUNDEF
    end
    outer = Machine.load64(zr_loading(), 0)
    outer_hidden = Machine.load64(zr_hidden_loader(), 0)
    Machine.store64(zr_loading(), 0, path)
    if hidden
      Machine.store64(zr_hidden_loader(), 0, path)
    end
    mid = 0
    if framed
      mid = kind == 1 ? Machine.id(:require_relative) : (kind == 2 ? Machine.id(:load) : Machine.id(:require))
    end
    r = zr_run_top(fn, mid)
    Machine.store64(zr_loading(), 0, outer)
    Machine.store64(zr_hidden_loader(), 0, outer_hidden)
    if r == QUNDEF
      # The files that it required stay loaded.
      if kind != 2 && hidden
        zr_hidden_forget(path)
      elsif kind != 2
        zr_ary_delete_string(visible, path)
      end
      if real != QNIL
        zr_ary_delete_string(zr_real_features(), real)
      end
      return r
    end
    # The file is provided, so an autoload that waits for it stops waiting.
    # `autoload?` returns nil and `const_defined?` returns false, as in ruby
    # after `rb_feature_provided` is true for the feature. A literal require
    # comes here and not to `Kernel.load_file`. A computed require also
    # gives the name that it used, in `Kernel.load_file`.
    if kind != 2
      zr_autoload_provided(Machine.value(QNIL), path)
    end
    Machine.value(QTRUE)
  end

  # Runs the file's toplevel under the frame of the Kernel method `mid`,
  # as a backtrace through a require shows it. When `mid` is 0, it runs
  # under the caller's frame.
  #: (ptr, word) -> value
  def zr_run_top(fn, mid)
    if mid == 0
      return Top.call(fn)
    end
    e = zr_find_method(zr_global(G_KERNEL), mid)
    rec = Machine.slot(Frame.size)
    t = zr_task()
    Frame[rec].prev = Task[t].top
    Frame[rec].meta = MEntry[e].meta
    Frame[rec].line = 0
    Frame[rec].serial = 0
    Frame[rec].self = zr_global(G_MAIN)
    Frame[rec].cref = Machine.value(QNIL)
    Frame[rec].blk = Machine.value(QNIL)
    Frame[rec].nvalues = 0
    Frame[rec].entry = 0
    Frame[rec].svars = Machine.value(QNIL)
    Frame[rec].defined = Machine.value(QNIL)
    Task[t].top = rec
    r = Top.call(fn)
    Task[t].top = Frame[rec].prev
    r
  end

  # The table that the compiler writes for a require with a computed name
  # (lib/zr/runtime.rb, `load_tables`): the count of compiled-in files,
  # their entries, and ten (bytes, length) texts.
  class LoadTable < Layout
    attr_accessor :units #: word
    attr_accessor :rows #: ptr
    attr_accessor :roots #: ptr
    attr_accessor :roots_len #: word
    attr_accessor :missing #: ptr
    attr_accessor :missing_len #: word
    attr_accessor :preloaded #: ptr
    attr_accessor :preloaded_len #: word
    attr_accessor :ext #: ptr
    attr_accessor :ext_len #: word
    attr_accessor :spots #: ptr
    attr_accessor :spots_len #: word
    attr_accessor :coverable #: ptr
    attr_accessor :coverable_len #: word
    attr_accessor :branches #: ptr
    attr_accessor :branches_len #: word
    attr_accessor :defs #: ptr
    attr_accessor :defs_len #: word
    attr_accessor :sources #: ptr
    attr_accessor :sources_len #: word
    attr_accessor :manifest #: ptr
    attr_accessor :manifest_len #: word
    attr_accessor :redirects #: ptr
    attr_accessor :redirects_len #: word
  end

  #: () -> ptr
  def zr_load_table
    Machine.ptr(Machine.load64(Machine.extern(:zr_load_tables), 0))
  end

  # Returns the compiled toplevel of the program's file at `path`, as an
  # Integer address, or nil. Each entry is (path bytes, length, toplevel),
  # so a require with a computed name can find a compiled-in file.
  #: (value) -> value
  def zr_unit_for(path)
    t = zr_load_table()
    i = 0
    while i < LoadTable[t].units
      row = LoadTable[t].rows + (i * 24)
      if zr_bytes_eq(Machine.ptr(Machine.load64(row, 0)), Machine.load64(row, 8), RString[path].ptr, RString[path].len)
        return zr_fix(Machine.load64(row, 16))
      end
      i += 1
    end
    Machine.value(QNIL)
  end

  # Returns a text that a require with a computed name reads, one name on
  # each line. 0: the library directories of the build, searched after
  # $LOAD_PATH. 1: the ruby features that this runtime has no file for.
  # 2: the features that ruby loads before the program. 3: the directory
  # of this runtime's native extensions. 4: error_highlight's spots.
  # 5: the lines that Coverage counts. 6: the branches that it reports.
  # 7: the def and block spans that identify a method entry. 8: the digest
  # of each source file of the compiler that the program links in, each
  # after a path and a tab. 9: the gem manifest (lib/zr/manifest.rb).
  # The last text, the redirects, is read only by `zr_require_redirect`.
  #: (value) -> value
  def zr_load_names(which)
    t = zr_load_table()
    w = zr_fix2long(which)
    if w == 0
      return zr_str_new(LoadTable[t].roots, LoadTable[t].roots_len)
    elsif w == 1
      return zr_str_new(LoadTable[t].missing, LoadTable[t].missing_len)
    elsif w == 2
      return zr_str_new(LoadTable[t].preloaded, LoadTable[t].preloaded_len)
    elsif w == 4
      return zr_str_new(LoadTable[t].spots, LoadTable[t].spots_len)
    elsif w == 5
      return zr_str_new(LoadTable[t].coverable, LoadTable[t].coverable_len)
    elsif w == 6
      return zr_str_new(LoadTable[t].branches, LoadTable[t].branches_len)
    elsif w == 7
      return zr_str_new(LoadTable[t].defs, LoadTable[t].defs_len)
    elsif w == 8
      return zr_str_new(LoadTable[t].sources, LoadTable[t].sources_len)
    elsif w == 9
      return zr_str_new(LoadTable[t].manifest, LoadTable[t].manifest_len)
    end
    zr_str_new(LoadTable[t].ext, LoadTable[t].ext_len)
  end

  # Whether `e` is a String with the same bytes as the String `s`.
  #: (value, value) -> bool
  def zr_string_of(e, s)
    zr_string_of_bytes(e, RString[s].ptr, RString[s].len)
  end

  #: (value, ptr, word) -> bool
  def zr_string_of_bytes(e, bytes, len)
    if zr_special_p(e) || zr_type(e) != T_STRING
      return false
    end
    zr_bytes_eq(RString[e].ptr, RString[e].len, bytes, len)
  end

  # The index of the last String in `a` equal to `s`, or -1.
  #: (value, value) -> word
  def zr_ary_rindex_string(a, s)
    zr_ary_rindex_bytes(a, RString[s].ptr, RString[s].len)
  end

  #: (value, ptr, word) -> word
  def zr_ary_rindex_bytes(a, bytes, len)
    i = RArray[a].len
    while i > 0
      i -= 1
      if zr_string_of_bytes(zr_ary_at(a, i), bytes, len)
        return i
      end
    end
    -1
  end

  #: (value, value) -> bool
  def zr_ary_has_string(a, s)
    zr_ary_rindex_string(a, s) >= 0
  end

  #: (value, ptr, word) -> bool
  def zr_ary_has_bytes(a, bytes, len)
    zr_ary_rindex_bytes(a, bytes, len) >= 0
  end

  # Removes the last String equal to `s` from `a`.
  #: (value, value) -> void
  def zr_ary_delete_string(a, s)
    i = zr_ary_rindex_string(a, s)
    if i >= 0
      zr_ary_splice(a, zr_fix(i), zr_fix(1), zr_ary_new(0))
    end
  end

  # Raises a LoadError for a file that is not found, with CRuby's message,
  # under the frame of Kernel#require_relative.
  #: (ptr, word) -> value
  def zr_load_error(path, len)
    zr_load_error_in(Machine.id(:require_relative), path, len)
  end

  # The same, under the frame of Kernel's `mid`.
  #: (word, ptr, word) -> value
  def zr_load_error_in(mid, path, len)
    e = zr_find_method(zr_global(G_KERNEL), mid)
    rec = Machine.slot(Frame.size)
    t = zr_task()
    Frame[rec].prev = Task[t].top
    Frame[rec].meta = MEntry[e].meta
    Frame[rec].line = 0
    Frame[rec].serial = 0
    Frame[rec].self = zr_global(G_MAIN)
    Frame[rec].cref = Machine.value(QNIL)
    Frame[rec].blk = Machine.value(QNIL)
    Frame[rec].nvalues = 0
    Frame[rec].entry = 0
    Frame[rec].svars = Machine.value(QNIL)
    Frame[rec].defined = Machine.value(QNIL)
    Task[t].top = rec
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("cannot load such file -- "), 25)
    zr_buf_push(b, path, len)
    exc = zr_exc_new(zr_core_class(Machine.id(:LoadError)), zr_buf_take(b))
    zr_ivar_set(exc, Machine.id(:@path), zr_str_new(path, len))
    r = zr_raise(exc)
    Task[t].top = Frame[rec].prev
    r
  end

  # Whether a path exists, and what it is: 0 for nothing, 1 for a
  # directory, 2 for a regular file, 3 for anything else.
  #: (value) -> value
  def zr_path_kind(path)
    buf = zr_xmalloc(STAT_LEN)
    r = Machine.u32(Libc.stat(RString[path].ptr, buf))
    mode = zr_os_stat_mode(buf) & S_IFMT
    zr_xfree(buf)
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

  # st_mode's file type bits, which POSIX defines with the same values on
  # all hosts.
  S_IFMT = 61440
  S_IFDIR = 16384
  S_IFREG = 32768

  # Returns the time in nanoseconds on the clock `id` (darwin: 0 real
  # time, 6 monotonic).
  #: (value) -> value
  def zr_clock_ns(id)
    ts = Machine.slot(16)
    Libc.clock_gettime(Machine.i32(zr_fix2long(id)), ts)
    zr_fix(Machine.load64(ts, 0) * 1000000000 + Machine.load64(ts, 8))
  end

  # Returns the clock's resolution in nanoseconds.
  #: (value) -> value
  def zr_clock_res_ns(id)
    ts = Machine.slot(16)
    Libc.clock_getres(Machine.i32(zr_fix2long(id)), ts)
    zr_fix(Machine.load64(ts, 0) * 1000000000 + Machine.load64(ts, 8))
  end

  # Returns crypt(3) of the text with the salt.
  #: (value, value) -> value
  def zr_str_crypt(text, salt)
    out = Libc.crypt(RString[text].ptr, RString[salt].ptr)
    if out == 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("invalid salt"), 12)
    end
    zr_str_new(out, zr_cstr_len(out))
  end

  # The full process sleeps `ns` nanoseconds, or until a POSIX signal
  # arrives. Returns true when the time passed. Returns false when a POSIX
  # signal stopped the sleep and its handlers ran.
  #: (value) -> value
  def zr_nanosleep(ns)
    n = zr_fix2long(ns)
    ts = Machine.slot(16)
    Machine.store64(ts, 0, n / 1000000000)
    Machine.store64(ts, 8, n % 1000000000)
    if Libc.nanosleep(ts, 0) == Machine.i32(0)
      return Machine.value(QTRUE)
    end
    if zr_trap_check() == QUNDEF
      return Machine.value(QUNDEF)
    end
    Machine.value(QFALSE)
  end

  # Returns the local zone at `secs` since the epoch: its offset east of
  # UTC in seconds, whether daylight time is in effect, and its
  # abbreviation.
  #: (value) -> value
  def zr_time_local(secs)
    Libc.tzset()
    t = Machine.slot(8)
    Machine.store64(t, 0, zr_fix2long(secs))
    tm = Machine.slot(64)
    Libc.localtime_r(t, tm)
    out = zr_ary_new(3)
    zr_ary_push(out, zr_fix(Machine.load64(tm, 40)))
    zr_ary_push(out, zr_bool(Machine.u32(Machine.load32(tm, 32)) > 0))
    zone = Machine.ptr(Machine.load64(tm, 48))
    zr_ary_push(out, zr_str_new(zone, zr_cstr_len(zone)))
    out
  end

  # `exit!`: the process ends immediately, and no handler runs.
  #: (value) -> value
  def zr_exit_now(status)
    Libc._exit(Machine.i32(zr_fix2long(status)))
    Machine.value(QNIL)
  end

  # Returns a user's home directory, or nil when there is no such user. A
  # nil name gives the home directory of this process's user.
  #: (value) -> value
  def zr_home_dir(name)
    pw = name == QNIL ? Libc.getpwuid(Libc.getuid()) : Libc.getpwnam(RString[name].ptr)
    if pw == 0
      return Machine.value(QNIL)
    end
    dir = zr_os_passwd_dir(pw)
    if dir == 0
      return Machine.value(QNIL)
    end
    zr_str_new(dir, zr_cstr_len(dir))
  end

  # Returns a C string as a Ruby String, or nil for a null pointer.
  #: (ptr) -> value
  def zr_cstr_str(text)
    if text == 0
      return Machine.value(QNIL)
    end
    zr_str_new(text, zr_cstr_len(text))
  end

  #: (value) -> value
  def zr_pw_name(name)
    zr_os_passwd_row(Libc.getpwnam(RString[name].ptr))
  end

  #: (value) -> value
  def zr_pw_uid(uid)
    zr_os_passwd_row(Libc.getpwuid(Machine.i32(zr_fix2long(uid))))
  end

  #: () -> value
  def zr_pw_next
    zr_os_passwd_row(Libc.getpwent())
  end

  #: () -> value
  def zr_pw_rewind
    Libc.setpwent()
    Machine.value(QNIL)
  end

  #: () -> value
  def zr_pw_done
    Libc.endpwent()
    Machine.value(QNIL)
  end

  # Returns the four fields of darwin's group: name at 0, password at 8,
  # gid at 16, and a null-terminated array of member names at 24.
  #: (ptr) -> value
  def zr_gr_row(gr)
    if gr == 0
      return Machine.value(QNIL)
    end
    out = zr_ary_new(4)
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(gr, 0))))
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(gr, 8))))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(gr, 16))))
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

  #: (value) -> value
  def zr_gr_name(name)
    zr_gr_row(Libc.getgrnam(RString[name].ptr))
  end

  #: (value) -> value
  def zr_gr_gid(gid)
    zr_gr_row(Libc.getgrgid(Machine.i32(zr_fix2long(gid))))
  end

  #: () -> value
  def zr_gr_next
    zr_gr_row(Libc.getgrent())
  end

  #: () -> value
  def zr_gr_rewind
    Libc.setgrent()
    Machine.value(QNIL)
  end

  #: () -> value
  def zr_gr_done
    Libc.endgrent()
    Machine.value(QNIL)
  end

  #: () -> value
  def zr_nprocessors
    zr_fix(Libc.sysconf(Machine.i32(SC_NPROCESSORS_ONLN)))
  end

  # Returns a sysconf or pathconf value, or nil when the name has no limit.
  #: (value) -> value
  def zr_sysconf(name)
    got = Libc.sysconf(Machine.i32(zr_fix2long(name)))
    if got == 0 - 1
      return Machine.value(QNIL)
    end
    zr_fix(got)
  end

  # Returns a confstr value. The first call gets the length, which confstr
  # returns when the buffer is empty.
  #: (value) -> value
  def zr_confstr(name)
    which = Machine.i32(zr_fix2long(name))
    len = Libc.confstr(which, Machine.ptr(0), 0)
    if len == 0
      return Machine.value(QNIL)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_reserve(b, len)
    Libc.confstr(which, Buf[b].ptr, len)
    Buf[b].len = len - 1
    zr_buf_take(b)
  end

  #: () -> value
  def zr_login_name
    zr_cstr_str(Libc.getlogin())
  end

  # Returns uname's first five fields: sysname, nodename, release, version
  # and machine.
  #: () -> value
  def zr_uname
    buf = Machine.slot(UTSNAME_LEN)
    if Libc.uname(buf) != 0
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
end
