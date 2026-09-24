# frozen_string_literal: true

require "spec_helper"

describe "Classes: searching and matching" do
  it "case when class" do
    result = zr(<<~'RUBY')
      # Issue #404 Phase 3 Tier 4 follow-up: `case obj when ClassConst`
      # on a poly receiver. Pre-Tier-4 the lowering left ConstantReadNode
      # arms unimplemented for poly recv (literal cascade only handled
      # sym/str/int/float/nil/bool). Module#=== is equivalent to
      # `arg.is_a?(recv)`, so we route through sp_class_le over
      # sp_class_for_poly and the precomputed ancestors.
      #
      # Coverage:
      #   - Class match against a poly recv carrying primitives.
      #   - Multiple primitive class arms in one case.
      #   - else clause.

      def describe(v)
        case v
        when Integer
          "int"
        when String
          "string"
        when Float
          "float"
        when Symbol
          "symbol"
        else
          "other"
        end
      end

      puts describe(42)
      puts describe("hello")
      puts describe(3.14)
      puts describe(:sym)
      puts describe(nil)
    RUBY

    _(result).must_answer <<~'OUT'
      int
      string
      float
      symbol
      other
    OUT
  end

  it "case when class scalar predicate" do
    result = zr(<<~'RUBY')
      # `case <scalar> when ClassConst` previously compiled the
      # class-constant when-arm into a strcmp against the sp_Class
      # struct, failing C compile with "incompatible type for argument
      # 2 of strcmp". The same shape applied to int / float / symbol /
      # bool predicates would have compared the predicate's value
      # against an sp_Class struct. Fix: at compile_when_conds, when
      # the when-arg is a ConstantReadNode naming a built-in class,
      # resolve via Module#=== — match only when the class corresponds
      # to the predicate's kind (Integer / Float for numeric, String
      # for string, Symbol for symbol, TrueClass / FalseClass for
      # bool). Anything else is a static false.

      class Box
        attr_accessor :v
        def initialize; @v = nil; end
        def setstr(s); @v = s; end
      end

      def classify(b)
        v = b.v
        case v
        when String
          "string"
        else
          "other"
        end
      end

      b1 = Box.new
      b1.setstr("hello")
      puts classify(b1)

      # int predicate + class consts
      n = 42
      case n
      when Integer
        puts "int-matched"
      when String
        puts "wrong"
      else
        puts "no"
      end

      # sym predicate + class consts
      s = :hello
      case s
      when Symbol
        puts "sym-matched"
      when String
        puts "wrong-sym"
      else
        puts "no-sym"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      string
      int-matched
      sym-matched
    OUT
  end

  it "case when qualified class" do
    result = zr(<<~'RUBY')
      # `case obj when Mod::Klass` had two bugs:
      #
      # 1. compile_case_stmt emitted the predicate tmp as `sp_<X> *` even
      #    when the predicate's actual storage was a value type
      #    (`sp_<X>` without the pointer) — producing C errors of the
      #    form "initializing 'sp_X *' with an expression of incompatible
      #    type 'sp_X'; take the address with &". The fix routes the
      #    declaration through c_type so value-type classes get the
      #    right C shape.
      #
      # 2. The static-resolution branch in compile_when_conds only matched
      #    ConstantReadNode arguments, so qualified constants
      #    (ConstantPathNode like `Mod::Klass`) fell through to the
      #    poly-receiver path and emitted `<undeclared identifier>` C.
      #    Fix: also accept ConstantPathNode and route through
      #    resolve_const_ref_name to get the registered class name.

      module Mod
        class Klass
          def initialize(v); @v = v; end
          def get; @v; end
        end
        class Other
          def initialize(v); @v = v; end
          def get; @v; end
        end
      end

      k = Mod::Klass.new(1)
      result = case k
               when Mod::Klass then "match"
               when Mod::Other then "other"
               else "neither"
               end
      puts result

      # Plain (non-namespaced) class also exercises the c_type fix, since
      # the pointer-vs-value mismatch was independent of namespacing.
      class Plain
        def initialize; @x = 1; end
      end
      p_inst = Plain.new
      result2 = case p_inst
                when Plain then "plain"
                else "?"
                end
      puts result2
    RUBY

    _(result).must_answer "match\nplain\n"
  end

  it "class literal constructors" do
    result = zr(<<~'RUBY')
      # `Array[...]` and `Range.new(...)` are the constructor spellings of the
      # `[...]` and `(a..b)` literals. Both raised NoMethodError while the literal
      # for the same value worked (#3485, #3486). They desugar to the literal, so
      # what has to hold is that they type and behave as one -- including the
      # element type an array literal carries, and the exclusive form of a range.
      p Array[1, 2, 3]
      p Array[]
      p Array["a", "b"]
      p Array[1.5, 2.5]
      p Array[[1, 2], [3, 4]]

      a = Array[3, 1, 2]
      p a.sort
      p a.length
      p a.push(9)
      p a.map { |x| x * 2 }
      p a.sum

      p Range.new(1, 3).to_a
      p Range.new(1, 3, true).to_a
      p Range.new(1, 3, false).to_a
      p Range.new("a", "c").to_a
      p Range.new(1, 5).sum
      p Range.new(1, 3).include?(2)
      p Range.new(1, 3) == (1..3)
      p Range.new(1, 3, true) == (1...3)

      r = Range.new(2, 4)
      t = 0
      r.each { |i| t += i }
      p t

      # the sibling constructors that already worked stay working
      p Hash[[[:a, 1]]]
      p Array.new(3, 0)
      p [1, 2, 3]
      p (1..3).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      []
      ["a", "b"]
      [1.5, 2.5]
      [[1, 2], [3, 4]]
      [1, 2, 3]
      3
      [3, 1, 2, 9]
      [6, 2, 4, 18]
      15
      [1, 2, 3]
      [1, 2]
      [1, 2, 3]
      ["a", "b", "c"]
      15
      true
      true
      true
      9
      {a: 1}
      [0, 0, 0]
      [1, 2, 3]
      [1, 2, 3]
    OUT
  end

  it "class reopen binds to the current scope" do
    result = zr(<<~'RUBY')
      # A `class Name` statement looks Name up in the CURRENT cref only -- ruby's
      # `vm_define_class` asks the cref's own constant table and mints there on a
      # miss. It never reaches a same-named constant in an enclosing scope, so an
      # outer `class Program` is invisible to the `class Program` below, which
      # reopens the `Program = Data.define(:vertex)` written right beside it.
      #
      # Sow's `lib/sow/gl/op.rb` is this shape, and the body was attached to the
      # outer class: `Sow::GL::Op::Program.new(vertex: 1)` then raised "wrong number
      # of arguments (given 1, expected 0)".

      module Sow
        class Program; end
        module GL
          module Op
            Program = Data.define(:vertex)
            class Program
              def kind = :program
            end
          end
        end
      end
      p Sow::GL::Op::Program.new(vertex: 1).kind
      p Sow::GL::Op::Program.ancestors.include?(Data)
      p Sow::Program.instance_methods(false)

      # A bare READ inside the inner scope sees the inner constant first too: the
      # cref walk asks each scope for classes AND values before moving out.
      module Sow
        module GL
          module Op
            p Program
            def self.get = Program
          end
        end
      end
      p Sow::GL::Op.get

      # The same rule for every other definition shape: a module reopens the module
      # right here, `class X < Base` mints a fresh X here and leaves the outer one
      # untouched, a Class.new-minted X reopens, and a subclass of the Data class
      # names the nearer constant.
      module Outer
        module Shared
          def self.where = :outer
        end
        class Base; end
        class Leaf; end
        Dyn = Class.new
        module Inner
          module Shared
            def self.where = :inner
          end
          class Leaf < Base
            def where = :inner
          end
          Dyn = Class.new
          class Dyn
            def where = :inner_dyn
          end
          class Fresh
            def where = :fresh
          end
        end
        Plain = Data.define(:x)
        module Inner2
          class Plain
            def where = :fresh_plain
          end
          class Sub < Plain
            def where = :sub
          end
        end
        class Made; end
        module Inner3
          Made = Data.define(:a)
          class Sub < Made
            def where = :sub_of_data
          end
        end
      end
      p Outer::Inner::Shared.where, Outer::Shared.where
      p Outer::Inner::Leaf.new.where, Outer::Inner::Leaf.superclass, Outer::Leaf.instance_methods(false)
      p Outer::Inner::Dyn.new.where, Outer::Dyn.instance_methods(false)
      p Outer::Inner::Fresh.new.where
      p Outer::Inner2::Plain.new.where, Outer::Plain.members
      p Outer::Inner2::Sub.new.where, Outer::Inner2::Sub.superclass
      p Outer::Inner3::Sub.new(a: 1).where, Outer::Inner3::Sub.ancestors.include?(Data)
    RUBY

    _(result).must_answer <<~'OUT'
      :program
      true
      []
      Sow::GL::Op::Program
      Sow::GL::Op::Program
      :inner
      :outer
      :inner
      Outer::Base
      []
      :inner_dyn
      []
      :fresh
      :fresh_plain
      [:x]
      :sub
      Outer::Inner2::Plain
      :sub_of_data
      true
    OUT
  end

  it "class values" do
    result = zr(<<~'RUBY')
      class Shape
        def initialize(name)
          @name = name
        end

        def name
          @name
        end
      end

      class Circle < Shape
      end

      factory = Circle
      c = factory.new("round")
      puts c.name
      puts c.class
      puts c.class == Circle
      puts c.is_a?(Shape)
      puts c.instance_of?(Shape)
      puts Circle.ancestors.include?(Shape)

      [1, "one", :one, nil, factory].each do |v|
        puts v.class
      end

      case c
      when Circle
        puts "circle branch"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      round
      Circle
      true
      true
      false
      true
      Integer
      String
      Symbol
      NilClass
      Class
      circle branch
    OUT
  end

  it "core helper is in no method list" do
    result = zr(<<~'RUBY')
      # A helper the core library keeps for itself, where CRuby has no
      # method at all, shows in no list and answers no respond_to?.
      p Exception.private_instance_methods(false).sort
      p Exception.instance_methods(false).include?(:decorate)
      p RuntimeError.new("x").respond_to?(:decorate, true)
      p Exception.private_method_defined?(:decorate), Exception.method_defined?(:decorate)

      e = RuntimeError.new("x")
      p e.private_methods.include?(:decorate), e.methods.include?(:full_message)

      # Methods the core makes for the program stay listed.
      S = Struct.new(:a)
      p S.instance_methods(false).sort
      D = Data.define(:b)
      p D.instance_methods(false).sort

    RUBY

    _(result).must_answer <<~'OUT'
      [:initialize, :method_missing, :respond_to_missing?]
      false
      false
      false
      false
      false
      true
      [:a, :a=]
      [:b]
    OUT
  end

  it "index op write value position" do
    result = zr(<<~'RUBY')
      # `h[k] op= v` used as an expression, with a receiver or key that is not a
      # plain variable or literal.
      #
      # The value form ran the write and then re-read the slot to produce the value,
      # which re-emitted the receiver and key expressions -- so it accepted only
      # shapes it could safely evaluate twice, and declined everything else outright.
      # A method-call key is the common one: `v[s.tag] += 1` as the last expression
      # of a block is in value position, and a block lifted to a proc puts it there.
      #
      # Both are evaluated once now, into temps the write and the read-back share,
      # which is also what CRuby promises.

      # the reported shape: an indexed operator-write as a block's value, on a
      # captured local, keyed by a method call
      class Tagged
        def initialize(t)
          @t = t
        end

        def tag
          @t
        end
      end

      v = {}
      [Tagged.new("a"), Tagged.new("a"), Tagged.new("b")].each do |s|
        v[s.tag] ||= 0
        v[s.tag] += 1
      end
      p v

      # in value position directly
      w = {}
      w["k"] ||= 0
      p(w["k"] += 5)
      p w

      # the key is evaluated exactly once
      $calls = 0
      def key_once
        $calls += 1
        "k"
      end

      h = {"k" => 10}
      p(h[key_once] += 1)
      p $calls
      p h

      # the receiver is evaluated exactly once
      $rcalls = 0
      def recv_once(x)
        $rcalls += 1
        x
      end

      g = {"k" => 1}
      p(recv_once(g)["k"] += 2)
      p $rcalls
      p g

      # an array receiver, with a computed index
      a = [1, 2, 3]
      def idx
        1
      end
      p(a[idx] += 10)
      p a

      # a nested receiver expression
      m = {"outer" => [5]}
      p(m["outer"][0] += 1)
      p m

      # string values fold too
      s = {"k" => "x"}
      p(s[key_once] += "y")
      p s

      # a poly-keyed hash reached through a method call on the key
      class Box
        def initialize(n)
          @n = n
        end

        def n
          @n
        end
      end

      counts = {}
      [Box.new(1), Box.new(1), Box.new(2)].each do |b|
        counts[b.n] ||= 0
        counts[b.n] += 1
      end
      p counts
    RUBY

    _(result).must_answer <<~'OUT'
      {"a" => 2, "b" => 1}
      5
      {"k" => 5}
      11
      1
      {"k" => 11}
      3
      1
      {"k" => 3}
      12
      [1, 12, 3]
      6
      {"outer" => [6]}
      "xy"
      {"k" => "xy"}
      {1 => 2, 2 => 1}
    OUT
  end

  it "is a answers a class in one step and an open chain by a walk" do
    result = zr(<<~'RUBY')
      # `is_a?` with a class argument answers from the receiver's list of
      # superclasses; an uninitialized class (Class.allocate) has an open chain,
      # which `Class.new` refuses to inherit and the `class` keyword accepts,
      # and it answers by a walk; a subclass under it never gets an allocator.
      class A; end
      class B < A; end
      class C < B; end
      module M; end
      class D < C; include M; end

      c = C.new
      d = D.new
      p [c.is_a?(A), c.is_a?(B), c.is_a?(C), c.is_a?(D), c.is_a?(M), c.is_a?(Object), c.is_a?(BasicObject)]
      p [d.is_a?(A), d.is_a?(C), d.is_a?(D), d.is_a?(M), d.is_a?(Comparable), d.kind_of?(Kernel)]
      p [A === c, C === c, D === c, M === d, Class === c, Module === C, Class === C]
      s = c.singleton_class
      p [c.is_a?(s), C.new.is_a?(s), s.is_a?(Class), C.is_a?(Class), C.is_a?(Module), C.is_a?(A)]

      open = Class.allocate
      begin
        Class.new(open)
      rescue TypeError => e
        p [e.class, e.message]
      end
      Open = open
      class Under < Open; end
      begin
        Under.allocate
      rescue TypeError => e
        p [e.class, e.message]
      end
      p [Under.ancestors, Under.is_a?(Class), C.new.is_a?(Under)]
      def open.tag = :before
      open.send(:initialize, A)
      p [Under.ancestors.take(4), Open.superclass, C.new.is_a?(Under), A.new.is_a?(Open), open.new.is_a?(A), open.new.is_a?(Under)]
      p [(open.tag rescue :gone), open.singleton_class.instance_methods(false)]
      begin
        Under.new
      rescue TypeError => e
        p [e.class, e.message]
      end
      begin
        open.send(:initialize, A)
      rescue TypeError => e
        p [e.class, e.message]
      end

      begin
        c.is_a?(3)
      rescue TypeError => e
        p [e.class, e.message]
      end
      p [1.is_a?(Integer), 1.is_a?(Comparable), nil.is_a?(NilClass), :s.is_a?(Symbol), 1.5.is_a?(Float), 1.instance_of?(Integer), 1.instance_of?(Numeric)]
      case c
      when D then p :d
      when B then p :b
      end
      begin
        raise IOError, "x"
      rescue StandardError => e
        p [e.is_a?(IOError), e.is_a?(StandardError), e.class.ancestors.index(StandardError)]
      end


    RUBY

    _(result).must_answer <<~'OUT'
      [true, true, true, false, false, true, true]
      [true, true, true, true, false, true]
      [true, true, false, true, false, true, true]
      [true, false, true, true, true, false]
      [TypeError, "can't inherit uninitialized class"]
      [TypeError, "allocator undefined for Under"]
      [[Under, Open], true, false]
      [[Under, Open, A, Object], A, false, false, true, false]
      [:gone, []]
      [TypeError, "allocator undefined for Under"]
      [TypeError, "already initialized class"]
      [TypeError, "class or module required"]
      [true, true, true, true, true, true, false]
      :b
      [true, true, 1]
    OUT
  end

  it "predicate class arg" do
    result = zr(<<~'RUBY')
      # any?/all?/none?/one? with a Class pattern match by ===; grep(Class)
      # filters, including over typed arrays where the answer is static.
      p [1, 2, 3].all?(Integer)
      p [1, 2, 3].any?(String)
      p [1, "a"].all?(Integer)
      p [1, "a"].any?(String)
      p [1, 2].none?(String)
      p [1, "a", 2].one?(String)
      p [1, 2, 3].grep(Integer)
      p ["a", 1, "b"].grep(String)
      p [1, 2.5, "x"].grep(Numeric)
      p [1, 2, 3].any?(2)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      true
      true
      [1, 2, 3]
      ["a", "b"]
      [1, 2.5]
      true
    OUT
  end

  it "toplevel def is one body for every class" do
    result = zr(<<~'RUBY')
      # A definition on the universal spine -- Object, Kernel, BasicObject -- is
      # inherited by every class in the program, and zeo emits its body ONCE rather
      # than once per class. This pins the four things that makes observable.
      #
      # An ivar a shared body touches must land on the RECEIVER, a constant it reads
      # must resolve against Object, `self` must be the receiver, and the private
      # visibility a top-level `def` carries in ruby must survive on every carrier.

      CONST = "toplevel-const"

      def stash(v) = @stashed = v
      def fetch_stashed = @stashed
      def read_const = CONST
      def which_self = self.class.name

      module Kernel
        def kernel_reopened = "kernel-#{self.class}"
      end

      class Widget
        ONLY_HERE = "widget-const"
        def initialize = @own = 1

        def use_all
          stash(:from_widget)
          [fetch_stashed, read_const, which_self, kernel_reopened, @own, ONLY_HERE]
        end
      end

      class Gadget < Widget
        def initialize
          super
          @extra = 2
        end

        def peek
          stash(:from_gadget)
          [fetch_stashed, @own, @extra, read_const]
        end
      end

      widget = Widget.new
      p widget.use_all
      gadget = Gadget.new
      p gadget.peek

      # The ivar the shared body wrote belongs to the receiver, not to Object, and
      # each receiver keeps its own.
      p [widget.instance_variables.sort, gadget.instance_variables.sort]

      # A top-level `def` is PRIVATE, on every class that inherits it.
      p [widget.respond_to?(:read_const), widget.private_methods.include?(:read_const)]
      p [widget.send(:read_const), 1.send(:read_const), "s".send(:read_const)]

      # Reflection still names the real owner rather than the carrier.
      p [widget.method(:read_const).owner, Widget.instance_method(:read_const).owner]
      p [widget.is_a?(Kernel), Widget.include?(Kernel)]

      # A reopened Kernel reaches every class the same way, and `self` inside it is
      # the receiver.
      p [widget.send(:kernel_reopened), gadget.send(:kernel_reopened), 1.send(:kernel_reopened)]
    RUBY

    _(result).must_answer <<~'OUT'
      [:from_widget, "toplevel-const", "Widget", "kernel-Widget", 1, "widget-const"]
      [:from_gadget, 1, 2, "toplevel-const"]
      [[:@own, :@stashed], [:@extra, :@own, :@stashed]]
      [false, true]
      ["toplevel-const", "toplevel-const", "toplevel-const"]
      [Object, Object]
      [true, true]
      ["kernel-Widget", "kernel-Gadget", "kernel-Integer"]
    OUT
  end

  it "unknown qualified superclass" do
    result = zr(<<~'RUBY')
      # A superclass naming a constant the program never defines.
      #
      # CRuby evaluates the superclass expression when the definition RUNS, raises
      # `NameError` there, and never brings the class into being. zeo does the same by
      # rewriting the whole definition to the bare constant read -- but only once it
      # agrees the name is unknown, and the test for that read the LAST segment only.
      #
      # So `class Tilt < ::Tilt::Template` counted as known because some unrelated
      # `Template` was assigned somewhere in the program, and the definition was
      # registered instead of deferred -- failing later as an unknown superclass
      # rather than raising where Ruby raises. temple, wicked_pdf and dotenv all
      # write that self-shadowing shape against a gem that may not be installed.

      # An unrelated constant that happens to share the leaf.
      module Rendering
        Template = "not the one temple means"
      end

      p Rendering::Template

      begin
        class Tilt < ::Tilt::Template
        end
      rescue NameError => e
        p e.class
        p e.message.include?("Tilt")
      end

      # The class never came into being.
      p defined?(Tilt).nil?

      # A bare leaf is still resolved leniently: `Template` here could name the
      # constant above through the lexical chain, so it is NOT deferred -- it is a
      # genuine compile-time question, and answering it "unknown" would be wrong.
      module Rendering
        class Sub
          def call
            "still compiles"
          end
        end
      end

      p Rendering::Sub.new.call
    RUBY

    _(result).must_answer <<~'OUT'
      "not the one temple means"
      NameError
      true
      true
      "still compiles"
    OUT
  end
end
