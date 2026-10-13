# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# rb_int_parse_cstr, the parser under rb_cstr_to_inum: the Integer that
# a C string starts with, where it stops, and the bytes that it counts,
# for each base, flag and length, with and without `endp` (no `endp`
# refuses text after the number), against ruby's answer.
class CExtIntParseCstrTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>

    /* [value, the offset of *endp or nil, *ndigits] for `len` bytes of
       `str` (to its NUL for a negative `len`). */
    static VALUE ip_parse(VALUE self, VALUE str, VALUE len, VALUE base, VALUE flags, VALUE with_endp) {
      const char *s = StringValueCStr(str);
      char *end = NULL;
      size_t ndigits = 9999;
      VALUE value = rb_int_parse_cstr(s, NUM2LONG(len), RTEST(with_endp) ? &end : NULL, &ndigits, NUM2INT(base), NUM2INT(flags));
      return rb_ary_new_from_args(3, value, end ? LONG2NUM(end - s) : Qnil, SIZET2NUM(ndigits));
    }

    static VALUE ip_null(VALUE self) {
      char *end = (char *)1;
      size_t ndigits = 9999;
      VALUE value = rb_int_parse_cstr(NULL, 3, &end, &ndigits, 10, RB_INT_PARSE_DEFAULT);
      return rb_ary_new_from_args(3, value, end ? Qtrue : Qfalse, SIZET2NUM(ndigits));
    }

    static VALUE ip_flags(VALUE self) {
      return rb_ary_new_from_args(5, INT2FIX(RB_INT_PARSE_SIGN), INT2FIX(RB_INT_PARSE_UNDERSCORE), INT2FIX(RB_INT_PARSE_PREFIX),
                                  INT2FIX(RB_INT_PARSE_ALL), INT2FIX(RB_INT_PARSE_DEFAULT));
    }

    void Init_intparse(void) {
      VALUE m = rb_define_module("IntParse");
      rb_define_module_function(m, "parse", ip_parse, 5);
      rb_define_module_function(m, "null", ip_null, 0);
      rb_define_module_function(m, "flags", ip_flags, 0);
    }
  C

  PROGRAM = <<~'RUBY'
    require "intparse"

    def show(label)
      p [label, yield]
    rescue StandardError => e
      p [label, e.class, e.message]
    end

    texts = ["", "0", "7", "42", "-42", "+42", "  42", " \t-7", "42  ", "42x", "x42", "-", "+", " ",
             "0x1f", "0X1F", "0b101", "0o17", "0d19", "017", "0_17", "00", "000", "0_0", "0__0", "0x", "0b", "0_",
             "1_000", "1__000", "1_", "_1", "1_000_000_000_000_000_000_000", "-1_2_3",
             "18446744073709551615", "18446744073709551616", "-18446744073709551616", "123456789012345678901234567890",
             "ff", "FF", "zz", "Zz", "19", "0 1", "1 2"]
    bases = [0, 2, 8, 10, 16, 36, -8, -16, -1]
    flags = [7, 0, 1, 2, 4]
    texts.each do |text|
      bases.each do |base|
        flags.each do |flag|
          [-1, text.bytesize, [text.bytesize - 1, 0].max, 0, 1, 2].uniq.each do |len|
            [true, false].each do |with_endp|
              show([text, base, flag, len, with_endp]) { IntParse.parse(text, len, base, flag, with_endp) }
            end
          end
        end
      end
    end
    show(:radix_1) { IntParse.parse("1", -1, 1, 7, true) }
    show(:radix_37) { IntParse.parse("1", -1, 37, 7, true) }
    show(:radix_big) { IntParse.parse("1", -1, -40, 7, true) }
    show(:null) { IntParse.null }
    show(:flags) { IntParse.flags }
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("intparse", SOURCE)
  end

  def test_each_answer_is_rubys
    ruby, (plain,) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal ruby.stdout.lines.size, plain.stdout.lines.size, "zr stderr:\n#{plain.stderr}"
    ruby.stdout.lines.zip(plain.stdout.lines).each { |want, got| assert_equal want, got }
  end
end
