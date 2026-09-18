# frozen_string_literal: true

require "spec_helper"

describe "Methods: defining and naming methods" do
  it "alias and alias method including inherited sources" do
    result = ze0(<<~'RUBY')
      # Same-class and inherited sources, both spellings, chained across levels.

      class Base
        def greet(who); "hi " + who; end
        alias hail greet
        alias_method :salute, :greet
      end
      class Mid < Base
        alias_method :welcome, :greet
        alias hey greet
      end
      class Leaf < Mid
        alias again welcome
      end
      puts Base.new.hail("a")
      puts Base.new.salute("b")
      puts Mid.new.welcome("c")
      puts Mid.new.hey("d")
      puts Leaf.new.again("e")
      p Leaf.method_defined?(:again)
    RUBY

    _(result).must_answer <<~'OUT'
      hi a
      hi b
      hi c
      hi d
      hi e
      true
    OUT
  end

  it "alias and names" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # `alias` names a method wherever it is written -- the definee is `self`
      # where `self` is a class or a module, and the enclosing class
      # otherwise, which at the top level is `Object`.

      def hello = "hi"
      alias howdy hello
      p howdy

      class C
        def a = 1
      end

      # A reopen names the same class, so the alias lands where `a` is.
      class C
        alias b a
      end
      p C.new.b

      # `alias $new $old` names the STORAGE, so a write through either name is
      # visible through both.
      $first = 1
      alias $second $first
      $second = 2
      p $first

      # These verbs take a name, and ruby lets it be written as a String.
      class Named
        attr_reader "x"
        attr_writer "y"
        attr_accessor "z"
        alias_method "w", "x"

        def initialize
          @x = 1
          @y = 2
          @z = 3
        end

        def hidden = :h
        private "hidden"

        # One the declaration pass cannot reach -- written inside another
        # expression -- is an ordinary send of `Module#attr_reader`.
        p(attr_reader(:late))
      end

      n = Named.new
      p n.x, n.w
      n.z = 8
      p n.z
      p Named.instance_methods(false).sort
      p Named.private_instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT'
      "hi"
      1
      2
      [:late]
      1
      1
      8
      [:late, :w, :x, :y=, :z, :z=]
      [:hidden, :initialize]
    OUT
  end

  it "alias binds a body from another stream" do
    result = ze0(<<~'RUBY', files: {"an_alias_binds_a_body_from_another_stream/lib/thing_core.rb" => "module Streamed\n  class Thing\n    attr_reader :v\n    def initialize(v) = @v = v\n    def ==(other) = other.is_a?(Thing) && v == other.v\n    def hash = v.hash\n  end\nend\n", "an_alias_binds_a_body_from_another_stream/lib/thing_ext.rb" => "require \"thing_core\"\nmodule Streamed\n  class Thing\n    alias_method :eql?, :==\n  end\nend\n"})
      # `alias_method :eql?, :==` in one file, `def ==` in another. The alias must
      # bind that `==`, so two equal values are `eql?` and `Array#-` subtracts them.
      #
      # zeo bound `Kernel#eql?` -- identity -- because `resolve_aliases` compares the
      # alias's `seq` against the def's, and the analyze walk numbers the whole main
      # file before the first feature unit while a unit's body really runs at its
      # `require`. Across two streams those numbers order nothing, so the def read as
      # "defined later" and the alias fell through to the ancestors.
      #
      # bundler writes exactly this on `Gem::Dependency` (rubygems_ext.rb), and its
      # `==` lives in rubygems' dependency.rb. Every locked gem then compared unequal
      # to its own Gemfile twin, `@dependencies - @locked_deps.values` subtracted
      # nothing, and `bundle install` refused all 69 as newly added.
      #
      # The companion rule is `an_alias_of_a_builtin_keeps_the_old_body.rb`: WITHIN
      # one stream seq is real execution order, and the wrap idiom depends on it.

      $LOAD_PATH.unshift File.expand_path(
        "an_alias_binds_a_body_from_another_stream/lib", __dir__
      )
      require "thing_ext"

      a = Streamed::Thing.new(1)
      b = Streamed::Thing.new(1)

      m = a.method(:eql?)
      p [m.owner.to_s, m.original_name.to_s]
      p [a == b, a.eql?(b), a.hash == b.hash]
      p [([a] - [b]).size, [a, b].uniq.size]
    RUBY

    _(result).must_answer <<~'OUT'
      ["Streamed::Thing", "=="]
      [true, true, true]
      [0, 1]
    OUT
  end

  it "alias binds the body that exists when it runs" do
    result = ze0(<<~'RUBY')
      class T1
        alias_method :eql?, :==
      end
      class T1
        def ==(other) = true
      end
      a, b = T1.new, T1.new
      p [a == b, a.eql?(b), a.eql?(a)]
      p T1.instance_methods(false).sort
      p T1.instance_method(:eql?).owner.to_s
      p a.method(:eql?).owner.to_s
      p a.send(:eql?, b)

      # BasicObject#== is identity, whatever the receiver's own `==` says.
      class T2
        def ==(other) = true
      end
      c, d = T2.new, T2.new
      p [c == d, BasicObject.instance_method(:==).bind(c).call(d)]

      # The alias still follows a source the SAME class defined EARLIER.
      class T3
        def label = "first"
        alias_method :tag, :label
        def label = "second"
      end
      p [T3.new.label, T3.new.tag]
    RUBY

    _(result).must_answer <<~'OUT'
      [true, false, true]
      [:==, :eql?]
      "T1"
      "T1"
      false
      [true, false]
      ["second", "first"]
    OUT
  end

  it "alias captures earlier def" do
    result = ze0(<<~'RUBY')
      # An alias captures the definition in effect where it appears. Aliases were a
      # name mapping resolved at the end, so when the target was redefined later in
      # the same body the alias answered the NEW definition.
      class A
        def greet; "A"; end
        alias_method :old_greet, :greet
        def greet; "B"; end
      end
      p A.new.greet
      p A.new.old_greet

      class B
        def hi; "one"; end
        alias hi2 hi
        def hi; "two"; end
      end
      p B.new.hi
      p B.new.hi2

      # an alias with no later redefinition still maps names
      class C
        def val; 7; end
        alias v val
      end
      p C.new.v
      p C.new.val

      # a wrapper that calls the captured original
      class D
        def run; "base"; end
        alias_method :run_without, :run
        def run; "wrapped(" + run_without + ")"; end
      end
      p D.new.run
      p D.new.run_without
    RUBY

    _(result).must_answer <<~'OUT'
      "B"
      "A"
      "two"
      "one"
      7
      7
      "wrapped(base)"
      "base"
    OUT
  end

  it "alias creates a second callable name for the same method" do
    result = ze0(<<~'RUBY')
      class Greeter
        def hello
          "hi"
        end
        alias hola hello
      end
      g = Greeter.new
      puts g.hello
      puts g.hola
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      hi
    OUT
  end

  it "alias frame names the method it was born as" do
    result = ze0(<<~'RUBY')
      # The two halves of an alias's identity, which pull in opposite directions.
      #
      # A FRAME names the method it was BORN as: CRuby labels it from
      # `me->def->original_id`, so a backtrace through `alias_method :kaboom, :boom`
      # says `C#boom`. zeo labelled it with the alias.
      #
      # `__callee__` is the other half and keeps the name the method was CALLED by,
      # while `__method__` keeps the original. Those two shared one string -- the
      # frame label -- so fixing the frame broke `__callee__`, and it is folded at
      # compile time now: an alias is emitted as its own body, which knows the name
      # it answers to.

      class Al
        def real(x) = [__method__, __callee__, x]
        alias_method :nick, :real
        alias nick2 real
        def boom = raise("x")
        alias_method :kaboom, :boom
      end

      p Al.new.real(1)
      p Al.new.nick(2)
      p Al.new.nick2(3)
      p [Al.instance_method(:nick).original_name, Al.new.method(:nick).name]

      begin
        Al.new.kaboom
      rescue RuntimeError => e
        puts e.backtrace.first
      end

      module Mixin
        def base = caller(0).first[/in '(.*)'/, 1]
        alias_method :aliased, :base
      end
      class User
        include Mixin
      end
      p [User.new.base, User.new.aliased]

      class Both
        def orig(x) = [__method__, __callee__, x]
        alias_method :by_method, :orig
        alias by_keyword orig
        def frame = caller(0).first[/in \'(.*)\'/, 1]
        alias_method :frame_alias, :frame
      end
      p Both.new.orig(1)
      p Both.new.by_method(2)
      p Both.new.by_keyword(3)
      p [Both.new.frame, Both.new.frame_alias]
      p [Both.instance_method(:by_method).original_name, Both.new.method(:by_method).name]

      module Shared
        def base = [__method__, __callee__, caller(0).first[/in \'(.*)\'/, 1]]
        alias_method :aliased, :base
      end
      class Host
        include Shared
      end
      p Host.new.base
      p Host.new.aliased

      class Deep
        def one = __callee__
        alias two one
        alias three two
      end
      p [Deep.new.one, Deep.new.two, Deep.new.three]
    RUBY

    _(result).must_answer <<~'OUT'
      [:real, :real, 1]
      [:real, :nick, 2]
      [:real, :nick2, 3]
      [:real, :nick]
      lang/methods/definition_test.rb:17:in 'Al#boom'
      ["Mixin#base", "Mixin#base"]
      [:orig, :orig, 1]
      [:orig, :by_method, 2]
      [:orig, :by_keyword, 3]
      ["Both#frame", "Both#frame"]
      [:orig, :by_method]
      [:base, :base, "Shared#base"]
      [:base, :aliased, "Shared#base"]
      [:one, :two, :three]
    OUT
  end

  it "alias global" do
    result = ze0(<<~'RUBY')
      # AliasGlobalVariableNode -- `alias $copy $orig`.
      #
      # Compile-time only: Spinel registers $copy as a name pointing to
      # $orig's storage slot. Subsequent reads/writes of either share
      # state. Out of scope: dynamic alias from method body, since the
      # entire compile-time map is built once at AST scan.

      $orig = "hello"
      alias $copy $orig
      puts $copy        # hello

      $orig = "updated"
      puts $copy        # updated

      $copy = "back"
      puts $orig        # back
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      updated
      back
    OUT
  end

  it "alias inherited method" do
    result = ze0(<<~'RUBY')
      # `alias` can reference a method inherited from an ancestor, not just one
      # defined directly on the class. The alias snapshots the inherited body.
      class Parent
        def foo; "parent-foo"; end
        def greet(name); "hi " + name; end
      end

      class Child < Parent
        alias bar foo
        alias hail greet
      end

      puts Child.new.bar
      puts Child.new.hail("ada")

      # Two levels up resolves too.
      class Grandchild < Child
        alias baz foo
      end
      puts Grandchild.new.baz
    RUBY

    _(result).must_answer <<~'OUT'
      parent-foo
      hi ada
      parent-foo
    OUT
  end

  it "alias keyword definee" do
    result = ze0(<<~'RUBY')
      # The `alias` KEYWORD in expression position aliases on the frame's DEFAULT
      # DEFINEE, which is not `self`: the receiver's singleton under
      # `instance_exec` (rspec's top-level DSL pairs `def shared_examples` with
      # `alias shared_context shared_examples` on the RSpec module object), and
      # the module itself under `class_exec`.
      module M
        def self.definitions
          proc do
            def hi(x) = "hi #{x}"
            alias ho hi
          end
        end
      end
      module M
        instance_exec(&M.definitions)
      end
      p M.hi(1)
      p M.ho(2)
      module N; end
      N.class_exec do
        def inst = "instance side"
        alias inst2 inst
      end
      class K2
        include N
      end
      p K2.new.inst2
    RUBY

    _(result).must_answer <<~'OUT'
      "hi 1"
      "hi 2"
      "instance side"
    OUT
  end

  it "alias method dispatch" do
    result = ze0(<<~'RUBY')
      class Animal
        def speak(n); "sound" + n.to_s; end
        alias_method :vocalize, :speak
        alias cry speak
      end
      class Dog < Animal
        alias_method :woof, :speak
      end
      a = Animal.new
      puts a.speak(2)
      puts a.vocalize(3)
      puts a.cry(1)
      d = Dog.new
      puts d.woof(4)
    RUBY

    _(result).must_answer <<~'OUT'
      sound2
      sound3
      sound1
      sound4
    OUT
  end

  it "alias methods" do
    result = ze0(<<~'RUBY')
      # Both the `alias` keyword and `alias_method` create a second name for an
      # existing method, snapshotting its current body. The source method can be
      # defined in the same class or inherited from an ancestor.
      class Animal
        def speak(sound)
          "the animal says #{sound}"
        end
        alias vocalize speak            # keyword form, same-class source
        alias_method :emit, :speak      # method form, same-class source
      end

      class Dog < Animal
        alias_method :woof, :speak      # source is INHERITED from Animal
        alias bark speak                # keyword form, inherited source
      end

      a = Animal.new
      puts a.speak("moo")               # the animal says moo
      puts a.vocalize("baa")            # the animal says baa
      puts a.emit("cluck")              # the animal says cluck

      d = Dog.new
      puts d.woof("woof")               # the animal says woof
      puts d.bark("bark")               # the animal says bark

      # Aliases resolve through several inheritance levels, and an alias can even
      # alias another alias.
      class Puppy < Dog
        alias yip woof                  # woof is Dog's alias of Animal#speak
      end
      puts Puppy.new.yip("yip")         # the animal says yip
    RUBY

    _(result).must_answer <<~'OUT'
      the animal says moo
      the animal says baa
      the animal says cluck
      the animal says woof
      the animal says bark
      the animal says yip
    OUT
  end

  it "alias of a builtin binds the body" do
    result = ze0(<<~'RUBY')
      # `alias new old` captures the METHOD, not the name: a later `def old`
      # replaces the original without disturbing the alias.
      #
      # The alias of a builtin used to be a name indirection resolved at call
      # time, so the standard wrap idiom -- alias the primitive away, redefine
      # it, call the alias from the new body -- recursed until the stack ran
      # out. It is how rubygems installs its own `Kernel#require`.

      module Kernel
        alias orig_p p
        def p(*a)
          orig_p(:wrapped, *a)
        end
      end
      p 1

      # The same shape across two bodies, where the redefinition cannot even be
      # seen from the body that wrote the alias.
      module Kernel
        alias orig_pr print
      end
      module Kernel
        def print(*a)
          orig_pr("[", *a, "]\n")
        end
      end
      print "two bodies"

      # A builtin CLASS, reached through an instance rather than a universal.
      class String
        alias orig_upcase upcase
        def upcase = "shout(#{orig_upcase})"
      end
      puts "hi".upcase

      # A user class, whose aliased primitive comes from an ancestor's table
      # rather than its own.
      class Widget
        alias orig_inspect inspect
        def inspect = "Widget!"
      end
      w = Widget.new
      puts w.inspect
      puts w.orig_inspect.start_with?("#<Widget:0x")

      # The control: an alias of a USER method already bound its body.
      class Counter
        def tick = "first"
        alias orig_tick tick
        def tick = "second"
      end
      puts Counter.new.tick
      puts Counter.new.orig_tick
    RUBY

    _(result).must_answer <<~'OUT'
      :wrapped
      1
      [two bodies]
      shout(HI)
      Widget!
      true
      second
      first
    OUT
  end

  it "alias of a builtin keeps the old body" do
    result = ze0(<<~'RUBY')
      # `alias_method :old, :m` on a BUILTIN class, followed by `def m`, keeps
      # `old` on the ORIGINAL body -- the standard monkeypatch-wrap idiom, which
      # Net::HTTP debugging, test doubles and a great deal of gem code are written
      # with. It once made the wrapper call itself until the stack ran out.
      #
      # A builtin's first definition is a native row with no `Scope`, so the alias
      # cannot clone a body the way a user-class alias does; the row it registers
      # names the source instead. Dispatch answers that row from the native table
      # rather than by re-sending the name, so a later `def` cannot capture it.
      #
      # The rows here name the receiver's OWN class. The chain case -- a universal,
      # or a user class inheriting the primitive -- is
      # `an_alias_of_a_builtin_binds_the_body.rb`.
      #
      # The second program below is the same rule with no redefinition at all: an
      # alias taken BEFORE a reopen still answers the original.

      class String
        alias_method :zeo_gap_old_upcase, :upcase
        def upcase = "wrapped(#{zeo_gap_old_upcase})"
      end

      puts "ab".upcase
      puts "ab".zeo_gap_old_upcase

      class Array
        alias_method :zeo_gap_old_first, :first
      end

      class Array
        def first(*) = "replaced"
      end

      puts [1, 2].first.inspect
      puts [1, 2].zeo_gap_old_first.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      wrapped(AB)
      AB
      "replaced"
      1
    OUT
  end

  it "alias of a runtime method" do
    result = ze0(<<~'RUBY')
      # `alias_method` names a method the class body itself just created. bundler's
      # `Runtime` is the shape: a `define_method` wrapper called five times, then
      # `alias_method :gems, :specs`. The source only exists once the body has run,
      # so the alias has to be checked THERE and not before.
      class Runtime
        def self.definition_method(meth)
          define_method(meth) { "answering #{meth}" }
        end
        private_class_method :definition_method

        definition_method :specs
        definition_method :requires

        alias_method :gems, :specs
      end
      r = Runtime.new
      p r.specs, r.gems, r.requires
      p Runtime.instance_methods(false).sort
      p Runtime.method_defined?(:gems)
      p r.method(:gems).call

      # An alias of an ordinary `def` in the same body still works, and so does one
      # of an inherited method.
      class Base
        def greet = "hi"
      end
      class Sub < Base
        def shout = "HI"
        alias_method :yell, :shout
        alias_method :hello, :greet
      end
      p Sub.new.yell, Sub.new.hello
      p Sub.instance_methods(false).sort

      # ...and a reopen aliasing something the FIRST body defined.
      class Reopened
        define_method(:original) { :first }
      end
      class Reopened
        alias_method :second, :original
      end
      p Reopened.new.second

      # A genuinely missing source is still a NameError, raised where the body runs.
      begin
        Class.new { alias_method :nope, :no_such_method_anywhere }
      rescue NameError => e
        puts e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "answering specs"
      "answering specs"
      "answering requires"
      [:gems, :requires, :specs]
      true
      "answering specs"
      "HI"
      "hi"
      [:hello, :shout, :yell]
      :first
      NameError
    OUT
  end

  it "alias of a superseded method" do
    result = ze0(<<~'RUBY')
      # The classic alias-chaining idiom: reopen a class, alias the old body, then
      # redefine the method to call the alias. `analyze::add_own_method` keeps one
      # row per name (the reopened body replaces the original in `own_methods`), and
      # `mro::resolve_aliases` runs after the whole walk, so the alias clones the
      # NEW body instead of the one that existed when the alias ran -- `greet` calls
      # itself and the process aborts with a native stack overflow.
      #
      # The fix needs execution order: superseded scopes are never deleted
      # (`compiler.scopes` is append-only) and `SiteDef.seq` already records def
      # order; aliases must carry their seq and resolve against the newest row
      # defined BEFORE them. The sibling divergence -- a CALL placed before the
      # reopen also sees the final body -- has its own file,
      # `pre_reopen_call_sees_the_final_body.rb`.
      class Greeter
        def greet
          "base"
        end
      end

      class Greeter
        alias_method :old_greet, :greet
        def greet
          "new(#{old_greet})"
        end
      end

      puts Greeter.new.greet

      class Farewell
        def bye
          "bye"
        end
        alias bye_keyword_alias bye
        def bye
          "later(#{bye_keyword_alias})"
        end
      end

      puts Farewell.new.bye
    RUBY

    _(result).must_answer <<~'OUT'
      new(base)
      later(bye)
    OUT
  end

  it "alias of inherited method" do
    result = ze0(<<~'RUBY')
      class P1; def greet; "P"; end; end
      class Q1 < P1
        alias_method :old_greet, :greet
        def greet; "Q"; end
      end
      p Q1.new.old_greet

      class P2; def greet; "P"; end; end
      class Q2 < P2
        alias old_greet2 greet
        def greet; "Q"; end
      end
      p Q2.new.old_greet2   # Ruby: "P"   Spinel: "Q"

      class A
        def greet; "A"; end
        alias_method :old_greet, :greet
        def greet; "B"; end
      end
      p A.new.greet       # => "B"
      p A.new.old_greet   # => "A"

      class C
        def greet; "C"; end
        alias_method :old_greet, :greet
        def greet; "D(" + old_greet + ")"; end
      end
      p C.new.greet       # => "D(C)"

      class R1 < P1
        alias_method :parent_greet, :greet
        def greet
          "R(" + parent_greet + ")"
        end
      end
      p R1.new.greet
      p R1.new.parent_greet

      class S1 < P1
        alias_method :same_greet, :greet
      end
      p S1.new.same_greet
      p S1.new.greet
    RUBY

    _(result).must_answer <<~'OUT'
      "P"
      "P"
      "B"
      "A"
      "D(C)"
      "R(P)"
      "P"
      "P"
      "P"
    OUT
  end

  it "alias preserves the original methods own parameters" do
    result = ze0(<<~'RUBY')
      class Calc
        def add(a, b)
          a + b
        end
        alias sum add
      end
      puts Calc.new.sum(3, 4)
    RUBY

    _(result).must_answer "7\n"
  end

  it "alias under modifier" do
    result = ze0(<<~'RUBY')
      class C
        def original = 1
        alias aliased original if true        # statically true: the alias is created

        def greet = "hi"
        alias hello greet unless false        # unless false: also created

        alias parend original if (true)       # parenthesized constant folds too

        # a statically-false guard creates no alias and compiles cleanly. CRuby does
        # not define these either, so they are intentionally never called.
        alias never_made original if false
        alias also_none greet unless true

        # if/elsif: the statically-selected branch's alias is the one registered
        def from_b = "b"
        if false
          alias chosen original
        elsif true
          alias chosen from_b
        end
      end

      puts C.new.aliased
      puts C.new.hello
      puts C.new.parend
      puts C.new.chosen
      puts C.new.original
      puts C.new.greet
    RUBY

    _(result).must_answer <<~'OUT'
      1
      hi
      1
      b
      1
      hi
    OUT
  end

  it "alias whose source resolves nowhere is a name error at program start" do
    result = ze0(<<~'RUBY')
      # `alias_method :foo, :nope_missing`: real Ruby raises NameError when the
      # class body EXECUTES (runtime, not compile time) -- mirrored by
      # `validate_aliases` at startup, with CRuby's message.

      class Typo
        alias_method :foo, :nope_missing
      end
      puts "unreached"
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      lang/methods/definition_test.rb:6:in 'Module#alias_method': undefined method 'nope_missing' for class 'Typo' (NameError)

        alias_method :foo, :nope_missing
        ^^^^^^^^^^^^
      	from lang/methods/definition_test.rb:6:in '<class:Typo>'
      	from lang/methods/definition_test.rb:5:in '<main>'
    ERR
  end

  it "arg forwarding to rest callee" do
    result = ze0(<<~'RUBY')
      # `...` into a callee with `*rest` / `**kwrest` keeps positionals and keywords apart.
      def h1(*a, **k) = [a, k]
      def h10(...) = h1(...)
      p h10(1, k: 2)
      p h10(3)
      p h10
      p h10(1, 2, k: 3, j: 4)

      # rest only, kwrest only
      def h3(*a) = a
      def h30(...) = h3(...)
      p h30(1, 2)
      p h30
      def h4(**k) = k
      def h40(...) = h4(...)
      p h40(k: 2, j: 3)

      # leading concrete params on both sides, and mixed keyword/kwrest
      def h5(x, *a, k: 0, **r) = [x, a, k, r]
      def h50(x, ...) = h5(x, ...)
      p h50(0, 1, 2, k: 5, z: 6)
      p h50(0)

      # inside a class
      class Fw
        def go(*a, **k) = [a, k]
        def fw(...) = go(...)
      end
      p Fw.new.fw(1, q: 2)

      # fixed-arity callees keep the direct positional forward
      def h2(a, b: 0) = [a, b]
      def h20(...) = h2(...)
      p h20(1, b: 5)
      p h20(7)
    RUBY

    _(result).must_answer <<~'OUT'
      [[1], {k: 2}]
      [[3], {}]
      [[], {}]
      [[1, 2], {k: 3, j: 4}]
      [1, 2]
      []
      {k: 2, j: 3}
      [0, [1, 2], 5, {z: 6}]
      [0, [], 0, {}]
      [[1], {q: 2}]
      [1, 5]
      [7, 0]
    OUT
  end

  it "call splat positional" do
    result = ze0(<<~'RUBY')
      # Call-site positional splat `f(*args)`: a single trailing splat expands an
      # array across a method's fixed parameters. Previously rejected at compile time
      # (the callee was left untyped and dead-code-eliminated, or the splat arg failed
      # to emit). The splat array's element type now propagates to the callee's params
      # so it is emitted, the operand is evaluated once into a rooted temp, and a
      # fixed-arity mismatch raises ArgumentError exactly as CRuby does.
      def s(x); x; end

      def add3(a, b, c); a + b + c; end
      def join2(a, b); a + b; end

      # splat of a local, a literal, and a method-call result
      nums = [1, 2, 3]
      p add3(*nums)
      p add3(*[4, 5, 6])
      p add3(*s([7, 8, 9]))

      # string and float element kinds
      p join2(*["x", "y"])
      p join2(*[1.5, 2.5])

      # splat after a fixed leading arg
      rest = [20, 30]
      p add3(10, *rest)

      # value position vs statement position
      total = add3(*nums)
      p total
      add3(*nums)  # statement: no output, must still compile

      # optional params: a short splat falls back to the defaults
      def opt(a, b = 9, c = 100); a + b + c; end
      p opt(*[1])
      p opt(*[1, 2])
      p opt(*[1, 2, 3])
      p opt(*s([5]))

      # rest-param callee absorbs any length
      def collect(*xs); xs.sum; end
      p collect(*[1, 2, 3, 4])

      # arity mismatch raises ArgumentError with CRuby's exact message
      begin
        add3(*[1, 2])
      rescue ArgumentError => e
        p e.message
      end
      begin
        join2(*[1, 2, 3])
      rescue ArgumentError => e
        p e.message
      end
      begin
        opt(*[1, 2, 3, 4])
      rescue ArgumentError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      6
      15
      24
      "xy"
      4.0
      60
      6
      110
      103
      6
      114
      10
      "wrong number of arguments (given 2, expected 3)"
      "wrong number of arguments (given 3, expected 2)"
      "wrong number of arguments (given 4, expected 1..3)"
    OUT
  end

  it "callee through alias" do
    result = ze0(<<~'RUBY')
      class A1
        def a; __callee__; end
        alias b a
        alias_method :c, :a
        def m; __method__; end
        alias n m
        def both; [__method__, __callee__]; end
        alias both2 both
      end
      o = A1.new
      p o.a
      p o.b
      p o.c
      p o.m
      p o.n
      p o.both
      p o.both2

      def top; __callee__; end
      alias top2 top
      p top
      p top2

      class Sub < A1; end
      s = Sub.new
      p s.b
      p s.a

      class Chain
        def orig; __callee__; end
        alias one orig
        alias two one
      end
      p Chain.new.two
      p Chain.new.one
      p Chain.new.orig
    RUBY

    _(result).must_answer <<~'OUT'
      :a
      :b
      :c
      :m
      :m
      [:both, :both]
      [:both, :both2]
      :top
      :top2
      :b
      :a
      :two
      :one
      :orig
    OUT
  end

  it "class method alias" do
    result = ze0(<<~'RUBY')
      # An alias inside `class << self` whose source is a BUILTIN class method.
      #
      # `class << self; alias [] new; end` is the `Klass[...]` constructor shorthand,
      # and 14 of the cluster's rows are that one line: rack, rack-test, pry, coderay,
      # sprockets, warden, omniauth, better_errors and five more rack-* gems.
      #
      # The instance side already handled this by recording a NAME indirection rather
      # than cloning a body -- the source lives in a static builtin table and has no
      # body to clone. The singleton side had no such table, so it raised. Now it has
      # one, and `rack-test` mattering to railties and sprockets-rails is why.

      class Request
        class << self
          alias [] new
        end

        def initialize(env = {})
          @env = env
        end

        attr_reader :env
      end

      r = Request["PATH_INFO" => "/"]
      p r.class
      p r.env

      # The alias answers reflection too -- it is a name indirection, not a row, so
      # `respond_to?` has to be asked about it separately.
      p Request.respond_to?(:[])
      p Request.respond_to?(:never_defined)

      # A subclass reaches it through the ordinary ancestor walk.
      class JsonRequest < Request
      end

      p JsonRequest["a" => 1].class

      # A real `def self.[]` still wins over an alias of the same name: the alias is
      # probed only once every real class-method lookup has missed.
      class Sized
        class << self
          alias [] new
        end

        def self.[](n)
          "explicit #{n}"
        end
      end

      p Sized[3]

      # An alias whose source is a user `def self.x` never needed this path -- it
      # clones the body, as it always did -- but it has to keep working beside it.
      class Builder
        def self.build(tag)
          "built #{tag}"
        end

        class << self
          alias make build
        end
      end

      p Builder.make("x")

      # An alias of an alias terminalises, so the rewrite cannot chain at run time.
      class Chained
        class << self
          alias [] new
          alias create []
        end

        def initialize(v = 1)
          @v = v
        end

        attr_reader :v
      end

      p Chained.create(9).v
    RUBY

    _(result).must_answer <<~'OUT'
      Request
      {"PATH_INFO" => "/"}
      true
      false
      JsonRequest
      "explicit 3"
      "built x"
      9
    OUT
  end

  it "const alias method call" do
    result = ze0(<<~'RUBY')
      # A constant aliasing a class (`A = M::N`) works as a method-call receiver:
      # the alias receiver is rewritten to the underlying class so `A.foo`
      # dispatches like the direct `M::N.foo`.

      module M
        class N
          def self.foo; 42; end
          def self.bar(x); x + 1; end
        end
      end

      A = M::N
      puts A.foo          # 42
      puts A.bar(10)      # 11

      class Top
        def self.greet; "hi"; end
      end
      B = Top
      puts B.greet        # hi
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      11
      hi
      done
    OUT
  end

  it "def reflection" do
    result = ze0(<<~'RUBY')
      def twice(n)
        n * 2
      end
      puts twice(5)
      puts respond_to?(:twice, true)
      p method(:twice).arity
      p method(:twice).parameters
    RUBY

    _(result).must_answer <<~'OUT'
      10
      true
      1
      [[:req, :n]]
    OUT
  end

  it "define method accepts a method object body" do
    result = ze0(<<~'RUBY')
      # `define_method(name, method_obj)` / `define_singleton_method(name,
      # method_obj)` with a `Method`/`UnboundMethod` body (not a Proc): aliases
      # within a class, an UnboundMethod copied into a subclass, a bound Method
      # as an object singleton, the subclass-compatibility TypeError, and the
      # still-working Proc form. Oracle-verified verbatim.

      class A
        def greet(n); "hi #{n}"; end
        r = define_method(:hail, instance_method(:greet))
        p r
      end
      p A.new.hail("x")
      class Sub < A
        define_method(:hey, A.instance_method(:greet))
      end
      p Sub.new.hey("y")
      class B < A
        def m(n); n * 2; end
      end
      class C < B
        define_method(:m2, B.instance_method(:m))
      end
      p C.new.m2(5)
      class Unrelated; end
      begin
        Unrelated.class_eval { define_method(:g, A.instance_method(:greet)) }
      rescue TypeError => e
        puts e.message
      end
      class Widget
        def ping(x); "pong #{x}"; end
      end
      w = Widget.new
      w.define_singleton_method(:sm, Widget.new.method(:ping))
      p w.sm("z")
      class D
        define_method(:sq) { |x| x * x }
      end
      p D.new.sq(6)
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      :hail
      "hi x"
      "hi y"
      10
      bind argument must be a subclass of A
      "pong z"
      36
      done
    OUT
  end

  it "define method and send" do
    result = ze0(<<~'RUBY')
      # Method definition and dispatch at run time: the binary carries the method
      # tables and the reflection paths that build them.
      class Calculator
        %i[add sub].each do |op|
          define_method(op) { |a, b| op == :add ? a + b : a - b }
        end
      end
      c = Calculator.new
      puts c.send(:add, 2, 3), c.public_send(:sub, 9, 4)
      p Calculator.instance_methods(false).sort
      p c.method(:add).arity
      p c.respond_to?(:mul)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      [:add, :sub]
      2
      false
    OUT
  end

  it "define method block closes over the class body" do
    result = ze0(<<~'RUBY')
      # `define_method(:m) { ... }` in a class or module body desugars to a plain
      # method -- and a method is a function of its own, so it cannot reach a
      # local living on the enclosing class-body frame. rubygems writes exactly that
      # shape in `core_ext/kernel_warn.rb`:
      #
      #   module Kernel
      #     original_warn = instance_method(:warn)
      #     module_function define_method(:warn) { |*m, **kw| original_warn.bind_call(self, *m, **kw) }
      #   end
      #
      # which emitted a method body naming `original_warn` and stopped bundler and
      # rubyzip at compile time on an unknown name. A capturing block declines the
      # desugar and installs a real closure through `Module#define_method` instead.

      module Greeter
        greeting = "hi"
        define_method(:hello) { greeting }
      end
      class Plain
        include Greeter
      end
      p Plain.new.hello

      class Shouter
        suffix = "!"
        # A parameter of its own alongside the captured local.
        define_method(:shout) { |word| [word, suffix].join }
        # Captured from one scope further in, so the depth is 2 rather than 1.
        define_method(:nested) { [1].map { suffix }.first }
        # No capture at all: this one keeps the direct desugar, and its own locals
        # must not be mistaken for an enclosing scope's.
        define_method(:own) { |a| doubled = a * 2; doubled + 1 }
      end
      p Shouter.new.shout("hey")
      p Shouter.new.nested
      p Shouter.new.own(4)

      # The captured local is shared, not copied: a later write in the class body is
      # visible to the method, exactly as a closure requires.
      class Counter
        n = 0
        define_method(:bump) { n += 1 }
        define_method(:read) { n }
      end
      c = Counter.new
      c.bump
      c.bump
      p c.read

      # A `define_method` inside a METHOD body was always a closure and must stay
      # one -- the desugar there emits the def in expression position.
      class Later
        def self.build(v)
          define_method(:val) { v }
        end
        build(42)
      end
      p Later.new.val
    RUBY

    _(result).must_answer <<~'OUT'
      "hi"
      "hey!"
      "!"
      9
      2
      42
    OUT
  end

  it "define method body frame label" do
    result = ze0(<<~'RUBY')
      # A `define_method` body is a BLOCK, and ruby labels its frame as one --
      # `block in <class:Named>` -- because that is literally what it is. zeo labels
      # it after the method it installs, so the frame claims a method scope ruby
      # never reports:
      #
      #     class Named; define_method(:dm) { where }; end
      #     Named.new.dm      ruby "block in <class:Named>"   zeo "Named#dm"
      #
      # A real `def` is the opposite and zeo now gets it right (see
      # `tests/method_defined_in_a_block_frame_label.rb`): a `def` written inside a
      # block still creates an ordinary method, so ruby names the frame after the
      # method. The two are the same question asked of the two ways to define one,
      # and the answers go opposite ways -- which is what makes it easy to fix one
      # and miss the other.
      #
      # Only the LITERAL-symbol form diverges. A computed name stays an ordinary call
      # with an ordinary block (no `DefMethod` node), so it already answers
      # correctly -- the last pair below is the control.
      #
      # The base is what is wrong, not the depth: the anonymous case below already
      # counts two levels, and only names `Object#dm2` where ruby names `<main>`.

      def where = caller_locations(1, 1).first.label

      class Named
        define_method(:dm) { where }
      end
      p Named.new.dm

      Anon = Class.new { define_method(:dm2) { where } }
      p Anon.new.dm2

      # A computed name never becomes a `DefMethod` node -- already correct.
      name = :dm3
      Anon2 = Class.new { define_method(name) { where } }
      p Anon2.new.dm3

      # A real `def` through a block names the method -- already correct.
      [1].each { def plain = where }
      p plain
    RUBY

    _(result).must_answer <<~'OUT'
      "block in <class:Named>"
      "block (2 levels) in <main>"
      "block (2 levels) in <main>"
      "Object#plain"
    OUT
  end

  it "define method call allocates nothing" do
    result = ze0(<<~'RUBY')
      # A method define_method makes allocates nothing per call: its body runs
      # as a stack image of the block under the receiver, and the block the
      # call was given reaches it through the frame.
      class Base
        def greet(x) = "base #{x}"
      end

      class Kid < Base
        define_method(:greet) { |x| "kid " + super(x) }
        define_method(:with_block) { |&b| [block_given?, b ? b.call(1) : :none] }
        define_method(:defines) { def made = :made; self.class.instance_methods(false).sort }
        define_method(:early) { |n| return :early if n.zero?; :late }
        define_method(:each_twice) { |&b| b.call(1); b.call(2); :done }
        define_method(:lam, ->(a, b = 2) { [a, b] })
        pr = proc { |a| a }
        define_method(:pro, pr)
        alias_method :greet2, :greet
      end

      k = Kid.new
      p k.greet(1), k.greet2(2)
      p k.with_block { |v| v + 1 }, k.with_block
      p k.defines
      p k.early(0), k.early(1)
      p k.each_twice { |v| break :broke if v == 2 }
      p k.each_twice { |v| next :skip }
      p k.lam(1), k.lam(1, 3)
      p((k.lam rescue $!.class))
      p k.pro(5), (k.pro rescue $!.class)
      m = k.method(:with_block)
      p m.call { 7 }, m.unbind.bind(Kid.new).call { 8 }
      p k.method(:greet) == k.method(:greet2), k.method(:greet).hash == k.method(:greet).hash
      p m.arity, m.parameters, k.method(:lam).parameters, k.method(:greet).owner
      events = []
      tp = TracePoint.new(:call, :return) { |t| events << [t.event, t.method_id, t.lineno] if t.method_id == :early }
      tp.enable { k.early(0); k.early(1) }
      p events
      def looped(k)
        i = 0
        total = 0
        while i < 20000
          total += k.lam(i).last
          total += k.greet(i).size
          i += 1
        end
        total
      end
      p looped(k)
      p k.singleton_class.instance_method(:greet).owner
      class Kid
        define_method(:greet) { |x| "again " + x.to_s }
      end
      p k.greet(3), k.greet2(3)

    RUBY

    _(result).must_answer <<~'OUT'
      "kid base 1"
      "kid base 2"
      [false, 2]
      [false, :none]
      [:defines, :each_twice, :early, :greet, :greet2, :lam, :made, :pro, :with_block]
      :early
      :late
      :broke
      :done
      [1, 2]
      [1, 3]
      ArgumentError
      5
      ArgumentError
      [false, 7]
      [false, 8]
      true
      true
      0
      [[:block, :b]]
      [[:req, :a], [:opt, :b]]
      Kid
      [[:call, :early, 12], [:return, :early, 12], [:call, :early, 12], [:return, :early, 12]]
      308890
      Kid
      "again 3"
      "kid base 3"
    OUT
  end

  it "define method from a proc is strict" do
    result = ze0(<<~'RUBY')
      # A method defined from a plain proc still checks METHOD arity when called
      # (`define_method` hardens proc semantics); zeo keeps the proc's lenient
      # binding and pads with nil. The lambda-sourced form already agrees.
      # (Found by the 2026-08-24 probe sweep.)
      c = Class.new
      c.send(:define_method, :two) { |a, b| [a, b] }
      begin
        p c.new.two(1)
      rescue ArgumentError => e
        puts e.message
      end
      p c.new.two(1, 2)
    RUBY

    _(result).must_answer <<~'OUT'
      wrong number of arguments (given 1, expected 2)
      [1, 2]
    OUT
  end

  it "define method from module unbound" do
    result = ze0(<<~'RUBY')
      # `define_method(name, SomeModule.instance_method(:m))` -- a MODULE-owned
      # UnboundMethod binds into any class (CRuby's rule; a CLASS-owned one still
      # requires a descendant). rack installs ERB::Escape#html_escape into
      # Rack::Utils this way without ever including the module.
      module M
        def hi = "from-M(#{self.class})"
      end
      class C
        define_method(:hi2, M.instance_method(:hi))
      end
      p C.new.hi2
    RUBY

    _(result).must_answer "\"from-M(C)\"\n"
  end

  it "define method parameters" do
    result = ze0(<<~'RUBY')
      class C
        define_method(:inc) { |a, b = 5| a + b }
      end
      p C.new.inc(1, 9)
      p C.new.inc(1)
      class D
        define_method(:two) { |a, b| [a, b] }
      end
      r = (D.new.two(1) rescue $!.class); p r
      p D.new.two(1, 2)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      6
      ArgumentError
      [1, 2]
    OUT
  end

  it "define method under private" do
    result = ze0(<<~'RUBY')
      class V1
        private
        define_method(:a) { :a }
        def b = :b
      end

      p V1.private_instance_methods(false).sort
    RUBY

    _(result).must_answer "[:a, :b]\n"
  end

  it "define method with a proc body" do
    result = ze0(<<~'RUBY')
      # `define_method(name, &value)` -- the body is a value the program computes, so
      # there is no block to desugar into a `def`. Every gem that builds methods in a
      # loop uses it; zeo rejected it at compile time even though the runtime
      # `Module#define_method` installs a Proc, a Method or an UnboundMethod body.

      class Greeter
        say = proc { |n| "hi #{n}" }
        define_method(:greet, &say)
        define_method(:now, &::Time.method(:now))

        %w[one two].each_with_index do |name, i|
          define_method(name) { i }
        end
      end

      g = Greeter.new
      p g.greet("world")
      p g.now.class
      p [g.one, g.two]
      p Greeter.instance_method(:greet).arity
    RUBY

    _(result).must_answer <<~'OUT'
      "hi world"
      Time
      [0, 1]
      1
    OUT
  end

  it "send with a name held in a variable reaches a method defined by define_method" do
    result = ze0(<<~'RUBY')
      class Greeter
        define_method(:hello) do
          puts :hi
        end
      end

      name = :hello
      Greeter.new.send(name)
    RUBY

    _(result).must_answer "hi\n"
  end

  it "dynamic define method" do
    result = ze0(<<~'RUBY')
      class BadDynamicDefineMethod
        name = "bad"
        define_method(name) { 1 }
      end
    RUBY

    _(result).must_answer ""
  end

  it "forward args" do
    result = ze0(<<~'RUBY')
      # `...` forwarding for positional arguments (#1288): the compiler synthesizes
      # concrete params from the call sites and forwards them directly -- no rest
      # array / splat. Free function, instance method, class method, multiple sites.
      def target(a, b, c)
        a + b + c
      end
      def fwd(...)
        target(...)
      end
      puts fwd(1, 2, 3)
      puts fwd(10, 20, 30)

      def join2(a, b)
        "#{a}-#{b}"
      end
      def wrap(...)
        join2(...)
      end
      puts wrap("x", "y")

      class Calc
        def add(a, b)
          a + b
        end
        def run(...)
          add(...)
        end
        def self.mul(a, b)
          a * b
        end
        def self.build(...)
          mul(...)
        end
      end
      puts Calc.new.run(3, 4)
      puts Calc.build(3, 4)

      # keyword arguments forward too (keyword params compile to positional C params
      # mapped by name, so synthesizing a key-named param carries them).
      def kw_target(a:, b:)
        a * 10 + b
      end
      def kw_fwd(...)
        kw_target(...)
      end
      puts kw_fwd(a: 3, b: 4)

      def mixed(x, label:)
        "#{label}=#{x}"
      end
      def mixed_fwd(...)
        mixed(...)
      end
      puts mixed_fwd(7, label: "n")

      # chained forwarding: a forwarding method called only via another forward
      # infers its arity transitively from its target (h -> f -> g).
      def leaf(a)
        a * 2
      end
      def mid(...)
        leaf(...)
      end
      def top(...)
        mid(...)
      end
      puts top(21)
    RUBY

    _(result).must_answer <<~'OUT'
      6
      60
      x-y
      7
      12
      34
      n=7
      42
    OUT
  end

  it "issue method vs callee alias" do
    result = ze0(<<~'RUBY')
      # __method__ returns the name the method was DEFINED with, __callee__ the name
      # it was CALLED through -- the two diverge for an aliased method.
      class CalleeTest
        def original_name
          [__method__, __callee__]
        end
        alias aliased_name original_name
      end
      p CalleeTest.new.aliased_name
    RUBY

    _(result).must_answer "[:original_name, :aliased_name]\n"
  end

  it "issue undef method dynamic class body" do
    result = ze0(<<~'RUBY')
      # undef_method called inside a `Class.new { ... }` / `#class_eval { ... }`
      # block raises NoMethodError instead of undefining the method -- it only
      # works in a literal `class ... end` body. This breaks bare `require
      # "delegate"`: Delegator's setup calls `kernel.class_eval { undef_method m }`
      # on a duplicated Kernel module.
      klass = Class.new do
        def foo
          1
        end

        def bar
          2
        end
      end
      klass.class_eval do
        undef_method :bar
      end
      o = klass.new
      p o.foo
      p o.respond_to?(:bar)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      false
    OUT
  end

  it "issue229 uncalled cls method" do
    result = ze0(<<~'RUBY')
      # Issue #229: an unused class method whose body has bare `new(args)`
      # against a defining class with different `initialize` arity used to
      # emit a body that wouldn't C-compile. Sister to issue #224 (which
      # fixed bare-`new` *dispatch* for reachable inherited cls methods);
      # this is the unreached-emit complement. The fix DCEs cls methods
      # with no call site so unreachable bodies never have to type-check.
      #
      # Three Sam-Ruby-filed variants exercise here: solo class (arity
      # mismatch), 3-class inheritance with one leaf called (multiple
      # dead bodies multiply), and default-arg initialize (type mismatch).

      # Variant 1: solo class. Base.create is defined but never called.
      # Pre-fix: `sp_Base_cls_create` emits `return sp_Base_new(lv_attrs)`
      # against a 0-arg `sp_Base_new(void)` and `cc` rejects.
      class Base
        def initialize
          @x = 1
        end
        def x; @x; end

        def self.create(attrs)
          new(attrs)
        end
      end

      b = Base.new
      puts b.x                               # 1

      # Variant 2: 3-class inheritance, only the leaf is called.
      # Pre-fix all three (Base2/Mid/Leaf) emitted cls_create bodies;
      # only Leaf's compiled. With DCE, only Leaf::create is live.
      class Base2
        def initialize
          @v = 0
        end

        def self.create(attrs)
          new(attrs)
        end
      end

      class Mid < Base2
      end

      class Leaf < Mid
        def initialize(x)
          @x = x
        end
        def x; @x; end
      end

      # `Leaf.create(42)` runs the body propagated from Base2.create:
      # `instance = new(attrs)` => `Leaf.new(42)` => Leaf#initialize(42).
      puts Leaf.create(42).x                 # 42

      # Variant 3: default-arg initialize. `sp_Base3_new` is synthesized
      # as `sp_Base3_new(sp_StrIntHash *)` from the default literal, but
      # the uncalled `Base3.create` can't infer its `attrs` ptype so the
      # body's `sp_Base3_new(lv_attrs)` had `lv_attrs : mrb_int` against
      # the declared `sp_StrIntHash *`. DCE drops the body entirely.
      class Base3
        def initialize(attrs = {})
          @v = attrs.length
        end
        def v; @v; end

        def self.create(attrs)
          new(attrs)
        end
      end

      # Demonstrate Base3 still works for the *called* path: explicit
      # `Base3.new` is live, so `sp_Base3_new` is emitted and called.
      # Only `Base3.create` (the uncalled cls method) drops.
      b3 = Base3.new
      puts b3.v                              # 0
    RUBY

    _(result).must_answer <<~'OUT'
      1
      42
      0
    OUT
  end

  it "kwarg name matches positional param" do
    result = ze0(<<~'RUBY')
      # A keyword key binds by name only to a parameter that IS a keyword. A
      # positional parameter merely sharing the name takes the whole hash
      # positionally, the way any other unconsumed keyword hash does. Matching on the
      # name alone made the call look like it supplied no positional argument: the
      # value came back 0, and where the callee had a second parameter the compiler
      # reported a missing keyword instead of the arity error CRuby raises.
      def top(x)
        x
      end
      p top(x: 9)

      class C
        def self.f(attrs)
          attrs
        end

        def g(opts)
          opts
        end

        def h(a, b)
          [a, b]
        end
      end

      p C.f(attrs: 1)
      p C.new.g(opts: 2)
      p C.new.h(1, b: 2)

      # a real keyword parameter of the same name still binds by name
      class D
        def self.f(x: 0)
          x
        end

        def self.g(a, x: 0)
          [a, x]
        end
      end

      p D.f(x: 9)
      p D.g(1, x: 9)

      # and the arity error is the one CRuby raises, not a missing-keyword report
      class E
        def self.f(attrs, extra)
          [attrs, extra]
        end
      end

      begin
        E.f(attrs: 1)
        puts "no raise"
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      {x: 9}
      {attrs: 1}
      {opts: 2}
      [1, {b: 2}]
      9
      [1, 9]
      wrong number of arguments (given 1, expected 2)
    OUT
  end

  it "main using in a method names the rule" do
    result = ze0(<<~'RUBY')
      # `using` called from a method body activates nothing: ruby raises
      # RuntimeError "main.using is permitted only at toplevel", whether the
      # module is anonymous or a constant a refinement actually lives in.
      module Second
        refine Array do
          def second = self[1]
        end
      end

      def use_anonymous
        using Module.new
      end

      def use_named
        using Second
      end

      def self.use_from_a_class_method
        using Second
      end

      [:use_anonymous, :use_named, :use_from_a_class_method].each do |name|
        send(name)
      rescue Exception => e
        puts "#{name}: #{e.class}: #{e.message}"
      end

      # Nothing was activated, so the refinement is still invisible here.
      begin
        [1, 2].second
      rescue NoMethodError
        puts "still refined nowhere"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      use_anonymous: RuntimeError: main.using is permitted only at toplevel
      use_named: RuntimeError: main.using is permitted only at toplevel
      use_from_a_class_method: RuntimeError: main.using is permitted only at toplevel
      still refined nowhere
    OUT
  end

  it "method named self" do
    result = ze0(<<~'RUBY')
      # A method whose name is `self`. Ruby allows it: `def self(token)` with an
      # argument list defines an ordinary instance method called `self`, reachable
      # through `send`. The `parser` gem's AST builder does this.
      #
      # `self` is a keyword the generated program cannot escape and reuse, so it
      # gets a mangled spelling of its own.

      class Builder
        def self(token)
          "made #{token}"
        end
      end

      puts Builder.new.send(:self, "node")
      p Builder.instance_methods(false)
    RUBY

    _(result).must_answer <<~'OUT'
      made node
      [:self]
    OUT
  end

  it "module instance method unbound" do
    result = ze0(<<~'RUBY')
      # Module#instance_method builds an unbound method object; #bind supplies the
      # self and the result behaves as an ordinary bound Method (#2676).
      class Animal
        def breathe; "inhale"; end
        def speak(x); "say #{x}"; end
      end
      m = Animal.instance_method(:breathe)
      p m.name
      p m.arity
      p m.owner
      a = Animal.new
      bm = m.bind(a)
      p bm.call
      p Animal.instance_method(:speak).bind(a).call("hi")
    RUBY

    _(result).must_answer <<~'OUT'
      :breathe
      0
      Animal
      "inhale"
      "say hi"
    OUT
  end

  it "nonliteral define method each" do
    result = ze0(<<~'RUBY')
      class BadDefineMethodEach
        names = [:one, :two]

        names.each do |name|
          define_method("#{name}") { 1 }
        end
      end
    RUBY

    _(result).must_answer ""
  end

  it "per object undef retires the method for that object" do
    result = ze0(<<~'RUBY')
      # `undef_method` through an OBJECT's singleton class retires the name for that
      # one object. zeo recorded nothing: the class still defined the name, so every
      # lookup found it and the call answered where ruby raises.
      #
      # A tombstone, not an absence -- there is no method to remove, only a class
      # definition to stop answering with.
      class Foo
        def close = "class"
        def read = "read"
      end

      g = Foo.new
      g.singleton_class.undef_method(:close)
      p g.respond_to?(:close)
      p(begin
        g.close
      rescue NoMethodError
        :raised
      end)

      # The retirement is that object's alone, and reaches only the name it named.
      p Foo.new.close
      p g.read

      # It outranks a singleton method of the same name installed BEFORE it, and the
      # object can be given a fresh one afterwards.
      h = Foo.new
      h.define_singleton_method(:close) { "mine" }
      p h.close
      h.singleton_class.undef_method(:close)
      p(begin
        h.close
      rescue NoMethodError
        :raised
      end)
      h.define_singleton_method(:close) { "again" }
      p h.close

      # `method_missing` gets its turn, exactly as it does for a name nothing ever
      # defined.
      class Catcher
        def gone = "still here"
        def method_missing(n, *) = "missing:#{n}"
        def respond_to_missing?(_n, _priv = false) = true
      end
      c = Catcher.new
      p c.gone
      c.singleton_class.undef_method(:gone)
      p c.gone
    RUBY

    _(result).must_answer <<~'OUT'
      false
      :raised
      "class"
      "read"
      "mine"
      :raised
      "again"
      "still here"
      "missing:gone"
    OUT
  end

  it "ruby2 keywords marks a define method method" do
    result = ze0(<<~'RUBY')
      class Base
        def m(a = nil, k: :default) = [a, k]
      end
      class ViaDefine < Base
        define_method(:m) { |*args, &blk| super(*args, &blk) }
        ruby2_keywords(:m)
      end
      p ViaDefine.new.m(k: 1), ViaDefine.new.m(2)
      class ViaDef < Base
        ruby2_keywords def m(*args, &blk) = super(*args, &blk)
      end
      p ViaDef.new.m(k: 3)
      class Forward
        define_method(:call) { |*args| target(*args) }
        ruby2_keywords(:call)
        def target(x = 0, y: 9) = [x, y]
      end
      p Forward.new.call(y: 4), Forward.new.call(5)
      p Hash.ruby2_keywords_hash?(ViaDefine.instance_method(:m).then { |um| Class.new(Base) { define_method(:m) { |*a| a.last }; ruby2_keywords(:m) }.new.m(z: 1) })

    RUBY

    _(result).must_answer <<~'OUT'
      [nil, 1]
      [2, :default]
      [nil, 3]
      [0, 4]
      [5, 9]
      true
    OUT
  end

  it "runtime alias binds the body that exists when it runs" do
    result = ze0(<<~'RUBY')
      # `alias_method` copies the method entry that exists WHEN IT RUNS, so a `def`
      # written below it does not reach the alias. The row is concealed until the
      # `def`'s own line, which is also what makes the name undefined above it.
      class T1; end
      T1.class_eval { alias_method :eql?, :== }
      class T1
        def ==(other) = true
      end
      a, b = T1.new, T1.new
      p [a == b, a.eql?(b), a.eql?(a)]
      p T1.instance_method(:eql?).owner.to_s

      # The `send` spelling reaches the same place.
      class T2; end
      T2.send(:alias_method, :same?, :==)
      class T2
        def ==(other) = true
      end
      p [T2.new == T2.new, T2.new.same?(T2.new)]

      # An alias taken BELOW the def copies the def, and a later redefinition does
      # not reach it.
      class T4
        def label = "one"
      end
      T4.class_eval { alias_method :tag, :label }
      class T4
        def label = "two"
      end
      p [T4.new.label, T4.new.tag]

      # Two defs of the name with the alias between them.
      class T5
        def v = 1
      end
      T5.class_eval { alias_method :w, :v }
      class T5
        def v = 2
      end
      p [T5.new.v, T5.new.w]

      # The class-method channel, where the source is an inherited `def self.x`.
      class T7base; def self.tag = "base"; end
      class T7 < T7base; end
      T7.singleton_class.class_eval { alias_method :made, :tag }
      class T7
        def self.tag = "own"
      end
      p [T7.tag, T7.made]

      # A COMPUTED source name leaves every def eager -- the documented limit.
      class T8
        def base = 1
      end
      nm = :base
      T8.class_eval { alias_method :copy, nm }
      p T8.new.copy

      # The compile-time `alias` keyword is a different path and is unchanged.
      class T9
        def one = 1
        alias two one
        def one = 11
      end
      p [T9.new.one, T9.new.two]
    RUBY

    _(result).must_answer <<~'OUT'
      [true, false, true]
      "T1"
      [true, false]
      ["two", "one"]
      [2, 1]
      ["own", "base"]
      1
      [11, 1]
    OUT
  end

  it "runtime alias method covers user and builtin sources" do
    result = ze0(<<~'RUBY')
      # Runtime `Module#alias_method` (computed names, ostruct's bulk-`!` loop
      # shape): aliases of user methods, of builtins (`dup`/`class`), snapshot
      # semantics against a later runtime redefinition, the Symbol return value,
      # NameError for an unresolvable source, and the frozen-class refusal.
      # Expected output oracle-verified verbatim.

      class T
        def greet
          "hi"
        end
      end
      class T
        instance_methods(false).each do |m|
          alias_method "#{m}!", m
        end
      end
      t = T.new
      puts t.greet!
      class T
        ["dup", "class"].each { |m| alias_method "my_#{m}", m.to_sym }
      end
      p t.my_class
      p t.my_dup.class
      class Snap; end
      n1 = :v
      Snap.class_eval { define_method(n1) { "old" } }
      Snap.class_eval do
        [[:v2, :v]].each { |a, b| p alias_method(a, b) }
      end
      Snap.class_eval { define_method(n1) { "new" } }
      o = Snap.new
      p o.v2
      p o.v
      class T
        begin
          [[:x, :nope]].each { |a, b| alias_method(a, b) }
        rescue NameError => e
          puts e.message
        end
      end
      class Fz
        def m
          1
        end
      end
      Fz.freeze
      begin
        Fz.class_eval { [[:m2, :m]].each { |a, b| alias_method(a, b) } }
      rescue FrozenError => e
        puts e.message
      end
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      T
      T
      :v2
      "old"
      "new"
      undefined method 'nope' for class 'T'
      can't modify frozen Class: Fz
      done
    OUT
  end

  it "runtime class alias of inherited method" do
    result = ze0(<<~'RUBY')
      # A `Class.new(Base)` where `Base` is a COMPILED class cannot run any method
      # it inherits: the process aborts with "class_id guarantees this downcast".
      # `alias_method` is only the shape that reaches it first.
      #
      # zeo compiles `Base#greet` into an inherent method on a generated `Base`
      # struct, reached through a trampoline that downcasts the receiver to that
      # struct. A compiled `class Sub < Base` is safe because `analyze::mro`
      # materializes a layout-correct copy of every inherited method onto `Sub` at
      # compile time. `Class.new(Base)` mints its class at RUN time, so there is no
      # copy to materialize: `runtime_class_new` gives it a `DynObject` -- name-keyed
      # ivars, no struct -- and the ancestor walk hands that object to `Base`'s
      # trampoline, which downcasts and aborts.
      #
      # So this is not the `Method`/`UnboundMethod` snapshot bug that
      # `tests/method_object_freezes_its_entry.rb` fixed, and copying the LAYER
      # rather than the body does not close it: re-resolving through the layer finds
      # the same struct-downcasting trampoline. What is missing is the bridge
      # `builtins/value_subclass.rs` already builds for a builtin root -- an instance
      # that answers the runtime subclass for `.class` while carrying the compiled
      # ancestor's own payload for its methods to run against. `Class.new` over a
      # builtin root (`Class.new(String)`) works today for exactly that reason.
      #
      # A body written inside the `Class.new` block is unaffected: those become
      # runtime overlay entries, which take their receiver as an argument.

      class Base
        def greet = "base"
        def with_ivar
          @x = 1
          "iv#{@x}"
        end
      end

      # The plain case -- no alias anywhere.
      Plain = Class.new(Base)
      p Plain.new.greet
      p Plain.new.with_ivar

      # The alias case, which is how this was first found.
      Sub = Class.new(Base) do
        alias_method :old_greet, :greet
        def greet = "new+" + old_greet
      end

      p Sub.new.greet
      p Sub.new.old_greet
      p Sub.instance_method(:old_greet).owner

      # A builtin root already bridges, and must keep working.
      Tagged = Class.new(String)
      p Tagged.new("hi").upcase
      p Tagged.new("hi").class == Tagged
    RUBY

    _(result).must_answer <<~'OUT'
      "base"
      "iv1"
      "new+base"
      "base"
      Sub
      "HI"
      true
    OUT
  end

  it "runtime define method" do
    result = ze0(<<~'RUBY')
      # Runtime metaprogramming (#97): define_method with a computed name, inside a
      # class-body loop whose block captures the loop variable, plus an
      # explicit-receiver define_method and define_singleton_method.

      class Animal
        [:walk, :run, :swim].each do |action|
          define_method(action) { "#{action}ing" }
        end
      end

      a = Animal.new
      puts a.walk
      puts a.run
      puts a.swim
      puts a.respond_to?(:walk)
      puts a.respond_to?(:fly)

      # Explicit-receiver define_method adds a method dynamically.
      Animal.define_method(:name) { "generic animal" }
      puts Animal.new.name

      # define_singleton_method on a specific object.
      dog = Animal.new
      dog.define_singleton_method(:bark) { "woof" }
      puts dog.bark
      puts Animal.new.respond_to?(:bark)

      # define_singleton_method on a class -> a class method.
      Animal.define_singleton_method(:kingdom) { "Animalia" }
      puts Animal.kingdom
    RUBY

    _(result).must_answer <<~'OUT'
      walking
      runing
      swiming
      true
      false
      generic animal
      woof
      false
      Animalia
    OUT
  end

  it "runtime undef method on a module reaches its includers" do
    result = ze0(<<~'RUBY')
      # `Module#undef_method` called at RUNTIME -- from inside a `def self.x` body,
      # where `self` is the module -- retires the name for every class that already
      # includes the module. zeo keeps answering with the original body.
      #
      # The name IS collected: `analyze::collect_runtime_undefs` descends into a
      # `def self.x` body precisely so this shape is seen (a `self` that is the
      # module means the undef really does target it), and the name lands on
      # `ClassInfo::runtime_undefs`, which stops codegen emitting a DIRECT call.
      # So the call site correctly goes through dynamic dispatch.
      #
      # What is missing is the runtime half: the dispatched `undef_method` has to
      # write a TOMBSTONE into the overlay that the MRO walk then honours for every
      # includer, the way `zeo_rt`'s dynamic definition path installs a body. Today
      # the send resolves and does nothing that a later lookup consults, so the
      # static row keeps winning.
      #
      # The gate is `Module#undef_method` reaching a module that has already been
      # included -- a plain `undef_method` in a class BODY is decided at compile
      # time and works (see `tests/a_nested_class_undef_stays_in_that_class.rb`).
      module Retiring
        def self.retire
          undef_method :doomed
        end

        def doomed
          "still here"
        end
      end

      class UsesRetiring
        include Retiring
      end

      p UsesRetiring.new.doomed
      Retiring.retire
      begin
        p UsesRetiring.new.doomed
      rescue NoMethodError
        p :doomed_undefined
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "still here"
      :doomed_undefined
    OUT
  end

  it "singleton body visibility cursor reaches define method" do
    result = ze0(<<~'RUBY')
      # A `private` in a `class << self` body is a CURSOR that persists across a
      # block: methods `define_method` installs after it are PRIVATE singleton
      # methods. Oracle-verified -- `Vis.hidden` raises NoMethodError.
      #
      # zeo consumes a bare `private` in a class body as a COMPILE-TIME cursor
      # (lower/defs.rs) and bakes it into the `def`s that follow. A runtime
      # `define_method` is not a `def`, so nothing carries the cursor to it, and the
      # method comes out public.
      #
      # The runtime half already exists: `runtime_define_method` takes a class-body
      # frame and reads `f.vis`. What is missing is the cursor reaching the
      # singleton's own class body, where the residual statement now runs.
      class Vis
        class << self
          private
          [:hidden].each { |n| define_method(n) { :h } }
          public
          [:shown].each { |n| define_method(n) { :s } }
        end
      end
      p Vis.singleton_class.private_method_defined?(:hidden)
      p Vis.singleton_class.public_method_defined?(:shown)
      p (Vis.hidden rescue $!.class)
      p Vis.shown
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      NoMethodError
      :s
    OUT
  end

  it "undef method on a module reaches its includers" do
    result = ze0(<<~'RUBY')
      # A runtime `undef_method` on a MODULE retires the name for every includer.
      # zeo materializes an included method onto each includer's own flattened
      # table, so the tombstone -- which sits on the module -- was somewhere the
      # flattened probe never looked, and the includer went on answering.
      module Retiring
        def self.retire = undef_method(:doomed)

        def doomed = "still here"
        def kept = "kept"
      end

      class UsesRetiring
        include Retiring
      end

      class AlsoUses
        include Retiring
        def doomed = "my own"
      end

      p UsesRetiring.new.doomed
      p AlsoUses.new.doomed
      Retiring.retire
      begin
        UsesRetiring.new.doomed
      rescue NoMethodError => e
        p e.class
      end
      # A NEARER own definition still wins -- the tombstone is farther up the chain.
      p AlsoUses.new.doomed
      # Everything else the module gave is untouched.
      p UsesRetiring.new.kept
      p UsesRetiring.new.respond_to?(:doomed)
      p UsesRetiring.instance_method(:kept).owner.to_s

      # A subclass of an includer sees it too.
      class Deeper < UsesRetiring; end
      begin
        Deeper.new.doomed
      rescue NoMethodError => e
        p [:deeper, e.class]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "still here"
      "my own"
      NoMethodError
      "my own"
      "kept"
      false
      "Retiring"
      [:deeper, NoMethodError]
    OUT
  end

  it "undef method reflection" do
    result = ze0(<<~'RUBY')
      # `undef_method` on a runtime class is a lookup TERMINATOR, not a deletion:
      # every probe that walks the MRO has to stop at it rather than answering from
      # a still-live ancestor definition.
      class Base
        def greet = "hi"
        def self.describe = "Base"
      end

      Sub = Class.new(Base) do
        undef_method :greet
      end

      p Sub.new.respond_to?(:greet)
      p Sub.new.respond_to?(:greet, true)
      p Sub.method_defined?(:greet)
      p Sub.public_method_defined?(:greet)
      p Sub.private_method_defined?(:greet)
      p Sub.instance_methods(false)
      p Sub.instance_method(:greet) rescue p $!.class

      begin
        Sub.new.greet
      rescue NoMethodError
        puts "NoMethodError"
      end

      # `super` must not reach past the undef either.
      Deeper = Class.new(Sub) do
        define_method(:greet) do
          begin
            super()
          rescue NoMethodError
            "no super"
          end
        end
      end
      p Deeper.new.greet

      # Redefining after the undef clears the tombstone.
      Sub.class_eval { define_method(:greet) { "back" } }
      p Sub.new.greet
      p Sub.new.respond_to?(:greet)
      p Base.new.greet
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
      false
      []
      NameError
      NoMethodError
      "no super"
      "back"
      true
      "hi"
    OUT
  end

  it "visibility" do
    result = ze0(<<~'RUBY')
      class Box
        def run
          self.helper + implicit_helper
        end

        private

        def helper
          10
        end

        def implicit_helper
          helper
        end
      end

      puts Box.new.run

      class A
        def pub_a
          priv_a
        end

        private def priv_a
          "priv_a"
        end
      end

      class B
        def pub_b
          priv_b
        end

        def priv_b
          "priv_b"
        end

        private :priv_b
      end

      puts A.new.pub_a
      puts B.new.pub_b

      class Money
        def initialize(amount)
          @amount = amount
        end

        def greater_than_five
          other = Money.new(5)
          amount > other.amount
        end

        protected

        def amount
          @amount
        end
      end

      puts Money.new(10).greater_than_five

      class Secretive
        private

        def secret
          "shh"
        end
      end

      puts Secretive.new.send(:secret)
    RUBY

    _(result).must_answer <<~'OUT'
      20
      priv_a
      priv_b
      true
      shh
    OUT
  end

  it "wrong arity" do
    result = ze0(<<~'RUBY', path: "ze0/wrong_arity.rb")
      def two(a, b)
        a + b
      end
      puts two(1, 2)
      puts two(1)
    RUBY

    _(result).must_answer "3\n", stderr: <<~'ERR', status: 1
      ze0/wrong_arity.rb:1:in 'Object#two': wrong number of arguments (given 1, expected 2) (ArgumentError)

          caller: ze0/wrong_arity.rb:5
          | puts two(1)
                 ^^^
          callee: ze0/wrong_arity.rb:1
          | def two(a, b)
                ^^^
      	from ze0/wrong_arity.rb:5:in '<main>'
    ERR
  end

  it "zsuper in define method" do
    result = ze0(<<~'RUBY')
      # A bare `super` inside a `define_method` body is an error in ruby:
      #
      #     RuntimeError: implicit argument passing of super from method defined by
      #     define_method() is not supported. Specify all arguments explicitly.
      #
      # zeo runs it as though `super()` had been written, so a program that ruby
      # refuses silently does something -- and something subtly different from what
      # a bare `super` means anywhere else, since a zsuper forwards the CURRENT values
      # of the method's parameters and a `define_method` body has no parameter list to
      # forward from.
      #
      # Ruby refuses rather than guessing precisely because the answer is ambiguous.
      # Accepting it means a `define_method` wrapper written by a macro forwards
      # nothing where the author expected the arguments to carry through, which fails
      # later at the callee rather than here.
      #
      # The explicit form is fine and must stay working (the first case below).

      class Base
        def who(*args) = "base#{args.inspect}"
      end

      explicit = Class.new(Base) { define_method(:who) { |*a| "dm(" + super(*a) + ")" } }
      p explicit.new.who(1, 2)

      zsuper = Class.new(Base) { define_method(:who) { super } }
      begin
        p zsuper.new.who
      rescue RuntimeError => e
        puts "#{e.class}: #{e.message}"
      end

      with_params = Class.new(Base) { define_method(:who) { |a| super } }
      begin
        p with_params.new.who(1)
      rescue RuntimeError => e
        puts "#{e.class}: #{e.message}"
      end

      # A bare `super` in an ordinary `def` is fine.
      ordinary = Class.new(Base) { def who(*args) = "def(" + super + ")" }
      p ordinary.new.who(3)
    RUBY

    _(result).must_answer <<~'OUT'
      "dm(base[1, 2])"
      RuntimeError: implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly.
      RuntimeError: implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly.
      "def(base[3])"
    OUT
  end
end
