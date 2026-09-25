# frozen_string_literal: true

require "spec_helper"

describe "Cache programs" do
  it "const cache invalidation" do
    result = zr(<<~'RUBY')
      WHICH = "first"

      def read_which = WHICH

      # Warm the site, then reassign the same constant. Ruby warns and rebinds; the
      # cached read must not survive the rebinding.
      p read_which
      Object.send(:remove_const, :WHICH)
      WHICH = "second"
      p read_which

      module Shelf
        ITEM = "shelf"
        def self.item = ITEM
      end
      p Shelf.item
      Shelf.send(:remove_const, :ITEM)
      Shelf.const_set(:ITEM, "restocked")
      p Shelf.item

      # A constant read that MISSES caches nothing, so defining the name afterwards
      # has to take effect.
      def read_late = LATE
      begin
        read_late
      rescue NameError => e
        p e.message
      end
      LATE = 42
      p read_late

      # Removing a constant after the site has cached it must raise again.
      def read_gone = GONE
      GONE = 1
      p read_gone
      Object.send(:remove_const, :GONE)
      begin
        read_gone
      rescue NameError => e
        p e.message
      end

      # A nested class named only once it is bound to a constant becomes reachable
      # through that namespace.
      module Box; end
      def read_inner = Box::Inner
      begin
        read_inner
      rescue NameError => e
        p e.class
      end
      Box.const_set(:Inner, Class.new)
      p read_inner.name
      p read_inner.name

      # Threads share one constant table, so a value written by one is what the
      # other's cached site must answer with.
      SHARED = "before"
      def read_shared = SHARED
      p read_shared
      Thread.new do
        Object.send(:remove_const, :SHARED)
        Object.const_set(:SHARED, "after")
      end.join
      p read_shared
    RUBY

    _(result).must_answer <<~'OUT'
      "first"
      "second"
      "shelf"
      "restocked"
      "uninitialized constant LATE"
      42
      1
      "uninitialized constant GONE"
      NameError
      "Box::Inner"
      "Box::Inner"
      "before"
      "after"
    OUT
  end

  it "special constant receivers hit the site's cell" do
    result = zr(<<~'RUBY')
      # One site, receivers of five classes in turn: nil, true, false, a
      # symbol and a String. The site finds each class itself and its
      # cells answer; a method defined or redefined after the site ran
      # is what the next send reaches.
      def describe(x) = x.tag

      class NilClass; def tag = "nil"; end
      class TrueClass; def tag = "true"; end
      class FalseClass; def tag = "false"; end
      class Symbol; def tag = "sym #{self}"; end
      class String; def tag = "str #{self}"; end

      inputs = [nil, true, false, :a, "s", nil, :b, false]
      p inputs.map { |x| describe(x) }
      p inputs.map { |x| describe(x) }

      class NilClass; def tag = "nil again"; end
      class Symbol; def tag = "sym again"; end
      p inputs.map { |x| describe(x) }

      # Predicates on a special constant, ten thousand times at one site.
      n = 0
      20_000.times { |i| n += 1 if (i.even? ? nil : :s).nil? }
      p n
      p [nil, true, false, :x].map(&:frozen?)
      p [nil, false, :y].map { |x| x.respond_to?(:tag) }
    RUBY

    _(result).must_answer <<~'OUT'
      ["nil", "true", "false", "sym a", "str s", "nil", "sym b", "false"]
      ["nil", "true", "false", "sym a", "str s", "nil", "sym b", "false"]
      ["nil again", "true", "false", "sym again", "str s", "nil again", "sym again", "false"]
      10000
      [true, true, true, true]
      [true, true, true]
    OUT
  end

  it "struct members are read and written at the site" do
    result = zr(<<~'RUBY')
      # One reader site and one writer site over a Struct, a keyword
      # Struct, a Data, an attr_accessor object and a subclass that
      # redefines the reader: the cell's shape says which the site does
      # in place, and every guard that fails takes the call.
      Point = Struct.new(:x, :y)
      Named = Struct.new(:x, :y, keyword_init: true)
      Pair = Data.define(:x, :y)
      class Reader
        attr_accessor :x, :y
        def initialize(x, y) = (@x = x; @y = y)
      end
      class Loud < Point
        def x = "loud #{super}"
      end

      def read_x(o) = o.x
      def write_x(o, v) = o.x = v

      things = [Point.new(1, 2), Named.new(x: 3, y: 4), Pair.new(x: 5, y: 6), Reader.new(7, 8), Loud.new(9, 10)]
      p things.map { |t| read_x(t) }
      p things.map { |t| read_x(t) }
      writable = [things[0], things[1], things[3], things[4]]
      p writable.map { |t| write_x(t, t.x.to_s * 2) }
      p writable.map { |t| read_x(t) }

      # A struct made with no values reads nil and takes a write.
      bare = Point.allocate
      p read_x(bare)
      write_x(bare, :set)
      p [read_x(bare), bare.y, bare.to_a]

      # A frozen struct refuses the write at the site.
      pt = Point.new(1, 2).freeze
      begin
        write_x(pt, 3)
      rescue => e
        p [e.class, e.message]
      end
      p read_x(pt)

      # A member redefined after the site ran.
      class Point; def x = "redefined"; end
      p read_x(things[0])

      # Ten thousand reads and writes through one site each.
      acc = Point.new(0, 0)
      10_000.times { |i| acc.y = acc.y + i }
      p acc.y
      p acc
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3, 5, 7, "loud 9"]
      [1, 3, 5, 7, "loud 9"]
      ["11", "33", "77", "loud 9loud 9"]
      ["11", "33", "77", "loud loud 9loud 9"]
      nil
      [:set, nil, [:set, nil]]
      [FrozenError, "can't modify frozen Point: #<struct Point x=1, y=2>"]
      1
      "redefined"
      49995000
      #<struct Point x=0, y=49995000>
    OUT
  end

  it "frozen nul literal cache" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true
      # `fresh_receiver.delete("\0")` must not corrupt the receiver, also when a GC
      # runs during the call (as in doom's `data[8,8].delete("\0")` WAD name parse).
      # Here the receiver has no NUL, so delete removes nothing: it still allocates a
      # fresh string (delete always does), but the resulting bytes are unchanged.
      out = []
      8000.times do |i|
        out << "item#{i % 100}".delete("\x00")
      end
      puts out.length
      puts out[0]
      puts out.last
      bad = 0
      out.each_with_index { |s, i| bad += 1 unless s == "item#{i % 100}" }
      puts "bad=#{bad}"

      # Sibling-operand shape: a fresh string operand sits next to a frozen
      # NUL-containing literal. The literal can allocate on first evaluation, and a
      # GC at that time must not free the fresh operand. `a + "pad\0"` keeps "pad".
      def joinit(a)
        a + "pad\x00"
      end
      res = []
      8000.times do |i|
        res << joinit("head#{i}")
      end
      GC.start
      # GC-safety check: the fresh "head<i>" prefix must survive (a corrupted operand
      # would garble it). NUL-agnostic (via start_with?) so it does not depend on
      # whether `+` keeps the frozen literal's trailing NUL.
      sbad = 0
      res.each_with_index { |s, i| sbad += 1 unless s.start_with?("head#{i}pad") }
      puts "scount=#{res.size} sbad=#{sbad}"
      puts res[0].delete("\x00")
      puts res.last.delete("\x00")
    RUBY

    _(result).must_answer <<~'OUT'
      8000
      item0
      item99
      bad=0
      scount=8000 sbad=0
      head0pad
      head7999pad
    OUT
  end

  it "raise names the snippet and the eval site" do
    result = zr(<<~'RUBY')
      src = "raise 'boom'"
      begin
        eval(src)
      rescue => e
        puts e.backtrace.first(2)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      (eval at compiler/cache/cache_test.rb:3):1:in '<main>'
      compiler/cache/cache_test.rb:3:in 'Kernel#eval'
    OUT
  end

  it "snippet reaches its callers block" do
    result = zr(<<~'RUBY')
      # `yield`, `block_given?` and a bare `super` written at a snippet's own
      # level belong to the method the `eval` was called from -- CRuby reads them
      # off the caller's control frame. zr publishes the home from every scope
      # that lexically contains a run-time `eval`, so the snippet finds it
      # whichever eval surface ran it.

      YIELD = "yield 7"
      GIVEN = "block_given?"
      SUPER = "super"
      DEF_S = "defined?(super)"
      DEF_Y = "defined?(yield)"

      def plain = eval(YIELD)
      def given = eval(GIVEN)
      def through_instance_eval = instance_eval(YIELD)
      def through_class_eval = self.class.class_eval(YIELD)
      def through_binding = eval(YIELD, binding)

      p(plain { |x| x * 3 })
      p given
      p(given { })
      p(through_instance_eval { |x| "ie #{x}" })
      p(through_class_eval { |x| "ce #{x}" })
      p(through_binding { |x| "b #{x}" })

      # A block re-publishes the home it inherited, so an intervening method that
      # can eval cannot shadow it.
      def helper
        eval(["1", "2"].first)
        yield
      end
      def outer
        helper { p eval(YIELD) }
      end
      outer { |x| "outer got #{x}" }

      def nested
        [1].map { [2].map { eval(YIELD) } }
      end
      p(nested { |x| x + 100 })

      # A bare `super` forwards the enclosing method's own arguments.
      class Base
        def go(a, b = 2, *rest, k: 9) = [a, b, rest, k]
      end
      class Sub < Base
        def go(a, b = 20, *rest, k: 90) = eval(SUPER)
      end
      p Sub.new.go(1)
      p Sub.new.go(1, 2, 3, k: 4)

      # `defined?` answers the same questions.
      class DBase; def d = 1; end
      class DSub < DBase; def d = eval(DEF_S); end
      class DSolo; def d = eval(DEF_S); end
      p DSub.new.d
      p DSolo.new.d
      p eval(DEF_S)
      def dy = eval(DEF_Y)
      p dy
      p(dy { })

      # A method that HAS no block raises `LocalJumpError` when the snippet
      # yields; an `eval` called from a scope that can never have one -- the top
      # level, a class body -- does not compile at all, which is CRuby's own
      # `Invalid yield` and carries the eval's location as its whole backtrace.
      def blockless = eval(YIELD)
      begin
        blockless
      rescue LocalJumpError => e
        puts "#{e.class}: #{e.message}"
      end
      begin
        eval(YIELD)
      rescue SyntaxError => e
        puts "#{e.class}: #{e.message}"
        p e.backtrace
      end
      class InBody
        begin
          eval(YIELD)
        rescue SyntaxError => e
          puts "class body: #{e.message}"
        end
      end
      # `defined?(yield)` asks rather than yields, so it answers nil instead.
      p eval(DEF_Y)
    RUBY

    _(result).must_answer <<~'OUT'
      21
      false
      true
      "ie 7"
      "ce 7"
      "b 7"
      "outer got 7"
      [[107]]
      [1, 20, [], 90]
      [1, 2, [3], 4]
      "super"
      nil
      nil
      nil
      "yield"
      LocalJumpError: no block given (yield)
      SyntaxError: (eval at compiler/cache/cache_test.rb:74):1: Invalid yield
      ["(eval at compiler/cache/cache_test.rb:74)"]
      class body: (eval at compiler/cache/cache_test.rb:81):1: Invalid yield
      nil
    OUT
  end

  it "snippet refines and uses at run time" do
    result = zr(<<~'RUBY')

      # Refinements are a compile-time decision in a program: a `refine` mints a
      # holder the compiler registers, and a `using` rewrites the call sites in
      # its lexical range. A snippet has neither -- its module is a run-time
      # constant and what it refines lives in the running program's registry --
      # so both go through the run time: `Module#refine` mints and marks the
      # holder, and a `using` fills an activation slot every call site it covers
      # reads.

      module Outer
        refine Integer do
          def trip = self * 3
        end
      end

      MINT = "module Minted; refine String do; def shout = upcase + '!'; end; end"
      eval(MINT)
      p Minted.refinements.size
      p Minted.refinements.first.class
      p "hi".respond_to?(:shout)

      USE = [
        "using Outer",
        "p 7.trip",
        "p 7.respond_to?(:trip)",
        "p 7.send(:trip)",
        "p 7.method(:trip).owner.to_s",
        "p [1, 2].map { |x| x.trip }",
        # A `def` written after the `using` sees it too: the slot outlives the
        # call, exactly as CRuby's lexical activation outlives the eval.
        "def tripler(n) = n.trip",
      ].join("\n")
      eval(USE)
      p tripler(5)

      # ... and nothing outside the snippet's own range sees it.
      begin
        3.trip
      rescue NoMethodError
        puts "outside: NoMethodError"
      end

      # A snippet that both mints and activates.
      BOTH = [
        "module Both; refine Symbol do; def twice = [self, self]; end; end",
        "using Both",
        "p :a.twice",
      ].join("\n")
      eval(BOTH)

      # `using` answers the receiver it activated on.
      ACT = "using Outer"
      p eval(ACT)
      class Host; end
      p Host.class_eval(ACT)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      Refinement
      false
      21
      true
      21
      "#<refinement:Integer@Outer>"
      [3, 6]
      15
      outside: NoMethodError
      [:a, :a]
      main
      Host
    OUT
  end

  it "snippets regexp literal has its own site" do
    result = zr(<<~'RUBY')
      # A non-interpolated regexp literal is ONE frozen object per site, cached in
      # the runtime under an emitter-assigned id. A program's ids are dense from
      # zero and minted by one compile; a run-time `eval` is compiled by a FRESH
      # compiler that starts at zero again, so the two spaces collided and a site
      # answered whichever pattern reached the cache first.
      #
      # It is silent: both sides get a working Regexp, just the wrong one. The
      # tools found it -- the env-var check scanned every doc with a pattern
      # from a run-time-required unit and reported the whole file as an undefined
      # variable name.
      #
      # `flipflop::EVAL_BASE` and the `using` slots already hold their id spaces
      # apart for exactly this reason; regexp literals and `attach_function` symbol
      # sites did not.

      text = "a ZR_TEST_ONE b ZR_TEST_TWO c"
      names = /\bZR_TEST_[A-Z0-9_]+\b/

      # The snippet's own literals come first, so its site 0 is minted before the
      # program reaches its own.
      eval(%q{
        def words(s) = s.scan(/\w+/)
        def digits(s) = s.scan(/\d+/)
      })

      p text.scan(names)
      p words("hi there")
      p digits("a1 b22 c333")
      p text.scan(names)
      p text.scan(/\bZR_TEST_[A-Z0-9_]+\b/)

      # A second snippet must not collide with the first either.
      eval(%q{ def caps(s) = s.scan(/[A-Z]+/) })
      p caps("aBcDe")
      p words("still here")

      # The identity a per-site cache exists for: one site, one frozen object.
      two = [text.scan(names), text.scan(names)]
      p two.first == two.last
      p names.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      ["ZR_TEST_ONE", "ZR_TEST_TWO"]
      ["hi", "there"]
      ["1", "22", "333"]
      ["ZR_TEST_ONE", "ZR_TEST_TWO"]
      ["ZR_TEST_ONE", "ZR_TEST_TWO"]
      ["B", "D"]
      ["still", "here"]
      true
      true
    OUT
  end
end
