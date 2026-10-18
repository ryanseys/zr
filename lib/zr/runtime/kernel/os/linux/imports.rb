module Zr::Kern
  # The C functions that the linux layer calls, from musl.
  module Libc
    #: (ptr, word, i32) -> word
    def self.getrandom(p, n, i) = Machine.import

    #: (i32) -> i32
    def self.setuid(i) = Machine.import
    #: (i32) -> i32
    def self.setgid(i) = Machine.import
    #: (i32) -> i32
    def self.seteuid(i) = Machine.import
    #: (i32) -> i32
    def self.setegid(i) = Machine.import
    #: () -> i32
    def self.issetugid = Machine.import

    #: () -> ptr
    def self.__errno_location = Machine.import
    #: (i32, i32, word) -> i32
    def self.fcntl(i1, i2, n) = Machine.import
    #: (i32, word, ptr) -> i32
    def self.ioctl(i, n, p) = Machine.import
    #: (ptr, i32, i32) -> i32
    def self.open(p, i1, i2) = Machine.import
    #: (ptr, word, i32) -> i32
    def self.poll(p, n, i) = Machine.import

    #: (ptr, word, i32, i32, i32, word) -> ptr
    def self.mmap(p, n1, i1, i2, i3, n2) = Machine.import
    #: (ptr, word, i32) -> i32
    def self.madvise(p, n, i) = Machine.import
    #: (ptr, ptr) -> void
    def self.__clear_cache(p1, p2) = Machine.import

    #: (ptr) -> word
    def self.malloc_usable_size(p) = Machine.import

    #: (i32, ptr, ptr) -> i32
    def self.sigaction(i, p1, p2) = Machine.import

    #: (ptr, ptr) -> i32
    def self.sigaltstack(p1, p2) = Machine.import

    #: (i32, ptr, ptr) -> i32
    def self.sigprocmask(i, p1, p2) = Machine.import

    #: (i32) -> i32
    def self.raise(i) = Machine.import

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
    #: (i32, ptr) -> ptr
    def self.fdopen(fd, mode) = Machine.import
    #: (ptr, word, word, ptr, word) -> void
    def self.qsort_r(base, nel, width, compar, arg) = Machine.import
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
    #: (ptr, i32) -> i32
    def self.pthread_kill(p, i) = Machine.import
    #: (ptr, ptr) -> i32
    def self.pthread_key_create(p1, p2) = Machine.import
    #: (word, ptr) -> i32
    def self.pthread_setspecific(k, p) = Machine.import
    #: (word) -> ptr
    def self.pthread_getspecific(k) = Machine.import
    #: () -> ptr
    def self.pthread_self = Machine.import
    #: (i32, ptr) -> ptr
    def self.setlocale(i, p) = Machine.import
    #: (i32) -> ptr
    def self.nl_langinfo(i) = Machine.import
  end
end
