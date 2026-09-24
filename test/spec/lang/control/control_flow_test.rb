# frozen_string_literal: true

require "spec_helper"

describe "Control: control flow" do
  it "break in a define method body returns" do
    result = zr(<<~'RUBY')
      # `define_method(:go) { break :early }` answers `:early`: the block BECAME
      # the method, so there is no yielding call left to break out of, and CRuby
      # applies its lambda rule -- `break` returns from the method. rake's
      # `define_method(:execute) { ... break if @failure ... }` (cxxproject) is
      # the corpus shape. A real `def` cannot reach this: CRuby rejects a bare
      # `break` in a method body outright.
      class Runner
        def initialize(failed) = @failure = failed

        define_method(:execute) do |arg|
          break :bailed if @failure

          "ran #{arg}"
        end

        # A bare `break` with no value answers nil, like a bare `return`.
        define_method(:blank) { break }

        # ...and a `break` still breaks the INNER call when one is written between
        # it and the method body.
        define_method(:scan) do |items|
          found = nil
          items.each do |i|
            if i > 2
              found = i
              break
            end
          end
          break :none if found.nil?

          found
        end
      end

      p Runner.new(false).execute(:job)
      p Runner.new(true).execute(:job)
      p Runner.new(false).blank
      p Runner.new(false).scan([1, 2, 5, 9])
      p Runner.new(false).scan([1, 2])

      # The singleton spelling takes the same rule.
      class Gate
        define_singleton_method(:open?) { break false }
      end
      p Gate.open?
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      "ran job"
      :bailed
      nil
      5
      :none
      false
      still running
    OUT
  end

  it "break in a while condition leaves the loop" do
    result = zr(<<~'RUBY')
      # A `while` loop is entered before its condition runs, so a `break` or
      # `next` in the condition belongs to that loop: at the top level, in a
      # method, and in a block, where it leaves the loop and not the block.
      i = 0
      p(while (i += 1; i < 3 or break :done); end)

      def f
        j = 0
        while (j += 1; j < 5 or break j * 10); end
      end
      p f

      k = 0
      p [1].map { while (k += 1; k < 2 or break :inner); end }

      n = 0
      seen = []
      while (n += 1; next if n == 2; seen << n; n < 4); end
      p seen

      m = 0
      p(until (m += 1; m > 2 and break :stopped); end)

    RUBY

    _(result).must_answer <<~'OUT'
      :done
      50
      [:inner]
      [1, 3, 4]
      :stopped
    OUT
  end

  it "break with a value makes the iterator call return it" do
    result = zr(<<~'RUBY')
      # `break <v>` in a block makes the whole Enumerable call evaluate to <v>
      # (CRuby TAG_BREAK), not the partial accumulator -- across value-producing
      # (map/select/reject/reduce/count/find) and self-returning
      # (each_with_index) iterators. Bare break -> nil.

      a = [1, 2, 3]
      p a.map { |x| break 99 if x == 2; x * 10 }
      p a.select { |x| break :s if x == 2; x.odd? }
      p a.reject { |x| break 7 if x == 2; false }
      p a.reduce(0) { |s, x| break 100 if x == 2; s + x }
      p a.count { |x| break 5 if x == 2; true }
      p a.find { |x| break(-1) if x == 2; false }
      p a.each_with_index { |x, i| break i if x == 2 }
      p a.map { |x| break if x == 2; x }
      p a.map { |x| x + 1 }
    RUBY

    _(result).must_answer <<~'OUT'
      99
      :s
      7
      100
      5
      -1
      1
      nil
      [2, 3, 4]
    OUT
  end

  it "case tail all arms return" do
    result = zr(<<~'RUBY')
      # A tail `case` whose every arm leaves the function has no value of its own,
      # so the value path widened it to poly and returned the box from a concretely
      # typed function. The if/elsif/else form of the same dispatch always worked
      # (#4156). d3 keeps the mixed shape honest: one arm returns, the others carry
      # a value, so the case still IS the method's value.
      def d1(n)
        case n
        when 1 then return [1, 2]
        when 2 then return [3]
        else return []
        end
      end

      def d2(n)
        case n
        when 1
          return "one"
        else
          raise ArgumentError, "bad"
        end
      end

      def d3(n)
        case n
        when 1 then return "a"
        when 2 then "b"
        else "c"
        end
      end

      def d4(n)
        case n
        when 1 then return 10
        else return 20
        end
      end

      p d1(1), d1(9)
      p d2(1)
      begin
        d2(2)
      rescue ArgumentError => e
        p e.message
      end
      p d3(1), d3(2), d3(9)
      p d4(1), d4(2)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      []
      "one"
      "bad"
      "a"
      "b"
      "c"
      10
      20
    OUT
  end

  it "cmeth return nil or obj via intermediate" do
    result = zr(<<~'RUBY')
      # Issue #411. A class method that initializes a local to `nil`,
      # conditionally reassigns it through an intermediate variable, and
      # returns the local emitted with return type `mrb_int` even though
      # the local itself was correctly typed `sp_Foo *`:
      #
      #   static mrb_int sp_Bar_cls_find(void) {
      #       sp_Foo * lv_result = NULL;
      #       sp_Foo * lv_instance = NULL;
      #       lv_result = NULL;
      #       lv_instance = sp_Foo_new();
      #       lv_result = lv_instance;
      #       return lv_result;       // sp_Foo * -> mrb_int — fails
      #   }
      #
      # Root cause: `infer_all_returns`'s cmeth branch ran a single
      # `scan_locals` pass before calling `infer_body_return`. The first
      # pass typed `result` as "nil" (only the initial `result = nil`
      # was visible), so the tail expression `result` inferred as nil
      # and `unify_return_type` collapsed the cmeth's return to "nil"
      # -> `mrb_int`. The local-decl precompute later upgraded the
      # local correctly via `refine_method_body_locals`'s 2-pass logic
      # ("nil + nullable_pointer_type -> obj_<C>?"), but by that point
      # `@cls_cmeth_returns` was already pinned at "nil".
      #
      # Fix: replace the single-pass scan_locals in
      # `infer_all_returns`'s cmeth branch with a
      # `refine_method_body_locals` call so the multi-pass refinement
      # runs before `infer_body_return` reads the tail.
      #
      # Coverage:
      #   - the canonical Rails-style `_adapter_find_by_id` shape with
      #     intermediate variable (the issue's repro),
      #   - same shape returning the local directly through an `if/else`
      #     branch (no intermediate, regression check that the existing
      #     direct path still works),
      #   - the simple `nil`-fallback flow control (`return nil unless
      #     ...`) to confirm the unify-with-nil tail still resolves
      #     correctly to `obj_<C>?`.

      class Foo
        attr_accessor :tag
        attr_accessor :flag
        def initialize(tag)
          @tag = tag
          @flag = 0
        end
      end

      class Bar
        def self.find(t)
          result = nil
          if t == "yes"
            instance = Foo.new("found")
            result = instance
          end
          result
        end

        def self.find_direct(t)
          result = nil
          if t == "yes"
            result = Foo.new("direct")
          end
          result
        end

        def self.maybe(t)
          return nil unless t == "yes"
          Foo.new("maybe")
        end
      end

      x = Bar.find("yes")
      puts x.nil? ? "nil" : x.tag       # found

      y = Bar.find("no")
      puts y.nil? ? "nil" : y.tag       # nil

      a = Bar.find_direct("yes")
      puts a.nil? ? "nil" : a.tag       # direct

      b = Bar.find_direct("no")
      puts b.nil? ? "nil" : b.tag       # nil

      c = Bar.maybe("yes")
      puts c.nil? ? "nil" : c.tag       # maybe

      d = Bar.maybe("no")
      puts d.nil? ? "nil" : d.tag       # nil
    RUBY

    _(result).must_answer <<~'OUT'
      found
      nil
      direct
      nil
      maybe
      nil
    OUT
  end

  it "collatz" do
    result = zr(<<~'RUBY')
      def steps(n)
        count = 0
        while n != 1
          if n % 2 == 0
            n = n / 2
          else
            n = 3 * n + 1
          end
          count = count + 1
        end
        count
      end
      puts steps(27)
      puts steps(1)
      puts steps(97)
    RUBY

    _(result).must_answer <<~'OUT'
      111
      0
      118
    OUT
  end

  it "concealed class answers nil until reopened" do
    result = zr(<<~'RUBY')
      def probe? = false
      if probe?
        class Ghost
          def x = 1
        end
      end
      if defined?(Ghost)
        puts "have ghost"
      else
        puts "no ghost"
      end
      class Ghost
        def y = 2
      end
      puts defined?(Ghost)
      puts Ghost.new.y
      begin
        Ghost.new.x
      rescue NoMethodError => e
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      no ghost
      constant
      2
      NoMethodError
    OUT
  end

  it "if/elsif/else answers the same as a statement and as a value" do
    result = zr(<<~'RUBY')
      n = -5
      if n < 0
        puts :negative
      elsif n == 0
        puts :zero
      else
        puts :positive
      end

      n2 = 0
      result = if n2 < 0
        :negative
      elsif n2 == 0
        :zero
      else
        :positive
      end
      puts result
    RUBY

    _(result).must_answer "negative\nzero\n"
  end

  it "__LINE__, defined?, the if and unless modifiers, and a ternary chain all answer" do
    result = zr(<<~'RUBY')
      # Test control flow additions

      # __LINE__
      puts __LINE__  # 4

      # defined? on known variable
      x = 42
      puts defined?(x) ? "yes" : "no"  # yes

      # String freeze (no-op in AOT)
      s = "hello"
      puts s  # hello

      # Modifier if/unless
      y = 10
      puts "big" if y > 5     # big
      puts "small" unless y > 100  # small

      # Ternary chains
      a = 3
      puts(a == 1 ? "one" : a == 2 ? "two" : a == 3 ? "three" : "other")  # three

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      4
      yes
      hello
      big
      small
      three
      done
    OUT
  end

  it "break inside a case inside a loop leaves the loop" do
    result = zr(<<~'RUBY')
      out = []
      i = 0
      loop do
        case i
        when 3
          break
        when 7
          break
        end
        out << i
        i = i + 1
        break if i > 50
      end
      p out
    RUBY

    _(result).must_answer "[0, 1, 2]\n"
  end

  it "a method call used as an argument in a while condition runs on every iteration" do
    result = zr(<<~'RUBY')
      # A method call used as an ARGUMENT inside a while condition must be
      # re-evaluated every iteration, not hoisted into a temp before the loop.
      class Gen
        def initialize
          @x = 0
        end
        def cur
          @x
        end
        def advance
          @x = @x + 1
        end
        def small?(v)
          v < 3
        end
      end
      g = Gen.new
      count = 0
      while g.small?(g.cur)
        g.advance
        count = count + 1
        break if count >= 100
      end
      puts count
    RUBY

    _(result).must_answer "3\n"
  end

  it "next inside a case inside a while skips to the following iteration" do
    result = zr(<<~'RUBY')
      out = []
      i = 0
      while i < 8
        i = i + 1
        case i % 3
        when 0
          next
        end
        out << i
      end
      p out
    RUBY

    _(result).must_answer "[1, 2, 4, 5, 7, 8]\n"
  end

  it "a method call used as an argument in an until condition runs on every iteration" do
    result = zr(<<~'RUBY')
      # Same re-evaluation requirement for an until condition argument.
      class Gen
        def initialize
          @x = 0
        end
        def cur
          @x
        end
        def advance
          @x = @x + 1
        end
        def reached?(v)
          v >= 3
        end
      end
      g = Gen.new
      count = 0
      until g.reached?(g.cur)
        g.advance
        count = count + 1
        break if count >= 100
      end
      puts count
    RUBY

    _(result).must_answer "3\n"
  end

  it "an until modifier re-reads the method in its condition on each pass" do
    result = zr(<<~'RUBY')
      class Box
        def initialize
          @v = 0
        end
        def get
          @v
        end
        def bump
          @v = @v + 1
        end
        def at_least?(n)
          get >= n
        end
      end
      b = Box.new
      b.bump until b.at_least?(4)
      puts b.get
    RUBY

    _(result).must_answer "4\n"
  end

  it "a while modifier re-reads the method in its condition on each pass" do
    result = zr(<<~'RUBY')
      class Counter
        def initialize
          @n = 0
        end
        def n
          @n
        end
        def step
          @n = @n + 1
        end
        def under?(limit)
          n < limit
        end
      end
      c = Counter.new
      c.step while c.under?(5)
      puts c.n
    RUBY

    _(result).must_answer "5\n"
  end

  it "each loop binds its own stop" do
    result = zr(<<~'RUBY')
      # Every `loop` desugars to a `rescue StopIteration` whose binding must be
      # ITS OWN local. A single fixed name (`__loop_stop`) aliased every loop in
      # the program to one local -- a `Ractor.new { loop { ... } }` written inside
      # a method that also used `loop` looked like it captured the enclosing
      # method's binding, and refused isolation over a name the source never
      # wrote. (The fixed name also leaked into `local_variables`.)
      def outer_uses_loop
        count = 0
        loop do
          count += 1
          break if count == 2
        end
        r = Ractor.new do
          total = 0
          loop do
            total += 1
            break if total == 3
          end
          total
        end
        puts r.value
        puts count
      end

      outer_uses_loop

      # `loop` returns the StopIteration's result through its binding -- the
      # binding the desugar names must still resolve per loop.
      e = [1, 2].each
      first = loop do
        e.next
      end
      puts first.inspect

      puts local_variables.grep(/__loop/).length
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      3
      2
      [1, 2]
      0
    OUT
      lang/control/control_flow_test.rb:13: warning: Ractor API is experimental and may change in future versions of Ruby.
    ERR
  end

  it "exc frame break next pops" do
    result = zr(<<~'RUBY')
      # break/next leaving a begin/rescue inside a loop must pop the live setjmp
      # frame, exactly like an early return: the stale jmp_buf otherwise points
      # into a dead C stack frame and the next raise longjmps into garbage
      # (repeated iterations also overflow the 64-slot exception stack).

      def scan(arr)
        r = 0
        i = 0
        while i < arr.length
          begin
            if arr[i] == 9
              r = i
              break
            end
            raise "odd" if arr[i].odd?
          rescue
            r = r + 100
          end
          i = i + 1
        end
        r
      end

      def skip_odds(arr)
        total = 0
        arr.each do |x|
          begin
            next if x.odd?
            total = total + x
          rescue
            total = total + 1000
          end
        end
        total
      end

      def first_big(arr)
        found = arr.each do |x|
          begin
            break x if x > 10
          rescue
            nil
          end
        end
        found
      end

      200.times do
        scan([2, 9, 4])
        skip_odds([1, 2, 3, 4])
        first_big([5, 20, 7])
      end

      p scan([2, 9, 4])
      p scan([1, 2, 9])
      p skip_odds([1, 2, 3, 4])
      p first_big([5, 20, 7])
      begin
        raise "after"
      rescue => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      6
      20
      after
    OUT
  end

  it "an early return out of a begin pops its frame, so two hundred of them do not leak" do
    result = zr(<<~'RUBY')
      # An early `return` from inside begin/rescue must pop the live setjmp
      # exception frames it exits. If codegen emits a bare C `return`, the frame
      # stays on sp_exc_stack with a jmp_buf pointing into a dead C stack frame;
      # the next raise longjmps into garbage (Doom's SoundManager#[] crashed this
      # way), and repeated calls overflow the exception stack.

      class SoundCache
        def initialize
          @cache = {}
        end

        def [](key)
          begin
            return @cache[key] if @cache.key?(key)
            value = key * 2
            @cache[key] = value
            value
          rescue
            -1
          end
        end
      end

      sc = SoundCache.new
      sc[7]  # populate: the non-early path pops its frame correctly

      # Each early-return hit leaked one frame (capacity is far below 200).
      total = 0
      1.upto(200) { |i| total += sc[7] }
      puts total

    RUBY

    _(result).must_answer <<~'OUT'
      2800
    OUT
  end

  it "a raise after many early returns lands in the fresh handler" do
    result = zr(<<~'RUBY')
      # An early `return` from inside begin/rescue must pop the live setjmp
      # exception frames it exits. If codegen emits a bare C `return`, the frame
      # stays on sp_exc_stack with a jmp_buf pointing into a dead C stack frame;
      # the next raise longjmps into garbage (Doom's SoundManager#[] crashed this
      # way), and repeated calls overflow the exception stack.

      class SoundCache
        def initialize
          @cache = {}
        end

        def [](key)
          begin
            return @cache[key] if @cache.key?(key)
            value = key * 2
            @cache[key] = value
            value
          rescue
            -1
          end
        end
      end

      sc = SoundCache.new
      sc[7]  # populate: the non-early path pops its frame correctly

      # A raise must land in this fresh handler, not a stale leaked frame.
      begin
        sc[7]
        raise "boom"
      rescue => e
        puts "caught #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      caught boom
    OUT
  end

  it "an early return through two nested begin frames pops both" do
    result = zr(<<~'RUBY')
      # An early `return` from inside begin/rescue must pop the live setjmp
      # exception frames it exits. If codegen emits a bare C `return`, the frame
      # stays on sp_exc_stack with a jmp_buf pointing into a dead C stack frame;
      # the next raise longjmps into garbage (Doom's SoundManager#[] crashed this
      # way), and repeated calls overflow the exception stack.

      class SoundCache
        def initialize
          @cache = {}
        end

        def [](key)
          begin
            return @cache[key] if @cache.key?(key)
            value = key * 2
            @cache[key] = value
            value
          rescue
            -1
          end
        end
      end

      sc = SoundCache.new
      sc[7]  # populate: the non-early path pops its frame correctly

      # Early return through two nested begin frames pops both.
      def double_nested(flag)
        begin
          begin
            return "inner-out" if flag
            "no"
          rescue
            "r1"
          end
          "outer"
        rescue
          "r2"
        end
      end

      200.times { double_nested(true) }
      puts double_nested(true)
      begin
        raise "deep"
      rescue => e
        puts "caught #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      inner-out
      caught deep
    OUT
  end

  it "a return from a begin/rescue nested inside a begin/ensure runs the deferred clause" do
    result = zr(<<~'RUBY')
      # An early `return` from inside begin/rescue must pop the live setjmp
      # exception frames it exits. If codegen emits a bare C `return`, the frame
      # stays on sp_exc_stack with a jmp_buf pointing into a dead C stack frame;
      # the next raise longjmps into garbage (Doom's SoundManager#[] crashed this
      # way), and repeated calls overflow the exception stack.

      class SoundCache
        def initialize
          @cache = {}
        end

        def [](key)
          begin
            return @cache[key] if @cache.key?(key)
            value = key * 2
            @cache[key] = value
            value
          rescue
            -1
          end
        end
      end

      sc = SoundCache.new
      sc[7]  # populate: the non-early path pops its frame correctly

      # Return from a begin/rescue nested inside begin..ensure: the deferred
      # return must pop down to the frame depth at ensure entry (both the rescue
      # frame and the ensure frame), then run the ensure.
      def rescue_in_ensure(flag)
        begin
          begin
            return "early" if flag
            "body"
          rescue
            "rescued"
          end
        ensure
          $ensure_runs += 1
        end
      end

      $ensure_runs = 0
      200.times { rescue_in_ensure(true) }
      puts $ensure_runs
      begin
        raise "after ensure"
      rescue => e
        puts "caught #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      200
      caught after ensure
    OUT
  end

  it "a return from a begin/ensure nested inside a begin/rescue carries on after the ensure" do
    result = zr(<<~'RUBY')
      # An early `return` from inside begin/rescue must pop the live setjmp
      # exception frames it exits. If codegen emits a bare C `return`, the frame
      # stays on sp_exc_stack with a jmp_buf pointing into a dead C stack frame;
      # the next raise longjmps into garbage (Doom's SoundManager#[] crashed this
      # way), and repeated calls overflow the exception stack.

      class SoundCache
        def initialize
          @cache = {}
        end

        def [](key)
          begin
            return @cache[key] if @cache.key?(key)
            value = key * 2
            @cache[key] = value
            value
          rescue
            -1
          end
        end
      end

      sc = SoundCache.new
      sc[7]  # populate: the non-early path pops its frame correctly

      # Return from a begin..ensure nested inside begin/rescue: after the ensure
      # runs, the deferred return must also pop the enclosing rescue frame.
      def ensure_in_rescue(flag)
        begin
          begin
            return "early2" if flag
            "body"
          ensure
            $ensure_runs2 += 1
          end
        rescue
          "rescued"
        end
      end

      $ensure_runs2 = 0
      200.times { ensure_in_rescue(true) }
      puts $ensure_runs2
      begin
        raise "after ensure 2"
      rescue => e
        puts "caught #{e.message}"
      end
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      200
      caught after ensure 2
      done
    OUT
  end

  it "for compiles to coll.each and performs no type dispatch of its own" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `for` performs NO type dispatch -- ruby compiles it to `coll.each { |x|
      # ... }` -- and it opens NO scope: the index is a name of the body
      # around it and outlives the loop. `redo` runs the body again without
      # stepping, and a block-local is a name the block alone can see.

      for i in 1..3
        print i
      end
      puts
      p i

      for a, b in [[1, 2], [3, 4]]
        p [a, b]
      end
      p [a, b]

      pairs = []
      for key, value in { one: 1, two: 2 }
        pairs << [key, value]
      end
      p pairs, key, value

    RUBY

    _(result).must_answer <<~'OUT'
      123
      3
      [1, 2]
      [3, 4]
      [3, 4]
      [[:one, 1], [:two, 2]]
      :two
      2
    OUT
  end

  it "a single for index over a multi-value yield binds the whole pair" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A single index over a multi-value yield binds the WHOLE pair.
      for pair in { three: 3 }
        p pair
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [:three, 3]
    OUT
  end

  it "for walks a live Array, so what the body appends is reached" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # The Array is live: what the body appends is walked.
      grown = [1]
      for g in grown
        grown << 2 if g == 1
        print g
      end
      puts

      out = []
      for x in [1, 2, 3, 4]
        next if x == 2
        break if x == 4

        out << x
      end
      p out, x

    RUBY

    _(result).must_answer <<~'OUT'
      12
      [1, 3]
      4
    OUT
  end

  it "for answers the collection when it runs out, and a break supplies its own value" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # Running out answers the collection; a `break` supplies its own.
      p(for c in [1, 2] do end)
      p(for d in (1...4) do print d end)
      puts
      p(for e in [1, 2, 3] do break e * 10 if e == 2 end)

      for outer in [1, 2]
        for inner in %i[x y]
          print "#{outer}#{inner} "
        end
      end
      puts

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      1231...4

      20
      1x 1y 2x 2y 
    OUT
  end

  it "a raise inside a for body leaves the loop's own state behind cleanly" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A raise inside the body leaves the loop's own state behind cleanly.
      begin
        for r in [1, 2]
          raise ArgumentError, "stop" if r == 2
        end
      rescue ArgumentError => err
        p err.message, r
      end

      begin
        for n in 5
          p n
        end
      rescue NoMethodError => err
        p err.message
      end

      def first_over(list, limit)
        for item in list
          return item if item > limit
        end
        :none
      end

      p first_over([1, 2, 3], 1), first_over([1], 9)

    RUBY

    _(result).must_answer <<~'OUT'
      "stop"
      2
      "undefined method 'each' for an instance of Integer"
      2
      :none
    OUT
  end

  it "an ensure the for jump crosses runs its clause, and the jump goes on" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # An `ensure` the jump crosses runs its clause and the jump goes on.
      def guarded(list)
        log = []
        for n in list
          begin
            next if n == 2
            break if n == 4

            log << n
          ensure
            log << [:e, n]
          end
        end
        log
      end

      p guarded([1, 2, 3, 4, 5])

    RUBY

    _(result).must_answer <<~'OUT'
      [1, [:e, 1], [:e, 2], 3, [:e, 3], [:e, 4]]
    OUT
  end

  it "redo in a native loop steps nothing" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `redo` in a native loop steps nothing.
      turns = 0
      count = 0
      while count < 2
        count += 1
        turns += 1
        redo if turns == 1
      end
      p [count, turns]

      for z in [1, 2]
        turns += 1
        redo if turns == 3
      end
      p [z, turns]

    RUBY

    _(result).must_answer <<~'OUT'
      [2, 2]
      [2, 5]
    OUT
  end

  it "redo in a block re-enters past the bindings, so the parameter keeps its value" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `redo` in a block re-enters PAST the bindings, so the parameter keeps
      # what the body assigned to it.
      steps = []
      [10].each do |v|
        steps << v
        if v < 12
          v += 1
          redo
        end
      end
      p steps

    RUBY

    _(result).must_answer <<~'OUT'
      [10, 11, 12]
    OUT
  end

  it "an ensure in the way of a redo runs each time round" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # ...and an `ensure` in the way runs each time round.
      log = []
      attempts = 0
      [1].each do |_|
        begin
          attempts += 1
          redo if attempts < 3
        ensure
          log << attempts
        end
      end
      p log

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
    OUT
  end

  it "a block-local starts nil on every invocation and never touches the outer name" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A block-local starts nil every invocation and never touches the name
      # outside it.
      scratch = :outer
      seen = []
      [1, 2].each do |n; scratch|
        seen << scratch
        scratch = n
        seen << scratch
      end
      p seen, scratch

    RUBY

    _(result).must_answer <<~'OUT'
      [nil, 1, nil, 2]
      :outer
    OUT
  end

  it "a block-local survives a redo, exactly as a parameter does" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # It survives a redo, exactly as a parameter does.
      kept = []
      rounds = 0
      [1].each do |_; held|
        held = (held || 0) + 1
        kept << held
        rounds += 1
        redo if rounds < 3
      end
      p kept
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
    OUT
  end

  it "for over paren collection" do
    result = zr(<<~'RUBY')
      # A parenthesized collection in a for loop must iterate like the bare form.
      sum = 0
      for i in (0..4)
        sum += i
      end
      p sum

      for j in (1...4)
        p j
      end

      total = 0
      for element in ([5, 6, 7])
        total += element
      end
      p total

      for key, value in ({ "a" => 1, "b" => 2 })
        puts "#{key}=#{value}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      10
      1
      2
      3
      18
      a=1
      b=2
    OUT
  end

  it "gated builtin name is free until required" do
    result = zr(<<~'RUBY')
      # A require-gated builtin's constant does not exist until its feature is
      # required -- so a program that never requires `json` is free to define its
      # own `class JSON`, exactly as CRuby is.
      #
      # zr's reopen detection saw the dormant slot (deliberately -- a same-kind
      # reopen attaches to it) and rejected the kind mismatch with a TypeError
      # CRuby never raises: "JSON is not a class". A hundred ledger gems defined
      # some builtin's name without its require.
      class JSON
        def self.parse(s)
          "my own #{s}"
        end
      end

      puts JSON.parse("parser")
      puts JSON.instance_of?(Class)
    RUBY

    _(result).must_answer "my own parser\ntrue\n"
  end

  it "heterogeneous tuple return" do
    result = zr(<<~'RUBY')
      def kv(s)
        return nil, nil if s.empty?
        return s, s
      end

      a, b = kv("x")
      p [a, b]
      c, d = kv("")
      p [c, d]

      def mixed(s)
        return 1, 1, 1 if s == "i"
        return "a", "b", "c" if s == "s"
        return nil, nil, nil
      end

      e, f, g = mixed("i")
      p [e, f, g]
      h, i, j = mixed("s")
      p [h, i, j]
      k, l, m = mixed("x")
      p [k, l, m]

      def partial(s)
        return s, 1 if s.empty?
        return s, "x"
      end

      n, o = partial("")
      p [n, o]
      q, r = partial("y")
      p [q, r]
    RUBY

    _(result).must_answer <<~'OUT'
      ["x", "x"]
      [nil, nil]
      [1, 1, 1]
      ["a", "b", "c"]
      [nil, nil, nil]
      ["", 1]
      ["y", "x"]
    OUT
  end

  it "if expr multi stmt body" do
    result = zr(<<~'RUBY')
      # When an `if` expression's value is consumed (assignment, return,
      # ternary slot, etc.) and a branch holds multiple statements,
      # compile_if_expr previously kept only the last statement of each
      # branch — emitting `(cond ? lastexpr : ...)`. Any leading
      # side-effect statements in the branch were silently dropped.
      #
      # Fix: detect multi-stmt branches, emit a real `if (cond) { ... }
      # else { ... }` that compiles each leading statement for its side
      # effect and assigns the final expression to a temp. Return the
      # temp as the if-expression's value. Single-stmt / no-stmt branches
      # keep using the original ternary fast path.
      #
      # Coverage:
      # - Multi-stmt then- and else-branches assigned to a local
      # - Elsif chain recursion (multi-stmt branches inside the else slot)
      # - Nested if-expression used as a method argument
      # - Mixed branch lengths (single-stmt then, multi-stmt else)
      # - Empty/missing else (implicit nil → 0)
      #
      # Out of scope:
      # - Poly type-unification of mixed concrete branches (int/string).
      #   Spinel's inference picks one concrete type as the unified type
      #   rather than `poly`, so `tmp = 1LL;` is emitted against a
      #   `const char *` slot. The bug isn't in this PR's multi-stmt
      #   restructuring — the ternary fast path has the same inference
      #   issue. Separate fix.

      x = if true
            puts "a"
            1
          else
            puts "z"
            0
          end
      puts x

      y = if false
            puts "skipped"
            99
          else
            puts "b"
            puts "c"
            42
          end
      puts y

      # Elsif chain recursion.
      z = if false
            1
          elsif true
            puts "elsif"
            2
          else
            3
          end
      puts z

      # Nested if-expression as a method argument.
      puts(if true
             puts "nested"
             10
           end)

      # Mixed branch lengths.
      m = if false
            99
          else
            puts "else-multi"
            100
          end
      puts m

      # Empty/missing else.
      n = if true
            puts "no-else"
            77
          end
      puts n
    RUBY

    _(result).must_answer <<~'OUT'
      a
      1
      b
      c
      42
      elsif
      2
      nested
      10
      else-multi
      100
      no-else
      77
    OUT
  end

  it "logical value return" do
    result = zr(<<~'RUBY')
      def assert_equal(expected, actual)
        if expected != actual
          raise "logical value return mismatch"
        end
      end

      assert_equal(2, 1 && 2)
      assert_equal(nil, nil && 2)
      assert_equal(nil, false || nil)
      assert_equal(false, false && 3)
      assert_equal(true, true || nil)
      assert_equal(nil, true && nil)
      assert_equal(4, false || 4)

      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "loop and redo" do
    result = zr(<<~'RUBY')
      i = 0
      result = loop do
        i += 1
        break i * 10 if i == 3
      end
      puts result

      j = 0
      attempts = 0
      while j < 3
        attempts += 1
        if attempts < 5 && j == 1
          redo
        end
        j += 1
      end
      puts j
      puts attempts
    RUBY

    _(result).must_answer <<~'OUT'
      30
      3
      6
    OUT
  end

  it "loop break value" do
    result = zr(<<~'RUBY')
      # A valued break out of Kernel#loop is the value of the loop -- and, when the
      # loop is a method's tail expression, of the method.
      def factor; i = 0; loop { i += 1; break i * 10 if i >= 3 }; end
      p factor
      def labelled; n = 0; r = loop { n += 1; break "done:#{n}" if n == 2 }; r; end
      p labelled
      def novalue; x = 0; loop { x += 1; break if x > 5 }; x; end
      p novalue
      def after; loop { break }; 99; end
      p after
    RUBY

    _(result).must_answer <<~'OUT'
      30
      "done:2"
      6
      99
    OUT
  end

  it "loop control" do
    result = zr(<<~'RUBY')
      # `break` and `next` inside a loop are the LOOP's, whether the loop is
      # written in a method or inside a block; only a jump with no loop around
      # it is the block's.
      def first_square_over(limit)
        i = 0
        while true
          i += 1
          break if i * i > limit
        end
        i
      end
      p first_square_over(50)

      def odds_below(n)
        out = []
        i = 0
        while i < n
          i += 1
          next if i % 2 == 0
          out << i
        end
        out
      end
      p odds_below(7)

      p [1, 2].map { |n| i = 0; while i < 10; i += 1; break if i == n + 2; end; i }
      p [1].map { o = []; i = 0; while i < 5; i += 1; next if i == 2; o << i; end; o }
      p [1].map { i = 0; until i > 2; i += 1; break :early; end; i }
      p [1].map { i = 0; (i += 1; break :modifier if i > 1) while true; i }

      # A `while` answers nil, or whatever a `break` gave it.
      p(while true; break 7; end)
      i = 0
      p(while i < 2; i += 1; end)

      # A block written inside a loop keeps its own `break`.
      seen = []
      n = 0
      while n < 3
        n += 1
        seen << [1, 2, 3].each { |x| break x * 10 if x == 2 }
      end
      p seen

      # Nested loops: the inner `break` leaves only the inner one.
      pairs = []
      i = 0
      while i < 3
        i += 1
        j = 0
        while j < 9
          j += 1
          break if j == 2
        end
        pairs << [i, j]
      end
      p pairs

      # A jump out of a `rescue` clause inside a loop pops only what it opened.
      kept = []
      i = 0
      while i < 5
        i += 1
        begin
          raise "stop" if i == 4
          next if i == 2
          kept << i
        rescue StandardError
          break
        end
      end
      p kept

      # `else` runs only when the body finished, and outside the clauses.
      p(begin
          "a" + "b"
        rescue StandardError
          :rescued
        else
          "c" + "d"
        end)
      p(begin
          raise "boom"
        rescue StandardError
          :rescued
        else
          :else_ran
        end)

      # A method defined twice keeps the last one, as ruby does.
      class Twice
        def answer = 1
        def answer(_x) = 2
      end
      p Twice.new.answer(0)
      p Twice.instance_method(:answer).arity
    RUBY

    _(result).must_answer <<~'OUT'
      8
      [1, 3, 5, 7]
      [3, 4]
      [[1, 3, 4, 5]]
      [1]
      [2]
      7
      nil
      [20, 20, 20]
      [[1, 2], [2, 2], [3, 2]]
      [1, 3]
      "cd"
      :rescued
      2
      1
    OUT
  end

  it "loop enum with index find" do
    result = zr(<<~'RUBY')
      # Blockless Kernel#loop yields an infinite Enumerator; with_index over a
      # generator-backed enum is lazy, and Enumerator#find drives via #next so
      # infinite sources terminate on the block's break and finite sources
      # return nil on no match (#3236).
      r = loop.with_index.find { |_, i| break i if i == 3 }
      p r
      e = loop
      p e.class
      a = [10, 20, 30].each
      p a.find { |v| v > 15 }
      p a.rewind.find { |v| v > 99 }
      p [1, 2, 3].each.with_index.find { |v, i| v + i == 5 }
    RUBY

    _(result).must_answer <<~'OUT'
      3
      Enumerator
      20
      nil
      [3, 2]
    OUT
  end

  it "loop in value position" do
    result = zr(<<~'RUBY')
      # A `while`/`until`/`loop`/`for` written where a value is READ: the loop
      # itself is worth nil (`for` its collection), and a `break v` its own.
      r = while true
        break :val
      end
      p r
      i = 0
      q = while i < 3
        i += 1
      end
      p q
      n = 0
      z = until n >= 2
        n += 1
        break n if n == 2
      end
      p z
      f = for x in [1,2,3]
        break :early if x == 2
      end
      p f
      g = for y in [1,2]
      end
      p g
      l = loop do
        break 42
      end
      p l
      h = [1,2].map { |v| (while false; end) || v }
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      :val
      nil
      2
      :early
      [1, 2]
      42
      [1, 2]
    OUT
  end

  it "loop return frame pop" do
    result = zr(<<~'RUBY')
      # A `return` from inside `loop { }` has to pop the handler frame that loop
      # opened (it rescues StopIteration through a setjmp). Without the accounting
      # the frame stack grew by one per call and, past its 64 slots, the writes ran
      # off the end of the array -- the GC then walked a corrupted root stack and
      # the program segfaulted.

      def first_at_least(n)
        i = 0
        loop do
          i += 1
          loop do
            return i if i >= n
            break
          end
        end
      end

      200.times { first_at_least(3) }
      GC.start
      p first_at_least(3)
      p first_at_least(7)

      # the same shape with the loop's value used (the value-position emitter)
      def pick(n)
        i = 0
        v = loop do
          i += 1
          return -1 if i > n
          break i if i == n
        end
        v
      end

      200.times { pick(4) }
      GC.start
      live = (1..50).map { |i| [i.to_s, i] }
      GC.start
      p live.length
      p pick(4)
      p pick(0)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      7
      50
      4
      -1
    OUT
  end

  it "loop stopiteration result" do
    result = zr(<<~'RUBY')
      e001 = [1, 2].each
      r001 = loop { e001.next }
      p r001
      e002 = (1..3).each
      r002 = loop { e002.next }
      p r002
      r003 = loop { break 5 }
      p r003
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      1..3
      5
    OUT
  end

  it "multi return" do
    result = zr(<<~'RUBY')
      def divmod(a, b)
        [a / b, a % b]
      end

      q, r = divmod(17, 5)
      puts q  # 3
      puts r  # 2

      # Swap
      x = 10
      y = 20
      x, y = y, x
      puts x  # 20
      puts y  # 10

      # From array literal
      a, b, c = [100, 200, 300]
      puts a  # 100
      puts b  # 200
      puts c  # 300

      # Multiple return values used in expressions
      def minmax(a, b)
        if a < b
          [a, b]
        else
          [b, a]
        end
      end

      lo, hi = minmax(42, 7)
      puts lo  # 7
      puts hi  # 42

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      20
      10
      100
      200
      300
      7
      42
      done
    OUT
  end

  it "multi return bare" do
    result = zr(<<~'RUBY')
      # `return a, b` materializes as a fixed-arity tuple struct, preserving
      # heterogeneous element types unboxed.

      class C
        def initialize
          @x = 1
          @y = 2
          @z = 3
          @s1 = "hi"
          @s2 = "lo"
          @f1 = 1.5
          @f2 = 2.5
        end

        def two_ints
          return @x, @y
        end

        def three_ints
          return @x, @y, @z
        end

        def two_strs
          return @s1, @s2
        end

        def two_floats
          return @f1, @f2
        end

        # Heterogeneous: int + string (no boxing — fields keep concrete types).
        def int_and_str
          return @x, @s1
        end

        # Heterogeneous: int + float + string.
        def three_mixed
          return @x, @f1, @s1
        end

        def consume
          a, b = two_ints
          a + b
        end
      end

      c = C.new

      a, b = c.two_ints
      puts a            # 1
      puts b            # 2

      a, b, d = c.three_ints
      puts a            # 1
      puts b            # 2
      puts d            # 3

      s1, s2 = c.two_strs
      puts s1           # hi
      puts s2           # lo

      f1, f2 = c.two_floats
      puts f1           # 1.5
      puts f2           # 2.5

      i, s = c.int_and_str
      puts i            # 1
      puts s            # hi

      i, f, s = c.three_mixed
      puts i            # 1
      puts f            # 1.5
      puts s            # hi

      puts c.consume    # 3

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      1
      2
      3
      hi
      lo
      1.5
      2.5
      1
      hi
      1
      1.5
      hi
      3
      done
    OUT
  end

  it "next in proc and yield" do
    result = zr(<<~'RUBY')
      # `next` leaves the BLOCK with its value. Three emission contexts: a _proc_N
      # function body (next = the proc's return), a yield-inlined block splice
      # (next = leave the do{}while(0) wrapper with the value), and a genuine loop
      # (next = plain continue -- must stay untouched).
      a = []
      -> {
        a << 1
        next
        a << 2
      }.call
      p a
      f = -> { next 42; 7 }
      p f.call
      def r(val)
        v = yield()
        val == v
      end
      p r(nil) { next }
      p r(1) { next 1 }
      p r(5) { 5 }
      g = proc { [1, 2, 3].each { |i| next if i == 2; a << i }; a.length }
      p g.call
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      42
      true
      true
      true
      3
    OUT
  end

  it "next in then block" do
    result = zr(<<~'RUBY')
      def pick(n)
        n.then do |v|
          next [] if v.zero?
          next [v] if v < 10
          [v, v * 2]
        end
      end

      p pick(0)
      p pick(3)
      p pick(20)

      p(
        [1, 2].flat_map do |v|
          v.then do |x|
            next [] if x == 1
            [x]
          end
        end
      )

      def tally(n)
        seen = []
        n.tap do |v|
          next if v.negative?
          seen << v
        end
        seen
      end

      p tally(-1)
      p tally(7)

      h = 0.then do |v|
        next({}) if v.zero?
        { "k" => v }
      end
      p h

      s = "ab".then do |t|
        next "-" if t.empty?
        t.upcase
      end
      p s
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [3]
      [20, 40]
      [2]
      []
      [7]
      {}
      "AB"
    OUT
  end

  it "next value each index" do
    result = zr(<<~'RUBY')
      # `next <value>` through each.with_index collectors: map contributes the value,
      # select/reject decide inclusion, the scalar terminals read the value.
      p [10, 20, 30].each_with_index.map { |x, i| next 0 if i == 1; x + i }       # [10, 0, 32]
      p [10, 20, 30].each_with_index.map { |x, i| x + i }                         # [10, 21, 32]
      p [10, 20, 30].each_with_index.select { |x, i| next true if i == 0; x > 15 } # [[10,0],[20,1],[30,2]]
      p [1, 2, 3, 4].each_with_index.count { |x, i| next true if i == 0; x.even? } # 3
      p [2, 4, 6].each_with_index.all? { |x, i| next true if i == 2; x.even? }     # true
      p [10, 20, 30].each_with_index.map { |x, i| }                               # [nil, nil, nil] (empty body)
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 0, 32]
      [10, 21, 32]
      [[10, 0], [20, 1], [30, 2]]
      3
      true
      [nil, nil, nil]
    OUT
  end

  it "next value flat map" do
    result = zr(<<~'RUBY')
      # `next [..]` inside a flat_map block flattens its array, exactly like the tail.
      p [1, 2, 3].flat_map { |x| next [0] if x == 2; [x, x] }        # [1, 1, 0, 3, 3]
      p [1, 2, 3].flat_map { |x| [x, x * 10] }                       # [1, 10, 2, 20, 3, 30]
      p ["a", "b"].flat_map { |s| next ["X"] if s == "b"; [s, s] }   # ["a", "a", "X"]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1, 0, 3, 3]
      [1, 10, 2, 20, 3, 30]
      ["a", "a", "X"]
    OUT
  end

  it "next value map" do
    result = zr(<<~'RUBY')
      # `next <value>` inside a map block contributes that value, rather than
      # dropping the element as a bare `continue` would.
      p [1, 2, 3].map { |x| next x * 2 }                                  # [2, 4, 6]

      # An interior conditional next with a fall-through tail expression.
      p [1, 2, 3, 4].map { |x| next 0 if x.even?; x }                     # [1, 0, 3, 0]

      # A next carrying a computed local, mixed with a tail.
      p [1, 2, 3].map { |x| y = x * x; next y if x == 2; y + 100 }        # [101, 4, 109]

      # String elements with a conditional next.
      p ["a", "bb", "ccc"].map { |s| next "X" if s.length == 2; s.upcase } # ["A", "X", "CCC"]

      # A next whose value type differs from the tail widens the result to a poly
      # array, so the carried value is boxed (not coerced to the tail's scalar type).
      p [1, 2, 3].map { |x| next "big" if x > 2; x }                      # [1, 2, "big"]
      p [1, 2, 3].map { |x| next x.to_f if x == 2; x * 10 }              # [10, 2.0, 30]

      # A plain map (no next) and select/reject keep their behavior.
      p [1, 2, 3].map { |x| x + 1 }                                       # [2, 3, 4]
      p [1, 2, 3, 4].select { |x| x > 2 }                                 # [3, 4]
      p [1, 2, 3, 4].reject(&:even?)                                      # [1, 3]
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6]
      [1, 0, 3, 0]
      [101, 4, 109]
      ["A", "X", "CCC"]
      [1, 2, "big"]
      [10, 2.0, 30]
      [2, 3, 4]
      [3, 4]
      [1, 3]
    OUT
  end

  it "a return inside a block exits the method the block was written in" do
    result = zr(<<~'RUBY')
      # A `return` inside a block exits the method the BLOCK was written in, however
      # many frames it has to unwind through. Every method it passes on the way is
      # just a relay: one that catches a `Signal::Return` of its own -- because it has
      # a `begin` or an escaping block -- must still let this one through.
      def one
        [1, 2, 3].each { |x| yield x }
        :fell
      end
      def c1; one { |x| return x }; :no; end
      p c1

    RUBY

    _(result).must_answer <<~'OUT'
      1
    OUT
  end

  it "a return travels out through two nested blocks and an explicit &b" do
    result = zr(<<~'RUBY')
      # Through two nested blocks and an explicit `&b`.
      def two(&b)
        [1, 2].each { |x| [3, 4].each { |y| b.call(x * y) } }
        :fell
      end
      def c2; two { |v| return v }; :no; end
      p c2

    RUBY

    _(result).must_answer <<~'OUT'
      3
    OUT
  end

  it "a return travels out through an Enumerator and through a lazy chain" do
    result = zr(<<~'RUBY')
      # Through an Enumerator, and through a lazy chain.
      def three
        Enumerator.new { |y| y << 1; y << 2 }.each { |v| yield v }
        :fell
      end
      def c3; three { |v| return v }; :no; end
      p c3

    RUBY

    _(result).must_answer <<~'OUT'
      1
    OUT
  end

  it "a return travels out of a block a builtin yielded to" do
    result = zr(<<~'RUBY')
      def lazily
        [1, 2, 3].lazy.map { |x| x * 2 }.each { |v| yield v }
        :fell
      end
      def c4; lazily { |v| return v }; :no; end
      p c4

    RUBY

    _(result).must_answer <<~'OUT'
      2
    OUT
  end

  it "a return passes a relay whose begin has an ensure but no return of its own" do
    result = zr(<<~'RUBY')
      # Through a relay that has a `begin`/`ensure` -- no `return` of its own, so it
      # has nothing to catch.
      def ensured
        begin
          yield 9
        ensure
          nil
        end
        :fell
      end
      def c5; ensured { |v| return v }; :no; end
      p c5

    RUBY

    _(result).must_answer <<~'OUT'
      9
    OUT
  end

  it "a return passes several relays and still reaches its home" do
    result = zr(<<~'RUBY')
      def rescued
        yield 8
      rescue StandardError
        :r
      else
        :fell
      end
      def c6; rescued { |v| return v }; :no; end
      p c6

    RUBY

    _(result).must_answer <<~'OUT'
      8
    OUT
  end

  it "a relay's own return inside a begin returns the relay, not the home method" do
    result = zr(<<~'RUBY')
      # Through a relay that has a `return` of its own INSIDE the begin: it really
      # does catch, and must still tell the two apart.
      def both
        begin
          yield 7
          return :inner
        rescue StandardError
          :r
        end
      end
      def c7; both { |v| return v }; :no; end
      p c7
      p both { :ignored }

    RUBY

    _(result).must_answer <<~'OUT'
      7
      :inner
    OUT
  end

  it "a return travels out through several frames" do
    result = zr(<<~'RUBY')
      # Through several frames, and through `__send__`.
      def deep3(&b) = deep2(&b)
      def deep2(&b) = deep1(&b)
      def deep1(&b)
        [1, 2].each { |x| b.call(x) }
        :fell
      end
      def c8; deep3 { |v| return v }; :no; end
      p c8

    RUBY

    _(result).must_answer <<~'OUT'
      1
    OUT
  end

  it "a return travels out through __send__" do
    result = zr(<<~'RUBY')
      class Relay
        def go(&b)
          begin
            __send__(:inner, &b)
          rescue StandardError
            :r
          end
          :fell
        end
        def inner = yield(:through_send)
      end
      def c9; Relay.new.go { |v| return v }; :no; end
      p c9

    RUBY

    _(result).must_answer <<~'OUT'
      :through_send
    OUT
  end

  it "a return whose home has already unwound raises LocalJumpError" do
    result = zr(<<~'RUBY')
      # A `return` whose home has already unwound is a LocalJumpError, not a jump
      # into a dead frame.
      def escapee = proc { return :gone }
      begin
        escapee.call
      rescue LocalJumpError => e
        p [:local_jump, e.reason]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [:local_jump, :return]
    OUT
  end

  it "a lambda's return is its own and never leaves the caller" do
    result = zr(<<~'RUBY')
      # A lambda's `return` is its own, and never leaves the caller.
      def lam
        l = lambda { return :from_lambda }
        [l.call, :after]
      end
      p lam
    RUBY

    _(result).must_answer <<~'OUT'
      [:from_lambda, :after]
    OUT
  end

  it "or return expression" do
    result = zr(<<~'RUBY')
      def fetch006(h006, k006)
        v006 = h006[k006] or return
        v006
      end
      p fetch006({ a: 1 }, :a)
      p fetch006({ a: 1 }, :b)

      def g(x)
        y = x or return "none"
        "got #{y}"
      end
      p g(nil)
      p g(5)

      def h(x)
        y = x || return
        y * 2
      end
      p h(3)
      p h(nil)

      def sum_positive(a)
        t = 0
        a.each do |v|
          v > 0 or next
          t += v
        end
        t
      end
      p sum_positive([1, -2, 3])

      def first_neg(a)
        found = nil
        a.each do |v|
          v < 0 and break
          found = v
        end
        found
      end
      p first_neg([1, 2, -3, 4])
    RUBY

    _(result).must_answer <<~'OUT'
      1
      nil
      "none"
      "got 5"
      6
      nil
      4
      2
    OUT
  end

  it "times" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_times
        attempts = 0
        3.times do |i|
          attempts += 1
          if i == 1 && attempts < 5
            redo
          end
          puts "i=#{i} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_times
    RUBY

    _(result).must_answer <<~'OUT'
      i=0 attempt=1
      i=1 attempt=5
      i=2 attempt=6
      total=6
    OUT
  end

  it "Array#each" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_each
        attempts = 0
        [10, 20, 30].each do |x|
          attempts += 1
          if x == 20 && attempts < 5
            redo
          end
          puts "x=#{x} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_each
    RUBY

    _(result).must_answer <<~'OUT'
      x=10 attempt=1
      x=20 attempt=5
      x=30 attempt=6
      total=6
    OUT
  end

  it "while" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_while
        i = 0
        attempts = 0
        while i < 3
          attempts += 1
          if i == 1 && attempts < 5
            redo
          end
          puts "i=#{i} attempt=#{attempts}"
          i += 1
        end
        puts "total=#{attempts}"
      end
      t_while
    RUBY

    _(result).must_answer <<~'OUT'
      i=0 attempt=1
      i=1 attempt=5
      i=2 attempt=6
      total=6
    OUT
  end

  it "until" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_until
        i = 0
        attempts = 0
        until i >= 3
          attempts += 1
          if i == 1 && attempts < 5
            redo
          end
          puts "i=#{i} attempt=#{attempts}"
          i += 1
        end
        puts "total=#{attempts}"
      end
      t_until
    RUBY

    _(result).must_answer <<~'OUT'
      i=0 attempt=1
      i=1 attempt=5
      i=2 attempt=6
      total=6
    OUT
  end

  it "for-in over range" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_for_range
        attempts = 0
        for i in 0..2
          attempts += 1
          if i == 1 && attempts < 5
            redo
          end
          puts "i=#{i} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_for_range
    RUBY

    _(result).must_answer <<~'OUT'
      i=0 attempt=1
      i=1 attempt=5
      i=2 attempt=6
      total=6
    OUT
  end

  it "for-in over array" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_for_array
        attempts = 0
        for x in [10, 20, 30]
          attempts += 1
          if x == 20 && attempts < 5
            redo
          end
          puts "x=#{x} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_for_array
    RUBY

    _(result).must_answer <<~'OUT'
      x=10 attempt=1
      x=20 attempt=5
      x=30 attempt=6
      total=6
    OUT
  end

  it "Kernel#loop (uses break to terminate)" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_loop
        i = 0
        attempts = 0
        loop do
          attempts += 1
          if i == 1 && attempts < 5
            redo
          end
          puts "i=#{i} attempt=#{attempts}"
          i += 1
          break if i >= 3
        end
        puts "total=#{attempts}"
      end
      t_loop
    RUBY

    _(result).must_answer <<~'OUT'
      i=0 attempt=1
      i=1 attempt=5
      i=2 attempt=6
      total=6
    OUT
  end

  it "Integer#upto" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_upto
        attempts = 0
        0.upto(2) do |i|
          attempts += 1
          if i == 1 && attempts < 5
            redo
          end
          puts "i=#{i} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_upto
    RUBY

    _(result).must_answer <<~'OUT'
      i=0 attempt=1
      i=1 attempt=5
      i=2 attempt=6
      total=6
    OUT
  end

  it "Integer#downto" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_downto
        attempts = 0
        2.downto(0) do |i|
          attempts += 1
          if i == 1 && attempts < 5
            redo
          end
          puts "i=#{i} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_downto
    RUBY

    _(result).must_answer <<~'OUT'
      i=2 attempt=1
      i=1 attempt=5
      i=0 attempt=6
      total=6
    OUT
  end

  it "Integer#step" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_step
        attempts = 0
        0.step(4, 2) do |i|
          attempts += 1
          if i == 2 && attempts < 5
            redo
          end
          puts "i=#{i} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_step
    RUBY

    _(result).must_answer <<~'OUT'
      i=0 attempt=1
      i=2 attempt=5
      i=4 attempt=6
      total=6
    OUT
  end

  it "Array#each with index" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_each_with_index
        attempts = 0
        ["a", "b", "c"].each_with_index do |x, i|
          attempts += 1
          if i == 1 && attempts < 5
            redo
          end
          puts "x=#{x} i=#{i} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_each_with_index
    RUBY

    _(result).must_answer <<~'OUT'
      x=a i=0 attempt=1
      x=b i=1 attempt=5
      x=c i=2 attempt=6
      total=6
    OUT
  end

  it "Array#each cons" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_each_cons
        attempts = 0
        [1, 2, 3, 4].each_cons(2) do |pair|
          attempts += 1
          if pair[0] == 2 && attempts < 5
            redo
          end
          puts "pair=#{pair.inspect} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_each_cons
    RUBY

    _(result).must_answer <<~'OUT'
      pair=[1, 2] attempt=1
      pair=[2, 3] attempt=5
      pair=[3, 4] attempt=6
      total=6
    OUT
  end

  it "Array#each slice" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_each_slice
        attempts = 0
        [1, 2, 3, 4, 5].each_slice(2) do |chunk|
          attempts += 1
          if chunk[0] == 3 && attempts < 5
            redo
          end
          puts "chunk=#{chunk.inspect} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_each_slice
    RUBY

    _(result).must_answer <<~'OUT'
      chunk=[1, 2] attempt=1
      chunk=[3, 4] attempt=5
      chunk=[5] attempt=6
      total=6
    OUT
  end

  it "Array#each with object" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_each_with_object
        attempts = 0
        result = [1, 2, 3].each_with_object([]) do |x, acc|
          attempts += 1
          if x == 2 && attempts < 5
            redo
          end
          acc << x * 10
        end
        puts result.inspect
        puts "total=#{attempts}"
      end
      t_each_with_object
    RUBY

    _(result).must_answer "[10, 20, 30]\ntotal=6\n"
  end

  it "Array#zip iteration" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_zip
        attempts = 0
        [1, 2, 3].zip([10, 20, 30]) do |a, b|
          attempts += 1
          if a == 2 && attempts < 5
            redo
          end
          puts "a=#{a} b=#{b} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_zip
    RUBY

    _(result).must_answer <<~'OUT'
      a=1 b=10 attempt=1
      a=2 b=20 attempt=5
      a=3 b=30 attempt=6
      total=6
    OUT
  end

  it "Array#cycle (with count to terminate)" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_cycle
        attempts = 0
        [1, 2].cycle(2) do |x|
          attempts += 1
          if x == 1 && attempts < 3
            redo
          end
          puts "x=#{x} attempt=#{attempts}"
        end
        puts "total=#{attempts}"
      end
      t_cycle
    RUBY

    _(result).must_answer <<~'OUT'
      x=1 attempt=3
      x=2 attempt=4
      x=1 attempt=5
      x=2 attempt=6
      total=6
    OUT
  end

  it "Nested redo (mixed loop kinds) — exercises label-stack uniqueness" do
    result = zr(<<~'RUBY')
      # RedoNode coverage — `redo` re-runs the current iteration of the
      # enclosing loop without re-evaluating the guard or advancing the
      # iterator. Spinel emits a labeled goto back to the iteration top.
      # Each loop form needs the wrapping helper trio (push_redo_label /
      # emit_redo_label / pop_redo_label) so this file exercises every
      # form that has it.
      #
      # Per-section `def t_<form>; ...; end; t_<form>` isolates the
      # `attempts` / `i` / `x` locals. Was 17 separate tests covering
      # each loop form individually plus a nested case.


      def t_nested
        inner_attempts = 0
        outer_done = 0
        i = 0
        while i < 2
          outer_done += 1
          3.times do |j|
            inner_attempts += 1
            if i == 0 && j == 1 && inner_attempts < 4
              redo
            end
            puts "i=#{i} j=#{j} attempt=#{inner_attempts}"
          end
          i += 1
        end
        puts "outer_done=#{outer_done}"
        puts "inner_attempts=#{inner_attempts}"
      end
      t_nested
    RUBY

    _(result).must_answer <<~'OUT'
      i=0 j=0 attempt=1
      i=0 j=1 attempt=4
      i=0 j=2 attempt=5
      i=1 j=0 attempt=6
      i=1 j=1 attempt=7
      i=1 j=2 attempt=8
      outer_done=2
      inner_attempts=8
    OUT
  end

  it "redo keeps the block parameters" do
    result = zr(<<~'RUBY')
      # `redo` re-runs the block BODY; it does not re-yield, so the block's
      # parameters and block-locals keep the values the body gave them.
      n = 0
      [1].each do |x; y|
        y ||= 0
        x += 10
        y += 100
        n += 1
        redo if n < 2
        p [x, y]
      end

      # The same rule when the redo crosses an `ensure`.
      m = 0
      [1].each do |v|
        v += 1
        begin
          m += 1
          redo if m < 3
        ensure
          nil
        end
        p v
      end

      # A `while` loop's `redo` re-runs the body without re-testing.
      i = 0
      k = 0
      while i < 1
        k += 1
        i += 1 if k >= 2
        redo if k < 2
      end
      p [i, k]
    RUBY

    _(result).must_answer <<~'OUT'
      [21, 200]
      4
      [1, 2]
    OUT
  end

  it "redo reruns the current iteration without retesting" do
    result = zr(<<~'RUBY')
      i = 0
      attempts = 0
      while i < 3
        attempts += 1
        if attempts < 5 && i == 1
          redo
        end
        i += 1
      end
      puts i
      puts attempts
    RUBY

    _(result).must_answer "3\n6\n"
  end

  it "return inside while" do
    result = zr(<<~'RUBY')
      def first_over(limit)
        i = 0
        while true
          i = i + 1
          if i * i > limit
            return i
          end
        end
      end
      puts first_over(50)
      puts first_over(0)
      def early(n)
        return "neg" if n < 0
        "pos"
      end
      puts early(-1)
      puts early(1)
      def bare
        return
      end
      p bare
    RUBY

    _(result).must_answer <<~'OUT'
      8
      1
      neg
      pos
      nil
    OUT
  end

  it "return nil call scalar return" do
    result = zr(<<~'RUBY')
      # A method whose return type is a concrete scalar (here mrb_int, pinned by the
      # `42` branch) but one branch's value is a call that resolves to nil through a
      # nil/unresolved receiver. That call is emitted as a poly nil-box
      # (`sp_box_nil()`), and returning it raw from an mrb_int function is
      # uncompilable C ("returning sp_RbVal from a function with incompatible result
      # type mrb_int"). The fix coerces the box at the return slot
      # (`sp_poly_to_i(sp_box_nil())`). The nil branch is never executed here -- the
      # regression is purely that the method must compile.
      module AR
        def self.adapter
          nil
        end
      end

      class Base
        def self.count(flag)
          if flag
            42
          else
            AR.adapter.count("x")   # nil receiver -> poly nil-box into the mrb_int slot
          end
        end
      end

      puts Base.count(true).to_s
    RUBY

    _(result).must_answer "42\n"
  end

  it "return table across methods" do
    result = zr(<<~'RUBY')
      # Factoring a table of int arrays out into its own method is the ordinary way
      # to write this, and the caller's `rows = build(n)` has to reach the same
      # storage the callee built. Without a slot for the method's value that write
      # was an unmodeled source, the caller's table stayed a boxed poly array, and
      # every helper reading an element out of it bound a boxed parameter.
      class F
        def self.mul(a, b)
          (a * b) % 97
        end
      end

      class T
        def self.build(count)
          Array.new(count) { |c| [c, c + 1, c + 2] }
        end

        def self.consume(rows, s)
          acc = 0
          i = 0
          while i < rows.length
            row = rows[i]
            acc += F.mul(row[0], s)
            i += 1
          end
          acc
        end
      end

      rows = T.build(4)
      p T.consume(rows, 3)
    RUBY

    _(result).must_answer "18\n"
  end

  it "return unify int vs pointer" do
    result = zr(<<~'RUBY')
      # #581 (Sam Ruby). When a function's explicit `return X` and
      # implicit final-expression return disagree on the value-vs-
      # pointer axis (here int param early return + hash literal
      # implicit), the analyzer's lenient unify_return_type previously
      # demoted the int as a default sentinel and picked the hash
      # type, declaring the function as `sp_StrStrHash *`. The early
      # `return value` then emitted `return mrb_int` from a
      # pointer-typed function -- fatal -Wint-conversion under -Werror.
      #
      # Fix: post-fixpoint pass widens the function's stored return
      # type to "poly" when the body's actual return paths contradict
      # the analyzer's narrow choice on the value-vs-pointer axis.
      # The existing codegen-side `@current_method_return == "poly"`
      # boxing arm in compile_return_stmt then routes both branches
      # through box_expr_to_poly correctly.
      #
      # Scope-set-up at the widen-check site (push_scope + declare
      # params + refine_method_body_locals) is load-bearing: without
      # it, ivar / local reads in the body fall back to int default
      # and the check reports spurious mismatches for methods whose
      # body is actually homogeneous (e.g. spinel's own helpers like
      # `parse_id_list` returning `@parse_id_pool[k]`).

      def f(value)
        return value if value < 0
        {"k" => "v"}
      end

      # The early-return path returns the int parameter.
      r1 = f(-1)
      puts r1.is_a?(Integer)
      puts r1

      # The implicit-return path returns the hash literal.
      r2 = f(5)
      puts r2.is_a?(Hash)
      puts r2["k"]
    RUBY

    _(result).must_answer <<~'OUT'
      true
      -1
      true
      v
    OUT
  end

  it "return unify isa early return" do
    result = zr(<<~'RUBY')
      # #585 (Sam Ruby). Sibling shape of #581. A method that early-
      # returns the param when `value.is_a?(Hash)` is false, then falls
      # through to a pointer-shaped value, declared its return type as
      # the pointer-shaped path and the early `return value` (int) tried
      # to return mrb_int from a pointer-typed function -- fatal under
      # -Werror.
      #
      # The function-signature side surfaces the same widen-to-poly fix
      # as #581 (post-fixpoint widen pass). The fix here also closes a
      # latent bug in the @unified_imeth_returns marker (spinel's
      # Array#index returns -1 for not-found, not nil, so the
      # `.index == nil` check at the producer site never added entries
      # and the marker stayed empty). Switching to `.include?` lets the
      # imeth-family marker get populated, which the widen pass then
      # honors -- so the #563 self-operator dispatch family stays intact
      # even after the value-vs-pointer widen lands.

      class Host
        def stringify_keys(value)
          return value unless value.is_a?(Hash)
          "stringified"
        end
      end

      # The early-return path returns the int parameter as-is.
      puts Host.new.stringify_keys(42)

      # The fall-through path returns the pointer-shaped value.
      puts Host.new.stringify_keys({"a" => 1})
    RUBY

    _(result).must_answer "42\nstringified\n"
  end

  it "return void and nullable object" do
    result = zr(<<~'RUBY')
      # Regression: a method returning nil in every path is typed `void`, so an
      # explicit `return nil` must emit a bare `return;` rather than `return <value>;`
      # from a void C function. And a method returning a nullable object with an early
      # bare `return` (Ruby nil) must emit the type's nil (NULL), not a bare `return;`
      # in a non-void C function. Both previously produced -Wreturn-mismatch errors.

      class Pool
        def initialize
          @n = 1
        end
        def n
          @n
        end
      end

      class Db
        def self.open
          @pool = Pool.new
        end
        def self.close
          return if @pool.nil?
          @pool = nil
        end
        def self.pool
          @pool
        end
      end

      class Logger
        def self.log(msg)
          return nil if msg.empty?
          puts msg
          nil
        end
      end

      class Counter
        @count = 0
        def self.bump
          @count = @count + 1
          nil
        end
        def self.count
          @count
        end
        # Void method (returns nil in every path): the early `return bump` discards
        # bump's (void) value, but the side effect must still run -- codegen emits
        # `(void)(bump()); return;`, not a bare `return;` that would drop the call.
        def self.tick(run)
          return bump if run
          nil
        end
      end

      Db.open
      p Db.pool.n
      Db.close
      p Db.pool.nil?
      Logger.log("")
      Logger.log("hi")

      Counter.tick(false)
      p Counter.count
      Counter.tick(true)
      p Counter.count
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      hi
      0
      1
    OUT
  end

  it "unless with else" do
    result = zr(<<~'RUBY')
      n = 5
      unless n < 0
        puts :non_negative
      else
        puts :negative
      end
    RUBY

    _(result).must_answer "non_negative\n"
  end

  it "until and an unless guard never send a programs bang" do
    result = zr(<<~'RUBY')
      # `until` and an `unless` guard test truthiness as a branch does, so a
      # class that defines `!` cannot turn them. `x&.!` is a safe call of `!`.
      class Always
        def ! = true
      end

      n = 0
      until Always.new
        n += 1
        break
      end
      p n

      k = 0
      k += 1 until k >= 3 || Always.new
      p k

      r = case 1
          in Integer unless Always.new then :guarded
          else :else
          end
      p r

      p nil&.!
      p Always.new&.!
      p(!Always.new)

    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      :else
      nil
      true
      true
    OUT
  end

  it "value object nil loop reset" do
    result = zr(<<~'RUBY')
      # A value-type object local assigned inside a block loop is reset with a
      # zeroed struct, not NULL -- a method returning the object on some paths
      # and (implicit) nil on others is still a value type (#3267).
      class Flag
        def initialize(bool) = @bool = bool
        def bool? = @bool
      end

      def find_flag(name)
        return Flag.new(true) if name == "-q"
        return Flag.new(false) if name == "-n"
      end

      def check(argument)
        (1...argument.length).each do |idx|
          flag = find_flag("-#{argument[idx]}")
          return false unless flag&.bool?
        end
        true
      end

      puts check("-qn")
      puts check("-qq")
    RUBY

    _(result).must_answer "false\ntrue\n"
  end

  it "valued break" do
    result = zr(<<~'RUBY')
      # A `break <v>` inside a block makes the iterator call return <v> (CRuby's
      # TAG_BREAK). It works across value-producing iterators (map/select/reduce/...)
      # and self-returning ones (each/each_with_index). Bare `break` returns nil; a
      # `break a, b` returns an array. Each receiver is a typed local (monomorphic, so
      # it is not widened to poly) to exercise the runtime path rather than folding.
      arr = [1, 2, 3]

      # collect family: result is the break value, not a partial array
      p arr.map { |x| break 99 if x == 2; x * 10 }
      p arr.select { |x| break :stop if x == 2; x.odd? }
      p arr.reject { |x| break 7 if x == 2; false }
      p arr.filter_map { |x| break "f" if x == 2; x }
      p arr.flat_map { |x| break [0] if x == 2; [x, x] }

      # reduce / find / count / *_by
      p arr.reduce(0) { |s, x| break 100 if x == 2; s + x }
      p arr.find { |x| break(-1) if x == 2; false }
      p arr.count { |x| break 5 if x == 2; true }
      p arr.sort_by { |x| break :s if x == 2; x }
      p arr.min_by { |x| break 0 if x == 2; x }

      # range and integer iterators
      rng = (1..5)
      n = 3
      m = 1
      p rng.map { |x| break 42 if x == 3; x }
      p n.times { |x| break :done if x == 1 }
      p m.upto(4) { |x| break x * 100 if x == 3 }

      # self-returning iterators: break replaces the receiver result
      p arr.each { |x| break 9 if x == 2 }
      labelled = [10, 20, 30]
      p labelled.each_with_index { |x, i| break i if x == 20 }
      big = (1..9)
      p big.each { |x| break x * x if x == 4 }
      p arr.each_with_object([]) { |x, o| break :bail if x == 2; o << x }

      # no break: the iterators still return their normal value
      p arr.map { |x| x + 1 }
      p arr.reduce(0) { |s, x| s + x }

      # bare break -> nil; break with several values -> array
      p arr.each { |x| break if x == 2 }
      p arr.map { |x| break 1, 2, 3 if x == 2; x }

      # break binds to the nearest enclosing block: an inner each's break does not
      # escape the outer each
      total = 0
      inner = [10, 20]
      arr.each do |x|
        inner.each { |y| total += y; break }
        total += x
      end
      p total

      # a break inside a nested while binds to the while, not the iterator
      p arr.map { |x| k = 0; while true; k += 1; break if k == 2; end; x + k }

      # multi-param destructuring with break
      pairs = [[1, 2], [3, 4]]
      p pairs.map { |a, b| break "stop" if b == 4; a + b }
    RUBY

    _(result).must_answer <<~'OUT'
      99
      :stop
      7
      "f"
      [0]
      100
      -1
      5
      :s
      0
      42
      :done
      300
      9
      1
      16
      :bail
      [2, 3, 4]
      6
      nil
      [1, 2, 3]
      36
      [3, 4, 5]
      "stop"
    OUT
  end

  it "valued break proc" do
    result = zr(<<~'RUBY')
      # break inside a lambda returns from the LAMBDA (CRuby); break inside an
      # explicitly created non-lambda proc raises LocalJumpError "break from
      # proc-closure" when called -- even while the creating iterator is live.
      l = -> { break 9 }
      p l.call
      p lambda { break }.call

      # lambda break runs intervening ensures on its way out
      l2 = -> { begin; break 3; ensure; puts "le"; end }
      p l2.call

      # a lambda created and broken inside an iterator stays lambda-local
      p([1].map { l3 = -> { break 42 }; l3.call })

      # an escaped proc raises when called after its context is gone
      def orphan; proc { break 1 }; end
      begin
        orphan.call
      rescue LocalJumpError => e
        puts "#{e.class}: #{e.message}"
      end

      # ...and CRuby raises for an explicit proc even while the iterator is live
      [1, 2].each do |x|
        pr = proc { break :pb }
        begin
          pr.call
        rescue LocalJumpError => e
          puts "live: #{e.message}"
        end
      end
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      9
      nil
      le
      3
      [42]
      LocalJumpError: break from proc-closure
      live: break from proc-closure
      live: break from proc-closure
      done
    OUT
  end

  it "valued break recv" do
    result = zr(<<~'RUBY')
      # Self-returning iterators with an IMPURE receiver: the receiver expression is
      # evaluated exactly once (spilled to a temp used as both the loop source and
      # the no-break result).
      $mk = 0
      def make_arr
        $mk += 1
        [1, 2, 3]
      end

      p(make_arr.each { |x| break 9 if x == 2 })
      p $mk

      # no break taken: the receiver value is the result, still evaluated once
      $mk = 0
      p(make_arr.each { |x| break 9 if x == 99 })
      p $mk

      # each_with_index / reverse_each variants
      $mk = 0
      p(make_arr.each_with_index { |x, i| break i if x == 2 })
      p $mk
      $mk = 0
      p(make_arr.reverse_each { |x| break x if x == 2 })
      p $mk

      # an ivar-mutating receiver expression
      class Counter
        attr_reader :n
        def initialize; @n = 0; end
        def bump_and_get
          @n += 1
          [@n, @n * 2]
        end
      end
      c = Counter.new
      p(c.bump_and_get.each { |v| break v if v > 1 })
      p c.n

      # statement position with an impure receiver
      $mk = 0
      make_arr.each { |x| break if x == 2 }
      p $mk
    RUBY

    _(result).must_answer <<~'OUT'
      9
      1
      [1, 2, 3]
      1
      1
      1
      2
      1
      2
      1
      1
    OUT
  end

  it "valued break tail" do
    result = zr(<<~'RUBY')
      # A break-carrying iterator in a method's TAIL (return) position: its value --
      # the break value, or the normal result when no break is taken -- IS the
      # method's return value. (A plain iteration call at tail is a side-effect
      # statement; a break-carrying one must instead flow through the value path.)

      # self-returning iterator, break taken -> the break value
      def each_brk;   [1, 2, 3].each { |x| break x * 100 if x == 2 }; end
      p each_brk

      # self-returning iterator, break NOT taken -> the receiver
      def each_recv;  [1, 2, 3].each { |x| break x if x == 99 }; end
      p each_recv

      # each_with_index / each_with_object at tail
      def ewi_brk;  %w[a b c].each_with_index { |s, i| break i if s == "b" }; end
      p ewi_brk
      def ewo_brk;  [1, 2, 3].each_with_object([]) { |x, o| break :bail if x == 2; o << x }; end
      p ewo_brk

      # value-producing iterators at tail, break taken
      def map_brk;    [1, 2, 3].map    { |x| break :m if x == 2; x }; end
      def select_brk; [1, 2, 3].select { |x| break 0  if x == 2; x.odd? }; end
      def reject_brk; [1, 2, 3].reject { |x| break 7  if x == 2; false }; end
      def reduce_brk; [1, 2, 3].reduce(0) { |a, x| break 77 if x == 2; a + x }; end
      def find_brk;   [1, 2, 3].find   { |x| break(-1) if x == 2; false }; end
      p map_brk; p select_brk; p reject_brk; p reduce_brk; p find_brk

      # value-producing iterators at tail, break NOT taken -> the normal result
      def map_normal; [1, 2, 3].map { |x| x * 2 }; end
      p map_normal

      # range iterator at tail
      def rng_brk;    (1..5).map { |x| break x if x == 3; x }; end
      p rng_brk

      # a guard return before the tail iterator (the iterator is still the tail value)
      def guarded(n)
        return :zero if n == 0
        [1, 2, 3].each { |x| break x * n if x == 2 }
      end
      p guarded(0)
      p guarded(5)

      # tail iterator through a user method that yields: the CALL's value is the
      # break value even though the yield sits inside the method's own iterator
      def relay
        [10, 20, 30].each { |x| yield x }
      end
      def via_relay
        relay { |x| break x + 1 if x == 20 }
      end
      p via_relay

      # an if/else whose both tail branches are break-carrying iterators
      def branchy(flag)
        if flag
          [1, 2].map { |x| break :t if x == 2; x }
        else
          [3, 4].each { |x| break x if x == 4 }
        end
      end
      p branchy(true)
      p branchy(false)
    RUBY

    _(result).must_answer <<~'OUT'
      200
      [1, 2, 3]
      1
      :bail
      :m
      0
      7
      77
      -1
      [2, 4, 6]
      3
      :zero
      10
      21
      :t
      4
    OUT
  end

  it "valued break yield" do
    result = zr(<<~'RUBY')
      # A `break <v>` inside a block propagates through user methods that yield
      # (CRuby's TAG_BREAK): the CALL that received the block returns <v>, however
      # deep the yield sits -- inside the method's own loops or nested iterators.
      def m1; yield; end
      p(m1 { break 5 })
      p(m1 { 3 })

      # a no-value method body: bare result is nil
      def m2; yield; nil; end
      p(m2 { break :v })

      # yield inside the method's own while loop
      def m3; i = 0; while i < 3; i += 1; yield i; end; :done; end
      p(m3 { |i| break i * 10 if i == 2 })
      p(m3 { |i| i })

      # yield inside a nested iterator: the break still exits the OUTER call
      def m4; [1, 2, 3].each { |x| yield x }; end
      p(m4 { |x| break x + 100 if x == 2 })

      # nested WRAPPED iterator: the inner map has its own break scope, yet the
      # spliced outer block's break targets m5's call (serial addressing)
      def m5; [1, 2].map { |x| break :inner if x > 99; yield x }; end
      p(m5 { |x| break :outer if x == 2; x })
      p(m5 { |x| x * 2 })

      # receiver-bearing user method: the no-break result is the METHOD's value,
      # not the receiver
      class Bag
        def initialize(xs); @xs = xs; end
        def each
          i = 0
          while i < @xs.length
            yield @xs[i]
            i += 1
          end
          :bag_done
        end
      end
      b = Bag.new([1, 2, 3])
      p(b.each { |x| break x * 7 if x == 2 })
      p(b.each { |x| x })

      # statement position
      m1 { break 7 }
      puts "after"

      # statement-position nesting: the inner each's break must not escape to the
      # outer map
      p [1, 2, 3].map { |x| break 1 if x == 9; [5, 6].each { break }; x }
    RUBY

    _(result).must_answer <<~'OUT'
      5
      3
      :v
      20
      :done
      102
      :outer
      [2, 4]
      14
      :bag_done
      after
      [1, 2, 3]
    OUT
  end

  it "while break value" do
    result = zr(<<~'RUBY')
      # A valued break from a while used in value position yields that value.
      def s(x); x; end
      n = s(0)
      r = while true
        n += 1
        break "stopped at #{n}" if n == 3
      end
      p r
      m = s(0)
      r2 = while true
        m += 1
        break m * 10 if m == 5
      end
      p r2
    RUBY

    _(result).must_answer <<~'OUT'
      "stopped at 3"
      50
    OUT
  end

  it "while tail return type" do
    result = zr(<<~'RUBY')
      def find(x)
        while true
          return "hit" if x > 0
          return "" if x < -10
          x += 1
        end
      end
      v = find(5)
      puts v.upcase
      def count_up(x)
        until false
          return x * 2 if x > 3
          x += 1
        end
      end
      puts count_up(1) + 10
      def with_break(x)
        while true
          break if x > 0
        end
      end
      puts with_break(1).inspect
      def finite(x)
        while x < 3
          return "s" if x == 2
          x += 1
        end
      end
      puts finite(0).inspect
      puts finite(1).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      HIT
      18
      nil
      "s"
      "s"
    OUT
  end

  it "while until" do
    result = zr(<<~'RUBY')
      i = 0
      sum = 0
      while i < 10
        i += 1
        next if i == 5
        break if i == 8
        sum += i
      end
      puts sum
      puts i

      n = 5
      until n == 0
        n -= 1
      end
      puts n

      count = 0
      count += 1 while count < 3
      puts count
    RUBY

    _(result).must_answer <<~'OUT'
      23
      8
      0
      3
    OUT
  end

  it "while until as value" do
    result = zr(<<~'RUBY')
      # A while/until loop used in value position evaluates to nil (CRuby semantics).
      # (A valued `break` would change this, but that is a separate gap and is
      # rejected at compile time rather than silently yielding nil.)

      # while as an assignment RHS
      i = 0
      r = while i < 3; i += 1; end
      p r                 # nil
      p i                 # 3 (the loop ran)

      # until in parentheses as an RHS
      done = false
      n = 0
      x = (until done; n += 1; done = n >= 2; end)
      p x                 # nil
      p n                 # 2

      # loop value embedded in an array literal
      j = 0
      a = [1, (while j < 2; j += 1; end), 2]
      p a                 # [1, nil, 2]

      # loop value passed as a method argument
      def f(v); v.inspect; end
      k = 0
      p f(while k < 1; k += 1; end)   # "nil"

      # post-test begin..end while, used as a value
      m = 0
      post = begin; m += 1; end while m < 3
      p [post, m]         # [nil, 3]

      # a plain (valueless) break still yields nil
      b = 0
      br = while b < 5; b += 1; break if b == 2; end
      p [br, b]           # [nil, 2]

      # while as the last expression of a method returns nil
      def loop_ret
        c = 0
        while c < 2; c += 1; end
      end
      p loop_ret          # nil
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      3
      nil
      2
      [1, nil, 2]
      "nil"
      [3, 3]
      [nil, 2]
      nil
    OUT
  end
end
