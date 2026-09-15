# darwin's half of the process's surroundings: the platform's name,
# where the environment is, where random bits come from, and the layouts
# of struct passwd and struct utsname.
Machine.import "_NSGetEnviron", [] => Ptr
Machine.import "arc4random", [] => I32

# RUBY_PLATFORM, as ruby 4.0.6 built for this OS and machine names it.
sig [] => Value
machine def zr_os_ruby_platform
  zr_str_new(Machine.bytes("arm64-darwin23"), 14)
end

# The environment's NULL-ended table of `NAME=value` strings.
sig [] => Ptr
machine def zr_os_environ
  Machine.ptr(Machine.load64(_NSGetEnviron(), 0))
end

# 32 random bits from the system.
sig [] => Word
machine def zr_os_random
  Machine.word(arc4random()) & 4294967295
end

# The ten fields of darwin's passwd an Etc::Passwd carries, in the order
# etc.c's setup_passwd gives them: name at 0, password at 8, uid at 16,
# gid at 20, gecos at 40, dir at 48, shell at 56, then the password's
# change time at 24, the login class at 32 and the account's expiry at
# 64. The two times are time_t, which INT2NUM takes as an int.
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

# darwin's utsname: five fields of 256 bytes each, sysname, nodename,
# release, version and machine.
UTSNAME_LEN = 1280
UTSNAME_FIELD = 256

# Child processes through posix_spawn, which is not variadic.
Machine.import "posix_spawnp", [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => I32
Machine.import "posix_spawn_file_actions_init", [Ptr] => I32
Machine.import "posix_spawn_file_actions_adddup2", [Ptr, I32, I32] => I32
Machine.import "posix_spawn_file_actions_addclose", [Ptr, I32] => I32
Machine.import "posix_spawn_file_actions_addchdir_np", [Ptr, Ptr] => I32
Machine.import "posix_spawn_file_actions_destroy", [Ptr] => I32
Machine.import "posix_spawnattr_init", [Ptr] => I32
Machine.import "posix_spawnattr_setflags", [Ptr, I32] => I32
Machine.import "posix_spawnattr_destroy", [Ptr] => I32
# POSIX_SPAWN_CLOEXEC_DEFAULT: every descriptor the parent holds stays
# behind, and only the file actions cross into the child. That is what
# CRuby reaches by opening each descriptor close-on-exec.
SPAWN_CLOEXEC_DEFAULT = 16384

# Spawn `words` (an Array of Strings, the program first). `dups` is a
# flat Array of (child descriptor, source descriptor) pairs applied in
# order, `closes` the child's descriptors to shut, `env` the child's
# whole environment as "KEY=value" strings or nil to inherit it, and
# `chdir` the child's directory or nil. The pid, or the negated errno.
sig [Value, Value, Value, Value, Value] => Value
machine def zr_os_spawn(words, dups, closes, env, chdir)
  argv = zr_spawn_vector(words)
  actions = Machine.slot(16)
  posix_spawn_file_actions_init(actions)
  attributes = Machine.slot(16)
  posix_spawnattr_init(attributes)
  posix_spawnattr_setflags(attributes, Machine.i32(SPAWN_CLOEXEC_DEFAULT))
  n = RArray.len(dups)
  i = 0
  while i < n
    posix_spawn_file_actions_adddup2(actions, Machine.i32(zr_fix2long(zr_ary_at(dups, i + 1))), Machine.i32(zr_fix2long(zr_ary_at(dups, i))))
    i += 2
  end
  n = RArray.len(closes)
  i = 0
  while i < n
    posix_spawn_file_actions_addclose(actions, Machine.i32(zr_fix2long(zr_ary_at(closes, i))))
    i += 1
  end
  if chdir != QNIL
    posix_spawn_file_actions_addchdir_np(actions, RString.ptr(chdir))
  end
  envp = zr_os_environ()
  if env != QNIL
    envp = zr_spawn_vector(env)
  end
  pid = Machine.slot(8)
  Machine.store64(pid, 0, 0)
  r = posix_spawnp(pid, RString.ptr(zr_ary_at(words, 0)), actions, attributes, argv, envp)
  posix_spawn_file_actions_destroy(actions)
  posix_spawnattr_destroy(attributes)
  free(argv)
  if env != QNIL
    free(envp)
  end
  if r != Machine.i32(0)
    return zr_fix(0 - Machine.word(r))
  end
  zr_fix(Machine.word(Machine.load32(pid, 0)))
end

Machine.import "setuid", [I32] => I32
Machine.import "setgid", [I32] => I32
Machine.import "seteuid", [I32] => I32
Machine.import "setegid", [I32] => I32
Machine.import "setruid", [I32] => I32
Machine.import "setrgid", [I32] => I32
Machine.import "issetugid", [] => I32

# One of the calls that set a single id, named by its Symbol: 0, or the
# errno as a negative.
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
