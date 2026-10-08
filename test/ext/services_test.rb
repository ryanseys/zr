# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# What the top 9000 gems' extensions wait on next (`zr-dev ext rank`):
# ruby_qsort, rb_name_error, Ractor-local storage, the $DEBUG and
# $VERBOSE words, native locks, a stdio FILE for an IO, an IO on a
# descriptor, onig_new, and the process's script name, each against
# ruby's answer.
class CExtServicesTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/io.h>
    #include <ruby/re.h>
    #include <ruby/encoding.h>
    #include <ruby/ractor.h>
    #include <ruby/thread_native.h>
    #include <ruby/util.h>
    #include <stdio.h>
    #include <string.h>
    #include <unistd.h>

    /* Not in the public headers: the gems that call it declare it. */
    size_t rb_obj_memsize_of(VALUE obj);

    struct sv_row { int key; int tag; };

    static int sv_by_key(const void *a, const void *b, void *data) {
      (*(int *)data)++;
      return ((const struct sv_row *)a)->key - ((const struct sv_row *)b)->key;
    }
    static int sv_raising(const void *a, const void *b, void *data) {
      rb_raise(rb_eArgError, "no order here");
      return 0;
    }
    static VALUE sv_qsort(VALUE self, VALUE keys, VALUE raise) {
      long n = RARRAY_LEN(keys);
      struct sv_row *rows = ALLOCA_N(struct sv_row, n);
      int calls = 0;
      for (long i = 0; i < n; i++) { rows[i].key = NUM2INT(RARRAY_AREF(keys, i)); rows[i].tag = (int)i; }
      ruby_qsort(rows, n, sizeof(*rows), RTEST(raise) ? sv_raising : sv_by_key, &calls);
      VALUE out = rb_ary_new();
      for (long i = 0; i < n; i++) rb_ary_push(out, rb_assoc_new(INT2FIX(rows[i].key), INT2FIX(rows[i].tag)));
      return out;
    }
    static VALUE sv_name_error(VALUE self, VALUE name) {
      rb_name_error(rb_intern_str(name), "no thing named %"PRIsVALUE" (%d)", name, 7);
      return Qnil;
    }

    static rb_ractor_local_key_t sv_key;
    static VALUE sv_local(VALUE self, VALUE v, VALUE set) {
      VALUE before = Qundef, found;
      int had = rb_ractor_local_storage_value_lookup(sv_key, &before);
      if (RTEST(set)) rb_ractor_local_storage_value_set(sv_key, v);
      found = rb_ractor_local_storage_value(sv_key);
      return rb_ary_new_from_args(3, had ? Qtrue : Qfalse, had ? before : Qnil, found);
    }
    static VALUE sv_flags(VALUE self) {
      return rb_assoc_new(*rb_ruby_debug_ptr(), *rb_ruby_verbose_ptr());
    }
    static VALUE sv_lock(VALUE self) {
      rb_nativethread_lock_t lock;
      rb_nativethread_lock_initialize(&lock);
      rb_nativethread_lock_lock(&lock);
      rb_nativethread_lock_unlock(&lock);
      rb_nativethread_lock_destroy(&lock);
      return ID2SYM(rb_intern("locked_and_unlocked"));
    }
    static VALUE sv_stdio(VALUE self, VALUE io, VALUE text) {
      rb_io_t *fptr;
      GetOpenFile(io, fptr);
      FILE *f = rb_io_stdio_file(fptr);
      fputs(StringValueCStr(text), f);
      fflush(f);
      return rb_io_stdio_file(fptr) == f ? Qtrue : Qfalse;
    }
    static VALUE sv_descriptor(VALUE self, VALUE klass, VALUE io, VALUE path) {
      struct rb_io_encoding enc = { rb_utf8_encoding(), NULL, 0, Qnil };
      int fd = dup(rb_io_descriptor(io));
      return rb_io_open_descriptor(klass, fd, FMODE_READABLE, path, Qnil, &enc);
    }
    static VALUE sv_onig(VALUE self, VALUE pattern, VALUE text) {
      regex_t *reg;
      OnigErrorInfo einfo;
      const UChar *p = (const UChar *)RSTRING_PTR(pattern);
      int r = onig_new(&reg, p, p + RSTRING_LEN(pattern), ONIG_OPTION_IGNORECASE, ONIG_ENCODING_ASCII, ONIG_SYNTAX_DEFAULT, &einfo);
      if (r != ONIG_NORMAL) {
        char s[ONIG_MAX_ERROR_MESSAGE_LEN];
        int n = onig_error_code_to_str((UChar *)s, r, &einfo);
        return rb_ary_new_from_args(3, INT2FIX(r), rb_str_new(s, n), INT2FIX(n == (int)strlen(s)));
      }
      OnigRegion *region = onig_region_new();
      const UChar *s = (const UChar *)RSTRING_PTR(text), *e = s + RSTRING_LEN(text);
      long at = onig_search(reg, s, e, s, e, region, ONIG_OPTION_NONE);
      VALUE out = rb_ary_new_from_args(3, LONG2NUM(at), LONG2NUM(region->beg[1]), LONG2NUM(region->end[2]));
      onig_region_free(region, 1);
      onig_free(reg);
      return out;
    }
    static VALUE sv_memsize(VALUE self, VALUE obj) { return rb_obj_memsize_of(obj) > 0 ? Qtrue : Qfalse; }
    static VALUE sv_script(VALUE self, VALUE name) { ruby_script(StringValueCStr(name)); return Qnil; }
    static VALUE sv_backtrace(VALUE self) { rb_backtrace(); return Qnil; }

    void Init_services(void) {
      VALUE m = rb_define_module("Services");
      sv_key = rb_ractor_local_storage_value_newkey();
      rb_define_module_function(m, "qsort", sv_qsort, 2);
      rb_define_module_function(m, "name_error", sv_name_error, 1);
      rb_define_module_function(m, "local", sv_local, 2);
      rb_define_module_function(m, "flags", sv_flags, 0);
      rb_define_module_function(m, "lock", sv_lock, 0);
      rb_define_module_function(m, "stdio", sv_stdio, 2);
      rb_define_module_function(m, "descriptor", sv_descriptor, 3);
      rb_define_module_function(m, "onig", sv_onig, 2);
      rb_define_module_function(m, "memsize", sv_memsize, 1);
      rb_define_module_function(m, "script", sv_script, 1);
      rb_define_module_function(m, "backtrace", sv_backtrace, 0);
    }
  C

  PROGRAM = <<~'RUBY'
    require "services"

    def show(label)
      p [label, yield]
    rescue StandardError => e
      p [label, e.class, e.message]
    end

    class Picky < IO
      def initialize(*) = raise("initialize ran")
    end

    keys = [5, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3, 2, 3, 8, 4, 6, 2, 6, 4, 3, 3, 8, 3, 2, 7, 9, 5]
    show(:qsort) { Services.qsort(keys, false) }
    show(:qsort_empty) { Services.qsort([], false) }
    show(:qsort_raising) { Services.qsort([2, 1], true) }
    show(:name_error) do
      Services.name_error("widget")
    rescue NameError => e
      [e.class, e.message, e.name]
    end
    show(:local) { [Services.local(nil, false), Services.local(nil, true), Services.local(5, true), Services.local(:x, false)] }
    show(:flags) do
      before = Services.flags
      $DEBUG = true
      $VERBOSE = nil
      after = Services.flags
      $DEBUG = false
      $VERBOSE = false
      [before, after]
    end
    show(:lock) { Services.lock }
    show(:stdio) do
      r, w = IO.pipe
      same = Services.stdio(w, "through a FILE")
      w.close
      [same, r.read]
    end
    show(:descriptor) do
      r, w = IO.pipe
      w.write("abc")
      w.close
      io = Services.descriptor(Picky, r, "pipe-end")
      [io.class, io.path, io.external_encoding, io.read, (io.write("x") rescue $!.class)]
    end
    show(:onig) { [Services.onig("(\\d+)-(\\d+)", "AB 12-34"), Services.onig("ab(", "x")] }
    show(:memsize) { Services.memsize("x" * 100) }
    show(:script) { Services.script("renamed"); $0 }
    show(:backtrace) { Services.backtrace }
    show(:gc) { 20.times.map { Services.qsort([3, 1, 2], false) }.uniq }
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("services", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
