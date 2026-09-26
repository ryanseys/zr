# frozen_string_literal: true

require "spec_helper"

describe "Singleton programs" do
  it "class methods take the full param shapes" do
    result = zr(<<~'RUBY')
      class P
        def self.m(a, b = 2, *rest, k: 9, **kw, &blk)
          [a, b, rest, k, kw, blk ? blk.call : nil]
        end
      end
      p P.m(1)
      p P.m(1, 3, 4, 5, k: 0, z: 1) { "blk" }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, [], 9, {}, nil]
      [1, 3, [4, 5], 0, {z: 1}, "blk"]
    OUT
  end

  it "class shift a constant object defines its singleton" do
    result = zr(<<~'RUBY')
      # `class << CONST` on a constant-bound object installs per-object
      # singleton methods on it.

      class Foo
        ANOTHER = Object.new
        class << ANOTHER
          def hi
            "hi"
          end
        end
      end
      puts Foo::ANOTHER.hi
    RUBY

    _(result).must_answer "hi\n"
  end

  it "class shift self constants are visible to the singletons class methods" do
    result = zr(<<~'RUBY')
      # The dominant `class << self` stdlib idiom (e.g.
      # URI's `class << self; RESERVED = ...; def escape; ...RESERVED...; end`)
      # defines constants alongside the class methods that reference them. The
      # constant is spliced onto the enclosing class, whose class methods resolve
      # it lexically (oracle-verified).

      class Config
        class << self
          PREFIX = "cfg:"
          LIMIT = 3
          def key(n); "#{PREFIX}#{n}"; end
          def capped(n); n > LIMIT ? LIMIT : n; end
        end
      end
      puts Config.key("host")
      puts Config.capped(9)
    RUBY

    _(result).must_answer "cfg:host\n3\n"
  end

  it "class shift self defines multiple class methods at once" do
    result = zr(<<~'RUBY')
      class MathUtils
        class << self
          def square(x)
            x * x
          end
          def cube(x)
            x * x * x
          end
        end
      end
      puts MathUtils.square(4)
      puts MathUtils.cube(3)
    RUBY

    _(result).must_answer "16\n27\n"
  end

  it "class singleton class p" do
    result = zr(<<~'RUBY')
      class C; end
      module M; end
      p C.singleton_class?
      p M.singleton_class?
    RUBY

    _(result).must_answer "false\nfalse\n"
  end

  it "constant free singleton body loses its cref" do
    result = zr(<<~'RUBY')
      # A `def` written in a `class << self` body has the SINGLETON as its cref, so
      # a `def` in a block inside it defines an instance method of that singleton --
      # a class method of the enclosing class.
      #
      # The cref a `def` in expression position uses is the body's own
      # `defining_class`, and for a CLASS-METHOD body that is `Scope::lexical_home`
      # -- the singleton's surrogate -- falling back to the class only where no
      # singleton was involved. Reading `defining_class` alone put the nested `def`
      # on the class instead, which is the shape the name of this file records.
      #
      # The constant-bearing twin below is kept beside it: a `class << self` body
      # holding a constant reaches the same answer by a different route, and a fix
      # must not trade one for the other.
      class Bar
        class << self
          def run
            [1].each { def inner = 3 }
          end
        end
      end
      Bar.run
      p Bar.singleton_class.instance_methods(false).sort
      p Bar.public_instance_methods(false).sort

      # The constant-bearing twin.
      class Baz
        class << self
          K = 1
          def run
            [1].each { def inner = 3 }
          end
        end
      end
      Baz.run
      p Baz.singleton_class.instance_methods(false).sort
      p Baz.public_instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT'
      [:inner, :run]
      []
      [:inner, :run]
      []
    OUT
  end

  it "constant in singleton class body" do
    result = zr(<<~'RUBY')
      # A constant assigned inside `class << self` belongs to the SINGLETON class,
      # not to the module the singleton is of. zr stores it on the module.
      #
      #     module M
      #       class << self
      #         SC = 1
      #       end
      #     end
      #     M.const_defined?(:SC, false)                   ruby false  zr true
      #     M.singleton_class.const_defined?(:SC, false)   ruby true   zr false
      #
      # `Module.nesting` shows the same thing from the other side: inside
      # `class << self` ruby reports `["#<Class:M>", "M"]` and zr reports `["M"]`,
      # so the singleton body is not treated as its own lexical scope at all.
      #
      # Reading `SC` from a method defined in that body works either way, which is
      # why it goes unnoticed -- the divergence is visible only to reflection and to
      # anything that asks WHERE the constant lives. Putting private helper constants
      # in `class << self` to keep them off the public module is the idiom this
      # breaks.

      module SingConst
        class << self
          SC = :in_singleton
          def read = SC
          def nesting = Module.nesting.map(&:to_s)
        end
      end

      p SingConst.read
      p SingConst.nesting
      p SingConst.const_defined?(:SC, false)
      p SingConst.singleton_class.const_defined?(:SC, false)
      p SingConst.singleton_class.constants(false)

      class ClsSing
        class << self
          CS = :cls_singleton
          def read = CS
        end
      end
      p ClsSing.read
      p [ClsSing.const_defined?(:CS, false), ClsSing.singleton_class.const_defined?(:CS, false)]

      # An ordinary module body puts it on the module -- already correct.
      module Plain
        PC = :plain
      end
      p [Plain.const_defined?(:PC, false), Plain.singleton_class.const_defined?(:PC, false)]
    RUBY

    _(result).must_answer <<~'OUT'
      :in_singleton
      ["#<Class:SingConst>", "SingConst"]
      false
      true
      [:SC]
      :cls_singleton
      [false, true]
      [true, false]
    OUT
  end

  it "def on an object defines a per object singleton" do
    result = zr(<<~'RUBY')
      # `def obj.name` and `class << obj` install per-object singleton
      # methods (identity-keyed overlay), reaching `@ivar`/`self`/params and
      # answering `respond_to?` only on that object.

      obj = Object.new
      obj.instance_variable_set(:@n, 10)
      def obj.double
        @n * 2
      end
      class << obj
        def plus(k)
          @n + k
        end
      end
      puts obj.double
      puts obj.plus(5)
      puts obj.respond_to?(:double)
      puts obj.respond_to?(:plus)
      puts Object.new.respond_to?(:double)
    RUBY

    _(result).must_answer <<~'OUT'
      20
      15
      true
      true
      false
    OUT
  end

  it "doubled module in a singleton chain" do
    result = zr(<<~'RUBY')
      # A module both INCLUDED and PREPENDED into a class's SINGLETON class holds
      # two positions there, exactly as it does in an instance ancestry -- and its
      # body runs once per position.
      #
      # It took both halves of the class-method channel, and the second is the one
      # that made this a project. The CHAIN had to hold the duplicate: its two areas
      # dedup apart, because `rb_include_module` searches the whole chain and
      # `rb_prepend_module` only the prepend area. And DISPATCH had to have
      # positions to walk, which it did not: a class method resolved through
      # `send_super_class_from`'s three branches over `class_method_prepends`, the
      # extend sources and the flattened `class_methods` tables, never over an
      # ancestry. There was nothing there to hold a module twice, so the second copy
      # re-entered the first and P2 below died of SystemStackError.
      #
      # `dispatch::singleton_walk` is that ancestry now, derived per walk: for each
      # non-module ancestor, its singleton prepends, its own `def self.x` layer, then
      # its extends. `super` resumes past the POSITION the running body occupies --
      # published in a resume cell of its own, since the instance channel indexes a
      # different sequence and a module used both ways would collide with it.
      #
      # Two things about that position are not obvious and both cost a debugging
      # pass. A materialized copy of an extended module's method bakes the class it
      # was materialized ONTO, not the module, so the position it occupies is the
      # first one at or after that class's layer which really answers. And a `super`
      # the COMPILER resolved enters a body the walk also knows a position for, so
      # it has to publish the same one or the walk reaches that body again.
      #
      # The wider sweep is `tests/singleton_chain_dispatch_sweep.rb`.

      module CM
        def hi = "cm(#{defined?(super) ? super : 'top'})"
      end

      class P1
        extend CM
        singleton_class.prepend CM
        def self.hi = "own(#{defined?(super) ? super : 'top'})"
      end
      p P1.singleton_class.ancestors.map(&:to_s)
      p P1.hi

      class P2
        singleton_class.include CM
        singleton_class.prepend CM
      end
      p P2.singleton_class.ancestors.map(&:to_s)
      p P2.hi
    RUBY

    _(result).must_answer <<~'OUT'
      ["CM", "#<Class:P1>", "CM", "#<Class:Object>", "#<Class:BasicObject>", "Class", "Module", "Object", "Kernel", "BasicObject"]
      "cm(own(cm(top)))"
      ["CM", "#<Class:P2>", "CM", "#<Class:Object>", "#<Class:BasicObject>", "Class", "Module", "Object", "Kernel", "BasicObject"]
      "cm(cm(top))"
    OUT
  end

  it "external singleton def" do
    result = zr(<<~'RUBY')
      class D; end
      def D.go; 42; end
      puts D.go

      def D.dbl(x); x * 2; end
      puts D.dbl(21)

      module M; end
      def M.wrap; "[" + yield + "]"; end
      puts M.wrap { "hi" }

      class Box
        def initialize(v); @v = v; end
        def val; @v; end
      end
      def Box.make(v); Box.new(v); end
      puts Box.make(11).val

      class Later
        def self.inside; 1; end
      end
      def Later.outside; inside + 100; end
      puts Later.outside
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      [hi]
      11
      101
    OUT
  end

  it "immediate singleton class" do
    result = zr(<<~'RUBY')
      p nil.singleton_class
      p true.singleton_class
      p false.singleton_class
      begin
        1.singleton_class
      rescue TypeError => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      NilClass
      TrueClass
      FalseClass
      TypeError
    OUT
  end

  it "an attr_accessor in a singleton class body reads from a module method" do
    result = zr(<<~'RUBY')
      module Config
        class << self
          attr_accessor :env_slot
        end
        def self.fetch
          v = env_slot
          v.nil? ? "default" : v
        end
      end
      p Config.fetch
      Config.env_slot = "production"
      p Config.fetch

      class Settings
        class << self
          attr_accessor :level, :tier
        end
        def self.summary
          "#{level} / #{tier}"
        end
      end
      Settings.level = 3
      Settings.tier = "prod"
      puts Settings.summary

      # a bare local assignment stays a local
      class Mix
        class << self
          attr_accessor :slot
        end
        def self.compute
          slot = 99
          slot
        end
      end
      p Mix.compute
    RUBY

    _(result).must_answer <<~'OUT'
      "default"
      "production"
      3 / prod
      99
    OUT
  end

  it "a module that defines self.name answers it, and one that does not answers its own name" do
    result = zr(<<~'RUBY')
      module Foo
        def self.name
          "custom"
        end
      end
      puts Foo.name

      module Bar
        def self.to_s
          "bar-to-s"
        end

        def self.describe
          "#{to_s}/#{name}"
        end
      end
      puts Bar.to_s
      puts Bar.name
      puts Bar.describe

      class Baz
        def self.name
          "baz-name"
        end

        def self.own
          name
        end
      end
      puts Baz.name
      puts Baz.own

      class Plain
      end
      puts Plain.name
    RUBY

    _(result).must_answer <<~'OUT'
      custom
      bar-to-s
      Bar
      bar-to-s/Bar
      baz-name
      baz-name
      Plain
    OUT
  end

  it "mixins across classes modules and singletons" do
    result = zr(<<~'RUBY')
      # The mix-in surface, combinatorially: `include`/`prepend`/`extend` against
      # classes, modules, singleton classes and plain objects, read off `ancestors`,
      # `super` chains, the notification hooks and the reflection predicates.
      #
      # Written 2026-08-21 as a differential sweep against ruby 4.0.7. It found four
      # divergences on its first run, three of them fixed in the same commit series:
      # a singleton `prepend` fired no `prepended` hook, its module landed AFTER the
      # singleton head in `ancestors` instead of before, and
      # `singleton_class.include M` reported itself as `M.extended(K)` rather than
      # `M.included(#<Class:K>)`. The fourth is `tests/gaps/
      # a_module_both_prepended_and_included.rb`, which is why `include A; prepend A`
      # is not among the shapes below.

      module A; end
      module B; end

      puts "-- ancestry, one class, every ordering"
      class I1;  include A;  include B;  end
      class I2;  include A, B;           end
      class P1;  prepend A;  prepend B;  end
      class P2;  prepend A, B;           end
      class M1;  include A;  prepend B;  end
      class M2;  prepend B;  include A;  end
      class M4;  prepend A;  include A;  end   # the include is a no-op: A is already there
      class M5;  include A;  include A;  end
      class M6;  prepend A;  prepend A;  end
      [I1, I2, P1, P2, M1, M2, M4, M5, M6].each do |k|
        puts "#{k}: #{k.ancestors.take_while { |a| a != Object }.map(&:to_s).join(' ')}"
      end

      puts "-- a module that mixes in a module, then joins a class"
      module Inner; end
      module Outer;  include Inner; end
      module POuter; prepend Inner; end
      class Host;  include Outer;  end
      class PHost; include POuter; end
      p Host.ancestors.take_while { |a| a != Object }.map(&:to_s)
      p PHost.ancestors.take_while { |a| a != Object }.map(&:to_s)

      puts "-- super through prepend / class / include / superclass"
      module Pre;  def who = "Pre(#{super})";  end
      module Inc;  def who = "Inc(#{super})";  end
      module Inc2; def who = "Inc2(#{super})"; end
      class SBase; def who = "SBase";          end
      class SKid < SBase
        prepend Pre
        include Inc
        include Inc2
        def who = "SKid(#{super})"
      end
      p SKid.new.who
      p SKid.ancestors.take_while { |a| a != Object }.map(&:to_s)

      module P1x; def tag = "P1(#{super})"; end
      module P2x; def tag = "P2(#{super})"; end
      class T; def tag = "T"; prepend P1x; prepend P2x; end
      p T.new.tag

      puts "-- a prepend reaching super into a module included on the SUPERCLASS"
      module GrandInc; def deep = "GrandInc"; end
      class GBase; include GrandInc; end
      module GPre; def deep = "GPre(#{super})"; end
      class GKid < GBase; prepend GPre; end
      p GKid.new.deep

      puts "-- the singleton side, every spelling"
      module SA; def s = "SA(#{super rescue 'x'})"; end
      module SB; def s = "SB(#{super rescue 'x'})"; end
      class One;  def self.s = "One";  class << self; prepend SA; end; end
      class Two;  def self.s = "Two";  singleton_class.prepend SA;    end
      class Four; def self.s = "Four"; extend SA;                     end
      p [One.s, Two.s, Four.s]
      p Two.singleton_class.ancestors.map(&:to_s).take(3)
      p Four.singleton_class.ancestors.map(&:to_s).take(3)

      class Five; def self.s = "Five"; end
      Five.singleton_class.prepend SA
      Five.singleton_class.prepend SB
      p Five.s, Five.singleton_class.ancestors.map(&:to_s).take(3)

      class Six; def self.s = "Six"; end
      Six.extend SA
      Six.extend SB
      p Six.s, Six.singleton_class.ancestors.map(&:to_s).take(3)

      puts "-- an object's own singleton"
      module OA; def hi = "OA(#{super rescue 'x'})"; end
      class Plain; def hi = "Plain"; end
      o = Plain.new
      o.extend OA
      p o.hi
      p o.singleton_class.ancestors.map(&:to_s).drop(1).take(2)
      p [o.is_a?(OA), Plain.new.is_a?(OA), o.singleton_class.include?(OA)]

      puts "-- every hook, and the argument each receives"
      module H
        def self.included(b)  = puts("included #{b}")
        def self.prepended(b) = puts("prepended #{b}")
        def self.extended(b)  = puts("extended #{b}")
      end
      class C1; include H; end
      class C2; prepend H; end
      class C3; extend  H; end
      class C4; end
      C4.include H
      C4.prepend H
      C4.extend  H
      C4.singleton_class.prepend H
      C4.singleton_class.include H
      module MH; include H; end

      puts "-- multi-arg include notifies in reverse"
      module H2; def self.included(b) = puts("H2 included #{b}"); end
      module H3; def self.included(b) = puts("H3 included #{b}"); end
      class C5; include H2, H3; end

      puts "-- the three primitives run, and their hooks follow"
      module Prim
        def self.append_features(b)  = (puts("append_features #{b}"); super)
        def self.prepend_features(b) = (puts("prepend_features #{b}"); super)
        def self.extend_object(b)    = (puts("extend_object #{b}"); super)
        def self.included(b)  = puts("Prim included #{b}")
        def self.prepended(b) = puts("Prim prepended #{b}")
        def self.extended(b)  = puts("Prim extended #{b}")
        def pm = :pm
      end
      class C6; include Prim; end
      class C7; prepend Prim; end
      class C8; extend  Prim; end
      p [C6.new.pm, C7.new.pm, C8.pm]

      puts "-- reflection agrees with the ancestry"
      module R1; def r = 1; end
      module R2; def r = 2; end
      class RC; include R1; prepend R2; def r = 0; end
      p [RC.include?(R1), RC.include?(R2)]
      p RC.included_modules.take(3).map(&:to_s)
      p [RC.instance_method(:r).owner.to_s, RC.new.method(:r).owner.to_s]
      p [RC.method_defined?(:r), RC.instance_methods(false)]
      p [RC < R1, RC < R2, R1 <=> RC, RC <=> R1]
      p [RC.new.is_a?(R1), RC.new.is_a?(R2), R1 === RC.new]

      puts "-- runtime-minted classes take the same rules"
      RM = Module.new { def q = :rm }
      RK = Class.new  { def q = :rk }
      RK.prepend RM
      p [RK.new.q, RK.ancestors.first.equal?(RM)]
      RK2 = Class.new { def q = :rk2 }
      RK2.include RM
      p RK2.new.q

      puts "-- a LATER include on a module reaches the class already hosting it"
      module Late; end
      module Mid;  end
      class LateHost; include Mid; end
      module Mid; include Late; end
      p LateHost.ancestors.take_while { |a| a != Object }.map(&:to_s)
      p LateHost.new.is_a?(Late)

      puts "-- a frozen target refuses both verbs"
      class FrozenTarget; end
      FrozenTarget.freeze
      begin; FrozenTarget.include R1; rescue => e; p [e.class, e.message]; end
      begin; FrozenTarget.prepend R1; rescue => e; p [e.class, e.message]; end

      puts "-- a module reached both ways holds TWO singleton positions, and order decides"
      # `rb_include_module` searches the whole chain and `rb_prepend_module` only the
      # prepend area, so whichever verb runs FIRST is the one that finds an empty
      # scope. `extend` then `prepend` gives two positions; the reverse gives one.
      module SP
        def sp = "sp"
      end
      class Both1
        extend SP
        singleton_class.prepend SP
      end
      p [Both1.singleton_class.ancestors.map(&:to_s).first(4), Both1.is_a?(SP)]

      class Both2
        singleton_class.include SP
        singleton_class.prepend SP
      end
      p [Both2.singleton_class.ancestors.map(&:to_s).first(4), Both2.is_a?(SP)]

      class Rev1; end
      Rev1.singleton_class.prepend SP
      Rev1.singleton_class.include SP
      p Rev1.singleton_class.ancestors.map(&:to_s).first(3)

      class Rev2; end
      Rev2.singleton_class.prepend SP
      Rev2.extend SP
      p Rev2.singleton_class.ancestors.map(&:to_s).first(3)

      class Twice; end
      Twice.singleton_class.prepend SP
      Twice.singleton_class.prepend SP
      p Twice.singleton_class.ancestors.map(&:to_s).first(3)
    RUBY

    _(result).must_answer <<~'OUT'
      -- ancestry, one class, every ordering
      I1: I1 B A
      I2: I2 A B
      P1: B A P1
      P2: A B P2
      M1: B M1 A
      M2: B M2 A
      M4: A M4
      M5: M5 A
      M6: A M6
      -- a module that mixes in a module, then joins a class
      ["Host", "Outer", "Inner"]
      ["PHost", "Inner", "POuter"]
      -- super through prepend / class / include / superclass
      "Pre(SKid(Inc2(Inc(SBase))))"
      ["Pre", "SKid", "Inc2", "Inc", "SBase"]
      "P2(P1(T))"
      -- a prepend reaching super into a module included on the SUPERCLASS
      "GPre(GrandInc)"
      -- the singleton side, every spelling
      ["SA(One)", "SA(Two)", "Four"]
      ["SA", "#<Class:Two>", "#<Class:Object>"]
      ["#<Class:Four>", "SA", "#<Class:Object>"]
      "SB(SA(Five))"
      ["SB", "SA", "#<Class:Five>"]
      "Six"
      ["#<Class:Six>", "SB", "SA"]
      -- an object's own singleton
      "OA(Plain)"
      ["OA", "Plain"]
      [true, false, true]
      -- every hook, and the argument each receives
      included C1
      prepended C2
      extended C3
      included C4
      prepended C4
      extended C4
      prepended #<Class:C4>
      included #<Class:C4>
      included MH
      -- multi-arg include notifies in reverse
      H3 included C5
      H2 included C5
      -- the three primitives run, and their hooks follow
      append_features C6
      Prim included C6
      prepend_features C7
      Prim prepended C7
      extend_object C8
      Prim extended C8
      [:pm, :pm, :pm]
      -- reflection agrees with the ancestry
      [true, true]
      ["R2", "R1", "Kernel"]
      ["R2", "R2"]
      [true, [:r]]
      [true, true, 1, -1]
      [true, true, true]
      -- runtime-minted classes take the same rules
      [:rm, true]
      :rk2
      -- a LATER include on a module reaches the class already hosting it
      ["LateHost", "Mid", "Late"]
      true
      -- a frozen target refuses both verbs
      [FrozenError, "can't modify frozen Class: FrozenTarget"]
      [FrozenError, "can't modify frozen Class: FrozenTarget"]
      -- a module reached both ways holds TWO singleton positions, and order decides
      [["SP", "#<Class:Both1>", "SP", "#<Class:Object>"], true]
      [["SP", "#<Class:Both2>", "SP", "#<Class:Object>"], true]
      ["SP", "#<Class:Rev1>", "#<Class:Object>"]
      ["SP", "#<Class:Rev2>", "#<Class:Object>"]
      ["SP", "#<Class:Twice>", "#<Class:Object>"]
    OUT
  end

  it "module function is public on the singleton" do
    result = zr(<<~'RUBY')
      # A `module_function` name is TWO rows: a private instance method of the
      # module, and a public method on the module's own singleton. `Kernel.puts`
      # reaches the second.
      #
      # `send_value_public_in` asked only the instance walk, and for a `Class`
      # receiver that walk reads Class/Module's own ancestry -- Kernel included.
      # So it found Kernel's PRIVATE instance row and refused a call CRuby allows.
      # A class-method row answers the call, so it decides the visibility.

      def try(label)
        p [label, yield]
      rescue NoMethodError => e
        p [label, :raised, e.message]
      end

      try(:kernel_format)  { Kernel.public_send(:format, "%d", 7) }
      try(:kernel_send)    { Kernel.send(:format, "%d", 7) }
      try(:math_sqrt)      { Math.public_send(:sqrt, 4.0) }
      try(:class_allocate) { Class.public_send(:allocate).is_a?(Class) }

      module MF
        module_function
        def helper = :helped
      end
      try(:mf_public)      { MF.public_send(:helper) }
      try(:mf_owner)       { MF.instance_method(:helper).owner }

      class WithPriv
        def self.hidden = :hidden
        private_class_method :hidden
        def self.shown = :shown
      end
      try(:priv_cm)        { WithPriv.public_send(:hidden) }
      try(:pub_cm)         { WithPriv.public_send(:shown) }
      try(:priv_via_send)  { WithPriv.send(:hidden) }

      module Ext
        def from_module = :from_module
      end
      class UsesExt
        extend Ext
      end
      try(:extended)       { UsesExt.public_send(:from_module) }
      try(:module_name)    { Comparable.public_send(:name) }
      try(:frozen_q)       { Kernel.public_send(:frozen?) }
    RUBY

    _(result).must_answer <<~'OUT'
      [:kernel_format, "7"]
      [:kernel_send, "7"]
      [:math_sqrt, 2.0]
      [:class_allocate, true]
      [:mf_public, :helped]
      [:mf_owner, MF]
      [:priv_cm, :raised, "private method 'hidden' called for class WithPriv"]
      [:pub_cm, :shown]
      [:priv_via_send, :hidden]
      [:extended, :from_module]
      [:module_name, "Comparable"]
      [:frozen_q, false]
    OUT
  end

  it "module singleton accessor" do
    result = zr(<<~'RUBY')
      # A module value assigned to a module-level
      # `class << self; attr_accessor :x; end` accessor reads back as that
      # module, and a call on the result reaches the module's own method.
      # Each accessor here gets one assignment.

      # 1. Module assigned to a module-level singleton accessor.
      module SqliteAdapter
        def self.answer
          42
        end
      end

      module ActiveRecord
        class << self
          attr_accessor :adapter
        end
      end

      ActiveRecord.adapter = SqliteAdapter
      puts ActiveRecord.adapter.answer    # 42

      # 2. A method on the stored module that returns a String. The
      #    call through the accessor gives the String.
      module Greeter
        def self.greet
          "hello"
        end
      end

      module Service
        class << self
          attr_accessor :greeter
        end
      end

      Service.greeter = Greeter
      puts Service.greeter.greet          # hello

      # 3. Class assigned to a module-level singleton accessor. A call
      #    through the accessor reaches the class method.
      class CounterClass
        def self.count
          7
        end
      end

      module Holder
        class << self
          attr_accessor :counter
        end
      end

      Holder.counter = CounterClass
      puts Holder.counter.count           # 7
    RUBY

    _(result).must_answer <<~'OUT'
      42
      hello
      7
    OUT
  end

  it "module singleton accessor poly" do
    result = zr(<<~'RUBY')
      # A module-level singleton accessor gets two or more different
      # module/class values. Each read gives the value of the last write.

      # 1. Two adapters reassigned — same shape as a Rails-style
      #    runtime adapter swap.
      module SqliteAdapter
        def self.name; "sqlite"; end
      end

      module PgAdapter
        def self.name; "postgres"; end
      end

      module ActiveRecord
        class << self
          attr_accessor :adapter
        end
      end

      ActiveRecord.adapter = SqliteAdapter
      puts ActiveRecord.adapter.name      # sqlite

      ActiveRecord.adapter = PgAdapter
      puts ActiveRecord.adapter.name      # postgres

      ActiveRecord.adapter = SqliteAdapter
      puts ActiveRecord.adapter.name      # sqlite

      # 2. Three candidates, and a conditional assignment picks which
      #    one the accessor holds.
      module A
        def self.tag; "A"; end
      end
      module B
        def self.tag; "B"; end
      end
      module C
        def self.tag; "C"; end
      end

      module Pick
        class << self
          attr_accessor :slot
        end
      end

      [1, 2, 3, 1].each do |n|
        if n == 1
          Pick.slot = A
        elsif n == 2
          Pick.slot = B
        else
          Pick.slot = C
        end
        puts Pick.slot.tag
      end
      # A B C A
    RUBY

    _(result).must_answer <<~'OUT'
      sqlite
      postgres
      sqlite
      A
      B
      C
      A
    OUT
  end

  it "module singleton self accessor" do
    result = zr(<<~'RUBY')
      # `self.<acc>` / `self.<acc> = v` for a module-level singleton accessor
      # (`class << self; attr_accessor`) must resolve to the same storage that
      # `Mod.<acc>` uses. A write through `self` in a module body is kept.

      # self.x = ... in the module body, runs at definition time
      module M
        class << self; attr_accessor :x; end
        self.x = [2, 3]
      end
      p M.x

      # self.x= and self.x inside a module class method
      module N
        class << self; attr_accessor :val; end
        def self.setup; self.val = 41; end
        def self.bump; self.val = self.val + 1; end
      end
      N.setup
      N.bump
      p N.val

      # An explicit `Mod.acc =` works alongside the self form
      module P
        class << self; attr_accessor :data; end
        self.data = "in-body"
      end
      p P.data
      P.data = "after"
      p P.data
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3]
      42
      "in-body"
      "after"
    OUT
  end

  it "a def nested two singleton bodies deep lands on the outer singleton" do
    result = zr(<<~'RUBY')
      # `class << self` inside `class << self` opens the SINGLETON's own singleton --
      # the same construct one level deeper, so it takes the same route one level
      # deeper. Its body becomes a reopen of the `#<Class:self>` surrogate, where a
      # `def` retagged as a class method of the surrogate IS an instance method of
      # `Foo.singleton_class.singleton_class`, which is where ruby puts it.
      #
      # lita spells the corpus's whole cluster this way -- 565 rows behind one file --
      # and its method is `private`, called by the DSL beside it.
      class Authorization
        def self.plain = :plain

        class << self
          class << self
            private

            def define_deprecated(name)
              define_method(name) { "deprecated:#{name}" }
            end
          end

          define_deprecated :add_user
          define_deprecated :remove_user
        end
      end

      p Authorization.add_user
      p Authorization.remove_user
      p Authorization.plain

    RUBY

    _(result).must_answer <<~'OUT'
      "deprecated:add_user"
      "deprecated:remove_user"
      :plain
    OUT
  end

  it "the nested def stays private there, and a receiverless call reaches it" do
    result = zr(<<~'RUBY')
      # `class << self` inside `class << self` opens the SINGLETON's own singleton --
      # the same construct one level deeper, so it takes the same route one level
      # deeper. Its body becomes a reopen of the `#<Class:self>` surrogate, where a
      # `def` retagged as a class method of the surrogate IS an instance method of
      # `Foo.singleton_class.singleton_class`, which is where ruby puts it.
      #
      # lita spells the corpus's whole cluster this way -- 565 rows behind one file --
      # and its method is `private`, called by the DSL beside it.
      class Authorization
        def self.plain = :plain

        class << self
          class << self
            private

            def define_deprecated(name)
              define_method(name) { "deprecated:#{name}" }
            end
          end

          define_deprecated :add_user
          define_deprecated :remove_user
        end
      end

      # The nested `def` lands two levels out, and stays private there. A call with
      # NO receiver is the only way ruby reaches it -- which is what the singleton
      # body beside it writes.
      p Authorization.singleton_class.singleton_class.private_method_defined?(:define_deprecated)
      p Authorization.singleton_class.singleton_class.public_method_defined?(:define_deprecated)
      p Authorization.singleton_class.instance_methods(false).sort

    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      [:add_user, :plain, :remove_user]
    OUT
  end

  it "a receiver the source wrote gets ruby's answer, not the rebound form's" do
    result = zr(<<~'RUBY')
      # `class << self` inside `class << self` opens the SINGLETON's own singleton --
      # the same construct one level deeper, so it takes the same route one level
      # deeper. Its body becomes a reopen of the `#<Class:self>` surrogate, where a
      # `def` retagged as a class method of the surrogate IS an instance method of
      # `Foo.singleton_class.singleton_class`, which is where ruby puts it.
      #
      # lita spells the corpus's whole cluster this way -- 565 rows behind one file --
      # and its method is `private`, called by the DSL beside it.
      class Authorization
        def self.plain = :plain

        class << self
          class << self
            private

            def define_deprecated(name)
              define_method(name) { "deprecated:#{name}" }
            end
          end

          define_deprecated :add_user
          define_deprecated :remove_user
        end
      end

      # A receiver the SOURCE wrote gets ruby's answer, not the rebound form's --
      # only the rebound `self.singleton_class` zr synthesizes for a receiverless
      # call is exempt. (The message names the surrogate a module where ruby names
      # it a class -- see tests/gaps/a_singleton_class_surrogate_is_a_module.rb.)
      begin
        Authorization.singleton_class.define_deprecated(:nope)
      rescue NoMethodError => e
        p e.class
      end

    RUBY

    _(result).must_answer <<~'OUT'
      NoMethodError
    OUT
  end

  it "a public nested def is an ordinary class method of the singleton class" do
    result = zr(<<~'RUBY')
      # `class << self` inside `class << self` opens the SINGLETON's own singleton --
      # the same construct one level deeper, so it takes the same route one level
      # deeper. Its body becomes a reopen of the `#<Class:self>` surrogate, where a
      # `def` retagged as a class method of the surrogate IS an instance method of
      # `Foo.singleton_class.singleton_class`, which is where ruby puts it.
      #
      # lita spells the corpus's whole cluster this way -- 565 rows behind one file --
      # and its method is `private`, called by the DSL beside it.
      class Authorization
        def self.plain = :plain

        class << self
          class << self
            private

            def define_deprecated(name)
              define_method(name) { "deprecated:#{name}" }
            end
          end

          define_deprecated :add_user
          define_deprecated :remove_user
        end
      end

      # A PUBLIC nested def is an ordinary class method of the singleton class, and
      # reflection agrees about its owner.
      class Reflected
        class << self
          class << self
            def maker = :maker
          end
        end
      end
      p Reflected.singleton_class.maker
      p Reflected.singleton_class.method(:maker).owner == Reflected.singleton_class.singleton_class

    RUBY

    _(result).must_answer <<~'OUT'
      :maker
      true
    OUT
  end

  it "a constant written in the nested body is read lexically by the def beside it" do
    result = zr(<<~'RUBY')
      # `class << self` inside `class << self` opens the SINGLETON's own singleton --
      # the same construct one level deeper, so it takes the same route one level
      # deeper. Its body becomes a reopen of the `#<Class:self>` surrogate, where a
      # `def` retagged as a class method of the surrogate IS an instance method of
      # `Foo.singleton_class.singleton_class`, which is where ruby puts it.
      #
      # lita spells the corpus's whole cluster this way -- 565 rows behind one file --
      # and its method is `private`, called by the DSL beside it.
      class Authorization
        def self.plain = :plain

        class << self
          class << self
            private

            def define_deprecated(name)
              define_method(name) { "deprecated:#{name}" }
            end
          end

          define_deprecated :add_user
          define_deprecated :remove_user
        end
      end

      # A constant written in the nested body is read lexically by the `def` beside
      # it, and `RESULT` -- a constant whose value the statement order decides --
      # sees the method the nested body just defined. (WHERE the constant lives is
      # the one-level-deeper form of zr's existing singleton-constant divergence;
      # see tests/gaps/a_nested_singleton_bodys_constant_is_hoisted.rb.)
      class WithConst
        class << self
          class << self
            SUFFIX = "!"
            def shout(s) = s + SUFFIX
          end
          RESULT = shout("hi")
        end
      end
      p WithConst.singleton_class::RESULT

    RUBY

    _(result).must_answer <<~'OUT'
      "hi!"
    OUT
  end

  it "an ordinary class written inside a singleton body ends the run" do
    result = zr(<<~'RUBY')
      # `class << self` inside `class << self` opens the SINGLETON's own singleton --
      # the same construct one level deeper, so it takes the same route one level
      # deeper. Its body becomes a reopen of the `#<Class:self>` surrogate, where a
      # `def` retagged as a class method of the surrogate IS an instance method of
      # `Foo.singleton_class.singleton_class`, which is where ruby puts it.
      #
      # lita spells the corpus's whole cluster this way -- 565 rows behind one file --
      # and its method is `private`, called by the DSL beside it.
      class Authorization
        def self.plain = :plain

        class << self
          class << self
            private

            def define_deprecated(name)
              define_method(name) { "deprecated:#{name}" }
            end
          end

          define_deprecated :add_user
          define_deprecated :remove_user
        end
      end

      # An ordinary `class` written inside a singleton body ENDS the run: its own
      # `class << self` is its own singleton, not the surrogate's.
      class Outer
        class << self
          class Inner
            class << self
              def who = :inners_class_method
            end
          end
          # `Inner` by bare name -- it belongs to the singleton class, which is
          # this method's lexical home, so the bare read resolves while
          # `Outer::Inner` raises.
          def outer_side = Inner.who
        end
      end
      p Outer.outer_side
      p Outer.singleton_class.singleton_class.method_defined?(:who)

    RUBY

    _(result).must_answer <<~'OUT'
      :inners_class_method
      false
    OUT
  end

  it "three singleton bodies deep is the same recursion again" do
    result = zr(<<~'RUBY')
      # `class << self` inside `class << self` opens the SINGLETON's own singleton --
      # the same construct one level deeper, so it takes the same route one level
      # deeper. Its body becomes a reopen of the `#<Class:self>` surrogate, where a
      # `def` retagged as a class method of the surrogate IS an instance method of
      # `Foo.singleton_class.singleton_class`, which is where ruby puts it.
      #
      # lita spells the corpus's whole cluster this way -- 565 rows behind one file --
      # and its method is `private`, called by the DSL beside it.
      class Authorization
        def self.plain = :plain

        class << self
          class << self
            private

            def define_deprecated(name)
              define_method(name) { "deprecated:#{name}" }
            end
          end

          define_deprecated :add_user
          define_deprecated :remove_user
        end
      end

      # Three levels deep is the same recursion again.
      class Deep
        class << self
          class << self
            class << self
              def level3 = :level3
            end
          end
        end
      end
      p Deep.singleton_class.singleton_class.level3
    RUBY

    _(result).must_answer <<~'OUT'
      :level3
    OUT
  end

  it "nested singleton bodys constant is hoisted" do
    result = zr(<<~'RUBY')
      # zr hoists a `class << self` body's constant one level out -- documented in
      # docs/COMPATIBILITY.md, and unchanged since the surrogate was first minted.
      # A NESTED `class << self` body's constant hoists the same one level: ruby
      # homes it on `K.singleton_class.singleton_class`, zr on
      # `K.singleton_class`.
      #
      # The property that carries the corpus is unaffected: the `def` beside it
      # still reads it by bare name, because both live on the same class either way.
      class K
        class << self
          class << self
            SUFFIX = "!"
            def shout(s) = s + SUFFIX
          end
        end
      end
      p K.singleton_class.shout("hi")
      p K.singleton_class.singleton_class.const_defined?(:SUFFIX)
      p K.singleton_class.const_defined?(:SUFFIX)
    RUBY

    _(result).must_answer <<~'OUT'
      "hi!"
      true
      false
    OUT
  end

  it "a dead receiver's singleton method does not follow the address to a later object" do
    result = zr(<<~'RUBY')
      # A singleton method is stored against its receiver's heap identity. Once the
      # receiver dies, an unrelated later object must not inherit it because the
      # allocator handed out the same address again.

      def with_singleton
        s = "victim"
        def s.shout = "SHOUT"
        s
      end

      module Loud
        def volume = 11
      end

      def with_extend
        a = [1, 2, 3]
        a.extend(Loud)
        a
      end

      def with_define_singleton
        h = { k: 1 }
        h.define_singleton_method(:tag) { "tagged" }
        h
      end

      200.times { with_singleton }
      200.times { with_extend }
      200.times { with_define_singleton }
      GC.start

      strays = [0, 0, 0]
      2000.times do
        strays[0] += 1 if ("x" * 6).respond_to?(:shout)
        strays[1] += 1 if [9, 8, 7].respond_to?(:volume)
        strays[2] += 1 if { j: 2 }.respond_to?(:tag)
      end
      p strays

      # The live receivers still answer, which is what the pin has to preserve.
      p with_singleton.shout
      p with_extend.volume
      p with_define_singleton.tag

      # `dup` drops singletons -- a fresh object is a fresh identity.
      kept = with_singleton
      p kept.dup.respond_to?(:shout)
      p kept.respond_to?(:shout)
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 0, 0]
      "SHOUT"
      11
      "tagged"
      false
      true
    OUT
  end

  it "the backtrace frame of a class << self body is spelled 'singleton class'" do
    result = zr(<<~'RUBY')
      # Ruby labels the backtrace frame of a `class << self` body `singleton class`
      # -- a fixed spelling, not a class name. zr homes such a body on a surrogate
      # class under the reserved name `#<Class:self>`, and printed THAT: an internal
      # name, unwritable in ruby, reaching a user's backtrace.
      class Config
        class << self
          [1].each { |n| define_method("m#{n}") { raise "boom" } }
        end
      end

      begin
        Config.m1
      rescue RuntimeError => e
        puts e.backtrace.first
        puts e.message
      end

      # A `def self.x` beside it keeps naming the class, not the singleton.
      class Config
        class << self
          def direct = raise("direct")
        end
      end
      begin
        Config.direct
      rescue RuntimeError => e
        puts e.backtrace.first
      end
    RUBY

    _(result).must_answer <<~'OUT'
      lang/singleton/singleton_test.rb:7:in 'block (2 levels) in singleton class'
      boom
      lang/singleton/singleton_test.rb:21:in 'Config.direct'
    OUT
  end

  it "a spliced statement keeps its own singleton-class frame over the enclosing class body" do
    result = zr(<<~'RUBY')
      # Ruby gives a `class << self` body a backtrace frame of its own, labelled
      # `singleton class`, with the enclosing `<class:Config>` frame beneath it.
      #
      # zr runs the body's statements inside the ENCLOSING class body. A singleton
      # body's locals are shared across the whole of it, so
      # `class << self; x = 1; puts x; end` must see one scope. Each statement
      # still runs under a `singleton class` frame.
      #
      # TWO positions must be right. The frame itself tracks the running
      # statement's line (40, 50 below). The ENCLOSING frame reads the
      # `class << self` KEYWORD's line (39, 49), not the line of the first
      # statement in the body. A block in `Boom` is `block in singleton class`,
      # not `block in <class:Boom>`.
      #
      # The first two bodies below hold a call on `self` (explicit or not) and a
      # statement that does not use `self`. A statement such as a constant write
      # gets the frame only once.
      #
      # A `class << self` written in a METHOD body gets the same frame.

      begin
        class Config
          class << self
            attr_accessor :setting
          end
          class << self
            self.setting = :configured
          end
        end
      rescue NoMethodError => e
        puts e.backtrace.take(3)
      end

      begin
        class Boom
          class << self
            [1].each { |n| raise "boom #{n}" }
          end
        end
      rescue RuntimeError => e
        puts e.backtrace.take(4)
      end

      # A body whose statements are BOTH kinds: a residual one (a CONSTANT, routed
      # into the surrogate and framed by the class body it becomes) between two
      # in-place ones. The run splits in three, and only ever one is on the stack.
      class Mixed
        class << self
          attr_accessor :a
          LIMIT = 3
          [2].each { |n| n }
        end
      end
      Mixed.a = 1
      p [Mixed.a, Mixed.singleton_class.const_get(:LIMIT)]

      begin
        class Mixed
          class << self
            [].fetch(99)
          end
        end
      rescue IndexError => e
        puts e.backtrace.take(2)
      end

      # The frame's LINE tracks the statement that is running, not the one the
      # group started on -- and the body's locals are shared across the whole of
      # it, which is why the statements could not simply be moved.
      begin
        class Walked
          class << self
            x = 1
            y = x + 1
            raise "at #{y}"
          end
        end
      rescue RuntimeError => e
        puts e.message
        puts e.backtrace.take(2)
      end

      # A `class << self` inside a METHOD body, where the frame underneath is the
      # method's rather than a class body's.
      class Late
        def self.install
          class << self
            raise "installing"
          end
        end
      end
      begin
        Late.install
      rescue RuntimeError => e
        puts e.backtrace.take(2)
      end

      # A body in TAIL position, read for its VALUE: the frame block has to be an
      # expression there rather than a statement.
      tail = class Valued
        class << self
          :from_singleton
        end
      end
      p tail
    RUBY

    _(result).must_answer <<~'OUT'
      lang/singleton/singleton_test.rb:27:in 'singleton class'
      lang/singleton/singleton_test.rb:26:in '<class:Config>'
      lang/singleton/singleton_test.rb:22:in '<main>'
      lang/singleton/singleton_test.rb:37:in 'block in singleton class'
      lang/singleton/singleton_test.rb:37:in 'Array#each'
      lang/singleton/singleton_test.rb:37:in 'singleton class'
      lang/singleton/singleton_test.rb:36:in '<class:Boom>'
      [1, 3]
      lang/singleton/singleton_test.rb:60:in 'Array#fetch'
      lang/singleton/singleton_test.rb:60:in 'singleton class'
      at 2
      lang/singleton/singleton_test.rb:75:in 'singleton class'
      lang/singleton/singleton_test.rb:72:in '<class:Walked>'
      lang/singleton/singleton_test.rb:88:in 'singleton class'
      lang/singleton/singleton_test.rb:87:in 'Late.install'
      :from_singleton
    OUT
  end

  it "top level def reachable from instance and class methods" do
    result = zr(<<~'RUBY')
      def helper(x)
        x + 1
      end
      class Widget
        def go
          helper(4)
        end
        def self.direct
          helper(10)
        end
      end
      puts Widget.new.go
      puts Widget.direct
    RUBY

    _(result).must_answer "5\n11\n"
  end

  it "value has no singleton class" do
    result = zr(<<~'RUBY')
      def try = (yield; :ok) rescue [$!.class, $!.message]

      p try { def (2**64).foo; end }
      p try { (2**64).singleton_class }
      p try { 1e300.singleton_class }
      p try { 1.5.singleton_class }
      p try { :sym.singleton_class }
      p try { "lit".freeze.singleton_class }
      p try { (-"dyn#{2}").singleton_class }

      # A def under instance_eval needs the singleton class; anything else
      # the block does runs.
      p try { 1.instance_eval { def foo1 = 1 } }, 2.respond_to?(:foo1)
      p try { (2**64).instance_eval { def foo2 = 1 } }
      p try { (2**64).instance_eval { self } }
      p try { 1e300.instance_eval { def foo3 = 1 } }

      # These have one.
      p try { "dyn#{1}".freeze.singleton_class.class }
      p try { 1r.singleton_class.class }
      p try { nil.singleton_class }
      p try { nil.instance_eval { def nil_x = 1 } }, nil.nil_x

    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "can't define singleton"]
      [TypeError, "can't define singleton"]
      [TypeError, "can't define singleton"]
      [TypeError, "can't define singleton"]
      [TypeError, "can't define singleton"]
      [TypeError, "can't define singleton"]
      [TypeError, "can't define singleton"]
      [TypeError, "can't define singleton"]
      false
      [TypeError, "can't define singleton"]
      :ok
      [TypeError, "can't define singleton"]
      :ok
      :ok
      :ok
      :ok
      1
    OUT
  end
end
