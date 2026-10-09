module Zr::Kern
  # The darwin part of the process environment: the platform name, the
  # location of the environment, the source of random bits, and the
  # layouts of struct passwd and struct utsname.

  # The program's NULL-terminated arguments, which main received.
  #: (i32, ptr) -> ptr
  def zr_os_argv(argc, argv)
    argv
  end

  # RUBY_PLATFORM, as ruby 4.0.7 built for this OS and machine gives it.
  #: () -> value
  def zr_os_ruby_platform
    zr_str_new(Machine.bytes("arm64-darwin23"), 14)
  end

  # Whether this OS takes a path in UTF-8: macOS does, so ruby's
  # rb_str_encode_ospath converts a path in another encoding.
  #: () -> word
  def zr_os_ospath_utf8
    1
  end

  # The locale's codeset, as ruby's main sets it: setlocale(LC_CTYPE, "")
  # from the environment, then nl_langinfo(CODESET). LC_CTYPE is 2 and
  # CODESET is 0 in darwin's headers.
  #: () -> value
  def zr_os_locale_charmap
    empty = Machine.slot(8)
    Machine.store64(empty, 0, 0)
    Libc.setlocale(Machine.i32(2), empty)
    codeset = Libc.nl_langinfo(Machine.i32(0))
    zr_str_new(codeset, zr_cstr_len(codeset))
  end

  # The environment's NULL-terminated table of `NAME=value` strings.
  #: () -> ptr
  def zr_os_environ
    Machine.ptr(Machine.load64(Libc._NSGetEnviron(), 0))
  end

  # 32 random bits from the system.
  #: () -> word
  def zr_os_random
    Machine.u32(Libc.arc4random()) & 4294967295
  end

  # The ten fields of darwin's passwd that an Etc::Passwd contains, in the
  # order of etc.c's setup_passwd: name at 0, password at 8, uid at 16,
  # gid at 20, gecos at 40, dir at 48, shell at 56, then the password
  # change time at 24, the login class at 32 and the account expiry at 64.
  # The two times are time_t, which INT2NUM converts as an int.
  #: (ptr) -> value
  def zr_os_passwd_row(pw)
    if pw == 0
      return Machine.value(QNIL)
    end
    out = zr_ary_new(10)
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 0))))
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 8))))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(pw, 16))))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(pw, 20))))
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 40))))
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 48))))
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 56))))
    zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(pw, 24))))
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 32))))
    zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(pw, 64))))
    out
  end

  # `pw_dir`, 48 bytes into darwin's passwd.
  #: (ptr) -> ptr
  def zr_os_passwd_dir(pw)
    Machine.ptr(Machine.load64(pw, 48))
  end

  # `_SC_NPROCESSORS_ONLN`.
  SC_NPROCESSORS_ONLN = 58

  # `_SC_PAGESIZE` and `_SC_PHYS_PAGES`, which give the machine's memory.
  SC_PAGESIZE = 29
  SC_PHYS_PAGES = 200

  # The machine's physical memory, for the limit on heap growth
  # (`zr_machine_bytes`, lib/zr/runtime/kernel/heap.rb). Returns 0 if the host does
  # not give it: sysconf returns -1 for a name that it does not know.
  #: () -> word
  def zr_os_machine_bytes
    pages = Libc.sysconf(Machine.i32(SC_PHYS_PAGES))
    size = Libc.sysconf(Machine.i32(SC_PAGESIZE))
    pages == 0 - 1 || size == 0 - 1 ? 0 : pages * size
  end

  # The monotonic clock, with its clock_gettime(2) number.
  CLOCK_MONOTONIC = 6

  # darwin's utsname: five fields of 256 bytes each: sysname, nodename,
  # release, version and machine.
  UTSNAME_LEN = 1280
  UTSNAME_FIELD = 256

  # POSIX_SPAWN_CLOEXEC_DEFAULT: the child gets none of the parent's
  # descriptors, only those from the file actions (`close_others: true`).
  SPAWN_CLOEXEC_DEFAULT = 16384
  # posix_spawn_file_actions_t and posix_spawnattr_t. Each one is a
  # pointer on darwin, and the slot has more space than necessary.
  SPAWN_ACTIONS_LEN = 16
  SPAWN_ATTR_LEN = 16

  # The child gets each descriptor that is not close-on-exec, as ruby's
  # does, unless `close_others` asks for none but the redirected ones.
  #: (value, value, value, value, value, value) -> value
  def zr_os_spawn(words, dups, closes, env, chdir, close_others)
    zr_posix_spawn(words, dups, closes, env, chdir, close_others == QTRUE ? SPAWN_CLOEXEC_DEFAULT : 0)
  end

  # A descriptor that the child keeps although it is close-on-exec.
  #: (ptr, word) -> void
  def zr_os_spawn_keep(actions, fd)
    Libc.posix_spawn_file_actions_addinherit_np(actions, Machine.i32(fd))
  end

  # Calls the function that sets a single id, given by its Symbol. Returns
  # 0, or the negative errno.
  #: (value, value) -> value
  def zr_os_setid(call, id)
    mid = zr_sym2id(call)
    n = Machine.i32(zr_fix2long(id))
    if mid == Machine.id(:setuid)
      return zr_io_status(Libc.setuid(n))
    elsif mid == Machine.id(:setgid)
      return zr_io_status(Libc.setgid(n))
    elsif mid == Machine.id(:seteuid)
      return zr_io_status(Libc.seteuid(n))
    elsif mid == Machine.id(:setegid)
      return zr_io_status(Libc.setegid(n))
    elsif mid == Machine.id(:setruid)
      return zr_io_status(Libc.setruid(n))
    end
    zr_io_status(Libc.setrgid(n))
  end

  #: () -> value
  def zr_os_issetugid
    zr_bool(Libc.issetugid() != Machine.i32(0))
  end

  # Darwin's getgroups(2) with no NGROUPS_MAX (16) limit, which CRuby
  # calls (unistd.h aliases it from 10.6 on). Plain `getgroups` stops at
  # 16 groups.
  module GetgroupsCall
    #: (ptr, i32, ptr) -> i32
    def self.call(fn, i, p) = Machine.indirect
  end

  #: (word, ptr) -> word
  def zr_os_getgroups(n, list)
    cell = Machine.static(:getgroups_fn, 8)
    if Machine.load64(cell, 0) == 0
      Machine.store64(cell, 0, Machine.word(Libc.dlsym(Machine.ptr(RTLD_DEFAULT), Machine.bytes("getgroups$DARWIN_EXTSN\0"))))
    end
    Machine.sword(GetgroupsCall.call(Machine.ptr(Machine.load64(cell, 0)), Machine.i32(n), list))
  end
end
