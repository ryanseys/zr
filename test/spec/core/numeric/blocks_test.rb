# frozen_string_literal: true

require "spec_helper"

describe "Numeric: blocks and yields" do
  it "float step block" do
    result = ze0(<<~'RUBY')
      # Issue #870: Float#step yields floats. Pre-fix the LV slot was
      # typed as mrb_int so `lv_x += 0.5` truncated to `+= 0` and looped
      # forever.
      result = []
      1.0.step(3.0, 0.5) { |x| result << x }
      puts result.inspect

      # int step still works
      out = []
      1.step(7, 2) { |i| out << i }
      puts out.inspect

      # float step argument widens int recv to float
      result2 = []
      1.step(3.0, 0.5) { |x| result2 << x }
      puts result2.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1.0, 1.5, 2.0, 2.5, 3.0]
      [1, 3, 5, 7]
      [1.0, 1.5, 2.0, 2.5, 3.0]
    OUT
  end

  it "floats and lambdas" do
    result = ze0(<<~'RUBY')
      puts 1.5 + 2.5
      puts 3.0 - 1
      puts 2.0 * 3
      puts 7.0 / 2
      puts 7.5 % 2
      puts 2.0 ** 3
      puts 1.0 == 1
      puts 1.5 < 2.5
      puts(1.5 <=> 2.5)
      puts(-1.5)
      puts 1.0
      puts 100.0
      puts 3.14

      class Adder
        def add(a, b)
          a + b
        end
      end

      puts Adder.new.add(1, 2.5)
      puts Adder.new.add(2.5, 1)

      add = ->(x, y) { x + y }
      puts add.call(3, 4)
      puts add.(3, 4)
      puts add[3, 4]

      square = lambda { |x| x * x }
      puts square.call(5)

      incr = -> (n = 1) { n + 1 }
      puts incr.call
      puts incr.call(10)

      class Runner
        def return_test
          f = -> {
            return 10
            20
          }
          puts f.call
          "after"
        end
      end

      puts Runner.new.return_test

      f = ->(x, y) { x + y }
      begin
        f.call(1)
      rescue ArgumentError => e
        puts "caught: #{e.message}"
      end
      puts f.call(1, 2)
    RUBY

    _(result).must_answer <<~'OUT'
      4.0
      2.0
      6.0
      3.5
      1.5
      8.0
      true
      true
      -1
      -1.5
      1.0
      100.0
      3.14
      3.5
      3.5
      7
      7
      7
      25
      2
      11
      10
      after
      caught: wrong number of arguments (given 1, expected 2)
      3
    OUT
  end

  it "int nil boxing min max block" do
    result = ze0(<<~'RUBY')
      # Empty collections return nil from min/max even when a comparator block is
      # supplied. Keep nonempty and argument-taking forms covered at the same time.
      class EmptyInts
        include Enumerable
        def each; end
      end

      plain_array = []
      array = [1].first(0)
      enum = EmptyInts.new

      p plain_array.min { |a, b| a <=> b }
      p plain_array.max { |a, b| a <=> b }
      p array.min { |a, b| a <=> b }
      p array.max { |a, b| a <=> b }
      p enum.min { |a, b| a <=> b }
      p enum.max { |a, b| a <=> b }

      values = [3, 1, 2]
      p values.min { |a, b| a <=> b }
      p values.max { |a, b| a <=> b }
      p values.min(2) { |a, b| a <=> b }
      p values.max(2) { |a, b| a <=> b }
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      nil
      nil
      1
      3
      [1, 2]
      [3, 2]
    OUT
  end

  it "integer step no limit" do
    result = ze0(<<~'RUBY')
      # Integer#step with no limit iterates until the block breaks.
      r = 1.step { |i| break i if i > 3 }
      p r
      n = 0
      5.step { |i| n += i; break if i >= 8 }
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      4
      26
    OUT
  end

  it "lambda float captures with float param" do
    result = ze0(<<~'RUBY')
      # A multi-statement lambda/proc may capture two or more non-Integer (Float,
      # String, ...) locals even when it also takes a Float parameter. Captures ride
      # the capture struct as real fields; a first-class proc's .call passes Float
      # args through the boxed side-channel, so there is no truncation conflict.

      t = 0.5
      g = 0.25
      f = lambda do |i, alpha|
        x = (i + 0.5) * 2.0
        s = (6.0 + (30.0 * g)) * (t + i)
        [x, s, alpha]
      end
      3.times { |i| p f.call(i, 0.7) }

      a = 1.5
      b = 2.5
      c = 3.5
      multi = lambda do |x, y|
        p1 = x + a
        p2 = y * b
        p3 = c - x
        [p1, p2, p3]
      end
      p multi.call(0.5, 2.0)

      name = "hi"
      scale = 10.0
      interp = ->(v) { "#{name}:#{v * scale}" }
      p interp.call(1.5)
    RUBY

    _(result).must_answer <<~'OUT'
      [1.0, 6.75, 0.7]
      [3.0, 20.25, 0.7]
      [5.0, 33.75, 0.7]
      [2.0, 5.0, 3.0]
      "hi:15.0"
    OUT
  end

  it "proc curry collects arguments and each step is reusable" do
    result = ze0(<<~'RUBY')
      add = ->(a, b, c) { a + b + c }
      p add.curry[1][2][3]
      p add.curry[1, 2][3]
      step = add.curry[10]
      p step[1][2]
      p step[3][4]
      p add.curry.arity
      p add.curry.lambda?
      p proc { |a, b| a * b }.curry[3][4]
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
      13
      17
      -1
      true
      12
    OUT
  end

  it "proc float arg" do
    result = ze0(<<~'RUBY')
      # A Float argument to a proc / lambda `.call` (or a lowered `yield`) must read
      # back as itself inside the block, not 0.0.
      #
      # Proc/lambda arguments ride an mrb_int[16] slot in the sp_proc_call ABI. A
      # Float placed in that slot was written by an arithmetic double->mrb_int
      # conversion (0.7 -> 0) and the callee, binding a concretely-Float-typed param,
      # read the truncated int slot back as a double -> 0.0. An Integer arg rides the
      # slot losslessly and a `def` method passes floats as real C doubles, so only
      # proc/lambda Float args were silently corrupted.
      #
      # Fix: a Float arg is published boxed into the _sp_proc_poly_args side-channel
      # (like a poly arg) and the callee reads a Float param back with sp_poly_to_f --
      # mirroring how the proc *return* value already boxes a Float.

      # 1. Single Float arg round-trips.
      f = lambda { |a| a }
      p f.call(0.7)                       #=> 0.7

      # 2. Two Float args (add inside the block).
      g = lambda { |a, b| a + b }
      p g.call(0.5, 0.25)                 #=> 0.75

      # 3. A plain proc (not a lambda).
      h = proc { |a| a }
      p h.call(0.5)                       #=> 0.5

      # 4. Mixed Integer + Float args keep their kinds.
      m = ->(a, b) { [a, b] }
      p m.call(1, 2.5)                    #=> [1, 2.5]

      # 5. A Float arg that feeds a built-up structure (the dangerous silent case).
      acc = []
      add = ->(v) { acc << v }
      add.call(0.7)
      add.call(1.3)
      p acc                              #=> [0.7, 1.3]

      # 6. A lowered `yield` of a Float.
      def y
        yield 0.7
      end
      p(y { |x| x })                     #=> 0.7

      # 7. The block computes with the Float arg (not just echoes it).
      sq = ->(x) { x * x }
      p sq.call(0.5)                      #=> 0.25

      # 8. Integer args remain correct (regression guard).
      i = ->(a) { a }
      p i.call(42)                       #=> 42

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      0.7
      0.75
      0.5
      [1, 2.5]
      [0.7, 1.3]
      0.7
      0.25
      42
      done
    OUT
  end

  it "proc float return" do
    result = ze0(<<~'RUBY')
      # A proc/lambda whose body's value is a Float carries that float back
      # through `.call` (boxed in the poly return slot), instead of truncating
      # to the int the proc-fn ABI slot defaults to.

      # Direct literal receiver.
      puts proc { 3.5 }.call
      puts(-> { 4.25 }.call)

      # Proc-variable receiver.
      f = proc { 1.5 }
      puts f.call
      g = -> { 2.0 }
      puts g.call

      # Float-valued expression in the body.
      h = proc { 1.5 + 2.0 }
      puts h.call

      # Float result used in arithmetic at the call site.
      puts f.call + 0.5

      # A method whose implicit-tail value is a float-returning proc call.
      def tail_flt
        pr = proc { 6.25 }
        pr.call
      end
      puts tail_flt
    RUBY

    _(result).must_answer <<~'OUT'
      3.5
      4.25
      1.5
      2.0
      3.5
      2.0
      6.25
    OUT
  end
end
