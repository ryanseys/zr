# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API that json's and stringio's own extensions call (catch and
# throw, formatted appends, an open's mode and encodings, `$_` and `$~`),
# and st tables of C strings and of C's own types, each against ruby's
# answer.
class CExtStdlibCApiTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/encoding.h>
    #include <ruby/io.h>
    #include <ruby/st.h>
    #include <fcntl.h>
    #include <string.h>

    static VALUE caught_i(RB_BLOCK_CALL_FUNC_ARGLIST(tag, data)) {
      if (RTEST(data)) rb_throw_obj(tag, rb_str_new_cstr("thrown"));
      return rb_str_new_cstr("fell through");
    }
    static VALUE s_catch(VALUE self, VALUE throwing) {
      VALUE tag = rb_obj_alloc(rb_cObject);
      return rb_catch_obj(tag, caught_i, throwing);
    }
    static VALUE s_catch_name(VALUE self) { return rb_catch("named", caught_i, Qtrue); }
    static VALUE s_throw_uncaught(VALUE self) { rb_throw("nowhere", Qnil); return Qnil; }

    static VALUE s_formats(VALUE self) {
      VALUE s = rb_str_new_cstr("n=");
      rb_str_catf(s, "%d and %s", 42, "text");
      VALUE e = rb_enc_sprintf(rb_usascii_encoding(), "<%ld>", 7L);
      rb_str_buf_cat_ascii(s, "!");
      return rb_ary_new_from_args(3, s, e, rb_obj_encoding(e));
    }
    static VALUE s_strings(VALUE self, VALUE str) {
      VALUE shared = rb_str_new_shared(str);
      VALUE interned = rb_str_to_interned_str(rb_str_new_cstr("same"));
      VALUE again = rb_str_to_interned_str(rb_str_new_cstr("same"));
      VALUE copy = rb_str_new_cstr("abc");
      rb_enc_copy(copy, rb_str_export_to_enc(rb_str_new_cstr("x"), rb_enc_find("ISO-8859-1")));
      return rb_ary_new_from_args(6, shared, shared == str ? Qtrue : Qfalse, rb_obj_frozen_p(interned),
                                  interned == again ? Qtrue : Qfalse, rb_obj_encoding(copy),
                                  rb_enc_from_encoding(rb_find_encoding(rb_str_new_cstr("euc-jp"))));
    }
    static VALUE s_find_none(VALUE self) { return rb_find_encoding(rb_str_new_cstr("no-such")) == NULL ? Qtrue : Qfalse; }
    static VALUE s_path(VALUE self, VALUE path) { return rb_path_to_class(path); }

    static VALUE s_modeenc(VALUE self, VALUE vmode, VALUE opt) {
      int oflags = -1, fmode = -1;
      rb_io_enc_t conv;
      rb_io_extract_modeenc(&vmode, 0, opt, &oflags, &fmode, &conv);
      return rb_ary_new_from_args(6, vmode, INT2FIX(oflags & 3), INT2FIX(fmode & 0xfff),
                                  conv.enc ? rb_enc_from_encoding(conv.enc) : Qnil,
                                  conv.enc2 ? rb_enc_from_encoding(conv.enc2) : Qnil, INT2FIX((oflags & O_TRUNC) != 0));
    }
    static VALUE s_lastline(VALUE self, VALUE line) {
      VALUE before = rb_lastline_get();
      rb_lastline_set(line);
      return before;
    }
    static VALUE s_backref(VALUE self) { return rb_backref_get(); }
    static VALUE s_rs(VALUE self) { return rb_ary_new_from_args(3, rb_rs, rb_default_rs, rb_output_fs); }

    static int each_pair(st_data_t key, st_data_t value, st_data_t out) {
      rb_ary_push((VALUE)out, rb_assoc_new(rb_str_new_cstr((const char *)key), INT2FIX(value)));
      return ST_CONTINUE;
    }
    static int mod_compare(st_data_t a, st_data_t b) { return (a % 10) != (b % 10); }
    static st_index_t mod_hash(st_data_t a) { return a % 10; }
    static const struct st_hash_type mod_type = { mod_compare, mod_hash };
    static VALUE s_tables(VALUE self) {
      char one[] = "one", two[] = "two", other_one[] = "one";
      st_table *t = st_init_strtable();
      st_insert(t, (st_data_t)one, 1);
      st_insert(t, (st_data_t)two, 2);
      st_insert(t, (st_data_t)other_one, 11);
      st_data_t got = 0;
      int found = st_lookup(t, (st_data_t)"two", &got);
      VALUE rows = rb_ary_new();
      st_foreach(t, each_pair, (st_data_t)rows);
      st_table *c = st_init_strcasetable();
      st_insert(c, (st_data_t)"Key", 5);
      st_data_t folded = 0;
      int casefound = st_lookup(c, (st_data_t)"kEY", &folded);
      st_table *m = st_init_table(&mod_type);
      st_insert(m, 13, 1);
      st_insert(m, 23, 2);
      st_data_t modded = 0;
      int modfound = st_lookup(m, 33, &modded);
      st_table *copy = st_copy(t);
      VALUE out = rb_ary_new_from_args(8, INT2FIX(found), INT2FIX(got), rows, INT2FIX(casefound), INT2FIX(folded),
                                       INT2FIX(modfound), INT2FIX(modded), SIZET2NUM(copy->num_entries));
      st_free_table(t);
      st_free_table(c);
      st_free_table(m);
      st_free_table(copy);
      return out;
    }

    void Init_stdlibc(void) {
      VALUE m = rb_define_module("StdlibC");
      rb_define_module_function(m, "catch", s_catch, 1);
      rb_define_module_function(m, "catch_name", s_catch_name, 0);
      rb_define_module_function(m, "throw_uncaught", s_throw_uncaught, 0);
      rb_define_module_function(m, "formats", s_formats, 0);
      rb_define_module_function(m, "strings", s_strings, 1);
      rb_define_module_function(m, "find_none", s_find_none, 0);
      rb_define_module_function(m, "path", s_path, 1);
      rb_define_module_function(m, "modeenc", s_modeenc, 2);
      rb_define_module_function(m, "lastline", s_lastline, 1);
      rb_define_module_function(m, "backref", s_backref, 0);
      rb_define_module_function(m, "rs", s_rs, 0);
      rb_define_module_function(m, "tables", s_tables, 0);
    }
  C

  PROGRAM = <<~'RUBY'
    require "stdlibc"

    def show(label)
      p [label, yield]
    rescue StandardError, ScriptError => e
      p [label, e.class, e.message]
    end

    module Outer
      class Inner; end
    end

    show(:catch) { [StdlibC.catch(true), StdlibC.catch(false), StdlibC.catch_name] }
    show(:throw_uncaught) { StdlibC.throw_uncaught }
    show(:formats) { StdlibC.formats }
    show(:strings) { StdlibC.strings("shared") }
    show(:find_none) { StdlibC.find_none }
    show(:path) { [StdlibC.path("Outer::Inner"), StdlibC.path("Comparable")] }
    show(:path_bad) { StdlibC.path("Outer::Nope") }
    show(:modeenc) do
      [StdlibC.modeenc(nil, nil), StdlibC.modeenc("r+", nil), StdlibC.modeenc("w:iso-8859-1", nil),
       StdlibC.modeenc("a", nil), StdlibC.modeenc(nil, { mode: "rb" }), StdlibC.modeenc("r:euc-jp:utf-8", nil),
       StdlibC.modeenc(nil, { encoding: "UTF-16LE", binmode: true }), StdlibC.modeenc(File::RDWR, nil)]
    end
    show(:modeenc_twice) { StdlibC.modeenc("r", { mode: "w" }) }
    show(:lastline) do
      $_ = "before"
      was = StdlibC.lastline("after")
      [was, $_]
    end
    show(:backref) { "hello" =~ /l+/; StdlibC.backref[0] }
    show(:rs) { a = StdlibC.rs; $/ = "x"; b = StdlibC.rs; $/ = "\n"; [a, b] }
    show(:tables) { StdlibC.tables }
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("stdlibc", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
