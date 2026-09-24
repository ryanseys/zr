# The WASI part of the process environment: the arguments and the
# environment from the host, the clocks, random bits, and the libc
# calls that a module implements itself because WASI has no process,
# user or time zone.

# RUBY_PLATFORM, as ruby 4.0.6 built for WASI gives it.
sig [] => Value
machine def zr_os_ruby_platform
  zr_str_new(Machine.bytes("wasm32-wasi"), 11)
end

# Converts a host vector of `count` 32-bit addresses at `raw` to a
# NULL-terminated table of words, with space for `extra` more.
sig [Ptr, Word, Word] => Ptr
machine def zr_wasi_table(raw, count, extra)
  table = zr_xmalloc((count + extra + 1) * 8)
  i = 0
  while i < count
    Machine.store64(table + (i * 8), 0, Machine.word(Machine.load32(raw + (i * 4), 0)))
    i += 1
  end
  Machine.store64(table + (count * 8), 0, 0)
  zr_xfree(raw)
  table
end

# The arguments come from the host, because `_start` gives main none.
sig [I32, Ptr] => Ptr
machine def zr_os_argv(argc, argv)
  sizes = Machine.slot(8)
  if args_sizes_get(zr_wasi_addr(sizes), zr_wasi_addr(sizes + 4)) != Machine.i32(0)
    return Machine.ptr(0)
  end
  count = Machine.word(Machine.load32(sizes, 0))
  raw = zr_xmalloc((count + 1) * 4)
  bytes = zr_xmalloc(Machine.word(Machine.load32(sizes, 4)) + 1)
  args_get(zr_wasi_addr(raw), zr_wasi_addr(bytes))
  zr_wasi_table(raw, count, 0)
end

# The environment. zr reads the host environment one time into its own
# table, which setenv and unsetenv change in place. The word after the
# table address is the number of free entries in the table.
sig [] => Ptr
machine def zr_os_environ
  cell = Machine.static(:wasi_environ, 16)
  if Machine.load64(cell, 0) != 0
    return Machine.ptr(Machine.load64(cell, 0))
  end
  sizes = Machine.slot(8)
  count = 0
  bytes = 0
  if environ_sizes_get(zr_wasi_addr(sizes), zr_wasi_addr(sizes + 4)) == Machine.i32(0)
    count = Machine.word(Machine.load32(sizes, 0))
    bytes = Machine.word(Machine.load32(sizes, 4))
  end
  raw = zr_xmalloc((count + 1) * 4)
  text = zr_xmalloc(bytes + 1)
  if count > 0
    environ_get(zr_wasi_addr(raw), zr_wasi_addr(text))
  end
  table = zr_wasi_table(raw, count, 8)
  Machine.store64(cell, 0, Machine.word(table))
  Machine.store64(cell, 8, 8)
  table
end

# The entry of `name` in the environment, or the entry that ends it.
sig [Ptr] => Ptr
machine def zr_wasi_env_row(name)
  len = zr_cstr_len(name)
  row = zr_os_environ()
  while Machine.load64(row, 0) != 0
    entry = Machine.ptr(Machine.load64(row, 0))
    if zr_bytes_eq(entry, len, name, len) && Machine.load8(entry + len, 0) == Machine.i8(61)
      return row
    end
    row += 8
  end
  row
end

sig [Ptr] => Ptr
machine def getenv(name)
  entry = Machine.ptr(Machine.load64(zr_wasi_env_row(name), 0))
  if entry == 0
    return entry
  end
  entry + zr_cstr_len(name) + 1
end

sig [Ptr, Ptr, I32] => I32
machine def setenv(name, value, overwrite)
  row = zr_wasi_env_row(name)
  if Machine.load64(row, 0) != 0 && overwrite == Machine.i32(0)
    return Machine.i32(0)
  end
  len = zr_cstr_len(name)
  vlen = zr_cstr_len(value)
  entry = zr_xmalloc(len + vlen + 2)
  zr_memcpy(entry, name, len)
  Machine.store8(entry + len, 0, Machine.i8(61))
  zr_memcpy(entry + len + 1, value, vlen + 1)
  if Machine.load64(row, 0) != 0
    Machine.store64(row, 0, Machine.word(entry))
    return Machine.i32(0)
  end
  cell = Machine.static(:wasi_environ, 16)
  if Machine.load64(cell, 8) == 0
    table = Machine.ptr(Machine.load64(cell, 0))
    used = (Machine.word(row) - Machine.word(table)) / 8
    grown = zr_xmalloc((used * 2 + 1) * 8)
    zr_memcpy(grown, table, (used + 1) * 8)
    zr_xfree(table)
    Machine.store64(cell, 0, Machine.word(grown))
    Machine.store64(cell, 8, used)
    row = grown + (used * 8)
  end
  Machine.store64(row, 0, Machine.word(entry))
  Machine.store64(row, 8, 0)
  Machine.store64(cell, 8, Machine.load64(cell, 8) - 1)
  Machine.i32(0)
end

sig [Ptr] => I32
machine def unsetenv(name)
  row = zr_wasi_env_row(name)
  if Machine.load64(row, 0) == 0
    return Machine.i32(0)
  end
  while Machine.load64(row, 0) != 0
    Machine.store64(row, 0, Machine.load64(row, 8))
    row += 8
  end
  cell = Machine.static(:wasi_environ, 16)
  Machine.store64(cell, 8, Machine.load64(cell, 8) + 1)
  Machine.i32(0)
end

# 32 random bits from the host.
sig [] => Word
machine def zr_os_random
  bits = Machine.slot(8)
  random_get(zr_wasi_addr(bits), Machine.i32(4))
  Machine.word(Machine.load32(bits, 0))
end

# There is no user database: getpwnam and similar calls find no user.
sig [Ptr] => Value
machine def zr_os_passwd_row(pw)
  Machine.value(QNIL)
end

sig [Ptr] => Ptr
machine def zr_os_passwd_dir(pw)
  Machine.ptr(0)
end

# musl's sysconf name for the processor count.
SC_NPROCESSORS_ONLN = 84

# `_SC_PAGESIZE` and `_SC_PHYS_PAGES`. wasi has neither. The names are
# here only so that `Etc.sysconf` has a name to use.
SC_PAGESIZE = 30
SC_PHYS_PAGES = 85

# wasi has no sysconf, so a module that calls it stops, with a message
# that gives the name, before its first line. `zr_machine_bytes` calls
# this in each program. The limit of a module is its own address space,
# not the host's memory. A wasm32 module can address only 4 GiB, and a
# return of 0 lets the heap use all of it.
sig [] => Word
machine def zr_os_machine_bytes
  0
end

# musl's utsname: six fields of 65 bytes: sysname, nodename, release,
# version, machine and domainname.
UTSNAME_LEN = 390
UTSNAME_FIELD = 65

# A module starts no process and changes no id. zr_posix_spawn, which a
# module never calls, uses these sizes for its structures.
SPAWN_ACTIONS_LEN = 16
SPAWN_ATTR_LEN = 16

sig [Value, Value, Value, Value, Value] => Value
machine def zr_os_spawn(words, dups, closes, env, chdir)
  zr_notimplement(Machine.bytes("spawn"), 5)
end

sig [Value, Value] => Value
machine def zr_os_setid(call, id)
  zr_fix(0 - WASI_ENOSYS)
end

sig [] => Value
machine def zr_os_issetugid
  Machine.value(QFALSE)
end

# wasi-libc's values for a process that does not exist: getpid is 42
# (the only value greater than 1 that it uses), the parent is 0, and
# each id is root's.
sig [] => I32
machine def getpid
  Machine.i32(42)
end

sig [] => I32
machine def getppid
  Machine.i32(0)
end

sig [] => I32
machine def getuid
  Machine.i32(0)
end

sig [] => I32
machine def geteuid
  Machine.i32(0)
end

sig [] => I32
machine def getgid
  Machine.i32(0)
end

sig [] => I32
machine def getegid
  Machine.i32(0)
end

sig [I32] => Void
machine def exit(code)
  proc_exit(code)
end

sig [I32] => Void
machine def _exit(code)
  proc_exit(code)
end

# A timespec from nanoseconds in a word.
sig [Ptr, Word] => Void
machine def zr_wasi_timespec(ts, ns)
  Machine.store64(ts, 0, ns / 1000000000)
  Machine.store64(ts, 8, ns % 1000000000)
end

# WASI's clock ids: 0 real time, 1 monotonic, 2 the process's CPU time,
# 3 the thread's CPU time. Process's CLOCK_IDS gives their ruby names.
CLOCK_MONOTONIC = 1

sig [I32, Ptr] => I32
machine def clock_gettime(id, ts)
  out = Machine.slot(8)
  if zr_wasi_status(clock_time_get(id, 1, zr_wasi_addr(out))) < Machine.i32(0)
    return Machine.i32(0 - 1)
  end
  zr_wasi_timespec(ts, Machine.load64(out, 0))
  Machine.i32(0)
end

sig [I32, Ptr] => I32
machine def clock_getres(id, ts)
  out = Machine.slot(8)
  if zr_wasi_status(clock_res_get(id, zr_wasi_addr(out))) < Machine.i32(0)
    return Machine.i32(0 - 1)
  end
  zr_wasi_timespec(ts, Machine.load64(out, 0))
  Machine.i32(0)
end

# A sleep is a wait on the monotonic clock only: one 48-byte
# subscription and one 32-byte event.
sig [Ptr, Ptr] => I32
machine def nanosleep(req, rem)
  sub = Machine.slot(48)
  memset(sub, Machine.i32(0), 48)
  Machine.store32(sub, 16, Machine.i32(1))
  Machine.store64(sub, 24, Machine.load64(req, 0) * 1000000000 + Machine.load64(req, 8))
  event = Machine.slot(32)
  n = Machine.slot(8)
  zr_wasi_status(poll_oneoff(zr_wasi_addr(sub), zr_wasi_addr(event), Machine.i32(1), zr_wasi_addr(n)))
end

# WASI has no time zone: local time is UTC, as wasi-libc gives it.
sig [] => Void
machine def tzset
end

# Fills struct tm for `*t` seconds since the epoch in UTC: seconds,
# minutes, hours, day of the month, month, year since 1900, day of the
# week, day of the year and daylight time as ints, then the offset east
# of UTC at 40 and the zone name at 48. The date calculation is Howard
# Hinnant's civil_from_days.
sig [Ptr, Ptr] => Ptr
machine def localtime_r(t, tm)
  secs = Machine.load64(t, 0)
  days = secs / 86400
  rem = secs % 86400
  if rem < 0
    rem += 86400
    days -= 1
  end
  Machine.store32(tm, 0, Machine.i32(rem % 60))
  Machine.store32(tm, 4, Machine.i32((rem / 60) % 60))
  Machine.store32(tm, 8, Machine.i32(rem / 3600))
  wday = (days + 4) % 7
  if wday < 0
    wday += 7
  end
  z = days + 719468
  era = (z >= 0 ? z : z - 146096) / 146097
  doe = z - (era * 146097)
  yoe = (doe - (doe / 1460) + (doe / 36524) - (doe / 146096)) / 365
  doy = doe - ((365 * yoe) + (yoe / 4) - (yoe / 100))
  mp = ((5 * doy) + 2) / 153
  mday = doy - (((153 * mp) + 2) / 5) + 1
  month = mp < 10 ? mp + 3 : mp - 9
  year = yoe + (era * 400) + (month <= 2 ? 1 : 0)
  Machine.store32(tm, 12, Machine.i32(mday))
  Machine.store32(tm, 16, Machine.i32(month - 1))
  Machine.store32(tm, 20, Machine.i32(year - 1900))
  Machine.store32(tm, 24, Machine.i32(wday))
  Machine.store32(tm, 28, Machine.i32(zr_wasi_year_day(year, month, mday)))
  Machine.store32(tm, 32, Machine.i32(0))
  Machine.store64(tm, 40, 0)
  Machine.store64(tm, 48, Machine.word(Machine.bytes("UTC\0")))
  tm
end

# The day of the year, from 0, of a date in the proleptic Gregorian
# calendar.
sig [Word, Word, Word] => Word
machine def zr_wasi_year_day(year, month, mday)
  before = (((month - 1) * 367) + 5) / 12
  if month > 2
    leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    before -= leap ? 1 : 2
  end
  before + mday - 1
end
