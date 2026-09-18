# frozen_string_literal: true

require "spec_helper"

describe "Singleton: searching and matching" do
  it "extended mode ignores whitespace and comments" do
    result = ze0(<<~'RUBY')
      r = /
        \d+  # a number
        -
        \d+  # another number
      /x
      puts r.match?("123-456")
    RUBY

    _(result).must_answer "true\n"
  end

  it "extended module carries a runtime installed body" do
    result = ze0(<<~'RUBY')
      # A `def` a module installs at RUN TIME -- one whose branch only the run time
      # picks -- is reachable through `extend` exactly as a statically registered
      # one is. fileutils writes the shape: `fu_windows?` is defined inside a
      # `case` on the host os, and the module body then calls it on itself.

      module Platform
        case (defined?(::RbConfig) ? ::RbConfig::CONFIG["host_os"] : ::RUBY_PLATFORM)
        when /mswin|mingw/
          def windows?; true end
        else
          def windows?; false end
        end

        def steady?; :steady end
      end

      module Host
        include Platform
        extend Platform

        # Reached through the singleton chain the `extend` opened, while the
        # module body is still running.
        ANSWER = windows?
        STEADY = steady?
      end

      p Host::ANSWER
      p Host::STEADY
      p Host.windows?
      p Host.steady?

      # The predicate must agree with the call: a name the send answers cannot be
      # one `respond_to?` denies.
      p Host.respond_to?(:windows?)
      p Host.respond_to?(:steady?)
      p Host.singleton_class.ancestors.include?(Platform)

      # The include half serves instances, unchanged.
      class Box
        include Platform
      end
      p Box.new.windows?
      p Platform.instance_methods(false).sort
      p Platform.instance_method(:windows?).owner

      # `extend` on an object, not a module.
      obj = Object.new
      obj.extend(Platform)
      p obj.windows?
      p obj.respond_to?(:windows?)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      :steady
      false
      :steady
      true
      true
      true
      false
      [:steady?, :windows?]
      Platform
      false
      true
    OUT
  end

  it "extended module keeps its visibility" do
    result = ze0(<<~'RUBY')
      # `obj.extend(M)` copies M's instance methods onto the object's singleton and
      # LOSES their visibility marks. A `module_function` name is private on the
      # instance side, so CRuby refuses `obj.extend(MF).public_send(:helper)` and
      # zeo allows it.
      #
      # The cause is a missing dimension, not a wrong rule. The per-object
      # singleton table is `singletons: FMap<usize, FMap<Symbol, MethodImpl>>`
      # (`runtime_meta/mod.rs:239`) -- a name and a body, with nowhere to record
      # whether the row is public, protected or private. `extend_object_default`
      # (`runtime_meta/api.rs:1718`) copies through `module_extendable_method_names`
      # and has nothing to copy the mark into, and `instance_method_visibility` has
      # nothing to read.
      #
      # The class-receiver twin is already right: `class C; extend M; end` puts M in
      # the singleton chain, where `class_method_is_private` walks real ancestors.
      # Only the per-object copy is flat.
      #
      # The fix is a parallel `singleton_vis` map written by `extend_object_default`
      # (from the source module's per-name visibility) and by
      # `runtime_define_singleton_method` (from the visibility cursor), read by
      # `instance_method_visibility` and by the `singleton_methods` /
      # `public_methods` / `private_methods` reflection trio. It is the same shape
      # the memory note calls "the per-object `extend` COPY that no overlay write
      # reaches".
      #
      # Found by widening `a_module_function_is_public_on_the_singleton.rb`, which
      # covers every route that IS right.

      module MF
        module_function
        def helper = :helped
      end

      o = Object.new.extend(MF)
      begin
        p o.public_send(:helper)
      rescue NoMethodError => e
        p [:raised, e.class]
      end
      p o.send(:helper)
      p o.singleton_methods.include?(:helper)
      p o.public_methods(false).include?(:helper)
      p o.private_methods(false).include?(:helper)
    RUBY

    _(result).must_answer <<~'OUT'
      [:raised, NoMethodError]
      :helped
      false
      false
      true
    OUT
  end

  it "extended receiver copies like ruby" do
    result = ze0(<<~'RUBY')
      # How extensions travel across copies: an object's clone carries the
      # singleton class (extended modules and def obj.method rows) and dup
      # drops it; a class's dup AND clone both keep it (rb_mod_init_copy
      # clones the singleton class either way).
      module Ex
        def exx = "exx"
      end
      o = Object.new
      o.extend Ex
      def o.own = "own"
      c = o.clone
      p c.exx
      p c.own
      p c.is_a?(Ex)
      p c.singleton_class.ancestors.include?(Ex)
      d = o.dup
      p d.respond_to?(:exx)
      p d.respond_to?(:own)
      k = Class.new
      k.extend Ex
      kc = k.clone
      p kc.exx
      p kc.is_a?(Ex)
      kd = k.dup
      p kd.respond_to?(:exx)
      p kd.is_a?(Ex)
    RUBY

    _(result).must_answer <<~'OUT'
      "exx"
      "own"
      true
      true
      false
      false
      "exx"
      true
      true
      true
    OUT
  end

  it "five recorded divergences that are not" do
    result = ze0(<<~'RUBY')
      # Five behaviours recorded in comments and docs as known divergences, all
      # of which zeo already answers exactly as ruby 4.0.6 does.
      #
      # Each was fixed at some point and its note left behind, so the record said
      # zeo was less correct than it is. The notes are deleted; these rows are
      # what replaces them, so a regression is caught rather than re-discovered
      # and re-filed.
      #
      #   1. Mixed Integer/Float comparison past 2**53 (docs/ROADMAP.md)
      #   2. A class-level `@x` read through an INHERITED class method
      #      (dispatch/send_value.rs)
      #   3. `UnboundMethod#bind` onto a subclass that overrides the name
      #      (runtime_meta/api.rs)
      #   4. `Struct.new("Name", ...)` namespacing (tests/e2e/variables.rs)
      #   5. A struct constant as a STATIC superclass (builtins/rstruct.rs)

      # 1. Exact, not through `as f64`.
      p 2**53 == (2**53).to_f
      p (2**53 + 1) == (2**53 + 1).to_f
      p 9007199254740993 > 9007199254740992.0
      p [2**53 + 1, 2.0**53].max
      p 1.send(:<, 2**53 + 1)

      # 2. The receiver's own storage, not the ancestor's.
      class Parent
        @x = "parent"
        class << self
          attr_reader :x
        end

        def self.show = @x
      end
      class Child < Parent
        @x = "child"
      end
      p Parent.show
      p Child.show
      p Child.x

      # 3. The OWNER's body, not the target's override.
      class Base
        def m = "base"
      end
      class Derived < Base
        def m = "derived"
      end
      p Base.instance_method(:m).bind(Derived.new).call

      # 4. `Struct::Name`, not a bare top-level `Name`.
      Named = Struct.new("Named", :a)
      p Struct::Named
      p Named.name

      # 5. A struct constant IS a static superclass, in both spellings.
      Point = Struct.new(:x, :y)
      class Sum < Point
        def total = x + y
      end
      p Sum.new(1, 2).total
      p Sum.ancestors.include?(Point)

      class Doubler < Struct.new(:z)
        def twice = z * 2
      end
      p Doubler.new(4).twice
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      9007199254740993
      true
      "parent"
      "child"
      "child"
      "base"
      Struct::Named
      "Struct::Named"
      3
      true
      8
    OUT
  end

  it "singleton class membership" do
    result = ze0(<<~'RUBY')
      # A value IS an instance of its own singleton class. CRuby gets this free --
      # `CLASS_OF(Foo)` literally IS `#<Class:Foo>`, and `#<Class:Sub>` inherits
      # `#<Class:Foo>` in a parallel chain. zeo mints singleton classes on demand, so
      # every reader of the relation has to answer it from the id's OWNER instead.
      #
      # `#class` still reports the real class: CRuby skips singletons there, which is
      # why `instance_of?` says false where `is_a?` says true.

      class Foo
        def self.a = 1
      end
      class Sub < Foo; end
      class Other; end

      sc = Foo.singleton_class

      p Foo.is_a?(sc)
      p Foo.kind_of?(sc)
      p Sub.is_a?(sc)
      p Other.is_a?(sc)
      p Foo.new.is_a?(sc)
      p Sub.is_a?(Sub.singleton_class)
      p Foo.is_a?(Sub.singleton_class)

      # `#class` and `instance_of?` deliberately look past the singleton.
      p Foo.class
      p Foo.instance_of?(sc)
      p Foo.instance_of?(Class)

      # `Module#===` is the same question, so `case` reaches it too.
      p sc === Foo
      p sc === Other
      case Sub
      when sc then puts "Sub matched #<Class:Foo>"
      else puts "no match"
      end

      # An ordinary object's singleton class has exactly one instance -- identity,
      # not equality.
      class Bag
        def initialize(n) = @n = n
        def ==(other) = other.is_a?(Bag)
      end
      a = Bag.new(1)
      b = Bag.new(2)
      p a == b
      p a.is_a?(a.singleton_class)
      p b.is_a?(a.singleton_class)
      p a.singleton_class.equal?(b.singleton_class)

      # ...and the module chain above a singleton class still answers, unchanged.
      p Foo.is_a?(Class)
      p Foo.is_a?(Module)
      p Foo.is_a?(Object)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
      true
      false
      Class
      false
      true
      true
      false
      Sub matched #<Class:Foo>
      true
      true
      false
      false
      true
      true
      true
    OUT
  end

  it "singleton class mixin" do
    result = ze0(<<~'RUBY')
      # `include`/`prepend`/`extend` inside `class << obj` on a PER-INSTANCE
      # singleton -- rdoc's `class << self; prepend Git; end` written inside a method
      # body, spreadsheet's `include Compatibility` inside a `module_eval`, treetop's
      # and tins'.
      #
      # These become `recv.singleton_class.include(M)`, which is not a paraphrase of
      # the mixin but the primitive itself: CRuby DEFINES `obj.extend(M)` as
      # `rb_include_module(rb_singleton_class(obj), M)`. So the runtime routes a
      # mix-in on a minted singleton class straight to the same machinery `extend`
      # already uses, rather than splicing ancestry the owner's dispatch never reads
      # -- which would have made the mixin vanish silently.
      #
      # Two limits of that machinery are pre-existing and reachable through plain
      # `obj.extend(M)` too; they live in tests/gaps/singleton_mixin_super_and_override.rb.

      module Git
        def parse_entries
          "git-entries"
        end
      end

      module Compat
        def helper
          "compat"
        end
      end

      class Parser
        def parse_entries
          "plain"
        end

        def switch!
          class << self
            prepend Git
          end
          self
        end

        def mixin!
          class << self
            include Compat
          end
          self
        end
      end

      a = Parser.new
      p a.parse_entries
      p a.switch!.parse_entries

      # Only THAT object is affected -- the class itself is untouched.
      p Parser.new.parse_entries

      b = Parser.new
      p b.mixin!.helper
      p Parser.new.respond_to?(:helper)

      # Reflection sees the mixin on the singleton.
      p a.singleton_class.include?(Git)

      # The same three verbs on a plain object outside any method body.
      module Tagged
        def tag
          "tagged"
        end
      end

      o = Object.new
      class << o
        include Tagged
      end
      p [o.tag, Object.new.respond_to?(:tag)]

      # `extend` inside `class << obj` reaches one level further out -- the
      # singleton's OWN singleton -- exactly as it does inside `class << self`.
      module Maker
        def build_it
          "built"
        end
      end

      q = Object.new
      class << q
        extend Maker
      end
      p q.singleton_class.build_it
    RUBY

    _(result).must_answer <<~'OUT'
      "plain"
      "git-entries"
      "plain"
      "compat"
      false
      true
      ["tagged", false]
      "built"
    OUT
  end

  it "values singleton class is one object" do
    result = ze0(<<~'RUBY')
      # `v.singleton_class` must answer the SAME object every time. For a value
      # receiver -- a String, an Array, a Hash, a Range, anything not an
      # `Object`-backed instance -- zeo minted a fresh one per call, so `equal?` was
      # false and any state written on it was lost.
      #
      # An `Object.new` receiver was already right, which is what narrowed it to the
      # value side. The cache was there; its KEY was not. `singleton_class_key`
      # answered `None` for everything but an Object and a Class, where the sibling
      # `extend_key` -- the same question about the same receiver -- already keyed
      # every heap value by its address. They are one function now, and
      # `value_identity` covers every `Arc`-backed variant `weak_owner` can pin:
      # Range, Proc, MatchData, Fiber, Enumerator, Thread, Mutex, Queue and Ractor
      # joined the five that were there.
      #
      # The address is safe as a key for the same reason `value_ivars`' is: the row
      # holds its owner, so the allocation cannot be freed and the address cannot be
      # reused while the row lives (`an_ivar_on_a_bare_value_survives_address_reuse.rb`).
      #
      # Found by the sweep for `a_singleton_body_ivar_reaches_the_singleton_class`,
      # where `class << some_string; @tag = "x"; end` then read back nil.
      h = "str"
      h.singleton_class.instance_variable_set(:@t, 1)
      p h.singleton_class.instance_variable_get(:@t)
      p h.singleton_class.equal?(h.singleton_class)

      class << h
        @tag = "on the string's singleton"
      end
      p h.singleton_class.instance_variable_get(:@tag)

      # The `Object` receiver that already works, as the control.
      o = Object.new
      o.singleton_class.instance_variable_set(:@t, 2)
      p o.singleton_class.instance_variable_get(:@t)
      p o.singleton_class.equal?(o.singleton_class)

      # Every heap kind answers one object, and defining on it works.
      [ "s", [1], {a: 1}, (1..2), /x/, proc { 1 }, Thread::Mutex.new, Thread::Queue.new,
        /a/.match("a"), Object.new ].each do |v|
        puts "#{v.class}: #{v.singleton_class.equal?(v.singleton_class)}"
      end

      # A dup is a different object, so it gets a different singleton.
      d = "dup me"
      p d.dup.singleton_class.equal?(d.singleton_class)

      # The state written on one is there through the next ask.
      arr = [1]
      arr.singleton_class.instance_variable_set(:@k, :v)
      p arr.singleton_class.instance_variable_get(:@k)
      def arr.second = self[1]
      p arr.singleton_methods
      p arr.singleton_class.instance_methods(false)

      # An `extend` files its module in the singleton's ancestry.
      module Tag; def tagged = :yes; end
      str = "x"
      str.extend(Tag)
      p [str.tagged, str.is_a?(Tag), str.singleton_class.include?(Tag)]
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      "on the string's singleton"
      2
      true
      String: true
      Array: true
      Hash: true
      Range: true
      Regexp: true
      Proc: true
      Thread::Mutex: true
      Thread::Queue: true
      MatchData: true
      Object: true
      false
      :v
      [:second]
      [:second]
      [:yes, true, true]
    OUT
  end
end
