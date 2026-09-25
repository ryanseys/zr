# frozen_string_literal: true

require "spec_helper"

describe "Guards: frozen literals" do
  it "freeze returns self keeping the static collection type" do
    result = zr(<<~'RUBY')
      # `.freeze` returns self, so `names` stays a static Array and
      # `names[0]` / `names.length` still work. The example uses a local, not
      # the `NAMES = [...].freeze` constant idiom, because a constant read
      # always takes the generic path.

      names = ["a", "b"].freeze
      puts names[0]
      puts names.length
      puts names.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      a
      2
      true
    OUT
  end

  it "frozen and arg validation guards" do
    result = zr(<<~'RUBY')
      # Frozen mutators (String insert/prepend/slice!, Hash []=/merge!/clear) and
      # arg validation (Integer base, Set enumerable, Random#bytes, Float#divmod
      # NaN) raise the CRuby exception class rather than silently mutating.

      require "set"
      p("s".freeze.instance_of?(String)) # keep require used, warm path
      p(("abc".freeze.insert(0, "x") rescue $!.class))
      p(("abc".freeze.slice!(0) rescue $!.class))
      p(({a: 1}.freeze.merge!({b: 2}) rescue $!.class))
      p(({a: 1}.freeze.clear rescue $!.class))
      h = {x: 5}.freeze
      p((begin; h[:x] += 1; rescue => e; e.class; end))
      p((Integer(5, 16) rescue $!.class))
      p((Set.new(5) rescue $!.class))
      p(((Set[1, 2] & 5) rescue $!.class))
      p((Random.new(1).bytes(-1) rescue $!.class))
      p((1.0.divmod(0.0 / 0.0) rescue $!.class))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      FrozenError
      FrozenError
      FrozenError
      FrozenError
      FrozenError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      FloatDomainError
    OUT
  end

  it "frozen class and object mutation guards raise cruby frozen errors" do
    result = zr(<<~'RUBY')
      # The frozen-class guard family: civar/cvar writes (static paths and
      # reflection), runtime define_method / define_singleton_method, plus
      # frozen-object ivar/singleton/extend guards and the frozen-builtin
      # instance_variable_set raises. The cvar guard is on the storage OWNER
      # (`Sub.freeze` doesn't stop a write to Base's `@@z`). Expected output
      # is verbatim ruby 4.0.7 (addresses normalized in-script).

      class Foo
        def self.setiv; @x = 1; end
        def self.setcv; @@y += 1; end
        def bump; @@y = 9; end
        @@y = 0
      end
      module Bar; end
      puts Foo.frozen?
      Foo.freeze
      puts Foo.frozen?
      Bar.freeze
      puts Bar.frozen?
      def try
        yield
      rescue => e
        puts "#{e.class}: #{e.message.sub(/0x[0-9a-f]+/, "0xADDR")}"
      end
      try { Foo.instance_variable_set(:@a, 1) }
      try { Foo.class_variable_set(:@@b, 1) }
      try { Foo.setiv }
      try { Foo.setcv }
      try { Foo.new.bump }
      name = :c
      try { Foo.define_singleton_method(name) { 1 } }
      try { Foo.send(:define_method, :m2) { 1 } }
      class Base
        @@z = 1
        def self.setz; @@z = 5; end
        def self.z; @@z; end
      end
      class Sub < Base; end
      Sub.freeze
      Sub.setz
      puts Base.z
      o = Object.new.freeze
      try { o.instance_variable_set(:@v, 1) }
      try { o.define_singleton_method(name) { 2 } }
      try { o.extend(Comparable) }
      s = "st".freeze
      try { s.instance_variable_set(:@v, 1) }
      try { 5.instance_variable_set(:@v, 1) }
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      FrozenError: can't modify frozen Class: Foo
      FrozenError: can't modify frozen Class: Foo
      FrozenError: can't modify frozen Class: Foo
      FrozenError: can't modify frozen Class: Foo
      FrozenError: can't modify frozen Class: Foo
      FrozenError: can't modify frozen Class: Foo
      FrozenError: can't modify frozen Class: Foo
      5
      FrozenError: can't modify frozen Object: #<Object:0xADDR>
      FrozenError: can't modify frozen Object: #<Object:0xADDR>
      FrozenError: can't modify frozen Object: #<Object:0xADDR>
      FrozenError: can't modify frozen String: "st"
      FrozenError: can't modify frozen Integer: 5
    OUT
  end

  it "frozen hash opassign guard" do
    result = zr(<<~'RUBY')
      # A compound assignment (h[k] += v) to a frozen Hash raises FrozenError instead
      # of silently mutating; a non-frozen hash updates normally.
      def inc(h); h[:x] += 1; h[:x]; rescue FrozenError => e; e.class.name; end
      p inc({x: 5}.freeze)
      p inc({x: 5})
    RUBY

    _(result).must_answer <<~'OUT'
      "FrozenError"
      6
    OUT
  end

  it "frozen string append guard" do
    result = zr(<<~'RUBY')
      # <<, concat, and prepend on a frozen String raise FrozenError with the CRuby
      # message (including contents), whether the receiver is a chained .freeze or a
      # frozen local; a mutable string appends normally.
      def ap(s, x); s << x; end
      begin; ap("abc".freeze, "x"); rescue FrozenError => e; puts e.message; end
      begin; "hi".freeze.concat("!"); rescue FrozenError => e; puts e.message; end
      begin; "yo".freeze.prepend(">"); rescue FrozenError => e; puts e.message; end
      d = "abc".dup.freeze
      begin; d << "z"; rescue FrozenError => e; puts e.message; end
      m = "go"; m << "!"; puts m
    RUBY

    _(result).must_answer <<~'OUT'
      can't modify frozen String: "abc"
      can't modify frozen String: "hi"
      can't modify frozen String: "yo"
      can't modify frozen String: "abc"
      go!
    OUT
  end

  it "frozen string dedup intern and mutation guard" do
    result = zr(<<~'RUBY')
      p((-"hello").equal?(-"hello"))
      p("a".dedup.equal?("a".dedup))
      p(("he" + "llo").dedup.equal?("hello".dedup))
      a = "abc".freeze
      p((-a).equal?(a))
      p((-"x").equal?(-"y"))
      p((-"frozen").frozen?)
      nul = "a b"
      p nul.bytesize
      p("a b".dedup.equal?("a b".dedup))
      begin
        (-"immutable") << "!"
      rescue FrozenError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      false
      true
      3
      true
      can't modify frozen String: "immutable"
    OUT
  end

  it "guarded definitions" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A `class` written inside another statement is the class's whole body,
      # and whether the statement runs is a run-time fact. The row still
      # registers -- ids are the backend's and no class row can be minted
      # while the program runs -- but concealed, so the constant appears only
      # where the body actually runs.

      value = 1

      if value.positive?
        class Taken
          def go = :taken
        end
      end

      if value.negative?
        class Skipped
          def go = :skipped
        end
      end

      p Taken.new.go
      p defined?(Skipped)

      # A module reads the same way, and one nested in a guarded class body
      # waits for the body around it.
      unless value.zero?
        module Tools
          class Inner
            def go = :inner
          end
        end
      end
      p Tools::Inner.new.go

      # A `def` under a guard is installed where it stands, so the branch that
      # does not run writes no method.
      class Host
        def base = 1
        if [].any?
          def extra = 2
        end
        if [1].any?
          def added = 3
        end
      end
      p Host.new.base
      p Host.new.added
      p Host.new.respond_to?(:extra)
      p Host.instance_methods(false).sort

      # A `class` written in an EXPRESSION runs where the statement does, so
      # its row is declared like any other.
      LAST = (class Valued
        7
      end)

      p LAST, Valued.name

      made = module Named
        :named
      end

      p made, Named.name

      begin
        class InBegin
          def go = :in_begin
        end
      end

      p InBegin.new.go
    RUBY

    _(result).must_answer <<~'OUT'
      :taken
      nil
      :inner
      1
      3
      false
      [:added, :base]
      7
      "Valued"
      :named
      "Named"
      :in_begin
    OUT
  end

  it "guarded reopen" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A `def` under a guard is REGISTERED BUT NOT PROMISED: it claims no static
      # row and installs where it stands, so the body has to run for the method to
      # exist. A class body written under a guard is that same guard around every
      # `def` it holds, which is what keeps a reopen the branch never took from
      # adding its methods anyway.

      def enabled? = [false].sample
      def disabled? = [true].sample

      class Widget
        def base = "base"
      end

      class Widget
        def extra = "extra"
      end if enabled?

      class Widget
        def other = "other"
      end if disabled?

      p Widget.instance_methods(false).sort
      p Widget.new.other
      begin
        Widget.new.extra
      rescue NoMethodError => e
        puts "NoMethodError: #{e.name}"
      end
      p Widget.new.respond_to?(:extra)

      # Both arms of one guard reopen the same class: only the arm that runs adds
      # anything, and the constant is the same class either way.
      class Impl
        def greet = "base"
      end
      if enabled?
        class Impl
          def greet = "yes"
          def only_yes = 1
        end
      else
        class Impl
          def greet = "no"
          def only_no = 2
        end
      end
      p Impl.new.greet
      p Impl.instance_methods(false).sort
      p Impl.new.only_no

      # A module reopened under a guard answers the same way.
      module Flags
        def self.base = :base
      end

      module Flags
        def self.extra = :extra
      end if disabled?

      p Flags.extra
      p Flags.singleton_methods(false).sort

      # A guarded body still gives the class row its ivars and its class variables.
      class Holder
        def initialize = @seen = []
        def seen = @seen
      end

      class Holder
        @@count = 0
        def push(x)
          @seen << x
          @@count += 1
          @@count
        end
      end if disabled?

      h = Holder.new
      p h.push(:a)
      p h.seen
    RUBY

    _(result).must_answer <<~'OUT'
      [:base, :other]
      "other"
      NoMethodError: extra
      false
      "no"
      [:greet, :only_no]
      2
      :extra
      [:base, :extra]
      1
      [:a]
    OUT
  end

  it "static guards" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A guard a whole-program compile can decide leaves only the branch that
      # runs. It matters more than it saves: a `def` in each branch of a guard
      # that stayed dynamic would leave TWO definitions of one name and the
      # later one would simply win, so an engine gate would pick the branch
      # written for the engine this is not.

      if RUBY_ENGINE == "truffleruby"
        class Fast
          def kind = :truffle
        end
      else
        class Fast
          def kind = :ruby
        end
      end

      p Fast.new.kind

      def report
        if RUBY_ENGINE != "ruby"
          :other
        else
          :ruby
        end
      end
      p report

      p(RUBY_VERSION >= "3.3.0" ? :new : :old)

      # `&&`, `||` and `!` fold three-valued, so one decided side settles the
      # guard even when the other stays unknown.
      p :yes if RUBY_ENGINE == "ruby" && !(RUBY_ENGINE == "jruby")
      p(:no) unless RUBY_ENGINE == "opal" || RUBY_ENGINE == "rbx"

      # The anchored `::Foo` means the TOP LEVEL, not an empty namespace.
      module Wrapper
        Integer = :shadowed

        def self.plain = ::Integer
        def self.shadowed = Integer
      end

      p Wrapper.plain, Wrapper.shadowed
      p ::Wrapper.plain
    RUBY

    _(result).must_answer <<~'OUT'
      :ruby
      :ruby
      :new
      :yes
      :no
      Integer
      :shadowed
      Integer
    OUT
  end
end
