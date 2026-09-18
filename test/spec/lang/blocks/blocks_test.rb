# frozen_string_literal: true

require "spec_helper"

describe "Blocks programs" do
  it "block arg constant callable" do
    result = ze0(<<~'RUBY')
      # `&SOME_LAMBDA` forwards a callable the same way `&some_lambda` does: a
      # constant read is as deterministic and side-effect-free as a local one. Only
      # locals and ivars were accepted, so the constant form was refused outright.
      DOUBLE = ->(x) { x * 2 }
      p [1, 2, 3].map(&DOUBLE)

      TO_S = ->(x) { x.to_s }
      p [1, 2].map(&TO_S)
      p [1, 2, 3].select(&->(x) { x > 1 })

      BIG = ->(x) { x > 2 }
      p [1, 2, 3, 4].select(&BIG)
      p [1, 2, 3, 4].reject(&BIG)
      p [3, 1, 2].sort_by(&DOUBLE)
      p [1, 2, 3].each(&DOUBLE)

      module M
        F = ->(x) { x + 1 }
      end
      p [1, 2].map(&M::F)

      # the local and ivar forms keep working
      f = ->(x) { x * 3 }
      p [1, 2].map(&f)
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6]
      ["1", "2"]
      [2, 3]
      [3, 4]
      [1, 2]
      [1, 2, 3]
      [1, 2, 3]
      [2, 3]
      [3, 6]
    OUT
  end

  it "block autosplat collectors" do
    result = ze0(<<~'RUBY')
      # A block with 2+ params iterating an array whose elements are sub-arrays
      # auto-splats each element across the params (CRuby proc auto-splat), for the
      # collecting emitters map/collect, select/filter, reject, and sort_by. A single
      # param still binds the whole sub-array. Receivers route through a method param
      # so the runtime (poly-array) path runs, not a folded literal.
      def s(x); x; end

      # --- map / collect: each param gets a positional element ---
      p s([["a", 1], ["b", 2]]).map { |k, v| "#{k}#{v}" }   # ["a1", "b2"]
      p s([[1, 2], [3, 4]]).map { |a, b| a + b }             # [3, 7]
      p s([[1, 2], [3, 4]]).collect { |a, b| a * b }         # [2, 12]

      # --- single param keeps the whole sub-array (no splat) ---
      p s([[1, 2], [3, 4]]).map { |pair| pair.sum }          # [3, 7]

      # --- select / reject return the whole matching elements ---
      p s([[1, 2], [3, 1]]).select { |a, b| a < b }          # [[1, 2]]
      p s([[1, 2], [3, 1]]).reject { |a, b| a < b }          # [[3, 1]]
      p s([[1, 2], [3, 1]]).filter { |a, b| a < b }          # [[1, 2]]

      # --- sort_by over the second element ---
      p s([["bob", 30], ["amy", 20]]).sort_by { |n, a| a }   # [["amy", 20], ["bob", 30]]
      p s([[3, 9], [1, 9], [2, 9]]).sort_by { |a, b| a }     # [[1, 9], [2, 9], [3, 9]]

      # --- 3 params over triples ---
      p s([[1, 2, 3], [4, 5, 6]]).map { |a, b, c| a + b + c } # [6, 15]

      # --- more params than elements: extras are nil ---
      p s([[1, 2], [3, 4]]).map { |a, b, c| [a, b, c] }      # [[1, 2, nil], [3, 4, nil]]

      # --- empty receiver ---
      p s([]).map { |a, b| a + b }                           # []

      # --- numbered params auto-splat the same way ---
      p s([[1, 2], [3, 4]]).map { _1 + _2 }                  # [3, 7]
    RUBY

    _(result).must_answer <<~'OUT'
      ["a1", "b2"]
      [3, 7]
      [2, 12]
      [3, 7]
      [[1, 2]]
      [[3, 1]]
      [[1, 2]]
      [["amy", 20], ["bob", 30]]
      [[1, 9], [2, 9], [3, 9]]
      [6, 15]
      [[1, 2, nil], [3, 4, nil]]
      []
      [3, 7]
    OUT
  end

  it "block forward" do
    result = ze0(<<~'RUBY')
      # A method whose only use of its &block parameter is to forward it to another
      # call (never calling/yielding it directly) must stay a real method and pass
      # the block along -- to a yielding target and to an explicit &block target.

      def yield_target
        yield 5
      end

      def block_target(&b)
        b.call(5)
      end

      def fwd_to_yield(&b)
        yield_target(&b)
      end

      def fwd_to_block(&b)
        block_target(&b)
      end

      puts(fwd_to_yield { |x| x * 2 })
      puts(fwd_to_block { |x| x * 2 })

      # Two-hop forward: the block threads through two forwarding methods.
      def hop1(&b)
        fwd_to_yield(&b)
      end
      puts(hop1 { |x| x + 100 })

      # Forwarding an anonymous block parameter.
      def fwd_anon(&)
        yield_target(&)
      end
      puts(fwd_anon { |x| x * 3 })

      # A forwarder used at several call sites with different block bodies.
      def relay(&b)
        yield_target(&b)
      end
      puts(relay { |x| x - 1 })
      puts(relay { |x| x * x })
    RUBY

    _(result).must_answer <<~'OUT'
      10
      10
      105
      15
      4
      25
    OUT
  end

  it "block forward block arg" do
    result = ze0(<<~'RUBY')
      # `&proc_var` argument forwarding (`def m(&b); g(&b); end`).
      #
      # Pre-fix Spinel never parsed `&expr` in call argument position
      # (`g(&block)`) — Prism's `PM_BLOCK_ARGUMENT_NODE` had no case in
      # `flatten()`, so the codegen saw the call as taking no block at all
      # and the captured `&block` was silently dropped at every forwarding
      # call site.
      #
      # This PR adds:
      #   - parser case for PM_BLOCK_ARGUMENT_NODE → "BlockArgumentNode"
      #   - `find_block_arg(nid)` helper that returns the inner expression
      #   - `strip_block_arg` filter so &block-args don't leak into the
      #     positional-args comma list at compile_call_args / -with_defaults
      #     / compile_typed_call_args
      #   - extends Sites A, B, and the receiverless has_block_param path
      #     to fall through to find_block_arg when has_literal_block returns 0,
      #     emitting the proc expression directly (no compile_proc_literal call,
      #     since the proc is already a captured `sp_Proc *`).

      # 1. Site A (self-call) &proc_var forwarding.
      class Forwarder
        def outer(&block)
          inner(&block)
        end

        def inner(&block)
          block.call
        end
      end

      Forwarder.new.outer { puts "1-self-amp" }

      # 2. Site B (typed-receiver) &proc_var forwarding — outer captures
      #    &block, then forwards it to a different receiver's method.
      class Sink
        def receive(&block)
          block.call
        end
      end

      class Source
        def relay(sink, &block)
          sink.receive(&block)
        end
      end

      Source.new.relay(Sink.new) { puts "2-recv-amp" }

      # 3. Top-level (receiverless) `&proc_var` forwarding.
      def outer_top(&block)
        inner_top(&block)
      end

      def inner_top(&block)
        block.call
      end

      outer_top { puts "3-top-amp" }

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1-self-amp
      2-recv-amp
      3-top-amp
      done
    OUT
  end

  it "block forward nilcheck" do
    result = ze0(<<~'RUBY')
      # Forwarding `&block` into a callee that nil-checks the forwarded block.
      # The combination (forward + nil-check) previously rejected at compile time.

      def inner(&blk) = (blk ? blk.call : 0)
      def outer(&blk) = inner(&blk)

      puts outer { 7 }          # block forwarded through: 7
      puts outer                # no block given: forwarded nil, inner's check -> 0

      def wrap(&b) = inner(&b)
      puts wrap { 6 * 7 }       # value flows through the forwarded block: 42

      # anonymous block forwarding (`&`)
      def anon(&) = inner(&)
      puts anon { 5 }           # 5
      puts anon                 # 0

      # receiver-form: an instance method forwarding into a nil-checking sibling
      # (distinct method names to avoid an unrelated implicit-self resolution quirk)
      class Runner
        def run_inner(&blk) = (blk ? blk.call : -1)
        def run_outer(&blk) = run_inner(&blk)
      end
      r = Runner.new
      puts r.run_outer { 8 }    # 8
      puts r.run_outer          # nil forwarded -> -1
    RUBY

    _(result).must_answer <<~'OUT'
      7
      0
      42
      5
      0
      8
      -1
    OUT
  end

  it "block forward recursive cmethod" do
    result = ze0(<<~'RUBY')
      # A literal block on an implicit-self call to a &block-forwarding recursive
      # class method: the block lifts to a real proc (capturing enclosing locals)
      # and the &block forward passes the caller's proc through.
      class M
        def self.walk(node, &block)
          return block.call(node) if node.is_a?(String)
          node.each { |child| walk(child, &block) }
        end

        def self.go(root)
          out = []
          walk(root) { |n| out << n }
          out.join(",")
        end
      end

      puts M.go([["a"], "b"])
      out2 = []
      M.walk([["x", ["y"]], "z"]) { |n| out2 << n }
      p out2

      # a &block forward CHAIN between class methods carries the block's value
      # type through (g's literal block reaches f's blk_ret via the forward)
      class N
        def self.f(&block)
          block.call(1)
        end

        def self.g(&block)
          f(&block)
        end
      end
      p(N.g { |n| n * 3 })
    RUBY

    _(result).must_answer <<~'OUT'
      a,b
      ["x", "y", "z"]
      3
    OUT
  end

  it "block forward self call" do
    result = ze0(<<~'RUBY')
      # Self-call `m { ... }` &block forwarding (Site A).
      #
      # When a method on class C calls another method on the same class
      # without an explicit receiver (`m { ... }` instead of `self.m { ... }`),
      # dispatch goes through `compile_no_recv_call_expr`'s
      # `@current_class_idx >= 0` branch — call this Site A. Pre-fix this
      # branch always emitted `sp_C_m(self, ca)` with no block tail, so a
      # literal block at the call site was silently dropped and the binary
      # segfaulted in `sp_proc_call(NULL, ...)`.
      #
      # Site A reuses the `has_literal_block` helper and the
      # `omit_trailing` 4th arg of `compile_typed_call_args` introduced
      # in the previous PR (Site B / typed-receiver forwarding); the only
      # new code here is the same `bp`/`tail` template adapted to the
      # self-call form.

      # 1. Bare self-call dispatch — one method invokes another method
      #    of the same class with a literal block.
      class Caller
        def kick
          inner { puts "1-self-call" }
        end

        def inner(&block)
          block.call
        end
      end

      Caller.new.kick

      # 2. Self-call passes a value through to the block via block.call(arg).
      class Wrapper
        def go
          forward(7) { |i| puts "2-arg=#{i}" }
        end

        def forward(n, &block)
          block.call(n)
        end
      end

      Wrapper.new.go

      # 3. Self-call inside a loop — each iteration forwards a fresh block.
      class Bank
        def run
          deposit_each(3) { |i| puts "3-dollar-#{i}" }
        end

        def deposit_each(n, &block)
          i = 0
          while i < n
            block.call(i)
            i = i + 1
          end
        end
      end

      Bank.new.run

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1-self-call
      2-arg=7
      3-dollar-0
      3-dollar-1
      3-dollar-2
      done
    OUT
  end

  it "block forwarded into recursive yielder" do
    result = ze0(<<~'RUBY')
      # A block handed to a method that FORWARDS it to a self-recursive yielder.
      #
      # The yielder recurses, so its block cannot be spliced into it -- it is lowered
      # to take a real &block proc. The forwarder in front of it is marked `yields`
      # all the same (forwarding is what earns that mark), and the capture analysis
      # read that mark as "the block is spliced, so nothing escapes". The block was
      # then built as a proc with no capture struct, and its writes to enclosing
      # locals went to a copy of them: the block ran, and what it assigned never
      # arrived (#4145).
      $ran = 0

      def walk(n)
        yield
        walk(n - 1) { nil } if n > 0
        nil
      end

      def hop(n, &block)
        walk(n, &block)
      end

      seen = nil
      hop(1) { $ran += 1; seen = 1 }
      p [seen, $ran]

      # Deeper: two forwarders in front of the yielder, and a capture written on
      # every recursion level rather than once.
      $log = []

      def down(n)
        yield n
        down(n - 1) { |k| $log << -k } if n > 0
        nil
      end

      def mid(n, &b) = down(n, &b)
      def top(n, &b) = mid(n, &b)

      acc = []
      top(2) { |k| acc << k }
      p [acc, $log]

      # The block written at the yielder's own call site was always right; pinned so
      # the two paths cannot drift apart.
      direct = []
      walk(1) { direct << :d }
      p direct

      # The return type of a lowered recursive yielder is the one its body derives.
      # It used to be forced to Integer, which was right only by coincidence: a body
      # ending in a String or an Array emitted `return char *` from a function typed
      # sp_int and produced no binary at all.
      def ends_nil(n)
        yield
        ends_nil(n - 1) { nil } if n > 0
        nil
      end

      def ends_str(n)
        yield
        ends_str(n - 1) { nil } if n > 0
        "x"
      end

      def ends_ary(n)
        yield
        ends_ary(n - 1) { nil } if n > 0
        [1]
      end

      def ends_sym(n)
        yield
        ends_sym(n - 1) { nil } if n > 0
        :a
      end

      p [ends_nil(1) { }, ends_str(1) { }, ends_ary(1) { }, ends_sym(1) { }]

      # A return that DOES come out of a yield still reads the block's answer through
      # the proc side-channel, which is what the forced Integer was there for.
      def carry(n)
        return yield if n <= 0
        carry(n - 1) { yield }
      end
      p carry(2) { 42 }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1]
      [[2], [-1, 0]]
      [:d]
      [nil, "x", [1], :a]
      42
    OUT
  end

  it "block given block param" do
    result = ze0(<<~'RUBY')
      # `block_given?` for `&block` parameters.
      #
      # Pre-fix `block_given?` only returned the right answer inside methods
      # that used `yield` (`@in_yield_method == 1`). Methods that captured
      # the block solely via `&block` and never invoked yield fell through
      # to the constant `"0"` — losing the answer for the one case where
      # the runtime *does* know whether a block was forwarded.
      #
      # Fix: track the enclosing method's `&block` param name in
      # `@current_method_block_param`, set/restored at all three method-emit
      # sites (emit_instance_method, emit_class_level_method,
      # emit_toplevel_method) via a new find_block_param_name helper. The
      # block_given? handler returns `(lv_<param> != NULL)` after the
      # existing `@in_yield_method` branch.
      #
      # This test exercises the no-block-passed observable through the
      # receiverless default-padding path and the explicit `self.block_given?`
      # spelling.

      # 1. Top-level `&block` method, called without a block — block_given?
      #    must return false. Pre-fix this constant-returned 0 with no
      #    visibility into the actual presence of a block.
      def top(&block)
        if block_given?
          puts "1-yes"
        else
          puts "1-no"
        end
      end

      top                       #=> 1-no

      # 2. Same shape with a regular arg before &block — find_block_param_name
      #    must skip the int param and pick the trailing proc-typed slot.
      def top2(label, &block)
        if block_given?
          puts label + "-yes"
        else
          puts label + "-no"
        end
      end

      top2("2")                 #=> 2-no

      def top3(&block)
        if self.block_given?
          puts "3-yes"
        else
          puts "3-no"
        end
      end

      def top4(&block)
        if self.block_given?
          puts "4-yes"
        else
          puts "4-no"
        end
      end

      top3                      #=> 3-no
      top4 {}                   #=> 4-yes

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1-no
      2-no
      3-no
      4-yes
      done
    OUT
  end

  it "block kwrest param" do
    result = ze0(<<~'RUBY')
      def m(a)
        yield a
      end
      p(m([1, 2]) { |*a, **k| [a, k] })
      p(m([1, 2]) { |a, b, **k| [a, b, k] })
      def m2(x, y)
        yield x, y
      end
      p(m2(1, 2) { |a, b, **k| [a, b, k] })
      def m3(a)
        yield a, x: 9, y: 8
      end
      p(m3(1) { |v, x:, **k| [v, x, k] })
    RUBY

    _(result).must_answer <<~'OUT'
      [[[1, 2]], {}]
      [1, 2, {}]
      [1, 2, {}]
      [1, 9, {y: 8}]
    OUT
  end

  it "block param destructure" do
    result = ze0(<<~'RUBY')
      # Parenthesized block parameters destructure each array element into the nested
      # names: `|a, (b, c), d|`, `|(a, b)|`, nested `(b, (c, d))`, a named splat rest
      # `(b, *r)`, and an anonymous splat `(*)`. Works across every block-taking form.

      # each: paren param destructures the element
      [[1, [2, 3], 4]].each { |a, (b, c), d| p [a, b, c, d] }        # [1, 2, 3, 4]

      # a single fully-parenthesized param over each element
      [[1, 2], [3, 4]].each { |(a, b)| p [a, b] }                    # [1, 2] then [3, 4]

      # leading paren then a trailing plain param
      [[[1, 2], 3]].each { |(a, b), c| p [a, b, c] }                 # [1, 2, 3]

      # nested destructuring
      [[1, [2, [3, 4]]]].each { |a, (b, (c, d))| p [a, b, c, d] }    # [1, 2, 3, 4]

      # a named splat rest inside the destructure collects the tail
      [[1, [2, 3, 4]]].each { |a, (b, *r)| p [a, b, r] }             # [1, 2, [3, 4]]

      # an anonymous splat consumes-and-discards its slot
      [[1, 2, 3]].each { |a, (*), b| p [a, b] }                      # [1, 3]

      # map returns the block value with destructured params
      p([[1, 2], [3, 4]].map { |(a, b)| a + b })                     # [3, 7]

      # each_with_index with a destructured first param
      [[10, 20], [30, 40]].each_with_index { |(a, b), i| p [a, b, i] }

      # each_slice yields sub-arrays; a single |(lo, hi)| splits each slice
      p([1, 2, 3, 4].each_slice(2).map { |(lo, hi)| hi - lo })       # [1, 1]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [1, 2]
      [3, 4]
      [1, 2, 3]
      [1, 2, 3, 4]
      [1, 2, [3, 4]]
      [1, 3]
      [3, 7]
      [10, 20, 0]
      [30, 40, 1]
      [1, 1]
    OUT
  end

  it "block param distribution" do
    result = ze0(<<~'RUBY')
      def m(a)
        yield a
      end
      p(m([1, 2]) { |a, | a })
      p(m([1, 2]) { |a, *b, c, d| [a, b, c, d] })
      p(m([1, 2]) { |a=5, b=4, c=3| [a, b, c] })
      p(m([1, 2]) { |a=5, b, c, d| [a, b, c, d] })
      p(m([1]) { |a, b=5, c=6, d, e| [a, b, c, d, e] })
      p(m([1, 2]) { |a, b=5, c=6, d, e| [a, b, c, d, e] })
      p(m([1, 2, 3]) { |a, b=5, c=6, d, e| [a, b, c, d, e] })
      p(m([1, 2, 3, 4]) { |a, b=5, c=6, d, e| [a, b, c, d, e] })
      p(m([1, 2, 3, 4, 5]) { |a, b=5, c=6, d, e| [a, b, c, d, e] })
      p(m([1, 2, 3, 4, 5, 6]) { |a, b=5, c=6, d, e| [a, b, c, d, e] })
      p(m([1, 2, 3, 4, 5]) { |a, *b, c| [a, b, c] })
      p(m([1, 2, 3]) { |*a, b| [a, b] })
      def m2(x, y, z)
        yield x, y, z
      end
      p(m2(1, 2, 3) { |a, *b, c| [a, b, c] })
      p(m2(1, 2, 3) { |a, b=9, c| [a, b, c] })
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [1, [], 2, nil]
      [1, 2, 3]
      [5, 1, 2, nil]
      [1, 5, 6, nil, nil]
      [1, 5, 6, 2, nil]
      [1, 5, 6, 2, 3]
      [1, 2, 6, 3, 4]
      [1, 2, 3, 4, 5]
      [1, 2, 3, 4, 5]
      [1, [2, 3, 4], 5]
      [[1, 2], 3]
      [1, [2], 3]
      [1, 2, 3]
    OUT
  end

  it "block splat param iterators" do
    result = ze0(<<~'RUBY')
      # Block splat parameters through the specialized iterator lowerings: a
      # splat-only block wraps each yielded element whole (two-value yields pack
      # both); |x, *r| binds an empty rest for scalar elements. Unsupported
      # lowerings reject at compile time rather than binding nil.
      def m1(a) = a.map { |*x| x }
      p m1([1, 2])
      def m2(a) = a.map { |*x| x }
      p m2(["a", "b"])
      def m3(a) = a.map { |*x| x }
      p m3([1, :s])
      def s1(a) = a.select { |*x| x[0] > 1 }
      p s1([1, 2])
      def r1(a) = a.reject { |*x| x[0] > 1 }
      p r1([1, 2])
      def e1(a); acc = []; a.each { |*x| acc << x }; acc; end
      p e1([7, 8])
      def t1(n); acc = []; n.times { |*x| acc << x }; acc; end
      p t1(2)
      def mr(a) = a.map { |x, *r| [x, r] }
      p mr([1, 2])
      def ewi(a); acc = []; a.each_with_index { |*x| acc << x }; acc; end
      p ewi([9, 10])
      # A boxed (sp_RbVal) poly receiver -- `cond ? array : hash` -- reaches the poly
      # map fold, which previously bound only a required param and left `*x` empty
      # (nil elements). It now wraps the whole element into the rest array too.
      def pm(c); (c ? [1, 2, 3] : { a: 1 }).map { |*x| x[0] }; end
      p pm(true)
      # and stable when the poly value is rebuilt through the map across a loop
      def pl; r = [1, 2, 3]; 3.times { r = r.map { |*x| x[0] } }; r; end
      p pl
    RUBY

    _(result).must_answer <<~'OUT'
      [[1], [2]]
      [["a"], ["b"]]
      [[1], [:s]]
      [2]
      [1]
      [[7], [8]]
      [[0], [1]]
      [[1, []], [2, []]]
      [[9, 0], [10, 1]]
      [1, 2, 3]
      [1, 2, 3]
    OUT
  end

  it "block tail prelude inside" do
    result = ze0(<<~'RUBY')
      # A block emitter that renders its tail as an EXPRESSION must catch that
      # expression's statement-shaped setup itself: g_pre at that point is the buffer
      # for the whole enclosing line, so anything routed there runs OUTSIDE the
      # block. `h[k] += 1` puts its whole read-modify-write in the prelude and leaves
      # only the read inside -- under Mutex#synchronize that dropped the update out
      # of the critical section, and concurrent increments went missing.
      N = 3000

      def guarded(n)
        h = { "a" => 0 }
        l = Mutex.new
        q = Queue.new
        n.times { q << 1 }
        4.times { q << nil }
        ts = 4.times.map do
          Thread.new do
            loop do
              v = q.pop
              break if v.nil?
              l.synchronize { h["a"] += 1 }
            end
          end
        end
        ts.each(&:join)
        h["a"]
      end

      puts guarded(N)

      # do...end reaches the same emitter
      def guarded_do(n)
        h = { "b" => 0 }
        l = Mutex.new
        n.times { l.synchronize do h["b"] += 1 end }
        h["b"]
      end
      puts guarded_do(500)

      # File.open has the same shape: the setup would run before the file is opened
      path = "spinel_blocktail_#{Process.pid}.tmp"
      File.write(path, "xyz")
      acc = { "n" => 0 }
      r = File.open(path) { |f| acc["n"] += f.read.length }
      puts r
      puts acc["n"]
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      3000
      500
      3
      3
    OUT
  end

  it "block yield keyword param" do
    result = ze0(<<~'RUBY')
      # A yielded block binds keyword params by name from the yielded kwargs hash;
      # an omitted optional keyword takes its default.
      def kw; yield(a: 1, b: 2); end
      def kwd; yield(x: 5); end
      def mixed; yield(1, k: 9); end
      kw { |a:, b:| p a + b }
      kwd { |x:, y: 10| p [x, y] }
      mixed { |n, k:| p [n, k] }
    RUBY

    _(result).must_answer <<~'OUT'
      3
      [5, 10]
      [1, 9]
    OUT
  end

  it "block yield optional param" do
    result = ze0(<<~'RUBY')
      # A yielded block binds optional positional params to the yielded arg when
      # present, else to the declared default expression.
      def one; yield 5; end
      def two; yield 5, 99; end
      one { |a, b=10| p [a, b] }
      one { |a, b=10, c=20| p [a, b, c] }
      two { |a, b=10| p [a, b] }
      def with_arg(d); yield d; end
      with_arg(3) { |a, b=(a + 2)| p [a, b] }
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 10]
      [5, 10, 20]
      [5, 99]
      [3, 5]
    OUT
  end

  it "blocks" do
    result = ze0(<<~'RUBY')
      3.times do |i|
        puts i
      end
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      2
    OUT
  end

  it "captured block call value" do
    result = ze0(<<~'RUBY')
      # A nested proc literal can capture an enclosing method's &block (an
      # sp_Proc param) and call it, and the value flows back at the block's
      # real type. Covers the value carried through the proc-var indirection
      # (`p = proc { blk.call }; p.call`) for int / string / argument blocks,
      # at top level and inside an instance method.

      # top-level, int block
      def f_int(&blk)
        p = proc { blk.call }
        p.call
      end
      puts f_int { 7 }

      # top-level, string block: the value rides the int slot and reads back
      # as a string (typed through the p.call -> blk.call indirection).
      def f_str(&blk)
        p = proc { blk.call }
        p.call
      end
      puts f_str { "hi" }

      # top-level, block with an argument
      def f_arg(&blk)
        p = proc { blk.call(10) }
        p.call
      end
      puts f_arg { |x| x + 5 }

      # a plain proc local inside an instance method (no &block) is typed proc
      class Box
        def make
          p = proc { 42 }
          p.call
        end
      end
      puts Box.new.make

      # instance method capturing its &block through a proc local, string block
      class Runner
        def run(&blk)
          p = proc { blk.call }
          p.call
        end
      end
      puts Runner.new.run { "inst" }
    RUBY

    _(result).must_answer <<~'OUT'
      7
      hi
      15
      42
      inst
    OUT
  end

  it "case when lambda predicate" do
    result = ze0(<<~'RUBY')
      # case/when with lambda predicates: Proc#=== calls the lambda with the
      # scrutinee, so its parameter takes the scrutinee's type -- including a
      # Class-valued scrutinee that can't ride the integer proc-call ABI.

      class Story
      end

      class Comment
      end

      class W
        def self.go(x)
          case x.class
          when ->(b) { b == Story }
            "story"
          when ->(b) { b == Comment }
            "comment"
          else
            "other"
          end
        end
      end

      puts W.go(Story.new)
      puts W.go(Comment.new)
      puts W.go(42)

      # statement-position case, int scrutinee
      def f(n)
        case n
        when ->(v) { v > 10 }
          puts "big"
        when ->(v) { v.even? }
          puts "even"
        else
          puts "other"
        end
      end
      f(11)
      f(4)
      f(3)

      # a proc held in a variable still dispatches Proc#===
      big = ->(v) { v > 5 }
      case 7
      when big then puts "big7"
      else puts "no"
      end
      case 2
      when big then puts "big2"
      else puts "no2"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      story
      comment
      other
      big
      even
      other
      big7
      no2
    OUT
  end

  it "class defined inside a lambda registers" do
    result = ze0(<<~'RUBY')
      # A `class` written inside a lambda body defines its class where it is
      # written, exactly like one inside a block -- both run later, maybe never,
      # and the registration is a compile-time fact either way (the body still
      # EXECUTES only when the lambda runs).
      #
      # zeo's registration walk descended blocks but stopped at lambdas, so the
      # marker reached codegen with no site: "`class`/`module` in a position the
      # analyze walk doesn't register". `class Object` reopens inside lambdas
      # dominate that ledger bucket.
      handler = lambda do
        class BuiltInsideALambda
          def greeting
            "from inside"
          end
        end
      end

      handler.call
      puts BuiltInsideALambda.new.greeting

      arrow = -> {
        class Object
          def lambda_patched
            "patched"
          end
        end
      }
      arrow.call
      puts lambda_patched
    RUBY

    _(result).must_answer <<~'OUT'
      from inside
      patched
    OUT
  end

  it "closure capture float" do
    result = ze0(<<~'RUBY')
      # A closure that captures a float-typed outer variable: the capture rides a
      # native double cell, so reads, writes, and compound-assignment all work. (A
      # proc that also takes a float parameter is still rejected, since float proc
      # arguments ride the truncating int slot.)

      # mutate a captured float accumulator across several calls
      def running_total
        total = 0.0
        add_half = -> { total += 0.5 }
        add_half.call
        add_half.call
        add_half.call
        total
      end
      puts running_total

      # read-only capture of a float
      def scaled
        factor = 2.5
        scale = -> { factor * 10.0 }
        scale.call
      end
      puts scaled

      # capture mutated inside the proc, then read back in the enclosing scope
      def accumulate
        acc = 1.0
        bump = -> { acc *= 2.0 }
        bump.call
        bump.call
        acc
      end
      puts accumulate

      # int and float captures coexisting in one proc
      def mixed
        n = 0
        sum = 0.0
        step = -> { n += 1; sum += 1.5 }
        step.call
        step.call
        "#{n}/#{sum}"
      end
      puts mixed
    RUBY

    _(result).must_answer <<~'OUT'
      1.5
      25.0
      4.0
      2/3.0
    OUT
  end

  it "cmethod self receiver" do
    result = ze0(<<~'RUBY')
      class Keystore
        def self.maker
          1
        end
        def self.go
          self.maker
        end
      end
      puts Keystore.go
      class P157
        def self.base; "b"; end
      end
      class C157 < P157
        def self.go2
          self.base + "!"
        end
        def self.go3
          self.create! { |x| x * 2 }
        end
        def self.create!
          yield 21
        end
      end
      puts C157.go2
      p C157.go3
      class I157
        def val; 7; end
        def read; self.val + 1; end
      end
      p I157.new.read
    RUBY

    _(result).must_answer <<~'OUT'
      1
      b!
      42
      8
    OUT
  end

  it "combined optional rest post keyword keyword rest and block params all bind correctly" do
    result = ze0(<<~'RUBY')
      class Widget
        def build(a, b = 10, *rest, c, d: 5, **kw, &blk)
          puts a
          puts b
          puts rest
          puts c
          puts d
          puts kw[:e]
          puts blk.call
        end
      end
      Widget.new.build(1, 2, 3, 4, 5, d: 99, e: 100) { "block!" }
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      4
      5
      99
      100
      block!
    OUT
  end

  it "container typing compile gaps" do
    result = ze0(<<~'RUBY')
      # Three shapes that did not compile at all, each for its own reason.

      # A multiple-assignment target captured by a later block. The target lives in a
      # heap cell, and the assignment named `lv_<name>` -- a variable that was never
      # declared, with the cell sitting right beside it in the same function.
      def build
        [1, ["a", "b"], "tail"]
      end

      n, list, tail = build

      list.each do |s|
        p [n, s, tail]
      end

      # A parameter defaulting to an empty `{}`. With no key evidence it settled on
      # the symbol-keyed variant, and the body's String key was then written through
      # an sp_sym slot. Such a hash is created here rather than handed in, so
      # narrowing it converts nothing and reinterprets nobody.
      def flat(node, acc = {})
        node.each { |key, value| acc[key.to_s] = value }
        acc
      end

      p flat({ "a" => 1 })
      p flat({ "b" => 2, "c" => 3 })

      # A defaulted accumulator whose key is already right stays as it is
      def tally(words, acc = {})
        words.each { |w| acc[w] = (acc[w] || 0) + 1 }
        acc
      end

      p tally(["x", "y", "x"])

      # Hash#select / #reject whose block value is only known at run time -- here the
      # block calls a Proc held as the hash value. The predicate was emitted as
      # `!(value)`, and a boxed value is a struct, which does not compile.
      checks = { "big" => ->(v) { v > 1 }, "small" => ->(v) { v < 1 } }
      p checks.reject { |_k, check| check.call(3) }.keys
      p checks.select { |_k, check| check.call(3) }.keys

      # the same predicate with an ordinary boolean block still works
      nums = { "a" => 1, "b" => 5 }
      p nums.select { |_k, v| v > 2 }.keys
      p nums.reject { |_k, v| v > 2 }.keys
    RUBY

    _(result).must_answer <<~'OUT'
      [1, "a", "tail"]
      [1, "b", "tail"]
      {"a" => 1}
      {"b" => 2, "c" => 3}
      {"x" => 2, "y" => 1}
      ["small"]
      ["big"]
      ["b"]
      ["a"]
    OUT
  end

  it "curry compose" do
    result = ze0(<<~'RUBY')
      add001 = ->(a, b) { a + b }.curry
      c001 = add001[1] >> ->(x001) { x001 * 10 }
      p c001.call(4)

      add002 = ->(a, b) { a + b }.curry; p((add002[1] >> ->(x002) { x002 * 10 }).call(4))  # Ruby: 50
      c003 = ->(a) { a + 1 }.curry; p((c003 >> ->(x003) { x003 * 10 }).call(4))            # Ruby: 50
      c004 = ->(a) { a + 1 }.curry; p((c004 << ->(x004) { x004 * 10 }).call(4))            # Ruby: 41

      add005 = ->(a, b) { a + b }.curry
      p add005[1][2]                                                   # => 3
      p add005[1].call(2)                                              # => 3
      c006 = ->(x006) { x006 + 1 } >> ->(x007) { x007 * 10 }
      p c006.call(4)                                                   # => 50
      p((->(x008) { x008 + 1 } >> ->(x009) { x009 * 10 }).call(4))     # => 50

      mul = ->(a, b) { a * b }.curry
      inc = ->(x) { x + 1 }
      p((inc >> mul[3]).call(4))
      p((mul[2] << inc).call(4))
      p(mul[2][5])
    RUBY

    _(result).must_answer <<~'OUT'
      50
      50
      50
      41
      3
      3
      50
      50
      15
      10
      10
    OUT
  end

  it "curry constant lambda" do
    result = ze0(<<~'RUBY')
      # `curry` walks the chain back to the base proc to learn its arity, which is
      # how it knows which application completes it. The walk resolved a lambda held
      # in a LOCAL and not one held in a CONSTANT, so a curried constant never
      # realized: every application answered another Proc (#4017).
      F = ->(a, b) { a + b }
      p F.curry[1][2]
      p F.curry.(1).(2)
      p F.curry[1].call(2)
      p F.curry[1, 2]

      # a local copied from the constant resolves through it
      G = F
      p G.curry[1][2]
      g = F
      p g.curry[1][2]

      # the argument type is irrelevant, and so is the arity
      R = ->(r, v) { r.cover?(v) }
      p R.curry[(1..9)][5]
      S = ->(a, b, c) { a + b + c }
      p S.curry[1][2][3]
      p S.curry[1, 2][3]
      T = ->(a) { a * 2 }
      p T.curry[21]

      # a partial application is still a Proc
      p F.curry[1].class
      p F.curry.class

      # and the local-held lambda keeps working
      f = ->(a, b) { a + b }
      p f.curry[1][2]
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      3
      3
      3
      3
      true
      6
      6
      42
      Proc
      Proc
      3
    OUT
  end

  it "def in class new block yields" do
    result = ze0(<<~'RUBY')
      # A `def` in expression position (a `Class.new` block) threads its
      # block too.

      k = Class.new do
        def run
          yield 10
        end
      end
      puts k.new.run { |x| x * 2 }
    RUBY

    _(result).must_answer "20\n"
  end

  it "default arg find block" do
    result = ze0(<<~'RUBY')
      # find / detect { |x| cond } used as a parameter default. The default is
      # evaluated at the call site, where the block's local variable has no top-level
      # declaration -- previously this emitted C referencing an undeclared `lv_n`.
      A = [1, 2, 3, 4]

      def kw(x: A.find { |n| n > 2 })
        x
      end
      p kw           # 3
      p kw(x: 99)    # 99 (default not evaluated when the arg is given)
      p kw           # 3 (a second defaulting call in the same scope)

      def kwd(y: A.detect { |n| n > 10 })
        y
      end
      p kwd          # nil (no element matches)

      def opt(z = A.find { |n| n == 4 })
        z
      end
      p opt          # 4
    RUBY

    _(result).must_answer <<~'OUT'
      3
      99
      3
      nil
      4
    OUT
  end

  it "defined yield no block" do
    result = ze0(<<~'RUBY')
      # defined?(yield) must reflect whether the current method actually received a
      # block: nil when called without one, "yield" when a block is present.
      def f
        defined?(yield)
      end
      p f                 # no block -> nil
      p f { 1 }           # block    -> "yield"

      # routed through a helper that conditionally yields, to exercise the lowered
      # __yblk__ runtime path rather than a fully-inlined block.
      def g(&blk)
        defined?(yield)
      end
      p g                 # nil
      p g { 42 }          # "yield"
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "yield"
      nil
      "yield"
    OUT
  end

  it "defined yield reflects block presence at runtime" do
    result = ze0(<<~'RUBY')
      # defined?(yield) is nil without a block, "yield" with one.

      def f
        defined?(yield)
      end
      p f
      p f { 1 }
      def g(&blk)
        defined?(yield)
      end
      p g
      p g { 42 }
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "yield"
      nil
      "yield"
    OUT
  end

  it "derived proc identity" do
    result = ze0(<<~'RUBY', path: "lang/blocks/derived_proc_identity.rb")
      # Two kinds of proc that are DERIVED from something else keep a trace of what
      # they came from, and zeo's do not.
      #
      # 1. `method(:m).to_proc` reports the METHOD's `source_location`; zeo answers
      #    nil, the C-level-Proc answer, because the location does not travel from
      #    the Method object into the proc it becomes.
      #
      # 2. `:sym.to_proc` inspects as `#<Proc:0xADDR(&:sym) (lambda)>` -- the symbol
      #    is named right in the identity, with no space before it. zeo prints the
      #    plain locationless form, so a table of symbol-derived callbacks is again
      #    a column of identical strings, which is what
      #    `tests/proc_inspect_identity.rb` fixed for ordinary blocks.
      #
      # A block written in the source now carries both (that file is the control
      # below), so what is missing is only the derived cases: the proc is built by a
      # runtime row, which has nowhere to put either fact.

      def norm(s) = s.sub(/0x\h+/, "0xADDR").sub(%r{[^ ]*/}, "")

      def target = :body
      mp = method(:target).to_proc
      p mp.source_location&.last
      p mp.lambda?

      sp = :upcase.to_proc
      puts norm(sp.inspect)
      p sp.source_location
      p sp.call("ok")

      # An ordinary block carries both -- already correct.
      pr = proc { }
      p pr.source_location&.last
      puts norm(pr.inspect)
    RUBY

    _(result).must_answer <<~'OUT'
      20
      true
      #<Proc:0xADDR(&:upcase) (lambda)>
      nil
      "OK"
      31
      #<Proc:0xADDR derived_proc_identity.rb:31>
    OUT
  end

  it "destructured names are capturable by escaping blocks" do
    result = ze0(<<~'RUBY')
      # A destructured name is an ordinary local: an escaping block captures it by
      # reference, so a write inside the block is visible after it returns. This
      # regressed once already -- `captures::own_param_names` kept its own copy of
      # the param-name walk and didn't know about destructures, so the name was
      # classified as a block-own local and silently read `nil`.

      def capture((a, b))
        bump = -> { a += 10 }
        bump.call
        [a, b]
      end
      p capture([1, 2])

      def collect((x, y))
        out = []
        [1, 2].each { |i| out << (x * i + y) }
        out
      end
      p collect([10, 1])
    RUBY

    _(result).must_answer <<~'OUT'
      [11, 2]
      [11, 21]
    OUT
  end

  it "empty block body iterators" do
    result = ze0(<<~'RUBY')
      # `{ }` and `{ nil }` are the same block, and CRuby answers accordingly. The
      # iterator arms each read the block body's TAIL to type their result, and most
      # of them declined outright when there was none -- so the call fell through to
      # the unresolved-call gate and reported the METHOD as undefined, which is the
      # one thing it is not (#4006):
      #
      #   p [].filter_map{}   # undefined method 'filter_map' for an instance of Array
      #
      # An empty body now carries the nil it means, once, rather than a dozen arms
      # each special-casing it.
      p [].filter_map {}
      p [1, 2].filter_map {}
      p [1, 2].select {}
      p [1, 2].reject {}
      p [1, 2].find {}
      p [1, 2].detect {}
      p [1, 2].flat_map {}
      p [1, 2].group_by {}
      p [1, 2].partition {}
      p [1, 2].take_while {}
      p [1, 2].drop_while {}
      p [1, 2].map {}
      p [1, 2].each {}
      p [1, 2].each_with_index {}
      p [1, 2].each_with_object([]) {}
      p [1, 2].count {}
      p [1, 2].all? {}
      p [1, 2].any? {}
      p [1, 2].none? {}

      # a nil body is a VALUE in a predicate slot, not the absence of one: `void _tN`
      # is not a declaration, so `select { nil }` never compiled either
      p [1, 2].select { nil }
      p [1, 2].reject { nil }
      p [1, 2].map { nil }
      p [1, 2].count { nil }

      # sum accumulates BOXED here: the answer is the init for an empty receiver and
      # a TypeError for a non-empty one, never nil -- typing it nil folded the call
      # away and printed "nil" for `[].sum {}`
      p [].sum {}
      begin
        p [1].sum {}
      rescue TypeError => e
        p e.class
      end

      # the same through other receivers
      p({ a: 1 }.filter_map {})
      p({ a: 1 }.group_by {})
      p (1..3).filter_map {}
      p (1..3).select {}
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      []
      [1, 2]
      nil
      nil
      [nil, nil]
      {nil => [1, 2]}
      [[], [1, 2]]
      []
      [1, 2]
      [nil, nil]
      [1, 2]
      [1, 2]
      []
      0
      false
      false
      true
      []
      [1, 2]
      [nil, nil]
      0
      0
      TypeError
      []
      {nil => [[:a, 1]]}
      []
      []
    OUT
  end

  it "empty block param shadow" do
    result = ze0(<<~'RUBY')
      # A block with an EMPTY body still binds its parameters, so a parameter that
      # shadows an outer local still needs its own slot. The rename pass skipped such
      # a block outright -- there is nothing inside it to rewrite -- and the two names
      # then shared one C slot, which took the inner block's type while the outer
      # block kept assigning its own (#4027):
      #
      #   error: assigning to 'sp_PolyArray *' from incompatible type 'sp_RbVal'

      # the report's shape: the inner parameter is an array, the outer one a poly
      # element of the flat_map source
      [].flat_map do |a|
        [].map{}.tap do |a|
        end
      end
      p [1, 2].flat_map { |a| [3, 4].map { |x| x }.tap { |a| }.size.times.to_a }

      # an empty-bodied block whose parameter shadows an outer local of another type
      s = "outer"
      [7].each do |s|
      end
      p s
      n = 5
      %w[a b].each_with_index do |n, i|
      end
      p n

      # the same for a rest parameter and for a block-local, which are renamed on the
      # same pass
      r = 1
      [[8, 9]].each do |*r|
      end
      p r
      q = "keep"
      [1].each do |x; q|
      end
      p q

      # the empty block's own value is still nil, and tap still answers its receiver
      p([1].each { |z| })
      p([5, 6].tap { |z| })
      p([1, 2].map { |z| })
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, 0, 1]
      "outer"
      5
      1
      "keep"
      [1]
      [5, 6]
      [nil, nil]
    OUT
  end

  it "external singleton def yields its call site block" do
    result = ze0(<<~'RUBY')
      obj = Object.new
      def obj.greet
        yield "world"
      end
      puts obj.greet { |x| "hello #{x}" }
      def obj.maybe
        block_given? ? yield(5) : "none"
      end
      puts obj.maybe
      puts obj.maybe { |n| n * 100 }
    RUBY

    _(result).must_answer <<~'OUT'
      hello world
      none
      500
    OUT
  end

  it "forward args block" do
    result = ze0(<<~'RUBY')
      # `...` forwards a block as well as positional/keyword args. The forwarder is a
      # real function, so a literal block is redirected straight to the (yielding or
      # &block) target it forwards to, with the call-site args coming along.

      def y_target(a, b)
        yield(a + b)
      end
      def fwd(...)
        y_target(...)
      end
      puts(fwd(3, 4) { |s| s * 2 })          # 14

      # Chained forwarders, block threaded to the final yielder.
      def g(a)
        yield(a * 10)
      end
      def f(...)
        g(...)
      end
      def e(...)
        f(...)
      end
      puts(e(5) { |x| x + 1 })               # 51

      # Forward to a target with an explicit &block param.
      def block_target(a, &blk)
        blk.call(a) + blk.call(a)
      end
      def fwd_bt(...)
        block_target(...)
      end
      puts(fwd_bt(7) { |n| n * n })          # 98

      # Instance-method forwarding with a block.
      class C
        def base(a)
          yield(a)
        end
        def relay(...)
          base(...)
        end
      end
      puts(C.new.relay(9) { |v| v - 3 })     # 6

      # Forward positional + keyword args together with a block.
      def kw_target(a, mult:)
        yield(a * mult)
      end
      def fwd_kw(...)
        kw_target(...)
      end
      puts(fwd_kw(3, mult: 4) { |r| r + 100 })   # 112
    RUBY

    _(result).must_answer <<~'OUT'
      14
      51
      98
      6
      112
    OUT
  end

  it "forwarded block same name callee" do
    result = ze0(<<~'RUBY')
      # Several methods share the forwarded name; the one that KEEPS the block
      # decides whether the forwarder's captures need cells.
      class Decoy
        def store(&b)
          b.call
        end
      end

      class Holder
        def store(&b)
          @proc = b
        end

        def run
          @proc.call
        end
      end

      def forward(h, &b)
        h.store(&b)
      end

      h = Holder.new
      n = 0
      forward(h) { n += 1 }
      3.times { h.run }
      p n

      # the decoy still works on its own
      d = Decoy.new
      m = 0
      forward(d) { m += 10 }
      p m

      # and the order the classes are defined in must not matter
      class Later
        def keep(&b)
          @b = b
        end

        def fire
          @b.call
        end
      end

      def fwd2(o, &b)
        o.keep(&b)
      end

      k = 0
      l = Later.new
      fwd2(l) { k += 2 }
      2.times { l.fire }
      p k
    RUBY

    _(result).must_answer <<~'OUT'
      3
      10
      4
    OUT
  end

  it "i920" do
    result = ze0(<<~'RUBY')
      f = -> (x) { x * 2 }
      g = -> (x) { x + 1 }
      puts (f << g).call(3)
      puts (f >> g).call(3)

      p1 = proc { |x| x * 2 }
      p2 = proc { |x| x + 1 }
      puts (p1 << p2).call(3)
      puts (p1 >> p2).call(3)
    RUBY

    _(result).must_answer <<~'OUT'
      8
      7
      8
      7
    OUT
  end

  it "initialize block param" do
    result = ze0(<<~'RUBY')
      # An explicit `&blk` block parameter on initialize is threaded through .new:
      # the constructor accepts the block and forwards it, so a stored block can be
      # called later.
      class Widget
        def initialize(&blk)
          @cb = blk
        end
        def fire = @cb.call(10)
      end
      puts Widget.new { |x| x * 3 }.fire

      # block combined with a positional argument
      class Handler
        def initialize(name, &cb)
          @name = name
          @cb = cb
        end
        def run(x) = "#{@name}: #{@cb.call(x)}"
      end
      puts Handler.new("double") { |n| n * 2 }.run(21)

      # optional block: absent -> nil ivar
      class Maybe
        def initialize(&blk)
          @blk = blk
        end
        def has? = !@blk.nil?
      end
      puts Maybe.new { }.has?
      puts Maybe.new.has?
    RUBY

    _(result).must_answer <<~'OUT'
      30
      double: 42
      true
      false
    OUT
  end

  it "initialize yield" do
    result = ze0(<<~'RUBY')
      # A `yield` / `block_given?` inside `initialize` must run the constructor body
      # (and drive the block when one is passed), for both heap and value-type classes.
      #
      # The emitted constructor sp_X_new skips a yielding initialize (a yielding method
      # is normally realized by inlining at its call sites, but new->initialize is a
      # bespoke path). With no block at the call site, nothing inlined the body either,
      # so every `@ivar = ...` in initialize vanished and the object came back with all
      # ivars nil -- and a later method call on an ivar-held object segfaulted.
      #
      # Fix: inline the yielding initialize body at the construction site even when no
      # block is given (block_given? folds to false, a guarded yield is dead code), and
      # make that inline value-type aware (sp_X by value + "." deref, vs sp_X * + "->").

      # 1. Heap class, constructed WITHOUT a block: ivars must be set (the gap).
      class Grid
        attr_reader :width, :height
        def initialize(w, h = 10)
          @width = w
          @height = h
          yield self if block_given?
        end
      end
      g = Grid.new(4)
      p g.width                          #=> 4
      p g.height                         #=> 10

      # 2. Heap class, constructed WITH a block: the block runs and sees self.
      seen = nil
      g2 = Grid.new(5) { |gg| seen = gg.width }
      p g2.width                         #=> 5
      p seen                             #=> 5

      # 3. block_given? false path leaves the guarded yield unreached.
      g3 = Grid.new(7, 8)
      p [g3.width, g3.height]            #=> [7, 8]

      # 4. Value-type class with a yielding initialize, WITH a block.
      class Vec
        attr_reader :x, :y
        def initialize(x, y)
          @x = x
          @y = y
          yield self if block_given?
        end
      end
      sum = 0
      v = Vec.new(3, 4) { |vv| sum = vv.x + vv.y }
      p [v.x, v.y]                       #=> [3, 4]
      p sum                              #=> 7

      # 5. Value-type class constructed WITHOUT a block.
      v2 = Vec.new(1, 2)
      p [v2.x, v2.y]                     #=> [1, 2]

      # 6. A method call on an ivar-held constructed object (the segfault case).
      class Holder
        def initialize(n)
          @grid = Grid.new(n)
          yield if block_given?
        end
        def grid_width = @grid.width
      end
      p Holder.new(9).grid_width         #=> 9

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      4
      10
      5
      5
      [7, 8]
      [3, 4]
      7
      [1, 2]
      9
      done
    OUT
  end

  it "lambda call dot call and bracket syntax" do
    result = ze0(<<~'RUBY')
      add = ->(x, y) { x + y }
      puts add.call(3, 4)
      puts add.(3, 4)
      puts add[3, 4]

      square = lambda { |x| x * x }
      puts square.call(5)

      incr = -> (n = 1) { n + 1 }
      puts incr.call
      puts incr.call(10)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      7
      7
      25
      2
      11
    OUT
  end

  it "lambda capturing block param" do
    result = ze0(<<~'RUBY')
      # A lambda's required parameters are typed from the call sites the analysis can
      # see, and fall back to Integer when it sees none. That fallback is only safe
      # for a lambda it can enumerate the callers of, so one that ESCAPES widens to
      # poly instead -- including one that is a block's TAIL VALUE, which a collecting
      # iterator boxes into its result array.
      #
      # desugar_block_capture_wrap rewrites a block whose parameter is captured into
      # `->(__cap){ <body> }.call(param)`, so the block's tail becomes that call and
      # the literal sits one level in. Reading the block's tail alone found the call,
      # never marked the literal, and its parameter took the Integer default -- so the
      # Proc read back out of the array bound an address-shaped number (#4064).
      matchers = ["alpha"].map { |word| ->(line) { line.include?(word) } }
      p matchers[0].call("an alpha line")

      pairs = ["alpha"].map { |word| ->(line) { [line, word] } }
      p pairs[0].call("a line")

      # the same shape without map in it: a method that yields and returns the value
      def first_of(list)
        list.each { |k| return yield(k) }
      end
      f = first_of(["beta"]) { |word| ->(line) { line.include?(word) } }
      p f.call("a beta line")
      p f.call("nothing here")

      # capturing a block-local rather than the parameter still works
      locals = ["gamma"].map { |word| w = "#{word}"; ->(line) { line.include?(w) } }
      p locals[0].call("a gamma line")

      # each closure keeps its OWN copy of the captured parameter
      all = %w[a b c].map { |ch| ->(s) { s + ch } }
      p all.map { |l| l.call("x") }
    RUBY

    _(result).must_answer <<~'OUT'
      true
      ["a line", "alpha"]
      true
      false
      true
      ["xa", "xb", "xc"]
    OUT
  end

  it "lambda escapes through constant" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A Holder holds a lambda that closed over the Holder.
      # At exit: cycle leak: 2 objects (Holder x1, Proc x1)
      # A lambda held in a constant (or an ivar) and passed to a method that calls
      # it escapes: its parameters ride the boxed ABI. The escape scan followed only
      # a local, so the literal kept the no-evidence int default and an Array
      # argument was read as an integer -- every call answered 0 (#3968).
      A = ->(x) { x[0] }
      B = ->(_x) { 0 }
      def run(h) = h.call([9])
      p run(A)
      p run(B)

      C = ->(a, b) { a[0] + b[0] }
      D = ->(a, b) { a[1] + b[1] }
      def run2(h) = h.call([1, 2], [3, 4])
      p run2(C)
      p run2(D)

      def manhattan(a, b) = ((a[0] - b[0]).abs + (a[1] - b[1]).abs).to_f
      ASTAR = ->(a, b) { manhattan(a, b) }
      DIJKSTRA = ->(_a, _b) { 0.0 }
      def run3(h) = h.call([0, 0], [3, 4])
      p run3(ASTAR)
      p run3(DIJKSTRA)

      # an ivar-held lambda passed on
      class Holder
        def initialize
          @f = ->(x) { x[1] }
        end
        def use(g) = g.call([7, 8])
        def go = use(@f)
      end
      p Holder.new.go

      # a directly-called constant lambda keeps its precise typing
      E = ->(n) { n * 2 }
      p E.call(21)
    RUBY

    _(result).must_answer <<~'OUT'
      9
      0
      4
      6
      7.0
      0.0
      8
      42
    OUT
  end

  it "lambda keyword call" do
    result = ze0(<<~'RUBY')
      l = ->(k: 5) { k }
      p(l.call(k: 9))
      p(l.call)
      p(->(a, k:) { [a, k] }.call(1, k: 2))
    RUBY

    _(result).must_answer <<~'OUT'
      9
      5
      [1, 2]
    OUT
  end

  it "lambda nested emit" do
    result = ze0(<<~'RUBY')
      # Nested proc literals: the emitter must not splice the inner _proc_ function
      # into the middle of the outer one (both built into the same buffer before).
      f = -> { -> { 41 }.call + 1 }
      puts f.call
      g = proc { -> { "in" }.call + "ner" }
      puts g.call
    RUBY

    _(result).must_answer <<~'OUT'
      42
      inner
    OUT
  end

  it "lowered block given" do
    result = ze0(<<~'RUBY')
      # A self-recursive yielding method is emitted as a real C function (the block
      # becomes a proc parameter) rather than inlined. `block_given?` inside it must
      # reflect whether a block was actually passed -- true on the block-bearing call,
      # false when invoked without one -- not a constant.
      def gen(n)
        return -1 unless block_given?
        yield n
        gen(n - 1) { |x| yield x } if n > 1
        n
      end

      gen(3) { |v| puts v }   # block present: yields 3, 2, 1
      puts gen(5)             # no block: returns -1
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      1
      -1
    OUT
  end

  it "massign captured proc cell" do
    result = ze0(<<~'RUBY')
      def make
        p = proc { "orig" }
        esc = lambda { p.call }   # captures p by reference -> p lives in a heap cell
        q = proc { "new" }
        p, n = q, 5               # multi-assign into the captured proc local
        puts n
        esc
      end
      e = make
      puts e.call                 # reads the reassigned p through the closure
    RUBY

    _(result).must_answer <<~'OUT'
      5
      new
    OUT
  end

  it "massign proc cell nil" do
    result = ze0(<<~'RUBY')
      # Multi-assign of nil (a boxed sp_RbVal temp) into a captured TY_PROC cell must
      # launder to NULL, not cast the sp_RbVal struct to (mrb_int) (invalid C).
      def make
        p = proc { "orig" }
        esc = lambda { p ? p.call : "was nil" }   # captures p -> heap cell
        p, n = nil, 5                             # nil into the captured proc cell
        puts n
        esc
      end
      e = make
      puts e.call
    RUBY

    _(result).must_answer <<~'OUT'
      5
      was nil
    OUT
  end

  it "module nested reopen yield" do
    result = ze0(<<~'RUBY')
      module NS
        class Base
          def self.ping
            "ping"
          end
        end
      end

      module NS
        class Base
          def self.transaction
            yield
          end
          def self.compute
            yield
          end
        end
      end

      puts NS::Base.ping
      puts(NS::Base.transaction { "inside" })
      v = NS::Base.transaction { "assigned" }
      puts v
      n = NS::Base.compute { 41 + 1 }
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      ping
      inside
      assigned
      42
    OUT
  end

  it "named block parameter can be called explicitly" do
    result = ze0(<<~'RUBY')
      # A `&block` parameter is real syntax now (a rejection this test
      # used to check for was lifted).

      class Foo
        def bar(&blk)
          blk.call(5)
        end
      end
      puts Foo.new.bar { |x| x * 2 }
    RUBY

    _(result).must_answer "10\n"
  end

  it "new with block" do
    result = ze0(<<~'RUBY')
      # A literal block passed to `.new` is forwarded to `initialize`, so
      # `yield`/`block_given?` inside it see the block.

      class Builder
        attr_reader :items
        def initialize
          @items = []
          yield self if block_given?
        end
        def add(x) = @items << x
      end

      # The block runs during construction and captures an outer local.
      label = "n"
      b = Builder.new do |bld|
        3.times { |i| bld.add("#{label}#{i}") }
      end
      p b.items

      # No block: block_given? is false.
      p Builder.new.items

      # Struct with a custom initialize can `super` into the member setter and yield.
      Point = Struct.new(:x, :y) do
        def initialize(x, y)
          super(x * 2, y * 2)
          yield self if block_given?
        end
      end
      pt = Point.new(3, 4) { |p| puts "built (#{p.x}, #{p.y})" }
      p [pt.x, pt.y]

      # Data.define custom initialize forwarding through super.
      Measure = Data.define(:n) do
        def initialize(n:)
          super(n: n * 10)
        end
      end
      p Measure.new(n: 4).n
    RUBY

    _(result).must_answer <<~'OUT'
      ["n0", "n1", "n2"]
      []
      built (6, 8)
      [6, 8]
      40
    OUT
  end

  it "param referenced only inside an escaping block is captured" do
    result = ze0(<<~'RUBY')
      # The parameter-capture fix: `n` (a method param) appears ONLY inside
      # the escaping block -- previously misclassified as a block-own local
      # and silently re-declared Nil. Oracle: 11, 12.

      class Pair
        def each(&blk)
          blk.call(1)
          blk.call(2)
          self
        end
        def add_all(n)
          each { |x| puts x + n }
        end
        def mapped(&blk)
          result = []
          each { |x| result << blk.call(x) }
          result
        end
      end
      Pair.new.add_all(10)
      puts Pair.new.mapped { |x| x * 3 }.length
    RUBY

    _(result).must_answer <<~'OUT'
      11
      12
      2
    OUT
  end

  it "parenthesized block params destructure their slot" do
    result = ze0(<<~'RUBY')
      # A parenthesized parameter destructures the value bound to its slot --
      # `|(a, b)|`, mixed with plain params, and nested arbitrarily deep. Lowered
      # as the multi-assignment it is (see `hir::Params::destructures`).

      [[1, 2], [3, 4]].each { |(a, b)| p [a, b] }
      [[1, [2, 3], 4]].each { |a, (b, c), d| p [a, b, c, d] }
      [[[1, 2], 3]].each { |(a, b), c| p [a, b, c] }
      [[1, [2, [3, 4]]]].each { |a, (b, (c, d))| p [a, b, c, d] }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [3, 4]
      [1, 2, 3, 4]
      [1, 2, 3]
      [1, 2, 3, 4]
    OUT
  end

  it "positional install still beats a block installed accessor" do
    result = ze0(<<~'RUBY')
      # ...and the pass's own job is untouched: a block-installed accessor still
      # loses to the `def` written below it, and so does a macro a class method
      # expands. A fix that made `dyn_defs` refuse more than it should would show
      # up here and nowhere else.

      class Blocked
        [:y].each { |a| attr_writer(a) }
        def y=(v)
          @y = [v, v]
        end
        attr_reader :y
      end
      class Macro
        def self.make(n) = attr_writer(n)
        make :z
        def z=(v)
          @z = [v, v]
        end
        attr_reader :z
      end
      b = Blocked.new
      b.y = 1
      p b.y
      m = Macro.new
      m.z = 2
      p m.z
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1]
      [2, 2]
    OUT
  end

  it "proc" do
    result = ze0(<<~'RUBY')
      # Test &block, Proc.new, proc, Proc#call

      # &block parameter — receive block as Proc
      def apply(x, &block)
        block.call(x)
      end

      puts apply(5) { |n| n * 2 }  # 10

      # Store block in variable
      def make_doubler
        proc { |n| n * 2 }
      end

      doubler = make_doubler
      puts doubler.call(7)  # 14

      # Proc.new
      adder = Proc.new { |n| n + 10 }
      puts adder.call(5)  # 15

      # Pass proc to method
      def transform(x, fn)
        fn.call(x)
      end

      puts transform(3, doubler)  # 6

      # Method with &block forwarding
      def with_logging(x, &blk)
        puts "before"
        result = blk.call(x)
        puts "after"
        result
      end

      with_logging(42) do |n|
        puts n
      end
      # before, 42, after

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      10
      14
      15
      6
      before
      42
      after
      done
    OUT
  end

  it "proc arg channel released" do
    result = ze0(<<~'RUBY', env: {"ZEO_GC" => "1"})
      # This golden reads `GC.stat[:heap_live_slots]`, which only the allocation
      # registry can answer, and only `ZEO_GC=1` arms it. CRuby always tracks, so the
      # oracle needs no counterpart.

      # The boxed-argument and result channels a proc call publishes through were GC
      # roots nothing cleared, so the last call's arguments and result stayed
      # reachable for the rest of the program. The callee reads them out and drops
      # the references now.
      #
      # `GC.stat[:heap_live_slots]` is what makes that measurable rather than merely
      # asserted, and it is why this golden carries a `.gc` sidecar: the count comes
      # from the allocation registry, which only `ZEO_GC=1` arms. Without it the key
      # is absent, because a heap with no record of an allocation cannot answer
      # truthfully and inventing a number is worse than the `nil` a caller can read
      # as "this heap cannot say".
      #
      # A direct liveness test would not be portable in the other direction: zeo's
      # finalizers fire promptly where CRuby's have not run yet, so the honest
      # version of THAT test fails on ruby. A slot count is the portable spelling of
      # the same property -- a dropped structure stops being live.
      #
      # Spinel's original read `GC.stat["bytes"]`. CRuby's `GC.stat` is keyed by
      # SYMBOL and has no "bytes" statistic, so a String subscript is nil there and
      # the comparison raises `NoMethodError` on ruby too.
      def build(len)
        n = len.to_i
        a = []
        i = 0
        while i < n
          a << [i, i]
          i += 1
        end
        a
      end

      sink = proc { |x| x.size }

      def feed(s)
        big = build(120_000)
        s.call(big) == 120_000
      end

      base = GC.stat[:heap_live_slots]
      p feed(sink)
      GC.start
      GC.start
      # the argument is gone, not merely unreferenced by the program
      p GC.stat[:heap_live_slots] < base + 100_000

      # the result channel holds its value only until the next call, not forever
      maker = proc { |n| build(n) }
      def take(m)
        m.call(60_000).size == 60_000
      end
      b2 = GC.stat[:heap_live_slots]
      p take(maker)
      noop = proc { |z| z }
      p noop.call(1) == 1
      GC.start
      GC.start
      p GC.stat[:heap_live_slots] < b2 + 100_000

      # the arguments themselves still arrive intact
      two = proc { |a, b| [a, b] }
      p two.call("x", [1, 2])
      rest = proc { |*a| a }
      p rest.call(1, "b", :c)
      nested = proc { |v| two.call(v, v) }
      p nested.call(7)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      ["x", [1, 2]]
      [1, "b", :c]
      [7, 7]
    OUT
  end

  it "proc arg object" do
    result = ze0(<<~'RUBY')
      class Wrapper
        def initialize(val)
          @val = val
          @extra = []  # force heap allocation (pointer ivar)
        end

        def value
          @val
        end
      end

      def pass(&block)
        w = Wrapper.new(77)
        block.call(w)
      end

      pass { |w| puts w.value }
    RUBY

    _(result).must_answer "77\n"
  end

  it "proc block param call" do
    result = ze0(<<~'RUBY')
      # A proc's own &block param (#2648): the caller's literal block rides the
      # _sp_proc_blk side-channel into the callee's prologue; calling without a
      # block binds nil.
      p(->(&b) { b.call(9) }.call { |x| x + 1 })
      f = ->(&b) { b.nil? ? "none" : b.call(1) }
      p f.call
      p(f.call { |x| x * 100 })
      g = ->(a, &b) { a + b.call(a) }
      p(g.call(5) { |x| x * 2 })
      # the passed block captures an enclosing local (lifted like any escaping block)
      base = 50
      p(->(&b) { b.call(3) }.call { |x| base + x })
    RUBY

    _(result).must_answer <<~'OUT'
      10
      "none"
      100
      15
      53
    OUT
  end

  it "proc call splat" do
    result = ze0(<<~'RUBY')
      pr = ->(a, b, c) { a + b + c }
      args = [1, 2, 3]
      p(pr.call(*args))
      p(pr[*args])
      p(pr.(*args))
      p(pr.yield(*args))
      s = ->(x, y) { "#{x}-#{y}" }
      p(s.call(*["a", "b"]))
      add = proc { |a, b| a + b }
      p(add.call(*[4, 5]))
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
      6
      6
      "a-b"
      9
    OUT
  end

  it "proc called from two scopes" do
    result = ze0(<<~'RUBY')
      # A proc handed to a method is called from there as well as from the scope
      # that made it. The two sites pass different types, so the params cannot be
      # pinned to the visible one.
      sink = proc { |x| x.size }

      def feed(s)
        rows = [[1], [2], [3]]
        s.call(rows)
      end

      p feed(sink)
      p sink.call([1, 2])
      p sink.call("abcd")

      double = proc { |n| n * 2 }

      def apply(f, v)
        f.call(v)
      end

      p apply(double, 21)
      p double.call(3)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      4
      42
      6
    OUT
  end

  it "proc capture enclosing lambda" do
    result = ze0(<<~'RUBY')
      # A proc closing over an ENCLOSING lambda/proc's variables (#2648): the
      # enclosing proc's frame owns the variable, so its prologue materializes the
      # heap cell and the inner proc captures the cell pointer. The proc's own **kw
      # param also binds (the whole trailing kwargs hash).
      g = ->(x) { ->{ x } }
      p(g.call(5).call)
      p(g.call(7).call)
      # counter factory: reassignment through the cell, one cell per outer call
      make = ->(start) { ->{ start += 1 } }
      c1 = make.call(10)
      p c1.call
      p c1.call
      c2 = make.call(100)
      p c2.call
      p c1.call
      # string capture and multi-level
      tag = ->(prefix) { ->(x) { "#{prefix}:#{x}" } }
      p tag.call("id").call(5)
      adder = ->(a) { ->(b) { a + b } }
      p adder.call(3).call(4)
      # own **kw param
      p(->(a, **kw) { [a, kw] }.call(1, x: 2))
      p(->(a, **kw) { [a, kw] }.call(1))
      opts = ->(a, **kw) { kw.length + a }
      p opts.call(1, x: 2, y: 3)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      7
      11
      12
      101
      13
      "id:5"
      7
      [1, {x: 2}]
      [1, {}]
      3
    OUT
  end

  it "proc capture nested frame" do
    result = ze0(<<~'RUBY')
      [1].each do |k|
        values = [2]
        f = ->(e) { values.include?(k) }
        p f.call(0)
      end

      [3].each do |k|
        values = [3]
        f = ->(e) { values.include?(k) }
        p f.call(0)
      end

      g = lambda {
        names = ["a"]
        f = ->(e) { names.include?(e) }
        p f.call("a")
        p f.call("b")
      }
      g.call

      %w[x y].each_with_index do |s, i|
        seen = []
        add = -> { seen << "#{s}#{i}" }
        add.call
        add.call
        p seen
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      false
      ["x0", "x0"]
      ["y1", "y1"]
    OUT
  end

  it "proc case eq" do
    result = ze0(<<~'RUBY')
      even = ->(x) { x.even? }
      puts(even === 4)
      puts(even === 3)
      r = case 5
      when even then "even"
      else "odd"
      end
      puts r
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      odd
    OUT
  end

  it "proc case eq value" do
    result = ze0(<<~'RUBY')
      # Proc#=== answers the proc's return value; a case/when only cares about its
      # truthiness, so both readings agree there but a direct call does not (#3818).
      double = ->(x) { x * 2 }
      p(double === 5)
      pred = ->(x) { x > 3 }
      p(pred === 5)
      p(pred === 1)
      v = 5
      case v
      when ->(x) { x > 3 } then puts "big"
      else puts "small"
      end
      box = [->(x) { x.to_s }, 1]
      f = box[0]
      p(f === 7)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      true
      false
      big
      "7"
    OUT
  end

  it "proc cell capture marked" do
    result = ze0(<<~'RUBY')
      # A captured Proc rides in an sp_int cell -- an integer slot holding a
      # collectable object. The capture's scan marked the CELL and nothing marked the
      # proc, so a nested `proc { |v| two.call(v, v) }` called through freed memory
      # once full cycles were frequent (#4077). Run it under SPINEL_GC_FULL_INTERVAL=1
      # to see the difference; the shape is what matters here.
      two = proc { |a, b| [a, b] }
      nested = proc { |v| two.call(v, v) }

      adder = proc { |a, b| a + b }
      twice = proc { |n| adder.call(n, n) }
      outer = proc { |n| twice.call(twice.call(n)) }

      i = 0
      while i < 200
        Array.new(2_000, i * 1.0)      # churn, so the collector actually runs
        GC.start if (i % 50).zero?
        i += 1
      end

      p nested.call(7)
      p outer.call(3)

      # the same shape one level deeper, and through a method
      def drive(p1, n) = p1.call(n)

      deep = proc { |n| nested.call(n) }
      p drive(deep, 5)

      # a proc captured by a proc captured by a proc
      a1 = proc { |x| x * 2 }
      a2 = proc { |x| a1.call(x) + 1 }
      a3 = proc { |x| a2.call(x) * 10 }
      GC.start
      GC.start
      p a3.call(4)
    RUBY

    _(result).must_answer <<~'OUT'
      [7, 7]
      12
      [5, 5]
      90
    OUT
  end

  it "proc closure" do
    result = ze0(<<~'RUBY')
      # Regression test for proc closures (capturing outer locals).
      # Phase 2 of proc closure recovery: captures via heap cells + per-proc
      # capture struct, mirroring the Fiber capture mechanism.

      # Escaping closure with mutation
      def make_counter
        n = 0
        proc { n = n + 1; n }
      end

      c = make_counter
      puts c.call
      puts c.call
      puts c.call

      # Read-only escaping closure
      def make_adder(base)
        proc { |n| n + base }
      end
      add5 = make_adder(5)
      puts add5.call(3)
      puts add5.call(10)

      # Non-escaping closure with multiple captures and mutation
      def apply_twice(x)
        total = 0
        count = 0
        doubler = proc { |n| total = total + n * 2; count = count + 1 }
        doubler.call(x)
        doubler.call(x)
        puts total
        puts count
      end
      apply_twice(5)

      # Two procs capturing the same local — mutations must propagate
      def make_pair
        shared = 100
        inc = proc { shared = shared + 1 }
        inc.call
        inc.call
        shared
      end
      puts make_pair
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      8
      15
      20
      2
      102
    OUT
  end

  it "proc compose container" do
    result = ze0(<<~'RUBY')
      fs001 = [->(x) { x + 1 }]
      id001 = ->(x) { x }
      c001 = id001 >> fs001[0]
      p c001.call(4)
      h = { f: ->(x) { x * 2 } }
      c003 = id001 >> h[:f]
      p c003.call(3)
      p (id001 >> fs001[0]).call(1)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      6
      2
    OUT
  end

  it "proc compose curry forward" do
    result = ze0(<<~'RUBY')
      # Proc composition through poly-param procs, curry saturation, Proc.new(&b)
      # forwarding a captured block, and explicit Method#to_proc.

      # forward and backward composition
      inc = ->(a) { a + 1 }
      dbl = ->(a) { a * 2 }
      p (inc >> dbl).call(5)
      p (inc << dbl).call(5)

      # composition through a method boundary (type-erased operands)
      def chain(x); (->(a) { a + 1 } >> ->(a) { a * 2 }).call(x); end
      p chain(5)

      # curry saturates through a method param
      def apply2(pr); pr.curry.call(1).call(2); end
      p apply2(->(a, b) { a + b })

      # curry on a local proc, single-call and bracket application
      add3 = ->(a, b, c) { a + b + c }
      p add3.curry[1][2][3]
      cur = add3.curry.call(10)
      p cur.call(20).call(30)

      # Proc.new(&b) returns the forwarded block as a proc
      def make(&b); Proc.new(&b); end
      pr = make { |x| x * 2 }
      p pr.call(5)
      p pr.call(7)

      # proc(&b) behaves the same
      def wrap(&b); proc(&b); end
      w = wrap { |x| x + 100 }
      p w.call(1)

      # explicit Method#to_proc
      def triple(x); x * 3; end
      tp = method(:triple).to_proc
      p tp.call(5)
      p [1, 2, 3].map(&method(:triple))
    RUBY

    _(result).must_answer <<~'OUT'
      12
      11
      12
      3
      6
      60
      10
      14
      101
      15
      [3, 6, 9]
    OUT
  end

  it "proc curry" do
    result = ze0(<<~'RUBY')
      # Proc#curry completion typing: a curried application stays a curry until it
      # reaches the proc's arity, when it realizes to the proc's (int) result -- so a
      # completed curry is a first-class int (printable with `p`, usable in
      # arithmetic), while a partial application is still a curry awaiting more args.
      add = ->(a, b) { a + b }
      sub = ->(a, b) { a - b }
      mul3 = ->(a, b, c) { a * b * c }

      # direct chains realize to int
      p add.curry[5][3]                 # 8
      p sub.curry[10][3]                # 7
      p mul3.curry[2][3][4]             # 24

      # a completed curry is an ordinary int value
      total = add.curry[10][20]
      p total + 1                       # 31
      p add.curry[2][3] * 10            # 50
      p [add.curry[1][2], add.curry[3][4]]  # [3, 7]

      # partial applications held in variables, completed later
      add5 = add.curry[5]
      p add5[3]                         # 8
      p add5[100]                       # 105

      f = mul3.curry[2]
      g = f[3]
      p g[4]                            # 24
      p f[5][6]                         # 60

      # empty curry then full application
      cc = add.curry
      p cc[10][20]                      # 30

      # .call / .() forms also complete
      p add.curry.call(7).call(8)       # 15
    RUBY

    _(result).must_answer <<~'OUT'
      8
      7
      24
      31
      50
      [3, 7]
      8
      105
      24
      60
      30
      15
    OUT
  end

  it "proc keyword param" do
    result = ze0(<<~'RUBY')
      # A stored proc declaring keyword params binds them from the call's kwargs;
      # an omitted optional keyword takes its default.
      add = proc { |a:, b:| a + b }
      p add.call(a: 1, b: 2)
      opt = proc { |x:, y: 100| [x, y] }
      p opt.call(x: 5)
      p opt.call(x: 5, y: 6)
      mixed = proc { |n, k:| [n, k] }
      p mixed.call(9, k: 3)
      # A required keyword omitted from the call raises ArgumentError, as in CRuby.
      begin
        add.call(a: 1)
      rescue ArgumentError => e
        puts "raised: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      3
      [5, 100]
      [5, 6]
      [9, 3]
      raised: missing keyword: :b
    OUT
  end

  it "proc pattern from container" do
    result = ze0(<<~'RUBY')
      tbl001 = { even: ->(x) { x.even? } }
      p(case 4 when tbl001[:even] then "y" else "n" end)
      tbl002 = { even: ->(x) { x.even? } }; p(tbl002[:even] === 4)
      arr003 = [->(x) { x.even? }]; p(arr003[0] === 4)
      l = ->(x) { x.odd? }
      p(case 3 when l then "o" else "e" end)
      p(Integer === 3)
      p((1..5) === 3)
    RUBY

    _(result).must_answer <<~'OUT'
      "y"
      true
      true
      "o"
      true
      true
    OUT
  end

  it "proc ruby2 keywords warning" do
    result = ze0(<<~'RUBY', path: "lang/blocks/proc_ruby2_keywords_warning.rb")
      pr = proc { |x| x }
      pr.ruby2_keywords
      p :done
    RUBY

    _(result).must_answer ":done\n", stderr: "lang/blocks/proc_ruby2_keywords_warning.rb:2: warning: Skipping set of ruby2_keywords flag for proc (proc accepts keywords or post arguments or proc does not accept argument splat)\n"
  end

  it "procs own block param receives the call site block" do
    result = ze0(<<~'RUBY')
      # A proc/lambda that declares its own `&block` parameter receives the
      # block passed to its `#call` -- the block rides the closure's third
      # parameter into the body, where `b.call`/`b.nil?` reflect it. Covers a
      # Proc-typed receiver (the lambda literal, a fast-path `#call`), a Poly
      # local (`f`/`g`, the dynamic `Proc#call` builtin), a blockless call
      # (binds nil), and a passed block that captures an enclosing local.

      p(->(&b) { b.call(9) }.call { |x| x + 1 })
      f = ->(&b) { b.nil? ? "none" : b.call(1) }
      p f.call
      p(f.call { |x| x * 100 })
      g = ->(a, &b) { a + b.call(a) }
      p(g.call(5) { |x| x * 2 })
      base = 50
      p(->(&b) { b.call(3) }.call { |x| base + x })
    RUBY

    _(result).must_answer <<~'OUT'
      10
      "none"
      100
      15
      53
    OUT
  end

  it "safe nav block calls" do
    result = ze0(<<~'RUBY')
      # A `&.` call has to reach the safe-nav guard. Three lowerings walk the
      # receiver without looking at the operator -- the value-position iterator, the
      # statement-position one, and the comprehension family -- so `v&.each { }` fed
      # a nil to sp_poly_iter_check and raised where CRuby answers nil. The first two
      # stand down until the guard has run; the guard re-enters them on the guarded
      # temp, and THAT pass lowers normally.
      #
      # And the guard could only be a ternary. A lowering that hoists statements (the
      # comprehension family builds a loop) put them in front of it, where they ran
      # on the very nil it exists to stop, so the guard becomes a statement `if` when
      # the value arm hoists.

      def sn_0(v) = v&.each { |x| x }
      p sn_0(nil)
      def sn_1(v) = v&.each_entry { |x| x }
      p sn_1(nil)
      def sn_2(v) = v&.each_with_index { |x, i| x }
      p sn_2(nil)
      def sn_3(v) = v&.each_pair { |k, v| k }
      p sn_3(nil)
      def sn_4(v) = v&.each_key { |k| k }
      p sn_4(nil)
      def sn_5(v) = v&.each_value { |v| v }
      p sn_5(nil)
      def sn_6(v) = v&.reverse_each { |x| x }
      p sn_6(nil)
      def sn_7(v) = v&.map { |x| x }
      p sn_7(nil)
      def sn_8(v) = v&.collect { |x| x }
      p sn_8(nil)
      def sn_9(v) = v&.select { |x| true }
      p sn_9(nil)
      def sn_10(v) = v&.filter { |x| true }
      p sn_10(nil)
      def sn_11(v) = v&.reject { |x| false }
      p sn_11(nil)
      def sn_12(v) = v&.sort_by { |x| x }
      p sn_12(nil)
      def sn_13(v) = v&.min_by { |x| x }
      p sn_13(nil)
      def sn_14(v) = v&.max_by { |x| x }
      p sn_14(nil)
      def sn_15(v) = v&.group_by { |x| x }
      p sn_15(nil)
      def sn_16(v) = v&.partition { |x| true }
      p sn_16(nil)
      def sn_17(v) = v&.flat_map { |x| x }
      p sn_17(nil)
      def sn_18(v) = v&.each_slice(2) { |x| x }
      p sn_18(nil)
      def sn_19(v) = v&.each_cons(2) { |x| x }
      p sn_19(nil)
      def sn_20(v) = v&.sum { |x| x }
      p sn_20(nil)
      def sn_21(v) = v&.all? { |x| true }
      p sn_21(nil)
      def sn_22(v) = v&.any? { |x| true }
      p sn_22(nil)
      def sn_23(v) = v&.none? { |x| false }
      p sn_23(nil)
      def sn_24(v) = v&.one? { |x| true }
      p sn_24(nil)
      def sn_25(v) = v&.take_while { |x| true }
      p sn_25(nil)
      def sn_26(v) = v&.drop_while { |x| false }
      p sn_26(nil)
      def sn_27(v) = v&.each_with_object(0) { |a, b| a }
      p sn_27(nil)
      def sn_28(v) = v&.reduce { |a, b| a }
      p sn_28(nil)
      def sn_29(v) = v&.inject { |a, b| a }
      p sn_29(nil)
      def sn_30(v) = v&.filter_map { |x| x }
      p sn_30(nil)
      def sn_31(v) = v&.find_index { |x| true }
      p sn_31(nil)
      def sn_32(v) = v&.times { |x| x }
      p sn_32(nil)
      def sn_33(v) = v&.upto(3) { |x| x }
      p sn_33(nil)
      def sn_34(v) = v&.step(3) { |x| x }
      p sn_34(nil)

      # and a non-nil receiver still walks: the guard must not swallow the call
      p [1, 2, 3]&.each { |x| x }
      p [1, 2, 3]&.select { |x| x > 1 }
      p [1, 2, 3]&.reject { |x| x > 1 }
      p [1, 2, 3]&.reduce { |a, b| a + b }
      p [1, 2, 3]&.group_by { |x| x.odd? }
      p({ "a" => 1 }&.each_pair { |k, v| k })
      p [1, 2, 3]&.map { |x| x * 2 }

      # through a method, where the receiver is genuinely poly
      def walk(v) = v&.select { |x| x > 1 }
      p walk([1, 2, 3])
      p walk(nil)
      def total(v) = v&.reduce(0) { |a, b| a + b }
      p total([1, 2, 3])
      p total(nil)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      [1, 2, 3]
      [2, 3]
      [1]
      6
      {true => [1, 3], false => [2]}
      {"a" => 1}
      [2, 4, 6]
      [2, 3]
      nil
      6
      nil
    OUT
  end

  it "safe nav block family" do
    result = ze0(<<~'RUBY')
      # `v&.<enumerable> { }` on a nil receiver answers nil. The element-loop
      # lowerings walk the receiver without looking at the call operator, so they ran
      # on the very nil the guard exists to stop.
      def pick(n) = n > 0 ? [1, 2, 4, 5] : nil

      def probe(v)
        [v&.map { |x| x },
         v&.flat_map { |x| x },
         v&.select { |x| x > 2 },
         v&.reject { |x| x > 2 },
         v&.filter_map { |x| x if x > 2 },
         v&.partition { |x| x > 2 },
         v&.group_by { |x| x > 2 },
         v&.sort_by { |x| -x },
         v&.min_by { |x| -x },
         v&.count { |x| x > 2 },
         v&.sum { |x| x },
         v&.each { |x| x },
         v&.each_with_index { |x, i| x }]
      end

      p probe([1, 2, 4, 5])
      p probe(nil)
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2, 4, 5], [1, 2, 4, 5], [4, 5], [1, 2], [4, 5], [[4, 5], [1, 2]], {false => [1, 2], true => [4, 5]}, [5, 4, 2, 1], 5, 2, 12, [1, 2, 4, 5], [1, 2, 4, 5]]
      [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
    OUT
  end

  it "singleton class block" do
    result = ze0(<<~'RUBY')
      # Singleton-class blocks define methods on an object's singleton class. The
      # `class << self` form inside a class/module body already worked; this adds the
      # `class << Const` form (a constant naming a class or module) and the top-level
      # `class << self` form. Both were rejected ("unsupported ... SingletonClassNode")
      # because the inner defs were attached to the enclosing scope's class rather
      # than the named one, and a top-level singleton-class node had no codegen path.

      # class << Const on a module
      module Greeter; end
      class << Greeter
        def hello; "hello"; end
      end
      p Greeter.hello

      # class << Const on a class, with arguments
      class Calc; end
      class << Calc
        def add(a, b); a + b; end
      end
      p Calc.add(3, 4)

      # multiple defs and class-level ivar state on the singleton
      module Registry; end
      class << Registry
        def push(x); @items ||= []; @items << x; @items; end
        def count; @items ? @items.length : 0; end
      end
      Registry.push(:a)
      Registry.push(:b)
      p Registry.count

      # class << self inside a class body still works (regression)
      class Config
        class << self
          def version; "1.0"; end
        end
      end
      p Config.version

      # top-level class << self defines a private-ish helper on main
      class << self
        def helper(n); n * 2; end
      end
      p helper(21)
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      7
      2
      "1.0"
      42
    OUT
  end

  it "splat delete and block tail iter" do
    result = ze0(<<~'RUBY')
      # Hash#delete with a splatted argument list (#3521): delete was missing from
      # the fixed-arity list, so the splat array reached the slot expecting one key.
      k001 = [:a]
      h001 = { a: 1 }
      h001.delete(*k001)
      p h001

      k002 = [:a]
      p({ a: 1 }.delete(*k002))

      h003 = { a: 1 }
      v003 = h003.delete(*k002)
      p v003

      # An iterator in the tail position of a BLOCK (#3522): the splice is read as
      # the value of a statement expression, and a receiver-returning iterator emits
      # as a loop with no value, so the slot got void (or the loop counter).
      def y001
        yield({ "a" => 1 })
      end
      p(y001 { |h| h.each { |k, v| nil } })

      def y002
        yield([1, 2])
      end
      p(y002 { |a| a.each { |x| nil } })

      def y003
        yield(1..2)
      end
      p(y003 { |r| r.each { |x| nil } })

      def y004
        yield(2)
      end
      p(y004 { |n| n.times { |i| nil } })

      # consuming it explicitly inside the block kept working
      def y005
        yield({ "a" => 1 })
      end
      p(y005 { |h| r = h.each { |k, v| nil }; r })
    RUBY

    _(result).must_answer <<~'OUT'
      {}
      1
      1
      {"a" => 1}
      [1, 2]
      1..2
      2
      {"a" => 1}
    OUT
  end

  it "splat into a proc or lambda receiver" do
    result = ze0(<<~'RUBY')
      add3 = ->(a, b, c) { a + b + c }
      args = [1, 2, 3]
      p add3.call(*args)
      p add3[*args]
      p add3.(*args)
      p add3.yield(*args)
      prc = proc { |a, b| a * b }
      p prc.call(*[4, 5])
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
      6
      6
      20
    OUT
  end

  it "to enum enum for" do
    result = ze0(<<~'RUBY')
      # to_enum / enum_for build a real lazy Enumerator that defers `recv.m(*args)`:
      # the receiver's method is driven through a fiber generator, so .class is
      # Enumerator, .next/.peek do external iteration, and the full Enumerable surface
      # works. Multi-value yields (`yield a, b`) collapse to an array element, matching
      # CRuby's ary2sv. Covers user classes (collection-backed, pure-yield,
      # value-type), the `return enum_for(:each) unless block_given?` idiom, and
      # builtin receivers.

      # --- the canonical idiom: return enum_for(:each) unless block_given? ---
      class Bag
        include Enumerable
        def initialize(*xs) = @xs = xs
        def each
          return enum_for(:each) unless block_given?
          @xs.each { |x| yield x }
        end
      end

      b = Bag.new(1, 2, 3)
      p b.each.class
      p b.each.to_a
      p b.each.map { |x| x * 10 }
      p b.each.select { |x| x > 1 }
      puts b.each.count
      puts b.each.include?(2)
      e = b.each
      p e.next
      p e.next

      # --- a pure-yield method (no backing collection) ---
      class Seq
        def go
          return enum_for(:go) unless block_given?
          yield 1
          yield 2
          yield 3
        end
      end
      p Seq.new.go.to_a
      p Seq.new.go.map { |x| x + 100 }
      g = Seq.new.go
      p g.next
      p g.peek
      p g.next

      # --- multi-value yields collapse to array elements (ary2sv) ---
      class Grid
        include Enumerable
        def initialize = @cells = [[1, 2], [3, 4]]
        def each
          return enum_for(:each) unless block_given?
          @cells.each { |a, b| yield a, b }
        end
      end
      p Grid.new.each.to_a
      p Grid.new.each.map { |a, b| a + b }
      p Grid.new.each.next

      # --- to_enum on an arbitrary method name (separated form) ---
      class Steps
        def initialize(n) = @n = n
        def upto_n
          i = 1
          while i <= @n
            yield i
            i += 1
          end
        end
        def stepper = to_enum(:upto_n)
      end
      p Steps.new(4).stepper.to_a
      p Steps.new(4).stepper.select { |n| n.even? }

      # --- builtin receivers ---
      p [10, 20, 30].to_enum(:each).to_a
      p({ "a" => 1, "b" => 2 }.to_enum(:each).to_a)
      p "hi".to_enum(:each_char).to_a
      p (1..3).to_enum(:each).to_a
      p [5, 6, 7].to_enum(:each_with_index).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      [1, 2, 3]
      [10, 20, 30]
      [2, 3]
      3
      true
      1
      2
      [1, 2, 3]
      [101, 102, 103]
      1
      2
      2
      [[1, 2], [3, 4]]
      [3, 7]
      [1, 2]
      [1, 2, 3, 4]
      [2, 4]
      [10, 20, 30]
      [["a", 1], ["b", 2]]
      ["h", "i"]
      [1, 2, 3]
      [[5, 0], [6, 1], [7, 2]]
    OUT
  end

  it "to enum size without block" do
    result = ze0(<<~'RUBY')
      p [1, 2].to_enum(:each).size
      p 3.times.to_enum.size
      p [1, 2].enum_for(:each) { 99 }.size
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      99
    OUT
  end

  it "top level def called from a lambda" do
    result = ze0(<<~'RUBY')
      def base
        40
      end
      f = ->(x) { base + x }
      puts f.call(2)
    RUBY

    _(result).must_answer "42\n"
  end

  it "top level def with block and yield" do
    result = ze0(<<~'RUBY')
      def twice
        yield 1
        yield 2
      end
      twice { |i| puts "got #{i}" }
    RUBY

    _(result).must_answer <<~'OUT'
      got 1
      got 2
    OUT
  end

  it "toplevel kwrest block param" do
    result = ze0(<<~'RUBY')
      class App
        def initialize(title:, body:)
          @title = title
          @body = body
        end

        def render
          puts @title
          @body.call
        end
      end

      # Top-level def combining `**kwrest` with `&block`, passing the block local
      # as a kwarg to a `.new` call site.
      def app(title = nil, **_chrome, &block)
        App.new(title: title || "default", body: block)
      end

      app("hello") { puts "ran" }.render
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      ran
    OUT
  end

  it "uniq block" do
    result = ze0(<<~'RUBY')
      # Array#uniq / uniq! with a block dedupe by the block's return value, keeping
      # the first element of each key group and preserving the receiver's element type.
      # Receivers are routed through per-type identity methods to defeat constant
      # folding and exercise the real typed runtime path.
      def ai(x); x; end
      def af(x); x; end
      def ap(x); x; end

      # Integer array.
      p ai([1, 2, 3, 4]).uniq { |n| n % 2 }          # [1, 2]
      p [1, 2, 3, 4, 5, 6].uniq { |n| n % 3 }        # [1, 2, 3]
      p ai([1, 2, 3, 4]).uniq { |n| n % 2 }.sum      # 3  (result stays an Int array)

      # String array.
      p %w[foo bar baz qux].uniq { |w| w[0] }        # ["foo", "bar", "qux"]

      # Float array.
      p af([1.5, 2.5, 3.5, 4.5]).uniq { |x| x.to_i % 2 }   # [1.5, 2.5]

      # Heterogeneous (poly) array.
      p ap([1, "a", 2, "b"]).uniq { |x| x.class }    # [1, "a"]

      # Empty and all-unique-key cases.
      p [].uniq { |n| n }                            # []
      p [5, 6, 7].uniq { |n| n }                     # [5, 6, 7]

      # uniq! mutates in place.
      a = [1, 1, 2, 3, 3]
      a.uniq! { |n| n }
      p a                                            # [1, 2, 3]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2, 3]
      3
      ["foo", "bar", "qux"]
      [1.5, 2.5]
      [1, "a"]
      []
      [5, 6, 7]
      [1, 2, 3]
    OUT
  end

  it "yield" do
    result = ze0(<<~'RUBY')
      # Test program for yield/block support

      # User-defined iterator with yield
      def my_times(n)
        i = 0
        while i < n
          yield i
          i += 1
        end
      end

      # Array#each
      def sum_array(arr)
        total = 0
        arr.each do |x|
          total += x
        end
        total
      end

      # Array#map
      def double_array(arr)
        arr.map do |x|
          x * 2
        end
      end

      # Array#select
      def evens(arr)
        arr.select do |x|
          x % 2 == 0
        end
      end

      # Nested yield
      def repeat(n)
        i = 0
        while i < n
          yield i
          i += 1
        end
      end

      # Main
      total = 0
      my_times(10) do |i|
        total += i
      end
      puts total  # 45

      arr = (1..10).to_a
      puts sum_array(arr)  # 55

      doubled = double_array(arr)
      puts doubled.length  # 10

      even_nums = evens(arr)
      puts even_nums.length  # 5

      # Nested: repeat yields, inner block accumulates
      result = 0
      repeat(5) do |i|
        my_times(i) do |j|
          result += j
        end
      end
      puts result  # 0+0+1+0+1+2+0+1+2+3 = 10
    RUBY

    _(result).must_answer <<~'OUT'
      45
      55
      10
      5
      10
    OUT
  end

  it "yield carries keywords" do
    result = ze0(<<~'RUBY')
      def m1
        yield 1, a: 2, b: 3
      end
      m1 { |x, **kw| p [x, kw] }
      m1 { |x, kw| p [x, kw] }

      def m2(h)
        yield 1, **h
      end
      m2({}) { |*a| p a }
      m2({z: 9}) { |*a| p a }

      def m3(h)
        yield(**h)
      end
      m3({}) { |*a| p a }
      m3({q: 1}) { |*a| p a }

      def m4(arr, h)
        yield(*arr, **h)
      end
      m4([1,2], {}) { |*a| p a }
      m4([1,2], {k: 3}) { |*a| p a }

      def m5
        yield a: 1
      end
      m5 { |kw| p kw }
      m5 { |a:| p a }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, {a: 2, b: 3}]
      [1, {a: 2, b: 3}]
      [1]
      [1, {z: 9}]
      []
      [{q: 1}]
      [1, 2]
      [1, 2, {k: 3}]
      {a: 1}
      1
    OUT
  end

  it "yield channels" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # The three channels a call carries -- positionals, keywords and the
      # block -- reaching a `yield`, and the anonymous spellings of each,
      # which ruby names `*`, `**` and `&`.

      # `yield(*a)`: how many values reach the block is a run-time fact.
      def spread(arr)
        yield(*arr)
      end
      spread([1, 2]) { |a, b| p [a, b] }
      spread([]) { |a| p a }

      # Keywords written at the yield. A block with no keyword parameters
      # takes them as a trailing Hash.
      def keyed
        yield 1, a: 2, b: 3
      end
      keyed { |x, opts| p [x, opts] }
      keyed { |x, a:, b:| p [x, a, b] }

      # A `**h` that is empty when it runs contributes nothing, so the block
      # sees one fewer argument rather than a `{}`.
      def double_splat(h)
        yield 9, **h
      end
      double_splat({ z: 1 }) { |x, **o| p [x, o] }
      double_splat({}) { |x, *rest| p [x, rest] }

      # The anonymous parameters, forwarded by name-less `*`, `**` and `&`.
      def sink(*a, **k) = p [a, k]
      def rest_only(*) = sink(*)
      def kw_only(**) = sink(**)
      def all_three(*, **, &) = sink(*, **, &)
      rest_only(1, 2)
      kw_only(a: 1)
      all_three(1, b: 2)

      def calls_block = yield 7
      def forward(&) = calls_block(&)
      p(forward { |x| x * 2 })

      # An `|a, |` trailing comma binds nothing, but it does turn the block's
      # auto-splat on, and it is not in the signature.
      p proc { |a,| a }.parameters
      p [[1, 2, 3]].map { |a,| a }
      p [[1, 2, 3]].map { |a| a }

      # ruby names each anonymous channel after the sigil that wrote it.
      def anon_rest(*); end
      def anon_kwrest(**); end
      def anon_block(&); end
      def forwards_all(...); end
      p method(:anon_rest).parameters
      p method(:anon_kwrest).parameters
      p method(:anon_block).parameters
      p method(:forwards_all).parameters
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      nil
      [1, {a: 2, b: 3}]
      [1, 2, 3]
      [9, {z: 1}]
      [9, []]
      [[1, 2], {}]
      [[], {a: 1}]
      [[1], {b: 2}]
      14
      [[:opt, :a]]
      [1]
      [[1, 2, 3]]
      [[:rest, :*]]
      [[:keyrest, :**]]
      [[:block, :&]]
      [[:rest, :*], [:keyrest, :**], [:block, :&]]
    OUT
  end

  it "yield splat" do
    result = ze0(<<~'RUBY')
      # `yield(*arr)`: a single splat spreads its array across the block's parameters
      # (auto-splat), exactly like passing the elements positionally. Previously
      # rejected ("unsupported expression: SplatNode") because each yield argument was
      # emitted as an expression and a SplatNode has no value form. The array is now
      # evaluated once into a rooted temp and the block params (plus any rest param)
      # bind from its elements, with a short array binding the surplus params to nil.
      def s(x); x; end

      # splat of a literal, a local, and a method-call result
      def m_lit; yield(*[1, 2]); end
      p(m_lit { |a, b| a + b })

      def m_loc(xs); yield(*xs); end
      p(m_loc([3, 4]) { |a, b| a * b })

      def m_call; yield(*s([7, 8])); end
      p(m_call { |a, b| a + b })

      # single param, string elements
      def m_one; yield(*[9]); end
      p(m_one { |a| a * 10 })

      def m_str; yield(*["x", "y"]); end
      p(m_str { |a, b| a + b })

      # extra elements are dropped; a short array binds the surplus param to nil
      def m_extra; yield(*[1, 2, 3]); end
      p(m_extra { |a, b| [a, b] })

      def m_short; yield(*[1]); end
      p(m_short { |a, b| [a, b.nil?] })

      # rest parameter collects the remainder
      def m_rest; yield(*[1, 2, 3]); end
      p(m_rest { |*xs| xs.sum })

      def m_fixed_rest; yield(*[1, 2, 3, 4]); end
      p(m_fixed_rest { |a, *rest| [a, rest] })

      # value position: the yield result is used
      def m_value; r = yield(*[2, 3]); r * 2; end
      p(m_value { |a, b| a + b })

      # multiple yields in one method
      def m_twice; yield(*[1, 2]); yield(*[3, 4]); end
      m_twice { |a, b| p a + b }

      # plain (non-splat) yield is unaffected
      def m_plain; yield(10, 20); end
      p(m_plain { |a, b| a + b })
    RUBY

    _(result).must_answer <<~'OUT'
      3
      12
      15
      90
      "xy"
      [1, 2]
      [1, true]
      6
      [1, [2, 3, 4]]
      10
      3
      7
      30
    OUT
  end

  it "yield takes splat arguments" do
    result = ze0(<<~'RUBY')
      # `HirNode::Yield` carries the same `Vec<ArrayElem>` a Call's positional
      # args do, so a splat flattens at runtime and the block then binds from
      # the result through its ordinary parameter machinery -- auto-splat,
      # rest, and nil-padding of surplus params all included.

      def m(*a); yield(*a); end
      p(m(1, 2) { |x, y| [x, y] })
      p(m(1) { |x, y| [x, y] })
      p(m() { |x, y| [x, y] })

      def mix(*a); yield(0, *a, 9); end
      p(mix(1, 2) { |*z| z })

      def empty; yield(*[]); end
      p(empty { |*z| z })

      def kwmix(*a); yield(*a, k: 1); end
      p(kwmix(1) { |x, k:| [x, k] })

      class W
        def initialize(n); @n = n; end
        attr_reader :n
      end
      def objs; yield(*[W.new(1), W.new(2)]); end
      p(objs { |a, b| a.n + b.n })
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, nil]
      [nil, nil]
      [0, 1, 2, 9]
      []
      [1, 1]
      3
    OUT
  end
end
