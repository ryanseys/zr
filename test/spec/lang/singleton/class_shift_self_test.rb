# frozen_string_literal: true

require "spec_helper"

describe "Singleton programs" do
  it "a class << self body lowers def, alias, attr_accessor, define_method, private and undef" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A `class << obj` body opens the object's SINGLETON class, which no row
      # can name -- a singleton is minted per object at run time. Each `def`
      # becomes a `define_singleton_method`, and every other statement is
      # lowered with `self` bound to `obj.singleton_class`, which is what
      # `self` is inside that body.

      class Config
        class << self
          def direct = :direct

          alias aliased direct

          attr_accessor :level

          # `self` is the singleton class, so a receiverless macro and an
          # explicit `self.` call both name it.
          self.send(:define_method, :made) { :made }

          private

          def hidden = :hidden
        end
      end

      p Config.direct, Config.aliased, Config.made
      Config.level = 3
      p Config.level
      p Config.singleton_class.private_instance_methods(false).sort
      p(begin
        Config.hidden
      rescue NoMethodError
        :private
      end)

      # A block written in the body closes over that `self` too.
      class Made
        class << self
          %w[a b].each { |n| define_method("m_#{n}") { n } }
        end
      end

      p Made.m_a, Made.m_b

      # An arbitrary statement runs where it stands.
      $log = []

      class Logged
        class << self
          $log << :before
          def one = 1
          $log << :after
        end
      end

      p $log, Logged.one

      # `undef` retires the name on the singleton class.
      class Retired
        class << self
          def gone = :gone
          undef gone
        end
      end

      p Retired.respond_to?(:gone)

      # `class << obj` on a plain object opens that one object's singleton.
      o = Object.new

      class << o
        def only = :only
      end

      p o.only, o.singleton_methods
      p Object.new.respond_to?(:only)
    RUBY

    _(result).must_answer <<~'OUT'
      :direct
      :direct
      :made
      3
      [:hidden]
      :private
      "a"
      "b"
      [:before, :after]
      1
      false
      :only
      [:only]
      false
    OUT
  end

  it "a class nested in a class << self body belongs to the singleton, and self:: roots a path there" do
    result = zr(<<~'RUBY')
      # Two things a `class << self` body can hold,
      # both straight out of irb: a nested `class` (color.rb's `class
      # ColorizeVisitor < Prism::Visitor`), and a constant path rooted at `self`
      # (input-method.rb's `self::Readline::HISTORY`).
      #
      # A class written here belongs to the SINGLETON class, exactly as a constant
      # written here does -- `class X` IS a constant write with a body. Both are
      # wrapped in the singleton surrogate at their own position, so the singleton
      # methods beside them still reach them by bare name while the enclosing
      # module answers for neither.
      module Color
        class << self
          class Visitor
            def initialize(name) = @name = name
            def render = "<#{@name}>"
          end

          def paint(name)
            Visitor.new(name).render
          end
        end
      end

      puts Color.paint("red")

      # The class is the singleton's, not the module's.
      p Color.singleton_class.const_defined?(:Visitor)
      p Color.constants
      p(begin; Color::Visitor; rescue NameError => e; e.message; end)
      p Color.singleton_class::Visitor.new("blue").render

      # A constant beside it takes the same route, and the two list together.
      module Sized
        class << self
          MAX = 5
          class Box; end
          def cap = MAX
        end
      end
      p Sized.cap
      p Sized.singleton_class.constants.sort
      p Sized.constants
      p(begin; Sized::MAX; rescue NameError => e; e.message; end)

      # `self::Engine.name` -- a constant path whose ROOT is dynamic but whose outer
      # node is still a path, which is what the old "is the immediate PARENT a
      # constant?" test misread as static.
      class Reader
        class << self
          def setup
            const_set(:Engine, ::String)
            const_set(:LABEL, self::Engine.name)
          end
        end
      end

      Reader.setup
      p Reader::Engine
      p Reader::LABEL
    RUBY

    _(result).must_answer <<~'OUT'
      <red>
      true
      []
      "uninitialized constant Color::Visitor"
      "<blue>"
      5
      [:Box, :MAX]
      []
      "uninitialized constant Sized::MAX"
      String
      "String"
    OUT
  end

  it "a constant written in a class << self body belongs to the singleton and Module.nesting reports it" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `class << self` opens the class's SINGLETON, which is a class in its own
      # right: a constant written there belongs to it and not to the class, the
      # class methods beside it read the constant through the cref, and
      # `Module.nesting` reports it. So the body gets a row of its own, named
      # `#<Class:Owner>` -- a name no Ruby constant can collide with. Only the
      # runtime mints a singleton, so the row names the class it is the
      # singleton of and the backend ties the two.

      class Config
        class << self
          PREFIX = "cfg:"
          LIMIT = 3

          def key(n) = "#{PREFIX}#{n}"
          def capped(n) = n > LIMIT ? LIMIT : n
          def nesting = Module.nesting.map(&:to_s)
        end
      end

      p Config.key("host")
      p Config.capped(9)
      p Config.nesting
      p Config.const_defined?(:PREFIX, false)
      p Config.singleton_class.const_defined?(:PREFIX, false)
      p Config.singleton_class.constants(false).sort

      # A second body reopens the SAME singleton, so its constants join the
      # first body's, and a class method written OUTSIDE cannot reach them by
      # bare name.
      class Config
        class << self
          SUFFIX = "!"

          def both = [PREFIX, SUFFIX]
        end

        def self.blind
          PREFIX
        rescue NameError
          :name_error
        end
      end

      p Config.both
      p Config.blind

      # The surrogate sits in the full lexical chain, so a body in `A::B` reads
      # A's constants -- and the enclosing scope's are shadowed by its own.
      module A
        ROOT = :a_const
        SHADOWED = :from_module

        module B
          class << self
            INNER = :inner
            SHADOWED = :from_singleton

            def chain = [INNER, ROOT, SHADOWED]
            def nest = Module.nesting.map(&:to_s)
          end
        end
      end

      p A::B.chain
      p A::B.nest

      # The surrogate is the body's DEFINEE too, so a `def` written in a block
      # here installs on the singleton, which is where ruby installs it.
      class Late
        class << self
          def install
            [1].each { def inner = :inner }
            :installed
          end
        end
      end

      p Late.install
      p Late.singleton_methods(false).sort
      p Late.inner

      # A `class` written here belongs to the singleton too -- `class X` IS a
      # constant write with a body -- and a `class << self` beside it opens the
      # surrogate's own singleton, the same construct one level deeper.
      module Color
        class << self
          class Visitor
            def initialize(name) = @name = name
            def render = "<#{@name}>"
          end

          class << self
            SUFFIX = "!"
            def shout(s) = s + SUFFIX
          end

          def paint(name) = Visitor.new(name).render
        end
      end

      p Color.paint("red")
      p Color.singleton_class.shout("hi")
      p Color.singleton_class.const_defined?(:Visitor)
      p Color.constants
      p Color.singleton_class.singleton_class.const_defined?(:SUFFIX)

      # `def self.x` here defines on the singleton's OWN singleton, one level
      # further up than a bare `def`.
      class MetaHost
        class << self
          def plain = "plain"
          def self.meta = "meta"
        end
      end

      p MetaHost.plain
      p(begin; MetaHost.meta; rescue NoMethodError; :no_such_method; end)
      p MetaHost.singleton_class.meta

      # The body has a backtrace frame of its own, labelled `singleton class`,
      # and its own locals, shared across the whole of it.
      begin
        class Walked
          class << self
            step = 1
            total = step + 1
            raise "at #{total}"
          end
        end
      rescue RuntimeError => e
        p [e.message, e.backtrace.first[/:\d+:in '.*'/]]
      end

      # A `class << obj` on any other receiver keeps the per-object road: its
      # `def`s are singleton methods of that object.
      target = Object.new
      class << target
        def only_mine = :mine
      end
      p target.only_mine
      p target.singleton_methods
    RUBY

    _(result).must_answer <<~'OUT'
      "cfg:host"
      3
      ["#<Class:Config>", "Config"]
      false
      true
      [:LIMIT, :PREFIX]
      ["cfg:", "!"]
      :name_error
      [:inner, :a_const, :from_singleton]
      ["#<Class:A::B>", "A::B", "A"]
      :installed
      [:inner, :install]
      :inner
      "<red>"
      "hi!"
      true
      []
      true
      "plain"
      :no_such_method
      "meta"
      ["at 2", ":129:in 'singleton class'"]
      :mine
      [:only_mine]
    OUT
  end

  it "class << Klass takes ordinary statements, and a prepend there fronts the class methods" do
    result = zr(<<~'RUBY')
      # `class << Klass` opens the class's SINGLETON, so `prepend M` there puts M's
      # instance methods in front of `Klass`'s own class methods, with `super` resuming
      # at the original. The body is ordinary statements: `self` names the singleton
      # class, an explicit `self.` receiver names the same thing, and a statement that
      # never reaches for `self` means what it means anywhere and just runs.
      #
      # The active_hash gems spell their pagination hook `class << Base;
      # self.prepend(ClassMethods); end`.

      SEEN = []

      module Wrap
        def greet = "wrapped(#{super})"
      end

      class Direct
        def self.greet = "Direct"
      end

      Direct.singleton_class.prepend(Wrap)
      p Direct.greet

      # The same edit written as a singleton body has the same effect.
      class Opened
        def self.greet = "Opened"
      end

      class << Opened
        prepend Wrap
      end

      p Opened.greet

      # (What a class-method prepend does NOT yet do is show up in
      # `singleton_class.ancestors` or in `Method#owner` -- dispatch and `super`
      # honour it, reflection does not. Filed separately; asserting it here would
      # only pin the divergence.)

      # An explicit `self.` receiver is that same singleton class.
      module Paginatable
        module ClassMethods
          def page = "paged(#{super})"
        end
      end

      class Records
        def self.page = "records"
      end

      class << Records
        self.prepend(Paginatable::ClassMethods)
      end

      p Records.page

      # A statement that consults `self` nowhere runs unchanged, at this position.
      class Quiet
        def self.tag = :quiet
      end

      class << Quiet
        SEEN << :body_ran
        prepend Wrap
      end

      p SEEN
      p Quiet.tag

      # A bare `singleton_class` in a class body IS that class's singleton, with no
      # constant naming it. activesupport writes its ERB patch that way, and pundit --
      # and every gem behind activesupport -- reaches the ledger through it.
      class Bare
        def self.greet = "bare"

        singleton_class.prepend Wrap
      end

      p Bare.greet

      module Namespaced
        class Deep
          def self.greet = "deep"

          singleton_class.prepend Wrap
        end
      end

      p Namespaced::Deep.greet

      # And the per-object form still defines per-object methods.
      obj = Object.new

      class << obj
        def shout = :loud
      end

      p obj.shout
      p obj.singleton_methods
    RUBY

    _(result).must_answer <<~'OUT'
      "wrapped(Direct)"
      "wrapped(Opened)"
      "paged(records)"
      [:body_ran]
      :quiet
      "wrapped(bare)"
      "wrapped(deep)"
      :loud
      [:shout]
    OUT
  end

  it "prepend, undef_method and private in a class << self body reach the class methods" do
    result = zr(<<~'RUBY')
      # `class << self` carries more than `def`: a `prepend` mixes into the singleton
      # ahead of the class's own `def self.x`, an `undef_method` retires an inherited
      # class method, and a `private` names one this body does not define.

      module Loud
        def greet
          "LOUD #{super}"
        end
      end

      class Base
        def self.greet
          "base"
        end

        def self.inherited_helper
          "helper"
        end

        def self.keyword_helper
          "keyword"
        end

        def self.secret
          "secret"
        end
      end

      class Child < Base
        class << self
          prepend Loud

          undef_method :inherited_helper

          undef :keyword_helper

          private :secret
        end

        def self.greet
          "child"
        end
      end

      puts Child.greet
      puts Base.greet

      begin
        Child.inherited_helper
      rescue NoMethodError => e
        puts "undef: #{e.class}"
      end
      puts Base.inherited_helper
      puts Child.respond_to?(:inherited_helper)

      begin
        Child.keyword_helper
      rescue NoMethodError => e
        puts "undef keyword: #{e.class}"
      end
      puts Base.keyword_helper

      begin
        Child.secret
      rescue NoMethodError => e
        puts "private: #{e.class}"
      end
      puts Child.send(:secret)
    RUBY

    _(result).must_answer <<~'OUT'
      LOUD child
      base
      undef: NoMethodError
      helper
      false
      undef keyword: NoMethodError
      keyword
      private: NoMethodError
      secret
    OUT
  end

  it "a statement in a class << self body runs in source order, so define_method lands between the defs" do
    result = zr(<<~'RUBY')
      # The corpus's single biggest lowering gap: `class << self` bodies rejected on
      # ONE shape -- a call with a receiver whose BLOCK reaches for `self`:
      #
      #     class << self
      #       %w(get post).each { |n| define_method(n) { ... } }
      #     end
      #
      # The mapping worked by rewriting a statement's RECEIVER, which cannot rebind
      # `self` for a nested block, so the whole statement was refused.
      #
      # It now runs where ruby runs it: as a statement of the singleton's own class
      # body. That is CRuby's structure, not a workaround for it -- `NODE_SCLASS`
      # compiles to a child iseq whose `self` IS the singleton class object, so a
      # block created inside sees that `self` for free.
      $log = []
      class Ordered
        class << self
          $log << :before_def
          def a = :a
          $log << :after_def
          %w(x y).each { |n| define_method(n) { n } }
          $log << :after_each
          def b = :b
          $log << :after_b
        end
      end

      # Statements run in SOURCE order, and the runtime one keeps its position among
      # them.
      p $log
      p [Ordered.a, Ordered.b, Ordered.x, Ordered.y]

      # The methods are real class methods of the enclosing class, reachable from a
      # statically-compiled call site -- which is the whole question the design
      # turned on.
      p Ordered.respond_to?(:x)
      p Ordered.singleton_class.method_defined?(:x)

      # `singleton_method_added` fires for a `define_method`'d name exactly as for a
      # `def`, and in source order -- which is what makes the ordering above an
      # observable rather than a tidiness argument.
      $hooks = []
      class Hooked
        def self.singleton_method_added(n) = $hooks << [:sma, n]
        class << self
          [:viaeach].each { |n| define_method(n) { n } }
          def plain = :plain
        end
      end
      p $hooks

      # Reflection cannot tell the two apart: same owner, same list.
      class Refl
        class << self
          [:m1].each { |n| define_method(n) { n } }
          def m2 = :m2
        end
      end
      p Refl.singleton_class.instance_methods(false).sort
      p (Refl.methods - Object.methods).sort
      p Refl.singleton_class.instance_method(:m1).owner == Refl.singleton_class
      p Refl.method(:m1).owner == Refl.singleton_class

      # The block's `self` is the singleton, so a `def_delegator`-style macro or any
      # other receiverless send inside it targets the singleton too.
      class Macro
        class << self
          def helper(n) = "helped:#{n}"
          [:one, :two].each do |n|
            define_method(n) { helper(n) }
          end
        end
      end
      p [Macro.one, Macro.two]

      # Constants in the same body still belong to the singleton class, and the
      # runtime statement can read them.
      class WithConst
        class << self
          NAMES = %w(alpha beta)
          NAMES.each { |n| define_method(n) { n } }
        end
      end
      p [WithConst.alpha, WithConst.beta]
      p WithConst.singleton_class.const_defined?(:NAMES)
      p WithConst.const_defined?(:NAMES)
    RUBY

    _(result).must_answer <<~'OUT'
      [:before_def, :after_def, :after_each, :after_b]
      [:a, :b, "x", "y"]
      true
      true
      [[:sma, :singleton_method_added], [:sma, :viaeach], [:sma, :plain]]
      [:m1, :m2]
      [:m1, :m2]
      true
      true
      ["helped:one", "helped:two"]
      ["alpha", "beta"]
      true
      false
    OUT
  end

  it "a return in class << self returns from the method that holds it" do
    result = zr(<<~'RUBY')
      def a = (class << self; return :inner; end; :outer)
      p a
      def b(x) = (class << self; return :early if $x > 1; end; :small)
      $x = 1; r1 = b(1); $x = 5; p [r1, b(5)]
      def c = ([1].each { class << self; return :from_block_sclass; end }; :outer)
      p c
      def d = (class << self; [2].each { return :nested_block }; end; :outer)
      p d
      def e
        class << self
          begin
            return :ens
          ensure
            puts "ensure ran"
          end
        end
        :outer
      end
      p e
      def f = (class << self; class << self; return :deep; end; end; :outer)
      p f
      def g = (class << self; def h = :h; end; :after)
      p [g, h]
      pr = proc { class << self; return 1; end }
      pr.call rescue p $!
      def mk = proc { class << self; return 2; end }
      begin; mk.call; rescue LocalJumpError => e; p [e.message, e.reason, e.exit_value]; end
    RUBY

    _(result).must_answer <<~'OUT'
      :inner
      [:small, :early]
      :from_block_sclass
      :nested_block
      ensure ran
      :ens
      :deep
      [:after, :h]
      #<LocalJumpError: unexpected return>
      ["unexpected return", :return, 2]
    OUT
  end
end
