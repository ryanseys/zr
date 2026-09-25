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
      # Written 2026-08-21 as a differential sweep against ruby 4.0.6. It found four
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

      # The blank lines keep the line numbers that the expected output names.












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
      lang/singleton/singleton_test.rb:40:in 'singleton class'
      lang/singleton/singleton_test.rb:39:in '<class:Config>'
      lang/singleton/singleton_test.rb:35:in '<main>'
      lang/singleton/singleton_test.rb:50:in 'block in singleton class'
      lang/singleton/singleton_test.rb:50:in 'Array#each'
      lang/singleton/singleton_test.rb:50:in 'singleton class'
      lang/singleton/singleton_test.rb:49:in '<class:Boom>'
      [1, 3]
      lang/singleton/singleton_test.rb:73:in 'Array#fetch'
      lang/singleton/singleton_test.rb:73:in 'singleton class'
      at 2
      lang/singleton/singleton_test.rb:88:in 'singleton class'
      lang/singleton/singleton_test.rb:85:in '<class:Walked>'
      lang/singleton/singleton_test.rb:101:in 'singleton class'
      lang/singleton/singleton_test.rb:100:in 'Late.install'
      :from_singleton
    OUT
  end

  it "the class-method channel is the derived singleton chain, swept against ruby" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

    RUBY

    _(result).must_answer ""
  end

  it "one module extended onto a class holds one position, and super reaches the tail" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      puts "== one module, one position, super reaches the tail"
      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end
      p One.tag
      p One.singleton_class.ancestors.map(&:to_s).first(3)
      p One.method(:tag).owner.to_s
      p [One.respond_to?(:tag), One.singleton_methods(false)]

    RUBY

    _(result).must_answer <<~'OUT'
      == one module, one position, super reaches the tail
      "M1(top)"
      ["#<Class:One>", "M1", "#<Class:Object>"]
      "M1"
      [true, []]
    OUT
  end

  it "an own def self.x sits ahead of the module the class extended" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      puts "== an own def self.x sits BEFORE the extended module"
      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      p OwnFirst.tag
      p OwnFirst.method(:tag).owner.to_s
      p OwnFirst.method(:tag).super_method&.owner.to_s

    RUBY

    _(result).must_answer <<~'OUT'
      == an own def self.x sits BEFORE the extended module
      "own(M1(top))"
      "#<Class:OwnFirst>"
      "M1"
    OUT
  end

  it "the last extend is the closest of several" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      puts "== extend order: the LAST extend is closest"
      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end
      p TwoMods.tag
      p TwoMods.singleton_class.ancestors.map(&:to_s).first(4)

    RUBY

    _(result).must_answer <<~'OUT'
      == extend order: the LAST extend is closest
      "M2(M1(top))"
      ["#<Class:TwoMods>", "M2", "M1", "#<Class:Object>"]
    OUT
  end

  it "a module reached by both extend and a singleton prepend holds two positions" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      puts "== a module reached BOTH ways holds two positions"
      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      p BothWays.tag
      p BothWays.singleton_class.ancestors.map(&:to_s).first(4)

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end
      p BothNoOwn.tag
      p BothNoOwn.singleton_class.ancestors.map(&:to_s).first(4)

    RUBY

    _(result).must_answer <<~'OUT'
      == a module reached BOTH ways holds two positions
      "cm(own(cm(top)))"
      ["CM", "#<Class:BothWays>", "CM", "#<Class:Object>"]
      "cm(cm(top))"
      ["CM", "#<Class:BothNoOwn>", "CM", "#<Class:Object>"]
    OUT
  end

  it "the reverse order of those two verbs gives the module one position" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      puts "== the reverse order gives ONE position"
      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM
      p PrependFirst.tag
      p PrependFirst.singleton_class.ancestors.map(&:to_s).first(3)

    RUBY

    _(result).must_answer <<~'OUT'
      == the reverse order gives ONE position
      "cm(top)"
      ["CM", "#<Class:PrependFirst>", "#<Class:Object>"]
    OUT
  end

  it "two singleton prepends stack latest closest, and super walks down them" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      puts "== two prepends stack, latest closest, and super walks down"
      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB
      p Stacked.tag
      p Stacked.singleton_class.ancestors.map(&:to_s).first(4)

    RUBY

    _(result).must_answer <<~'OUT'
      == two prepends stack, latest closest, and super walks down
      "PB(PA(own(top)))"
      ["PB", "PA", "#<Class:Stacked>", "#<Class:Object>"]
    OUT
  end

  it "a module that includes another brings both into the singleton chain" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      puts "== a module that includes another, extended"
      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end
      p Nested.tag
      p Nested.singleton_class.ancestors.map(&:to_s).first(4)
      p Nested.method(:tag).owner.to_s

    RUBY

    _(result).must_answer <<~'OUT'
      == a module that includes another, extended
      "outer(inner(top))"
      ["#<Class:Nested>", "Outer", "Inner", "#<Class:Object>"]
      "Outer"
    OUT
  end

  it "the parent's extend is reached from the child" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      puts "== inheritance: the parent's extend is reached from the child"
      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end
      p [Parent.tag, Child.tag, GrandChild.tag]
      p Child.singleton_class.ancestors.map(&:to_s).first(4)
      p [Parent.method(:tag).owner.to_s, GrandChild.method(:tag).owner.to_s]

    RUBY

    _(result).must_answer <<~'OUT'
      == inheritance: the parent's extend is reached from the child
      ["M1(top)", "M1(top)", "M1(top)"]
      ["#<Class:Child>", "#<Class:Parent>", "M1", "#<Class:Object>"]
      ["M1", "M1"]
    OUT
  end

  it "the child's own extend sits ahead of the parent's" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      puts "== the child adds its own extend, which sits ahead of the parent's"
      class ChildExtends < Parent
        extend M2
      end
      p ChildExtends.tag
      p ChildExtends.singleton_class.ancestors.map(&:to_s).first(5)

    RUBY

    _(result).must_answer <<~'OUT'
      == the child adds its own extend, which sits ahead of the parent's
      "M2(M1(top))"
      ["#<Class:ChildExtends>", "M2", "#<Class:Parent>", "M1", "#<Class:Object>"]
    OUT
  end

  it "a prepend on the parent's singleton is reached by super from the child" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      puts "== a prepend on the PARENT's singleton, reached by super from the child"
      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end
      p [PrependedParent.tag, PrependedChild.tag]
      p PrependedChild.singleton_class.ancestors.map(&:to_s).first(5)

    RUBY

    _(result).must_answer <<~'OUT'
      == a prepend on the PARENT's singleton, reached by super from the child
      ["PA(pp(top))", "pc(PA(pp(top)))"]
      ["#<Class:PrependedChild>", "PA", "#<Class:PrependedParent>", "#<Class:Object>", "#<Class:BasicObject>"]
    OUT
  end

  it "super from the last singleton position reaches Class's own methods" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      puts "== super reaches the instance tail (Class's own methods)"
      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end
      p Tailed.to_s
      p Tailed.name
      p Tailed.inspect

    RUBY

    _(result).must_answer <<~'OUT'
      == super reaches the instance tail (Class's own methods)
      "T(Tailed)"
      "N(Tailed)"
      "Tailed"
    OUT
  end

  it "super with explicit arguments, and a bare super, both pass through a mixin" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      puts "== super with explicit arguments, and zsuper, through a mixin"
      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end
      p ArgHost.build(1)
      p ArgHost.build(1, 3)

    RUBY

    _(result).must_answer <<~'OUT'
      == super with explicit arguments, and zsuper, through a mixin
      "own(over(argmod(1,20)))"
      "own(over(argmod(1,30)))"
    OUT
  end

  it "a prepended module beats define_singleton_method at the same name" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      puts "== define_singleton_method beats a prepended module's copy? no -- prepend wins"
      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }
      p DynHost.tag

    RUBY

    _(result).must_answer <<~'OUT'
      == define_singleton_method beats a prepended module's copy? no -- prepend wins
      "PA(dyn(noSuper))"
    OUT
  end

  it "a class minted at run time takes the same rules" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      puts "== a runtime class takes the same rules"
      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      p RtBase.tag
      RtSub = Class.new(RtBase)
      p RtSub.tag

    RUBY

    _(result).must_answer <<~'OUT'
      == a runtime class takes the same rules
      "rt_own(M1(top))"
      "rt_own(M1(top))"
    OUT
  end

  it "a module has a singleton chain of its own" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      puts "== a MODULE's own singleton chain"
      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end
      p HasSingleton.tag
      p HasSingleton.singleton_class.ancestors.map(&:to_s).first(3)

    RUBY

    _(result).must_answer <<~'OUT'
      == a MODULE's own singleton chain
      "modown(M1(top))"
      ["#<Class:HasSingleton>", "M1", "Module"]
    OUT
  end

  it "remove_method in class << self empties one position, and undef ends the walk" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      puts "== remove_method in class << self empties one position, undef ends the walk"
      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      p Removed.tag
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end
      begin
        Undefed.tag
      rescue NoMethodError
        p "undef ends the walk"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      == remove_method in class << self empties one position, undef ends the walk
      "M1(top)"
      "undef ends the walk"
    OUT
  end

  it "a class-level method_missing is reached through the same chain" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      puts "== a class-level method_missing is reached through the same chain"
      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end
      p Ghosted.ghost
      p Ghosted.respond_to?(:ghost)

    RUBY

    _(result).must_answer <<~'OUT'
      == a class-level method_missing is reached through the same chain
      "mmod_ghost"
      true
    OUT
  end

  it "the instance and class channels answer the same shape independently" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      puts "== instance and class channels answer the same shape independently"
      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end
      p [BothChannels.new.tag, BothChannels.tag]
      p BothChannels.ancestors.first(3).map(&:to_s)
      p BothChannels.singleton_class.ancestors.map(&:to_s).first(3)

    RUBY

    _(result).must_answer <<~'OUT'
      == instance and class channels answer the same shape independently
      ["inst(dual(top))", "cls(dual(top))"]
      ["BothChannels", "Dual", "Object"]
      ["#<Class:BothChannels>", "Dual", "#<Class:Object>"]
    OUT
  end

  it "super_method walks the singleton chain one position per step" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      puts "== #super_method walks the singleton chain, one position per step"
      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      p Chained.tag
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end
      p names

    RUBY

    _(result).must_answer <<~'OUT'
      == #super_method walks the singleton chain, one position per step
      "own(S2(S1))"
      [["#<Class:Chained>", "own(S2(S1))"], ["S2", "S2(S1)"], ["S1", "S1"]]
    OUT
  end

  it "super_method through a doubled module stops instead of looping" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      puts "== #super_method through a DOUBLED module stops instead of looping"
      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end
      p seats

    RUBY

    _(result).must_answer <<~'OUT'
      == #super_method through a DOUBLED module stops instead of looping
      ["CM", "CM"]
    OUT
  end

  it "unbind, bind and instance_method reach through a singleton class" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end

      puts "== unbind/bind and instance_method through a singleton class"
      p Chained.singleton_class.instance_method(:tag).owner.to_s
      p Chained.method(:tag).unbind.owner.to_s
      p Chained.singleton_class.ancestors.map(&:to_s).first(4)

    RUBY

    _(result).must_answer <<~'OUT'
      == unbind/bind and instance_method through a singleton class
      "#<Class:Chained>"
      "#<Class:Chained>"
      ["#<Class:Chained>", "S2", "S1", "#<Class:Object>"]
    OUT
  end

  it "respond_to? and method_defined? agree with the walk" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end


      puts "== respond_to? and method_defined? agree with the walk"
      p [Chained.respond_to?(:tag), Chained.singleton_class.method_defined?(:tag)]
      p [Removed.respond_to?(:tag), Undefed.respond_to?(:tag)]

    RUBY

    _(result).must_answer <<~'OUT'
      == respond_to? and method_defined? agree with the walk
      [true, true]
      [true, false]
    OUT
  end

  it "a frozen class refuses extend and a singleton prepend alike" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      puts "== a frozen class refuses both singleton verbs"
      class FrozenSingleton; end
      FrozenSingleton.freeze
      begin; FrozenSingleton.extend M1; rescue => e; p [e.class, e.message]; end
      begin; FrozenSingleton.singleton_class.prepend M1; rescue => e; p e.class; end

    RUBY

    _(result).must_answer <<~'OUT'
      == a frozen class refuses both singleton verbs
      [FrozenError, "can't modify frozen Class: FrozenSingleton"]
      FrozenError
    OUT
  end

  it "extend on a plain object keeps that object's own chain" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      class FrozenSingleton; end
      FrozenSingleton.freeze

      puts "== extend on a plain OBJECT keeps its own chain"
      obj = Object.new
      module ObjMod
        def tag = "obj(#{defined?(super) ? super : :top})"
      end
      obj.extend ObjMod
      p obj.tag
      p obj.singleton_class.ancestors.map(&:to_s).first(2)
      p obj.method(:tag).owner.to_s

    RUBY

    _(result).must_answer <<~'OUT'
      == extend on a plain OBJECT keeps its own chain
      "obj(top)"
      ["#<Class:#<Object:0xADDR>>", "ObjMod"]
      "ObjMod"
    OUT
  end

  it "a module extended onto a module answers super the same way" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      class FrozenSingleton; end
      FrozenSingleton.freeze

      obj = Object.new
      module ObjMod
        def tag = "obj(#{defined?(super) ? super : :top})"
      end
      obj.extend ObjMod

      puts "== a module extended onto a MODULE, and its super"
      module Extendee
        extend M1
        def self.tag = "modself(#{defined?(super) ? super : :top})"
      end
      p Extendee.tag
      p Extendee.method(:tag).owner.to_s
      p Extendee.method(:tag).super_method&.owner.to_s

    RUBY

    _(result).must_answer <<~'OUT'
      == a module extended onto a MODULE, and its super
      "modself(M1(top))"
      "#<Class:Extendee>"
      "M1"
    OUT
  end

  it "the walk answers the same on every ask" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      class FrozenSingleton; end
      FrozenSingleton.freeze

      obj = Object.new
      module ObjMod
        def tag = "obj(#{defined?(super) ? super : :top})"
      end
      obj.extend ObjMod

      module Extendee
        extend M1
        def self.tag = "modself(#{defined?(super) ? super : :top})"
      end

      puts "== the walk is stable across repeated asks"
      3.times { print Chained.tag, " " }
      puts
      p Chained.singleton_class.ancestors.map(&:to_s).first(4)

    RUBY

    _(result).must_answer <<~'OUT'
      == the walk is stable across repeated asks
      own(S2(S1)) own(S2(S1)) own(S2(S1)) 
      ["#<Class:Chained>", "S2", "S1", "#<Class:Object>"]
    OUT
  end

  it "a def self.x inside a singleton body sits one level further up" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      class FrozenSingleton; end
      FrozenSingleton.freeze

      obj = Object.new
      module ObjMod
        def tag = "obj(#{defined?(super) ? super : :top})"
      end
      obj.extend ObjMod

      module Extendee
        extend M1
        def self.tag = "modself(#{defined?(super) ? super : :top})"
      end


      puts "== a def self.x inside a singleton body is one level FURTHER up"
      class MetaHost
        class << self
          def plain = "plain"
          def self.meta = "meta"
        end
      end
      p MetaHost.plain
      p (MetaHost.meta rescue "MetaHost.meta -> #{$!.class}")
      p MetaHost.singleton_class.meta
      p MetaHost.singleton_class.singleton_methods(false)
      p MetaHost.singleton_methods(false).sort

    RUBY

    _(result).must_answer <<~'OUT'
      == a def self.x inside a singleton body is one level FURTHER up
      "plain"
      "MetaHost.meta -> NoMethodError"
      "meta"
      [:meta]
      [:plain]
    OUT
  end

  it "the same def inside class << obj sits one level further up too" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      class FrozenSingleton; end
      FrozenSingleton.freeze

      obj = Object.new
      module ObjMod
        def tag = "obj(#{defined?(super) ? super : :top})"
      end
      obj.extend ObjMod

      module Extendee
        extend M1
        def self.tag = "modself(#{defined?(super) ? super : :top})"
      end


      class MetaHost
        class << self
          def plain = "plain"
          def self.meta = "meta"
        end
      end

      puts "== the same inside class << obj"
      target = Object.new
      class << target
        def plain = "obj_plain"
        def self.meta = "obj_meta"
      end
      p target.plain
      p (target.meta rescue "target.meta -> #{$!.class}")
      p target.singleton_class.meta

    RUBY

    _(result).must_answer <<~'OUT'
      == the same inside class << obj
      "obj_plain"
      "target.meta -> NoMethodError"
      "obj_meta"
    OUT
  end

  it "a meta method takes arguments and a block like any other" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      class FrozenSingleton; end
      FrozenSingleton.freeze

      obj = Object.new
      module ObjMod
        def tag = "obj(#{defined?(super) ? super : :top})"
      end
      obj.extend ObjMod

      module Extendee
        extend M1
        def self.tag = "modself(#{defined?(super) ? super : :top})"
      end


      class MetaHost
        class << self
          def plain = "plain"
          def self.meta = "meta"
        end
      end

      target = Object.new
      class << target
        def plain = "obj_plain"
        def self.meta = "obj_meta"
      end

      puts "== a meta method takes arguments and a block like any other"
      class MetaArgs
        class << self
          def self.build(a, b = 2) = "build(#{a},#{b})"
          def self.each_twice = [yield(1), yield(2)]
        end
      end
      p MetaArgs.singleton_class.build(9)
      p MetaArgs.singleton_class.build(9, 3)
      p(MetaArgs.singleton_class.each_twice { |i| i * 10 })

    RUBY

    _(result).must_answer <<~'OUT'
      == a meta method takes arguments and a block like any other
      "build(9,2)"
      "build(9,3)"
      [10, 20]
    OUT
  end

  it "a meta method beside a mixin in one singleton body keeps its position" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      class FrozenSingleton; end
      FrozenSingleton.freeze

      obj = Object.new
      module ObjMod
        def tag = "obj(#{defined?(super) ? super : :top})"
      end
      obj.extend ObjMod

      module Extendee
        extend M1
        def self.tag = "modself(#{defined?(super) ? super : :top})"
      end


      class MetaHost
        class << self
          def plain = "plain"
          def self.meta = "meta"
        end
      end

      target = Object.new
      class << target
        def plain = "obj_plain"
        def self.meta = "obj_meta"
      end

      class MetaArgs
        class << self
          def self.build(a, b = 2) = "build(#{a},#{b})"
          def self.each_twice = [yield(1), yield(2)]
        end
      end

      puts "== a meta method beside a mixin in the same singleton body"
      module MetaMix
        def mixed = "mixed"
      end
      class MetaBoth
        class << self
          extend MetaMix
          def self.meta = "meta"
        end
      end
      p MetaBoth.singleton_class.meta
      p MetaBoth.singleton_class.mixed
    RUBY

    _(result).must_answer <<~'OUT'
      == a meta method beside a mixin in the same singleton body
      "meta"
      "mixed"
    OUT
  end

  it "a def in a class << obj body installs on the object, and a private below it marks the singleton" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `class << obj` opens the object's singleton class, which no class row
      # can name: a singleton is minted per object at run time. So each `def`
      # in the body is installed on the object itself, and a `private` run
      # marks the methods below it on the singleton class -- which is exactly
      # how ruby spells a private singleton method.

      class Box
        class << self
          def make(v) = new(v)

          def label = "box"

          def described = "#{label}: #{secret}"

          private

          def secret = :quiet
        end

        def initialize(v)
          @v = v
        end

        attr_reader :v
      end

      p Box.make(3).v
      p Box.label
      p Box.described
      p Box.singleton_methods.sort
      p Box.respond_to?(:secret), Box.respond_to?(:secret, true)
      p Box.singleton_class.private_method_defined?(:secret)

      # A named method retagged where the verb stands, rather than a mode over
      # the lines below it.
      class Later
        class << self
          def one = 1
          def two = 2

          private :two
        end
      end

      p Later.one
      p Later.singleton_methods.sort
      p Later.respond_to?(:two), Later.respond_to?(:two, true)

      # `class << obj` on a plain object touches that object alone.
      one = Object.new
      class << one
        def only_mine = :mine
      end

      p one.only_mine
      p Object.new.respond_to?(:only_mine)
      p one.singleton_methods

      # A singleton method takes arguments and a block like any other.
      class Maker
        class << self
          def build(*parts, sep: "-")
            yield parts.join(sep)
          end
        end
      end

      p Maker.build("a", "b") { |s| s.upcase }
      p Maker.build("a", "b", sep: "+") { |s| s }
      p Maker.method(:build).arity
      # `def obj.name` is `class << obj` with one method in it: the object no
      # compile can know gets the method where the statement stands.
      plain = Object.new

      def plain.greet(who = "you") = "hi #{who}"

      # The body is a LAMBDA, so a `return` leaves the method rather than the
      # block it was built from.
      def plain.early(n)
        return :small if n < 3

        :big
      end

      p plain.greet
      p plain.greet("ada")
      p plain.early(1), plain.early(9)
      p plain.singleton_methods.sort
      p plain.method(:greet).arity
      p plain.method(:greet).parameters
      p plain.respond_to?(:greet)
      p Object.new.respond_to?(:greet)

      # The statement answers the method's name, like any other `def`.
      p(def plain.later = 1)
      p plain.later

      # A class object takes one: that is a class method by another name.
      class Boxed
        def initialize(v) = @v = v
      end

      def Boxed.of(v) = new(v)
      def Boxed.tag = :boxed

      p Boxed.of(3).class
      p Boxed.tag
      p Boxed.singleton_methods.sort

      # `def self.name` inside a block installs on whatever `self` is there,
      # which inside `Module.new` is the new module.
      Made = Module.new do
        def self.built = :made

        def instance_side = :inst
      end

      p Made.built
      p Made.instance_methods(false)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      "box"
      "box: quiet"
      [:described, :label, :make]
      false
      true
      true
      1
      [:one]
      false
      true
      :mine
      false
      [:only_mine]
      "A-B"
      "a+b"
      -1
      "hi you"
      "hi ada"
      :small
      :big
      [:early, :greet]
      -1
      [[:opt, :who]]
      true
      false
      :later
      1
      Boxed
      :boxed
      [:of, :tag]
      :made
      [:instance_side]
    OUT
  end

  it "class << obj on a named object overrides its methods, with super reaching the class" do
    result = zr(<<~'RUBY')
      # `class << obj` (block form of def obj.m) on a statically-traceable object.
      class Widget
        def initialize(n)
          @n = n
        end
        def label
          "w#{@n}"
        end
      end

      W = Widget.new(1)
      class << W
        def label
          "custom-#{super}"
        end
        def extra
          "x"
        end
      end
      p W.label
      p W.extra
      p W.class
      p W.is_a?(Widget)
      p W.instance_of?(Widget)

      # local receiver
      class Thing
        def base
          "b"
        end
      end
      x = Thing.new
      class << x
        def special
          "s-#{base}"
        end
      end
      p x.special

      # constant with a body method reached from the singleton method
      class Config
        def base
          10
        end
      end
      CONFIG = Config.new
      class << CONFIG
        def reload
          "reload-#{base}"
        end
      end
      p CONFIG.reload
    RUBY

    _(result).must_answer <<~'OUT'
      "custom-w1"
      "x"
      Widget
      true
      true
      "s-b"
      "reload-10"
    OUT
  end

  it "prepending onto a singleton class puts the module's instance methods ahead of def self.x" do
    result = zr(<<~'RUBY')
      # `C.singleton_class.prepend(M)` prepends a module onto a class's SINGLETON
      # class, so M's INSTANCE methods become C's CLASS methods at higher priority
      # than C's own `def self.x` -- which they override, with `super` reaching the
      # original. For a whole-program AOT target this is a static structural fact
      # (recorded as `class_method_prepends`, the class-method mirror of `prepends`),
      # resolved through the ordinary flattened class-method tables and the singleton
      # super chain -- no runtime metaprogramming. Oracle-exact.

      # override + super reaching the original class method
      module Hook
        def greet
          "[" + super + "]"
        end
      end
      class Foo
        def self.greet
          "hi"
        end
      end
      Foo.singleton_class.prepend(Hook)
      puts Foo.greet

      # super with an argument passthrough
      module Audit
        def build(x)
          "audit(" + super + ")"
        end
      end
      class Maker
        def self.build(x)
          "made:#{x}"
        end
      end
      Maker.singleton_class.prepend(Audit)
      puts Maker.build("wheel")

      # multiple prepended modules -> a super chain across both, most-recent closest
      module M1
        def tag
          "M1[" + super + "]"
        end
      end
      module M2
        def tag
          "M2[" + super + "]"
        end
      end
      class Svc
        def self.tag
          "svc"
        end
      end
      Svc.singleton_class.prepend(M1)
      Svc.singleton_class.prepend(M2)
      puts Svc.tag

      # full override (the prepended method never calls super)
      module Force
        def mode
          "forced"
        end
      end
      class Engine
        def self.mode
          "stock"
        end
      end
      Engine.singleton_class.prepend(Force)
      puts Engine.mode

      # a NEW class method the module adds (no original to override), alongside an
      # untouched own class method
      module Extra
        def hello
          "hi from extra"
        end
      end
      class Plain
        def self.name_tag
          "plain"
        end
      end
      Plain.singleton_class.prepend(Extra)
      puts Plain.hello
      puts Plain.name_tag
    RUBY

    _(result).must_answer <<~'OUT'
      [hi]
      audit(made:wheel)
      M2[M1[svc]]
      forced
      hi from extra
      plain
    OUT
  end

  it "a singleton class's superclass is the superclass's singleton class" do
    result = zr(<<~'RUBY')
      # A singleton class's superclass is the singleton class of the superclass:
      #
      #     String.singleton_class.superclass  #=> #<Class:Object>
      #
      # zr answers `Class`, collapsing the parallel hierarchy to its base. That
      # chain is what makes class methods inherit -- `Sub.some_class_method` resolves
      # by walking `#<Class:Sub>` -> `#<Class:Base>` -> ... -> `Class` -- so a flat
      # answer describes an inheritance that is not the one actually used.
      #
      # Class-method inheritance itself already WORKS in zr (the `Sub.f` line
      # below), so the walk is right and only its reflection is wrong. Anything that
      # reasons about the chain rather than calling through it -- a library deciding
      # where to install a class method, `ancestors` on a singleton class -- reads
      # the wrong shape.

      p String.singleton_class.superclass
      p Object.singleton_class.superclass
      p BasicObject.singleton_class.superclass

      class Base; def self.f = :base_f; end
      class Sub < Base; end
      p Sub.f
      p Sub.singleton_class.superclass
      p Sub.singleton_class.ancestors.first(3)

      o = Object.new
      p o.singleton_class.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      #<Class:Object>
      #<Class:BasicObject>
      Class
      :base_f
      #<Class:Base>
      [#<Class:Sub>, #<Class:Base>, #<Class:Object>]
      Object
    OUT
  end

  it "a singleton-class constant survives a reopen, reads the enclosing scope, and hides from outside" do
    result = zr(<<~'RUBY')
      # Singleton-class constants (`class << self` surrogates) beyond the promoted
      # gap shape: reopens, enclosing-scope reads, nesting depth, and the reach
      # rules from outside the singleton body.

      # The enclosing module's OWN constants stay readable from the singleton body
      # (it sits in the lexical nesting), and the singleton's shadow the module's.
      module Outer
        PLAIN = :module_const
        SHADOWED = :from_module
        class << self
          SC = :singleton_const
          SHADOWED = :from_singleton
          def both = [SC, PLAIN, SHADOWED]
        end
      end
      p Outer.both

      # A class method defined OUTSIDE the `class << self` body cannot reach the
      # singleton's constant by bare name.
      module Outer
        def self.blind
          SC
        rescue NameError
          :name_error
        end
      end
      p Outer.blind

      # A second `class << self` body reopens the SAME singleton class -- its
      # constants join the first body's.
      module Outer
        class << self
          SC2 = :second_body
          def pair = [SC, SC2]
        end
      end
      p Outer.pair
      p Outer.singleton_class.constants(false).sort

      # Nested modules: the surrogate sits inside the full lexical chain, so a
      # singleton body in `A::B` reads A's constants too.
      module A
        ROOT = :a_const
        module B
          class << self
            INNER = :inner
            def chain = [INNER, ROOT]
            def nest = Module.nesting.map(&:to_s)
          end
        end
      end
      p A::B.chain
      p A::B.nest

      # Reflection through the singleton value: the constant is reachable with
      # const_get on the singleton class, and invisible from the module itself.
      p Outer.singleton_class.const_get(:SC)
      p [Outer.const_defined?(:SC), Outer.singleton_class.const_defined?(:SC)]
    RUBY

    _(result).must_answer <<~'OUT'
      [:singleton_const, :module_const, :from_singleton]
      :name_error
      [:singleton_const, :second_body]
      [:SC, :SC2, :SHADOWED]
      [:inner, :a_const]
      ["#<Class:A::B>", "A::B", "A"]
      :singleton_const
      [false, true]
    OUT
  end

  it "a bare private does not reach a following def self.x, which stays public" do
    result = zr(<<~'RUBY')
      # A bare `private` sets the default only for subsequent INSTANCE defs; a
      # singleton def (`def self.name` / `def Recv.name`) that follows is a
      # method on another object and stays public. net/protocol's
      # `private; def Protocol.protocol_param` is this shape.

      class Proto
        private
        def Proto.cls_param; "cls_ok"; end
        def self.self_param; "self_ok"; end
        def inst; "inst"; end
      end
      puts Proto.cls_param
      puts Proto.self_param
      begin
        Proto.new.inst
      rescue NoMethodError
        puts "inst_private"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      cls_ok
      self_ok
      inst_private
    OUT
  end

  it "a singleton method belongs to the object, so an Array or a String takes one and an Integer refuses" do
    result = zr(<<~'RUBY')
      # A singleton method belongs to the OBJECT, and in Ruby that includes any heap
      # value -- csv defines `def NO_QUOTED_FIELDS.[](i)` on a bare Array.
      NO_QUOTED = []
      def NO_QUOTED.[](_index) = false
      NO_QUOTED.freeze
      p NO_QUOTED[0], NO_QUOTED[99]
      p NO_QUOTED.size, NO_QUOTED.frozen?, NO_QUOTED.respond_to?(:[])

      # It is per-OBJECT, so a sibling of the same class is untouched.
      p [].respond_to?(:shout)
      s = +"hello"
      def s.shout = upcase + "!"
      p s.shout, s.length, s.class
      p (+"hello").respond_to?(:shout)

      h = {}
      h.define_singleton_method(:fetch_or) { |k| self[k] || :none }
      p h.fetch_or(:x)
      h[:x] = 1
      p h.fetch_or(:x)
      p h.singleton_methods

      # An immediate has no identity to attach one to, which is why Ruby refuses.
      begin
        1.define_singleton_method(:nope) { }
      rescue TypeError => e
        puts e.message
      end

      # ...but nil/true/false each have exactly one instance, so their singleton
      # class IS their class and Ruby accepts it there.
      nil.define_singleton_method(:blank?) { true }
      p nil.blank?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      0
      true
      true
      false
      "HELLO!"
      5
      String
      false
      :none
      1
      [:fetch_or]
      can't define singleton
      true
    OUT
  end

  it "a module prepended into a singleton wins the lookup, and Method#owner names it bare" do
    result = zr(<<~'RUBY')
      # A module prepended into a singleton class WINS the class-method lookup, so
      # `super` inside it reaches the class's own `def self.x` and `Method#owner`
      # names the module.
      #
      # zr flattens a singleton prepend: the module's body becomes the class's
      # winning class-method row and the class's own `def self.x` becomes that
      # row's super target. Two reflection answers have to say what ruby says in
      # spite of the flattening -- `defined?(super)`, which asked the CLASS's
      # instance ancestry (`Class`, holding no `def self.x`, so always nil), and
      # `#owner`, whose scan correctly finds the host the row sits on.
      #
      # A module reached through the singleton chain is named BARE, the same rule
      # an `extend`ed module already followed: only a real `def self.x` is reported
      # as owned by a singleton class.
      module SA
        def s = "SA(#{defined?(super) ? super : 'top'})"
      end
      module SB
        def s = "SB(#{defined?(super) ? super : 'top'})"
      end

      # The call form.
      class Runtime
        def self.s = "Runtime"
      end
      Runtime.singleton_class.prepend(SB)
      p Runtime.s
      p Runtime.method(:s).owner.to_s
      p Runtime.singleton_class.instance_method(:s).owner.to_s

      # The `class << self` form.
      class Written
        def self.s = "Written"
        class << self
          prepend SB
        end
      end
      p Written.s
      p Written.method(:s).owner.to_s

      # Two modules stack, and the second prepend runs first.
      class Stacked
        def self.s = "Stacked"
      end
      Stacked.singleton_class.prepend(SA)
      Stacked.singleton_class.prepend(SB)
      p Stacked.s
      p Stacked.method(:s).owner.to_s

      # An `extend` behind the class's own definition still loses, and its owner
      # is reported bare for the same reason.
      class Mixed
        extend SA
      end
      p Mixed.s
      p Mixed.method(:s).owner.to_s

      # Nothing prepended: the owner is the singleton class itself.
      class Plain
        def self.s = "Plain"
      end
      p Plain.method(:s).owner.to_s
      p Plain.singleton_class.instance_method(:s).owner.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "SB(Runtime)"
      "SB"
      "SB"
      "SB(Written)"
      "SB"
      "SB(SA(Stacked))"
      "SB"
      "SA(top)"
      "SA"
      "#<Class:Plain>"
      "#<Class:Plain>"
    OUT
  end

  it "the same prepend works on a Class.new receiver, and a subclass sees it through the ancestor walk" do
    result = zr(<<~'RUBY')
      # `X.singleton_class.prepend(M)` where X only ever exists at RUNTIME (a
      # `Class.new` minting -- the same shape as a rails class behind a computed
      # autoload): M's instance methods become X's class methods ABOVE X's own
      # `def self.x`, and `super` from one resumes at the shadowed definition.
      # The compile-time ancestry edit cannot name X, so this exercises the runtime
      # layer (`prepend_into_class_singleton` + the prepend-aware `super` resume);
      # a statically-registered receiver still takes the compile-time edit instead.
      # The subclass call checks the prepend is visible through inheritance -- the
      # ancestor walk finds the prepend layer at the parent's position.
      K = Class.new do
        def self.hi = "orig"
      end
      module Patch
        def hi = "patched-" + super
        def extra = "extra"
      end
      K.singleton_class.prepend(Patch)
      p K.hi
      p K.extra
      p K.respond_to?(:extra)
      Sub = Class.new(K)
      p Sub.hi
    RUBY

    _(result).must_answer <<~'OUT'
      "patched-orig"
      "extra"
      true
      "patched-orig"
    OUT
  end

  it "a subclass inherits its parent's singleton prepend for dispatch as well as reflection" do
    result = zr(<<~'RUBY')
      # A module prepended into a SINGLETON class, reached from every direction a
      # subclass chain gives it.
      #
      # zr has no singleton-class objects: a class method resolves through the
      # `class_method_prepends` stack, the extend sources and the flattened
      # `class_methods` tables. Three things that model got wrong, and each needed a
      # different half of the answer.
      #
      # `defined?(super)` and the `super` WALK disagreed. The probe scanned from the
      # target's own position, which INCLUDES the module prepended into its
      # singleton, while the walk skips that layer -- it got there THROUGH it. A
      # prepended module with no row beneath it therefore reported a super target
      # and then raised looking for it. One resolution serves both now.
      #
      # A SUBCLASS did not inherit its parent's singleton prepend for DISPATCH, only
      # for reflection: `prepended_class_methods` is keyed on the class the
      # `prepend` named, and the flat probe found the parent's own `def self.x`
      # instead -- which sits BEHIND the module in ruby's chain.
      #
      # And a prepend on an ANCESTOR was unreachable by `super` from a prepend on
      # the subclass, because materialization flattens an inherited `def self.x`
      # onto every descendant's table and the walk took the nearest copy. Only the
      # OWN-set can tell a class's real definition from the copy it was given.

      module L1
        def tag = "L1(#{defined?(super) ? super : 'top'})"
      end
      module L2
        def tag = "L2(#{defined?(super) ? super : 'top'})"
      end

      # A prepend with nothing beneath it: `defined?(super)` is false, and the
      # fallback branch runs rather than raising.
      class A1
        singleton_class.prepend L1
      end
      p A1.tag

      # ... and with the host's own row beneath it.
      class A2
        def self.tag = "own"
        singleton_class.prepend L1
      end
      p A2.tag

      # A subclass inherits the prepend, at its parent's position in the chain.
      class B0
        def self.tag = "B0"
      end
      class B1 < B0; end
      class B2 < B1; end
      B0.singleton_class.prepend L1
      p [B0.tag, B1.tag, B2.tag]

      # A prepend on the SUBCLASS resumes into the one on the ancestor.
      B2.singleton_class.prepend L2
      p [B0.tag, B1.tag, B2.tag]
      p B2.singleton_class.ancestors.first(5).map(&:to_s)

      # A subclass's OWN `def self.x` still outranks an ancestor's prepend, and its
      # `super` reaches it.
      class B3 < B0
        def self.tag = "B3(#{super})"
      end
      p B3.tag
      p B3.singleton_class.ancestors.first(4).map(&:to_s)

      # An `extend` of the same module is a different layer, and the two orders
      # answer differently.
      class C1
        extend L1
      end
      p C1.tag
      class C2
        def self.tag = "own2"
        extend L1
      end
      p C2.tag

      # The walk's tail is `Class`'s own instance methods.
      class D1
        def self.to_s = "d1(" + super + ")"
      end
      p D1.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "L1(top)"
      "L1(own)"
      ["L1(B0)", "L1(B0)", "L1(B0)"]
      ["L1(B0)", "L1(B0)", "L2(L1(B0))"]
      ["L2", "#<Class:B2>", "#<Class:B1>", "L1", "#<Class:B0>"]
      "B3(L1(B0))"
      ["#<Class:B3>", "L1", "#<Class:B0>", "#<Class:Object>"]
      "L1(top)"
      "own2"
      "d1(D1)"
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
