# frozen_string_literal: true

require "spec_helper"

describe "Methods: changing in place" do
  it "anon double splat forward" do
    result = zr(<<~'RUBY')
      # Anonymous `**` forwards keyword arguments the same way a named `**kw` does:
      # `def m(**) = target(**)` threads the caller's kwargs through to target.
      def target(a:, b:, c:) = [a, b, c]
      def fwd(**) = target(**)
      p fwd(a: 1, b: 2, c: 3)

      # forwarding into a keyword-rest callee collects the kwargs into a hash
      def collect(**opts) = opts
      def fwd2(**) = collect(**)
      p fwd2(x: 10, y: 20)

      # parity with the named `**o` form
      def fwd_named(**o) = target(**o)
      p fwd_named(a: 4, b: 5, c: 6)

      # an explicit keyword alongside the anonymous splat (literal + forward merge)
      def prepend(**) = collect(z: 99, **)
      p prepend(a: 1, b: 2)

      # a positional param ahead of the anonymous `**` must not be disturbed
      def with_pos(n, **) = [n, collect(**)]
      p with_pos(7, k: 1)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      {x: 10, y: 20}
      [4, 5, 6]
      {z: 99, a: 1, b: 2}
      [7, {k: 1}]
    OUT
  end

  it "bang operator override" do
    result = zr(<<~'RUBY')
      # `!` is an ordinary overridable method in ruby (`BasicObject#!`), and a class
      # that defines it decides its own truthiness under `!`. So `!x` calls the
      # override.
      #
      # `not x` is the same send and also calls it. A plain truthiness test
      # (`x ? a : b`) correctly does NOT call it, so the override changes only the
      # explicit operator -- which is why ruby made `!` a real method in 1.9. Null
      # object and Maybe-shaped wrappers use this.

      class Inverted
        def !() = :bang_called
      end

      i = Inverted.new
      p !i
      p (not i)
      p !!i

      class Blank
        def !() = true
      end
      b = Blank.new
      p !b
      p b ? :truthy : :falsy
    RUBY

    _(result).must_answer <<~'OUT'
      :bang_called
      :bang_called
      false
      true
      :truthy
    OUT
  end

  it "bare sibling cls method call" do
    result = zr(<<~'RUBY')
      # A bare call to a sibling `def self.X` inside another `def self.Y`
      # body in the same module/class is a call to `self.X(...)`, as in
      # CRuby. The sibling's params take the types of the call's args.

      # 1. Module case: outer cmeth makes a bare call to a sibling
      # cmeth that takes a string param.
      module Inv
        def self.outer(table)
          inner(table)
          table
        end

        def self.inner(name)
          # `name` must be a String here for this concatenation.
          "rows-for-" + name
        end
      end

      puts Inv.outer("articles")    # articles
      puts Inv.inner("posts")       # rows-for-posts

      # 2. Real-class case: sibling cmeth chained through a string
      # param.
      class Greeter
        def self.outer(x)
          inner(x)
        end

        def self.inner(s)
          "hello, " + s
        end
      end

      puts Greeter.outer("world")   # hello, world

      # 3. Multi-hop chain across three sibling cmeths inside a module,
      # so the String type must go through two calls.
      module Pipeline
        def self.start(s)
          middle(s)
        end

        def self.middle(t)
          finish(t)
        end

        def self.finish(u)
          "[" + u + "]"
        end
      end

      puts Pipeline.start("ok")     # [ok]
    RUBY

    _(result).must_answer <<~'OUT'
      articles
      rows-for-posts
      hello, world
      [ok]
    OUT
  end

  it "call arg int to obj cast" do
    result = zr(<<~'RUBY')
      # A method can return an object of one of two classes. A local
      # holds the result, and the program passes that local as an
      # argument to a method that expects one of the classes.

      class Holder
        attr_reader :name
        def initialize(name)
          @name = name
        end
      end

      class Wrapper
        attr_reader :tag
        def initialize(tag)
          @tag = tag
        end
      end

      # The helper returns a Holder or a Wrapper:
      def maybe_holder(flag)
        if flag == 0
          Holder.new("h0")
        else
          Wrapper.new("w0")
        end
      end

      def consume_holder(h)
        h.name
      end

      # Push instances into a heterogeneous array so neither class
      # stays value-typed.
      all = [Holder.new("init"), Wrapper.new("init")]

      h = maybe_holder(0)
      all << h

      # `h` holds a Holder, so consume_holder answers its name.
      puts consume_holder(h)
    RUBY

    _(result).must_answer "h0\n"
  end

  it "method object under prepend" do
    result = zr(<<~'RUBY')
      # A `Method` or `UnboundMethod` names ONE entry in the chain, also under
      # `prepend`:
      #
      #   * `super_method` advances past the prepended module, so the idiomatic
      #     `while m; m = m.super_method; end` walk reaches `Sub`, then `Base`, and
      #     stops.
      #   * `Base.instance_method(:greet).bind(sub)` runs `Base`'s body alone and
      #     answers "base". It does not dispatch again from the top of the chain.
      #
      # `bind` is important: an UnboundMethod taken from a named ancestor is how
      # you bypass an override on purpose (`Base.instance_method(:x).bind_call`
      # is the standard way to defeat a `method_missing` proxy or a prepended
      # wrapper).

      class Base
        def greet = "base"
      end
      module Mixin
        def greet = "mixin+" + super
      end
      class Sub < Base
        prepend Mixin
        def greet = "sub+" + super
      end

      m = Sub.new.method(:greet)
      p m.owner
      p m.super_method.owner
      p m.super_method.super_method.owner
      p m.call

      p Base.instance_method(:greet).bind(Sub.new).call
      p Base.instance_method(:greet).bind_call(Sub.new)
      p Sub.instance_method(:greet).owner
      p Mixin.instance_method(:greet).owner

      # The chain walk, with a limit so that the loop always ends.
      walk = []
      cur = Sub.new.method(:greet)
      20.times do
        break unless cur
        walk << cur.owner.to_s
        cur = cur.super_method
      end
      p walk
    RUBY

    _(result).must_answer <<~'OUT'
      Mixin
      Sub
      Base
      "mixin+sub+base"
      "base"
      "base"
      Mixin
      Mixin
      ["Mixin", "Sub", "Base"]
    OUT
  end

  it "operations with the receiver as their own argument" do
    result = zr(<<~'RUBY')
      # `s + s` hands the SAME Arc<Mutex<..>> in as both receiver and argument.
      # parking_lot's Mutex is not reentrant, so any implementation taking both
      # guards in one expression deadlocks -- the process hangs with no output
      # and no error, which is strictly worse than a wrong answer. Every
      # self-argument shape is covered here because the bug is silent: it
      # surfaces as a timeout, never as a failed assertion.

      s = "ab"
      p s + s
      p s * 2
      p s.concat(s)
      p Encoding.compatible?(s, s)
      a = [1, 2]
      p(a <=> a)
      p a == a
      p a + a
      p a - a
      p a & a
      p a | a
      h = {x: 1}
      p h == h
      p h.merge(h)
      r = Random.new(5)
      p r == r
    RUBY

    _(result).must_answer <<~'OUT'
      "abab"
      "abab"
      "abab"
      #<Encoding:UTF-8>
      0
      true
      [1, 2, 1, 2]
      []
      [1, 2]
      [1, 2]
      true
      {x: 1}
      true
    OUT
  end

  it "safe nav with splat" do
    result = zr(<<~'RUBY')
      # `recv&.meth(*args)` / `recv&.meth(**opts)` -- safe navigation on a call the
      # splat path handles. A nil receiver skips the arguments as well as the call,
      # and the receiver itself is evaluated exactly once either way. This is the
      # shape webrick's config dispatch uses: `@config[cb]&.call(*args)`.
      def add(a, b) = a + b
      def kw(a:, b: 10) = a * b

      args = [1, 2]
      opts = { a: 3, b: 4 }

      m = method(:add)
      p m&.call(*args)
      p((nil)&.call(*args))

      k = method(:kw)
      p k&.call(**opts)
      p k&.call(a: 5)

      arr = [1]
      p arr&.push(*args)
      p arr

      # the receiver is evaluated exactly once
      def side(v) = (puts "recv"; v)
      p side(nil)&.push(*args)
      p side([9])&.push(*args)

      # a block rides along
      p [3, 1, 2]&.sort_by { |x| -x }
      p [[1, 2]]&.map { |a, b| a + b }

      # non-nil object receiver with a class type
      class Bag
        def initialize = @items = []
        def add_all(*xs) = (@items.concat(xs); @items)
      end
      b = Bag.new
      p b&.add_all(*args)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      nil
      12
      50
      [1, 1, 2]
      [1, 1, 2]
      recv
      nil
      recv
      [9, 1, 2]
      [3, 2, 1]
      [3]
      [1, 2]
    OUT
  end

  it "self argument operations" do
    result = zr(<<~'RUBY')
      # Operations whose argument IS their receiver. These pass one shared mutable
      # object in twice, so an implementation that takes both locks at once hangs
      # the process -- a silent failure that shows up only as a timeout.
      s = "ab"
      p s + s
      p s * 2
      a = [1, 2]
      p(a <=> a)
      p a == a
      p a + a
      p a - a
      p a & a
      p a | a
      p a.concat(a)
      h = {x: 1}
      p h == h
      p h.merge(h)
      r = Random.new(5)
      p r == r
      p "ab".eql?("ab")
      p Encoding.compatible?(s, s)
      p s.concat(s)
    RUBY

    _(result).must_answer <<~'OUT'
      "abab"
      "abab"
      0
      true
      [1, 2, 1, 2]
      []
      [1, 2]
      [1, 2]
      [1, 2, 1, 2]
      true
      {x: 1}
      true
      true
      #<Encoding:UTF-8>
      "abab"
    OUT
  end

  it "straight line append accumulator" do
    result = zr(<<~'RUBY')
      # An accumulator that straight-line statements append to acts the same as one
      # that a loop appends to. A template compiler emits one `io << chunk` for each
      # literal chunk, with no loop. The cases here check a read before the appending
      # is finished, aliasing, freezing, passing the accumulator on, and interpolation.
      def render
        io = String.new
        io << "<p>a</p>"
        io << "<p>b</p>"
        io << "<p>c</p>"
        io
      end

      def read_between
        io = String.new
        io << "one"
        mid = io.length          # a read before the appending is done
        io << "two"
        "#{io}/#{mid}"
      end

      def aliased
        io = String.new
        io << "x"
        io << "y"
        other = io               # alias after the appends
        io << "z"                # mutation after aliasing
        [io, other, io.equal?(other)]
      end

      def to_helper(s)
        s.length
      end

      def passed
        io = String.new
        io << "abc"
        io << "de"
        to_helper(io) + io.length
      end

      def frozen_case
        io = String.new
        io << "p"
        io << "q"
        f = io.dup.freeze
        begin
          f << "r"
          "no raise"
        rescue FrozenError, RuntimeError
          "raised"
        end
      end

      def binary_case
        io = String.new
        io << "a b"
        io << "c d"
        [io.bytesize, io.bytes.length]
      end

      def interpolated(n)
        io = String.new
        io << "n=#{n};"
        io << "sq=#{n * n};"
        io
      end

      p render
      p render.length
      p read_between
      p aliased
      p passed
      p frozen_case
      p binary_case
      p interpolated(7)
      p render == "<p>a</p><p>b</p><p>c</p>"
      p render.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      "<p>a</p><p>b</p><p>c</p>"
      24
      "onetwo/3"
      ["xyz", "xyz", true]
      10
      "raised"
      [6, 6]
      "n=7;sq=49;"
      true
      false
    OUT
  end
end
