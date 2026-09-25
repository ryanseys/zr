# frozen_string_literal: true

require "spec_helper"

describe "Warning programs" do
  it "missing positional arg warns" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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

    _(result).must_answer "evaluated\ndone\n", stderr: "plain warning\nexperimental thing\nc\nd\n"
  end

  it "warn category and to i base0" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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

    _(result).must_answer "done\n", stderr: "plain\nexp\nc\nd\n"
  end

  it "warn render" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer "", stderr: "x\ny\nz\n1\n2\n\ns\n{a: 1}\nt\na\nb\nc\n1.5\n"
  end

  it "warn unresolved call context" do
    result = zr(<<~'RUBY')
      # A method with no caller still compiles, and the program runs.
      # `Util.size_of` has no call site, so its param has no known type.
      # Any warning about it names the containing method, as
      # "in <Class>.<method>", "in <Class>#<method>" or "in <Mod>.<method>".
      # The test asserts only the program output (the warning goes to
      # stderr; the harness drops it via 2>/dev/null).

      module Util
        def self.size_of(xs)
          xs.length
        end
      end

      puts "hello"
    RUBY

    _(result).must_answer "hello\n"
  end

  it "warn with uplevel" do
    result = zr(<<~'RUBY')
      # Kernel#warn with `uplevel:` prefixes the message with the caller frame's
      # "file:line: warning: ". zr's warn ignores the option and prints the bare
      # message.
      def helper
        warn "inside helper", uplevel: 0
        warn "callers fault", uplevel: 1
      end

      helper
      warn "no uplevel control"
    RUBY

    _(result).must_answer "", stderr: <<~'ERR'
      core/warning/warning_test.rb:5: warning: inside helper
      core/warning/warning_test.rb:9: warning: callers fault
      no uplevel control
    ERR
  end

  it "redefining a basic operator warns under the performance category" do
    result = zr(<<~'RUBY')
      # Under Warning[:performance], a program that writes over one of the
      # core's basic operators -- a def, an alias, define_method, remove_method,
      # undef_method or a prepend in front of it -- is told once, with the
      # category; a name the interpreter does not answer in place, a class
      # outside the table, or the category off, says nothing.
      def Warning.warn(message, category: nil) = super("#{category}: #{message}")
      Warning[:performance] = true
      class Integer
        def +(o) = 1
        def +(o) = 2
      end
      class String
        alias_method :length, :to_s
      end
      class Array
        define_method(:empty?) { true }
      end
      class Hash
        remove_method :size
      end
      class Float
        undef_method :<
      end
      module M; def ==(o) = true; end
      class Symbol
        prepend M
      end
      class Object
        def +(o) = 3
      end
      class Integer
        def times = 0
      end
      class NilClass
        def nil? = 1
      end
      Warning[:performance] = false
      class Float
        def -(o) = 0
      end
      puts "done"
    RUBY

    _(result).must_answer "done\n", stderr: <<~'ERR'
      performance: core/warning/warning_test.rb:9: warning: Redefining 'Integer#+' disables interpreter and JIT optimizations
      performance: core/warning/warning_test.rb:13: warning: Redefining 'String#length' disables interpreter and JIT optimizations
      performance: core/warning/warning_test.rb:16: warning: Redefining 'Array#empty?' disables interpreter and JIT optimizations
      performance: core/warning/warning_test.rb:19: warning: Redefining 'Hash#size' disables interpreter and JIT optimizations
      performance: core/warning/warning_test.rb:22: warning: Redefining 'Float#<' disables interpreter and JIT optimizations
      performance: core/warning/warning_test.rb:26: warning: Redefining 'Symbol#==' disables interpreter and JIT optimizations
      performance: core/warning/warning_test.rb:35: warning: Redefining 'NilClass#nil?' disables interpreter and JIT optimizations
    ERR
  end

  it "Warning checks types and categories, and warn follows rb_warn_m" do
    result = zr(<<~'RUBY')
      $stderr = $stdout
      def t(l) = (r = yield; puts "#{l}: #{r.inspect}") rescue puts("#{l}: #{$!.class}: #{$!.message}")
      t(1) { Warning[:deprecated] = 1 }
      t(2) { Warning[:deprecated] = nil; Warning[:deprecated] }
      t(3) { Warning["deprecated"] }
      t(4) { warn "x", category: "deprecated" }
      t(5) { warn "x", category: nil }
      t(6) { Warning[:performance] = true; warn "perf", category: :performance }
      t(7) { warn "a\n", "b" }
      t(8) { warn "q", uplevel: 1 }
      t(9) { def w9 = warn("in w9", uplevel: 1); w9 }
      t(10) { warn "x", uplevel: "1" }
      t(11) { warn "x", uplevel: nil }
      t(12) { warn 1, :sym, 2.5 }
      t(13) { Warning.warn("no newline") ; puts }
      t(14) { Warning.warn(:sym) }
      t(15) { Warning.warn("x", category: :bogus) }
      t(16) { module Warning; def self.warn(msg, category: nil, **kw) = print("W(#{category.inspect},#{kw}) #{msg}"); end; warn "via hook", category: :experimental; warn "d", category: :deprecated }
      t(17) { Warning[:experimental] = true; warn "exp2", category: :experimental }
      t(18) { $VERBOSE = nil; warn "silent?"; :after }
      t(19) { $VERBOSE = false; warn "back" }
    RUBY

    _(result).must_answer <<~'OUT'
      1: 1
      2: false
      3: TypeError: wrong argument type String (expected Symbol)
      4: nil
      x
      5: nil
      perf
      6: nil
      a
      b
      7: nil
      core/warning/warning_test.rb:2: warning: q
      8: nil
      core/warning/warning_test.rb:11: warning: in w9
      9: nil
      10: TypeError: no implicit conversion of String into Integer
      x
      11: nil
      1
      sym
      2.5
      12: nil
      no newline
      13: nil
      14: TypeError: wrong argument type Symbol (expected String)
      15: ArgumentError: unknown category: bogus
      W(:experimental,{}) via hook
      16: nil
      W(:experimental,{}) exp2
      17: nil
      18: :after
      W(nil,{}) back
      19: nil
    OUT
  end

  it "a negative uplevel, a bad category and a one-argument Warning.warn" do
    result = zr(<<~'RUBY')
      def t(label)
        p [label, yield]
      rescue => e
        p [label, e.class, e.message]
      end
      t(1) { warn "x", uplevel: -1 }
      t(2) { warn "x", category: 5 }
      t(3) { Warning.warn("x", category: "deprecated") }
      t(4) { Warning[:deprecated] = :yes }
      t(5) { Warning[:deprecated] }
      t(6) { Warning.warn("x".encode("UTF-16LE")) }
      module Warning
        def self.warn(message) = print("ONE #{message}")
      end
      t(7) { warn "arity one", category: :experimental }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, ArgumentError, "negative level (-1)"]
      [2, TypeError, "no implicit conversion of Integer into Symbol"]
      [3, TypeError, "wrong argument type String (expected Symbol)"]
      [4, :yes]
      [5, true]
      [6, Encoding::CompatibilityError, "ASCII incompatible encoding: UTF-16LE"]
      ONE arity one
      [7, nil]
    OUT
  end
end
