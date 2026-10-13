# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API of ruby/debug.h for sampling profilers
# (kernel/capi/profile.rb, kernel/postponed_jobs.rb), as stackprof,
# vernier and datadog use it: the frames that run and what each one
# names, jobs that run at the next safe point, a SIGPROF handler that
# samples the frames and triggers a job, and a T_DATA that keeps frames
# and marks them, as stackprof's does, against ruby's answers. A frame
# is no Fixnum: stackprof keeps its own frames as Fixnums.
class CExtProfileFramesTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <ruby/debug.h>
    #include <signal.h>
    #include <sys/time.h>

    static VALUE basename(VALUE path) {
      return NIL_P(path) ? Qnil : rb_funcall(rb_cFile, rb_intern("basename"), 1, path);
    }

    static VALUE describe(VALUE frame, int line) {
      VALUE abs = rb_profile_frame_absolute_path(frame);
      VALUE shown_abs = NIL_P(abs) ? Qnil : (rb_str_equal(abs, rb_str_new_cstr("<cfunc>")) == Qtrue ? abs : Qtrue);
      VALUE row = rb_ary_new_from_args(6, basename(rb_profile_frame_path(frame)), shown_abs, rb_profile_frame_label(frame),
                                       rb_profile_frame_base_label(frame), rb_profile_frame_full_label(frame),
                                       rb_profile_frame_first_lineno(frame));
      rb_ary_push(row, rb_profile_frame_classpath(frame));
      rb_ary_push(row, rb_profile_frame_singleton_method_p(frame));
      rb_ary_push(row, rb_profile_frame_method_name(frame));
      rb_ary_push(row, rb_profile_frame_qualified_method_name(frame));
      rb_ary_push(row, INT2NUM(line));
      return row;
    }

    static VALUE pf_frames(VALUE self, VALUE start, VALUE limit) {
      VALUE buff[64];
      int lines[64];
      int n = rb_profile_frames(NUM2INT(start), NUM2INT(limit), buff, lines);
      VALUE out = rb_ary_new();
      for (int i = 0; i < n; i++) rb_ary_push(out, describe(buff[i], lines[i]));
      return out;
    }

    /* Two samples in one place name the same frames, as a profiler's
       table keys them. */
    static VALUE pf_same(VALUE self) {
      VALUE a[8], b[8];
      int n = rb_profile_frames(0, 8, a, NULL);
      int m = rb_profile_frames(0, 8, b, NULL);
      if (n != m) return Qfalse;
      for (int i = 0; i < n; i++) if (a[i] != b[i]) return Qfalse;
      rb_gc_mark(a[0]);
      return Qtrue;
    }

    static VALUE pf_thread_frames(VALUE self, VALUE thread) {
      VALUE buff[64];
      int lines[64];
      int n = rb_profile_thread_frames(thread, 0, 64, buff, lines);
      VALUE out = rb_ary_new();
      for (int i = 0; i < n; i++) rb_ary_push(out, rb_profile_frame_full_label(buff[i]));
      return out;
    }

    /* A frame is no Fixnum and no special constant, as a pointer is. */
    static VALUE pf_kind(VALUE self) {
      VALUE frame;
      rb_profile_frames(0, 1, &frame, NULL);
      return rb_ary_new_from_args(2, FIXNUM_P(frame) ? Qtrue : Qfalse, RB_SPECIAL_CONST_P(frame) ? Qtrue : Qfalse);
    }

    /* stackprof keeps its frames in a table that its T_DATA marks. */
    struct kept { int n; VALUE frames[16]; };

    static void kept_mark(void *p) {
      struct kept *k = p;
      for (int i = 0; i < k->n; i++) rb_gc_mark(k->frames[i]);
    }

    static const rb_data_type_t kept_type = {"kept", {kept_mark, RUBY_TYPED_DEFAULT_FREE, NULL}, 0, 0, 0};

    static VALUE pf_keep(VALUE self) {
      struct kept *k;
      VALUE obj = TypedData_Make_Struct(rb_cObject, struct kept, &kept_type, k);
      k->n = rb_profile_frames(0, 16, k->frames, NULL);
      return obj;
    }

    static VALUE pf_kept(VALUE self, VALUE obj) {
      struct kept *k = rb_check_typeddata(obj, &kept_type);
      VALUE out = rb_ary_new();
      for (int i = 0; i < k->n; i++) rb_ary_push(out, rb_profile_frame_full_label(k->frames[i]));
      return out;
    }

    static int ran;
    static void job(void *data) { ran += (int)(long)data; }
    static void other_job(void *data) { ran += 100; }

    static VALUE pf_jobs(VALUE self) {
      rb_postponed_job_handle_t h = rb_postponed_job_preregister(0, job, (void *)1);
      rb_postponed_job_handle_t again = rb_postponed_job_preregister(0, job, (void *)2);
      ran = 0;
      rb_postponed_job_trigger(h);
      rb_postponed_job_trigger(h);
      return rb_ary_new_from_args(2, h == again ? Qtrue : Qfalse, INT2NUM(ran));
    }

    /* Two jobs of two functions, each triggered once. */
    static VALUE pf_register(VALUE self) {
      ran = 0;
      rb_postponed_job_trigger(rb_postponed_job_preregister(0, other_job, 0));
      rb_postponed_job_trigger(rb_postponed_job_preregister(0, job, (void *)2));
      return Qtrue;
    }

    static VALUE pf_ran(VALUE self) { return INT2NUM(ran); }

    /* stackprof: a SIGPROF handler samples the frames and triggers a job
       that keeps the sample. */
    static VALUE samples[256];
    static int sample_lines[256];
    static int sampled, taken;
    static rb_postponed_job_handle_t keep;

    static void keep_sample(void *data) { taken++; }

    static void on_prof(int sig) {
      if (sampled > 0) return;
      sampled = rb_profile_frames(0, 256, samples, sample_lines);
      rb_postponed_job_trigger(keep);
    }

    static VALUE pf_sample(VALUE self) {
      keep = rb_postponed_job_preregister(0, keep_sample, 0);
      sampled = taken = 0;
      struct sigaction sa = {0};
      sa.sa_handler = on_prof;
      sa.sa_flags = SA_RESTART;
      sigaction(SIGPROF, &sa, NULL);
      struct itimerval timer = {{0, 1000}, {0, 1000}};
      setitimer(ITIMER_PROF, &timer, NULL);
      VALUE result = rb_yield(Qnil);
      struct itimerval off = {{0, 0}, {0, 0}};
      setitimer(ITIMER_PROF, &off, NULL);
      signal(SIGPROF, SIG_IGN);
      VALUE labels = rb_ary_new();
      for (int i = 0; i < sampled; i++) rb_ary_push(labels, rb_profile_frame_full_label(samples[i]));
      return rb_ary_new_from_args(3, sampled > 0 ? Qtrue : Qfalse, taken > 0 ? Qtrue : Qfalse, labels);
    }

    void Init_prof(void) {
      VALUE m = rb_define_module("Prof");
      rb_define_module_function(m, "frames", pf_frames, 2);
      rb_define_module_function(m, "same?", pf_same, 0);
      rb_define_module_function(m, "thread_frames", pf_thread_frames, 1);
      rb_define_module_function(m, "jobs", pf_jobs, 0);
      rb_define_module_function(m, "register", pf_register, 0);
      rb_define_module_function(m, "ran", pf_ran, 0);
      rb_define_module_function(m, "sample", pf_sample, 0);
      rb_define_module_function(m, "kind", pf_kind, 0);
      rb_define_module_function(m, "keep", pf_keep, 0);
      rb_define_module_function(m, "kept", pf_kept, 1);
    }
  C

  PROGRAM = <<~'RUBY'
    require "prof"

    def show(label)
      p [label, yield]
    rescue StandardError => e
      p [label, e.class, e.message]
    end

    class Shape
      def area(w, h)
        product = w * h
        Prof.frames(0, 4)
      end

      def self.make = Prof.frames(0, 3)

      def each_side = [1].map { |side| Prof.frames(0, 4) }.first
    end

    module Tool
      def self.run = Prof.frames(0, 2)
    end

    obj = Object.new
    def obj.solo = Prof.frames(0, 2)

    Shape.new.area(2, 3).each { |row| p [:area, row] }
    Shape.make.each { |row| p [:make, row] }
    Shape.new.each_side.each { |row| p [:block, row] }
    Tool.run.each { |row| p [:module, row] }
    solo = obj.solo[1]
    p [:singleton, solo.values_at(2, 3, 7, 8), solo[6].match?(/\A#<Object:0x\h{16}>\z/)]
    p [:skip, Prof.frames(1, 2).map { |row| row[4] }]
    p [:top, Prof.frames(0, 2).map { |row| row[4] }]
    show(:same) { Prof.same? }
    show(:kind) { Prof.kind }
    def keep_here = Prof.keep
    kept = keep_here
    GC.start
    show(:kept) { Prof.kept(kept).first(2) }

    other = Thread.new { Thread.stop; :done }
    Thread.pass until other.status == "sleep"
    show(:thread) { Prof.thread_frames(other) }
    other.run
    other.join

    show(:jobs) { Prof.jobs }
    show(:jobs_ran) { 3.times { |i| i }; Prof.ran }
    show(:register) { Prof.register }
    show(:register_ran) { 3.times { |i| i }; Prof.ran }

    def busy
      deadline = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) + 0.05
      x = 0
      x += 1 while Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) < deadline
      x
    end
    sampled, taken, labels = Prof.sample { busy }
    p [:sample, sampled, taken, labels.include?("Object#busy")]
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @ext = Zr::Test::CExt.build("prof", SOURCE)
  end

  def test_each_function_gives_rubys_answer
    ruby, (plain, stressed) = Zr::Test::CExt.outputs_under(@ext, PROGRAM, [{}, { "ZR_GC_STRESS" => "1" }])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [plain.stdout, plain.status], "zr stderr:\n#{plain.stderr}"
    assert_equal [ruby.stdout, ruby.status], [stressed.stdout, stressed.status], "zr stderr under stress:\n#{stressed.stderr}"
  end
end
