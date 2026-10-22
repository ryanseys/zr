module Zr::Kern
  # The functions that the wasi layer calls: the WASI calls of the
  # host (`from:` names the wasm module), and the C library's.
  module Libc
    #: (i32, i32) -> i32
    def self.args_sizes_get(i1, i2) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32) -> i32
    def self.args_get(i1, i2) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32) -> i32
    def self.environ_sizes_get(i1, i2) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32) -> i32
    def self.environ_get(i1, i2) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32) -> i32
    def self.clock_res_get(i1, i2) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, word, i32) -> i32
    def self.clock_time_get(i1, n, i2) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32) -> i32
    def self.fd_close(i) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32) -> i32
    def self.fd_fdstat_get(i1, i2) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32) -> i32
    def self.fd_fdstat_set_flags(i1, i2) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32) -> i32
    def self.fd_filestat_get(i1, i2) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, word) -> i32
    def self.fd_filestat_set_size(i, n) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, word, i32) -> i32
    def self.fd_pread(i1, i2, i3, n, i4) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32) -> i32
    def self.fd_prestat_get(i1, i2) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32) -> i32
    def self.fd_prestat_dir_name(i1, i2, i3) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, word, i32) -> i32
    def self.fd_pwrite(i1, i2, i3, n, i4) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, i32) -> i32
    def self.fd_read(i1, i2, i3, i4) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, word, i32) -> i32
    def self.fd_readdir(i1, i2, i3, n, i4) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32) -> i32
    def self.fd_renumber(i1, i2) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, word, i32, i32) -> i32
    def self.fd_seek(i1, n, i2, i3) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32) -> i32
    def self.fd_sync(i) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, i32) -> i32
    def self.fd_write(i1, i2, i3, i4) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32) -> i32
    def self.path_create_directory(i1, i2, i3) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, i32, i32) -> i32
    def self.path_filestat_get(i1, i2, i3, i4, i5) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, i32, i32, i32, i32) -> i32
    def self.path_link(i1, i2, i3, i4, i5, i6, i7) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, i32, word, word, i32) -> i32
    def self.path_filestat_set_times(i1, i2, i3, i4, n1, n2, i5) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, i32, i32, word, word, i32, i32) -> i32
    def self.path_open(i1, i2, i3, i4, i5, n1, n2, i6, i7) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, i32, i32, i32) -> i32
    def self.path_readlink(i1, i2, i3, i4, i5, i6) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32) -> i32
    def self.path_remove_directory(i1, i2, i3) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, i32, i32, i32) -> i32
    def self.path_rename(i1, i2, i3, i4, i5, i6) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, i32, i32) -> i32
    def self.path_symlink(i1, i2, i3, i4, i5) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32) -> i32
    def self.path_unlink_file(i1, i2, i3) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32, i32, i32) -> i32
    def self.poll_oneoff(i1, i2, i3, i4) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32) -> void
    def self.proc_exit(i) = Machine.import(from: "wasi_snapshot_preview1")
    #: (i32, i32) -> i32
    def self.random_get(i1, i2) = Machine.import(from: "wasi_snapshot_preview1")
    # The heap's bump, which the module defines (backend/wasm/shims.rb).
    #: (word) -> word
    def self.zr_wasm_sbrk(n) = Machine.import
  end
end
