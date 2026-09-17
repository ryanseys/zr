# frozen_string_literal: true

require "spec_helper"

describe "PP programs" do
  it "deferred require loads when it runs" do
    result = ze0(<<~'RUBY')
      # A `require` written inside a METHOD body defines its feature's constants
      # when the method RUNS, exactly as CRuby does -- not before the program's
      # first statement.
      #
      # The file is compiled in as a UNIT: a load-path file nothing has required
      # yet. Its classes register for dispatch at startup because the static MRO
      # needs a shape, so `PrettyPrint` used to answer `defined?` before anything
      # loaded it.
      #
      # The fix reuses the machinery a runtime-CONDITIONAL class already had. Such
      # a class registers its shape and starts CONCEALED, revealed at the head of
      # its own body site; a unit's body site lives in the unit's function, so it
      # runs when the unit does. `Compiler::class_waits_for_its_unit` is the
      # predicate, and it feeds the same three places: the conceal
      # list, the class-body site's reveal, and `constant_is_positional`, which is
      # what stops `defined?` folding an answer at compile time.
      #
      # A VALUE constant a unit assigns needs the other half:
      # `Hir::unrun_unit_consts` records every unit's constant names -- it used to
      # record only an autoload target's -- and a bare-name `defined?` of one asks
      # the run time instead of concluding "written only later". A unit is not in
      # any statement stream, so "later" and "in a file nothing has run" looked
      # alike and meant opposite things.
      #
      # Reading a concealed constant also RUNS a pending `autoload` now. That is
      # where ruby loads, and a concealed class is exactly the shape an autoload
      # targets: registered for dispatch, no constant yet.
      #
      # The size half landed separately: `narrow_runtime_eval` drops a plain
      # `require` whose LITERAL feature names a unit this compile emitted, because
      # `dynamic_require` asks `features::load_feature` before the on-disk tier
      # that needs a compiler. `require_relative` and `load` stay conservative --
      # the first resolves against the calling file's directory, which is a
      # run-time fact, and the second asks DISK first.

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
    _(ze0(<<~'RUBY')).must_answer "0\n{aaaaaaaaaa: \"bbbbbbbbbbbbbbbbbbbb\",\n cccccccccccc: \"dddddddddddddddddddd\",\n eeeeeeeeeeee: [1, 2, 3, 4, 5, 6, 7, 8, 9]}\n1\n#<struct S\n aaaaaaaaaaaaaaa=\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\n bbbbbbbbbbbbbbbbbbbb=\"yyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\",\n ccccccccccccccccc=[1, 1, 1, 1, 1, 1, 1, 1, 1, 1]>\nP(1, 2)\n3\nnil\n[1]\n[1]\nKernel\n-1\n\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"\n"
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
  end

  it "pp guards its console require" do
    _(ze0(<<~'RUBY')).must_answer "{alpha: \"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\n beta:\n  [1,\n   2,\n   3,\n   4,\n   5,\n   6,\n   7,\n   8,\n   9,\n   10,\n   11,\n   12,\n   13,\n   14,\n   15,\n   16,\n   17,\n   18,\n   19,\n   20,\n   21,\n   22,\n   23,\n   24,\n   25,\n   26,\n   27,\n   28,\n   29,\n   30],\n gamma:\n  {delta: \"yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\", epsilon: [:a, :b, :c]}}\n"
      # pp asks io/console for the width under a `rescue LoadError`, so a
      # wide structure prints whether or not a console library is present.
      require "pp"
      pp({alpha: "x" * 60, beta: (1..30).to_a, gamma: {delta: "y" * 40, epsilon: [:a, :b, :c]}})
    RUBY
  end

  it "pp store float inf literal" do
    result = ze0(<<~'RUBY')
      # Kernel#pp prints inspect like p (and returns its argument); Hash#store is
      # the method form of []=; an out-of-range float literal is Float::INFINITY
      # (it used to emit an invalid C token).
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
