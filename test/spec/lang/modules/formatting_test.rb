# frozen_string_literal: true

require "spec_helper"

describe "Modules: formatting and inspection" do
  it "bare module body cmethod call" do
    result = ze0(<<~'RUBY')
      # Bare (receiverless) class-method call in a module/class body must propagate
      # the callee's return type to the call expression.
      #
      # `def self.mk` returns a typed hash; called bare as `mk` (not `M.mk`) in the
      # module body and passed as an argument, its result previously typed `void` --
      # the bare-call resolution read the scope-pass-only global g_cbody_class_id
      # (unset during the inference fixpoint) instead of the per-node enclosing-cbody
      # (node_cbody[id]). The void arg then made `take`'s param unknown and the call
      # miscompiled (`error: variable or field declared void`). Now it resolves via
      # node_cbody[id], so `take(mk)` sees a Hash[String,String].

      module M
        def self.mk
          h = {"" => ""}
          h.delete("")
          h["a"] = "1"
          h
        end

        class R
          def take(opts)
            n = 0
            opts.each { |k, v| n = n + 1 }
            n
          end
        end

        COUNT = R.new.take(mk)   # bare `mk`; result must be Hash[String,String], not void
      end

      puts M::COUNT.to_s         # 1
    RUBY

    _(result).must_answer "1\n"
  end

  it "class hierarchy module" do
    result = ze0(<<~'RUBY')
      # Issue #404 Phase 3 Tier 2. Modules in the unified cls_id
      # space + woven into ancestors via the @cls_includes pass.
      #
      # Coverage:
      #   - module constant in value position (Greeting / Comparable
      #     lookalike) lowers to a sp_Class with the unified cls_id.
      #   - <class>.ancestors weaves included modules in include-reverse
      #     order followed by the parent chain.
      #   - <class> <= <module> checks via the ancestors table.
      #   - <class> == <module> never holds (different cls_ids).

      module Greeting
        def hello
          "hello"
        end
      end

      module Politeness
        def please
          "please"
        end
      end

      class Base
      end

      class Polite < Base
        include Greeting
        include Politeness
      end

      # Module name as value -- compiles to sp_Class with unified cls_id.
      m = Greeting
      puts m.to_s          # => Greeting

      # Ancestors include the modules in include-reverse order.
      def names_of(arr)
        out = ""
        arr.each do |klass|
          out += "," unless out.length == 0
          out += klass.to_s
        end
        out
      end

      puts names_of(Polite.ancestors)
      # => Polite,Politeness,Greeting,Base,Object,Kernel,BasicObject

      # <= check on a module via the ancestors table.
      puts (Polite <= Greeting) ? "polite<=Greeting" : "polite!<=Greeting"
      puts (Polite <= Politeness) ? "polite<=Politeness" : "polite!<=Politeness"
      puts (Base <= Greeting) ? "base<=Greeting" : "base!<=Greeting"

      # Equality: a class is never == its included module.
      puts (Polite == Greeting) ? "eq" : "neq"
    RUBY

    _(result).must_answer <<~'OUT'
      Greeting
      Polite,Politeness,Greeting,Base,Object,Kernel,BasicObject
      polite<=Greeting
      polite<=Politeness
      base!<=Greeting
      neq
    OUT
  end

  it "class name collision across modules" do
    result = ze0(<<~'RUBY')
      # Same leaf-name classes in different modules must stay distinct. They share a
      # flat sp_<Name> C namespace keyed by the leaf name, so before the qualifying
      # pass `Web::Response` and `Chat::Response` collapsed onto one struct + method
      # set (the last `initialize` won), leaving the other class's ivars unset -- the
      # seed-then-delete `@cookies` here would be NULL and `push` would SIGSEGV.
      # Each class must get its own module-qualified identity, while a genuine reopen
      # of the same qualified class still merges.
      module Web
        class Response
          def initialize
            @cookies = [""]        # seed to pin the str_array element type
            @cookies.delete_at(0)  # then empty it
          end
          def add(c)
            @cookies.push(c)
          end
          def first
            @cookies[0]
          end
        end
      end

      # Reopening Web::Response (same qualified name) must MERGE, not create a new class.
      module Web
        class Response
          def tag
            "web"
          end
        end
      end

      module Chat
        class Response
          def initialize
            @content = "hi"
          end
          def content
            @content
          end
        end
      end

      module Llm
        module Inner
          class Response
            def initialize
              @x = 3
            end
            def x
              @x
            end
          end
        end
      end

      r = Web::Response.new
      r.add("sid")
      puts r.first              # sid  (cookies array was allocated, not NULL)
      puts r.tag               # web  (reopen merged in)
      puts Chat::Response.new.content      # hi   (distinct class)
      puts Llm::Inner::Response.new.x.to_s # 3    (3-deep distinct class)

      # A bare class reference inside a module body resolves lexically.
      module Web
        class User
          def go
            Response.new.tag   # bare Response -> Web::Response
          end
        end
      end
      puts Web::User.new.go    # web
    RUBY

    _(result).must_answer <<~'OUT'
      sid
      web
      hi
      3
      web
    OUT
  end

  it "class self body mixin keeps the metaclass chain" do
    result = ze0(<<~'RUBY')
      # A mixin written inside a `class << self` body reaches the singleton class,
      # and a singleton class's ancestry is ruby's parallel METACLASS chain --
      # `#<Class:Object>`, `#<Class:BasicObject>`, `Class`, `Module` -- not the
      # ordinary `Object`-rooted one.
      #
      # `class << self`'s three mixin verbs mean three different things:
      #
      #   include M   mixes M into the singleton class, so M's instance methods
      #               become the enclosing class's CLASS methods, behind its own.
      #               zeo lowers it to `extend M`, which is ruby's own meaning.
      #   prepend M   the same, AHEAD of the class's own `def self.x`.
      #   extend M    mixes M into the SINGLETON's singleton, one level further
      #               out, so it is a run-time send rather than an ancestry edit.
      #
      # A subclass carries its parent's whole singleton LAYER, not just the
      # parent's singleton class: `Child < Inc` lists `SA` between `#<Class:Inc>`
      # and `#<Class:Object>`.
      module SA
        def s = "SA(#{defined?(super) ? super : 'top'})"
      end
      module SB
        def s = "SB(#{defined?(super) ? super : 'top'})"
      end

      class Bare; end
      p Bare.singleton_class.ancestors.map(&:to_s)

      class Inc
        def self.s = "Inc"
        class << self
          include SA
        end
      end
      p Inc.s
      p Inc.singleton_class.include?(SA)
      p Inc.singleton_class.ancestors.map(&:to_s)
      p Inc.singleton_class.instance_methods(false).sort

      class Pre
        def self.s = "Pre"
        class << self
          prepend SA
        end
      end
      p Pre.s
      p Pre.singleton_class.include?(SA)
      p Pre.singleton_class.ancestors.map(&:to_s)

      class Both
        def self.s = "Both"
        class << self
          include SA
          prepend SB
        end
      end
      p Both.s
      p Both.singleton_class.ancestors.map(&:to_s)

      # The call form of the same two mixins builds the same ancestry.
      class Called
        def self.s = "Called"
      end
      Called.singleton_class.include(SA)
      Called.singleton_class.prepend(SB)
      p Called.singleton_class.ancestors.map(&:to_s)

      # A subclass sees its own metaclass chain continue through the PARENT's.
      class Child < Inc; end
      p Child.s
      p Child.singleton_class.ancestors.map(&:to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      ["#<Class:Bare>", "#<Class:Object>", "#<Class:BasicObject>", "Class", "Module", "Object", "Kernel", "BasicObject"]
      "Inc"
      true
      ["#<Class:Inc>", "SA", "#<Class:Object>", "#<Class:BasicObject>", "Class", "Module", "Object", "Kernel", "BasicObject"]
      [:s]
      "SA(Pre)"
      true
      ["SA", "#<Class:Pre>", "#<Class:Object>", "#<Class:BasicObject>", "Class", "Module", "Object", "Kernel", "BasicObject"]
      "SB(Both)"
      ["SB", "#<Class:Both>", "SA", "#<Class:Object>", "#<Class:BasicObject>", "Class", "Module", "Object", "Kernel", "BasicObject"]
      ["SB", "#<Class:Called>", "SA", "#<Class:Object>", "#<Class:BasicObject>", "Class", "Module", "Object", "Kernel", "BasicObject"]
      "Inc"
      ["#<Class:Child>", "#<Class:Inc>", "SA", "#<Class:Object>", "#<Class:BasicObject>", "Class", "Module", "Object", "Kernel", "BasicObject"]
    OUT
  end

  it "class under an anonymous module is named for now" do
    result = ze0(<<~'RUBY')
      # A class set as a constant of an anonymous module takes a temporary
      # name under the module's #<Module:0x...>; when the module is named,
      # everything it holds takes its name for good.
      def name_of(mod) = mod.name&.gsub(/0x\h+/, "0xXX")

      m = Module.new
      m::K = Class.new
      class m::Inner; end
      module m::Deep; end
      m::Deep.const_set(:Leaf, Class.new)
      p name_of(m::K), name_of(m::Inner), name_of(m::Deep), name_of(m::Deep::Leaf)
      p m::K.inspect.gsub(/0x\h+/, "0xXX")

      Named = m
      p m::K.name, m::Inner.name, m::Deep.name, m::Deep::Leaf.name

      # A class that already has a name keeps it.
      class Kept; end
      n = Module.new
      n::Alias = Kept
      Other = n
      p Kept.name, n::Alias.name
    RUBY

    _(result).must_answer <<~'OUT'
      "#<Module:0xXX>::K"
      "#<Module:0xXX>::Inner"
      "#<Module:0xXX>::Deep"
      "#<Module:0xXX>::Deep::Leaf"
      "#<Module:0xXX>::K"
      "Named::K"
      "Named::Inner"
      "Named::Deep"
      "Named::Deep::Leaf"
      "Kept"
      "Kept"
    OUT
  end

  it "mixin multi arg ordering" do
    result = ze0(<<~'RUBY')
      # A single multi-argument `include`/`prepend` keeps its arguments in SOURCE
      # order in the resulting ancestry, which is the OPPOSITE of what separate
      # statements produce:
      #
      #   include A, B      -> [self, A, B]      prepend A, B      -> [A, B, self]
      #   include A; include B -> [self, B, A]   prepend A; prepend B -> [B, A, self]
      #
      # zeo's mro flattens the registered mixin list with a uniform
      # "later-registered-is-closer" reversal (correct for the separate-statement
      # case), so a single multi-arg statement registers its modules in reverse to
      # come out in source order. Verified against ruby for the class-body form, the
      # `C.prepend(A, B)` call form, and dispatch through the chain via `super`.

      module A
        def who
          "A[" + (defined?(super) ? super : "_") + "]"
        end
      end
      module B
        def who
          "B[" + (defined?(super) ? super : "_") + "]"
        end
      end

      class InclBody
        include A, B
        def who
          "InclBody"
        end
      end
      puts InclBody.ancestors.first(3).inspect
      puts InclBody.new.who

      class PrepBody
        prepend A, B
        def who
          "PrepBody"
        end
      end
      puts PrepBody.ancestors.first(3).inspect
      puts PrepBody.new.who

      class PrepCall
        def who
          "PrepCall"
        end
      end
      PrepCall.prepend(A, B)
      puts PrepCall.ancestors.first(3).inspect
      puts PrepCall.new.who

      # Separate statements: later one is closest (unchanged by the ordering fix).
      class SepPrep
        def who
          "SepPrep"
        end
      end
      SepPrep.prepend(A)
      SepPrep.prepend(B)
      puts SepPrep.ancestors.first(3).inspect
      puts SepPrep.new.who

      class SepIncl
        def who
          "SepIncl"
        end
      end
      SepIncl.include(A)
      SepIncl.include(B)
      puts SepIncl.new.who
    RUBY

    _(result).must_answer <<~'OUT'
      [InclBody, A, B]
      InclBody
      [A, B, PrepBody]
      A[B[PrepBody]]
      [A, B, PrepCall]
      A[B[PrepCall]]
      [B, A, SepPrep]
      B[A[SepPrep]]
      SepIncl
    OUT
  end

  it "module builtin name class" do
    result = ze0(<<~'RUBY')
      module M
        class Bench
          def self.bench_name; "base"; end
          def name_of; self.class.bench_name; end
        end
        class Array < Bench
          def self.bench_name; "arr"; end
          def hi; "hello"; end
        end
        class Hash < Bench
          def self.bench_name; "hsh"; end
        end
      end
      p M::Array.new.hi
      p M::Array.new.name_of
      p M::Hash.new.name_of
      p M::Array.bench_name
      a = [1, 2]
      p a.class.to_s
      p({ x: 1 }.class.to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "arr"
      "hsh"
      "arr"
      "Array"
      "Hash"
    OUT
  end

  it "module name anonymous" do
    result = ze0(<<~'RUBY')
      # `Module#name` answers only for a class or module a CONSTANT PATH reaches.
      # Everything else is nameless and answers nil -- while `#to_s`/`#inspect` still
      # render it, which is the whole point of the two being different methods.
      module Outer
        class Inner; end
        module Mixin; end
      end

      p Outer.name
      p Outer::Inner.name
      p Outer::Mixin.name
      p Outer::Inner.inspect
      p String.name
      p Comparable.name

      anon_class = Class.new
      anon_module = Module.new
      p anon_class.name
      p anon_module.name
      p anon_class.to_s.start_with?("#<Class:0x")
      p anon_module.to_s.start_with?("#<Module:0x")
      p anon_class.inspect == anon_class.to_s

      # A singleton class is nameless too, however well its owner is named.
      p String.singleton_class.name
      p String.singleton_class.to_s
      p Outer::Inner.singleton_class.name
      obj = Object.new
      p obj.singleton_class.name

      # A `Struct.new` is nameless until a constant holds it.
      p Struct.new(:a).name
      Point = Struct.new(:x, :y)
      p Point.name
      p Point.new(1, 2).class.name

      # Naming happens on the FIRST constant assignment, and a second one does not
      # rename -- so the alias reports the original path.
      Named = anon_class
      p Named.name
      Alias = Named
      p Alias.name
      p Alias.equal?(Named)

      # A subclass of an anonymous class is itself anonymous until named.
      child = Class.new(anon_class)
      p child.name
      p child.superclass.equal?(anon_class)
    RUBY

    _(result).must_answer <<~'OUT'
      "Outer"
      "Outer::Inner"
      "Outer::Mixin"
      "Outer::Inner"
      "String"
      "Comparable"
      nil
      nil
      true
      true
      true
      nil
      "#<Class:String>"
      nil
      nil
      nil
      "Point"
      "Point"
      "Named"
      "Named"
      true
      nil
      true
    OUT
  end

  it "module reopen reports the module as owner" do
    result = ze0(<<~'RUBY')
      # Reopening a BUILTIN MODULE and asking who owns the method.
      #
      # A `module Comparable; def ctag; end; end` reopen flattens its row onto every
      # class in the chain, so dispatch is one probe rather than a walk. Each of
      # those classes registers a row of its own -- and every one of them claimed
      # the name as its OWN, so `#owner` named `Integer` where ruby names
      # `Comparable`, and `Integer.instance_methods(false)` listed it.
      #
      # A flattened row is already marked FOREIGN, because `super` must not find one
      # at the position it is resuming from. `#owner` and `instance_methods(false)`
      # ask that same question, and now read that same mark.

      module Mine
        def mtag = :m
      end
      module Comparable
        def ctag = :c
      end
      module Enumerable
        def etag = :e
      end
      class Widget
        include Mine
      end

      def show(label)
        puts format("%-32s %s", label, (yield).inspect)
      rescue => e
        puts format("%-32s %s", label, e.class)
      end

      show("user module owner")       { Widget.new.method(:mtag).owner }
      show("user module unbound")     { Widget.instance_method(:mtag).owner }
      show("user module own?")        { Widget.instance_methods(false).include?(:mtag) }
      show("declared on the module")  { Mine.instance_methods(false).include?(:mtag) }

      show("Comparable owner")        { 5.method(:ctag).owner }
      show("through String")          { "s".method(:ctag).owner }
      show("through Float")           { 1.5.method(:ctag).owner }
      show("Comparable unbound")      { Integer.instance_method(:ctag).owner }
      show("Integer own?")            { Integer.instance_methods(false).include?(:ctag) }
      show("Comparable own?")         { Comparable.instance_methods(false).include?(:ctag) }
      show("Comparable defines?")     { Comparable.method_defined?(:ctag) }

      show("Enumerable owner")        { [].method(:etag).owner }
      show("through Hash")            { {}.method(:etag).owner }
      show("through Range")           { (1..2).method(:etag).owner }
      show("Array own?")              { Array.instance_methods(false).include?(:etag) }

      # The reopened row still RUNS, from every includer.
      show("call through Integer")    { 5.ctag }
      show("call through Array")      { [].etag }
      show("call through Widget")     { Widget.new.mtag }
      show("no super above it")       { 5.method(:ctag).super_method.inspect }
    RUBY

    _(result).must_answer <<~'OUT'
      user module owner                Mine
      user module unbound              Mine
      user module own?                 false
      declared on the module           true
      Comparable owner                 Comparable
      through String                   Comparable
      through Float                    Comparable
      Comparable unbound               Comparable
      Integer own?                     false
      Comparable own?                  true
      Comparable defines?              true
      Enumerable owner                 Enumerable
      through Hash                     Enumerable
      through Range                    Enumerable
      Array own?                       false
      call through Integer             :c
      call through Array               :e
      call through Widget              :m
      no super above it                "nil"
    OUT
  end

  it "protocols" do
    result = ze0(<<~'RUBY')
      class Money
        include Comparable
        attr_reader :cents

        def initialize(cents)
          @cents = cents
        end

        def <=>(other)
          cents <=> other.cents
        end

        def to_s
          "$#{cents / 100}.#{cents % 100}"
        end

        def ==(other)
          other.is_a?(Money) && cents == other.cents
        end

        def hash
          cents.hash
        end

        def eql?(other)
          other.is_a?(Money) && cents == other.cents
        end
      end

      a = Money.new(1250)
      b = Money.new(3499)
      puts a
      puts "price: #{b}"
      puts a < b
      puts a.between?(Money.new(1000), Money.new(2000))
      puts a.clamp(Money.new(2000), Money.new(5000))
      puts a == Money.new(1250)
      puts [a, b].min
      puts [a, b].max
      puts [Money.new(1), Money.new(2)] == [Money.new(1), Money.new(2)]

      prices = {}
      prices[Money.new(500)] = "cheap"
      puts prices[Money.new(500)]
    RUBY

    _(result).must_answer <<~'OUT'
      $12.50
      price: $34.99
      true
      true
      $20.0
      true
      $12.50
      $34.99
      true
      cheap
    OUT
  end

  it "reopen mixin applies where it stands" do
    result = ze0(<<~'RUBY')
      # An `include`/`prepend` written in a REOPEN is a runtime event with a
      # position: code between the two bodies must not see the edit. zeo recorded it
      # as a compile-time ancestry fact, so it applied from program start.
      module Extra
        def tag = :from_module
      end

      class Thing
      end

      p Thing.new.respond_to?(:tag)
      p Thing.instance_methods.include?(:tag)
      p Thing.ancestors.map(&:to_s)

      class Thing
        include Extra
      end

      p Thing.new.respond_to?(:tag)
      p Thing.new.tag
      p Thing.ancestors.map(&:to_s)

      # A prepend layers most-recent-first, ahead of everything already prepended.
      module Loud
        def speak = "!" + super + "!"
      end
      module Also
        def speak = "[" + super + "]"
      end
      class Animal
        def speak = "raw"
      end
      class Dog < Animal
        prepend Loud
        def speak = "woof(" + super + ")"
      end

      p Dog.new.speak
      p Dog.ancestors.take(4).map(&:to_s)

      class Dog
        prepend Also
      end

      p Dog.new.speak
      p Dog.ancestors.take(5).map(&:to_s)

      # ...and a SUBCLASS minted before the reopen sees it too.
      class Puppy < Dog; end
      p Puppy.new.speak
      p Puppy.ancestors.take(5).map(&:to_s)

      # An include in the FIRST body stays a compile-time fact.
      module Early
        def e = :early
      end
      class WithEarly
        include Early
      end
      p WithEarly.new.e
      p WithEarly.ancestors.map(&:to_s).first(2)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      ["Thing", "Object", "Kernel", "BasicObject"]
      true
      :from_module
      ["Thing", "Extra", "Object", "Kernel", "BasicObject"]
      "!woof(raw)!"
      ["Loud", "Dog", "Animal", "Object"]
      "[!woof(raw)!]"
      ["Also", "Loud", "Dog", "Animal", "Object"]
      "[!woof(raw)!]"
      ["Puppy", "Also", "Loud", "Dog", "Animal"]
      :early
      ["WithEarly", "Early"]
    OUT
  end

  it "shared module body that must not be shared" do
    result = ze0(<<~'RUBY')
      # One `def` in a module, included into classes that make it emit DIFFERENTLY.
      # `codegen::share` serves a widely-inherited body from a single emitted
      # function, so each shape here is one it must decline -- and `codegen::
      # class_query` is what lets it know, by recording the question the emission
      # asked about its receiver and replaying it against the other members.
      #
      # Real gems turn out never to hit these: every sharing group in prism, uri,
      # minitest and rubygems renders identically for all its members. That makes the
      # safety net untestable in the field, so the shapes are built here on purpose --
      # one per question the trace records.

      # --- ShadowsKernel: is a bare name the Kernel free function, or a real method?

      module Report
        def render = "[#{format('%04d', 7)}]"
      end

      class PlainReport
        include Report
      end

      class CustomReport
        include Report
        # Shadows Kernel#format, so the very same body must NOT fold to the free
        # function here.
        def format(*args) = "custom#{args.length}"
      end

      p PlainReport.new.render
      p CustomReport.new.render

      # (The third shape the trace records, `ValueSuper`, cannot be exercised here:
      # a module mixed into a value subclass whose method calls `super` crashes the
      # generated program outright, with or without sharing. See
      # tests/gaps/module_super_into_a_value_builtin.rb.)

      # --- IvarSlot: where does the module's own ivar sit?

      class WithOne
        def initialize = @first = 1
      end

      module Tracked
        def track
          @seen = (@seen || 0) + 1
          "#{@seen}/#{@seen.class}/#{@seen + 1}/#{@seen * 3}/#{@seen.abs}/#{@seen.to_s}"
        end
      end

      class TrackedSub < WithOne
        include Tracked
      end

      class TrackedBare
        include Tracked
      end

      s = TrackedSub.new
      b = TrackedBare.new
      p [s.track.split("/").first, s.track.split("/").first]
      p b.track.split("/").first
      p [s.instance_variables, b.instance_variables]
    RUBY

    _(result).must_answer <<~'OUT'
      "[0007]"
      "[custom2]"
      ["1", "2"]
      "1"
      [[:@first, :@seen], [:@seen]]
    OUT
  end

  it "superclass clause skips an outer module" do
    files = beside("superclass_clause/bench.rb",
                "superclass_clause/outer.rb",
                "superclass_clause/root.rb",
                "superclass_clause/zprobe.rb")

    result = ze0(<<~'RUBY', files: files)
      # `class Bench < Probe` inside `module Mini` names `Mini::Probe`, even when an
      # unrelated top-level `module Probe` is registered and `Mini::Probe` is not yet.
      #
      # A superclass clause names a CLASS, so a module found in an OUTER scope is not
      # what the clause means and the search continues. Stopping on it refused the
      # whole definition -- `superclass must be an instance of Class (given an
      # instance of Module)` -- and left the subclass registered with no body site,
      # which is a class the program defines and no read can find.
      #
      # minitest and test-unit are the real pair: `class Benchmark < Test` inside
      # `module Minitest` found test-unit's top-level `module Test` whenever
      # `minitest/test.rb` had not been walked yet, and which of the two units the
      # compiler walks first is a demand-order fact, not a program fact.
      #
      # The rule is narrow on purpose. Preferring the inner scope OUTRIGHT is wrong:
      # rspec-mocks writes `class BasicObject` under an `unless
      # defined?(BasicObject)` that never runs, and the `class FluentInterfaceProxy <
      # BasicObject` beneath it means the BUILTIN. An outer candidate that is already
      # a class stays the answer.

      require_relative "superclass_clause/outer"
      require_relative "superclass_clause/root"

      p Mini::Bench.superclass
      p Mini::Bench.new.kind
      p Mini::Bench.new.bench
      p Mini::Bench.ancestors.take(2).map(&:to_s)
      p Probe.class
      p Mini::Probe.class
      # An outer candidate that IS a class still wins -- the builtin, not a
      # same-named class the program only defines under a guard that never runs.
      module Guarded
        unless defined?(BasicObject)
          class BasicObject
          end
        end
        class Fluent < BasicObject
        end
      end
      p Guarded::Fluent.superclass.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      Mini::Probe
      "mini-probe"
      "bench"
      ["Mini::Bench", "Mini::Probe"]
      Module
      Class
      "BasicObject"
    OUT
  end
end
