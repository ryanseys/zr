# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API of IO objects (GetOpenFile and the struct rb_io), raw
# descriptors and ruby's descriptor sets, which nio4r, hiredis, kgio and
# eventmachine call (`zr-dev ext rank`), each against ruby's answer.
class CExtIoTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/io.h>
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    #include <errno.h>
    #include <fcntl.h>
    #include <unistd.h>

    static VALUE io_fptr_fields(VALUE self, VALUE io) {
      rb_io_t *fptr;
      GetOpenFile(io, fptr);
      return rb_ary_new_from_args(4, INT2FIX(fptr->fd), INT2FIX(fptr->mode & FMODE_READWRITE),
                                  fptr->self == io ? Qtrue : Qfalse, INT2FIX(rb_io_mode(io) & FMODE_READWRITE));
    }
    static VALUE io_check_readable(VALUE self, VALUE io) {
      rb_io_t *fptr;
      GetOpenFile(io, fptr);
      rb_io_check_readable(fptr);
      return Qtrue;
    }
    static VALUE io_check_writable(VALUE self, VALUE io) {
      rb_io_t *fptr;
      GetOpenFile(io, fptr);
      rb_io_check_writable(fptr);
      return Qtrue;
    }
    static VALUE io_set_nonblock(VALUE self, VALUE io) {
      rb_io_t *fptr;
      GetOpenFile(io, fptr);
      rb_io_set_nonblock(fptr);
      return (fcntl(rb_io_descriptor(io), F_GETFL) & O_NONBLOCK) ? Qtrue : Qfalse;
    }
    static VALUE io_descriptor(VALUE self, VALUE io) { return INT2FIX(rb_io_descriptor(io)); }
    static VALUE io_convert(VALUE self, VALUE io) { return rb_convert_type(io, T_FILE, "IO", "to_io"); }
    static VALUE io_check_io(VALUE self, VALUE io) { return rb_io_check_io(io); }
    static VALUE io_get_io(VALUE self, VALUE io) { return rb_io_get_io(io); }
    static VALUE io_methods(VALUE self, VALUE io) {
      VALUE line = rb_io_gets(io);
      VALUE byte = rb_io_getbyte(io);
      VALUE eof = rb_io_eof(io);
      rb_io_binmode(io);
      VALUE path = rb_io_path(io);
      rb_io_close(io);
      return rb_ary_new_from_args(5, line, byte, eof, path, rb_funcall(io, rb_intern("closed?"), 0));
    }
    static VALUE io_wait(VALUE self, VALUE io, VALUE events, VALUE timeout) { return rb_io_wait(io, events, timeout); }
    static VALUE io_wait_fd(VALUE self, VALUE fd, VALUE events, VALUE usec) {
      struct timeval tv = { 0, NUM2INT(usec) };
      return INT2FIX(rb_wait_for_single_fd(NUM2INT(fd), NUM2INT(events), &tv));
    }
    static VALUE io_wait_readable(VALUE self, VALUE io) {
      int fd = rb_io_descriptor(io);
      char c;
      if (read(fd, &c, 1) == 1) return rb_str_new(&c, 1);
      int again = rb_io_wait_readable(fd);
      if (read(fd, &c, 1) == 1) return rb_assoc_new(INT2FIX(again), rb_str_new(&c, 1));
      return INT2FIX(errno);
    }
    static VALUE io_wait_bad_errno(VALUE self, VALUE io) {
      errno = EBADF;
      return INT2FIX(rb_io_wait_writable(rb_io_descriptor(io)));
    }

    static VALUE io_fd_sets(VALUE self) {
      rb_fdset_t set, copy;
      rb_fd_init(&set);
      rb_fd_init(&copy);
      rb_fd_set(3, &set);
      rb_fd_set(2000, &set);
      VALUE before = rb_ary_new_from_args(4, INT2FIX(rb_fd_isset(3, &set)), INT2FIX(rb_fd_isset(4, &set)),
                                          INT2FIX(rb_fd_isset(2000, &set)), INT2FIX(rb_fd_isset(5000, &set)));
      rb_fd_dup(&copy, &set);
      rb_fd_clr(3, &set);
      VALUE after = rb_ary_new_from_args(3, INT2FIX(rb_fd_isset(3, &set)), INT2FIX(rb_fd_isset(3, &copy)),
                                         INT2FIX(rb_fd_isset(2000, &copy)));
      rb_fd_zero(&copy);
      VALUE zeroed = INT2FIX(rb_fd_isset(2000, &copy));
      fd_set plain;
      FD_ZERO(&plain);
      FD_SET(7, &plain);
      rb_fd_copy(&copy, &plain, 8);
      VALUE copied = rb_ary_new_from_args(2, INT2FIX(rb_fd_isset(7, &copy)), INT2FIX(rb_fd_isset(6, &copy)));
      rb_fd_term(&set);
      rb_fd_term(&copy);
      return rb_ary_new_from_args(4, before, after, zeroed, copied);
    }
    static VALUE io_select_fds(VALUE self, VALUE r, VALUE w, VALUE usec) {
      rb_fdset_t rset, wset;
      rb_fd_init(&rset);
      rb_fd_init(&wset);
      int rfd = rb_io_descriptor(r), wfd = rb_io_descriptor(w);
      rb_fd_set(rfd, &rset);
      rb_fd_set(wfd, &wset);
      struct timeval tv = { 0, NUM2INT(usec) };
      int max = (rfd > wfd ? rfd : wfd) + 1;
      int n = rb_thread_fd_select(max, &rset, &wset, NULL, &tv);
      VALUE out = rb_ary_new_from_args(3, INT2FIX(n), INT2FIX(rb_fd_isset(rfd, &rset)), INT2FIX(rb_fd_isset(wfd, &wset)));
      rb_fd_term(&rset);
      rb_fd_term(&wset);
      return out;
    }
    static VALUE io_cloexec_open(VALUE self, VALUE path) {
      int fd = rb_cloexec_open(StringValueCStr(path), O_RDONLY, 0);
      if (fd < 0) return INT2FIX(-errno);
      rb_update_max_fd(fd);
      int flags = fcntl(fd, F_GETFD);
      close(fd);
      return (flags & FD_CLOEXEC) ? Qtrue : Qfalse;
    }

    void Init_ios(void) {
      VALUE m = rb_define_module("Ios");
      rb_define_module_function(m, "fptr_fields", io_fptr_fields, 1);
      rb_define_module_function(m, "check_readable", io_check_readable, 1);
      rb_define_module_function(m, "check_writable", io_check_writable, 1);
      rb_define_module_function(m, "set_nonblock", io_set_nonblock, 1);
      rb_define_module_function(m, "descriptor", io_descriptor, 1);
      rb_define_module_function(m, "convert", io_convert, 1);
      rb_define_module_function(m, "check_io", io_check_io, 1);
      rb_define_module_function(m, "get_io", io_get_io, 1);
      rb_define_module_function(m, "methods", io_methods, 1);
      rb_define_module_function(m, "wait", io_wait, 3);
      rb_define_module_function(m, "wait_fd", io_wait_fd, 3);
      rb_define_module_function(m, "wait_readable", io_wait_readable, 1);
      rb_define_module_function(m, "wait_bad_errno", io_wait_bad_errno, 1);
      rb_define_module_function(m, "fd_sets", io_fd_sets, 0);
      rb_define_module_function(m, "select_fds", io_select_fds, 3);
      rb_define_module_function(m, "cloexec_open", io_cloexec_open, 1);
    }
  C

  PROGRAM = <<~'RUBY'
    require "ios"

    def show(label)
      p [label, yield]
    rescue => e
      p [label, e.class, e.message]
    end

    class Wrapper
      def initialize(io) = @io = io
      def to_io = @io
    end

    r, w = IO.pipe
    show(:fields) { [Ios.fptr_fields(r)[1..], Ios.fptr_fields(w)[1..], Ios.fptr_fields(r)[0] == r.fileno] }
    show(:fields_gc) { GC.start; Ios.fptr_fields($stdout)[0..2] }
    show(:readable) { [Ios.check_readable(r), Ios.check_writable(w)] }
    show(:not_readable) { Ios.check_readable(w) }
    show(:not_writable) { Ios.check_writable(r) }
    show(:frozen) { Ios.fptr_fields(IO.pipe[0].freeze) rescue [$!.class, $!.message.sub(/fd \d+/, "fd N")] }
    show(:descriptor) { [Ios.descriptor(r) == r.fileno, Ios.descriptor($stderr)] }
    show(:convert) { [Ios.convert(r).equal?(r), Ios.convert(Wrapper.new(w)).equal?(w)] }
    show(:convert_bad) { Ios.convert("x") }
    show(:check_io) { [Ios.check_io(r).equal?(r), Ios.check_io(Wrapper.new(r)).equal?(r), Ios.check_io(1)] }
    show(:get_io_bad) { Ios.get_io(1) }
    show(:wait_none) { Ios.wait(r, IO::READABLE, 0.01) }
    show(:wait_writable) { Ios.wait(w, IO::WRITABLE, 0.01) }
    w.write("ab")
    show(:wait_ready) { Ios.wait(r, IO::READABLE, 0.01) }
    show(:wait_fd) { [Ios.wait_fd(r.fileno, IO::READABLE, 10_000), Ios.wait_fd(w.fileno, IO::READABLE | IO::WRITABLE, 10_000)] }
    show(:select) { Ios.select_fds(r, w, 10_000) }
    r.read(2)
    show(:wait_fd_none) { Ios.wait_fd(r.fileno, IO::READABLE, 10_000) }
    show(:select_none) { Ios.select_fds(r, IO.pipe[0], 10_000) }
    show(:nonblock) { Ios.set_nonblock(r) }
    show(:wait_readable) do
      Thread.new { sleep 0.02; w.write("z") }
      Ios.wait_readable(r)
    end
    show(:wait_bad_errno) { Ios.wait_bad_errno(w) }
    show(:fd_sets) { Ios.fd_sets }
    show(:cloexec_open) { [Ios.cloexec_open(__FILE__), Ios.cloexec_open("/no/such/file")] }
    show(:methods) do
      path = File.join(__dir__, "lines.txt")
      File.write(path, "one\ntwo\n")
      Ios.methods(File.open(path))
    end
    show(:closed) { w.close; Ios.fptr_fields(w) }
    show(:closed_descriptor) { Ios.descriptor(w) }
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("ios", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
