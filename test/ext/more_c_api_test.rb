# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API functions that the C extensions of the most downloaded gems
# call next (`zr-dev ext rank`): writes to an IO, errno and system errors,
# Strings and their encodings, conversions, keywords, temporary buffers,
# and what runs at the program's end. Each gives ruby's answer.
class CExtMoreCApiTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/encoding.h>
    #include <ruby/io.h>
    #include <ruby/vm.h>
    #include <errno.h>
    #include <stdarg.h>
    #include <string.h>
    #include <unistd.h>

    static VALUE io_calls(VALUE self, VALUE io) {
      VALUE args[2] = { rb_str_new_cstr("a"), INT2FIX(1) };
      rb_io_write(io, rb_str_new_cstr("write\n"));
      rb_io_addstr(rb_io_addstr(io, rb_str_new_cstr("add")), rb_str_new_cstr("str\n"));
      rb_io_print(2, args, io);
      rb_io_puts(2, args, io);
      VALUE fmt[3] = { rb_str_new_cstr("%s-%03d\n"), rb_str_new_cstr("x"), INT2FIX(7) };
      rb_io_printf(3, fmt, io);
      return Qnil;
    }
    static VALUE puts_into(int argc, VALUE *argv, VALUE self) { return rb_io_puts(argc - 1, argv + 1, argv[0]); }
    static VALUE print_into(int argc, VALUE *argv, VALUE self) { return rb_io_puts(0, NULL, argv[0]); }
    static VALUE eof(VALUE self) { rb_eof_error(); return Qnil; }
    static VALUE sys_fail(VALUE self, VALUE n) { errno = NUM2INT(n); rb_sys_fail("from C"); return Qnil; }
    static VALUE sys_fail_null(VALUE self, VALUE n) { errno = NUM2INT(n); rb_sys_fail(NULL); return Qnil; }
    static VALUE syserr_new(VALUE self, VALUE n, VALUE msg) { return rb_syserr_new_str(NUM2INT(n), msg); }
    static VALUE syserr_fail(VALUE self, VALUE n, VALUE msg) { rb_syserr_fail_str(NUM2INT(n), msg); return Qnil; }
    static VALUE errno_roundtrip(VALUE self) { errno = 0; *rb_errno_ptr() = EAGAIN; return INT2FIX(errno); }
    static VALUE get_path(VALUE self, VALUE obj) { return rb_get_path(obj); }

    static VALUE new_frozen(VALUE self, VALUE s) {
      VALUE f = rb_str_new_frozen(s);
      return rb_ary_new_from_args(3, f, OBJ_FROZEN(f) ? Qtrue : Qfalse, f == s ? Qtrue : Qfalse);
    }
    static VALUE freeze(VALUE self, VALUE s) { return rb_str_freeze(s); }
    static VALUE append(VALUE self, VALUE a, VALUE b) { rb_str_append(a, b); return rb_str_buf_append(a, b); }
    static VALUE plus(VALUE self, VALUE a, VALUE b) { return rb_str_plus(a, b); }
    static VALUE cmp(VALUE self, VALUE a, VALUE b) { return INT2FIX(rb_str_cmp(a, b)); }
    static VALUE export_to(VALUE self, VALUE s, VALUE name) { return rb_str_export_to_enc(s, rb_enc_find(StringValueCStr(name))); }
    static VALUE coderange(VALUE self, VALUE s) {
      int cr = rb_enc_str_coderange(s);
      return rb_str_new_cstr(cr == ENC_CODERANGE_7BIT ? "7bit" : cr == ENC_CODERANGE_VALID ? "valid" : cr == ENC_CODERANGE_BROKEN ? "broken" : "unknown");
    }
    static VALUE strlen_in(VALUE self, VALUE s) {
      return LONG2NUM(rb_enc_strlen(RSTRING_PTR(s), RSTRING_END(s), rb_enc_get(s)));
    }
    static VALUE codepoint(VALUE self, VALUE s) {
      int len = 0;
      unsigned int c = rb_enc_codepoint_len(RSTRING_PTR(s), RSTRING_END(s), &len, rb_enc_get(s));
      return rb_ary_new_from_args(2, UINT2NUM(c), INT2FIX(len));
    }
    static VALUE fix2str(VALUE self, VALUE n, VALUE base) { return rb_fix2str(n, NUM2INT(base)); }
    static VALUE cstr2inum(VALUE self, VALUE s, VALUE base) { return rb_cstr2inum(StringValueCStr(s), NUM2INT(base)); }
    static VALUE sym_to_s(VALUE self, VALUE sym) { return rb_sym_to_s(sym); }

    static VALUE unshift_pop(VALUE self, VALUE ary) {
      rb_ary_unshift(ary, INT2FIX(0));
      VALUE last = rb_ary_pop(ary);
      return rb_ary_new_from_args(2, ary, last);
    }
    static VALUE pop_empty(VALUE self) { return rb_ary_pop(rb_ary_new()); }
    static VALUE enc_names(VALUE self) {
      rb_encoding *utf8 = rb_enc_find("UTF-8");
      return rb_ary_new_from_args(4, rb_str_new_cstr(rb_enc_name(utf8)), rb_str_new_cstr(rb_enc_name(rb_enc_find("no-such-encoding"))),
                                  INT2FIX(rb_enc_dummy_p(rb_enc_find("UTF-7"))), INT2FIX(rb_enc_dummy_p(utf8)));
    }
    static VALUE to_str(VALUE self, VALUE v) { return rb_convert_type(v, T_STRING, "String", "to_str"); }
    static VALUE to_a(VALUE self, VALUE v) { return rb_convert_type(v, T_ARRAY, "Array", "to_a"); }
    static VALUE check_str(VALUE self, VALUE v) { return rb_check_convert_type(v, T_STRING, "String", "to_str"); }
    static VALUE check_ary(VALUE self, VALUE v) { return rb_check_array_type(v); }
    static VALUE attr_get(VALUE self, VALUE obj) { return rb_attr_get(obj, rb_intern("@name")); }
    static VALUE is_proc(VALUE self, VALUE obj) { return rb_obj_is_proc(obj); }
    static VALUE new_kw(VALUE self, VALUE klass, VALUE a, VALUE kw) {
      VALUE args[2] = { a, kw };
      return rb_class_new_instance_kw(2, args, klass, RB_PASS_KEYWORDS);
    }
    static VALUE call_kw(VALUE self, VALUE recv, VALUE kw) { return rb_funcallv_kw(recv, rb_intern("take"), 1, &kw, RB_PASS_KEYWORDS); }
    static VALUE call_hash(VALUE self, VALUE recv, VALUE kw) { return rb_funcallv_kw(recv, rb_intern("take"), 1, &kw, RB_NO_KEYWORDS); }
    static VALUE undef(VALUE self, VALUE klass) { rb_undef_method(klass, "gone"); return Qnil; }
    static VALUE require_set(VALUE self) { return rb_require("set"); }

    static int vformat(char *out, size_t n, const char *fmt, ...) {
      va_list ap;
      va_start(ap, fmt);
      int r = ruby_vsnprintf(out, n, fmt, ap);
      va_end(ap);
      return r;
    }
    static VALUE snprintf_calls(VALUE self) {
      char small[6], big[64], v[8];
      int a = ruby_snprintf(small, sizeof small, "%s=%d", "answer", 42);
      int b = ruby_snprintf(big, sizeof big, "%s and %.2f|%-4d|%x", "val", 1.5, 7, 255);
      int c = vformat(v, sizeof v, "%05ld", 42L);
      int d = ruby_snprintf(NULL, 0, "%d", 12345);
      return rb_ary_new_from_args(7, rb_str_new_cstr(small), INT2FIX(a), rb_str_new_cstr(big), INT2FIX(b),
                                  rb_str_new_cstr(v), INT2FIX(c), INT2FIX(d));
    }
    static VALUE tmp_buffer(VALUE self, VALUE n) {
      VALUE store;
      long count = NUM2LONG(n);
      long *words = ALLOCV_N(long, store, count);
      long sum = 0;
      for (long i = 0; i < count; i++) words[i] = i;
      rb_gc_start();
      for (long i = 0; i < count; i++) sum += words[i];
      ALLOCV_END(store);
      return LONG2NUM(sum);
    }
    static VALUE hash_bytes(VALUE self, VALUE a, VALUE b) {
      st_index_t ha = rb_st_hash(RSTRING_PTR(a), RSTRING_LEN(a), 7), hb = rb_st_hash(RSTRING_PTR(b), RSTRING_LEN(b), 7);
      st_index_t again = rb_st_hash(RSTRING_PTR(a), RSTRING_LEN(a), 7), seeded = rb_st_hash(RSTRING_PTR(a), RSTRING_LEN(a), 8);
      return rb_ary_new_from_args(3, ha == again ? Qtrue : Qfalse, ha == hb ? Qtrue : Qfalse, ha == seeded ? Qtrue : Qfalse);
    }

    static void at_end(VALUE data) { rb_funcallv(data, rb_intern("call"), 0, NULL); }
    static void at_vm_exit(ruby_vm_t *vm) { static const char text[] = "vm at exit\n"; write(1, text, sizeof text - 1); }
    static VALUE ends(VALUE self, VALUE text) { rb_set_end_proc(at_end, text); return Qnil; }

    void Init_more(void) {
      rb_ext_ractor_safe(true);
      VALUE m = rb_define_module("More");
      rb_define_module_function(m, "io_calls", io_calls, 1);
      rb_define_module_function(m, "puts_into", puts_into, -1);
      rb_define_module_function(m, "print_into", print_into, -1);
      rb_define_module_function(m, "eof", eof, 0);
      rb_define_module_function(m, "sys_fail", sys_fail, 1);
      rb_define_module_function(m, "sys_fail_null", sys_fail_null, 1);
      rb_define_module_function(m, "syserr_new", syserr_new, 2);
      rb_define_module_function(m, "syserr_fail", syserr_fail, 2);
      rb_define_module_function(m, "errno_roundtrip", errno_roundtrip, 0);
      rb_define_module_function(m, "get_path", get_path, 1);
      rb_define_module_function(m, "new_frozen", new_frozen, 1);
      rb_define_module_function(m, "freeze", freeze, 1);
      rb_define_module_function(m, "append", append, 2);
      rb_define_module_function(m, "plus", plus, 2);
      rb_define_module_function(m, "cmp", cmp, 2);
      rb_define_module_function(m, "export_to", export_to, 2);
      rb_define_module_function(m, "coderange", coderange, 1);
      rb_define_module_function(m, "strlen_in", strlen_in, 1);
      rb_define_module_function(m, "codepoint", codepoint, 1);
      rb_define_module_function(m, "fix2str", fix2str, 2);
      rb_define_module_function(m, "cstr2inum", cstr2inum, 2);
      rb_define_module_function(m, "sym_to_s", sym_to_s, 1);
      rb_define_module_function(m, "unshift_pop", unshift_pop, 1);
      rb_define_module_function(m, "pop_empty", pop_empty, 0);
      rb_define_module_function(m, "enc_names", enc_names, 0);
      rb_define_module_function(m, "to_str", to_str, 1);
      rb_define_module_function(m, "to_a", to_a, 1);
      rb_define_module_function(m, "check_str", check_str, 1);
      rb_define_module_function(m, "check_ary", check_ary, 1);
      rb_define_module_function(m, "attr_get", attr_get, 1);
      rb_define_module_function(m, "is_proc", is_proc, 1);
      rb_define_module_function(m, "new_kw", new_kw, 3);
      rb_define_module_function(m, "call_kw", call_kw, 2);
      rb_define_module_function(m, "call_hash", call_hash, 2);
      rb_define_module_function(m, "undef", undef, 1);
      rb_define_module_function(m, "require_set", require_set, 0);
      rb_define_module_function(m, "snprintf_calls", snprintf_calls, 0);
      rb_define_module_function(m, "tmp_buffer", tmp_buffer, 1);
      rb_define_module_function(m, "hash_bytes", hash_bytes, 2);
      rb_define_module_function(m, "ends", ends, 1);
      ruby_vm_at_exit(at_vm_exit);
    }
  C

  PROGRAM = <<~'RUBY'
    require "more"

    def show(label)
      p [label, yield]
    rescue => e
      p [label, e.class, e.message]
    end

    More.io_calls($stdout)
    # An object with only `write` takes what rb_io_* write, as an
    # extension that defines its own `<<` and `puts` as them needs.
    sink = Class.new do
      attr_reader :parts
      def initialize = @parts = []
      def write(*s) = (@parts.concat(s.map(&:to_s)); s.sum(&:size))
    end
    out = sink.new
    More.io_calls(out)
    p out.parts
    nested = [1, [2, ["three"]]]
    nested << nested
    $, = nil
    More.puts_into(out2 = sink.new, nested, "line\n", nil, :sym)
    p out2.parts
    More.print_into(out3 = sink.new)
    p out3.parts
    show(:eof) { More.eof }
    show(:sys_fail) { More.sys_fail(2) }
    show(:sys_fail_null) { More.sys_fail_null(13) }
    show(:syserr_new) { e = More.syserr_new(2, "where"); [e.class, e.message, e.errno] }
    show(:syserr_new_nil) { More.syserr_new(9999, nil).message }
    show(:syserr_fail) { More.syserr_fail(17, "here") }
    show(:errno) { More.errno_roundtrip }
    to_path = Object.new.tap { |o| def o.to_path = "/via/to_path" }
    show(:path) { [More.get_path("/a/b"), More.get_path(to_path)] }
    show(:path_bad) { More.get_path(42) }

    show(:frozen_copy) { s = +"abc"; f, frozen, same = More.new_frozen(s); [f, frozen, same, s.frozen?] }
    show(:frozen_same) { More.new_frozen("lit".freeze)[1..] }
    show(:freeze) { More.freeze(+"x").frozen? }
    show(:append) { More.append(+"ab", "cd") }
    show(:append_enc) { More.append("é".b, "é") }
    show(:plus) { More.plus("ab", "cd") }
    show(:cmp) { [More.cmp("a", "b"), More.cmp("b", "b"), More.cmp("c", "b"), More.cmp("ab", "a")] }
    show(:export) { r = More.export_to("café", "ISO-8859-1"); [r.encoding, r.bytes] }
    show(:coderange) { ["abc", "é", "\xff", "a".encode("UTF-16LE"), "".b].map { |s| More.coderange(s) } }
    show(:strlen) { ["héllo", "\xffa", "abc".encode("UTF-16LE")].map { |s| More.strlen_in(s) } }
    show(:codepoint) { ["éx", "abc", "\u{1F600}"].map { |s| More.codepoint(s) } }
    show(:codepoint_bad) { More.codepoint("\xff") }
    show(:codepoint_empty) { More.codepoint("") }
    show(:fix2str) { [More.fix2str(255, 16), More.fix2str(-5, 2), More.fix2str(35, 36)] }
    show(:cstr2inum) { [More.cstr2inum("ff", 16), More.cstr2inum("12abc", 10), More.cstr2inum("017", 0), More.cstr2inum(" 1_000 ", 0), More.cstr2inum("-0x10", 16)] }
    show(:cstr2inum_bad) { [More.cstr2inum("12abc", 0)] }
    show(:cstr2inum_prefix) { More.cstr2inum("0x1A", 0) }
    show(:sym_to_s) { s = More.sym_to_s(:hello); [s, s.frozen?] }

    show(:unshift_pop) { More.unshift_pop([1, 2]) }
    show(:pop_empty) { More.pop_empty }
    show(:unshift_frozen) { More.unshift_pop([1].freeze) }
    show(:encodings) { More.enc_names }
    Stringish = Struct.new(:text) { def to_str = text }
    Arrayish = Struct.new(:items) { def to_ary = items }
    Wrong = Class.new { def to_str = 1; def to_ary = :no }
    show(:to_str) { [More.to_str("s"), More.to_str(Stringish.new("via"))] }
    show(:to_str_int) { More.to_str(42) }
    show(:to_str_nil) { More.to_str(nil) }
    show(:to_str_false) { More.to_str(false) }
    show(:to_str_wrong) { More.to_str(Wrong.new) }
    show(:to_a) { [More.to_a(1..3), More.to_a({ a: 1 })] }
    show(:to_a_none) { More.to_a(Object.new) }
    show(:check_str) { [More.check_str("s"), More.check_str(Stringish.new("v")), More.check_str(42), More.check_str(Stringish.new(nil))] }
    show(:check_str_wrong) { More.check_str(Wrong.new) }
    show(:check_ary) { [More.check_ary([1]), More.check_ary(Arrayish.new([2])), More.check_ary("x"), More.check_ary(Arrayish.new(nil))] }
    show(:check_ary_wrong) { More.check_ary(Wrong.new) }
    holder = Object.new.tap { |o| o.instance_variable_set(:@name, "held") }
    show(:attr_get) { [More.attr_get(holder), More.attr_get(Object.new)] }
    show(:is_proc) { [More.is_proc(proc {}), More.is_proc(-> {}), More.is_proc(:sym), More.is_proc(nil)] }
    Point = Struct.new(:x, :y, keyword_init: false) do
      def initialize(x, y: 0) = super(x, y)
    end
    show(:new_kw) { More.new_kw(Point, 1, { y: 2 }).to_a }
    taker = Object.new.tap { |o| def o.take(*args, **kw) = [args, kw] }
    show(:call_kw) { More.call_kw(taker, { a: 1 }) }
    show(:call_hash) { More.call_hash(taker, { a: 1 }) }
    Gone = Class.new { def gone = 1 }
    More.undef(Gone)
    show(:undef) { Gone.new.gone }
    Quiet = Class.new { def self.method_undefined(name) = puts("undefined #{name}") }
    show(:undef_missing) { More.undef(Quiet); [Quiet.instance_methods(false), Quiet.new.respond_to?(:gone)] }
    Frozen = Class.new.freeze
    show(:undef_frozen) { More.undef(Frozen) }
    show(:require) { More.require_set }
    show(:snprintf) { More.snprintf_calls }
    show(:tmp_buffer) { [More.tmp_buffer(10), More.tmp_buffer(100_000)] }
    show(:hash_bytes) { More.hash_bytes("abc", "abd") }

    at_exit { puts "at_exit 1" }
    More.ends(proc { puts "end proc" })
    at_exit { puts "at_exit 2" }
  RUBY

  FATAL = <<~'C'
    #include <ruby.h>
    static VALUE die(VALUE self, VALUE n) { rb_fatal("stopped at %d", NUM2INT(n)); return Qnil; }
    void Init_fatal_ext(void) { rb_define_module_function(rb_define_module("FatalExt"), "die", die, 1); }
  C

  DIES = <<~'RUBY'
    require "fatal_ext"
    at_exit { puts "at_exit runs" }
    begin
      FatalExt.die(3)
    rescue Exception => e
      puts "rescued #{e.class}"
    end
    puts "not reached"
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  def test_each_function_gives_rubys_answer
    assert_same_as_ruby(Zr::Test::CExt.build("more", SOURCE), PROGRAM)
  end

  def test_the_answers_hold_under_the_collectors_stress
    ext = Zr::Test::CExt.build("more", SOURCE)
    ruby, (zr,) = Zr::Test::CExt.outputs_under(ext, PROGRAM, [{ "ZR_GC_STRESS" => "1" }])
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
  end

  # rb_fatal's `fatal` passes every rescue and ends the program, after
  # the at_exit handlers, with its message on stderr.
  def test_fatal_ends_the_program
    ruby, zr = Zr::Test::CExt.outputs(Zr::Test::CExt.build("fatal_ext", FATAL), DIES)
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
    assert_match(/stopped at 3 \(fatal\)/, zr.stderr)
  end

  def assert_same_as_ruby(ext, program)
    ruby, zr = Zr::Test::CExt.outputs(ext, program)
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
  end
end
