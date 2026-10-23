# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# The C API's signals, child processes and ends of the program: kill and
# signal names, the default handling of a signal, pending interrupts,
# `$?`, waits, spawns, exec, and exit, abort and fatal errors. Each gives
# ruby's answer. A call that ends or replaces the process runs in a child.
class CExtProcessCApiTest < Minitest::Test
  SOURCE = <<~'C'
    #include <ruby.h>
    #include <errno.h>
    #include <signal.h>
    #include <string.h>
    #include <unistd.h>

    static VALUE kill_(int argc, VALUE *argv, VALUE self) { return rb_f_kill(argc, argv); }
    static VALUE signal_name(VALUE self, VALUE n) {
      const char *name = ruby_signal_name(NUM2INT(n));
      return name ? rb_str_new_cstr(name) : Qnil;
    }
    static VALUE signal_name_kept(VALUE self, VALUE n) {
      return ruby_signal_name(NUM2INT(n)) == ruby_signal_name(NUM2INT(n)) ? Qtrue : Qfalse;
    }
    static VALUE default_signal(VALUE self, VALUE n) { ruby_default_signal(NUM2INT(n)); return Qtrue; }
    static VALUE interrupted(VALUE self, VALUE th) { return rb_thread_interrupted(th) ? Qtrue : Qfalse; }
    static VALUE interrupted_after_kill(VALUE self, VALUE n) {
      kill(getpid(), NUM2INT(n));
      return rb_thread_interrupted(rb_thread_current()) ? Qtrue : Qfalse;
    }
    static VALUE interrupt(VALUE self) { rb_interrupt(); return Qnil; }
    static VALUE exit_(VALUE self, VALUE n) { rb_exit(NUM2INT(n)); return Qnil; }
    static VALUE f_exit(int argc, VALUE *argv, VALUE self) { return rb_f_exit(argc, argv); }
    static VALUE f_abort(int argc, VALUE *argv, VALUE self) { return rb_f_abort(argc, argv); }
    static VALUE exc_fatal(VALUE self, VALUE exc) { rb_exc_fatal(exc); return Qnil; }
    static VALUE status_set(VALUE self, VALUE status, VALUE pid) { rb_last_status_set(NUM2INT(status), NUM2PIDT(pid)); return Qnil; }
    static VALUE status_get(VALUE self) { return rb_last_status_get(); }
    static VALUE waitpid_(VALUE self, VALUE pid, VALUE flags) {
      int status = -7;
      errno = 0;
      rb_pid_t got = rb_waitpid(NUM2PIDT(pid), &status, NUM2INT(flags));
      return rb_ary_new_from_args(3, PIDT2NUM(got), INT2FIX(status), INT2FIX(got == -1 ? errno : 0));
    }
    static VALUE waitpid_null(VALUE self, VALUE pid) { return PIDT2NUM(rb_waitpid(NUM2PIDT(pid), NULL, 0)); }
    static VALUE syswait(VALUE self, VALUE pid) { rb_syswait(NUM2PIDT(pid)); return Qnil; }
    static VALUE detach(VALUE self, VALUE pid) { return rb_detach_process(NUM2PIDT(pid)); }
    static VALUE spawn_(int argc, VALUE *argv, VALUE self) {
      errno = 0;
      rb_pid_t pid = rb_spawn(argc, argv);
      return rb_ary_new_from_args(2, PIDT2NUM(pid), INT2FIX(pid == -1 ? errno : 0));
    }
    static VALUE spawn_err_in(int argc, VALUE *argv, size_t size) {
      char buf[16];
      memset(buf, 'x', sizeof(buf));
      buf[sizeof(buf) - 1] = '\0';
      errno = 0;
      rb_pid_t pid = rb_spawn_err(argc, argv, buf, size);
      return rb_ary_new_from_args(3, PIDT2NUM(pid), INT2FIX(pid == -1 ? errno : 0), rb_str_new_cstr(buf));
    }
    static VALUE spawn_err(int argc, VALUE *argv, VALUE self) { return spawn_err_in(argc, argv, 16); }
    static VALUE spawn_err_short(int argc, VALUE *argv, VALUE self) { return spawn_err_in(argc, argv, 3); }
    static VALUE f_exec(int argc, VALUE *argv, VALUE self) { return rb_f_exec(argc, argv); }
    static VALUE proc_exec(VALUE self, VALUE command) {
      errno = 0;
      int result = rb_proc_exec(StringValueCStr(command));
      return rb_ary_new_from_args(2, INT2FIX(result), INT2FIX(errno));
    }
    static VALUE times(VALUE self) { return rb_proc_times(Qnil); }
    static VALUE c_fork(VALUE self) {
      pid_t pid = fork();
      if (pid == 0) {
        rb_thread_atfork();
        return Qnil;
      }
      return PIDT2NUM(pid);
    }
    static VALUE c_fork_exec(VALUE self, VALUE command) {
      pid_t pid = fork();
      if (pid == 0) {
        rb_thread_atfork_before_exec();
        rb_proc_exec(StringValueCStr(command));
        _exit(127);
      }
      return PIDT2NUM(pid);
    }
    static VALUE sleep_deadly(VALUE self) { rb_thread_sleep_deadly(); return Qtrue; }

    void Init_proc_ext(void) {
      VALUE m = rb_define_module("ProcExt");
      rb_define_module_function(m, "kill", kill_, -1);
      rb_define_module_function(m, "signal_name", signal_name, 1);
      rb_define_module_function(m, "signal_name_kept?", signal_name_kept, 1);
      rb_define_module_function(m, "default_signal", default_signal, 1);
      rb_define_module_function(m, "interrupted?", interrupted, 1);
      rb_define_module_function(m, "interrupted_after_kill?", interrupted_after_kill, 1);
      rb_define_module_function(m, "interrupt", interrupt, 0);
      rb_define_module_function(m, "exit", exit_, 1);
      rb_define_module_function(m, "f_exit", f_exit, -1);
      rb_define_module_function(m, "f_abort", f_abort, -1);
      rb_define_module_function(m, "exc_fatal", exc_fatal, 1);
      rb_define_module_function(m, "status_set", status_set, 2);
      rb_define_module_function(m, "status_get", status_get, 0);
      rb_define_module_function(m, "waitpid", waitpid_, 2);
      rb_define_module_function(m, "waitpid_null", waitpid_null, 1);
      rb_define_module_function(m, "syswait", syswait, 1);
      rb_define_module_function(m, "detach", detach, 1);
      rb_define_module_function(m, "spawn", spawn_, -1);
      rb_define_module_function(m, "spawn_err", spawn_err, -1);
      rb_define_module_function(m, "spawn_err_short", spawn_err_short, -1);
      rb_define_module_function(m, "f_exec", f_exec, -1);
      rb_define_module_function(m, "proc_exec", proc_exec, 1);
      rb_define_module_function(m, "times", times, 0);
      rb_define_module_function(m, "c_fork", c_fork, 0);
      rb_define_module_function(m, "c_fork_exec", c_fork_exec, 1);
      rb_define_module_function(m, "sleep_deadly", sleep_deadly, 0);
    }
  C

  PROGRAM = <<~'RUBY'
    require "proc_ext"
    $stdout.sync = true

    def outcome
      yield
    rescue Exception => e
      [e.class, e.message]
    end

    # A call that ends or replaces the process runs in a child: its exit
    # status and the signal that ended it.
    def child(&block)
      Process.wait(fork(&block))
      [$?.exitstatus, $?.termsig]
    end

    def wait_for(list)
      100.times { break unless list.empty?; sleep 0.01 }
      list
    end

    puts "-- rb_f_kill"
    got = []
    Signal.trap(:USR1) { got << :usr1 }
    p ProcExt.kill(:USR1, Process.pid)
    p wait_for(got)
    p ProcExt.kill(0, Process.pid, Process.pid)
    p outcome { ProcExt.kill(:USR1) }
    p outcome { ProcExt.kill(:NO_SUCH_SIGNAL, Process.pid) }
    p outcome { ProcExt.kill("-USR1", Process.pid) }.class

    puts "-- ruby_signal_name"
    p [2, 9, 15, 0, -1, 1000].map { |n| ProcExt.signal_name(n) }
    p ProcExt.signal_name(Signal.list.fetch("USR2")) == "USR2"
    p ProcExt.signal_name_kept?(2)

    puts "-- ruby_default_signal"
    p child { Signal.trap(:TERM) { puts "trapped" }; ProcExt.default_signal(15); puts "not reached" }
    p child { Signal.trap(:CHLD) { puts "chld" }; p ProcExt.default_signal(Signal.list.fetch("CHLD")); exit 3 }

    puts "-- rb_thread_interrupted"
    p ProcExt.interrupted?(Thread.current)
    sleeper = Thread.new { sleep }
    10.times { break if sleeper.stop?; sleep 0.01 }
    p ProcExt.interrupted?(sleeper)
    sleeper.kill.join
    got = []
    Signal.trap(:USR2) { got << :usr2 }
    p ProcExt.interrupted_after_kill?(Signal.list.fetch("USR2"))
    p wait_for(got)
    p ProcExt.interrupted?(Thread.current)

    puts "-- rb_interrupt"
    p outcome { ProcExt.interrupt }
    e = begin; ProcExt.interrupt; rescue Interrupt => error; error; end
    p [e.signo, e.is_a?(SignalException)]

    puts "-- rb_exit"
    p outcome { ProcExt.exit(3) }
    p (begin; ProcExt.exit(3); rescue SystemExit => error; [error.status, error.success?]; end)
    p child { ProcExt.exit(4) }
    p child { at_exit { puts "at_exit runs" }; ProcExt.exit(0) }

    puts "-- rb_f_exit"
    p outcome { ProcExt.f_exit }
    p (begin; ProcExt.f_exit(false); rescue SystemExit => error; error.status; end)
    p outcome { ProcExt.f_exit(5, 6) }
    p child { ProcExt.f_exit(7) }
    p child { ProcExt.f_exit(true) }

    puts "-- rb_f_abort"
    p child { STDERR.reopen(STDOUT); ProcExt.f_abort("goodbye") }
    p (begin; ProcExt.f_abort; rescue SystemExit => error; [error.status, error.message]; end)

    puts "-- rb_exc_fatal"
    p child { at_exit { puts "at_exit after fatal" }; begin; ProcExt.exc_fatal(RuntimeError.new("boom")); rescue Exception; puts "rescued"; ensure; puts "ensure"; end }
    # After an ensure clause that the program wrote, it goes on as a raise.
    p child {
      begin
        begin
          ProcExt.exc_fatal(RuntimeError.new("inner"))
        ensure
          puts "inner ensure"
        end
      rescue Exception => e
        puts "outer rescued #{e.class}: #{e.message}"
      end
      puts "goes on"
    }
    def ends_in_ensure = ProcExt.exc_fatal(RuntimeError.new("method"))
    def with_ensure
      ends_in_ensure
    ensure
      puts "method ensure"
    end
    p child { begin; with_ensure; rescue Exception => e; puts "rescued after the method's ensure: #{e.message}"; end }
    p child { begin; ProcExt.exc_fatal(RuntimeError.new("bare")); rescue Exception; puts "rescued"; end; puts "not reached" }
    # In a thread it ends the thread with the error, unreported, and the
    # main thread gets it; after an ensure it is a raise there too.
    p child {
      STDERR.reopen(STDOUT)
      thread = Thread.new { ProcExt.exc_fatal(RuntimeError.new("thread")) }
      begin
        thread.join
        puts "joined"
        sleep 1
      rescue Exception => e
        puts "main got #{e.class}: #{e.message}"
      end
      p thread.status
    }
    p child {
      STDERR.reopen(STDOUT)
      Thread.report_on_exception = false
      thread = Thread.new { begin; ProcExt.exc_fatal(RuntimeError.new("thread ensure")); rescue Exception; puts "thread rescued"; ensure; puts "thread ensure"; end }
      begin
        thread.join
        puts "joined"
      rescue Exception => e
        puts "main got #{e.class}: #{e.message}"
      end
      p thread.status
    }

    puts "-- rb_last_status_set and rb_last_status_get"
    system("exit 1")
    p ProcExt.status_get.equal?($?)
    ProcExt.status_set(3 << 8, 1234)
    p [$?.pid, $?.exitstatus, $?.frozen?, $?.inspect]
    ProcExt.status_set(9, 77)
    p [$?.termsig, $?.to_s]
    p Thread.new { ProcExt.status_get }.value

    puts "-- rb_waitpid"
    pid = spawn("exit 7")
    r = ProcExt.waitpid(pid, 0)
    p [r[0] == pid, r[1] >> 8, r[2], $?.pid == pid, $?.exitstatus]
    r = ProcExt.waitpid(pid, 0)
    p [r, r[2] == Errno::ECHILD::Errno, $?.pid == pid]
    pid = spawn("sleep 5")
    p ProcExt.waitpid(pid, Process::WNOHANG)
    Process.kill(:TERM, pid)
    r = ProcExt.waitpid(pid, 0)
    p [r[0] == pid, r[1] & 0x7f, $?.termsig]
    p ProcExt.waitpid_null(spawn("true")).positive?

    puts "-- rb_syswait"
    pid = spawn("exit 2")
    p ProcExt.syswait(pid)
    p [$?.pid == pid, $?.exitstatus]
    ProcExt.syswait(pid)
    p $?.exitstatus

    puts "-- rb_detach_process"
    waiter = ProcExt.detach(spawn("exit 9"))
    p [waiter.class, waiter.value.exitstatus, waiter.pid.positive?]
    p ProcExt.detach(1).value

    puts "-- rb_spawn"
    r = ProcExt.spawn("echo", "spawned")
    Process.wait(r[0])
    p r[1]
    Process.wait(ProcExt.spawn("pwd", { chdir: "/" })[0])
    Process.wait(ProcExt.spawn({ "ZR_CAPI" => "from env" }, "echo $ZR_CAPI")[0])
    p ProcExt.spawn("zr-test-no-such-command")
    p $?.exitstatus
    p outcome { ProcExt.spawn }
    p outcome { ProcExt.spawn("true", { no_such_option: 1 }) }

    puts "-- rb_spawn_err"
    p ProcExt.spawn_err("pwd", { chdir: "/zr-test-no-such-dir" })
    p ProcExt.spawn_err("zr-test-no-such-command")
    p ProcExt.spawn_err_short("pwd", { chdir: "/zr-test-no-such-dir" })
    r = ProcExt.spawn_err("true")
    Process.wait(r[0])
    p r[1..]

    puts "-- rb_f_exec"
    p child { ProcExt.f_exec("echo", "exec'd") }
    p child { ProcExt.f_exec("sh", "-c", "exit 6") }
    p child { ProcExt.f_exec({ "ZR_CAPI" => "exec env" }, "echo $ZR_CAPI") }
    p child { ProcExt.f_exec("pwd", { chdir: "/" }) }
    p outcome { ProcExt.f_exec("zr-test-no-such-command") }
    p outcome { ProcExt.f_exec }

    puts "-- rb_proc_exec"
    p child { ProcExt.proc_exec("echo via sh; exit 3") }
    p ProcExt.proc_exec(" \t\n") == [-1, Errno::ENOENT::Errno]
    p ProcExt.proc_exec("") == [-1, Errno::ENOENT::Errno]

    puts "-- rb_proc_times"
    t = ProcExt.times
    p [t.class, t.members, t.to_a.all?(Float)]

    puts "-- rb_thread_atfork"
    sleeper = Thread.new { sleep }
    10.times { break if sleeper.stop?; sleep 0.01 }
    pid = ProcExt.c_fork
    if pid.nil?
      p [Thread.list.size, Thread.main.equal?(Thread.current), sleeper.alive?]
      exit!(0)
    end
    Process.wait(pid)
    p [$?.exitstatus, Thread.list.size]
    sleeper.kill.join

    puts "-- rb_thread_atfork_before_exec"
    Process.wait(ProcExt.c_fork_exec("echo exec after fork; exit 4"))
    p $?.exitstatus

    puts "-- rb_thread_sleep_deadly"
    main = Thread.current
    # A wakeup before the sleep starts would be lost, and the sleep has no end.
    waker = Thread.new { Thread.pass until main.stop?; main.wakeup }
    p ProcExt.sleep_deadly
    waker.join
    p child { STDERR.reopen(File::NULL); ProcExt.sleep_deadly; puts "not reached" }
  RUBY

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
  end

  def test_each_function_gives_rubys_answer
    ruby, zr = Zr::Test::CExt.outputs(Zr::Test::CExt.build("proc_ext", SOURCE), PROGRAM)
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
    # The reports of the fatal errors: the place, the message and the frames.
    assert_equal ruby.stderr, zr.stderr
  end

  def test_the_answers_hold_under_the_collectors_stress
    ext = Zr::Test::CExt.build("proc_ext", SOURCE)
    ruby, (zr,) = Zr::Test::CExt.outputs_under(ext, PROGRAM, [{ "ZR_GC_STRESS" => "1" }])
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
  end
end
