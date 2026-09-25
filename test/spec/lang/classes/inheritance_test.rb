# frozen_string_literal: true

require "spec_helper"

describe "Classes: inheritance and ancestors" do
  it "bare super forwards current arguments" do
    result = zr(<<~'RUBY')
      # Forwards the CURRENT bindings (the reassigned `name`), through
      # required and optional params alike.

      class A
        def greet(name, punct = ".")
          "hi #{name}#{punct}"
        end
      end

      class B < A
        def greet(name, punct = ".")
          name = name + "!"
          super
        end
      end

      puts B.new.greet("bob")
      puts B.new.greet("bob", "?")
    RUBY

    _(result).must_answer "hi bob!.\nhi bob!?\n"
  end

  it "bare super forwards rest and keyword params" do
    result = zr(<<~'RUBY')
      class C
        def count(*nums)
          nums.length
        end
      end

      class D < C
        def count(*nums)
          super * 10
        end
      end

      puts D.new.count(1, 2, 3)

      class E
        def kw(a:, b: 2)
          "a=#{a} b=#{b}"
        end
      end

      class F < E
        def kw(a:, b: 2)
          "got " + super
        end
      end

      puts F.new.kw(a: 1, b: 9)
    RUBY

    _(result).must_answer "30\ngot a=1 b=9\n"
  end

  it "bare super forwards the current methods own params" do
    result = zr(<<~'RUBY')
      # Bare `super` (no parens) forwards the CURRENT method's own already-
      # bound parameter values positionally -- also unbound before this fix
      # (same root cause as the explicit-args case above).

      class Animal
        def initialize(name)
          @name = name
        end
        def name
          @name
        end
      end

      class Dog < Animal
        def initialize(name)
          super
          @greeting = "woof from #{name}"
        end
        def greeting
          @greeting
        end
      end

      d = Dog.new("Rex")
      puts d.name
      puts d.greeting
    RUBY

    _(result).must_answer "Rex\nwoof from Rex\n"
  end

  it "bare super from anonymous splat" do
    result = zr(<<~'RUBY')
      class A
        def m(a = 1, *rest, k: 2, **kw) = [a, rest, k, kw]
      end

      class B < A
        def m(*) = super
      end

      p B.new.m(9, k: 3, z: 4)
    RUBY

    _(result).must_answer "[9, [{k: 3, z: 4}], 2, {}]\n"
  end

  it "built in hierarchy extension classes are real and ancestor matched" do
    result = zr(<<~'RUBY')
      # `KeyError < IndexError` -- exercises the extended built-in hierarchy
      # (an addition beyond the original minimal foundation).

      begin
        raise KeyError, "missing"
      rescue IndexError => e
        puts "caught KeyError via IndexError: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer "caught KeyError via IndexError: missing\n"
  end

  it "builtin subclasses" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A user subclass of a builtin. The sidecar names the parent, and the
      # REGISTRAR follows from the ancestors the backend works out -- a payload
      # wrapper for `Array`/`String`/`Hash`, a definition with no instances for
      # an immediate, the exception registrar for an exception.

      class Stack < Array
        def peek = last
      end

      s = Stack.new
      s.push(1)
      s << 2
      p s
      p [s.size, s.peek, s.class]
      p s.push(3).class            # a self-return re-wraps to Stack
      p s.map { |x| x * 10 }
      p s.map { |x| x }.class      # a NEW array is a plain Array
      p [s.is_a?(Array), s.is_a?(Enumerable)]
      p Stack.new([5, 6, 7]).sum

      class Tag < String
        def shout = "#{upcase}!"
      end

      t = Tag.new("hi")
      p [t.shout, t.class, t == "hi", "hi" == t]
      p({ "k" => 42 }[Tag.new("k")])

      class Counter < Hash
        def initialize = super(0)
      end

      c = Counter.new
      c[:a] += 1
      c[:b] += 1
      p [c[:a], c[:b], c[:missing]]
      p c

      # An immediate has no instances at all: the DEFINITION is legal and `.new`
      # raises what CRuby raises.
      class MyInt < Integer; end
      p [MyInt.superclass, MyInt.ancestors.include?(Numeric)]
      begin
        MyInt.new
      rescue NoMethodError => e
        puts e.message
      end

      # A builtin with an allocator is an ordinary object.
      class Measure < Numeric; end
      p [Measure.superclass, Measure < Comparable]

      # An exception subclass keeps the native message and backtrace surface.
      class Refused < ArgumentError
        def initialize(what) = super("refused #{what}")
      end
      begin
        raise Refused, "this"
      rescue StandardError => e
        p [e.class, e.message, e.is_a?(ArgumentError)]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [2, 2, Stack]
      Stack
      [10, 20, 30]
      Array
      [true, true]
      18
      ["HI!", Tag, true, true]
      42
      [1, 1, 0]
      {a: 1, b: 1}
      [Integer, true]
      undefined method 'new' for class MyInt
      [Numeric, true]
      [Refused, "refused this", true]
    OUT
  end

  it "class body dsl call" do
    result = zr(<<~'RUBY')
      # self in a class body is the class, so a receiver-less call there naming a class
      # method is a real call. So a declarative class-body DSL records its value, and
      # the read afterwards gives that value, not nil.
      # In a subclass, the DSL method writes the subclass's own class-level ivar, not
      # the base class's -- also when it reaches the ivar through a sibling method.
      class Base
        def self.key(k = nil)
          @key = k if k
          @key
        end
      end

      class A < Base
        key :a
      end
      class B < Base
        key :b
      end
      p A.key
      p B.key
      p Base.key

      class Own
        def self.tag(t = nil)
          @tag = t if t
          @tag
        end
        tag :own
      end
      p Own.tag

      # The DSL method names no ivar itself: it reaches one through a sibling class
      # method the subclass also inherits unchanged.
      class Model
        def self.fields
          @fields ||= []
        end
        def self.field(n, type = :string)
          fields.push([n, type])
        end
      end

      class User < Model
        field :id, :int
        field :name
      end
      class Post < Model
        field :title
      end
      p User.fields
      p Post.fields
      p Model.fields

      module Notes
        def self.note(s); (@notes ||= []).push(s); end
        def self.notes; @notes || []; end
        note "from the module body"
      end
      p Notes.notes
    RUBY

    _(result).must_answer <<~'OUT'
      :a
      :b
      nil
      :own
      [[:id, :int], [:name, :string]]
      [[:title, :string]]
      []
      ["from the module body"]
    OUT
  end

  it "class declaration reaches the inherited hook" do
    result = zr(<<~'RUBY')
      # `Super.inherited(C)` fires when the class is CREATED -- once per class, in
      # document order, and only for a hook already installed by then.
      class Base
        def self.inherited(k)
          puts "inherited #{k}"
          super
        end
      end
      class A < Base; end
      class B < A; end
      class A; end  # reopen: creates nothing
      class Silent
        def self.inherited(k) = puts("late hook #{k}")
      end
      class BeforeHook < Silent; end
      p [A.name, B.name]
    RUBY

    _(result).must_answer <<~'OUT'
      inherited A
      inherited B
      late hook BeforeHook
      ["A", "B"]
    OUT
  end

  it "class reflection" do
    result = zr(<<~'RUBY')
      # Classes and modules answer reflection queries about their constants,
      # methods, and class variables.
      module Config
        VERSION = "1.0"
        @@count = 0
      end

      # const_get / const_defined? resolve a literal name against the class's
      # constant registry (a String or Symbol name both work).
      puts Config.const_get(:VERSION)         # 1.0
      p Config.const_defined?(:VERSION)       # true
      p Config.const_defined?("MISSING")      # false

      # A missing constant raises NameError; a malformed name is a different error.
      begin
        Config.const_get(:Nope)
      rescue NameError => e
        puts e.message                        # uninitialized constant Config::Nope
      end
      begin
        Config.const_defined?("lower")
      rescue NameError => e
        puts e.message                        # wrong constant name lower
      end

      # method_defined? walks the ancestry, so inherited methods count too.
      class Animal
        def breathe; end
      end
      class Dog < Animal
        def bark; end
      end
      p Dog.method_defined?(:bark)            # true (own)
      p Dog.method_defined?(:breathe)         # true (inherited)
      p Dog.method_defined?(:object_id)       # true (from Object)
      p Dog.method_defined?(:nope)            # false

      # class_variable_get/set/defined? reflect over @@ storage.
      p Config.class_variable_defined?(:@@count)  # true
      Config.class_variable_set(:@@count, 7)
      p Config.class_variable_get(:@@count)       # 7
    RUBY

    _(result).must_answer <<~'OUT'
      1.0
      true
      false
      uninitialized constant Config::Nope
      wrong constant name lower
      true
      true
      true
      false
      true
      7
    OUT
  end

  it "class reflection builtins" do
    result = zr(<<~'RUBY')
      p Enumerator.name
      p Enumerator.ancestors
      Pt = Struct.new(:x)
      p Pt.name
      p Pt.ancestors
      p Pt.superclass
      p Rational.name
      p Regexp.name
      p Complex.ancestors
      p Range.ancestors
      p Complex.superclass
      p Integer.ancestors
      p Symbol.ancestors
    RUBY

    _(result).must_answer <<~'OUT'
      "Enumerator"
      [Enumerator, Enumerable, Object, Kernel, BasicObject]
      "Pt"
      [Pt, Struct, Enumerable, Object, Kernel, BasicObject]
      Struct
      "Rational"
      "Regexp"
      [Complex, Numeric, Comparable, Object, Kernel, BasicObject]
      [Range, Enumerable, Object, Kernel, BasicObject]
      Numeric
      [Integer, Numeric, Comparable, Object, Kernel, BasicObject]
      [Symbol, Comparable, Object, Kernel, BasicObject]
    OUT
  end

  it "class subclasses" do
    result = zr(<<~'RUBY')
      # Class#subclasses returns the direct, defined subclasses from the compile-time
      # class graph. The elements are boxed classes, and #to_s works on them. The test
      # "class subclasses name" checks `.name`.
      class Base; end
      class Kid1 < Base; end
      class Kid2 < Base; end
      class GKid < Kid1; end
      p Base.subclasses.length
      p Base.subclasses.map { |c| c.to_s }.sort
      p Kid1.subclasses.map { |c| c.to_s }
      p Kid2.subclasses
    RUBY

    _(result).must_answer <<~'OUT'
      2
      ["Kid1", "Kid2"]
      ["GKid"]
      []
    OUT
  end

  it "class subclasses name" do
    result = zr(<<~'RUBY')
      # Class#subclasses hands back boxed classes, so `.map { |c| c.name }` reaches
      # the poly dispatch: a class-tagged value answers #name/#to_s/#inspect with its
      # class name. A boxed class is a Class, not an instance of that class, so it
      # does not call a user #name of the class.
      class Base; end
      class Kid1 < Base; end
      class Kid2 < Base; end
      p Base.subclasses.length
      p Base.subclasses.map { |c| c.name }.sort
      p Base.subclasses.map { |c| c.to_s }.sort
      p Kid1.ancestors.map { |c| c.to_s }.first(3)

      # a user #name still wins: the user object is the likelier receiver
      class Person
        attr_reader :name
        def initialize(n); @name = n; end
      end
      p [Person.new("ann"), Person.new("bob")].map { |x| x.name }

      # encoding-tagged values keep answering for themselves
      p "x".encoding.name
      p "x".encoding.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      2
      ["Kid1", "Kid2"]
      ["Kid1", "Kid2"]
      ["Kid1", "Base", "Object"]
      ["ann", "bob"]
      "UTF-8"
      "UTF-8"
    OUT
  end

  it "cmethod super" do
    result = zr(<<~'RUBY')
      class Foo
        def self.base
          100
        end
        def self.greet(name)
          "hello #{name}"
        end
        def self.tag(pfx = "t")
          pfx + "-foo"
        end
      end
      class Bar < Foo
        def self.base
          super * 10
        end
        def self.greet(name)
          super(name.upcase) + "!"
        end
        def self.tag(pfx = "t")
          super
        end
      end
      class Baz < Bar
        def self.base
          super + 1
        end
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

  it "defined super reports super" do
    result = zr(<<~'RUBY')
      # `defined?(super)` answers "super" when a super method exists from the
      # current method's position and nil when none does. It does not answer
      # "method", because `super` is not a plain method reference.
      class DefBase
        def probe
          defined?(super).inspect
        end
      end

      class DefKid < DefBase
        def probe
          defined?(super).inspect
        end
      end

      puts DefKid.new.probe
      puts DefBase.new.probe
    RUBY

    _(result).must_answer <<~'OUT'
      "super"
      nil
    OUT
  end

  it "dlx subclass ring attr" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Dancing Links. The whole data structure is a ring of Columns and Nodes by definition.
      # At exit: cycle leak: 10 objects (Node x6, Column x4)
      # A ring whose fields hold both a base class and its subclass: reading one
      # yields a polymorphic value, and the local it is bound to has to be poly too.
      # This is true also when the callee's return type widens after the local's.
      class Node
        attr_accessor :left, :right, :up, :down, :column

        def initialize
          @left = self
          @right = self
          @up = self
          @down = self
          @column = nil
        end

        def link_right(node)
          node.right = @right
          node.left = self
          @right.left = node
          @right = node
          node
        end

        def link_down(node)
          node.down = @down
          node.up = self
          @down.up = node
          @down = node
          node
        end
      end

      class Column < Node
        attr_accessor :size, :name

        def initialize(name)
          super()
          @size = 0
          @name = name
        end

        def cover
          right.left = left
          left.right = right
          i = down
          while !i.equal?(self)
            j = i.right
            while !j.equal?(i)
              j.down.up = j.up
              j.up.down = j.down
              j.column.size -= 1
              j = j.right
            end
            i = i.down
          end
        end

        def uncover
          i = up
          while !i.equal?(self)
            j = i.left
            while !j.equal?(i)
              j.column.size += 1
              j.down.up = j
              j.up.down = j
              j = j.left
            end
            i = i.up
          end
          right.left = self
          left.right = self
        end
      end

      class ExactCover
        def initialize(columns, rows)
          @root = Column.new("root")
          @cols = {}
          columns.each do |cname|
            col = Column.new(cname)
            @root.link_right(col)
            @cols[cname] = col
          end
          rows.each do |row|
            first = nil
            row.each do |cname|
              col = @cols[cname]
              node = Node.new
              node.column = col
              col.link_down(node)
              col.size += 1
              first = first.nil? ? node : first.link_right(node)
            end
          end
          @solution = []
          @results = []
        end

        def smallest_column
          best = nil
          c = @root.right
          while !c.equal?(@root)
            best = c if best.nil? || c.size < best.size
            c = c.right
          end
          best
        end

        def remaining_columns
          n = 0
          c = @root.right
          while !c.equal?(@root)
            n += 1
            c = c.right
          end
          n
        end

        def search
          if @root.right.equal?(@root)
            @results << @solution.map { |n| n.column.name }.sort
            return
          end
          col = smallest_column
          return if col.nil? || col.size.zero?
          col.cover
          r = col.down
          while !r.equal?(col)
            @solution.push(r)
            j = r.right
            while !j.equal?(r)
              j.column.cover
              j = j.right
            end
            search
            @solution.pop
            j = r.left
            while !j.equal?(r)
              j.column.uncover
              j = j.left
            end
            r = r.down
          end
          col.uncover
        end

        def solve
          search
          @results
        end
      end

      ec = ExactCover.new(%w[1 2 3], [%w[1 2], %w[3], %w[1], %w[2 3]])
      p ec.solve.sort
    RUBY

    _(result).must_answer "[[\"1\", \"3\"], [\"2\", \"3\"]]\n"
  end

  it "forward args new and super" do
    result = zr(<<~'RUBY')
      # `...` argument forwarding in the two positions that bypassed the shared
      # call-argument lowering.
      #
      # `def m(...)` and a plain `n(...)` already worked -- the parameter desugars to
      # `*__fwd_rest, **__fwd_kw, &__fwd_blk` and the call site re-expands the three.
      # Two callers never reached that code:
      #
      #   Klass.new(...)  -- the STATIC `new` interception decided the call had no
      #                      dynamic arguments, because it looked for a splat or a
      #                      `**`, and a `...` is neither in prism's spelling.
      #   super(...)      -- lowered its arguments with a hand-rolled loop that had
      #                      no forwarding case at all.
      #
      # nokogiri is the reason this matters: `Reader.new(...)` in nokogiri/xml.rb is
      # the first, and its dependents (xpath, loofah, capybara, rails-dom-testing,
      # roo, savon, sanitize) inherit the failure without containing a `...`
      # themselves. io-stream and strong_migrations are the second.

      class Base
        def initialize(a, b = 2, *rest, key: "k", **opts, &blk)
          @seen = [a, b, rest, key, opts, blk ? blk.call : nil]
        end

        attr_reader :seen
      end

      # `super(...)`: every kind of argument crosses in one go.
      class Child < Base
        def initialize(...)
          super(...)
        end
      end

      p Child.new(1).seen
      p Child.new(1, 9, 10, 11, key: "z", extra: true).seen
      p Child.new(1) { "block ran" }.seen

      # A leading required parameter before the `...`, which is the shape
      # io-stream's `def initialize(io, ...)` uses.
      class Tagged < Base
        def initialize(tag, ...)
          @tag = tag
          super(...)
        end

        attr_reader :tag
      end

      t = Tagged.new("t", 5, key: "q")
      p [t.tag, t.seen]

      # `Klass.new(...)` through the static interception, receiverless and qualified.
      module Outer
        class Made
          def initialize(*args, **opts)
            @args = args
            @opts = opts
          end

          attr_reader :args, :opts
        end

        def self.build(...)
          Made.new(...)
        end
      end

      m = Outer.build(1, 2, flag: true)
      p [m.args, m.opts]

      class Wrapper
        def self.make(...)
          new(...)
        end

        def initialize(*a)
          @a = a
        end

        attr_reader :a
      end

      p Wrapper.make(7, 8).a

      # `...` reaching an ordinary send and a block-taking method, so the block half
      # of the forwarding is exercised through both.
      def collect(...)
        [1, 2, 3].map(...)
      end
      p collect { |x| x * 10 }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, [], "k", {}, nil]
      [1, 9, [10, 11], "z", {extra: true}, nil]
      [1, 2, [], "k", {}, "block ran"]
      ["t", [5, 2, [], "q", {}, nil]]
      [[1, 2], {flag: true}]
      [7, 8]
      [10, 20, 30]
    OUT
  end

  it "immediate builtin subclass defines but cannot instantiate" do
    result = zr(<<~'RUBY')
      # A user subclass of an IMMEDIATE builtin (D3): the DEFINITION is allowed --
      # `superclass`/`ancestors`/`is_a?` resolve -- but there are no instances, so
      # `MyInt.new` raises CRuby's exact `NoMethodError`.

      class MyInt < Integer; end
      puts MyInt.superclass
      puts MyInt.ancestors.include?(Integer)
      puts MyInt.ancestors.include?(Numeric)
      begin
        MyInt.new
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
      class MySym < Symbol; end
      begin; MySym.new; rescue => e; puts e.class; end
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      true
      true
      NoMethodError: undefined method 'new' for class MyInt
      NoMethodError
    OUT
  end

  it "inheritance super chain" do
    result = zr(<<~'RUBY')
      class Animal
        def speak
          puts :generic
        end
      end

      class Dog < Animal
        def speak
          super
          puts :woof
        end
      end

      Dog.new.speak
    RUBY

    _(result).must_answer "generic\nwoof\n"
  end

  it "inherited cmethod self class" do
    result = zr(<<~'RUBY')
      # A class method a subclass inherits runs with self = that subclass: CRuby's
      # `def self.bench_name; self.name; end` answers the subclass's name. The
      # defining class's name was folded in at compile time, so a subclass that did
      # not override the method reported the base class.

      class Base
        def self.bench_name
          name.to_s
        end

        def self.describe
          "<#{bench_name}>"
        end

        def label
          self.class.bench_name
        end
      end

      class Sub < Base
        def self.bench_name
          "sub!"
        end
      end

      class Sub2 < Base
      end

      def pick(f)
        f ? Sub.new : Sub2.new
      end

      p pick(true).label
      p pick(false).label
      p Sub2.bench_name
      p Sub.describe
      p Sub2.describe
    RUBY

    _(result).must_answer <<~'OUT'
      "sub!"
      "Sub2"
      "Sub2"
      "<sub!>"
      "<Sub2>"
    OUT
  end

  it "inherited def is one body for every subclass" do
    result = zr(<<~'RUBY')
      # A definition on a superclass is inherited by every subclass, and zr emits
      # its body ONCE rather than once per subclass. This pins what that makes
      # observable -- the class half of the module rule beside it.
      #
      # The body may not depend on the carrier. A constant it reads resolves from
      # the DEFINING class, `self` is the receiver, a method it calls dispatches to
      # the receiver's own override, `super` resumes from the defining class's
      # position, and the frame names the class the `def` was written in.
      #
      # A body that names an instance variable is deliberately NOT shared: a
      # carrier reads ivars by slot. Those rows are here so the split stays
      # visible.

      class Base
        LIMIT = 10

        def plain = "base-plain"
        def reads_const = LIMIT
        def selfy = self.class.name
        def calls_hook = "calls:#{hook}"
        def hook = "base-hook"
        def with_block = [1, 2].map { |z| z * 2 }
        def stashes = (@count ||= 0) + 1

        private

        def secret = "quiet"

        public

        def reaches_private = secret
      end

      class Mid < Base
        def hook = "mid-hook"
      end

      class Leaf < Mid
        def with_block = ["L"] + super
      end

      # A carrier with its own ivars, so the shared body's receiver has a layout
      # the defining class never saw.
      class Roomy < Base
        def initialize
          @a = 1
          @b = 2
        end
      end

      base, mid, leaf, roomy = Base.new, Mid.new, Leaf.new, Roomy.new

      p [base.plain, mid.plain, leaf.plain, roomy.plain]
      p [base.reads_const, leaf.reads_const]
      p [base.selfy, mid.selfy, leaf.selfy, roomy.selfy]

      # The call inside a shared body still finds the RECEIVER's override.
      p [base.calls_hook, mid.calls_hook, leaf.calls_hook]
      p [base.with_block, mid.with_block, leaf.with_block]

      # An ivar a body touches belongs to the receiver, and each keeps its own.
      p [base.stashes, roomy.stashes]
      p [base.instance_variables.sort, roomy.instance_variables.sort]

      # `private` on the superclass reaches every subclass.
      p [leaf.respond_to?(:secret), leaf.reaches_private, roomy.send(:secret)]

      # Reflection names the defining class, not the carrier.
      p [leaf.method(:plain).owner, Roomy.instance_method(:plain).owner]
      p [Leaf.instance_method(:hook).owner, Leaf.superclass, Mid.superclass]

      # The frame does too -- three classes deep.
      begin
        leaf.reads_const
        raise "x" if leaf.plain
      rescue RuntimeError
        # `plain` is Base's, so a raise INSIDE it would say Base#plain; this only
        # pins that the shared body ran at all.
      end
      p Leaf.ancestors.first(3)
    RUBY

    _(result).must_answer <<~'OUT'
      ["base-plain", "base-plain", "base-plain", "base-plain"]
      [10, 10]
      ["Base", "Mid", "Leaf", "Roomy"]
      ["calls:base-hook", "calls:mid-hook", "calls:mid-hook"]
      [[2, 4], [2, 4], ["L", 2, 4]]
      [1, 1]
      [[:@count], [:@a, :@b, :@count]]
      [false, "quiet", "quiet"]
      [Base, Base]
      [Mid, Mid, Base]
      [Leaf, Mid, Base]
    OUT
  end

  it "inherited factory cmethod site" do
    result = zr(<<~'RUBY')
      class Base
        def self.build
          rec = new
          yield rec
          rec
        end
      end
      class Keystore < Base
        def key=(v); @key = v; end
        def key; @key; end
        def self.upsert(k)
          build do |kv|
            kv.key = k
          end
        end
      end
      puts Keystore.upsert("traffic").key

      class Base2
        def self.build
          rec = new
          yield rec if block_given?
          rec
        end
        def self.direct
          build { |r| r.tag }
        end
        def tag; "base"; end
      end
      class Mid2 < Base2
        def tag; "mid"; end
      end
      class Leaf2 < Mid2
        def name=(v); @name = v; end
        def name; @name; end
        def self.upsert(k)
          self.build do |kv|
            kv.name = k
          end
        end
      end
      p Base2.direct.tag
      p Leaf2.upsert("x").name
      mid = Mid2.build { |r| r.tag }
      p mid.tag
    RUBY

    _(result).must_answer <<~'OUT'
      traffic
      "base"
      "x"
      "mid"
    OUT
  end

  it "inherited frame names the defining class" do
    result = zr(<<~'RUBY')
      # Ruby labels a backtrace frame with the class the `def` was WRITTEN in, not
      # the class of the receiver it was called on. An inherited method called on a
      # subclass still says `Base#boom`.
      #
      # zr named the carrier -- `S1#boom` -- so every backtrace through an
      # inherited method reported a class that never defined the method. The rule
      # was already right for a module (`M#mixed`, never `Bar#mixed`) and the
      # superclass half was simply excluded.
      #
      # The exception is a `def self.x` written inside `class << self`: its defining
      # class is the singleton SURROGATE, an internal name no user can write, and
      # ruby still spells that frame `Config.direct`. A surrogate is not in the
      # owner's ancestry, which is what tells the two apart.

      class Base
        def where = caller(0).first[/in '(.*)'/, 1]
        def boom = raise("from base")
      end

      module Mixed
        def mixed_where = caller(0).first[/in '(.*)'/, 1]
      end

      class Middle < Base
        include Mixed
      end

      class Leaf < Middle
        def own_where = caller(0).first[/in '(.*)'/, 1]
      end

      p [Base.new.where, Middle.new.where, Leaf.new.where]
      p [Middle.new.mixed_where, Leaf.new.mixed_where]
      p Leaf.new.own_where

      # The same rule through a raise, three classes deep.
      begin
        Leaf.new.boom
      rescue RuntimeError => e
        puts e.backtrace.first
      end

      # A `def self.x` in a `class << self` body keeps naming the CLASS.
      class Config
        class << self
          def direct = caller(0).first[/in '(.*)'/, 1]
        end
      end
      p Config.direct

      # An overriding subclass names itself, because it is where the `def` is.
      class Override < Base
        def boom = raise("from override")
      end
      begin
        Override.new.boom
      rescue RuntimeError => e
        puts e.backtrace.first
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["Base#where", "Base#where", "Base#where"]
      ["Mixed#mixed_where", "Mixed#mixed_where"]
      "Leaf#own_where"
      lang/classes/inheritance_test.rb:17:in 'Base#boom'
      "Config.direct"
      lang/classes/inheritance_test.rb:53:in 'Override#boom'
    OUT
  end

  it "inherited hook on runtime class" do
    result = zr(<<~'RUBY')
      # `Class.new(Base)` fires Base's `inherited` hook at creation -- before the
      # body block runs and before any constant names the class (the hook sees
      # `name == nil`), exactly as a literal `class Named < Base` does. minitest's
      # whole Runnable registry is this hook, fired by every spec-DSL `describe`.
      class Base
        def self.inherited(k)
          super
          p [:inherited, k.name]
        end
      end
      K = Class.new(Base)
      class Named < Base; end
      k2 = Class.new(Base)
      p :done
    RUBY

    _(result).must_answer <<~'OUT'
      [:inherited, nil]
      [:inherited, "Named"]
      [:inherited, nil]
      :done
    OUT
  end

  it "inherited initialize default arg" do
    result = zr(<<~'RUBY')
      class A
        def some_virtual_method
          1
        end
      end

      class B < A
        def initialize(arg = some_virtual_method)
          @arg = arg
        end
        def arg; @arg; end
      end

      class C < B
      end

      p C.new.arg
      p B.new.arg
      p C.new(7).arg
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      7
    OUT
  end

  it "inherited self boxed class" do
    result = zr(<<~'RUBY')
      $o007 = []

      class Base007
        def register007
          $o007 << self
        end
        def visible007?
          true
        end
        def kind007
          "base"
        end
      end

      class Sub007 < Base007
        def kind007
          "sub"
        end
      end

      Sub007.new.register007
      Base007.new.register007
      p $o007.map { |x| x.visible007? }
      p $o007.map { |x| x.kind007 }
      p $o007.map { |x| x.class.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      [true, true]
      ["sub", "base"]
      ["Sub007", "Base007"]
    OUT
  end

  it "initialize subclass construction" do
    result = zr(<<~'RUBY')
      # The reroute trap: builtin initialize rows must NOT make subclass
      # construction think a USER initialize exists. Every shape below goes
      # through the value-subclass constructor.
      class Stack < Array; end
      p Stack.new(3, 0)
      p Stack.new(2) { |i| i * 5 }
      p Stack.new.class

      class Registry < Hash; end
      r = Registry.new(0)
      p [r.class, r[:missing]]

      class Tag < String; end
      p Tag.new("x")

      # A user initialize STILL wins, and super still re-seeds the payload.
      class Sized < Array
        def initialize(n)
          super(n, :x)
        end
      end
      p Sized.new(2)

      # And the private rows resolve on the subclass through the ancestry.
      s = Stack.new(1, 1)
      s.send(:initialize, 2, 9)
      p s
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 0, 0]
      [0, 5]
      Stack
      [Registry, 0]
      "x"
      [:x, :x]
      [9, 9]
    OUT
  end

  it "a bare new in an inherited class method makes the calling subclass" do
    result = zr(<<~'RUBY')
      # A bare `new` in an inherited class method makes an instance of the
      # subclass that calls it, not of the parent class that defines the
      # method. `Article.create` runs the body of `Base.create`, and its
      # `new` calls the constructor of Article.

      # Basic: bare `new`, no args.
      class Base
        def self.create
          new
        end
      end

      class Article < Base
        def initialize
          @x = "hello"
        end
        def x; @x; end
      end

      puts Article.create.x                  # hello

      # Variant: a bare `new(attrs)` gives the Hash argument to the
      # `initialize` of Article2.
      class Base2
        def self.create(attrs)
          instance = new(attrs)
          instance
        end
      end

      class Article2 < Base2
        def initialize(attrs)
          @title = attrs[:title]
        end
        def title; @title; end
      end

      puts Article2.create({title: "hello"}).title     # hello

      # Multi-level: bare `new` resolves to the leaf class.
      class Mid < Base; end
      class Deep < Mid
        def initialize
          @x = "deep"
        end
        def x; @x; end
      end
      puts Deep.create.x                     # deep

      # A second call runs the body of Base2.create again.
      puts Article2.create({title: "world"}).title     # world
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      hello
      deep
      world
    OUT
  end

  it "object copy and reopen" do
    result = zr(<<~'RUBY')
      # `clone`/`dup` run the object's `initialize_copy` hook after the shallow
      # copy, so a class can un-share a copied member. A bare `super` in that hook
      # reaches Object's default (no-op) copy hook instead of raising.
      class Board
        def initialize
          @rows = [[1], [2]]
        end
        def initialize_copy(orig)
          super
          @rows = @rows.clone   # a fresh outer array for the copy
        end
        def add_row
          @rows.push([9])
        end
        def size
          @rows.length
        end
      end
      b = Board.new
      c = b.clone
      c.add_row
      puts c.size               # 3
      puts b.size               # 2  -- the original is independent

      # Reopening `Object` adds methods to EVERY receiver -- built-in and user alike
      # -- dispatched with the real receiver as `self`.
      class Object
        def type_name
          "a " + self.class.name
        end
      end
      puts "hi".type_name       # a String
      puts 42.type_name         # a Integer
      puts [1, 2].type_name     # a Array
      puts Board.new.type_name  # a Board
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      a String
      a Integer
      a Array
      a Board
    OUT
  end

  it "object initialize super" do
    result = zr(<<~'RUBY')
      # `super` reaching the root `initialize`, which every chain bottoms out on.
      # Object#initialize (BasicObject's, really) takes no arguments and does
      # nothing -- it exists so the ordinary `include SomeMixin` + `super` idiom
      # works, and so a bare `super` at the top of a chain has something to reach
      # instead of raising "no superclass method".

      module Greet
        def initialize
          super          # reaches Object#initialize
          @greeted = true
        end
        def greeted?; @greeted; end
      end

      class Person
        include Greet
      end
      p Person.new.greeted?

      # A class whose only initialize is inherited: bare super forwards nothing.
      class Base
        def initialize; super; @base = "b"; end
        attr_reader :base
      end
      class Derived < Base; end
      p Derived.new.base

      # Arity 0 is enforced: forwarding an argument to the root initialize raises,
      # exactly as CRuby does, so a permissive signature can't hide a real bug.
      class Strict
        def initialize(x); super; end   # bare super forwards x -> too many args
      end
      begin
        Strict.new(1)
      rescue ArgumentError => e
        p e.message
      end

      # super() (explicit empty parens) is how a parameterized initialize reaches
      # the root without forwarding.
      class Ok
        def initialize(x); super(); @x = x; end
        attr_reader :x
      end
      p Ok.new(42).x

      # initialize is private: reflection does not advertise it.
      p Object.new.respond_to?(:initialize)
      p Object.new.respond_to?(:initialize, true)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "b"
      "wrong number of arguments (given 1, expected 0)"
      42
      false
      true
    OUT
  end

  it "receiver built subclass skips its own initialize" do
    result = zr(<<~'RUBY')
      # A subclass of a builtin whose CONSTRUCTOR takes the receiver class --
      # `ObjectSpace::WeakMap`, `WeakRef` -- is registered with that constructor
      # directly, so `.new` reaches the native builder and the subclass's own
      # `initialize` never runs. Ruby runs it, and `super()` reaches the builtin.
      #
      # The answer is silently WRONG rather than a raise: `@label` is simply never
      # written, so the reader answers nil. A subclass that also changes the ARITY
      # raises `ArgumentError` from the native constructor instead, which at least
      # says something.
      class LabelledWeakMap < ObjectSpace::WeakMap
        def initialize(label)
          super()
          @label = label
        end

        attr_reader :label
      end

      m = LabelledWeakMap.new("cache")
      p m.class
      p m.label
      key = "k"
      m[key] = "v"
      p m[key]
    RUBY

    _(result).must_answer <<~'OUT'
      LabelledWeakMap
      "cache"
      "v"
    OUT
  end

  it "reopened prelude and parent methods resolve on subclass instances" do
    result = zr(<<~'RUBY')
      # The dispatch guard tests for the MRO-walk fallback (`lookup_mro`):
      # a reopened exception-prelude class's method visible on rescued
      # subclass instances, late parent reopens and mid-chain module
      # includes visible on deep-leaf instances. Expected output is
      # verbatim ruby 4.0.7.

      class StandardError
        def tagged; "SE-tag: #{message}"; end
      end
      begin
        raise ArgumentError, "boom"
      rescue => e
        puts e.tagged
      end
      class Base
        def hello; "base hello"; end
      end
      class Mid < Base; end
      class Leaf < Mid; end
      puts Leaf.new.hello
      class Base
        def late; "late method"; end
      end
      puts Leaf.new.late
      module Mixin
        def mixed; "mixed in"; end
      end
      class Mid
        include Mixin
      end
      puts Leaf.new.mixed
      class Exception
        def exc_tag; "exc: #{self.class}"; end
      end
      begin
        raise "r"
      rescue => e
        puts e.exc_tag
      end
    RUBY

    _(result).must_answer <<~'OUT'
      SE-tag: boom
      base hello
      late method
      mixed in
      exc: RuntimeError
    OUT
  end

  it "reopening object dispatches to builtin and user receivers" do
    result = zr(<<~'RUBY')
      # reopening Object (with an include + a def) makes those methods
      # dispatch on built-in AND user receivers with the real receiver as self.

      module ObjectGreeting
        def hi
          "hi from " + self.class.name
        end
      end
      class Object
        include ObjectGreeting
        def global_hi
          "global " + self.class.name
        end
      end
      class LocalThing
      end
      puts "x".hi
      puts "x".global_hi
      puts 1.global_hi
      puts [1, 2].global_hi
      puts LocalThing.new.global_hi
    RUBY

    _(result).must_answer <<~'OUT'
      hi from String
      global String
      global Integer
      global Array
      global LocalThing
    OUT
  end

  it "runtime subclass dynamic self" do
    result = zr(<<~'RUBY')
      class B
        def self.who
          name
        end
        def self.make
          new
        end
        def self.tally
          @count = (@count || 0) + 1
        end
        def self.count = @count
        def self.describe_self
          "#{self} / #{self.name} / #{to_s}"
        end
      end

      k = Class.new(B)
      def k.name = "K"

      puts B.who
      puts k.who
      puts k.make.class == k
      puts k.describe_self
      B.tally
      k.tally
      k.tally
      p [B.count, k.count]

      # variable-held compile-time class still right
      h = B
      puts h.who
      # sibling class-method call through dynamic self
      class Registry
        def self.create
          build(:x)
        end
        def self.build(tag)
          "#{name}:#{tag}"
        end
      end
      r = Class.new(Registry)
      def r.build(tag) = "override:#{tag}"
      puts Registry.create
      puts r.create
    RUBY

    _(result).must_answer <<~'OUT'
      B
      K
      true
      #<Class:0xADDR> / K / #<Class:0xADDR>
      [1, 2]
      B
      Registry:x
      override:x
    OUT
  end

  it "runtime super chain" do
    result = zr(<<~'RUBY')
      # Runtime `super` across a three-level runtime class chain, a
      # `define_method` body, and a `super` inside a `rescue` -- all resolved through
      # the runtime method-frame stack because each class is minted at runtime.

      a = Class.new do
        def label(s)
          "A(#{s})"
        end
      end
      b = Class.new(a) do
        def label(s)
          "B->" + super
        end
      end
      c = Class.new(b) do
        # define_method body super, forwarding the same arg up the chain
        define_method(:label) { |s| "C->" + super(s) }
      end
      p c.new.label("x")

      # super inside a rescue in a runtime method still targets the runtime parent
      guard = Class.new(a) do
        def label(s)
          raise "boom" if s.empty?
          super
        rescue
          "A(<empty>)"
        end
      end
      p guard.new.label("ok")
      p guard.new.label("")

      # a native Struct with a custom initialize that supers, then reads back
      weighted = Struct.new(:base, :bonus) do
        def initialize(base)
          super(base, base / 2)
        end
        def total
          base + bonus
        end
      end
      w = weighted.new(10)
      p [w.base, w.bonus, w.total]
    RUBY

    _(result).must_answer <<~'OUT'
      "C->B->A(x)"
      "A(ok)"
      "A(<empty>)"
      [10, 5, 15]
    OUT
  end

  it "self class divergent returns" do
    result = zr(<<~'RUBY')
      # `self.class.<cmeth>` in a parent-defined instance method calls the
      # class method of the receiver's real class. This is true also when
      # the base and subclass methods return different types -- the
      # canonical Rails "abstract base raises, subclass returns concrete
      # value" pattern. The base method runs only when the receiver is
      # an instance of the base class.
      #
      # Coverage:
      #   - Variant 1: Base.label raises, Article.label returns
      #     String. Article.new.describe should print the String.
      #   - Variant 2: IntBase.foo returns int, StrChild.foo returns
      #     String. StrChild gets the String and IntBase gets the int.
      #     puts shows both correctly.

      class Base
        def self.label
          raise "subclass must override"
        end

        def describe
          self.class.label
        end
      end

      class Article < Base
        def self.label
          "articles"
        end
      end

      puts Article.new.describe

      class IntBase
        def self.foo; 42; end
        def show; self.class.foo; end
      end
      class StrChild < IntBase
        def self.foo; "child"; end
      end

      puts StrChild.new.show
      puts IntBase.new.show
    RUBY

    _(result).must_answer <<~'OUT'
      articles
      child
      42
    OUT
  end

  it "self operator subclass dispatch" do
    result = zr(<<~'RUBY')
      # `self[k]` and `self[k] = v` from inside a parent-defined method
      # call the subclass override at runtime, not the parent's operator.
      # This is the operator form of a bare method call to a subclass.
      #
      # Roundhouse example: ActiveRecord::Base#fill_timestamps does
      # `self[:updated_at] = now if cols.include?(:updated_at)`, and
      # the call goes to the column code of the subclass. No model
      # raises NotImplementedError.

      class Base
        def [](name)
          raise NotImplementedError
        end

        def []=(name, value)
          raise NotImplementedError
        end

        def fetch
          self[:foo]
        end

        def fill
          self[:foo] = "bar"
        end
      end

      class Article < Base
        def [](name); "result"; end
        def []=(name, value); @foo = value; end
        def foo; @foo; end
      end

      a = Article.new
      puts a.fetch
      a.fill
      puts a.foo
    RUBY

    _(result).must_answer "result\nbar\n"
  end

  it "subclass of an allocatorless builtin defines but never builds" do
    result = zr(<<~'RUBY')
      # `Binding`, `Encoding`, `Rational` and `MatchData` carry no allocator in
      # CRuby: the class definition is legal -- it registers a real class, takes
      # class methods, and answers `ancestors`/`superclass` -- but `.new` raises
      # NoMethodError, and every instance the runtime hands out is of the builtin
      # class itself. Gems subclass them to hang a namespace or a class method off
      # the name, never to build one, so zr registers the definition and lets
      # `.new` raise exactly what CRuby raises.
      class MyBinding < Binding
        def self.label = :binding
      end

      class MyEncoding < Encoding
        def self.label = :encoding
      end

      class MyRational < Rational; end
      class MyMatchData < MatchData; end

      p MyBinding.superclass
      p MyEncoding.superclass
      p MyRational.superclass
      p MyMatchData.superclass
      p MyBinding.label
      p MyEncoding.label
      p MyRational.ancestors.take(3)

      [MyBinding, MyEncoding, MyRational, MyMatchData].each do |klass|
        begin
          klass.new
        rescue NoMethodError => e
          puts "#{klass}: #{e.class}"
        end
      end

      # The builtins themselves keep making their own instances, and those are NOT
      # of the subclass.
      p Rational(3, 4).class
      p "abc".match(/b/).class
      p Encoding::UTF_8.class
      p binding.class
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      Binding
      Encoding
      Rational
      MatchData
      :binding
      :encoding
      [MyRational, Rational, Numeric]
      MyBinding: NoMethodError
      MyEncoding: NoMethodError
      MyRational: NoMethodError
      MyMatchData: NoMethodError
      Rational
      MatchData
      Encoding
      Binding
      still running
    OUT
  end

  it "subclass of self" do
    result = zr(<<~'RUBY')
      # `class Sub < self` inside a class body names the ENCLOSING class -- a
      # compile-time fact, not a dynamic superclass. optparse gives every argument
      # style this shape (`class NoArgument < self` inside `class Switch`), and
      # rubygems vendors optparse, so every `gem` command depends on it.
      class Switch
        def initialize(pattern = nil, conv = nil, &block)
          @pattern, @conv, @block = pattern, conv, block
        end
        attr_reader :pattern, :conv, :block

        def self.guess(arg) = arg.nil? ? NoArgument : RequiredArgument

        class NoArgument < self
          def self.pattern = /\A\z/
          def parse(arg) = [:none, arg]
        end

        class RequiredArgument < self
          def parse(arg) = [:required, arg]
        end
      end

      s = Switch::NoArgument.new { :from_block }
      p s.class, s.block.call, s.parse(1)
      p Switch::RequiredArgument.new(/x/).pattern
      p Switch::RequiredArgument.new(/x/).parse(2)
      p Switch.new(nil, :conv).conv

      # The inherited surface, the class-method surface, and the ancestry.
      p Switch::NoArgument.ancestors[0, 2]
      p Switch::NoArgument.superclass
      p Switch::NoArgument.pattern
      p Switch.guess(nil), Switch.guess(1)
      p Switch::NoArgument.new.is_a?(Switch)
      p Switch::NoArgument.instance_method(:conv).owner

      # Held in a collection and dispatched dynamically, the way optparse's
      # DefaultList does.
      list = {}
      list["-"] = Switch::NoArgument.new { :dash }
      list["="] = Switch::RequiredArgument.new(/=/) { :eq }
      p list.map { |k, v| [k, v.class, v.parse(k)] }

      # A deeper chain: `< self` from inside a subclass body names THAT subclass.
      class Base
        def kind = :base
        class Middle < self
          def kind = :middle
          class Leaf < self
            def kind = :leaf
          end
        end
      end
      p Base::Middle::Leaf.ancestors[0, 3]
      p Base::Middle::Leaf.new.kind
      p Base::Middle.new.kind

      # `super` still walks the chain the header established.
      class Chain
        def describe = "chain"
        class Link < self
          def describe = "link of #{super}"
        end
      end
      p Chain::Link.new.describe
    RUBY

    _(result).must_answer <<~'OUT'
      Switch::NoArgument
      :from_block
      [:none, 1]
      /x/
      [:required, 2]
      :conv
      [Switch::NoArgument, Switch]
      Switch
      /\A\z/
      Switch::NoArgument
      Switch::RequiredArgument
      true
      Switch
      [["-", Switch::NoArgument, [:none, "-"]], ["=", Switch::RequiredArgument, [:required, "="]]]
      [Base::Middle::Leaf, Base::Middle, Base]
      :leaf
      :middle
      "link of chain"
    OUT
  end

  it "subclass ring dispatch" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A ring of Columns and Nodes, which is the dispatch shape under test.
      # At exit: cycle leak: 7 objects (Column x4, Node x3)
      # A circular doubly-linked structure whose left/right/up/down fields hold both
      # a base class and its subclass -- Knuth's Dancing Links. A slot typed as a
      # class that HAS subclasses is only its STATIC type, because an inherited
      # method storing `self` types the slot as the class that DEFINED the method,
      # while the object can be any subclass.
      #
      # So a read of such a slot can be assigned to a local, and a method that only
      # the subclass defines works on it. It does not raise:
      #
      #   undefined method 'size' for an instance of Node
      #
      # The call dispatches at run time, on the real object.
      class Node
        attr_accessor :left, :right, :up, :down, :column, :row_name

        def initialize(row_name = nil)
          @row_name = row_name
          @left = self
          @right = self
          @up = self
          @down = self
          @column = nil
        end

        def append_to_row(other)
          @left = other
          @right = other.right
          other.right.left = self
          other.right = self
          self
        end
      end

      class Column < Node
        attr_accessor :size, :name

        def initialize(name)
          super(nil)
          @name = name
          @size = 0
          @column = self
        end

        def cover
          right.left = left
          left.right = right
          i = down
          while !i.equal?(self)
            j = i.right
            while !j.equal?(i)
              j.down.up = j.up
              j.up.down = j.down
              j.column.size -= 1
              j = j.right
            end
            i = i.down
          end
        end

        def uncover
          i = up
          while !i.equal?(self)
            j = i.left
            while !j.equal?(i)
              j.column.size += 1
              j.down.up = j
              j.up.down = j
              j = j.left
            end
            i = i.up
          end
          right.left = self
          left.right = self
        end
      end

      class ExactCover
        attr_reader :solutions

        def initialize(column_names)
          @root = Column.new("__root__")
          @columns = {}
          column_names.each do |name|
            col = Column.new(name)
            col.append_to_row(@root.left)
            @columns[name] = col
          end
          @solutions = []
          @stack = []
        end

        def add_row(name, members)
          first = nil
          members.each do |member|
            col = @columns.fetch(member)
            node = Node.new(name)
            node.column = col
            node.up = col.up
            node.down = col
            col.up.down = node
            col.up = node
            col.size += 1
            first = first.nil? ? node : node.append_to_row(first.left)
          end
          self
        end

        def search
          if @root.right.equal?(@root)
            @solutions << @stack.map(&:row_name).sort
            return
          end
          col = smallest_column
          return if col.size.zero?

          col.cover
          row = col.down
          while !row.equal?(col)
            @stack.push(row)
            node = row.right
            while !node.equal?(row)
              node.column.cover
              node = node.right
            end
            search
            @stack.pop
            node = row.left
            while !node.equal?(row)
              node.column.uncover
              node = node.left
            end
            row = row.down
          end
          col.uncover
        end

        def remaining_columns
          names = []
          col = @root.right
          while !col.equal?(@root)
            names << "#{col.name}(#{col.size})"
            col = col.right
          end
          names
        end

        private

        def smallest_column
          best = @root.right
          col = best.right
          while !col.equal?(@root)
            best = col if col.size < best.size
            col = col.right
          end
          best
        end
      end
      k = ExactCover.new(%w[1 2 3])
      k.add_row("A", %w[1 2])
      k.add_row("B", %w[3])
      k.search
      p k.solutions
    RUBY

    _(result).must_answer "[[\"A\", \"B\"]]\n"
  end

  it "subclass through base slot" do
    result = zr(<<~'RUBY')
      # A slot typed as a class that HAS subclasses is only its STATIC type: an
      # inherited method storing `self` types the slot as the class that DEFINED the
      # method, while the object can be any subclass. A method that the runtime
      # object has works on the read, and does not raise:
      #
      #   Column.new.attach(n); n.link.size
      #   # undefined method 'size' for an instance of Node
      #
      # `.class` on the same read answers Column.
      class Node
        attr_accessor :link

        def initialize
          @link = nil
        end

        def attach(other)
          other.link = self
          self
        end
      end

      class Column < Node
        attr_accessor :size

        def initialize
          super()
          @size = 9
        end
      end

      n = Node.new
      c = Column.new
      c.attach(n)
      p n.link.class
      p n.link.size

      # the base's own members keep working through the same slot
      m = Node.new
      Node.new.attach(m)
      p m.link.class
      p m.link.link.inspect

      # and a subclass stored directly, not through the inherited method
      k = Node.new
      k.link = Column.new
      p k.link.size
    RUBY

    _(result).must_answer <<~'OUT'
      Column
      9
      Node
      "nil"
      9
    OUT
  end

  it "subclass via parent accessor" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A parent method writes `self` into its own accessor.
      # At exit: cycle leak: 1 objects (Column x1)
      # A parent holds an accessor pointing at another object of the same family, and
      # a parent method writes `self` into it. A read of it can call a method that
      # only the subclass defines, with no NoMethodError.
      #
      # The parent and the subclass see the same inherited ivar in the same way.
      # The call dispatches at run time, on the real object.
      #
      # Then `name` itself: a user READER owns the name just as a user method does,
      # so Method#name and Class#name do not take the call.
      class Node
        attr_accessor :right
        def initialize
          @right = self
        end

        def link(other)
          other.right = self
          self
        end
      end

      class Column < Node
        attr_accessor :name
        def initialize(name)
          super()
          @name = name
        end
      end

      root = Column.new("root")
      Column.new("a").link(root)
      p root.right.name
      p root.right.class
      p root.right.right.name

      # the same shape with a method rather than a reader
      class Node2
        attr_accessor :peer
        def attach(other)
          other.peer = self
          self
        end
      end
      class Leaf < Node2
        def initialize(v) = @v = v
        def value = @v
      end
      b = Leaf.new(2)
      Leaf.new(1).attach(b)
      p b.peer.value

      # a plain reader named `name`, with no inheritance in sight
      class Plain
        attr_reader :name
        def initialize(n) = @name = n
      end
      p Plain.new("x").name
      p [Plain.new("y")].first.name
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      Column
      "a"
      1
      "x"
      "y"
    OUT
  end

  it "subclassing and reopening a runtime class" do
    result = zr(<<~'RUBY')
      # `class Point < Struct.new(:x, :y)` -- a superclass that only exists at RUN
      # time (a `Struct`/`Data` class, a `Class.new`, a constant holding either).
      # The subclass can't be one of the statically emitted structs, so it is
      # minted at runtime too; `super`, `superclass`, and a namespaced name all
      # have to keep working through it. `class D ... end` reopening such a
      # constant installs onto the existing class rather than registering a fresh
      # (memberless) one, so a generated reader still resolves in the body.

      class Point < Struct.new(:x, :y)
        def dist2; x * x + y * y; end
      end
      p Point.new(3, 4).dist2
      p Point.superclass.ancestors.include?(Struct)

      Base = Class.new do
        def greet; "base"; end
      end
      class Child < Base
        def greet; "child+" + super; end
      end
      p Child.new.greet
      p Child.superclass.equal?(Base)

      D = Data.define(:v)
      class D
        def double; v * 2; end
      end
      p D.new(5).double

      module NS; end
      class NS::Item < Struct.new(:a)
        def show; "a=#{a}"; end
      end
      p NS.constants
      p NS::Item.name
      p NS::Item.new(1).show
    RUBY

    _(result).must_answer <<~'OUT'
      25
      true
      "child+base"
      true
      10
      [:Item]
      "NS::Item"
      "a=1"
    OUT
  end

  it "super arguments" do
    result = zr(<<~'RUBY')
      class Animal
        def initialize(name)
          @name = name
        end

        def name
          @name
        end
      end

      class Dog < Animal
        def initialize(name, breed)
          super(name)
          @breed = breed
        end

        def breed
          @breed
        end
      end

      class Puppy < Animal
        def initialize(name)
          super
          @greeting = "woof from #{name}"
        end

        def greeting
          @greeting
        end
      end

      d = Dog.new("Rex", "Lab")
      puts d.name
      puts d.breed

      pup = Puppy.new("Fido")
      puts pup.name
      puts pup.greeting
    RUBY

    _(result).must_answer <<~'OUT'
      Rex
      Lab
      Fido
      woof from Fido
    OUT
  end

  it "super forms" do
    result = zr(<<~'RUBY')
      # `super`'s three written shapes mean three different things, and a bare
      # `super` forwards the current method's arguments AS CURRENTLY BOUND --
      # including a parameter that is optional here but required in the parent.

      class Parent
        def greet(name)
          "Parent(#{name})"
        end
      end

      # Bare `super` forwards the child's optional parameter into the parent's
      # REQUIRED slot -- the shapes differ, so a bucket-by-bucket match wouldn't
      # bind the parent's `name` at all.
      class BareSuper < Parent
        def greet(name = "default")
          super
        end
      end
      puts BareSuper.new.greet
      puts BareSuper.new.greet("given")

      # `super()` with empty parens passes NO arguments -- the opposite meaning.
      class ParenSuper < Parent
        def greet(name = "child")
          super("explicit")
        end
      end
      puts ParenSuper.new.greet

      # Bare `super` forwards the CURRENT value, reassignments included.
      class Reassigned < Parent
        def greet(name)
          name = name.upcase
          super
        end
      end
      puts Reassigned.new.greet("ada")

      # Flattening works across buckets: required + optional + post.
      class Multi
        def show(a, b, c, d)
          "a=#{a} b=#{b} c=#{c} d=#{d}"
        end
      end
      class MultiChild < Multi
        def show(a, b = 2, c = 3, d = 4)
          super
        end
      end
      puts MultiChild.new.show(1)
      puts MultiChild.new.show(1, 9)
      puts MultiChild.new.show(1, 9, 8, 7)

      # A parent optional beyond what the child supplies evaluates its own default.
      class Defaults
        def run(a, b = "parent-default")
          "a=#{a} b=#{b}"
        end
      end
      class DefaultsChild < Defaults
        def run(a)
          super
        end
      end
      puts DefaultsChild.new.run("x")

      # Keyword parameters are matched by NAME.
      class KwParent
        def config(host:, port: 80)
          "#{host}:#{port}"
        end
      end
      class KwChild < KwParent
        def config(host:, port: 8080)
          super
        end
      end
      puts KwChild.new.config(host: "example.com")
      puts KwChild.new.config(host: "example.com", port: 3000)

      # A rest parameter forwards whole.
      class RestParent
        def all(*args)
          args.inspect
        end
      end
      class RestChild < RestParent
        def all(*args)
          super
        end
      end
      puts RestChild.new.all(1, 2, 3)

      # `super { ... }` passes a LITERAL BLOCK to the parent, which yields to it.
      class BlockParent
        def run
          yield
        end

        def each_twice
          yield 1
          yield 2
        end
      end
      class BlockChild < BlockParent
        def run
          super { "from-child-block" }
        end

        def each_twice
          super { |v| puts "got #{v}" }
        end
      end
      puts BlockChild.new.run
      BlockChild.new.each_twice

      # With no literal block, the parent sees the CHILD's own block (forwarded).
      class ForwardBlock < BlockParent
        def run
          super
        end
      end
      puts ForwardBlock.new.run { "from-caller" }

      # A `super` block closes over the child's own locals -- `super()` here, since
      # the parent's `run` takes no arguments and bare `super` would forward `tag`.
      class ClosureBlock < BlockParent
        def run(tag)
          count = 0
          result = super() { count += 1; "#{tag}-#{count}" }
          "#{result} (count=#{count})"
        end
      end
      puts ClosureBlock.new.run("t")

      # `super` through a module in the ancestor chain.
      module Loud
        def speak
          super.upcase
        end
      end
      class Animal
        def speak
          "rawr"
        end
      end
      class Lion < Animal
        include Loud
      end
      puts Lion.new.speak
    RUBY

    _(result).must_answer <<~'OUT'
      Parent(default)
      Parent(given)
      Parent(explicit)
      Parent(ADA)
      a=1 b=2 c=3 d=4
      a=1 b=9 c=3 d=4
      a=1 b=9 c=8 d=7
      a=x b=parent-default
      example.com:8080
      example.com:3000
      [1, 2, 3]
      from-child-block
      got 1
      got 2
      from-caller
      t-1 (count=1)
      RAWR
    OUT
  end

  it "super in non initialize" do
    result = zr(<<~'RUBY')
      # `super` in a non-`initialize` instance method calls the parent's
      # method of the same name, found up the parent chain. The result
      # has the type that the parent's method returns.

      class A
        def value
          10
        end

        def doubled(x)
          x * 2
        end
      end

      class B < A
        def value
          super         # bare super forwards no args
        end

        def doubled(x)
          super(x) + 1  # explicit super(arg) -> A.doubled(x) + 1
        end
      end

      class C < B
        def value
          super + 5     # B.value calls A.value (10) -> 10 + 5 = 15
        end
      end

      b = B.new
      puts b.value.to_s       # 10
      puts b.doubled(3).to_s  # 6 + 1 = 7

      c = C.new
      puts c.value.to_s       # 15
    RUBY

    _(result).must_answer <<~'OUT'
      10
      7
      15
    OUT
  end

  it "super object initialize" do
    result = zr(<<~'RUBY')
      # `super()` from an initialize no ancestor defines reaches Object's, which
      # takes no arguments and does nothing. It was answered with a NoMethodError.

      class Base
        def run(i)
          i
        end
      end

      class Child < Base
        def initialize(n = 3)
          super()
          @n = n
        end

        def val
          @n
        end
      end

      class Child2 < Base
        def initialize
          super
          @m = 1
        end

        def val
          @m
        end
      end

      p Child.new.val
      p Child.new(9).val
      p Child2.new.val
    RUBY

    _(result).must_answer <<~'OUT'
      3
      9
      1
    OUT
  end

  it "super qualified superclass" do
    result = zr(<<~'RUBY')
      module A
        module B
          class Handler
            def initialize; @req = 1; end
            def greet; "hi from #{@req}"; end
          end
        end
      end
      class Child < A::B::Handler
        def initialize
          super
          @ws = 2
        end
      end
      c = Child.new
      puts c.greet
      puts "ok"
    RUBY

    _(result).must_answer "hi from 1\nok\n"
  end

  it "super reaches the root initialize" do
    result = zr(<<~'RUBY')
      # `super` reaching the root `initialize` -- what every chain bottoms out on,
      # and what makes the ordinary `include SomeMixin` + `super` idiom work. It
      # does not raise "no superclass method 'initialize'": the runtime `super`
      # finds the builtin BasicObject#initialize. Arity 0 is enforced, and
      # `initialize` stays private to reflection.

      module Greet
        def initialize
          super
          @greeted = true
        end
        def greeted?; @greeted; end
      end
      class Person
        include Greet
      end
      p Person.new.greeted?

      class Strict
        def initialize(x); super; end
      end
      begin
        Strict.new(1)
      rescue ArgumentError => e
        p e.message
      end

      class Ok
        def initialize(x); super(); @x = x; end
        attr_reader :x
      end
      p Ok.new(42).x

      p Object.new.respond_to?(:initialize)
      p Object.new.respond_to?(:initialize, true)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "wrong number of arguments (given 1, expected 0)"
      42
      false
      true
    OUT
  end

  it "super runtime fallback" do
    result = zr(<<~'RUBY')
      # `super` with no definition above the defining class.
      #
      # Real Ruby resolves `super` at CALL time against the receiver's live ancestry
      # (`vm_search_super_method`) and raises NoMethodError only when that walk comes
      # up empty -- there is no definition-time check. The message comes from the one
      # method-missing raiser, so it carries the same "for an instance of X" receiver
      # description every other NoMethodError uses.

      # 1. `super` into a method that exists nowhere above -> rescuable NoMethodError.
      class Rec
        def as_json
          h = super
          h[:x] = 1
          h
        end
      end

      begin
        Rec.new.as_json
      rescue NoMethodError => e
        puts e.message
      end

      # 2. `super` reaching a method that only an INCLUDED MODULE defines. A
      #    compile-time scan of the superclass chain alone misses this; the runtime
      #    walk covers the real ancestry, modules included.
      module Greet
        def hi
          "[hi]"
        end
      end

      class C
        include Greet
        def hi
          super
        end
      end

      puts C.new.hi

      # 3. Module-to-module `super` along the include chain.
      module M1
        def tag
          "M1"
        end
      end

      module M2
        include M1
        def tag
          "M2(#{super})"
        end
      end

      class F
        include M2
        def tag
          "F[#{super}]"
        end
      end

      puts F.new.tag

      # 4. The receiver description is shared with every other NoMethodError shape:
      #    an instance, a class, a module, and nil each render differently.
      begin
        Object.new.no_such_method
      rescue NoMethodError => e
        puts e.message
      end

      begin
        nil.no_such_method
      rescue NoMethodError => e
        puts e.message
      end

      module Helper; end

      begin
        Helper.no_such_method
      rescue NoMethodError => e
        puts e.message
      end

      begin
        String.no_such_method
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      super: no superclass method 'as_json' for an instance of Rec
      [hi]
      F[M2(M1)]
      undefined method 'no_such_method' for an instance of Object
      undefined method 'no_such_method' for nil
      undefined method 'no_such_method' for module Helper
      undefined method 'no_such_method' for class String
    OUT
  end

  it "super with args" do
    result = zr(<<~'RUBY')
      # super (bare or with explicit args) gives the Child param types to
      # the Parent params, so Parent gets the real values, not Integers.
      class Parent
        def greet(name)
          puts "Parent: #{name}"
        end
      end

      class Child < Parent
        def greet(name)
          super
          puts "Child: #{name}"
        end
      end

      class Echo < Parent
        def greet(name)
          super(name)
          puts "Echo done"
        end
      end

      Child.new.greet("Alice")
      Echo.new.greet("Bob")
    RUBY

    _(result).must_answer <<~'OUT'
      Parent: Alice
      Child: Alice
      Parent: Bob
      Echo done
    OUT
  end

  it "super with empty parens passes no arguments" do
    result = zr(<<~'RUBY')
      # `super()` and bare `super` mean OPPOSITE things: the parens form
      # passes nothing, so the parent's optional takes its default.

      class G
        def greet(name = "anon")
          "hi #{name}"
        end
      end

      class H < G
        def greet(name)
          super() + "!"
        end
      end

      puts H.new.greet("bob")
    RUBY

    _(result).must_answer "hi anon!\n"
  end

  it "super with explicit args binds the parents own param names" do
    result = zr(<<~'RUBY')
      # `super(name)` binds the parent's own parameter names. Here parent and
      # child deliberately use different names (`name` vs. `name, breed`), so
      # the test passes only when `super(name)` binds Animal's own `name`.

      class Animal
        def initialize(name)
          @name = name
        end
        def name
          @name
        end
      end

      class Dog < Animal
        def initialize(name, breed)
          super(name)
          @breed = breed
        end
        def breed
          @breed
        end
      end

      d = Dog.new("Rex", "Lab")
      puts d.name
      puts d.breed
    RUBY

    _(result).must_answer "Rex\nLab\n"
  end

  it "superclass never defined" do
    result = zr(<<~'RUBY')
      # A superclass naming a constant the program never defines. The program still
      # compiles. A library can subclass something from a gem it failed to load --
      # irb's `class CallTracer < ::CallTracer`, guarded by a `require "tracer"`
      # that already raised LoadError -- and the definition never runs. Real Ruby
      # evaluates the superclass expression when the definition RUNS, raises
      # NameError there, and leaves no class behind.
      class Base
        def who = :base
      end

      class Ordinary < Base
      end

      puts Ordinary.new.who
      puts Ordinary.superclass

      begin
        class Sub < ::Nope
          def hi = :hi
        end
      rescue NameError => e
        puts e.class
        puts e.message
      end

      p defined?(Sub)
      p Object.const_defined?(:Sub)

      # The name elsewhere is an ordinary unresolved constant read, so it raises the
      # same way rather than silently answering an empty class.
      begin
        Sub.new
      rescue NameError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      base
      Base
      NameError
      uninitialized constant Nope
      nil
      false
      uninitialized constant Sub
    OUT
  end

  it "superclass reaches an inherited constant alias" do
    result = zr(<<~'RUBY')
      # A superclass clause resolves through the ENCLOSING class's ancestry, and
      # an inherited constant may be an ALIAS of a class defined elsewhere. rss's
      # maker layer is the shape: `AuthorsBase = ChannelBase::AuthorsBase` inside
      # ItemBase, read by `class Authors < AuthorsBase` under `Item < ItemBase`.
      module M
        class Base
          class AuthorsBase
            def kind
              :authors_base
            end
          end
        end
        class Channel < Base
          class Authors < AuthorsBase; end
        end
        class ItemBase
          AuthorsBase = Base::AuthorsBase
        end
        class Item < ItemBase
          class Authors < AuthorsBase; end
        end
      end
      p M::Channel::Authors.superclass
      p M::Item::Authors.superclass
      p M::Item::Authors.new.kind
      p M::Channel::Authors.new.kind
    RUBY

    _(result).must_answer <<~'OUT'
      M::Base::AuthorsBase
      M::Base::AuthorsBase
      :authors_base
      :authors_base
    OUT
  end

  it "to enum from a super bridge" do
    result = zr(<<~'RUBY')
      # `to_enum(:meth)` on the implicit self works correctly inside a
      # method that a subclass reaches with `super`.
      class Base
        def each
          return to_enum(:each) unless block_given?
          yield 1
          yield 2
        end

        def each_tagged(tag)
          return enum_for(:each_tagged, tag) unless block_given?
          yield "#{tag}-a"
          yield "#{tag}-b"
        end
      end

      class Sub < Base
        def each(&block)
          return to_enum(:each) unless block_given?
          super(&block)
          yield 3
        end
      end

      p Base.new.each.to_a
      p Sub.new.each.to_a
      p Base.new.each_tagged("x").to_a

      collected = []
      Sub.new.each { |n| collected << n }
      p collected

      e = Sub.new.each
      p e.class
      p e.next
      p e.next
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2, 3]
      ["x-a", "x-b"]
      [1, 2, 3]
      Enumerator
      1
      2
    OUT
  end

  it "undefined allocator holds for subclasses" do
    result = zr(<<~'RUBY')
      # A class whose allocator CRuby undefines refuses `allocate`, and so does
      # a subclass of it, unless the subclass gets an allocator of its own, as
      # the classes Struct.new and Data.define make do. The constructors of
      # those classes still build their objects.

      def show(label)
        print label, ": "
        r = yield
        puts r.is_a?(Module) ? r : r.inspect.gsub(/0x\h+/, "X")
      rescue => e
        puts "#{e.class}: #{e.message.gsub(/0x\h+/, "X")}"
      end

      [Proc, Method, UnboundMethod, Binding, Thread, Encoding, Float, Struct, Data].each do |k|
        show(k.name) { k.allocate }
        show("#{k.name} subclass") { Class.new(k).allocate }
      end

      show("Rational") { Rational.allocate }
      show("Rational subclass") { Class.new(Rational).allocate }
      show("Complex") { Complex.allocate }

      show("Struct.new") { Struct.new(:a).allocate }
      show("Struct.new subclass") { Class.new(Struct.new(:a)).allocate }
      show("Data.define") { Data.define(:a).allocate }
      show("Data.define subclass") { Class.new(Data.define(:a)).allocate }

      show("Proc subclass new") { Class.new(Proc).new { 1 }.call }
      show("Thread subclass new") { Class.new(Thread).new { 2 }.value }
      show("Struct subclass new") { Class.new(Struct.new(:a)).new(3).a }
      show("Data subclass new") { Class.new(Data.define(:a)).new(a: 4).a }
      show("Rational") { Rational(1, 3) + 1 }
      show("Complex") { Complex(1, 1) * 2 }

      show("singleton") { Object.new.singleton_class.allocate }
      show("singleton new") { Object.new.singleton_class.new }

    RUBY

    _(result).must_answer <<~'OUT'
      Proc: TypeError: allocator undefined for Proc
      Proc subclass: TypeError: allocator undefined for #<Class:X>
      Method: TypeError: allocator undefined for Method
      Method subclass: TypeError: allocator undefined for #<Class:X>
      UnboundMethod: TypeError: allocator undefined for UnboundMethod
      UnboundMethod subclass: TypeError: allocator undefined for #<Class:X>
      Binding: TypeError: allocator undefined for Binding
      Binding subclass: TypeError: allocator undefined for #<Class:X>
      Thread: TypeError: allocator undefined for Thread
      Thread subclass: TypeError: allocator undefined for #<Class:X>
      Encoding: TypeError: allocator undefined for Encoding
      Encoding subclass: TypeError: allocator undefined for #<Class:X>
      Float: TypeError: allocator undefined for Float
      Float subclass: TypeError: allocator undefined for #<Class:X>
      Struct: TypeError: allocator undefined for Struct
      Struct subclass: TypeError: allocator undefined for #<Class:X>
      Data: TypeError: allocator undefined for Data
      Data subclass: TypeError: allocator undefined for #<Class:X>
      Rational: NoMethodError: undefined method 'allocate' for class Rational
      Rational subclass: NoMethodError: undefined method 'allocate' for class #<Class:X>
      Complex: NoMethodError: undefined method 'allocate' for class Complex
      Struct.new: #<struct a=nil>
      Struct.new subclass: #<struct a=nil>
      Data.define: #<data a=nil>
      Data.define subclass: #<data a=nil>
      Proc subclass new: 1
      Thread subclass new: 2
      Struct subclass new: 3
      Data subclass new: 4
      Rational: (4/3)
      Complex: (2+2i)
      singleton: TypeError: can't create instance of singleton class
      singleton new: TypeError: can't create instance of singleton class
    OUT
  end

  it "unresolved super value" do
    result = zr(<<~'RUBY')
      # A module whose method calls `super`, never included anywhere, so nothing says
      # what that super answers. The raise for it never returns. The program still
      # compiles when the super value goes into a boxed slot, such as an
      # interpolation.
      # a module whose `super` is interpolated, never included
      module Numbered
        def render(text) = "#{super}!"
      end
      class Plain
        def render(text) = text
      end
      p Plain.new.render("hi")

      # the neighbouring shapes
      module Whole
        def render2(text) = super
      end
      class Plain2
        def render2(text) = text
      end
      p Plain2.new.render2("ho")

      # super interpolated where it DOES resolve
      class Base
        def label = "base"
      end
      class Child < Base
        def label = "#{super}-child"
      end
      p Child.new.label

      # an unresolved super in other value positions
      module Orphan
        def a = [super]
        def b = super.to_s
        def c = { k: super }
        def d = super + 1
      end
      class Other
        def a = 1
        def b = 2
        def c = 3
        def d = 4
      end
      p [Other.new.a, Other.new.b, Other.new.c, Other.new.d]
    RUBY

    _(result).must_answer <<~'OUT'
      "hi"
      "ho"
      "base-child"
      [1, 2, 3, 4]
    OUT
  end

  it "value builtin subclass c tag" do
    result = zr(<<~'RUBY')
      # `C`: a subclass of a value builtin (String/Array) marshals its class
      # symbol then the inherited body inline, `I`-wrapped for a string's
      # encoding and any user ivars. Round-trips through the subclass.

      def wire(x) = Marshal.dump(x).bytes.join(",")
      def rt(x) = Marshal.load(Marshal.dump(x))
      class MyStr < String; end
      class Stack < Array; end
      puts wire(MyStr.new("hi"))
      s = MyStr.new("hi")
      s.instance_variable_set(:@x, 5)
      puts wire(s)
      puts wire(Stack.new([1, 2]))
      r = rt(MyStr.new("hi"))
      puts "#{r.class} #{r} #{r.upcase}"
      puts rt(s).instance_variable_get(:@x)
      st = rt(Stack.new([1, 2]))
      puts st.class
      p st.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      4,8,73,67,58,10,77,121,83,116,114,34,7,104,105,6,58,6,69,84
      4,8,73,67,58,10,77,121,83,116,114,34,7,104,105,7,58,6,69,84,58,7,64,120,105,10
      4,8,67,58,10,83,116,97,99,107,91,7,105,6,105,7
      MyStr hi HI
      5
      Stack
      [1, 2]
    OUT
  end

  it "value class super" do
    result = zr(<<~'RUBY')
      # A Struct or Data value class may define a custom `initialize` that calls
      # `super` to set its members -- bare, explicit-positional, or (for Data)
      # keyword super.

      # Bare `super` forwards this method's own params into the members.
      Trip = Struct.new(:x, :y, :z) do
        def initialize(x, y)
          super             # sets x and y; z stays nil
        end
      end
      p Trip.new(1, 2).to_a           # [1, 2, nil]

      # Explicit positional super can compute extra members.
      Vec = Struct.new(:a, :b, :sum) do
        def initialize(a, b)
          super(a, b, a + b)
        end
      end
      p Vec.new(3, 4).to_a            # [3, 4, 7]

      # Data delegates by KEYWORD; omitting a member raises ArgumentError, and args
      # routed through a method aren't constant-folded at the call site.
      Scaled = Data.define(:x, :y) do
        def initialize(x:, y:)
          super(x: x * 100, y: y + 1)
        end
      end
      def make_scaled(a, b)
        Scaled.new(x: a, y: b)
      end
      p make_scaled(5, 2)             # #<data Scaled x=500, y=3>

      Pair = Data.define(:m, :n) do
        def initialize(m:, n:)
          super(m: m)                 # forgets :n
        end
      end
      begin
        Pair.new(m: 1, n: 2)
      rescue ArgumentError => e
        puts "error: #{e.message}"    # missing keyword: :n
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, nil]
      [3, 4, 7]
      #<data Scaled x=500, y=3>
      error: missing keyword: :n
    OUT
  end

  it "value subclass" do
    result = zr(<<~'RUBY')
      # User subclasses of Array/String/Hash are the native ValueSubclass (D3): they
      # wrap a payload of the root kind, inherit its methods through the payload
      # bridge, re-wrap self-returning mutators, and compare/hash by their payload.

      class Stack < Array
        def peek
          last
        end
      end

      s = Stack.new
      s.push(1)
      s << 2
      s.push(3)
      p s
      puts s.size
      puts s.peek
      puts s.pop
      puts s.class
      puts s.push(4).class          # self-return re-wraps to Stack
      puts s.map { |x| x * 10 }.inspect
      puts s.map { |x| x }.class    # a NEW array is a plain Array
      puts s.is_a?(Array)
      puts s.is_a?(Enumerable)
      puts Stack.new([5, 6, 7]).sum

      class Tag < String
        def shout
          upcase + "!"
        end
      end

      t = Tag.new("hi")
      puts t.shout
      puts t.class
      puts(t == "hi")
      puts("hi" == t)                # symmetric ==
      puts(Tag.new("k").hash == "k".hash)
      lookup = { "k" => 42 }
      puts lookup[Tag.new("k")]      # payload Hash-key equality

      class Counter < Hash
        def initialize
          super(0)
        end
      end

      c = Counter.new
      c[:a] += 1
      c[:a] += 1
      c[:b] += 1
      puts c[:a]
      puts c[:b]
      puts c[:missing]
      p c
      puts c.class
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      3
      3
      3
      Stack
      Stack
      [10, 20, 40]
      Array
      true
      true
      18
      HI!
      Tag
      true
      true
      true
      42
      2
      1
      0
      {a: 2, b: 1}
      Counter
    OUT
  end
end
