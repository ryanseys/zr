# frozen_string_literal: true

require "spec_helper"

describe "Classes: slicing" do
  it "bare call class before toplevel" do
    result = zr(<<~'RUBY')
      # A bare call inside a method resolves the way CRuby's ancestry does: the
      # enclosing class's own chain answers it before a top-level `def` does, because
      # a top-level def lands on Object, which is BELOW the class. Spinel kept
      # top-level defs in a flat table consulted ahead of the class members, so a
      # helper in a class lost to a same-named helper beside it.
      def helper = "top"
      def size = 9
      def name = "top-name"

      class K
        def helper = "class"
        def size = 5
        def run = helper
        def sz = size
      end

      class Base
        def helper = "base"
      end

      class Sub < Base
        def run = helper
      end

      class NoneOfIt
        def run = helper
      end

      class Attr
        attr_reader :name
        def initialize
          @name = "attr"
        end

        def run = name
      end

      p K.new.run
      p K.new.sz
      p Sub.new.run
      p NoneOfIt.new.run
      p Attr.new.run
      p helper
      p size
      p name

      # a class method's bare call sees its own class first as well
      class Counter
        def self.bump = tick
        def self.tick = 3
      end
      def tick = 99
      p Counter.bump
      p tick
    RUBY

    _(result).must_answer <<~'OUT'
      "class"
      5
      "base"
      "top"
      "attr"
      "top"
      9
      "top-name"
      3
      99
    OUT
  end

  it "class body is its own scope" do
    result = zr(<<~'RUBY')
      # A class or module body is a SEPARATE SCOPE, not a region of the one that
      # encloses it. CRuby says so structurally: `NODE_CLASS` compiles the body with
      # `NEW_CHILD_ISEQ(..., ISEQ_TYPE_CLASS)` (compile.c), a child iseq with its own
      # local table, and `NODE_MODULE` does the same. Only the SUPERCLASS expression
      # is compiled into the enclosing iseq -- `COMPILE(ret, "super", nd_super)` sits
      # beside the `defineclass` instruction, not inside the child -- which is why
      # `class Sub < sup` can read `sup` while `Sub`'s body cannot.
      #
      # zr emits each body as its own function for exactly this reason (see
      # `codegen::emit_class_body_site_lifted`), so this file is the rule that lift
      # stands on. A body that could see an enclosing local would have to be emitted
      # inside the enclosing scope, and `fn main` would go back to being the whole
      # class-definition phase of the program in one function body.
      #
      # Every `nil` below is a name the body must NOT see. The last two sections are
      # the two ways a body still reaches outward -- a nested body is its own scope
      # again, and a body's own locals are ordinary locals an escaping block closes
      # over (optparse's accept-table setup is this shape).

      outer = :outer

      class Scoped
        p defined?(outer)
        inner = :inner
        p inner
        # A `def` is a third scope: it cannot see the class body's locals either.
        def self.reads_inner = defined?(inner)
      end
      p defined?(inner)
      p Scoped.reads_inner

      # A REOPEN runs a new body, with a new local table -- the first body's locals
      # are gone, not carried forward.
      class Scoped
        p defined?(inner)
      end

      module Moduled
        p defined?(outer)
        m = :m
        p m
      end

      # The superclass expression runs in the ENCLOSING scope and reads `sup`; the
      # body that follows it does not.
      sup = Struct.new(:a)
      class WithSuper < sup
        p defined?(sup)
      end
      p WithSuper.new(1).a

      class Nesting
        mid = :mid
        class Inner
          p defined?(mid)
        end
        p mid
      end

      # A body written inside a BLOCK sees no more than one at the top level: the
      # block's own `i` is not in scope.
      [10].each do |i|
        class InBlock
          p defined?(i)
        end
      end

      # A body's OWN locals are ordinary locals, and an escaping block closes over
      # them the way one written at the top level does.
      class Escaping
        seen = []
        %w[a b].each { |el| seen << el }
        p seen
      end
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      :inner
      nil
      nil
      nil
      nil
      :m
      nil
      1
      nil
      :mid
      nil
      ["a", "b"]
    OUT
  end

  it "class body is worth its last statement" do
    result = zr(<<~'RUBY')
      # A `class`/`module` is an expression, and its value is the body's last
      # statement -- nil for an empty body, the symbol a trailing `def` answers,
      # and a nested definition's own value when that is what ends the body.
      x = class Solo
        def a; end
      end
      p x

      y = class Empty
      end
      p y

      z = module Mod
        1 + 1
      end
      p z

      w = class Outer
        class Inner
          7
        end
      end
      p w

      class Holder
        M = (class Inner2; 7; end)
        N = (module Inner3; end)
      end
      p Holder::M, Holder::N

      # The value is a RECEIVER as readily as anything else -- `end.freeze` sends to
      # whatever the body answered, not to the module (regexp-examples spells its
      # constant tables this way).
      module Wrapper
        module Frozen
          A = [1].freeze
        end.freeze
      end
      p Wrapper::Frozen::A.frozen?

      r = class Named2
        def m; 1; end
      end.name
      p r

      # `undef` and `alias` answer nil, unlike the `undef_method`/`alias_method`
      # sends that spell the same effect (those answer the module and the new name).
      class Named
        def a; end
        def b; end
        U = (undef :a)
        A = (alias c b)
      end
      p Named::U, Named::A
    RUBY

    _(result).must_answer <<~'OUT'
      :a
      nil
      2
      7
      7
      nil
      true
      "m"
      nil
      nil
    OUT
  end

  it "class def order" do
    result = zr(<<~'RUBY')
      # Issue #14: classes referenced before their definition must still
      # produce a working struct layout. Earlier classes that embed a
      # value-type instance of a later class need the later class's struct
      # to be emitted first.

      class Box
        def initialize
          @ticket = Ticket.new(7)
        end
        def num; @ticket.num; end
      end

      class Ticket
        def initialize(num)
          @num = num
        end
        def num; @num; end
      end

      puts Box.new.num                # 7

      # Multi-level chain: Outer -> Middle -> Leaf, all defined back-to-front.
      class Outer
        def initialize
          @mid = Middle.new
          @leaf = Leaf.new(11)
        end
        def show
          puts @mid.value
          puts @leaf.value
        end
      end

      class Middle
        def initialize
          @leaf = Leaf.new(3)
        end
        def value; @leaf.value; end
      end

      class Leaf
        def initialize(v); @v = v; end
        def value; @v; end
      end

      Outer.new.show                  # 3 / 11

      # Parent class has a value-type ivar of a class defined later: child
      # inherits the (flattened) field, so the dep walk must follow the
      # parent chain too.
      class Holder
        def initialize
          @item = Item.new(42)
        end
        def value; @item.value; end
      end

      class SubHolder < Holder
      end

      class Item
        def initialize(v); @v = v; end
        def value; @v; end
      end

      puts SubHolder.new.value        # 42
    RUBY

    _(result).must_answer <<~'OUT'
      7
      3
      11
      42
    OUT
  end

  it "class is not its own superclass" do
    files = beside("own_superclass/abstract.rb", "own_superclass/adapter.rb", "own_superclass/base.rb")

    result = zr(<<~'RUBY', files: files)
      # Ruby evaluates a superclass expression BEFORE it binds the class's own name,
      # so the name being defined is never a candidate for its own superclass -- the
      # lexical search walks straight past it and continues outward. Rails writes
      # exactly this, literally: `class SchemaDumper < SchemaDumper` inside
      # `ActiveRecord::ConnectionAdapters`, meaning `ActiveRecord::SchemaDumper`.
      #
      # Resolving it to the inner name instead makes a class its own parent, and a
      # superclass chain that points at itself is an infinite walk: every unguarded
      # `parent` loop in the compiler runs forever on it.

      module App
        class Dumper
          def kind = :outer
        end

        module Adapters
          class Dumper < Dumper
            def extra = :extra
          end
        end
      end

      p App::Adapters::Dumper.superclass
      p App::Adapters::Dumper.new.kind
      p App::Adapters::Dumper.new.extra
      p App::Dumper.superclass

      # ... and the adapter subclasses that then inherit THROUGH it -- the rest of
      # the shape, where a chain that pointed at itself would have looped.
      module App
        module Adapters
          class MySQL < Adapters::Dumper
            def kind = [:mysql, super]
          end
        end
      end

      p App::Adapters::MySQL.new.kind
      p App::Adapters::MySQL.ancestors.take(3)

      # The same shape ACROSS FILES, which is how rails has it: the abstract file
      # writes `class Dumper < Dumper` and the adapters inherit through it. Split
      # across a require graph, the name the superclass clause must skip is one the
      # other files have already referenced.
      require_relative "own_superclass/base"
      require_relative "own_superclass/abstract"
      require_relative "own_superclass/adapter"

      p Store::Adapters::Dumper.superclass
      p Store::Adapters::Dumper.new.extra
      p Store::Adapters::MySQL.new.kind
      p Store::Adapters::MySQL.ancestors.take(3)

      # A deeper name still wins when it is a REAL definition rather than the one
      # being written: nothing here is skipped.
      module App
        class Real
          def who = :top
        end

        module Adapters
          class Real
            def who = :nested
          end

          class UsesNested < Real
          end
        end
      end

      p App::Adapters::UsesNested.new.who
      p App::Adapters::UsesNested.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      App::Dumper
      :outer
      :extra
      Object
      [:mysql, :outer]
      [App::Adapters::MySQL, App::Adapters::Dumper, App::Dumper]
      Store::Dumper
      :extra
      [:mysql, :base]
      [Store::Adapters::MySQL, Store::Adapters::Dumper, Store::Dumper]
      :nested
      App::Adapters::Real
    OUT
  end

  it "a class method bumping a shared counter reads it back through the class variable" do
    result = zr(<<~'RUBY')
      # ClassVariableReadNode -- `@@var`, plus expression-form
      # ClassVariableWriteNode (the `@@x = ...` last-expression-as-return
      # path) and several real-world class-var idioms.
      #
      # Spinel's class vars are independent per declaring class -- the
      # ClassVariableWriteNode commit covers the storage-shape
      # limitation in detail. This test exercises only patterns that
      # stay inside one class's slot (no cross-hierarchy reads).

      # 1. Singleton-counter idiom: class-method bumps a shared counter,
      #    instance-method reads it. Both routes touch @@count via the
      #    same @current_class_idx, so they share the cvar_Counter_count
      #    slot.
      class Counter
        @@count = 0

        def self.tick
          @@count = @@count + 1   # expression-form ClassVariableWriteNode
        end

        def self.value
          @@count                  # plain ClassVariableReadNode
        end

        def instance_value
          @@count                  # readable from instance methods too
        end
      end

      puts Counter.value           # 0
      Counter.tick
      Counter.tick
      Counter.tick
      puts Counter.value           # 3
      puts Counter.new.instance_value   # 3 -- instance reads same slot


    RUBY

    _(result).must_answer <<~'OUT'
      0
      3
      3
    OUT
  end

  it "two unrelated classes with the same class-variable name keep their own" do
    result = zr(<<~'RUBY')
      # ClassVariableReadNode -- `@@var`, plus expression-form
      # ClassVariableWriteNode (the `@@x = ...` last-expression-as-return
      # path) and several real-world class-var idioms.
      #
      # Spinel's class vars are independent per declaring class -- the
      # ClassVariableWriteNode commit covers the storage-shape
      # limitation in detail. This test exercises only patterns that
      # stay inside one class's slot (no cross-hierarchy reads).

      # 2. Per-class isolation: two unrelated classes with the same cvar
      #    name get independent slots. Without the per-class qualification
      #    in cvar_qname, Counter.tick would have changed Other's count
      #    too.
      class Other
        @@count = 100

        def self.value
          @@count
        end
      end

      puts Other.value             # 100, unaffected by Counter.tick calls


    RUBY

    _(result).must_answer <<~'OUT'
      100
    OUT
  end

  it "a class variable given a non-zero value in the class body keeps it" do
    result = zr(<<~'RUBY')
      # ClassVariableReadNode -- `@@var`, plus expression-form
      # ClassVariableWriteNode (the `@@x = ...` last-expression-as-return
      # path) and several real-world class-var idioms.
      #
      # Spinel's class vars are independent per declaring class -- the
      # ClassVariableWriteNode commit covers the storage-shape
      # limitation in detail. This test exercises only patterns that
      # stay inside one class's slot (no cross-hierarchy reads).

      # 3. Cvar with explicit non-zero initial value at class body. Spinel
      #    folds the literal into the static C decl (compile-time), so the
      #    cvar enters the program with the source's value rather than the
      #    type default. Conditional rewrites at class body level (e.g.
      #    `if X; @@y = ...; end`) are NOT supported -- Spinel doesn't run
      #    class-body statements at startup, only constant assignments and
      #    method definitions get hoisted.
      class Config
        @@debug = true
        @@max_retries = 5

        def self.debug?; @@debug; end
        def self.max_retries; @@max_retries; end
      end

      puts Config.debug?           # true (folded into static decl)
      puts Config.max_retries      # 5


    RUBY

    _(result).must_answer <<~'OUT'
      true
      5
    OUT
  end

  it "a class variable updated across many class-method calls accumulates" do
    result = zr(<<~'RUBY')
      # ClassVariableReadNode -- `@@var`, plus expression-form
      # ClassVariableWriteNode (the `@@x = ...` last-expression-as-return
      # path) and several real-world class-var idioms.
      #
      # Spinel's class vars are independent per declaring class -- the
      # ClassVariableWriteNode commit covers the storage-shape
      # limitation in detail. This test exercises only patterns that
      # stay inside one class's slot (no cross-hierarchy reads).

      # 4. Cvar updated across many class-method calls -- the cumulative
      #    state lives in the cvar slot, not in any temporary. Chained
      #    `.add(n).add(m)` returning self isn't supported in Spinel
      #    (class methods are static C functions with no self), so we
      #    call separately.
      class Tally
        @@total = 0

        def self.add(n)
          @@total = @@total + n
        end

        def self.total
          @@total
        end
      end

      Tally.add(10)
      Tally.add(20)
      Tally.add(12)
      puts Tally.total             # 42


    RUBY

    _(result).must_answer <<~'OUT'
      42
    OUT
  end

  it "a class variable written from an instance method is read by a class method" do
    result = zr(<<~'RUBY')
      # ClassVariableReadNode -- `@@var`, plus expression-form
      # ClassVariableWriteNode (the `@@x = ...` last-expression-as-return
      # path) and several real-world class-var idioms.
      #
      # Spinel's class vars are independent per declaring class -- the
      # ClassVariableWriteNode commit covers the storage-shape
      # limitation in detail. This test exercises only patterns that
      # stay inside one class's slot (no cross-hierarchy reads).

      # 5. Cvar mutation across instance and class methods of the same
      #    class. Real Ruby code mixes these freely (e.g. ActiveRecord
      #    counter caches).
      class Registry
        @@items = 0

        def self.count
          @@items
        end

        def register
          @@items = @@items + 1
        end
      end

      r = Registry.new
      r.register
      r.register
      puts Registry.count          # 2
    RUBY

    _(result).must_answer <<~'OUT'
      2
    OUT
  end

  it "initialize takes the full param shapes" do
    result = zr(<<~'RUBY')
      # `.new` was the last call site still binding arguments by hand, and it
      # only handled required + optional -- `def initialize(*values)` was a
      # flat compile-time rejection.

      class Splat
        def initialize(*v); @v = v; end
        attr_reader :v
      end
      p Splat.new.v
      p Splat.new(1).v
      p Splat.new(1, 2, 3).v

      class Mixed
        def initialize(a, b = 5, *rest, last)
          @all = [a, b, rest, last]
        end
        attr_reader :all
      end
      p Mixed.new(1, 9).all
      p Mixed.new(1, 2, 3, 4, 9).all

      class Kw
        def initialize(a, k:, j: 7, **rest)
          @all = [a, k, j, rest]
        end
        attr_reader :all
      end
      p Kw.new(1, k: 2).all
      p Kw.new(1, k: 2, j: 3, z: 4).all

      class Post
        def initialize(a, *m, y, z); @all = [a, m, y, z]; end
        attr_reader :all
      end
      p Post.new(1, 2, 3, 4, 5).all
      p Post.new(1, 2, 3).all
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [1]
      [1, 2, 3]
      [1, 5, [], 9]
      [1, 2, [3, 4], 9]
      [1, 2, 7, {}]
      [1, 2, 3, {z: 4}]
      [1, [2, 3], 4, 5]
      [1, [], 2, 3]
    OUT
  end

  it "nested reopen resolves enclosing const" do
    result = zr(<<~'RUBY')
      # A class first defined COMPACT (`class Outer::Widget`) and later reopened
      # NESTED (`module Outer; class Widget`) must resolve a bare constant against the
      # reopen's enclosing nesting (`Outer::Helper`), not just the compact def's own
      # scope -- the rubygems `Gem::StubSpecification` / `prepend BetterPermissionError`
      # shape.
      module Outer
      end

      class Outer::Widget
      end

      module Outer
        module Helper
          def hi = "helper"
        end

        class Widget
          prepend Helper
        end
      end

      puts Outer::Widget.new.hi
    RUBY

    _(result).must_answer "helper\n"
  end

  it "poly first last n" do
    result = zr(<<~'RUBY')
      # `first(n)` / `last(n)` on a value whose type is only known at run time, in a
      # program where a user class owns the name (which is what routes the call
      # through the dispatch at all).
      class Bag
        def initialize(a)
          @a = a
        end

        def first(n = 1)
          @a[0, n]
        end

        def last(n = 1)
          @a[-n, n]
        end
      end

      def pick(f)
        f ? [1, 2, 3, 4] : nil
      end

      x = pick(true)
      p x.first
      p x.first(2)
      p x.last
      p x.last(2)
      p x.first(0)
      p x.first(99)

      b = Bag.new([7, 8, 9])
      p b.first
      p b.first(2)
      p b.last(2)

      def pickh(f)
        f ? { "a" => 1, "b" => 2 } : nil
      end
      p pickh(true).first(1)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [1, 2]
      4
      [3, 4]
      []
      [1, 2, 3, 4]
      [7]
      [7, 8]
      [8, 9]
      [["a", 1]]
    OUT
  end

  it "pre reopen call sees the final body" do
    result = zr(<<~'RUBY')
      # A call that executes BEFORE a class is reopened must run the body that
      # exists at that moment. zr compiles one function per surviving method row
      # (last-def-wins across the whole program), so the first call below already
      # dispatches to the reopened body. Fixing this for real means versioned
      # method emission with position-aware call sites, or routing reopened
      # redefinitions through the runtime overlay at their execution point -- the
      # same timeline family as method_added_sees_the_superseded_body.rb (and, in
      # the same shape, visibility_change_in_a_reopened_class.rb).
      class Early
        def word
          "first"
        end
      end

      puts Early.new.word

      class Early
        def word
          "second"
        end
      end

      puts Early.new.word
    RUBY

    _(result).must_answer "first\nsecond\n"
  end

  it "reopening a user class adds and replaces methods" do
    result = zr(<<~'RUBY')
      # Pre-15.2 this was the codebase's one SILENT-wrongness bug: the second
      # `class Foo` registered a shadowed duplicate, so `b` never dispatched
      # and the original `a` kept winning.

      class Foo
        def a
          "first"
        end
      end

      class Foo
        def b
          "added"
        end

        def a
          "replaced"
        end
      end

      puts Foo.new.a
      puts Foo.new.b
    RUBY

    _(result).must_answer "replaced\nadded\n"
  end
end
