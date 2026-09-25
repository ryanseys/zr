# frozen_string_literal: true

require "spec_helper"

describe "Builtins: raising and rescuing" do
  it "builtin frames in a backtrace" do
    result = zr(<<~'RUBY')
      # Ruby's backtrace names the C frames a raise passed through. A raise from
      # inside a block given to `Kernel#then` shows ruby's
      # `from ...:in 'Kernel#then'` line between the block and its caller; zr's
      # native builtin rows push no frame, so that line is missing and the two frames
      # around it become adjacent.
      #
      # The frame is what makes the trace readable -- it is how a reader sees that
      # the failure came through `then` rather than from the calling line directly --
      # and anything that INDEXES into `caller` counts a different depth than ruby
      # does. zr already pushes frames for compiled methods, so the machinery
      # exists; the builtin rows do not use it.
      #
      # `caller_locations` from a method reached through such a builtin already
      # reports ruby's label (the three lines at the end), so only the raise path
      # is short a frame here.

      def inner = raise("boom")

      begin
        1.then { inner }
      rescue => e
        puts e.backtrace.map { |l| l.sub(/^.*gaps./, "").sub(/:\d+:/, ":N:") }
      end

      def who = caller_locations(1, 1).first.label
      def direct = who
      p direct
      p [1].map { who }.first
      p 1.then { who }
    RUBY

    _(result).must_answer <<~'OUT'
      compiler/builtins/exceptions_test.rb:N:in 'Object#inner'
      compiler/builtins/exceptions_test.rb:N:in 'block in <main>'
      compiler/builtins/exceptions_test.rb:N:in 'Kernel#then'
      compiler/builtins/exceptions_test.rb:N:in '<main>'
      "Object#direct"
      "block in <main>"
      "block in <main>"
    OUT
  end

  it "builtin reopen chained patches and nme" do
    result = zr(<<~'RUBY')
      # A patch calling another patch (implicit self -> direct free-fn call, the
      # result's `+` going back through dynamic String dispatch), and an unknown
      # method still raising real Ruby's exact NoMethodError.

      class String
        def shout
          exclaim + "?"
        end

        def exclaim
          self + "!"
        end
      end

      puts "hey".shout
      begin
        "hey".nope
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer "hey!?\nundefined method 'nope' for an instance of String\n"
  end

  it "exception object surface" do
    result = zr(<<~'RUBY')
      # Exception object surface: value equality (==), identity equality (eql?), the
      # #exception copy method (instance and class forms), non-String message
      # coercion, and Exception.to_tty?.
      e = RuntimeError.new("m")
      e2 = RuntimeError.new("m")

      # == compares class + message; two distinct RuntimeErrors with the same
      # message are equal. eql? is identity (distinct objects are not eql?).
      p e == e2
      p e == RuntimeError.new("other")
      p e == "not an exception"
      p e.eql?(e)
      p e.eql?(e2)

      # #exception with no argument answers self; with a new message, a copy.
      p e.exception.equal?(e)
      p e.exception("n").message
      p e.exception("n").equal?(e)

      # The class-method form is an alias for .new.
      p RuntimeError.exception("z").message
      p RuntimeError.exception("z").class

      # A non-String message is coerced to a String via its own to_s.
      p RuntimeError.new(42).message
      p RuntimeError.new(:sym).message
      p ArgumentError.new([1, 2]).message

      # Exception.to_tty? answers a boolean.
      p [true, false].include?(Exception.to_tty?)

      # Raising a non-Exception class is a TypeError, not an attempt to build it.
      p(begin; raise String; rescue => ex; ex.class; end)
      p(begin; raise Object, "m"; rescue => ex; ex.class; end)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      false
      true
      "n"
      false
      "z"
      RuntimeError
      "42"
      "sym"
      "[1, 2]"
      true
      TypeError
      TypeError
    OUT
  end

  it "exception owner rows" do
    result = zr(<<~'RUBY')
      # Ruby declares these four rows ON an exception class, not on an
      # ancestor. Reflection has to name the same owner, because a rescue
      # handler that asks `SignalException.instance_methods(false)` gets a different
      # answer from `Exception`'s.
      #
      # `Exception#respond_to?` is the odd one: it gives Kernel's answer exactly, and
      # exists only because `Exception` also carries a private `method_missing`.

      p Exception.instance_methods(false).sort
      p SignalException.instance_methods(false).sort
      p UncaughtThrowError.instance_methods(false).sort

      # Each name reports the class that declares it, not the one that answers it.
      %i[respond_to? message inspect].each { |m| p Exception.instance_method(m).owner }
      %i[signm signo].each { |m| p SignalException.instance_method(m).owner }
      %i[to_s tag value].each { |m| p UncaughtThrowError.instance_method(m).owner }

      # A subclass declares none of them, and still answers all of them.
      class Custom < SignalException; end
      p Custom.instance_methods(false)
      p Custom.new("TERM").signo
      p Custom.new("TERM").signm

      # `respond_to?` keeps the whole protocol -- private opt-in, the
      # `respond_to_missing?` hook, and the arity check.
      class Hooked < StandardError
        def respond_to_missing?(name, _include_private) = name == :magic
      end
      e = Hooked.new("boom")
      p [e.respond_to?(:message), e.respond_to?(:nope), e.respond_to?(:magic)]
      p [e.respond_to?(:initialize), e.respond_to?(:initialize, true)]
      p e.respond_to?("message")
      begin
        e.respond_to?
      rescue ArgumentError => err
        p err.message
      end
      begin
        e.respond_to?(1)
      rescue TypeError => err
        p err.message
      end

      # The signal pair reads through a `message` override, because `signm` sends.
      class Loud < SignalException
        def message = "LOUD"
      end
      p Loud.new("TERM").signm

      # `UncaughtThrowError#to_s` renders the tag, which `Exception#to_s` cannot.
      begin
        throw :nope, 42
      rescue UncaughtThrowError => err
        p err.to_s
        p [err.tag, err.value]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:==, :backtrace, :backtrace_locations, :cause, :detailed_message, :exception, :full_message, :inspect, :message, :respond_to?, :set_backtrace, :to_s]
      [:signm, :signo]
      [:tag, :to_s, :value]
      Exception
      Exception
      Exception
      SignalException
      SignalException
      UncaughtThrowError
      UncaughtThrowError
      UncaughtThrowError
      []
      15
      "SIGTERM"
      [true, false, true]
      [false, true]
      true
      "wrong number of arguments (given 0, expected 1..2)"
      "1 is not a symbol nor a string"
      "SIGTERM"
      "uncaught throw :nope"
      [:nope, 42]
    OUT
  end

  it "exception reflection surface" do
    result = zr(<<~'RUBY')
      # Exception classes as first-class constants: defined?, superclass chain,
      # and the rarer subclasses as reflectable values.
      p defined?(ArgumentError)
      p defined?(StopIteration)
      p StopIteration.superclass
      p SyntaxError.superclass
      p Interrupt.superclass
      p SignalException.superclass
      p NoMatchingPatternKeyError.superclass
      p ClosedQueueError.superclass
      p UncaughtThrowError.superclass
      p EOFError.superclass
      p ThreadError.superclass
      p FiberError.name
      p SecurityError.superclass
      p RegexpError.superclass
      p EncodingError.superclass
      p NoMatchingPatternError.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      "constant"
      "constant"
      IndexError
      ScriptError
      SignalException
      Exception
      NoMatchingPatternError
      StopIteration
      ArgumentError
      IOError
      StandardError
      "FiberError"
      Exception
      StandardError
      StandardError
      StandardError
    OUT
  end

  it "exception value parity" do
    result = zr(<<~'RUBY')
      # Exception value semantics: #== by class+message, KeyError key inspect,
      # Math::DomainError naming, private/public NameError on undefined names,
      # NameError#name, and raise with an explicit cause.

      # == compares class and message; equal? stays identity
      def pair_eq(a, b); a == b; end
      p pair_eq(TypeError.new("m"), TypeError.new("m"))
      p pair_eq(TypeError.new("m"), TypeError.new("other"))
      p pair_eq(TypeError.new("m"), ArgumentError.new("m"))
      e1 = RuntimeError.new("same")
      p pair_eq(e1, e1)
      p e1.equal?(RuntimeError.new("same"))

      # KeyError message renders a symbol key as :sym
      def dig(h, k); h.fetch(k); end
      begin; dig({}, :missing_key); rescue KeyError => e; puts e.message; end
      begin; dig({ a: 1 }, :b); rescue KeyError => e; puts e.message; end

      # fetch on an empty literal still finds present keys after insert
      h2 = {}
      h2[:x] = 5
      p dig(h2, :x)

      # Math::DomainError renders qualified and rescues by both spellings
      def bad_sqrt(x) = Math.sqrt(x)
      begin
        bad_sqrt(-1.0)
      rescue Math::DomainError => e
        p e.class
        puts e.message
      end

      # private with an undefined name raises NameError when the body runs
      class Vis
        def real; end
        begin
          private :absent
          puts "no raise"
        rescue NameError => e
          puts e.class
          puts e.message.lines.first
        end
        private :real
      end
      p Vis.new.respond_to?(:real)

      # NameError#name carries the missing name; other classes raise NoMethodError
      def build_ne(m, n); NameError.new(m, n).name; end
      p build_ne("msg", :foo)
      begin
        TypeError.new("m").name
      rescue NoMethodError => e
        puts e.class
      end

      # raise with an explicit cause: kwarg overrides the implicit chain
      def blow(m); raise "top", cause: ArgumentError.new(m); end
      begin
        blow("root")
      rescue => e
        p e.cause
        puts e.message
      end

      # implicit cause still threads when no kwarg is given
      begin
        begin
          raise ArgumentError, "inner"
        rescue ArgumentError
          raise "outer"
        end
      rescue => e
        p e.cause
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      false
      key not found: :missing_key
      key not found: :b
      5
      Math::DomainError
      Numerical argument is out of domain - sqrt
      NameError
      undefined method 'absent' for class 'Vis'
      false
      :foo
      NoMethodError
      #<ArgumentError: root>
      top
      #<ArgumentError: inner>
    OUT
  end

  it "frozen error raised inside a thread surfaces at join" do
    result = zr(<<~'RUBY')
      a = [1]
      a.freeze
      t = Thread.new { a[0] = 9 }
      begin
        t.join
      rescue FrozenError => e
        puts "at join: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "at join: can't modify frozen Array: [1]\n", stderr: <<~'ERR'
      #<Thread:0xADDR compiler/builtins/exceptions_test.rb:3 run> terminated with exception (report_on_exception is true):
      compiler/builtins/exceptions_test.rb:3:in 'block in <main>': can't modify frozen Array: [1] (FrozenError)
    ERR
  end

  it "kernel raise is a real dispatch row reachable through send" do
    result = zr(<<~'RUBY')
      # `obj.send(:raise, ...)` reaches the Kernel#raise method. It does the same
      # as CRuby: class and message, bare re-raise from `$!`, a bare class that
      # uses its name as the message, a String that gives a RuntimeError, and a
      # TypeError for an object that is not an exception.

      o = Object.new
      begin
        o.send(:raise, ArgumentError, "via send")
      rescue ArgumentError => e
        puts e.message
      end
      begin
        o.send(:raise, ArgumentError)
      rescue ArgumentError => e
        puts e.message
      end
      begin
        o.send(:raise, "bare msg")
      rescue RuntimeError => e
        puts e.message
      end
      begin
        o.send(:raise)
      rescue RuntimeError => e
        puts "[#{e.message}]"
      end
      begin
        begin
          raise IOError, "orig"
        rescue
          o.send(:raise)
        end
      rescue IOError => e
        puts e.message
      end
      begin
        o.send(:raise, 42)
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      via send
      ArgumentError
      bare msg
      []
      orig
      exception class/object expected
    OUT
  end

  it "signal module and signal exception surface" do
    result = zr(<<~'RUBY')
      # SignalException/Interrupt resolve a signal name<->number (#signo/#signm,
      # arg-form validation) and the Signal module answers list/signame/trap
      # (trap is a validated no-op that records the prior action). Byte-verified
      # against ruby 4.0.6 on darwin.

      p Interrupt.new.signo
      p Interrupt.new.message
      p Interrupt.new("stop").signm
      e = SignalException.new(9, "custom"); p [e.signo, e.message, e.signm]
      p SignalException.new(9).message
      p SignalException.new("INT").signo
      p SignalException.new(:TERM).message
      p((SignalException.new("KILL", "x") rescue $!.class))
      p((SignalException.new("NOPE") rescue $!.class))
      begin; raise SignalException, "SIGINT"; rescue SignalException => x; p x.signo; end
      p Signal.list["INT"]
      p Signal.list.class
      p Signal.signame(15)
      p Signal.signame(2.9)
      p Signal.signame(999)
      p((Signal.signame(nil) rescue $!.class))
      p Signal.trap("USR1", "IGNORE")
      p Signal.trap("USR1", "DEFAULT")
      p((Signal.trap("KILL", "IGNORE") rescue $!.class))
      p Signal.class
    RUBY

    _(result).must_answer <<~'OUT'
      2
      "Interrupt"
      "stop"
      [9, "custom", "custom"]
      "SIGKILL"
      2
      "SIGTERM"
      ArgumentError
      ArgumentError
      2
      2
      Hash
      "TERM"
      "INT"
      nil
      TypeError
      "DEFAULT"
      "IGNORE"
      Errno::EINVAL
      Module
    OUT
  end
end
