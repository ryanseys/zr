# frozen_string_literal: true

require "spec_helper"

describe "Warning programs" do
  it "missing positional arg warns" do
    result = ze0(<<~'RUBY')
      # A statically-detectable wrong-arity call raises ArgumentError at RUNTIME,
      # exactly when the call would run (dead code stays silent, matching CRuby).
      # This replaces the old compat behaviour of padding the missing slot with 0.

      module M
        def self.run!(a, b, c, d)
          puts "a=#{a} b=#{b} c=#{c} d=#{d}"
        end
      end

      begin
        M.run!(1, 2, false)        # missing `d`
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
      M.run!(10, 20, true, 30)     # all args supplied

      def never_called
        M.run!(1)                  # dead code: no raise unless executed
      end
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: wrong number of arguments (given 3, expected 4)
      a=10 b=20 c=true d=30
      done
    OUT
  end

  it "warn category" do
    result = ze0(<<~'RUBY')
      # Kernel#warn(category:) honors CRuby's default warning levels. The :deprecated
      # category is off by default (Warning[:deprecated] == false without -W:deprecated),
      # so those warnings print nothing; other categories print normally. Suppressed
      # messages are still evaluated for their side effects.
      warn("plain warning")
      warn("deprecated thing", category: :deprecated)
      warn("experimental thing", category: :experimental)
      warn("a", "b", category: :deprecated)
      warn("c", "d", category: :experimental)

      # the message expression of a suppressed warning is still evaluated
      def shout; $stdout.puts "evaluated"; "msg"; end
      warn(shout, category: :deprecated)

      $stdout.puts "done"
    RUBY

    _(result).must_answer <<~'OUT', stderr: "plain warning\nexperimental thing\nc\nd\n"
      evaluated
      done
    OUT
  end

  it "warn category and to i base0" do
    result = ze0(<<~'RUBY')
      # Kernel#warn(category:) honors CRuby's default warning levels: :deprecated is
      # off by default (prints nothing), while :experimental and the uncategorized
      # form print to stderr. The keyword Hash itself is never printed, and a
      # suppressed warning's message arguments are still evaluated for side effects.
      warn("plain warning")
      warn("deprecated thing", category: :deprecated)
      warn("experimental thing", category: :experimental)
      warn("a", "b", category: :deprecated)
      warn("c", "d", category: :experimental)

      def shout
        $stdout.puts "evaluated"
        "msg"
      end
      warn(shout, category: :deprecated)

      # String#to_i(0) auto-detects the base from the literal's prefix: 0x/0X hex,
      # 0b/0B binary, 0o/0O or a bare leading 0 octal, 0d decimal, otherwise decimal.
      puts "0xff".to_i(0)
      puts "0b101".to_i(0)
      puts "0o755".to_i(0)
      puts "0777".to_i(0)
      puts "0d42".to_i(0)
      puts "42".to_i(0)
      puts "-0xff".to_i(0)
      puts "+0b101".to_i(0)
      puts "  99 apples".to_i(0)
    RUBY

    _(result).must_answer <<~'OUT', stderr: "plain warning\nexperimental thing\nc\nd\n"
      evaluated
      255
      5
      493
      511
      42
      42
      -255
      5
      99
    OUT
  end

  it "warn category suppresses only deprecated" do
    _(ze0(<<~'RUBY')).must_answer "done\n", stderr: "plain\nexp\nc\nd\n"
      # :deprecated is off by default (prints nothing); :experimental and the
      # uncategorized form print to stderr. The kwarg Hash is never itself
      # printed.

      warn("plain")
      warn("dep", category: :deprecated)
      warn("exp", category: :experimental)
      warn("a", "b", category: :deprecated)
      warn("c", "d", category: :experimental)
      puts "done"
    RUBY
  end

  it "warn render" do
    _(ze0(<<~'RUBY')).must_answer "", stderr: "x\ny\nz\n1\n2\n\ns\n{a: 1}\nt\na\nb\nc\n1.5\n"
      warn ["x", "y"]
      warn "z"
      warn 1, 2
      warn []
      warn nil
      warn :s
      warn({ a: 1 })
      warn "t\n"
      warn ["a", ["b", "c"]]
      warn 1.5

    RUBY
  end

  it "warn unresolved call context" do
    _(ze0(<<~'RUBY')).must_answer "hello\n"
      # #490. A method with no reachable caller defaults its params to
      # mrb_int, then any operation in the body that's invalid on Int
      # fires "cannot resolve call to '<m>' on int (emitting 0)". The
      # previous warning omitted the source method and was a debugging
      # papercut for library-style entry points: the user had to bisect
      # defs to find the culprit. The warning now includes the
      # containing method as "in <Class>.<method>" / "in <Class>#<method>"
      # / "in <Mod>.<method>" so it's actionable without bisection.
      # Test asserts only the program output (the warning goes to
      # stderr; the harness drops it via 2>/dev/null), so this test
      # also doubles as a "library-method-with-no-caller still compiles"
      # regression guard.

      module Util
        def self.size_of(xs)
          xs.length
        end
      end

      puts "hello"
    RUBY
  end

  it "warn with uplevel" do
    result = ze0(<<~'RUBY', path: "core/warning/warn_with_uplevel.rb")
      # Kernel#warn with `uplevel:` prefixes the message with the caller frame's
      # "file:line: warning: ". zeo's warn ignores the option and prints the bare
      # message.
      def helper
        warn "inside helper", uplevel: 0
        warn "callers fault", uplevel: 1
      end

      helper
      warn "no uplevel control"
    RUBY

    _(result).must_answer "", stderr: "core/warning/warn_with_uplevel.rb:5: warning: inside helper\ncore/warning/warn_with_uplevel.rb:9: warning: callers fault\nno uplevel control\n"
  end
end
