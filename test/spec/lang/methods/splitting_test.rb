# frozen_string_literal: true

require "spec_helper"

describe "Methods: splitting and joining" do
  it "builtin called every way answers the same" do
    result = ze0(<<~'RUBY')
      # A builtin reached through a site's cell, through send, through a
      # Method object, through method_missing's fallback, under a refinement
      # and with keywords answers as ruby's does, and its frame names it.
      a = [3, 1, 2]
      p a.push(4), a.send(:pop), a.method(:shift).call, a.public_send(:unshift, 0), a.method(:first).unbind.bind_call(a, 2)
      h = { a: 1 }
      p h.fetch(:a), h.send(:fetch, :b, 2), (h.fetch(:c) rescue $!.class), h.method(:key?).call(:a), h.fetch(:z) { |k| k }
      p (a.push(1, 2, x: 3) rescue $!.class), a.pop(1, 2) rescue p $!.class, $!.message
      p ("x".split(",", 2, 3) rescue $!.message), [1].first(1, 2) rescue p $!.message
      module Twice
        refine Array do
          def pop = super * 2
        end
      end
      using Twice
      p [5].pop, [5].send(:pop), [5].method(:pop).call
      class Sneaky
        def method_missing(name, *args, &blk) = name == :pop ? [:missing, *args] : super
        def respond_to_missing?(name, priv = false) = name == :pop || super
      end
      p Sneaky.new.pop(1), Sneaky.new.respond_to?(:pop), (Sneaky.new.shift rescue $!.class)
      def frames = [1].each { return caller_locations(0, 3).map(&:label) }
      p frames.size >= 2
      begin
        [].fetch(3)
      rescue IndexError => e
        p e.backtrace_locations&.first&.label
      end
      p [1, 2].sum { |v| v * 2 }, [1, 2].inject(:+), (1..3).reduce(1) { |m, v| m * v }, [[1, 2]].to_h { |a, b| [b, a] }

    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, 2]
      4
      3
      [0, 1, 2]
      [0, 1]
      1
      2
      KeyError
      true
      :z
      ArgumentError
      "wrong number of arguments (given 2, expected 0..1)"
      "wrong number of arguments (given 2, expected 0..1)"
      10
      10
      10
      [:missing, 1]
      true
      NoMethodError
      true
      "Array#fetch"
      6
      3
      6
      {2 => 1}
    OUT
  end

  it "default args" do
    result = ze0(<<~'RUBY')
      # Issue #49 (default args at call sites) and the scope follow-ups.
      # Merged from default_arg_{ctor,method,inherited,partial,self_call,
      # callee_scope}.rb. Each section covers a distinct dispatch path;
      # the original split had only the dispatch path varying, so the
      # class shapes mostly didn't collide. Where they did (`Foo` was
      # reused in self_call and callee_scope for unrelated purposes) the
      # names are made path-specific (SelfDefault / CalleeFoo).

      # ---- Constructor default ----
      # `Counter.new` (no arg) and `Counter.new(7)` both need to compile.
      class Counter
        def initialize(start = 0)
          @n = start
        end
        attr_reader :n
      end
      puts Counter.new.n         # 0
      puts Counter.new(7).n      # 7

      # ---- Instance method default + inherited dispatch ----
      # Same Greeter covers both: direct call and a subclass inheriting
      # the defaulted method without redefining it.
      class Greeter
        def hello(name = "world")
          puts "Hello, #{name}"
        end
      end
      class GreeterChild < Greeter
      end
      Greeter.new.hello                # Hello, world
      Greeter.new.hello("Ruby")        # Hello, Ruby
      GreeterChild.new.hello           # Hello, world
      GreeterChild.new.hello("Ruby")   # Hello, Ruby

      # ---- Partial defaulting ----
      # Caller supplies some leading positional args; trailing defaults
      # fill the rest.
      class M
        def f(a, b = 1, c = 2)
          puts a + b + c
        end
      end
      m = M.new
      m.f(10)             # 13
      m.f(10, 20)         # 32
      m.f(10, 20, 30)     # 60

      # ---- Implicit-self call inside same class ----
      # Bare-method dispatch from within a class body must also fill in
      # the callee's defaults; previously this path called compile_call
      # _args without the defaults map.
      class SelfDefault
        def initialize
          bar
          bar(99)
        end
        def bar(x = 42)
          puts x
        end
      end
      SelfDefault.new
      # 42
      # 99

      # ---- Default expression reads @ivar ----
      # The inlined default expansion at the caller's site must resolve
      # against the call's *receiver* (here Wrapper#grab's recv `@w`),
      # not the caller's `self`. WrapperCaller has no @base, so a naive
      # inlining would either fail to compile or read the wrong instance.
      class Wrapper
        def initialize(seed)
          @base = seed
        end
        def grab(target = @base * 10)
          target
        end
      end
      class WrapperCaller
        def initialize
          @w = Wrapper.new(3)
        end
        def go
          @w.grab
        end
      end
      puts WrapperCaller.new.go        # 30

      # ---- Default expression calls a same-class bare method ----
      # CallerBar defines its own `target` returning 2, but CalleeFoo's
      # default-arg `target` must still dispatch to CalleeFoo#target
      # (returning 1) rather than the caller's vtable.
      class CalleeFoo
        def target
          1
        end
        def foo(opt = target)
          opt
        end
      end
      class CallerBar
        def target
          2     # different value — must NOT be picked up by CalleeFoo#foo
        end
        def check
          CalleeFoo.new.foo
        end
      end
      puts CallerBar.new.check         # 1
    RUBY

    _(result).must_answer <<~'OUT'
      0
      7
      Hello, world
      Hello, Ruby
      Hello, world
      Hello, Ruby
      13
      32
      60
      42
      99
      30
      1
    OUT
  end

  it "issue runtime redefine accessor" do
    result = ze0(<<~'RUBY')
      # Redefining an already-compiled method AT RUNTIME has to take effect.
      #
      # A runtime definition lands in the overlay, and only DYNAMIC dispatch consults
      # it -- so a call whose receiver class zeo knows at compile time keeps answering
      # with the compiled body. Path 1 therefore de-optimizes any name a runtime
      # definition site could install (`Compiler::runtime_redefs`), the same way a
      # guarded `undef_method` already de-optimizes its own.
      #
      # The literal-name form inside a class body is untouched: lowering desugars it
      # into an ordinary `def` before any of this, so no call survives to collect.

      class Node
        attr_accessor :value

        def initialize(v)
          @value = v
        end
      end

      n = Node.new(7)
      p n.value

      # A COMPUTED name, so the literal-name `define_method` lowering (which zeo
      # compiles as an ordinary `def`) cannot see it.
      name = [:va, :lue].join.to_sym
      Node.send(:define_method, name) { "dyn-#{@value}" }
      p [n.value, n.send(:value), Node.new(1).value]

      m = Node.new(5)
      m.define_singleton_method(:value) { "sing" }
      p [m.value, m.send(:value), n.value]

      class Other
        attr_reader :z

        def initialize
          @z = 1
        end
      end

      o = Other.new
      def o.z
        "obj-singleton"
      end
      p [o.z, Other.new.z]

      # A LITERAL name still counts once the call reaches runtime -- with an explicit
      # receiver, or through `send`, neither of which desugars.
      class Plain
        def a = "a0"
        def b = "b0"
        def c = "c0"
      end
      q = Plain.new
      Plain.define_method(:a) { "a1" }
      p [q.a, Plain.new.a]
      Plain.send(:define_method, :b) { "b1" }
      p q.b

      # A runtime `alias_method` replaces the target the same way.
      Plain.send(:alias_method, :c, :a)
      p q.c

      # The class-body form keeps its compile-time lowering, so the LAST definition
      # in the body wins and nothing de-optimizes.
      class Body
        def w = "first"
        define_method(:w) { "second" }
      end
      p Body.new.w

      # Redefining under a name nothing else uses leaves the rest of the program
      # alone: `value` above is dynamic now, `size` here is not.
      class Sized
        def size = 3
      end
      p Sized.new.size
    RUBY

    _(result).must_answer <<~'OUT'
      7
      ["dyn-7", "dyn-7", "dyn-1"]
      ["sing", "sing", "dyn-7"]
      ["obj-singleton", 1]
      ["a1", "a1"]
      "b1"
      "a1"
      "second"
      3
    OUT
  end

  it "kwargs and double splats preserve source order" do
    result = ze0(<<~'RUBY')
      # The KwArg merge: `Call`/`HashLit`/`Yield` carry ONE ordered list of
      # literal pairs and `**h` double-splats. Ruby's Hash is insertion-ordered
      # and the merge is left-to-right last-wins, so the interleaving is
      # observable. The old two-field split got the order wrong for a splat
      # before a pair and couldn't represent two splats at all. All
      # oracle-verified against ruby 4.0.6.

      def capture(**h) = h
      p capture(**{a: 1, b: 2}, c: 3)   # splat before pair
      p capture(c: 3, **{a: 1, b: 2})   # pair before splat
      p capture(**{x: 1}, **{y: 2})     # two splats
      p capture(**{x: 1}, **{x: 2})     # last-wins on dup key
      p capture(**{a: 1}, b: 2, **{c: 3})
      h = {a: 1}
      p({**h, b: 2})
      p({b: 2, **h})
      def y
        yield 1, **{k: 2, j: 3}
      end
      y { |*a| p a }
      class HasToHash
        def to_hash = {z: 99}
      end
      p capture(**HasToHash.new, w: 1)
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      {a: 1, b: 2, c: 3}
      {c: 3, a: 1, b: 2}
      {x: 1, y: 2}
      {x: 2}
      {a: 1, b: 2, c: 3}
      {a: 1, b: 2}
      {b: 2, a: 1}
      [1, {k: 2, j: 3}]
      {z: 99, w: 1}
    OUT
      lang/methods/splitting_test.rb:12: warning: key :x is duplicated and overwritten on line 12
    ERR
  end

  it "kwargs double splat forward" do
    result = ze0(<<~'RUBY')
      # Forwarding a `**hash` into a callee's keyword-rest (`**opts`) parameter.
      # The forwarded hash's entries must reach `opts`; the kwrest param keeps its
      # Symbol-keyed hash type (it receives the whole hash, not a value type).
      def collect(**opts)
        opts
      end

      h = {a: 1, b: 2}
      p collect(**h)            # {a: 1, b: 2}
      p collect(c: 3, **h)      # {c: 3, a: 1, b: 2}  -- literal before splat
      p collect(**h, a: 9)      # {a: 9, b: 2}        -- splat then literal (last wins)

      # Reading a single key back out of the kwrest hash.
      def fetch_a(**opts)
        opts[:a]
      end
      p fetch_a(**h)            # 1

      # A named keyword param alongside a kwrest: the named key is consumed,
      # the rest flow into the kwrest hash.
      def split(a:, **rest)
        [a, rest]
      end
      abc = {a: 1, b: 2, c: 3}
      p split(**abc)            # [1, {b: 2, c: 3}]

      # A positional param of the same name does NOT consume a forwarded key: the
      # key stays in the keyword-rest (only keyword params consume).
      def split_positional(a, **rest)
        [a, rest]
      end
      p split_positional(1, **abc)   # [1, {a: 1, b: 2, c: 3}]

      # Forwarding the kwrest onward to another **kw callee.
      def outer(**opts)
        collect(**opts)
      end
      p outer(x: 1, y: 2)       # {x: 1, y: 2}
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2}
      {c: 3, a: 1, b: 2}
      {a: 9, b: 2}
      1
      [1, {b: 2, c: 3}]
      [1, {a: 1, b: 2, c: 3}]
      {x: 1, y: 2}
    OUT
  end

  it "multi write call rhs as expr" do
    result = ze0(<<~'RUBY')
      # #584 (cielavenir). Multi-assignment used as an expression value
      # whose RHS is a call returning a typed array (here `gets.split.
      # map(&:to_i)` → int_array), followed by an outer subscript /
      # comparison. Previously `compile_expr`'s MultiWriteNode arm only
      # handled the ArrayNode-RHS shape (#554) and fell through to
      # `return "0"` for the call-returning-array shape -- the outer
      # `[0]` then lowered to `sp_IntArray_get(0, 0LL)` (NULL recv)
      # and segv'd on the next iteration of any consumer loop.

      def two_ints; [10, 20]; end
      def three; [7, 8, 9]; end

      # T1: call-returning-array RHS, value-of-expression form
      result = (x, y = two_ints)
      p x
      p y
      p result

      # T2: subscript chain on the value
      first = (p1, p2, p3 = three)[0]
      p p1
      p p2
      p p3
      p first

      # T3: subscript chain on the value with comparison
      def pair; [3, 4]; end
      flag = (a, b = pair)[0] == 3
      p a
      p b
      p flag
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      [10, 20]
      7
      8
      9
      7
      3
      4
      true
    OUT
  end

  it "ruby2 keywords forwarding" do
    result = ze0(<<~'RUBY')
      # The keyword/positional split rides on the trailing hash's OWN mark
      # (`RHashData::kw_marked`, CRuby's `rb_keyword_given_p`), and a splat CLEARS
      # it: `def forward(*args) = sink(*args)` hands `sink` a positional Hash, not
      # keywords. `ruby2_keywords` is the opt-out, and the whole reason it exists.
      def sink(a = 1, *rest, k: 2, **kw) = [a, rest, k, kw]

      # Written keywords are keywords.
      p sink(9, k: 3)

      # A plain hash argument is positional...
      h = { k: 3 }
      p sink(9, h)
      # ...and so is one a splat expanded, however it was written at the outer call.
      def forward(*args) = sink(*args)
      p forward(9, k: 3)

      def forward_block(*args, &b) = sink(*args, &b)
      p forward_block(9, k: 3)

      # An explicit `**` at the forwarding site IS keywords again.
      def forward_kw(*args, **kw) = sink(*args, **kw)
      p forward_kw(9, k: 3)
      p sink(9, **h)

      # `...` forwards both channels intact.
      def forward_all(...) = sink(...)
      p forward_all(9, k: 3)

      # `ruby2_keywords` keeps the mark, so the splat re-promotes.
      def target(*a, **k) = [a, k]
      ruby2_keywords def fwd(*a) = target(*a)
      p fwd(1, k: 2)
      p fwd(1, 2)
      p fwd(1, { k: 2 })

      class C
        def target(*a, **k) = [a, k]
        ruby2_keywords def fwd(*a) = target(*a)
        def plain(*a) = target(*a)
      end
      p C.new.fwd(1, k: 2)
      p C.new.plain(1, k: 2)

      # A bare `super` forwards keywords; an anonymous splat forwards positionally.
      class A
        def m(a = 1, *rest, k: 2, **kw) = [a, rest, k, kw]
      end
      class B < A
        def m(*) = super
      end
      class D < A
        def m(a = 1, *rest, k: 2, **kw) = super
      end
      p B.new.m(9, k: 3, z: 4)
      p D.new.m(9, k: 3, z: 4)

      # `Proc#ruby2_keywords` answers the proc.
      pr = proc { |x| x }
      p pr.ruby2_keywords.equal?(pr)
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      [9, [], 3, {}]
      [9, [{k: 3}], 2, {}]
      [9, [{k: 3}], 2, {}]
      [9, [{k: 3}], 2, {}]
      [9, [], 3, {}]
      [9, [], 3, {}]
      [9, [], 3, {}]
      [[1], {k: 2}]
      [[1, 2], {}]
      [[1, {k: 2}], {}]
      [[1], {k: 2}]
      [[1, {k: 2}], {}]
      [9, [{k: 3, z: 4}], 2, {}]
      [9, [], 3, {z: 4}]
      true
    OUT
      lang/methods/splitting_test.rb:59: warning: Skipping set of ruby2_keywords flag for proc (proc accepts keywords or post arguments or proc does not accept argument splat)
    ERR
  end

  it "self receiver runs no visibility check" do
    result = ze0(<<~'RUBY')
      # Ruby runs no visibility check against a literal `self` receiver (private has
      # been reachable through one since 2.7), nor against the receiver it
      # synthesizes for a call written with none. Every other explicit receiver
      # still meets the barrier.

      class Acct
        def initialize(n)
          @n = n
        end

        def via_self = self.secret
        def via_nothing = secret
        def via_safe_nav = self&.secret
        def via_send = self.send(:secret)
        def with_args = self.tagged("x", 2)
        def with_kwargs = self.tagged("x", 2, sep: "-")
        def with_splat = self.tagged(*["x", 2])
        def with_block = self.each_twice { |i| i }
        def richer?(other) = self.balance > other.balance

        protected

        def balance = @n

        private

        def secret = "secret #{@n}"

        def tagged(a, b, sep: ":")
          [a, b].join(sep)
        end

        def each_twice
          [yield(1), yield(2)]
        end
      end

      a = Acct.new(1)
      p a.via_self
      p a.via_nothing
      p a.via_safe_nav
      p a.via_send
      p a.with_args
      p a.with_kwargs
      p a.with_splat
      p a.with_block
      p a.richer?(Acct.new(0))

      # An ordinary explicit receiver still raises -- for both verbs.
      begin
        a.secret
      rescue NoMethodError => e
        puts e.message
      end
      begin
        a.balance
      rescue NoMethodError => e
        puts e.message
      end

      # A class body's `self` is the class, and the rule holds there too.
      class Cfg
        class << self
          def build = self.prepare
          def build_splat = self.prepare(*[])

          private

          def prepare(*) = :prepared
        end
      end
      p Cfg.build
      p Cfg.build_splat
      begin
        Cfg.prepare
      rescue NoMethodError => e
        puts e.message
      end

      # `class << self` writes its visibility verbs with no receiver at all: zeo
      # synthesizes one, and that synthetic receiver must not raise the barrier.
      # (The verbs' RUNTIME form -- `private(*names)` -- is a separate question
      # about which table a singleton body writes; see the singleton-visibility
      # golden.)
      class Vis
        class << self
          def a = :a
          def b = :b
          def c = :c

          private :a
        end
      end
      p Vis.b
      p Vis.c
      begin
        Vis.a
      rescue NoMethodError => e
        puts e.message
      end

      # A module body, same two shapes.
      module Mod
        def self.run = self.helper

        class << self
          private

          def helper = :helped
        end
      end
      p Mod.run
    RUBY

    _(result).must_answer <<~'OUT'
      "secret 1"
      "secret 1"
      "secret 1"
      "secret 1"
      "x:2"
      "x-2"
      "x:2"
      [1, 2]
      true
      private method 'secret' called for an instance of Acct
      protected method 'balance' called for an instance of Acct
      :prepared
      :prepared
      private method 'prepare' called for class Cfg
      :b
      :c
      private method 'a' called for class Vis
      :helped
    OUT
  end
end
