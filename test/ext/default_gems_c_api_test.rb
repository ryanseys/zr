# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API that the own C of zlib, etc, io/console and digest calls:
# the transcoder (rb_econv_*), rb_str_conv_enc_opts, the String helpers,
# rb_check_funcall, rb_check_id, the IO helpers, and
# rb_ext_resolve_symbol, each against ruby's answer.
class CExtDefaultGemsCApiTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/encoding.h>
    #include <ruby/io.h>

    static VALUE g_econv(VALUE self, VALUE from, VALUE to, VALUE input, VALUE room, VALUE opts) {
      VALUE ecopts;
      int flags = rb_econv_prepare_opts(opts, &ecopts);
      rb_econv_t *ec = rb_econv_open_opts(StringValueCStr(from), StringValueCStr(to), flags, ecopts);
      if (!ec) return Qnil;
      VALUE out = rb_ary_new();
      const unsigned char *sp = (const unsigned char *)RSTRING_PTR(input);
      const unsigned char *se = sp + RSTRING_LEN(input);
      for (int i = 0; i < 8; i++) {
        unsigned char buf[64];
        unsigned char *dp = buf;
        long size = NUM2LONG(room);
        rb_econv_result_t r = rb_econv_convert(ec, &sp, se, &dp, buf + size, 0);
        rb_ary_push(out, rb_ary_new_from_args(3, INT2FIX(r), LONG2NUM(se - sp), rb_str_new((char *)buf, dp - buf)));
        if (r != econv_destination_buffer_full) break;
      }
      rb_econv_close(ec);
      return out;
    }
    static VALUE check_error_of(VALUE ec) { rb_econv_check_error((rb_econv_t *)ec); return Qnil; }
    static VALUE g_check_error(VALUE self, VALUE input) {
      rb_econv_t *ec = rb_econv_open_opts("UTF-8", "EUC-JP", 0, Qnil);
      const unsigned char *sp = (const unsigned char *)RSTRING_PTR(input);
      unsigned char buf[64], *dp = buf;
      rb_econv_convert(ec, &sp, sp + RSTRING_LEN(input), &dp, buf + 64, 0);
      int state = 0;
      rb_protect(check_error_of, (VALUE)ec, &state);
      VALUE err = rb_errinfo();
      rb_set_errinfo(Qnil);
      rb_econv_close(ec);
      return state ? rb_obj_class(err) : Qnil;
    }
    static VALUE g_str_convert(VALUE self, VALUE str) {
      rb_econv_t *ec = rb_econv_open_opts("UTF-8", "UTF-16LE", 0, Qnil);
      VALUE out = rb_econv_str_convert(ec, str, ECONV_PARTIAL_INPUT);
      rb_econv_close(ec);
      return out;
    }
    static VALUE g_conv_enc(VALUE self, VALUE str, VALUE to) {
      return rb_str_conv_enc_opts(str, NULL, rb_to_encoding(to), 0, Qnil);
    }
    static VALUE g_strings(VALUE self, VALUE str) {
      VALUE copy = rb_str_resurrect(str);
      rb_str_locktmp(copy);
      int locked = rb_protect((VALUE (*)(VALUE))rb_str_resize, copy, NULL) == Qnil;
      rb_set_errinfo(Qnil);
      rb_str_unlocktmp(copy);
      VALUE interned = rb_interned_str_cstr("hi");
      return rb_ary_new_from_args(8, rb_str_inspect(str), copy, rb_obj_frozen_p(copy), INT2FIX(locked),
                                  interned, rb_obj_frozen_p(interned), rb_obj_encoding(interned),
                                  rb_obj_encoding(rb_locale_str_new_cstr("x")));
    }
    static VALUE g_fs(VALUE self) {
      VALUE a = rb_filesystem_str_new("ab", 2), b = rb_filesystem_str_new_cstr("cd");
      return rb_ary_new_from_args(3, a, b, rb_obj_encoding(a) == rb_obj_encoding(b) ? Qtrue : Qfalse);
    }
    static VALUE g_check_funcall(VALUE self, VALUE recv, VALUE name) {
      VALUE r = rb_check_funcall(recv, rb_to_id(name), 0, NULL);
      return r == Qundef ? ID2SYM(rb_intern("undef")) : r;
    }
    static VALUE g_check_id(VALUE self, VALUE name) {
      ID id = rb_check_id(&name);
      return rb_assoc_new(id ? ID2SYM(id) : Qnil, name);
    }
    static VALUE g_io(VALUE self, VALUE io) {
      rb_io_t *fptr;
      GetOpenFile(io, fptr);
      return rb_ary_new_from_args(3, rb_io_closed_p(io), INT2FIX(rb_io_read_pending(fptr)), rb_io_get_write_io(io) == io ? Qtrue : Qfalse);
    }
    static VALUE g_encoding_option(VALUE self, VALUE opts) {
      rb_encoding *enc = NULL, *enc2 = NULL;
      int found = rb_io_extract_encoding_option(opts, &enc, &enc2, NULL);
      return rb_ary_new_from_args(3, INT2FIX(found), enc ? rb_enc_from_encoding(enc) : Qnil, enc2 ? rb_enc_from_encoding(enc2) : Qnil);
    }
    VALUE defaultgems_marker(void) { return INT2FIX(42); }
    static VALUE g_resolve(VALUE self) {
      VALUE (*f)(void) = (VALUE (*)(void))rb_ext_resolve_symbol("defaultgems.so", "defaultgems_marker");
      return f ? f() : Qnil;
    }
    static VALUE g_obj_reveal(VALUE self) {
      VALUE s = rb_str_new_cstr("x");
      rb_obj_hide(s);
      rb_obj_reveal(s, rb_cString);
      return rb_obj_class(s);
    }

    void Init_defaultgems(void) {
      VALUE m = rb_define_module("DefaultGems");
      rb_define_module_function(m, "econv", g_econv, 5);
      rb_define_module_function(m, "check_error", g_check_error, 1);
      rb_define_module_function(m, "str_convert", g_str_convert, 1);
      rb_define_module_function(m, "conv_enc", g_conv_enc, 2);
      rb_define_module_function(m, "strings", g_strings, 1);
      rb_define_module_function(m, "fs", g_fs, 0);
      rb_define_module_function(m, "check_funcall", g_check_funcall, 2);
      rb_define_module_function(m, "check_id", g_check_id, 1);
      rb_define_module_function(m, "io", g_io, 1);
      rb_define_module_function(m, "encoding_option", g_encoding_option, 1);
      rb_define_module_function(m, "resolve", g_resolve, 0);
      rb_define_module_function(m, "obj_reveal", g_obj_reveal, 0);
    }
  C

  PROGRAM = <<~'RUBY'
    require "defaultgems"

    p DefaultGems.econv("UTF-8", "EUC-JP", "café あい", 64, nil)
    p DefaultGems.econv("UTF-8", "UTF-16BE", "abcdefgh", 4, nil)
    p DefaultGems.econv("UTF-8", "US-ASCII", "aéb", 64, { undef: :replace, replace: "?" })
    p DefaultGems.econv("UTF-8", "US-ASCII", "a\xffb".b, 64, { invalid: :replace })
    p DefaultGems.econv("UTF-8", "NOPE-NOT-ONE", "a", 8, nil)
    p DefaultGems.check_error("ok"), DefaultGems.check_error("bad \xff".b), DefaultGems.check_error("\u{1F600}")
    p DefaultGems.str_convert("hé")
    p DefaultGems.conv_enc("café", "ISO-8859-1"), DefaultGems.conv_enc("abc", "UTF-16LE").encoding
    p DefaultGems.conv_enc("ascii", "Windows-1252").encoding, DefaultGems.conv_enc("あ", "US-ASCII")
    p DefaultGems.strings("a\"b\né")
    p DefaultGems.fs
    p DefaultGems.check_funcall("abc", "upcase"), DefaultGems.check_funcall(1, "no_such_method_here")
    o = Object.new
    def o.respond_to_missing?(name, priv) = name == :ghost
    def o.method_missing(name, *) = name == :ghost ? :boo : super
    p DefaultGems.check_funcall(o, "ghost")
    p DefaultGems.check_id(:inspect), DefaultGems.check_id("inspect"), DefaultGems.check_id("never_interned_#{rand(10**12)}")[0]
    begin
      DefaultGems.check_id(12)
    rescue TypeError => e
      p e.message
    end
    r, w = IO.pipe
    w.write("hello\nworld\n")
    r.gets
    p DefaultGems.io(r), DefaultGems.io(w)
    r.close
    w.close
    p DefaultGems.encoding_option(nil), DefaultGems.encoding_option({}), DefaultGems.encoding_option({ encoding: "EUC-JP" })
    p DefaultGems.encoding_option({ encoding: "EUC-JP:UTF-8" }), DefaultGems.encoding_option({ external_encoding: "UTF-16LE" })
    p DefaultGems.encoding_option({ external_encoding: "EUC-JP", internal_encoding: "UTF-8" })
    p DefaultGems.encoding_option({ internal_encoding: nil }), DefaultGems.encoding_option({ external_encoding: "BINARY", internal_encoding: "UTF-8" })
    p DefaultGems.resolve, DefaultGems.obj_reveal
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("defaultgems", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain,) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
  end
end
