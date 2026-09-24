# frozen_string_literal: true

require "spec_helper"

describe "Methods: blocks and yields" do
  it "class in a define method block" do
    result = zr(<<~'RUBY')
      # Ruby rejects the `class` keyword inside a `def`, and accepts it inside a
      # BLOCK -- so `define_method(:x) { module M; end }` is legal, and the module
      # takes the block's own lexical cref. zr desugars a literal-symbol
      # `define_method` into the same node a `def` produces, which made the walk
      # stop there and the definition reach codegen unregistered.
      #
      # followupboss_client is the shape at the top level (a `require` override
      # whose branches define `Her::Middleware` classes), import.rb the shape in a
      # class body (`module ::Kernel` inside `define_method(:global)`).

      # The body runs when the METHOD does, not when it is defined -- and only
      # then, once per call.
      define_method(:install_top) do
        module Top
          puts "top body"
          WHO = "top"
          def self.hi = "top hi"
        end
      end

      puts "defined"
      install_top
      p [Top::WHO, Top.hi, Top.class]

      # The cref is the block's, so a class body's `define_method` nests the
      # definition under that class.
      class Host
        define_method(:install) do
          module Inner
            WHO = "inner"
          end

          class Nested
            def hi = "nested"
          end
        end

        define_singleton_method(:install_from_singleton) do
          module FromSingleton
            WHO = "singleton"
          end
        end
      end

      Host.new.install
      Host.install_from_singleton
      p [Host::Inner::WHO, Host::Nested.new.hi, Host::Nested.name]
      p [Host::FromSingleton::WHO, defined?(Inner), defined?(FromSingleton)]

      # A cref-absolute reopen from inside one reaches the real top-level class,
      # and a branch inside the block is descended into just as at the top level.
      # (No `defined?` probe before the call: zr registers a definition at compile
      # time whatever position it is written in, so `defined?(1.zr_shout)` answers
      # "method" before the block has run where ruby answers nil. That divergence
      # belongs to the registration model and predates this shape -- a plain block
      # shows it too.)
      define_method(:patch) do |which|
        case which
        when :kernel
          module ::Kernel
            def zr_shout = "SHOUT"
          end
        when :string
          class ::String
            def zr_shout = "str shout"
          end
        end
      end

      patch(:kernel)
      patch(:string)
      p [1.zr_shout, "s".zr_shout]

      # Calling twice re-runs the body, which is what makes the counter climb --
      # the same thing a plain block does. (A `module` reopen, so no constant is
      # assigned twice: the second assignment's warning goes to stderr, and the
      # order it interleaves with stdout is not a fact about either compiler.)
      module Counter
        def self.n = @n ||= 0
        def self.bump = @n = n + 1
      end
      define_method(:count_up) do
        module Counter
          bump
        end
      end
      count_up
      count_up
      p Counter.n
    RUBY

    _(result).must_answer <<~'OUT'
      defined
      top body
      ["top", "top hi", Module]
      ["inner", "nested", "Host::Nested"]
      ["singleton", nil, nil]
      ["SHOUT", "str shout"]
      2
    OUT
  end

  it "class method open class call" do
    result = zr(<<~'RUBY')
      # `infer_call_type`'s class-body fallback used to short-circuit on
      # any call inside a class body — including those with a receiver.
      # A `recv.method(...)` whose method isn't on the enclosing class
      # resolved as the default `int`, and the receiver-aware branches
      # below (Fiber.yield → poly, infer_open_class_type → user open-
      # class return) never ran. The fix gates the fallback on
      # `recv < 0`.
      #
      # Reproducer here: an open-class method on Integer that returns a
      # hash. Without the fix, `C#wrap`'s body calls `x.to_pair` whose
      # inferred return came out as `int` (the enclosing C class has no
      # `to_pair`), but the actual emit returns `sp_SymIntHash *` →
      # "returning sp_SymIntHash * from a function with return type
      # mrb_int" -Wint-conversion error.

      class Integer
        def to_pair
          {a: self, b: self * 2, c: self * 3}
        end
      end

      class C
        def wrap(x)
          x.to_pair
        end
      end

      h = C.new.wrap(5)
      puts h[:a]   # 5
      puts h[:b]   # 10
      puts h[:c]   # 15
    RUBY

    _(result).must_answer <<~'OUT'
      5
      10
      15
    OUT
  end

  it "defined yield outside a method" do
    result = zr(<<~'RUBY')
      # `defined?(yield)` at the top level makes zr emit a program that does not
      # compile: `__blk` is not in scope.
      #
      # Codegen lowers `defined?(yield)` to a test of the enclosing method's block
      # parameter, `__blk`. At the top level there is no enclosing method and so no
      # such binding, and nothing declines the lowering first. Ruby answers `nil`:
      # there is no block here, which is exactly what `defined?` is being asked.
      #
      # A compile failure is worse than a wrong answer -- the whole program is
      # rejected over an expression whose value is a constant `nil`.

      p defined?(yield)

      # Inside a method both answers are already right; only the top-level form fails.
      def with_block = defined?(yield)
      p with_block
      p(with_block { })
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      "yield"
    OUT
  end

  it "escaping block capturing self via explicit self dot method" do
    result = zr(<<~'RUBY')
      # Before `HirNode::SelfRef` existed, an escaping block could only ever
      # capture `self` implicitly via a bare `@ivar` reference --
      # `self.method_name` is another way a block needs the same capture (see
      # `analyze::captures`'s new `SelfRef` arm). Also exercises implicit-self
      # dispatch (`each_num(a, b)`, no receiver) from inside the SAME method
      # that constructs the escaping block.

      class Collector
        def initialize(tag)
          @tag = tag
        end

        def tag
          @tag
        end

        def each_num(a, b)
          yield a
          yield b
        end

        def run(a, b)
          each_num(a, b) { |n| puts "tag=#{self.tag}:#{n}" }
        end
      end

      Collector.new("x").run(1, 2)
    RUBY

    _(result).must_answer "tag=x:1\ntag=x:2\n"
  end

  it "issue method name def in block" do
    result = zr(<<~'RUBY')
      # `__method__` inside a `def` written in a BLOCK. Such a def installs at
      # runtime, as a method-body lambda, so the name has to be carried into the
      # body: reading it off the enclosing scope answers whatever encloses the
      # `def` -- nil at the top level.
      def probe(label)
        result = yield
        puts "#{label}: #{result.inspect}"
      end

      probe("method_name") do
        def named_method
          __method__
        end
        named_method
      end
    RUBY

    _(result).must_answer "method_name: :named_method\n"
  end

  it "lambda default reads its sibling parameters" do
    result = zr(<<~'RUBY')
      # A lambda written as a parameter DEFAULT closes over the parameters bound
      # before it: the default is evaluated in the callee's frame, so `dest` and
      # `out` are that frame's locals and the lambda captures them like any block
      # in the body would. zr walked the body alone for escaping blocks, so the
      # parameters stayed plain slots and the lambda's read of `dest` had nothing
      # to read.

      def home(dest: "d", out: $stdout, build: -> { vendor(dest: dest, out: out) })
        build.call
      end
      def vendor(dest:, out:) = out.puts("vendor #{dest}")
      home
      home(dest: "x")

      def opt(a = 1, f = -> { a * 2 }) = f.call
      p opt
      p opt(5)
      p opt(5, -> { :given })

      def late(a = 1, f = proc { a += 1; a }, b = f.call)
        [a, b, f.call]
      end
      p late
    RUBY

    _(result).must_answer <<~'OUT'
      vendor d
      vendor x
      2
      10
      :given
      [2, 2, 3]
    OUT
  end

  it "later def on a builtin reaches back" do
    result = zr(<<~'RUBY')
      # A later `def` reopening a BUILTIN class used to reach BACK: a call written
      # above the reopen answered with the reopened body.
      #
      # The reopen's row registers at STARTUP, so EVERY site above it was affected --
      # statically bound and dynamic alike, and every fold with it. `p [1,2].size`
      # before `class Array; def size` answered `:own_size`, and so did a site that
      # reached the row through full dispatch. (The gap's original note said both
      # calls "bind STATICALLY to `__bm_Array::take_while`". Nothing folds past a
      # reopen, which is what makes the whole class of divergence one fix rather
      # than a per-site one.)
      #
      # The reopen is now POSITIONAL, and both ends are emitted: one `.bss` byte per
      # `(builtin class, method name)` in `zr_reopen_flags`, stored where the
      # `class Foo ... end` stands, read by a prologue in the reopened body. Above
      # that line the body forwards to the row it replaced. No table registers, the
      # runtime looks nothing up, and the inline caches stay valid -- a positional
      # OVERLAY install would have called `mark_live()`, the global gate that takes
      # every send in the program onto the per-ancestor walk.
      #
      # Two things the forward is NOT. It is not `super`: `super` resumes PAST the
      # reopened class, and a name the builtin owns outright (`Array#size`) has
      # nothing above it -- ruby raises "no superclass method" for a `super` written
      # there, and rightly. And it is not free of the block: a body that names no
      # `&blk` still has to forward the caller's, so a flagged body takes a block
      # parameter whether or not it declares one.
      #
      # `a_reopened_builtin_answers_from_its_own_line.rb` carries the widened sweep.

      p [1, 2].take_while { true }
      class Array
        def take_while
          :array_own
        end
      end
      p [1, 2].take_while { true }
    RUBY

    _(result).must_answer "[1, 2]\n:array_own\n"
  end

  it "lifted block class method self cls" do
    result = zr(<<~'RUBY')
      # A class method that carries the receiving class must still carry it into a
      # lifted block: a sibling class-method call there used an identifier the
      # proc's signature does not have.
      class Base
        def self.dispatch(a)
          "#{name}:#{a}"
        end

        def self.tag
          "#{name}!"
        end

        def self.run(specs)
          out = []
          f = proc { |spec| out << dispatch(spec) }
          specs.each(&f)
          out << name
          out
        end

        def self.no_captures
          g = proc { tag }
          g.call
        end

        def self.each_tagged(xs)
          seen = []
          k = proc { |v| seen << tag }
          xs.each(&k)
          seen
        end
      end

      class Sub < Base
      end

      p Base.run(["a", "b"])
      p Sub.run(["c"])
      p Base.no_captures
      p Sub.no_captures
      p Base.each_tagged([1, 2])
      p Sub.each_tagged([3])
    RUBY

    _(result).must_answer <<~'OUT'
      ["Base:a", "Base:b", "Base"]
      ["Sub:c", "Sub"]
      "Base!"
      "Sub!"
      ["Base!", "Base!"]
      ["Sub!"]
    OUT
  end

  it "massign splat rhs" do
    result = zr(<<~'RUBY')
      # Splat on the RHS of a multiple assignment (`*a = *x`), rest-only targets
      # under a scalar RHS (`*a = 5` -> [5]), and nil splats contributing nothing.
      *a = *[1, 2]
      p a
      *b = *nil
      p b
      *c = 5
      p c
      d, *e = *[1, 2, 3]
      p d
      p e
      f, *g = 7
      p f
      p g
      h = [*nil]
      p h
      def r(val)
        x = yield
        val == x
      end
      p r([1]) { next *1 }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      []
      [5]
      1
      [2, 3]
      7
      []
      []
      true
    OUT
  end

  it "method defined in a block frame label" do
    result = zr(<<~'RUBY')
      # A method DEFINED inside a block carries the block's nesting in its frame
      # label, so `caller` and `caller_locations` name it wrongly:
      #
      #     "block (2 levels) in Object#c1"   instead of   "Object#c1"
      #
      # The label is baked when codegen emits the method's `FrameGuard`, and for a
      # `def` reached through a block it is built from the emitting position rather
      # than from the method the `def` creates. Where the `def` was WRITTEN has no
      # bearing on what the resulting method is called -- ruby names the frame after
      # the method, and a `def` inside a block produces an ordinary method of the
      # enclosing class.
      #
      # It reaches anything that reads a frame by name: a logger tagging its call
      # site, a DSL blaming the right line, and every `caller` assertion in a test.
      # Defining methods inside `each`/`class_exec`/`instance_eval` blocks is the
      # normal shape for a generated API, so the mislabelled frames are the ones a
      # generated method produces.

      [1].each do
        def c1 = c2
        def c2 = caller_locations(1, 1).first.label
      end
      p c1

      # The same method, called from a block rather than defined in one, is right.
      [1].each { p c2 }

      # A top-level def is already right.
      def d1 = d2
      def d2 = caller_locations(1, 1).first.label
      p d1
    RUBY

    _(result).must_answer <<~'OUT'
      "Object#c1"
      "block in <main>"
      "Object#d1"
    OUT
  end

  it "method param destructure" do
    result = zr(<<~'RUBY')
      # def m((a, b)) destructures an array argument across the parenthesized
      # parameter, like block parameters do.
      def m((a, b))
        a + b
      end
      p m([1, 2])
      x = m([10, 20])
      p x
      def mixed(pre, (a, b), post)
        "#{pre}:#{a}#{b}:#{post}"
      end
      p mixed(1, [2, 3], 4)
      def rest3((a, *r))
        [a, r]
      end
      p rest3([1, 2, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      3
      30
      "1:23:4"
      [1, [2, 3]]
    OUT
  end

  it "method params destructure" do
    result = zr(<<~'RUBY')
      # METHOD params destructure too, not just block params.
      #
      # `r##"..."##`: the body contains `"#{a}`, which would close an `r#"..."#`.

      def pair((a, b)) = "#{a}-#{b}"
      puts pair([1, 2])
      def nested((a, (b, c))) = [a, b, c]
      p nested([1, [2, 3]])
      def mixed(x, (y, z)) = [x, y, z]
      p mixed(1, [2, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      1-2
      [1, 2, 3]
      [1, 2, 3]
    OUT
  end

  it "parameter default assigns a method local" do
    result = zr(<<~'RUBY')
      # `def fetch(name, default = (no_default = true))` is the idiom for "was an
      # argument actually passed?" -- and the local the default assigns belongs to the
      # WHOLE method, not to the default expression. It is nil when the default did
      # not run, and every block in the body can read it.
      #
      # Defaults are not part of a method's body, so a pass that collects locals by
      # walking the body alone never sees the name. A block capturing it then
      # fresh-declared its own and read `nil` -- silently, with no diagnostic -- and a
      # NESTED block hit a refusal instead. memoizable's `Memory#fetch` is the shape,
      # three block levels deep.

      def fetch(name, default = (no_default = true))
        [1].each do
          [2].each do
            [3].each do
              p [name, no_default, default]
            end
          end
        end
      end

      fetch(:given)
      fetch(:passed, 9)

      # One level is the same question, and read `nil` before.
      def one_level(d = (flag = true))
        [1].each { p [d, flag] }
      end

      one_level
      one_level(:explicit)

      # The local is a real method local outside any block, too.
      def plainly(d = (seen = :yes))
        [d, seen]
      end

      p plainly
      p plainly(:passed)

      # A default may assign more than one, and a later default may READ an earlier
      # parameter -- ruby evaluates them left to right.
      def several(a = (x = 1), b = a + 1, c = (y = b * 2))
        [a, b, c, x, y]
      end

      p several
      p several(10)
      p several(10, 20)

      # A keyword parameter's default scopes its local the same way.
      def keyworded(k: (kw_flag = :defaulted))
        [1].each { p [k, kw_flag] }
      end

      keyworded
      keyworded(k: :given)

      # ... and the name survives being ASSIGNED again inside a block, which makes it
      # a shared cell rather than a per-block copy.
      def reassigned(d = (count = 0))
        [1, 2, 3].each { count = (count || 0) + 1 }
        [d, count]
      end

      p reassigned
      p reassigned(:passed)

      # When the default did NOT run, the name is simply nil -- it is declared for the
      # whole method either way.
      def untouched(d = (never = :ran))
        [d, never]
      end

      p untouched(:passed)

      # A block that escapes (a Proc kept past the call) reads the same cell.
      def escaping(d = (tag = :from_default))
        -> { [d, tag] }
      end

      p escaping.call
      p escaping(:passed).call
    RUBY

    _(result).must_answer <<~'OUT'
      [:given, true, true]
      [:passed, nil, 9]
      [true, true]
      [:explicit, nil]
      [:yes, :yes]
      [:passed, nil]
      [1, 2, 4, 1, 4]
      [10, 11, 22, nil, 22]
      [10, 20, 40, nil, 40]
      [:defaulted, :defaulted]
      [:given, nil]
      [0, 3]
      [:passed, 3]
      [:passed, nil]
      [:from_default, :from_default]
      [:passed, nil]
    OUT
  end

  it "post params fill from the front when underfull" do
    result = zr(<<~'RUBY')
      # Post params fill left-to-right from whatever the lead/optional/rest slots
      # left behind, nil-padding the tail -- they are anchored to the END of the
      # argument list only when there are enough values to reach them.

      def one(x) = yield x
      one([1, 2]) { |a, *b, c, d| p [a, b, c, d] }
      one([1, 2, 3, 4, 5]) { |a, *b, c| p [a, b, c] }
      one([1, 2]) { |a, b = 5, c = 6, d, e| p [a, b, c, d, e] }
      one([1, 2, 3, 4, 5]) { |a, b = 5, c = 6, d, e| p [a, b, c, d, e] }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, [], 2, nil]
      [1, [2, 3, 4], 5]
      [1, 5, 6, 2, nil]
      [1, 2, 3, 4, 5]
    OUT
  end

  it "proc compose method operand" do
    result = zr(<<~'RUBY')
      # Proc#>> / #<< with a Method operand composes through Method#to_proc, whose
      # trampoline publishes its boxed result -- composing the raw method object
      # mis-typed the intermediate (#2692).
      inc = ->(x) { x + 1 }
      dbl = 2.method(:*)
      g = (inc >> dbl)
      p(g.call(4))
      p((dbl >> inc).call(4))
      p((inc << dbl).call(4))
      half = ->(x) { x * 10 }
      p((dbl >> half).call(3))
    RUBY

    _(result).must_answer <<~'OUT'
      10
      9
      9
      60
    OUT
  end

  it "proc destructured parameters" do
    result = zr(<<~'RUBY')
      p(->((a, b)) {}.parameters)
      p(proc { |(a, b)| }.parameters)
      p(->(x, (a, b)) {}.parameters)
      p(->((a, b)) {}.call([1, 2]))
      p(->(x) {}.call(3))
      p(->(x) { x }.parameters)
      p(->((a, b)) { a + b }.call([1, 2]))
      p(proc { |(a, b)| b }.call([3, 4]))
    RUBY

    _(result).must_answer <<~'OUT'
      [[:req]]
      [[:opt]]
      [[:req, :x], [:req]]
      nil
      nil
      [[:req, :x]]
      3
      4
    OUT
  end

  it "proc installed as a method checks its shape" do
    result = zr(<<~'RUBY')
      # `define_method` HARDENS proc semantics: the installed method arity-checks
      # like a `def`, and an undeclared keyword is an error. The block binder
      # underneath is lenient on both counts -- it pads a missing positional with
      # nil and drops an unknown keyword -- so the shape is checked before the
      # body runs.
      #
      # Three rules make this narrower than it sounds, and each is a row below.
      #
      #   * A trailing kw-marked Hash is only KEYWORDS when the callee declares
      #     some. `def f(*a); f(k: 1)` puts the hash in `a`, which is also exactly
      #     how a `ruby2_keywords` splat forwards one.
      #   * Only a MARKED hash counts even then. A genuine positional Hash must
      #     not be peeled, or the arity reported for it is wrong.
      #   * A body with no Ruby SOURCE was built by the runtime -- an accessor
      #     from `attr_accessor`, an Enumerator shuttle, `Symbol#to_proc` -- and
      #     has no Ruby-level shape to check against.

      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end

      # --- Positional arity -----------------------------------------------------
      c = Class.new
      c.send(:define_method, :two) { |a, b| [a, b] }
      show { c.new.two(1) }
      show { c.new.two(1, 2) }
      show { c.new.two(1, 2, 3) }

      c.send(:define_method, :opt) { |a, b = :d| [a, b] }
      show { c.new.opt(1) }
      show { c.new.opt(1, 2) }
      show { c.new.opt }

      c.send(:define_method, :splat) { |a, *rest| [a, rest] }
      show { c.new.splat(1) }
      show { c.new.splat(1, 2, 3) }
      show { c.new.splat }

      # A lambda source was already strict, and stays so.
      c.send(:define_method, :lam, ->(a, b) { [a, b] })
      show { c.new.lam(1) }

      # --- Keywords -------------------------------------------------------------
      k = Class.new { def kw(a:) = a }
      show { k.new.kw(a: 1, b: 2) }
      show { k.new.method(:kw).call(a: 1, z: 9) }
      show { k.new.send(:kw, a: 1, q: 3) }
      show { k.new.kw(a: 1) }
      show { k.new.kw }

      kr = Class.new { def kw(a:, **rest) = [a, rest] }
      show { kr.new.kw(a: 1, b: 2) }

      # A method with NO declared keywords takes the hash positionally.
      s = Class.new { def any(*a) = a }
      show { s.new.any(k: 1) }
      show { s.new.any(1, k: 2) }

      one = Class.new { def one(x) = x }
      show { one.new.one(k: 1) }

      # An UNMARKED trailing Hash is a positional, and must not be peeled.
      kh = Class.new { def kw(a:) = a }
      show { kh.new.kw({ a: 1 }) }

      # --- Runtime-built bodies keep working ------------------------------------
      o = Object.new
      o.singleton_class.attr_accessor :tag
      o.tag = "x"
      show { o.tag }
      show { [1, 2].map(&:to_s) }
      show { [[1, 2]].each_with_object([]) { |(a, b), acc| acc << a + b } }
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: wrong number of arguments (given 1, expected 2)
      [1, 2]
      ArgumentError: wrong number of arguments (given 3, expected 2)
      [1, :d]
      [1, 2]
      ArgumentError: wrong number of arguments (given 0, expected 1..2)
      [1, []]
      [1, [2, 3]]
      ArgumentError: wrong number of arguments (given 0, expected 1+)
      ArgumentError: wrong number of arguments (given 1, expected 2)
      ArgumentError: unknown keyword: :b
      ArgumentError: unknown keyword: :z
      ArgumentError: unknown keyword: :q
      1
      ArgumentError: missing keyword: :a
      [1, {b: 2}]
      [{k: 1}]
      [1, {k: 2}]
      {k: 1}
      ArgumentError: wrong number of arguments (given 1, expected 0; required keyword: a)
      "x"
      ["1", "2"]
      [3]
    OUT
  end

  it "proc method wave10" do
    result = zr(<<~'RUBY')
      pr = proc { |a, b = 1, *c, d:, e: 2, **f, &g| }
      p pr.parameters
      la = ->(a, b = 1) {}
      p la.parameters
      def m117(x); x * 2; end
      mo = method(:m117)
      pc = mo.to_proc
      p pc.call(5)
      add = proc { |a, b| a + b }
      p add.yield(1, 2)
      # bound method to_proc
      class C2116
        def initialize(n); @n = n; end
        def scale(x); x * @n; end
        def label(s); "#{s}:#{@n}"; end
      end
      obj = C2116.new(3)
      sp = obj.method(:scale).to_proc
      p sp.call(7)
      lp = obj.method(:label).to_proc
      p lp.call("id")
      # string-returning top-level
      def greet(name); "hello #{name}"; end
      gp = method(:greet).to_proc
      p gp.call("matz")
      p gp.arity
      p gp.lambda?
      # parameters edge: anonymous + numbered
      p proc { |*| }.parameters
      p proc { |**| }.parameters
      p ->(a, *, &blk) {}.parameters
      np = proc { _2 }
      p np.parameters
      # post params
      p ->(a, *m, z) {}.parameters
      # builtin operator bound method: __bam wrapper with self-carried param
      bm = 5.method(:+)
      p bm.call(3)
      bp = bm.to_proc
      p bp.call(10)
      p bp.arity
      sm = "ab".method(:*)
      p sm.call(2)
    RUBY

    _(result).must_answer <<~'OUT'
      [[:opt, :a], [:opt, :b], [:rest, :c], [:keyreq, :d], [:key, :e], [:keyrest, :f], [:block, :g]]
      [[:req, :a], [:opt, :b]]
      10
      3
      21
      "id:3"
      "hello matz"
      1
      true
      [[:rest, :*]]
      [[:keyrest, :**]]
      [[:req, :a], [:rest, :*], [:block, :blk]]
      [[:opt, :_1], [:opt, :_2]]
      [[:req, :a], [:rest, :m], [:req, :z]]
      8
      15
      1
      "abab"
    OUT
  end

  it "proc parameters" do
    result = zr(<<~'RUBY')
      # Proc#parameters reflects the block/lambda signature. A proc reports required
      # positionals as :opt (it doesn't enforce arity); a lambda reports them as :req.
      p proc { |x| }.parameters
      p lambda { |x| }.parameters

      # Optional, splat, post, keyword, keyword-splat and block params, in order.
      sig = proc { |a, b = 1, *rest, last, key:, opt: 2, **kw, &blk| }
      p sig.parameters

      # Lambda form of the same signature (required positionals become :req).
      lam = ->(a, b = 1, *rest, last, key:, opt: 2, **kw, &blk) { }
      p lam.parameters

      # Anonymous splats report the sigil as their name.
      p proc { |*| }.parameters
      p proc { |**| }.parameters

      # The Symbol#method_missing idiom: parameters travels with a stored proc.
      doubler = ->(n) { n * 2 }
      p doubler.parameters
      p [1, 2, 3].map(&doubler)
    RUBY

    _(result).must_answer <<~'OUT'
      [[:opt, :x]]
      [[:req, :x]]
      [[:opt, :a], [:opt, :b], [:rest, :rest], [:opt, :last], [:keyreq, :key], [:key, :opt], [:keyrest, :kw], [:block, :blk]]
      [[:req, :a], [:opt, :b], [:rest, :rest], [:req, :last], [:keyreq, :key], [:key, :opt], [:keyrest, :kw], [:block, :blk]]
      [[:rest, :*]]
      [[:keyrest, :**]]
      [[:req, :n]]
      [2, 4, 6]
    OUT
  end

  it "proc parameters lambda keyword forces the reporting view" do
    result = zr(<<~'RUBY')
      # `parameters(lambda:)` forces the view: true reports plain positionals as
      # :req, false as :opt, nil follows the receiver. A defaulted positional
      # stays :opt in every view; a bound method's to_proc keeps the method arity.

      p proc { |x, y| }.parameters(lambda: true)
      p ->(x, y) { }.parameters(lambda: false)
      p proc { |x, y = 1| }.parameters(lambda: true)
      p proc { |x| }.parameters(lambda: nil)
      p lambda { _1 }.parameters
      def greet(name); end
      gp = method(:greet).to_proc
      p [gp.arity, gp.lambda?]
    RUBY

    _(result).must_answer <<~'OUT'
      [[:req, :x], [:req, :y]]
      [[:opt, :x], [:opt, :y]]
      [[:req, :x], [:opt, :y]]
      [[:opt, :x]]
      [[:req, :_1]]
      [1, true]
    OUT
  end

  it "proc parameters lambda kw" do
    result = zr(<<~'RUBY')
      # Proc#parameters(lambda:) forces the reporting view (#2693): true reports
      # plain positionals as :req, false as :opt, nil follows the receiver's own
      # nature. Defaulted positionals stay :opt in every view, and rest/key/block
      # kinds never change. Kinds are stored canonically (lambda-style) and remapped
      # at print time, which also fixes numbered params on a lambda (:req, not :opt).
      p proc { |x, y| }.parameters
      p proc { |x, y| }.parameters(lambda: true)
      p ->(x, y) {}.parameters
      p ->(x, y) {}.parameters(lambda: false)
      p proc { |x, y=1| }.parameters(lambda: true)
      p ->(x, y=1) {}.parameters(lambda: false)
      p proc { |a, *r, k: 1, &b| }.parameters(lambda: true)
      p proc { |x| }.parameters(lambda: nil)
      pr = proc { |x, y| }
      p pr.parameters(lambda: true)
      p lambda { _1 }.parameters
      p proc { _1 + _2 }.parameters(lambda: true)
    RUBY

    _(result).must_answer <<~'OUT'
      [[:opt, :x], [:opt, :y]]
      [[:req, :x], [:req, :y]]
      [[:req, :x], [:req, :y]]
      [[:opt, :x], [:opt, :y]]
      [[:req, :x], [:opt, :y]]
      [[:opt, :x], [:opt, :y]]
      [[:req, :a], [:rest, :r], [:key, :k], [:block, :b]]
      [[:opt, :x]]
      [[:req, :x], [:req, :y]]
      [[:req, :_1]]
      [[:req, :_1], [:req, :_2]]
    OUT
  end

  it "proc parameters reflect the signature" do
    result = zr(<<~'RUBY')
      p proc { |x, y| }.parameters
      p lambda { |x, y| }.parameters
      p proc { |a, b = 1, *c, d, k:, m: 2, **n, &blk| }.parameters
      p ->(a, b) { }.parameters
      p proc { |*| }.parameters
      p proc { |**| }.parameters
    RUBY

    _(result).must_answer <<~'OUT'
      [[:opt, :x], [:opt, :y]]
      [[:req, :x], [:req, :y]]
      [[:opt, :a], [:opt, :b], [:rest, :c], [:opt, :d], [:keyreq, :k], [:key, :m], [:keyrest, :n], [:block, :blk]]
      [[:req, :a], [:req, :b]]
      [[:rest, :*]]
      [[:keyrest, :**]]
    OUT
  end

  it "proc parameters source names" do
    result = zr(<<~'RUBY')
      # `Proc#parameters` reports the names the PROGRAM wrote. Three things leaked
      # the compiler's own names instead (#4045).
      #
      # A block parameter colliding with an outer local is renamed to `b__bp<N>`, and
      # the emitter strips that suffix -- for the positional kinds only, so rest,
      # keyword, keyword-rest and block reported the suffix verbatim.
      #
      # Stripping alone was not enough either: the stripped name appears nowhere else
      # in the program, so it is not in the generated symbol table, and interning it
      # at emit time came too late -- the symbol rendered EMPTY. The rename interns
      # the source name now, while the table is still open.
      #
      # And the implicit rest a trailing comma synthesizes (`|a,|`) is not a
      # parameter Ruby reports at all.
      p(->((a, b)) {}.parameters)
      p(proc { |a, *b| }.parameters)
      p(->(a, b = 1, *c, d:, e: 2, **f, &g) {}.parameters)
      p(proc { |a, b = 1, *c, d:, e: 2, **f, &g| }.parameters)
      a = 1; b = 2; c = 3; d = 4; e = 5; f = 6; g = 7
      p(proc { |a, b = 1, *c, d:, e: 2, **f, &g| }.parameters)
      p([a, b, c, d, e, f, g])
      p(lambda { |x, (y, z)| }.parameters)
      p(proc { |*| }.parameters)
      p(proc { |a, | }.parameters)
      p(proc { }.parameters)
    RUBY

    _(result).must_answer <<~'OUT'
      [[:req]]
      [[:opt, :a], [:rest, :b]]
      [[:req, :a], [:opt, :b], [:rest, :c], [:keyreq, :d], [:key, :e], [:keyrest, :f], [:block, :g]]
      [[:opt, :a], [:opt, :b], [:rest, :c], [:keyreq, :d], [:key, :e], [:keyrest, :f], [:block, :g]]
      [[:opt, :a], [:opt, :b], [:rest, :c], [:keyreq, :d], [:key, :e], [:keyrest, :f], [:block, :g]]
      [1, 2, 3, 4, 5, 6, 7]
      [[:req, :x], [:req]]
      [[:rest, :*]]
      [[:opt, :a]]
      []
    OUT
  end

  it "a recursive method that yields reaches its block at every depth" do
    result = zr(<<~'RUBY')
      # A method that drives its block (yield or block.call) and calls itself
      # recursively compiles as a real function with a proc-materialized block
      # instead of hitting the inline depth cap: the &block param rides as an
      # sp_Proc * and the self-call forwards it, so the recursion is plain C
      # recursion.

      # class method, block.call + &block self-forward
      class Walker
        def self.walk(depth, &block)
          block.call(depth)
          walk(depth - 1, &block) if depth > 0
        end
      end

      Walker.walk(2) { |n| puts n }

    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      0
    OUT
  end

  it "an instance method recurses and yields the same way" do
    result = zr(<<~'RUBY')
      # A method that drives its block (yield or block.call) and calls itself
      # recursively compiles as a real function with a proc-materialized block
      # instead of hitting the inline depth cap: the &block param rides as an
      # sp_Proc * and the self-call forwards it, so the recursion is plain C
      # recursion.

      # class method, block.call + &block self-forward
      class Walker
        def self.walk(depth, &block)
          block.call(depth)
          walk(depth - 1, &block) if depth > 0
        end
      end

      # instance method
      class IWalker
        def walk(depth, &block)
          block.call(depth)
          walk(depth - 1, &block) if depth > 0
        end
      end

      IWalker.new.walk(2) { |n| puts n + 10 }

    RUBY

    _(result).must_answer <<~'OUT'
      12
      11
      10
    OUT
  end

  it "a top-level def recurses and yields the same way" do
    result = zr(<<~'RUBY')
      # A method that drives its block (yield or block.call) and calls itself
      # recursively compiles as a real function with a proc-materialized block
      # instead of hitting the inline depth cap: the &block param rides as an
      # sp_Proc * and the self-call forwards it, so the recursion is plain C
      # recursion.

      # class method, block.call + &block self-forward
      class Walker
        def self.walk(depth, &block)
          block.call(depth)
          walk(depth - 1, &block) if depth > 0
        end
      end

      # top-level def
      def twalk(depth, &block)
        block.call(depth)
        twalk(depth - 1, &block) if depth > 0
      end

      twalk(2) { |n| puts n + 20 }

    RUBY

    _(result).must_answer <<~'OUT'
      22
      21
      20
    OUT
  end

  it "a declared &block beside a literal yield in the body recurses too" do
    result = zr(<<~'RUBY')
      # A method that drives its block (yield or block.call) and calls itself
      # recursively compiles as a real function with a proc-materialized block
      # instead of hitting the inline depth cap: the &block param rides as an
      # sp_Proc * and the self-call forwards it, so the recursion is plain C
      # recursion.

      # class method, block.call + &block self-forward
      class Walker
        def self.walk(depth, &block)
          block.call(depth)
          walk(depth - 1, &block) if depth > 0
        end
      end

      # declared &block with a literal `yield` in the body
      class YWalker
        def self.walk(depth, &block)
          yield depth
          walk(depth - 1, &block) if depth > 0
        end
      end

      YWalker.walk(2) { |n| puts n + 30 }

    RUBY

    _(result).must_answer <<~'OUT'
      32
      31
      30
    OUT
  end

  it "recursion through a receiver's own yielding method walks a tree" do
    result = zr(<<~'RUBY')
      # A method that drives its block (yield or block.call) and calls itself
      # recursively compiles as a real function with a proc-materialized block
      # instead of hitting the inline depth cap: the &block param rides as an
      # sp_Proc * and the self-call forwards it, so the recursion is plain C
      # recursion.

      # class method, block.call + &block self-forward
      class Walker
        def self.walk(depth, &block)
          block.call(depth)
          walk(depth - 1, &block) if depth > 0
        end
      end

      # recursion through a receiver's own yielding method (the tree-walk shape)
      class TNode
        def initialize(depth)
          @depth = depth
        end

        def leaf?
          @depth <= 0
        end

        def each
          yield TNode.new(@depth - 1)
          yield TNode.new(@depth - 2)
          nil
        end
      end

      class TreeWalker
        def self.walk(node, &block)
          return block.call(node) if node.leaf?

          node.each do |child| walk(child, &block) end
        end
      end

      TreeWalker.walk(TNode.new(2)) { |n| puts "leaf" }

    RUBY

    _(result).must_answer <<~'OUT'
      leaf
      leaf
      leaf
    OUT
  end

  it "a real proc passed by the caller is reached at every depth" do
    result = zr(<<~'RUBY')
      # A method that drives its block (yield or block.call) and calls itself
      # recursively compiles as a real function with a proc-materialized block
      # instead of hitting the inline depth cap: the &block param rides as an
      # sp_Proc * and the self-call forwards it, so the recursion is plain C
      # recursion.

      # class method, block.call + &block self-forward
      class Walker
        def self.walk(depth, &block)
          block.call(depth)
          walk(depth - 1, &block) if depth > 0
        end
      end

      # caller passes a real proc
      pr = proc { |n| puts n + 40 }
      Walker.walk(1, &pr)

    RUBY

    _(result).must_answer <<~'OUT'
      41
      40
    OUT
  end

  it "a captured local mutated through the recursion holds every write" do
    result = zr(<<~'RUBY')
      # A method that drives its block (yield or block.call) and calls itself
      # recursively compiles as a real function with a proc-materialized block
      # instead of hitting the inline depth cap: the &block param rides as an
      # sp_Proc * and the self-call forwards it, so the recursion is plain C
      # recursion.

      # class method, block.call + &block self-forward
      class Walker
        def self.walk(depth, &block)
          block.call(depth)
          walk(depth - 1, &block) if depth > 0
        end
      end

      # a captured local mutated through the recursion
      total = 0
      Walker.walk(3) { |n| total += n }
      puts total

    RUBY

    _(result).must_answer <<~'OUT'
      6
    OUT
  end

  it "a yield-method inlined inside the recursive method keeps its own yield" do
    result = zr(<<~'RUBY')
      # A method that drives its block (yield or block.call) and calls itself
      # recursively compiles as a real function with a proc-materialized block
      # instead of hitting the inline depth cap: the &block param rides as an
      # sp_Proc * and the self-call forwards it, so the recursion is plain C
      # recursion.

      # class method, block.call + &block self-forward
      class Walker
        def self.walk(depth, &block)
          block.call(depth)
          walk(depth - 1, &block) if depth > 0
        end
      end

      # a yield-method inlined INSIDE the recursive method: the callee's own yield
      # splices its call-site block, while a yield in that spliced block still binds
      # the enclosing method's proc (callee even shadows the &block name)
      class SNode
        def each
          block = 5
          yield block
          nil
        end
      end

      class MixWalker
        def self.walk(depth, &block)
          yield depth
          SNode.new.each do |x|
            walk(depth - 1, &block) if depth > 0
          end
          nil
        end
      end

      MixWalker.walk(1) { |n| puts n + 50 }
    RUBY

    _(result).must_answer <<~'OUT'
      51
      50
    OUT
  end

  it "redefinition timeline edges" do
    result = zr(<<~'RUBY')
      # The positional-redefinition timeline (`analyze::redefs`) beyond the two
      # promoted gap shapes: each call must see the body installed AT THAT MOMENT.

      # Three bodies across three sites -- every window observed.
      class Tri
        def gen = 1
      end
      puts Tri.new.gen

      class Tri
        def gen = 2
      end
      puts Tri.new.gen

      class Tri
        def gen = 3
      end
      puts Tri.new.gen

      # A subclass instance follows the SUPERCLASS's timeline (the overlay
      # propagates down the ancestry).
      class TriKid < Tri; end
      puts TriKid.new.gen

      # The redefinition changes ARITY: the pre-reopen body takes an argument,
      # the post-reopen one refuses it.
      class Ar
        def m(x) = "one:#{x}"
      end
      puts Ar.new.m(5)

      class Ar
        def m = "zero"
      end
      puts Ar.new.m
      begin
        Ar.new.m(5)
      rescue ArgumentError => e
        puts e.message
      end

      # `method(:name)` reflection resolves positionally too.
      class Refl
        def word = "early"
      end
      m = Refl.new.method(:word)
      puts m.call

      class Refl
        def word = "late"
      end
      puts Refl.new.method(:word).call
      # A Method object captured BEFORE the reopen: CRuby's Method is a snapshot
      # of the entry it was taken from.
      puts m.call

      # An attr reader superseded by a hand-written one ACROSS sites, with a
      # reader call in the window.
      class Acc
        attr_accessor :v
      end
      a = Acc.new
      a.v = 10
      puts a.v

      class Acc
        def v = "handwritten"
      end
      puts a.v

      # A yield-taking body superseded by a non-yielding one.
      class Blk
        def run = yield(1)
      end
      puts(Blk.new.run { |x| x + 1 })

      class Blk
        def run = "no yield"
      end
      puts Blk.new.run
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      3
      one:5
      zero
      wrong number of arguments (given 1, expected 0)
      early
      late
      early
      10
      handwritten
      2
      no yield
    OUT
  end

  it "splat value positions" do
    result = zr(<<~'RUBY')
      # Splat in value positions: `break *x` / `next *x` build an array (nil -> [],
      # array -> itself, scalar -> [v]); `when *arr` is membership of the splatted
      # array (literal or variable), on both statement and value-position cases.
      a = while true; break *[1, 2]; end
      p a
      b = while true; break *nil; end
      p b
      c = while true; break *1; end
      p c
      def r(v)
        x = yield
        v == x
      end
      p r([1]) { next *1 }
      p r([]) { next *nil }
      p r([2, 3]) { next *[2, 3] }
      def cat(x)
        case x
        when *['a', 'b', 'c'] then "letter"
        when *[1, 2, 3] then "number"
        else "other"
        end
      end
      p cat('b')
      p cat(2)
      p cat(:z)
      lst = [10, 20]
      case 20
      when *lst then puts "in list"
      else puts "not"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      []
      [1]
      true
      true
      true
      "letter"
      "number"
      "other"
      in list
    OUT
  end

  it "yield inside a constructor block belongs to the method" do
    result = zr(<<~'RUBY')
      # `Hash.new { ... }` lowers to its own `HirNode::New`, not to an ordinary
      # call, and the block hangs off that node. Two walks that decide whether a
      # method needs its `__blk` parameter used to match `New { args, .. }` and so
      # never looked at the block or the keyword arguments at all -- a `yield` in a
      # default-value block was invisible, and the method came out with no block
      # parameter to yield to.
      def with_default
        h = Hash.new { |_hash, key| yield key }
        [h[:a], h[:b]]
      end

      p(with_default { |k| "made:#{k}" })

      # `Array.new`'s block is the same node shape.
      def sized(n)
        Array.new(n) { |i| yield i }
      end

      p(sized(3) { |i| i * i })

      # ...and so is a `Struct.new` body, where the yield sits one level deeper.
      def build_point
        Struct.new(:x, :y) do
          define_method(:label) { "point" }
        end
      end

      Point = build_point
      p Point.new(1, 2).label

      # `block_given?` is the other half of the same question, and reaches the same
      # walk through the same node.
      def maybe_default
        h = Hash.new { |_hash, _key| block_given? }
        h[:anything]
      end

      p maybe_default
      p(maybe_default { :unused })
    RUBY

    _(result).must_answer <<~'OUT'
      ["made:a", "made:b"]
      [0, 1, 4]
      "point"
      false
      true
    OUT
  end

  it "yield method call in method body" do
    result = zr(<<~'RUBY')
      # Calling a yield-using method on implicit self from inside another
      # instance method's body used to drop the literal block — the call
      # site emitted `sp_C_run(self, "foo")` against a signature that
      # wanted 4 args. Same call from top-level worked.
      #
      # scan path: compile_writer_and_block_call_stmt's literal-block
      # branch only handled `recv < 0` for top-level methods (via the
      # global @meth_has_yield table) and `recv >= 0` for class methods
      # (via try_yield_or_trampoline_dispatch). The "implicit self inside
      # class method" case fell into neither.

      class C
        def run(name)
          yield
          name
        end

        def call_it
          run("foo") do
            puts "block ran"
          end
        end

        # Variant: default arg in target. Same root cause; just a different
        # arity surface — exercised explicitly because the issue called it
        # out as a separate failure mode.
        def run_with_default(name, count = 1)
          yield
          count
        end

        def call_it_default
          run_with_default("bar", -1) do
            puts "default-arg block ran"
          end
        end
      end

      # Parent class with the yield method, child calls it via implicit
      # self — exercises the new ancestor walk.
      class P
        def each_thing
          yield 1
          yield 2
        end
      end

      class K < P
        def use
          each_thing do |v|
            puts v
          end
        end
      end

      C.new.call_it
      C.new.call_it_default
      K.new.use
    RUBY

    _(result).must_answer <<~'OUT'
      block ran
      default-arg block ran
      1
      2
    OUT
  end

  it "yield self method return" do
    result = zr(<<~'RUBY')
      module M
        def self.go
          yield
        end
      end
      puts M.go { 7 }

      class K
        def self.twice
          yield + yield
        end
      end
      puts K.twice { 5 }

      module W
        def self.wrap
          "[" + yield + "]"
        end
      end
      puts W.wrap { "hi" }
      puts W.wrap { "hi" }.to_s
      v = M.go { 7 }
      puts Integer(v)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      10
      [hi]
      [hi]
      7
    OUT
  end

  it "yield value returns from method" do
    result = zr(<<~'RUBY')
      def f
        yield
      end

      def factory_init(size)
        free = []
        i = 0
        while i < size
          free.push(yield)
          i += 1
        end
        free
      end

      def double_yield
        yield * 2
      end

      puts f { 99 }

      result = factory_init(3) { 42 }
      puts result.length
      puts result[0]
      puts result[1]
      puts result[2]

      puts double_yield { 21 }
    RUBY

    _(result).must_answer <<~'OUT'
      99
      3
      42
      42
      42
      42
    OUT
  end
end
