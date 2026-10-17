# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API that date's own extension (date_core) calls beyond the rest:
# rb_num_coerce_cmp, rb_int_positive_pow, rb_rational_num/den,
# rb_str_to_inum, rb_str_format, rb_memhash and ruby_strtoul, each
# against ruby's answer.
class CExtDateCApiTest < Minitest::Test
  SOURCE = <<~'C'
    #include <errno.h>
    #include <ruby.h>
    #include <ruby/util.h>

    RUBY_EXTERN VALUE rb_int_positive_pow(long x, unsigned long y);

    static VALUE d_coerce_cmp(VALUE self, VALUE x, VALUE y) { return rb_num_coerce_cmp(x, y, rb_intern("<=>")); }
    static VALUE d_pow(VALUE self, VALUE x, VALUE y) { return rb_int_positive_pow(NUM2LONG(x), NUM2ULONG(y)); }
    static VALUE d_num_den(VALUE self, VALUE r) { return rb_assoc_new(rb_rational_num(r), rb_rational_den(r)); }
    static VALUE d_to_inum(VALUE self, VALUE s, VALUE base, VALUE bad) { return rb_str_to_inum(s, NUM2INT(base), RTEST(bad)); }
    static VALUE d_format(VALUE self, VALUE fmt, VALUE args) {
      return rb_str_format((int)RARRAY_LEN(args), RARRAY_CONST_PTR(args), fmt);
    }
    static VALUE d_memhash_same(VALUE self, VALUE a, VALUE b) {
      return rb_memhash(RSTRING_PTR(a), RSTRING_LEN(a)) == rb_memhash(RSTRING_PTR(b), RSTRING_LEN(b)) ? Qtrue : Qfalse;
    }
    static VALUE d_strtoul(VALUE self, VALUE s, VALUE base) {
      char *end = NULL;
      errno = 0;
      unsigned long v = ruby_strtoul(StringValueCStr(s), &end, NUM2INT(base));
      int err = errno;
      return rb_ary_new_from_args(3, ULONG2NUM(v), end ? LONG2NUM(end - RSTRING_PTR(s)) : Qnil, INT2FIX(err == ERANGE ? 1 : err == EINVAL ? 2 : 0));
    }

    void Init_datecapi(void) {
      VALUE m = rb_define_module("DateCApi");
      rb_define_module_function(m, "coerce_cmp", d_coerce_cmp, 2);
      rb_define_module_function(m, "pow", d_pow, 2);
      rb_define_module_function(m, "num_den", d_num_den, 1);
      rb_define_module_function(m, "to_inum", d_to_inum, 3);
      rb_define_module_function(m, "format", d_format, 2);
      rb_define_module_function(m, "memhash_same", d_memhash_same, 2);
      rb_define_module_function(m, "strtoul", d_strtoul, 2);
    }
  C

  PROGRAM = <<~'RUBY'
    require "datecapi"

    class Num
      def initialize(n) = @n = n
      def coerce(other) = [other, @n]
    end
    p DateCApi.coerce_cmp(1, Num.new(2)), DateCApi.coerce_cmp(3, Num.new(2.5)), DateCApi.coerce_cmp(1, Object.new)
    p DateCApi.coerce_cmp(1, Struct.new(:x) { def coerce(_) = nil }.new(1))
    p DateCApi.pow(10, 3), DateCApi.pow(10, 25), DateCApi.pow(-2, 63), DateCApi.pow(7, 0)
    p DateCApi.num_den(3/4r), DateCApi.num_den(-6/4r), DateCApi.num_den(Rational(10**30, 7))
    p DateCApi.to_inum("123", 10, false), DateCApi.to_inum("12x", 10, false), DateCApi.to_inum("ff", 16, false)
    p DateCApi.to_inum("  42  ", 10, true), DateCApi.to_inum("99999999999999999999999", 10, false)
    begin
      DateCApi.to_inum("12x", 10, true)
    rescue ArgumentError => e
      p e.message
    end
    p DateCApi.format("%0*d", [4, 7]), DateCApi.format("%*s|", [5, "ab"]), DateCApi.format("%.3f %s", [1.23456, :x])
    p DateCApi.format("plain", []), DateCApi.format("%<a>s-%<b>d", [{ a: "x", b: 2 }])
    p DateCApi.memhash_same("abc", "abc".dup), DateCApi.memhash_same("abc", "abd"), DateCApi.memhash_same("", "")
    ["123", "  +77z", "-1", "0x1F", "0x", "017", "09", "zz", "", "18446744073709551615", "18446744073709551616"].each do |s|
      p [s, DateCApi.strtoul(s, 0), DateCApi.strtoul(s, 10), DateCApi.strtoul(s, 16)]
    end
    p DateCApi.strtoul("10", 1), DateCApi.strtoul("10", 37), DateCApi.strtoul("zz", 36)
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("datecapi", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain,) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
  end
end
