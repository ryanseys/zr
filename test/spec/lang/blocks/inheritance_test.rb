# frozen_string_literal: true

require "spec_helper"

describe "Blocks: inheritance and ancestors" do
  it "bare super in a block forwards the methods block" do
    result = ze0(<<~'RUBY')
      # A bare `super` written inside a BLOCK forwards the enclosing method's block
      # to the parent, exactly as one written directly in the method body does.
      # zeo forwards the method's PARAMETERS through this shape correctly -- see
      # `tests/a_bare_super_inside_a_block_forwards_the_methods_params.rb` -- but
      # not its BLOCK, so the parent raises `LocalJumpError: no block given`.
      #
      # The two halves are synthesized at different places. The forwarded argument
      # list is built by `codegen::call::super_calls` at the emission site, which is
      # inside the block and still knows the enclosing method's `Params`. The
      # forwarded BLOCK is the enclosing method's `__blk` parameter, and whether the
      # method has one at all is decided much earlier, by `analyze`'s
      # `scan_bare_block_use` -- which does see the nested `super` and does set
      # `uses_bare_block`. What is missing is the capture: `__blk` is an ordinary
      # local of the enclosing method, so the block's `move` closure has to capture
      # it the way it captures any other parameter the body reads, and nothing in
      # the block's HIR mentions it (the reference is synthesized at emit time).
      #
      # That is the same shape as `Captures::zsuper_forwards`, which exists for
      # precisely this reason on the parameter side: a bare `super` in a block makes
      # the enclosing method's parameters live even though they appear nowhere in
      # the block. The fix is to extend that flag to imply `__blk` as well, so the
      # closure captures the block along with the parameters it already does.
      #
      # Written as one file so the divergence is the whole output: CRuby yields the
      # block through both `super`s and prints the collected values.
      class Base
        def each_thing
          yield 1
          yield 2
          :base_done
        end
      end

      class Nested < Base
        def each_thing
          [1].map { super }.first
        end
      end

      acc = []
      p Nested.new.each_thing { |v| acc << v }
      p acc

      # The same through two closures, which is how it reaches a real gem: the
      # parameters forward, so only the block is missing.
      class Deeper < Base
        def each_thing
          [1].map { [2].map { super }.first }.first
        end
      end

      acc2 = []
      p Deeper.new.each_thing { |v| acc2 << v * 10 }
      p acc2
    RUBY

    _(result).must_answer <<~'OUT'
      :base_done
      [1, 2]
      :base_done
      [10, 20]
    OUT
  end

  it "bare super inside a block forwards the methods params" do
    result = ze0(<<~'RUBY')
      # A bare `super` forwards the enclosing method's parameters as currently
      # bound. Inside a BLOCK that is invisible to any walk of the block's own
      # syntax: the forwarding argument list is synthesized when the call is emitted,
      # so nothing in the block mentions the parameters at all.
      #
      # zeo's capture analysis walks local reads, found none, and captured nothing.
      # The block's `move` closure then consumed the enclosing parameter outright,
      # and every later use of it in the method was a borrow-after-move --
      # `require "active_model"` failed to build with 14 of these, over `name`,
      # `options` and `url_safe`.
      class Base
        def greet(name, options = {})
          "base:#{name}:#{options[:k]}"
        end
      end

      class Child < Base
        def greet(name, options = {})
          got = [1].map { super }
          "#{got.first}|after:#{name}:#{options[:k]}"
        end
      end

      p Child.new.greet("x", k: 1)

      # `super` forwards the parameters' CURRENT values, not the ones passed in, and
      # a block sees the reassignment the same way the method body does.
      class Reassigning < Base
        def greet(name, options = {})
          name = name.upcase
          inner = [1].map { super }.first
          "#{inner}|still:#{name}"
        end
      end

      p Reassigning.new.greet("y", k: 2)

      # Every parameter kind forwards, and the method keeps using each one after.
      class WideBase
        def call(a, b = :bee, *rest, k:, m: :em, **opts)
          [a, b, rest, k, m, opts]
        end
      end

      class Wide < WideBase
        def call(a, b = :bee, *rest, k:, m: :em, **opts)
          from_block = [1].map { super }.first
          [from_block, a, b, rest, k, m, opts]
        end
      end

      p Wide.new.call(1, :two, 3, 4, k: :kay, z: 9)

      # The parameter is still a live, mutable local afterwards -- the closure took a
      # copy, not the binding.
      class Mutating < Base
        def greet(name, options = {})
          2.times { super }
          name << "!"
          name
        end
      end

      p Mutating.new.greet(+"z")

      # A block that DOES name a parameter still works, and one whose own parameter
      # shadows the method's must not confuse the two.
      class Shadowing < Base
        def greet(name, options = {})
          seen = ["inner"].map { |name| name }
          "#{[1].map { super }.first}|#{seen.first}|#{name}"
        end
      end

      p Shadowing.new.greet("outer", k: 3)

      # A nested block reaches the same parameters through two closures.
      class Nested < Base
        def greet(name, options = {})
          got = [1].map { [2].map { super }.first }.first
          "#{got}|#{name}"
        end
      end

      p Nested.new.greet("deep", k: 4)
    RUBY

    _(result).must_answer <<~'OUT'
      "base:x:1|after:x:1"
      "base:Y:2|still:Y"
      [[1, :two, [3, 4], :kay, :em, {z: 9}], 1, :two, [3, 4], :kay, :em, {z: 9}]
      "z!"
      "base:outer:3|inner|outer"
      "base:deep:4|deep"
    OUT
  end

  it "include inside a class new block mixes the module at runtime" do
    result = ze0(<<~'RUBY')
      # `Class.new { include M }` mixes M's instance methods into the runtime
      # class's ancestry, so instances dispatch them (and reflection sees M).
      # Last-included wins on a name collision, matching CRuby's ancestry.

      module Greet
        def hello = "hi #{name}"
      end
      module A; def who = "A"; end
      module B; def who = "B"; end
      c = Class.new do
        include Greet
        include A
        include B
        def name = "x"
      end
      obj = c.new
      puts obj.hello
      puts obj.who
      puts c.ancestors.include?(Greet)
      puts c.include?(A)
    RUBY

    _(result).must_answer <<~'OUT'
      hi x
      B
      true
      true
    OUT
  end

  it "lambda inference chain" do
    result = ze0(<<~'RUBY')
      # Stress test: lambda parameter inference through a chain of top-level
      # methods. infer_lambda_param_types runs a fixed-point loop that
      # discovers `g`-as-lambda one hop at a time: f1's g is detected from
      # the direct `.call`, then f2 inherits because it passes its g to f1
      # (which now has lambda-typed param), then f3 inherits from f2, etc.
      # A chain of N methods needs N iterations to converge. With the new
      # 256-iteration safety cap and oscillation guard, this monotonic
      # 5-deep chain must converge cleanly without tripping either.

      def f1(g)
        g.call(1)
      end

      def f2(g)
        f1(g)
      end

      def f3(g)
        f2(g)
      end

      def f4(g)
        f3(g)
      end

      def f5(g)
        f4(g)
      end

      double = ->(x) { x * 2 }
      puts f5(double)
      puts f4(double)
      puts f3(double)
      puts f2(double)
      puts f1(double)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      2
      2
      2
    OUT
  end

  it "runtime super in blocks" do
    result = ze0(<<~'RUBY')
      # A `super` inside a method defined in a NON-const `Struct.new` / `Data.define`
      # block, or a `Class.new` block, resolves at runtime (#192): the class is minted
      # at runtime, so there is no compile-time defining class to splice -- `super`
      # reads the class off the runtime method-frame stack instead.

      # explicit positional super into the native Struct member-binding initialize
      pair = Struct.new(:x, :y) do
        def initialize(x)
          super(x, x * 2)
        end
      end
      p pair.new(5).to_a

      # bare (zsuper) forwarding of the method's own params
      echo = Struct.new(:a, :b) do
        def initialize(a, b)
          super
        end
      end
      p echo.new(1, 2).to_a

      # keyword super into the native Data initialize
      coord = Data.define(:lat, :lng) do
        def initialize(lat:, lng:)
          super(lat: lat * 10, lng: lng)
        end
      end
      p coord.new(lat: 1, lng: 2)

      # super from a Class.new override into a runtime parent's method
      base = Class.new do
        def greet(n)
          "hi #{n}"
        end
      end
      sub = Class.new(base) do
        def greet(n)
          super(n) + "!"
        end
      end
      p sub.new.greet("y")
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 10]
      [1, 2]
      #<data lat=10, lng=2>
      "hi y!"
    OUT
  end

  it "super forward block given" do
    result = ze0(<<~'RUBY')
      # Bare `super` (implicit argument forwarding) inside a `block_given?` branch.
      # When a method body references block_given?, calling it with a block inlines
      # the body and renames the param locals for the capture context; bare super's
      # forwarded arguments must reference the renamed locals, not the original names.
      class Base
        def m(x = nil); "base(#{x})"; end
        def two(a, b); "base(#{a},#{b})"; end
      end

      class Sub < Base
        def m(x = nil)
          if block_given? then super else "self" end
        end
        def two(a, b)
          if block_given? then super else "self" end
        end
      end

      # with a block: inlined, params renamed -> super forwards the renamed locals
      p Sub.new.m(1) { 0 }
      p Sub.new.two(1, 2) { 0 }
      # without a block: the non-inlined path still works
      p Sub.new.m(7)
      p Sub.new.two(3, 4)

      # a poly-typed forwarded argument (boxing branch) in the same context
      class Wrap
        def m(x); "wrap:#{x.inspect}"; end
      end
      class WrapSub < Wrap
        def m(x); block_given? ? super : "self"; end
      end
      def val(v); v; end
      p WrapSub.new.m(val("hi")) { 0 }

      # prepend chain: a prepended method referencing block_given? is inlined at a
      # block call site and its params renamed; the bare super to the prepended-over
      # method must forward the renamed locals too (a sibling of the parent-chain
      # forwarding above).
      module Logged
        def compute(x)
          if block_given? then super else "noblock" end
        end
      end
      class Calc
        prepend Logged
        def compute(x); "calc(#{x})"; end
      end
      p Calc.new.compute(5) { 0 }
      p Calc.new.compute(7)
    RUBY

    _(result).must_answer <<~'OUT'
      "base(1)"
      "base(1,2)"
      "self"
      "self"
      "wrap:\"hi\""
      "calc(5)"
      "noblock"
    OUT
  end

  it "super forwards positional splat double splat and block pass" do
    result = ze0(<<~'RUBY')
      # `super(first, *rest)`, `super(**opts)`, and `super(*args, &block)` all
      # forward through the runtime arg vector -- the splat/double-splat/block-
      # pass shapes a plain call carries, now available at a `super` site too.

      class A
        def m(a, b, c) = "#{a}-#{b}-#{c}"
        def kw(x:, y:) = "#{x}/#{y}"
        def each(*a) = a.each { |v| yield v }
      end
      class B < A
        def m(first, *rest) = super(first, *rest)
        def kw(**opts) = super(**opts)
        def each(*args, &block) = super(*args, &block)
      end
      puts B.new.m(1, 2, 3)
      puts B.new.kw(x: 7, y: 9)
      B.new.each(10, 20) { |v| puts v }
    RUBY

    _(result).must_answer <<~'OUT'
      1-2-3
      7/9
      10
      20
    OUT
  end

  it "super into yielding parent" do
    result = ze0(<<~'RUBY')
      # `super` reaching a parent that yields. A yielding method has no standalone
      # function -- it is inlined at every call site -- so the child has to be
      # inlined too, carrying its caller's block down to the parent. Before this the
      # call was left referencing a function nobody emitted and the link failed.

      class Base
        def go(x)
          p ["base", x]
          yield(x * 2)
        end

        def each_thing
          yield 1
          yield 2
          :done
        end

        def self.build(n)
          p ["cbuild", n]
          yield n
        end
      end

      class Mid < Base
        def go(x)
          p ["mid", x]
          super
        end

        def each_thing
          p "mid-each"
          super
        end

        def self.build(n)
          p ["cmid", n]
          super
        end
      end

      class Leaf < Mid
        def go(x)
          p ["leaf", x]
          super
        end
      end

      # a three-link chain
      p Leaf.new.go(3) { |v| v + 1 }
      # the middle link called directly, with two differently-typed blocks
      p Mid.new.go(5) { |v| v + 2 }
      p Mid.new.go(7) { |v| "got #{v}" }
      # several yields under the super
      acc = []
      p Mid.new.each_thing { |v| acc << v }
      p acc
      # a class-method super
      p Mid.build(4) { |v| v * 10 }

      # `super(args)`: the parent sees the rewritten argument, not the original
      class B2
        def run(a)
          yield a
        end
      end
      class S2 < B2
        def run(a)
          super(a + 1)
        end
      end
      p S2.new.run(1) { |v| v * 100 }

      # a splat parameter travels down the same path
      class B3
        def all(*xs)
          p ["b3", xs]
          yield xs.length
        end
      end
      class S3 < B3
        def all(*xs)
          p ["s3", xs]
          super
        end
      end
      p S3.new.all(1, 2, 3) { |n| n * 5 }

      # a parent that does NOT yield still goes through a plain call
      class B4
        def plain(a) = a * 2
      end
      class S4 < B4
        def plain(a) = super + 1
      end
      p S4.new.plain(5)
    RUBY

    _(result).must_answer <<~'OUT'
      ["leaf", 3]
      ["mid", 3]
      ["base", 3]
      7
      ["mid", 5]
      ["base", 5]
      12
      ["mid", 7]
      ["base", 7]
      "got 14"
      "mid-each"
      :done
      [1, 2]
      ["cmid", 4]
      ["cbuild", 4]
      40
      200
      ["s3", [1, 2, 3]]
      ["b3", [1, 2, 3]]
      15
      11
    OUT
  end

  it "super with a literal block drives the parents yield" do
    result = ze0(<<~'RUBY')
      class Parent
        def run
          yield
        end
        def each_twice
          yield 1
          yield 2
        end
      end
      class Child < Parent
        def run
          super { "from-child" }
        end
        def each_twice
          super { |v| puts "got #{v}" }
        end
      end
      puts Child.new.run
      Child.new.each_twice
    RUBY

    _(result).must_answer <<~'OUT'
      from-child
      got 1
      got 2
    OUT
  end

  it "toplevel extend block param" do
    result = ze0(<<~'RUBY')
      # A module method declaring &block, reached through a top-level extend, is
      # called with the block argument: it used to be dropped, and the emitted C
      # did not compile (#3803).
      module DSL
        def update(&proc)
          if proc
            proc.call
          else
            puts 'no block'
          end
        end

        def render(z: :foreground, &proc)
          puts "render #{z}"
          proc.call if proc
        end

        def plain(n)
          puts "plain #{n}"
        end
      end

      extend DSL

      update { puts 'block ran' }
      update
      render(z: :background) { puts 'render block' }
      render
      plain 3
    RUBY

    _(result).must_answer <<~'OUT'
      block ran
      no block
      render background
      render block
      render foreground
      plain 3
    OUT
  end
end
