# frozen_string_literal: true

require "spec_helper"

describe "PP programs" do
  it "compiled code releases a dead slot" do
    result = zr(<<~'RUBY', env: {"ZR_TEST_RT_LEAKCHECK" => "1"})
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # PrettyPrint's own graph, reached through `pp`. See pp_pretty_print.rb.gccheck.

      # At exit: cycle leak: 11 objects (Array x7, PP x1, PrettyPrint::Group x1, PrettyPrint::GroupQueue x1, Proc x1)
      # Compiled code must not release a stack slot that holds no live value.
      # Every local slot gets its first value on entry to the method, so no path
      # (a normal exit or a raise) reaches a slot that has no value in it.
      #
      # Without `ZR_TEST_RT_LEAKCHECK=1` the program prints the right answer either
      # way. The leak check finds a release of a bad slot.
      #
      # Oracle: the program prints its line and exits 0.
      require "pp"

      class Plain
      end

      PP.pp(Plain.new, +"")
      puts "done"
    RUBY

    _(result).must_answer "done\n"
  end

  it "deferred require loads when it runs" do
    result = zr(<<~'RUBY')
      # A `require` written inside a METHOD body defines its feature's constants
      # when the method RUNS, exactly as CRuby does -- not before the program's
      # first statement.
      #
      # So `defined?(PrettyPrint)` is nil before the first call to `lazy`. The
      # first `require` returns true, and the second returns false.

      def lazy
        require "prettyprint"
      end

      p defined?(PrettyPrint)
      p lazy
      p defined?(PrettyPrint)
      p lazy
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      "constant"
      false
    OUT
  end

  it "first pp loads pp rb" do
    result = zr(<<~'RUBY')
      # The first pp requires ruby's pp.rb, as CRuby's prelude does, so a wide
      # object wraps and a pretty_print method answers for its object.

      p $LOADED_FEATURES.grep(/\/pp\.rb/).size
      pp({aaaaaaaaaa: "bbbbbbbbbbbbbbbbbbbb", cccccccccccc: "dddddddddddddddddddd", eeeeeeeeeeee: [1,2,3,4,5,6,7,8,9]})
      p $LOADED_FEATURES.grep(/\/pp\.rb/).size
      S = Struct.new(:aaaaaaaaaaaaaaa, :bbbbbbbbbbbbbbbbbbbb, :ccccccccccccccccc)
      pp S.new("x"*30, "y"*30, [1]*10)
      class Point
        def initialize(x, y) = (@x, @y = x, y)
        def pretty_print(q) = q.text("P(#{@x}, #{@y})")
      end
      pp(Point.new(1, 2), 3)
      p pp
      x = pp [1]
      p x
      p Kernel.instance_method(:pp).owner
      p method(:pp).arity
      pp "x" * 100

    RUBY

    _(result).must_answer <<~'OUT'
      0
      {aaaaaaaaaa: "bbbbbbbbbbbbbbbbbbbb",
       cccccccccccc: "dddddddddddddddddddd",
       eeeeeeeeeeee: [1, 2, 3, 4, 5, 6, 7, 8, 9]}
      1
      #<struct S
       aaaaaaaaaaaaaaa="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
       bbbbbbbbbbbbbbbbbbbb="yyyyyyyyyyyyyyyyyyyyyyyyyyyyyy",
       ccccccccccccccccc=[1, 1, 1, 1, 1, 1, 1, 1, 1, 1]>
      P(1, 2)
      3
      nil
      [1]
      [1]
      Kernel
      -1
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    OUT
  end

  it "pp asks io/console for the width under a rescue, so a wide structure prints either way" do
    result = zr(<<~'RUBY')
      # pp asks io/console for the width under a `rescue LoadError`, so a
      # wide structure prints whether or not a console library is present.
      require "pp"
      pp({alpha: "x" * 60, beta: (1..30).to_a, gamma: {delta: "y" * 40, epsilon: [:a, :b, :c]}})
    RUBY

    _(result).must_answer <<~'OUT'
      {alpha: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
       beta:
        [1,
         2,
         3,
         4,
         5,
         6,
         7,
         8,
         9,
         10,
         11,
         12,
         13,
         14,
         15,
         16,
         17,
         18,
         19,
         20,
         21,
         22,
         23,
         24,
         25,
         26,
         27,
         28,
         29,
         30],
       gamma:
        {delta: "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy", epsilon: [:a, :b, :c]}}
    OUT
  end

  it "the pretty printer wraps, indents and groups every structure it is given" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # PrettyPrint's own graph. A Group holds its GroupQueue and the queue holds the group back.
      # At exit: cycle leak: 219 objects (Array x155, PP x16, PrettyPrint::Group x16, PrettyPrint::GroupQueue x16, Proc x16)
      # `pp` -- the gap this closes was three separate defects, each of which the
      # pretty printer walks straight into:
      #
      #   * `$>` read nil, where it is not a copy of `$stdout` but the SAME slot, and
      #     `PP.pp` defaults its output to it;
      #   * `yield(*v, **kwsplat)` passed a stray `{}` when the keywords turned out
      #     empty, so `seplist`'s `|k, v|` bound the whole pair to `k`;
      #   * a `def` in each branch of a `RUBY_VERSION` guard left two definitions of
      #     one name in the body and the later simply won, so the pre-3.4 hash
      #     renderer was the one that ran.
      require "pp"

      pp({a: 1})
      pp({a: 1, b: 2})
      pp({"k" => "v"})
      pp [1, 2, 3]
      pp "str"
      pp 42
      pp nil
      pp({a: {b: {c: 1}}})
      pp [{x: 1}, {y: 2}]

      # The same rendering, captured rather than printed.
      p PP.pp({a: 1}, +"")
      p PP.pp([1, [2, [3]]], +"")
      p({a: 1}.pretty_inspect)
      p PP.singleline_pp({a: 1, b: 2}, +"")

      # A symbol key needing quotes takes the `=>` form even in the 3.4 renderer.
      pp({:"a b" => 1})
      pp({1 => :one})

      # An object with no `pretty_print` of its own falls back to its inspect.
      class Plain
        def initialize = @x = 1
      end
      p PP.pp(Plain.new, +"").sub(/0x[0-9a-f]+/, "ADDR")

      # Wide enough to break across lines, which is the whole point of the group
      # machinery underneath.
      p PP.pp((1..40).to_a, +"", 40)

      # `$>` is one slot with `$stdout`, which is where `PP.pp` sends its output by
      # default.
      p $>.equal?($stdout)
      p defined?($>)
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1}
      {a: 1, b: 2}
      {"k" => "v"}
      [1, 2, 3]
      "str"
      42
      nil
      {a: {b: {c: 1}}}
      [{x: 1}, {y: 2}]
      "{a: 1}\n"
      "[1, [2, [3]]]\n"
      "{a: 1}\n"
      "{a: 1, b: 2}"
      {"a b": 1}
      {1 => :one}
      "#<Plain:ADDR @x=1>\n"
      "[1,\n 2,\n 3,\n 4,\n 5,\n 6,\n 7,\n 8,\n 9,\n 10,\n 11,\n 12,\n 13,\n 14,\n 15,\n 16,\n 17,\n 18,\n 19,\n 20,\n 21,\n 22,\n 23,\n 24,\n 25,\n 26,\n 27,\n 28,\n 29,\n 30,\n 31,\n 32,\n 33,\n 34,\n 35,\n 36,\n 37,\n 38,\n 39,\n 40]\n"
      true
      "global-variable"
    OUT
  end

  it "pp prints inspect and answers its argument, store is the method form of []=, and a huge literal is Infinity" do
    result = zr(<<~'RUBY')
      # Kernel#pp prints inspect like p (and returns its argument); Hash#store is
      # the method form of []=; an out-of-range float literal is Float::INFINITY.
      pp [1, 2, 3]
      x = pp(42)
      puts x
      h = {}
      h.store(:x, 5)
      p h[:x]
      sh = {}
      sh.store("k", "v")
      p sh["k"]
      p 1e400
      p(-1e400)
      p 1e308
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      42
      42
      5
      "v"
      Infinity
      -Infinity
      1.0e+308
    OUT
  end
end
