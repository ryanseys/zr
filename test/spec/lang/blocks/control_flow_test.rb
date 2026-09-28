# frozen_string_literal: true

require "spec_helper"

describe "Blocks: control flow" do
  it "anon block forward" do
    result = zr(<<~'RUBY')
      # Anonymous `&` block forwarding (Ruby 3.1+).
      #
      # `def outer(&); inner(&); end` declares an unnamed block parameter
      # and forwards it via the matching anonymous `&` in the call. The
      # unnamed parameter works like any other `&block`, and the bare `&`
      # in the call forwards it.

      # 1. Top-level outer/inner with anonymous & forwarding.
      def outer(&)
        inner(&)
      end

      def inner(&block)
        block.call
      end

      outer { puts "1-top-level" }

      # 2. Anonymous & with a body that does work before forwarding.
      def with_prefix(label, &)
        puts label
        inner(&)
      end

      with_prefix("2-prefix") { puts "  body" }

      # 3. Anonymous & on a class instance method, forwarding to another
      #    class instance method via typed-receiver dispatch.
      class Outer
        def kick(&)
          sink(&)
        end

        def sink(&block)
          block.call
        end
      end

      Outer.new.kick { puts "3-class-method" }
    RUBY

    _(result).must_answer "1-top-level\n2-prefix\n  body\n3-class-method\n"
  end

  it "block local shadow" do
    result = zr(<<~'RUBY')
      # A block-local declaration (`|x; sum|`) introduces a fresh variable scoped to
      # the block: it shadows any enclosing local of the same name, is reset to nil on
      # each block invocation, and must never leak its writes back out.

      # shadows an enclosing local -- the outer value survives untouched
      sum = 99
      [1].each { |x; sum| sum = x }
      p sum                                  # 99

      # reset to nil each invocation (so `sum || 0` starts from 0 every element)
      total = 42
      [1, 2, 3].each { |x; total| total = (total || 0) + x }
      p total                                # 42

      # two block-locals, both shadowing
      a = 1
      b = 2
      [0].each { |z; a, b| a = 7; b = 8 }
      p [a, b]                               # [1, 2]

      # a nested block-local shadows while the outer block variable stays intact
      r = 0
      [5].each do |i|
        [9].each { |j; r| r = j }
        r = i
      end
      p r                                    # 5

      # a block-local coexisting with a param of a different name
      n = 100
      [10, 20].each { |v; n| n = v }
      p n                                    # 100
    RUBY

    _(result).must_answer <<~'OUT'
      99
      42
      [1, 2]
      5
      100
    OUT
  end

  it "block optional unused" do
    result = zr(<<~'RUBY')
      class Greeter
        def greet(text = nil, &block)
          puts text || "anonymous"
          yield if block
        end

        def call_internal
          greet("internal")
        end
      end

      Greeter.new.greet("hi")
      Greeter.new.call_internal

      def forwarder(&block)
        Greeter.new.greet("forwarded", &block)
      end
      forwarder { puts "  block received" }
    RUBY

    _(result).must_answer "hi\ninternal\nforwarded\n  block received\n"
  end

  it "block param call block given" do
    result = zr(<<~'RUBY')
      # A method that captures its block as `&blk` AND calls `block_given?`
      # calls the block through `blk.call`. `block_given?` does not change
      # how the literal block reaches `blk`.

      # 1. Top-level &blk + block_given? + blk.call.
      def build(&blk)
        blk.call(42) if block_given?
      end
      build { |x| puts x }              #=> 42

      # 2. Expression context: the call result is consumed.
      def build_v(&blk)
        r = blk.call(21) if block_given?
        r
      end
      puts build_v { |x| x * 2 }        #=> 42

      # 3. Instance method.
      class Foo
        def run(&blk)
          blk.call(7) if block_given?
        end
      end
      Foo.new.run { |x| puts x }        #=> 7

      # 4. Singleton (class) method.
      class Bar
        def self.make(&blk)
          blk.call(9) if block_given?
        end
      end
      Bar.make { |x| puts x }           #=> 9

      # 5. A method mixing &blk and an actual yield still works.
      def mix(&blk)
        yield 5 if block_given?
      end
      mix { |x| puts x }                #=> 5

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      7
      9
      5
      done
    OUT
  end

  it "block param call value return" do
    result = zr(<<~'RUBY')
      # An &block-param method called with a literal block returns the
      # value of blk.call, typed by the block body's return type rather than
      # as an Integer. Different literal blocks at the same method can give
      # values of different types.

      def applies(&blk)
        blk.call("hi")
      end

      # string-returning block: the carried pointer prints as a string,
      # not a raw address.
      puts applies { |x| x.upcase }

      # int-returning block at the SAME method: per-call-site typing, no
      # signature change.
      puts applies { |x| x.length }

      # block body that does not depend on the param's type works for
      # instance methods too (value-return typing is receiver-agnostic).
      class Runner
        def run(&blk)
          blk.call("hi")
        end
      end
      puts Runner.new.run { "fixed" }
      puts Runner.new.run { |x| "got" }

      # instance &block method whose block body depends on the yielded arg's
      # type: the block param is typed from blk.call's arg (string here), so
      # string methods resolve.
      puts Runner.new.run { |x| x.upcase }
    RUBY

    _(result).must_answer <<~'OUT'
      HI
      2
      fixed
      got
      HI
    OUT
  end

  it "break and next inside a yielded block behave like real ruby" do
    result = zr(<<~'RUBY')
      # `next` skips to the next yield; `break value` makes the WHOLE call
      # (`each_num(...)`) evaluate to that value, stopping further yields.

      class Collector
        def each_num(a, b, c)
          yield a
          yield b
          yield c
        end
      end
      result = Collector.new.each_num(1, 2, 3) { |n| next if n == 2; break "stopped" if n == 3; puts n }
      puts result
    RUBY

    _(result).must_answer "1\nstopped\n"
  end

  it "break leaves the define method call it was given to" do
    result = zr(<<~'RUBY')
      class W < Array
        define_method(:each) { |*args, &blk| super(*args, &blk) }
      end
      p W.new([1, 2, 3]).take(2)
      def via_each(o)
        o.each { |x| break x * 10 }
      end
      p via_each(W.new([4, 5]))
      class V < Array
        def each(*args, &blk) = super(*args, &blk)
      end
      p V.new([1, 2, 3]).take(2)
      class U < Array
        define_method(:each) { |&blk| [9].each { |x| blk.call(x) }; :fell_through }
      end
      p(U.new.each { |x| break x + 1 })
      class T2
        define_method(:run) { |&b| b }
      end
      pr = T2.new.run { break 5 }
      begin; pr.call; rescue LocalJumpError => e; p e.reason; end


    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      40
      [1, 2]
      10
      :break
    OUT
  end

  it "break needs the call its block was given to" do
    result = zr(<<~'RUBY')
      # A `break` leaves the call its block was given to. Once that call has
      # returned there is nothing to leave, even while the method the block was
      # written in still runs, and the break is a LocalJumpError. A shareable
      # Proc is cut off from its method, so neither `break` nor `return` has
      # anywhere to go.
      def make(&b) = b
      def kept
        make { break 1 }.call
      rescue LocalJumpError => e
        "kept: #{e.message} (#{e.reason}, #{e.exit_value.inspect})"
      end
      p kept

      def through(&b) = b.call
      p through { break 2 }
      p [1, 2, 3].each { |x| break x * 10 if x == 2 }
      def yielder = yield
      p yielder { break 3 }
      def forward(&b) = [1].map(&b)
      p forward { break 4 }
      p loop { break 5 }
      p 3.times { break 6 }
      def nested = [1].each { [2].each { break 9 }; break 10 }
      p nested
      p send(:yielder) { break 11 }
      p 1.then { break 12 }

      pr = proc { break 8 }
      begin
        pr.call
      rescue LocalJumpError => e
        puts "a proc: #{e.message}"
      end

      def m = yield
      begin
        p m(&Ractor.shareable_proc { break 1 })
      rescue LocalJumpError => e
        puts "a shareable break: #{e.message}"
      end

      def shareable_return
        Ractor.shareable_proc { return 1 }.call
        2
      end
      begin
        p shareable_return
      rescue LocalJumpError => e
        puts "a shareable return: #{e.message}"
      end

      def plain_return
        pr = proc { return 1 }
        pr.call
        2
      end
      p plain_return
      def kept_return
        make { return 3 }.call
        4
      end
      p kept_return

    RUBY

    _(result).must_answer <<~'OUT'
      "kept: break from proc-closure (break, 1)"
      2
      20
      3
      4
      5
      6
      10
      11
      12
      a proc: break from proc-closure
      a shareable break: break from proc-closure
      a shareable return: unexpected return
      1
      3
    OUT
  end

  it "a kept block that breaks after the call at its site returned is a LocalJumpError, however it is called" do
    result = zr(<<~'RUBY')
      # The call at the block's site has returned, so a later call of the
      # kept block, or a later call that gets it with `&`, has no call to
      # leave. The method that wrote the block still runs.
      def capture(&b) = b
      def yielding = yield
      def call_it(b) = b.call

      def later(how)
        b = capture { break :gone }
        case how
        when :call then b.call
        when :method then call_it(b)
        when :yield then yielding(&b)
        when :exec then Object.new.instance_exec(&b)
        end
      rescue LocalJumpError => e
        "#{how}: #{e.message}"
      end
      %i[call method yield exec].each { |how| puts later(how) }
    RUBY

    _(result).must_answer <<~'OUT'
      call: break from proc-closure
      method: break from proc-closure
      yield: break from proc-closure
      exec: break from proc-closure
    OUT
  end

  it "case local in lambda" do
    result = zr(<<~'RUBY')
      # A local assigned inside a `case`/`when` branch of a lambda/proc
      # body is a local of that lambda, as it is for an `if`/`while`
      # branch. It can be read after the branch.

      # 1. case-branch local, read after the branch.
      f = lambda do |t|
        case t
        when :a
          x = 10
          x + 1
        end
      end
      puts f.call(:a)                   #=> 11

      # 2. proc form, same shape.
      g = proc do |t|
        case t
        when :b
          y = 20
          y * 2
        end
      end
      puts g.call(:b)                   #=> 40

      # 3. Closure mutation inside a case branch updates the captured
      #    outer variable (not a shadowing proc-local).
      acc = 0
      h = lambda do |t|
        case t
        when :a
          acc = acc + 10
        when :b
          acc = acc + 100
        end
        acc
      end
      h.call(:a)
      h.call(:b)
      puts acc                          #=> 110

      # 4. if-branch local in a lambda (the already-working sibling path,
      #    kept as a guard).
      k = lambda do |n|
        if n > 0
          m = n * 3
          m + 1
        else
          0
        end
      end
      puts k.call(4)                    #=> 13

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      11
      40
      110
      13
      done
    OUT
  end

  it "lambda explicit return" do
    result = zr(<<~'RUBY')
      # An explicit `return <value>` inside a lambda/proc body must carry its
      # value out through `.call` instead of being lost (returning 0). The proc
      # return-type inference has to consider the ReturnNode tail, not only an
      # implicit tail expression, so the call site and the body's return channel
      # agree on the type.
      f = lambda { return 7 }
      puts f.call

      g = -> { return 42 }
      puts g.call

      # Explicit return of a non-int value.
      s = lambda { return "hi" }
      puts s.call

      fl = lambda { return 1.5 }
      puts fl.call

      # Explicit return that uses the block parameter.
      dbl = lambda { |x| return x * 2 }
      puts dbl.call(5)

      # Routed through a method parameter (defeats any constant-folding of the
      # receiver, exercising the general proc-call path).
      def via(p)
        p.call
      end
      puts via(lambda { return 99 })

      # Conditional explicit return with a matching implicit tail type.
      pick = lambda { |n| return 0 if n.negative?; n + 1 }
      puts pick.call(-3)
      puts pick.call(4)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      42
      hi
      1.5
      10
      99
      0
      5
    OUT
  end

  it "lifted block nonlocal return" do
    result = zr(<<~'RUBY')
      # A `return` inside a block that is lifted to a proc.
      #
      # `@graph.adj[v].each { }` has a poly receiver, so the dispatch materializes
      # the block as a real proc. The `return` in it must leave the METHOD, not just
      # the proc: without a proc-return frame the value went to the proc's own return
      # slot and the search kept looping, answering -1 for every reachable target.
      #
      # The destructuring `v, dist = queue.shift` writes a local the lifted block
      # captures, so its target is a heap cell rather than a plain C local.

      class Graph
        attr_reader :adj, :vertices
        def initialize(n)
          @vertices = n
          @adj = Array.new(n) { [] }
        end
        def add(a, b)
          @adj[a] << b
          @adj[b] << a
        end
        def each(&blk)
          @adj.each(&blk)
        end
      end

      class Other
        attr_reader :adj, :vertices
        def initialize; @adj = []; @vertices = 0; end
        def each; yield 1; end
      end

      class Solver
        def initialize(g)
          @graph = g
        end
        def bfs(start, target)
          return 0 if start == target
          visited = Array.new(@graph.vertices, 0)
          queue = [[start, 0]]
          visited[start] = 1
          while !queue.empty?
            v, dist = queue.shift
            @graph.adj[v].each do |neighbor|
              if neighbor == target
                return dist + 1
              end
              if visited[neighbor] == 0
                visited[neighbor] = 1
                queue << [neighbor, dist + 1]
              end
            end
          end
          -1
        end
      end

      def pick(f)
        f ? Graph.new(6) : Other.new
      end

      g = pick(true)
      g.add(0, 1); g.add(1, 2); g.add(2, 3); g.add(0, 4); g.add(4, 5)
      s = Solver.new(g)
      p s.bfs(0, 3)
      p s.bfs(0, 5)
      p s.bfs(0, 0)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      0
    OUT
  end

  it "nonlocal return" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `return` written in a block leaves the METHOD, not the block. The
      # value travels as a signal aimed at the activation the proc holds; the
      # method's boundary folds it, and a dead activation answers
      # LocalJumpError.

      def first_over(list, limit)
        list.each { |n| return n if n > limit }
        :none
      end

      p first_over([1, 2, 3, 4], 2), first_over([1, 2], 9)

      # The signal names ONE activation, so the return lands in the frame that
      # wrote it rather than in whichever frame catches first.
      def countdown(n)
        return :floor if n.zero?

        [n].each do |x|
          reached = countdown(x - 1)
          return "#{reached}/#{n}" if n == 1
        end
        :walked
      end
      p countdown(3), countdown(1)

      # Two blocks deep, and through a method that only relays the proc.
      def relay(&block) = run(block)
      def run(block) = [block.call, :unreached]

      def through
        relay { return :through }
        :no
      end
      p through

      def deep
        [[1, 2], [3, 4]].each do |pair|
          pair.each { |n| return n if n > 2 }
        end
        :none
      end
      p deep

      # A proc that outlives the method it was written in has nowhere to
      # return to.
      def escaped = proc { return :nowhere }

      begin
        escaped.call
      rescue LocalJumpError => e
        p e.class
      end

      # A lambda catches its own `return` and its own `break`: both are the
      # lambda's value, and the method around it carries on.
      def lambdas
        answer = -> (n) { return n * 2 }
        broken = -> (n) { break n + 1 }
        [answer.call(4), broken.call(4), :carried_on]
      end
      p lambdas

      # `return` with no value is nil, and the value is read before `$!`
      # unwinds.
      def bare
        [1].each { return }
        :no
      end
      p bare

      def rescued
        [1].each do |_|
          raise ArgumentError, "held"
        rescue ArgumentError
          return $!.message
        end
      end
      p rescued

      # A block that returns is still an ordinary block everywhere else.
      def mixed(list)
        seen = list.map do |n|
          next :skip if n == 2
          return :big if n > 3

          n
        end
        [:finished, seen]
      end
      p mixed([1, 2, 3]), mixed([1, 4])
    RUBY

    _(result).must_answer <<~'OUT'
      3
      :none
      :walked
      "floor/1"
      :through
      3
      LocalJumpError
      [8, 5, :carried_on]
      nil
      "held"
      [:finished, [1, :skip, 3]]
      :big
    OUT
  end

  it "proc call value return" do
    result = zr(<<~'RUBY')
      # `lambda {}` / `proc {}` (method-call form) record their block's return
      # type, so `.call` gives a value of that type, not an Integer.
      f = lambda { "hello" }
      puts f.call

      g = proc { "world" }
      puts g.call

      # An Array return value.
      h = lambda { [1, 2, 3] }
      p h.call

      # A rescue-bound exception value flows out through the same path.
      r = lambda { begin; raise "boom"; rescue => e; "msg:#{e.message}"; end }
      puts r.call

      # An Integer return value.
      n = proc { 42 }
      puts n.call
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      world
      [1, 2, 3]
      msg:boom
      42
    OUT
  end

  it "proc cell opassign returns new value" do
    result = zr(<<~'RUBY')
      # A stored proc/lambda whose body op-assigns a captured local must return the
      # POST-assignment value (not the stale pre-assignment slot), while the mutation
      # still persists in the captured variable.
      n = 5
      c = -> { n += 10 }
      p c.call
      p n

      m = 2
      d = proc { m *= 3 }
      p d.call
      p m

      # an inline (non-escaping) block accumulator is a separate path; keep it covered.
      acc = 0
      [1, 2, 3].each { acc += 1 }
      p acc
    RUBY

    _(result).must_answer <<~'OUT'
      15
      15
      6
      6
      3
    OUT
  end

  it "a non-lambda proc's return returns from the method that made the proc" do
    result = zr(<<~'RUBY')
      # A non-lambda proc's `return` returns from the method that created the proc
      # (CRuby non-local return); a lambda's `return` is local to the lambda.
      def m
        proc { return 30 }.call
        40
      end
      p m

    RUBY

    _(result).must_answer <<~'OUT'
      30
    OUT
  end

  it "a lambda's return answers the lambda, and the method carries on" do
    result = zr(<<~'RUBY')
      def lam
        -> { return 30 }.call
        40
      end
      p lam

    RUBY

    _(result).must_answer <<~'OUT'
      40
    OUT
  end

  it "a non-local return abandons the rest of the method" do
    result = zr(<<~'RUBY')
      # the non-local return aborts the rest of the method
      def compute
        r = proc { return 7 }.call
        r + 100
      end
      p compute

    RUBY

    _(result).must_answer <<~'OUT'
      7
    OUT
  end

  it "a non-local return carries a heap value home" do
    result = zr(<<~'RUBY')
      # heap (string) return value
      def smethod
        proc { return "early" }.call
        "late"
      end
      p smethod

    RUBY

    _(result).must_answer <<~'OUT'
      "early"
    OUT
  end

  it "a bare return in a proc answers nil" do
    result = zr(<<~'RUBY')
      # bare return yields nil
      def bare
        proc { return }.call
        "after"
      end
      p bare.inspect

    RUBY

    _(result).must_answer <<~'OUT'
      "nil"
    OUT
  end

  it "a conditional return in a proc returns non-locally only where the guard holds" do
    result = zr(<<~'RUBY')
      # conditional: returns non-locally only when the guard holds
      def cond(x)
        proc { return "yes" if x > 0 }.call
        "no"
      end
      p cond(5)
      p cond(-1)

    RUBY

    _(result).must_answer <<~'OUT'
      "yes"
      "no"
    OUT
  end

  it "a proc built by Proc.new returns non-locally the same way" do
    result = zr(<<~'RUBY')
      # Proc.new form
      def pnew
        Proc.new { return 99 }.call
        -1
      end
      p pnew

    RUBY

    _(result).must_answer <<~'OUT'
      99
    OUT
  end

  it "each recursive invocation owns its own proc-return frame" do
    result = zr(<<~'RUBY')
      # Recursion: each invocation owns its own proc-return frame, so the return
      # targets the correct method instance.
      def countdown(n, acc)
        proc { return acc if n == 0 }.call
        countdown(n - 1, acc + n)
      end
      p countdown(5, 0)

    RUBY

    _(result).must_answer <<~'OUT'
      15
    OUT
  end

  it "an inner returning-proc method unwinds only itself" do
    result = zr(<<~'RUBY')
      # Nested returning-proc methods: inner's return unwinds only inner.
      def inner
        proc { return "inner-ret" }.call
        "inner-normal"
      end
      def outer
        x = inner
        proc { return "outer:#{x}" }.call
        "outer-normal"
      end
      p outer

    RUBY

    _(result).must_answer <<~'OUT'
      "outer:inner-ret"
    OUT
  end

  it "a multi-value return out of a proc answers an array" do
    result = zr(<<~'RUBY')
      # Multi-value return becomes an array.
      def mv
        proc { return 1, 2, 3 }.call
        [9]
      end
      p mv

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
    OUT
  end

  it "many sequential calls each pop their own frame, returning or falling through" do
    result = zr(<<~'RUBY')
      # Many sequential calls: each non-local return (and each fall-through) pops its
      # frame, so the bounded frame stack never overflows.
      def doubled(x)
        proc { return x * 2 }.call
        -1
      end
      def maybe(x)
        proc { return 100 if x.even? }.call
        1
      end
      td = 0; ts = 0
      500.times { |i| td += doubled(i); ts += maybe(i) }
      p td
      p ts

    RUBY

    _(result).must_answer <<~'OUT'
      249500
      25250
    OUT
  end

  it "a returning proc that does not return answers its tail" do
    result = zr(<<~'RUBY')
      # Fall-through value: a returning proc that does NOT return still yields its tail
      # expression (the `.call` result is the method's value). Mixed return/tail types
      # unify to a poly home; same-type stays scalar.
      def tail_or_ret(n)
        proc { return 99 if n < 0; "tail" }.call
      end
      p tail_or_ret(5)
      p tail_or_ret(-1)

    RUBY

    _(result).must_answer <<~'OUT'
      "tail"
      99
    OUT
  end

  it "the same fall-through answers an Integer tail" do
    result = zr(<<~'RUBY')
      def tail_int(n)
        proc { return 5 if n < 0; 10 }.call
      end
      p tail_int(1)
      p tail_int(-1)

    RUBY

    _(result).must_answer <<~'OUT'
      10
      5
    OUT
  end

  it "a return inside an inlined iteration block returns from the enclosing method" do
    result = zr(<<~'RUBY')
      # A `return` inside an inlined iteration block is non-local: it returns from the
      # home method, not just the block, so the trailing statement is skipped.
      def first_even_times_ten
        proc { [1, 2, 3].each { |x| return x * 10 if x == 2 }; :fell }.call
        :after
      end
      p first_even_times_ten

    RUBY

    _(result).must_answer <<~'OUT'
      20
    OUT
  end

  it "an inlined block that fires no return answers its tail" do
    result = zr(<<~'RUBY')
      # Inlined block that falls through (no return fires) -- its tail is the value.
      def all_fall_through
        proc { [1, 2, 3].each { |x| x * 10 }; :fell }.call
      end
      p all_fall_through

    RUBY

    _(result).must_answer <<~'OUT'
      :fell
    OUT
  end

  it "a block-body local survives beside a non-local return from the block" do
    result = zr(<<~'RUBY')
      # Block-body local plus a non-local return from inside the block.
      def block_local_return
        proc { [1, 2, 3].each { |x| y = x * 10; return y if x == 2 }; :fell }.call
      end
      p block_local_return

    RUBY

    _(result).must_answer <<~'OUT'
      20
    OUT
  end

  it "each_with_index inside a returning proc returns non-locally" do
    result = zr(<<~'RUBY')
      # each_with_index inside a returning proc.
      def index_of_twenty
        proc { [10, 20, 30].each_with_index { |v, i| return i if v == 20 }; -1 }.call
      end
      p index_of_twenty

    RUBY

    _(result).must_answer <<~'OUT'
      1
    OUT
  end

  it "map inside a proc collects, with no return to fire" do
    result = zr(<<~'RUBY')
      # map (a collecting block) inside a proc, no return.
      def doubled_array
        proc { [1, 2, 3].map { |x| x * 2 } }.call
      end
      p doubled_array

    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6]
    OUT
  end

  it "nested inlined blocks carry a non-local return out through both" do
    result = zr(<<~'RUBY')
      # Nested inlined blocks (block within block) with a non-local return.
      def nested_blocks_return
        proc { [1, 2].each { |a| [3, 4].each { |b| return a * b if a == 2 && b == 4 } }; 0 }.call
      end
      p nested_blocks_return

    RUBY

    _(result).must_answer <<~'OUT'
      8
    OUT
  end

  it "sibling inlined blocks that reuse a parameter name share one declaration" do
    result = zr(<<~'RUBY')
      # Sibling inlined blocks reusing a param name share one declaration.
      def sibling_param_reuse
        proc { [1, 2].each { |x| return x if x == 2 }; [3, 4].each { |x| return x }; 0 }.call
      end
      p sibling_param_reuse

    RUBY

    _(result).must_answer <<~'OUT'
      2
    OUT
  end

  it "deep recursion through a returning-proc method grows the frame stack and unwinds it" do
    result = zr(<<~'RUBY')
      # Deep recursion through a returning-proc method: the frame stack grows past the
      # old fixed cap (256) rather than raising SystemStackError.
      def countdown_to_zero(n)
        return n if n <= 0
        proc { return countdown_to_zero(n - 1) }.call
      end
      p countdown_to_zero(2000)

    RUBY

    _(result).must_answer <<~'OUT'
      0
    OUT
  end

  it "a fiber whose body holds an inlined block keeps that block's own locals" do
    result = zr(<<~'RUBY')
      # A fiber whose body contains an inlined block: the block params/locals are
      # collected for the fiber function (parallels the proc collection fix).
      fib = Fiber.new do
        total = 0
        [1, 2, 3].each { |x| total += x }
        Fiber.yield total
      end
      p fib.resume
    RUBY

    _(result).must_answer <<~'OUT'
      6
    OUT
  end

  it "proc return escape localjump" do
    result = zr(<<~'RUBY')
      # A non-lambda proc whose home method exits via an exception (not a normal
      # return) and is called afterwards raises LocalJumpError, as in CRuby -- the
      # home node is dropped as the exception unwinds the method, so the later return
      # finds no live home rather than jumping into a freed stack frame.
      $escaped = nil
      def home
        $escaped = proc { return 99 }
        raise "boom"
      end
      begin
        home
      rescue => e
        puts "rescued: #{e.message}"
      end
      begin
        $escaped.call
        puts "WRONG: no error"
      rescue LocalJumpError => e
        puts "localjump: #{e.message}"
      end
    RUBY

    _(result).must_answer "rescued: boom\nlocaljump: unexpected return\n"
  end

  it "proc return scopes" do
    result = zr(<<~'RUBY')
      la = lambda { return 5 }
      p la.call
      def m; pr = proc { return 7 }; pr.call; 9; end
      p m
      puts "still here"
      pr2 = proc { |x| x * 2 }
      p pr2.call(3)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      7
      still here
      6
    OUT
  end

  it "proc universal return" do
    result = zr(<<~'RUBY')
      # Universal boxed proc return (CRuby's uniform VALUE proc ABI): a first-class
      # proc publishes its result through one boxed return channel regardless of the
      # value's static type, so a proc reached through a type-erased path -- stored in
      # an ivar, forwarded, returned from a method -- yields the right value for every
      # return kind. Direct monomorphic calls are unchanged.

      # Direct calls across every return kind.
      puts((-> { 42 }).call)
      puts((-> { "hi" }).call)
      p((-> { [1, 2, 3] }).call)
      puts((-> { 3.5 }).call)
      p((-> { :sym }).call)
      p((-> { { a: 1 } }).call)
      p((-> { (1..3) }).call)
      p((-> { true }).call)

      # Explicit return of each kind (interior + tail return routing through the slot).
      f = lambda { |n| return "neg" if n.negative?; n * 2 }
      puts f.call(-1)
      puts f.call(5)

      # A proc stored in an ivar and called back (the escaped path the old escape
      # analysis had to special-case; now every proc rides the boxed channel).
      class Holder
        def store(&blk)
          @blk = blk
        end

        def run(x)
          @blk.call(x)
        end
      end
      h = Holder.new
      h.store { |x| x * 3 }
      puts h.run(14)

      # A proc returned across a method boundary, then called by the caller.
      def make_adder(n)
        ->(x) { x + n }
      end
      puts make_adder(100).call(5)

      # Composition and curry thread the boxed channel between stages.
      inc = ->(x) { x + 1 }
      dbl = ->(x) { x * 2 }
      puts (inc >> dbl).call(10)
      puts (inc << dbl).call(10)

      # `next`/`break <expr>` carry a value out of a proc too, so a proc whose
      # next/break value type differs from its tail must widen to the boxed channel
      # (else the .call site trusts the tail's scalar type and mis-unboxes the other
      # path). Both direct and through the type-erased ivar path.
      nx = ->(x) { next "s" if x > 0; 42 }
      p nx.call(3)      # "s"
      p nx.call(-1)     # 42
      bk = ->(x) { break [x, x] if x > 0; 7 }
      p bk.call(2)      # [2, 2]
      p bk.call(-1)     # 7

      relay = Holder.new
      relay.store { |x| next :sym if x > 0; 9 }
      p relay.run(1)    # :sym
      p relay.run(-1)   # 9
    RUBY

    _(result).must_answer <<~'OUT'
      42
      hi
      [1, 2, 3]
      3.5
      :sym
      {a: 1}
      1..3
      true
      neg
      10
      42
      105
      22
      21
      "s"
      42
      [2, 2]
      7
      :sym
      9
    OUT
  end

  it "recursive block forward value" do
    result = zr(<<~'RUBY')
      # A method that forwards its &block down a recursive call and returns
      # the result carries the block's value back. The tail is the recursive
      # call (its value must be returned, not dropped for side-effect), and
      # the governing blk.call is in the base case `return blk.call if ...`.

      def countdown(n, &blk)
        return blk.call if n <= 0
        countdown(n - 1) { blk.call }
      end

      # string block: the value comes back through every recursive call and is
      # typed string via the base-case return.
      puts countdown(2) { "done" }

      # int block at the same method
      puts countdown(3) { 42 }

      # depth 0 (base case taken immediately)
      puts countdown(0) { "base" }
    RUBY

    _(result).must_answer <<~'OUT'
      done
      42
      base
    OUT
  end

  it "redo inside a yielded block reruns without advancing" do
    result = zr(<<~'RUBY')
      class Collector
        def each_num(a, b)
          yield a
          yield b
        end
      end
      attempts = 0
      Collector.new.each_num(1, 2) do |n|
        attempts += 1
        if n == 1 && attempts < 2
          redo
        end
        puts "n=#{n} attempts=#{attempts}"
      end
    RUBY

    _(result).must_answer "n=1 attempts=2\nn=2 attempts=3\n"
  end

  it "return in a block leaves the lambda around it" do
    result = zr(<<~'RUBY')
      # A `return` written in a block that sits inside a lambda leaves the
      # lambda, not the method that made the lambda: a lambda is the innermost
      # frame a return can name.
      def first(items)
        f = ->(list) {
          list.each do |x|
            return x if x > 1
          end
          :fell_through
        }
        [f.call(items), :after]
      end

      p first([1, 2, 3])
      p first([0, 1])

      # Two blocks deep inside the lambda.
      def deep
        g = ->(rows) {
          rows.each do |row|
            row.each do |cell|
              return cell if cell == :found
            end
          end
          :none
        }
        [g.call([[:a], [:found, :b]]), g.call([[:a]])]
      end

      p deep

      # A plain block inside a method still returns from the method.
      def plain
        [1, 2].each { |x| return x }
        :not_here
      end

      p plain

      # The lambda ended, so its frame answers no return any more.
      def escaped
        ->(_) { proc { return :late } }.call(nil)
      end

      held = escaped
      begin
        held.call
      rescue LocalJumpError => e
        p [e.class, e.message]
      end

      # An ensure on the way out of the lambda runs.
      def with_ensure
        h = -> {
          [1].each do
            begin
              return :body
            ensure
              puts "ensure ran"
            end
          end
        }
        h.call
      end

      p with_ensure

      # A lambda inside a lambda: the innermost one takes the return.
      outer = ->(n) {
        inner = ->(m) {
          [m].each { |x| return x * 2 }
          :inner_fell
        }
        [inner.call(n), :outer_went_on]
      }
      p outer.call(5)

    RUBY

    _(result).must_answer <<~'OUT'
      [2, :after]
      [:fell_through, :after]
      [:found, :none]
      1
      [LocalJumpError, "unexpected return"]
      ensure ran
      :body
      [10, :outer_went_on]
    OUT
  end

  it "scope boundary stops the block and return walks" do
    result = zr(<<~'RUBY')
      # The walks that ask "does this body use its block?", "does it contain a
      # `super`?" and "does a `begin` here need the method's return catch?" all stop
      # at the same three boundaries. These are the boundaries, exercised from the
      # outside.

      # A `def` nested in a method body is a fresh scope: its `yield` is its OWN
      # block's, and the enclosing method needs no block parameter for it.
      class Definer
        def install
          def installed
            yield :from_installed
          end
          :installed
        end
      end

      d = Definer.new
      p d.install
      p(d.installed { |v| "inner got #{v}" })

      # A `class` body is the same boundary.
      def define_holder
        Class.new do
          def speak
            yield :never
          end
        end
        :defined
      end

      p define_holder

      # A lambda catches its OWN `return`: it returns from the lambda, never from
      # the enclosing method, so the method keeps running.
      def lambda_return
        l = -> { return :from_lambda }
        [l.call, :method_continued]
      end

      p lambda_return

      # ...while a `return` in a plain block returns from the METHOD, which is the
      # case the `begin`/rescue catch exists for.
      def block_return
        [1, 2].each { |v| return :"returned_at_#{v}" }
        :never_reached
      end

      p block_return

      # A `begin` wrapping that block still lets the method-level return through.
      def rescued_block_return
        begin
          [1].each { return :through_begin }
        rescue StandardError
          :rescued
        end
        :never_reached
      end

      p rescued_block_return

      # A block and a lambda have no `super` target of their own, so a `super`
      # inside one targets the enclosing METHOD -- neither is a stop.
      class Sup
        def name; "sup"; end
      end

      class SubSup < Sup
        def name
          ["x"].map { super }.first + "!"
        end
      end

      p SubSup.new.name
    RUBY

    _(result).must_answer <<~'OUT'
      :installed
      "inner got from_installed"
      :defined
      [:from_lambda, :method_continued]
      :returned_at_1
      :through_begin
      "sup!"
    OUT
  end

  it "spread block keeps its arguments while they bind" do
    result = zr(<<~'RUBY')
      # A block that spreads a lone argument over its parameters reads the
      # Array `to_ary` answered while its parameters bind, and a default or
      # a destructuring parameter runs Ruby in between: the Array stays
      # alive across a collection, and a default that changes it changes
      # nothing the block was called with, as ruby copies the arguments
      # before any default runs.

      class Fresh
        def to_ary = [1, 2]
      end

      def each_fresh
        yield Fresh.new
      end

      out = each_fresh { |a, b = (GC.start; "x" * 100_000; :default), c| [a, b, c] }
      p out

      class Shared
        attr_reader :items
        def initialize = @items = [1, 2]
        def to_ary = @items
      end

      shared = Shared.new
      p each_fresh { |a, b = (shared.items.concat([0] * 10_000); :grown), c| [a, b, c] }.tap { shared.items.replace([1, 2]) }
      p each_fresh { |a, b = (shared.items[1] = :changed; :written), c| [a, b, c] }.tap { shared.items.replace([1, 2]) }
      p each_fresh { |a, b = (shared.items.clear; :cleared), c| [a, b, c] }.tap { shared.items.replace([1, 2]) }

      # A destructured first parameter whose `to_ary` grows the Array the
      # block spreads, then the parameters after it.
      class Growing
        def initialize(items) = @items = items
        def to_ary
          @items.concat([0] * 10_000)
          [:x, :y]
        end
      end

      def yield_growing
        items = [nil, 2, 3]
        items[0] = Growing.new(items)
        yield items
      end

      p yield_growing { |(x, y), c, d| [x, y, c, d] }

    RUBY

    _(result).must_answer <<~'OUT'
      [1, :default, 2]
      [1, :grown, 2]
      [1, :written, 2]
      [1, :cleared, 2]
      [:x, :y, 2, 3]
    OUT
  end

  it "toplevel proc return" do
    result = zr(<<~'RUBY')
      puts "before"
      pr001 = proc { return 1 }
      r001 = (pr001.call rescue $!.class)
      p r001
      puts "after"
    RUBY

    _(result).must_answer "before\n"
  end

  it "upto downto block" do
    result = zr(<<~'RUBY')
      # upto/downto with a block: the body must run whether or not the block declares
      # a parameter, so a no-param block (`1.upto(5) { h += 1 }`) gives 5, not 0.
      # A declared param is rebound each iteration, so
      # mutating it inside the block does not perturb the loop (CRuby semantics).
      h = 0
      1.upto(5) { h += 1 }
      puts h                      # 5

      i = 0
      1.upto(5) { |n| i += n }
      puts i                      # 15

      c = 0
      5.downto(1) { c += 1 }
      puts c                      # 5

      s = 0
      1.upto(3) { |n| n += 100; s += n }
      puts s                      # 306

      d = 0
      9.downto(7) { |n| d += n }
      puts d                      # 24
    RUBY

    _(result).must_answer <<~'OUT'
      5
      15
      5
      306
      24
    OUT
  end

  it "yield and block given branch on whether a block was passed" do
    result = zr(<<~'RUBY')
      class Foo
        def maybe_yield
          if block_given?
            yield 42
          else
            -1
          end
        end
      end
      f = Foo.new
      puts f.maybe_yield { |x| x * 2 }
      puts f.maybe_yield
    RUBY

    _(result).must_answer "84\n-1\n"
  end

  it "yield call assigned return" do
    result = zr(<<~'RUBY')
      # A top-level method that yields, called with a literal block, and the
      # result assigned (`x = measure { ... }`). The block runs, and the
      # variable gets the value of the method's last statement.

      def measure
        yield
        42
      end

      x = measure { puts "block" }
      puts x.to_s         # 42

      # Last stmt is a local read (after locals + yield).
      def assign_last
        yield
        z = 99
        z
      end

      w = assign_last { puts "hi" }
      puts w.to_s         # 99

      # String return type
      def str_call
        yield
        "result"
      end

      s = str_call { puts "in" }
      puts s
    RUBY

    _(result).must_answer <<~'OUT'
      block
      42
      hi
      99
      in
      result
    OUT
  end

  it "yield value mixed block types" do
    result = zr(<<~'RUBY')
      # A class-method with `yield` inlined at two call sites whose blocks return
      # DIFFERENT types: each call site gets the value of its own block, with that
      # block's type. An Integer result is not read as a String.
      class Box
        def initialize(s)
          @s = s
        end
        def content
          @s
        end
        def self.make(s)
          b = Box.new(s)
          if block_given?
            yield b
          else
            b
          end
        end
      end

      r = Box.make("foo") { |b| b.content }
      n = Box.make("hello") { |b| b.content.length }
      p r
      p n
      m = Box.make("tail")
      p m.content
    RUBY

    _(result).must_answer <<~'OUT'
      "foo"
      5
      "tail"
    OUT
  end

  it "yield value return" do
    result = zr(<<~'RUBY')
      # A yield-using method called with a literal block returns the yielded
      # value, typed by the block's return type (not the int default). Covers
      # instance + top-level methods, expression / assignment contexts, and
      # value vs string vs concat-with-yield bodies.

      # int yield, instance method, expression position
      class W
        def s
          yield
        end
      end
      puts W.new.s { 7 }

      # string yield, instance method (bare yield is the return value)
      puts W.new.s { "str" }

      # string yield used inside the method body (concat with yield)
      class G
        def wrap
          "[" + yield + "]"
        end
      end
      puts G.new.wrap { "x" }

      # top-level method, string yield
      def t
        yield
      end
      puts t { "hi" }

      # string yield stored in a local: the pointer round-trips through the
      # int slot and reads back as a string (no -Wint-conversion).
      sv = W.new.s { "str" }
      puts sv

      # assignment context with an int yield (no pointer round-trip)
      n = W.new.s { 11 }
      puts n

      # block with a parameter, int arithmetic
      class A
        def give
          yield 5
        end
      end
      puts A.new.give { |x| x + 1 }

      # yield value flowing through interpolation
      def deco
        "<#{yield}>"
      end
      puts deco { "body" }
    RUBY

    _(result).must_answer <<~'OUT'
      7
      str
      [x]
      hi
      str
      11
      6
      <body>
    OUT
  end
  it "an each or a times with a block literal runs in place, and a program sees what the call gave it" do
    result = zr(<<~'RUBY')
      # `ary.each { |x| }` and `n.times { |i| }` run in place at the site: the
      # loop and the block's body in the caller's own function, with a frame
      # for the builtin and one for the block linked under the caller's for
      # the loop's duration. What a program sees is what the call gave it:
      # the frames in a backtrace, `break`, `next`, `redo` and `return`, an
      # exception rescued outside or inside, an ensure, the receiver mutated
      # as it is walked, a block-local reset every turn, the answer, and a
      # redefinition of the method, a subclass, or any other receiver, which
      # take the call.
      def frames = caller(0).map { |l| l[/in '(.*)'/, 1] }
      def f
        [1].each { |x| p frames }
        2.times { |i| p frames if i == 1 }
        [1].each { |x| [2].each { |y| p frames } }
      end
      f
      def g
        [1, 2, 3].each { |x| return x * 10 if x == 2 }
        :never
      end
      p g
      r = []
      [1, 2, 3, 4].each { |x| next if x.odd?; r << x }
      p r
      p [1, 2, 3].each { |x| break x + 100 if x == 2 }
      p 5.times { |i| break i if i == 3 }
      seen = 0
      [1, 2].each { |x| seen += 1; redo if seen == 1 }
      p seen
      a = [1]
      a.each { |x| a << x + 1 if a.size < 4 }
      p a
      b = [1, 2, 3, 4]
      b.each { |x| b.pop }
      p b
      p [1, 2].each { |x; y| y = (y || 0) + x; p y }
      begin
        [1, 2].each { |x| raise "in #{x}" if x == 2 }
      rescue => e
        p [e.message, e.backtrace.map { |l| l[/in '(.*)'/, 1] }]
      end
      p frames
      x = [1, 2].each { |v| begin; raise "no" if v == 1; rescue; p [:rescued, v]; ensure; p [:ensured, v]; end }
      p x
      p((1..3).to_a.each { |i| "a#{i}" =~ /a(\d)/ && p($1) })
      def h = yield 5
      p h { |v| [1].each { |x| p [v, x] }; 3.times { |i| next i } }
      class MyArray < Array; def each = :mine; end
      p MyArray.new([1]).each { |x| raise }
      p({ a: 1 }.each { |k, v| p [k, v] })
      p (2**70).times { break :big }
      p [1, 2].each.next
      p 3.times.to_a
      t = 0
      th = Thread.new { 200_000.times { |i| t += 1 } }
      Thread.pass
      th.join
      p t
      n = 0
      100_000.times { |i| [1, 2].each { |x| n += x } }
      p n
      class Array; def each = :redefined; end
      p [1].each { |x| raise }
      class Integer; def times = :redefined; end
      p 3.times { raise }
    RUBY

    _(result).must_answer <<~'OUT'
      ["Object#frames", "block in Object#f", "Array#each", "Object#f", "<main>"]
      ["Object#frames", "block in Object#f", "Integer#times", "Object#f", "<main>"]
      ["Object#frames", "block (2 levels) in Object#f", "Array#each", "block in Object#f", "Array#each", "Object#f", "<main>"]
      20
      [2, 4]
      102
      3
      3
      [1, 2, 3, 4]
      [1, 2]
      1
      2
      [1, 2]
      ["in 2", ["block in <main>", "Array#each", "<main>"]]
      ["Object#frames", "<main>"]
      [:rescued, 1]
      [:ensured, 1]
      [:ensured, 2]
      [1, 2]
      "1"
      "2"
      "3"
      [1, 2, 3]
      [5, 1]
      3
      :mine
      [:a, 1]
      {a: 1}
      :big
      1
      [0, 1, 2]
      200000
      300000
      :redefined
      :redefined
    OUT
  end
  it "a Range of fixnums runs each in place, to the last fixnum but not past it" do
    result = zr(<<~'RUBY')
      s = 0
      (1..5).each { |i| s += i }
      p s
      p (1...4).each { |i| s += i }
      p s
      p (3..1).each { raise }
      p (1...1).each { raise }
      p (1..2).each { |i| break i * 100 if i == 2 }
      p (2**62 - 2..2**62 - 1).each { |i| p i }
      p (2**62 - 3...2**62 - 1).each { |i| p i }
      p (1.0..2).each { } rescue p $!.class
      p ("a".."c").each { |c| print c }
      p (1..).each { |i| break i if i > 2 }
      p (1..3).each { |i| p caller(0)[1][/in '(.*)'/, 1] if i == 1 }
      n = 0
      (1..1_000_000).each { |i| n += i & 1 }
      p n
      class Range; def each = :redefined; end
      p (1..3).each { raise }
    RUBY

    _(result).must_answer <<~'OUT'
      15
      1...4
      21
      3..1
      1...1
      200
      4611686018427387902
      4611686018427387903
      4611686018427387902..4611686018427387903
      4611686018427387901
      4611686018427387902
      4611686018427387901...4611686018427387903
      TypeError
      abc"a".."c"
      3
      "Range#each"
      1..3
      500000
      :redefined
    OUT
  end
end
