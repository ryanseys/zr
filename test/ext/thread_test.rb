# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# C that runs without the GVL (rb_thread_call_without_gvl): on the
# thread's own OS thread, or on a worker OS thread with green threads
# (ZR_THREADS=green), while the program's other threads run; its unblocking
# function stops it for Thread#kill and Thread#raise; and it calls back
# into Ruby with rb_thread_call_with_gvl. Each program gives ruby's
# output, also under ZR_GC_STRESS.
class CExtThreadTest < Minitest::Test
  SOURCE = <<~C
    #include <ruby.h>
    #include <ruby/thread.h>
    #include <stdint.h>
    #include <unistd.h>

    static void *nap(void *ms) { usleep((useconds_t)(intptr_t)ms * 1000); return (void *)42; }
    static VALUE sleep_without_gvl(VALUE self, VALUE ms) {
      void *r = rb_thread_call_without_gvl(nap, (void *)(intptr_t)NUM2INT(ms), RUBY_UBF_IO, NULL);
      return INT2FIX((intptr_t)r);
    }

    static volatile int stop_flag;
    static void *spin(void *arg) { while (!stop_flag) usleep(1000); return (void *)7; }
    static void unblock(void *arg) { stop_flag = 1; }
    static VALUE wait_for_unblock(VALUE self) {
      stop_flag = 0;
      return INT2FIX((intptr_t)rb_thread_call_without_gvl(spin, NULL, unblock, NULL));
    }

    /* A handshake with no clock in it: the C waits, without the GVL, for a
       flag that only another Ruby thread sets, for 30 s at most. */
    static volatile int waiting, flag;
    static void *wait_flag(void *arg) {
      waiting = 1;
      for (int i = 0; i < 30000 && !flag; i++) usleep(1000);
      waiting = 0;
      return (void *)(intptr_t)flag;
    }
    static VALUE wait_for_flag(VALUE self) {
      flag = 0;
      return rb_thread_call_without_gvl(wait_flag, NULL, RUBY_UBF_IO, NULL) ? Qtrue : Qfalse;
    }
    static VALUE is_waiting(VALUE self) { return waiting ? Qtrue : Qfalse; }
    static VALUE set_flag(VALUE self) { flag = 1; return Qnil; }

    static void *in_gvl(void *blk) { return (void *)rb_funcall((VALUE)blk, rb_intern("call"), 0); }
    static void *reenter(void *blk) { usleep(20000); return rb_thread_call_with_gvl(in_gvl, blk); }
    static VALUE call_back(VALUE self, VALUE blk) {
      return (VALUE)rb_thread_call_without_gvl(reenter, (void *)blk, RUBY_UBF_IO, NULL);
    }

    int ruby_thread_has_gvl_p(void);
    static void *ask(void *arg) { return (void *)(intptr_t)(ruby_native_thread_p() * 2 + ruby_thread_has_gvl_p()); }
    static VALUE asked_inside(VALUE self) { return INT2FIX((intptr_t)rb_thread_call_without_gvl(ask, NULL, RUBY_UBF_IO, NULL)); }
    static VALUE asked_outside(VALUE self) { return INT2FIX((intptr_t)ask(NULL)); }

    void Init_nap(void) {
      VALUE m = rb_define_module("Nap");
      rb_define_module_function(m, "sleep", sleep_without_gvl, 1);
      rb_define_module_function(m, "wait_for_unblock", wait_for_unblock, 0);
      rb_define_module_function(m, "wait_for_flag", wait_for_flag, 0);
      rb_define_module_function(m, "waiting?", is_waiting, 0);
      rb_define_module_function(m, "set_flag", set_flag, 0);
      rb_define_module_function(m, "call_back", call_back, 1);
      rb_define_module_function(m, "asked_inside", asked_inside, 0);
      rb_define_module_function(m, "asked_outside", asked_outside, 0);
    }
  C

  RUNS = [{}, { "ZR_GC_STRESS" => "1" }, { "ZR_THREADS" => "green" }, { "ZR_THREADS" => "green", "ZR_GC_STRESS" => "1" }].freeze

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("nap", SOURCE)
  end

  def assert_same_as_ruby(program)
    ruby, runs = Zr::Test::CExt.outputs_under(@ext, program, RUNS)
    RUNS.zip(runs).each do |env, zr|
      assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr's output differs from ruby's under #{env}\nzr stderr:\n#{zr.stderr}"
    end
  end

  def test_c_without_the_gvl_returns_its_result_alone_and_among_threads
    assert_same_as_ruby(<<~RUBY)
      require "nap"
      p Nap.sleep(5)
      # The thread runs only while the C holds no GVL, and the C returns
      # true only once the thread has run: no tick count, no clock.
      t = Thread.new { Thread.pass until Nap.waiting?; Nap.set_flag }
      p Nap.wait_for_flag
      t.join
      p 3.times.map { Thread.new { Nap.sleep(50) } }.map(&:value)
    RUBY
  end

  def test_an_interrupt_stops_the_c_through_its_unblocking_function
    assert_same_as_ruby(<<~RUBY)
      require "nap"
      t = Thread.new { Nap.wait_for_unblock }
      sleep 0.1
      t.kill
      t.join
      p t.status
      t = Thread.new { Nap.wait_for_unblock }
      sleep 0.1
      t.raise(RuntimeError, "stop")
      begin
        t.join
      rescue RuntimeError => e
        p [e.class, e.message]
      end
      p Thread.new { Nap.sleep(10) }.value
    RUBY
  end

  def test_the_c_calls_back_into_ruby_with_the_gvl
    assert_same_as_ruby(<<~RUBY)
      require "nap"
      p Nap.call_back(-> { [1, 2].sum + 39 })
      other = Thread.new { sleep 0.3 }
      p Nap.call_back(-> { "back in ruby: \#{Thread.current == Thread.main}" })
      p Nap.asked_inside, Nap.asked_outside
      other.join
    RUBY
  end
end
