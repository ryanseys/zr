# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# C functions as blocks (rb_block_call, rb_proc_new, rb_iter_break), the
# C API's calls of Procs and Methods, and its recursion guards, which
# rbtree, rugged and io-event call (`zr-dev ext rank`), each against
# ruby's answer.
class CExtBlocksTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>

    static VALUE collect_i(RB_BLOCK_CALL_FUNC_ARGLIST(yielded, out)) {
      rb_ary_push(out, rb_ary_new_from_args(3, yielded, INT2FIX(argc), rb_ary_new_from_values(argc, argv)));
      return INT2FIX(RARRAY_LEN(out));
    }
    static VALUE collect(VALUE self, VALUE obj, VALUE mid) {
      VALUE out = rb_ary_new();
      VALUE r = rb_block_call(obj, SYM2ID(mid), 0, NULL, collect_i, out);
      return rb_assoc_new(r, out);
    }

    static VALUE doubled_i(RB_BLOCK_CALL_FUNC_ARGLIST(x, data)) { return rb_yield(rb_funcall(x, '*', 1, INT2FIX(2))); }
    static VALUE each_doubled(VALUE self, VALUE obj) {
      return rb_block_call(obj, rb_intern("each"), 0, NULL, doubled_i, Qnil);
    }

    static VALUE find_i(RB_BLOCK_CALL_FUNC_ARGLIST(x, limit)) {
      if (RTEST(rb_funcall(x, '>', 1, limit))) rb_iter_break_value(x);
      return Qnil;
    }
    static VALUE first_over(VALUE self, VALUE obj, VALUE limit) {
      return rb_block_call(obj, rb_intern("each"), 0, NULL, find_i, limit);
    }
    static VALUE stop_i(RB_BLOCK_CALL_FUNC_ARGLIST(x, data)) { rb_iter_break(); return Qnil; }
    static VALUE stop(VALUE self, VALUE obj) { return rb_block_call(obj, rb_intern("each"), 0, NULL, stop_i, Qnil); }
    static VALUE nested_i(RB_BLOCK_CALL_FUNC_ARGLIST(x, limit)) {
      return rb_block_call(x, rb_intern("each"), 0, NULL, find_i, limit);
    }
    static VALUE nested(VALUE self, VALUE obj, VALUE limit) {
      return rb_block_call(obj, rb_intern("map"), 0, NULL, nested_i, limit);
    }

    static VALUE raise_i(RB_BLOCK_CALL_FUNC_ARGLIST(x, data)) { rb_raise(rb_eRuntimeError, "from the block: %d", FIX2INT(x)); }
    static VALUE raising(VALUE self, VALUE obj) { return rb_block_call(obj, rb_intern("each"), 0, NULL, raise_i, Qnil); }

    static VALUE passing(VALUE self, VALUE obj) { return rb_block_call(obj, rb_intern("map"), 0, NULL, NULL, Qnil); }
    static VALUE each(VALUE self, VALUE obj) { return rb_each(obj); }

    static VALUE with_args(VALUE self, VALUE obj, VALUE a, VALUE kw) {
      VALUE args[2] = { a, kw };
      VALUE out = rb_ary_new();
      VALUE r = rb_block_call_kw(obj, rb_intern("give"), 2, args, collect_i, out, RB_PASS_KEYWORDS);
      return rb_assoc_new(r, out);
    }

    static VALUE adder_i(RB_BLOCK_CALL_FUNC_ARGLIST(x, base)) {
      VALUE sum = rb_str_dup(base);
      for (int i = 0; i < argc; i++) rb_str_append(sum, rb_obj_as_string(argv[i]));
      if (!NIL_P(blockarg)) rb_str_append(sum, rb_funcall(blockarg, rb_intern("call"), 0));
      return sum;
    }
    static VALUE adder(VALUE self) { return rb_proc_new(adder_i, rb_str_new_cstr("kept:")); }

    static VALUE splat(VALUE self, VALUE values) { return rb_yield_splat(values); }
    static VALUE proc_info(VALUE self, VALUE proc) {
      return rb_ary_new_from_args(2, INT2FIX(rb_proc_arity(proc)), rb_proc_lambda_p(proc));
    }
    static VALUE proc_call(VALUE self, VALUE proc, VALUE args) { return rb_proc_call(proc, args); }
    static VALUE method_call(VALUE self, VALUE method, VALUE a) { return rb_method_call(1, &a, method); }

    static VALUE show_i(VALUE obj, VALUE out, int recursive) {
      if (recursive) return rb_str_cat_cstr(out, "[...]");
      rb_str_cat_cstr(out, "(");
      for (long i = 0; i < RARRAY_LEN(obj); i++) {
        VALUE x = RARRAY_AREF(obj, i);
        if (RB_TYPE_P(x, T_ARRAY)) rb_funcall(rb_mKernel, rb_intern("show_into"), 2, x, out);
        else rb_str_append(out, rb_inspect(x));
      }
      return rb_str_cat_cstr(out, ")");
    }
    static VALUE show_into(VALUE self, VALUE obj, VALUE out) { return rb_exec_recursive(show_i, obj, out); }

    static VALUE same_i(VALUE a, VALUE b, int recursive) {
      if (recursive) return Qtrue;
      if (!RB_TYPE_P(a, T_ARRAY) || !RB_TYPE_P(b, T_ARRAY)) return rb_equal(a, b);
      if (RARRAY_LEN(a) != RARRAY_LEN(b)) return Qfalse;
      for (long i = 0; i < RARRAY_LEN(a); i++)
        if (!RTEST(rb_funcall(rb_mKernel, rb_intern("same"), 2, RARRAY_AREF(a, i), RARRAY_AREF(b, i)))) return Qfalse;
      return Qtrue;
    }
    static VALUE same(VALUE self, VALUE a, VALUE b) { return rb_exec_recursive_paired(same_i, a, b, b); }

    void Init_blocks(void) {
      VALUE m = rb_define_module("Blocks");
      rb_define_module_function(m, "collect", collect, 2);
      rb_define_module_function(m, "each_doubled", each_doubled, 1);
      rb_define_module_function(m, "first_over", first_over, 2);
      rb_define_module_function(m, "stop", stop, 1);
      rb_define_module_function(m, "nested", nested, 2);
      rb_define_module_function(m, "raising", raising, 1);
      rb_define_module_function(m, "passing", passing, 1);
      rb_define_module_function(m, "each", each, 1);
      rb_define_module_function(m, "with_args", with_args, 3);
      rb_define_module_function(m, "adder", adder, 0);
      rb_define_module_function(m, "splat", splat, 1);
      rb_define_module_function(m, "proc_info", proc_info, 1);
      rb_define_module_function(m, "proc_call", proc_call, 2);
      rb_define_module_function(m, "method_call", method_call, 2);
      rb_define_global_function("show_into", show_into, 2);
      rb_define_global_function("same", same, 2);
    }
  C

  PROGRAM = <<~'RUBY'
    require "blocks"

    def show(label)
      p [label, yield]
    rescue => e
      p [label, e.class, e.message]
    end

    class Giver
      def give(a, key: 0)
        yield a, key
        yield
        yield [a, key]
        :given
      end
    end
    class Guarded
      attr_reader :log
      def initialize = @log = []
      def each
        @log << :start
        [1, 2, 3].each { |x| yield x }
        @log << :end
      ensure
        @log << :ensure
      end
    end

    show(:collect_array) { Blocks.collect([1, [2, 3], nil], :each) }
    show(:collect_hash) { Blocks.collect({ a: 1, b: 2 }, :each) }
    show(:collect_pairs) { Blocks.collect({ a: 1 }, :each_pair) }
    show(:collect_map) { Blocks.collect([1, 2], :map) }
    show(:collect_none) { Blocks.collect([], :each) }
    show(:each_doubled) { out = []; Blocks.each_doubled([1, 2, 3]) { |x| out << x }; out }
    show(:each_doubled_none) { Blocks.each_doubled([1]) }
    show(:first_over) { [Blocks.first_over([1, 5, 2, 9], 3), Blocks.first_over([1, 2], 3), Blocks.first_over(1..Float::INFINITY, 41)] }
    show(:stop) { Blocks.stop([1, 2]) }
    show(:ensure_on_break) { g = Guarded.new; [Blocks.first_over(g, 1), g.log] }
    show(:nested) { Blocks.nested([[1, 5], [2], [7, 8]], 4) }
    show(:raising) { Blocks.raising([7]) }
    show(:raise_ensure) { g = Guarded.new; begin; Blocks.raising(g); rescue => e; [e.message, g.log]; end }
    show(:passing) { Blocks.passing([1, 2]) { |x| x + 10 } }
    show(:passing_none) { Blocks.passing([1, 2]).class }
    show(:each) { out = []; r = Blocks.each([3, 4]) { |x| out << x }; [r, out] }
    show(:with_args) { Blocks.with_args(Giver.new, :a, { key: 9 }) }
    show(:adder) { a = Blocks.adder; GC.start; [a.call(1, 2), a.call, a.call(3) { "!" }, a.(*[4, 5]), a.lambda?, a.arity, a.class] }
    show(:adder_yielded) { [1, 2].map(&Blocks.adder) }
    show(:adder_hash) { { x: 1 }.map(&Blocks.adder) }
    show(:splat) { [Blocks.splat([1, 2]) { |a, b| [b, a] }, Blocks.splat([]) { |*a| a }, Blocks.splat([[1, 2]]) { |a| a }] }
    show(:splat_not_array) { Blocks.splat(1) { } }
    show(:splat_no_block) { Blocks.splat([1]) }
    show(:proc_info) { [Blocks.proc_info(proc { |a, b| }), Blocks.proc_info(lambda { |a, *b| }), Blocks.proc_info(:upcase.to_proc), Blocks.proc_info(method(:puts).to_proc)] }
    show(:proc_call) { [Blocks.proc_call(proc { |a, b| [b, a] }, [1, 2]), Blocks.proc_call(lambda { |*a| a }, [])] }
    show(:proc_call_arity) { Blocks.proc_call(lambda { |a| a }, [1, 2]) }
    show(:method_call) { Blocks.method_call(1.method(:+), 2) }
    show(:recursive) { a = [1, [2, "x"]]; a[1] << a; out = +""; show_into(a, out); out }
    show(:recursive_flat) { out = +""; show_into([1, [2], [3, [4]]], out); out }
    show(:paired) { a = [1]; a << a; b = [1]; b << b; [same(a, b), same([1, [2]], [1, [2]]), same([1, [2]], [1, [3]])] }
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("blocks", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
