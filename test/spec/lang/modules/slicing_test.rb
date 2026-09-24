# frozen_string_literal: true

require "spec_helper"

describe "Modules: slicing" do
  it "builtin module reopen reaches all includers" do
    result = zr(<<~'RUBY')
      # Reopening a builtin MODULE (D3): the added method reaches every includer --
      # Enumerable across Array/Hash, Comparable across Integer.

      module Enumerable
        def second
          first(2).last
        end
      end
      module Comparable
        def clamp_low(lo)
          self < lo ? lo : self
        end
      end
      puts [10, 20, 30].second
      puts({ a: 1, b: 2 }.map { |k, v| v }.second)
      puts 5.clamp_low(8)
      puts 12.clamp_low(8)
    RUBY

    _(result).must_answer <<~'OUT'
      20
      2
      8
      12
    OUT
  end

  it "later def on a module installs at its line" do
    result = zr(<<~'RUBY')
      # Ruby installs each `def` where it stands, and a MODULE's `def` is no
      # different: a call written above a reopen answers the FIRST body, in every
      # class that mixed the module in, in a module that includes it, and in an
      # object that extended it.
      #
      # zr used to answer the last body everywhere, because a module's rows reach
      # a host by MATERIALIZATION -- analyze copies them onto each includer once,
      # for the whole program -- so the reopen's body was the one that got copied
      # and there was no position to install it at. `analyze::redefs` gives it the
      # same timeline a plain class already had.

      module M
        def z = "first"
      end
      class K; include M; end
      class P; prepend M; end
      obj = Object.new
      obj.extend(M)

      p K.new.z, P.new.z, obj.z
      p K.instance_method(:z).owner

      module M
        def z = "second"
      end

      p K.new.z, P.new.z, obj.z
      p K.instance_method(:z).owner

      # A host that joins AFTER the reopen sees the reopened body, and one with its
      # OWN definition keeps it.
      class Late; include M; end
      p Late.new.z

      class Over
        include M
        def z = "own"
      end
      module M
        def z = "third"
      end
      p Over.new.z, K.new.z

      # `super` through the module reaches the body standing at the time.
      module N
        def w = "n1"
      end
      class H
        include N
        def w = "h-" + super
      end
      p H.new.w
      module N
        def w = "n2"
      end
      p H.new.w

      # A module included into another module carries the timeline through.
      module Inner
        def q = "i1"
      end
      module Outer
        include Inner
      end
      class Z; include Outer; end
      p Z.new.q
      module Inner
        def q = "i2"
      end
      p Z.new.q

      # The shape that already worked, kept so a fix cannot close this by breaking
      # that one.
      class L
        def y = "first"
      end
      p L.new.y
      class L
        def y = "second"
      end
      p L.new.y
    RUBY

    _(result).must_answer <<~'OUT'
      "first"
      "first"
      "first"
      M
      "second"
      "second"
      "second"
      M
      "second"
      "own"
      "third"
      "h-n1"
      "h-n2"
      "i1"
      "i2"
      "first"
      "second"
    OUT
  end

  it "mixin in a case arm widens its call sites" do
    result = zr(<<~'RUBY')
      # A `prepend`/`include`/`extend` reachable through a class-body `case` arm is
      # an ancestry edit exactly as one in an `if` branch is. Whether it happens is a
      # runtime fact, so every call site the module could newly answer has to stop
      # folding -- `C.new.tag` below must reach the prepended override, not the
      # class's own body underneath it.
      module Tagger
        def tag
          :from_module
        end
      end

      class Widened
        def tag
          :from_class
        end
      end

      class Widened
        case ENV.fetch("ZR_TEST_MIXIN_MODE", "on")
        when "on" then prepend Tagger
        else nil
        end
      end

      p Widened.new.tag
      p Widened.ancestors.first
    RUBY

    _(result).must_answer ":from_module\nTagger\n"
  end

  it "module class reflection" do
    result = zr(<<~'RUBY')
      # A module/class constant must behave as a first-class Module/Class
      # object: .class, is_a?/kind_of?/instance_of?(Module|Class), and a
      # nested name rendered with the `::` separator.
      module Foo
        class Bar; end
      end
      module Outer
        module Inner; end
      end
      module M; end
      class C; end

      puts Foo::Bar.name           # nested name uses ::
      puts Foo.class               # Module
      puts C.class                 # Class
      puts Outer::Inner.class      # Module (ConstantPathNode receiver)
      puts M.is_a?(Module)         # true
      puts C.is_a?(Module)         # true
      puts M.is_a?(Class)          # false
      puts C.is_a?(Class)          # true
      puts M.is_a?(Object)         # true
      puts M.instance_of?(Module)  # true
      puts C.instance_of?(Class)   # true
      puts M.instance_of?(Class)   # false
      k = C                        # dynamic Class value
      puts k.is_a?(Class)          # true
      puts k.class                 # Class
    RUBY

    _(result).must_answer <<~'OUT'
      Foo::Bar
      Module
      Class
      Module
      true
      true
      false
      true
      true
      true
      true
      false
      true
      Class
    OUT
  end

  it "module redefinition reaches its copies" do
    result = zr(<<~'RUBY')
      # A module's rows are MATERIALIZED onto every class that mixes it in, so a
      # host's own flattened copy answers before the module is ever asked. A second
      # `def` on the module wrote an overlay row nothing read, and every call --
      # before the redefinition as well as after -- got the LAST body.
      #
      # The fix retires the host's copy, which sends the walk on to the module.
      # A host with a `def` of its own keeps it.

      module Kernel
        def helper = :first
      end
      p 5.helper
      p "s".helper
      p [].helper
      p Object.new.helper
      p helper
      p 5.method(:helper).owner

      module Kernel
        def helper = :second
      end
      p 5.helper
      p "s".helper
      p [].helper
      p Object.new.helper
      p helper

      # A user module mixed into a BUILTIN.
      module Shout
        def shout = "one"
      end
      class String
        include Shout
      end
      p "x".shout
      p String.instance_method(:shout).owner
      module Shout
        def shout = "two"
      end
      p "x".shout

      # A user module mixed into a user class, and a host with its OWN def.
      module M
        def m_helper = :one
      end
      class C
        include M
      end
      class D
        include M
        def m_helper = :own
      end
      c = C.new
      p c.m_helper
      p D.new.m_helper

      module M
        def m_helper = :two
      end
      p c.m_helper
      p D.new.m_helper
      p C.instance_method(:m_helper).owner
      p D.instance_method(:m_helper).owner
    RUBY

    _(result).must_answer <<~'OUT'
      :first
      :first
      :first
      :first
      :first
      Kernel
      :second
      :second
      :second
      :second
      :second
      "one"
      Shout
      "two"
      :one
      :own
      :two
      :own
      M
      D
    OUT
  end

  it "module reopen cmeth redefine" do
    result = zr(<<~'RUBY')
      # #517. `module M; def self.X; ...; end; end` re-opened with a
      # second `def self.X` previously emitted two C functions with the
      # same name but possibly-conflicting return types. CRuby's
      # semantics: last definition wins; spinel now replaces the
      # @meth_* row in place when the same `<Mod>_cls_<X>` is seen
      # again (sibling to the class-reopen fix #489).

      module M
        def self.greet
          "first"
        end
      end

      module M
        def self.greet
          "second"
        end
        def self.only_in_reopen
          "extra"
        end
      end

      # Last definition wins.
      puts M.greet
      # Method unique to the reopen is also available.
      puts M.only_in_reopen
    RUBY

    _(result).must_answer "second\nextra\n"
  end

  it "reopen module and class" do
    result = zr(<<~'RUBY')
      # Reopening `Module` and `Class` themselves must work. A class value's
      # own ancestry runs `Class -> Module -> Object`, so a method added by
      # reopening either one registers correctly, like any other builtin
      # reopen.
      #
      # minitest's spec.rb opens with `class Module; def infect_an_assertion ...`
      # and calls it 34 times to build the expectations DSL.
      class Module
        def zr_tag = "mod:#{name}"

        def zr_define(sym)
          class_eval "def #{sym}; :#{sym}_ran; end"
        end
      end

      class Class
        def zr_kind = "class:#{name}"
      end

      module M; end
      class C; end
      class D < C; end

      # Every module and every class answers the Module reopen...
      p M.zr_tag
      p C.zr_tag
      p String.zr_tag
      p Comparable.zr_tag

      # ...and only classes answer the Class reopen.
      p C.zr_kind
      p D.zr_kind
      p Integer.zr_kind
      p M.respond_to?(:zr_kind)

      # A method added to Module is a real instance method of it, so the reflection
      # surface agrees.
      p Module.instance_method(:zr_tag).owner
      p Class.method_defined?(:zr_tag)
      p M.is_a?(Module)

      # The reopened method doing what minitest's does: defining methods on the
      # receiver from a computed string.
      C.zr_define(:greet)
      p C.new.greet

      # A reopen must not displace the builtin surface it sits beside.
      p C.name
      p D.superclass
      p C.instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT'
      "mod:M"
      "mod:C"
      "mod:String"
      "mod:Comparable"
      "class:C"
      "class:D"
      "class:Integer"
      false
      Module
      true
      true
      :greet_ran
      "C"
      C
      [:greet]
    OUT
  end

  it "runtime def on a module reaches its including classes" do
    result = zr(<<~'RUBY')
      module Greet
        def hello = :first
      end

      class Host
        include Greet
      end

      h = Host.new
      p h.hello

      # `module_eval` reaching a MODULE at run time. The including class carries a
      # flattened copy of the module's row, and it has to stop answering here.
      def redefine_by_module_eval
        Greet.module_eval { def hello = :by_module_eval }
      end
      redefine_by_module_eval
      p h.hello

      # `class_eval` on a module is the same door.
      def redefine_by_class_eval
        Greet.class_eval { def hello = :by_class_eval }
      end
      redefine_by_class_eval
      p h.hello

      # ...and so is `define_method`.
      def redefine_by_define_method
        Greet.send(:define_method, :hello) { :by_define_method }
      end
      redefine_by_define_method
      p h.hello

      # A module mixed into a CORE class, which is the shape the bug was found on.
      module Kernel
        def late = :a
      end
      def bump
        Kernel.module_eval { def late = :b }
      end
      p 5.late
      bump
      p 5.late

      # The module itself answers the same body, and a fresh instance agrees with
      # the one made before any of the redefinitions.
      p Host.new.hello
      p Greet.instance_method(:hello).owner
    RUBY

    _(result).must_answer <<~'OUT'
      :first
      :by_module_eval
      :by_class_eval
      :by_define_method
      :a
      :b
      :by_define_method
      Greet
    OUT
  end
end
