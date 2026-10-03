module Zr::Kern
  # The Linux part of the process environment, as musl supplies it: the
  # platform name, the location of the environment, the source of random
  # bits, and the layouts of struct passwd and struct utsname.

  # The program's NULL-terminated arguments, which main received.
  #: (i32, ptr) -> ptr
  def zr_os_argv(argc, argv)
    argv
  end

  # RUBY_PLATFORM, as ruby 4.0.7 built against musl gives it.
  #: () -> value
  def zr_os_ruby_platform
    zr_str_new(Machine.bytes("aarch64-linux-musl"), 18)
  end

  # The environment's NULL-terminated table of `NAME=value` strings.
  #: () -> ptr
  def zr_os_environ
    Machine.ptr(Machine.load64(Machine.extern(:environ), 0))
  end

  # 32 random bits from the kernel.
  #: () -> word
  def zr_os_random
    bits = Machine.slot(8)
    Machine.store64(bits, 0, 0)
    Libc.getrandom(bits, 4, Machine.i32(0))
    Machine.u32(Machine.load32(bits, 0))
  end

  # The seven fields of Linux's passwd that an Etc::Passwd contains, in the
  # order of etc.c's setup_passwd: name at 0, password at 8, uid at 16,
  # gid at 20, gecos at 24, dir at 32 and shell at 40.
  #: (ptr) -> value
  def zr_os_passwd_row(pw)
    if pw == 0
      return Machine.value(QNIL)
    end
    out = zr_ary_new(7)
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 0))))
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 8))))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(pw, 16))))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(pw, 20))))
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 24))))
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 32))))
    zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 40))))
    out
  end

  # `pw_dir`, 32 bytes into Linux's passwd.
  #: (ptr) -> ptr
  def zr_os_passwd_dir(pw)
    Machine.ptr(Machine.load64(pw, 32))
  end

  # `_SC_NPROCESSORS_ONLN`.
  SC_NPROCESSORS_ONLN = 84

  # `_SC_PAGESIZE` and `_SC_PHYS_PAGES`, which give the machine's memory.
  SC_PAGESIZE = 30
  SC_PHYS_PAGES = 85

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
  CLOCK_MONOTONIC = 1

  # Linux's utsname: six fields of 65 bytes each: sysname, nodename,
  # release, version, machine and domainname.
  UTSNAME_LEN = 390
  UTSNAME_FIELD = 65

  # musl's posix_spawn_file_actions_t and posix_spawnattr_t are structures
  # in the caller's memory. A spawned child keeps only the descriptors that
  # are not close-on-exec. ruby opens each descriptor close-on-exec, so no
  # more flags are necessary.
  SPAWN_ACTIONS_LEN = 80
  SPAWN_ATTR_LEN = 336

  #: (value, value, value, value, value) -> value
  def zr_os_spawn(words, dups, closes, env, chdir)
    zr_posix_spawn(words, dups, closes, env, chdir, 0)
  end

  # Calls the function that sets a single id, given by its Symbol. Returns
  # 0, or the negative errno. Linux has no setruid or setrgid. ruby
  # refuses them, with a message that gives the name.
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
      return zr_notimplement(Machine.bytes("setruid"), 7)
    end
    zr_notimplement(Machine.bytes("setrgid"), 7)
  end

  #: () -> value
  def zr_os_issetugid
    zr_bool(Libc.issetugid() != Machine.i32(0))
  end
end
