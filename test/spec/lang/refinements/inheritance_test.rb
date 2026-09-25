# frozen_string_literal: true

require "spec_helper"

describe "Refinements: inheritance and ancestors" do
  it "anonymous refinement module can be activated" do
    result = zr(<<~'RUBY')
      # `using Module.new { refine C do ... end }` is irb's shape, and the only way to
      # activate a refinement over a class chosen where no constant names the module.
      # The lowering already built the holder and the activation as a PAIR, and a
      # statement is one node -- so at the top level the pair was dropped on the floor
      # and `using` ran as an ordinary call, which raises. It rides in a `Seq` now.
      #
      # `tests/refinement_holder_names_reach_codegen.rb` covers the holder's NAME
      # reaching a generated identifier; this covers the holder being activated at
      # all.
      Named = 1

      using Module.new {
        refine Array do
          def second = self[1]
          def penultimate = self[-2]
        end

        refine Symbol do
          def shout = to_s.upcase + "!"
        end
      }

      p [10, 20, 30].second
      p [10, 20, 30].penultimate
      p :hi.shout

      # A second anonymous holder: the two are named for their byte offsets, so they
      # must stay distinct and both stay active.
      using Module.new { refine Integer do def kb = self * 1024 end }
      p 2.kb
      p [10, 20, 30].second

      # The holder claims no constant, so `Named` still means what it did.
      p Named
    RUBY

    _(result).must_answer <<~'OUT'
      20
      20
      "HI!"
      2048
      20
      1
    OUT
  end

  it "issue runtime refinement module" do
    result = zr(<<~'RUBY')
      # An anonymous refinement module built and used at RUNTIME. Zr implements
      # refinements as a compile-time lexical rewrite over a NAMED module's `refine`
      # blocks, so `Module.new` produces a plain runtime module with no `refine` on
      # it, and `using` has no compile-time module to apply.
      #
      # This is the one thing still standing between zr and irb. The gem is
      # vendored and compiles CLEAN -- zero errors, down from 51 -- and runs
      # deep into its own initialization before stopping at completion.rb:164,
      # which is written exactly like this. Closing it means teaching the existing
      # rewrite this shape: an anonymous `Module.new { refine C do ... end }` passed
      # straight to `using`, which is a bounded extension rather than a new
      # mechanism.
      class Probe
        using Module.new {
          refine ::String do
            def shout = upcase + "!"
          end
        }

        def self.run = "hi".shout
      end

      p Probe.run
    RUBY

    _(result).must_answer "\"HI!\"\n"
  end

  it "operator assignment sends through the refinements in force" do
    result = zr(<<~'RUBY')
      # An operator assignment on an attribute or an index -- `recv.name op= v`,
      # `recv[i] op= v`, their `||=` and `&&=`, and `&.` -- reads, writes and
      # operates through the refinements in force, as each send alone would.
      class Base
        def initialize = @v = 1
        def [](i) = @v
      end
      class Leaf < Base; end
      module Setters
        refine Base do
          def v = @v
          def v=(x)
            @v = x
          end
          def []=(i, x)
            @v = x
          end
        end
        refine Integer do
          def plus_one = self + 1
        end
      end
      using Setters
      l = Leaf.new
      l.v = 5
      p l.v
      l.v += 1
      p l.v
      l.v ||= 0
      l.v &&= l.v * 2
      p l.v
      l[0] += 3
      p l[0]
      l&.v -= 1
      p l.v
      p(l.send(:v=, 9))

    RUBY

    _(result).must_answer <<~'OUT'
      5
      6
      12
      15
      14
      9
    OUT
  end

  it "refine import methods" do
    result = zr(<<~'RUBY')
      module Helpers
        def helper = :helped
      end

      module R
        refine String do
          import_methods Helpers
        end
      end

      using R
      p "x".helper
    RUBY

    _(result).must_answer ":helped\n"
  end

  it "refine in an anonymous module" do
    result = zr(<<~'RUBY')
      # `refine` is a private method of `Module`, so every module has it -- including
      # one built with `Module.new`. zr defines it only for a module introduced by a
      # `module` KEYWORD, so the anonymous form raises
      # `NoMethodError: undefined method 'refine'`.
      #
      # Building the refinement holder at run time is how a library parameterizes one:
      # a `Module.new { refine(target) { ... } }` inside a method is the only way to
      # refine a class chosen by the caller, since the `module` keyword needs a
      # constant name written in the source.
      #
      # `tests/gaps/issue_runtime_refinement_module.rb` covers what happens after a
      # runtime refinement is DEFINED. This is the step before it: the definition is
      # refused outright.

      m = Module.new do
        refine(String) do
          def shout = upcase + "!"
        end
      end
      p m.class
      p m.refinements.size

      module Named
        refine String do
          def whisper = downcase
        end
      end
      p Named.refinements.size

      # Not activated here, so both must still be absent.
      begin
        "x".shout
      rescue NoMethodError => e
        puts "not active: #{e.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Module
      1
      1
      not active: NoMethodError
    OUT
  end

  it "refine singleton class" do
    result = zr(<<~'RUBY')
      # `refine Target.singleton_class` refines Target's CLASS methods: a covered
      # `Target.m` consults the holder, an uncovered one raises as ever, and the
      # refined body runs with the class itself as `self`. The Range pair checks a
      # refined class method beside an ordinary one on the same holder module, and
      # `respond_to?` under the activation answers for the class but not for an
      # instance (the singleton candidate matches only Class receivers).
      module ClassSide
        refine String.singleton_class do
          def build(n) = "built-#{n}"
        end
        refine Range.singleton_class do
          def from(o) = o.is_a?(Range) ? o : (o..o)
        end
      end
      begin
        String.build(1)
      rescue NoMethodError => e
        p e.class
      end
      using ClassSide
      p String.build(2)
      p Range.from(3)
      p Range.from(4..5)
      p [String.respond_to?(:build), 2.respond_to?(:build)]
    RUBY

    _(result).must_answer <<~'OUT'
      NoMethodError
      "built-2"
      3..3
      4..5
      [true, false]
    OUT
  end

  it "refined calls through safe navigation and splats" do
    result = zr(<<~'RUBY')
      # `recv&.m` where a `using` covers `m`. The nil test is the only difference
      # from an ordinary refined call: a nil receiver answers nil and evaluates
      # neither the arguments nor the block.
      module R
        refine String do
          def shout = upcase
          private def quiet = downcase
        end
      end
      module R2
        refine Array do
          def pick(n) = self[n]
          def each_twice(&b) = (each(&b); each(&b))
        end
      end
      using R
      using R2

      s = "hi"
      p s&.shout
      p nil&.shout
      p [s, nil].map { |x| x&.shout }
      begin
        s&.quiet
      rescue NoMethodError => e
        puts e.message
      end

      a = [1, 2]
      p a&.pick(1)
      out = []
      a&.each_twice { |x| out << x }
      p out
      p nil&.pick(0)

      # The receiver is evaluated ONCE, and not at all past the nil test.
      calls = 0
      recv = ->(v) { calls += 1; v }
      p recv.call(nil)&.shout
      p recv.call("ok")&.shout
      p calls

      # A splat and a double-splat at a refined call: the element count is a
      # run-time number, so the arguments travel as an Array.
      module R3
        refine Hash do
          def merged(**kw) = merge(kw)
          def pick(*ns, **kw) = [ns, kw]
        end
      end
      using R3
      h = { a: 1 }
      extra = { b: 2 }
      p h.merged(**extra)
      p h.pick(*[1, 2], **extra)
      p h.merged(c: 3)
      p h&.pick(*[0])
    RUBY

    _(result).must_answer <<~'OUT'
      "HI"
      nil
      ["HI", nil]
      private method 'quiet' called for an instance of String
      2
      [1, 2, 1, 2]
      nil
      nil
      "OK"
      2
      {a: 1, b: 2}
      [[1, 2], {b: 2}]
      {a: 1, c: 3}
      [[0], {}]
    OUT
  end

  it "refinement holder names reach codegen" do
    result = zr(<<~'RUBY')
      # A refinement's holder module is named `#refinement:<Target>` -- deliberately
      # unspellable as a Ruby constant, so it claims no name inside the refining
      # module, and it is the same name CRuby prints for `M.refinements`.
      #
      # `#` and `:` are not identifier characters, so every generated name built
      # from a class NAME has to sanitize. `class_ident`'s nested arm did not, and
      # the mint aborts rather than raising: four gems in the corpus (caps, kgl,
      # kuport, lambit) died with `"__c405_#refinement:String" is not a valid
      # identifier` instead of compiling.
      #
      # The holder only reaches that ident when it has CLASS methods to emit, which
      # is why plain refinements never tripped it. `module_function` inside `refine`
      # is one way -- it makes each `def` a module function of the holder, i.e. a
      # singleton method -- and it is exactly what kgl 0.0.9 ships.
      module Sizes
        refine Integer do
          module_function

          def kb = self * 1024
        end
      end

      # `def self.x` inside `refine` is the other way the holder gets a class method,
      # and the same ident is built for it.
      module Helpers
        refine Float do
          def self.unit = "px"

          def rounded = round(2)
        end
      end

      # `refine ::Hash` anchors at top level, which renders as `::Hash` and flattens
      # to a LEADING DOT: `#refinement:.Hash`. lambit 0.0.2 died on this one.
      module Anchored
        refine ::Hash do
          def second_value = values[1]
        end
      end

      # A qualified target flattens `::` to `.` so the name reads as one leaf.
      module Outer
        class Inner
          def initialize(n) = @n = n
          def n = @n
        end
      end

      module Qualified
        refine Outer::Inner do
          def doubled = n * 2
        end
      end

      # Two refinements of DIFFERENT targets in one module: their holders must stay
      # distinct idents, not collapse into each other.
      module Pair
        refine String do
          def shout = upcase + "!"
        end

        refine Symbol do
          def shout = to_s.upcase + "!"
        end
      end

      using Sizes
      using Helpers
      using Anchored
      using Qualified
      using Pair

      # `module_function` made `kb` a PRIVATE instance method of the refinement, so
      # the refined call needs an explicit send -- the point here is that the holder
      # reached codegen at all, not the visibility.
      p 2.send(:kb)
      p 3.14159.rounded
      p({ a: 1, b: 2 }.second_value)
      p Outer::Inner.new(21).doubled
      p "hi".shout
      p :hi.shout

      # The NAME is Ruby-visible and must not have changed -- only the generated
      # identifier it is mangled into.
      p Pair.refinements.map { |r| r.to_s }.sort
      p Anchored.refinements.map { |r| r.to_s }
      p Sizes.refinements.size
      p Pair.constants
    RUBY

    _(result).must_answer <<~'OUT'
      2048
      3.14
      2
      42
      "HI!"
      "HI!"
      ["#<refinement:String@Pair>", "#<refinement:Symbol@Pair>"]
      ["#<refinement:Hash@Anchored>"]
      1
      []
    OUT
  end

  it "refinement import methods" do
    result = zr(<<~'RUBY')
      # Refinement#import_methods: copies a module's OWN methods into the
      # refinement at their declared visibility; ancestors are not imported.
      module Helpers
        def shout = "#{self}!"
        private def whisper = "(#{self})"
      end

      module Loud
        refine String do
          import_methods Helpers
        end
      end

      # Private on Module, private on Refinement.
      p Module.private_instance_methods(false).include?(:refine)
      p Module.private_instance_methods(false).include?(:using)
      p Refinement.private_instance_methods(false).include?(:import_methods)

      ref = Loud.refinements.first
      p ref.class
      p ref.instance_methods(false).sort
      p ref.private_instance_methods(false).include?(:whisper)

      # Argument validation happens before any import.
      module Bad
        refine String do
          begin
            import_methods Helpers, "nope"
          rescue TypeError => e
            puts e.message
          end
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      Refinement
      [:shout]
      true
      wrong argument type String (expected Module)
    OUT
  end

  it "refinement objects" do
    result = zr(<<~'RUBY')
      # `Module#refinements` answered `[]`, so `Refinement#target` had no receiver
      # to be called on at all.
      #
      # A refine holder is an ORDINARY registered module carrying the refined
      # methods, under a name the source could never write. What makes it a
      # Refinement is the (module, target) pair the compiler marks it with -- the
      # same pair that renders `#<refinement:String@M>` and that `#target` reads.

      module Single
        refine String do
          def shout = upcase + "!"
        end
      end

      r = Single.refinements.first
      p Single.refinements.size
      p r.class
      p r.target
      p r.to_s
      p r.inspect
      p r.name
      p r.ancestors
      p r.instance_methods(false)
      p [r.is_a?(Module), r.is_a?(Class), r.frozen?]
      p Single.refinements.first.equal?(Single.refinements.first)

      # The holder is no constant of the refining module, and the refined method is
      # no method of the target.
      p Single.constants
      p Single.instance_methods(false)
      p String.instance_methods.include?(:shout)

      # Several blocks in one module keep source order.
      module Several
        refine Array do
          def second = self[1]
        end
        refine Hash do
          def only = values.first
        end
        refine Symbol do
          def twice = "#{self}#{self}"
        end
      end
      p Several.refinements.map(&:target)
      p Several.refinements.map(&:to_s)
      p Several.refinements.map { |m| m.instance_methods(false) }

      # A nested target prints its full path.
      module Deep
        refine Process::Tms do
          def spent = utime + stime
        end
      end
      p Deep.refinements.map(&:target)
      p Deep.refinements.map(&:to_s)

      # A module with no `refine` has none, and `Refinement` itself declares one row.
      p Module.new.refinements
      p Comparable.refinements
      p Refinement.instance_methods(false).sort
      p Refinement.superclass
      p Refinement.ancestors
      p Refinement.instance_method(:target).arity
      p Module.instance_method(:refinements).arity

      # And the refinements still WORK, which is the point of all of it.
      using Several
      p [1, 2, 3].second
      p({ a: 1 }.only)
      p :ab.twice
    RUBY

    _(result).must_answer <<~'OUT'
      1
      Refinement
      String
      "#<refinement:String@Single>"
      "#<refinement:String@Single>"
      nil
      [#<refinement:String@Single>]
      [:shout]
      [true, false, false]
      true
      []
      []
      false
      [Array, Hash, Symbol]
      ["#<refinement:Array@Several>", "#<refinement:Hash@Several>", "#<refinement:Symbol@Several>"]
      [[:second], [:only], [:twice]]
      [Process::Tms]
      ["#<refinement:Process::Tms@Deep>"]
      []
      []
      [:target]
      Module
      [Refinement, Module, Object, Kernel, BasicObject]
      0
      0
      2
      1
      "abab"
    OUT
  end

  it "everything lexically after the using sees the refinement, and dispatch is otherwise ordinary" do
    result = zr(<<~'RUBY')
      # Refinements (`Module#refine` / `Kernel#using`), every line oracle-checked
      # against ruby 4.0.7 -- several are not what the documentation leads you to
      # expect.
      #
      # THE RULE, as the oracle behaves: everything lexically AFTER the `using`, in
      # the same file, sees the refinement -- including class and module bodies
      # opened after it, and `def`s written after it. A `def` written BEFORE it does
      # not. Dispatch is otherwise entirely ordinary: `send`, `respond_to?` and
      # `Object#method` all honour it, and only `instance_methods` does not.
      #
      # `refine C do ... end` puts its methods in a hidden holder MODULE, never on
      # the target class -- registering them on the target would leak them past the
      # `using` scope and into `instance_methods`. `using M` records the lexical
      # byte range it covers, and every call site inside one routes through
      # `refined_send`, which tries the holders and then falls back to an ordinary
      # send.
      module M
        refine String do
          def shout = upcase + "!"
          def size = 999
        end
        refine Integer do
          def double = self * 2
        end
      end

      # A refinement is invisible before the `using`, and to a `def` written above it.
      def early(s)
        begin
          s.shout
        rescue NoMethodError
          :not_visible
        end
      end
      begin
        "a".shout
      rescue NoMethodError => e
        p [:before, e.class]
      end

      using M

      p early("x")
      p "hi".shout
      p "hi".size
      p 3.double
      p [1, 2].map { |n| n.double }

      # A `def` and a class body written after the `using` both see it.
      def helper(s) = s.shout
      p helper("ok")
      class Holder
        def call(s) = s.shout
      end
      p Holder.new.call("z")

      # Ordinary dispatch honours it; reflection over the class does not.
      p "hi".respond_to?(:shout)
      p "hi".send(:shout)
      p "hi".method(:shout).owner.class
      p String.instance_methods.include?(:shout)

      # A non-literal receiver, so the guard cannot lean on a static class.
      x = "dyn"
      p x.shout

      # `using` inside a module body scopes to that body.
      module Inner
        using M
        def self.go(s) = s.shout
      end
      p Inner.go("q")
      p M.class

      # The holder the refined methods live in is a constant of nobody's, and
      # `Refinement` is an ordinary `Module` subclass.
      p M.constants
      p Refinement.superclass

      # A second `using` stacks onto the first rather than replacing it.
      module N
        refine Array do
          def second = self[1]
        end
      end
      using N
      p [1, 2, 3].second
      p "still".shout

      # `super` in a refined method reaches what the refinement overrode, and an
      # operator refines like any other name.
      class Widget
        def label = "plain"
      end
      module P
        refine Widget do
          def label = "refined " + super
        end
        refine Integer do
          def +(other) = 999
        end
        # A refinement is active inside its own block, so a sibling refined method
        # is reachable by bare name.
        refine String do
          def bang = self + "!"
          def twice = bang + bang
        end
      end
      using P
      p Widget.new.label
      p 1 + 2
      p "a".twice
    RUBY

    _(result).must_answer <<~'OUT'
      [:before, NoMethodError]
      :not_visible
      "HI!"
      999
      6
      [2, 4]
      "OK!"
      "Z!"
      true
      "HI!"
      Refinement
      false
      "DYN!"
      "Q!"
      Module
      []
      Module
      2
      "STILL!"
      "refined plain"
      999
      "a!a!"
    OUT
  end

  it "reflection entry sees the refinements active at it" do
    result = zr(<<~'RUBY')
      # `send`, `respond_to?` and `method` all honour a refinement in ruby, and all
      # three are ordinary Kernel methods any class may shadow. zr folded the two
      # questions at compile time, which works only where the receiver's class is
      # known -- inside a method body a parameter's class is not, so a refined name
      # was invisible to all three, and a class carrying its own `respond_to?` was
      # answered over.
      module R
        refine Array do
          def second = self[1]
        end
      end
      using R

      # The receiver is a parameter: its class is a runtime fact.
      def q(a) = a.respond_to?(:second)
      def s(a) = a.send(:second)
      def m(a) = a.method(:second).call
      def mo(a) = a.method(:second).owner
      def c(a) = a.second

      p q([1, 2])
      p s([1, 2])
      p m([1, 2])
      p mo([1, 2])
      p c([1, 2])

      # The same five where the class IS known, which already worked.
      p [1, 2].respond_to?(:second)
      p [1, 2].send(:second)
      p [1, 2].method(:second).call
      p [1, 2].method(:second).owner
      p [1, 2].second

      # A name no refinement defines still answers for the unrefined receiver.
      p q([1, 2]) == q([1, 2])
      p({ a: 1 }.respond_to?(:second))
      def r(a) = a.respond_to?(:size)
      p r([1, 2]), r("ab")

      # A class that defines its OWN reflection entry wins the lookup, whether or
      # not the compiler knows the receiver's class.
      class Shadow
        def respond_to?(_n, _all = false) = :shadowed
        def method(_n) = :shadow_method
        def send(_n) = :shadow_send
      end
      def sh(o) = o.respond_to?(:anything)
      def shm(o) = o.method(:anything)
      def shs(o) = o.send(:anything)
      p sh(Shadow.new), shm(Shadow.new), shs(Shadow.new)
      p Shadow.new.respond_to?(:anything), Shadow.new.method(:anything), Shadow.new.send(:anything)

      # `respond_to_missing?` keeps answering for a receiver of an unknown class.
      class Ghost
        def respond_to_missing?(n, _all = false) = n == :spooky
      end
      def g(o) = o.respond_to?(:spooky)
      p g(Ghost.new), Ghost.new.respond_to?(:spooky), g(Ghost.new) == Ghost.new.respond_to?(:boring)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      2
      2
      #<refinement:Array@R>
      2
      true
      2
      2
      #<refinement:Array@R>
      2
      true
      false
      true
      true
      :shadowed
      :shadow_method
      :shadow_send
      :shadowed
      :shadow_method
      :shadow_send
      true
      true
      false
    OUT
  end

  it "using that never runs keeps the refinements before it" do
    result = zr(<<~'RUBY')
      module A
        refine(String) { def shout = "A:#{upcase}" }
      end
      module B
        refine(String) { def shout = "B:#{upcase}" }
      end
      module C
        refine(String) { def whisper = "C:#{downcase}" }
      end

      using A
      using B if false
      p "x".shout

      flag = true
      using C if flag
      p "Y".whisper, "x".shout

      if flag
        using B
      else
        using C
      end
      p "x".shout, "Y".whisper

      using B unless flag
      p "x".shout

    RUBY

    _(result).must_answer <<~'OUT'
      "A:X"
      "C:y"
      "A:X"
      "B:X"
      "C:y"
      "B:X"
    OUT
  end
end
