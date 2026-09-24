# frozen_string_literal: true

require "spec_helper"

describe "Classes: defining and naming methods" do
  it "alias before override binds inherited" do
    result = zr(<<~'RUBY')
      # An `alias` written BEFORE the class overrides its source binds the body
      # that existed at the alias's position -- the INHERITED one. rspec-core's
      # QueryOptimized does `alias find_items_for items_for` then redefines
      # `items_for` to memoize through the alias; binding the override instead
      # made the memo call itself forever.
      class Query
        def items_for(m) = "inherited scan #{m}"
      end
      class QueryOptimized < Query
        alias find_items_for items_for
        private :find_items_for
        def items_for(m) = "memoized: #{send(:find_items_for, m)}"
      end
      p QueryOptimized.new.items_for(1)
    RUBY

    _(result).must_answer "\"memoized: inherited scan 1\"\n"
  end

  it "alias captures the overriding bodys own behavior in a subclass" do
    result = zr(<<~'RUBY')
      # `alias` binds to whichever body is ALREADY in effect at the alias
      # statement's own position -- here, `Dog`'s own override (found in
      # `Dog`'s `own_methods`), not `Animal`'s.

      class Animal
        def speak
          "generic"
        end
      end
      class Dog < Animal
        def speak
          "woof"
        end
        alias original_speak speak
      end
      d = Dog.new
      puts d.speak
      puts d.original_speak
    RUBY

    _(result).must_answer "woof\nwoof\n"
  end

  it "anonymous class" do
    result = zr(<<~'RUBY')
      # Anonymous runtime classes (#97): Class.new with define_method and def bodies,
      # constant naming, is_a?/instance_of?, and a runtime superclass chain.

      Animal = Class.new do
        define_method(:speak) { "generic sound" }
        def legs
          4
        end
      end
      a = Animal.new
      puts a.speak
      puts a.legs
      puts a.is_a?(Animal)
      puts a.is_a?(Object)
      puts a.instance_of?(Animal)
      puts Animal.superclass
      puts Animal.name

      Mammal = Class.new(Animal) do
        define_method(:warm_blooded) { true }
      end
      m = Mammal.new
      puts m.speak
      puts m.legs
      puts m.warm_blooded
      puts m.is_a?(Animal)
      puts m.instance_of?(Animal)
      puts Mammal.superclass.name

      klass = Class.new
      puts klass.new.is_a?(klass)
    RUBY

    _(result).must_answer <<~'OUT'
      generic sound
      4
      true
      true
      true
      Object
      Animal
      generic sound
      4
      true
      true
      false
      Animal
      true
    OUT
  end

  it "class side alias of an inherited new" do
    result = zr(<<~'RUBY')
      class Q1; end
      Q1.singleton_class.class_eval { alias_method :made, :new }
      p Q1.made.class.to_s

      class Q2; end
      Q2.singleton_class.class_eval { alias_method :label, :name }
      p Q2.label

      class Q3; end
      Q3.singleton_class.class_eval { alias_method :raw, :allocate }
      p Q3.raw.class.to_s

      class Q4; end
      Q4.singleton_class.send(:alias_method, :ims, :instance_methods)
      p Q4.ims(false)

      class Q5; end
      Q5.singleton_class.class_eval { alias_method :str, :to_s }
      p Q5.str

      module Q6; end
      Q6.singleton_class.class_eval { alias_method :nm, :name }
      p Q6.nm

      class Q9
        singleton_class.alias_method :made2, :new
      end
      p Q9.made2.class.to_s

      class QA
        def self.new = super
      end
      QA.singleton_class.class_eval { alias_method :m3, :new }
      p QA.m3.class.to_s

      module Macro
        def tag = "from the macro"
      end
      class QC
        extend Macro
      end
      QC.singleton_class.class_eval { alias_method :label, :tag }
      p QC.label
    RUBY

    _(result).must_answer <<~'OUT'
      "Q1"
      "Q2"
      "Q3"
      []
      "Q5"
      "Q6"
      "Q9"
      "QA"
      "from the macro"
    OUT
  end

  it "const alias in class position" do
    result = zr(<<~'RUBY')
      # A constant that ALIASES a class or module (`ALIAS = Base`) reads as a value
      # everywhere -- but the interesting positions are the ones that usually hold a
      # literal class NAME: `rescue`, `is_a?`, and `raise`. Ruby evaluates the
      # constant in all three, so the alias works there, and an undefined constant
      # raises only once the expression is actually reached.
      module M
        module Tag; end
        class Base < StandardError
          include Tag
        end
        ALIAS = Base
        TAGALIAS = Tag
      end

      p M::ALIAS
      p M::ALIAS.new("x").class
      p M::Base.new("x").is_a?(M::ALIAS)
      p M::Base.new("x").is_a?(M::TAGALIAS)
      p 1.is_a?(M::TAGALIAS)

      begin
        raise M::Base, "boom"
      rescue M::ALIAS => e
        p [:rescued, e.message]
      end

      begin
        raise M::Base, "tagged"
      rescue M::TAGALIAS => e
        p [:by_module_alias, e.message]
      end

      # `raise` through the alias itself.
      begin
        raise M::ALIAS, "through the alias"
      rescue M::Base => e
        p [e.class.to_s, e.message]
      end

      # --- unqualified, which is the same rule one scope out ----------------------
      Plain = M::Base
      p M::Base.new("y").is_a?(Plain)
      begin
        raise Plain, "plain"
      rescue Plain => e
        p [:plain, e.message]
      end

      # --- an undefined constant raises only where Ruby reaches it -----------------
      begin
        1
      rescue NoSuchErrorClass => e
        p :never
      end
      p :the_clause_that_never_fired_still_compiled

      begin
        begin
          raise "x"
        rescue AlsoMissing
          p :no
        end
      rescue NameError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      M::Base
      M::Base
      true
      true
      false
      [:rescued, "boom"]
      [:by_module_alias, "tagged"]
      ["M::Base", "through the alias"]
      true
      [:plain, "plain"]
      :the_clause_that_never_fired_still_compiled
      "uninitialized constant AlsoMissing"
    OUT
  end

  it "nested class undef stays in that class" do
    result = zr(<<~'RUBY')
      # `undef_method` under a guard zeo cannot decide is a RUNTIME fact, so the
      # name goes on the class's `runtime_undefs` and codegen stops emitting a
      # direct call for it. The walk that collects those names had no stops, so a
      # nested class's undef was credited to the ENCLOSING class too -- which only
      # de-optimizes a name the outer class never undefs, but it de-optimizes it in
      # every program that nests this way.
      class Outer
        def keep
          "outer-keep"
        end

        class Inner
          def keep
            "inner-keep"
          end
          undef_method :keep if 1 == 1
        end
      end

      p Outer.new.keep
      begin
        p Outer::Inner.new.keep
      rescue NoMethodError
        p :inner_undefined
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "outer-keep"
      :inner_undefined
    OUT
  end

  it "runtime alias of a builtin reaches a class receiver" do
    result = zr(<<~'RUBY', files: beside("runtime_alias/lib/kernel_patch.rb"))
      # A run-time `alias_method` on Kernel whose source is a BUILTIN row landed
      # where an ordinary receiver could reach it and nowhere a Class or Module
      # receiver looks -- while `respond_to?` answered true for both, so the
      # disagreement was between two of zeo's own tables.
      #
      # rubygems' `kernel_require.rb` is exactly this shape
      # (`alias_method :gem_original_require, :require`), and it is required at run
      # time, so `zeo gem install` died with "undefined method
      # 'gem_original_require' for class Gem::Net::HTTP".
      #
      # The require must be COMPUTED: spliced through `-I` the alias and its callers
      # compile into one stream and the frozen registry answers.

      $LOAD_PATH.unshift File.expand_path(
        "runtime_alias/lib", __dir__
      )
      feature = "kernel_patch"
      require feature

      class Widget; end
      module Trait; end
      anon = Module.new
      obj = Object.new

      p Widget.respond_to?(:zeo_orig_frozen, true)
      [Widget, Trait, anon, (class << obj; self; end), obj].each do |recv|
        p recv.send(:zeo_orig_frozen)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      false
      false
      false
    OUT
  end

  it "superclass named through a qualified alias" do
    result = zr(<<~'RUBY')
      # `class Map < Collection::MapImplementation` -- concurrent-ruby's shape, where
      # the superclass is named through a QUALIFIED constant that holds a class.
      #
      # `const_write_values` keys the scope-less writes by their LEAF, so
      # `MapImplementation = ...` written inside `module Collection` is filed under
      # that leaf alone and the path never matched it. The subclass was judged to
      # have a compile-time superclass, went down the static path, and was DROPPED
      # when nothing there could resolve the name -- `Concurrent::Map` simply did not
      # exist, and i18n could not build its cache on top of it.
      module D
        module Coll
          class Backend
            def kind = :backend
          end
          IMPL = Backend
        end

        class ViaQualified < Coll::IMPL
          def extra = :extra
        end
        class ViaFullyQualified < D::Coll::IMPL; end
      end

      # An UNQUALIFIED alias always worked, and a qualified real class always took
      # the static path. Both stay here so a fix to one cannot quietly move the other.
      module E
        class Backend
          def kind = :backend
        end
        IMPL = Backend
        class ViaBare < IMPL; end
        class ViaRealClass < E::Backend; end
      end

      p D::ViaQualified.new.kind
      p D::ViaQualified.new.extra
      p D::ViaQualified.superclass
      p D::ViaFullyQualified.new.kind
      p E::ViaBare.new.kind
      p E::ViaRealClass.new.kind
      p D::ViaQualified.ancestors.include?(D::Coll::Backend)
    RUBY

    _(result).must_answer <<~'OUT'
      :backend
      :extra
      D::Coll::Backend
      :backend
      :backend
      :backend
      true
    OUT
  end

  it "undef removes a name including an inherited one" do
    result = zr(<<~'RUBY')
      # `undef` works on a name this class only INHERITS, which is why it
      # can't be "delete the local def" -- there is none. It stays live on
      # the ancestor that defined it, and `respond_to?` must agree.

      class B
        def inherited_m; "from B"; end
        def own; "own"; end
      end
      class C < B
        def local_m; "local"; end
        undef local_m
        undef inherited_m
      end
      begin; C.new.local_m; rescue NoMethodError; puts "local: NoMethodError"; end
      begin; C.new.inherited_m; rescue NoMethodError; puts "inherited: NoMethodError"; end
      p B.new.inherited_m
      p C.new.own
      p C.new.respond_to?(:inherited_m)
      class D
        def a; 1; end
        def b; 2; end
        undef a, b
      end
      begin; D.new.a; rescue NoMethodError; puts "D#a gone"; end
    RUBY

    _(result).must_answer <<~'OUT'
      local: NoMethodError
      inherited: NoMethodError
      "from B"
      "own"
      false
      D#a gone
    OUT
  end
end
