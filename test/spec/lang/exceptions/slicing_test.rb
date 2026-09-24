# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: slicing" do
  it "begin rescue else clause" do
    result = zr(<<~'RUBY')
      # Phase 1B: `begin..rescue..else..end` the `else` body runs only when
      # the begin body completed without exception. Pre-fix the parser
      # emitted the else_clause field but the codegen ignored it -- the
      # else body was silently dropped from emit.
      #
      # Covered:
      #   - else with no exception (else runs)
      #   - else with exception (else does NOT run)
      #   - else combined with ensure
      #   - method-level def with begin..rescue..else

      # 1. No exception -- else runs.
      begin
        x = 1
      rescue
        puts "rescued"
      else
        puts "else ran"
      end

      # 2. Exception -- else skipped, rescue runs.
      begin
        raise "boom"
      rescue
        puts "rescued boom"
      else
        puts "should not appear"
      end

      # 3. else + ensure: order is body -> (else | rescue) -> ensure.
      begin
        y = 2
      rescue
        puts "rescue"
      else
        puts "else"
      ensure
        puts "ensure"
      end

      # 4. Method-level: else's last expr is the method return value
      # (overriding begin body's). When else's last is `puts ...` which
      # returns nil, the method returns nil (spinel's int slot lowers it
      # to 0).
      def m_else_succeeds
        10
      rescue
        -1
      else
        puts "else fired"
      end
      puts m_else_succeeds       # "else fired" then 0 (spinel int slot for nil)

      # 5. Method-level: exception path skips else, rescue value returned.
      def m_else_skipped
        raise "x"
        10
      rescue
        -1
      else
        puts "should not fire"
      end
      puts m_else_skipped        # -1
    RUBY

    _(result).must_answer <<~'OUT'
      else ran
      rescued boom
      else
      ensure
      else fired

      -1
    OUT
  end

  it "builtin arg mismatches raise cruby error shapes" do
    result = zr(<<~'RUBY')
      # The table rows validate argument TYPES with CRuby's exact TypeError/
      # ArgumentError messages (previously an arg-type mismatch degraded to
      # NoMethodError) -- all real, rescuable exceptions now.

      a = ["a"].first
      begin
        a + 1
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
      arr = [[1]].first
      begin
        arr[:x]
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
      one = [1].first
      begin
        one < "a"
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: no implicit conversion of Integer into String
      TypeError: no implicit conversion of Symbol into Integer
      ArgumentError: comparison of Integer with String failed
    OUT
  end

  it "a proc return runs an intervening ensure, and then the home method returns" do
    result = zr(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # proc `return` runs an intervening ensure, then the home method returns.
      def ret_through_ensure
        begin
          proc { return 30 }.call
        ensure
          puts "ensure-ret"
        end
        40
      end
      p ret_through_ensure

    RUBY

    _(result).must_answer <<~'OUT'
      ensure-ret
      30
    OUT
  end

  it "two nested ensures run inner first as a proc return unwinds" do
    result = zr(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # Two nested ensures run inner-first as the proc return unwinds.
      def ret_through_two_ensures
        begin
          begin
            proc { return 1 }.call
          ensure
            puts "inner"
          end
        ensure
          puts "outer"
        end
        99
      end
      p ret_through_two_ensures

    RUBY

    _(result).must_answer <<~'OUT'
      inner
      outer
      1
    OUT
  end

  it "a non-matching rescue is skipped, and the ensure still runs" do
    result = zr(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # A non-matching rescue is skipped; the ensure still runs.
      def ret_nonmatching_rescue
        begin
          proc { return 7 }.call
        rescue TypeError
          puts "should-not-run"
        ensure
          puts "ensure-nonmatch"
        end
      end
      p ret_nonmatching_rescue

    RUBY

    _(result).must_answer <<~'OUT'
      ensure-nonmatch
      7
    OUT
  end

  it "a proc return that passes no ensure goes straight home" do
    result = zr(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # A proc return that passes through no ensure goes straight home (regression).
      def ret_no_ensure
        proc { return 5 }.call
        6
      end
      p ret_no_ensure

    RUBY

    _(result).must_answer <<~'OUT'
      5
    OUT
  end

  it "a proc return through a rescue modifier still returns" do
    result = zr(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # proc return passing through a rescue modifier still returns home.
      def ret_through_rescue_modifier
        x = (proc { return 9 }.call rescue 0)
        x + 100
      end
      p ret_through_rescue_modifier

    RUBY

    _(result).must_answer <<~'OUT'
      9
    OUT
  end

  it "a throw runs an intervening ensure before it reaches its catch" do
    result = zr(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # `throw` runs an intervening ensure before reaching its catch.
      r = catch(:t) do
        begin
          throw :t, 11
        ensure
          puts "throw-ensure"
        end
      end
      p r

    RUBY

    _(result).must_answer <<~'OUT'
      throw-ensure
      11
    OUT
  end

  it "a throw to an outer tag passes an inner catch of another tag, running its ensure" do
    result = zr(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # A throw to an outer tag passes an inner catch of a different tag and runs the
      # ensure between throw and the matching catch.
      r2 = catch(:outer) do
        catch(:inner) do
          begin
            throw :outer, 22
          ensure
            puts "between-ensure"
          end
        end
        :inner_normal
      end
      p r2

    RUBY

    _(result).must_answer <<~'OUT'
      between-ensure
      22
    OUT
  end

  it "a throw that passes no ensure is delivered directly" do
    result = zr(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # A throw NOT passing any ensure delivers directly (regression).
      p(catch(:q) { throw :q, 33 })

    RUBY

    _(result).must_answer <<~'OUT'
      33
    OUT
  end

  it "an ordinary exception still runs its ensure" do
    result = zr(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # A normal exception still runs its ensure (regression).
      def raise_through_ensure
        begin
          raise "boom"
        ensure
          puts "exc-ensure"
        end
      end
      begin
        raise_through_ensure
      rescue => e
        puts "caught: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      exc-ensure
      caught: boom
    OUT
  end

  it "an uncaught throw raises UncaughtThrowError, which a bare rescue catches" do
    result = zr(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # An uncaught throw raises UncaughtThrowError -- catchable by its class and by a
      # bare rescue (it is a StandardError), with a CRuby-shaped message.
      begin
        throw :nope
      rescue UncaughtThrowError => e
        puts e.message
      end

      begin
        throw :nope, 1
      rescue => e
        puts "bare: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      uncaught throw :nope
      bare: uncaught throw :nope
    OUT
  end

  it "an uncaught throw runs the ensures it passes on its way out" do
    result = zr(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # An uncaught throw runs intervening ensures on its way out (it is an exception).
      def uncaught_runs_ensure
        begin
          throw :gone
        ensure
          puts "uncaught-ensure"
        end
      end
      begin
        uncaught_runs_ensure
      rescue UncaughtThrowError
        puts "rescued-uncaught"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      uncaught-ensure
      rescued-uncaught
    OUT
  end

  it "conv typeerror names the right class" do
    result = zr(<<~'RUBY')
      # The class a conversion TypeError names has to survive the emission that sits
      # between taking it and writing it. class_ruby_name built the qualified name
      # into a shared static buffer, so a message built as
      #
      #   cn = class_ruby_name(...);  emit_expr(arg);  printf("...%s...", cn)
      #
      # printed whichever class the argument's own emission asked about. Below, the
      # inner conversion is EMITTED but never runs (its branch is not taken), and it
      # was enough to rename the error the outer one raises.
      #
      # The same buffer is why `is_a?` on a namespaced exception compared its
      # receiver against itself (#4133).
      module M
        class Alpha; end
        class Beta; end
      end

      x = M::Beta.new
      cond = (ARGV.length > 99)

      begin
        p 1.0.quo(cond ? ((1.0.quo(M::Alpha.new) > 0.0) ? x : x) : x)
      rescue TypeError => e
        p e.message
      end

      # The same shape through the Array and Hash protocols, which name a class the
      # same way.
      begin
        p [1, 2].product(cond ? ((1.0.quo(M::Alpha.new) > 0.0) ? x : x) : x)
      rescue TypeError => e
        p e.message
      end

      begin
        p({ 1 => 2 }.merge(cond ? ((1.0.quo(M::Alpha.new) > 0.0) ? x : x) : x))
      rescue TypeError => e
        p e.message
      end

      # A top-level class is not qualified and never used the buffer, so it was
      # right all along -- pinned so a future change cannot take it the other way.
      class Plain; end
      begin
        p 1.0.quo(Plain.new)
      rescue TypeError => e
        p e.message
      end

      # Two nested classes named in one expression, each keeping its own name.
      begin
        p 1.0.quo(M::Alpha.new)
      rescue TypeError => e
        p e.message
      end
      begin
        p 1.0.quo(M::Beta.new)
      rescue TypeError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "M::Beta can't be coerced into Float"
      "no implicit conversion of M::Beta into Array"
      "no implicit conversion of M::Beta into Hash"
      "Plain can't be coerced into Float"
      "M::Alpha can't be coerced into Float"
      "M::Beta can't be coerced into Float"
    OUT
  end

  it "defined does not swallow nomethoderror" do
    result = zr(<<~'RUBY')
      # `defined?` must answer `nil` for a call chain that cannot run, never raise.
      # zr evaluates the receiver chain and lets the `NoMethodError` escape.
      #
      # Ruby evaluates a method-call `defined?` by resolving each link and stopping at
      # the first miss (`defined?`'s `NODE_CALL` case walks the receiver, then probes
      # the method table without invoking). zr emits the chain and guards only the
      # LAST send, so an intermediate miss escapes as an ordinary raise.
      #
      # This is the idiom's whole point -- `defined?(a.b.c)` is how ruby code asks
      # "is this reachable?" without a rescue -- so a raise here defeats the guard the
      # programmer wrote.

      # The single-link forms already answer correctly.
      p defined?([].size)
      p defined?(String.nope)
      p defined?([].nope)

      # ...and the chain raises rather than answering nil.
      p defined?([].nope.nope)
      p defined?(nil.foo.bar)
    RUBY

    _(result).must_answer <<~'OUT'
      "method"
      nil
      nil
      nil
      nil
    OUT
  end

  it "error names the code it came from" do
    result = zr(<<~'RUBY')
      # detailed_message shows the line an error came from with a caret run
      # under the node that failed, as error_highlight spots it: a call's name
      # or arguments, a constant, an operator write, and for a wrong argument
      # count both the caller and the callee. did_you_mean adds its guess.

      def show
        yield
      rescue Exception => e
        puts e.detailed_message(highlight: false), "--"
      end
      def two(a, b) = a
      def kw(a:) = a
      x = nil
      show { x.lenght }
      show { x&.foo.bar }
      show { 1 + nil }
      show { Integer("zz") }
      show { [1, 2].first("a") }
      show { two(1) }
      show { kw }
      show { UndefinedThing }
      show { Comparable::Nope }
      show { foo_bar_baz }
      show { x.foo = 1 }
      show { h = nil; h[:a] += 1 }
      show { a = nil; a += 1 }
      show { ->(a) {}.call }
      show { {a: 1}.fetch(:b) }
      show { "abc".unknown_meth(1, 2) }
      show { lengthh = 1; lenghth }
      show { [1].frist }

    RUBY

    _(result).must_answer <<~'OUT'
      undefined method 'lenght' for nil (NoMethodError)
      
      show { x.lenght }
              ^^^^^^^
      --
      undefined method 'bar' for nil (NoMethodError)
      
      show { x&.foo.bar }
                   ^^^^
      --
      nil can't be coerced into Integer (TypeError)
      
      show { 1 + nil }
                 ^^^
      --
      invalid value for Integer(): "zz" (ArgumentError)
      
      show { Integer("zz") }
                     ^^^^
      --
      no implicit conversion of String into Integer (TypeError)
      
      show { [1, 2].first("a") }
                          ^^^
      --
      wrong number of arguments (given 1, expected 2) (ArgumentError)
      
          caller: lang/exceptions/slicing_test.rb:19
          | show { two(1) }
                   ^^^
          callee: lang/exceptions/slicing_test.rb:11
          | def two(a, b) = a
                ^^^
      --
      missing keyword: :a (ArgumentError)
      
          caller: lang/exceptions/slicing_test.rb:20
          | show { kw }
                   ^^
          callee: lang/exceptions/slicing_test.rb:12
          | def kw(a:) = a
                ^^
      --
      uninitialized constant UndefinedThing (NameError)
      
      show { UndefinedThing }
             ^^^^^^^^^^^^^^
      --
      uninitialized constant Comparable::Nope (NameError)
      
      show { Comparable::Nope }
                       ^^^^^^
      --
      undefined local variable or method 'foo_bar_baz' for main (NameError)
      
      show { foo_bar_baz }
             ^^^^^^^^^^^
      --
      undefined method 'foo=' for nil (NoMethodError)
      
      show { x.foo = 1 }
              ^^^^^^
      --
      undefined method '[]' for nil (NoMethodError)
      
      show { h = nil; h[:a] += 1 }
                       ^^^^
      --
      undefined method '+' for nil (NoMethodError)
      
      show { a = nil; a += 1 }
                        ^
      --
      wrong number of arguments (given 0, expected 1) (ArgumentError)
      
          caller: lang/exceptions/slicing_test.rb:27
          | show { ->(a) {}.call }
                           ^^^^^
          callee: lang/exceptions/slicing_test.rb:27
          | show { ->(a) {}.call }
                   ^^
      --
      key not found: :b (KeyError)
      --
      undefined method 'unknown_meth' for an instance of String (NoMethodError)
      
      show { "abc".unknown_meth(1, 2) }
                  ^^^^^^^^^^^^^
      --
      undefined local variable or method 'lenghth' for main (NameError)
      
      show { lengthh = 1; lenghth }
                          ^^^^^^^
      Did you mean?  lengthh
      --
      undefined method 'frist' for an instance of Array (NoMethodError)
      
      show { [1].frist }
                ^^^^^^
      Did you mean?  first
      --
    OUT
  end

  it "a break, next or redo out of an ensure-carrying begin runs the ensure first" do
    result = zr(<<~'RUBY')
      # A jump out of an ensure-carrying `begin` runs the ensure first: it
      # travels as a signal and the `begin` settles it onto its own target.
      i = 0
      while i < 4
        begin
          break if i == 2
          puts "b#{i}"
        ensure
          puts "e#{i}"
        end
        i += 1
      end
      puts "---"
      j = 0
      while j < 4
        j += 1
        begin
          next if j == 2
          puts "n#{j}"
        ensure
          puts "ne#{j}"
        end
      end
      puts "---"
      k = 0
      tries = 0
      while k < 2
        begin
          tries += 1
          redo if tries == 1
          puts "k#{k}"
        ensure
          puts "ke#{k}"
        end
        k += 1
      end
      puts "---"
      m = 0
      while m < 3
        m += 1
        begin
          raise "x" if m == 1
          puts "m#{m}"
        rescue
          next
        ensure
          puts "me#{m}"
        end
      end
      puts "---"
      n = 0
      while n < 3
        n += 1
        begin
          puts "n#{n}"
        ensure
          break if n == 2
        end
      end
      puts "done"
      puts "===";
      for x in [1,2,3]
        begin
          break if x == 3
          next if x == 2
          puts "f#{x}"
        ensure
          puts "fe#{x}"
        end
      end
      puts "---"
      3.times do |i|
        begin
          next if i == 1
          puts "t#{i}"
        ensure
          puts "te#{i}"
        end
      end
      puts "---"
      [1,2,3].each do |i|
        begin
          break if i == 3
          puts "a#{i}"
        ensure
          puts "ae#{i}"
        end
      end
      puts "---"
      y = 0
      until y >= 3
        y += 1
        begin
          begin
            next if y == 2
            puts "u#{y}"
          ensure
            puts "ui#{y}"
          end
        ensure
          puts "uo#{y}"
        end
      end
      puts "---"
      z = 0
      while z < 3
        z += 1
        begin
          begin
            break if z == 2
            puts "w#{z}"
          ensure
            puts "wi#{z}"
          end
        rescue
          puts "never"
        ensure
          puts "wo#{z}"
        end
      end
      puts "done"
      puts "===";
      def a
        begin
          return 1
        ensure
          puts "ensure a"
        end
      end
      p a

    RUBY

    _(result).must_answer <<~'OUT'
      b0
      e0
      b1
      e1
      e2
      ---
      n1
      ne1
      ne2
      n3
      ne3
      n4
      ne4
      ---
      ke0
      k0
      ke0
      k1
      ke1
      ---
      me1
      m2
      me2
      m3
      me3
      ---
      n1
      n2
      done
      ===
      f1
      fe1
      fe2
      fe3
      ---
      t0
      te0
      te1
      t2
      te2
      ---
      a1
      ae1
      a2
      ae2
      ae3
      ---
      u1
      ui1
      uo1
      ui2
      uo2
      u3
      ui3
      uo3
      ---
      w1
      wi1
      wo1
      wi2
      wo2
      done
      ===
      ensure a
      1
    OUT
  end

  it "a raise out of an ensure-carrying begin runs the ensure and carries the exception" do
    result = zr(<<~'RUBY')
      def b
        begin
          raise "boom"
        rescue => e
          return "r:#{e.message}"
        ensure
          puts "ensure b"
        end
      end
      p b

    RUBY

    _(result).must_answer <<~'OUT'
      ensure b
      "r:boom"
    OUT
  end

  it "an ensure inside a loop body runs on every pass" do
    result = zr(<<~'RUBY')
      def c
        [10, 20].each do |x|
          begin
            return x if x == 20
            puts "seen #{x}"
          ensure
            puts "ensure c #{x}"
          end
        end
        :none
      end
      p c

    RUBY

    _(result).must_answer <<~'OUT'
      seen 10
      ensure c 10
      ensure c 20
      20
    OUT
  end

  it "nested ensures run inner first as the jump leaves" do
    result = zr(<<~'RUBY')
      def d
        begin
          begin
            return 5
          ensure
            puts "inner d"
          end
        ensure
          puts "outer d"
        end
      end
      p d

    RUBY

    _(result).must_answer <<~'OUT'
      inner d
      outer d
      5
    OUT
  end

  it "an ensure that the jump does not cross does not run" do
    result = zr(<<~'RUBY')
      def e
        begin
          return 1
        ensure
          return 2
        end
      end
      p e

    RUBY

    _(result).must_answer <<~'OUT'
      2
    OUT
  end

  it "an ensure runs before the value the begin answers reaches its reader" do
    result = zr(<<~'RUBY')
      def f
        begin
          yield
          return :after
        ensure
          puts "ensure f"
        end
      end
      p(f { 1 })
      puts "===";
      r = [1,2,3].map do |x|
        begin
          next x * 10 if x == 2
          x
        ensure
          puts "ens #{x}"
        end
      end
      p r
      r2 = [1,2,3].each do |x|
        begin
          break :stop if x == 2
        ensure
          puts "b ens #{x}"
        end
      end
      p r2
      tries = 0
      r3 = [1,2].map do |x|
        begin
          tries += 1
          redo if x == 1 && tries == 1
          x
        ensure
          puts "r ens #{x} #{tries}"
        end
      end
      p r3
      def deep
        [1,2].each do |x|
          begin
            begin
              next if x == 1
              return :from_block
            ensure
              puts "inner #{x}"
            end
          ensure
            puts "outer #{x}"
          end
        end
        :none
      end
      p deep
      r = [1,2,3].map do |x|
        begin
          next x * 10 if x == 2
          x
        ensure
          puts "ens #{x}"
        end
      end
      p r
      r2 = [1,2,3].each do |x|
        begin
          break :stop if x == 2
        ensure
          puts "b ens #{x}"
        end
      end
      p r2
    RUBY

    _(result).must_answer <<~'OUT'
      ensure f
      :after
      ===
      ens 1
      ens 2
      ens 3
      [1, 20, 3]
      b ens 1
      b ens 2
      :stop
      r ens 1 1
      r ens 1 2
      r ens 2 3
      [1, 2]
      inner 1
      outer 1
      inner 2
      outer 2
      :from_block
      ens 1
      ens 2
      ens 3
      [1, 20, 3]
      b ens 1
      b ens 2
      :stop
    OUT
  end

  it "nested ensure self" do
    result = zr(<<~'RUBY')
      # A method shaped `save; begin; yield self; ensure; restore; end; self` must
      # compile when it yields to a block that calls the SAME method (re-entrantly).
      #
      # The yielding-method inliner recorded the receiver-temp name in a file-static
      # buffer that g_self points into. A nested inline (the yielded block calling the
      # method again) overwrote that single static, so the outer frame's ensure and
      # trailing self emitted the inner receiver temp -- "use of undeclared identifier
      # '_tN'". Making the buffer stack-local gives each recursive inline its own.

      class C
        attr_reader :log
        def initialize = (@log = [])
        def save = (@log << :save)
        def restore = (@log << :restore)
        def with_state
          save
          begin
            yield self
          ensure
            restore
          end
          self
        end
      end

      c = C.new
      # 1. Single call.
      c.with_state { |s| s.save }
      # 2. Two-level nesting (the gap).
      c.with_state { |s| s.with_state { |ss| ss.save } }
      # 3. Three-level nesting.
      c.with_state { |s| s.with_state { |ss| ss.with_state { |sss| sss.save } } }
      p c.log.length                     #=> 15
      # 4. ensure still runs when the block raises.
      begin
        c.with_state { |s| raise "boom" }
      rescue
      end
      p c.log.last                       #=> :restore

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      15
      :restore
      done
    OUT
  end

  it "no method error messages name the real class" do
    result = zr(<<~'RUBY')
      class Widget
      end

      w = [Widget.new].first
      begin
        w.nope
      rescue NoMethodError => e
        puts e.message
      end

      module Helper
      end

      begin
        Helper.new
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      undefined method 'nope' for an instance of Widget
      undefined method 'new' for module Helper
    OUT
  end

  it "overfull raise is a runtime argument error" do
    result = zr(<<~'RUBY')
      # `Kernel#raise` with more than 3 positional arguments (appnexusapi passes
      # a message twice) or with only `cause:` is a RUNTIME ArgumentError: the
      # call evaluates its arguments first and raises only when reached, so the
      # program still loads and an untaken branch never complains.
      def never_reached
        raise RuntimeError, "a", "b", ["c"] if false
        :loadable
      end
      p never_reached

      side_effects = []
      begin
        raise RuntimeError, side_effects << :msg, side_effects << :bt, side_effects << :extra
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end
      p side_effects

      begin
        raise(cause: RuntimeError.new("x"))
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      :loadable
      ArgumentError: wrong number of arguments (given 4, expected 0..3)
      [:msg, :bt, :extra]
      ArgumentError: only cause is given with no arguments
      still running
    OUT
  end

  it "raise cause is three state" do
    result = zr(<<~'RUBY')
      # CRuby distinguishes three states with a Qundef/Qnil/value sentinel
      # (rb_f_raise, eval.c:740), and the first two mean OPPOSITE things: an
      # omitted `cause:` chains automatically from $!, while `cause: nil`
      # SUPPRESSES that chaining. Modeling this as Option<NodeId> would lower
      # `cause: nil` to None and silently chain anyway -- so both are asserted
      # here, along with the TypeError and circular-cause rejections.

      def blow(m); raise "top", cause: ArgumentError.new(m); end
      begin
        blow("root")
      rescue => e
        p e.cause
        puts e.message
      end
      begin
        begin
          raise ArgumentError, "inner"
        rescue ArgumentError
          raise "outer"
        end
      rescue => e
        p e.cause
      end
      begin
        begin
          raise ArgumentError, "inner2"
        rescue ArgumentError
          raise "outer2", cause: nil
        end
      rescue => e
        p e.cause
      end
      begin
        raise "x", cause: 5
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
      begin
        a = RuntimeError.new("a")
        b = RuntimeError.new("b")
        begin
          raise a, cause: b
        rescue; end
        raise b, cause: a
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<ArgumentError: root>
      top
      #<ArgumentError: inner>
      nil
      TypeError: exception object expected
      ArgumentError: circular causes
    OUT
  end

  it "raise in ensure loses cause" do
    result = zr(<<~'RUBY')
      # An exception raised inside an `ensure` while another is propagating takes the
      # propagating one as its `cause`. zr leaves `cause` nil, so the original
      # failure is gone.
      #
      # Ruby sets `cause` from whatever is in flight at the raise -- `$!` -- and an
      # `ensure` running during propagation has the original in `$!`. That is the one
      # case where the cause chain matters most: the ensure's own failure (a close
      # that fails, a rollback that fails) is what surfaces, and the cause is the only
      # remaining record of what went wrong first.
      #
      # zr already builds the chain for the ordinary shape -- a raise inside a
      # `rescue` gets its cause (the second block below) -- so `$!` is tracked and the
      # ensure path simply does not consult it.

      begin
        begin
          raise "first"
        ensure
          raise "second"
        end
      rescue => e
        p [e.message, e.cause&.message]
      end

      # Already correct: raising from a rescue.
      begin
        begin
          raise "orig"
        rescue
          raise "wrapped"
        end
      rescue => e
        p [e.message, e.cause&.message]
      end

      # Three deep, through an ensure in the middle.
      begin
        begin
          begin
            raise "a"
          ensure
            raise "b"
          end
        rescue
          raise "c"
        end
      rescue => e
        p [e.message, e.cause&.message, e.cause&.cause&.message]
      end

      # An ensure that raises with NOTHING in flight has no cause in ruby either.
      begin
        begin
          :fine
        ensure
          raise "alone"
        end
      rescue => e
        p [e.message, e.cause&.message]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["second", "first"]
      ["wrapped", "orig"]
      ["c", "b", "a"]
      ["alone", nil]
    OUT
  end

  it "raise reraise in def" do
    result = zr(<<~'RUBY')
      # Phase 1A: bare `raise` (re-raise) inside a def's rescue clause.
      # Pre-fix the codegen routed the surrounding begin/rescue's body
      # through compile_body_into which uses compile_expr for the last
      # stmt; compile_expr's raise arm ignored the 2-arg form and emitted
      # `sp_raise(<class_expr>)` -- passing an sp_Class compound literal to
      # sp_raise(const char *), C compile fail. Fix: expr-form raise now
      # mirrors compile_control_call_stmt's 2-arg handling
      # (sp_raise_cls("ClassName", msg)).

      def helper
        begin
          raise StandardError, "inner"
        rescue => e
          raise
        end
      end

      begin
        helper
      rescue => e
        puts "outer: #{e.class}: #{e.message}"
      end

      # Variant: 2-arg raise as the only statement (no rescue, propagates).
      def thrower
        raise ArgumentError, "from thrower"
      end

      begin
        thrower
      rescue ArgumentError => e
        puts "caught: #{e.message}"
      end

      # Variant: 1-arg raise (string only) in def + outer rescue.
      def thrower2
        raise "plain message"
      end

      begin
        thrower2
      rescue => e
        puts "got: #{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      outer: StandardError: inner
      caught: from thrower
      got: RuntimeError: plain message
    OUT
  end

  it "re raise preserves the exact same object not a copy" do
    result = zr(<<~'RUBY')
      # Proves re-raise doesn't construct a fresh exception -- mutating an
      # ivar (via an `attr_accessor`-generated setter) INSIDE the inner
      # `rescue`, then bare `raise`-ing, must be visible to the OUTER
      # `rescue` reading the same ivar back. Constructed and raised in ONE
      # expression (`raise Tagged.new(...)`), not first assigned to a named
      # local -- a named local assigned an `Object`-typed value inside a
      # `begin`'s body (or any branching construct) hits a real, pre-existing
      # codegen gap when that local's type has to widen
      # to `Poly` across branches (confirmed to affect plain `if`/`else` too,
      # unrelated to exception handling itself).

      class Tagged < StandardError
        def initialize(msg, tag)
          super(msg)
          @tag = tag
        end
        attr_accessor :tag
      end
      begin
        begin
          raise Tagged.new("x", "initial")
        rescue Tagged => e
          e.send(:tag=, "mutated")
          raise
        end
      rescue Tagged => e
        puts "tag: #{e.send(:tag)}"
      end
    RUBY

    _(result).must_answer "tag: mutated\n"
  end

  it "reraise nested rescue" do
    result = zr(<<~'RUBY')
      # A bare `raise` re-raises the exception its own rescue caught, even when the
      # rescue body ran another begin/rescue first. The saved class/message buffers
      # were shared across clauses, so the inner clause overwrote the outer one's
      # numbering and the re-raise named temporaries that were out of scope by then
      # -- the C build failed (#4052).

      def inner = raise(ArgumentError, "inner boom")

      def cleanup_that_raises
        yield
      rescue StandardError
        begin
          inner
        rescue StandardError => e
          puts "swallowed: #{e.class}: #{e.message}"
        end
        raise
      end

      begin
        cleanup_that_raises { raise "outer boom" }
      rescue StandardError => e
        puts "caught: #{e.class}: #{e.message}"
      end

      # the same with an ensure on the inner handler
      def cleanup_with_ensure
        yield
      rescue StandardError
        begin
          inner
        rescue StandardError
          nil
        ensure
          puts "ensured"
        end
        raise
      end

      begin
        cleanup_with_ensure { raise TypeError, "typed boom" }
      rescue StandardError => e
        puts "caught: #{e.class}: #{e.message}"
      end

      # two levels of nesting inside one rescue body
      def two_levels
        yield
      rescue StandardError
        begin
          begin
            inner
          rescue StandardError => e
            puts "inner: #{e.message}"
          end
          raise "middle boom"
        rescue StandardError => e
          puts "middle: #{e.message}"
        end
        raise
      end

      begin
        two_levels { raise "outermost boom" }
      rescue StandardError => e
        puts "caught: #{e.message}"
      end

      # a nested rescue in the body, then an explicit raise of a NEW exception
      def replaces
        yield
      rescue StandardError
        begin
          inner
        rescue StandardError
          nil
        end
        raise RuntimeError, "replacement"
      end

      begin
        replaces { raise "original" }
      rescue StandardError => e
        puts "caught: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      swallowed: ArgumentError: inner boom
      caught: RuntimeError: outer boom
      ensured
      caught: TypeError: typed boom
      inner: inner boom
      middle: middle boom
      caught: outermost boom
      caught: replacement
    OUT
  end

  it "three rescue clauses skips non matching ones in order" do
    result = zr(<<~'RUBY')
      begin
        raise RangeError, "oops"
      rescue ArgumentError
        puts "arg"
      rescue TypeError
        puts "type"
      rescue RangeError => e
        puts "range: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "range: oops\n"
  end

  it "unknown keyword argument is an error" do
    result = zr(<<~'RUBY')
      # A keyword a method does not declare raises ArgumentError ("unknown
      # keyword: :b") on EVERY call path. zr's compile-time arity check gets the
      # static shapes right; the DYNAMIC paths -- a runtime-defined method, a
      # `Method#call`, a `send` -- silently drop the extra keyword and the call
      # succeeds. Likely the `**kwrest`-peel shape from the kwargs channel.
      # (Found by the 2026-08-24 probe sweep.)
      c = Class.new { def kw(a:) = a }

      begin
        p c.new.kw(a: 1, b: 2)
      rescue ArgumentError => e
        puts e.message
      end

      m = c.new.method(:kw)
      begin
        p m.call(a: 1, z: 9)
      rescue ArgumentError => e
        puts e.message
      end

      begin
        p c.new.send(:kw, a: 1, q: 3)
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      unknown keyword: :b
      unknown keyword: :z
      unknown keyword: :q
    OUT
  end
end
