# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API of IO::Buffer (ruby/io/buffer.h): buffers over C's memory,
# locks, the bytes with their flags, a callback with the buffer locked,
# the calls that manage memory, and one transfer each of read, pread,
# write and pwrite, each against ruby's answer.
class CExtIoBufferTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/io/buffer.h>
    #include <stdlib.h>
    #include <string.h>

    static char lent[16] = "hello, world";

    static VALUE b_is(VALUE self, VALUE v) { return rb_io_buffer_p(v) ? Qtrue : Qfalse; }
    static VALUE b_readonly(VALUE self, VALUE v) { return rb_io_buffer_readonly_p(v) ? Qtrue : Qfalse; }
    static VALUE b_sizes(VALUE self) {
      return rb_ary_new_from_args(3, SIZET2NUM(RUBY_IO_BUFFER_PAGE_SIZE), SIZET2NUM(RUBY_IO_BUFFER_MAP_ALIGNMENT),
                                  SIZET2NUM(RUBY_IO_BUFFER_DEFAULT_SIZE));
    }
    static VALUE b_classes(VALUE self) { return rb_ary_new_from_args(3, rb_cIOBuffer, rb_cIOBufferStorage, rb_cIOBufferSlice); }

    /* Buffers over C's memory, over memory that C hands over, and over
       new memory that the flags choose. */
    static VALUE b_external(VALUE self) { return rb_io_buffer_new(lent, 12, RB_IO_BUFFER_EXTERNAL); }
    static VALUE b_lent(VALUE self) { return rb_str_new(lent, 12); }
    static VALUE b_owned(VALUE self) {
      char *bytes = malloc(8);
      memcpy(bytes, "internal", 8);
      return rb_io_buffer_new(bytes, 8, RB_IO_BUFFER_INTERNAL);
    }
    static VALUE b_fresh(VALUE self, VALUE size, VALUE flags) { return rb_io_buffer_new(NULL, NUM2SIZET(size), NUM2INT(flags)); }

    /* A locked wrapper of C's memory for the length of one call. */
    static VALUE b_borrowed(VALUE self) {
      VALUE buffer = rb_io_buffer_new_locked(lent, 5, 0);
      VALUE seen = rb_ary_new_from_args(2, rb_funcall(buffer, rb_intern("locked?"), 0), rb_funcall(buffer, rb_intern("get_string"), 0));
      rb_io_buffer_free_locked(buffer);
      return rb_ary_new_from_args(3, seen, rb_funcall(buffer, rb_intern("null?"), 0), rb_funcall(buffer, rb_intern("locked?"), 0));
    }

    static VALUE b_lock(VALUE self, VALUE buffer) { return rb_io_buffer_lock(buffer); }
    static VALUE b_unlock(VALUE self, VALUE buffer) { return rb_io_buffer_unlock(buffer); }
    static VALUE b_try_unlock(VALUE self, VALUE buffer) { return INT2FIX(rb_io_buffer_try_unlock(buffer)); }
    static VALUE b_free(VALUE self, VALUE buffer) { return rb_io_buffer_free(buffer); }
    static VALUE b_transfer(VALUE self, VALUE buffer) { return rb_io_buffer_transfer(buffer); }
    static VALUE b_resize(VALUE self, VALUE buffer, VALUE size) { rb_io_buffer_resize(buffer, NUM2SIZET(size)); return buffer; }
    static VALUE b_advance(VALUE self, VALUE buffer, VALUE amount) { rb_io_buffer_advance(buffer, NUM2SIZET(amount)); return buffer; }
    static VALUE b_clear(VALUE self, VALUE buffer, VALUE value, VALUE offset, VALUE length) {
      rb_io_buffer_clear(buffer, (uint8_t)NUM2INT(value), NUM2SIZET(offset), NUM2SIZET(length));
      return buffer;
    }

    /* The flags and the bytes that rb_io_buffer_get_bytes gives. */
    static VALUE b_bytes(VALUE self, VALUE buffer) {
      void *base = (void *)1;
      size_t size = 99;
      int flags = rb_io_buffer_get_bytes(buffer, &base, &size);
      if (!flags) return INT2FIX(0);
      return rb_ary_new_from_args(2, INT2FIX(flags), base ? rb_str_new(base, size) : Qnil);
    }
    static VALUE b_reading(VALUE self, VALUE buffer) {
      const void *base;
      size_t size;
      rb_io_buffer_get_bytes_for_reading(buffer, &base, &size);
      return base ? rb_str_new(base, size) : Qnil;
    }

    /* Callbacks under the lock: the bytes, whether the buffer is locked
       then, and one that raises. */
    static VALUE read_cb(const void *base, size_t size, VALUE buffer) {
      return rb_ary_new_from_args(2, rb_str_new(base, size), rb_funcall(buffer, rb_intern("locked?"), 0));
    }
    static VALUE write_cb(void *base, size_t size, VALUE buffer) {
      if (size > 0) memset(base, '*', size);
      return rb_funcall(buffer, rb_intern("locked?"), 0);
    }
    static VALUE raise_cb(const void *base, size_t size, VALUE buffer) {
      rb_raise(rb_eRuntimeError, "callback raised with %d bytes", (int)size);
      return Qnil;
    }
    static VALUE b_locked_read(VALUE self, VALUE buffer) { return rb_io_buffer_locked_for_reading(buffer, read_cb, buffer); }
    static VALUE b_locked_write(VALUE self, VALUE buffer) { return rb_io_buffer_locked_for_writing(buffer, write_cb, buffer); }
    static VALUE b_locked_raise(VALUE self, VALUE buffer) { return rb_io_buffer_locked_for_reading(buffer, raise_cb, buffer); }

    static VALUE b_read(VALUE self, VALUE buffer, VALUE io, VALUE offset, VALUE length) {
      return rb_io_buffer_read(buffer, io, NUM2SIZET(offset), NUM2SIZET(length));
    }
    static VALUE b_pread(VALUE self, VALUE buffer, VALUE io, VALUE from, VALUE offset, VALUE length) {
      return rb_io_buffer_pread(buffer, io, NUM2OFFT(from), NUM2SIZET(offset), NUM2SIZET(length));
    }
    static VALUE b_write(VALUE self, VALUE buffer, VALUE io, VALUE offset, VALUE length) {
      return rb_io_buffer_write(buffer, io, NUM2SIZET(offset), NUM2SIZET(length));
    }
    static VALUE b_pwrite(VALUE self, VALUE buffer, VALUE io, VALUE from, VALUE offset, VALUE length) {
      return rb_io_buffer_pwrite(buffer, io, NUM2OFFT(from), NUM2SIZET(offset), NUM2SIZET(length));
    }
    static VALUE b_map(VALUE self, VALUE io, VALUE size, VALUE flags) {
      return rb_io_buffer_map(io, NUM2SIZET(size), 0, NUM2INT(flags));
    }

    void Init_iobuf(void) {
      VALUE m = rb_define_module("IOBuf");
      rb_define_module_function(m, "is?", b_is, 1);
      rb_define_module_function(m, "readonly?", b_readonly, 1);
      rb_define_module_function(m, "sizes", b_sizes, 0);
      rb_define_module_function(m, "classes", b_classes, 0);
      rb_define_module_function(m, "external", b_external, 0);
      rb_define_module_function(m, "lent", b_lent, 0);
      rb_define_module_function(m, "owned", b_owned, 0);
      rb_define_module_function(m, "fresh", b_fresh, 2);
      rb_define_module_function(m, "borrowed", b_borrowed, 0);
      rb_define_module_function(m, "lock", b_lock, 1);
      rb_define_module_function(m, "unlock", b_unlock, 1);
      rb_define_module_function(m, "try_unlock", b_try_unlock, 1);
      rb_define_module_function(m, "free", b_free, 1);
      rb_define_module_function(m, "transfer", b_transfer, 1);
      rb_define_module_function(m, "resize", b_resize, 2);
      rb_define_module_function(m, "advance", b_advance, 2);
      rb_define_module_function(m, "clear", b_clear, 4);
      rb_define_module_function(m, "bytes", b_bytes, 1);
      rb_define_module_function(m, "reading", b_reading, 1);
      rb_define_module_function(m, "locked_read", b_locked_read, 1);
      rb_define_module_function(m, "locked_write", b_locked_write, 1);
      rb_define_module_function(m, "locked_raise", b_locked_raise, 1);
      rb_define_module_function(m, "read", b_read, 4);
      rb_define_module_function(m, "pread", b_pread, 5);
      rb_define_module_function(m, "write", b_write, 4);
      rb_define_module_function(m, "pwrite", b_pwrite, 5);
      rb_define_module_function(m, "map", b_map, 3);
    }
  C

  PROGRAM = <<~'RUBY'
    require "iobuf"
    require "tmpdir"
    Warning[:experimental] = false

    def show(label)
      p [label, yield]
    rescue StandardError => e
      p [label, e.class, e.message.gsub(/0x\h+/, "0xX")]
    end

    B = IO::Buffer
    show(:classes) { IOBuf.classes == [B, B::Storage, B::Slice] }
    show(:sizes) { IOBuf.sizes == [B::PAGE_SIZE, B::MAP_ALIGNMENT, B::DEFAULT_SIZE] }
    storage = B.new(8)
    show(:is) { [storage, storage.slice(1, 2), "text", 1, nil].map { |v| IOBuf.is?(v) } }
    show(:readonly) { [storage, B.for("frozen".freeze), B.for(+"open"), storage.slice(0, 1)].map { |b| IOBuf.readonly?(b) } }
    show(:readonly_none) { IOBuf.readonly?(:symbol) }

    # C's memory, read and written in place.
    external = IOBuf.external
    show(:external) { [external.class, external.size, external.get_string, external.external?, external.internal?] }
    external.set_string("HELLO")
    show(:external_write) { IOBuf.lent }
    show(:external_bytes) { IOBuf.bytes(external) }
    show(:external_resize) { IOBuf.resize(external, 4) }
    owned = IOBuf.owned
    show(:owned) { [owned.get_string, owned.internal?, owned.external?] }
    show(:owned_resize) { IOBuf.resize(owned, 4).get_string }
    show(:owned_free) { [IOBuf.free(owned).null?, owned.size] }
    show(:fresh_internal) { b = IOBuf.fresh(4, B::INTERNAL); [b.get_string, b.internal?, b.size] }
    show(:fresh_mapped) { b = IOBuf.fresh(4, B::MAPPED); [b.get_string, b.mapped?, b.size] }
    show(:fresh_empty) { b = IOBuf.fresh(0, 0); [b.null?, b.size, b.valid?] }
    show(:fresh_no_kind) { IOBuf.fresh(5, 0) }
    show(:borrowed) { IOBuf.borrowed }

    # Locks: the Storage under the slices holds the count.
    slice = storage.slice(2, 3)
    show(:lock) { [IOBuf.lock(storage).equal?(storage), storage.locked?] }
    show(:lock_slice) { IOBuf.lock(slice); [slice.locked?, storage.locked?] }
    show(:free_locked) { IOBuf.free(storage) }
    show(:transfer_locked) { IOBuf.transfer(storage) }
    show(:unlocks) { [IOBuf.try_unlock(slice), IOBuf.try_unlock(storage), IOBuf.try_unlock(storage), storage.locked?] }
    show(:unlock_unlocked) { IOBuf.unlock(storage) }
    show(:lock_nil) { IOBuf.lock(nil) }
    show(:lock_string) { IOBuf.lock("text") }

    # The calls that manage memory refuse a Slice.
    show(:free_slice) { IOBuf.free(slice) }
    show(:transfer_slice) { IOBuf.transfer(slice) }
    frozen = B.new(4).freeze
    show(:free_frozen) { IOBuf.free(frozen).null? }

    # The bytes and the flags.
    text = +"bytes!"
    show(:bytes_string) { IOBuf.bytes(B.for(text)) }
    show(:bytes_frozen) { IOBuf.bytes(B.for("still".freeze)) }
    show(:bytes_new) { IOBuf.bytes(B.new(3)) }
    show(:bytes_slice) { IOBuf.bytes(B.for(text).slice(1, 3)) }
    show(:bytes_null) { IOBuf.bytes(B.new(0)) }
    gone = B.new(8)
    gone_slice = gone.slice(4, 4)
    gone.resize(2)
    show(:bytes_invalid) { IOBuf.bytes(gone_slice) }
    show(:reading_invalid) { IOBuf.reading(gone_slice) }
    show(:bytes_not_buffer) { IOBuf.bytes(42) }

    # The callback runs with the buffer locked, also when it raises.
    reader = B.for(+"under lock")
    show(:locked_read) { [IOBuf.locked_read(reader), reader.locked?] }
    show(:locked_raise) { IOBuf.locked_raise(reader) }
    show(:after_raise) { reader.locked? }
    writer = B.new(4)
    show(:locked_write) { [IOBuf.locked_write(writer), writer.get_string, writer.locked?] }
    show(:locked_write_readonly) { IOBuf.locked_write(B.for("ro".freeze)) }
    show(:locked_write_frozen) { IOBuf.locked_write(B.new(2).freeze) }
    show(:locked_read_invalid) { IOBuf.locked_read(gone_slice) }
    show(:locked_after_invalid) { gone.locked? }

    # Transfer, resize, advance and clear.
    source = B.for(+"abcdef").dup
    moved = IOBuf.transfer(source)
    show(:transfer) { [moved.get_string, source.null?, moved.class] }
    show(:resize_grow) { IOBuf.resize(moved, 8).get_string }
    show(:resize_slice) { s = moved.slice(0, 4); IOBuf.resize(s, 2); [s.size, s.get_string] }
    show(:advance_owning) { IOBuf.advance(moved, 1) }
    view = moved.slice(0, 6)
    show(:advance_slice) { IOBuf.advance(view, 2); [view.size, view.get_string] }
    show(:advance_past) { IOBuf.advance(view, 10) }
    show(:clear) { IOBuf.clear(moved, 0x2d, 1, 3).get_string }
    show(:clear_wide) { IOBuf.clear(moved, 0x2d, 6, 9) }
    show(:clear_readonly) { IOBuf.clear(B.for("ro".freeze), 0, 0, 1) }

    # One transfer each through a pipe and a file.
    r, w = IO.pipe
    w.write("piped bytes")
    w.close
    into = B.new(16)
    show(:read) { [IOBuf.read(into, r, 2, 5), into.get_string(0, 8)] }
    show(:read_zero) { IOBuf.read(into, r, 0, 0) }
    show(:read_past) { IOBuf.read(into, r, 10, 10) }
    r.close
    Dir.mktmpdir do |dir|
      path = File.join(dir, "data")
      File.write(path, "0123456789")
      File.open(path, "r+") do |file|
        show(:pread) { [IOBuf.pread(into, file, 4, 0, 3), into.get_string(0, 3)] }
        show(:pwrite) { [IOBuf.pwrite(B.for("XY"), file, 8, 0, 2), File.read(path)] }
        show(:write) { file.seek(0); [IOBuf.write(B.for("ab"), file, 0, 2), file.flush && File.read(path)] }
        show(:map) { IOBuf.map(file, 4, B::READONLY).then { |m| [m.get_string, m.readonly?, m.mapped?] } }
        show(:map_private) { IOBuf.map(file, 4, B::PRIVATE).then { |m| m.set_string("zz"); [m.get_string, File.read(path)] } }
      end
      show(:read_closed) { IOBuf.read(B.new(2), File.open(path).tap(&:close), 0, 1) }
    end
    GC.start
    show(:after_gc) { [IOBuf.lent, external.get_string(0, 5)] }
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("iobuf", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
