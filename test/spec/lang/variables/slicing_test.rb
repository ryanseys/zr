# frozen_string_literal: true

require "spec_helper"

describe "Variables: slicing" do
  it "assignment in condition warning" do
    result = zr(<<~'RUBY')
      # Ruby warns when a conditional's test is an assignment of a LITERAL --
      # `warning: found '= literal' in conditional, should be ==` -- the classic
      # `if x = 1` typo. zeo emits nothing.
      #
      # The warning is deliberately narrow: only a literal right-hand side triggers
      # it, because `if (m = gets)` is an idiom and must stay quiet. So the cases it
      # does fire on are almost always the mistake it is named for, which is what
      # makes it worth having.
      #
      # zeo already emits parse warnings from `zeo_rt::emit_parse_warnings`, so the
      # channel exists; this diagnostic is not among the ones it carries. Both
      # streams below are compared, and the warning belongs on stderr.

      x = 0
      if x = 1
        puts "literal assign taken"
      end

      while x = 2
        break
      end

      puts "unless:" if (x = 3)

      # No warning for a non-literal right-hand side -- these must stay silent.
      def gets_line = "value"
      if (m = gets_line)
        puts "idiom ok: #{m}"
      end
      y = [1]
      if (z = y.first)
        puts "call ok: #{z}"
      end

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      literal assign taken
      unless:
      idiom ok: value
      call ok: 1
      done
    OUT
      lang/variables/slicing_test.rb:15: warning: found '= literal' in conditional, should be ==
      lang/variables/slicing_test.rb:19: warning: found '= literal' in conditional, should be ==
      lang/variables/slicing_test.rb:23: warning: found '= literal' in conditional, should be ==
    ERR
  end

  it "begin value body local" do
    result = zr(<<~'RUBY')
      # The value of a begin/rescue is the body's when the body carries one. A body
      # whose last statement is a local read is typed by a write that comes later in
      # the walk, so within a round it reads as "not settled yet" -- and taking the
      # handler's type alone at that point made the whole begin an Integer, coercing
      # the array the body really answered into an int slot.
      r = (begin; a = [1]; a; rescue; 0; end)
      p r

      s = (begin; b = [1, 2]; b; rescue; 0; end)
      p s

      t = (begin; 5; rescue; 0; end)
      p t

      u = (begin; c = "x"; c; rescue; 0; end)
      p u

      v = (begin; d = [1]; d; rescue; "z"; end)
      p v

      w = (begin; e = { a: 1 }; e; rescue; 0; end)
      p w

      # a body that really has no value still takes the handler's
      x = (begin; raise "boom"; rescue; 7; end)
      p x
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [1, 2]
      5
      "x"
      [1]
      {a: 1}
      7
    OUT
  end

  it "captured param reassigned in the body shares one cell" do
    result = zr(<<~'RUBY')
      # A parameter that is BOTH captured by an escaping block AND reassigned
      # used to get its capture cell declared twice -- once by the prologue's
      # param wrap and once by the hoist prelude's param-seeded arm -- so the
      # second declaration wrapped the first cell in another cell (an invalid
      # program, from the timeout gem's captured `message ||= ...`). Exactly one
      # owner now: the prelude for assigned params, the prologue otherwise.

      def f(x)
        t = proc { x }
        x = 2
        t.call
      end
      p f(1)
      def g(m = nil)
        m ||= "d"
        t = proc { m }
        t.call
      end
      p g
      p g("y")
    RUBY

    _(result).must_answer <<~'OUT'
      2
      "d"
      "y"
    OUT
  end

  it "global multi assign" do
    result = zr(<<~'RUBY')
      # Multi-assignment into global variables must declare and type every
      # target from the right-hand side, not only the first. A non-int RHS
      # (string / float / array) or a splat-rest target previously left the C
      # global declared as mrb_int and failed to compile.
      $g1, $g2 = 1, 2
      p [$g1, $g2]

      $s1, $s2 = "x", "y"
      p [$s1, $s2]

      $f1, $f2 = 1.5, 2.5
      p [$f1, $f2]

      $pp, $qq = [10, 20]
      p [$pp, $qq]

      # mixed local and global targets
      first, $g = 1, 2
      p [first, $g]

      # splat-rest target collects into an array global
      $x, *$rest = 1, 2, 3, 4
      p $x
      p $rest

      # heterogeneous targets
      $h1, $h2, $h3 = "a", 2, 3.0
      p [$h1, $h2, $h3]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      ["x", "y"]
      [1.5, 2.5]
      [10, 20]
      [1, 2]
      1
      [2, 3, 4]
      ["a", 2, 3.0]
    OUT
  end

  it "global nil slot" do
    result = zr(<<~'RUBY')
      # A global whose only value is nil got no type, and a global with no type got
      # no slot, so the reference did not compile at all ('gv_foo' undeclared). The
      # same for a global never assigned anywhere, which Ruby also reads as nil.
      $foo = nil
      p $foo.nil?
      p $foo

      # never assigned
      p $never_written.nil?

      # a later write still decides the type: this one is an Integer, not a boxed slot
      $n = nil
      $n = 5
      p $n
      p $n + 1

      # and a nil string global is nil, not the empty string: assigning nil used to
      # store "" while `.nil?` compares against NULL, so it answered false
      $s = nil
      p $s.nil?
      $s = "x"
      p $s.nil?
      p $s

      # read through a method, which is where this first showed up
      $log = nil
      $log_dead = false

      def live_write
        puts "no pipe" if $log.nil?
        puts "dead" if $log_dead
      end

      live_write
      $log = "open"
      live_write
      p $log

      # the underscore-prefixed spelling takes the same path
      $_x = nil
      p $_x.nil?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      true
      5
      6
      true
      false
      "x"
      no pipe
      "open"
      true
    OUT
  end

  it "Operator-write ($x += / -= / *= / /= ... )" do
    result = zr(<<~'RUBY')
      # Global variable compound writes — Or / And / Operator / Target.
      # Was four tests; merged here. Globals across the original files
      # happened to reuse `$count`, so this file picks distinct names per
      # section so the merged script's accumulated state doesn't change
      # the per-section semantics.


      # Mirror of LocalVariableOperatorWriteNode but the storage is a
      # C-level global symbol via sanitize_gvar(name).
      $counter = 0
      $counter += 1
      $counter += 5
      puts $counter   # 6
      $counter -= 2
      puts $counter   # 4
      $counter *= 3
      puts $counter   # 12
      $counter /= 4
      puts $counter   # 3
    RUBY

    _(result).must_answer <<~'OUT'
      6
      4
      12
      3
    OUT
  end

  it "Or-write ($x ||= val)" do
    result = zr(<<~'RUBY')
      # Global variable compound writes — Or / And / Operator / Target.
      # Was four tests; merged here. Globals across the original files
      # happened to reuse `$count`, so this file picks distinct names per
      # section so the merged script's accumulated state doesn't change
      # the per-section semantics.


      # Mirror of LocalVariableOrWriteNode. Only assigns if the global
      # is currently falsy.
      #
      # Note: Spinel uses C-truthy semantics (any zero is falsy), which
      # diverges from CRuby (only nil/false are falsy). For unassigned
      # globals (default 0/nil) the two agree on the first assignment;
      # subsequent ||= against truthy non-zero ints also agree. This
      # test exercises only the agreement region.
      $or_count ||= 5    # never assigned, fires
      puts $or_count     # 5
      $or_count ||= 99   # already 5 (truthy in both), doesn't fire
      puts $or_count     # 5
    RUBY

    _(result).must_answer "5\n5\n"
  end

  it "And-write ($x &&= val)" do
    result = zr(<<~'RUBY')
      # Global variable compound writes — Or / And / Operator / Target.
      # Was four tests; merged here. Globals across the original files
      # happened to reuse `$count`, so this file picks distinct names per
      # section so the merged script's accumulated state doesn't change
      # the per-section semantics.


      # Mirror of LocalVariableAndWriteNode. Only assigns if the global
      # is currently truthy.
      $and_count = 5
      $and_count &&= 10  # 5 is truthy, fires
      puts $and_count    # 10
      $and_count &&= 0   # 10 is truthy in C, fires
      puts $and_count    # 0
    RUBY

    _(result).must_answer "10\n0\n"
  end

  it "Target (multi-assign LHS for globals)" do
    result = zr(<<~'RUBY')
      # Global variable compound writes — Or / And / Operator / Target.
      # Was four tests; merged here. Globals across the original files
      # happened to reuse `$count`, so this file picks distinct names per
      # section so the merged script's accumulated state doesn't change
      # the per-section semantics.


      # `$a, $b = 1, 2` -- each LHS slot is a GlobalVariableTargetNode.
      # Routes through MultiWriteNode's emit_multi_write_target to the
      # same g_<name> C-level storage GlobalVariableWriteNode uses.
      $ga, $gb = 1, 2
      puts $ga          # 1
      puts $gb          # 2
      $ga, $gb = $gb, $ga    # swap
      puts $ga          # 2
      puts $gb          # 1
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      2
      1
    OUT
  end

  it "is a against statically typed array hash range and symbol locals" do
    result = zr(<<~'RUBY')
      arr = [1, 2, 3]
      puts arr.is_a?(Array)
      puts arr.is_a?(Object)
      puts arr.is_a?(Hash)
      h = {a: 1}
      puts h.is_a?(Hash)
      r = 1..5
      puts r.is_a?(Range)
      sym = :foo
      puts sym.is_a?(Symbol)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      true
      true
    OUT
  end

  it "local across begin clauses" do
    result = zr(<<~'RUBY')
      # A local first assigned inside a `begin` body is still in scope in the
      # `rescue`/`ensure` clauses and after the whole `begin` -- one Ruby scope, even
      # though each clause runs on its own path.
      class Box
        def initialize(v) = @v = v
        def v = @v
        def close = "closed #{@v}"
      end

      def read_in_ensure
        begin
          b = Box.new(1)
          b.v
        ensure
          puts b.close
        end
      end
      p read_in_ensure

      def read_after_rescue
        begin
          c = Box.new(2)
        rescue
          nil
        end
        c.v
      end
      p read_after_rescue

      def assigned_in_rescue
        begin
          raise "boom"
        rescue
          d = Box.new(3)
        end
        d.v
      end
      p assigned_in_rescue

      # Reassigning inside the body must be visible outside it, not shadowed by a
      # binding confined to the body.
      def reassigned_inside
        e = Box.new(4)
        begin
          e = Box.new(5)
        ensure
          nil
        end
        e.v
      end
      p reassigned_inside

      # ...and a multi-assignment's targets are locals for this purpose too.
      def multi_assigned_inside
        begin
          f, g = Box.new(6), Box.new(7)
        ensure
          nil
        end
        [f.v, g.v]
      end
      p multi_assigned_inside

      # A local the body never reaches is nil in the ensure, not undefined.
      def never_assigned
        begin
          raise "boom"
          h = Box.new(8)
        rescue
          p defined?(h)
          p h
        end
      end
      never_assigned
    RUBY

    _(result).must_answer <<~'OUT'
      closed 1
      1
      2
      3
      5
      [6, 7]
      "local-variable"
      nil
    OUT
  end

  it "local or write first assign" do
    result = zr(<<~'RUBY')
      # `x ||= v` on a method-local with no earlier assignment, and a tail assignment
      # as a method's value.
      #
      # The or-write emitter treated every non-poly local as already truthy, so the
      # assignment was dropped entirely -- the variable kept its declaration's zero.
      # And a tail local write returned the return type's default rather than the
      # value just assigned, so even an or-write that DID run was invisible.

      class Crash
        def to_s
          text ||= ["Usage:", "foo"].join(" ")
        end
      end
      p Crash.new.to_s

      # every representation: pointer slots test NULL, the sentinel-carrying scalars
      # are declared with their nil sentinel because nothing else ever assigns them
      def gi; x ||= 5; x; end
      def gf; x ||= 1.5; x; end
      def gs; x ||= "s"; x; end
      def ga; x ||= [1, 2]; x; end
      def gh; x ||= { "a" => 1 }; x["a"]; end   # not the Hash itself: #inspect spacing moves between Ruby versions
      def gb; x ||= true; x; end
      def gy; x ||= :sym; x; end
      p gi, gf, gs, ga, gh, gb, gy

      # a definite assignment first: the or-write is the no-op it always was
      def hi; x = 3; x ||= 5; x; end
      def hs; x = "q"; x ||= "s"; x; end
      def hn; x = nil; x ||= "z"; x; end
      p hi, hs, hn

      # a tail write is the method's value, whatever the shape
      def ti; x = 5; end
      def ts; x = "hi"; end
      def ta; x = [1]; end
      def to; x ||= "o"; end
      p ti, ts, ta, to

      # the or-write must not re-fire once the slot holds something, and must fire
      # again for each fresh block-local
      def loops
        seen = []
        i = 0
        while i < 3
          memo ||= "iter#{i}"
          seen.push(memo)
          i += 1
        end
        seen
      end
      p loops

      def per_block
        out = []
        3.times do |n|
          fresh ||= "b#{n}"
          out.push(fresh)
        end
        out
      end
      p per_block

      # the value expression must not run when the slot is already set: the whole
      # point of ||= is that the right-hand side is skipped
      $calls = 0
      def costly
        $calls += 1
        "made"
      end

      def once
        v = nil
        2.times { v ||= costly }
        v
      end
      p once
      p $calls
    RUBY

    _(result).must_answer <<~'OUT'
      "Usage: foo"
      5
      1.5
      "s"
      [1, 2]
      1
      true
      :sym
      3
      "q"
      "z"
      5
      "hi"
      [1]
      "o"
      ["iter0", "iter0", "iter0"]
      ["b0", "b1", "b2"]
      "made"
      1
    OUT
  end

  it "local rebind after self returning mutator" do
    result = zr(<<~'RUBY')
      # A local holding both a scalar and a self-returning Array mutator's result stays poly.
      x = [1, 2]
      r = x.pop
      p r
      r = x.concat([3])
      p r
      r = x.push(4)
      p r
      r = x.reverse!
      p r
      r = x.sort!
      p r
      p r.class

      # either order
      y = [5, 6]
      s = 0
      s = y.concat([7])
      p s
      s = y.first
      p s

      # string arrays too
      z = ["a"]
      t = z.pop
      p t
      t = z.concat(["b"])
      p t
      t = "q"
      p t

      # an array-only capture still follows the receiver's widening
      a = [1, 2]
      c = a.push(:x)
      p c
      p a
    RUBY

    _(result).must_answer <<~'OUT'
      2
      [1, 3]
      [1, 3, 4]
      [4, 3, 1]
      [1, 3, 4]
      Array
      [5, 6, 7]
      5
      "a"
      ["b"]
      "q"
      [1, 2, :x]
      [1, 2, :x]
    OUT
  end

  it "multiple assignment names its constant scope first" do
    result = zr(<<~'RUBY')
      # A multiple assignment evaluates each target's receiver or scope
      # before the right-hand side, and an attribute target through an
      # explicit receiver may not reach a private writer.
      def scope_for_it = (puts "scope"; Object)
      scope_for_it::QB, c = (puts "value"; [1, 2])
      p QB, c

      class Opaque
        attr_reader :s

        private attr_writer :s

        def set_both = (self.s, @t = 1, 2; [s, @t])
      end
      begin
        Opaque.new.s, c = 1, 2
        p :called
      rescue NoMethodError => e
        p e.message
      end
      p Opaque.new.set_both

    RUBY

    _(result).must_answer <<~'OUT'
      scope
      value
      1
      2
      "private method 's=' called for an instance of Opaque"
      [1, 2]
    OUT
  end

  it "ruby underscore is an ordinary readable local" do
    result = zr(<<~'RUBY')
      # Ruby's `_` is an ordinary local: it reads back, it reassigns from its own
      # value, and only the first `_` in a parameter list owns the name. The
      # generated program has no named binding that spells `_`, so it must be
      # mangled.

      _ = 10
      p _
      _ = _ + 5
      p _
      [[1, :a]].each { |n, _| p n }
      [[1, :a]].each { |_, sym| p sym }
      _, second = [:first, :second]
      p [second, _]
    RUBY

    _(result).must_answer <<~'OUT'
      10
      15
      1
      :a
      [:second, :first]
    OUT
  end
end
