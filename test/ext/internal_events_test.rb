# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The internal events of ruby/debug.h (kernel/internal_events.rb), as
# ruby-prof, allocation_tracer and vernier hear them: a C TracePoint on
# RUBY_INTERNAL_EVENT_NEWOBJ hears each allocation with its class, place
# and method, and one on FREEOBJ hears the sweep free an object, against
# ruby's answers. A hook runs no Ruby and hears no event of its own.
class CExtInternalEventsTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/debug.h>

    static VALUE watched;            /* the class whose objects count */
    static long made, freed;
    static VALUE last;               /* the last object made, which the program keeps */
    static VALUE first_place;        /* [path, lineno, method_id, flag] of the first */
    static int other_flags;          /* an event that is not the point's */

    static void on_new(VALUE tp, void *data) {
      rb_trace_arg_t *arg = rb_tracearg_from_tracepoint(tp);
      if (rb_tracearg_event_flag(arg) != RUBY_INTERNAL_EVENT_NEWOBJ) other_flags++;
      VALUE obj = rb_tracearg_object(arg);
      if (rb_obj_class(obj) != watched) return;
      if (made++ == 0) {
        /* The hook keeps what it read in C until it ends: no Ruby
           object is made here but the place's own. */
        static VALUE place[4];
        place[0] = rb_tracearg_path(arg);
        place[1] = rb_tracearg_lineno(arg);
        place[2] = rb_tracearg_method_id(arg);
        place[3] = rb_tracearg_defined_class(arg);
        first_place = (VALUE)place;
      }
      last = obj;
    }

    static void on_free(VALUE tp, void *data) {
      rb_trace_arg_t *arg = rb_tracearg_from_tracepoint(tp);
      if (rb_tracearg_event_flag(arg) != RUBY_INTERNAL_EVENT_FREEOBJ) other_flags++;
      /* The object is going: its identity is all that a hook may use. */
      if (rb_tracearg_object(arg)) freed++;
    }

    static VALUE al_count(VALUE self, VALUE klass) {
      watched = klass;
      made = 0;
      first_place = 0;
      VALUE tp = rb_tracepoint_new(0, RUBY_INTERNAL_EVENT_NEWOBJ, on_new, 0);
      rb_tracepoint_enable(tp);
      VALUE kept = rb_yield(Qnil);
      rb_tracepoint_disable(tp);
      VALUE *place = (VALUE *)first_place;
      VALUE where = place ? rb_ary_new_from_args(4, rb_funcall(rb_cFile, rb_intern("basename"), 1, place[0]), place[1], place[2], place[3])
                          : Qnil;
      return rb_ary_new_from_args(4, LONG2NUM(made), where, rb_equal(last, kept) ? Qtrue : Qfalse, INT2NUM(other_flags));
    }

    static VALUE al_frees(VALUE self, VALUE klass) {
      watched = klass;
      freed = 0;
      VALUE tp = rb_tracepoint_new(0, RUBY_INTERNAL_EVENT_FREEOBJ, on_free, 0);
      rb_tracepoint_enable(tp);
      rb_yield(Qnil);
      rb_tracepoint_disable(tp);
      return rb_ary_new_from_args(2, freed > 0 ? Qtrue : Qfalse, INT2NUM(other_flags));
    }

    static VALUE al_after(VALUE self) { return LONG2NUM(made); }

    void Init_alloc(void) {
      rb_global_variable(&watched);
      VALUE m = rb_define_module("Alloc");
      rb_define_module_function(m, "count", al_count, 1);
      rb_define_module_function(m, "frees", al_frees, 1);
      rb_define_module_function(m, "after", al_after, 0);
    }
  C

  PROGRAM = <<~'RUBY'
    require "alloc"

    class Widget
      def initialize(n) = @n = n
    end

    class Factory
      def build(n)
        Widget.new(n)
      end
    end

    def show(label)
      p [label, yield]
    rescue StandardError => e
      p [label, e.class, e.message]
    end

    # ruby makes one more object of the class at its first instance.
    Widget.new(0)
    show(:count) do
      Alloc.count(Widget) do
        f = Factory.new
        3.times { |i| f.build(i) }
        f.build(9)
      end
    end
    show(:none) { Alloc.count(Widget) { [1, 2].map(&:to_s); "x" * 3 }.first }
    show(:off) { Widget.new(1); Alloc.after }
    show(:frees) do
      Alloc.frees(Widget) do
        200.times { |i| Widget.new(i) }
        GC.start
        GC.start
      end
    end
    show(:alive) { Widget.new(5).instance_variable_get(:@n) }
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @ext = Zr::Test::CExt.build("alloc", SOURCE)
  end

  def test_each_event_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
