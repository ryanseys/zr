# frozen_string_literal: true

require "spec_helper"

describe "Modules: constants" do
  it "const aliased class reopen include" do
    result = zr(<<~'RUBY')
      # Reopening a class through a constant alias (`CONST = SomeClass` or
      # `CONST = expr.class`) reopens that class, and a module included into a
      # reopened built-in becomes dispatchable on the primitive. Regression
      # for #1036 (the to_words gem's `INTEGER_KLASS = 1.class; class
      # INTEGER_KLASS; include ToWords; end` shape).

      module IntWords
        def wordy
          "wordy_" + self.to_s
        end
      end

      # Constant alias to a built-in (via `.class`) + module include.
      INT_ALIAS = 1.class
      class INT_ALIAS
        include IntWords
      end
      puts 42.wordy

      module Greeter
        def greet
          "hi from greeter"
        end
      end

      # Constant alias to a user class + module include.
      class Box
      end
      BOX_ALIAS = Box
      class BOX_ALIAS
        include Greeter
      end
      puts Box.new.greet
    RUBY

    _(result).must_answer "wordy_42\nhi from greeter\n"
  end

  it "const source location of a module constant" do
    result = zr(<<~'RUBY')
      # `Module#const_source_location` answers where a constant was assigned. zeo
      # answers `nil` for a constant written in a module or class body -- the ordinary
      # case -- so the method is only ever right about constants that do not exist.
      #
      # zeo records source locations for methods (`Method#source_location` works) but
      # a constant write is emitted as a plain `zeo_rt::const_set` carrying no span,
      # so `constants.rs` has nothing to report. The information exists at compile
      # time: the same `ClassDef`/assignment node the write is emitted from is the one
      # `const_added` was taught to announce from.
      #
      # It is what a reloader or a diagnostic uses to say WHERE a duplicate constant
      # came from -- the "already initialized constant" warning quotes it -- so
      # answering nil turns a precise message into a vague one.

      module NS
        X = 1
        class Inner
          Y = 2
        end
      end
      Z = 3

      p NS.const_source_location(:X)&.last
      p NS::Inner.const_source_location(:Y)&.last
      p Object.const_source_location(:Z)&.last
      p NS.const_source_location(:Nope)
      p Object.const_source_location(:NS)&.last

      # A constant set at run time reports the caller's line.
      NS.const_set(:W, 4)
      p NS.const_source_location(:W)&.last
    RUBY

    _(result).must_answer <<~'OUT'
      16
      18
      21
      nil
      15
      30
    OUT
  end

  it "constant is how ruby spells a module alias" do
    result = zr(<<~'RUBY')
      # Ruby has no separate alias form for a class or module: naming one twice IS
      # assigning its value to a second constant, and the second name then works
      # everywhere the first does -- `include`, a superclass clause, `.new`. oauth2
      # keeps `OAuth2::FilteredAttributes = OAuth2::AUTH_SANITIZER::FilteredAttributes`
      # as a permanent public alias after moving the implementation to another gem;
      # celluloid-io writes `Constants = ::Socket::Constants` and includes that.

      module Vendor
        module Sanitizer
          module FilteredAttributes
            def filtered = :filtered
          end

          class Base
            def kind = :base
          end
        end
      end

      module App
        # The alias sits in the ENCLOSING scope, and the class body one level in
        # reads it -- ruby's lexical lookup, and where the scope-blind version of
        # this search used to find the wrong module.
        FilteredAttributes = Vendor::Sanitizer::FilteredAttributes

        class Authenticator
          include FilteredAttributes
        end

        # ... and as a superclass, anchored at the top level with `::`.
        Base = ::Vendor::Sanitizer::Base
        class Client < Base
          def kind = [:client, super]
        end
      end

      p App::Authenticator.new.filtered
      p App::Client.new.kind
      p App::Authenticator.ancestors.include?(Vendor::Sanitizer::FilteredAttributes)
      p App::Client.superclass.equal?(Vendor::Sanitizer::Base)

      # An alias OF an alias resolves through.
      module Deeper
        Same = App::Base
        class Grand < Same
        end
      end
      p Deeper::Grand.superclass.equal?(Vendor::Sanitizer::Base)
    RUBY

    _(result).must_answer <<~'OUT'
      :filtered
      [:client, :base]
      true
      true
      true
    OUT
  end

  it "mixin of a constant holding a runtime module" do
    result = zr(<<~'RUBY')
      # A constant the program ASSIGNS a module to, then mixes in. zeo used to
      # refuse this outright: a compiled class dispatches off a static MRO, so an
      # ancestry edit no compile-time name can describe would vanish silently, and a
      # loud refusal beat a wrong answer.
      #
      # It does not have to vanish. The directive keeps its runtime self-send --
      # `runtime_meta::splice_mixin` performs the edit and fires the hook when the
      # body executes -- and every call site widens, so nothing folds to the class's
      # own body underneath an override the splice installed. Widening EVERY name is
      # blunt, but a module minted at run time has no method list to read, and it
      # costs the fast path only in programs that do this.
      #
      # The shape is everywhere. net-ssh picks its `Prompt` out of three candidates
      # behind a rescued require; rspec-rails builds `ControllerAssertionDelegator`
      # by calling `AssertionDelegator.new(...)`; coderunner's `SYSTEM_MODULE` names
      # whichever batch system the host runs.
      module Highline
        def prompt(q) = "highline: #{q}"
      end

      module Clear
        def prompt(q) = "clear: #{q}"
      end

      Prompt = ENV.key?("ZR_TEST_USES_HIGHLINE") ? Highline : Clear

      class KeyFactory
        include Prompt
        def ask = prompt("passphrase")
      end

      p KeyFactory.new.ask
      p KeyFactory.ancestors.first(3).map(&:to_s)
      p KeyFactory.new.is_a?(Clear)

      # All three directives, against a module with no compile-time identity at all.
      # `Loud#speak` reaches the class's own body through `super`, which is the case
      # a folded call site would have broken.
      Minted = Module.new do
        def tag = "minted"
      end

      Loud = Module.new do
        def speak = "LOUD(#{super})"
      end

      Helper = Module.new do
        def build = "built"
      end

      class Widget
        include Minted
        prepend Loud
        extend Helper
        def speak = "quiet"
      end

      p Widget.new.tag
      p Widget.new.speak
      p Widget.build
      p Widget.new.respond_to?(:tag)

      # Top level: `include M` there is `Object.include(M)`, so the methods reach
      # every object.
      def delegator(*names)
        Module.new do
          names.each { |n| define_method(n) { "delegated #{n}" } }
        end
      end

      Delegated = delegator(:alpha, :beta)
      include Delegated

      p alpha
      p Object.include?(Delegated)
    RUBY

    _(result).must_answer <<~'OUT'
      "clear: passphrase"
      ["KeyFactory", "Clear", "Object"]
      true
      "minted"
      "LOUD(quiet)"
      "built"
      true
      "delegated alpha"
      true
    OUT
  end

  it "module const defined" do
    result = zr(<<~'RUBY')
      class A
        X = 1
        Y = "two"
      end

      puts A.const_defined?(:X)
      puts A.const_defined?(:Y)
      puts A.const_defined?(:Z)

      class B
      end

      puts B.const_defined?(:W)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
    OUT
  end

  it "module const get and const defined reflect the registry" do
    result = zr(<<~'RUBY')
      module M
        X = 7
        module N
        end
      end
      puts M.const_get(:X)
      puts M.const_get("X")
      p M.const_defined?(:X)
      p M.const_defined?(:Nope)
      p M.const_defined?(:N)
      p M.const_get(:N).is_a?(Module)
      begin; M.const_get(:Missing); rescue NameError => e; puts e.message; end
      begin; M.const_defined?("bad"); rescue NameError => e; puts e.message; end
    RUBY

    _(result).must_answer <<~'OUT'
      7
      7
      true
      false
      true
      true
      uninitialized constant M::Missing
      wrong constant name bad
    OUT
  end

  it "module constants depth argument" do
    result = zr(<<~'RUBY')
      p Module.constants(0)
      p Module.constants(1)
      p Module.constants(nil)
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      []
    OUT
  end

  it "module constants included modules" do
    result = zr(<<~'RUBY')
      # Module#include? / #included_modules / #constants (#2674). The constant
      # registry is a flat namespace, so ownership is recovered from the AST: a
      # class's own constants are the ConstantWriteNodes in its body.
      #
      # NOTE: the order of constants WITHIN one class is not specified -- CRuby reads
      # them out of an id table, so it varies between programs. Only the grouping is
      # meaningful (own first, then the other ancestors), so multi-constant classes
      # are compared sorted.
      module Walks; end
      class Animal; end
      class Dog < Animal; include Walks; end
      p Dog.include?(Walks)
      p Dog.included_modules
      p Dog.included_modules.include?(Walks)
      p Dog.constants

      module Mod; MC = 9; MD = 10; end
      class A; X = 1; end
      class B < A; Y = 2; include Mod; end
      p A.constants
      p B.constants.sort
      p B.constants(false)
      p Mod.constants.sort
      p B.constants.map { |s| s.to_s }.sort

      # own comes before the inherited groups, and the groups follow #ancestors
      module P; PC = 5; end
      module I; IC = 7; end
      class Own1; prepend P; include I; Q = 6; end
      p Own1.ancestors
      p Own1.constants
      class A2; AC = 1; end
      class B2 < A2; prepend P; BC = 2; end
      p B2.constants

      class Empty; end
      p Empty.constants
      module M2; end
      p M2.constants
    RUBY

    _(result).must_answer <<~'OUT'
      true
      [Walks, Kernel]
      true
      []
      [:X]
      [:MC, :MD, :X, :Y]
      [:Y]
      [:MC, :MD]
      ["MC", "MD", "X", "Y"]
      [P, Own1, I, Object, Kernel, BasicObject]
      [:Q, :PC, :IC]
      [:BC, :PC, :AC]
      []
      []
    OUT
  end

  it "module constants nested" do
    result = zr(<<~'RUBY')
      # A nested class or module IS a constant of the enclosing one. `constants`
      # collected only the value-assigning form, so a module holding both reported
      # the value and not the nested module (#4040).
      module Layout
        WIDTH = 24
        module Border
          def self.wrap(text) = "|#{text}|"
        end
        class Frame
          def initialize(n) = @n = n
          def n = @n
        end
        HEIGHT = 8
      end
      p Layout.constants.sort
      p Layout::Border.wrap("x")
      p Layout::Frame.new(2).n

      module OnlyNested
        module A; end
        module B; end
      end
      p OnlyNested.constants.sort

      module OnlyValues
        X = 1
        Y = 2
      end
      p OnlyValues.constants.sort

      module Empty; end
      p Empty.constants

      class Holder
        INNER = 3
        class Deep
          DEEPER = 4
        end
      end
      p Holder.constants.sort
      p Holder::Deep.constants.sort
    RUBY

    _(result).must_answer <<~'OUT'
      [:Border, :Frame, :HEIGHT, :WIDTH]
      "|x|"
      2
      [:A, :B]
      [:X, :Y]
      []
      [:Deep, :INNER]
      [:DEEPER]
    OUT
  end

  it "module relative constant path" do
    result = zr(<<~'RUBY')
      # Test: relative ConstantPath class/module definitions inside a module.

      module M
        class A
        end

        class A::B
          def value
            10
          end
        end

        module N
        end

        module N::P
          class C
            def value
              30
            end
          end
        end
      end

      puts M::A::B.new.value
      puts M::N::P::C.new.value
    RUBY

    _(result).must_answer "10\n30\n"
  end

  it "module s constants answers for its receiver" do
    result = zr(<<~'RUBY')
      TOP_LEVEL_MARK = 1
      module M
        IN_M = 2
      end

      # A bare `Module.constants` is the lexical-scope query.
      p Module.constants.include?(:TOP_LEVEL_MARK)

      # Given an argument it stops being that and asks Module's own set.
      p Module.constants(false)

      # Given ANY OTHER receiver it asks that receiver's, whatever the arity. Every
      # singleton class of a module inherits this row -- `#<Class:M>.singleton_class`
      # has `#<Class:Module>` as its superclass -- so this is the path
      # `M.singleton_class.constants` takes.
      sc = M.singleton_class
      sc.const_set(:ON_THE_SINGLETON, 3)
      p sc.constants(false)
      p sc.constants.include?(:ON_THE_SINGLETON)
      p M.constants
      p M.singleton_class.const_get(:ON_THE_SINGLETON)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      []
      [:ON_THE_SINGLETON]
      true
      [:IN_M]
      3
    OUT
  end
end
