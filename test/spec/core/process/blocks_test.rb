# frozen_string_literal: true

require "spec_helper"

describe "Process: blocks and yields" do
  it "at exit returns proc" do
    _(ze0(<<~'RUBY')).must_answer "Proc\n"
      v001 = at_exit { }
      p v001.class
    RUBY
  end

  it "class exec def body" do
    result = ze0(<<~'RUBY')
      # class_exec / module_exec with a method-defining block is the same
      # compile-time reopen class_eval already rode (#2722).
      class C; end
      C.class_exec { def hi; 3; end }
      p(C.new.hi)
      module M; end
      M.module_exec { def mm; 4; end }
      class D; include M; end
      p D.new.mm
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
    OUT
  end

  it "exit systemexit and block given" do
    result = ze0(<<~'RUBY')
      # `exit`/`abort` raise a RESCUABLE SystemExit carrying the status (it unwinds
      # through ensure), and `block_given?` answers for an `&block` parameter through
      # both the receiverless and the explicit `self.` spelling.
      begin
        abort("bye now")
        puts "unreached"
      rescue SystemExit => e
        puts "status=#{e.status}"
        puts "msg=#{e.message}"
      end
      puts "continued"

      begin
        exit 3
      rescue SystemExit => e
        puts "exit-status=#{e.status}"
        puts "exit-success=#{e.success?}"
      end

      # The unwind runs ensure blocks on its way out.
      def guarded
        exit 0
      ensure
        puts "ensure ran"
      end
      begin
        guarded
      rescue SystemExit => e
        puts "guarded-status=#{e.status}"
      end

      def top(&block)
        block_given? ? "yes" : "no"
      end
      p top
      p(top {})

      def top_self(&block)
        self.block_given? ? "yes" : "no"
      end
      p top_self
      p(top_self {})
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT', stderr: "bye now\n"
      status=1
      msg=bye now
      continued
      exit-status=3
      exit-success=false
      ensure ran
      guarded-status=0
      "no"
      "yes"
      "no"
      "yes"
      done
    OUT
  end

  it "instance exec autosplat" do
    result = ze0(<<~'RUBY')
      # Auto-splat: a single array arg destructured across N>=2 block params
      # (CRuby binds arr[0]..arr[N-1] at arity >= 2). The params are typed
      # from the array's element type and codegen reads each element via the
      # typed sp_<Prefix>_get.

      class Box
        def initialize(v)
          @v = v
        end

        def base
          @v
        end
      end

      class BoxPlus < Box
      end

      b = BoxPlus.new(100)

      # Array literal arg, three params, combined with a rebound-self call.
      puts(b.instance_exec([1, 2, 3]) { |x, y, z| base + x + y + z })   #=> 106

      # Two params; the element type drives the param C types.
      puts(b.instance_exec([10, 20]) { |x, y| x + y })                  #=> 30

      # String-element array auto-splats too.
      puts(b.instance_exec(["a", "b"]) { |x, y| x + y })                #=> ab

      # A top-level-local array arg resolves its element type during the
      # rewrite walk (the root walk now declares top-level locals in scope),
      # so it auto-splats the same as a literal.
      nums = [10, 20]
      puts(b.instance_exec(nums) { |x, y| base + x + y })               #=> 130

      words = ["x", "y"]
      puts(b.instance_exec(words) { |x, y| x + y })                     #=> xy
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      106
      30
      ab
      130
      xy
      done
    OUT
  end

  it "instance exec capture" do
    result = ze0(<<~'RUBY')
      # Outer-local capture in a direct instance_exec block. Call-site
      # inline-splicing runs the block body in the caller's scope, so the
      # block both reads the caller's locals and writes them back -- the
      # mutation persists after the call, matching CRuby's closure semantics.
      #
      # Capture only applies to heap receivers (the inlined path); a subclass
      # keeps Box heap-allocated.

      class Box
        def initialize(v)
          @v = v
        end
      end

      class BoxPlus < Box
      end

      b = Box.new(10)

      # Read an outer local, write it back: the mutation is visible afterward.
      acc = 100
      b.instance_exec { acc = acc + @v }
      puts acc                         #=> 110

      # Accumulate across successive calls against the same captured local.
      b.instance_exec { acc = acc + @v }
      b.instance_exec { acc = acc + @v }
      puts acc                         #=> 130

      # Capture alongside a block param.
      total = 0
      b.instance_exec(5) { |x| total = total + @v + x }
      puts total                       #=> 15

      # Capture in expression position: the block reads outer locals and its
      # value flows out as the call's value.
      base = 7
      r = b.instance_exec(3) { |x| base + @v + x }
      puts r                           #=> 20

      # Write-back in expression position: mutate a captured local and also
      # use the call's value.
      n = 1
      m = b.instance_exec { n = n + @v; n }
      puts n                           #=> 11
      puts m                           #=> 11

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      110
      130
      15
      20
      11
      11
      done
    OUT
  end

  it "instance exec direct" do
    result = ze0(<<~'RUBY')
      # Direct-path instance_exec: `recv.instance_exec(args) { |params| body }`
      # called without a wrapping trampoline method. The analyze pass lifts
      # the block to a static function `sp_iexec_<N>(self, args...)` and
      # rewrites the call site to dispatch through it.
      #
      # Sibling of test/instance_exec_trampoline.rb (codegen-time inlining
      # of the def-m-instance_exec trampoline pattern). The direct form is
      # what most CRuby code writes: `obj.instance_exec(5) { |n| ... }` at
      # the call site, no wrapper method involved.
      #
      # Boundaries:
      #   - Strict arity: call-site args count == block params count.
      #   - No outer-local capture (the lifted function cannot see the
      #     caller's locals). Convert to the trampoline form for that.
      #   - Receiver must be a statically-resolvable obj_<C> -- a typed
      #     local, ivar, method param, or constant constructor.
      #   - return / break / next / yield / block_given? inside the block
      #     are rejected (silently for now; a follow-up upgrades to a hard error).
      #   - Value-typed receivers are unsupported (TODO carried over from
      #     compile_instance_eval_inlined_stmt's same issue). Multi-instance
      #     classes keep the receiver heap-allocated.

      # 1. Bare direct call with one arg. The block body adds the call-site
      #    arg to the receiver's @sum via the typed method `add`. Bare
      #    method calls inside the block resolve against the receiver's
      #    class (same dispatch path the trampoline tests exercise).
      class Builder
        def initialize
          @sum = 0
        end

        def add(n)
          @sum = @sum + n
        end

        def total
          @sum
        end
      end

      b = Builder.new
      b.instance_exec(10) { |n| add(n) }
      b.instance_exec(20) { |n| add(n) }
      b.instance_exec(12) { |n| add(n) }
      puts b.total                  #=> 42

      # 2. Two args at the call site forward into two block params. Block
      #    body computes against them, mutates the receiver's ivar via the
      #    rebound-self path, and returns nothing (the baseline locks the
      #    return type to void).
      class Acc < Builder
      end

      a1 = Acc.new
      a2 = Acc.new
      a1.instance_exec(3, 4) { |s, k| add(s * k) }
      a2.instance_exec(7, 2) { |s, k| add(s * k) }
      a1.instance_exec(1, 0) { |s, k| add(s + k) }
      puts a1.total                 #=> 13
      puts a2.total                 #=> 14

      # 3. Zero-arg form (degenerate, equivalent to instance_eval): the
      #    detector accepts arity-0, the lifted function takes only the
      #    receiver. Tests that the baseline doesn't conflate arity-0
      #    with the instance_eval lift (they're independent registries
      #    even when behavior overlaps).
      b2 = Builder.new
      b2.instance_exec { add(100) }
      b2.instance_exec { add(50) }
      puts b2.total                 #=> 150

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      13
      14
      150
      done
    OUT
  end

  it "instance exec implicit self" do
    result = ze0(<<~'RUBY')
      # Implicit-self direct call inside a class method:
      #   def configure
      #     instance_exec(10) { |n| add(n) }   # no explicit receiver
      #   end
      #
      # CRuby resolves this to `self.instance_exec(10) { |n| add(n) }`.
      # Spinel's analyze pass picks up @current_class_idx for the
      # receiver type when both:
      #   - The call has no explicit receiver
      #   - The block is a literal `{ ... }` (not `&proc_var`)
      #
      # Distinguishing from the trampoline-body case is critical: a
      # trampoline body's `instance_exec(args, &b)` has the &b arg
      # stored in @nd_block as a BlockArgumentNode (not a literal
      # BlockNode), so the analyze rewrite skips it and leaves the
      # call site for codegen's trampoline-pattern detector.

      class Builder
        def initialize
          @s = 0
        end
        def add(n)
          @s = @s + n
        end
        def total
          @s
        end

        # Implicit-self direct call -- no explicit receiver. Resolves
        # to self.instance_exec(...) at analyze time.
        def configure
          instance_exec(10) { |n| add(n) }
          instance_exec(20) { |n| add(n) }
          instance_eval { add(12) }   # sibling: instance_eval implicit-self too
        end
      end

      b = Builder.new
      b2 = Builder.new
      b.configure
      puts b.total   # 42

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      done
    OUT
  end

  it "instance exec nested" do
    result = ze0(<<~'RUBY')
      # Nested instance_exec: the rewrite descends into a lifted block body
      # so an inner instance_exec call lifts too, rebinding self per level.
      # The inner receiver is an outer-scope local captured into the block;
      # codegen splices the inner inline within the outer inline.

      class Outer
        def initialize
          @label = 10
        end

        def val
          @label
        end
      end

      class Inner
        def initialize
          @label = 20
        end

        def val
          @label
        end
      end

      o = Outer.new
      i = Inner.new

      # Inner self rebinds to `i`; its `val` reads Inner's ivar.
      puts(o.instance_exec { i.instance_exec { val } })   #=> 20

      # Outer self rebinds to `o`; the cross-level capture of `i` and the
      # rebound-self call compose: 10 + 20.
      puts(o.instance_exec { val + i.instance_exec { val } })   #=> 30
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      20
      30
      done
    OUT
  end

  it "instance exec numbered" do
    result = ze0(<<~'RUBY')
      # Numbered block params (`_1.._N`) and the implicit `it` param in a
      # direct instance_exec. Each numbered slot binds to the corresponding
      # call-site arg, and the block body runs with self rebound to the
      # receiver. The parser normalizes `it` to a single-slot numbered
      # param, so it shares the same lowering.

      class Box
        def initialize(v)
          @v = v
        end
      end

      class BoxPlus < Box
      end

      b = BoxPlus.new(10)

      # Single numbered param.
      puts b.instance_exec(7) { _1 * 2 }       #=> 14

      # `it` (implicit single param).
      puts b.instance_exec(8) { it + 1 }       #=> 9

      # Two numbered params.
      puts b.instance_exec(3, 4) { _1 + _2 }   #=> 7

      # Numbered param mixed with a rebound-self ivar read.
      puts b.instance_exec(5) { @v + _1 }      #=> 15

      # Expression position.
      n = b.instance_exec(2) { _1 * @v }
      puts n                                   #=> 20

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      14
      9
      7
      15
      20
      done
    OUT
  end

  it "instance exec override" do
    result = ze0(<<~'RUBY')
      # User-defined instance_exec / instance_eval methods shadow the
      # compile-time intrinsic. Ordinary method dispatch resolves to the
      # user's method instead of the lift.
      #
      # Before the override check landed in iexec_rewrite_call /
      # ieval_rewrite_call, Spinel silently bypassed user overrides by
      # rewriting the call to __sp_iexec_<N> at the analyze level. CRuby
      # would have dispatched to the user's method; Spinel did not.
      #
      # A fuller approach (registering BasicObject and routing every
      # intrinsic through method-resolution from the start) would
      # rearchitect the class table. The lighter version here -- a
      # cls_find_method check that bails out of the rewrite when the
      # user has their own method -- gets the correctness win without
      # the rearchitecture risk.

      class Wrap
        def initialize
          @marker = 0
        end

        # User-defined instance_exec on Wrap. Spinel should NOT lift the
        # block at the call site below; it should dispatch to this method
        # instead, matching CRuby.
        def instance_exec(x, &b)
          @marker = x + 100
          @marker
        end

        def marker
          @marker
        end
      end

      # Two instances so Wrap stays heap-allocated (value-type promotion
      # would otherwise complicate the test independent of the override
      # question).
      w1 = Wrap.new
      w2 = Wrap.new
      ret = w1.instance_exec(5) { |x| 9999 }  # block ignored -- user method runs
      puts ret              # 105
      puts w1.marker        # 105

      # Sibling override of instance_eval. Same expected dispatch.
      class Wrap2
        def initialize
          @tag = ""
        end

        def instance_eval(&b)
          @tag = "user-instance-eval-ran"
        end

        def tag
          @tag
        end
      end

      w3 = Wrap2.new
      w4 = Wrap2.new
      # Block body is a no-op -- the user method ignores it. We use a noop
      # rather than `@tag = "intrinsic-ran"` because the latter would force
      # Spinel to compile the block as a proc literal even though it's
      # never invoked, and proc compilation of a toplevel-ivar string
      # assignment trips an unrelated proc-return-type issue.
      w3.instance_eval { 1 }   # block ignored by user method
      puts w3.tag           # user-instance-eval-ran

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      105
      105
      user-instance-eval-ran
      done
    OUT
  end

  it "instance exec trampoline result" do
    result = ze0(<<~'RUBY')
      # An instance_exec result used through an intermediate local inside a method
      # (not a bare trampoline body), in value position. The method forwards its
      # block to a receiverless instance_exec, binds the result to a local, and
      # transforms it -- so the method's return type must resolve through the
      # forwarded-block value, and the method inlines per call site splicing the
      # literal block.

      # Heap receiver (a mutating method keeps it heap-allocated).
      class Calc
        def initialize
          @base = 10
          @hits = 0
        end
        def bump
          @hits = @hits + 1
        end
        def run(x, &b)
          r = instance_exec(x, @base, &b)
          r * 2
        end
      end

      c = Calc.new
      c.bump
      puts(c.run(5) { |a, b| a + b })       # (5 + 10) * 2 = 30
      puts(c.run(100) { |a, b| a - b })     # (100 - 10) * 2 = 180

      # Value-type receiver (small immutable class -> by-value struct).
      class Point
        def initialize(x, y)
          @x = x
          @y = y
        end
        def fold(&b)
          acc = instance_exec(@x, @y, &b)
          acc + 1
        end
      end

      p1 = Point.new(3, 4)
      p2 = Point.new(10, 20)
      puts(p1.fold { |a, b| a + b })        # (3 + 4) + 1 = 8
      puts(p2.fold { |a, b| a * b })        # (10 * 20) + 1 = 201

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      30
      180
      8
      201
      done
    OUT
  end

  it "instance exec value" do
    result = ze0(<<~'RUBY')
      # A top-level method forwarding a block to instance_exec, with its return value
      # consumed. Previously the value form linked against an un-emitted `sp_run`; a
      # receiverless instance_exec does not rebind self, so it is exactly `b.call`.

      def run(&b) = instance_exec(&b)

      # value form (the reported failure)
      x = run { 42 }
      puts x

      # side-effect form
      run { puts "side-effect" }

      # value used inside a larger expression
      def compute(&b) = instance_exec(&b)
      puts(compute { 10 } + compute { 20 })

      # positional args forward to the block
      def run_args(n, &b) = instance_exec(n, &b)
      puts run_args(21) { |v| v * 2 }

      # a captured local is visible (self is unchanged at top level)
      factor = 3
      def apply(&b) = instance_exec(&b)
      puts apply { factor * 10 }

      # class-level instance_exec still rebinds self to the instance (unchanged path)
      class Widget
        def initialize = (@n = 7)
        def tap_it(&b) = instance_exec(&b)
      end
      puts Widget.new.tap_it { @n * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      42
      side-effect
      30
      42
      30
      14
    OUT
  end

  it "instance exec valuetype" do
    result = ze0(<<~'RUBY')
      # A value-type receiver (an immutable, scalar-only class the compiler
      # promotes to a by-value struct) works with direct instance_exec via
      # inline-splice. self is rebound to a by-value copy of the receiver, so
      # ivar reads, bare rebound method calls, block params, expression-
      # position values and outer-local capture all resolve against it. (A
      # value type is immutable by construction, so there is no self-ivar
      # write-back to observe -- matching how the receiver is passed by value.)

      class Vec
        def initialize(x, y)
          @x = x
          @y = y
        end

        def x
          @x
        end

        def sum
          @x + @y
        end
      end

      v = Vec.new(3, 4)

      # ivar read in the block.
      puts(v.instance_exec { @x })               #=> 3

      # operator over two ivar reads.
      puts(v.instance_exec { @x * @y })          #=> 12

      # bare rebound method call against the value-type self.
      puts(v.instance_exec { sum })              #=> 7

      # positional arg bound to a block param, combined with a rebound call.
      puts(v.instance_exec(10) { |k| sum + k })  #=> 17

      # expression position: the call value flows into an outer local.
      r = v.instance_exec { @x + 100 }
      puts r                                     #=> 103

      # outer-local capture: written from inside the block (caller scope, so
      # it propagates regardless of by-value self).
      acc = 0
      v.instance_exec { acc = sum + 1 }
      puts acc                                   #=> 8

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      3
      12
      7
      17
      103
      8
      done
    OUT
  end

  it "process launch errors" do
    result = ze0(<<~'RUBY')
      # Process-launch error shapes: `system(cmd, exception: true)` raises
      # RuntimeError on failure and Errno::ENOENT on a missing command (zeo
      # answers false/nil, ignoring the option), and a bare `spawn` of a
      # missing command names it in the ENOENT message ("No such file or
      # directory - cmd"); zeo's message is the @-form with an empty site.
      # (Found by the 2026-08-24 probe sweep.)
      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { system("false", exception: true) }
      show { system("definitely_not_a_cmd_xyz", exception: true) }
      show { spawn("definitely_not_a_cmd_xyz") }
    RUBY

    _(result).must_answer <<~'OUT'
      RuntimeError: Command failed with exit 1: false
      Errno::ENOENT: No such file or directory - definitely_not_a_cmd_xyz
      Errno::ENOENT: No such file or directory - definitely_not_a_cmd_xyz
    OUT
  end
end
