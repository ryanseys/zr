module Zr::Kern
  # T_FILE: the struct through which C reaches an IO. zr's IO is a plain
  # object that keeps its fields as ivars, so CRuby's inline GetOpenFile,
  # `RFILE(rb_io_taint_check(io))->fptr`, reads a companion cell of the
  # IO instead: rb_io_taint_check gives it. The cell has CRuby's RFile
  # layout, and its `fptr` points at a struct rb_io in CRuby 4.0's layout,
  # which the C API fills from the IO each time C checks the stream
  # (rb_io_check_closed). The IO keeps its companion in a hidden ivar, so
  # the two live and die together.
  T_FILE = 11

  class RFile < Layout
    attr_reader :basic #: RBasic
    attr_accessor :fptr #: ptr
  end

  # The size of struct rb_io, and the offsets of the fields that zr fills:
  # `self` (the IO), `fd` and `mode` (two ints), and `pathv`.
  RB_IO_BYTES = 208
  RB_IO_SELF = 0
  RB_IO_FD = 16
  RB_IO_MODE = 20
  RB_IO_PATHV = 32

  # A new companion of the IO `io`, whose struct holds the IO and nil for
  # its path, with every other field zero.
  #: (value) -> value
  def zr_rfile_new(io)
    fptr = zr_xmalloc(RB_IO_BYTES)
    Libc.memset(fptr, Machine.i32(0), RB_IO_BYTES)
    Machine.store64(fptr, RB_IO_SELF, Machine.word(io))
    Machine.store32(fptr, RB_IO_FD, Machine.i32(0 - 1))
    Machine.store64(fptr, RB_IO_PATHV, QNIL)
    f = zr_alloc(T_FILE, zr_class_of(io), RFile.size)
    RBasic[f].flags = RBasic[f].flags | FL_CONCEALED
    RFile[f].fptr = fptr
    f
  end

  # The struct's Values: the IO, and the path that C may have stored.
  #: (value) -> void
  def zr_mark_rfile(f)
    fptr = RFile[f].fptr
    zr_mark(Machine.value(Machine.load64(fptr, RB_IO_SELF)))
    zr_mark(Machine.value(Machine.load64(fptr, RB_IO_PATHV)))
  end

  #: (value) -> void
  def zr_release_rfile(f)
    zr_xfree(RFile[f].fptr)
  end
end
