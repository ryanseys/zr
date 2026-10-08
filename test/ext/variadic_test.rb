# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API's variadic functions: rb_raise and rb_sprintf with C's
# printf directives and PRIsVALUE, a va_list through rb_vsprintf,
# rb_funcall and rb_yield_values, rb_scan_args in each of its forms,
# rb_rescue2 and rb_ary_new_from_args.
class CExtVariadicTest < Minitest::Test
  SOURCE = <<~C
    #include <ruby.h>
    #include <stdarg.h>

    static VALUE ints(VALUE self) {
      return rb_sprintf("[%d|%5d|%-5d|%05d|%+d|% d|%.3d|%i|%u|%ld|%lld|%zu|%hd]",
                        42, 42, 42, 42, 42, 42, 7, -3, -1, -9000000000L, 9000000000LL, (size_t)18, (short)70000);
    }
    static VALUE bases(VALUE self) {
      return rb_sprintf("[%x|%X|%#x|%o|%#o|%lx|%08x|%c%c|%%|%p]", 255, 255, 255, 8, 8, -1L, 3054, 'o', 'k', (void *)0x1f);
    }
    static VALUE texts(VALUE self) {
      return rb_sprintf("[%s|%8s|%-8s|%.2s|%*d|%-*d|%.*s|%s]", "abc", "abc", "abc", "abc", 6, 1, 6, 1, 3, "abcdef", (char *)0);
    }
    static VALUE floats(VALUE self) {
      return rb_sprintf("[%f|%.2f|%e|%g|%g|%10.3e|%-8.1f|%G]", 3.5, 2.0 / 3, 12345.678, 0.0001, 1e20, 6.02e23, -1.25, 1e-10);
    }
    static VALUE values(VALUE self, VALUE v) {
      return rb_sprintf("<%"PRIsVALUE"> <%+"PRIsVALUE"> <% "PRIsVALUE"> <%8"PRIsVALUE"> <%.2"PRIsVALUE">", v, v, v, v, v);
    }
    static VALUE vformat(const char *fmt, ...) {
      va_list ap;
      va_start(ap, fmt);
      VALUE s = rb_vsprintf(fmt, ap);
      va_end(ap);
      return s;
    }
    static VALUE through_va_list(VALUE self, VALUE v) { return vformat("%s=%d %"PRIsVALUE" %.1f", "n", 5, v, 0.25); }
    static VALUE raises(VALUE self, VALUE kind, VALUE v) {
      if (kind == ID2SYM(rb_intern("arg"))) rb_raise(rb_eArgError, "bad value %"PRIsVALUE" (%d of %ld)", v, 2, 3L);
      if (kind == ID2SYM(rb_intern("type"))) rb_raise(rb_eTypeError, "no implicit conversion of %s into %s", rb_obj_classname(v), "Integer");
      rb_raise(rb_eRuntimeError, "plain");
      return Qnil;
    }
    static VALUE calls(VALUE self, VALUE s) {
      VALUE parts = rb_funcall(s, rb_intern("split"), 1, rb_str_new_cstr(","));
      VALUE joined = rb_funcall(parts, rb_intern("join"), 1, rb_str_new_cstr("+"));
      VALUE sum = rb_funcall(INT2FIX(1), '+', 1, INT2FIX(2));
      VALUE many = rb_funcall(rb_cObject, rb_intern("send"), 18, ID2SYM(rb_intern("format")),
        rb_str_new_cstr("%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s"),
        INT2FIX(1), INT2FIX(2), INT2FIX(3), INT2FIX(4), INT2FIX(5), INT2FIX(6), INT2FIX(7), INT2FIX(8),
        INT2FIX(9), INT2FIX(0), INT2FIX(1), INT2FIX(2), INT2FIX(3), INT2FIX(4), INT2FIX(5), INT2FIX(6));
      return rb_ary_new_from_args(4, joined, sum, many, rb_funcall(s, rb_intern("size"), 0));
    }
    static VALUE yields(VALUE self) { return rb_yield_values(3, INT2FIX(1), rb_str_new_cstr("two"), Qnil); }
    static VALUE scan(int argc, VALUE *argv, VALUE self) {
      VALUE a, b, rest, c, opts, blk;
      int n = rb_scan_args(argc, argv, "11*1:&", &a, &b, &rest, &c, &opts, &blk);
      return rb_ary_new_from_args(8, INT2FIX(n), a, b, rest, c, opts, blk == Qnil ? Qnil : rb_funcall(blk, rb_intern("call"), 0),
                                  rb_keyword_given_p() ? Qtrue : Qfalse);
    }
    static VALUE scan_opt(int argc, VALUE *argv, VALUE self) {
      VALUE a, b;
      rb_scan_args(argc, argv, "02", &a, &b);
      return rb_ary_new_from_args(2, a, b);
    }
    static VALUE body(VALUE obj) { return rb_funcall(obj, rb_intern("go"), 0); }
    static VALUE rescuer(VALUE data, VALUE exc) {
      return rb_ary_new_from_args(2, data, rb_funcall(exc, rb_intern("message"), 0));
    }
    static VALUE rescue2(VALUE self, VALUE obj) {
      return rb_rescue2(body, obj, rescuer, ID2SYM(rb_intern("rescued")), rb_eTypeError, rb_eKeyError, (VALUE)0);
    }
    static VALUE warns(VALUE self, VALUE v) {
      rb_warn("careful with %"PRIsVALUE, v);
      rb_warning("only under -w: %d", 1);
      return Qnil;
    }

    void Init_variadic(void) {
      VALUE m = rb_define_module("Variadic");
      rb_define_module_function(m, "ints", ints, 0);
      rb_define_module_function(m, "bases", bases, 0);
      rb_define_module_function(m, "texts", texts, 0);
      rb_define_module_function(m, "floats", floats, 0);
      rb_define_module_function(m, "values", values, 1);
      rb_define_module_function(m, "through_va_list", through_va_list, 1);
      rb_define_module_function(m, "raises", raises, 2);
      rb_define_module_function(m, "calls", calls, 1);
      rb_define_module_function(m, "yields", yields, 0);
      rb_define_module_function(m, "scan", scan, -1);
      rb_define_module_function(m, "scan_opt", scan_opt, -1);
      rb_define_module_function(m, "rescue2", rescue2, 1);
      rb_define_module_function(m, "warns", warns, 1);
    }
  C

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("variadic", SOURCE)
  end

  # Plain, and under stress: the Values that C passes are on its stack.
  RUNS = [{}, { "ZR_GC_STRESS" => "1" }].freeze

  # Compares stderr too, where each warning names the program's path.
  def assert_same_as_ruby(program)
    ruby, runs = Zr::Test::CExt.outputs_under(@ext, program, RUNS)
    shown = ->(run) { [run.stdout, run.stderr.gsub(%r{^/\S+/}, ""), run.status] }
    RUNS.zip(runs).each { |env, zr| assert_equal shown.(ruby), shown.(zr), "zr's output differs from ruby's under #{env}" }
  end

  def test_printf_directives_format_as_rubys_own_printf
    assert_same_as_ruby(<<~RUBY)
      require "variadic"
      puts Variadic.ints, Variadic.bases, Variadic.texts, Variadic.floats
      p Variadic.ints.encoding
      p Variadic.values(:sym), Variadic.values("caf\\u00e9"), Variadic.values(nil), Variadic.values([1, "a"])
      p Variadic.values("caf\\u00e9").encoding, Variadic.values("tab\\there"), Variadic.values(:"odd sym")
      p Variadic.through_va_list(1.5)
    RUBY
  end

  def test_rb_raise_formats_its_message
    assert_same_as_ruby(<<~RUBY)
      require "variadic"
      [[:arg, :x], [:type, 3.0], [:other, nil]].each do |kind, v|
        Variadic.raises(kind, v)
      rescue => e
        p [e.class, e.message, e.message.encoding]
      end
    RUBY
  end

  def test_calls_yields_and_arrays_take_their_variadic_values
    assert_same_as_ruby(<<~RUBY)
      require "variadic"
      p Variadic.calls("a,b,c")
      p Variadic.yields { |*args| args }
      p Variadic.yields { |a, b, c| [c, b, a] }
    RUBY
  end

  def test_scan_args_sorts_the_arguments_as_ruby_does
    assert_same_as_ruby(<<~RUBY)
      require "variadic"
      p Variadic.scan(1, 2)
      p Variadic.scan(1, 2, 3)
      p Variadic.scan(1, 2, 3, 4, 5, k: 6) { :blk }
      p Variadic.scan(1, 2, {k: 1})
      p Variadic.scan_opt, Variadic.scan_opt(1), Variadic.scan_opt(1, 2)
      [-> { Variadic.scan(1) }, -> { Variadic.scan_opt(1, 2, 3) }].each do |call|
        call.()
      rescue ArgumentError => e
        p e.message
      end
    RUBY
  end

  def test_rescue2_rescues_only_the_classes_that_it_names
    assert_same_as_ruby(<<~RUBY)
      require "variadic"
      ok = Object.new.tap { |o| def o.go = :went }
      type = Object.new.tap { |o| def o.go = raise(TypeError, "type!") }
      key = Object.new.tap { |o| def o.go = {}.fetch(:nope) }
      other = Object.new.tap { |o| def o.go = raise(ArgumentError, "arg!") }
      p Variadic.rescue2(ok), Variadic.rescue2(type), Variadic.rescue2(key)
      begin
        Variadic.rescue2(other)
      rescue => e
        p [e.class, e.message]
      end
      p $!
    RUBY
  end

  def test_warnings_go_to_stderr_as_ruby_writes_them
    assert_same_as_ruby(<<~RUBY)
      require "variadic"
      Variadic.warns(:first)
      $VERBOSE = true
      Variadic.warns("second")
      $VERBOSE = nil
      Variadic.warns(3)
    RUBY
  end
end
