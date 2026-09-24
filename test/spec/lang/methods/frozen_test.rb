# frozen_string_literal: true

require "spec_helper"

describe "Methods: frozen literals" do
  it "class method barrier follows the visibility timeline" do
    result = zr(<<~'RUBY')
      class C
        def self.helper(x) = x + 1
      end

      module M
        def bonus(x) = x + 100
      end

      # ONE call site, asked again after every change -- the site remembers its
      # barrier verdict, so each answer has to be the one ruby gives at that moment.
      def ask(n)
        C.helper(n)
      rescue NoMethodError => e
        e.message
      end

      def ask_bonus(n)
        C.bonus(n)
      rescue NoMethodError => e
        e.message
      end

      # A name Class supplies and C does not, so the barrier falls through.
      def ask_frozen
        C.frozen?
      rescue NoMethodError => e
        e.message
      end

      puts ask(1)
      puts ask_bonus(1)
      puts ask_frozen

      C.private_class_method(:helper)
      puts ask(2)

      C.public_class_method(:helper)
      puts ask(3)

      C.define_singleton_method(:helper) { |x| x * 10 }
      puts ask(4)

      C.extend(M)
      puts ask(5)
      puts ask_bonus(5)

      C.singleton_class.send(:private, :bonus)
      puts ask_bonus(6)

      C.singleton_class.send(:public, :bonus)
      puts ask_bonus(7)

      C.freeze
      puts ask_frozen
      puts ask(8)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      undefined method 'bonus' for class C
      false
      private method 'helper' called for class C
      4
      40
      50
      105
      private method 'bonus' called for class C
      107
      true
      80
    OUT
  end

  it "a class method reopened across class bodies answers each body's own version" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== a reopen across class bodies"
      class C
        def self.t = "t1"
      end
      p C.t
      class C
        def self.t = "t2"
      end
      p C.t

    RUBY

    _(result).must_answer <<~'OUT'
      == a reopen across class bodies
      "t1"
      "t2"
    OUT
  end

  it "module_function reaches the same timeline" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== module_function reaches it the same way"
      module F
        module_function
        def g = "g1"
      end
      p F.g
      module F
        module_function
        def g = "g2"
      end
      p F.g

    RUBY

    _(result).must_answer <<~'OUT'
      == module_function reaches it the same way
      "g1"
      "g2"
    OUT
  end

  it "three bodies each answer in their own window" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== three bodies, and every window sees its own"
      class Three
        def self.v = 1
      end
      a = Three.v
      class Three
        def self.v = 2
      end
      b = Three.v
      class Three
        def self.v = 3
      end
      p [a, b, Three.v]

    RUBY

    _(result).must_answer <<~'OUT'
      == three bodies, and every window sees its own
      [1, 2, 3]
    OUT
  end

  it "two definitions in one body with a statement between them each hold their window" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== two definitions in ONE body with a statement between"
      class Between
        def self.w = "first"
        SEEN = w
        def self.w = "second"
      end
      p [Between::SEEN, Between.w]

    RUBY

    _(result).must_answer <<~'OUT'
      == two definitions in ONE body with a statement between
      ["first", "second"]
    OUT
  end

  it "the class-method and instance-method channels do not interfere" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== the two channels do not interfere"
      class Both
        def self.n = "cls1"
        def n = "inst1"
      end
      p [Both.n, Both.new.n]
      class Both
        def self.n = "cls2"
        def n = "inst2"
      end
      p [Both.n, Both.new.n]

    RUBY

    _(result).must_answer <<~'OUT'
      == the two channels do not interfere
      ["cls1", "inst1"]
      ["cls2", "inst2"]
    OUT
  end

  it "a redefined class method keeps its arguments, its block and its defaults" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== a redefined class method keeps its arguments, block and keywords"
      class Args
        def self.k(a, b = 2, *rest, c:, d: 4, &blk) = "1:#{a},#{b},#{rest},#{c},#{d},#{blk&.call}"
      end
      p Args.k(1, c: 3) { "blk" }
      class Args
        def self.k(a, b = 2, *rest, c:, d: 4, &blk) = "2:#{a},#{b},#{rest},#{c},#{d},#{blk&.call}"
      end
      p Args.k(1, 9, 8, c: 3, d: 7) { "blk" }

    RUBY

    _(result).must_answer <<~'OUT'
      == a redefined class method keeps its arguments, block and keywords
      "1:1,2,[],3,4,blk"
      "2:1,9,[8],3,7,blk"
    OUT
  end

  it "self is the class in every body, so class-level ivars carry across them" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== self is the CLASS in every body: class-level ivars and cvars"
      class SelfIsClass
        @tag = "ivar"
        @@shared = "cvar"
        def self.s = "1:#{@tag}/#{@@shared}"
      end
      p SelfIsClass.s
      class SelfIsClass
        def self.s = "2:#{@tag}/#{@@shared}"
      end
      p SelfIsClass.s

    RUBY

    _(result).must_answer <<~'OUT'
      == self is the CLASS in every body: class-level ivars and cvars
      "1:ivar/cvar"
      "2:ivar/cvar"
    OUT
  end

  it "super from a redefined class method reaches the parent's" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== super from a redefined class method"
      class SuperBase
        def self.s = "base"
      end
      class SuperSub < SuperBase
        def self.s = "1(#{super})"
      end
      p SuperSub.s
      class SuperSub
        def self.s = "2(#{super})"
      end
      p SuperSub.s

    RUBY

    _(result).must_answer <<~'OUT'
      == super from a redefined class method
      "1(base)"
      "2(base)"
    OUT
  end

  it "a subclass sees the timeline of the parent's class method" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== a subclass sees the timeline of the parent's class method"
      class PBase
        def self.p1 = "p1"
      end
      class PSub < PBase; end
      before = PSub.p1
      class PBase
        def self.p1 = "p2"
      end
      p [before, PSub.p1]

    RUBY

    _(result).must_answer <<~'OUT'
      == a subclass sees the timeline of the parent's class method
      ["p1", "p2"]
    OUT
  end

  it "a module's own def self.x follows the same timeline" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== a module's own def self.x"
      module ModSelf
        def self.m = "m1"
      end
      p ModSelf.m
      module ModSelf
        def self.m = "m2"
      end
      p ModSelf.m

    RUBY

    _(result).must_answer <<~'OUT'
      == a module's own def self.x
      "m1"
      "m2"
    OUT
  end

  it "reflection names the owner, and the last body's report is the one that stands" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== reflection names the owner, and the last body's report"
      # `#arity`/`#parameters` in the WINDOW report the FINAL body on both channels
      # -- the meta rows are static and the timeline lives in the overlay. See
      # `tests/gaps/a_redefinition_window_reports_the_last_body.rb`.
      class Reflect
        def self.r = "r1"
      end
      p [Reflect.method(:r).owner.to_s, Reflect.r]
      class Reflect
        def self.r(x) = "r2#{x}"
      end
      p [Reflect.method(:r).owner.to_s, Reflect.method(:r).arity, Reflect.r("!")]

    RUBY

    _(result).must_answer <<~'OUT'
      == reflection names the owner, and the last body's report
      ["#<Class:Reflect>", "r1"]
      ["#<Class:Reflect>", 1, "r2!"]
    OUT
  end

  it "singleton_method_added reports each definition where it is written" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== singleton_method_added reports each definition where it stands"
      class Hooked
        def self.singleton_method_added(n)
          (@seen ||= []) << n unless n == :singleton_method_added
          super
        end
        def self.a = "a1"
      end
      p Hooked.instance_variable_get(:@seen)
      class Hooked
        def self.a = "a2"
      end
      p [Hooked.instance_variable_get(:@seen), Hooked.a]

    RUBY

    _(result).must_answer <<~'OUT'
      == singleton_method_added reports each definition where it stands
      [:a]
      [[:a, :a], "a2"]
    OUT
  end

  it "a redefinition clears the private mark, as ruby does" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` WHERE IT STANDS, so a call written between two
      # same-name definitions answers the FIRST body. zr's static tables carry only
      # the last-def-wins winner, so `analyze::redefs` puts the timeline in the
      # runtime overlay instead: the first body installs at boot, and each later one
      # re-installs at its own document position.
      #
      # The instance channel had that; the class-method channel did not -- `redefs`
      # skipped `is_class_method` outright, so `C.t` answered the reopened body from
      # the program's first line. The two channels are separate maps and separate
      # hooks, which is what this file sweeps.
      #
      # No call-site change was needed: a class-method send is already dynamic (it
      # has an explicit receiver), and the overlay outranks the frozen row. What was
      # missing was the install.

      puts "== a redefinition clears the private mark, as ruby does"
      # Only the SECOND half is asserted here: a `private_class_method` mark made
      # BEFORE the reopen is not enforced inside the window -- the same on both
      # channels, and the same gap file as the arity above.
      class Vis
        def self.v = "v1"
        private_class_method :v
      end
      class Vis
        def self.v = "v2"
      end
      p Vis.v
    RUBY

    _(result).must_answer <<~'OUT'
      == a redefinition clears the private mark, as ruby does
      "v2"
    OUT
  end

  it "defined calls" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `defined?(f(a))` answers "method" only when the call resolves AND
      # every argument is itself defined, so one undefined argument makes the
      # whole answer nil.

      p defined?(puts(1))
      x = 5
      p defined?(puts(x))
      p defined?(puts(Missing))
      p defined?([1, 2].map(Missing))
      p defined?(nothing_here(1))
      p defined?(puts(@never_set))

      # `defined?(super)` asks whether the walk above this method finds one.
      class Base
        def f = 1
      end

      class Sub < Base
        def f = defined?(super)
        def g = defined?(super)
      end

      p Sub.new.f
      p Sub.new.g

      # Outside a method, and in a method Object itself holds, there is no
      # super to find.
      def top = defined?(super)
      p top
      p defined?(super)

      # `{ x: }` and `f(a:)` write the value as the name alone.
      value = 7
      p({ value: })
      def kw(a:, b: 2) = [a, b]
      a = 9
      p kw(a:)

      # A `&b` parameter is the block channel, and a body the runtime
      # installs binds it the same way a `def` does.
      class Runtime
        define_method(:named) do |n, &blk|
          [n, blk&.call]
        end
      end
      p Runtime.new.named(1) { :given }
      p Runtime.new.named(2)
      p proc { |&b| b&.call }.call { :inner }
    RUBY

    _(result).must_answer <<~'OUT'
      "method"
      "method"
      nil
      nil
      nil
      nil
      "super"
      nil
      nil
      nil
      {value: 7}
      [9, 2]
      [1, :given]
      [2, nil]
      :inner
    OUT
  end

  it "destructuring parameters" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A `(a, b)` parameter takes ONE slot like any other, and the names
      # inside it are written from that slot afterwards, by ruby's own
      # destructure -- the same split a multiple assignment uses. ruby reports
      # such a parameter with no name at all.

      p [[1, 2], [3, 4]].map { |(a, b)| a + b }
      p({ a: 1, b: 2 }.each_with_index.map { |(k, v), i| [k, v, i] })
      p proc { |(a, (b, c))| [a, b, c] }.call([1, [2, 3]])
      p proc { |(a, *r)| [a, r] }.call([1, 2, 3])
      p proc { |(a, *)| a }.call([1, 2, 3])
      p proc { |(a, b), (c, d)| [a, b, c, d] }.call([1, 2], [3, 4])

      p lambda { |(k, v), i| [k, v, i] }.parameters
      p proc { |(k, v), i| }.parameters

      def pair((a, b), c) = [a, b, c]
      p pair([1, 2], 3)
      p method(:pair).parameters
      p method(:pair).arity

      # A value that is not an Array goes through ruby's `to_ary` rule, and one
      # that answers none binds the whole value to the first name.
      p proc { |(a, b)| [a, b] }.call(7)

      class Pairy
        def to_ary = [:x, :y]
      end
      p proc { |(a, b)| [a, b] }.call(Pairy.new)
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 7]
      [[:a, 1, 0], [:b, 2, 1]]
      [1, 2, 3]
      [1, [2, 3]]
      1
      [1, 2, 3, 4]
      [[:req], [:req, :i]]
      [[:opt], [:opt, :i]]
      [1, 2, 3]
      [[:req], [:req, :c]]
      2
      [7, nil]
      [:x, :y]
    OUT
  end

  it "later def self reaches back" do
    result = zr(<<~'RUBY')
      # A later `def self.x` installs at its OWN line: a call written above the
      # reopen answers the earlier body, as ruby's install-where-it-stands rule
      # requires. `module_function` reaches it the same way -- its class-method copy
      # is an ordinary `def self.x` by the time analyze is done.
      #
      # `analyze::redefs` skipped `is_class_method` in both of its history scans, so
      # a `(class, name)` pair on the singleton channel was never even a candidate.
      # It counts the two channels APART now -- `def x` and `def self.x` are
      # different methods, and only same-channel bodies supersede one another -- and
      # each candidate carries which channel it is on, through the boot row, the
      # spliced install and the emitted body (whose `self` is the CLASS).
      #
      # NO call-site change was needed, which is what made this smaller than it
      # looked: a class-method send already has an explicit receiver and is already
      # dynamic, and the overlay outranks the frozen row. What was missing was the
      # install -- `runtime_replace_class_method_c`, whose overlay map holds an
      # `RProc` where a compiled trampoline is a `ValueFn`, so the fn is wrapped as
      # the value-receiver proc every class-method row there already is.
      #
      # One ordering fix rode with it: materialization copies an inherited
      # `def self.x` onto every descendant, so a SUBCLASS answered the flattened
      # copy of the final body and lost the parent's timeline entirely. The
      # ancestors' overlay is probed before that flat table now, stopping at the
      # first ancestor that really defines the name.
      #
      # The wider sweep is `tests/class_method_redefinition_timeline.rb`; what the
      # window still misreports is `tests/gaps/a_redefinition_window_reports_the_last_body.rb`.

      class C
        def self.t = "t1"
      end
      p C.t
      class C
        def self.t = "t2"
      end
      p C.t

      module F
        module_function
        def g = "g1"
      end
      p F.g
      module F
        module_function
        def g = "g2"
      end
      p F.g
    RUBY

    _(result).must_answer <<~'OUT'
      "t1"
      "t2"
      "g1"
      "g2"
    OUT
  end

  it "method introspection" do
    result = zr(<<~'RUBY')
      # Test __method__, freeze/frozen?

      # __method__
      def greet
        puts __method__  # greet
      end
      greet

      def calculate
        puts __method__  # calculate
      end
      calculate

      # freeze / frozen? (AOT treats everything as frozen)
      s = "hello"
      s.freeze
      puts s           # hello
      puts s.frozen?   # true

      # Integer#freeze (no-op)
      n = 42
      puts n.frozen?   # true

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      greet
      calculate
      hello
      true
      true
      done
    OUT
  end

  it "splat arguments" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A `*` splat at a call site makes the argument count unknown at compile
      # time, so the send hands the runtime ONE Array rather than a slot array
      # and the runtime spreads it. `...` forwards the three channels the
      # parameter took: the positional rest, the keywords and the block.

      def report(*a, **k, &b) = [a, k, b.nil? ? nil : b.call]

      list = [1, 2, 3]
      p report(*list)
      p report(*list, 9)
      p report(0, *list)
      p report(*list, x: 1)
      p report(*list, **{ y: 2 })
      p report(*[]) { :blocked }

      p [1, 2].push(*list)
      p "%s-%s" % ["a", "b"]
      p [0, *list, 4]

      def forward(...) = report(...)

      p forward(1, 2, x: 3)
      p forward(1) { :blocked }
      p forward
      p method(:forward).parameters
      p method(:forward).arity

      # A splat-expanded Hash is POSITIONAL again, not a keyword channel.
      def positional(a) = a
      p positional(*[{ z: 1 }])

      # The splat runs ruby's `to_a` rule, so anything that answers one spreads.
      p report(*(1..3))
      p report(*nil)
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2, 3], {}, nil]
      [[1, 2, 3, 9], {}, nil]
      [[0, 1, 2, 3], {}, nil]
      [[1, 2, 3], {x: 1}, nil]
      [[1, 2, 3], {y: 2}, nil]
      [[], {}, :blocked]
      [1, 2, 1, 2, 3]
      "a-b"
      [0, 1, 2, 3, 4]
      [[1, 2], {x: 3}, nil]
      [[1], {}, :blocked]
      [[], {}, nil]
      [[:rest, :*], [:keyrest, :**], [:block, :&]]
      -1
      {z: 1}
      [[1, 2, 3], {}, nil]
      [[], {}, nil]
    OUT
  end

  it "tail forms" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # Three forms that need no machinery of their own.
      #
      # `when *list` spreads its value the way a call site's splat does and tests
      # the elements one at a time -- how MANY there are is a run-time number, so
      # the arm is a loop where a written-out `when` is a chain.
      #
      # `def self.x` at the top level names `main`, which is one object and not a
      # class, so the method lands on its singleton exactly as `def obj.x` does.
      #
      # A `super` in a scope with no `def` of its own may still BE a method at run
      # time, and only the run time can tell.

      SMALL = [1, 2, 3]
      ROUND = [10, 20]

      def kind(x)
        case x
        when *SMALL then :small
        when *ROUND then :round
        when 99 then :ninety_nine
        when *[] then :never
        else :other
        end
      end
      p [1, 3, 10, 20, 99, 7].map { |x| kind(x) }

      # The elements are tested with `===`, so a class matches an instance.
      case "abc"
      when *[Integer, String] then puts "matched by class"
      end

      # `def self.x` at the top level.
      def self.only_main = :from_main
      p only_main
      p self.only_main
      p singleton_methods.sort
      begin
        Object.new.only_main
      rescue NoMethodError => e
        puts "NoMethodError: #{e.name}"
      end

      # A `super` in a top-level `def` walks above Object and finds nothing.
      def no_parent
        super
      rescue NoMethodError => e
        e.message
      end
      p no_parent

      # A block that BECOMES a method at run time: an explicit-argument `super`
      # reaches the target, and a bare one is ruby's own refusal.
      class Base
        def who(*a) = "base#{a.inspect}"
      end

      explicit = Class.new(Base) { define_method(:who) { |*a| "dyn(" + super(*a) + ")" } }
      p explicit.new.who(9)
      p Class.new(Base) { define_method(:m) { defined?(super) ? "has" : "none" } }.new.m
      p Class.new { define_method(:m) { defined?(super) ? "has" : "none" } }.new.m

      bare = Class.new(Base) { define_method(:who) { super } }
      begin
        bare.new.who
      rescue RuntimeError => e
        puts "RuntimeError: #{e.message[0, 40]}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:small, :small, :round, :round, :ninety_nine, :other]
      matched by class
      :from_main
      :from_main
      [:inspect, :only_main, :to_s]
      NoMethodError: only_main
      "super: no superclass method 'no_parent' for main"
      "dyn(base[9])"
      "none"
      "none"
      RuntimeError: implicit argument passing of super from 
    OUT
  end

  it "tail forms two" do
    result = zr(<<~'RUBY', path: "zr/tail_forms_two.rb")
      # frozen_string_literal: true

      # More forms that needed no machinery of their own.

      # `a..b` written where a condition goes is ruby's flip-flop: a latch that
      # turns ON where `a` is true and OFF where `b` is, answering true for every
      # test in between. The state outlives the statement, so it lives in the
      # runtime's own table and each site owns one.
      inclusive = []
      (1..8).each { |i| inclusive << i if (i == 3)..(i == 5) }
      p inclusive

      # The two ends can be the same test: `..` asks the right operand at once, so
      # it ends where it started; `...` waits for the next test.
      one = []
      many = []
      (1..6).each do |i|
        one << i if (i == 3)..(i == 3)
        many << i if (i == 3)...(i == 3)
      end
      p one
      p many

      # Two sites keep separate latches, and one that never turns off runs on.
      a = []
      b = []
      (1..6).each do |i|
        a << i if (i == 2)..(i == 4)
        b << i if (i == 3)..(i == 99)
      end
      p a, b

      # A bare `k: v` tail is ONE Hash element inside an array literal: there is
      # no keyword channel to put it in.
      p [1, { b: 2 }, c: 3, d: 4]

      # `Outer::Inner = v` where the scope is a class this program declares hands
      # the runtime an owner id; a nested path, or a scope only the run time can
      # name, is read as a VALUE and the constant is set on it.
      module A
        module B
          LEVEL = 1
        end
      end
      A::B::LEVEL = 42
      p A::B::LEVEL

      module Registry; end
      def stock(m)
        m::LIST ||= []
        m::LIST << :entry
      end
      stock(Registry)
      stock(Registry)
      p Registry::LIST

      # `module_function :name` of a method an `include` supplied: which ancestor
      # carries it is the run time's own question.
      module Greet
        def hello(who) = "hi #{who}"
      end
      module Util
        include Greet
        module_function :hello
      end
      p Util.hello("x")
      p Util.private_instance_methods(false).include?(:hello)

      # An omitted end never fires: a beginless flip-flop never turns on and an
      # endless one never turns off.
      beginless = []
      endless = []
      (1..5).each do |i|
        beginless << i if ..(i == 3)
        endless << i if (i == 2)..
      end
      p beginless, endless

      # `h[*keys] = v`: how many index arguments there are is a run-time number,
      # so the setter takes one Array. The answer is still V.
      h = {}
      keys = [:k]
      p(h[*keys] = 9)
      p h

      # Names only the run time builds are the runtime's own visibility verb.
      HIDDEN = %i[one two]
      class Both
        def one = 1
        def two = 2
        def three = 3
        private(*HIDDEN)
      end
      p Both.private_instance_methods(false).sort
      p Both.public_instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      [3, 4, 5]
      [3]
      [3, 4, 5, 6]
      [2, 3, 4]
      [3, 4, 5, 6]
      [1, {b: 2}, {c: 3, d: 4}]
      42
      [:entry, :entry]
      "hi x"
      true
      []
      [2, 3, 4, 5]
      9
      {k: 9}
      [:one, :two]
      [:three]
    OUT
      zr/tail_forms_two.rb:45: warning: already initialized constant A::B::LEVEL
      zr/tail_forms_two.rb:42: warning: previous definition of LEVEL was here
    ERR
  end
end
