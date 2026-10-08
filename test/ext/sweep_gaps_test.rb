# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API functions that the gem sweep found that zr lacked, each as
# the gems use it (pg, sqlite3, gherkin, mini_racer), against ruby's
# answers: rb_ary_delete, rb_funcall_with_block(_kw),
# rb_copy_generic_ivar, rb_gc_adjust_memory_usage, rb_locale_encindex,
# rb_absint_numwords, rb_str_encode_ospath and
# rb_thread_lock_native_thread.
class CExtSweepGapsTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/encoding.h>
    #include <ruby/thread.h>

    static VALUE g_delete(VALUE self, VALUE ary, VALUE item) { return rb_ary_delete(ary, item); }

    static VALUE g_with_block(VALUE self, VALUE recv, VALUE name, VALUE args, VALUE block) {
      return rb_funcall_with_block(recv, rb_to_id(name), (int)RARRAY_LEN(args), RARRAY_CONST_PTR(args), block);
    }

    static VALUE g_with_block_kw(VALUE self, VALUE recv, VALUE name, VALUE args, VALUE block) {
      return rb_funcall_with_block_kw(recv, rb_to_id(name), (int)RARRAY_LEN(args), RARRAY_CONST_PTR(args), block, RB_PASS_KEYWORDS);
    }

    static VALUE g_copy_ivars(VALUE self, VALUE dest, VALUE obj) {
      rb_copy_generic_ivar(dest, obj);
      return dest;
    }

    static VALUE g_hidden(VALUE self, VALUE obj) { return rb_attr_get(obj, rb_intern("hidden")); }
    static VALUE g_hide(VALUE self, VALUE obj, VALUE v) { return rb_ivar_set(obj, rb_intern("hidden"), v); }

    static VALUE g_adjust(VALUE self, VALUE diff) {
      rb_gc_adjust_memory_usage(NUM2LONG(diff));
      return Qtrue;
    }

    static VALUE g_locale(VALUE self) {
      return rb_ary_new_from_args(2, INT2NUM(rb_locale_encindex() == rb_enc_to_index(rb_locale_encoding())),
                                  rb_enc_from_encoding(rb_enc_from_index(rb_locale_encindex())));
    }

    static VALUE g_numwords(VALUE self, VALUE v, VALUE bits) {
      size_t nlz = 99;
      size_t words = rb_absint_numwords(v, NUM2SIZET(bits), &nlz);
      return rb_ary_new_from_args(2, words == (size_t)-1 ? INT2NUM(-1) : SIZET2NUM(words), SIZET2NUM(nlz));
    }

    static VALUE g_ospath(VALUE self, VALUE path) {
      VALUE out = rb_str_encode_ospath(path);
      return rb_ary_new_from_args(3, out, rb_obj_encoding(out), out == path ? Qtrue : Qfalse);
    }

    static VALUE g_lock(VALUE self) { return rb_thread_lock_native_thread() ? Qtrue : Qfalse; }

    void Init_gaps(void) {
      VALUE m = rb_define_module("Gaps");
      rb_define_module_function(m, "delete", g_delete, 2);
      rb_define_module_function(m, "with_block", g_with_block, 4);
      rb_define_module_function(m, "with_block_kw", g_with_block_kw, 4);
      rb_define_module_function(m, "copy_ivars", g_copy_ivars, 2);
      rb_define_module_function(m, "hidden", g_hidden, 1);
      rb_define_module_function(m, "hide", g_hide, 2);
      rb_define_module_function(m, "adjust", g_adjust, 1);
      rb_define_module_function(m, "locale", g_locale, 0);
      rb_define_module_function(m, "numwords", g_numwords, 2);
      rb_define_module_function(m, "ospath", g_ospath, 1);
      rb_define_module_function(m, "lock", g_lock, 0);
    }
  C

  PROGRAM = <<~'RUBY'
    require "gaps"

    def show(label)
      p [label, yield]
    rescue StandardError => e
      p [label, e.class, e.message]
    end

    class Keeper
      def pick(a, b = 0, scale: 1) = yield((a + b) * scale)

      private def secret = :hidden
    end

    show(:delete) { a = [1, 2, 1, 3]; [Gaps.delete(a, 1), a] }
    show(:delete_none) { a = [1]; [Gaps.delete(a, 9), a] }
    show(:delete_frozen) { Gaps.delete([1].freeze, 1) }
    show(:with_block) { Gaps.with_block(Keeper.new, :pick, [2, 3], proc { |v| v * 10 }) }
    show(:with_no_block) { Gaps.with_block([3, 1, 2], :sort, [], nil) }
    show(:with_block_kw) { Gaps.with_block_kw(Keeper.new, :pick, [2, { scale: 3 }], proc { |v| v + 1 }) }
    show(:with_block_private) { Gaps.with_block(Keeper.new, :secret, [], nil) }

    source = +"text"
    source.instance_variable_set(:@a, 1)
    source.instance_variable_set(:@b, [2])
    Gaps.hide(source, :kept)
    show(:copy) do
      copy = Gaps.copy_ivars(+"copy", source)
      [copy.instance_variables, copy.instance_variable_get(:@b).equal?(source.instance_variable_get(:@b)), Gaps.hidden(copy)]
    end
    show(:copy_none) { Gaps.copy_ivars([1], [2]).instance_variables }
    show(:copy_object) do
      o = Object.new
      o.instance_variable_set(:@x, 1)
      Gaps.copy_ivars(+"s", o).instance_variables
    end
    show(:copy_frozen) { Gaps.copy_ivars("frozen".freeze, source) }

    show(:adjust) { [Gaps.adjust(1 << 20), Gaps.adjust(-(1 << 20)), Gaps.adjust(-(1 << 40))] }
    show(:locale) { Gaps.locale }
    show(:numwords) do
      [[0, 8], [1, 8], [255, 8], [256, 8], [-256, 8], [2**64, 64], [2**64 - 1, 64], [2**100, 32], [5, 0]].map { |v, bits| Gaps.numwords(v, bits) }
    end
    show(:ospath) do
      ["café", "café".encode("ISO-8859-1"), "\xff".b, "plain".encode("US-ASCII")].map do |path|
        out, enc, same = Gaps.ospath(path)
        [out.bytes, enc, same]
      end
    end
    show(:lock) { Gaps.lock }
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("gaps", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
