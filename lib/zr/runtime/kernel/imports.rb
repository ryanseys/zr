module Zr::Kern
  # The C functions that the portable kernel calls, as `Libc.name(...)`.
  # The linker finds each in the C library; an OS layer defines a def
  # of the same name for one that its OS does not have.
  module Libc
    #: (ptr, ptr, i32) -> i32
    def self.setenv(p1, p2, i) = Machine.import
    #: (ptr) -> i32
    def self.unsetenv(p) = Machine.import
    #: (ptr, word) -> ptr
    def self.getcwd(p, n) = Machine.import

    #: () -> i32
    def self.getpid = Machine.import
    #: (ptr, i32) -> i32
    def self.access(p, i) = Machine.import
    #: (ptr, ptr) -> i32
    def self.stat(p1, p2) = Machine.import

    #: () -> i32
    def self.getuid = Machine.import
    #: () -> i32
    def self.geteuid = Machine.import
    #: () -> i32
    def self.getgid = Machine.import
    #: () -> i32
    def self.getegid = Machine.import

    #: (i32, ptr) -> i32
    def self.clock_gettime(i, p) = Machine.import
    #: (i32, ptr) -> i32
    def self.clock_getres(i, p) = Machine.import
    #: (ptr, ptr) -> ptr
    def self.crypt(p1, p2) = Machine.import
    #: (ptr, ptr) -> i32
    def self.nanosleep(p1, p2) = Machine.import

    #: () -> void
    def self.tzset = Machine.import
    #: (ptr, ptr) -> ptr
    def self.localtime_r(p1, p2) = Machine.import

    #: (i32) -> void
    def self._exit(i) = Machine.import

    #: (ptr) -> ptr
    def self.getpwnam(p) = Machine.import
    #: (i32) -> ptr
    def self.getpwuid(i) = Machine.import

    #: (ptr) -> ptr
    def self.getgrnam(p) = Machine.import
    #: (i32) -> ptr
    def self.getgrgid(i) = Machine.import
    #: () -> void
    def self.setpwent = Machine.import
    #: () -> void
    def self.endpwent = Machine.import
    #: () -> ptr
    def self.getpwent = Machine.import
    #: () -> void
    def self.setgrent = Machine.import
    #: () -> void
    def self.endgrent = Machine.import
    #: () -> ptr
    def self.getgrent = Machine.import
    #: (i32) -> word
    def self.sysconf(i) = Machine.import
    #: (i32, ptr, word) -> word
    def self.confstr(i, p, n) = Machine.import
    #: (ptr, i32) -> word
    def self.pathconf(p, i) = Machine.import
    #: (i32, i32) -> word
    def self.fpathconf(i1, i2) = Machine.import
    #: (ptr) -> i32
    def self.uname(p) = Machine.import
    #: () -> ptr
    def self.getlogin = Machine.import

    #: (ptr, i32) -> ptr
    def self.dlopen(p, i) = Machine.import
    #: (ptr, ptr) -> ptr
    def self.dlsym(p1, p2) = Machine.import
    #: () -> ptr
    def self.dlerror = Machine.import
    #: (ptr, i32, word) -> ptr
    def self.memchr(p, i, n) = Machine.import

    #: (ptr, word) -> i32
    def self.munmap(p, n) = Machine.import

    #: (f64, f64) -> f64
    def self.fmod(x1, x2) = Machine.import
    #: (f64, f64) -> f64
    def self.pow(x1, x2) = Machine.import

    #: (ptr, ptr) -> f64
    def self.strtod(p1, p2) = Machine.import
    #: (f64) -> f64
    def self.cbrt(x) = Machine.import
    #: (f64) -> f64
    def self.sin(x) = Machine.import
    #: (f64) -> f64
    def self.cos(x) = Machine.import
    #: (f64) -> f64
    def self.tan(x) = Machine.import
    #: (f64) -> f64
    def self.atan(x) = Machine.import
    #: (f64) -> f64
    def self.exp(x) = Machine.import
    #: (f64, f64) -> f64
    def self.atan2(x1, x2) = Machine.import
    #: (f64, f64) -> f64
    def self.hypot(x1, x2) = Machine.import
    #: (f64) -> f64
    def self.sinh(x) = Machine.import
    #: (f64) -> f64
    def self.cosh(x) = Machine.import
    #: (f64) -> f64
    def self.tanh(x) = Machine.import
    #: (f64) -> f64
    def self.log(x) = Machine.import
    #: (f64) -> f64
    def self.log2(x) = Machine.import
    #: (f64) -> f64
    def self.log10(x) = Machine.import
    #: (f64) -> f64
    def self.asin(x) = Machine.import
    #: (f64) -> f64
    def self.acos(x) = Machine.import
    #: (f64) -> f64
    def self.asinh(x) = Machine.import
    #: (f64) -> f64
    def self.acosh(x) = Machine.import
    #: (f64) -> f64
    def self.atanh(x) = Machine.import
    #: (f64) -> f64
    def self.tgamma(x) = Machine.import
    #: (f64, ptr) -> f64
    def self.lgamma_r(x, p) = Machine.import
    #: (f64) -> f64
    def self.erf(x) = Machine.import
    #: (f64) -> f64
    def self.erfc(x) = Machine.import
    #: (f64) -> f64
    def self.expm1(x) = Machine.import
    #: (f64) -> f64
    def self.log1p(x) = Machine.import
    #: (f64, f64, f64) -> f64
    def self.fma(x1, x2, x3) = Machine.import
    #: (f64, i32) -> f64
    def self.ldexp(x, i) = Machine.import
    #: (f64, ptr) -> f64
    def self.frexp(x, p) = Machine.import

    #: (i32, ptr, word) -> word
    def self.read(i, p, n) = Machine.import
    #: (i32, ptr, word, word) -> word
    def self.pread(i, p, n1, n2) = Machine.import
    #: (i32, ptr, word, word) -> word
    def self.pwrite(i, p, n1, n2) = Machine.import
    #: (i32) -> i32
    def self.close(i) = Machine.import
    #: (i32) -> i32
    def self.dup(i) = Machine.import
    #: (i32, i32) -> i32
    def self.dup2(i1, i2) = Machine.import
    #: (i32) -> i32
    def self.fsync(i) = Machine.import
    #: (i32, word, i32) -> word
    def self.lseek(i1, n, i2) = Machine.import
    #: (ptr) -> i32
    def self.unlink(p) = Machine.import
    #: (ptr, ptr) -> i32
    def self.rename(p1, p2) = Machine.import
    #: (i32) -> i32
    def self.isatty(i) = Machine.import
    #: (i32, ptr) -> i32
    def self.fstat(i, p) = Machine.import
    #: (i32, i32) -> i32
    def self.fchmod(i1, i2) = Machine.import
    #: (ptr, i32) -> i32
    def self.mkdir(p, i) = Machine.import
    #: (ptr) -> i32
    def self.rmdir(p) = Machine.import
    #: (ptr) -> i32
    def self.chdir(p) = Machine.import
    #: (ptr) -> ptr
    def self.opendir(p) = Machine.import
    #: (i32) -> ptr
    def self.fdopendir(i) = Machine.import
    #: (i32) -> i32
    def self.fchdir(i) = Machine.import
    #: (ptr) -> ptr
    def self.readdir(p) = Machine.import
    #: (ptr) -> i32
    def self.closedir(p) = Machine.import
    #: (i32) -> ptr
    def self.strerror(i) = Machine.import

    #: (i32, ptr) -> i32
    def self.tcgetattr(i, p) = Machine.import
    #: (i32, i32, ptr) -> i32
    def self.tcsetattr(i1, i2, p) = Machine.import
    #: (i32, i32) -> i32
    def self.tcflush(i1, i2) = Machine.import
    #: (i32) -> ptr
    def self.ttyname(i) = Machine.import

    #: (i32) -> i32
    def self.posix_openpt(i) = Machine.import
    #: (i32) -> i32
    def self.grantpt(i) = Machine.import
    #: (i32) -> i32
    def self.unlockpt(i) = Machine.import
    #: (i32) -> ptr
    def self.ptsname(i) = Machine.import

    #: (ptr) -> i32
    def self.chroot(p) = Machine.import

    #: (ptr, ptr) -> i32
    def self.lstat(p1, p2) = Machine.import
    #: (ptr, ptr) -> ptr
    def self.realpath(p1, p2) = Machine.import
    #: (ptr, i32) -> i32
    def self.chmod(p, i) = Machine.import
    #: (ptr, i32, i32) -> i32
    def self.chown(p, i1, i2) = Machine.import
    #: (ptr, i32, i32) -> i32
    def self.lchown(p, i1, i2) = Machine.import
    #: (ptr, i32) -> i32
    def self.lchmod(p, i) = Machine.import
    #: (ptr, ptr) -> i32
    def self.link(p1, p2) = Machine.import
    #: (ptr, ptr) -> i32
    def self.symlink(p1, p2) = Machine.import
    #: (ptr, ptr, word) -> word
    def self.readlink(p1, p2, n) = Machine.import
    #: (ptr, i32) -> i32
    def self.mkfifo(p, i) = Machine.import
    #: (ptr, word) -> i32
    def self.truncate(p, n) = Machine.import
    #: (i32, word) -> i32
    def self.ftruncate(i, n) = Machine.import
    #: (i32) -> i32
    def self.umask(i) = Machine.import
    #: (i32, ptr, ptr, i32) -> i32
    def self.utimensat(i1, p1, p2, i2) = Machine.import
    #: (i32, i32) -> i32
    def self.flock(i1, i2) = Machine.import

    #: () -> value
    def self.zr_toplevel = Machine.import
    #: () -> value
    def self.zr_prelude = Machine.import
    #: () -> value
    def self.zr_gem_prelude = Machine.import

    #: (ptr, i32, word) -> ptr
    def self.memset(p, i, n) = Machine.import

    #: (word) -> ptr
    def self.malloc(n) = Machine.import
    #: (ptr) -> void
    def self.free(p) = Machine.import
    #: (ptr, ptr, word) -> ptr
    def self.memmove(p1, p2, n) = Machine.import
    #: () -> void
    def self.abort = Machine.import

    #: (i32, ptr) -> i32
    def self.getrusage(i, p) = Machine.import
    #: (i32, ptr, i32) -> i32
    def self.waitpid(i1, p, i2) = Machine.import
    #: (ptr) -> i32
    def self.pipe(p) = Machine.import
    #: () -> i32
    def self.getppid = Machine.import
    #: (i32, i32) -> i32
    def self.kill(i1, i2) = Machine.import
    #: (i32, ptr) -> ptr
    def self.signal(i, p) = Machine.import

    #: (ptr, ptr, ptr, ptr, ptr, ptr) -> i32
    def self.posix_spawnp(p1, p2, p3, p4, p5, p6) = Machine.import
    #: (ptr) -> i32
    def self.posix_spawn_file_actions_init(p) = Machine.import
    #: (ptr, i32, i32) -> i32
    def self.posix_spawn_file_actions_adddup2(p, i1, i2) = Machine.import
    #: (ptr, i32) -> i32
    def self.posix_spawn_file_actions_addclose(p, i) = Machine.import
    #: (ptr, ptr) -> i32
    def self.posix_spawn_file_actions_addchdir_np(p1, p2) = Machine.import
    #: (ptr, i32) -> i32
    def self.posix_spawn_file_actions_addinherit_np(p, i) = Machine.import
    #: (ptr) -> i32
    def self.posix_spawn_file_actions_destroy(p) = Machine.import
    #: (ptr) -> i32
    def self.posix_spawnattr_init(p) = Machine.import
    #: (ptr, i32) -> i32
    def self.posix_spawnattr_setflags(p, i) = Machine.import
    #: (ptr) -> i32
    def self.posix_spawnattr_destroy(p) = Machine.import

    #: (ptr, ptr, ptr) -> i32
    def self.execve(p1, p2, p3) = Machine.import

    #: () -> i32
    def self.getpgrp = Machine.import
    #: (i32) -> i32
    def self.getpgid(i) = Machine.import
    #: (i32, i32) -> i32
    def self.setpgid(i1, i2) = Machine.import
    #: (i32) -> i32
    def self.getsid(i) = Machine.import
    #: () -> i32
    def self.setsid = Machine.import
    #: (i32, ptr) -> i32
    def self.getgroups(i, p) = Machine.import
    #: (i32, i32) -> i32
    def self.getpriority(i1, i2) = Machine.import
    #: (i32, i32, i32) -> i32
    def self.setpriority(i1, i2, i3) = Machine.import

    #: (i32, ptr) -> i32
    def self.getrlimit(i, p) = Machine.import
    #: (i32, ptr) -> i32
    def self.setrlimit(i, p) = Machine.import

    #: (i32, i32) -> i32
    def self.setreuid(i1, i2) = Machine.import
    #: (i32, i32) -> i32
    def self.setregid(i1, i2) = Machine.import
    #: (i32, ptr) -> i32
    def self.setgroups(i, p) = Machine.import
    #: (ptr, i32) -> i32
    def self.initgroups(p, i) = Machine.import

    #: () -> i32
    def self.fork = Machine.import

    #: (i32, i32, i32) -> i32
    def self.socket(i1, i2, i3) = Machine.import
    #: (i32, i32, i32, ptr) -> i32
    def self.socketpair(i1, i2, i3, p) = Machine.import
    #: (i32, ptr, i32) -> i32
    def self.bind(i1, p, i2) = Machine.import
    #: (i32, i32) -> i32
    def self.listen(i1, i2) = Machine.import
    #: (i32, ptr, ptr) -> i32
    def self.accept(i, p1, p2) = Machine.import
    #: (i32, ptr, i32) -> i32
    def self.connect(i1, p, i2) = Machine.import
    #: (i32, ptr, word, i32) -> word
    def self.send(i1, p, n, i2) = Machine.import
    #: (i32, ptr, word, i32, ptr, i32) -> word
    def self.sendto(i1, p1, n, i2, p2, i3) = Machine.import
    #: (i32, ptr, word, i32, ptr, ptr) -> word
    def self.recvfrom(i1, p1, n, i2, p2, p3) = Machine.import
    #: (i32, ptr, i32) -> word
    def self.sendmsg(i1, p, i2) = Machine.import
    #: (i32, ptr, i32) -> word
    def self.recvmsg(i1, p, i2) = Machine.import
    #: (i32, i32) -> i32
    def self.shutdown(i1, i2) = Machine.import
    #: (i32, ptr, ptr) -> i32
    def self.getsockname(i, p1, p2) = Machine.import
    #: (i32, ptr, ptr) -> i32
    def self.getpeername(i, p1, p2) = Machine.import
    #: (i32, i32, i32, ptr, ptr) -> i32
    def self.getsockopt(i1, i2, i3, p1, p2) = Machine.import
    #: (i32, i32, i32, ptr, i32) -> i32
    def self.setsockopt(i1, i2, i3, p, i4) = Machine.import
    #: (ptr, ptr, ptr, ptr) -> i32
    def self.getaddrinfo(p1, p2, p3, p4) = Machine.import
    #: (ptr) -> void
    def self.freeaddrinfo(p) = Machine.import
    #: (i32) -> ptr
    def self.gai_strerror(i) = Machine.import
    #: (ptr, i32, ptr, i32, ptr, i32, i32) -> i32
    def self.getnameinfo(p1, i1, p2, i2, p3, i3, i4) = Machine.import
    #: (ptr, word) -> i32
    def self.gethostname(p, n) = Machine.import
    #: (ptr) -> ptr
    def self.gethostbyname(p) = Machine.import
    #: (ptr, i32, i32) -> ptr
    def self.gethostbyaddr(p, i1, i2) = Machine.import
    #: (i32) -> ptr
    def self.hstrerror(i) = Machine.import
    #: (ptr, ptr) -> ptr
    def self.getservbyname(p1, p2) = Machine.import
    #: (i32, ptr) -> ptr
    def self.getservbyport(i, p) = Machine.import
    #: (ptr) -> i32
    def self.getifaddrs(p) = Machine.import
    #: (ptr) -> void
    def self.freeifaddrs(p) = Machine.import
    #: (ptr) -> i32
    def self.if_nametoindex(p) = Machine.import
    #: (i32, ptr) -> ptr
    def self.if_indextoname(i, p) = Machine.import
    #: (i32, ptr, ptr) -> i32
    def self.inet_pton(i, p1, p2) = Machine.import

    #: (ptr, word, ptr, word) -> ptr
    def self.memmem(p1, n1, p2, n2) = Machine.import

    #: (ptr, i32, i32) -> void
    def self.openlog(p, i1, i2) = Machine.import
    #: (i32, ptr) -> void
    def self.syslog(i, p) = Machine.import
    #: () -> void
    def self.closelog = Machine.import
    #: (i32) -> i32
    def self.setlogmask(i) = Machine.import

    #: (i32, ptr, word) -> word
    def self.write(i, p, n) = Machine.import
    #: (i32) -> void
    def self.exit(i) = Machine.import
    #: (ptr, word, word) -> i32
    def self.posix_memalign(p, n1, n2) = Machine.import
    #: (ptr) -> ptr
    def self.getenv(p) = Machine.import
  end
end
