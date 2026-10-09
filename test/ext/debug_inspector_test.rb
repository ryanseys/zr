# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The debug inspector of ruby/debug.h (kernel/capi/debug.rb), as
# debug_inspector, binding_of_caller, bindex and byebug use it: the frames
# that run, their locations, selves, classes, code and bindings, from a C
# method and from a C TracePoint's hook, against ruby's answers.
class CExtDebugInspectorTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/debug.h>

    static VALUE send0(VALUE recv, const char *name) { return rb_funcall(recv, rb_intern(name), 0); }

    static VALUE basename(VALUE path) {
      return NIL_P(path) ? Qnil : rb_funcall(rb_cFile, rb_intern("basename"), 1, path);
    }

    /* Each frame: where it is, its self's class, its class, its locals
       and the label of its code. */
    static VALUE rows_of(const rb_debug_inspector_t *dc, void *data) {
      VALUE locations = rb_debug_inspector_backtrace_locations(dc);
      VALUE out = rb_ary_new();
      for (long i = 0; i < RARRAY_LEN(locations); i++) {
        VALUE location = RARRAY_AREF(locations, i);
        VALUE binding = rb_debug_inspector_frame_binding_get(dc, i);
        VALUE iseq = rb_debug_inspector_frame_iseq_get(dc, i);
        VALUE row = rb_ary_new_from_args(8, basename(send0(location, "path")), send0(location, "lineno"), send0(location, "label"),
                                         send0(location, "base_label"), rb_obj_class(rb_debug_inspector_frame_self_get(dc, i)),
                                         rb_debug_inspector_frame_class_get(dc, i),
                                         NIL_P(binding) ? Qnil : send0(binding, "local_variables"),
                                         NIL_P(iseq) ? Qnil : send0(iseq, "label"));
        rb_ary_push(out, row);
      }
      return out;
    }

    static VALUE in_frames(VALUE self) { return rb_debug_inspector_open(rows_of, NULL); }

    /* The bindings of the Ruby frames, as binding_of_caller keeps them. */
    static VALUE bindings_of(const rb_debug_inspector_t *dc, void *data) {
      VALUE out = rb_ary_new();
      long n = RARRAY_LEN(rb_debug_inspector_backtrace_locations(dc));
      for (long i = 0; i < n; i++) {
        VALUE binding = rb_debug_inspector_frame_binding_get(dc, i);
        if (!NIL_P(binding)) rb_ary_push(out, binding);
      }
      return out;
    }

    static VALUE in_bindings(VALUE self) { return rb_debug_inspector_open(bindings_of, NULL); }

    static VALUE depths_of(const rb_debug_inspector_t *dc, void *data) {
      VALUE now = rb_debug_inspector_current_depth();
      VALUE first = rb_debug_inspector_frame_depth(dc, 0), second = rb_debug_inspector_frame_depth(dc, 1);
      return rb_ary_new_from_args(2, LONG2NUM(NUM2LONG(now) - NUM2LONG(first)), LONG2NUM(NUM2LONG(first) - NUM2LONG(second)));
    }

    static VALUE in_depths(VALUE self) { return rb_debug_inspector_open(depths_of, NULL); }

    static VALUE self_at(const rb_debug_inspector_t *dc, void *data) {
      return rb_debug_inspector_frame_self_get(dc, *(long *)data);
    }

    static VALUE in_self_at(VALUE self, VALUE index) {
      long i = NUM2LONG(index);
      return rb_debug_inspector_open(self_at, &i);
    }

    /* bindex: each raise keeps the bindings of its frames in the error, in
       an ivar that Ruby cannot name. */
    static void raised(VALUE tp, void *data) {
      VALUE e = rb_tracearg_raised_exception(rb_tracearg_from_tracepoint(tp));
      if (NIL_P(rb_attr_get(e, rb_intern("bindings"))))
        rb_ivar_set(e, rb_intern("bindings"), rb_debug_inspector_open(bindings_of, NULL));
    }

    static VALUE in_keep_bindings(VALUE self) {
      rb_tracepoint_enable(rb_tracepoint_new(Qnil, RUBY_EVENT_RAISE, raised, 0));
      return Qnil;
    }

    static VALUE in_bindings_of(VALUE self, VALUE e) { return rb_attr_get(e, rb_intern("bindings")); }

    /* byebug: at each call, the frames as the hook sees them. */
    static VALUE seen;

    static void called(VALUE tp, void *data) {
      rb_ary_push(seen, rb_debug_inspector_open(rows_of, NULL));
    }

    static VALUE in_watch(VALUE self) {
      seen = rb_ary_new();
      VALUE tp = rb_tracepoint_new(Qnil, RUBY_EVENT_CALL, called, 0);
      rb_tracepoint_enable(tp);
      rb_yield(Qnil);
      rb_tracepoint_disable(tp);
      return seen;
    }

    void Init_inspect(void) {
      rb_global_variable(&seen);
      VALUE m = rb_define_module("Inspect");
      rb_define_module_function(m, "frames", in_frames, 0);
      rb_define_module_function(m, "bindings", in_bindings, 0);
      rb_define_module_function(m, "depths", in_depths, 0);
      rb_define_module_function(m, "self_at", in_self_at, 1);
      rb_define_module_function(m, "keep_bindings", in_keep_bindings, 0);
      rb_define_module_function(m, "bindings_of", in_bindings_of, 1);
      rb_define_module_function(m, "watch", in_watch, 0);
    }
  C

  PROGRAM = <<~'RUBY'
    require "inspect"

    def show(label)
      p [label, yield]
    rescue StandardError => e
      p [label, e.class, e.message]
    end

    class Walker
      def walk(a)
        b = a + 1
        [b].map { |x| Inspect.frames }[0]
      end

      def caller_binding(seed)
        local = seed * 2
        Inspect.bindings[0]
      end

      def self.depths = Inspect.depths

      def failing(n)
        inner = n
        raise ArgumentError, "deep" if n.zero?

        failing(n - 1)
      end
    end

    show(:frames) { Walker.new.walk(1) }
    show(:top) { Inspect.frames.last(2) }
    binding_kept = Walker.new.caller_binding(21)
    show(:binding) { [binding_kept.local_variables, binding_kept.local_variable_get(:local), binding_kept.receiver.class] }
    show(:set) { binding_kept.local_variable_set(:local, 7); binding_kept.local_variable_get(:local) }
    show(:eval) { binding_kept.eval("local + seed") }
    show(:caller) do
      here = 10
      [Inspect.bindings[0].local_variable_get(:here), Inspect.bindings[1].receiver]
    end
    show(:depths) { Walker.depths }
    show(:self_at) { Inspect.self_at(0) }
    show(:no_frame) { Inspect.self_at(1000) }
    show(:negative) { Inspect.self_at(-1) }

    Inspect.keep_bindings
    GC.start
    show(:bindex) do
      Walker.new.failing(2)
    rescue ArgumentError => e
      kept = Inspect.bindings_of(e)
      [e.instance_variables, kept.size, kept.first(3).map { |b| b.local_variable_get(:inner) }]
    end
    show(:reraise) do
      begin
        Walker.new.failing(0)
      rescue ArgumentError => e
        first = Inspect.bindings_of(e)
        raise e
      end
    rescue ArgumentError => e
      Inspect.bindings_of(e).equal?(first)
    end

    show(:hook) { Inspect.watch { Walker.new.walk(5) }.map { |frames| frames.first(3) } }
    # A core method that ruby writes in Ruby runs its :call hook in its
    # own frame.
    show(:core_hook) { Inspect.watch { [1, 2].first }.map { |frames| frames.first(2) } }
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("inspect", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
