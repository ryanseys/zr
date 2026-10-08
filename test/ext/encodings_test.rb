# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# An rb_encoding's functions, which CRuby's inline encoding functions call
# through the struct (rb_enc_mbcput, rb_enc_isspace...), and the exported
# functions over them, which cgi, oj and nokogiri call, each against
# ruby's answer in several encodings.
class CExtEncodingsTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/encoding.h>

    static rb_encoding *enc_of(VALUE name) { return rb_enc_find(StringValueCStr(name)); }

    static VALUE e_put(VALUE self, VALUE name, VALUE code) {
      rb_encoding *enc = enc_of(name);
      char buf[16];
      int n = rb_enc_mbcput(NUM2UINT(code), buf, enc);
      return rb_ary_new_from_args(3, rb_enc_str_new(buf, n, enc), INT2FIX(n), INT2FIX(rb_enc_codelen(NUM2INT(code), enc)));
    }
    static VALUE e_codes(VALUE self, VALUE str) {
      rb_encoding *enc = rb_enc_get(str);
      const char *p = RSTRING_PTR(str), *e = RSTRING_END(str);
      VALUE out = rb_ary_new();
      while (p < e) {
        int n = rb_enc_mbclen(p, e, enc);
        rb_ary_push(out, rb_ary_new_from_args(3, UINT2NUM(rb_enc_mbc_to_codepoint(p, e, enc)), INT2FIX(n),
                                              INT2FIX(rb_enc_precise_mbclen(p, e, enc))));
        p += n;
      }
      return out;
    }
    static VALUE e_precise(VALUE self, VALUE str, VALUE len) {
      const char *p = RSTRING_PTR(str);
      return INT2FIX(rb_enc_precise_mbclen(p, p + NUM2LONG(len), rb_enc_get(str)));
    }
    static VALUE e_ctypes(VALUE self, VALUE name, VALUE code) {
      rb_encoding *enc = enc_of(name);
      unsigned int c = NUM2UINT(code);
      VALUE out = rb_ary_new();
      rb_ary_push(out, INT2FIX(rb_enc_isspace(c, enc)));
      rb_ary_push(out, INT2FIX(rb_enc_isalpha(c, enc)));
      rb_ary_push(out, INT2FIX(rb_enc_isdigit(c, enc)));
      rb_ary_push(out, INT2FIX(rb_enc_isalnum(c, enc)));
      rb_ary_push(out, INT2FIX(rb_enc_isupper(c, enc)));
      rb_ary_push(out, INT2FIX(rb_enc_islower(c, enc)));
      rb_ary_push(out, INT2FIX(rb_enc_ispunct(c, enc)));
      rb_ary_push(out, INT2FIX(rb_enc_isprint(c, enc)));
      rb_ary_push(out, INT2FIX(rb_enc_isascii(c, enc)));
      rb_ary_push(out, INT2FIX(rb_enc_toupper(c, enc)));
      rb_ary_push(out, INT2FIX(rb_enc_tolower(c, enc)));
      return out;
    }
    static VALUE e_head(VALUE self, VALUE str, VALUE at) {
      const char *s = RSTRING_PTR(str);
      const char *h = rb_enc_left_char_head(s, s + NUM2LONG(at), RSTRING_END(str), rb_enc_get(str));
      return LONG2NUM(h - s);
    }
    static VALUE e_newline(VALUE self, VALUE str) {
      return INT2FIX(rb_enc_is_newline(RSTRING_PTR(str), RSTRING_END(str), rb_enc_get(str)));
    }
    static VALUE e_ascget(VALUE self, VALUE str) {
      int len = 99;
      int c = rb_enc_ascget(RSTRING_PTR(str), RSTRING_END(str), &len, rb_enc_get(str));
      return rb_assoc_new(INT2FIX(c), INT2FIX(c < 0 ? 99 : len));
    }
    static VALUE e_flags(VALUE self, VALUE name) {
      rb_encoding *enc = enc_of(name);
      return rb_ary_new_from_args(4, INT2FIX(rb_enc_unicode_p(enc)), INT2FIX(rb_enc_asciicompat(enc)),
                                  INT2FIX(rb_enc_mbminlen(enc)), INT2FIX(rb_enc_mbmaxlen(enc)));
    }
    static VALUE e_chr(VALUE self, VALUE name, VALUE code) { return rb_enc_uint_chr(NUM2UINT(code), enc_of(name)); }

    void Init_encs(void) {
      VALUE m = rb_define_module("Encs");
      rb_define_module_function(m, "put", e_put, 2);
      rb_define_module_function(m, "codes", e_codes, 1);
      rb_define_module_function(m, "precise", e_precise, 2);
      rb_define_module_function(m, "ctypes", e_ctypes, 2);
      rb_define_module_function(m, "head", e_head, 2);
      rb_define_module_function(m, "newline", e_newline, 1);
      rb_define_module_function(m, "ascget", e_ascget, 1);
      rb_define_module_function(m, "flags", e_flags, 1);
      rb_define_module_function(m, "chr", e_chr, 2);
    }
  C

  PROGRAM = <<~'RUBY'
    require "encs"

    def show(label)
      p [label, yield]
    rescue => e
      p [label, e.class, e.message]
    end

    NAMES = %w[UTF-8 ISO-8859-1 US-ASCII ASCII-8BIT EUC-JP Shift_JIS UTF-16LE UTF-16BE UTF-32LE GB18030 Windows-1252]
    show(:put_ascii) { NAMES.map { |n| Encs.put(n, 65) } }
    show(:put_utf8) { [0xE9, 0x20AC, 0x1F600, 0x7FF, 0x800].map { |c| Encs.put("UTF-8", c) } }
    show(:put_wide) { [Encs.put("UTF-16LE", 0x1F600), Encs.put("UTF-16BE", 0xE9), Encs.put("UTF-32LE", 0x20AC)] }
    show(:put_single) { [Encs.put("ISO-8859-1", 0xE9), Encs.put("Windows-1252", 0x80)] }
    show(:put_mb) { [Encs.put("EUC-JP", 0xA4A2), Encs.put("Shift_JIS", 0x82A0)] }
    show(:codes) do
      ["héllo €😀", "あい".encode("EUC-JP"), "あい".encode("Shift_JIS"), "h€".encode("UTF-16LE"), "\xE9t\xE9".b.force_encoding("ISO-8859-1"),
       "ok\xFFx".dup.force_encoding("UTF-8"), "€".encode("GB18030")].map { |s| Encs.codes(s) }
    end
    show(:precise) { s = "😀"; [Encs.precise(s, 4), Encs.precise(s, 2), Encs.precise(s, 0), Encs.precise("\xFF".dup.force_encoding("UTF-8"), 1)] }
    show(:ctypes) do
      [[" ", 32], ["A", 65], ["a", 97], ["7", 55], ["!", 33], ["\t", 9]].map { |_, c| Encs.ctypes("UTF-8", c) } +
        [Encs.ctypes("UTF-8", 0xE9), Encs.ctypes("UTF-8", 0xA0), Encs.ctypes("US-ASCII", 0x41)]
    end
    show(:head) { s = "aé😀b"; (0...s.bytesize).map { |i| Encs.head(s, i) } }
    show(:head_mb) { s = "aあb".encode("Shift_JIS"); (0...s.bytesize).map { |i| Encs.head(s, i) } }
    show(:newline) { [Encs.newline("\nx"), Encs.newline("x\n"), Encs.newline("\n".encode("UTF-16LE"))] }
    show(:ascget) { ["a", "é", "", "a".encode("UTF-16LE"), "é".encode("UTF-16LE")].map { |s| Encs.ascget(s) } }
    show(:flags) { NAMES.map { |n| Encs.flags(n) } }
    show(:chr) { [Encs.chr("UTF-8", 0xE9), Encs.chr("ISO-8859-1", 0xE9), Encs.chr("EUC-JP", 0xA4A2)] }
    show(:chr_bad) { Encs.chr("US-ASCII", 200) }
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("encs", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain,) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
  end
end
