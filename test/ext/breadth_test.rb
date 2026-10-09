# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API that the top 9000 gems' extensions wait on next (`zr-dev ext
# rank --top 9000`): Ranges, arithmetic sequences, Regexps, Arrays,
# Strings, numbers, classes and the globals, each against ruby's answer.
class CExtBreadthTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/encoding.h>
    #include <ruby/re.h>
    #include <ruby/io/buffer.h>
    #include <string.h>

    static VALUE b_ranges(VALUE self, VALUE obj) {
      VALUE beg = Qundef, end = Qundef;
      int excl = 7;
      int ok = rb_range_values(obj, &beg, &end, &excl);
      return ok ? rb_ary_new_from_args(4, INT2FIX(ok != 0), beg, end, INT2FIX(excl)) : INT2FIX(0);
    }
    static VALUE b_range_new(VALUE self, VALUE a, VALUE b, VALUE excl) { return rb_range_new(a, b, RTEST(excl)); }
    static VALUE b_arith(VALUE self, VALUE obj) {
      rb_arithmetic_sequence_components_t c;
      if (!rb_arithmetic_sequence_extract(obj, &c)) return Qfalse;
      return rb_ary_new_from_args(4, c.begin, c.end, c.step, INT2FIX(c.exclude_end));
    }
    static VALUE b_regexps(VALUE self, VALUE src, VALUE str) {
      VALUE re = rb_reg_new_str(src, ONIG_OPTION_IGNORECASE);
      VALUE re2 = rb_reg_new("b+", 2, 0);
      VALUE at = rb_reg_match(re, str);
      VALUE m = rb_funcall(re, rb_intern("match"), 1, str);
      return rb_ary_new_from_args(6, re, at, rb_reg_nth_match(0, m), rb_reg_nth_match(9, m), LONG2NUM(rb_reg_search(re2, str, 0, 0)),
                                  rb_reg_nth_match(1, Qnil));
    }
    static VALUE b_arrays(VALUE self) {
      VALUE a = rb_ary_new_from_args(3, INT2FIX(3), INT2FIX(1), INT2FIX(2));
      VALUE extra[2] = { INT2FIX(9), INT2FIX(8) };
      rb_ary_concat(a, rb_ary_new_from_args(1, INT2FIX(5)));
      VALUE deleted = rb_ary_delete_at(a, 0);
      rb_ary_sort_bang(a);
      VALUE s = rb_ary_to_s(a);
      rb_ary_cat(a, extra, 2);
      rb_ary_reverse(a);
      VALUE hidden = rb_ary_hidden_new(4);
      rb_ary_push(hidden, INT2FIX(1));
      VALUE packed = rb_ary_new_from_args(3, rb_enum_values_pack(0, NULL), rb_enum_values_pack(1, extra), rb_enum_values_pack(2, extra));
      VALUE frozen = rb_ary_freeze(rb_ary_new());
      VALUE mem[3];
      rb_mem_clear(mem, 3);
      return rb_ary_new_from_args(8, a, deleted, s, RARRAY_LEN(hidden) == 1 ? Qtrue : Qfalse, packed, rb_obj_frozen_p(frozen),
                                  mem[2], LONG2NUM(RARRAY_LEN(rb_ary_tmp_new(0))));
    }
    static VALUE b_ptr_use(VALUE self, VALUE a) {
      RARRAY_PTR_USE(a, ptr, { ptr[0] = rb_str_new_cstr("set through the pointer"); });
      return a;
    }
    static VALUE b_strings(VALUE self, VALUE str) {
      VALUE s = rb_str_dup(str);
      rb_str_update(s, 1, 2, rb_str_new_cstr("XY"));
      VALUE t = rb_str_tmp_new(3);
      memcpy(RSTRING_PTR(t), "abc", 3);
      VALUE m = rb_str_new_cstr("ab");
      rb_str_modify_expand(m, 100);
      return rb_ary_new_from_args(9, s, LONG2NUM(rb_str_strlen(str)), rb_str_length(str), rb_str_to_str(str), rb_str_new(RSTRING_PTR(t), 3),
                                  rb_str_capacity(m) >= 102 ? Qtrue : Qfalse, ID2SYM(rb_intern_str(str)),
                                  LONG2NUM(rb_memsearch("lo", 2, RSTRING_PTR(str), RSTRING_LEN(str), rb_enc_get(str))),
                                  DBL2NUM(rb_str_to_dbl(rb_str_new_cstr("2.5x"), 0)));
    }
    static VALUE b_strict_dbl(VALUE self, VALUE str) { return DBL2NUM(rb_str_to_dbl(str, 1)); }
    static VALUE b_to_str_bad(VALUE self, VALUE v) { return rb_str_to_str(v); }
    static VALUE b_asciicompat(VALUE self, VALUE str) { rb_must_asciicompat(str); return Qtrue; }
    static VALUE b_numbers(VALUE self) {
      VALUE big = rb_funcall(INT2FIX(2), rb_intern("**"), 1, INT2FIX(70));
      return rb_ary_new_from_args(10, rb_big_norm(big), DBL2NUM(rb_big2dbl(big)), rb_big_cmp(big, INT2FIX(1)),
                                  rb_big_plus(big, INT2FIX(1)), rb_big_minus(big, big), rb_big_mul(big, INT2FIX(2)),
                                  rb_dbl2big(1e20), rb_str2inum(rb_str_new_cstr("ff"), 16),
                                  INT2FIX(rb_num2short(INT2FIX(-7))), INT2FIX(rb_num2ushort(INT2FIX(65535))));
    }
    static VALUE b_pack(VALUE self, VALUE v, VALUE numwords, VALUE wordsize, VALUE flags) {
      unsigned char buf[32] = { 0 };
      int sign = rb_integer_pack(v, buf, NUM2SIZET(numwords), NUM2SIZET(wordsize), 0, NUM2INT(flags));
      size_t n = NUM2SIZET(numwords) * NUM2SIZET(wordsize);
      VALUE back = rb_integer_unpack(buf, NUM2SIZET(numwords), NUM2SIZET(wordsize), 0, NUM2INT(flags));
      VALUE negative = rb_integer_unpack(buf, NUM2SIZET(numwords), NUM2SIZET(wordsize), 0,
                                         (NUM2INT(flags) & ~INTEGER_PACK_2COMP) | INTEGER_PACK_NEGATIVE);
      return rb_ary_new_from_args(4, INT2FIX(sign), rb_str_new((char *)buf, n), back, negative);
    }
    static VALUE b_buffer(VALUE self, VALUE buffer, VALUE text) {
      const void *rbase;
      size_t rsize;
      rb_io_buffer_get_bytes_for_reading(buffer, &rbase, &rsize);
      VALUE seen = rb_str_new(rbase, rsize);
      void *wbase;
      size_t wsize;
      rb_io_buffer_get_bytes_for_writing(buffer, &wbase, &wsize);
      memcpy(wbase, RSTRING_PTR(text), RSTRING_LEN(text) < (long)wsize ? RSTRING_LEN(text) : (long)wsize);
      return rb_assoc_new(seen, SIZET2NUM(wsize));
    }
    static VALUE b_short(VALUE self, VALUE v) { return INT2FIX(rb_num2short(v)); }
    static VALUE b_to_int(VALUE self, VALUE v) { return rb_to_int(v); }
    static VALUE b_coerce(VALUE self, VALUE x, VALUE y) {
      return rb_ary_new_from_args(2, rb_num_coerce_bin(x, y, '+'), rb_num_coerce_relop(x, y, '<'));
    }
    static VALUE b_relop_bad(VALUE self, VALUE x, VALUE y) { return rb_num_coerce_relop(x, y, '<'); }
    static VALUE b_ints(VALUE self, VALUE v) {
      return rb_ary_new_from_args(2, rb_check_to_integer(v, "to_int"), rb_hash(INT2FIX(1)) == rb_funcall(INT2FIX(1), rb_intern("hash"), 0) ? Qtrue : Qfalse);
    }
    static VALUE b_objects(VALUE self, VALUE obj) {
      VALUE c = rb_obj_clone(obj);
      return rb_ary_new_from_args(6, rb_funcall(c, rb_intern("x"), 0), rb_obj_frozen_p(c), INT2FIX(rb_eql(INT2FIX(1), INT2FIX(1))), INT2FIX(rb_eql(INT2FIX(1), DBL2NUM(1.0))),
                                  rb_funcall(rb_obj_method(obj, ID2SYM(rb_intern("size"))), rb_intern("call"), 0), rb_obj_instance_variables(obj));
    }
    static VALUE b_init_copy(VALUE self, VALUE a, VALUE b) { return rb_obj_init_copy(a, b); }
    static VALUE b_frozen(VALUE self) { rb_error_frozen("thing"); return Qnil; }
    static VALUE b_memerror(VALUE self) { rb_memerror(); return Qnil; }
    static VALUE b_symbols(VALUE self, VALUE v) { return rb_to_symbol(v); }
    static VALUE b_const_id(VALUE self) {
      return rb_ary_new_from_args(2, INT2FIX(rb_is_const_id(rb_intern("Foo"))), INT2FIX(rb_is_const_id(rb_intern("foo"))));
    }
    static VALUE b_classes(VALUE self, VALUE klass) {
      rb_cvar_set(klass, rb_intern("@@seen"), INT2FIX(42));
      VALUE m = rb_module_new();
      VALUE k = rb_class_new(klass);
      return rb_ary_new_from_args(8, rb_cv_get(klass, "@@seen"), rb_mod_include_p(klass, rb_mKernel), INT2FIX(rb_mod_method_arity(klass, rb_intern("two"))),
                                  rb_obj_class(m), rb_class_superclass(k), rb_funcall(rb_class_instance_methods(0, NULL, klass), rb_intern("sort"), 0),
                                  INT2FIX(rb_method_basic_definition_p(rb_cArray, rb_intern("each"))),
                                  INT2FIX(rb_method_basic_definition_p(klass, rb_intern("two"))));
    }
    static VALUE b_two(VALUE self, VALUE a, VALUE b) { return rb_ary_new_from_args(2, a, b); }
    static VALUE b_define_id(VALUE self, VALUE klass) { rb_define_method_id(klass, rb_intern("from_id"), b_two, 2); return Qnil; }
    static VALUE b_undef(VALUE self, VALUE klass, VALUE name) { rb_undef(klass, rb_intern_str(name)); return Qnil; }
    static VALUE b_remove_const(VALUE self, VALUE mod, VALUE name) { return rb_mod_remove_const(mod, name); }
    static VALUE b_module_eval(VALUE self, VALUE mod, VALUE code) { return rb_mod_module_eval(1, &code, mod); }
    static VALUE b_globals(VALUE self) {
      return rb_ary_new_from_args(14, rb_cEnumerator, rb_cMatch, rb_mMath, rb_eMathDomainError, rb_mWaitReadable, rb_cStat,
                                  rb_eEncCompatError, rb_cUnboundMethod, rb_cBinding, rb_cDir, rb_eRegexpError, rb_eSystemExit,
                                  rb_eLocalJumpError, rb_cSet);
    }
    static VALUE b_stdio(VALUE self) {
      rb_io_write(rb_stdout, rb_str_new_cstr("to rb_stdout\n"));
      return rb_ary_new_from_args(2, rb_stdout == rb_gv_get("$stdout") ? Qtrue : Qfalse, rb_stderr == rb_gv_get("$stderr") ? Qtrue : Qfalse);
    }
    static VALUE b_misc(VALUE self, VALUE time) {
      return rb_ary_new_from_args(4, rb_time_utc_offset(time), rb_enc_from_encoding(rb_locale_encoding()), rb_get_argv(),
                                  rb_gc_latest_gc_info(ID2SYM(rb_intern("major_by"))) == Qnil ? Qtrue : Qtrue);
    }
    static VALUE b_notimpl(int argc, VALUE *argv, VALUE self) { return rb_f_notimplement(argc, argv, self, Qnil); }
    static VALUE b_nth(VALUE self, VALUE str, VALUE n) {
      const char *p = RSTRING_PTR(str), *e = RSTRING_END(str);
      return LONG2NUM(rb_enc_nth(p, e, NUM2LONG(n), rb_enc_get(str)) - p);
    }
    /* json's State#as_json=: a Proc, a Method and a Fiber are T_DATA. */
    static VALUE b_to_proc(VALUE self, VALUE v, VALUE check) {
      return RTEST(check) ? rb_check_convert_type(v, T_DATA, "Proc", "to_proc") : rb_convert_type(v, T_DATA, "Proc", "to_proc");
    }
    static VALUE b_negative(VALUE self, VALUE which) {
      return FIX2INT(which) ? rb_utf8_str_new(NULL, -5) : rb_str_new("x", -1);
    }
    static VALUE b_utf8(VALUE self, VALUE code) {
      char buf[8];
      int n = rb_uv_to_utf8(buf, NUM2ULONG(code));
      return rb_enc_str_new(buf, n, rb_utf8_encoding());
    }

    void Init_breadth(void) {
      VALUE m = rb_define_module("Breadth");
      rb_define_module_function(m, "ranges", b_ranges, 1);
      rb_define_module_function(m, "range_new", b_range_new, 3);
      rb_define_module_function(m, "arith", b_arith, 1);
      rb_define_module_function(m, "regexps", b_regexps, 2);
      rb_define_module_function(m, "arrays", b_arrays, 0);
      rb_define_module_function(m, "ptr_use", b_ptr_use, 1);
      rb_define_module_function(m, "strings", b_strings, 1);
      rb_define_module_function(m, "strict_dbl", b_strict_dbl, 1);
      rb_define_module_function(m, "to_str_bad", b_to_str_bad, 1);
      rb_define_module_function(m, "asciicompat", b_asciicompat, 1);
      rb_define_module_function(m, "numbers", b_numbers, 0);
      rb_define_module_function(m, "short", b_short, 1);
      rb_define_module_function(m, "buffer", b_buffer, 2);
      rb_define_module_function(m, "pack", b_pack, 4);
      rb_define_module_function(m, "to_int", b_to_int, 1);
      rb_define_module_function(m, "coerce", b_coerce, 2);
      rb_define_module_function(m, "relop_bad", b_relop_bad, 2);
      rb_define_module_function(m, "ints", b_ints, 1);
      rb_define_module_function(m, "objects", b_objects, 1);
      rb_define_module_function(m, "init_copy", b_init_copy, 2);
      rb_define_module_function(m, "frozen", b_frozen, 0);
      rb_define_module_function(m, "memerror", b_memerror, 0);
      rb_define_module_function(m, "symbols", b_symbols, 1);
      rb_define_module_function(m, "const_id", b_const_id, 0);
      rb_define_module_function(m, "classes", b_classes, 1);
      rb_define_module_function(m, "define_id", b_define_id, 1);
      rb_define_module_function(m, "undef", b_undef, 2);
      rb_define_module_function(m, "remove_const", b_remove_const, 2);
      rb_define_module_function(m, "module_eval", b_module_eval, 2);
      rb_define_module_function(m, "globals", b_globals, 0);
      rb_define_module_function(m, "stdio", b_stdio, 0);
      rb_define_module_function(m, "misc", b_misc, 1);
      rb_define_module_function(m, "notimpl", b_notimpl, -1);
      rb_define_module_function(m, "nth", b_nth, 2);
      rb_define_module_function(m, "utf8", b_utf8, 1);
      rb_define_module_function(m, "negative", b_negative, 1);
      rb_define_module_function(m, "to_proc", b_to_proc, 2);
    }
  C

  PROGRAM = <<~'RUBY'
    require "breadth"

    def show(label)
      p [label, yield]
    rescue StandardError, ScriptError => e
      p [label, e.class, e.message]
    end

    Spanish = Struct.new(:begin, :end, :exclude_end?)
    class Point
      attr_reader :x
      def initialize(x) = @x = x
      def size = 2
      def two(a, b) = [a, b]
    end
    class Money
      def initialize(v) = @v = v
      def coerce(other) = [Money.new(other), self]
      def +(other) = :plus
      def <(other) = :less
      def value = @v
    end
    class NoOrder
      def coerce(other) = [NoOrder.new, self]
      def <(other) = nil
    end
    module Doomed
      GONE = 1
    end

    show(:ranges) { [Breadth.ranges(1..3), Breadth.ranges(1...3), Breadth.ranges(Spanish.new(:a, :b, true)), Breadth.ranges(1.step(9, 2)), Breadth.ranges("no")] }
    show(:range_new) { [Breadth.range_new(1, 5, false), Breadth.range_new("a", "c", true)] }
    show(:range_new_bad) { Breadth.range_new(1, "a", false) }
    show(:arith) { [Breadth.arith(1.step(10, 3)), Breadth.arith((1..10) % 4), Breadth.arith(1...5), Breadth.arith(:no)] }
    show(:regexps) { Breadth.regexps("A(b)C", "xxabcbbb") }
    show(:arrays) { Breadth.arrays }
    show(:ptr_use) { a = [1, 2]; GC.start; Breadth.ptr_use(a); GC.start; a }
    show(:strings) { Breadth.strings("hello") }
    show(:strict_dbl) { Breadth.strict_dbl("1.25") }
    show(:strict_dbl_bad) { Breadth.strict_dbl("1.25x") }
    show(:to_str_bad) { Breadth.to_str_bad(1) }
    show(:asciicompat) { [Breadth.asciicompat("ok"), (Breadth.asciicompat("x".encode("UTF-16LE")) rescue $!.message)] }
    show(:numbers) { Breadth.numbers }
    show(:pack) do
      little = 0x02 | 0x20
      big = 0x01 | 0x10
      [Breadth.pack(0x0102030405, 2, 4, little), Breadth.pack(0x0102030405, 2, 4, big), Breadth.pack(-2, 1, 4, little | 0x80),
       Breadth.pack(-2, 1, 4, little), Breadth.pack(2**40, 1, 4, little), Breadth.pack(0, 1, 2, big), Breadth.pack(255, 1, 1, little | 0x80),
       Breadth.pack(2**70 + 3, 2, 8, 0x02 | 0x40)].map { |sign, bytes, back, negative| [sign, bytes.unpack1("H*"), back, negative] }
    end
    show(:buffer) do
      buffer = IO::Buffer.new(8)
      buffer.set_string("abcdefgh")
      seen = Breadth.buffer(buffer, "XY")
      slice = buffer.slice(2, 3)
      [seen, buffer.get_string, Breadth.buffer(slice, "123"), buffer.get_string, Breadth.buffer(IO::Buffer.new(0), "")]
    end
    show(:buffer_string) { s = +"hello"; IO::Buffer.for(s) { |b| Breadth.buffer(b, "J") }; s }
    show(:buffer_readonly) { IO::Buffer.for("frozen".freeze) { |b| Breadth.buffer(b, "x") } }
    show(:short) { Breadth.short(40000) }
    show(:short_low) { Breadth.short(-40000) }
    show(:to_int) { [Breadth.to_int(3), Breadth.to_int(2**70), Breadth.to_int(2.9), Breadth.to_int(Point.new(1).method(:size).arity)] }
    show(:to_int_nil) { Breadth.to_int(nil) }
    show(:to_int_false) { Breadth.to_int(false) }
    show(:to_int_sym) { Breadth.to_int(:a) }
    show(:to_int_str) { Breadth.to_int("1") }
    show(:coerce) { Breadth.coerce(1, Money.new(2)) }
    show(:relop_bad) { Breadth.relop_bad(1, NoOrder.new) }
    show(:relop_none) { Breadth.relop_bad(1, Object.new) }
    show(:ints) { [Breadth.ints(5), Breadth.ints(2.9), Breadth.ints("x")] }
    show(:objects) { Breadth.objects(Point.new(3).freeze) }
    show(:init_copy) { [Breadth.init_copy(Point.new(1), Point.new(2)).x, (Breadth.init_copy(Point.new(1), "s") rescue $!.message)] }
    show(:frozen) { Breadth.frozen }
    show(:memerror) do
      Breadth.memerror
    rescue NoMemoryError => e
      [e.class, e.message]
    end
    show(:symbols) { [Breadth.symbols(:a), Breadth.symbols("b"), (Breadth.symbols(3) rescue $!.message)] }
    show(:const_id) { Breadth.const_id }
    show(:classes) { Breadth.classes(Point) }
    show(:define_id) { Breadth.define_id(Point); Point.new(1).from_id(:a, :b) }
    show(:undef) { Breadth.undef(Point, "size"); Point.new(1).respond_to?(:size) }
    show(:undef_missing) { Breadth.undef(Point, "nothing_here") }
    show(:remove_const) { [Breadth.remove_const(Doomed, :GONE), Doomed.const_defined?(:GONE)] }
    show(:module_eval) { Breadth.module_eval(Point, "def evaled = :yes"); Point.new(1).evaled }
    show(:globals) { Breadth.globals }
    show(:stdio) { Breadth.stdio }
    show(:stdio_moved) do
      out = StringIO.new
      $stdout = out
      r = Breadth.stdio
      $stdout = STDOUT
      [r, out.string]
    end
    show(:misc) { Breadth.misc(Time.at(0).utc) }
    show(:notimpl) { Breadth.notimpl(1) }
    show(:nth) { [Breadth.nth("héllo", 2), Breadth.nth("héllo", 9), Breadth.nth("abc", 1)] }
    show(:utf8) { [Breadth.utf8(65), Breadth.utf8(0xE9), Breadth.utf8(0x1F600)] }
    show(:negative) { Breadth.negative(0) }
    show(:negative_null) { Breadth.negative(1) }
    show(:to_proc) do
      [Breadth.to_proc(:itself, false).class, Breadth.to_proc(:upcase, false).call("a"), Breadth.to_proc(-> { 1 }, false).lambda?,
       Breadth.to_proc(1.method(:+), false).class, Breadth.to_proc(:itself, true).class, Breadth.to_proc(1, true)]
    end
    show(:to_proc_bad) { Breadth.to_proc(1, false) }
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("breadth", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, "require 'stringio'\n#{PROGRAM}", [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
