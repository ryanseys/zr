# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: defining and naming methods" do
  it "alias of the inherited builtin raise works in every call shape" do
    result = zr(<<~'RUBY')
      # `alias_method :raise!, :raise` / `alias __raise__ raise` (ostruct's and
      # delegate's shapes): the source is Kernel's BUILTIN raise -- no user
      # `Scope` exists, so this used to be a compile error. Statically-resolved
      # sites substitute into the raise lowering (including the bare re-raise and the
      # 3-arg form, whose custom-backtrace argument is evaluated and dropped);
      # all outputs oracle-verified.

      class Reporter
        alias_method :raise!, :raise
        def two_arg
          raise! ArgumentError, "boom"
        rescue ArgumentError => e
          puts e.message
        end
        def re_raise
          begin
            raise IOError, "orig"
          rescue
            raise!
          end
        rescue IOError => e
          puts e.message
        end
        def three_arg
          raise! ArgumentError, "with-bt", caller(0)
        rescue ArgumentError => e
          puts e.message
        end
      end
      class Failer
        alias __raise__ raise
        def go
          __raise__ NotImplementedError, "need to define"
        rescue NotImplementedError => e
          puts e.message
        end
      end
      r = Reporter.new
      r.two_arg
      r.re_raise
      r.three_arg
      Failer.new.go
    RUBY

    _(result).must_answer <<~'OUT'
      boom
      orig
      with-bt
      need to define
    OUT
  end

  it "bare rescue does not catch a script error level exception" do
    result = zr(<<~'RUBY')
      # A bare `rescue` matches `StandardError` and below ONLY -- it must NOT
      # catch a raised `ScriptError` (a sibling branch of the hierarchy, both
      # direct children of `Exception`). This is the real semantic bare
      # `rescue`'s default narrows to `StandardError`, not `Exception`.

      begin
        begin
          raise ScriptError, "script problem"
        rescue => e
          puts "should not print: #{e.send(:message)}"
        end
      rescue ScriptError => e
        puts "outer caught ScriptError: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "outer caught ScriptError: script problem\n"
  end

  it "begin ensure with no rescue clause still runs ensure and propagates" do
    result = zr(<<~'RUBY')
      begin
        begin
          raise "boom"
        ensure
          puts "ensure ran"
        end
      rescue => e
        puts "caught outside: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "ensure ran\ncaught outside: boom\n"
  end

  it "begin rescue catches and ensure always runs" do
    result = zr(<<~'RUBY')
      begin
        puts "try"
        raise ArgumentError, "bad"
      rescue ArgumentError => e
        puts "caught: #{e.send(:message)}"
      ensure
        puts "ensure ran"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      try
      caught: bad
      ensure ran
    OUT
  end

  it "def in a rescue clause is not promised" do
    result = zr(<<~'RUBY')
      # The nested walk reaches a `rescue` clause, but reaching it is not the same as
      # promising it: the clause runs only if the body raised. The method's name goes
      # on record so a static call site stops folding, and reflection still answers
      # what actually ran.
      class Guarded
        begin
          Integer("1")
        rescue StandardError
          def only_on_failure
            :recovered
          end
        end
      end

      p Guarded.instance_methods(false)
      p Guarded.new.respond_to?(:only_on_failure)

      class Recovered
        begin
          Integer("not a number")
        rescue StandardError
          def only_on_failure
            :recovered
          end
        end
      end

      p Recovered.instance_methods(false)
      p Recovered.new.only_on_failure
    RUBY

    _(result).must_answer <<~'OUT'
      []
      false
      [:only_on_failure]
      :recovered
    OUT
  end

  it "error highlight library" do
    result = zr(<<~'RUBY')
      # error_highlight is loaded before the program, as ruby's gem prelude
      # loads it: a require of it answers false, and `detailed_message` shows
      # the line with a caret run under the call that failed. The program
      # carries no parser; the compiler found each spot while it held the tree.

      p require("error_highlight")
      p defined?(ErrorHighlight)
      p ErrorHighlight.respond_to?(:spot)

      def boom
        nil.nope
      rescue NoMethodError => e
        puts e.detailed_message(highlight: false)
      end
      boom

    RUBY

    _(result).must_answer <<~'OUT'
      false
      "constant"
      true
      undefined method 'nope' for nil (NoMethodError)
      
        nil.nope
           ^^^^^
    OUT
  end

  it "a raise takes the rescue arm and then the ensure" do
    result = zr(<<~'RUBY')
      begin
        puts "try"
        raise ArgumentError, "bad"
      rescue ArgumentError => e
        puts "caught: #{e.send(:message)}"
      ensure
        puts "ensure ran"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      try
      caught: bad
      ensure ran
    OUT
  end

  it "a body that raises nothing takes the else arm and then the ensure" do
    result = zr(<<~'RUBY')
      begin
        puts "body"
      rescue => e
        puts "rescued"
      else
        puts "else ran"
      ensure
        puts "ensure2 ran"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      body
      else ran
      ensure2 ran
    OUT
  end

  it "a subclass is caught by its parent's arm" do
    result = zr(<<~'RUBY')
      class AppError < StandardError
      end
      class ValidationError < AppError
      end

      begin
        raise ValidationError, "bad input"
      rescue AppError => e
        puts "caught as AppError: #{e.send(:message)}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      caught as AppError: bad input
    OUT
  end

  it "one arm naming several classes catches any of them" do
    result = zr(<<~'RUBY')
      begin
        raise TypeError, "wrong type"
      rescue ArgumentError, TypeError => e
        puts "caught one of: #{e.send(:message)}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      caught one of: wrong type
    OUT
  end

  it "a retry runs the body again, and the ensure sees how many attempts it took" do
    result = zr(<<~'RUBY')
      class Attempt
        def initialize
          @attempts = 0
        end

        def attempts
          @attempts
        end

        def run
          begin
            @attempts += 1
            raise "fail" if @attempts < 3
            puts "succeeded after #{@attempts} attempts"
          rescue
            retry if @attempts < 3
          ensure
            puts "ensure ran, attempts=#{@attempts}"
          end
        end
      end
      Attempt.new.run

    RUBY

    _(result).must_answer <<~'OUT'
      succeeded after 3 attempts
      ensure ran, attempts=3
    OUT
  end

  it "a method-body rescue needs no begin of its own" do
    result = zr(<<~'RUBY')
      class Worker
        def safe
          raise "oops"
        rescue => e
          "handled: #{e.send(:message)}"
        end
      end
      puts Worker.new.safe

    RUBY

    _(result).must_answer <<~'OUT'
      handled: oops
    OUT
  end

  it "an ensure runs before the return it wraps" do
    result = zr(<<~'RUBY')
      class ReturnTester
        def m
          begin
            raise "x"
          rescue
            return "returned"
          ensure
            puts "ensure ran before return"
          end
        end
      end
      puts ReturnTester.new.m

    RUBY

    _(result).must_answer <<~'OUT'
      ensure ran before return
      returned
    OUT
  end

  it "a rescue modifier supplies the value where the expression raises" do
    result = zr(<<~'RUBY')
      class Unsafe
        def op(n)
          raise "negative" if n < 0
          n * 2
        end
      end
      class Calc
        def safe_op(n) = Unsafe.new.op(n) rescue -1
      end
      c = Calc.new
      puts c.safe_op(5)
      puts c.safe_op(-5)

    RUBY

    _(result).must_answer <<~'OUT'
      10
      -1
    OUT
  end

  it "a rescue arm's value is the begin's value" do
    result = zr(<<~'RUBY')
      class TopRisk
        def risky_top
          raise "bad"
        end
      end
      x = TopRisk.new.risky_top rescue "fallback"
      puts x

    RUBY

    _(result).must_answer <<~'OUT'
      fallback
    OUT
  end

  it "an exception carries its own readers out through an inner arm and an outer one" do
    result = zr(<<~'RUBY')
      class MyError < StandardError
        def initialize(msg, code)
          super(msg)
          @code = code
        end
        def code
          @code
        end
      end

      class Inner
        def call
          begin
            raise MyError.new("failed with code 42", 42)
          rescue MyError => e
            puts "inner saw code #{e.send(:code)}"
            raise
          end
        end
      end

      begin
        Inner.new.call
      rescue MyError => e
        puts "outer saw code #{e.send(:code)}"
        puts "outer message: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      inner saw code 42
      outer saw code 42
      outer message: failed with code 42
    OUT
  end

  it "method level implicit rescue with no explicit begin end" do
    result = zr(<<~'RUBY')
      # `def m; ...; rescue => e; ...; end` -- `DefNode::body()` is directly a
      # `BeginNode` with no `begin_keyword_loc` in this shape (confirmed via
      # `Prism.parse`), flowing through the SAME `HirNode::Begin` lowering as
      # an explicit `begin`.

      class Worker
        def safe
          raise "oops"
        rescue => e
          "handled: #{e.send(:message)}"
        end
      end
      puts Worker.new.safe
    RUBY

    _(result).must_answer "handled: oops\n"
  end

  it "missing method via send raises a rescuable no method error" do
    result = zr(<<~'RUBY')
      class Plain
        def real
          :real
        end
      end
      p1 = Plain.new
      begin
        p1.send(:nope)
      rescue NoMethodError => e
        puts "caught nope"
      end
      begin
        p1.send(:nope2)
      rescue NameError => e
        puts "caught via NameError"
      end
    RUBY

    _(result).must_answer "caught nope\ncaught via NameError\n"
  end

  it "raise inside ensure replaces the original exception" do
    result = zr(<<~'RUBY')
      begin
        begin
          raise "original"
        ensure
          raise "from ensure"
        end
      rescue => e
        puts "caught: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "caught: from ensure\n"
  end

  it "rescue exception class explicitly catches a script error" do
    result = zr(<<~'RUBY')
      begin
        raise ScriptError, "script problem"
      rescue Exception => e
        puts "caught via Exception: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "caught via Exception: script problem\n"
  end

  it "rescue with a computed exception class expression" do
    result = zr(<<~'RUBY')
      # A rescue-list entry that is a COMPUTED expression (not a bare constant or
      # splat) is evaluated and matched at runtime -- net/http's `rescue
      # defined?(OpenSSL::SSL) ? OpenSSL::SSL::SSLError : IOError`.

      class MyErr < StandardError; end
      def go
        raise MyErr, "boom"
      rescue IOError, (defined?(Nope) ? Nope : MyErr) => e
        "caught #{e.class}: #{e.send(:message)}"
      end
      puts go
    RUBY

    _(result).must_answer "caught MyErr: boom\n"
  end

  it "rescue with multiple classes in one clause" do
    result = zr(<<~'RUBY')
      begin
        raise TypeError, "wrong type"
      rescue ArgumentError, TypeError => e
        puts "caught one of: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "caught one of: wrong type\n"
  end

  it "singleton body begin rescue and self value" do
    result = zr(<<~'RUBY')
      # securerandom picks its implementation with a `begin/rescue` inside `class <<
      # self`, aliasing whichever one works; and `class << self; self; end` is the
      # classic idiom whose VALUE is the singleton class.

      module Source
        class << self
          def from_device
            "device"
          end

          def from_fallback
            "fallback"
          end

          begin
            raise RuntimeError, "no device here"
            alias generate from_device
          rescue RuntimeError
            alias generate from_fallback
          end
        end

        SINGLETON = class << self
          self
        end
      end

      puts Source.generate
      puts Source::SINGLETON == Source.singleton_class
      puts Source::SINGLETON.instance_method(:generate).owner == Source.singleton_class
    RUBY

    _(result).must_answer <<~'OUT'
      fallback
      true
      true
    OUT
  end

  it "undef method raises" do
    result = zr(<<~'RUBY')
      # Issue #717. `undef <m>` removes the method from the class's
      # dispatch table AND a subsequent call to it raises NoMethodError
      # (matching CRuby). spinel previously recorded the undef but the
      # slot stayed callable.

      class C
        def meth; "method"; end
        undef meth
      end

      begin
        puts C.new.meth
      rescue NoMethodError
        puts "NoMethodError"
      end

      # Inheritance: child class's `undef <parent_method>` shadows the
      # parent. Calling on a Child instance must still raise; calling on
      # a parent instance still works.
      class P
        def hello; "hi"; end
      end

      class Child < P
        undef hello
      end

      begin
        puts Child.new.hello
      rescue NoMethodError
        puts "Child NoMethodError"
      end

      puts P.new.hello
    RUBY

    _(result).must_answer <<~'OUT'
      NoMethodError
      Child NoMethodError
      hi
    OUT
  end

  it "unmatched rescue class propagates to an outer rescue" do
    result = zr(<<~'RUBY')
      begin
        begin
          raise TypeError, "inner"
        rescue ArgumentError
          puts "wrong handler"
        end
      rescue TypeError => e
        puts "outer caught: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "outer caught: inner\n"
  end

  it "unrescued raise propagates through multiple method call frames" do
    result = zr(<<~'RUBY')
      # Three separate objects (not sibling methods on one class) --
      # implicit-self calls to a sibling method aren't supported yet
      # (a separate, pre-existing, documented gap), so each
      # level calls the next via an explicit receiver instead. Still a
      # genuine 3-frame unwind, crossing object boundaries too.

      class Level3
        def run
          raise "deep failure"
        end
      end
      class Level2
        def run
          Level3.new.run
        end
      end
      class Level1
        def run
          Level2.new.run
        end
      end
      begin
        Level1.new.run
      rescue => e
        puts "caught from deep: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "caught from deep: deep failure\n"
  end
end
