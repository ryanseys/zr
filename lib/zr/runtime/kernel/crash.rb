# Derived from the C of CRuby and of its gems (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.

module Zr::Kern
  # ruby's bug report. A fatal signal (SIGSEGV, SIGBUS, SIGILL or SIGABRT),
  # a bug that the runtime finds (zr_bug) and a C extension's rb_bug all
  # print it before the process ends, as error.c's rb_bug_for_fatal_signal
  # and rb_bug and vm_dump.c's rb_vm_bugreport do. It goes to the file or
  # the command that --crash-report or RUBY_CRASH_REPORT names, else to
  # stderr.
  #
  # zr has no VM stack, so the control frames are the frames of its own
  # frame list, one line each, with CRuby's names for their kinds. It
  # gives no machine registers.

  # The alternate stack that the handlers run on, so a report is written
  # also when the stack of the program is used up.
  CRASH_STACK_BYTES = 1048576

  # error.c's REPORT_BUG_BUFSIZ: the room for a file name or a command
  # word that a template expands to.
  CRASH_NAME_BYTES = 256

  # vm_dump.c's LIMITED_NAME_LENGTH.
  CRASH_NAME_LIMIT = 1024

  # The most native frames in a report.
  CRASH_C_FRAMES = 128

  # Installs the handlers of the fatal signals on an alternate stack, as
  # Init_signal does.
  #: () -> void
  def zr_crash_init
    stack = zr_os_stack_map(CRASH_STACK_BYTES)
    if stack != 0
      zr_os_altstack(stack, CRASH_STACK_BYTES)
    end
    fn = Machine.word(Machine.addr(:zr_crash_caught))
    zr_os_fatal_action(Machine.i32(SIGNAL_BUS), fn)
    zr_os_fatal_action(Machine.i32(SIGNAL_ILL), fn)
    zr_os_fatal_action(Machine.i32(SIGNAL_SEGV), fn)
    if zr_os_fatal_action(Machine.i32(SIGNAL_ABRT), fn) == Machine.i32(0)
      Machine.store64(Machine.static(:crash_armed, 8), 0, 1)
    end
  end

  # `--crash-report=TEMPLATE` (ruby_set_crash_report): the template that
  # names where a report goes, in place of RUBY_CRASH_REPORT. The runtime
  # keeps its own copy.
  #: (value) -> value
  def zr_crash_report_set(template)
    n = RString[template].len
    copy = zr_xmalloc(n + 1)
    zr_memcpy(copy, RString[template].ptr, n)
    Machine.store8(copy + n, 0, Machine.i8(0))
    Machine.store64(Machine.static(:crash_template, 8), 0, Machine.word(copy))
    Machine.value(QNIL)
  end

  # The handler of the fatal signals (sigsegv, sigbus, sigill and sigabrt
  # in signal.c): the report, then the signal's default action.
  #: (i32, ptr, ptr) -> void
  def zr_crash_caught(signo, info, ctx)
    Machine.gates_enter
    sig = Machine.u32(signo)
    name = Machine.bytes("SEGV")
    title = Machine.bytes("Segmentation fault")
    title_len = 18
    if sig == SIGNAL_BUS
      name = Machine.bytes("BUS\0")
      title = Machine.bytes("Bus Error")
      title_len = 9
    elsif sig == SIGNAL_ILL
      name = Machine.bytes("ILL\0")
      title = Machine.bytes("Illegal instruction")
      title_len = 19
    elsif sig == SIGNAL_ABRT
      name = Machine.bytes("ABRT")
      title = Machine.bytes("Aborted")
      title_len = 7
    end
    zr_crash_reserved(name, signo)
    # The abort of zr_bug reports the bug's message (rb_bug).
    bug = Machine.static(:crash_bug, 16)
    if sig == SIGNAL_ABRT && Machine.load64(bug, 0) != 0
      zr_crash_bug_report(Machine.ptr(Machine.load64(bug, 0)), Machine.load64(bug, 8))
      zr_os_crash_exit(signo)
      return
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, title, title_len)
    zr_buf_push(b, Machine.bytes(" at "), 4)
    zr_crash_hex(b, zr_os_fault_address(info))
    # signal_sender_message: who sent a signal from outside.
    sender = zr_os_signal_sender(info)
    if sender != 0 - 1 && sender != Machine.u32(Libc.getpid())
      if sender == 0
        zr_buf_push(b, Machine.bytes(" (sent by another process)"), 26)
      else
        zr_buf_push(b, Machine.bytes(" (sent by pid "), 14)
        zr_buf_long(b, sender)
        zr_buf_byte(b, 41)
      end
    end
    zr_crash_report(Buf[b].ptr, Buf[b].len)
    zr_os_crash_exit(signo)
  end

  # check_reserved_signal: a fatal signal while the report of another is
  # written says so and aborts. A second SIGABRT gets its default action
  # first, so the abort ends the process.
  #: (ptr, i32) -> void
  def zr_crash_reserved(name, signo)
    cell = Machine.static(:crash_signal, 8)
    prev = Machine.ptr(Machine.load64(cell, 0))
    if prev == 0
      Machine.store64(cell, 0, Machine.word(name))
      return
    end
    if Machine.u32(signo) == SIGNAL_ABRT
      old = Machine.slot(16)
      zr_os_sigaction(signo, SIGNAL_DEFAULT, old)
    end
    Libc.write(2, name, zr_crash_name_len(name))
    Libc.write(2, Machine.bytes(" received in "), 13)
    Libc.write(2, prev, zr_crash_name_len(prev))
    Libc.write(2, Machine.bytes(" handler\n"), 9)
    Libc.abort()
  end

  # A signal name of zr_crash_caught: four bytes, or three and a NUL.
  #: (ptr) -> word
  def zr_crash_name_len(name)
    Machine.u8(Machine.load8(name, 3)) == 0 ? 3 : 4
  end

  # rb_bug for the runtime and for C (zr_bug, rb_bug). A bug can come from
  # code that must not run the collector, which the report may, so this
  # keeps the message and aborts. The handler of SIGABRT, which it
  # installs again in case the program trapped the signal, writes the
  # report, and then SIGABRT's default action ends the process (die).
  # Where no handler runs, the message goes to stderr as it is.
  #: (ptr, word) -> void
  def zr_crash_bug(message, len)
    bug = Machine.static(:crash_bug, 16)
    Machine.store64(bug, 8, len)
    Machine.store64(bug, 0, Machine.word(message))
    if Machine.load64(Machine.static(:crash_armed, 8), 0) != 0
      zr_os_fatal_action(Machine.i32(SIGNAL_ABRT), Machine.word(Machine.addr(:zr_crash_caught)))
    else
      Libc.write(2, message, len)
    end
    Libc.abort()
  end

  # The report of a bug's message. A message that starts with `[BUG] ` or
  # ends with a newline gives the text between.
  #: (ptr, word) -> void
  def zr_crash_bug_report(message, len)
    if len >= 6 && zr_bytes_eq(message, 6, Machine.bytes("[BUG] "), 6)
      message += 6
      len -= 6
    end
    if len > 0 && Machine.u8(Machine.load8(message + len - 1, 0)) == 10
      len -= 1
    end
    zr_crash_report(message, len)
  end

  # report_bug: the report of the bug `message`. Only the first report is
  # written; a later one finds the report done and writes nothing.
  #: (ptr, word) -> void
  def zr_crash_report(message, len)
    done = Machine.static(:crash_done, 8)
    if Machine.load64(done, 0) != 0
      return
    end
    Machine.store64(done, 0, 1)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_crash_position(b)
    child = Machine.slot(8)
    Machine.store64(child, 0, 0)
    fd = zr_crash_open(b, child)
    if fd == 0 - 1
      return
    end
    Machine.store64(Machine.static(:crash_out, 8), 0, Machine.word(fd))
    zr_buf_push(b, Machine.bytes("[BUG] "), 6)
    zr_buf_push(b, message, len)
    zr_buf_byte(b, 10)
    zr_crash_description(b)
    zr_buf_push(b, Machine.bytes("\n\n"), 2)
    zr_crash_flush(b)
    if CRASH_NOTES != 0
      zr_crash_notes(Machine.bytes("-- Crash Report log information --------------------------------------------\n   See Crash Report log file in one of the following locations:\n     * ~/Library/Logs/DiagnosticReports\n     * /Library/Logs/DiagnosticReports\n   for more details.\nDon't forget to include the above Crash Report log file in bug reports.\n\n"), 314)
    end
    t = zr_task()
    if Task[t].top != 0
      zr_crash_frames(b, Task[t].top)
      zr_crash_backtrace(b, Task[t].top)
      zr_crash_threads(b)
    else
      zr_buf_push(b, Machine.bytes("-- Control frame information -----------------------------------------------\n  No Ruby execution context on the current thread.\n\n"), 129)
    end
    zr_crash_flush(b)
    zr_crash_c_frames(b)
    zr_buf_push(b, Machine.bytes("-- Other runtime information -----------------------------------------------\n\n"), 78)
    if Heap[zr_heap()].collecting == 0
      zr_crash_runtime(b)
    end
    zr_crash_flush(b)
    zr_crash_maps(b)
    if CRASH_NOTES != 0
      zr_crash_notes(Machine.bytes("[IMPORTANT]\nDon't forget to include the Crash Report log file under\nDiagnosticReports directory in bug reports.\n\n"), 113)
    end
    zr_buf_free(b)
    if fd > 2
      Libc.close(Machine.i32(fd))
    end
    if Machine.load64(child, 0) != 0
      zr_os_crash_wait(Machine.load64(child, 0))
    end
  end

  # Writes the buffer to the report and empties it.
  #: (ptr) -> void
  def zr_crash_flush(b)
    zr_crash_put(Buf[b].ptr, Buf[b].len)
    Buf[b].len = 0
  end

  # Writes `n` bytes to the report, all of them unless a write fails.
  #: (ptr, word) -> void
  def zr_crash_put(bytes, n)
    fd = Machine.i32(Machine.load64(Machine.static(:crash_out, 8), 0))
    done = 0
    while done < n
      w = Machine.sword(Libc.write(fd, bytes + done, n - done))
      if w <= 0
        return
      end
      done += w
    end
  end

  # `0x` and 16 hex digits, as ruby's %p writes a pointer.
  #: (ptr, word) -> void
  def zr_crash_hex(b, v)
    zr_buf_push(b, Machine.bytes("0x"), 2)
    shift = 60
    while true
      d = (v >> shift) & 15
      zr_buf_byte(b, d < 10 ? 48 + d : 87 + d)
      if shift == 0
        break
      end
      shift -= 4
    end
  end

  # err_position_0: `file:line: ` of the running Ruby code, `file: ` at
  # line 0, or nothing before the program runs.
  #: (ptr) -> void
  def zr_crash_position(b)
    rec = Task[zr_task()].top
    while rec != 0 && !zr_frame_shown_p(rec)
      rec = Frame[rec].prev
    end
    if rec == 0
      return
    end
    source = zr_frame_with_file(rec)
    if source == 0
      return
    end
    meta = Frame[source].meta
    zr_buf_push(b, FrameMeta[meta].file, FrameMeta[meta].file_len)
    line = zr_frame_level_line(source, 0)
    if line != 0
      zr_buf_byte(b, 58)
      zr_buf_long(b, line)
    end
    zr_buf_push(b, Machine.bytes(": "), 2)
  end

  # RUBY_DESCRIPTION, as the core set it.
  #: (ptr) -> void
  def zr_crash_description(b)
    e = zr_const_row(zr_global(G_OBJECT), Machine.id(:RUBY_DESCRIPTION))
    if e == 0
      return
    end
    v = zr_const_raw_value(e)
    if !zr_special_p(v) && zr_type(v) == T_STRING
      zr_buf_str(b, v)
    end
  end

  # bug_report_file: opens what the template names, and writes `b`, the
  # position, there. Without a template, or when the open or the write
  # fails, the report goes to stderr, then stdout. Returns the
  # descriptor, or -1 when no write works. A command's pid goes to
  # `child`.
  #: (ptr, ptr) -> word
  def zr_crash_open(b, child)
    template = Machine.ptr(Machine.load64(Machine.static(:crash_template, 8), 0))
    if template == 0
      template = Libc.getenv(Machine.bytes("RUBY_CRASH_REPORT\0"))
    end
    fd = 0 - 1
    if template != 0
      fd = zr_crash_target(template, child)
    end
    if fd != 0 - 1
      if zr_crash_write_all(fd, Buf[b].ptr, Buf[b].len)
        Buf[b].len = 0
        return fd
      end
      Libc.close(Machine.i32(fd))
    end
    if zr_crash_write_all(2, Buf[b].ptr, Buf[b].len)
      Buf[b].len = 0
      return 2
    end
    if zr_crash_write_all(1, Buf[b].ptr, Buf[b].len)
      Buf[b].len = 0
      return 1
    end
    0 - 1
  end

  #: (word, ptr, word) -> bool
  def zr_crash_write_all(fd, bytes, n)
    done = 0
    while done < n
      w = Machine.sword(Libc.write(Machine.i32(fd), bytes + done, n - done))
      if w <= 0
        return false
      end
      done += w
    end
    true
  end

  # open_report_path: a template that starts with `|` runs a command
  # (its words expanded one by one) that reads the report on its stdin;
  # any other names a file, which is made or emptied. Returns the
  # descriptor, or -1.
  #: (ptr, ptr) -> word
  def zr_crash_target(template, child)
    if Machine.u8(Machine.load8(template, 0)) == 0
      return 0 - 1
    end
    buf = Machine.slot(CRASH_NAME_BYTES)
    at = Machine.slot(8)
    if Machine.u8(Machine.load8(template, 0)) != 124
      Machine.store64(at, 0, Machine.word(template))
      zr_crash_expand(at, buf, CRASH_NAME_BYTES, false)
      fd = Machine.sword(zr_os_open(buf, Machine.i32(CRASH_WRITE_FLAGS), Machine.i32(438)))
      return fd < 0 ? 0 - 1 : Machine.word(fd)
    end
    Machine.store64(at, 0, Machine.word(template + 1))
    argv = Machine.slot(128)
    argc = 0
    room = buf
    left = CRASH_NAME_BYTES
    while argc < 15
      p = Machine.ptr(Machine.load64(at, 0))
      while Machine.u8(Machine.load8(p, 0)) == 32 || (Machine.u8(Machine.load8(p, 0)) >= 9 && Machine.u8(Machine.load8(p, 0)) <= 13)
        p += 1
      end
      Machine.store64(at, 0, Machine.word(p))
      used = zr_crash_expand(at, room, left, true)
      if used == 0
        break
      end
      Machine.store64(argv + (argc * 8), 0, Machine.word(room))
      argc += 1
      room += used
      left -= used
    end
    Machine.store64(argv + (argc * 8), 0, 0)
    if argc == 0
      return 0 - 1
    end
    zr_os_crash_spawn(argv, child)
  end

  # ruby_popen_writer: runs the command, its first word a path that is
  # not searched (execv), with a pipe on its stdin, and returns the
  # pipe's write end. When the command does not start, it says why on
  # stderr and returns -1. Only an OS layer that starts processes calls
  # it (`zr_os_crash_spawn`).
  #: (ptr, ptr) -> word
  def zr_crash_spawn(argv, child)
    fds = Machine.slot(8)
    if Libc.pipe(fds) < Machine.i32(0)
      return 0 - 1
    end
    r = Machine.load32(fds, 0)
    w = Machine.load32(fds, 4)
    actions = Machine.slot(SPAWN_ACTIONS_LEN)
    Libc.posix_spawn_file_actions_init(actions)
    Libc.posix_spawn_file_actions_adddup2(actions, r, Machine.i32(0))
    Libc.posix_spawn_file_actions_addclose(actions, r)
    Libc.posix_spawn_file_actions_addclose(actions, w)
    pid = Machine.slot(8)
    Machine.store64(pid, 0, 0)
    command = Machine.ptr(Machine.load64(argv, 0))
    ok = Libc.posix_spawn(pid, command, actions, Machine.ptr(0), argv, zr_os_environ())
    Libc.posix_spawn_file_actions_destroy(actions)
    Libc.close(r)
    if ok != Machine.i32(0)
      Libc.close(w)
      Libc.write(2, Machine.bytes("ruby_popen_writer("), 18)
      Libc.write(2, command, zr_cstr_len(command))
      Libc.write(2, Machine.bytes("): "), 3)
      text = Libc.strerror(ok)
      Libc.write(2, text, zr_cstr_len(text))
      Libc.write(2, Machine.bytes("\n"), 1)
      return 0 - 1
    end
    Machine.store64(child, 0, Machine.u32(Machine.load32(pid, 0)))
    Machine.u32(w)
  end

  # expand_report_argument: expands the template at the pointer in `at`
  # into `buf` (`size` bytes, NUL-terminated), up to a blank when `word`.
  # `%e`/`%E` give the executable's base name or its path with each `/`
  # as `!`, `%f`/`%F` the same of the main script, `%p` the pid, `%t`
  # the time in seconds, `%%` a `%`, and `%NNN` the byte of up to three
  # octal digits (zero ends the name). Moves the pointer past what it
  # read. Returns the bytes taken, the NUL included, or 0 for none.
  #: (ptr, ptr, word, bool) -> word
  def zr_crash_expand(at, buf, size, word)
    t = Machine.ptr(Machine.load64(at, 0))
    if size < 2 || Machine.u8(Machine.load8(t, 0)) == 0
      return 0
    end
    p = 0
    stop = size - 1
    store = true
    while true
      c = Machine.u8(Machine.load8(t, 0))
      t += 1
      if word && (c == 32 || (c >= 9 && c <= 13))
        break
      end
      if store
        if c == 37
          c = Machine.u8(Machine.load8(t, 0))
          t += 1
          if c == 101 || c == 69 || c == 102 || c == 70
            p = zr_crash_expand_name(buf, p, stop, c)
            c = 0 - 1
          elsif c == 112
            p = zr_crash_expand_long(buf, p, stop, Machine.u32(Libc.getpid()))
            c = 0 - 1
          elsif c == 116
            ts = Machine.slot(16)
            Libc.clock_gettime(Machine.i32(0), ts)
            p = zr_crash_expand_long(buf, p, stop, Machine.load64(ts, 0))
            c = 0 - 1
          elsif c >= 48 && c <= 55
            # ruby_scan_oct of up to three digits, from this one.
            v = 0
            n = 0
            d = c
            while n < 3 && d >= 48 && d <= 55
              v = (v * 8) + d - 48
              n += 1
              d = Machine.u8(Machine.load8(t + n - 1, 0))
            end
            t += n - 1
            c = v & 255
            if c == 0
              store = false
            end
          end
        end
        if store && c != 0 - 1 && p < stop
          Machine.store8(buf + p, 0, Machine.i8(c))
          p += 1
        end
      end
      if Machine.u8(Machine.load8(t, 0)) == 0
        break
      end
    end
    Machine.store64(at, 0, Machine.word(t))
    Machine.store8(buf + p, 0, Machine.i8(0))
    p + 1
  end

  # `%e`, `%E`, `%f` or `%F` (`kind`) into `buf` at `p`, cut at `stop`.
  #: (ptr, word, word, word) -> word
  def zr_crash_expand_name(buf, p, stop, kind)
    name = Machine.ptr(0)
    len = 0
    if kind == 101 || kind == 69
      table = Machine.ptr(Machine.load64(zr_args_cell(), 0))
      if table != 0 && Machine.load64(table, 0) != 0
        name = Machine.ptr(Machine.load64(table, 0))
        len = zr_cstr_len(name)
      end
    else
      s = zr_global(G_ARGV0)
      if s != QNIL && Machine.word(s) != 0
        name = RString[s].ptr
        len = RString[s].len
      end
    end
    if name == 0
      return p
    end
    start = 0
    if kind == 101 || kind == 102
      i = len
      while i > 0 && Machine.u8(Machine.load8(name + i - 1, 0)) != 47
        i -= 1
      end
      start = i
    end
    i = start
    while i < len && p < stop
      c = Machine.u8(Machine.load8(name + i, 0))
      if c == 47 && (kind == 69 || kind == 70)
        c = 33
      end
      Machine.store8(buf + p, 0, Machine.i8(c))
      p += 1
      i += 1
    end
    p
  end

  # The decimal digits of `n` into `buf` at `p`, cut at `stop`.
  #: (ptr, word, word, word) -> word
  def zr_crash_expand_long(buf, p, stop, n)
    digits = Machine.slot(24)
    k = zr_long_digits(n, digits)
    i = 0
    while i < k && p < stop
      Machine.store8(buf + p, 0, Machine.load8(digits + i, 0))
      p += 1
      i += 1
    end
    p
  end

  # bug_important_message: macOS's note, in reverse video on a terminal.
  # Each line up to the first empty one gets the width of the first, in
  # red, or in green when it starts with a blank.
  #: (ptr, word) -> void
  def zr_crash_notes(msg, len)
    fd = Machine.i32(Machine.load64(Machine.static(:crash_out, 8), 0))
    p = 0
    if Libc.isatty(fd) != Machine.i32(0)
      width = zr_crash_line_len(msg, 0, len)
      while true
        e = p + zr_crash_line_len(msg, p, len)
        if Machine.u8(Machine.load8(msg + p, 0)) == 32
          zr_crash_put(Machine.bytes("\e[;32;7m"), 8)
        else
          zr_crash_put(Machine.bytes("\e[;31;1;7m"), 10)
        end
        zr_crash_put(msg + p, e - p)
        i = e - p
        while i < width
          zr_crash_put(Machine.bytes(" "), 1)
          i += 1
        end
        zr_crash_put(Machine.bytes("\e[m\n"), 4)
        p = e + 1
        if p >= len
          break
        end
        if zr_crash_line_len(msg, p, len) < 2 || p + zr_crash_line_len(msg, p, len) >= len
          break
        end
      end
    end
    zr_crash_put(msg + p, len - p)
  end

  # The bytes from `p` to the next newline.
  #: (ptr, word, word) -> word
  def zr_crash_line_len(msg, p, len)
    i = p
    while i < len && Machine.u8(Machine.load8(msg + i, 0)) != 10
      i += 1
    end
    i - p
  end

  # rb_vmdebug_stack_dump_raw: the frames from the innermost out, each
  # `c:NNNN KIND   place`, with `:name` for a method of the core.
  #: (ptr, ptr) -> void
  def zr_crash_frames(b, top)
    zr_buf_push(b, Machine.bytes("-- Control frame information -----------------------------------------------\n"), 77)
    n = 0
    rec = top
    while rec != 0
      if zr_frame_shown_p(rec)
        n += 1
      end
      rec = Frame[rec].prev
    end
    rec = top
    while rec != 0
      if zr_frame_shown_p(rec)
        zr_buf_push(b, Machine.bytes("c:"), 2)
        zr_crash_pad_long(b, n, 4, 48)
        zr_buf_byte(b, 32)
        meta = Frame[rec].meta
        kind = FrameMeta[meta].kind
        if kind == KIND_BUILTIN
          zr_buf_push(b, Machine.bytes("CFUNC  :"), 8)
          zr_buf_sym(b, FrameMeta[meta].name)
        else
          if kind == KIND_DEF
            zr_buf_push(b, Machine.bytes("METHOD "), 7)
          elsif kind == KIND_BLOCK
            zr_buf_push(b, Machine.bytes("BLOCK  "), 7)
          elsif kind == KIND_CLASS || kind == KIND_MODULE || kind == KIND_SCLASS
            zr_buf_push(b, Machine.bytes("CLASS  "), 7)
          elsif kind == KIND_TOP
            zr_buf_push(b, Machine.bytes("TOP    "), 7)
          else
            zr_buf_push(b, Machine.bytes("EVAL   "), 7)
          end
          zr_crash_place(b, rec, 0)
        end
        zr_buf_byte(b, 10)
        n -= 1
        zr_crash_flush(b)
      end
      rec = Frame[rec].prev
    end
    zr_buf_byte(b, 10)
  end

  # `file:line` of the frame `rec` at its level `level`, or `ruby` and
  # the line for a frame with no file, as oldbt_bugreport writes it.
  #: (ptr, ptr, word) -> void
  def zr_crash_place(b, rec, level)
    source = zr_frame_with_file(rec)
    if source == 0
      zr_buf_push(b, Machine.bytes("ruby:0"), 6)
      return
    end
    meta = Frame[source].meta
    zr_buf_push(b, FrameMeta[meta].file, FrameMeta[meta].file_len)
    zr_buf_byte(b, 58)
    zr_buf_long(b, zr_frame_level_line(source, source == rec ? level : 0))
  end

  # `n` in `width` places, led by `fill`.
  #: (ptr, word, word, word) -> void
  def zr_crash_pad_long(b, n, width, fill)
    digits = Machine.slot(24)
    k = zr_long_digits(n, digits)
    while k < width
      zr_buf_byte(b, fill)
      width -= 1
    end
    zr_buf_push(b, digits, k)
  end

  # rb_backtrace_print_as_bugreport: the frames from the outermost in,
  # `file:line:in 'label'`, with a method's name and no owner.
  #: (ptr, ptr) -> void
  def zr_crash_backtrace(b, top)
    n = 0
    rec = top
    while rec != 0
      if zr_frame_shown_p(rec)
        n += zr_frame_levels(rec)
      end
      rec = Frame[rec].prev
    end
    if n > 0
      rows = zr_xmalloc(n * 16)
      i = 0
      rec = top
      while rec != 0
        if zr_frame_shown_p(rec)
          levels = zr_frame_levels(rec)
          level = 0
          while level < levels
            Machine.store64(rows + (i * 16), 0, Machine.word(rec))
            Machine.store64(rows + (i * 16), 8, level)
            i += 1
            level += 1
          end
        end
        rec = Frame[rec].prev
      end
      zr_buf_push(b, Machine.bytes("-- Ruby level backtrace information ----------------------------------------\n"), 77)
      while i > 0
        i -= 1
        rec = Machine.ptr(Machine.load64(rows + (i * 16), 0))
        zr_crash_place(b, rec, Machine.load64(rows + (i * 16), 8))
        zr_buf_push(b, Machine.bytes(":in '"), 5)
        meta = Frame[rec].meta
        if FrameMeta[meta].kind == KIND_BUILTIN
          zr_buf_sym(b, FrameMeta[meta].name)
        else
          zr_buf_label_as(b, zr_frame_label_meta(rec), false)
        end
        zr_buf_push(b, Machine.bytes("'\n"), 2)
        zr_crash_flush(b)
      end
      zr_xfree(rows)
    end
    zr_buf_byte(b, 10)
  end

  # The ractors and the threads that run: a thread is a fiber that is the
  # root of its own thread.
  #: (ptr) -> void
  def zr_crash_threads(b)
    own = Task[zr_task()].ractor
    seen = Machine.slot(512)
    ractors = 0
    threads = 0
    l = zr_fiber_list()
    i = 0
    while i < FiberList[l].len
      f = Machine.value(Machine.load64(FiberList[l].ptr + (i * 8), 0) & (0 - 2))
      if RFiber[f].home == f && RFiber[f].status != FIBER_TERMINATED && RFiber[f].task != 0
        r = Task[RFiber[f].task].ractor
        if r == own
          threads += 1
        end
        j = 0
        while j < ractors && Machine.load64(seen + (j * 8), 0) != r
          j += 1
        end
        if j == ractors && ractors < 64
          Machine.store64(seen + (j * 8), 0, r)
          ractors += 1
        end
      end
      i += 1
    end
    zr_buf_push(b, Machine.bytes("-- Threading information ---------------------------------------------------\nTotal ractor count: "), 97)
    zr_buf_long(b, ractors == 0 ? 1 : ractors)
    zr_buf_push(b, Machine.bytes("\nRuby thread count for this ractor: "), 36)
    zr_buf_long(b, threads == 0 ? 1 : threads)
    zr_buf_push(b, Machine.bytes("\n\n"), 2)
  end

  # rb_print_backtrace: each native frame as `file(symbol+0xoffset)
  # [0xaddress]`, as dladdr names it.
  #: (ptr) -> void
  def zr_crash_c_frames(b)
    frames = Machine.slot(CRASH_C_FRAMES * 8)
    n = zr_os_c_frames(frames, Machine.i32(CRASH_C_FRAMES))
    if n == 0
      return
    end
    zr_buf_push(b, Machine.bytes("-- C level backtrace information -------------------------------------------\n"), 77)
    info = Machine.slot(32)
    i = 0
    while i < n
      pc = Machine.load64(frames + (i * 8), 0)
      if zr_os_symbol_of(Machine.ptr(pc), info) != 0
        file = Machine.ptr(Machine.load64(info, 0))
        if file != 0
          zr_buf_push(b, file, zr_cstr_len(file))
        end
        sym = Machine.ptr(Machine.load64(info, 16))
        if sym != 0
          zr_buf_byte(b, 40)
          zr_buf_push(b, sym, zr_cstr_len(sym))
          zr_buf_push(b, Machine.bytes("+0x"), 3)
          zr_crash_hex_digits(b, pc - Machine.load64(info, 24))
          zr_buf_byte(b, 41)
        end
        zr_buf_byte(b, 32)
      end
      zr_buf_byte(b, 91)
      zr_crash_hex(b, pc)
      zr_buf_push(b, Machine.bytes("]\n"), 2)
      zr_crash_flush(b)
      i += 1
    end
    zr_buf_byte(b, 10)
  end

  # `v` in hex with no leading zeros.
  #: (ptr, word) -> void
  def zr_crash_hex_digits(b, v)
    shift = 60
    while shift > 0 && ((v >> shift) & 15) == 0
      shift -= 4
    end
    while true
      d = (v >> shift) & 15
      zr_buf_byte(b, d < 10 ? 48 + d : 87 + d)
      if shift == 0
        break
      end
      shift -= 4
    end
  end

  # The loaded script, the state of Ruby::Box, and the loaded features.
  #: (ptr) -> void
  def zr_crash_runtime(b)
    name = zr_global(G_ARGV0)
    if name != QNIL && Machine.word(name) != 0
      zr_buf_push(b, Machine.bytes("* Loaded script: "), 17)
      zr_crash_limited(b, name)
      zr_buf_push(b, Machine.bytes("\n\n"), 2)
    end
    if Libc.getenv(Machine.bytes("RUBY_BOX\0")) == 0
      zr_buf_push(b, Machine.bytes("* Ruby Box: disabled\n"), 21)
    else
      zr_buf_push(b, Machine.bytes("* Ruby Box: enabled\n* Current box id: "), 38)
      box = zr_box_reach()
      kind = box == QNIL ? Machine.value(QNIL) : zr_ivar_get(box, Machine.id(:kind))
      if box == QNIL || kind == zr_sym(Machine.id(:main))
        zr_buf_push(b, Machine.bytes("3, type: main\n"), 14)
      elsif kind == zr_sym(Machine.id(:root)) || kind == zr_sym(Machine.id(:master))
        zr_buf_push(b, kind == zr_sym(Machine.id(:root)) ? Machine.bytes("2, type: root\n") : Machine.bytes("1, type: root\n"), 14)
      else
        number = zr_ivar_get(box, Machine.id(:number))
        zr_buf_long(b, zr_fixnum_p(number) ? zr_fix2long(number) : 0)
        zr_buf_push(b, Machine.bytes(", type: user\n"), 13)
      end
    end
    # The array itself, as rb_dump_loaded_features reads it: no getter
    # runs, so a report from an allocation sends nothing.
    row = zr_gvar_row(Machine.id(:$LOADED_FEATURES))
    features = row == 0 ? Machine.value(QNIL) : IvEntry[row].value
    if !zr_special_p(features) && zr_type(features) == T_ARRAY
      zr_buf_push(b, Machine.bytes("* Loaded features:\n\n"), 20)
      i = 0
      while i < RArray[features].len
        v = Machine.value(Machine.load64(RArray[features].ptr + (i * 8), 0))
        zr_buf_byte(b, 32)
        zr_crash_pad_long(b, i, 4, 32)
        zr_buf_byte(b, 32)
        if !zr_special_p(v) && zr_type(v) == T_STRING
          zr_crash_limited(b, v)
        else
          zr_buf_push(b, Machine.bytes("#<"), 2)
          zr_crash_hex(b, Machine.word(v))
          zr_buf_byte(b, 62)
        end
        zr_buf_byte(b, 10)
        zr_crash_flush(b)
        i += 1
      end
    end
    zr_buf_byte(b, 10)
  end

  # A String, cut at CRASH_NAME_LIMIT bytes.
  #: (ptr, value) -> void
  def zr_crash_limited(b, s)
    n = RString[s].len
    zr_buf_push(b, RString[s].ptr, n > CRASH_NAME_LIMIT ? CRASH_NAME_LIMIT : n)
  end

  # Linux's /proc/self/maps, as the process memory map.
  #: (ptr) -> void
  def zr_crash_maps(b)
    fd = Machine.sword(zr_os_open(Machine.bytes("/proc/self/maps\0"), Machine.i32(CRASH_READ_FLAGS), Machine.i32(0)))
    if fd < 0
      return
    end
    zr_buf_push(b, Machine.bytes("* Process memory map:\n\n"), 23)
    zr_crash_flush(b)
    chunk = Machine.slot(256)
    while true
      n = Machine.sword(Libc.read(Machine.i32(fd), chunk, 256))
      if n <= 0
        break
      end
      zr_crash_put(chunk, n)
    end
    Libc.close(Machine.i32(fd))
    zr_crash_put(Machine.bytes("\n\n"), 2)
  end
end
