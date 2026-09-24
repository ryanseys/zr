# frozen_string_literal: true

require "spec_helper"

describe "Classes: constants" do
  it "bare constant still falls back to the top level from inside a class" do
    result = zr(<<~'RUBY')
      MAX_ITEMS = 5
      class Config
        LIMIT = 3
        def show
          puts LIMIT
          puts MAX_ITEMS
        end
      end
      Config.new.show
    RUBY

    _(result).must_answer "3\n5\n"
  end

  it "boxs constant on a shared class is its own" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # A constant written on a SHARED class inside a box, read back by path.
      # `Array::BOXC` is a scope-operator read rather than a cref walk, so it is
      # a different path into the same table.



      b = Ruby::Box.new
      b.eval("class Array; BOXC = 11; end")
      p(begin; Array::BOXC; rescue NameError; :namee; end)
      p b.eval("Array::BOXC")
    RUBY

    _(result).must_answer ":namee\n11\n"
  end

  it "class allocate builtin var" do
    result = zr(<<~'RUBY')
      # Class#allocate on builtin classes yields the class's empty value, and a
      # variable-held class (builtin or user) dispatches like the constant (#2655).
      # A user allocate skips initialize.
      p String.allocate
      p Array.allocate
      p Hash.allocate
      class Widget
        def initialize; @x = 1; end
      end
      w = Widget
      p w.allocate.class
      s = String
      p s.allocate
      p Widget.allocate.class
    RUBY

    _(result).must_answer <<~'OUT'
      ""
      []
      {}
      Widget
      ""
      Widget
    OUT
  end

  it "class allocate skips initialize" do
    result = zr(<<~'RUBY')
      # `Class#allocate` builds an instance WITHOUT running `initialize` (so a
      # required-arg `initialize` is bypassed); the object is still a usable
      # instance whose ivars start nil and can be assigned by hand. A builtin
      # value class allocates its empty value, and a variable-held class
      # dispatches like the constant.

      class Thing
        def initialize(x) = (@x = x)
        def x = @x
      end
      t = Thing.allocate
      p t.class.name
      p t.x
      t2 = Thing.allocate
      p t2.is_a?(Thing)
      p String.allocate
      p Array.allocate
      p Hash.allocate
      w = Thing
      p w.allocate.class
    RUBY

    _(result).must_answer <<~'OUT'
      "Thing"
      nil
      true
      ""
      []
      {}
      Thing
    OUT
  end

  it "class body runs in document order" do
    result = zr(<<~'RUBY')
      # A class body runs WHERE IT IS WRITTEN. zr already emitted it there for a
      # body reached directly from the top level, but the reachability walk deciding
      # which bodies those are only descended through a class body and a box scope --
      # so a `class` inside any other statement container fell back to the prelude and
      # ran ahead of everything, before the `rescue` lexically enclosing it existed.
      puts "before"
      begin
        class Registry
          Undefined
        end
      rescue NameError => e
        puts "caught #{e.message}"
      end
      puts "after"

      # The same, through the other containers a definition is commonly guarded by.
      ORDER = []
      ORDER << :top
      if true
        class Guarded
          ORDER << :guarded
        end
      end
      ORDER << :after_if

      case :go
      when :go
        module InCase
          ORDER << :in_case
        end
      end
      ORDER << :after_case

      begin
        begin
          class Nested
            ORDER << :nested
          end
        end
      end
      ORDER << :after_nested
      p ORDER

      # A reopen inside a container runs again, in place.
      class Counter
        COUNT = []
      end
      2.times do
        class Counter
          COUNT << COUNT.size
        end
      end
      p Counter::COUNT

      # The class is still REGISTERED whole-program, so it resolves as a constant
      # wherever it is named.
      p Registry.name
      p InCase.instance_of?(Module)
      p Guarded.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      before
      caught uninitialized constant Registry::Undefined
      after
      [:top, :guarded, :after_if, :in_case, :after_case, :nested, :after_nested]
      [0, 1]
      "Registry"
      true
      Object
    OUT
  end

  it "class const defined" do
    result = zr(<<~'RUBY')
      # Class#const_defined? answers at compile time from the flat constant/class
      # registry (the same namespace a constant read resolves against).
      class Foo
        CONST = 1
      end
      o = Foo.new
      p o.class.const_defined?(:CONST)
      p o.class.const_defined?(:NOPE)
      p Foo.const_defined?(:CONST)
      p Foo.const_defined?("CONST")
      p Foo.const_defined?(:Foo)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
    OUT
  end

  it "class constant path read" do
    result = zr(<<~'RUBY')
      # Issue #52: reading a class-scoped constant from outside the class
      # via `ClassName::CONST` used to emit `User_MAX_NAME_LENGTH` as an
      # undeclared C identifier. Now it's emitted as `cst_User_MAX_NAME_LENGTH`
      # with a matching declaration.

      class User
        MAX_NAME_LENGTH = 20
      end

      puts User::MAX_NAME_LENGTH    # 20

      # Mixed reads: class const, module const, top-level const all
      # accessible via the same path forms.
      TOP = 1

      module Site
        ROOT = 2

        class Page
          LIMIT = 3
        end
      end

      puts TOP                      # 1
      puts Site::ROOT               # 2
      puts Site::Page::LIMIT        # 3
    RUBY

    _(result).must_answer <<~'OUT'
      20
      1
      2
      3
    OUT
  end

  it "class in the source mints and runs" do
    result = zr(<<~'RUBY')
      # The header mints the class through the runtime; the BODY runs as one
      # more `class_eval` of its own source, which is what a class body IS
      # -- a scope of its own, with its own cref.

      src = "class Minted; def hi; :hi; end; end; Minted.new.hi"
      p eval(src)
      p Minted.name
    RUBY

    _(result).must_answer <<~'OUT'
      :hi
      "Minted"
    OUT
  end

  it "class value chained cmethod" do
    result = zr(<<~'RUBY')
      # A singleton method that returns the class object, chained into another
      # singleton method.
      #
      # The value was right; only the dispatch was missing. A Class-valued receiver
      # carried in a variable already switches on the class id and calls the matching
      # class's static method, but a receiver that is itself a CALL was excluded --
      # so `Job.set(1).run(2)` was rejected at compile time even though `c = Job;
      # c.run(2)` worked. A constant or accessor receiver still resolves statically
      # through its own path.
      #
      # The shape is any builder-style class API: ActiveJob's `set` returns the job
      # class so options can be chained before enqueueing.

      class Job
        def self.run(x)
          p "run #{x}"
        end

        def self.set(opts)
          self
        end

        def self.by_name(opts)
          Job
        end

        def self.label
          "job"
        end
      end

      Job.set(1).run(2)
      Job.by_name(1).run(3)
      p Job.set(1).label
      p Job.set(1) == Job

      # chained twice
      Job.set(1).set(2).run(4)

      # two classes defining the same singleton name: the arm is chosen by the
      # class the value actually carries
      class Other
        def self.run(x)
          p "other #{x}"
        end

        def self.pick(n)
          n == 1 ? Job : Other
        end

        def self.label
          "other"
        end
      end

      Other.pick(1).run(5)
      Other.pick(2).run(6)
      p Other.pick(1).label
      p Other.pick(2).label

      # through a local and an ivar, the shapes that already worked
      c = Job.set(1)
      c.run(7)

      class Holder
        def initialize
          @k = Job.set(1)
        end

        def go
          @k.run(8)
        end
      end

      Holder.new.go

      # a returned class used for instantiation
      class Widget
        def initialize(n)
          @n = n
        end

        def n
          @n
        end

        def self.klass
          Widget
        end
      end

      p Widget.klass.new(9).n
    RUBY

    _(result).must_answer <<~'OUT'
      "run 2"
      "run 3"
      "job"
      true
      "run 4"
      "run 5"
      "other 6"
      "job"
      "other"
      "run 7"
      "run 8"
      9
    OUT
  end

  it "class var builtin new" do
    result = zr(<<~'RUBY')
      # A local statically holding one builtin class constant dispatches like the
      # constant itself (#2715) -- the receiver is retargeted at the AST.
      k = Array
      p k.new(3, 0)
      h = Hash
      p h.new(9)[:missing]
      s = String
      p s.new("ab")
      k2 = Integer
      p k2.name
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 0, 0]
      9
      "ab"
      "Integer"
    OUT
  end

  it "const defined inherit" do
    result = zr(<<~'RUBY')
      # `const_defined?`/`const_get` take an `inherit` flag, and the two answers are
      # genuinely different: a top-level constant belongs to `Object`, so every class
      # sees it INHERITED and none of them owns it. A block opens no constant scope
      # either, so a constant written inside a `Class.new do ... end` body lands at
      # top level rather than in the class it appears to build.
      def err
        yield
      rescue NameError => e
        [:name_error, e.message]
      end

      TOP = 1
      class Compiled
        INSIDE = 2
        class Nested; end
      end

      p Compiled.const_defined?(:INSIDE, false)
      p Compiled.const_defined?(:INSIDE)
      p Compiled.const_defined?(:Nested, false)
      p Compiled.const_defined?(:TOP, false)
      p Compiled.const_defined?(:TOP, true)
      p Compiled.const_defined?(:Missing, false)
      p Compiled.const_defined?(:Missing)
      p Compiled.const_get(:INSIDE, false)
      p err { Compiled.const_get(:TOP, false) }
      p Compiled.const_get(:TOP, true)

      p Object.const_defined?(:TOP, false)
      p Object.const_defined?(:Compiled, false)

      # A class and a module minted at runtime.
      R = Class.new
      p R.const_defined?(:TOP, false)
      p R.const_defined?(:TOP, true)
      M = Module.new
      p M.const_defined?(:TOP, false)
      p M.const_defined?(:TOP, true)

      # A `Class.new do ... end` body is a BLOCK: its constants land at top level.
      Outer = Class.new do
        Inner = Class.new do
          def label = "inner"
        end
        X = 5
      end
      p Inner.new.label
      p X
      p Outer.const_defined?(:Inner, false)
      p Outer.const_defined?(:X, false)
      p Object.const_defined?(:Inner, false)
      p Object.const_defined?(:X, false)

      # An inherited constant is the subclass's by inheritance only.
      class Sub < Compiled; end
      p Sub.const_defined?(:INSIDE, false)
      p Sub.const_defined?(:INSIDE, true)
      p Sub.const_get(:INSIDE)

      # `const_set` at runtime is visible to both forms.
      Compiled.const_set(:LATE, 9)
      p Compiled.const_defined?(:LATE, false)
      p Compiled.const_get(:LATE)
      p Object.const_defined?(:LATE, false)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      true
      false
      false
      2
      [:name_error, "uninitialized constant Compiled::TOP"]
      1
      true
      true
      false
      true
      false
      true
      "inner"
      5
      false
      false
      true
      true
      false
      true
      2
      true
      9
      false
    OUT
  end

  it "const get class name" do
    result = zr(<<~'RUBY')
      # `Object.const_get(:Foo)` where Foo is a class or module the program defines:
      # the lookup knew only VALUE constants, so it raised NameError for a constant
      # the program does define.
      module M
        X = 5
        class Inner
          def self.hi = "hi"
        end
      end
      class Top
        def self.v = 7
      end
      k = Object.const_get(:Top)
      p k.v
      p Object.const_get("Top").v
      p Object.const_get(:M)::X
      p M.const_get(:X)
      p M.const_get(:Inner).hi
      p Object.const_get(:Top) == Top
      p Object.const_get(:Top).name
      begin
        Object.const_get(:Nope)
      rescue NameError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      7
      7
      5
      5
      "hi"
      true
      "Top"
      "uninitialized constant Nope"
    OUT
  end

  it "const inherit flag" do
    result = zr(<<~'RUBY')
      class Up; TAG = "up"; end
      class Down < Up; end
      p Down.const_defined?(:TAG)
      p Down.const_defined?(:TAG, false)
      r = (Down.const_get(:TAG, false) rescue $!.class); p r
      p Up.const_defined?(:TAG, false)
      p Up.const_get(:TAG, false)
      p Down.const_get(:TAG)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      NameError
      true
      "up"
      "up"
    OUT
  end

  it "const missing on a named class" do
    result = zr(<<~'RUBY')
      # `const_missing` is never called for a constant read off a class the compiler
      # can name: `ClsHost::Whatever` raises `NameError` directly.
      #
      # zr resolves a qualified constant whose left side is a known class at COMPILE
      # time, and a miss is baked as the raise. Ruby's miss is a call --
      # `rb_const_missing` -- so the hook gets its chance at run time. The hook exists
      # only to serve misses, so folding the miss removes the whole mechanism.
      #
      # The anonymous shape still works (the second half below), which is what makes
      # this easy to miss: `Class.new { def self.const_missing(n) ... }` has no name
      # for the compiler to fold against, so its reads stay dynamic and reach the
      # hook. That is the reverse of what a programmer would predict.
      #
      # `const_missing` is how a loader materializes a class on first reference --
      # every autoloading framework is built on it -- and those all define constants
      # with real names.

      class ClsHost
        def self.const_missing(name) = [:cls_missing, name]
      end
      module ModHost
        def self.const_missing(name) = [:mod_missing, name]
      end
      module ModHost2
        class << self
          def const_missing(name) = [:mod2_missing, name]
        end
      end

      p ClsHost::Whatever
      p ModHost::Whatever
      p ModHost2::Whatever
      p ClsHost.const_get(:Whatever)
      p ModHost.const_get(:Whatever)

      # The anonymous form already reaches the hook.
      anon = Class.new { def self.const_missing(name) = [:anon_missing, name] }
      p anon.const_get(:Nope)
    RUBY

    _(result).must_answer <<~'OUT'
      [:cls_missing, :Whatever]
      [:mod_missing, :Whatever]
      [:mod2_missing, :Whatever]
      [:cls_missing, :Whatever]
      [:mod_missing, :Whatever]
      [:anon_missing, :Nope]
    OUT
  end

  it "constant path that only holds a class" do
    result = zr(<<~'RUBY')
      # `M::ALIAS` where `ALIAS` is a constant HOLDING a class, not a class of its
      # own, is the scope operator's question. Handing the whole string to the
      # bare-name cref walk looks for a constant literally called "M::ALIAS" and
      # raises `uninitialized constant M::ALIAS` -- but only in the
      # positions that lower through the class-NAME path (`New`), so `p M::ALIAS`
      # answered and `M::ALIAS.new` did not.

      module M
        module Tag; end
        class Base < StandardError
          include Tag
          def initialize(m) = super("base: #{m}")
        end
        ALIAS = Base
        TAGALIAS = Tag
        Made = Struct.new(:a, :b)
        MADEALIAS = Made
      end

      TOP = M::Base

      p M::ALIAS
      p M::ALIAS.new("x").message
      p M::ALIAS.new("x").class
      p TOP.new("y").message
      p M::Base.new("x").is_a?(M::TAGALIAS)

      # A runtime-minted class reached through an alias, with and without a block.
      p M::MADEALIAS.new(1, 2).to_a
      p M::MADEALIAS.members

      # Through a deeper path, and through an alias OF an alias.
      module Outer
        module Inner
          Leaf = Class.new { def hi = :hi }
        end
        LEAFALIAS = Inner::Leaf
      end
      p Outer::Inner::Leaf.new.hi
      p Outer::LEAFALIAS.new.hi

      # `rescue` and `raise` name it too.
      begin
        raise M::ALIAS, "boom"
      rescue M::ALIAS => e
        p [e.class, e.message]
      end

      # A path whose LEAF is genuinely missing still says so.
      begin
        M::Nope.new
      rescue NameError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      M::Base
      "base: x"
      M::Base
      "base: y"
      true
      [1, 2]
      [:a, :b]
      :hi
      :hi
      [M::Base, "base: boom"]
      "uninitialized constant M::Nope"
    OUT
  end

  it "constants resolve through the superclass chain" do
    result = zr(<<~'RUBY')
      class Base2
        LIMIT = 5
      end

      class Sub2 < Base2
        def l
          LIMIT
        end
      end

      puts Sub2.new.l
    RUBY

    _(result).must_answer "5\n"
  end

  it "dynamic class new" do
    result = zr(<<~'RUBY')
      # Issue #404 Tier 5. Dynamic `<sp_Class>.new` over a Class-typed
      # value. Pre-Tier-5 only the constant-receiver form worked
      # (`Foo.new` resolves at codegen time); a Class-typed local
      # carrying the same class hit the unresolved-call warning + 0
      # emit. The delegated_type / STI shape needs runtime dispatch
      # because the candidate class is determined by data.
      #
      # Coverage:
      #   - Pick a class from a hash at runtime, call .new, get a
      #     boxed instance, dispatch instance methods via the existing
      #     cls_id-keyed poly dispatch.
      #   - Multiple classes share the dispatch table.
      #   - Only the zero-arg shape is supported in this tier; classes
      #     whose initialize requires args fall back to nil from the
      #     dispatch (out of scope for the MVP).

      class Article
        def kind; "article"; end
      end

      class Page
        def kind; "page"; end
      end

      class Comment
        def kind; "comment"; end
      end

      def make(klass)
        klass.new
      end

      a = make(Article)
      p = make(Page)
      c = make(Comment)

      puts a.kind
      puts p.kind
      puts c.kind

      # Single dispatch via a Class-typed local variable.
      k = Article
      obj = k.new
      puts obj.kind
    RUBY

    _(result).must_answer <<~'OUT'
      article
      page
      comment
      article
    OUT
  end

  it "nested classes define dispatch and resolve lexical constants" do
    result = zr(<<~'RUBY')
      module Store
        DEFAULT = 10

        class Item
          def price
            DEFAULT
          end
        end

        class Errors
          class NotFound
            def msg
              "not found"
            end
          end
        end
      end

      puts Store::Item.new.price
      puts Store::Errors::NotFound.new.msg
      puts Store::DEFAULT
    RUBY

    _(result).must_answer <<~'OUT'
      10
      not found
      10
    OUT
  end

  it "new on a dynamic constant scope" do
    result = zr(<<~'RUBY')
      # faraday's `self.class::Handler.new(...)`: the receiver spells a constant path,
      # but its scope is only known at run time, so the class comes from the receiver's
      # own class -- a subclass overrides which one by redefining the constant.

      class Builder
        class Handler
          def initialize(name)
            @name = name
          end

          def to_s
            "handler:#{@name}"
          end
        end

        def build(name)
          self.class::Handler.new(name)
        end

        def limit
          self.class::MAX
        end

        MAX = 10
      end

      class LoudBuilder < Builder
        class Handler
          def initialize(name)
            @name = name
          end

          def to_s
            "LOUD:#{@name}"
          end
        end

        MAX = 99
      end

      puts Builder.new.build("a")
      puts LoudBuilder.new.build("b")
      puts Builder.new.limit
      puts LoudBuilder.new.limit
    RUBY

    _(result).must_answer <<~'OUT'
      handler:a
      LOUD:b
      10
      99
    OUT
  end

  it "runtime class body names its own class" do
    result = zr(<<~'RUBY')
      # Ruby binds a class's constant BEFORE running its body, so a class whose
      # superclass is a runtime value may name itself inside that body. jmespath's
      # token.rb is exactly this shape:
      #
      #   class Token < Struct.new(:type, :value, :position, :binding_power)
      #     NULL_TOKEN = Token.new(:eof, '', nil)
      #
      # zr builds such a class as `Name = Class.new(sup) { body }`, which assigns the
      # constant only after the body has run -- so the self-reference raised
      # `uninitialized constant`. In the body `self` IS the class, which is the exact
      # answer; inside a `def` the constant is bound by the time the method can run,
      # so that read keeps the ordinary lexical path.
      module M
        class T < Struct.new(:a, :b)
          FIRST = T.new(1, 2)
          LATER = T.new(3, 4)

          def self.build(x)
            T.new(x, x * 2)
          end

          def sibling
            T.new(a + 1, b + 1)
          end
        end

        # A plain class names itself the same way, and always could.
        class P
          SELF_REF = P
        end
      end

      p M::T::FIRST.a
      p M::T::LATER.b
      p M::T.build(5).b
      p M::T::FIRST.sibling.a
      p M::P::SELF_REF
      p M::T::FIRST.is_a?(M::T)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      4
      10
      2
      M::P
      true
    OUT
  end

  it "top level scoped constant names the builtin class" do
    result = zr(<<~'RUBY')
      # `::Integer` (and other `::Name` top-level anchors) resolve to the builtin
      # class in every position: is_a?/kind_of?/instance_of? arguments, `===`
      # receivers, and as a first-class Class value.

      p 5.is_a?(::Integer)
      p "x".is_a?(::String)
      p 3.14.kind_of?(::Numeric)
      p 5.instance_of?(::Integer)
      p(::Integer === 7)
      p(::String === "a")
      p ::Integer
      p ::Array.new(2, 0)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      Integer
      [0, 0]
    OUT
  end
end
