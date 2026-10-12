# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API's threads, mutexes, fibers, evaluation and loads, st updates
# and hashes, time intervals and the other functions that grpc,
# eventmachine, ruby-prof, io-event and kgio call (`zr-dev ext rank`),
# each against ruby's answer.
class CExtThreadsAndFibersTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/encoding.h>
    #include <ruby/st.h>
    #include <ruby/thread.h>
    #include <ruby/io.h>
    #include <ruby/fiber/scheduler.h>

    /* Not in a public header: ruby's internal/thread.h declares it so. */
    VALUE rb_thread_io_blocking_region(struct rb_io *, rb_blocking_function_t *, void *);

    static VALUE body(void *arg) { return rb_funcall((VALUE)arg, rb_intern("*"), 1, INT2FIX(2)); }
    static VALUE t_create(VALUE self, VALUE n) {
      VALUE t = rb_thread_create(body, (void *)n);
      return rb_funcall(t, rb_intern("value"), 0);
    }
    static VALUE t_alone(VALUE self) { return INT2FIX(rb_thread_alone()); }
    static VALUE t_main(VALUE self) { return rb_thread_main() == rb_thread_current() ? Qtrue : Qfalse; }
    static VALUE t_locals(VALUE self) {
      VALUE t = rb_thread_current();
      rb_thread_local_aset(t, rb_intern("from_c"), INT2FIX(7));
      return rb_thread_local_aref(t, rb_intern("from_c"));
    }
    static VALUE t_stop_run(VALUE self, VALUE thread) { return rb_thread_run(thread); }
    static VALUE t_stop(VALUE self) { rb_thread_stop(); return Qtrue; }
    static VALUE t_wait_for(VALUE self) {
      struct timeval tv = { 0, 20000 };
      rb_thread_wait_for(tv);
      rb_thread_sleep(0);
      return Qtrue;
    }

    static VALUE counted(VALUE arg) {
      VALUE *n = (VALUE *)arg;
      *n = rb_funcall(*n, '+', 1, INT2FIX(1));
      return *n;
    }
    static VALUE raising(VALUE arg) { rb_raise(rb_eRuntimeError, "inside"); return Qnil; }
    static VALUE m_mutex(VALUE self) {
      VALUE m = rb_mutex_new();
      VALUE n = INT2FIX(0);
      VALUE locked = rb_mutex_locked_p(m);
      rb_mutex_lock(m);
      VALUE during = rb_ary_new_from_args(2, rb_mutex_locked_p(m), rb_mutex_trylock(m));
      rb_mutex_unlock(m);
      VALUE r = rb_mutex_synchronize(m, counted, (VALUE)&n);
      return rb_ary_new_from_args(5, locked, during, rb_mutex_trylock(m), r, n);
    }
    static VALUE m_raising(VALUE self, VALUE m) { return rb_mutex_synchronize(m, raising, Qnil); }

    static VALUE fiber_body(RB_BLOCK_CALL_FUNC_ARGLIST(first, data)) {
      VALUE got = rb_fiber_yield(1, &first);
      return rb_ary_new_from_args(2, got, data);
    }
    static VALUE f_fibers(VALUE self) {
      VALUE f = rb_fiber_new(fiber_body, rb_str_new_cstr("data"));
      VALUE a = INT2FIX(1), b = INT2FIX(2);
      VALUE first = rb_fiber_resume(f, 1, &a);
      VALUE alive = rb_fiber_alive_p(f);
      VALUE last = rb_fiber_resume(f, 1, &b);
      return rb_ary_new_from_args(6, first, alive, last, rb_fiber_alive_p(f), rb_obj_is_fiber(f), rb_obj_is_fiber(Qnil));
    }
    static VALUE f_current(VALUE self) { return rb_fiber_current() == rb_funcall(rb_path2class("Fiber"), rb_intern("current"), 0) ? Qtrue : Qfalse; }
    static VALUE f_raise(VALUE self, VALUE f, VALUE exc) { return rb_fiber_raise(f, 1, &exc); }
    static VALUE f_scheduler(VALUE self) { return rb_ary_new_from_args(2, rb_fiber_scheduler_current(), rb_fiber_scheduler_get()); }

    static VALUE e_eval(VALUE self, VALUE text) { return rb_eval_string(StringValueCStr(text)); }
    static VALUE e_protect(VALUE self, VALUE text) {
      int state = 99;
      VALUE r = rb_eval_string_protect(StringValueCStr(text), &state);
      VALUE err = rb_errinfo();
      rb_set_errinfo(Qnil);
      return rb_ary_new_from_args(3, r, INT2FIX(state), NIL_P(err) ? Qnil : rb_obj_class(err));
    }
    static VALUE e_load(VALUE self, VALUE path) {
      int state = 99;
      rb_load_protect(path, 0, &state);
      VALUE err = rb_errinfo();
      rb_set_errinfo(Qnil);
      return rb_ary_new_from_args(2, INT2FIX(state), NIL_P(err) ? Qnil : rb_funcall(err, rb_intern("message"), 0));
    }

    static VALUE o_misc(VALUE self, VALUE obj) {
      VALUE s = rb_any_to_s(obj);
      return rb_ary_new_from_args(3, rb_funcall(s, rb_intern("start_with?"), 1, rb_str_new_cstr("#<Object:0x")),
                                  rb_funcall(rb_obj_id(obj), rb_intern("=="), 1, rb_funcall(obj, rb_intern("object_id"), 0)),
                                  rb_class_attached_object(rb_singleton_class(obj)) == obj ? Qtrue : Qfalse);
    }
    static VALUE o_attached_bad(VALUE self) { return rb_class_attached_object(rb_cString); }
    static VALUE o_str_equal(VALUE self, VALUE a, VALUE b) { return rb_str_equal(a, b); }
    static VALUE o_to_float(VALUE self, VALUE v) { return rb_to_float(v); }
    static VALUE o_to_id(VALUE self, VALUE v) { return ID2SYM(rb_to_id(v)); }
    static VALUE o_enc_check(VALUE self, VALUE a, VALUE b) { return rb_enc_from_encoding(rb_enc_check(a, b)); }
    static VALUE o_during_gc(VALUE self) { return INT2FIX(rb_during_gc()); }
    static VALUE o_file_open(VALUE self, VALUE path) {
      VALUE f = rb_file_open_str(path, "r");
      VALUE line = rb_funcall(f, rb_intern("gets"), 0);
      rb_funcall(f, rb_intern("close"), 0);
      VALUE g = rb_file_open(StringValueCStr(path), "rb");
      VALUE bin = rb_funcall(g, rb_intern("binmode?"), 0);
      rb_funcall(g, rb_intern("close"), 0);
      return rb_assoc_new(line, bin);
    }

    static int update_i(st_data_t *key, st_data_t *value, st_data_t arg, int existing) {
      if (arg == 0) return ST_DELETE;
      *value = existing ? *value + arg : arg;
      return ST_CONTINUE;
    }
    static int collect_i(st_data_t key, st_data_t value, st_data_t out) {
      rb_ary_push((VALUE)out, rb_assoc_new(INT2FIX(key), INT2FIX(value)));
      return ST_CONTINUE;
    }
    static VALUE s_update(VALUE self) {
      st_table *t = st_init_numtable();
      int a = st_update(t, 1, update_i, 10);
      int b = st_update(t, 1, update_i, 5);
      int c = st_update(t, 2, update_i, 3);
      int d = st_update(t, 2, update_i, 0);
      VALUE rows = rb_ary_new();
      st_foreach(t, collect_i, (st_data_t)rows);
      st_clear(t);
      VALUE after = INT2FIX(t->num_entries);
      st_insert(t, 4, 40);
      st_foreach(t, collect_i, (st_data_t)rows);
      st_free_table(t);
      return rb_ary_new_from_args(6, INT2FIX(a), INT2FIX(b), INT2FIX(c), INT2FIX(d), rows, after);
    }
    static VALUE s_hashes(VALUE self) {
      st_index_t h1 = rb_st_hash_end(rb_st_hash_uint(rb_st_hash_uint32(rb_st_hash_start(1), 2), 3));
      st_index_t h2 = rb_st_hash_end(rb_st_hash_uint(rb_st_hash_uint32(rb_st_hash_start(1), 2), 3));
      st_index_t h3 = rb_st_hash_end(rb_st_hash_uint(rb_st_hash_uint32(rb_st_hash_start(1), 2), 4));
      return rb_ary_new_from_args(2, h1 == h2 ? Qtrue : Qfalse, h1 == h3 ? Qtrue : Qfalse);
    }

    static VALUE t_interval(VALUE self, VALUE v) {
      struct timeval tv = rb_time_interval(v);
      return rb_assoc_new(LONG2NUM(tv.tv_sec), LONG2NUM(tv.tv_usec));
    }
    static VALUE t_timeval(VALUE self, VALUE v) {
      struct timeval tv = rb_time_timeval(v);
      return rb_assoc_new(LONG2NUM(tv.tv_sec), LONG2NUM(tv.tv_usec));
    }

    static VALUE region_fn(void *data) { return (VALUE)data; }
    static VALUE t_region(VALUE self, VALUE io) {
      rb_io_t *fptr;
      GetOpenFile(io, fptr);
      return rb_thread_io_blocking_region(fptr, region_fn, (void *)Qtrue);
    }

    void Init_threads(void) {
      VALUE m = rb_define_module("Threads");
      rb_define_module_function(m, "create", t_create, 1);
      rb_define_module_function(m, "alone", t_alone, 0);
      rb_define_module_function(m, "main", t_main, 0);
      rb_define_module_function(m, "locals", t_locals, 0);
      rb_define_module_function(m, "run", t_stop_run, 1);
      rb_define_module_function(m, "stop", t_stop, 0);
      rb_define_module_function(m, "wait_for", t_wait_for, 0);
      rb_define_module_function(m, "mutex", m_mutex, 0);
      rb_define_module_function(m, "mutex_raising", m_raising, 1);
      rb_define_module_function(m, "fibers", f_fibers, 0);
      rb_define_module_function(m, "fiber_current", f_current, 0);
      rb_define_module_function(m, "fiber_raise", f_raise, 2);
      rb_define_module_function(m, "scheduler", f_scheduler, 0);
      rb_define_module_function(m, "eval", e_eval, 1);
      rb_define_module_function(m, "eval_protect", e_protect, 1);
      rb_define_module_function(m, "load", e_load, 1);
      rb_define_module_function(m, "misc", o_misc, 1);
      rb_define_module_function(m, "attached_bad", o_attached_bad, 0);
      rb_define_module_function(m, "str_equal", o_str_equal, 2);
      rb_define_module_function(m, "to_float", o_to_float, 1);
      rb_define_module_function(m, "to_id", o_to_id, 1);
      rb_define_module_function(m, "enc_check", o_enc_check, 2);
      rb_define_module_function(m, "during_gc", o_during_gc, 0);
      rb_define_module_function(m, "file_open", o_file_open, 1);
      rb_define_module_function(m, "st_update", s_update, 0);
      rb_define_module_function(m, "st_hashes", s_hashes, 0);
      rb_define_module_function(m, "interval", t_interval, 1);
      rb_define_module_function(m, "timeval", t_timeval, 1);
      rb_define_module_function(m, "region", t_region, 1);
    }
  C

  PROGRAM = <<~'RUBY'
    require "threads"

    def show(label)
      p [label, yield]
    rescue => e
      p [label, e.class, e.message]
    end

    class Stringy
      def to_str = "stringy"
    end

    show(:create) { Threads.create(21) }
    show(:alone) { [Threads.alone, (t = Thread.new { sleep 0.05 }; r = Threads.alone; t.join; r)] }
    show(:main) { [Threads.main, Thread.new { Threads.main }.value] }
    show(:locals) { [Threads.locals, Thread.current[:from_c]] }
    show(:stop_run) do
      t = Thread.new { Threads.stop; :woke }
      Thread.pass until t.stop?
      Threads.run(t)
      t.value
    end
    show(:wait_for) { Threads.wait_for }
    show(:mutex) { Threads.mutex }
    show(:mutex_raising) { m = Mutex.new; begin; Threads.mutex_raising(m); rescue => e; [e.message, m.locked?]; end }
    show(:fibers) { Threads.fibers }
    show(:fiber_current) { [Threads.fiber_current, Fiber.new { Threads.fiber_current }.resume] }
    show(:fiber_raise) { f = Fiber.new { Fiber.yield; :done }; f.resume; Threads.fiber_raise(f, RuntimeError.new("into the fiber")) }
    show(:scheduler) { Threads.scheduler }
    show(:eval) { [Threads.eval("1 + 2"), Threads.eval("self.to_s"), Threads.eval("[__FILE__ == '(eval)', __LINE__]")] }
    show(:eval_raise) { Threads.eval("raise ArgumentError, 'from eval'") }
    show(:eval_protect) { [Threads.eval_protect("40 + 2"), Threads.eval_protect("raise 'no'"), Threads.eval_protect("throw :x")] }
    show(:load) do
      good = File.join(__dir__, "loaded_good.rb")
      bad = File.join(__dir__, "loaded_bad.rb")
      File.write(good, "$loaded = :yes\n")
      File.write(bad, "raise 'bad file'\n")
      [Threads.load(good), $loaded, Threads.load(bad), Threads.load(File.join(__dir__, "missing.rb"))[0]]
    end
    show(:misc) { Threads.misc(Object.new) }
    show(:attached_bad) { Threads.attached_bad }
    show(:str_equal) { [Threads.str_equal("a", "a"), Threads.str_equal("a", "b"), Threads.str_equal("a", Stringy.new), Threads.str_equal("a", :a)] }
    show(:to_float) { [Threads.to_float(1), Threads.to_float(1.5), Threads.to_float(2**70), Threads.to_float(1r / 4)] }
    show(:to_float_nil) { Threads.to_float(nil) }
    show(:to_float_true) { Threads.to_float(true) }
    show(:to_float_string) { Threads.to_float("1.5") }
    show(:to_float_object) { Threads.to_float(Object.new) }
    show(:to_id) { [Threads.to_id(:a), Threads.to_id("b"), Threads.to_id(Stringy.new)] }
    show(:to_id_bad) { Threads.to_id(1) }
    show(:enc_check) { [Threads.enc_check("a", "b".b), Threads.enc_check("é", "a".b), Threads.enc_check("a".encode("UTF-16LE"), "")] }
    show(:enc_check_bad) { Threads.enc_check("é", "\xff".b) }
    show(:during_gc) { Threads.during_gc }
    show(:file_open) { Threads.file_open(__FILE__) }
    show(:file_open_missing) { Threads.file_open("/no/such/file") }
    show(:st_update) { Threads.st_update }
    show(:st_hashes) { Threads.st_hashes }
    show(:interval) { [Threads.interval(1), Threads.interval(1.25), Threads.interval(3r / 2), Threads.interval(0)] }
    show(:interval_negative) { Threads.interval(-1) }
    show(:interval_time) { Threads.interval(Time.at(1)) }
    show(:interval_string) { Threads.interval("1") }
    show(:timeval) { [Threads.timeval(Time.at(5, 250, :usec)), Threads.timeval(2), Threads.timeval(-1.5)] }
    show(:region) { Threads.region(IO.pipe[0]) }
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("threads", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
