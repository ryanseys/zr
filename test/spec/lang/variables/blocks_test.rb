# frozen_string_literal: true

require "spec_helper"

describe "Variables: blocks and yields" do
  it "block local resets to nil on every invocation" do
    result = ze0(<<~'RUBY')
      # The part that makes a block-local more than a naming convention, and
      # the reason it can't be hoisted out of the per-call prologue: `total`
      # is nil again at the top of EVERY call, so this never accumulates.

      total = 42
      [1, 2, 3].each { |x; total| total = (total || 0) + x }
      p total

      outs = []
      [1, 2].each { |x; acc| acc ||= []; acc << x; outs << acc.dup }
      p outs
    RUBY

    _(result).must_answer <<~'OUT'
      42
      [[1], [2]]
    OUT
  end

  it "block locals shadow an enclosing local and never write back" do
    result = ze0(<<~'RUBY')
      sum = 99
      [1].each { |x; sum| sum = x }
      p sum

      a = 1
      b = 2
      [0].each { |z; a, b| a = 7; b = 8 }
      p [a, b]

      n = 100
      [10, 20].each { |v; n| n = v }
      p n

      r = 0
      [5].each do |i|
        [9].each { |j; r| r = j }
        r = i
      end
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      99
      [1, 2]
      100
      5
    OUT
  end

  it "block locals work on the times inline path and in lambdas" do
    result = ze0(<<~'RUBY')
      # `n.times { }` on an integer literal is spliced inline as a native
      # loop rather than becoming a real Proc, so it binds its params at its
      # own site and needs the block-local declaration applied there too.

      n = "outer"
      3.times { |i; n| n = i }
      p n

      f = ->(x; t) { t = x * 2; t }
      p f.call(5)

      q = "kept"
      [[1, 2, 3]].each { |(x, y), *r; q| q = x }
      p q
    RUBY

    _(result).must_answer <<~'OUT'
      "outer"
      10
      "kept"
    OUT
  end

  it "block params are reassignable" do
    result = ze0(<<~'RUBY')
      1.upto(2) { |n| n = n + 10; puts n }
      3.times { |i| i = i * 2; print i }
      puts
    RUBY

    _(result).must_answer <<~'OUT'
      11
      12
      024
    OUT
  end

  it "escaping block can mutate a captured enclosing local" do
    result = ze0(<<~'RUBY')
      class Collector
        def each_num(a, b, c)
          yield a
          yield b
          yield c
        end
      end
      total = 0
      Collector.new.each_num(1, 2, 3) { |n| total += n }
      puts total
    RUBY

    _(result).must_answer "6\n"
  end

  it "inlined times block local is captured by a nested block" do
    result = ze0(<<~'RUBY')
      # A `.times` block-LOCAL (`|i; n|`) captured by a nested escaping block is
      # cell-wrapped for the same reason as its param (H1).

      store = []
      [1].each do |a|
        3.times do |i; n|
          n = i * 10
          store << ->() { "#{a}:#{i}:#{n}" }
        end
      end
      store.each { |p| puts p.call }
    RUBY

    _(result).must_answer <<~'OUT'
      1:0:0
      1:1:10
      1:2:20
    OUT
  end

  it "local write in a runtime class body gets its own scope" do
    result = ze0(<<~'RUBY')
      # `class X < <expression>` builds the class at runtime, so its body runs as a
      # block -- and a construct only the static class path can emit has no runtime
      # spelling. Reaching codegen with one used to abort the compiler with an
      # "unexpected top-level-only node in expression position" panic; a local write
      # would silently assign the ENCLOSING scope's variable instead of opening its
      # own. Both are rejected by name.
      #
      # A REOPEN (`Foo = Class.new; class Foo ... end`) has a static fallback for
      # exactly these bodies, so it takes that instead of rejecting -- see
      # `reopening_a_runtime_class_falls_back_rather_than_failing_to_compile`.
      #
      # A runtime-built class body EMITS as a block, which shares the enclosing
      # local scope -- but ruby gives a class body its own. The body's names are
      # renamed per body (`rename::isolate_runtime_class_locals`), so neither
      # direction leaks: the outer `y` keeps its value, and the body's `y` is
      # invisible outside. This used to be a clean compile-time rejection.

      y = 99
      class Foo < Struct.new(:a)
        y = 1
        define_method(:from_body) { y }
      end
      p y
      p Foo.new(0).from_body
      p defined?(y)
      p binding.local_variables
    RUBY

    _(result).must_answer <<~'OUT'
      99
      1
      "local-variable"
      [:y]
    OUT
  end

  it "massign cell captured target" do
    result = ze0(<<~'RUBY')
      # Multi-assign targets captured by a later lambda live in heap cells, so the
      # target write must go through the cell (doom's draw_automap min_x/max_y,
      # closed over by the to_sx/to_sy procs, were written as undeclared lv_ names).
      def bounds(a)
        min_x, max_x, min_y, max_y = a[0], a[1], a[2], a[3]
        to_sx = ->(wx) { wx - min_x }
        to_sy = ->(wy) { max_y - wy }
        puts to_sx.call(10)
        puts to_sy.call(3)
        puts max_x - min_y
        min_x, max_y = 100, 200
        puts to_sx.call(10)
        puts to_sy.call(3)
      end
      bounds([1, 2, 3, 4])
    RUBY

    _(result).must_answer <<~'OUT'
      9
      1
      -1
      -90
      197
    OUT
  end

  it "nested block captures the outer blocks own local" do
    result = ze0(<<~'RUBY')
      # The INNER block reads the OUTER block's own param `n`. The outer
      # block promotes `n` to a shared cell, so the
      # inner closure captures it -- previously a clean rejection,
      # now the real Ruby behavior. Oracle: n=1 -> 3+1,4+1; n=2 -> 3+2,4+2.

      class Collector
        def each_num(a, b)
          yield a
          yield b
        end
      end
      c = Collector.new
      c.each_num(1, 2) { |n| c.each_num(3, 4) { |m| puts m + n } }
    RUBY

    _(result).must_answer <<~'OUT'
      4
      5
      5
      6
    OUT
  end

  it "nested block reading outer cells and writing its own locals composes" do
    result = ze0(<<~'RUBY')
      # Four levels deep, mixing: a method-level captured local (`total`),
      # an outer block's cell-promoted local (`row`), block params read from
      # two levels down, and inner-only locals. Oracle-verified.

      def grid(n)
        total = 0
        n.times do |a|
          row = 0
          n.times do |b|
            n.times do |c|
              cell = a * 100 + b * 10 + c
              row = row + cell
              n.times do |d|
                bump = d + cell
                total = total + bump
              end
            end
          end
          total = total + row
        end
        total
      end
      p grid(2)
    RUBY

    _(result).must_answer "1340\n"
  end

  it "nested closure captures enclosing blocks own local" do
    result = ze0(<<~'RUBY')
      # A name that is both an enclosing block's own local AND captured by a
      # nested escaping closure must be declared once (as a shared cell), not
      # also fresh-declared by the own-locals prelude.

      adders = []
      [1, 2, 3].each do |n|
        base = n * 100
        adders << -> { base + n }
      end
      p adders.map(&:call)

      procs = []
      [10, 20].each do |k|
        acc = 0
        procs << -> { acc }
        acc = k + 1
        procs << -> { acc }
      end
      p procs.map(&:call)
    RUBY

    _(result).must_answer <<~'OUT'
      [101, 202, 303]
      [11, 11, 21, 21]
    OUT
  end

  it "ordinary method yield with no block raises rescuable local jump error" do
    result = ze0(<<~'RUBY')
      # The same LocalJumpError path an ordinary method has always needed -- it
      # used to abort the process instead of raising.

      def m
        yield
      end
      begin
        m
      rescue LocalJumpError => e
        puts "caught #{e.class}"
      end
      puts m { "with-block" }
    RUBY

    _(result).must_answer <<~'OUT'
      caught LocalJumpError
      with-block
    OUT
  end

  it "ractor block capturing an outer local is rejected where ruby rejects it" do
    result = ze0(<<~'RUBY')
      # CRuby's `ArgumentError`, raised by `Ractor.new` itself and catchable
      # there -- not the compile error zeo used to report. The verdict rides on
      # the Proc value (`RProc::with_outer_capture`), so a literal block and a
      # `&proc` argument reach the same raise.

      x = 5
      begin
        Ractor.new { x + 1 }
      rescue => e
        puts "raised: #{e.class}: #{e.send(:message)}"
      end
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      raised: ArgumentError: can not isolate a Proc because it accesses outer variables (x).
      still running
    OUT
      lang/variables/blocks_test.rb:8: warning: Ractor API is experimental and may change in future versions of Ruby.
    ERR
  end

  it "singleton method yield with no block raises rescuable local jump error" do
    result = ze0(<<~'RUBY')
      # A `yield` reached with no block is a RESCUABLE LocalJumpError, not a
      # process abort -- including for a singleton method, whose block is
      # threaded through the call site.

      obj = Object.new
      def obj.needs_block
        yield
      end
      begin
        obj.needs_block
      rescue LocalJumpError => e
        puts "caught #{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer "caught LocalJumpError: no block given (yield)\n"
  end
end
