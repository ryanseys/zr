# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: control flow" do
  it "abstract raise override return" do
    result = ze0(<<~'RUBY')
      # A method whose base impl always raises (C void return) but is overridden by a
      # value-returning subclass must be callable in value position (#1416): widen the
      # raising base's return to the override's type since its body never returns.
      module Helper
        def self.find(t); t.to_s; end
      end
      class Base
        def self.table_name; raise "abstract"; end
        def self.lookup; Helper.find(table_name); end
      end
      class Article < Base
        def self.table_name; "articles"; end
        def self.lookup; 0; end
      end
      puts Article.lookup

      # instance method, two overrides of divergent types -> unified poly
      class Shape
        def area; raise "abstract"; end
        def describe; "area=#{area}"; end
      end
      class Sq < Shape
        def area; 4; end
      end
      class Nm < Shape
        def area; "n/a"; end
      end
      puts Sq.new.describe
      puts Nm.new.describe
    RUBY

    _(result).must_answer <<~'OUT'
      0
      area=4
      area=n/a
    OUT
  end

  it "bare begin no handler" do
    result = ze0(<<~'RUBY')
      # A `begin ... end` with no rescue / else / ensure protects nothing, so it
      # emits no handler frame -- the do-while idiom above all. The forms that DO
      # need one still behave.
      i = 0
      begin
        i += 1
      end while i < 3
      p i

      j = 10
      begin
        j -= 1
      end until j <= 7
      p j

      v = begin
        1 + 1
      end
      p v

      w = begin
        "a"
        "b"
      end
      p w

      r = begin
        raise "x"
      rescue => e
        e.message
      end
      p r

      def f
        begin
          return 1
        ensure
          puts "ens"
        end
      end
      p f

      def g
        begin
          begin
            raise "inner"
          end
        rescue => e
          "caught #{e.message}"
        end
      end
      p g

      k = 0
      begin
        k += 1
        next if k == 1
      end while k < 2
      p k

      n = 0
      loop do
        begin
          n += 1
        end
        break if n > 2
      end
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      3
      7
      2
      "b"
      "x"
      ens
      1
      "caught inner"
      2
      3
    OUT
  end

  it "break across rescue" do
    result = ze0(<<~'RUBY')
      # A bare `break`/`next` inside a `begin`/`rescue` targets the native loop
      # written OUTSIDE the `begin` (Batch H). The `begin` expression is spliced
      # inline in the loop body, so its final settling translates the bubbled
      # control-flow signal into the loop's own literal jump -- `ensure` still runs
      # exactly once on the way out, and a re-raised exception still propagates.

      # break out of a while loop from the begin body
      i = 0
      while i < 5
        begin
          break if i == 3
          puts "body #{i}"
        rescue
        end
        i += 1
      end
      puts "after while"

      # next from a rescue clause continues the loop
      i = 0
      while i < 5
        i += 1
        begin
          raise "even" if i.even?
          puts "odd #{i}"
        rescue
          next
        end
      end

      # ensure runs before the break crosses out
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

      # a break inside a nested begin bubbles through to the outer loop
      i = 0
      while i < 4
        begin
          begin
            break if i == 2
            puts "inner #{i}"
          rescue
          end
        rescue
        end
        i += 1
      end
      puts "after nested"

      # a re-raised exception is still free to propagate past the loop
      begin
        i = 0
        while i < 3
          begin
            raise "boom" if i == 1
          rescue => e
            raise "rethrow #{e.message}"
          end
          i += 1
        end
      rescue => e
        puts "caught: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      body 0
      body 1
      body 2
      after while
      odd 1
      odd 3
      odd 5
      b0
      e0
      b1
      e1
      e2
      inner 0
      inner 1
      after nested
      caught: rethrow boom
    OUT
  end

  it "break in begin still leaves a raise free to propagate" do
    result = ze0(<<~'RUBY')
      # The loop-crossing settle only translates Break/Next/Redo; a re-raised
      # exception still `?`-propagates out to the outer handler (H2).

      begin
        i = 0
        while i < 3
          begin
            raise "boom" if i == 1
          rescue => e
            raise "rethrow #{e.message}"
          end
          i += 1
        end
      rescue => e
        puts "caught: #{e.message}"
      end
    RUBY

    _(result).must_answer "caught: rethrow boom\n"
  end

  it "break next from inside begin rescue nested in a real escaping block works" do
    result = ze0(<<~'RUBY')
      # A custom `yield`-based method attaches a real escaping block here
      # directly, exercising the same closure boundary `Array#each` would.
      # The begin/rescue lowering needs no
      # special handling: the block passed to `each_num` is ALREADY a real
      # escaping `Proc` (its own closure boundary, `in_real_proc` already
      # true), so a `next` inside the nested `begin`'s rescue clause raises
      # the exact same `Signal` it already would have -- caught by the Proc's
      # own wrapper loop, not by the (irrelevant here) native-loop rejection
      # check.

      class Each3
        def each_num
          yield 1
          yield 2
          yield 3
        end
      end

      Each3.new.each_num do |i|
        begin
          raise "boom" if i == 2
          puts "ok #{i}"
        rescue
          next
        ensure
          puts "ensure #{i}"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ok 1
      ensure 1
      ensure 2
      ok 3
      ensure 3
    OUT
  end

  it "class method begin rescue ensure with return" do
    result = ze0(<<~'RUBY')
      # Exercises the class-method body lowering's own `Signal::Return`
      # catch (added specifically for `Begin` nodes inside a class method --
      # class methods can't contain an escaping block at all, so `Begin` was
      # the only possible trigger there).

      class Factory
        def self.build(fail_it)
          begin
            raise "nope" if fail_it
            "built"
          rescue
            return "fallback"
          ensure
            puts "factory ensure"
          end
        end
      end
      puts Factory.build(false)
      puts Factory.build(true)
    RUBY

    _(result).must_answer <<~'OUT'
      factory ensure
      built
      factory ensure
      fallback
    OUT
  end

  it "ensure runs on return" do
    result = ze0(<<~'RUBY')
      # `begin..ensure..end` must run the ensure clause when the body
      # exits via `return` (bare or with a value). Previously the
      # generated C placed the ensure body *after* the unconditional
      # `return` it followed, so the writeback was dead code.

      class C
        def initialize
          @x = 0
          @v = 0
          @a = 0
        end

        def bare_return
          begin
            x = 100
            return
          ensure
            @x = x
          end
        end

        def value_return
          begin
            v = 7
            return v * 6
          ensure
            @v = v
          end
        end

        def multi_return(c)
          begin
            a = 1
            if c == 1
              return 11
            end
            a = 2
            if c == 2
              return 22
            end
            a = 3
          ensure
            @a = a
          end
        end

        def report
          bare_return
          puts value_return
          multi_return(1)
          puts "a1=" + @a.to_s
          multi_return(2)
          puts "a2=" + @a.to_s
          multi_return(3)
          puts "a3=" + @a.to_s
          puts @x
          puts @v
        end
      end

      C.new.report
    RUBY

    _(result).must_answer <<~'OUT'
      42
      a1=1
      a2=2
      a3=3
      100
      7
    OUT
  end

  it "ensure still runs when break crosses out of a begin" do
    result = ze0(<<~'RUBY')
      # The bubbled `break` is translated only AFTER `ensure` runs, exactly once
      # -- the loop-crossing settle sits below the ensure block (H2).

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
    RUBY

    _(result).must_answer <<~'OUT'
      b0
      e0
      b1
      e1
      e2
    OUT
  end

  it "exc stack window cleared" do
    result = ze0(<<~'RUBY')
      # The exception stack's mark window follows sp_exc_top up and down, and a slot
      # that leaves it kept its pointer. Pop below a used slot, collect (the object
      # is now unreferenced, so it is freed), then push back over it, and the window
      # covers a dangling pointer again -- the collector then walks a header that the
      # allocator has since handed to a string.
      #
      # The slots above the window are cleared where the window is defined, so after
      # any collection a slot outside it holds nothing. This exercises the shape:
      # nesting that oscillates across a used depth, with allocation in between.

      class MissingTemplate < StandardError; end

      def churn(i)
        s = +""
        10.times { |j| s << "<input name=\"f#{i}_#{j}\" value=\"_csrf_token\">" }
        s.length
      end

      def deep(n, i)
        return (raise MissingTemplate, "t#{i}") if n == 0
        begin
          deep(n - 1, i)
        rescue MissingTemplate => e
          churn(i)
          raise e if n > 1
          e.message.length
        end
      end

      total = 0
      2000.times do |i|
        d = (i % 3) + 1
        begin
          total += deep(d, i)
        rescue MissingTemplate
          total += 1
        end
        total += churn(i)
      end
      p total > 0
    RUBY

    _(result).must_answer "true\n"
  end

  it "exception cause" do
    result = ze0(<<~'RUBY')
      # Exception#cause: the exception being handled when a new one is raised
      # is threaded in automatically as the new exception's cause.
      begin
        begin
          raise "root failure"
        rescue
          raise TypeError, "while handling"
        end
      rescue => e
        puts e.class
        puts e.message
        puts e.cause.class
        puts e.cause.message
      end

      # A top-level raise (no active rescue) has no cause.
      begin
        raise "lonely"
      rescue => e
        p e.cause
      end

      # A builtin-raised error inside a rescue also chains.
      begin
        begin
          Integer("not a number")
        rescue
          raise "rewrapped"
        end
      rescue => e
        puts e.cause.class
        puts e.cause.message
      end

      # Three-deep chain.
      begin
        begin
          begin
            raise "level 1"
          rescue
            raise "level 2"
          end
        rescue
          raise "level 3"
        end
      rescue => e
        puts e.message
        puts e.cause.message
        puts e.cause.cause.message
        p e.cause.cause.cause
      end
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      while handling
      RuntimeError
      root failure
      nil
      ArgumentError
      invalid value for Integer(): "not a number"
      level 3
      level 2
      level 1
      nil
    OUT
  end

  it "infer trailing raise return" do
    result = ze0(<<~'RUBY')
      # A method whose body ends in a bare `raise` never returns through that
      # statement, so the raise must not contribute to the return type. Unifying its
      # void with the explicit returns' Integer has no rule and lands on poly, which
      # boxes the return of every `return x if cond; raise` guard method and, through
      # its callers, whatever they feed.
      class Table
        def initialize(names) = @names = names

        def offsets
          h = {}
          i = 0
          while i < @names.length
            h[@names[i]] = i * 2
            i += 1
          end
          h
        end

        # the shape: two guarded returns, then a raise
        def lookup(token, offs)
          return offs[token] if offs.key?(token)
          return token.to_i if token != ""
          raise ArgumentError, "unknown token"
        end
      end

      t = Table.new(["a", "b", "c"])
      o = t.offsets
      p o.keys.sort
      p o["c"]
      p t.lookup("b", o)
      p t.lookup("41", o)
      p t.lookup("a", o) + t.lookup("1", o)
      begin
        t.lookup("", o)
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      4
      2
      41
      1
      unknown token
    OUT
  end

  it "method level rescue return" do
    result = ze0(<<~'RUBY')
      # Method-level rescue: when a method body is a begin/rescue, the
      # rescue body's last expression should become the method's return
      # value. CRuby semantics: `def f; X; rescue; Y; end` returns X if
      # X succeeds, Y if X raises and the rescue catches.
      #
      # This test pins int-returning shapes only. String-returning method
      # bodies with begin/rescue need a separate fix to method return-type
      # inference (which currently picks int as the default for BeginNode-
      # bodied methods regardless of the begin/rescue branch types).

      # Bare rescue catches and returns fallback
      def safe(n)
        raise "boom" if n < 0
        n
      rescue
        -1
      end
      puts safe(5)
      puts safe(-1)

      # Typed rescue catches matching class and returns from rescue body.
      # Use explicit raise rather than Integer() since spinel's Integer()
      # doesn't raise on unparseable input — separate gap, not under test.
      def parse(s)
        raise ArgumentError, "bad" if s == "nope"
        s.to_i
      rescue ArgumentError
        -999
      end
      puts parse("42")
      puts parse("nope")

      # Rescue body with multiple statements: last is the return value
      def lookup(k)
        raise "missing" if k == "x"
        k.length
      rescue
        msg = "fallback"
        msg.length
      end
      puts lookup("hello")
      puts lookup("x")
    RUBY

    _(result).must_answer <<~'OUT'
      5
      -1
      42
      -999
      5
      8
    OUT
  end

  it "nested retry only restarts the innermost begin" do
    result = ze0(<<~'RUBY')
      outer_runs = 0
      inner_attempts = 0
      begin
        outer_runs += 1
        begin
          inner_attempts += 1
          raise "x" if inner_attempts < 2
          puts "inner ok after #{inner_attempts}"
        rescue
          retry if inner_attempts < 2
        end
        puts "outer ran #{outer_runs} times"
      end
    RUBY

    _(result).must_answer "inner ok after 2\nouter ran 1 times\n"
  end

  it "next inside begin rescue continues the enclosing native loop" do
    result = ze0(<<~'RUBY')
      # `next` from a `rescue` clause -> `continue` the enclosing loop (H2).

      i = 0
      while i < 5
        i += 1
        begin
          raise "x" if i.even?
          puts "odd #{i}"
        rescue
          next
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      odd 1
      odd 3
      odd 5
    OUT
  end

  it "next runs ensure" do
    result = ze0(<<~'RUBY')
      r = []
      [1].each do |x|
        begin
          r << :begin
          next
          r << :nope
        ensure
          r << :ensure
        end
      end
      p r
      r2 = []
      [1, 2].each do |x|
        begin
          r2 << :outer_begin
          begin
            r2 << :inner_begin
            next if x == 1
          ensure
            r2 << :inner_ensure
          end
          r2 << :after
        ensure
          r2 << :outer_ensure
        end
      end
      p r2
      r3 = []
      begin
        [1].each do |x|
          r3 << :in
          next
        end
        r3 << :out
      ensure
        r3 << :ens
      end
      p r3
    RUBY

    _(result).must_answer <<~'OUT'
      [:begin, :ensure]
      [:outer_begin, :inner_begin, :inner_ensure, :outer_ensure, :outer_begin, :inner_begin, :inner_ensure, :after, :outer_ensure]
      [:in, :out, :ens]
    OUT
  end

  it "raise with an explicit message and class" do
    result = ze0(<<~'RUBY')
      class MyError < StandardError
      end
      class Risky
        def check(n)
          raise MyError, "bad value: #{n}" if n < 0
          n * 2
        end
      end
      r = Risky.new
      puts r.check(5)
      puts r.check(-1)
    RUBY

    _(result).must_answer "10\n", stderr: <<~'ERR', status: 1
      lang/exceptions/control_flow_test.rb:5:in 'Risky#check': bad value: -1 (MyError)
      	from lang/exceptions/control_flow_test.rb:11:in '<main>'
    ERR
  end

  it "rescue" do
    result = ze0(<<~'RUBY')
      # Test rescue/raise/ensure

      def safe_div(a, b)
        if b == 0
          raise "division by zero"
        end
        a / b
      end

      # Basic rescue
      begin
        result = safe_div(10, 2)
        puts result  # 5
      rescue
        puts "error"
      end

      # Rescue with exception
      begin
        result = safe_div(10, 0)
        puts result
      rescue => e
        puts e  # division by zero
      end

      # Ensure
      def with_ensure
        puts "start"
        raise "oops"
        puts "unreachable"
      rescue => e
        puts e  # oops
      ensure
        puts "cleanup"
      end
      with_ensure

      # Retry pattern
      attempts = 0
      begin
        attempts += 1
        raise "fail" if attempts < 3
        puts attempts  # 3
      rescue
        retry if attempts < 3
      end

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      5
      division by zero
      start
      oops
      cleanup
      3
      done
    OUT
  end

  it "rescue naming an undefined constant compiles and never fires if no exception" do
    result = ze0(<<~'RUBY')
      # The `rescue` clause's class expression is only evaluated while matching
      # an actually-raised exception. A clause that never fires must not fail
      # the compile just because its class isn't defined.

      begin
        1 + 1
      rescue NeverDefined
        puts "caught"
      end
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "rescue return with ensure" do
    result = ze0(<<~'RUBY')
      # `return` / `next` from a rescue or else clause under `ensure` leaves the
      # handler stack intact for later rescues.
      def ret_from_rescue
        raise "x"
      rescue => e
        return "r:#{e.message}"
      ensure
        puts "ensure ran"
      end

      def ret_from_else
        1
      rescue
        return "rescued"
      else
        return "else"
      ensure
        puts "ensure ran"
      end

      def next_from_rescue(xs)
        out = []
        xs.each do |x|
          begin
            raise "odd" if x.odd?
            out << x
          rescue
            next
          ensure
            out << -x
          end
        end
        out
      end

      def nested_ret
        begin
          raise "inner"
        rescue
          return "inner-rescue"
        ensure
          puts "inner ensure"
        end
      ensure
        puts "outer ensure"
      end

      p ret_from_rescue
      p ret_from_else
      p next_from_rescue([1, 2, 3])
      p nested_ret

      # every later rescue must still catch
      begin
        raise "boom"
      rescue => e
        p e.message
      end
      p((Integer("zz") rescue -1))
      x = (raise "mod" rescue "modifier")
      p x
    RUBY

    _(result).must_answer <<~'OUT'
      ensure ran
      "r:x"
      ensure ran
      "else"
      [-1, 2, -2, -3]
      inner ensure
      outer ensure
      "inner-rescue"
      "boom"
      -1
      "modifier"
    OUT
  end

  it "rescue value empty container" do
    result = ze0(<<~'RUBY')
      # An empty container's type reads UNKNOWN for want of an element type, which is
      # not the same as producing no value. Wherever a rescue-bearing expression asks
      # "does this arm carry a value?", the two were conflated: the modifier form
      # built the array and threw it away (`x = ([] rescue 0)` assigned nil), and the
      # begin/rescue form took the other arm's type alone and put a container pointer
      # in an mrb_int slot (#3495, #3496). Both arms of both forms are covered here.
      a = ([] rescue 0)
      p a
      p a.class
      p ({} rescue 0)
      p (Array.new rescue 0)
      p (Hash.new rescue 0)
      p ([1] rescue 0)
      p (raise("x") rescue 0)

      # the value is a real container, not just something that prints like one
      b = ([] rescue 0)
      b << 1 if b.is_a?(Array)
      p b

      c = begin
        []
      rescue
        0
      end
      p c

      d = begin
        {}
      rescue
        0
      end
      p d

      # the empty container on the HANDLER side
      e = begin
        raise "e"
      rescue
        []
      end
      p e

      f = begin
        Integer("z")
      rescue ArgumentError
        {}
      end
      p f

      # both arms empty
      g = begin
        []
      rescue
        []
      end
      p g

      # a non-empty body still behaves
      h = begin
        [1, 2]
      rescue
        0
      end
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      []
      Array
      {}
      []
      {}
      [1]
      0
      [1]
      []
      {}
      []
      {}
      []
      [1, 2]
    OUT
  end

  it "retry and ensure combined inside an enclosing while loop" do
    result = ze0(<<~'RUBY')
      # The `begin`'s own `retry` restarts just its OWN body (not the `while`
      # loop), and `ensure` runs once per `while` ITERATION (twice total,
      # once per `i`) -- not once per `retry` attempt within an iteration.

      total_ensure = 0
      i = 0
      while i < 2
        attempts = 0
        begin
          attempts += 1
          raise "x" if attempts < 2
        rescue
          retry if attempts < 2
        ensure
          total_ensure += 1
        end
        i += 1
      end
      puts total_ensure
    RUBY

    _(result).must_answer "2\n"
  end

  it "retry loop runs ensure exactly once not per attempt" do
    result = ze0(<<~'RUBY')
      class Attempt
        def initialize
          @attempts = 0
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

    _(result).must_answer "succeeded after 3 attempts\nensure ran, attempts=3\n"
  end

  it "return from a rescue body still runs ensure exactly once" do
    result = ze0(<<~'RUBY')
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

    _(result).must_answer "ensure ran before return\nreturned\n"
  end

  it "return from ensure overrides return from the begin body" do
    result = ze0(<<~'RUBY')
      # Real, tricky Ruby semantic: a `return` inside `ensure` wins over a
      # `return` already in flight from `begin`'s own body -- not just "ensure
      # runs afterward", it actually REPLACES the method's return value.
      # Falls out for free here: `ensure`'s own statements lower inline,
      # so a `return` inside it
      # exits the enclosing method directly, superseding the return value
      # already in flight.

      class M
        def m
          begin
            return "from begin"
          ensure
            return "from ensure"
          end
        end
      end
      puts M.new.m
    RUBY

    _(result).must_answer "from ensure\n"
  end

  it "times loop containing begin rescue with no crossing control flow still works" do
    result = ze0(<<~'RUBY')
      # A native loop CONTAINING a `begin`/`rescue` (as opposed to a `begin`
      # containing a bare `break`/`next` TARGETING an outer loop, the
      # rejected shape) is completely unaffected -- the `.times` loop's own
      # control flow doesn't cross the begin/rescue closure boundary at all
      # here, so it just runs normally, once per iteration.

      3.times do |i|
        begin
          raise "x" if i == 1
          puts "ok #{i}"
        rescue
          puts "rescued #{i}"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ok 0
      rescued 1
      ok 2
    OUT
  end

  it "toplevel return from rescue" do
    result = ze0(<<~'RUBY')
      # `return` written at the top level ends the program. Zeo used to fold only
      # the plain statement form; from a position that RAISES the signal instead of
      # returning literally -- inside a `rescue` clause, an `ensure`, a `begin/end
      # while` -- it escaped every frame and the program died with "uncaught signal
      # escaped the top level". The exit status is 0 and `at_exit` still runs, both
      # of which say this is an ordinary end and not an error.
      at_exit { puts "at_exit ran" }

      puts "start"

      begin
        raise "boom"
      rescue RuntimeError => e
        puts "rescued #{e.message}"
        return
      end

      puts "never printed"
    RUBY

    _(result).must_answer <<~'OUT'
      start
      rescued boom
      at_exit ran
    OUT
  end

  it "unresolved tail call value" do
    result = ze0(<<~'RUBY')
      # A method whose body ends in a call nothing resolves (`@text.string` with
      # @text a String) never returns a value: the emitter answers that tail with a
      # NoMethodError raise. A caller that READS the value still needs a typed
      # result, and the untyped return made the assignment a void expression.

      # A user class sharing the tail call's NAME is not a candidate when the
      # receiver is statically a String: only a reopen of String could answer it.
      class Holder
        def initialize
          @string = "held"
        end

        def string
          @string
        end
      end

      class Gen
        def initialize
          @text = ""
        end

        def text
          @text.string
        end
      end

      class Parse
        def initialize
          @t = ""
        end

        def prep
          g = Gen.new
          @t = g.text
        end

        def size
          @t.length
        end
      end

      p1 = Parse.new
      begin
        p1.prep
      rescue NoMethodError => e
        puts "raised"
      end
      p p1.size
      p Holder.new.string
    RUBY

    _(result).must_answer <<~'OUT'
      raised
      0
      "held"
    OUT
  end

  it "valued break deep" do
    result = ze0(<<~'RUBY')
      # Deeply nested break scopes: each recursion level enters a break-wrapped
      # iterator whose scope stays live while the block recurses deeper, so many
      # scopes are simultaneously on the fixed-size break stack. This exercises the
      # push/pop balance and per-scope serial addressing at depth (well under the
      # SP_BRK_STACK_MAX guard that turns an overflow into a loud fatal rather than
      # corruption). deep(n) == n: each level's `each` returns its own break value.
      def deep(n)
        return 0 if n == 0
        [1, 2, 3].each do |x|
          break deep(n - 1) + 1
        end
      end
      p deep(1)
      p deep(40)

      # Depth through a yield method: the spliced block's break targets the call that
      # received it at each level, past the method's own iterator.
      def relay
        [1].each { |x| yield x }
      end
      def climb(n)
        return 0 if n == 0
        relay { |x| break climb(n - 1) + x }
      end
      p climb(50)

      # A break at a shallow level must still target its own scope when deeper
      # (already-returned) scopes have been popped: sequential, not just nested.
      def once
        [1, 2, 3].each { |x| break x * 10 if x == 2 }
      end
      sum = 0
      10.times { sum += once }
      p sum
    RUBY

    _(result).must_answer <<~'OUT'
      1
      40
      50
      200
    OUT
  end

  it "valued break ensure" do
    result = ze0(<<~'RUBY')
      # A break crossing begin/ensure frames runs the ensure bodies on the way out
      # (CRuby TAG_BREAK unwinding), then the call yields the break value.
      p([1, 2, 3].each { |x| begin; break 1 if x == 2; ensure; puts "e#{x}"; end })

      # nested ensures both run, innermost first
      p([1, 2].map do |x|
        begin
          begin
            break :deep if x == 2
            x
          ensure
            puts "inner#{x}"
          end
        ensure
          puts "outer#{x}"
        end
      end)

      # a rescue-only frame between break and the call unwinds cleanly, and a raise
      # AFTER the break-carrying loop still lands in the right handler
      begin
        r = [1, 2, 3].map { |x| begin; break x * 5 if x == 2; x; rescue; :never; end }
        p r
        raise "boom"
      rescue => e
        puts e.message
      end

      # an exception rescued OUTSIDE a wrapped call, then a later unrelated break
      begin
        [1, 2].each { |x| raise "mid" if x == 2 }
      rescue => e
        puts e.message
      end
      p([7, 8].each { |x| break x if x == 8 })

      # break through an ensure inside an inlined yield method
      def guarded
        begin
          yield
        ensure
          puts "guard"
        end
      end
      p(guarded { break :gv })

      # ensure that allocates while the break value is in flight
      p([1, 2].each { |x| begin; break [x, x + 1] if x == 2; ensure; s = "a#{x}" * 3; puts s; end })

      # next/redo in a wrapped block keep their meaning
      p([1, 2, 3].map { |x| next x * 2 if x == 2; break :b if x == 3; x })
    RUBY

    _(result).must_answer <<~'OUT'
      e1
      e2
      1
      inner1
      outer1
      inner2
      outer2
      :deep
      10
      boom
      mid
      8
      guard
      :gv
      a1a1a1
      a2a2a2
      [2, 3]
      :b
    OUT
  end
end
