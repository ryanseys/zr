# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The event hooks of ruby/debug.h (kernel/capi/trace.rb), as debase,
# rbtrace and datadog use them: rb_add_event_hook's
# `func(event, data, self, mid, klass)`, the raw-arg form of
# rb_add_event_hook2, a thread's own hooks, and their removal, also from
# inside a hook, against ruby's answers.
class CExtEventHookTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/debug.h>

    static VALUE seen;

    static VALUE event_name(rb_event_flag_t event) {
      switch (event) {
        case RUBY_EVENT_LINE: return ID2SYM(rb_intern("line"));
        case RUBY_EVENT_CLASS: return ID2SYM(rb_intern("class"));
        case RUBY_EVENT_END: return ID2SYM(rb_intern("end"));
        case RUBY_EVENT_CALL: return ID2SYM(rb_intern("call"));
        case RUBY_EVENT_RETURN: return ID2SYM(rb_intern("return"));
        case RUBY_EVENT_C_CALL: return ID2SYM(rb_intern("c_call"));
        case RUBY_EVENT_C_RETURN: return ID2SYM(rb_intern("c_return"));
        case RUBY_EVENT_RAISE: return ID2SYM(rb_intern("raise"));
        case RUBY_EVENT_B_CALL: return ID2SYM(rb_intern("b_call"));
        case RUBY_EVENT_B_RETURN: return ID2SYM(rb_intern("b_return"));
      }
      return UINT2NUM(event);
    }

    static void hook(rb_event_flag_t event, VALUE data, VALUE self, ID mid, VALUE klass) {
      rb_ary_push(seen, rb_ary_new_from_args(5, data, event_name(event), rb_obj_class(self), mid ? ID2SYM(mid) : Qnil,
                                             klass ? klass : Qnil));
    }

    static void raw(VALUE data, const rb_trace_arg_t *arg) {
      rb_trace_arg_t *ta = (rb_trace_arg_t *)arg;
      rb_ary_push(seen, rb_ary_new_from_args(4, data, rb_tracearg_event(ta), rb_tracearg_method_id(ta), rb_tracearg_lineno(ta)));
    }

    /* Hears one event, then removes itself. */
    static void once(rb_event_flag_t event, VALUE data, VALUE self, ID mid, VALUE klass) {
      rb_ary_push(seen, rb_ary_new_from_args(2, data, event_name(event)));
      rb_ary_push(seen, INT2NUM(rb_remove_event_hook(once)));
    }

    static VALUE eh_add(VALUE self, VALUE events, VALUE data) {
      rb_add_event_hook(hook, NUM2UINT(events), data);
      return Qnil;
    }

    static VALUE eh_add_raw(VALUE self, VALUE events, VALUE data) {
      rb_add_event_hook2((rb_event_hook_func_t)raw, NUM2UINT(events), data, RUBY_EVENT_HOOK_FLAG_RAW_ARG);
      return Qnil;
    }

    static VALUE eh_add_once(VALUE self, VALUE events, VALUE data) {
      rb_add_event_hook(once, NUM2UINT(events), data);
      return Qnil;
    }

    static VALUE eh_add_for(VALUE self, VALUE thread, VALUE events, VALUE data) {
      rb_thread_add_event_hook(thread, hook, NUM2UINT(events), data);
      return Qnil;
    }

    static VALUE eh_remove(VALUE self) { return INT2NUM(rb_remove_event_hook(hook)); }
    static VALUE eh_remove_raw(VALUE self) { return INT2NUM(rb_remove_event_hook((rb_event_hook_func_t)raw)); }
    static VALUE eh_remove_with(VALUE self, VALUE data) { return INT2NUM(rb_remove_event_hook_with_data(hook, data)); }
    static VALUE eh_remove_any(VALUE self) { return INT2NUM(rb_remove_event_hook_with_data(hook, Qundef)); }
    static VALUE eh_remove_for(VALUE self, VALUE thread) { return INT2NUM(rb_thread_remove_event_hook(thread, hook)); }

    static VALUE eh_seen(VALUE self) {
      VALUE out = seen;
      seen = rb_ary_new();
      return out;
    }

    void Init_hooks(void) {
      seen = rb_ary_new();
      rb_global_variable(&seen);
      VALUE m = rb_define_module("Hooks");
      rb_define_module_function(m, "add", eh_add, 2);
      rb_define_module_function(m, "add_raw", eh_add_raw, 2);
      rb_define_module_function(m, "add_once", eh_add_once, 2);
      rb_define_module_function(m, "add_for", eh_add_for, 3);
      rb_define_module_function(m, "remove", eh_remove, 0);
      rb_define_module_function(m, "remove_raw", eh_remove_raw, 0);
      rb_define_module_function(m, "remove_with", eh_remove_with, 1);
      rb_define_module_function(m, "remove_any", eh_remove_any, 0);
      rb_define_module_function(m, "remove_for", eh_remove_for, 1);
      rb_define_module_function(m, "seen", eh_seen, 0);
    }
  C

  PROGRAM = <<~'RUBY'
    require "hooks"

    LINE, CLASS, END_, CALL, RETURN, C_CALL, C_RETURN, RAISE = 0x1, 0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x80
    B_CALL, B_RETURN = 0x100, 0x200

    class Box
      def initialize(v) = @v = v

      def double
        v = @v
        v + v
      end

      def failing
        raise IndexError, "nope"
      rescue IndexError
        :caught
      end

      def each_twice = 2.times { |i| yield i }
    end

    Hooks.seen
    Hooks.add(CALL | RETURN, :a)
    Box.new(2).double
    p [:a_removed, Hooks.remove]
    p [:calls, Hooks.seen]

    Hooks.add(C_CALL | C_RETURN, :c)
    [3, 1].max
    Hooks.remove
    p [:c, Hooks.seen]

    Hooks.add(LINE | RAISE, :lr)
    Box.new(1).failing
    Hooks.remove
    p [:line_raise, Hooks.seen]

    Hooks.add(B_CALL | B_RETURN, :b)
    Box.new(1).each_twice { |i| i }
    Hooks.remove
    p [:blocks, Hooks.seen]

    Hooks.add(CLASS | END_, :k)
    class Box; end
    Hooks.remove
    p [:class, Hooks.seen]

    Hooks.add(CALL, :one)
    Hooks.add(CALL, :two)
    Box.new(1).double
    p [:with_data, Hooks.remove_with(:one)]
    Box.new(1).double
    p [:any, Hooks.remove_any]
    p [:two_hooks, Hooks.seen]

    Hooks.add_raw(CALL | RETURN, :raw)
    Box.new(3).double
    p [:raw_removed, Hooks.remove_raw]
    p [:raw, Hooks.seen]

    Hooks.add_once(CALL, :once)
    Box.new(1).double
    Box.new(1).double
    p [:once, Hooks.seen]

    other = Thread.new { Thread.stop; Box.new(4).double }
    Thread.pass until other.status == "sleep"
    Hooks.add_for(other, CALL, :thread)
    Box.new(5).double
    other.run
    other.join
    p [:thread_removed, Hooks.remove_for(other)]
    p [:thread, Hooks.seen]
    p [:nothing_left, Hooks.remove, Hooks.remove_raw]
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("hooks", SOURCE)
  end

  def test_each_hook_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
