# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# ruby/util.h's tables and digit scanners, which cgi's escape reads
# (`zr-dev ext rank`), each against ruby's answer.
class CExtUtilTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/util.h>

    static VALUE u_hexdigits(VALUE self) { return rb_str_new_cstr(ruby_hexdigits); }
    static VALUE u_digit36(VALUE self, VALUE byte) { return INT2FIX(ruby_digit36_to_number_table[NUM2INT(byte) & 0xff]); }
    static VALUE u_scan_digits(VALUE self, VALUE str, VALUE len, VALUE base) {
      size_t retlen = 99;
      int overflow = 99;
      unsigned long v = ruby_scan_digits(RSTRING_PTR(str), NUM2LONG(len), NUM2INT(base), &retlen, &overflow);
      return rb_ary_new_from_args(3, ULONG2NUM(v), SIZET2NUM(retlen), INT2FIX(overflow));
    }
    static VALUE u_scan_hex(VALUE self, VALUE str) {
      size_t n = 99;
      unsigned long v = ruby_scan_hex(RSTRING_PTR(str), RSTRING_LEN(str), &n);
      return rb_assoc_new(ULONG2NUM(v), SIZET2NUM(n));
    }
    static VALUE u_scan_oct(VALUE self, VALUE str) {
      size_t n = 99;
      unsigned long v = ruby_scan_oct(RSTRING_PTR(str), RSTRING_LEN(str), &n);
      return rb_assoc_new(ULONG2NUM(v), SIZET2NUM(n));
    }

    void Init_util(void) {
      VALUE m = rb_define_module("Util");
      rb_define_module_function(m, "hexdigits", u_hexdigits, 0);
      rb_define_module_function(m, "digit36", u_digit36, 1);
      rb_define_module_function(m, "scan_digits", u_scan_digits, 3);
      rb_define_module_function(m, "scan_hex", u_scan_hex, 1);
      rb_define_module_function(m, "scan_oct", u_scan_oct, 1);
    }
  C

  PROGRAM = <<~'RUBY'
    require "util"

    p Util.hexdigits
    p (0..255).map { |b| Util.digit36(b) }
    p Util.scan_digits("123abc", 6, 10)
    p Util.scan_digits("123abc", 6, 16)
    p Util.scan_digits("123abc", 2, 10)
    p Util.scan_digits("zZ9", -1, 36)
    p Util.scan_digits("777", -1, 8)
    p Util.scan_digits("xyz", -1, 10)
    p Util.scan_digits("", 0, 10)
    p Util.scan_digits("18446744073709551615", -1, 10)
    p Util.scan_digits("18446744073709551616", -1, 10)
    p Util.scan_digits("99999999999999999999999", -1, 10)
    p Util.scan_digits("ffffffffffffffffff", -1, 16)
    p Util.scan_hex("ffG"), Util.scan_hex("DEADbeef"), Util.scan_hex(""), Util.scan_hex("1234567890abcdef12")
    p Util.scan_oct("17789"), Util.scan_oct("8"), Util.scan_oct("7777777777777777777777777")
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("util", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain,) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
  end
end
