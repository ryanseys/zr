# frozen_string_literal: true

require "spec_helper"

describe "Constants: slicing" do
  it "bare call prefers self over toplevel" do
    result = zr(<<~'RUBY')
      # A receiverless call is a call on self, so self's own methods come first: the
      # enclosing class's singleton chain inside a class method, its instance chain
      # inside an instance method. A top-level def is a private method on Object and
      # so sits at the bottom of every ancestry. Argument types were bound to the
      # top-level method instead whenever one shared the name, which left the real
      # callee's parameters to be typed by its own body -- and where the two
      # disagreed on a container's shape the C build stopped. Renaming the top-level
      # method, or writing the receiver out, made it compile. (matz/spinel#4106)
      module Blocks
        def self.read
          state = { "key" => nil }
          title(state)
        end
        def self.title(state) = state["key"] = "v"
      end
      def title(a) = "top:#{a.size}"
      p Blocks.read
      p title({ "k" => 1 })

      # The same shape one level down: an instance method calling a sibling that
      # shares its name with a top-level def.
      class Doc
        def run
          state = { "key" => nil }
          helper(state)
        end
        def helper(state) = state["key"] = "inst"
      end
      def helper(a) = "top:#{a.class}"
      p Doc.new.run
      p helper([])

      # The call really does reach self's method, not the top-level one.
      module Counter
        def self.bump = tally(1)
        def self.tally(x) = x + 100
      end
      def tally(x) = x - 100
      p Counter.bump
      p tally(1)

      # A top-level def is still what a bare call at top level finds, and what an
      # object without its own definition of the name falls back to.
      def only_at_top(v) = "only:#{v}"
      p only_at_top(3)
      class Plain
        def ask = only_at_top(4)
      end
      p Plain.new.ask
    RUBY

    _(result).must_answer <<~'OUT'
      "v"
      "top:1"
      "inst"
      "top:Array"
      101
      -99
      "only:3"
      "only:4"
    OUT
  end

  it "bare constant resolution walks the lexical chain innermost first" do
    result = zr(<<~'RUBY')
      X = "top"
      module Outer
        X = "outer"
        module Inner
          X = "inner"
          def self.probe
            X
          end
        end
        def self.probe
          X
        end
      end
      puts Outer::Inner.probe
      puts Outer.probe
      puts X
    RUBY

    _(result).must_answer <<~'OUT'
      inner
      outer
      top
    OUT
  end

  it "constant read answers from its cell" do
    result = zr(<<~'RUBY')
      # A constant read answers from its site's cell while the cref and the
      # constant stamp hold: a constant set, removed or reopened
      # after the first read is seen by the same site, and a site inside a
      # block or a define_method body reads under its own cref.
      A = 1
      def read_a = A
      p read_a, read_a
      Object.send(:remove_const, :A)
      A = 2
      p read_a
      module M
        X = :m
        def self.read = X
        Y = :y
      end
      p M.read, M::X, M::Y
      M.send(:remove_const, :X)
      M.const_set(:X, :again)
      p M.read, M::X
      class Base
        C = :base
        def c = C
      end
      class Kid < Base
        def kc = C
      end
      p Kid.new.c, Kid.new.kc
      class Kid
        C = :kid
      end
      p Kid.new.c, Kid.new.kc
      reader = proc { A }
      p reader.call
      Object.send(:remove_const, :A)
      A = 3
      p reader.call, read_a
      Object.const_set(:Later, 4)
      p (Later), Object.const_defined?(:Later)
      klass = Class.new do
        Z = :z
        define_method(:z) { Z }
      end
      p klass.new.z, Z
      i = 0
      total = 0
      while i < 100_000
        total += A
        i += 1
      end
      p total
      p (Missing rescue $!.class)


    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      2
      :m
      :m
      :y
      :again
      :again
      :base
      :base
      :base
      :kid
      2
      3
      3
      4
      true
      :z
      :z
      300000
      NameError
    OUT
  end

  it "reassigned constant warning" do
    result = zr(<<~'RUBY')
      # Assigning a constant that already has a value warns TWICE on stderr -- once
      # at the new assignment, once naming where the previous one was. zeo assigns
      # silently, so the one diagnostic that catches a constant clobbered by a
      # second file, or by a name a library did not expect to own, never appears.
      #
      # The location half is in place: `tests/const_source_location_of_a_module_constant.rb`
      # records where every constant was assigned, and the warning's second line is
      # exactly that record read back. What is missing is the check at the write --
      # `constants.rs`'s `const_set` has no "was it already there" test, and
      # `warning.rs` is the channel it would report through.
      #
      # CRuby is deliberate about which writes are quiet: a `remove_const` first
      # clears the record, and a `class`/`module` reopen creates nothing, so neither
      # warns. Only a genuine second assignment does.

      D = 1
      D = 2
      p D

      module M
        E = 1
        E = 2
      end

      F = 3
      Object.send(:remove_const, :F)
      F = 4

      class C; end
      class C; end

      G = 5
      Object.const_set(:G, 6)
    RUBY

    _(result).must_answer "2\n", stderr: <<~'ERR'
      lang/constants/slicing_test.rb:17: warning: already initialized constant D
      lang/constants/slicing_test.rb:16: warning: previous definition of D was here
      lang/constants/slicing_test.rb:22: warning: already initialized constant M::E
      lang/constants/slicing_test.rb:21: warning: previous definition of E was here
      lang/constants/slicing_test.rb:33: warning: already initialized constant G
      lang/constants/slicing_test.rb:32: warning: previous definition of G was here
    ERR
  end

  it "scoped names" do
    result = zr(<<~'RUBY')
      # A `class` or `module` may name the scope it goes in. The name is the
      # path, and the class is the SAME one a nested body would have declared.
      module Outer
        X = :outer_x

        class Base
          def kind = :base
        end

        module Mixin
          def mixed = :mixed
        end
      end

      # A qualified name opens ONE cref frame: the body searches `Outer::Inner`
      # and then whatever encloses the statement, never `Outer`. So `Y` is
      # found here and `X` is not, though a body written inside `module Outer`
      # would have found both.
      class Outer::Inner < Outer::Base
        include Outer::Mixin

        Y = :inner_y

        def kind = [super, Y, mixed]

        def reach = [defined?(Y), defined?(X)]
      end

      module Outer::Side
        Z = :side_z

        def self.z = Z
      end

      # The scope may be deeper than one name, and the path may be reopened.
      class Outer::Inner
        def second = :again
      end

      class Outer::Inner::Deep
        def where = :deep
      end

      p Outer::Inner.name
      p Outer::Inner.superclass
      p Outer::Inner.ancestors.take(4)
      p Outer::Inner.new.kind
      p Outer::Inner.new.reach
      p Outer::Inner.new.second
      p Outer::Inner::Deep.new.where
      p Outer::Inner::Deep.name
      p Outer::Side.z
      p Outer::Side.name
      begin
        Outer::Inner.new.instance_eval { X }
      rescue NameError => e
        p e.class
      end

      # A nested body still nests: `Nested` inside `module Outer` sees `X`.
      module Outer
        class Nested
          def reach = [defined?(X), defined?(Y)]
        end
      end

      p Outer::Nested.new.reach
      p Outer::Nested.name

      # Sorted: a class row is registered before the first statement runs, so
      # the ORDER `constants` answers in is zr's registration order and not
      # ruby's assignment order.
      p Outer.constants.sort
      p Outer::Inner.constants.sort
    RUBY

    _(result).must_answer <<~'OUT'
      "Outer::Inner"
      Outer::Base
      [Outer::Inner, Outer::Mixin, Outer::Base, Object]
      [:base, :inner_y, :mixed]
      ["constant", nil]
      :again
      :deep
      "Outer::Inner::Deep"
      :side_z
      "Outer::Side"
      NameError
      ["constant", nil]
      "Outer::Nested"
      [:Base, :Inner, :Mixin, :Nested, :Side, :X]
      [:Deep, :Y]
    OUT
  end

  it "self call beats toplevel def" do
    result = zr(<<~'RUBY')
      # A receiverless call resolves against the enclosing definition's self. A
      # top-level `def` is a private method on Object, so it sits at the BOTTOM of
      # every ancestry -- last, not first.
      #
      # Several analysis passes asked for the free functions first, so a same-named
      # top-level def took the call. The one that mattered was narrow_object_arrays:
      # with the call attributed to the wrong scope, the real callee's parameter was
      # never joined to the caller's slot, and the two were narrowed apart -- an
      # sp_PolyArray argument passed to an sp_PtrArray parameter, and the C build
      # stopped (#4130; #4106 was the same rule at the parameter-binding site).
      #
      # The top-level methods below are never called and never passed anywhere.
      Scenario = Struct.new(:key)

      module Blocks
        def self.run
          scenarios = []
          heading(scenarios, "a")
          heading(scenarios, "b")
          scenarios
        end

        def self.heading(scenarios, said)
          scenarios.push(Scenario.new(said))
        end
      end

      def heading(a) = "top-level #{a}"

      p Blocks.run.length
      p Blocks.run.map { |s| s.key }

      # The same collision on the INSTANCE side, where the enclosing self is an
      # object rather than a module.
      class Sheet
        def fill
          rows = []
          row(rows, "a")
          row(rows, "b")
          rows
        end

        def row(rows, said)
          rows.push(Scenario.new(said))
        end
      end

      def row(x) = "top-level row"

      p Sheet.new.fill.length
      p Sheet.new.fill.map { |s| s.key }

      # And the top-level method still answers when it is the one actually named.
      p heading("x")
      p row(1)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      ["a", "b"]
      2
      ["a", "b"]
      "top-level x"
      "top-level row"
    OUT
  end

  it "shareable constant" do
    result = zr(<<~'RUBY')
      # shareable_constant_value: literal
      # ShareableConstantNode — the `# shareable_constant_value:` magic comment.
      #
      # CRuby uses this to mark constants for Ractor-shareable initialization.
      # Spinel has no Ractor runtime, so the shareability state is a no-op
      # and the wrapped constant write executes normally.

      FOO = [1, 2, 3]
      puts FOO.length
      puts FOO.first
    RUBY

    _(result).must_answer "3\n1\n"
  end

  it "top level def last def wins" do
    result = zr(<<~'RUBY')
      def v
        1
      end
      def v
        2
      end
      puts v
    RUBY

    _(result).must_answer "2\n"
  end

  it "top level defs" do
    result = zr(<<~'RUBY')
      # A top-level `def` is a PRIVATE instance method of Object -- so it is
      # callable by implicit self from anywhere (top level, any method body, any
      # class body), invisible to `respond_to?`, and reachable through `send`.

      def greet(name)
        "Hello, #{name}!"
      end

      puts greet("Ada")

      # Callable from inside a class's instance method...
      class Speaker
        def speak
          greet("from-instance")
        end
      end
      puts Speaker.new.speak

      # ...from a class METHOD...
      class Factory
        def self.build
          greet("from-class-method")
        end
      end
      puts Factory.build

      # ...from a class BODY...
      class AtBody
        RESULT = greet("from-class-body")
      end
      puts AtBody::RESULT

      # ...and from another top-level def.
      def outer
        greet("from-another-def")
      end
      puts outer

      # It is PRIVATE on Object: invisible to respond_to?, reachable via send.
      p self.respond_to?(:greet)
      p self.respond_to?(:greet, true)
      p send(:greet, "via-send")
      p Speaker.new.respond_to?(:greet)
      p Speaker.new.send(:greet, "on-an-instance")

      # Calling it with an explicit receiver is a NoMethodError (it's private).
      begin
        Speaker.new.greet("explicit")
      rescue NoMethodError => e
        puts "NoMethodError caught"
      end

      # Full parameter support: optional, rest, post, keywords, block.
      def every_kind(a, b = 2, *rest, c, d:, e: 5, **kw, &blk)
        parts = [a, b, rest, c, d, e, kw]
        parts << blk.call if blk
        parts
      end
      p every_kind(1, :post, d: 4)
      p every_kind(1, 9, :r1, :r2, :post, d: 4, e: 50, x: 1)
      p(every_kind(1, :post, d: 4) { "block!" })

      # Endless top-level defs.
      def square(x) = x * x
      p square(7)

      def zero = 0
      p zero

      # A top-level def can yield.
      def each_pair
        yield 1, 2
        yield 3, 4
      end
      each_pair { |a, b| p [a, b] }

      # Recursion works.
      def fact(n)
        n <= 1 ? 1 : n * fact(n - 1)
      end
      p fact(6)

      # Mutual recursion between two top-level defs.
      def even?(n) = n.zero? ? true : odd?(n - 1)
      def odd?(n) = n.zero? ? false : even?(n - 1)
      p [even?(10), odd?(7)]

      # A later def REPLACES an earlier one of the same name.
      def replaced = "first"
      def replaced = "second"
      p replaced

      # `__method__` reports the running method's name.
      def whoami = __method__
      p whoami

      # A top-level def is reachable as a Method object.
      m = method(:square)
      p m.call(9)
      p m.name

      # And usable as a block via &.
      p [1, 2, 3].map(&method(:square))

      # Top-level defs see top-level constants.
      LIMIT = 10
      def under_limit?(n) = n < LIMIT
      p under_limit?(3)
      p under_limit?(30)
    RUBY

    _(result).must_answer <<~'OUT'
      Hello, Ada!
      Hello, from-instance!
      Hello, from-class-method!
      Hello, from-class-body!
      Hello, from-another-def!
      false
      true
      "Hello, via-send!"
      false
      "Hello, on-an-instance!"
      NoMethodError caught
      [1, 2, [], :post, 4, 5, {}]
      [1, 9, [:r1, :r2], :post, 4, 50, {x: 1}]
      [1, 2, [], :post, 4, 5, {}, "block!"]
      49
      0
      [1, 2]
      [3, 4]
      720
      [true, true]
      "second"
      :whoami
      81
      :square
      [1, 4, 9]
      true
      false
    OUT
  end

  it "top level scoped constants" do
    result = zr(<<~'RUBY')
      # A `::Name` top-level anchor resolves to the builtin (or top-level) class in
      # every position -- CRuby represents top-level constants as living on Object,
      # so `::Integer` is `Object::Integer` is the `Integer` class.

      # As an is_a?/kind_of?/instance_of? argument.
      p 5.is_a?(::Integer)
      p "x".is_a?(::String)
      p [1].is_a?(::Array)
      p 3.14.kind_of?(::Numeric)
      p nil.is_a?(::NilClass)
      p 5.is_a?(::Comparable)
      p 5.instance_of?(::Integer)

      # As a `===` receiver (case/when membership).
      p(::Integer === 7)
      p(::Integer === "x")
      p(::Float === 1.5)
      p(::Symbol === :s)

      # As a first-class Class value.
      p ::Integer
      p ::String.name
      p ::Array.new(3, :x)

      # A user top-level class works the same.
      class Widget; end
      p Widget.new.is_a?(::Widget)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      true
      false
      true
      true
      Integer
      "String"
      [:x, :x, :x]
      true
    OUT
  end
end
