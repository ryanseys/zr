# frozen_string_literal: true

require "spec_helper"

describe "Variables: searching and matching" do
  it "array index assign out of range raises index error not a panic" do
    result = zr(<<~'RUBY')
      # Before this fix, a negative out-of-range `Array#[]=` index was an
      # unconditional abort -- a real `IndexError` (catchable) is
      # constructed instead now, and the array is otherwise
      # unaffected (an in-range negative-from-end or growing-positive index
      # still works exactly as before).

      a = [1, 2, 3]
      begin
        a[-10] = :x
      rescue IndexError => e
        puts "caught"
      end
      a[5] = :y
      puts a.length
      puts a[5]
    RUBY

    _(result).must_answer <<~'OUT'
      caught
      6
      y
    OUT
  end

  it "array index assign splices start length and range spans" do
    result = zr(<<~'RUBY')
      a = [1, 2, 3, 4]
      a[1, 2] = [:x, :y, :z]
      p a
      b = [1, 2, 3]
      b[1, 0] = [:ins]
      p b
      c = [1, 2, 3, 4]
      c[1..2] = [:r]
      p c
      d = [1, 2, 3, 4]
      d[1...3] = [:e]
      p d
      e = [1, 2, 3]
      e[0, 2] = :scalar
      p e
      f = [1, 2, 3]
      p(f[0, 1] = [:v])
    RUBY

    _(result).must_answer <<~'OUT'
      [1, :x, :y, :z, 4]
      [1, :ins, 2, 3]
      [1, :r, 4]
      [1, :e, 4]
      [:scalar, 3]
      [:v]
    OUT
  end

  it "compound and or assignment on an array index" do
    result = zr(<<~'RUBY')
      arr = [1, 2, 3]
      arr[0] += 10
      puts arr[0]
      arr[1] ||= 99
      puts arr[1]
    RUBY

    _(result).must_answer "11\n2\n"
  end

  it "compound assignment through a multi argument index" do
    result = zr(<<~'RUBY')
      # `[]`-style compound assignment with MORE than one index. `[]`/`[]=` are
      # ordinary methods, so `a[i, j] += rhs` is a two-argument `[]` paired with a
      # three-argument `[]=` -- Array's `(start, length)` splice form. Each index
      # binds to its own hidden local so a side-effecting index runs exactly once
      # across the read and the write, the same guarantee the receiver already had.

      a = [1, 2, 3, 4]
      a[1, 2] += ["x"]
      p a

      b = [1, 2, 3]
      b[0, 2] ||= 9
      p b

      $i = 0
      $j = 0
      def idx; $i += 1; 0; end
      def len; $j += 1; 1; end
      c = [1, 2, 3]
      c[idx, len] = [9]
      p c
      p [$i, $j]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, "x", 4]
      [1, 2, 3]
      [9, 2, 3]
      [1, 1]
    OUT
  end

  it "compound index assignment in tail position compiles" do
    result = zr(<<~'RUBY')
      # Regression test for a pre-existing codegen bug found during the
      # freeze work (not freeze-related): `HirNode::Seq` -- the lowering
      # artifact behind `arr[i] += 1` -- emitted a brace-less statement
      # sequence from `emit_expr`, producing an invalid program
      # whenever the compound assignment was the LAST statement of a
      # method/`begin` body. Latent since the `Seq` arm was written; every
      # prior test happened to put a statement after it.

      class Bumper
        def bump
          arr = [10]
          arr[0] += 1
        end
      end
      puts Bumper.new.bump
    RUBY

    _(result).must_answer "11\n"
  end

  it "defined classifies assignments it and match globals" do
    result = zr(<<~'RUBY')
      # `defined?` answers as CRuby's defined_expr0 does: every write, an
      # operator assignment among them, is an "assignment"; `it` is a local;
      # a call with a block literal is an expression; `$1` and `$&` are
      # defined while the last match holds them; `$~` always is.
      a = nil
      @x = 1
      p defined?(a ||= 1), defined?(a &&= 2), defined?(a += 1)
      p defined?(@x += 1), defined?(@y ||= 1), defined?($g ||= 2)
      p defined?(K ||= 1), defined?(a = 1), defined?(@x.to_s.b = 1)
      p [1].map { defined?(it) }
      p defined?(p { }), defined?(p)
      p defined?($~), defined?($!)
      "a" =~ /(a)/
      p defined?($1), defined?($2), defined?($&), defined?($`)
      "zz" =~ /nomatch/
      p defined?($1), defined?($&)

    RUBY

    _(result).must_answer <<~'OUT'
      "assignment"
      "assignment"
      "assignment"
      "assignment"
      "assignment"
      "assignment"
      "assignment"
      "assignment"
      nil
      ["local-variable"]
      "expression"
      "method"
      "global-variable"
      "global-variable"
      "global-variable"
      nil
      "global-variable"
      "global-variable"
      nil
      nil
    OUT
  end

  it "defined globals and match vars check definedness at runtime" do
    result = zr(<<~'RUBY')
      # A user global is "global-variable" only once assigned; a predefined
      # special ($~) always is; a match capture only when it participated. An
      # array literal is defined only if every element is.

      $set_g = 1
      p defined?($set_g)
      p defined?($never_set_g)
      p defined?($~)
      p defined?($1)
      "hi" =~ /(h)/
      p defined?($1)
      p defined?($2)
      p defined?([1, Array])
      p defined?([Nonexist_zzz, Array])
    RUBY

    _(result).must_answer <<~'OUT'
      "global-variable"
      nil
      "global-variable"
      nil
      "global-variable"
      nil
      "expression"
      nil
    OUT
  end

  it "definition hooks global" do
    result = zr(<<~'RUBY')
      # A definition hook written on `Module`, `Class` or `BasicObject` ITSELF
      # answers for every class in the program.
      #
      # No per-class owner scan can see one: such a reopen registers an ordinary
      # instance method whose owner is the very class the no-op default lives on, so
      # the two are indistinguishable by owner. The compiler records these by name
      # instead, and hands the list to the runtime.

      class Module
        def method_added(n) = puts("GLOBAL #{self}##{n}")
      end

      class Q
        def qq; end
      end

      module R
        def rr; end
      end

      class BasicObject
        def singleton_method_added(n) = ::Kernel.puts("GLOBAL s #{n}")
      end

      class S
        def self.sm; end
      end

      # The runtime shapes reach the same list.
      Class.new { define_method(:runtime_one) { } }
      Object.new.define_singleton_method(:runtime_two) { }
    RUBY

    _(result).must_answer <<~'OUT'
      GLOBAL Module#method_added
      GLOBAL Q#qq
      GLOBAL R#rr
      GLOBAL BasicObject#singleton_method_added
      GLOBAL s sm
      GLOBAL #<Class:0xADDR>#runtime_one
      GLOBAL s runtime_two
    OUT
  end

  it "index compound assignment works inside a thread block" do
    result = zr(<<~'RUBY')
      # From the reference corpus (index_opassign_in_thread_block.rb): the
      # `Seq` desugar's hidden temps declared inside an escaping Proc's own
      # prelude, against a captured-cell array.

      arr = [10]
      t = Thread.new do
        50.times { arr[0] += 1 }
      end
      t.join
      puts arr[0]
    RUBY

    _(result).must_answer "60\n"
  end

  it "index opassign value prelude rhs" do
    result = zr(<<~'RUBY')
      # Index operator-assignment in VALUE position whose RIGHT-HAND SIDE needs a
      # prelude. `index_opassign_in_thread_block.rb` pinned the value-position
      # op-write itself (a block lifted to a real proc, so its tail `arr[i] += x` is
      # emitted through the value form). That form writes the mutation into the
      # prelude buffer and then reads the slot back -- but while it was writing
      # THERE, an RHS wanting a prelude of its own (a user method call hoists its
      # receiver and spills each argument into a temp) had nowhere to put it and
      # emitted the declaration inline, inside the `sp_..._set(...)` argument list.
      # The result was structurally invalid C -- an unbalanced paren and a `_tN` used
      # before its declaration -- so it surfaced as a cc failure, not a type error.
      #
      # A literal or a bare local on the RHS needs no prelude and always worked, and
      # so did `arr[i] = arr[i] + <call>`; only the compound form in value position
      # with a prelude-carrying RHS broke.
      #
      # Reported as `arr[i] += <call> if <cond>`, but the trailing `if` is NOT part of
      # the trigger -- it only put the op-write in tail position. That spelling emits
      # byte-identical code to case 1, as does the same op-write reached through a
      # Thread (already covered by index_opassign_in_thread_block.rb), so neither
      # earns a case here. What follows is one case per distinct emitted path.

      class Outcome
        def map_one(f)
          f + 1.0
        end
      end

      outcome = Outcome.new

      # 1. the reduced engine shape: captured float array, captured object receiver,
      #    one argument -- spilled into a prelude temp -- as the body's tail.
      a = [1.0]
      ->() { a[0] += outcome.map_one(2.5) }.call
      p a

      # 2. the prelude is the RECEIVER hoist rather than an argument spill, and it
      #    allocates, so it carries a GC root that must also land before the write.
      b = [1.0]
      ->() { b[0] += Outcome.new.map_one(2.5) }.call
      p b

      # 3. integer array (a different set/get arm), and the op-write's own value is
      #    still the stored (post-op) result.
      d = [10]
      r = ->() { d[0] += outcome.map_one(7).to_i }.call
      p r
      p d

      # 4. hash receiver -- another arm, with its own key handling.
      h = { "k" => 10 }
      ->() { h["k"] += outcome.map_one(5).to_i }.call
      p h

      # 5. a method-call KEY is not effect-free, so receiver and key are hoisted into
      #    shared temps first (the #3417 path). Those hoisted lines, the RHS's
      #    prelude, and the mutation must come out in that order.
      class Slot
        def tag
          0
        end
      end
      v = [1.0]
      s = Slot.new
      ->() { v[s.tag] += outcome.map_one(2.5) }.call
      p v
    RUBY

    _(result).must_answer <<~'OUT'
      [4.5]
      [4.5]
      18
      [18]
      {"k" => 16}
      [4.5]
    OUT
  end

  it "rightward assign destructure" do
    result = zr(<<~'RUBY')
      # Rightward assignment with an array / hash pattern (MatchRequiredNode):
      # `value => [a, b, c]` destructures and binds, raising
      # NoMatchingPatternError when the value does not match.

      # Integer array.
      [1, 2, 3] => a, b, c
      puts a
      puts b
      puts c

      # String array (binds string-typed locals).
      ["x", "y"] => p, q
      puts p
      puts q

      # Hash pattern binds by key.
      {name: "Alice", age: 30} => {name:, age:}
      puts name
      puts age

      # Length mismatch raises NoMatchingPatternError.
      begin
        [1, 2] => d, e, f
        puts "no raise"
      rescue NoMatchingPatternError
        puts "raised"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      x
      y
      Alice
      30
      raised
    OUT
  end
end
