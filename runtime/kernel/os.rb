# The OS layer: every call the kernel makes that an operating system
# answers in its own way. Each OS implements all of them under
# runtime/kernel/os/<os>/, beside whatever helpers and constants it needs, and
# the rest of the kernel calls only these. `test/unit/os_api_test.rb`
# holds each OS to this list, name and signature.
#
# The constants each OS defines as well:
#   EINTR EBADF EPROTOTYPE EAI_SYSTEM NSIG CLOCK_MONOTONIC
#   O_NONBLOCK O_NONBLOCK_OFF O_CLOEXEC PTY_OPEN_FLAGS
#   TIOCGWINSZ TIOCSWINSZ TIOCSCTTY TERMIOS_LEN STAT_LEN MSGHDR_LEN MSGHDR_FLAGS
#   SPAWN_ACTIONS_LEN SPAWN_ATTR_LEN SC_NPROCESSORS_ONLN UTSNAME_LEN
#   UTSNAME_FIELD RTLD_DEFAULT
#
# The core library's OS layer, under runtime/core/os/<os>/, holds the numbers
# ruby gives each OS's constants: errno.rb, io_constants.rb,
# process_constants.rb, file_constants.rb and clock_constants.rb, each
# run just before the portable file that uses it (`Zr::CORE_NAMES`).
#
# errno and descriptors
#   zr_os_errno          [] => Word
#   zr_os_set_errno      [Word] => Void
#   zr_os_fcntl          [I32, I32, Word] => I32
#   zr_os_ioctl          [I32, Word, Ptr] => I32
#   zr_os_open           [Ptr, I32, I32] => I32
#   zr_os_realpath       [Ptr] => Ptr
#   zr_os_dirent_name    [Ptr] => Ptr
#   zr_os_stat_rows      [Ptr] => Value
#   zr_os_stat_size      [Ptr] => Word
#   zr_os_stat_mode      [Ptr] => Word
#   zr_os_wait_fd        [Value, Value, Value] => Value
#   zr_os_wait_fds       [Value, Value, Value] => Value
#
# the process
#   zr_os_main           [I32, Ptr] => I32
#   zr_os_argv           [I32, Ptr] => Ptr
#   zr_os_ruby_platform  [] => Value
#   zr_os_environ        [] => Ptr
#   zr_os_random         [] => Word
#   zr_os_passwd_row     [Ptr] => Value
#   zr_os_passwd_dir     [Ptr] => Ptr
#   zr_os_spawn          [Value, Value, Value, Value, Value] => Value
#   zr_os_setid          [Value, Value] => Value
#   zr_os_issetugid      [] => Value
#   zr_os_sigaction      [I32, Word, Ptr] => I32
#   zr_os_poll_start     [] => Void
#   zr_os_malloc_size    [Ptr] => Word
#   zr_os_machine_bytes  [] => Word
#
# stacks and loaded code
#   zr_os_stack_low      [] => Word
#   zr_os_stack_high     [] => Word
#   zr_os_stack_map      [Word] => Ptr
#   zr_os_jit_reserve    [Value] => Value
#   zr_os_jit_release    [Value, Value] => Value
#   zr_os_jit_map        [Value, Value, Value] => Value
#   zr_os_jit_write      [Value, Value] => Value
#   zr_os_symbol         [Value] => Value
#   zr_os_libffi_path    [] => Ptr
#
# the C library
#   zr_os_sort           [Ptr, Word] => Void
#   zr_os_sha256_blocks  [Ptr, Ptr, Word] => Bool
#
# floats
#   zr_os_cospi          [F64] => F64
#   zr_os_sinpi          [F64] => F64
#
# sockets
#   zr_os_sockaddr_len   [Ptr] => Word
#   zr_os_addrinfo_row   [Ptr] => Value
#   zr_os_addrinfo_next  [Ptr] => Ptr
#   zr_os_h_errno        [] => Word
#   zr_os_peereid        [Value] => Value
#
# The architecture layer, under runtime/kernel/arch/<arch>/, answers the
# same way for the machine: the `zr_switch` raw function, CONTEXT_BYTES,
# and
#   zr_arch_context_start [Ptr, Word, Word] => Void
