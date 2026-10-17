# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API that the own C of bigdecimal, nkf and syslog calls:
# rb_Rational, rb_complex_real/imag, rb_opts_exception_p, rb_f_sprintf,
# rb_num_coerce_bin's errors, NUM2LL, NUM2ULL and NUM2DBL's, rb_ary_replace,
# ruby_version and the Ractor-local pointers that prism's and ffi's C read
# and rb_define_dummy_encoding, each against ruby's answer.
class CExtBundledGemsCApiTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/encoding.h>
    #include <ruby/ractor.h>

    int rb_opts_exception_p(VALUE opts, int default_value);

    static VALUE b_rational(VALUE self, VALUE n, VALUE d) { return rb_Rational(n, d); }
    static VALUE b_parts(VALUE self, VALUE z) { return rb_assoc_new(rb_complex_real(z), rb_complex_imag(z)); }
    static VALUE b_exception(VALUE self, VALUE opts) { return INT2FIX(rb_opts_exception_p(opts, 7)); }
    static VALUE b_sprintf(VALUE self, VALUE args) { return rb_f_sprintf((int)RARRAY_LEN(args), RARRAY_CONST_PTR(args)); }
    static VALUE b_coerce(VALUE self, VALUE x, VALUE y) { return rb_num_coerce_bin(x, y, '+'); }
    RUBY_EXTERN const char ruby_version[];
    static rb_ractor_local_key_t ptr_key;
    static VALUE b_ll(VALUE self, VALUE v) { return LL2NUM(NUM2LL(v)); }
    static VALUE b_ull(VALUE self, VALUE v) { return ULL2NUM(NUM2ULL(v)); }
    static VALUE b_dbl(VALUE self, VALUE v) { return DBL2NUM(NUM2DBL(v)); }
    static VALUE b_replace(VALUE self, VALUE a, VALUE b) { return rb_ary_replace(a, b); }
    static VALUE b_version(VALUE self) { return rb_str_new_cstr(ruby_version); }
    static VALUE b_ptr(VALUE self) {
      void *before = rb_ractor_local_storage_ptr(ptr_key);
      rb_ractor_local_storage_ptr_set(ptr_key, (void *)&ptr_key);
      return rb_assoc_new(before ? Qtrue : Qfalse, rb_ractor_local_storage_ptr(ptr_key) == (void *)&ptr_key ? Qtrue : Qfalse);
    }
    static VALUE b_dummy(VALUE self, VALUE name) {
      int index = rb_define_dummy_encoding(StringValueCStr(name));
      return rb_enc_from_encoding(rb_enc_from_index(index));
    }

    void Init_bundledcapi(void) {
      VALUE m = rb_define_module("BundledCApi");
      rb_define_module_function(m, "rational", b_rational, 2);
      rb_define_module_function(m, "parts", b_parts, 1);
      rb_define_module_function(m, "exception", b_exception, 1);
      rb_define_module_function(m, "sprintf", b_sprintf, 1);
      rb_define_module_function(m, "dummy", b_dummy, 1);
      rb_define_module_function(m, "coerce", b_coerce, 2);
      rb_define_module_function(m, "ll", b_ll, 1);
      rb_define_module_function(m, "ull", b_ull, 1);
      rb_define_module_function(m, "dbl", b_dbl, 1);
      rb_define_module_function(m, "replace", b_replace, 2);
      rb_define_module_function(m, "version", b_version, 0);
      rb_define_module_function(m, "ptr", b_ptr, 0);
      ptr_key = rb_ractor_local_storage_ptr_newkey(NULL);
    }
  C

  PROGRAM = <<~'RUBY'
    require "bundledcapi"

    p BundledCApi.rational(3, 6), BundledCApi.rational("1/3", 2), BundledCApi.rational(1.5, 1)
    p((BundledCApi.rational(1, 0) rescue $!.class), (BundledCApi.rational(nil, 1) rescue $!.class))
    p BundledCApi.parts(Complex(1, 2)), BundledCApi.parts(Complex(1.5, -0.0))
    p BundledCApi.exception(nil), BundledCApi.exception({}), BundledCApi.exception({ exception: true }), BundledCApi.exception({ exception: false })
    p((BundledCApi.exception({ exception: 1 }) rescue [$!.class, $!.message]), (BundledCApi.exception({ other: 1 }) rescue [$!.class, $!.message]))
    p BundledCApi.sprintf(["%05.1f|%-3s|%x", 3.14159, "a", 255]), BundledCApi.sprintf(["plain"])
    e = BundledCApi.dummy("X-ZR-TEST")
    p e, e.dummy?, e.name, Encoding.find("X-ZR-TEST").equal?(e), Encoding.list.include?(e), "a".force_encoding(e).encoding
p((BundledCApi.dummy("UTF-8") rescue [$!.class, $!.message]))
bad = Object.new
def bad.coerce(_) = 1
good = Object.new
def good.coerce(x) = [x, 2]
[["s"], [nil], [bad], [good], [2.5]].each do |(y)|
  p BundledCApi.coerce(1, y)
rescue TypeError => e
  p [e.class, e.message]
end
    [1e30, -1e30, Float::NAN, 2.5, 2**70].each do |v|
      p [(BundledCApi.ll(v) rescue $!.message), (BundledCApi.ull(v) rescue $!.message)]
    end
    p BundledCApi.dbl(3), BundledCApi.dbl(1r / 4), (BundledCApi.dbl(Object.new) rescue [$!.class, $!.message])
    a = [1]
    p BundledCApi.replace(a, [2, 3]).equal?(a), a, BundledCApi.version == RUBY_VERSION
    p BundledCApi.ptr, BundledCApi.ptr
  RUBY

  def setup

    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("bundledcapi", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain,) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
  end
end
