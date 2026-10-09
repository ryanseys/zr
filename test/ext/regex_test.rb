# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# Onigmo's regex API (onig_search, onig_match, OnigRegion and names) and
# the rest of what strscan's extension calls, each against ruby's answer.
class CExtRegexTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/re.h>
    #include <ruby/encoding.h>

    struct rx_args { long from; int raise; };

    static OnigPosition rx_search_fn(regex_t *reg, VALUE str, struct re_registers *regs, void *data) {
      struct rx_args *args = data;
      const UChar *s = (const UChar *)RSTRING_PTR(str), *e = s + RSTRING_LEN(str);
      if (args->raise) rb_raise(rb_eRuntimeError, "raised in the match function");
      return onig_search(reg, s, e, s + args->from, e, regs, ONIG_OPTION_NONE);
    }
    static OnigPosition rx_match_fn(regex_t *reg, VALUE str, struct re_registers *regs, void *data) {
      struct rx_args *args = data;
      const UChar *s = (const UChar *)RSTRING_PTR(str), *e = s + RSTRING_LEN(str);
      return onig_match(reg, s, e, s + args->from, regs, ONIG_OPTION_NONE);
    }
    static VALUE rx_groups(struct re_registers *regs) {
      VALUE out = rb_ary_new();
      for (int i = 0; i < regs->num_regs; i++)
        rb_ary_push(out, rb_assoc_new(LONG2NUM(regs->beg[i]), LONG2NUM(regs->end[i])));
      return out;
    }
    static VALUE rx_run(VALUE re, VALUE str, VALUE from, int search, int raise) {
      struct re_registers regs;
      struct rx_args args = { NUM2LONG(from), raise };
      onig_region_init(&regs);
      OnigPosition r = rb_reg_onig_match(re, str, search ? rx_search_fn : rx_match_fn, &args, &regs);
      VALUE out = rb_assoc_new(LONG2NUM(r), r >= 0 ? rx_groups(&regs) : Qnil);
      onig_region_free(&regs, 0);
      return out;
    }
    static VALUE rx_search(VALUE self, VALUE re, VALUE str, VALUE from) { return rx_run(re, str, from, 1, 0); }
    static VALUE rx_match(VALUE self, VALUE re, VALUE str, VALUE from) { return rx_run(re, str, from, 0, 0); }
    static VALUE rx_raising(VALUE self, VALUE re, VALUE str) { return rx_run(re, str, INT2FIX(0), 1, 1); }
    static VALUE rx_no_regs(VALUE self, VALUE re, VALUE str) {
      struct rx_args args = { 0, 0 };
      return LONG2NUM(rb_reg_onig_match(re, str, rx_search_fn, &args, NULL));
    }
    static VALUE rx_backref(VALUE self, VALUE re, VALUE str, VALUE name) {
      struct re_registers regs;
      struct rx_args args = { 0, 0 };
      onig_region_init(&regs);
      rb_reg_onig_match(re, str, rx_search_fn, &args, &regs);
      const UChar *n = (const UChar *)RSTRING_PTR(name);
      int with = onig_name_to_backref_number(RREGEXP_PTR(re), n, n + RSTRING_LEN(name), &regs);
      int without = onig_name_to_backref_number(RREGEXP_PTR(re), n, n + RSTRING_LEN(name), NULL);
      onig_region_free(&regs, 0);
      return rb_assoc_new(INT2FIX(with), INT2FIX(without));
    }
    static int rx_each_name(const UChar *name, const UChar *end, int n, int *groups, regex_t *reg, void *arg) {
      VALUE list = rb_ary_new();
      for (int i = 0; i < n; i++) rb_ary_push(list, INT2FIX(groups[i]));
      rb_ary_push((VALUE)arg, rb_assoc_new(rb_str_new((const char *)name, end - name), list));
      return 0;
    }
    static int rx_stop_second(const UChar *name, const UChar *end, int n, int *groups, regex_t *reg, void *arg) {
      return ++*(int *)arg == 2 ? 7 : 0;
    }
    static VALUE rx_names(VALUE self, VALUE re) {
      VALUE out = rb_ary_new();
      int seen = 0;
      int r = onig_foreach_name(RREGEXP_PTR(re), rx_each_name, (void *)out);
      int stopped = onig_foreach_name(RREGEXP_PTR(re), rx_stop_second, &seen);
      return rb_ary_new_from_args(4, out, INT2FIX(r), INT2FIX(stopped), INT2FIX(seen));
    }
    static VALUE rx_regions(VALUE self) {
      OnigRegion a, b;
      onig_region_init(&a);
      onig_region_init(&b);
      int set = onig_region_set(&a, 2, 5, 9);
      int bad = onig_region_set(&a, -1, 0, 0);
      int copied = rb_reg_region_copy(&b, &a);
      VALUE out = rb_ary_new_from_args(7, INT2FIX(set), INT2FIX(bad), INT2FIX(copied), INT2FIX(a.num_regs),
                                       INT2FIX(b.num_regs), LONG2NUM(b.beg[2]), LONG2NUM(b.end[2]));
      onig_region_clear(&b);
      rb_ary_push(out, rb_assoc_new(LONG2NUM(b.beg[2]), LONG2NUM(b.end[2])));
      onig_region_free(&a, 0);
      onig_region_free(&b, 0);
      rb_ary_push(out, INT2FIX(a.allocated + a.num_regs));
      OnigRegion *heap = onig_region_new();
      onig_region_resize(heap, 3);
      rb_ary_push(out, INT2FIX(heap->num_regs));
      onig_region_free(heap, 1);
      return out;
    }
    static VALUE rx_source(VALUE self, VALUE re) { return RREGEXP_SRC(re); }
    static VALUE rx_enc_raise(VALUE self, VALUE name) {
      rb_enc_raise(rb_enc_get(name), rb_eIndexError, "undefined group name reference: %.*s",
                   (int)RSTRING_LEN(name), RSTRING_PTR(name));
      return Qnil;
    }
    static VALUE rx_misc(VALUE self, VALUE klass, VALUE hashish) {
      rb_alias(klass, rb_intern("other_name"), rb_intern("name"));
      rb_deprecate_constant(klass, "OLD");
      return rb_ary_new_from_args(2, rb_check_hash_type(hashish), rb_str_dump(rb_str_new_cstr("a\tb\xe9")));
    }

    void Init_rx(void) {
      VALUE m = rb_define_module("Rx");
      rb_define_module_function(m, "search", rx_search, 3);
      rb_define_module_function(m, "match", rx_match, 3);
      rb_define_module_function(m, "raising", rx_raising, 2);
      rb_define_module_function(m, "no_regs", rx_no_regs, 2);
      rb_define_module_function(m, "backref", rx_backref, 3);
      rb_define_module_function(m, "names", rx_names, 1);
      rb_define_module_function(m, "regions", rx_regions, 0);
      rb_define_module_function(m, "source", rx_source, 1);
      rb_define_module_function(m, "enc_raise", rx_enc_raise, 1);
      rb_define_module_function(m, "misc", rx_misc, 2);
    }
  C

  PROGRAM = <<~'RUBY'
    require "rx"

    def show(label)
      p [label, yield]
    rescue StandardError => e
      p [label, e.class, e.message]
    end

    class Named
      OLD = 1
      def name = :named
    end
    class Hashish
      def to_hash = { k: 1 }
    end

    show(:search) { [Rx.search(/b(c)?/, "abcab", 0), Rx.search(/b(c)?/, "abcab", 2), Rx.search(/z/, "abc", 0)] }
    show(:match) { [Rx.match(/b(c)/, "abcab", 1), Rx.match(/b(c)/, "abcab", 0), Rx.match(/(?<x>a)|(?<y>b)/, "b", 0)] }
    show(:empty) { [Rx.search(//, "", 0), Rx.match(/\z/, "ab", 2)] }
    show(:encodings) do
      euc = "\xA4\xA2x".dup.force_encoding("EUC-JP")
      [Rx.search(/./, euc, 0), Rx.search(/x/, euc, 0), Rx.search(/./n, "\xff".b, 0), Rx.search(/é/, "café", 0)]
    end
    show(:incompatible) { Rx.search(/é/, "\xA4\xA2".dup.force_encoding("EUC-JP"), 0) }
    show(:broken) { Rx.search(/a/, "\xff".dup.force_encoding("UTF-8"), 0) }
    show(:raising) { Rx.raising(/a/, "a") }
    show(:no_regs) { [Rx.no_regs(/c/, "abc"), Rx.no_regs(/z/, "abc")] }
    show(:backref) do
      re = /(?<n>a)|(?<n>b)|(?<o>c)/
      [Rx.backref(re, "a", "n"), Rx.backref(re, "b", "n"), Rx.backref(re, "c", "o"), Rx.backref(re, "c", "none")]
    end
    show(:names) { [Rx.names(/(?<b>x)(?<a>y)(?<b>z)/), Rx.names(/plain/)] }
    show(:regions) { Rx.regions }
    show(:source) { [Rx.source(/a+b/i), Rx.source(Regexp.new("x.y"))] }
    show(:enc_raise) do
      Rx.enc_raise("nämë")
    rescue IndexError => e
      [e.message, e.message.encoding]
    end
    show(:misc) do
      r = Rx.misc(Named, Hashish.new)
      [r, Named.new.other_name, (Rx.misc(Named, 1) rescue $!.class), Named.deprecate_constant(:OLD) && :ok]
    end
    show(:gc) do
      res = 50.times.map { |i| Rx.search(Regexp.new("(\\d+)#{i}"), "x 12#{i} y", 0) }
      GC.start
      res.last
    end
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("rx", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
