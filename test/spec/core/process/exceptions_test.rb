# frozen_string_literal: true

require "spec_helper"

describe "Process: raising and rescuing" do
  it "at exit handler raise reports" do
    result = zr(<<~'RUBY')
      # An exception inside an at_exit handler is reported immediately, and the
      # remaining handlers still run (CRuby's rule; the status becomes 1).
      at_exit { puts "h-after" }
      at_exit { raise "handler boom" }
      at_exit { puts "h-before" }
      puts "body"
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR', status: 1
      body
      h-before
      h-after
    OUT
      core/process/exceptions_test.rb:4:in 'block in <main>': handler boom (RuntimeError)
    ERR
  end

  it "at exit handler that raises sets status 1" do
    result = zr(<<~'RUBY')
      # The handler's error is reported, the next handler still runs, and the
      # program ends with status 1.
      at_exit { puts :second }
      at_exit { raise "x" }
      puts 1

    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR', status: 1
      1
      second
    OUT
      core/process/exceptions_test.rb:4:in 'block in <main>': x (RuntimeError)
    ERR
  end

  it "class bodies execute at their document position and rerun per reopen" do
    result = zr(<<~'RUBY')
      # Real Ruby runs a class/module body WHERE IT APPEARS, interleaved
      # with surrounding top-level code, re-executing each reopen's body at
      # its own site; a rescued raise inside a module body shows the
      # `<module:M>` frame and `<main>` at the `module` keyword's line.
      # (Bodies used to be hoisted wholesale to the head of `run_main`,
      # printing before earlier top-level output and reading line 0.)

      puts "top1"
      class Foo
        puts "body1"
      end
      puts "top2"
      class Foo
        puts "body2"
      end
      class Outer
        puts "outer start"
        class Inner
          puts "inner body"
        end
        puts "outer end"
      end
      module M
        begin
          raise "inmod"
        rescue => e
          puts "rescued: #{e.backtrace[0]}"
          puts "from: #{e.backtrace[1]}"
        end
      end
      puts "top3"
    RUBY

    _(result).must_answer <<~'OUT'
      top1
      body1
      top2
      body2
      outer start
      inner body
      outer end
      rescued: core/process/exceptions_test.rb:25:in '<module:M>'
      from: core/process/exceptions_test.rb:23:in '<main>'
      top3
    OUT
  end

  it "failed exec names the program" do
    result = zr(<<~'RUBY')
      begin
        exec("/no/such/program-zr")
      rescue SystemCallError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer "Errno::ENOENT: No such file or directory - /no/such/program-zr\n"
  end

  it "instance exec no block error" do
    result = zr(<<~'RUBY')
      # Blockless instance_exec is LocalJumpError; blockless instance_eval (no
      # source string either) is the arity ArgumentError. Both oracle shapes.
      o = Object.new
      begin
        o.instance_exec
      rescue LocalJumpError => e
        puts "exec: #{e.class}: #{e.message}"
      end
      begin
        o.instance_eval
      rescue ArgumentError => e
        puts "eval: #{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      exec: LocalJumpError: no block given
      eval: ArgumentError: wrong number of arguments (given 0, expected 1..3)
    OUT
  end

  it "the CPU-time clock ids resolve to Integers, whatever the platform numbers them" do
    result = zr(<<~'RUBY')
      # The CPU-time clock ids resolve to Integers. Their exact value is the
      # platform's own clock id (it differs between Linux and macOS), so assert the
      # type, not the value. Regression for #2666.
      p((Process::CLOCK_PROCESS_CPUTIME_ID rescue $!.class).is_a?(Integer))
      p((Process::CLOCK_THREAD_CPUTIME_ID rescue $!.class).is_a?(Integer))
      p(Process::CLOCK_MONOTONIC.is_a?(Integer))
      p(Process::CLOCK_REALTIME.is_a?(Integer))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
    OUT
  end

  it "signal module" do
    result = zr(<<~'RUBY')
      # The Signal module and the SignalException/Interrupt hierarchy: name<->number
      # resolution (signame/list), trap as a validated no-op returning the prior
      # handler, and #signo/#signm on the exception objects.
      puts Signal.list["INT"]
      puts Signal.list["TERM"]
      puts Signal.signame(9)
      p Signal.signame(999)
      p Signal.signame(2.9)
      puts Signal.trap("USR1", "IGNORE")
      puts Signal.trap("USR1", "DEFAULT")
      p(begin; Signal.trap("NOPE", "IGNORE"); rescue => e; e.class; end)

      e = SignalException.new("INT")
      puts e.signo
      puts e.message
      puts SignalException.new(9).message
      p(begin; SignalException.new("NOPE"); rescue => x; x.class; end)

      i = Interrupt.new
      puts i.signo
      puts i.message
      puts Interrupt.new("stop").message
    RUBY

    _(result).must_answer <<~'OUT'
      2
      15
      KILL
      nil
      "INT"
      DEFAULT
      IGNORE
      ArgumentError
      2
      SIGINT
      SIGKILL
      ArgumentError
      2
      Interrupt
      stop
    OUT
  end

  it "trap quotes the signal name" do
    result = zr(<<~'RUBY')
      # `trap`'s unsupported-signal ArgumentError uses straight quotes in ruby 4
      # ("unsupported signal 'SIGNOPE'"); zr still uses the old backtick form.
      # (Found by the 2026-08-24 probe sweep.)
      begin
        trap("NOPE") { }
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer "unsupported signal 'SIGNOPE'\n"
  end

  it "uncaught exceptions still exit nonzero through the coroutine boundary" do
    result = zr(<<~'RUBY')
      # The top-level uncaught-raise contract (message on stderr, exit 1) must
      # survive the main body's Result crossing back to the OS main thread.

      raise "through the boundary"
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      core/process/exceptions_test.rb:4:in '<main>': through the boundary (RuntimeError)
    ERR
  end

  it "uncaught interrupt is reported and ends by sigint" do
    result = zr(<<~'RUBY')
      # Interrupt, unlike the other signals, is reported before the process
      # ends by SIGINT.
      at_exit { puts :handler }
      raise Interrupt

    RUBY

    _(result).must_answer "handler\n", stderr: <<~'ERR', status: nil, signal: 2
      core/process/exceptions_test.rb:4:in '<main>': Interrupt (Interrupt)
    ERR
  end

  it "uncaught no method error exits via the ordinary top level handler" do
    result = zr(<<~'RUBY')
      class Plain
      end
      Plain.new.send(:missing)
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      core/process/exceptions_test.rb:3:in '<main>': undefined method 'missing' for an instance of Plain (NoMethodError)

      Plain.new.send(:missing)
               ^^^^^
    ERR
  end

  it "uncaught raise with no rescue anywhere exits with the message" do
    result = zr(<<~'RUBY')
      raise "boom"
    RUBY

    _(result).must_answer "", stderr: "core/process/exceptions_test.rb:1:in '<main>': boom (RuntimeError)\n", status: 1
  end

  it "uncaught signal exception ends by its signal" do
    result = zr(<<~'RUBY')
      # The handlers run, nothing is reported, and the process ends by the
      # signal itself.
      at_exit { puts :handler, $!.class }
      raise SignalException, "TERM"

    RUBY

    _(result).must_answer "handler\nSignalException\n", status: nil, signal: 15
  end

  it "unrescued definition raise aborts where ruby aborts" do
    result = zr(<<~'RUBY')
      # The other half of `a_definition_ruby_raises_on_raises`: with nothing to
      # catch it, the program runs up to the definition and then dies exactly where
      # ruby dies -- same message, same backtrace line, same exit status. The
      # statements ABOVE it still run and still print, which is what a compile-time
      # refusal took away.
      puts "before"

      class Base; end
      class Other; end
      class Sub < Base; end
      class Sub < Other
        def never = "unreachable"
      end

      puts "after"
    RUBY

    _(result).must_answer "before\n", stderr: <<~'ERR', status: 1
      core/process/exceptions_test.rb:11:in '<main>': superclass mismatch for class Sub (TypeError)
    ERR
  end
end
