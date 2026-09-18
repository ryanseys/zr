# frozen_string_literal: true

require "spec_helper"

describe "Methods: slicing" do
  it "anon splat forward" do
    result = ze0(<<~'RUBY')
      # An anonymous positional splat (`def m(a, *) = f(a, *)`, Ruby 3.0) must forward
      # through a receiver call, like a named `*args` does.
      #
      # An anonymous `*` was dropped def-side (only a named rest was registered), and
      # the anonymous `*` at the call site is a SplatNode with no expression, so the
      # argument packer emitted the -1 node and rejected ("no type"). Register the
      # anonymous rest under a synthetic name and resolve the call-site `*` to it.

      # 1. The gap: leading arg + anonymous rest forwarded to a rest-taking method.
      class R
        def call(m, *args) = [m, args]
      end
      class W
        def initialize(r) = (@r = r)
        def invoke(method, *) = @r.call(method, *)
        def go = invoke(:a, 1, 2)
      end
      p W.new(R.new).go                  #=> [:a, [1, 2]]

      # 2. Pure anonymous forward.
      class Q
        def sum(*a) = a.sum
        def fwd(*) = sum(*)
      end
      p Q.new.fwd(1, 2, 3)               #=> 6

      # 3. Leading arg + anon rest, empty and non-empty.
      class Z
        def take(x, *r) = [x, r]
        def pass(y, *) = take(y, *)
      end
      p Z.new.pass(:k)                   #=> [:k, []]
      p Z.new.pass(:k, 1, 2)             #=> [:k, [1, 2]]

      # 4. A named splat is unaffected (regression).
      class N
        def call(m, *a) = [m, a]
        def inv(method, *args) = call(method, *args)
      end
      p N.new.inv(:x, 9, 8)              #=> [:x, [9, 8]]

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, [1, 2]]
      6
      [:k, []]
      [:k, [1, 2]]
      [:x, [9, 8]]
      done
    OUT
  end

  it "bound method rest args" do
    result = ze0(<<~'RUBY')
      # A Method object whose target has a rest parameter takes ONE array there,
      # not one C argument per call-site argument. Bound positionally, the first
      # argument went into the array pointer's slot and the call died.
      class Var
        def sum(*a); a.sum; end
        def one(x); x * 2; end
        def mix(a, *rest); [a, rest]; end
      end
      p Var.new.method(:sum).call(1, 2, 3)
      p Var.new.method(:sum).call
      p Var.new.method(:one).call(4)
      p Var.new.method(:mix).call(1, 2, 3)
      p Var.new.sum(1, 2, 3)
    RUBY

    _(result).must_answer <<~'OUT'
      6
      0
      8
      [1, [2, 3]]
      6
    OUT
  end

  it "call and write" do
    result = ze0(<<~'RUBY')
      # CallAndWriteNode -- `obj.attr &&= val`.
      #
      # Reads `obj.attr`; if truthy, assigns. Mirror of CallOrWriteNode
      # with condition inverted. Receiver evaluated exactly once.

      class Cfg
        attr_accessor :name
        def initialize(n)
          @name = n
        end
      end

      set = Cfg.new("hello")
      set.name &&= "WORLD"      # truthy -> fires
      puts set.name             # WORLD

      # Receiver-once verification.
      $call_count = 0
      def get_cfg(c)
        $call_count += 1
        c
      end

      c = Cfg.new("first")
      get_cfg(c).name &&= "second"  # `c.name` truthy -> fires;
                                    # get_cfg called exactly once
      puts $call_count           # 1
      puts c.name                # second
    RUBY

    _(result).must_answer <<~'OUT'
      WORLD
      1
      second
    OUT
  end

  it "call or write" do
    result = ze0(<<~'RUBY')
      # CallOrWriteNode -- `obj.attr ||= val`.
      #
      # Reads `obj.attr`; if falsy, assigns `obj.attr = val`. Receiver
      # evaluated exactly once.
      #
      # Spinel's nil-to-empty-string conversion for string slots makes
      # the "fire when nil" branch hard to exercise in a CRuby-equivalent
      # way (CRuby sees nil-falsy; Spinel sees ""-truthy because it
      # sentinels nil to the empty string in typed string slots). This
      # test focuses on the don't-fire-when-truthy branch which agrees
      # in both.

      class Cfg
        attr_accessor :name
        def initialize(n)
          @name = n
        end
      end

      set = Cfg.new("explicit")
      set.name ||= "fallback"   # truthy -> doesn't fire
      puts set.name             # explicit

      # Receiver evaluated once: a side-effecting receiver only fires once.
      $call_count = 0
      def get_cfg(c)
        $call_count += 1
        c
      end

      c = Cfg.new("first")
      get_cfg(c).name ||= "second"  # `c.name` is "first" (truthy), so no write,
                                    # but get_cfg should still be called exactly once
      puts $call_count           # 1
      puts c.name                # first
    RUBY

    _(result).must_answer <<~'OUT'
      explicit
      1
      first
    OUT
  end

  it "class method visibility" do
    result = ze0(<<~'RUBY')
      # `private_class_method` marks a class method the same way `private` marks an
      # instance one: the name stays callable from inside the class's own class
      # methods and through `send`, but an explicit receiver raises, and the default
      # reflection stops reporting it.
      #
      # Enforcement is compile-time, like the instance half -- so a call zeo resolves
      # statically reads the visibility the class BODY declared. A `private_class_method`
      # run later, against an already-compiled class, still changes what the
      # reflection reports but cannot retract a call site already bound (zeo's
      # documented Path-1 posture, which the instance half shares).
      def err
        yield
      rescue NoMethodError => e
        [:nome, e.message]
      end

      class A
        def self.pub = helper
        def self.helper = 21
        private_class_method :helper
      end
      p A.pub
      p err { A.helper }
      p A.respond_to?(:helper)
      p A.respond_to?(:helper, true)
      p A.singleton_methods
      p A.send(:helper)
      p err { A.public_send(:helper) }
      p A.method(:helper).call

      # The singleton class's instance methods ARE the class's class methods, and
      # report the same visibility.
      sc = A.singleton_class
      p sc.instance_methods(false).sort
      p sc.private_instance_methods(false)
      p sc.private_method_defined?(:helper)
      p sc.public_method_defined?(:helper)
      p sc.public_method_defined?(:pub)

      # The `def` form, on a module.
      module M
        def self.pub2 = h2
        private_class_method def self.h2 = 7
      end
      p M.pub2
      p err { M.h2 }

      # `public_class_method` puts it back.
      class B
        def self.helper = 1
        private_class_method :helper
        public_class_method :helper
      end
      p B.helper
      p B.respond_to?(:helper)

      # A subclass inherits the mark, and can promote it back.
      class C < A; end
      p err { C.helper }
      p C.pub
      class Promoted < A
        public_class_method :helper
      end
      p Promoted.helper

      # An explicit `self` receiver is allowed, exactly as for a private instance
      # method.
      class S
        def self.entry = self.secret
        def self.secret = :ok
        private_class_method :secret
      end
      p S.entry

      # `new` is a class method like any other.
      class D
        private_class_method :new
        def self.build = new
      end
      p err { D.new }
      p D.build.class

      # Several names at once. Ruby resolves each right here, so the `def`s have to
      # come first -- `private_class_method` on an undefined name is a NameError.
      class Multi
        def self.one = 1
        def self.two = 2
        def self.three = 3
        private_class_method :one, :two
      end
      p err { Multi.one }
      p err { Multi.two }
      p Multi.three
      p Multi.singleton_methods.sort
    RUBY

    _(result).must_answer <<~'OUT'
      21
      [:nome, "private method 'helper' called for class A"]
      false
      true
      [:pub]
      21
      [:nome, "private method 'helper' called for class A"]
      21
      [:pub]
      [:helper]
      true
      false
      true
      7
      [:nome, "private method 'h2' called for module M"]
      1
      true
      [:nome, "private method 'helper' called for class C"]
      21
      21
      :ok
      [:nome, "private method 'new' called for class D"]
      D
      [:nome, "private method 'one' called for class Multi"]
      [:nome, "private method 'two' called for class Multi"]
      3
      [:three]
    OUT
  end

  it "ctor default reads self" do
    result = ze0(<<~'RUBY')
      # A constructor's default argument is evaluated on the object being built, so
      # it can call the object's own methods. Emitting it at the call site named a
      # `self` that does not exist there yet; the construction now allocates first
      # and runs initialize with the fresh object in scope.

      class A
        def base
          10
        end

        def initialize(n = base * 2)
          @n = n
        end

        def val
          @n
        end
      end

      class Counter
        attr_reader :size
        def initialize(items = default_items)
          @size = items.length
        end

        def default_items
          [1, 2, 3]
        end
      end

      p A.new.val
      p A.new(5).val
      p Counter.new.size
      p Counter.new([1]).size
    RUBY

    _(result).must_answer <<~'OUT'
      20
      5
      3
      1
    OUT
  end

  it "destructuring params take splats" do
    result = ze0(<<~'RUBY')
      # A destructuring param may carry a splat, named or anonymous -- the same
      # `before`/`splat`/`after` shape every multi-assignment target group has.

      [[1, [2, 3, 4]]].each { |a, (b, *r)| p [a, b, r] }
      [[1, 2, 3]].each { |a, (*), b| p [a, b] }
      [[[1, 2, 3], 9]].each { |(*init, last), z| p [init, last, z] }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, [3, 4]]
      [1, 3]
      [[1, 2], 3, 9]
    OUT
  end

  it "issue runtime override builtin iterator" do
    result = ze0(<<~'RUBY')
      # Overriding a BUILTIN iterator at runtime has to take effect.
      #
      # Two layers had to move, because a builtin receiver reaches neither of the
      # ones the object receiver uses. Dispatch: the value MRO walk probed the
      # registry reopens and the builtin table per ancestor but never the overlay,
      # so the definition sat there unread -- a runtime `define_method` now outranks
      # both, PER ancestor, which is ruby's placement rule (an `Enumerable` override
      # must not beat `Array`'s own row). Codegen: `3.times` and `(1..3).each` on
      # literal receivers fuse into native counted loops, which are not calls at
      # all, so nothing is left for the Path 1 de-optimization to stand down from --
      # the nomination has to be withheld while the sites are chosen.

      t = 0
      3.times { |i| t += i }
      Integer.send(:define_method, :times) { |&b| b.call(99); self }
      r = []
      3.times { |i| r << i }
      p [t, r]

      a = [1, 2]
      s = []
      a.each { |v| s << v }
      Array.send(:define_method, :each) { |&b| b.call(:patched); self }
      s2 = []
      a.each { |v| s2 << v }
      p [s, s2]

      h = { x: 1 }
      hk = []
      h.each { |k, v| hk << [k, v] }
      Hash.send(:define_method, :each) { |&b| b.call(:hpatched, nil); self }
      hk2 = []
      h.each { |k, v| hk2 << [k, v] }
      p [hk, hk2]

      rg = []
      (1..3).each { |i| rg << i }
      Range.send(:define_method, :each) { |&b| b.call(:rpatched); self }
      rg2 = []
      (1..3).each { |i| rg2 << i }
      p [rg, rg2]

      # A per-object singleton on the very array being iterated is closer still.
      c = [7, 8]
      c1 = []
      c.each { |v| c1 << v }
      def c.each; yield :singleton; self; end
      c2 = []
      c.each { |v| c2 << v }
      p [c1, c2]

      # The fused loop stands down for a NON-literal receiver too, and for one
      # reached through a variable.
      n = 3
      n2 = []
      n.times { |i| n2 << i }
      p n2

      # A name nothing patches keeps its fused loop -- this is the common case, and
      # the reason the nomination is withheld per NAME rather than switched off.
      sum = 0
      4.upto(6) { |i| sum += i }
      p sum
    RUBY

    _(result).must_answer <<~'OUT'
      [3, [99]]
      [[1, 2], [:patched]]
      [[[:x, 1]], [[:hpatched, nil]]]
      [[1, 2, 3], [:rpatched]]
      [[:patched], [:singleton]]
      [99]
      15
    OUT
  end

  it "keyword arguments" do
    result = ze0(<<~'RUBY')
      # Keyword arguments and `**` double-splats: literal `k: v` pairs and `**hash`
      # expansions live in ONE ordered list, merged left-to-right with last-key-wins.
      # Because Ruby's Hash is insertion-ordered, the order the two are written in is
      # observable -- so it has to be preserved end to end.

      def capture(**opts) = opts

      # --- key order is preserved across a splat/pair boundary --------------------
      base = { a: 1, b: 2 }

      # A splat written BEFORE a literal pair: the splatted keys come first.
      p capture(**base, c: 3)          # {a: 1, b: 2, c: 3}

      # ...and AFTER: the literal pair comes first.
      p capture(c: 3, **base)          # {c: 3, a: 1, b: 2}

      # Interleaved, in exactly the written order.
      p capture(**{a: 1}, b: 2, **{c: 3})   # {a: 1, b: 2, c: 3}

      # --- more than one `**` per call --------------------------------------------
      p capture(**{x: 1}, **{y: 2})    # {x: 1, y: 2}

      # A duplicated key takes its LAST value, wherever the collision comes from.
      p capture(**{k: 1}, k: 2)        # {k: 2}
      p capture(k: 1, **{k: 2})        # {k: 2}

      # --- the same rules drive a `{ }` hash literal ------------------------------
      h = { a: 1 }
      p({ **h, b: 2 })                 # {a: 1, b: 2}
      p({ b: 2, **h })                 # {b: 2, a: 1}
      p({ x: 0, **{ x: 9 } })          # {x: 9}

      # --- `**obj` converts through `to_hash` -------------------------------------
      # A non-Hash that defines `to_hash` splats like a hash; a plain object would
      # raise TypeError.
      class Options
        def to_hash = { timeout: 30, retries: 2 }
      end
      p capture(**Options.new, verbose: true)   # {timeout: 30, retries: 2, verbose: true}

      # --- a runtime-empty `**h` contributes nothing at a CALL site ---------------
      # (unlike a hash literal, where `{**{}}` is a real empty hash).
      def describe(*positional, **kw)
        [positional, kw]
      end
      empty = {}
      p describe(1, 2, **empty)         # [[1, 2], {}]  -- no phantom trailing hash arg
      p({ **empty })                    # {}            -- an explicit empty hash literal

      # --- keyword params bind by name; a keyword-less callee gets an options hash -
      def greet(name:, greeting: "Hello") = "#{greeting}, #{name}!"
      puts greet(name: "Ada")
      puts greet(**{ name: "Grace", greeting: "Hi" })

      def legacy(opts = {}) = opts       # declares NO keywords
      p legacy(mode: :fast, level: 3)    # {mode: :fast, level: 3} -- becomes one hash

      # --- `yield` forwards keywords too ------------------------------------------
      def with_config
        yield 1, **{ width: 80, height: 24 }
      end
      with_config { |n, cfg| p [n, cfg] }   # [1, {width: 80, height: 24}]
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      {a: 1, b: 2, c: 3}
      {c: 3, a: 1, b: 2}
      {a: 1, b: 2, c: 3}
      {x: 1, y: 2}
      {k: 2}
      {k: 2}
      {a: 1, b: 2}
      {b: 2, a: 1}
      {x: 9}
      {timeout: 30, retries: 2, verbose: true}
      [[1, 2], {}]
      {}
      Hello, Ada!
      Hi, Grace!
      {mode: :fast, level: 3}
      [1, {width: 80, height: 24}]
    OUT
      lang/methods/slicing_test.rb:24: warning: key :k is duplicated and overwritten on line 24
      lang/methods/slicing_test.rb:25: warning: key :k is duplicated and overwritten on line 25
      lang/methods/slicing_test.rb:31: warning: key :x is duplicated and overwritten on line 31
    ERR
  end

  it "keyword table to a def without keywords roots no stale slot" do
    result = ze0(<<~'RUBY')
      # Literal keywords reach a def that declares none as one Hash, made
      # before the arity check fills the required parameters' slots: the
      # collector must not read what an earlier frame left in them.
      def fill(a, b) = [a, b]
      def take(first, opts = nil) = [first, opts]

      last = nil
      2000.times do |i|
        fill(Object.new, Object.new)
        last = take("x", k: i)
      end
      p last

    RUBY

    _(result).must_answer "[\"x\", {k: 1999}]\n"
  end

  it "kwargs and forwarding" do
    result = ze0(<<~'RUBY')
      # Keyword arguments through every dispatch shape, plus argument forwarding
      # (`...`, anonymous `*`/`**`/`&`).

      def config(host:, port: 80, **rest)
        [host, port, rest]
      end

      # Literal keywords, in any written order.
      p config(host: "a")
      p config(host: "a", port: 8080)
      p config(port: 8080, host: "a")
      p config(host: "a", debug: true, retries: 3)

      # A `**hash` splat supplies them.
      opts = { host: "b", port: 443 }
      p config(**opts)
      p config(**{ host: "c" })

      # Keywords through `send` -- the dynamic path.
      p send(:config, host: "d")
      p send(:config, **opts)

      # Through a Method object.
      p method(:config).call(host: "e", port: 1)

      # Through a dynamically-typed receiver.
      class Server
        def start(host:, port: 3000)
          "#{host}:#{port}"
        end
      end
      s = Server.new
      p s.start(host: "x")
      p s.start(**{ host: "y", port: 9 })
      holder = [Server.new]
      p holder[0].start(host: "z")
      p holder.first.start(host: "w", port: 2)

      # A missing required keyword raises at runtime, so it can be rescued.
      begin
        config(port: 1)
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end

      # An unknown keyword raises too (no **rest to absorb it).
      def strict(a:) = a
      begin
        strict(a: 1, b: 2)
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end

      # Keywords and positionals together.
      def mixed(a, b = 2, *rest, key:, opt: :o, **kw)
        [a, b, rest, key, opt, kw]
      end
      p mixed(1, key: :k)
      p mixed(1, 9, :r, key: :k, opt: :p, extra: 1)

      # A trailing Hash is NOT implicitly converted to keywords (Ruby 3+).
      def positional_hash(h) = h
      p positional_hash({ a: 1 })

      # --- Forwarding ------------------------------------------------------------

      def target(a, b = :db, *rest, key: :dk, **kw, &blk)
        out = [a, b, rest, key, kw]
        out << blk.call if blk
        out
      end

      # `...` forwards positionals, keywords and the block together.
      def fwd_all(...) = target(...)
      p fwd_all(1)
      p fwd_all(1, 2, 3, key: :k, extra: 9)
      p(fwd_all(1) { "blk" })

      # Anonymous `*` forwards positionals.
      def fwd_pos(*) = target(*)
      p fwd_pos(1, 2, 3)

      # Anonymous `**` forwards keywords.
      def fwd_kw(a, **) = target(a, **)
      p fwd_kw(1, key: :k, x: 1)

      # Anonymous `&` forwards the block.
      def fwd_blk(a, &) = target(a, &)
      p(fwd_blk(1) { "anon-blk" })

      # Named forwarding still works.
      def fwd_named(*args, **kw, &blk) = target(*args, **kw, &blk)
      p fwd_named(1, 2, key: :k)
      p(fwd_named(1) { "named" })

      # A splat and literal args compose.
      def splat_mix(*args) = target(*args, key: :from_call)
      p splat_mix(1, 2)

      # Forwarding through two hops.
      def hop1(...) = hop2(...)
      def hop2(...) = target(...)
      p hop1(1, 2, key: :hopped)
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", 80, {}]
      ["a", 8080, {}]
      ["a", 8080, {}]
      ["a", 80, {debug: true, retries: 3}]
      ["b", 443, {}]
      ["c", 80, {}]
      ["d", 80, {}]
      ["b", 443, {}]
      ["e", 1, {}]
      "x:3000"
      "y:9"
      "z:3000"
      "w:2"
      ArgumentError: missing keyword: :host
      ArgumentError: unknown keyword: :b
      [1, 2, [], :k, :o, {}]
      [1, 9, [:r], :k, :p, {extra: 1}]
      {a: 1}
      [1, :db, [], :dk, {}]
      [1, 2, [3], :k, {extra: 9}]
      [1, :db, [], :dk, {}, "blk"]
      [1, 2, [3], :dk, {}]
      [1, :db, [], :k, {x: 1}]
      [1, :db, [], :dk, {}, "anon-blk"]
      [1, 2, [], :k, {}]
      [1, :db, [], :dk, {}, "named"]
      [1, 2, [], :from_call, {}]
      [1, 2, [], :hopped, {}]
    OUT
  end

  it "kwargs double splat at a call site binds" do
    result = ze0(<<~'RUBY')
      # `**h` merges into the G2 trailing-kwargs Hash (literal pairs first,
      # splat entries after, same-key replacement -- `Hash#merge`'s rule).

      class Greeter
        def f(x:, y: 0)
          "#{x}/#{y}"
        end
      end
      h = {x: 1}
      puts Greeter.new.f(**h)
      puts Greeter.new.f(y: 5, **{x: 2, y: 9})
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      1/0
      2/9
    OUT
      lang/methods/slicing_test.rb:11: warning: key :y is duplicated and overwritten on line 11
    ERR
  end

  it "kwargs splat unknown keyword" do
    result = ze0(<<~'RUBY')
      # Forwarding a **hash that carries a key not accepted by the callee's fixed
      # keyword params raises ArgumentError, matching CRuby, instead of silently
      # ignoring the extra key.
      def take(a:); a; end
      def f(h); take(**h); end

      begin
        f({a: 1, b: 2})
      rescue ArgumentError => e
        puts e.message          # unknown keyword: :b
      end

      p f({a: 5})               # 5, a valid forward still works

      def two(a:, b:); [a, b]; end
      def g(h); two(**h); end

      begin
        g({a: 1, b: 2, c: 3, d: 4})
      rescue ArgumentError => e
        puts e.message          # unknown keywords: :c, :d
      end

      p g({a: 1, b: 2})         # [1, 2]

      # a callee WITH a keyword-rest absorbs the extras (no error).
      def rest(a:, **opts); [a, opts]; end
      p rest(a: 1, x: 9, y: 8)  # [1, {x: 9, y: 8}]
    RUBY

    _(result).must_answer <<~'OUT'
      unknown keyword: :b
      5
      unknown keywords: :c, :d
      [1, 2]
      [1, {x: 9, y: 8}]
    OUT
  end

  it "kwsplat literal" do
    result = ze0(<<~'RUBY')
      # Double-splatting a hash LITERAL at a call site (`f(**{ ... })`) must compile.
      #
      # The call-site double-splat pre-evaluates the spread hash to a temp. For a bare
      # variable that emits with no prelude, but a hash literal drains its own
      # construction into the prelude buffer -- which landed inside the temp's
      # declaration line, so the emitted C was `sp_SymPolyHash * _t = sp_SymPolyHash
      # *_t2 = ...` (a type name where an expression was expected). Render the literal
      # into a side buffer first so its construction lands before the assignment.

      # 1. Into a keyword-rest parameter.
      def a(**k) = k
      p a(**{ x: 1, y: 2 })              #=> {x: 1, y: 2}

      # 2. Into explicit keyword parameters.
      def b(x:, y:) = [x, y]
      p b(**{ x: 3, y: 4 })              #=> [3, 4]

      # 3. Literal splat plus a trailing explicit key.
      def c(**k) = k
      p c(**{ x: 1 }, z: 5)              #=> {x: 1, z: 5}

      # 4. All keyword params supplied (including one with a default).
      def r(x:, y:, z: 0) = [x, y, z]
      p r(**{ x: 1, y: 2, z: 9 })        #=> [1, 2, 9]

      # 5. String-value kwargs into a kwrest.
      def kw(**opts) = opts
      p kw(**{ color: "red", size: 3 })  #=> {color: "red", size: 3}

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      {x: 1, y: 2}
      [3, 4]
      {x: 1, z: 5}
      [1, 2, 9]
      {color: "red", size: 3}
      done
    OUT
  end

  it "leading optional params" do
    result = ze0(<<~'RUBY')
      # Ruby funds the required parameters first and spends what is left on the
      # optional ones, wherever they sit. Reading the argument list positionally put
      # a lone argument in the leading optional and left the required one at its zero
      # value, and the arity check rejected the call outright before that.
      def a(x = 1, y)
        [x, y]
      end
      p a(8)
      p a(7, 8)

      def b(x = 1, y = 2, z)
        [x, y, z]
      end
      p b(9)
      p b(8, 9)
      p b(7, 8, 9)

      # an optional in the middle
      def c(p1, o = 2, r)
        [p1, o, r]
      end
      p c(1, 3)
      p c(1, 2, 3)

      class K
        def m(x = 1, y)
          [x, y]
        end
      end
      p K.new.m(8)
      p K.new.m(7, 8)

      e = ->(x = 1, y) { [x, y] }
      p e.call(8)

      # mixed with a keyword parameter
      def f(x = 1, y, k: 5)
        [x, y, k]
      end
      p f(8)
      p f(8, k: 9)

      # the conventional shapes are untouched
      def h(x, y = 2)
        [x, y]
      end
      p h(1)
      p h(1, 3)

      def i(x, y)
        [x, y]
      end
      p i(1, 2)

      def j(x = 1, y = 2)
        [x, y]
      end
      p j
      p j(8)
      p j(8, 9)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 8]
      [7, 8]
      [1, 2, 9]
      [8, 2, 9]
      [7, 8, 9]
      [1, 2, 3]
      [1, 2, 3]
      [1, 8]
      [7, 8]
      [1, 8]
      [1, 8, 5]
      [1, 8, 9]
      [1, 2]
      [1, 3]
      [1, 2]
      [1, 2]
      [8, 2]
      [8, 9]
    OUT
  end

  it "leading splat scalar massign" do
    result = ze0(<<~'RUBY')
      # A leading/middle-splat massign with a scalar RHS aligns the value to the post-
      # rest targets: the rest is empty and the first post-target takes the value.
      def a1(x); *a, b = x; [a, b]; end
      p a1(1)
      def a2(x); *a, b, c = x; [a, b, c]; end
      p a2(1)
      def a3(x); a, *r, c = x; [a, r, c]; end
      p a3(1)
      def a4(x); a, b, *r = x; [a, b, r]; end
      p a4(1)
      def a5(x); *a = x; a; end
      p a5(1)
      def a6(x); *a, b = x; [a, b]; end
      p a6([1, 2, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      [[], 1]
      [[], 1, nil]
      [1, [], nil]
      [1, nil, []]
      [1]
      [[1, 2], 3]
    OUT
  end

  it "method added hook survives a reopen" do
    result = ze0(<<~'RUBY')
      # The ClassMethods idiom where the `include` sits in a REOPEN, and where the
      # hook is inherited one class further down.
      #
      # Both are the shape bundler actually has, and both were missed after the
      # first cut of the fix: `analyze::classes` takes a different branch for a
      # reopen site (`defer_positional_mixin`, which stages the mixin as a runtime
      # send) and that branch skipped recording the edge. `class Bundler::Thor;
      # include Bundler::Thor::Base` IS a reopen, because the nested `Thor::*`
      # files create the shell first -- so the whole of Thor missed it.
      #
      # The lesson worth keeping: an edge belongs to the INCLUDE, not to how the
      # mixin happens to be staged.
      module CM
        def method_added(name) = ((@added ||= []) << name)
        def added = @added
      end

      module Base
        class << self
          def included(base) = base.extend(CM)
        end
      end

      class Reopened; end

      class Reopened
        include Base
        def a; end
      end

      p Reopened.added

      # One further down: the hook arrives on the superclass and the subclass's own
      # definitions must still announce.
      class Below < Reopened
        def b; end
        def c; end
      end

      p Below.added
    RUBY

    _(result).must_answer "[:a]\n[:b, :c]\n"
  end

  it "param lengthlike body widen" do
    result = ze0(<<~'RUBY')
      # #552. Body-usage param inference widens int/nil-defaulted
      # params to flat `poly` when the body calls a length-like
      # method (length / size / empty?) on the param. These methods
      # exist on String / Array / Hash but NOT on Integer, so a
      # body proving it calls them on a param establishes the param
      # is one of those container types. Codegen's poly-recv
      # dispatch routes through tag/cls_id arms covering String +
      # every Array variant + every Hash variant.
      #
      # Discriminator: the Hash case (last line, prints 2) failed
      # pre-fix; the warning was silenced for some cases by earlier
      # Option C work but the Hash-variant length dispatch wasn't
      # wired in emit_poly_builtin_dispatch. String and Array
      # variants happen to have worked already; this test still
      # pins them so a future regression in the broader poly-recv
      # length pathway is caught.
      #
      # nil semantics: nil has no #length, and the poly path used
      # to answer 0 for it (the length helper's answer for anything
      # that is not a collection). It raises NoMethodError now, as
      # CRuby does (#3974), so the nil case is asserted through a
      # rescue.
      #
      # Conservative classifier: only length / size / empty? widen.
      # These don't exist on Integer so widening to poly is sound.
      # Methods that DO exist on Integer (<<, &, |, +, -, *, [])
      # are deliberately excluded -- a body like
      # `def poke(data); data << 8; end` (optcarrot's PPU) is
      # legitimately Integer arithmetic and would break under a
      # broader widening.

      def consume_length(x)
        x.length
      end

      def consume_empty(x)
        x.empty?
      end

      class Box
        attr_accessor :contents
      end

      b = Box.new
      begin
        puts consume_length(b.contents)
      rescue NoMethodError => e
        puts e.message
      end
      b.contents = "hello"
      puts consume_length(b.contents)
      b.contents = [1, 2, 3, 4]
      puts consume_length(b.contents)
      b.contents = { "a" => 1, "b" => 2 }
      puts consume_length(b.contents)
      puts consume_empty(b.contents)
      b.contents = {}
      puts consume_empty(b.contents)
    RUBY

    _(result).must_answer <<~'OUT'
      undefined method 'length' for nil
      5
      4
      2
      false
      true
    OUT
  end

  it "redefining a method in one class body last def wins" do
    result = ze0(<<~'RUBY')
      class Foo
        def a
          "first"
        end

        def a
          "second"
        end
      end

      puts Foo.new.a
    RUBY

    _(result).must_answer "second\n"
  end

  it "redefinition window reports its own body" do
    result = ze0(<<~'RUBY')
      # Inside a REDEFINITION WINDOW -- between two same-name `def`s -- reflection
      # answers for the body that is LIVE, not the last one written.
      #
      # `analyze::redefs` put the timeline in the runtime overlay: the first body
      # installs at boot and each later one re-installs at its own document
      # position. What it did NOT carry was everything beside the body. `#arity`,
      # `#parameters` and `#source_location` are compile-time tables keyed by
      # `(class, name)` with no position, so from the program's first line they
      # answered the final `def`.
      #
      # The fix is a reflection row per BODY (`ProgramDesc::redef_metas`), seeded
      # UNregistered and installed by whichever position is live -- the boot install
      # for the first body, the positional install for each later one. Both halves
      # of a `def` now land at the same place.
      #
      # Still open, and filed: a `private` mark made before a reopen is not enforced
      # in the window (a_redefinition_window_ignores_a_visibility_mark.rb), and a
      # `Method`/`UnboundMethod` captured in the window does not snapshot its
      # definition (a_method_object_does_not_snapshot_its_definition.rb).

      def loc(m) = [m.arity, m.parameters, m.source_location&.last]

      class R
        def r = "r1"
      end
      p loc(R.instance_method(:r))
      class R
        def r(x, y = 1, *z, k:, **o, &b) = "r2"
      end
      p loc(R.instance_method(:r))
      class R
        def r(a) = "r3"
      end
      p loc(R.instance_method(:r))
      p R.new.r(1)

      class CR
        def self.c = "c1"
      end
      p loc(CR.method(:c))
      class CR
        def self.c(x) = "c2"
      end
      p loc(CR.method(:c))

      # three bodies in ONE body, with statements between
      class T
        def t = 1
        p loc(instance_method(:t))
        def t(a) = 2
        p loc(instance_method(:t))
        def t(a, b) = 3
        p loc(instance_method(:t))
      end

      # a method_added hook observing each
      class H
        def self.method_added(n)
          p [:added, n, instance_method(n).arity] unless n == :method_added
        end
        def h = 1
        def h(a) = 2
      end

      # a module's method
      module MM
        def m = 1
      end
      p loc(MM.instance_method(:m))
      module MM
        def m(a, b) = 2
      end
      p loc(MM.instance_method(:m))
    RUBY

    _(result).must_answer <<~'OUT'
      [0, [], 24]
      [-3, [[:req, :x], [:opt, :y], [:rest, :z], [:keyreq, :k], [:keyrest, :o], [:block, :b]], 28]
      [1, [[:req, :a]], 32]
      "r3"
      [0, [], 38]
      [1, [[:req, :x]], 42]
      [0, [], 48]
      [1, [[:req, :a]], 50]
      [2, [[:req, :a], [:req, :b]], 52]
      [:added, :h, 0]
      [:added, :h, 1]
      [0, [], 67]
      [2, [[:req, :a], [:req, :b]], 71]
    OUT
  end

  it "second def on a builtin is positional" do
    result = ze0(<<~'RUBY')
      class Array
        def size = 1
      end
      p [1, 2].size
      class Array
        def size = 2
      end
      p [1, 2].size

      module Kernel
        def helper = "first"
      end
      puts helper
      module Kernel
        def helper = "second"
      end
      puts helper

      class String
        def shout = "first"
      end
      puts "a".shout
      class String
        def shout = "second"
      end
      puts "a".shout
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      first
      second
      first
      second
    OUT
  end

  it "singleton body writes the class method table" do
    result = ze0(<<~'RUBY')
      # A `class << self` body's statements are RECEIVERLESS in ruby. zeo rebinds
      # them onto `self.singleton_class`, so the receiver must be the surrogate --
      # that is the table those methods live in -- while the visibility barrier the
      # receiverless form never raises must stay down.

      class Vis
        class << self
          def a = :a
          def b = :b
          def c = :c

          # The literal form folds at compile time; the computed one is a real
          # `Module#private`/`#public` send at run time. Both write the same table.
          private :a
          names = [:b]
          private(*names)
          public(*names)
        end
      end
      p Vis.b
      p Vis.c
      begin
        Vis.a
      rescue NoMethodError => e
        puts e.message
      end

      # `extend self` first, then the singleton body re-scopes what the extend
      # brought in -- fileutils' Verbose/NoWrite/DryRun shape.
      module Chatty
        def speak = :spoke
        def hush = :hushed
        private :speak, :hush

        extend self

        class << self
          public(*[:speak, :hush])
        end
      end
      p Chatty.speak
      p Chatty.hush

      # NOTE: `protected(*names)` on a CLASS method is a known gap in both
      # backends -- the runtime's class-method visibility is a private/public
      # boolean, so protected cannot be recorded there. Left out deliberately
      # rather than pinned wrong.

      # A receiver the SOURCE wrote is not the synthesized one: the barrier holds.
      class Hand
        class << self
          def open_it = :open

          private

          def shut = :shut
        end
      end
      p Hand.open_it
      begin
        Hand.singleton_class
        Hand.shut
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      :b
      :c
      private method 'a' called for class Vis
      :spoke
      :hushed
      :open
      private method 'shut' called for class Hand
    OUT
  end

  it "splat call" do
    result = ze0(<<~'RUBY')
      # Splat operator at the call site.
      # Covers pure splat, splat into a method with required + rest params,
      # and mixed prefix/splat/suffix into a rest-collecting method.

      def collect(*nums)
        total = 0
        nums.each { |n| total += n }
        puts nums.length
        puts total
      end

      # Pure splat into rest-only method
      args = [1, 2, 3]
      collect(*args)        # length 3, total 6

      # Empty splat
      empty = []
      collect(*empty)       # length 0, total 0

      # Splat with a method that has fixed prefix + rest
      def mix(a, b, *rest)
        puts a
        puts b
        puts rest.length
        rest.each { |x| puts x }
      end

      # Pure splat fills both fixed slots and the rest
      quad = [10, 20, 30, 40]
      mix(*quad)            # a=10, b=20, rest=[30,40]

      # Prefix + splat fills the rest
      tail = [3, 4, 5]
      mix(1, 2, *tail)      # a=1, b=2, rest=[3,4,5]

      # Prefix + splat + suffix all bundle into rest
      mid = [3, 4]
      mix(1, 2, *mid, 5, 6) # a=1, b=2, rest=[3,4,5,6]

      # Bare call leaves rest empty (regression check for the empty-rest fix)
      mix(100, 200)         # a=100, b=200, rest=[]

      # Prefix overflows into rest when method has *only* a rest param
      collect(7, *args)     # length 4, total 13
      collect(7, 8, *args, 9) # length 6, total 36

      # Mixed-type splat sources: poly_array source, mixed prefix/suffix.
      # Spinel's *rest is always int_array so element values are mrb_int bits
      # for non-int elements — but the length is correct and the bundle
      # round-trips intact for downstream splatting.
      def count(*xs)
        puts xs.length
      end
      count(1, "x", 2.0)            # 3
      mix = [1, "two", :three, 4.0]
      count(*mix)                   # 4
      count(0, *mix, "tail", 99.5)  # 7

      # Two splats in one call (multi-splat fallback path).
      left = [1, 2]
      right = [3, 4, 5]
      count(*left, *right)          # 5

      # Splat into a method with str fixed prefix + rest — exercises the
      # splat-aware param-type inference (without it, "first" would default to
      # mrb_int and we'd print garbage instead of "alpha").
      def head_str(first, *tail)
        puts first
        puts tail.length
      end
      strs = ["alpha", "beta", "gamma"]
      head_str(*strs)               # alpha / 2
    RUBY

    _(result).must_answer <<~'OUT'
      3
      6
      0
      0
      10
      20
      2
      30
      40
      1
      2
      3
      3
      4
      5
      1
      2
      4
      3
      4
      5
      6
      100
      200
      0
      4
      13
      6
      30
      3
      4
      7
      5
      alpha
      2
    OUT
  end

  it "splat destructure" do
    result = ze0(<<~'RUBY')
      # Splat (rest) target in multi-assignment.
      # Covers leading / trailing / middle splat against array literals,
      # different element types, and a rest-returning function source.

      # Trailing splat from array literal (int_array)
      a, *b = [1, 2, 3, 4]
      puts a            # 1
      puts b.length     # 3
      b.each { |v| puts v }   # 2 / 3 / 4

      # Leading splat (everything but the last lands in the splat target)
      *xs, last = [10, 20, 30, 40]
      puts last         # 40
      puts xs.length    # 3
      xs.each { |v| puts v }  # 10 / 20 / 30

      # Middle splat
      first, *mid, fin = [100, 200, 300, 400, 500]
      puts first        # 100
      puts fin          # 500
      puts mid.length   # 3
      mid.each { |v| puts v } # 200 / 300 / 400

      # Splat with str_array RHS
      s, *rest = ["alpha", "beta", "gamma"]
      puts s            # alpha
      puts rest.length  # 2
      rest.each { |w| puts w }  # beta / gamma

      # RHS shorter than fixed targets — splat target empty
      p, *q = [42]
      puts p            # 42
      puts q.length     # 0

      # Function returning typed array
      def numbers
        [7, 8, 9, 10]
      end

      n1, *n_rest = numbers
      puts n1           # 7
      puts n_rest.length  # 3
      n_rest.each { |v| puts v }  # 8 / 9 / 10

      # Mixed-type destructure: each fixed target gets its own native type
      ma, mb, mc = [1, "b", 2.0]
      puts ma           # 1
      puts mb           # b
      puts mc           # 2.0

      # Mixed-type with splat: splat target becomes a poly_array
      mx, *mmid, mlast = [10, "two", :three, 4.0, "five"]
      puts mx           # 10
      puts mlast        # five
      puts mmid.length  # 3
      mmid.each { |mv| p mv }  # "two" / :three / 4.0
    RUBY

    _(result).must_answer <<~'OUT'
      1
      3
      2
      3
      4
      40
      3
      10
      20
      30
      100
      500
      3
      200
      300
      400
      alpha
      2
      beta
      gamma
      42
      0
      7
      3
      8
      9
      10
      1
      b
      2.0
      10
      five
      3
      "two"
      :three
      4.0
    OUT
  end

  it "splat forwarding args" do
    result = ze0(<<~'RUBY')
      # A splat in the middle of a call keeps the trailing positional args, and
      # forwarding *args/**kw does not drop the keyword arguments.
      def g(a, b, c, d) = [a, b, c, d]
      def mid(m) = g(1, *m, 4)
      p mid([2, 3])
      def g5(a, b, c, d, e) = [a, b, c, d, e]
      def mid5(m) = g5(1, *m, 5)
      p mid5([2, 3, 4])
      def gk(a, b, c: 0) = [a, b, c]
      def fwd(*args, **kw) = gk(*args, **kw)
      p fwd(1, 2, c: 3)
      p fwd(1, 2)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [1, 2, 3, 4, 5]
      [1, 2, 3]
      [1, 2, 0]
    OUT
  end

  it "unbind bind a class method" do
    result = ze0(<<~'RUBY')
      # `UnboundMethod#bind` asks whether the argument is an instance of the method's
      # OWNER, and a class method's owner is `#<Class:Foo>` -- so the argument must be
      # a class in Foo's ancestry, not an instance of Foo. CRuby words that refusal
      # differently too, because it reaches the test through a singleton `methclass`.

      class Foo
        def self.a = 1
        def b = 2
      end
      class Sub < Foo; end
      class Other; end

      um = Foo.method(:a).unbind
      p um.owner
      p um.bind(Foo).call

      # A subclass IS an instance of `#<Class:Foo>`, so it binds and answers.
      p um.bind(Sub).call

      # Everything else is refused with the singleton wording -- an unrelated class,
      # an instance of the owner, and an immediate all take the same message.
      [Other, Foo.new, 3].each do |bad|
        begin
          um.bind(bad)
        rescue TypeError => e
          puts e.message
        end
      end

      # `bind_call` runs the same check.
      p um.bind_call(Sub)
      begin
        um.bind_call(Other)
      rescue TypeError => e
        puts e.message
      end

      # Reaching the same method through the singleton class gives an INSTANCE-kind
      # unbound method, and it binds the same way.
      sm = Foo.singleton_class.instance_method(:a)
      p sm.owner
      p sm.bind(Foo).call

      # The instance case is unaffected, which is what makes this the singleton branch
      # rather than `bind` as a whole.
      p Foo.instance_method(:b).bind(Foo.new).call
      p Foo.instance_method(:b).bind(Sub.new).call

      # ...and a genuinely wrong argument must still be refused, with the wording the
      # non-singleton owner gets.
      begin
        Foo.instance_method(:b).bind(Object.new)
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<Class:Foo>
      1
      1
      singleton method called for a different object
      singleton method called for a different object
      singleton method called for a different object
      1
      singleton method called for a different object
      #<Class:Foo>
      1
      2
      2
      bind argument must be an instance of Foo
    OUT
  end

  it "unknown and missing keywords collect all names with no method suffix" do
    result = ze0(<<~'RUBY')
      # CRuby reports every offending keyword (singular/plural) with no
      # `(in 'method')` suffix, for both direct calls and **hash forwarding.

      def take(a:); a; end
      def two(a:, b:); [a, b]; end
      def rest(a:, **opts); [a, opts]; end
      def try
        yield
      rescue ArgumentError => e
        puts e.message
      end
      try { take(**{a: 1, b: 2}) }
      try { two(**{a: 1, b: 2, c: 3, d: 4}) }
      try { two(**{a: 1}) }
      p rest(a: 1, x: 9, y: 8)
    RUBY

    _(result).must_answer <<~'OUT'
      unknown keyword: :b
      unknown keywords: :c, :d
      missing keyword: :b
      [1, {x: 9, y: 8}]
    OUT
  end
end
