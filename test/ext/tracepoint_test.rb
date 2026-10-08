# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API of ruby/debug.h for tracers (kernel/capi/trace.rb), as
# byebug, ruby-prof and bindex use it: C TracePoints made, turned on and
# off, and the trace arg of each event, against ruby's answers. The
# program never names TracePoint: the extension's imports alone make zr
# build it with the trace events (Ext::Source#traces?).
class CExtTracepointTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/debug.h>

    static VALUE events_seen;

    static VALUE basename(VALUE path) {
      return NIL_P(path) ? Qnil : rb_funcall(rb_cFile, rb_intern("basename"), 1, path);
    }

    static VALUE call_return_value(VALUE arg) { return rb_tracearg_return_value((rb_trace_arg_t *)arg); }

    /* The error that `fn(arg)` raises, as [class, message], or its value. */
    static VALUE caught(VALUE (*fn)(VALUE), VALUE arg) {
      int state = 0;
      VALUE v = rb_protect(fn, arg, &state);
      if (!state) return v;
      VALUE e = rb_errinfo();
      rb_set_errinfo(Qnil);
      return rb_ary_new_from_args(2, rb_obj_class(e), rb_funcall(e, rb_intern("message"), 0));
    }

    /* Each event as a row: its name, its flag, where, the method, the
       class, self, and what the event alone has. */
    static void hook(VALUE tp, void *data) {
      rb_trace_arg_t *arg = rb_tracearg_from_tracepoint(tp);
      rb_event_flag_t flag = rb_tracearg_event_flag(arg);
      VALUE extra = Qnil;
      switch (flag) {
        case RUBY_EVENT_RETURN: case RUBY_EVENT_C_RETURN: case RUBY_EVENT_B_RETURN:
          extra = rb_tracearg_return_value(arg); break;
        case RUBY_EVENT_RAISE: case RUBY_EVENT_RESCUE:
          extra = rb_funcall(rb_tracearg_raised_exception(arg), rb_intern("message"), 0); break;
        case RUBY_EVENT_CALL: {
          VALUE b = rb_tracearg_binding(arg);
          extra = rb_ary_new_from_args(2, rb_funcall(b, rb_intern("local_variables"), 0), rb_tracearg_parameters(arg));
          break;
        }
        case RUBY_EVENT_LINE:
          extra = caught(call_return_value, (VALUE)arg); break;
      }
      VALUE self = rb_tracearg_self(arg);
      VALUE row = rb_ary_new_from_args(9, rb_tracearg_event(arg), UINT2NUM(flag), basename(rb_tracearg_path(arg)),
                                       rb_tracearg_lineno(arg), rb_tracearg_method_id(arg), rb_tracearg_callee_id(arg),
                                       rb_tracearg_defined_class(arg), rb_obj_class(self), extra);
      rb_ary_push(*(VALUE *)data, row);
    }

    static VALUE tr_new(VALUE self, VALUE events) {
      return rb_tracepoint_new(Qnil, NUM2UINT(events), hook, &events_seen);
    }

    static VALUE tr_new_for(VALUE self, VALUE thread, VALUE events) {
      return rb_tracepoint_new(thread, NUM2UINT(events), hook, &events_seen);
    }

    static VALUE tr_enable(VALUE self, VALUE tp) {
      VALUE before = rb_tracepoint_enabled_p(tp);
      rb_tracepoint_enable(tp);
      return rb_ary_new_from_args(2, before, rb_tracepoint_enabled_p(tp));
    }

    static VALUE tr_disable(VALUE self, VALUE tp) {
      VALUE before = rb_tracepoint_enabled_p(tp);
      rb_tracepoint_disable(tp);
      return rb_ary_new_from_args(2, before, rb_tracepoint_enabled_p(tp));
    }

    static VALUE outside(VALUE tp) { return (VALUE)rb_tracearg_from_tracepoint(tp); }

    static VALUE tr_outside(VALUE self, VALUE tp) { return caught(outside, tp); }

    static VALUE tr_log(VALUE self) {
      VALUE out = events_seen;
      events_seen = rb_ary_new();
      return out;
    }

    /* A point that nothing but its being on keeps, as bindex's is. */
    static void raised(VALUE tp, void *data) {
      VALUE e = rb_tracearg_raised_exception(rb_tracearg_from_tracepoint(tp));
      rb_ary_push(events_seen, rb_ary_new_from_args(2, ID2SYM(rb_intern("kept")), rb_funcall(e, rb_intern("message"), 0)));
    }

    static VALUE tr_keep_raises(VALUE self) {
      rb_tracepoint_enable(rb_tracepoint_new(0, RUBY_EVENT_RAISE, raised, 0));
      return Qnil;
    }

    /* A hook that raises in the call of `area`: the error reaches the code
       that fired the event. */
    static void raising(VALUE tp, void *data) {
      if (rb_tracearg_method_id(rb_tracearg_from_tracepoint(tp)) == ID2SYM(rb_intern("area")))
        rb_raise(rb_eArgError, "from the hook");
    }

    static VALUE tr_raising(VALUE self) { return rb_tracepoint_new(Qnil, RUBY_EVENT_CALL, raising, 0); }

    void Init_tracer(void) {
      events_seen = rb_ary_new();
      rb_global_variable(&events_seen);
      VALUE m = rb_define_module("Tracer");
      rb_define_module_function(m, "point", tr_new, 1);
      rb_define_module_function(m, "point_for", tr_new_for, 2);
      rb_define_module_function(m, "enable", tr_enable, 1);
      rb_define_module_function(m, "disable", tr_disable, 1);
      rb_define_module_function(m, "outside", tr_outside, 1);
      rb_define_module_function(m, "log", tr_log, 0);
      rb_define_module_function(m, "keep_raises", tr_keep_raises, 0);
      rb_define_module_function(m, "raising", tr_raising, 0);
    }
  C

  PROGRAM = <<~'RUBY'
    require "tracer"

    LINE, CLASS, END_, CALL, RETURN, C_CALL, C_RETURN, RAISE = 0x1, 0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x80
    B_CALL, B_RETURN, THREAD_BEGIN, THREAD_END, RESCUE = 0x100, 0x200, 0x400, 0x800, 0x4000

    module Helper
      def help(x) = x + 1
    end

    class Shape
      include Helper

      def area(w, h)
        product = w * h
        product
      end
      alias size area

      def self.make = new
      def inspect = "#<Shape>"

      def each_side
        [1, 2].each { |side| yield side }
      end

      def fail_once
        raise IndexError, "bad side"
      rescue IndexError
        :rescued
      end
    end

    def show(label)
      Tracer.log
      value = yield
      p [label, value, Tracer.log]
    rescue StandardError => e
      p [label, e.class, e.message, Tracer.log]
    end

    point = Tracer.point(CALL | RETURN | LINE)
    show(:outside) { Tracer.outside(point) }
    show(:enable) { Tracer.enable(point) }
    show(:again) { Tracer.enable(point) }
    show(:calls) { Shape.new.area(2, 3) }
    show(:alias) { Shape.new.size(4, 5) }
    show(:module) { Shape.new.help(1) }
    show(:singleton) { Shape.make && :made }
    show(:disable) { Tracer.disable(point) }
    show(:off) { Shape.new.area(1, 1) }

    blocks = Tracer.point(B_CALL | B_RETURN)
    Tracer.enable(blocks)
    show(:blocks) { Shape.new.each_side { |side| side * 2 } }
    Tracer.disable(blocks)

    cs = Tracer.point(C_CALL | C_RETURN)
    Tracer.enable(cs)
    show(:c) { [3, 1, 2].sort.first }
    Tracer.disable(cs)

    errors = Tracer.point(RAISE | RESCUE)
    Tracer.enable(errors)
    show(:raise) { Shape.new.fail_once }
    Tracer.disable(errors)

    classes = Tracer.point(CLASS | END_)
    Tracer.enable(classes)
    show(:class) { class Shape; def extra = 1; end; Shape.new.extra }
    Tracer.disable(classes)

    other = Thread.new { sleep 0.01; Shape.new.area(5, 5) }
    mine = Tracer.point_for(other, CALL)
    Tracer.enable(mine)
    show(:thread) { Shape.new.area(6, 6); other.join.value }
    Tracer.disable(mine)

    Tracer.keep_raises
    GC.start
    show(:kept) { begin; raise "kept one"; rescue => e; e.message; end }

    raising = Tracer.raising
    Tracer.enable(raising)
    show(:raising) { Shape.new.area(1, 2) }
    Tracer.disable(raising)
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("tracer", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
