# frozen_string_literal: true

require "spec_helper"

describe "Blocks: defining and naming methods" do
  it "alias keyword inside a class eval block aliases at runtime" do
    result = ze0(<<~'RUBY')
      # `alias new old` in a general (non-class-body) context -- here a module's
      # `class_eval` block, where `self` is the module -- desugars to a runtime
      # `alias_method`, the same path delegate.rb's `kernel.class_eval do alias
      # __raise__ raise end` needs.

      class Foo
        def greet = "hi"
      end
      Foo.class_eval do
        alias hello greet
      end
      puts Foo.new.hello
      puts Foo.new.greet
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      hi
    OUT
  end

  it "curry through parameter" do
    result = ze0(<<~'RUBY')
      # Whether an application saturates a curry is decided statically when the base
      # proc's arity can be traced. A curry that arrives through a parameter, a
      # container or an untyped slot cannot be traced, and answering "not yet
      # saturated" for those meant a method taking a curried Proc returned a Proc
      # where CRuby returns the value (#4068). Saturation is a run-time property of
      # the accumulator, so it is read there.
      JOIN = ->(a, b) { "#{a}/#{b}" }

      def apply_final(rule)
        rule.call("x")
      end

      curried = JOIN.curry["nickname"]
      p curried.call("x")
      p apply_final(curried)
      p apply_final(curried).class

      # a partial application through the same parameter still answers a Proc
      TRIPLE = ->(a, b, c) { "#{a}#{b}#{c}" }
      def apply_one(rule)
        rule.call("2")
      end
      part = TRIPLE.curry["1"]
      p apply_one(part).class
      p apply_one(part).call("3")

      # through a container, and through a method's return
      procs = [JOIN.curry["k"]]
      p procs[0].call("v")

      def fetch_rule
        JOIN.curry["m"]
      end
      p fetch_rule.call("n")

      # the statically traceable forms are unchanged
      p JOIN.curry["a"]["b"]
      p JOIN.curry.call("a", "b")
      p ->() { 5 }.curry.call
    RUBY

    _(result).must_answer <<~'OUT'
      "nickname/x"
      "nickname/x"
      String
      Proc
      "123"
      "k/v"
      "m/n"
      "a/b"
      "a/b"
      5
    OUT
  end

  it "def in a block stays runtime only" do
    result = ze0(<<~'RUBY')
      # `Reach::through_block` is the one restriction the nested walk keeps: a `def`
      # written in a block may never run at all, so it is not registered at compile
      # time. It still defines itself when the block runs, which is all CRuby
      # promises either.
      class Looped
        [1].each do
          def defined_by_the_block
            :ran
          end
        end
      end

      p Looped.instance_methods(false)
      p Looped.new.defined_by_the_block

      class NeverRuns
        [].each do
          def never_defined
            :unreachable
          end
        end
      end

      p NeverRuns.instance_methods(false)
      p NeverRuns.new.respond_to?(:never_defined)
    RUBY

    _(result).must_answer <<~'OUT'
      [:defined_by_the_block]
      :ran
      []
      false
    OUT
  end

  it "method missing to ary spreads" do
    result = ze0(<<~'RUBY')
      # A BasicObject that forwards to an Array through method_missing, and says
      # so through respond_to_missing?, spreads over block parameters, a
      # multiple assignment and a splat, as rb_check_funcall lets it: prism's
      # lex_compat tokens are such objects.
      class Tok < BasicObject
        def initialize(a) = @a = a
        def respond_to_missing?(name, include_private = false) = @a.respond_to?(name, include_private)
        def method_missing(name, ...) = @a.send(name, ...)
      end
      toks = [Tok.new([[1, 2], :on_x, "t", 3])]
      toks.each { |(l, c), ev, text, st| p [l, c, ev, text, st] }
      toks.each { |a, b| p [a, b] }
      a, b = Tok.new([5, 6])
      p [a, b]
      x, y = *Tok.new([7, 8])
      p [x, y]
      p [Tok.new([1]).to_ary]

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, :on_x, "t", 3]
      [[1, 2], :on_x]
      [5, 6]
      [7, 8]
      [[1]]
    OUT
  end

  it "proc anonymous rest" do
    result = ze0(<<~'RUBY')
      # `|*|` (anonymous rest) accepts any arity in a lambda; the arity check keys
      # on rest PRESENCE, not on it having a name.
      l = lambda { |*| 1 }
      p l.call(2, 3, 4)
      p l.call
      pr = proc { |*| 7 }
      p pr.call(1)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      7
    OUT
  end

  it "proc curry reflection" do
    result = ze0(<<~'RUBY')
      c = ->(a, b) { a + b }.curry
      p(c.arity)
      p(c.lambda?)
      p(c.class)
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      true
      Proc
    OUT
  end

  it "proc new with a block is that block" do
    result = ze0(<<~'RUBY')
      p Proc.new { |x| x * 2 }.call(4)
      p Proc.new { |a, b| [a, b] }.arity
      p Proc.new {}.lambda?
    RUBY

    _(result).must_answer <<~'OUT'
      8
      2
      false
    OUT
  end

  it "proc optional params" do
    result = ze0(<<~'RUBY')
      # Optional parameters on proc literals: CRuby's distribution -- requireds from
      # the front, posts reserved at the back, optionals consume what remains (else
      # their defaults, which may reference earlier params), the rest takes the rest.
      p1 = proc do |a=5, *b, c|
        [a, b, c]
      end
      p p1.call(1, 2, 3)
      p p1.call(1)
      p p1.call(1, 2)
      p2 = proc { |x, y=9| [x, y] }
      p p2.call(1)
      p p2.call(1, 2)
      l = lambda { |x, y=9| [x, y] }
      p l.call(3)
      begin
        l.call
      rescue ArgumentError
        puts "arity"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, [2], 3]
      [5, [], 1]
      [1, [], 2]
      [1, 9]
      [1, 2]
      [3, 9]
      arity
    OUT
  end

  it "proc rest post params" do
    result = ze0(<<~'RUBY')
      # Splat-rest and trailing post-required parameters on proc literals: CRuby's
      # distribution fills leading requireds from the front, posts from the back,
      # the (possibly empty) remainder is the rest, and missing posts bind nil.
      p1 = proc do |*a, b|
        [a, b]
      end
      p p1.call(1, 2, 3)
      p p1.call(1)
      p p1.call

      p2 = proc do |x, *m, y|
        [x, m, y]
      end
      p p2.call(1, 2, 3, 4, 5)
      p p2.call(1, 2)

      # lambda: rest lifts the max, requireds+posts stay mandatory
      l = lambda do |x, *m, y|
        [x, m, y]
      end
      p l.call(1, 9)
      p l.call(1, 2, 3, 9)
      begin
        l.call(1)
      rescue ArgumentError
        puts "arity enforced"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], 3]
      [[], 1]
      [[], nil]
      [1, [2, 3, 4], 5]
      [1, [], 2]
      [1, [], 9]
      [1, [2, 3], 9]
      arity enforced
    OUT
  end
end
