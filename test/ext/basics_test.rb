# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# A C extension built against ruby 4.0.7's own headers runs in a zr
# binary and gives ruby's answers: its methods and their arities, the
# Strings and numbers that it makes and reads inline, its calls of Ruby,
# and each way that an exception leaves or stays in C.
class CExtBasicsTest < Minitest::Test
  SOURCE = <<~C
    #include <ruby.h>

    static VALUE hello(VALUE self) { return rb_utf8_str_new_cstr("hello from C"); }
    static VALUE add(VALUE self, VALUE a, VALUE b) { return LONG2NUM(NUM2LONG(a) + NUM2LONG(b)); }
    static VALUE twice(VALUE self, VALUE x) { VALUE two = INT2FIX(2); return rb_funcallv(x, rb_intern("*"), 1, &two); }
    static VALUE count_args(int argc, VALUE *argv, VALUE self) { return INT2FIX(argc); }
    static VALUE first_of(VALUE self, VALUE args) { return RARRAY_LEN(args) > 0 ? RARRAY_AREF(args, 0) : Qnil; }
    static VALUE yields(VALUE self) { rb_yield(INT2FIX(1)); return rb_yield(INT2FIX(2)); }
    static VALUE given(VALUE self) { return rb_block_given_p() ? Qtrue : Qfalse; }
    static VALUE boom(VALUE self) { rb_exc_raise(rb_exc_new_cstr(rb_eArgError, "boom from C")); return Qnil; }
    static VALUE call_explode(VALUE obj) { return rb_funcallv(obj, rb_intern("explode"), 0, NULL); }
    static VALUE passes_through(VALUE self, VALUE obj) { call_explode(obj); return Qtrue; }
    static VALUE protected_call(VALUE self, VALUE obj) {
      int state = 0;
      VALUE r = rb_protect(call_explode, obj, &state);
      if (state) { rb_set_errinfo(Qnil); return INT2FIX(state); }
      return r;
    }
    static VALUE rethrow(VALUE self, VALUE obj) {
      int state = 0;
      rb_protect(call_explode, obj, &state);
      if (state) rb_jump_tag(state);
      return Qnil;
    }
    static VALUE cleanup(VALUE obj) { return rb_funcallv(obj, rb_intern("cleanup!"), 0, NULL); }
    static VALUE ensured(VALUE self, VALUE obj) { return rb_ensure(call_explode, obj, cleanup, obj); }
    static VALUE rescuer(VALUE data, VALUE exc) { return rb_funcallv(exc, rb_intern("message"), 0, NULL); }
    static VALUE rescued(VALUE self, VALUE obj) { return rb_rescue(call_explode, obj, rescuer, Qnil); }
    static VALUE big(VALUE self) { return ULL2NUM(18446744073709551615ULL); }
    static VALUE neg(VALUE self) { return LL2NUM(-9223372036854775807LL - 1); }
    static VALUE as_long(VALUE self, VALUE v) { return LONG2NUM(NUM2LONG(v)); }
    static VALUE as_ulong(VALUE self, VALUE v) { return ULONG2NUM(NUM2ULONG(v)); }
    static VALUE as_int(VALUE self, VALUE v) { return INT2NUM(NUM2INT(v)); }
    static VALUE half(VALUE self, VALUE v) { return DBL2NUM(NUM2DBL(v) / 2); }
    static VALUE bytes(VALUE self, VALUE s) {
      StringValue(s);
      VALUE out = rb_str_new(RSTRING_PTR(s), RSTRING_LEN(s));
      rb_str_cat_cstr(out, "!");
      return out;
    }
    static VALUE cstr(VALUE self, VALUE s) { return rb_usascii_str_new_cstr(StringValueCStr(s)); }
    static VALUE upcase_in_place(VALUE self, VALUE s) {
      rb_str_modify(s);
      for (long i = 0; i < RSTRING_LEN(s); i++) RSTRING_PTR(s)[i] &= ~0x20;
      return s;
    }

    void Init_hello(void) {
      VALUE m = rb_define_module("Hello");
      rb_define_module_function(m, "hello", hello, 0);
      rb_define_module_function(m, "add", add, 2);
      rb_define_module_function(m, "twice", twice, 1);
      rb_define_module_function(m, "count_args", count_args, -1);
      rb_define_module_function(m, "first_of", first_of, -2);
      rb_define_module_function(m, "yields", yields, 0);
      rb_define_module_function(m, "given", given, 0);
      rb_define_module_function(m, "boom", boom, 0);
      rb_define_module_function(m, "passes_through", passes_through, 1);
      rb_define_module_function(m, "protected_call", protected_call, 1);
      rb_define_module_function(m, "rethrow", rethrow, 1);
      rb_define_module_function(m, "ensured", ensured, 1);
      rb_define_module_function(m, "rescued", rescued, 1);
      rb_define_module_function(m, "big", big, 0);
      rb_define_module_function(m, "neg", neg, 0);
      rb_define_module_function(m, "as_long", as_long, 1);
      rb_define_module_function(m, "as_ulong", as_ulong, 1);
      rb_define_module_function(m, "as_int", as_int, 1);
      rb_define_module_function(m, "half", half, 1);
      rb_define_module_function(m, "bytes", bytes, 1);
      rb_define_module_function(m, "cstr", cstr, 1);
      rb_define_module_function(m, "upcase_in_place", upcase_in_place, 1);
    }
  C

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("hello", SOURCE)
  end

  def assert_same_as_ruby(program)
    ruby, zr = Zr::Test::CExt.outputs(@ext, program)
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr's output differs from ruby's\nzr stderr:\n#{zr.stderr}"
  end

  def test_methods_take_their_arguments_by_arity_and_reflect_ruby_arities
    assert_same_as_ruby(<<~RUBY)
      require "hello"
      p Hello.hello, Hello.hello.encoding
      p Hello.add(2, 3), Hello.twice(21), Hello.twice("ab")
      p Hello.count_args, Hello.count_args(1, 2, 3), Hello.count_args(k: 1)
      p Hello.first_of, Hello.first_of(:a, :b)
      p %i[hello add count_args first_of].map { Hello.method(_1).arity }
      p Hello.respond_to?(:add), Hello.private_instance_methods(false).sort.first(3)
      begin
        Hello.add(1)
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      p $LOADED_FEATURES.grep(/hello/).map { File.basename(_1) }
    RUBY
  end

  def test_a_c_method_yields_to_its_block
    assert_same_as_ruby(<<~RUBY)
      require "hello"
      Hello.yields { |x| p [:yielded, x] }
      p Hello.given, Hello.given {}
      p [1, 2].map { |x| Hello.yields { |y| x * y } }
      begin
        Hello.yields
      rescue LocalJumpError => e
        p [e.class, e.message]
      end
      r = [1, 2, 3].each { |x| Hello.yields { break :out if x == 2 } }
      p r
    RUBY
  end

  def test_an_exception_leaves_c_or_stays_in_it
    assert_same_as_ruby(<<~RUBY)
      require "hello"
      class Exploder
        def explode = raise(TypeError, "kaboom")
        def cleanup! = puts("cleaned up")
      end
      class Quiet
        def explode = :fine
        def cleanup! = puts("cleaned up quietly")
      end
      def show
        p yield
      rescue => e
        p [e.class, e.message]
      end
      show { Hello.boom }
      show { Hello.passes_through(Exploder.new) }
      show { Hello.passes_through(Quiet.new) }
      show { Hello.protected_call(Exploder.new) }
      show { Hello.protected_call(Quiet.new) }
      show { Hello.rethrow(Exploder.new) }
      show { Hello.ensured(Exploder.new) }
      show { Hello.ensured(Quiet.new) }
      show { Hello.rescued(Exploder.new) }
      show { Hello.rescued(Quiet.new) }
      p $!
      p catch(:t) { Hello.passes_through(Object.new.tap { |o| def o.explode = throw(:t, :thrown) }) }
    RUBY
  end

  def test_numbers_convert_as_ruby_converts_them
    assert_same_as_ruby(<<~RUBY)
      require "hello"
      p Hello.big, Hello.neg, Hello.add(2**40, 1)
      p Hello.as_long(3.9), Hello.as_long(-3.9), Hello.as_long(2**62), Hello.as_long(-2**63)
      p Hello.as_ulong(-1), Hello.as_ulong(2**64 - 1), Hello.as_ulong(2**63)
      p Hello.half(3), Hello.half(2**70)
      [nil, 2**64, -2**64, 1e30, -1e30, "x", Object.new].each do |v|
        Hello.as_long(v)
      rescue => e
        p [e.class, e.message.sub(/0x\\h+/, "")]
      end
      [2**31, -2**31 - 1, 2**31 - 1].each do |v|
        p Hello.as_int(v)
      rescue RangeError => e
        p [e.class, e.message]
      end
      [nil, "1", true].each do |v|
        Hello.half(v)
      rescue TypeError => e
        p [e.class, e.message]
      end
      class Two
        def to_int = 2
      end
      p Hello.as_long(Two.new)
    RUBY
  end

  def test_strings_keep_their_bytes_and_encodings
    assert_same_as_ruby(<<~RUBY)
      require "hello"
      s = Hello.bytes("caf\\u00e9")
      p s, s.encoding, s.bytesize
      p Hello.cstr("abc"), Hello.cstr("abc").encoding
      begin
        Hello.cstr("a\\0b")
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      t = +"shout"
      p Hello.upcase_in_place(t), t, t.ascii_only?
      begin
        Hello.upcase_in_place("frozen".freeze)
      rescue FrozenError => e
        p [e.class, e.message]
      end
      class Strish
        def to_str = "via to_str"
      end
      p Hello.bytes(Strish.new)
      begin
        Hello.bytes(1)
      rescue TypeError => e
        p [e.class, e.message]
      end
    RUBY
  end
end
