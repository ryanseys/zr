# frozen_string_literal: true

require "spec_helper"

describe "Methods: inheritance and ancestors" do
  it "bare super gives the method its block" do
    result = zr(<<~'RUBY')
      # A bare `super` -- no parentheses, no literal block -- forwards the enclosing
      # method's own block to the parent, so the method needs its `__blk` parameter
      # even though nothing in its body says `yield` or `block_given?`.
      #
      # This is a stop the block-use walk has to make on the `super` node itself,
      # not on anything under it. Collapsing that walk onto `for_each_child` dropped
      # the arm, and every method containing a bare `super` silently lost its block
      # parameter -- `Gem::Version#freeze` was the first casualty, and the emitted
      # method simply stopped taking a block.
      class Base
        def each_thing
          yield 1
          yield 2
          :base_done
        end
      end

      class Child < Base
        def each_thing
          super
        end
      end

      acc = []
      p Child.new.each_thing { |v| acc << v }
      p acc

      # `super()` with an explicit empty argument list forwards the block too --
      # only the ARGUMENTS are suppressed, which is a different question.
      class Explicit < Base
        def each_thing
          super()
        end
      end

      acc2 = []
      p Explicit.new.each_thing { |v| acc2 << v * 10 }
      p acc2

      # A LITERAL block on the `super` replaces the forwarded one, so the method
      # does not need its own -- but the literal block's body may still use it.
      class Literal < Base
        def each_thing
          super { |v| yield(v * 100) }
        end
      end

      acc3 = []
      Literal.new.each_thing { |v| acc3 << v }
      p acc3

      # A method whose parent never yields still forwards harmlessly.
      class Quiet
        def go; :quiet; end
      end

      class QuietChild < Quiet
        def go; super; end
      end

      p QuietChild.new.go { :never_called }
    RUBY

    _(result).must_answer <<~'OUT'
      :base_done
      [1, 2]
      :base_done
      [10, 20]
      [100, 200]
      :quiet
    OUT
  end

  it "bare super in a define method block is refused" do
    result = zr(<<~'RUBY')
      class P; def x(*a) = a; end

      class Q < P
        def self.make(a) = define_method(:x) { super }
        make(1)
      end
      begin
        p Q.new.x
      rescue => e
        p e.class, e.message
      end

      class R < P
        def self.make(a) = define_method(:x) { |*| super }
        make(1)
      end
      begin
        p R.new.x(5)
      rescue => e
        p e.class, e.message
      end

      class V < P
        define_method(:x) { super }
      end
      begin
        p V.new.x
      rescue => e
        p e.class, e.message
      end

      # A block of a def keeps the def's arguments.
      class S < P
        def x(a) = [1].map { super }
      end
      p S.new.x(7)

      class U < P
        def x(a)
          pr = proc { super }
          pr.call
        end
      end
      p U.new.x(9)

      class T < P
        define_method(:x) { |a| super(a, 2) }
      end
      p T.new.x(3)

    RUBY

    _(result).must_answer <<~'OUT'
      RuntimeError
      "implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly."
      RuntimeError
      "implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly."
      RuntimeError
      "implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly."
      [[7]]
      [9]
      [3, 2]
    OUT
  end

  it "conditionally defined method is visible to reflection and extend" do
    result = zr(<<~'RUBY')
      # A `def` nested in a `case`/`if` branch (a platform-conditional definition,
      # as in fileutils' StreamUtils_) is registered as an own method, so
      # `instance_methods` and `extend` -- both resolved at compile time in zr --
      # can see it. A branch the compiler folds away (`if false`) still defines
      # nothing, matching CRuby.

      module Inner
        case 1
        when 2 then def flavor; "two"; end
        else def flavor; "other"; end
        end
        if false
          def gated; "on"; end
        end
      end
      p Inner.instance_methods(false).sort
      module Host
        extend Inner
        puts flavor
      end
      p Host.respond_to?(:gated)
    RUBY

    _(result).must_answer <<~'OUT'
      [:flavor]
      other
      false
    OUT
  end

  it "defined super in a module define method" do
    result = zr(<<~'RUBY')
      # `defined?(super)` in a scope with no method NAME of its own, and the bare
      # `super` beside it.
      #
      # Such a scope is either outside any method -- the top level, a class body,
      # where ruby answers nil -- or a block that BECOMES a method at run time
      # (`K.define_method(:m) { }`, and the same call through `send`, which the
      # compiler cannot recognize as a definition at all). Only the run time can
      # tell those apart, and it does: the same method-frame stack
      # `send_super_dynamic` resumes from, empty outside a method.
      #
      # The static classification answered "method" for every one of them, so a body
      # with no super target at all reported one -- and `defined?(super) ? super :
      # fallback`, the idiom a mixin that may or may not have a target is written
      # with, took the `super` branch and raised.
      #
      # The BARE `super` is the other half. A zsuper forwards the method's
      # parameters and a block-shaped body has none, so ruby refuses it by name; a
      # scope that never became a method gets `NoMethodError` instead. The compiler
      # knows which only for the `define_method` spelling it can see, so the run
      # time picks.

      class Base
        def m = "base"
      end
      class Sub < Base
        define_method(:m) { "sub(" + (defined?(super) ? "has" : "none") + ")" }
      end
      p Sub.new.m

      class Lone
        define_method(:n) { defined?(super) ? "has" : "none" }
      end
      p Lone.new.n

      module Mx
      end
      class Host
        include Mx
      end
      Mx.send(:define_method, :q) { defined?(super) ? "has" : "none" }
      p Host.new.q

      # A scope that never becomes a method, in each of its spellings.
      def outside
        [
          (begin; super; rescue => e; [e.class.to_s, e.message]; end),
          (begin; super(); rescue => e; [e.class.to_s, e.message]; end),
          defined?(super).inspect,
        ]
      end
      p outside
      [1].each { p [(begin; super; rescue => e; e.class.to_s; end), defined?(super).inspect] }

      # A block inside a REAL method still means that method's super.
      class Base2
        def m = "base2"
      end
      class Sub2 < Base2
        def m = [1].map { defined?(super) ? super : "none" }
      end
      p Sub2.new.m

      # An explicit-argument super through the `send` spelling reaches the target.
      class Sub3 < Base2
      end
      Sub3.send(:define_method, :m) { "s3(" + super() + ")" }
      p Sub3.new.m

      # A bare one is ruby's own refusal, by either spelling.
      class Sub4 < Base2
      end
      Sub4.send(:define_method, :m) { "s4(" + super + ")" }
      begin
        Sub4.new.m
      rescue => e
        p [e.class.to_s, e.message]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "sub(has)"
      "none"
      "none"
      [["NoMethodError", "super: no superclass method 'outside' for main"], ["NoMethodError", "super: no superclass method 'outside' for main"], "nil"]
      ["NoMethodError", "nil"]
      ["base2"]
      "s3(base2)"
      ["RuntimeError", "implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly."]
    OUT
  end

  it "extend pulls in module instance methods as class methods" do
    result = zr(<<~'RUBY')
      module MathHelpers
        def double(x)
          x * 2
        end
      end
      class Calc
        extend MathHelpers
      end
      puts Calc.double(21)
    RUBY

    _(result).must_answer "42\n"
  end

  it "include method body locals" do
    result = zr(<<~'RUBY')
      # A module instance method with body locals, included into a user class.
      # The method runs on an instance of the class, and its body locals (`found`,
      # `doubled`) work as in any method. The helper lives on a separate class so
      # its return type resolves cleanly (the check is the included method's own
      # body locals, not the callee).
      class Result
        def initialize(v)
          @v = v
        end
        def v
          @v
        end
      end

      class Factory
        def self.make(n)
          Result.new(n * 2)
        end
      end

      module Dispatcher
        def run(n)
          found = Factory.make(n)   # object-typed local, declared in the clone
          doubled = found.v
          doubled + 1
        end
      end

      class Runner
        include Dispatcher
      end

      puts Runner.new.run(5).to_s
    RUBY

    _(result).must_answer "11\n"
  end

  it "inherited class method keeps its own cvars" do
    result = zr(<<~'RUBY')
      # A class variable belongs to the class the code was WRITTEN in, never to
      # the receiver that reached it -- an inherited class method still reads and
      # writes its own class's storage.
      class Base
        @@subs = []
        def self.subs = @@subs
        def self.note(k) = @@subs << k
      end

      class Late < Base
      end

      class Later < Late
      end

      Late.note("late")
      Later.note("later")
      p Base.subs
      p Late.subs
      p Later.subs

      module Counter
        @@hits = 0
        def self.hit = @@hits += 1
      end
      Counter.hit
      p Counter.hit
    RUBY

    _(result).must_answer <<~'OUT'
      ["late", "later"]
      ["late", "later"]
      ["late", "later"]
      2
    OUT
  end

  it "inherited method kwarg block self" do
    result = zr(<<~'RUBY')
      # Two checks, from the shape of a Rails controller test:
      #
      # 1. In `def f(x, y = @ivar)`, the default value of `y` is the object
      #    in @ivar. Two sibling classes (Foo and Bar) both define `status`
      #    and `body`. `r` must be the Bar in @resp, not the first class that
      #    has those methods. The model is
      #    `assert_response(expected, response = @__response)`.
      #
      # 2. A block given to a method runs with the `self` of the code that
      #    wrote the block. A call inside the block to a method of that
      #    `self` goes to the correct object.

      class Foo
        attr_accessor :status, :body
        def initialize
          @status = 100
          @body = "Foo"
        end
      end

      class Bar
        attr_accessor :status, :body
        def initialize
          @status = 200
          @body = "Bar"
        end
      end

      class Outer
        def initialize
          @resp = Bar.new
        end

        # `r` is the Bar in @resp, not a Foo, which also defines
        # .status/.body.
        def check(expected, r = @resp)
          raise "got status=#{r.status}, expected=#{expected}" unless r.status == expected
          raise "got body=#{r.body}" unless r.body == "Bar"
        end

        # The block given to `helper` calls `check` on the Outer that
        # wrote the block.
        def helper(label)
          yield
          puts label
        end

        def run
          helper("from-outer") do
            check(200)
          end
        end
      end

      Outer.new.run
      puts "OK"
    RUBY

    _(result).must_answer "from-outer\nOK\n"
  end

  it "a class method with a default argument takes a call that leaves it out" do
    result = zr(<<~'RUBY')
      # A `def self.m` with a default argument accepts a call that omits
      # it, on a module and on a class.

      # Module form.
      module M
        def self.greet(name, msg = "default")
          name + "/" + msg
        end
      end

      puts M.greet("a")            # a/default
      puts M.greet("a", "world")   # a/world

      # Class form.
      class C
        def self.greet(name, msg = "fromcls")
          name + "/" + msg
        end
      end

      puts C.greet("b")            # b/fromcls
      puts C.greet("b", "explicit")  # b/explicit

      # A subclass inherits the class method and its default.
      class Sub < C
      end

      puts Sub.greet("c")          # c/fromcls
    RUBY

    _(result).must_answer <<~'OUT'
      a/default
      a/world
      b/fromcls
      b/explicit
      c/fromcls
    OUT
  end

  it "method added hook arrives through extend" do
    result = zr(<<~'RUBY')
      # `method_added` reaching a class through `extend`, both standard spellings.
      #
      # The first is the ClassMethods idiom: a module's `included` hook does
      # `base.extend(ClassMethods)`, and `ClassMethods` defines `method_added`.
      # The extend is inside a method that runs at mixin time, so the hook
      # takes effect only at the include. Each later `def` in the class
      # must call it.
      #
      # Kept beside it: the INHERITED spelling. Two shapes of one feature belong
      # in one file, so a change that fixes one and breaks the other cannot pass.
      module Hook
        def self.included(base) = base.extend(ClassMethods)

        module ClassMethods
          def method_added(name)
            (@added ||= []) << name
          end

          def added = @added
        end
      end

      class Uses
        include Hook
        def a; end
        def b; end
      end

      p Uses.added

      # The inherited spelling, so the two are side by side.
      class Base
        def self.method_added(name) = ((@seen ||= []) << name)
        def self.seen = @seen
      end

      class Child < Base
        def one; end
      end

      p Child.seen
    RUBY

    _(result).must_answer "[:a, :b]\n[:one]\n"
  end

  it "method super chain" do
    result = zr(<<~'RUBY')
      # `Method#super_method` walks UP the ancestor chain: it answers the same
      # method as the next ancestor that defines it, re-seated onto that ancestor --
      # so calling the result runs the ancestor's body, not the override it was
      # reached through. `nil` once the chain runs out.

      module Loud
        def greet = "LOUD"
      end

      class Base
        def greet = "base"
      end

      class Middle < Base
        include Loud
        def greet = "middle"
      end

      class Leaf < Middle
      end

      m = Middle.new.method(:greet)
      p m.call
      p m.owner

      # Each step up the chain: Middle -> Loud (the included module) -> Base.
      first = m.super_method
      p first.owner, first.call
      second = first.super_method
      p second.owner, second.call
      p second.super_method

      # The receiver never changes -- only where the lookup resumes.
      p first.receiver.class

      # A leaf that overrides nothing starts at the first real definer, so its
      # chain is one shorter.
      leaf = Leaf.new.method(:greet)
      p leaf.call, leaf.owner
      p leaf.super_method.owner

      # A method no ancestor redefines has no super at all.
      class Solo
        def only = 1
      end
      p Solo.new.method(:only).super_method

      # Builtins participate too: Integer#to_s shadows Kernel#to_s.
      p 1.method(:to_s).owner
      p 1.method(:to_s).super_method.owner

      # UnboundMethod has the same walk.
      u = Middle.instance_method(:greet)
      p u.owner
      p u.super_method.owner
      p u.super_method.super_method.owner
      p u.super_method.super_method.super_method
      p u.super_method.bind(Leaf.new).call

      # Class methods walk the singleton chain the same way. Their `#owner` is a
      # SINGLETON CLASS (`#<Class:Child>`), which zr has no object for, so this
      # asserts the walk itself rather than the owner's spelling.
      class Parent
        def self.build = "parent"
      end
      class Child < Parent
        def self.build = "child"
      end
      cm = Child.method(:build)
      p cm.call, cm.name
      p cm.super_method.call
      p cm.super_method.super_method
    RUBY

    _(result).must_answer <<~'OUT'
      "middle"
      Middle
      Loud
      "LOUD"
      Base
      "base"
      nil
      Middle
      "middle"
      Middle
      Loud
      nil
      Integer
      Kernel
      Middle
      Loud
      Base
      nil
      "LOUD"
      "child"
      :build
      "parent"
      nil
    OUT
  end

  it "method visibility inherit" do
    result = zr(<<~'RUBY')
      # Visibility resolves up the ancestor chain: an inherited method keeps its
      # defining class's visibility, and a subclass may re-declare it (private :m /
      # public :m). respond_to? / method_defined? reflect the effective visibility.

      class Base
        def base_pub; 1; end

        private

        def base_priv; 2; end
      end

      class Sub < Base
        private :base_pub      # demote an inherited public method
        public :base_priv      # promote an inherited private method
        def own_pub; 3; end
      end

      class AttrBase
        private

        def val; 9; end
      end

      class AttrSub < AttrBase
        attr_reader :val       # public attr overrides an inherited private method
      end

      # inherited, not re-declared: keep Base's visibility
      puts Base.new.respond_to?(:base_pub)
      puts Base.new.respond_to?(:base_priv)
      puts Base.method_defined?(:base_pub)
      puts Base.method_defined?(:base_priv)

      # re-declared in Sub: effective visibility flips
      puts Sub.new.respond_to?(:base_pub)        # demoted -> false
      puts Sub.new.respond_to?(:base_pub, true)  # include_all -> true
      puts Sub.new.respond_to?(:base_priv)       # promoted -> true
      puts Sub.new.respond_to?(:own_pub)
      puts Sub.method_defined?(:base_pub)        # demoted -> false
      puts Sub.method_defined?(:base_priv)       # promoted -> true
      puts Sub.private_method_defined?(:base_pub)
      puts Sub.public_method_defined?(:base_priv)

      # a public attr in a subclass overrides an inherited private method
      puts AttrBase.new.respond_to?(:val)        # inherited private -> false
      puts AttrSub.new.respond_to?(:val)         # public attr override -> true
      puts AttrSub.public_method_defined?(:val)  # -> true
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      false
      true
      true
      true
      false
      true
      true
      true
      false
      true
      true
    OUT
  end

  it "methods and instance methods reflect names with visibility and inheritance" do
    result = zr(<<~'RUBY')
      module M
        def helper; end
      end
      class Base
        def pub; end
        private
        def priv; end
      end
      class Sub < Base
        include M
        def own; end
        def pub; end          # override
        def self.factory; end
      end
      puts Sub.instance_methods(false).sort.inspect   # [:own, :pub]
      puts Sub.instance_methods.include?(:helper)      # true (module)
      puts Sub.instance_methods.include?(:pub)         # true
      puts Sub.instance_methods.include?(:priv)        # false (private)
      puts Base.private_instance_methods(false).inspect # [:priv]
      puts M.instance_methods.inspect                  # [:helper]
      puts Sub.singleton_methods.inspect               # [:factory]
      o = Sub.new
      puts o.methods.include?(:own)                    # true
      puts o.methods.include?(:factory)                # false
      puts o.private_methods.include?(:priv)           # true
      puts "s".methods.include?(:upcase)               # true
    RUBY

    _(result).must_answer <<~'OUT'
      [:own, :pub]
      true
      true
      false
      [:priv]
      [:helper]
      [:factory]
      true
      false
      true
      true
    OUT
  end

  it "module method defined accepts the inherit flag" do
    result = zr(<<~'RUBY')
      class Foo; def bar; end; end
      p Foo.method_defined?(:bar)
      p Foo.method_defined?(:bar, true)
      p Foo.method_defined?(:nope, false)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
    OUT
  end

  it "module method defined inherit false restricts to own methods" do
    result = zr(<<~'RUBY')
      # `inherit: false` reports only methods the receiver defines directly --
      # its own defs and attr accessors -- skipping the ancestor walk.

      class Animal; def name; end; attr_accessor :age; end
      class Dog < Animal; def bark; end; end
      p Dog.method_defined?(:bark, false)
      p Dog.method_defined?(:name, false)
      p Dog.method_defined?(:age=, false)
      p Animal.method_defined?(:age, false)
      p Animal.method_defined?(:bark, false)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      false
    OUT
  end

  it "module method defined inherited" do
    result = zr(<<~'RUBY')
      class Animal; def breathe; end; end
      class Dog < Animal; def bark; end; end

      p Dog.method_defined?(:bark)       # own
      p Dog.method_defined?(:breathe)    # user superclass
      p Dog.method_defined?(:object_id)  # inherited from Object/Kernel
      p Dog.method_defined?(:frozen?)    # inherited from Object/Kernel
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
    OUT
  end

  it "modules class method is not inherited by an including class" do
    result = zr(<<~'RUBY')
      module Bag
        def self.macro(n) = define_method(n) { n }
        def self.[](k) = "Bag.[] #{k}"
        def helper = "helper"
        module_function :helper
      end
      include Bag
      p Bag[:k]
      p helper
      p Dir["/definitely/no/such/glob/*"]
      p({ a: 1 }[:a])
      p [10, 20][1]
    RUBY

    _(result).must_answer <<~'OUT'
      "Bag.[] k"
      "helper"
      []
      1
      20
    OUT
  end

  it "per object extend reports the wrong method owner" do
    result = zr(<<~'RUBY')
      # `obj.extend(M)` seats M in THAT OBJECT's singleton ancestry, so the method
      # it supplies is owned by M -- the same rule that now holds for a class-level
      # `extend` (see an_extended_modules_row_answers_as_the_modules_own.rb). zr
      # reports the object's CLASS instead.
      #
      # WHY. A class records the copies an `extend` made in
      # `OverlayEntry::extended_class_methods`, so reflection can tell a copied row
      # from a `def self.x` written on the class. An OBJECT has no such record: both
      # `obj.extend(M)` and `def obj.hi` write straight into the identity-keyed
      # `maps().singletons` table, and nothing afterwards can say which put a name
      # there. Guessing "an extended module that defines the name owns it" is wrong
      # exactly when a later `def obj.hi` shadows one, so the fix is the record, not
      # the guess: an extended-name set beside the singleton table, cleared by every
      # own definition, mirroring what the class side already keeps.
      #
      # Everything else about a per-object extend already agrees, and is asserted in
      # the golden beside this one.
      module Ext
        def hi = 1
      end

      o = Object.new
      o.extend(Ext)
      p o.method(:hi).owner
      p o.method(:hi).unbind.owner
      p o.singleton_method(:hi).owner rescue p $!.class

      # A per-object `def` written after the extend must keep reporting the
      # singleton class, which is what makes the guess unusable.
      def o.hi = 2
      p o.method(:hi).owner
      p o.hi
    RUBY

    _(result).must_answer <<~'OUT'
      Ext
      Ext
      Ext
      #<Class:#<Object:0xADDR>>
      2
    OUT
  end

  it "re scoping an inherited method binds it here" do
    result = zr(<<~'RUBY')
      # `private :inherited_method` does not redefine anything -- it binds the name on
      # THIS class at a new visibility, still running the ancestor's body. Ruby plants
      # a real method entry for it (CRuby's VM_METHOD_TYPE_ZSUPER), which is why the
      # name then answers `private_instance_methods(false)` and
      # `instance_method(:x).owner` on the subclass.

      class Base
        def visible = :visible
        def also = :also
        def hidden = :hidden
        private :hidden
      end

      class Sub < Base
        private :visible
      end

      class Reopened < Base
        public :hidden
      end

      p Sub.instance_methods(false).sort
      p Sub.private_instance_methods(false).sort
      p Sub.instance_method(:visible).owner
      p Sub.new.method(:also).owner

      # The call site has to see the SUBCLASS's answer, not the definition's.
      begin
        Sub.new.visible
      rescue NoMethodError => e
        p e.message
      end
      p Sub.new.send(:visible)
      p Base.new.visible

      # Visibility is inherited from the ancestor's entry, not re-read off the `def`.
      p Base.private_method_defined?(:hidden)
      p Sub.private_method_defined?(:hidden)
      p Reopened.public_method_defined?(:hidden)
      p Reopened.new.hidden

      # Nothing was moved: the ancestor keeps its own answer.
      p Base.private_instance_methods(false).sort
      p Base.instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [:visible]
      Sub
      Base
      "private method 'visible' called for an instance of Sub"
      :visible
      :visible
      true
      true
      true
      :hidden
      [:hidden]
      [:also, :visible]
    OUT
  end

  it "runtime subclass inherited class method" do
    result = zr(<<~'RUBY')
      # A runtime subclass (`Class.new(B)`) dispatches an inherited class method
      # through the nearest REGISTERED ancestor's materialized copy -- whose
      # self-sends were re-resolved from that ancestor's viewpoint -- not the
      # owner's own row. B overrides `leaf`, so `tmpl` through the runtime
      # subclass must see B's override, the same answer the compiled `B.tmpl`
      # call gets (minitest's Runnable/Test split is this exact shape).
      class A
        def self.tmpl = "tmpl:#{leaf}"
        def self.leaf = (raise NotImplementedError, "subclass responsibility")
      end
      class B < A
        def self.leaf = "B-leaf"
      end
      p B.tmpl
      k = Class.new(B)
      p k.tmpl
    RUBY

    _(result).must_answer <<~'OUT'
      "tmpl:B-leaf"
      "tmpl:B-leaf"
    OUT
  end

  it "runtime subclass method reflection" do
    result = zr(<<~'RUBY')
      # `Method`-object reflection on a RUNTIME-minted subclass finds the
      # inherited frozen class methods -- rspec grabs
      # `example_group_class.method(:next_runnable_index_for)` on every
      # describe-created group, and the responds/reflection walk only consulted
      # the receiver's own (nonexistent) registry entry.
      class Base
        def self.next_index(f) = "idx #{f}"
      end
      k = Class.new(Base)
      p k.respond_to?(:next_index)
      m = k.method(:next_index)
      p m.call(1)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "idx 1"
    OUT
  end

  it "subclass calls a non overridden inherited method" do
    result = zr(<<~'RUBY')
      # Closes a real, pre-existing latent gap: a class's own LITERAL methods each
      # get a generated method, but `Dog.new.speak` with no override at all has
      # none to call -- generated structs do not inherit each other's methods. MRO
      # materialization fixes this as a byproduct of doing modules correctly
      # (every MRO-reachable method gets its own Scope on the receiver).

      class Animal
        def speak
          "generic"
        end
      end
      class Dog < Animal
      end
      puts Dog.new.speak
    RUBY

    _(result).must_answer "generic\n"
  end

  it "super channels" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `super` sends through the same three channels an ordinary call does:
      # positionals with a `*` splat spread among them, a keyword Hash of its
      # own, and the block. The Array the runtime reads is built here, so a
      # splat is one different push and nothing else changes.

      class Base
        def go(*args, **kw)
          ["base", args, kw]
        end

        def pair(a, b) = "#{a}/#{b}"
      end

      class Kid < Base
        def go(*args, **kw) = super(*args, **kw)
      end

      class Splatter < Base
        def go(head, *rest) = super(head, *rest, tail: rest.size)

        def pair(a, b) = super(*[a, b])
      end

      p Kid.new.go(1, 2, a: 3)
      p Kid.new.go
      p Splatter.new.go(1, 2, 3)
      p Splatter.new.pair(:x, :y)

      # A module's `super` walks the ancestors above the module, not above the
      # class the method was called on.
      module Loud
        def speak(word)
          "#{super(word)}!"
        end
      end

      class Quiet
        def speak(word) = word
      end

      class Shouter < Quiet
      end
      Shouter.include(Loud)

      p Shouter.new.speak("hi")
      p Shouter.ancestors.take(3).map(&:to_s)

      # A body the runtime installed has no defining class until it runs, so
      # the target comes off the method-frame stack instead.
      P = Module.new do
        def label(*parts, sep: "-")
          "<#{super(*parts, sep: sep)}>"
        end

        def each_upper
          super { |v| yield v.upcase }
        end
      end

      class Plain
        def label(*parts, sep: "-") = parts.join(sep)

        def each_upper
          yield "a"
          yield "b"
        end
      end
      Plain.prepend(P)

      p Plain.new.label("a", "b")
      p Plain.new.label("a", "b", sep: "+")

      seen = []
      Plain.new.each_upper { |v| seen << v }
      p seen

      # A bare `super` still forwards the parameters by their CURRENT values.
      class Renamer < Base
        def pair(a, b)
          a = "#{a}#{a}"
          super
        end
      end
      p Renamer.new.pair("q", "r")
    RUBY

    _(result).must_answer <<~'OUT'
      ["base", [1, 2], {a: 3}]
      ["base", [], {}]
      ["base", [1, 2, 3], {tail: 2}]
      "x/y"
      "hi!"
      ["Shouter", "Loud", "Quiet"]
      "<a-b>"
      "<a+b>"
      ["A", "B"]
      "qq/r"
    OUT
  end

  it "super from an extended module method resolves the singleton chain" do
    result = zr(<<~'RUBY')
      # `extend M` puts M in the receiver's SINGLETON-class chain, so a
      # `super` inside M's method must resolve that chain (most recent
      # extend first), falling back to the runtime walk for builtin
      # defaults.

      module Base
        def greet
          "base"
        end
      end
      module Loud
        def greet
          super + "!"
        end
      end
      class Host
        extend Base
        extend Loud
      end
      puts Host.greet
    RUBY

    _(result).must_answer "base!\n"
  end

  it "super from an override reaches an included module method" do
    result = zr(<<~'RUBY')
      module Tagged
        def tag
          "base(#{super})"
        end
      end
      class Widget
        include Tagged
        def tag
          "widget"
        end
      end
      puts Widget.new.tag
    RUBY

    _(result).must_answer "widget\n"
  end

  it "super in a block" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `super` resumes the MRO walk above the class the `def` was WRITTEN in.
      # A block has no method of its own, so a `super` in one belongs to the
      # method that wrote the block -- and a class method walks the singleton
      # chain instead.

      class Base
        def greet(a, b = 2) = "base #{a} #{b}"
        def with_block = "base #{yield 5}"
        def self.make(x) = "base make #{x}"
        def channels(*xs, **k) = "base #{xs} #{k}"
      end

      class Child < Base
        # A bare `super` sends the parameters by their CURRENT values, which
        # the block has to carry even though it names none of them.
        def greet(a, b = 2)
          a = a.upcase
          [1].map { [1].map { super } }.flatten.first
        end

        # The block a bare `super` forwards is the enclosing method's, the
        # same channel a bare `yield` written there reads.
        def with_block
          [1].map { super }.first
        end

        def self.make(x)
          [1].map { super }.first
        end

        # Every argument channel, forwarded by a bare `super`.
        def channels(*xs, **k) = super
      end

      p Child.new.greet("q")
      p Child.new.with_block { |n| n * 3 }
      p Child.make(4)
      p Child.new.channels(1, 2, a: 3)

      # An inherited class method keeps walking from where it was written.
      class Grand < Child; end
      p Grand.make(9)

      # A lambda is a block too.
      class Lam < Base
        def greet(a, b = 2)
          l = -> { super }
          l.call
        end
      end
      p Lam.new.greet("l")

      # A block written AT the `super` replaces the one that would forward.
      class Blocky < Base
        def with_block
          [1].map { super { |n| n + 100 } }.first
        end
      end
      p Blocky.new.with_block

      # The anonymous channels forward by the names ruby gives them.
      class Anon < Base
        def channels(*, **) = super
      end
      p Anon.new.channels(6, z: 7)

      # A `class << self` body writes the same singleton row a `def self.x` does.
      class Singly < Base
        class << self
          def make(x) = super
        end
      end
      p Singly.make(8)
    RUBY

    _(result).must_answer <<~'OUT'
      "base Q 2"
      "base 15"
      "base make 4"
      "base [1, 2] {a: 3}"
      "base make 9"
      "base l 2"
      "base 105"
      "base [6] {z: 7}"
      "base make 8"
    OUT
  end

  it "super in an aliased define method body names the original" do
    result = zr(<<~'RUBY')
      # `super` in a method define_method made, reached under an alias, looks
      # up the name the method was defined under, as a def reached under an
      # alias does; `defined?(super)` answers for that name too.
      class Base
        def greet(x) = "base #{x}"
        def plain(x) = "plain #{x}"
      end

      class Kid < Base
        define_method(:greet) { |x| ["kid", defined?(super), super(x)] }
        def plain(x) = ["kid", defined?(super), super]
        alias_method :greet2, :greet
        alias_method :plain2, :plain
      end

      k = Kid.new
      p k.greet(1), k.greet2(2)
      p k.plain(1), k.plain2(2)

    RUBY

    _(result).must_answer <<~'OUT'
      ["kid", "super", "base 1"]
      ["kid", "super", "base 2"]
      ["kid", "super", "plain 1"]
      ["kid", "super", "plain 2"]
    OUT
  end

  it "super in dynamic define method" do
    result = zr(<<~'RUBY')
      # `super` inside a `define_method` whose NAME is not a literal symbol. The
      # block body gets its method context (the name and the owner) at run time.
      #
      # The dynamic form is the one metaprogramming actually uses -- a name computed
      # in a loop is the whole reason to reach for `define_method` -- so this is the
      # shape a delegation or wrapper macro hits.
      #
      # The explicit-argument form resolves to Base#who. The bare form raises
      # ruby's OWN RuntimeError about implicit argument passing (see
      # `tests/zsuper_in_define_method.rb`), not a NoMethodError.

      class Base
        def who(*a) = "base#{a.inspect}"
      end

      name = :who

      explicit = Class.new(Base) { define_method(name) { |*a| "dyn(" + super(*a) + ")" } }
      begin
        p explicit.new.who(9)
      rescue NoMethodError => e
        puts "explicit: #{e.class}: #{e.message}"
      end

      bare = Class.new(Base) { define_method(name) { super } }
      begin
        p bare.new.who
      rescue => e
        puts "bare: #{e.class}: #{e.message}"
      end

      # The LITERAL-name form is correct and must stay so.
      lit = Class.new(Base) { define_method(:who) { |*a| "lit(" + super(*a) + ")" } }
      p lit.new.who(1)
    RUBY

    _(result).must_answer <<~'OUT'
      "dyn(base[9])"
      bare: RuntimeError: implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly.
      "lit(base[1])"
    OUT
  end

  it "super resolves in a class method" do
    result = zr(<<~'RUBY')
      # In Ruby `def self.foo` is an ordinary instance method on the SINGLETON
      # class, and singleton classes form a parallel chain --
      # #<Class:C>.super == #<Class:C.superclass> (make_metaclass,
      # class.c:1186) -- so `super` needs no special case. Covers a three-level
      # chain, explicit args, and zsuper forwarding of a defaulted parameter.

      class Foo
        def self.base; 100; end
        def self.greet(name); "hello #{name}"; end
        def self.tag(pfx = "t"); pfx + "-foo"; end
      end
      class Bar < Foo
        def self.base; super * 10; end
        def self.greet(name); super(name.upcase) + "!"; end
        def self.tag(pfx = "t"); super; end
      end
      class Baz < Bar
        def self.base; super + 1; end
      end
      p Foo.base
      p Bar.base
      p Baz.base
      p Bar.greet("matz")
      p Bar.tag
      p Bar.tag("x")
    RUBY

    _(result).must_answer <<~'OUT'
      100
      1000
      1001
      "hello MATZ!"
      "t-foo"
      "x-foo"
    OUT
  end

  it "super site remembers the next method" do
    result = zr(<<~'RUBY')
      # A `super` site keeps the method it reached last, keyed on the chain
      # node it runs from and the name; a redefinition, a new include, a
      # define_method body shared under two names, a module met twice in
      # the chain, a refinement and keywords all still reach ruby's answer.
      class A; def hi(x, k: 1) = "A#{x}#{k}"; end
      class B < A; def hi(x, k: 2) = "B" + super(x, k: k); end
      class C < B; def hi(x, k: 3) = "C" + super; end
      module M; def hi(x, k: 0) = "M" + super; end
      class D < C; include M; def hi(x, k: 4) = "D" + super; end
      objs = [B.new, C.new, D.new]
      3.times { p objs.map { |o| o.hi(1) } }
      class B; def hi(x, k: 2) = "b" + super(x, k: k); end
      3.times { p objs.map { |o| o.hi(2) } }
      class C; include M; end
      3.times { p objs.map { |o| o.hi(3) } }
      module N; def hi(x, k: 0) = "N" + super; end
      D.prepend(N)
      p D.new.hi(4), D.ancestors.take(5)
      BODY = proc { |x| "dm:" + super(x) }
      class E < A
        define_method(:hi, &BODY)
        define_method(:hey, &BODY)
        def hey(x) = "hey" + x.to_s
        alias_method :hey2, :hey
      end
      class F < E; define_method(:hey, &BODY); end
      3.times { p [E.new.hi(5), F.new.hey(6)] }
      class G < A
        def hi(x, k: 7) = [1].map { |i| super(x + i, k: k) }.first
        def with_block = super rescue $!.class
      end
      3.times { p G.new.hi(8), G.new.with_block }
      module R
        refine(A) { def hi(x, k: 9) = "R" + super }
      end
      using R
      3.times { p A.new.hi(10), D.new.hi(11) }
      o = A.new
      def o.hi(x, k: 12) = "S" + super
      3.times { p o.hi(13) }
      class H < A; def hi(x, k: 1) = super() rescue $!.class; end
      p H.new.hi(1)
      class I < A; def bye = super; end
      p (I.new.bye rescue $!.class)


    RUBY

    _(result).must_answer <<~'OUT'
      ["BA12", "CBA13", "DMCBA14"]
      ["BA12", "CBA13", "DMCBA14"]
      ["BA12", "CBA13", "DMCBA14"]
      ["bA22", "CbA23", "DMCbA24"]
      ["bA22", "CbA23", "DMCbA24"]
      ["bA22", "CbA23", "DMCbA24"]
      ["bA32", "CMbA33", "DMCMbA34"]
      ["bA32", "CMbA33", "DMCMbA34"]
      ["bA32", "CMbA33", "DMCMbA34"]
      "NDMCMbA40"
      [N, D, M, C, M]
      ["dm:A51", "dm:hey6"]
      ["dm:A51", "dm:hey6"]
      ["dm:A51", "dm:hey6"]
      "A97"
      NoMethodError
      "A97"
      NoMethodError
      "A97"
      NoMethodError
      "RA109"
      "NDMCMbA110"
      "RA109"
      "NDMCMbA110"
      "RA109"
      "NDMCMbA110"
      "SRA1312"
      "SRA1312"
      "SRA1312"
      ArgumentError
      NoMethodError
    OUT
  end

  it "toplevel include module method" do
    result = zr(<<~'RUBY')
      module M004
        def double004(n); n * 2; end
        def greet004; "hi"; end
      end
      include M004
      p double004(21)
      p greet004

      module M005
        def self.triple005(n); n * 3; end
      end
      include M005
      p M005.triple005(4)
    RUBY

    _(result).must_answer <<~'OUT'
      42
      "hi"
      12
    OUT
  end

  it "unbound method from a module binds to anything" do
    result = zr(<<~'RUBY')
      # Since ruby 3.0 the bind check reads the OWNER, and a MODULE owner imposes no
      # check at all: the receiver does not have to have the module in its ancestry.
      # zr read the class the method was FETCHED from and applied the class rule to
      # every owner, so both halves of that were wrong.
      M = Module.new { def nest = 1 }
      p M.instance_method(:nest).bind(Object.new).call
      p M.instance_method(:nest).bind_call(Object.new)

      module Named
        def named_one = :named
      end
      p Named.instance_method(:named_one).bind(Object.new).call
      p Named.instance_method(:named_one).bind(String).call

      # Fetched from a class that mixes it in, the owner is still the module.
      module Mixin
        def mixed = :m
      end
      class Host
        include Mixin
      end
      um = Host.instance_method(:mixed)
      p um.owner
      p um.bind(Object.new).call
      p um.bind_call(Object.new)

      # A CLASS owner keeps the rule, and the rule reads the owner rather than the
      # class it was fetched from: this one came off `B` and binds an `A`.
      class A
        def x = 1
      end
      class B < A
      end
      b = B.instance_method(:x)
      p b.owner
      p b.bind(A.new).call

      # What must still refuse.
      begin
        A.instance_method(:x).bind(Object.new)
      rescue TypeError => e
        p e.message
      end
      class S
        def self.only = 1
      end
      begin
        S.singleton_class.instance_method(:only).bind(Object.new)
      rescue TypeError => e
        p e.message
      end
      p S.singleton_class.instance_method(:only).bind(S).call
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      :named
      :named
      Mixin
      :m
      :m
      A
      1
      "bind argument must be an instance of A"
      "singleton method called for a different object"
      1
    OUT
  end
end
