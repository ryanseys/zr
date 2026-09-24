# Linux's half of the process's surroundings, as musl answers them: the
# platform's name, where the environment is, where random bits come
# from, and the layouts of struct passwd and struct utsname.
Machine.import "getrandom", [Ptr, Word, I32] => Word

# The program's NULL-ended arguments, which main was given.
sig [I32, Ptr] => Ptr
machine def zr_os_argv(argc, argv)
  argv
end

# RUBY_PLATFORM, as ruby 4.0.6 built against musl names it.
sig [] => Value
machine def zr_os_ruby_platform
  zr_str_new(Machine.bytes("aarch64-linux-musl"), 18)
end

# The environment's NULL-ended table of `NAME=value` strings.
sig [] => Ptr
machine def zr_os_environ
  Machine.ptr(Machine.load64(Machine.extern(:environ), 0))
end

# 32 random bits from the kernel.
sig [] => Word
machine def zr_os_random
  bits = Machine.slot(8)
  Machine.store64(bits, 0, 0)
  getrandom(bits, 4, Machine.i32(0))
  Machine.word(Machine.load32(bits, 0))
end

# The seven fields of Linux's passwd an Etc::Passwd carries, in the
# order etc.c's setup_passwd gives them: name at 0, password at 8, uid
# at 16, gid at 20, gecos at 24, dir at 32 and shell at 40.
sig [Ptr] => Value
machine def zr_os_passwd_row(pw)
  if pw == 0
    return Machine.value(QNIL)
  end
  out = zr_ary_new(7)
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 0))))
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 8))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(pw, 16))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(pw, 20))))
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 24))))
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 32))))
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 40))))
  out
end

# `pw_dir`, 32 bytes into Linux's passwd.
sig [Ptr] => Ptr
machine def zr_os_passwd_dir(pw)
  Machine.ptr(Machine.load64(pw, 32))
end

# `_SC_NPROCESSORS_ONLN`.
SC_NPROCESSORS_ONLN = 84

# `_SC_PAGESIZE` and `_SC_PHYS_PAGES`, which say what the machine has.
SC_PAGESIZE = 30
SC_PHYS_PAGES = 85

# What this machine has, for the bound the heap's growth keeps under
# (`zr_machine_bytes`, runtime/kernel/heap.rb), or 0 where the host will not
# say -- sysconf answers -1 for a name it does not know.
sig [] => Word
machine def zr_os_machine_bytes
  pages = sysconf(Machine.i32(SC_PHYS_PAGES))
  size = sysconf(Machine.i32(SC_PAGESIZE))
  pages == 0 - 1 || size == 0 - 1 ? 0 : pages * size
end

# The clock that never jumps, as clock_gettime(2) numbers it.
CLOCK_MONOTONIC = 1

# Linux's utsname: six fields of 65 bytes each, sysname, nodename,
# release, version, machine and domainname.
UTSNAME_LEN = 390
UTSNAME_FIELD = 65

# musl's posix_spawn_file_actions_t and posix_spawnattr_t are structures
# the caller holds. A spawned child keeps only what is not close-on-exec,
# and ruby opens every descriptor close-on-exec, so no flag asks more.
SPAWN_ACTIONS_LEN = 80
SPAWN_ATTR_LEN = 336

sig [Value, Value, Value, Value, Value] => Value
machine def zr_os_spawn(words, dups, closes, env, chdir)
  zr_posix_spawn(words, dups, closes, env, chdir, 0)
end

Machine.import "setuid", [I32] => I32
Machine.import "setgid", [I32] => I32
Machine.import "seteuid", [I32] => I32
Machine.import "setegid", [I32] => I32
Machine.import "issetugid", [] => I32

# One of the calls that set a single id, named by its Symbol: 0, or the
# errno as a negative. Linux has no setruid or setrgid, which ruby
# refuses by name.
sig [Value, Value] => Value
machine def zr_os_setid(call, id)
  mid = zr_sym2id(call)
  n = Machine.i32(zr_fix2long(id))
  if mid == Machine.id(:setuid)
    return zr_io_status(setuid(n))
  elsif mid == Machine.id(:setgid)
    return zr_io_status(setgid(n))
  elsif mid == Machine.id(:seteuid)
    return zr_io_status(seteuid(n))
  elsif mid == Machine.id(:setegid)
    return zr_io_status(setegid(n))
  elsif mid == Machine.id(:setruid)
    return zr_notimplement(Machine.bytes("setruid"), 7)
  end
  zr_notimplement(Machine.bytes("setrgid"), 7)
end

sig [] => Value
machine def zr_os_issetugid
  zr_bool(issetugid() != Machine.i32(0))
end
