# frozen_string_literal: true

require "spec_helper"

describe "Classes: formatting and inspection" do
  it "allocate on a value class" do
    result = ze0(<<~'RUBY')
      # `Class#allocate` on a value class -- the gap this promotes.
      #
      # Only 2 of zeo's 98 native classes declared a blank value, so `Regexp`,
      # `Mutex` and `Queue` all refused where ruby allocates, and `MatchData` gave
      # the wrong refusal (`TypeError` for a name ruby `undef`s, which is a
      # `NoMethodError`). Every row here now matches ruby.
      #
      # The blank Regexp is the interesting one: it is UNINITIALIZED rather than
      # empty, so `#source` refuses. A blank that quietly answered `""` would be
      # a pattern matching everything -- a wrong answer, not a missing one.

      def t(l); r=(begin; yield.inspect; rescue Exception=>e; "#{e.class}: #{e.message}"; end); puts format("%-22s %s", l, r); end
      t("Regexp.allocate")   { Regexp.allocate.class }
      t("Regexp source")     { Regexp.allocate.source }
      t("Mutex.allocate")    { Mutex.allocate.class }
      t("Queue.allocate")    { Queue.allocate.class }
      t("Proc.allocate")     { Proc.allocate.class }
      t("MatchData.allocate"){ MatchData.allocate.class }
      t("String.allocate")   { String.allocate }
      t("Array.allocate")    { Array.allocate }
      t("Hash.allocate")     { Hash.allocate }
      t("Time.allocate")     { Time.allocate.class }
    RUBY

    _(result).must_answer <<~'OUT'
      Regexp.allocate        Regexp
      Regexp source          TypeError: uninitialized Regexp
      Mutex.allocate         Thread::Mutex
      Queue.allocate         Thread::Queue
      Proc.allocate          TypeError: allocator undefined for Proc
      MatchData.allocate     NoMethodError: undefined method 'allocate' for class MatchData
      String.allocate        ""
      Array.allocate         []
      Hash.allocate          {}
      Time.allocate          Time
    OUT
  end

  it "bare reopen does not steal a declaring site" do
    result = ze0(<<~'RUBY', files: {"bare_reopen/aitem.rb" => "# Reopened BARE, in a file the compiler walks BEFORE the one that declares\n# the class with its superclass.\nmodule Store\n  class Item\n    class Nested\n      def where = \"aitem\"\n    end\n  end\nend\n", "bare_reopen/item.rb" => "module Store\n  class Base\n    def base = \"base\"\n  end\n  class Item < Base\n    autoload :Nested, File.expand_path(\"aitem\", __dir__)\n    def own = \"own\"\n  end\nend\n", "bare_reopen/root.rb" => "module Store\n  autoload :Item, File.expand_path(\"item\", __dir__)\nend\n"})
      # One file REOPENS `class Item` bare; another DECLARES it with a superclass.
      # The compiler walks units in demand order, so the bare reopen can come first
      # -- and the declaration must still be the one that fixes the superclass and
      # runs a class body.
      #
      # `Bundler::Source::Git` is written this way: `source/git/git_proxy.rb`
      # reopens `class Git` bare to hold its error classes, and `source/git.rb`
      # declares `class Git < Path`. With the bare file walked first, the
      # declaration lost its class-body site entirely: the class was registered from
      # the reopen, concealed at boot, and no site was ever emitted to reveal it --
      # so the constant read raised for a class the program defines, and the
      # `autoload` written inside the declaration's body registered on `Object`.
      #
      # Which of the two files the compiler walks first is a demand-order fact this
      # golden cannot pin, so it pins the SHAPE and the answers. The order itself is
      # guarded where it can be: `every_bundled_gem_compiles` asserts that every
      # positional class in every bundled gem has a body site some statement stream
      # actually reaches, and `--dump=classes` names a violation directly -- a class
      # whose sites all read `stream=NONE`, or one whose only site is in the file
      # that merely reopens it.

      require_relative "bare_reopen/root"

      p Store::Item
      p Store::Item.superclass
      p Store::Item.new.base
      p Store::Item.new.own
      p Store::Item::Nested.new.where
      p Store::Item.equal?(Store.const_get(:Item))
      p defined?(Store::Item)
      p Store::Item.ancestors.take(2).map(&:to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      Store::Item
      Store::Base
      "base"
      "own"
      "aitem"
      true
      "constant"
      ["Store::Item", "Store::Base"]
    OUT
  end

  it "class const as value" do
    result = ze0(<<~'RUBY')
      # Issue #404 Phase 1. A class constant referenced as a value (not
      # as the receiver of `.new` / a class method call) used to emit a
      # bare C identifier:
      #
      #   c = Row     ->  lv_c = Row;             /* Row undeclared */
      #   puts c.to_s ->  warning: cannot resolve call to 'to_s' on class_Row
      #
      # Phase 1 wires the minimum surface needed for class-as-value to
      # round-trip through a local:
      #   - sp_Class struct (mrb_int cls_id) in sp_runtime.h.
      #   - infer_type for ConstantReadNode / ConstantPathNode resolving
      #     to a registered class returns "class".
      #   - c_type "class" -> "sp_Class"; c_default_val "class" ->
      #     ((sp_Class){-1LL}).
      #   - compile_expr's ConstantReadNode arm emits a sp_Class compound
      #     literal carrying the class index instead of the bare name.
      #   - compile_object_method_expr's recv_type == "class" branch
      #     lowers `.to_s` to the new sp_class_to_s helper, which
      #     bound-checks against the per-program sp_class_names[] table
      #     emitted by emit_class_runtime.
      #
      # Out of scope for Phase 1 (deferred to later work):
      #   - `.name` / `.inspect` / `.==` / `.!=` on Class values.
      #   - Module distinction (Module vs Class kind).
      #   - Dispatch through a Class-typed local (`c.new(...)`).
      #   - is_a?(Klass-typed-variable), case/when on Class values.
      #   - Precomputed ancestors / .superclass / `.<` / `.<=`.
      #
      # Phase 2 will pick those up; the issue stays open until then.

      class Row
        attr_accessor :x
      end

      class Article < Row
      end

      # Local assignment from a class constant.
      c = Row
      puts c.to_s                   # Row

      # Same shape with a subclass.
      d = Article
      puts d.to_s                   # Article

      # Pass a Class value through a typed-pointer round trip via an
      # instance method that reads it off an ivar -- exercises the
      # "store sp_Class on the heap and read it back" path that the
      # bare `Foo` reference originally broke at the C-emit boundary.
      class Holder
        attr_accessor :klass
      end

      h = Holder.new
      h.klass = Row
      puts h.klass.to_s             # Row
      h.klass = Article
      puts h.klass.to_s             # Article
    RUBY

    _(result).must_answer <<~'OUT'
      Row
      Article
      Row
      Article
    OUT
  end

  it "class hierarchy" do
    result = ze0(<<~'RUBY')
      # Issue #404 Phase 3 (Tier 1, classes-only). Exercise the
      # precomputed ancestors / parents tables added in this phase.
      # Modules + dynamic is_a? + case-when on Class come in later
      # tiers; this test stays on user-class inheritance.

      class A
      end

      class B < A
      end

      class C < B
      end

      # .superclass walks @cls_parents one step.
      puts B.superclass.to_s  # => A
      puts C.superclass.to_s  # => B
      # A's superclass is Object per CRuby.
      puts A.superclass == Object ? "A-root-ok" : "A-root-bad"

      # .ancestors returns a PolyArray of boxed sp_Class. Iterate and
      # concatenate the names so the output exercises sp_box_class +
      # the PolyArray iteration over class-tagged poly elements.
      def names_of(arr)
        out = ""
        arr.each do |klass|
          out += "," unless out.length == 0
          out += klass.to_s
        end
        out
      end

      puts names_of(C.ancestors)  # => "C,B,A,Object,Kernel,BasicObject"
      puts names_of(A.ancestors)  # => "A,Object,Kernel,BasicObject"

      # `<` / `<=` -- proper / non-proper subclass.
      puts (C < A) ? "C<A" : "C!<A"
      puts (C <= A) ? "C<=A" : "C!<=A"
      puts (A < A) ? "A<A" : "A!<A"
      puts (A <= A) ? "A<=A" : "A!<=A"
      puts (A < C) ? "A<C" : "A!<C"
    RUBY

    _(result).must_answer <<~'OUT'
      A
      B
      A-root-ok
      C,B,A,Object,Kernel,BasicObject
      A,Object,Kernel,BasicObject
      C<A
      C<=A
      A!<A
      A<=A
      A!<C
    OUT
  end

  it "class hierarchy builtin" do
    result = ze0(<<~'RUBY')
      # Issue #404 Phase 3 Tier 4. Built-in class prefix in the
      # unified cls_id space. Primitives (Integer, String, Array, ...)
      # now occupy cls_ids 0..20 per docs/CLASS-OBJECT.md; user
      # classes shift to cls_id BC + internal_ci, where BC is the
      # reserved built-in count.
      #
      # Coverage:
      #   - Built-in class const in value position: Integer.to_s ->
      #     "Integer" via the sp_class_names table.
      #   - Built-in class hierarchy: Integer < Numeric, Integer <=
      #     Object, Integer < Comparable (transitive via include).
      #   - `obj.is_a?(klass)` where obj is a primitive (poly recv via
      #     sp_class_for_poly mapping) and klass is a sp_Class value.
      #     The pre-Tier-4 path returned the sp_Class{-1} sentinel for
      #     primitives.

      puts Integer.to_s            # Integer
      puts Float.to_s              # Float
      puts String.to_s             # String
      puts Array.to_s              # Array

      # Hierarchy queries on built-in classes.
      puts (Integer < Numeric) ? "int<num" : "int!<num"     # int<num
      puts (Integer <= Object) ? "int<=obj" : "int!<=obj"   # int<=obj
      puts (Integer < Comparable) ? "int<cmp" : "int!<cmp"  # int<cmp (via Numeric)
      puts (Float < Numeric) ? "flt<num" : "flt!<num"       # flt<num
      puts (String < Object) ? "str<obj" : "str!<obj"       # str<obj

      # Dynamic is_a?(klass) where klass is a Class-typed local pointing
      # at a built-in. The recv is a poly primitive.
      def check(obj, klass)
        obj.is_a?(klass)
      end

      int_klass = Integer
      str_klass = String
      num_klass = Numeric

      puts check(5, int_klass)     ? "5-int"  : "5-notint"      # 5-int
      puts check(5, str_klass)     ? "5-str"  : "5-notstr"      # 5-notstr
      puts check(5, num_klass)     ? "5-num"  : "5-notnum"      # 5-num
      puts check("hi", str_klass)  ? "hi-str" : "hi-notstr"     # hi-str
      puts check("hi", num_klass)  ? "hi-num" : "hi-notnum"     # hi-notnum
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      Float
      String
      Array
      int<num
      int<=obj
      int<cmp
      flt<num
      str<obj
      5-int
      5-notstr
      5-num
      hi-str
      hi-notnum
    OUT
  end

  it "class lt builtin parent" do
    result = ze0(<<~'RUBY')
      # Class#< with a built-in parent class. A user class A < StandardError
      # should report `A < StandardError == true` and have StandardError
      # in its ancestor chain.

      class A < StandardError; end
      class B < Numeric; end

      puts((A < StandardError).inspect)
      puts((A <= StandardError).inspect)
      puts((B < Numeric).inspect)
      puts((B < Object).inspect)
      # Sibling hierarchies: A < Object (true via StandardError -> Object).
      puts((A < Object).inspect)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
    OUT
  end

  it "class name in cmeth" do
    result = ze0(<<~'RUBY')
      # #509. `Class#name` (and `self.name`) inside `def self.X` body
      # previously fell through to the unresolved-call warning and
      # emitted 0. Used by ActiveRecord's `"#{name}.table_name must
      # be overridden"` raise pattern (4 sites in roundhouse).
      #
      # Fix: bare `name` in cmeth context routes to
      # sp_class_to_s({@current_class_idx}) via compile_no_recv_call_expr;
      # `self.name` is special-cased in compile_object_method_expr
      # (since SelfNode there types as obj_<C> and the obj-method
      # dispatch has no `name` arm). Analyze types both forms as
      # `string`.

      class Foo
        def self.who
          "I am #{name}"
        end
        def self.who_self
          "I am #{self.name}"
        end
      end

      class Bar
        def self.greet
          name + " says hi"
        end
      end

      puts Foo.who
      puts Foo.who_self
      puts Bar.greet
    RUBY

    _(result).must_answer <<~'OUT'
      I am Foo
      I am Foo
      Bar says hi
    OUT
  end

  it "class name means what it means here" do
    result = ze0(<<~'RUBY')
      # Whether a superclass NAME is a compile-time class or a constant holding one
      # minted at run time is a question about the site that spells it. Asking the
      # whole arena "is there a `class Error` anywhere" answers for every other site
      # too: citrus writes `module Citrus; class Error < StandardError`, toml-rb
      # writes `module TomlRB; Error = Class.new(StandardError)`, and with both
      # compiled in the second one's subclass was put on the static path, where
      # nothing defines `TomlRB::Error` at all.

      module Citrus
        class Error < StandardError; end
        class ParseError < Error; end
      end

      module TomlRB
        Error = Class.new(StandardError)
        ParseError = Class.new(Error)

        class ValueOverwriteError < Error
          def initialize(key)
            super("Key #{key.inspect} is defined more than once")
          end
        end
      end

      p TomlRB::ValueOverwriteError.new("k").message
      p TomlRB::ValueOverwriteError.superclass.equal?(TomlRB::Error)
      p TomlRB::ParseError.superclass.equal?(TomlRB::Error)
      p Citrus::ParseError.superclass.equal?(Citrus::Error)
      p TomlRB::Error.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      "Key \"k\" is defined more than once"
      true
      true
      true
      StandardError
    OUT
  end

  it "class named after a compiler type compiles and behaves" do
    result = ze0(<<~'RUBY')
      # `Vec`, `Option` and `Box` are names a compiler wants for itself. Ruby lets
      # a program take any of them, and the class must behave as Ruby says.

      class Vec
        def initialize(x, y)
          @x = x
          @y = y
        end
        attr_reader :x, :y
        def +(other) = Vec.new(@x + other.x, @y + other.y)
        def to_s = "Vec(#{@x}, #{@y})"
      end
      class Option
        def initialize(v) = @v = v
        def some? = !@v.nil?
      end
      class Box
        def initialize(v) = @v = v
        def get = @v
      end
      puts(Vec.new(1, 2) + Vec.new(10, 20))
      p Vec.new(1, 2).class.name
      p Option.new(nil).some?
      p Box.new(:b).get
    RUBY

    _(result).must_answer <<~'OUT'
      Vec(11, 22)
      "Vec"
      false
      :b
    OUT
  end

  it "class reopen replaces methods" do
    result = ze0(<<~'RUBY')
      # #489. Two `class Foo` definitions in the same translation unit
      # (whether from two require_relative'd files or a single file with
      # re-opened class) previously emitted duplicate C function symbols
      # for each repeated method name (sp_Foo_go twice, etc.), failing
      # C compile with "redefinition of 'sp_Foo_go'". CRuby's semantics
      # are "last definition wins": the second body replaces the first
      # for any method with the same name; methods unique to either copy
      # survive. Fix: append_cls_meth / append_cls_cmeth detect a matching
      # existing entry and replace its row in the parallel arrays instead
      # of appending. Same shape repro across require_relative is fully
      # covered by this single-file reopen.

      class Foo
        def initialize
          @x = 1
        end
        def go
          "first: " + @x.to_s
        end
        def only_first
          "kept"
        end
      end

      class Foo
        def initialize
          @x = 2
        end
        def go
          "second: " + @x.to_s
        end
        def only_second
          "added"
        end
      end

      f = Foo.new
      puts f.go
      puts f.only_first
      puts f.only_second
    RUBY

    _(result).must_answer <<~'OUT'
      second: 2
      kept
      added
    OUT
  end

  it "class value unified" do
    result = ze0(<<~'RUBY')
      # .class yields a first-class (name-backed) Class value for every receiver
      # kind: it compares with ===/== semantics, stringifies via to_s, and a Class
      # scrutinee in when matches only Class/Module.
      p 1.class
      p "s".class
      p :sym.class
      p nil.class
      p [1].class
      p({}.class)
      p 1.class == Integer
      p "s".class.to_s
      r = case :symbol.class
          when Symbol then "bar"
          when String then "bar"
          else "foo"
          end
      p r
      x = [1, "a"]
      p x[0].class
      puts "cls: #{1.class}"
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      String
      Symbol
      NilClass
      Array
      Hash
      true
      "String"
      "foo"
      Integer
      cls: Integer
    OUT
  end

  it "class var new arg" do
    result = ze0(<<~'RUBY')
      class Point
        def initialize(x); @x = x; end
        def to_s; "P(#{@x})"; end
      end

      pt = Point
      p pt.new(7).to_s
    RUBY

    _(result).must_answer "\"P(7)\"\n"
  end

  it "classes and modules" do
    result = ze0(<<~'RUBY', path: "ze0/classes_and_modules.rb")
      class Animal
        LEGS = 4

        def initialize(name)
          @name = name
          @sounds = 0
        end

        def name
          @name
        end

        def legs
          LEGS
        end

        def speak
          "..."
        end

        def describe
          "#{name} says #{speak}"
        end

        def heard
          @sounds += 1
          @sounds
        end

        def to_s
          "<#{self.class}: #{@name}>"
        end
      end

      class Dog < Animal
        def speak
          "woof"
        end
      end

      class Puppy < Dog
        def speak
          "yip"
        end
      end

      class Stack
        def initialize
          @items = []
        end

        def push(v)
          @items << v
          self
        end

        def each
          @items.each { |i| yield i }
          self
        end

        def size
          @items.size
        end
      end

      class Counter
        def self.build
          new
        end

        def self.label
          "counter"
        end

        def initialize
          @n = 0
        end

        def bump
          @n += 1
          self
        end

        def value
          @n
        end
      end

      module Greeting
        WORD = "hi"

        def self.hello
          WORD
        end
      end

      a = Animal.new("cat")
      d = Dog.new("rex")
      pup = Puppy.new("bit")

      p a.describe
      p d.describe
      p pup.describe
      p a.legs
      p d.class
      p Puppy.ancestors.first(4)
      p Puppy.superclass
      p d.is_a?(Animal)
      p d.is_a?(Puppy)
      puts d
      p a.heard
      p a.heard
      p Animal::LEGS
      p Animal.instance_methods(false).sort

      [Animal.new("a"), Dog.new("b"), Puppy.new("c")].each { |x| puts x.describe }

      s = Stack.new
      s.push(1).push(2).push(3)
      p s.size
      total = 0
      s.each { |i| total += i }
      p total

      c = Counter.build
      p c.bump.bump.bump.value
      p Counter.label
      p Counter.instance_methods(false).sort

      p Greeting.hello
      p Greeting.class
      p Greeting::WORD

      def boom(x)
        x.speak
      end
      p boom(d)

      class Account
        attr_accessor :balance
        attr_reader :owner
        attr_writer :note

        def initialize(owner, balance)
          @owner = owner
          @balance = balance
          @note = ""
        end

        def summary = "#{@owner}: #{@balance} #{@note}"

        private

        def secret = :hidden

        protected

        def guarded = :maybe

        public

        def open = :yes
      end

      # Ruby's visibility barrier is a question about the SITE: a receiverless
      # call asks nothing, and an explicit receiver is measured against the
      # class of `self` where the call is written.
      class Vault < Account
        # A sibling reaches a protected method; `self` here IS an Account.
        def kin?(other) = guarded == other.guarded

        # In a class method `self` is the class, which is no kind of Account,
        # so the same call is refused.
        def self.peek(a) = a.guarded

        # A receiverless call and an explicit `self` both reach a private one.
        def both = [secret, open]
      end

      class Savings < Account
        attr_reader :rate

        def initialize(owner, balance, rate)
          @owner = owner
          @balance = balance
          @note = "s"
          @rate = rate
        end

        def named = :n
        private :named
      end

      hi = Vault.new("hi", 9)
      lo = Vault.new("lo", 2)
      p hi.kin?(lo)
      p hi.both

      [["protected", -> { hi.guarded }],
       ["private", -> { hi.secret }],
       ["from a class method", -> { Vault.peek(hi) }]].each do |what, go|
        p [what, go.call]
      rescue NoMethodError => e
        p [what, e.message]
      end

      p Account.instance_methods(false).sort
      p Account.private_instance_methods(false).sort
      p Account.protected_instance_methods(false).sort
      p Savings.private_instance_methods(false).sort
      p Account.instance_method(:balance).parameters
      p Account.instance_method(:balance=).parameters
      p Account.instance_method(:balance).arity
      p Account.instance_method(:balance=).arity
      p Account.instance_method(:balance).source_location.last

      acct = Account.new("ada", 10)
      p acct.owner, acct.balance, acct.summary
      acct.balance = 25
      acct.note = "!"
      p acct.balance, acct.summary
      p acct.instance_variables

      sav = Savings.new("bob", 5, 2)
      p sav.owner, sav.balance, sav.rate, sav.summary
      sav.balance = 7
      p sav.balance, sav.instance_variables
      p acct.send(:secret), sav.send(:named)

      class Boom < StandardError
      end

      class Louder < Boom
        attr_accessor :code
      end

      class Bad < ArgumentError
      end

      p Boom.superclass, Louder.superclass, Bad.superclass
      p Boom.ancestors.first(5)
      p Boom.new("hi").message
      p Boom.new.message
      p Louder.new("x").is_a?(StandardError)
      p Louder.new("x").is_a?(Boom)
      p Bad.new("y").is_a?(ArgumentError)
      p Boom.instance_methods(false)

      loud = Louder.new("m")
      loud.code = 7
      p loud.code, loud.message, loud.instance_variables


      class Walker
        def initialize(name)
          @name = name
        end

        def step = "..."
        def trail = "#{@name} #{step}"

        def each
          yield 1
          yield 2
        end
      end

      class Runner < Walker
        def initialize(name, pace)
          super(name)
          @pace = pace
        end

        def step = "#{super}!"
        def trail = "#{super} @#{@pace}"

        def each(&blk) = super(&blk)
      end

      class Sprinter < Runner
        def step = "#{super}#{super}"

        def each
          super { |v| yield v * 10 }
        end
      end

      p Walker.new("w").trail
      p Runner.new("r", 5).trail
      p Sprinter.new("s", 9).trail
      p Sprinter.new("s", 9).step

      seen = []
      Sprinter.new("s", 1).each { |v| seen << v }
      p seen

      class Quiet < Walker
        def step(loud = "shh") = super()
      end
      p Quiet.new("q").step

      class Boom2 < StandardError
        def initialize(msg = "boom")
          super
        end
      end

      class Louder2 < Boom2
        def initialize(msg)
          super("#{msg}!")
        end
      end

      p Boom2.new.message, Boom2.new("x").message, Louder2.new("y").message
      p Louder2.new("y").is_a?(StandardError)


      class Ledger
        TOTAL = 0
        SECRET = :hidden
        private_constant :SECRET

        attr_reader :rows

        def initialize = @rows = []

        private def stamp(row) = "#{row}!"

        def add(row)
          @rows << stamp(row)
          self
        end

        alias push add

        def size = @rows.size
        alias_method :count, :size
      end

      led = Ledger.new
      led.add("a").push("b")
      p led.rows, led.size, led.count
      p Ledger::TOTAL
      p Ledger.constants.sort
      p Ledger.private_instance_methods(false).sort
      p Ledger.instance_methods(false).sort

      begin
        Ledger::SECRET
      rescue NameError => e
        p e.class, e.message
      end

      def blow_up
        raise Louder, "went wrong"
      end
      blow_up
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR', status: 1
      "cat says ..."
      "rex says woof"
      "bit says yip"
      4
      Dog
      [Puppy, Dog, Animal, Object]
      Dog
      true
      false
      <Dog: rex>
      1
      2
      4
      [:describe, :heard, :legs, :name, :speak, :to_s]
      a says ...
      b says woof
      c says yip
      3
      6
      3
      "counter"
      [:bump, :value]
      "hi"
      Module
      "hi"
      "woof"
      true
      [:hidden, :yes]
      ["protected", "protected method 'guarded' called for an instance of Vault"]
      ["private", "private method 'secret' called for an instance of Vault"]
      ["from a class method", "protected method 'guarded' called for an instance of Vault"]
      [:balance, :balance=, :guarded, :note=, :open, :owner, :summary]
      [:initialize, :secret]
      [:guarded]
      [:initialize, :named]
      []
      [[:req]]
      0
      1
      141
      "ada"
      10
      "ada: 10 "
      25
      "ada: 25 !"
      [:@owner, :@balance, :@note]
      "bob"
      5
      2
      "bob: 5 s"
      7
      [:@owner, :@balance, :@note, :@rate]
      :hidden
      :n
      StandardError
      Boom
      ArgumentError
      [Boom, StandardError, Exception, Object, Kernel]
      "hi"
      "Boom"
      true
      true
      true
      []
      7
      "m"
      [:@code]
      "w ..."
      "r ...! @5"
      "s ...!...! @9"
      "...!...!"
      [10, 20]
      "..."
      "boom"
      "x"
      "y!"
      true
      ["a!", "b!"]
      2
      2
      0
      [:TOTAL]
      [:initialize, :stamp]
      [:add, :count, :push, :rows, :size]
      NameError
      "private constant Ledger::SECRET referenced"
    OUT
      ze0/classes_and_modules.rb:356:in 'Object#blow_up': went wrong (Louder)
      	from ze0/classes_and_modules.rb:358:in '<main>'
    ERR
  end

  it "compiled class allocates directly" do
    result = ze0(<<~'RUBY')
      # `Foo.new` on a plain compiled class allocates without dispatching for
      # `new` at all: the runtime's `new` is served by the CONSTRUCTOR, not by a
      # class-method row, so the call site's cache could only ever remember the
      # miss and re-walk the singleton chain per allocation.
      #
      # The gate is what this file is really about -- every shape below has to
      # keep the dynamic route, because each is a question only the run time can
      # answer:
      #   - an own `def self.new` overrides the constructor
      #   - `private_class_method :new` raises NoMethodError from the walk
      #   - a class with no `initialize` rejects arguments as `Object#initialize`
      #   - a raise from `initialize` is attributed to `initialize`, not the site
      class A
        def initialize(x = 5, *rest, &b) = (@x = x; @r = rest; @b = b ? b.call : nil)
        def to_s = "A(#{@x},#{@r},#{@b})"
      end
      class B < A; end
      class Priv
        def self.make = new
        private_class_method :new
      end
      class Own
        def self.new(*a) = "own new #{a.inspect}"
      end
      class NoInit; end
      puts A.new
      puts A.new(1, 2, 3)
      puts A.new { 42 }
      puts B.new(9)
      p Priv.make.class
      begin; Priv.new; rescue NoMethodError => e; puts e.message; end
      p Own.new(1)
      p NoInit.new.class
      begin; NoInit.new(1); rescue ArgumentError => e; puts e.message; end
      class Raiser; def initialize = raise("boom"); end
      begin; Raiser.new; rescue => e; puts "#{e.message} @ #{e.backtrace.first}"; end
    RUBY

    _(result).must_answer <<~'OUT'
      A(5,[],)
      A(1,[2, 3],)
      A(5,[],42)
      A(9,[],)
      Priv
      private method 'new' called for class Priv
      "own new [1]"
      NoInit
      wrong number of arguments (given 1, expected 0)
      boom @ lang/classes/formatting_test.rb:35:in 'Raiser#initialize'
    OUT
  end

  it "core classes" do
    result = ze0(<<~'RUBY')
      # The P-B core classes: File, Dir, Time, Process, ENV.
      #
      # Everything here is zone- and machine-independent on purpose: Time uses a
      # fixed epoch read in UTC, paths are built under a scratch directory this
      # script creates, and nothing prints a real pid/clock/environment value --
      # only facts about them. That is what lets the output be diffed against real
      # ruby at all.

      # --- File: the pure-path family (string work, never touches the disk) -------
      puts File.basename("/home/user/notes.md")
      puts File.basename("/home/user/notes.md", ".md")
      puts File.basename("/home/user/notes.md", ".*")
      puts File.basename("/a/b/")
      puts File.dirname("/home/user/notes.md")
      puts File.dirname("solo")
      puts File.dirname("/x")
      p File.extname("archive.tar.gz")
      p File.extname(".bashrc")      # a LEADING dot is a name, not an extension
      p File.extname("trailing.")    # ...but a TRAILING one is an extension
      p File.split("/a/b/c.rb")
      puts File.join("a", "b", "c")
      puts File.join("a/", "/b")     # the separator at the seam collapses
      p File.absolute_path?("/abs")
      p File.absolute_path?("rel")

      # --- Time: a fixed instant, read in UTC ------------------------------------
      t = Time.at(1700000000).getutc
      puts t.to_s
      puts t.inspect
      p [t.year, t.month, t.day, t.hour, t.min, t.sec]
      p [t.wday, t.yday]
      p t.to_i
      p t.utc?
      p t.zone
      p t.utc_offset
      p t.monday?, t.tuesday?

      # strftime -- the directive table, including Ruby's own padding flags.
      puts t.strftime("%Y-%m-%d %H:%M:%S")
      puts t.strftime("%F %T")
      puts t.strftime("%a %A %b %B")
      puts t.strftime("%j %u %w %p %I")
      puts t.strftime("%z %Z")
      puts t.strftime("100%% literal")
      jan = Time.at(1704067200).getutc  # 2024-01-01, a single-digit month
      puts jan.strftime("%m|%-m|%_m")

      # Arithmetic: `t + n` is a Time, `t - other_time` is a Float of seconds.
      p (t + 60).to_i
      p (t - 60).to_i
      p (Time.at(100) - Time.at(40))
      p (Time.at(100) - Time.at(40)).class

      # A Float epoch is kept EXACTLY -- `subsec` answers the double's true
      # fraction, and `nsec` is the truncated view of it.
      p Time.at(0.5).subsec
      p Time.at(10.8).subsec
      p Time.at(10.8).nsec
      p (Time.at(10.8) - 0.9).nsec
      p Time.at(1.25).to_f
      p Time.at(-0.5).to_i           # floored: second -1 ...
      p Time.at(-0.5).nsec           # ... plus a positive remainder

      # Time includes Comparable, so the whole ordering surface follows from <=>.
      p Time.at(5) < Time.at(6)
      p Time.at(5).between?(Time.at(1), Time.at(9))
      p Time.at(1).clamp(Time.at(2), Time.at(5)).to_i
      p [Time.at(3), Time.at(1), Time.at(2)].sort.map(&:to_i)
      p Time.at(5) == Time.at(5)
      p Time.at(5).getutc == Time.at(5)   # equality is by instant, not by zone
      p({ Time.at(99) => "found" }[Time.at(99)])

      # The civil constructors. `Time.utc`'s 7th argument is MICROSECONDS...
      u = Time.utc(2007, 11, 1, 15, 25, 0, 123456)
      p u.usec
      p u.nsec
      puts u.inspect
      # ...while `Time.new`'s is a UTC OFFSET in seconds.
      o = Time.new(2000, 1, 1, 0, 0, 0, 3600)
      p o.utc_offset
      p o.utc?
      puts o.to_s

      # --- Dir and File, on a real scratch tree ----------------------------------
      # (`Dir.mktmpdir`/`Dir.tmpdir` are stdlib's tmpdir.rb, not core -- built by
      # hand here so the example needs no require. The pid keeps concurrent runs
      # from colliding.)
      root = File.join(ENV.fetch("TMPDIR", "/tmp"), "zeo_core_classes_#{Process.pid}")
      Dir.mkdir(root)
      begin
        Dir.chdir(root) do
          Dir.mkdir("sub")
          File.write("one.rb", "alpha\nbeta\n")
          File.write("two.txt", "")
          File.write("sub/three.rb", "gamma\n")

          p File.read("one.rb")
          p File.readlines("one.rb")
          p File.readlines("one.rb", chomp: true)
          p File.size("one.rb")
          p File.exist?("one.rb"), File.exist?("nope.rb")
          p File.file?("one.rb"), File.file?("sub")
          p File.directory?("sub"), File.directory?("one.rb")
          p File.zero?("two.txt"), File.zero?("one.rb")
          p File.size?("two.txt")   # nil for an EMPTY file, not 0
          p File.size?("one.rb")

          # Dir listing and globbing.
          p Dir.children(".").sort
          p Dir.entries(".").sort
          p Dir.glob("*.rb").sort
          p Dir.glob("**/*.rb").sort
          p Dir.glob("*.{rb,txt}").sort
          p Dir.glob("?ne.rb")
          p Dir["*.rb"]
          p Dir.exist?("sub"), Dir.exist?("nope")
          p Dir.empty?("sub")

          # File.open: the block form closes afterwards and answers the block's
          # value; a lengthed read at EOF is nil where a whole-rest read is "".
          File.open("counted.txt", "w") { |f| f.print "ABCDEFGHIJ" }
          File.open("counted.txt", "r") do |f|
            p f.read(5)
            p f.read(5)
            p f.read(5)      # nil at EOF
            f.rewind
            p f.read(2)
            p f.tell
            f.seek(0)
            p f.read
            p f.eof?
          end
          p File.open("counted.txt", "r") { |f| f.read(3) }

          # A closed file raises rather than reading garbage.
          h = File.open("counted.txt", "r")
          h.close
          p h.closed?
          begin
            h.read
          rescue IOError => e
            puts "IOError: #{e.message}"
          end

          File.delete("two.txt")
          p File.exist?("two.txt")
          File.rename("one.rb", "renamed.rb")
          p File.exist?("renamed.rb")

          # Clean the tree from the inside, so the ensure below only has to remove
          # the (now empty) root.
          Dir.glob("**/*").sort.reverse.each do |e|
            File.directory?(e) ? Dir.rmdir(e) : File.delete(e)
          end
        end
      ensure
        Dir.rmdir(root) if Dir.exist?(root)
      end

      # --- Errors: the Errno family, with CRuby's message shape ------------------
      begin
        File.read("/definitely/not/here")
      rescue Errno::ENOENT => e
        puts "#{e.class}: #{e.message}"
      end
      p Errno::ENOENT.superclass
      p Errno::ENOENT.ancestors.include?(StandardError)

      begin
        Dir.entries("/definitely/not/here")
      rescue SystemCallError => e     # caught by the PARENT class
        puts e.class
      end

      # --- ENV: an Object with Hash-shaped methods, not a Hash -------------------
      p ENV.class
      ENV["ZEO_EXAMPLE"] = "set"
      p ENV["ZEO_EXAMPLE"]
      p ENV.key?("ZEO_EXAMPLE")
      p ENV.fetch("ZEO_EXAMPLE")
      p ENV.fetch("ZEO_ABSENT", "default")
      p ENV.fetch("ZEO_ABSENT") { |k| "computed:#{k}" }
      p ENV["ZEO_ABSENT"]
      p ENV.delete("ZEO_EXAMPLE")
      p ENV.key?("ZEO_EXAMPLE")
      p ENV.to_h.class
      p ENV.keys.class

      # --- Process ---------------------------------------------------------------
      p Process.pid.is_a?(Integer)
      p Process.pid > 0
      p Process.clock_gettime(Process::CLOCK_MONOTONIC).is_a?(Float)
      p Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond).is_a?(Integer)
    RUBY

    _(result).must_answer <<~'OUT'
      notes.md
      notes
      notes
      b
      /home/user
      .
      /
      ".gz"
      ""
      "."
      ["/a/b", "c.rb"]
      a/b/c
      a/b
      true
      false
      2023-11-14 22:13:20 UTC
      2023-11-14 22:13:20 UTC
      [2023, 11, 14, 22, 13, 20]
      [2, 318]
      1700000000
      true
      "UTC"
      0
      false
      true
      2023-11-14 22:13:20
      2023-11-14 22:13:20
      Tue Tuesday Nov November
      318 2 2 PM 10
      +0000 UTC
      100% literal
      01|1| 1
      1700000060
      1699999940
      60.0
      Float
      (1/2)
      (225179981368525/281474976710656)
      800000000
      900000000
      1.25
      -1
      500000000
      true
      true
      2
      [1, 2, 3]
      true
      true
      "found"
      123456
      123456000
      2007-11-01 15:25:00.123456 UTC
      3600
      false
      2000-01-01 00:00:00 +0100
      "alpha\nbeta\n"
      ["alpha\n", "beta\n"]
      ["alpha", "beta"]
      11
      true
      false
      true
      false
      true
      false
      true
      false
      nil
      11
      ["one.rb", "sub", "two.txt"]
      [".", "..", "one.rb", "sub", "two.txt"]
      ["one.rb"]
      ["one.rb", "sub/three.rb"]
      ["one.rb", "two.txt"]
      ["one.rb"]
      ["one.rb"]
      true
      false
      false
      "ABCDE"
      "FGHIJ"
      nil
      "AB"
      2
      "ABCDEFGHIJ"
      true
      "ABC"
      true
      IOError: closed stream
      false
      true
      Errno::ENOENT: No such file or directory @ rb_sysopen - /definitely/not/here
      SystemCallError
      true
      Errno::ENOENT
      Object
      "set"
      true
      "set"
      "default"
      "computed:ZEO_ABSENT"
      nil
      "set"
      false
      Hash
      Array
      true
      true
      true
      true
    OUT
  end

  it "def self inside class self is unreachable" do
    result = ze0(<<~'RUBY')
      # A `def self.x` written INSIDE `class << self` defines a method on the
      # singleton's OWN singleton -- `K.singleton_class.x` -- and it is NOT a class
      # method of `K`.
      #
      # `class << self`'s body is retagged onto the enclosing class, so a plain `def`
      # there becomes a class method (see `zeo-singleton-model`). Retagging a
      # `def self.x` the same way put it one level too low, which was two divergences
      # from one drop: `K.x` answered where ruby raises NoMethodError, and
      # `K.singleton_class.x` was undefined.
      #
      # The level it belongs to has no compile-time namespace in zeo, and needs
      # none: a singleton class is an ordinary OBJECT at run time, so the def is a
      # per-object singleton method on it -- exactly what `class << obj` already
      # spells, through the same `define_singleton_method` lowering. `class << obj`
      # had the same hole and takes the same route.
      #
      # The wider sweep is `tests/singleton_chain_dispatch_sweep.rb`.

      class K
        class << self
          def hi = "class method"
          def self.meta = "meta"
        end
      end
      p K.hi
      begin
        p K.singleton_class.meta
      rescue NoMethodError => e
        p e.class.to_s
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "class method"
      "meta"
    OUT
  end

  it "env gated class stays concealed" do
    result = ze0(<<~'RUBY')
      if ENV["ZEO_NOPE"]
        class Gated
          def x = 1
        end
      end
      puts defined?(Gated).inspect
      puts Object.constants.include?(:Gated)
      begin
        Object.const_get(:Gated)
      rescue NameError => e
        puts "raised #{e.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      false
      raised NameError
    OUT
  end

  it "every native class allocates where ruby does" do
    result = ze0(<<~'RUBY')
      # `Class#allocate` answers a blank instance for every native class ruby
      # allocates, and refuses for every one ruby refuses -- with ruby's own error
      # class each time.
      #
      # 30 of these 52 rows used to diverge. Only 2 of zeo's 98 native classes
      # declared a blank value, so `allocate` fell through to a refusal for the
      # other 26 that ruby allocates, and `Marshal.load` -- which allocates before
      # it fills -- could not load any of them.
      #
      # The three shapes ruby uses, and now zeo too:
      #
      #   * a blank instance, for a class whose payload has an empty form;
      #   * `TypeError: allocator undefined for X`, for a class with no blank;
      #   * `NoMethodError: undefined method 'allocate' for class X`, for the five
      #     ruby UNDEFINES the name on (`zeo_abi::ALLOCATE_UNDEFINED`). The two
      #     refusals are not interchangeable: `rescue TypeError` around
      #     `MatchData.allocate` catches nothing.

      %w[date set stringio strscan pathname time bigdecimal zlib socket monitor
         objspace digest etc].each { |f| require f }

      NAMES = %w[
        Array Hash String Range Regexp MatchData Object BasicObject Rational Complex
        Struct Data Time Date DateTime Set StringIO StringScanner Pathname BigDecimal
        Dir File IO Encoding Enumerator Enumerator::Lazy Method UnboundMethod Proc
        Binding Module Class Thread Mutex Queue SizedQueue ConditionVariable
        ThreadGroup Fiber Random ObjectSpace::WeakMap Digest::MD5 Zlib::Deflate
        Zlib::Inflate Socket TCPSocket Etc::Passwd Process::Status Exception
        RuntimeError Errno::ENOENT TracePoint Symbol Integer Float
      ]

      NAMES.each do |n|
        k = Object.const_get(n)
        row = begin
                # `BasicObject` has no `#class`, so name the class we asked rather
                # than the one the instance reports.
                k.allocate
                "ok"
              rescue ScriptError, StandardError => e
                "#{e.class}: #{e.message}"
              end
        puts "#{n}\t#{row}"
      end

      # The undef is INHERITED, because ruby's sits on the singleton chain.
      sub = Class.new(MatchData)
      begin
        sub.allocate
        puts "subclass\tallocated"
      rescue NoMethodError => e
        puts "subclass\t#{e.class}"
      end

      # And it is a genuinely absent method, not a raising one.
      puts "respond_to?\t#{[Rational, Complex, MatchData, Module].map { |k| k.respond_to?(:allocate) }.uniq.inspect}"

      # A blank reports its own class, including where the payload alone could not
      # say which one it is (`File` and the sockets share `IO`'s).
      puts "classes\t#{[File, IO, Socket, TCPSocket, Date, DateTime, Queue, SizedQueue].map { |k| k.allocate.class }.inspect}"
    RUBY

    _(result).must_answer <<~'OUT'
      Array	ok
      Hash	ok
      String	ok
      Range	ok
      Regexp	ok
      MatchData	NoMethodError: undefined method 'allocate' for class MatchData
      Object	ok
      BasicObject	ok
      Rational	NoMethodError: undefined method 'allocate' for class Rational
      Complex	NoMethodError: undefined method 'allocate' for class Complex
      Struct	TypeError: allocator undefined for Struct
      Data	TypeError: allocator undefined for Data
      Time	ok
      Date	ok
      DateTime	ok
      Set	ok
      StringIO	ok
      StringScanner	ok
      Pathname	ok
      BigDecimal	TypeError: allocator undefined for BigDecimal
      Dir	ok
      File	ok
      IO	ok
      Encoding	TypeError: allocator undefined for Encoding
      Enumerator	ok
      Enumerator::Lazy	ok
      Method	TypeError: allocator undefined for Method
      UnboundMethod	TypeError: allocator undefined for UnboundMethod
      Proc	TypeError: allocator undefined for Proc
      Binding	TypeError: allocator undefined for Binding
      Module	NoMethodError: undefined method 'allocate' for class Module
      Class	ok
      Thread	TypeError: allocator undefined for Thread
      Mutex	ok
      Queue	ok
      SizedQueue	ok
      ConditionVariable	ok
      ThreadGroup	ok
      Fiber	ok
      Random	ok
      ObjectSpace::WeakMap	ok
      Digest::MD5	ok
      Zlib::Deflate	ok
      Zlib::Inflate	ok
      Socket	ok
      TCPSocket	ok
      Etc::Passwd	ok
      Process::Status	ok
      Exception	ok
      RuntimeError	ok
      Errno::ENOENT	ok
      TracePoint	TypeError: allocator undefined for TracePoint
      Symbol	TypeError: allocator undefined for Symbol
      Integer	TypeError: allocator undefined for Integer
      Float	TypeError: allocator undefined for Float
      subclass	NoMethodError
      respond_to?	[false]
      classes	[File, IO, Socket, TCPSocket, Date, DateTime, Thread::Queue, Thread::SizedQueue]
    OUT
  end

  it "a Hash default block runs for a missing key and not for a written one" do
    result = ze0(<<~'RUBY')
      h = Hash.new { |hash, key| "missing: #{key}" }
      puts h[:a]
      puts h[:b]
      h[:c] = "set"
      puts h[:c]
      puts h[:d]

      counts = Hash.new { |hsh, k| 0 }
      counts[:x] = 5
      puts counts[:x]
      puts counts[:y]

      d = Hash.new { |hsh, key| key.to_s.length }
      puts d["hello"]
      puts d["hi"]
    RUBY

    _(result).must_answer <<~'OUT'
      missing: a
      missing: b
      set
      missing: d
      5
      0
      5
      2
    OUT
  end

  it "initialize override param inference" do
    result = ze0(<<~'RUBY')
      # A subclass `initialize` override repurposes its positional parameters; a
      # parent `initialize` parameter default (e.g. `opts = nil`) must not widen an
      # unrelated override parameter to poly. Each case checks the override param
      # carries its value through, and that string params stay concrete.

      # Minimal repro: parent nil-default, child int param.
      class Base1
        def initialize(opts = nil)
          @id = 0
        end
      end
      class Article1 < Base1
        attr_reader :id
        def initialize(id = 0)
          @id = id
        end
      end
      a1 = Article1.new(7)
      puts a1.class.to_s
      puts a1.id

      # Multi-param override: int + two string params, none poisoned.
      class Base2
        def initialize(opts = nil)
          @id = 0
        end
      end
      class Article2 < Base2
        attr_reader :id, :title, :body
        def initialize(id = 0, title = "", body = "")
          @id = id
          @title = title
          @body = body
        end
      end
      a2 = Article2.new(7, "t", "b")
      puts a2.id
      puts a2.title
      puts a2.body

      # Parent concrete default (control: must keep working).
      class Base3
        def initialize(opts = 0)
          @id = 0
        end
      end
      class Article3 < Base3
        attr_reader :id
        def initialize(id = 0)
          @id = id
        end
      end
      puts Article3.new(7).id

      # Explicit super() with no forwarding.
      class Base4
        def initialize(opts = nil)
          @id = 0
        end
      end
      class Article4 < Base4
        attr_reader :id
        def initialize(id = 0)
          super()
          @id = id
        end
      end
      puts Article4.new(7).id
    RUBY

    _(result).must_answer <<~'OUT'
      Article1
      7
      7
      t
      b
      7
      7
    OUT
  end

  it "nil value class union" do
    result = ze0(<<~'RUBY')
      # `nil | W` where W would otherwise be a value-layout class: any nil
      # witness on a W-typed slot disqualifies the value layout (a by-value
      # struct has no nil), falling back to the pointer form whose NULL-nil
      # machinery narrows as usual. Each shape below was a miscompile
      # (`return 0` into a struct return) or would be.
      class W
        def initialize(v); @v = v; end
        def year; @v; end
      end

      # return nil | W
      def maybe(s)
        return nil if s.nil?
        W.new(70)
      end
      a = maybe("x")
      puts a.nil? ? "nil" : a.year.to_s
      puts maybe(nil).nil?

      # ternary arm nil
      def pick(f)
        f ? W.new(1) : nil
      end
      p pick(true).nil?
      p pick(false).nil?

      # local seeded nil then assigned
      w = nil
      w = W.new(3) if maybe("x")
      puts w.nil? ? "nil" : w.year.to_s

      # optional param defaulting nil
      def show(x = nil)
        x.nil? ? "none" : "got " + x.year.to_s
      end
      puts show
      puts show(W.new(9))
    RUBY

    _(result).must_answer <<~'OUT'
      70
      true
      false
      true
      3
      none
      got 9
    OUT
  end

  it "qualified class ruby name" do
    result = ze0(<<~'RUBY')
      # A nested class whose leaf name is a builtin's is qualified internally
      # (`Brainfuck__Array`) so it cannot be mistaken for the builtin. Its
      # Ruby-visible name is still `Brainfuck::Array`, through every spelling.

      module Brainfuck
        class Array
          def self.bench_name
            name.to_s
          end
          def label
            self.class.name
          end
        end
      end

      p Brainfuck::Array.bench_name
      p Brainfuck::Array.new.label
      p Brainfuck::Array.name
    RUBY

    _(result).must_answer <<~'OUT'
      "Brainfuck::Array"
      "Brainfuck::Array"
      "Brainfuck::Array"
    OUT
  end

  it "qualified reopen keeps nesting" do
    result = ze0(<<~'RUBY')
      # A class first seen through a compact `module A::B::C` definition still
      # resolves bare enclosing names from a NESTED reopen's body: CRuby's
      # nesting is per definition site, and the nested site carries the full
      # chain (rspec-core's formatters.rb opens `module RSpec::Core::Formatters`
      # compact while base_formatter.rb nests the same module around
      # `Formatters.register self`).
      module Outer
        module Core
        end
      end
      module Outer::Core::Fmt
        def self.register(k) = (@r ||= []) << k
        def self.registered = @r
      end
      module Outer
        module Core
          module Fmt
            class Base
              Fmt.register self.name
            end
          end
        end
      end
      p Outer::Core::Fmt.registered
    RUBY

    _(result).must_answer "[\"Outer::Core::Fmt::Base\"]\n"
  end

  it "reflective program keeps every class" do
    result = ze0(<<~'RUBY')
      # Reflection wide enough to produce ANY class is a hatch, not an edge: no
      # scan of the source bounds what these can name, so the compiler stops
      # narrowing the builtin method tables and carries all of them
      # (`analyze::class_reach::hands_out_every_class`).
      #
      # Each block below names its class only THROUGH the reflective surface, so
      # the narrowed set would have dropped it.

      p Marshal.load(Marshal.dump({ a: [1, 2] }))

      name = ["Path", "name"].join
      p Object.const_get(name).public_send(:new, "/tmp").basename.to_s

      verb = ["to", "_c"].join
      p 2.send(verb)

      p Object.constants.include?(:Comparable)

      seen = []
      ObjectSpace.each_object(Class) { |c| seen << c }
      p seen.is_a?(Array)
    RUBY

    _(result).must_answer <<~'OUT'
      {a: [1, 2]}
      "tmp"
      (2+0i)
      true
      true
    OUT
  end

  it "reopened builtin" do
    result = ze0(<<~'RUBY')
      # A gated builtin is the runtime's half of a library whose other half is
      # ruby: `require "digest"` reveals the module the runtime carries, and a
      # `module Digest` after it REOPENS that module rather than shadowing it.
      require "digest"

      module Digest
        MARKER = :mine

        class Tag
          def initialize(name) = @name = name

          def to_s = "tag:#{@name}"
        end

        def self.marker = [MARKER, Tag.new("t").to_s]
      end

      # A second statement reopens the same module again, and reads what the
      # first one wrote.
      module Digest
        def self.again = MARKER
      end

      p Digest.marker
      p Digest.again
      p Digest.name
      p Digest.instance_of?(Module)
      p Digest.constants.include?(:MARKER)
      p Digest.const_get(:MARKER)

      # The reopen adds to the module; it does not replace it, so the native
      # half is still there.
      p Digest::SHA256.hexdigest("a")
      p Digest::MD5.hexdigest("")

      # A class written inside the reopen is the module's, under its qualified
      # name, and its own instance variables are its own.
      p Digest::Tag.new("x").to_s
      p Digest::Tag.name
      p Digest::Tag.new("y").instance_variables
    RUBY

    _(result).must_answer <<~'OUT'
      [:mine, "tag:t"]
      :mine
      "Digest"
      true
      true
      :mine
      "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
      "d41d8cd98f00b204e9800998ecf8427e"
      "tag:x"
      "Digest::Tag"
      [:@name]
    OUT
  end

  it "reopened builtin class runs a ruby initialize" do
    result = ze0(<<~'RUBY')
      # Reopening a natively implemented builtin with a Ruby `initialize` runs
      # that body.
      #
      # Ruby's `new` is `allocate` plus `initialize`, and a builtin's registered
      # constructor FUSES the two, so the Ruby body was never consulted:
      # `Pathname.new` left `@path` nil and all 94 of its methods read it. That is
      # what kept the `pathname` corelib segment off.
      #
      # `Class#new` now asks whether a NON-NATIVE `initialize` wins the lookup. The
      # two rows live in different tables -- a compile-time reopen registers on the
      # VALUE channel, the native row is in the class's static method table -- so
      # the answer is exact. The gap file said `method_owner` could not tell them
      # apart; true, and it names the wrong table.
      #
      # Both reopen channels are covered below: a `class Pathname; def initialize`
      # body, and a runtime `define_method(:initialize)`.
      #
      # NOT probed here, and not a bug this can fix: once a Ruby `initialize`
      # replaces the native one and does not set the NATIVE state, a native reader
      # sees that state's default where ruby sees nil (`Pathname#to_s` answers ""
      # against ruby's nil). That is the native/Ruby hybrid seam, and it closes
      # when the `pathname` corelib segment replaces the native rows outright. A
      # reopen that adds only ordinary methods keeps the native constructor and is
      # what every other Pathname test in the corpus exercises.
      class Pathname
        def initialize(a) = @p = "P:#{a}"
        def mine = @p
      end
      p [Pathname.new("/x").mine, Pathname.new("/x").instance_variables]

      # `Pathname.allocate` used to raise `allocator undefined`. A class states its
      # own blank value with `allocate <fn>;` in its `ruby_class!` header.
      p Pathname.allocate.inspect
      p Pathname.allocate.instance_variables

      # A runtime install reaches it through the overlay.
      Pathname.class_eval do
        define_method(:initialize) { |a| @q = "Q:#{a}" }
        define_method(:other) { @q }
      end
      p [Pathname.new("/z").other, Pathname.new("/z").instance_variables]

      # Everything else about a reopen already worked, and stays so a fix cannot
      # regress it: an ordinary override, and a Ruby ivar on each natively backed
      # value.
      class Array
        def mine = "A-#{size}"
        def stash = (@a = 1)
      end
      p [[1, 2].mine, [1].stash]
      class String
        def mine = "S"
        def stash = (@s = 7)
      end
      p ["q".mine, "q".stash]
      class Hash
        def stash = (@h = 9)
      end
      p({}.stash)
      class Exception
        def stash = (@e = 4)
      end
      p RuntimeError.new("x").stash
      class Object
        def stash = (@o = 5)
      end
      p Object.new.stash

      # A bootstrap builtin must NOT read as a reopen: exceptions keep their own
      # rows on the object channel, and asking it lost every `RuntimeError.new`.
      p RuntimeError.new("boom").message
      p String.new("s")
      p Array.new(2, 0)
      p Hash.new(9)[:k]
    RUBY

    _(result).must_answer <<~'OUT'
      ["P:/x", [:@p]]
      "#<Pathname:>"
      []
      ["Q:/z", [:@q]]
      ["A-2", 1]
      ["S", 7]
      9
      4
      5
      "boom"
      "s"
      [0, 0]
      9
    OUT
  end

  it "splat and double splat at a new call site" do
    result = ze0(<<~'RUBY')
      # A `*args` positional splat and a `**h` double-splat at `.new`
      # dispatch through the runtime constructor rather than being rejected.

      class Point
        def initialize(x, y); @x = x; @y = y; end
        def to_s; "(#{@x}, #{@y})"; end
      end
      Pair = Data.define(:a, :b)
      args = [1, 2]
      h = { a: 3, b: 4 }
      puts Point.new(*args)
      p Pair.new(**h)
      p Pair.new(**{ a: 5, b: 6 })
    RUBY

    _(result).must_answer <<~'OUT'
      (1, 2)
      #<data Pair a=3, b=4>
      #<data Pair a=5, b=6>
    OUT
  end

  it "superclass clause reads the enclosing ancestry" do
    result = ze0(<<~'RUBY')
      # A bare constant resolves in two halves: the lexical scopes' own tables, then
      # the ANCESTORS of the innermost one. A superclass clause is a bare constant,
      # so `class Leaf < Inner` nested in `class Mid < Base` finds `Base::Inner`.
      #
      # Zeo did only the first half for a superclass clause -- ordinary reads
      # already did both -- so the definition resolved to nothing, was rewritten
      # into a runtime `Leaf = Class.new(Inner)`, and the next line's `Leaf.new`
      # raised `uninitialized constant`.
      #
      # rake writes exactly this: `class Scope < LinkedList` nests `class EmptyScope
      # < EmptyLinkedList`, where `EmptyLinkedList` is a constant of `LinkedList`.
      # `require "rake"` died on the `EMPTY = EmptyScope.new` two lines below it.

      class Base
        class Inner
          def who = "inner"
        end
        module Marker; end
        WIDTH = 7
      end

      class Mid < Base
        class Leaf < Inner
          def who = "leaf"
        end
        ONE = Leaf.new
      end

      p Mid::Leaf.superclass
      p Mid::Leaf.name
      p Mid::ONE.who
      p Mid::Leaf.ancestors.take(3).map(&:to_s)

      # The lexical half still wins over the ancestry half.
      class Shadow < Base
        class Inner
          def who = "shadowed"
        end
        class Leaf < Inner; end
      end
      p Shadow::Leaf.superclass.name
      p Shadow::Leaf.new.who

      # A module of that name in the ancestry is still a TypeError, as ruby says.
      begin
        Class.new(Base) { const_set(:Bad, Class.new(Base::Marker)) }
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Base::Inner
      "Mid::Leaf"
      "leaf"
      ["Mid::Leaf", "Base::Inner", "Object"]
      "Shadow::Inner"
      "shadowed"
      superclass must be an instance of Class (given an instance of Module)
    OUT
  end

  it "user initialize on a native class runs" do
    skip "Kernel#format raises ArgumentError where ruby formats the value"

    result = ze0(<<~'RUBY')

      # A native class's `new` FUSES allocate and initialize, so it cannot run a
      # body it does not know about. Ruby's `new` is allocate plus whatever
      # `initialize` resolves to, so once a program reopens the class with its own,
      # the native construction is GONE -- `String.new("x")` answers `""` and
      # `Hash.new(5)` has no default. Only `new` is affected: `Time.now` and
      # `Time.at` build their own instances and never ask.

      def t(label)
        r = begin
          yield.inspect
        rescue Exception => e
          "#{e.class}: #{e.message}"
        end
        puts format("%-26s %s", label, r)
      end

      class String
        def initialize(*) = @s = 1
      end
      t("String.new content") { String.new("x") }
      t("String.new ivars") { String.new("x").instance_variables }
      t("a literal is unaffected") { "y" }

      class Time
        def initialize(*) = @t = "T"
        def mine = @t
      end
      t("Time.new") { [Time.new.mine, Time.new.instance_variables] }
      t("Time.now unaffected") { Time.now.instance_variables }
      t("Time.at unaffected") { Time.at(0).instance_variables }
      t("through a variable") { k = Time; [k.new.mine, k.new.instance_variables] }
      t("Class#new directly") { Class.instance_method(:new).bind(Time).call.mine }

      class Hash
        def initialize(*) = @h = 1
      end
      t("Hash.new content") { h = Hash.new(5); [h.default, h.instance_variables] }

      class Array
        def initialize(*) = @a = 1
      end
      t("Array.new content") { Array.new(3, 0) }
    RUBY

    _(result).must_answer <<~'OUT'
      String.new content         ""
      String.new ivars           [:@s]
      a literal is unaffected    "y"
      Time.new                   ["T", [:@t]]
      Time.now unaffected        []
      Time.at unaffected         []
      through a variable         ["T", [:@t]]
      Class#new directly         "T"
      Hash.new content           [nil, [:@h]]
      Array.new content          []
    OUT
  end

  it "visibility change in a reopened class" do
    result = ze0(<<~'RUBY')
      # Visibility is positional: `private :name` in a REOPENED class body applies
      # from that point in program order, and calls made while the method was still
      # public succeed. zeo's analyze folds visibility into one order-insensitive
      # table (the later `private` is visible to reflection from the start), and
      # compiled static call sites never re-check visibility at all -- so the
      # explicit-receiver call after the reopen still succeeds where ruby raises
      # NoMethodError.
      class Toggler
        def pub
          "pub"
        end
      end

      t = Toggler.new
      puts t.pub
      puts Toggler.public_method_defined?(:pub).inspect

      class Toggler
        private :pub
      end

      begin
        t.pub
      rescue NoMethodError => e
        puts "after reopen: #{e.class}"
      end
      puts Toggler.public_method_defined?(:pub).inspect
      puts Toggler.private_method_defined?(:pub).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      pub
      true
      after reopen: NoMethodError
      false
      true
    OUT
  end
end
