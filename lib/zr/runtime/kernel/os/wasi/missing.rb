# Derived from the C of CRuby (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.

module Zr::Kern
  # The libc calls that the portable kernel makes and that WASI has no
  # form of: no processes, signals, sockets, terminals, users or dynamic
  # loading. As in CRuby's wasm/missing.c, each call fails with ENOTSUP,
  # so the method that makes it raises Errno::ENOTSUP, which a program
  # can rescue. Without these, the build stopped the module at the call
  # with "has no wasm form". A call whose answer WASI does know (uname,
  # sysconf, getrusage, truncate, utimensat) gives it.

  WASI_ENOTSUP = 58
  WASI_EBADF = 8
  WASI_ECHILD = 12
  WASI_ESRCH = 71
  WASI_ENXIO = 60

  # musl's getaddrinfo error for a name that cannot be resolved.
  EAI_FAIL = 0 - 4

  # The CPU time clock of the process, and the bits of
  # path_filestat_set_times for a given time and for now.
  WASI_PROCESS_CPUTIME = 2
  WASI_SET_ATIM = 1
  WASI_SET_ATIM_NOW = 2
  WASI_SET_MTIM = 4
  WASI_SET_MTIM_NOW = 8

  #: () -> i32
  def zr_wasi_unsupported
    zr_wasi_fail(WASI_ENOTSUP)
  end

  #: () -> ptr
  def zr_wasi_unsupported_ptr
    zr_os_set_errno(WASI_ENOTSUP)
    Machine.ptr(0)
  end

  #: () -> word
  def zr_wasi_unsupported_word
    zr_os_set_errno(WASI_ENOTSUP)
    0 - 1
  end

  # Processes. A module is one process with no children.

  #: () -> i32
  def fork
    zr_notimplement(Machine.bytes("fork"), 4)
    Machine.i32(0 - 1)
  end

  #: (ptr, ptr, ptr) -> i32
  def execve(path, argv, envp)
    zr_wasi_unsupported()
  end

  #: (i32, ptr, i32) -> i32
  def waitpid(pid, status, flags)
    zr_wasi_fail(WASI_ECHILD)
  end

  # Signal 0 to this process tells that it exists. A module receives no
  # other signal.
  #: (i32, i32) -> i32
  def kill(pid, signo)
    if pid != Libc.getpid() && pid != Machine.i32(0)
      return zr_wasi_fail(WASI_ESRCH)
    end
    signo == Machine.i32(0) ? Machine.i32(0) : zr_wasi_unsupported()
  end

  #: (i32, ptr) -> ptr
  def signal(signo, handler)
    Machine.ptr(0)
  end

  #: (ptr) -> i32
  def pipe(fds)
    zr_wasi_unsupported()
  end

  #: (i32) -> i32
  def dup(fd)
    zr_wasi_unsupported()
  end

  #: (i32, i32) -> i32
  def dup2(from, to)
    zr_wasi_unsupported()
  end

  # posix_spawn returns its error. Its helpers only fill structures, so
  # they succeed.
  #: (ptr, ptr, ptr, ptr, ptr, ptr) -> i32
  def posix_spawn(pid, path, actions, attributes, argv, envp)
    Machine.i32(WASI_ENOTSUP)
  end

  #: (ptr, ptr, ptr, ptr, ptr, ptr) -> i32
  def posix_spawnp(pid, file, actions, attributes, argv, envp)
    Machine.i32(WASI_ENOTSUP)
  end

  #: (ptr) -> i32
  def posix_spawn_file_actions_init(actions)
    Machine.i32(0)
  end

  #: (ptr) -> i32
  def posix_spawn_file_actions_destroy(actions)
    Machine.i32(0)
  end

  #: (ptr, i32, i32) -> i32
  def posix_spawn_file_actions_adddup2(actions, from, to)
    Machine.i32(0)
  end

  #: (ptr, i32) -> i32
  def posix_spawn_file_actions_addclose(actions, fd)
    Machine.i32(0)
  end

  #: (ptr, i32) -> i32
  def posix_spawn_file_actions_addinherit_np(actions, fd)
    Machine.i32(0)
  end

  #: (ptr, ptr) -> i32
  def posix_spawn_file_actions_addchdir_np(actions, path)
    Machine.i32(0)
  end

  #: (ptr) -> i32
  def posix_spawnattr_init(attributes)
    Machine.i32(0)
  end

  #: (ptr) -> i32
  def posix_spawnattr_destroy(attributes)
    Machine.i32(0)
  end

  #: (ptr, i32) -> i32
  def posix_spawnattr_setflags(attributes, flags)
    Machine.i32(0)
  end

  #: (ptr, ptr) -> i32
  def posix_spawnattr_setsigdefault(attributes, set)
    Machine.i32(0)
  end

  #: (ptr, ptr) -> i32
  def posix_spawnattr_setsigmask(attributes, set)
    Machine.i32(0)
  end

  # The process is the only one in its group and its session.
  #: () -> i32
  def getpgrp
    Libc.getpid()
  end

  #: (i32) -> i32
  def getpgid(pid)
    pid == Machine.i32(0) || pid == Libc.getpid() ? Libc.getpid() : zr_wasi_fail(WASI_ESRCH)
  end

  #: (i32) -> i32
  def getsid(pid)
    getpgid(pid)
  end

  #: (i32, i32) -> i32
  def setpgid(pid, group)
    zr_wasi_unsupported()
  end

  #: () -> i32
  def setsid
    zr_wasi_unsupported()
  end

  #: (i32, i32) -> i32
  def getpriority(which, who)
    Machine.i32(0)
  end

  #: (i32, i32, i32) -> i32
  def setpriority(which, who, priority)
    zr_wasi_unsupported()
  end

  #: (i32, ptr) -> i32
  def getrlimit(resource, limits)
    zr_wasi_unsupported()
  end

  #: (i32, ptr) -> i32
  def setrlimit(resource, limits)
    zr_wasi_unsupported()
  end

  # The CPU time of the process as user time, from WASI's clock. The
  # kernel reads the two timevals at 0 and 16 (`zr_proc_rusage`).
  #: (i32, ptr) -> i32
  def getrusage(who, ru)
    Libc.memset(ru, Machine.i32(0), 144)
    out = Machine.slot(8)
    if zr_wasi_status(Libc.clock_time_get(Machine.i32(WASI_PROCESS_CPUTIME), 1, zr_wasi_addr(out))) < Machine.i32(0)
      return Machine.i32(0 - 1)
    end
    ns = Machine.load64(out, 0)
    Machine.store64(ru, 0, ns / 1000000000)
    Machine.store32(ru, 8, Machine.i32((ns % 1000000000) / 1000))
    Machine.i32(0)
  end

  # Users and groups. Each id is root's (getuid), and nothing changes it.

  #: (i32, ptr) -> i32
  def getgroups(n, list)
    Machine.i32(0)
  end

  #: (i32, ptr) -> i32
  def setgroups(n, list)
    zr_wasi_unsupported()
  end

  #: (ptr, i32) -> i32
  def initgroups(user, group)
    zr_wasi_unsupported()
  end

  #: (i32, i32) -> i32
  def setreuid(real, effective)
    zr_wasi_unsupported()
  end

  #: (i32, i32) -> i32
  def setregid(real, effective)
    zr_wasi_unsupported()
  end

  #: () -> ptr
  def getlogin
    zr_wasi_unsupported_ptr()
  end

  #: (ptr, ptr) -> ptr
  def crypt(text, salt)
    zr_notimplement(Machine.bytes("crypt"), 5)
    Machine.ptr(0)
  end

  # The system. These are wasi-libc's answers.

  #: (ptr, word, ptr, word) -> word
  def zr_wasi_field(buf, at, text, n)
    zr_memcpy(buf + at, text, n)
    Machine.store8(buf + at + n, 0, Machine.i8(0))
    at + UTSNAME_FIELD
  end

  #: (ptr) -> i32
  def uname(buf)
    Libc.memset(buf, Machine.i32(0), UTSNAME_LEN)
    at = zr_wasi_field(buf, 0, Machine.bytes("wasi"), 4)
    at = zr_wasi_field(buf, at, Machine.bytes("localhost"), 9)
    at = zr_wasi_field(buf, at, Machine.bytes("0.0.0"), 5)
    at = zr_wasi_field(buf, at, Machine.bytes("0.0.0"), 5)
    zr_wasi_field(buf, at, Machine.bytes("wasm32"), 6)
    Machine.i32(0)
  end

  #: (ptr, word) -> i32
  def gethostname(buf, size)
    if size < 10
      return zr_wasi_fail(WASI_ENAMETOOLONG)
    end
    zr_memcpy(buf, Machine.bytes("localhost\0"), 10)
    Machine.i32(0)
  end

  # One processor, WASI's 64 KiB page, and musl's clock tick.
  #: (i32) -> word
  def sysconf(name)
    if name == Machine.i32(SC_NPROCESSORS_ONLN) || name == Machine.i32(SC_NPROCESSORS_ONLN - 1)
      return 1
    end
    if name == Machine.i32(SC_PAGESIZE)
      return 65536
    end
    if name == Machine.i32(2)
      return 100
    end
    zr_os_set_errno(WASI_EINVAL)
    0 - 1
  end

  #: (i32, ptr, word) -> word
  def confstr(name, buf, size)
    zr_os_set_errno(WASI_EINVAL)
    0
  end

  #: (ptr, i32) -> word
  def pathconf(path, name)
    zr_wasi_unsupported_word()
  end

  #: (i32, i32) -> word
  def fpathconf(fd, name)
    zr_wasi_unsupported_word()
  end

  # A guest is never privileged, so chroot fails as it fails for a user
  # who is not root.
  #: (ptr) -> i32
  def chroot(path)
    zr_wasi_fail(WASI_EPERM)
  end

  #: (i32) -> i32
  def fchdir(fd)
    zr_wasi_unsupported()
  end

  # Files. WASI has no permission bits, owners or FIFOs. A mode change on
  # a file that exists does nothing, as fchmod's does.

  #: (ptr, i32) -> i32
  def chmod(path, mode)
    buf = Machine.slot(STAT_LEN)
    zr_wasi_path_stat(path, buf, Machine.i32(1))
  end

  #: (ptr, i32) -> i32
  def lchmod(path, mode)
    buf = Machine.slot(STAT_LEN)
    zr_wasi_path_stat(path, buf, Machine.i32(0))
  end

  #: (ptr, i32, i32) -> i32
  def chown(path, owner, group)
    zr_wasi_unsupported()
  end

  #: (ptr, i32, i32) -> i32
  def lchown(path, owner, group)
    zr_wasi_unsupported()
  end

  #: (ptr, i32) -> i32
  def mkfifo(path, mode)
    zr_wasi_unsupported()
  end

  # No other process can hold a lock, so each lock is granted.
  #: (i32, i32) -> i32
  def flock(fd, operation)
    stat = Machine.slot(FDSTAT_LEN)
    zr_wasi_status(Libc.fd_fdstat_get(fd, zr_wasi_addr(stat)))
  end

  #: (ptr, word) -> i32
  def truncate(path, size)
    fd = zr_os_open(path, Machine.i32(O_WRONLY), Machine.i32(0))
    if fd < Machine.i32(0)
      return fd
    end
    r = ftruncate(fd, size)
    close(fd)
    r
  end

  # The times of a path, from the working directory. Nil `spec` sets
  # both to now.
  #: (i32, ptr, ptr, i32) -> i32
  def utimensat(dirfd, path, spec, flags)
    where = Machine.slot(16)
    dir = zr_wasi_resolve(path, where)
    if dir < Machine.i32(0)
      return dir
    end
    atime = 0
    mtime = 0
    set = WASI_SET_ATIM_NOW | WASI_SET_MTIM_NOW
    if spec != 0
      atime = (Machine.load64(spec, 0) * 1000000000) + Machine.load64(spec, 8)
      mtime = (Machine.load64(spec, 16) * 1000000000) + Machine.load64(spec, 24)
      set = WASI_SET_ATIM | WASI_SET_MTIM
    end
    follow = (Machine.u32(flags) & AT_SYMLINK_NOFOLLOW) != 0 ? 0 : 1
    zr_wasi_status(Libc.path_filestat_set_times(dir, Machine.i32(follow), zr_wasi_rest(where), zr_wasi_rest_len(where),
                                                atime, mtime, Machine.i32(set)))
  end

  #: (ptr, ptr) -> ptr
  def realpath(path, out)
    zr_os_realpath(path)
  end

  #: (ptr, word) -> i32
  def munmap(at, size)
    zr_wasi_fail(WASI_EINVAL)
  end

  #: (ptr, i32, word) -> ptr
  def memchr(p, c, n)
    want = Machine.u8(Machine.i8(c))
    i = 0
    while i < n
      if Machine.u8(Machine.load8(p + i, 0)) == want
        return p + i
      end
      i += 1
    end
    Machine.ptr(0)
  end

  # Terminals. No descriptor is one.

  #: (i32, ptr) -> i32
  def tcgetattr(fd, buf)
    zr_wasi_fail(WASI_ENOTTY)
  end

  #: (i32, i32, ptr) -> i32
  def tcsetattr(fd, action, buf)
    zr_wasi_fail(WASI_ENOTTY)
  end

  #: (i32, i32) -> i32
  def tcflush(fd, queue)
    zr_wasi_fail(WASI_ENOTTY)
  end

  #: (i32) -> ptr
  def ttyname(fd)
    zr_os_set_errno(WASI_ENOTTY)
    Machine.ptr(0)
  end

  #: (i32) -> i32
  def posix_openpt(flags)
    zr_wasi_unsupported()
  end

  #: (i32) -> i32
  def grantpt(fd)
    zr_wasi_unsupported()
  end

  #: (i32) -> i32
  def unlockpt(fd)
    zr_wasi_unsupported()
  end

  #: (i32) -> ptr
  def ptsname(fd)
    zr_wasi_unsupported_ptr()
  end

  # Dynamic loading. A module cannot load code, so FFI, Fiddle and a C
  # extension raise LoadError with dlerror's message.

  #: (ptr, i32) -> ptr
  def dlopen(path, flags)
    Machine.ptr(0)
  end

  #: () -> ptr
  def dlerror
    Machine.bytes("dynamic loading is not supported on WASI\0")
  end

  #: (ptr, ptr) -> ptr
  def dlsym(handle, name)
    Machine.ptr(0)
  end

  #: (ptr, ptr) -> i32
  def dladdr(at, info)
    Machine.i32(0)
  end

  # The system log. A module has none to write to.

  #: (ptr, i32, i32) -> void
  def openlog(ident, options, facility)
  end

  #: () -> void
  def closelog
  end

  #: (i32, ptr) -> void
  def syslog(priority, format)
  end

  #: (i32) -> i32
  def setlogmask(mask)
    cell = Machine.static(:wasi_logmask, 8)
    old = Machine.load32(cell, 0)
    if mask != Machine.i32(0)
      Machine.store32(cell, 0, mask)
    end
    old
  end

  # Sockets. WASI preview 1 opens none and resolves no name.

  #: (i32, i32, i32) -> i32
  def socket(domain, type, protocol)
    zr_wasi_unsupported()
  end

  #: (i32, i32, i32, ptr) -> i32
  def socketpair(domain, type, protocol, fds)
    zr_wasi_unsupported()
  end

  #: (i32, ptr, i32) -> i32
  def bind(fd, addr, len)
    zr_wasi_unsupported()
  end

  #: (i32, ptr, i32) -> i32
  def connect(fd, addr, len)
    zr_wasi_unsupported()
  end

  #: (i32, i32) -> i32
  def listen(fd, backlog)
    zr_wasi_unsupported()
  end

  #: (i32, ptr, ptr) -> i32
  def accept(fd, addr, len)
    zr_wasi_unsupported()
  end

  #: (i32, i32) -> i32
  def shutdown(fd, how)
    zr_wasi_unsupported()
  end

  #: (i32, ptr, ptr) -> i32
  def getsockname(fd, addr, len)
    zr_wasi_unsupported()
  end

  #: (i32, ptr, ptr) -> i32
  def getpeername(fd, addr, len)
    zr_wasi_unsupported()
  end

  #: (i32, i32, i32, ptr, ptr) -> i32
  def getsockopt(fd, level, name, value, len)
    zr_wasi_unsupported()
  end

  #: (i32, i32, i32, ptr, i32) -> i32
  def setsockopt(fd, level, name, value, len)
    zr_wasi_unsupported()
  end

  #: (i32, ptr, word, i32) -> word
  def send(fd, buf, n, flags)
    zr_wasi_unsupported_word()
  end

  #: (i32, ptr, word, i32, ptr, i32) -> word
  def sendto(fd, buf, n, flags, addr, len)
    zr_wasi_unsupported_word()
  end

  #: (i32, ptr, i32) -> word
  def sendmsg(fd, header, flags)
    zr_wasi_unsupported_word()
  end

  #: (i32, ptr, word, i32, ptr, ptr) -> word
  def recvfrom(fd, buf, n, flags, addr, len)
    zr_wasi_unsupported_word()
  end

  #: (i32, ptr, i32) -> word
  def recvmsg(fd, header, flags)
    zr_wasi_unsupported_word()
  end

  #: (i32, ptr, ptr) -> i32
  def inet_pton(family, text, out)
    zr_wasi_unsupported()
  end

  #: (ptr, ptr, ptr, ptr) -> i32
  def getaddrinfo(host, service, hints, out)
    Machine.i32(EAI_FAIL)
  end

  #: (ptr, i32, ptr, i32, ptr, i32, i32) -> i32
  def getnameinfo(addr, len, host, hostlen, service, servicelen, flags)
    Machine.i32(EAI_FAIL)
  end

  #: (ptr) -> void
  def freeaddrinfo(list)
  end

  #: (i32) -> ptr
  def gai_strerror(code)
    Machine.bytes("Non-recoverable failure in name resolution\0")
  end

  #: (ptr, ptr) -> ptr
  def getservbyname(name, protocol)
    Machine.ptr(0)
  end

  #: (i32, ptr) -> ptr
  def getservbyport(port, protocol)
    Machine.ptr(0)
  end

  #: (ptr) -> i32
  def getifaddrs(out)
    zr_wasi_unsupported()
  end

  #: (ptr) -> void
  def freeifaddrs(list)
  end

  #: (ptr) -> i32
  def if_nametoindex(name)
    Machine.i32(0)
  end

  #: (i32, ptr) -> ptr
  def if_indextoname(index, out)
    zr_os_set_errno(WASI_ENXIO)
    Machine.ptr(0)
  end
end
