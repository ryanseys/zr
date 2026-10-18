module Zr::Kern
  # The C functions that the darwin layer calls, from libSystem.
  module Libc
    #: () -> ptr
    def self._NSGetEnviron = Machine.import
    #: () -> i32
    def self.arc4random = Machine.import

    #: (i32) -> i32
    def self.setuid(i) = Machine.import
    #: (i32) -> i32
    def self.setgid(i) = Machine.import
    #: (i32) -> i32
    def self.seteuid(i) = Machine.import
    #: (i32) -> i32
    def self.setegid(i) = Machine.import
    #: (i32) -> i32
    def self.setruid(i) = Machine.import
    #: (i32) -> i32
    def self.setrgid(i) = Machine.import
    #: () -> i32
    def self.issetugid = Machine.import

    #: (f64) -> f64
    def self.__cospi(x) = Machine.import
    #: (f64) -> f64
    def self.__sinpi(x) = Machine.import

    #: () -> ptr
    def self.__error = Machine.import
    # open(2) takes the mode for a new file as a variadic argument, and this
    # platform passes a variadic argument on the stack. `__open` is the
    # fixed-arity call that open's wrapper makes after it reads that
    # argument.
    #: (ptr, i32, i32) -> i32
    def self.__open(p, i1, i2) = Machine.import

    #: (i32, i32, word) -> i32
    def self.__fcntl(i1, i2, n) = Machine.import

    #: (i32, word, ptr) -> i32
    def self.__ioctl(i, n, p) = Machine.import

    #: (i32) -> ptr
    def self._dyld_get_image_header(i) = Machine.import
    #: (i32) -> word
    def self._dyld_get_image_vmaddr_slide(i) = Machine.import
    #: (ptr, ptr) -> i32
    def self.strcmp(p1, p2) = Machine.import
    #: (ptr, word, i32, i32, i32, word) -> ptr
    def self.mmap(p, n1, i1, i2, i3, n2) = Machine.import
    #: (i32) -> void
    def self.pthread_jit_write_protect_np(i) = Machine.import
    #: (ptr, word) -> void
    def self.sys_icache_invalidate(p, n) = Machine.import

    #: (ptr) -> word
    def self.malloc_size(p) = Machine.import

    #: (ptr, ptr, i32) -> i32
    def self.CC_SHA256_Update(p1, p2, i) = Machine.import

    #: (i32, ptr, ptr) -> i32
    def self.sigaction(i, p1, p2) = Machine.import

    #: (ptr, ptr) -> i32
    def self.sigaltstack(p1, p2) = Machine.import

    #: (i32, ptr, ptr) -> i32
    def self.sigprocmask(i, p1, p2) = Machine.import

    #: (i32) -> i32
    def self.raise(i) = Machine.import

    #: (ptr, i32) -> i32
    def self.backtrace(p, i) = Machine.import

    #: (i32, ptr, ptr) -> i32
    def self.getpeereid(i, p1, p2) = Machine.import

    #: () -> ptr
    def self.pthread_self = Machine.import
    #: (ptr) -> ptr
    def self.pthread_get_stackaddr_np(p) = Machine.import
    #: (ptr) -> word
    def self.pthread_get_stacksize_np(p) = Machine.import
    #: (ptr, word, i32) -> i32
    def self.mprotect(p, n, i) = Machine.import

    #: (ptr, ptr, ptr, ptr) -> i32
    def self.pthread_create(p1, p2, p3, p4) = Machine.import
    #: (ptr) -> i32
    def self.pthread_detach(p) = Machine.import
    #: (ptr, ptr) -> i32
    def self.pthread_mutex_init(p1, p2) = Machine.import
    #: (ptr) -> i32
    def self.pthread_mutex_lock(p) = Machine.import
    #: (ptr) -> i32
    def self.pthread_mutex_destroy(p) = Machine.import
    #: (ptr, word, word, ptr, ptr) -> void
    def self.qsort_r(base, nel, width, thunk, compar) = Machine.import
    #: (ptr) -> i32
    def self.pthread_mutex_unlock(p) = Machine.import
    #: (ptr, ptr) -> i32
    def self.pthread_cond_init(p1, p2) = Machine.import
    #: (ptr, ptr) -> i32
    def self.pthread_cond_wait(p1, p2) = Machine.import
    #: (ptr) -> i32
    def self.pthread_cond_broadcast(p) = Machine.import
    #: (ptr) -> i32
    def self.pthread_cond_destroy(p) = Machine.import
    #: (i32, ptr, ptr) -> i32
    def self.pthread_sigmask(i, p1, p2) = Machine.import
    #: () -> i32
    def self.sched_yield = Machine.import
    #: (ptr, i32) -> i32
    def self.pthread_kill(p, i) = Machine.import
    #: (ptr, ptr) -> i32
    def self.pthread_threadid_np(p1, p2) = Machine.import
    #: (ptr, ptr) -> i32
    def self.pthread_key_create(p1, p2) = Machine.import
    #: (word, ptr) -> i32
    def self.pthread_setspecific(k, p) = Machine.import
    #: (word) -> ptr
    def self.pthread_getspecific(k) = Machine.import
    #: (i32, ptr) -> ptr
    def self.setlocale(i, p) = Machine.import
    #: (i32) -> ptr
    def self.nl_langinfo(i) = Machine.import
  end
end
