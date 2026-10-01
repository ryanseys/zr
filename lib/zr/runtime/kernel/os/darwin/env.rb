# The darwin part of the process environment: the platform name, the
# location of the environment, the source of random bits, and the
# layouts of struct passwd and struct utsname.
Machine.import "_NSGetEnviron", [] => Ptr
Machine.import "arc4random", [] => I32

# The program's NULL-terminated arguments, which main received.
sig [I32, Ptr] => Ptr
machine def zr_os_argv(argc, argv)
  argv
end

# RUBY_PLATFORM, as ruby 4.0.7 built for this OS and machine gives it.
sig [] => Value
machine def zr_os_ruby_platform
  zr_str_new(Machine.bytes("arm64-darwin23"), 14)
end

# The environment's NULL-terminated table of `NAME=value` strings.
sig [] => Ptr
machine def zr_os_environ
  Machine.ptr(Machine.load64(_NSGetEnviron(), 0))
end

# 32 random bits from the system.
sig [] => Word
machine def zr_os_random
  Machine.word(arc4random()) & 4294967295
end

# The ten fields of darwin's passwd that an Etc::Passwd contains, in the
# order of etc.c's setup_passwd: name at 0, password at 8, uid at 16,
# gid at 20, gecos at 40, dir at 48, shell at 56, then the password
# change time at 24, the login class at 32 and the account expiry at 64.
# The two times are time_t, which INT2NUM converts as an int.
sig [Ptr] => Value
machine def zr_os_passwd_row(pw)
  if pw == 0
    return Machine.value(QNIL)
  end
  out = zr_ary_new(10)
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 0))))
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 8))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(pw, 16))))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(pw, 20))))
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 40))))
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 48))))
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 56))))
  zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(pw, 24))))
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(pw, 32))))
  zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(pw, 64))))
  out
end

# `pw_dir`, 48 bytes into darwin's passwd.
sig [Ptr] => Ptr
machine def zr_os_passwd_dir(pw)
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
sig [] => Word
machine def zr_os_machine_bytes
  pages = sysconf(Machine.i32(SC_PHYS_PAGES))
  size = sysconf(Machine.i32(SC_PAGESIZE))
  pages == 0 - 1 || size == 0 - 1 ? 0 : pages * size
end

# The monotonic clock, with its clock_gettime(2) number.
CLOCK_MONOTONIC = 6

# darwin's utsname: five fields of 256 bytes each: sysname, nodename,
# release, version and machine.
UTSNAME_LEN = 1280
UTSNAME_FIELD = 256

# POSIX_SPAWN_CLOEXEC_DEFAULT: the child gets none of the parent's
# descriptors, only those from the file actions. CRuby gets the same
# result when it opens each descriptor close-on-exec.
SPAWN_CLOEXEC_DEFAULT = 16384
# posix_spawn_file_actions_t and posix_spawnattr_t. Each one is a
# pointer on darwin, and the slot has more space than necessary.
SPAWN_ACTIONS_LEN = 16
SPAWN_ATTR_LEN = 16

sig [Value, Value, Value, Value, Value] => Value
machine def zr_os_spawn(words, dups, closes, env, chdir)
  zr_posix_spawn(words, dups, closes, env, chdir, SPAWN_CLOEXEC_DEFAULT)
end

Machine.import "setuid", [I32] => I32
Machine.import "setgid", [I32] => I32
Machine.import "seteuid", [I32] => I32
Machine.import "setegid", [I32] => I32
Machine.import "setruid", [I32] => I32
Machine.import "setrgid", [I32] => I32
Machine.import "issetugid", [] => I32

# Calls the function that sets a single id, given by its Symbol. Returns
# 0, or the negative errno.
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
    return zr_io_status(setruid(n))
  end
  zr_io_status(setrgid(n))
end

sig [] => Value
machine def zr_os_issetugid
  zr_bool(issetugid() != Machine.i32(0))
end
