# frozen_string_literal: true

require "spec_helper"

describe "Object: slicing" do
  it "class object id" do
    result = ze0(<<~'RUBY')
      # A class is an object, so it needs an `object_id` of its own. Every class
      # used to report the same one, which quietly broke anything memoizing on it --
      # a `seen[mod.object_id]` guard would treat the first class it met as every
      # class it met afterwards.

      MODS = [Object, BasicObject, Array, Hash, String, Symbol, Integer, Float,
              Comparable, Enumerable, Kernel, Math, Process, Struct, Class, Module]

      puts "-- every class and module gets its own id"
      ids = MODS.map(&:object_id)
      p ids.uniq.size == MODS.size

      puts "-- and the same one every time it is asked"
      p MODS.map(&:object_id) == ids

      puts "-- so a cache keyed on it distinguishes them"
      seen = {}
      MODS.each { |m| seen[m.object_id] = m }
      p seen.size

      puts "-- a class id never collides with an instance's"
      objs = [Object.new, "s", [], {}, :sym, 1, 2.5, nil, true, false]
      p (ids & objs.map(&:object_id)).empty?

      puts "-- __id__ is the same answer"
      p Array.__id__ == Array.object_id
      p Array.object_id != Hash.object_id

      puts "-- singleton classes are distinct too"
      p Array.singleton_class.object_id != Hash.singleton_class.object_id
    RUBY

    _(result).must_answer <<~'OUT'
      -- every class and module gets its own id
      true
      -- and the same one every time it is asked
      true
      -- so a cache keyed on it distinguishes them
      16
      -- a class id never collides with an instance's
      true
      -- __id__ is the same answer
      true
      true
      -- singleton classes are distinct too
      true
    OUT
  end

  it "define singleton method installs a closure" do
    result = ze0(<<~'RUBY')
      # `define_singleton_method(:literal) { ... }` desugars to a `def self.name`
      # node so the installed method has a compile-time home. The node carries an
      # `is_def` flag saying whether it came from the `def` KEYWORD, and the desugar
      # set it `true` on the grounds that the install path reads `is_class_method`
      # instead. Three other things read it, and all three were wrong:
      #
      #   THE BODY IS A CLOSURE. `captures`'s `DefMethod` arm walks a body only when
      #   it is reachable as an escaping proc -- a real `def` opens a scope of its
      #   own and cannot see an enclosing local at all. Marked as a `def`, the block
      #   was never walked, so an enclosing local it reads was never promoted to a
      #   shared cell: the closure fresh-declared the name and answered `nil`. Where
      #   the desugar sat inside ANOTHER block, the same miss surfaced instead as
      #   codegen's escaping-block refusal (active_fields, unparser, proc_to_ast).
      #
      #   A BARE `super` IS AN ERROR IN IT. Ruby refuses to guess the arguments for
      #   a method whose body is a block (`scope_is_define_method`); zeo ran it.
      #
      #   ITS FRAME IS NAMED AFTER THE BLOCK, not after the method it creates --
      #   `block in <class:Traced>`, the same label `define_method` gets.
      #
      # `is_def: false` is what its `define_method` sibling already carried.

      # --- the closure, at every scope a capture can come from --------------------
      class Store
        def self.build_class_method(v)
          define_singleton_method(:from_class_method) { v }
          define_method(:from_define_method) { v }
        end

        def build_instance_singleton(v)
          define_singleton_method(:from_instance_method) { v }
        end
      end

      Store.build_class_method(1)
      p Store.from_class_method
      p Store.new.from_define_method

      store = Store.new
      store.build_instance_singleton(2)
      p store.from_instance_method

      def build_at_top_level(v)
        define_singleton_method(:from_top_level) { v }
      end
      build_at_top_level(3)
      p from_top_level

      # A `def` written inside a block, whose parameter the desugar's block reads:
      # the shape that hit the escaping-block refusal.
      [0].each do
        def build_inside_a_block(v)
          define_singleton_method(:from_inside_a_block) { v }
        end
      end
      build_inside_a_block(4)
      p from_inside_a_block

      # Each install is its own closure over its own capture -- not one shared cell.
      class Registry
        [:a, :b].each do |key|
          define_singleton_method(:"lookup_#{key}") { key }
        end
      end
      p Registry.lookup_a
      p Registry.lookup_b

      # --- `super` ----------------------------------------------------------------
      class Base
        def self.describe(n) = "Base.describe(#{n})"
      end

      class Implicit < Base
        define_singleton_method(:describe) { |n| super }
      end

      begin
        Implicit.describe(1)
      rescue RuntimeError => e
        puts "#{e.class}: #{e.message}"
      end

      # Spelling the arguments out is how ruby says to write it.
      class Explicit < Base
        define_singleton_method(:describe) { |n| super(n) }
      end
      p Explicit.describe(2)

      # --- the frame label --------------------------------------------------------
      class Traced
        define_singleton_method(:label) { caller_locations(0, 1).first.label }
      end
      p Traced.label
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      2
      3
      4
      :a
      :b
      RuntimeError: implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly.
      "Base.describe(2)"
      "block in <class:Traced>"
    OUT
  end

  it "define singleton method installs at its position" do
    result = ze0(<<~'RUBY')
      # `C.define_singleton_method(:m) { }` written at STATEMENT position is a
      # runtime event with a place in the program. Lowering desugared it into an
      # inline `def self.m` reopen, and last-`def`-wins then made both call sites
      # answer the new body -- so the method reached back in time.
      class Later
        def self.mode = :compiled
      end

      p Later.mode
      Later.define_singleton_method(:mode) { :runtime }
      p Later.mode
      p Later.singleton_methods(false).sort

      # A name the class never defined is added, not replaced.
      Later.define_singleton_method(:fresh) { :new_one }
      p Later.fresh
      p Later.respond_to?(:fresh)

      # The block is a real closure over its writing scope.
      tag = :captured
      Later.define_singleton_method(:tagged) { tag }
      p Later.tagged

      # Arguments bind through the block's parameter list.
      Later.define_singleton_method(:twice) { |n| n * 2 }
      p Later.twice(21)

      # The IN-BODY spelling still installs at compile time, where nothing can
      # observe a before.
      class InBody
        define_singleton_method(:mode) { :from_body }
      end
      p InBody.mode
      p InBody.singleton_methods(false)

      # `self.` inside a body means the same thing.
      class SelfBody
        self.define_singleton_method(:mode) { :from_self }
      end
      p SelfBody.mode
    RUBY

    _(result).must_answer <<~'OUT'
      :compiled
      :runtime
      [:mode]
      :new_one
      true
      :captured
      42
      :from_body
      [:mode]
      :from_self
    OUT
  end

  it "first ivar write appends only a name no row holds" do
    result = ze0(<<~'RUBY')
      # One write site shared by classes whose tables order names differently.
      module Setter
        def set_b(v) = (@b = v)
        def set_a(v) = (@a = v)
      end
      class AB; include Setter; def initialize = (@a = 1; @b = 2); end
      class BA; include Setter; def initialize = (@b = 3); end
      class Empty; include Setter; end
      objs = [AB.new, BA.new, Empty.new]
      objs.each { |o| o.set_b(9); o.set_a(8); o.set_b(7) }
      objs.each { |o| p [o.class, o.instance_variables, o.instance_variables.map { |n| o.instance_variable_get(n) }] }

      # Seventy names: every bit of the filter collides.
      class Many
        def initialize
          70.times { |i| instance_variable_set(:"@v#{i}", i) }
        end
        def again
          @v3 = :three
          @v67 = :sixty_seven
          @fresh = :fresh
          self
        end
      end
      m = Many.new.again
      p m.instance_variables.size, m.instance_variables.uniq.size, m.instance_variable_get(:@v67), m.instance_variable_get(:@fresh)

      # Removal, then the same name written again at a site.
      class Removal
        def initialize = (@x = 1; @y = 2)
        def put_x(v) = (@x = v)
      end
      r = Removal.new
      r.remove_instance_variable(:@x)
      r.put_x(5)
      r.put_x(6)
      p r.instance_variables, r.instance_variable_get(:@x)

      # dup and clone, then a first write on the copy.
      class Pt
        def initialize = (@x = 1)
        def add_y = (@y = 2; self)
        def add_x = (@x = 10; self)
      end
      a = Pt.new
      b = a.dup.add_y.add_x
      c = a.clone.add_x.add_y
      p a.instance_variables, b.instance_variables, c.instance_variables, b.instance_variable_get(:@x)

      # Marshal round trip, then writes.
      d = Marshal.load(Marshal.dump(Pt.new)).add_y.add_x
      p d.instance_variables, d.instance_variable_get(:@x)

      # Many objects through initialize, with a collection between.
      class Node
        def initialize(v) = (@l = nil; @r = nil; @v = v; @t = "n"; @u = v * 2)
        attr_reader :v, :u, :t
      end
      nodes = Array.new(20_000) { |i| Node.new(i) }
      GC.start
      p nodes.sum(&:u), nodes.map(&:t).uniq, nodes[17].instance_variables

      # A frozen object and a class's own ivars.
      f = Pt.new.freeze
      begin
        f.add_y
      rescue => e
        p e.class
      end
      class Pt; @count = 1; def self.bump = (@count += 1; @other = 2); end
      Pt.bump
      p Pt.instance_variables

    RUBY

    _(result).must_answer <<~'OUT'
      [AB, [:@a, :@b], [8, 7]]
      [BA, [:@b, :@a], [7, 8]]
      [Empty, [:@b, :@a], [7, 8]]
      71
      71
      :sixty_seven
      :fresh
      [:@y, :@x]
      6
      [:@x]
      [:@x, :@y]
      [:@x, :@y]
      10
      [:@x, :@y]
      10
      399980000
      ["n"]
      [:@l, :@r, :@v, :@t, :@u]
      FrozenError
      [:@count, :@other]
    OUT
  end

  it "hashing an object hands out its object id" do
    result = ze0(<<~'RUBY')
      # An object's hash comes from its object_id, which the first hash hands
      # out, as CRuby's objid_hash does: an object put in a Hash takes the next
      # id, and the next object_id asked for counts past it.
      h = {Object.new => 1}
      p Object.new.object_id
      s = Object.new
      p s.hash == s.hash, {s => 2}[s], [s].uniq.size, s.object_id

    RUBY

    _(result).must_answer <<~'OUT'
      24
      true
      2
      1
      32
    OUT
  end

  it "module new with only definitions is a real module" do
    result = ze0(<<~'RUBY')
      # `Readers = Module.new` (rspec-core writes exactly that) and its block form
      # build a module the rest of the program mixes in -- so zeo compiles the pair
      # to the `module Readers ... end` they are equivalent to, and `include` becomes
      # a static ancestry edge instead of a runtime splice no compiled class can see.
      Readers = Module.new
      p Readers.class
      p Readers.name
      p Readers.instance_methods(false)

      Greet = Module.new do
        def hello = "hello"
        def self.tag = "greet"
        attr_reader :who
        private def secret = "shh"
        alias hi hello
      end
      p Greet.name
      p Greet.instance_methods(false).sort
      p Greet.private_instance_methods(false).sort
      p Greet.tag

      class Host
        include Greet
        include Readers
        def initialize = @who = "world"
      end
      h = Host.new
      p h.hello, h.hi, h.who
      p Host.ancestors.first(4)
      p h.is_a?(Greet)
      p Greet.instance_method(:hello).owner

      # The assignment answers with the MODULE; the `module` keyword answers with its
      # body's last statement. Only the first is right here.
      p(Val = Module.new { def a = 1 })

      # A nested one is named for where it is written, and a later `module` reopens
      # the same module rather than defining a second one.
      module Outer
        Inner = Module.new do
          def deep = "deep"
        end
      end
      module Outer
        module Inner
          def deeper = "deeper"
        end
      end
      class C1
        include Outer::Inner
      end
      p C1.new.deep, C1.new.deeper
      p Outer::Inner.name
      p Outer.constants.sort

      # A body that names a CONSTANT keeps the runtime spelling: a real module joins
      # the constant lookup of everything written inside it, and `Module.new`'s block
      # opens no scope of its own -- `X = 1` here writes `Object::X`, and `Module.nesting`
      # answers with the enclosing chain, not with this module.
      Scoped = Module.new do
        X = 1
        def self.nest = Module.nesting
      end
      p Scoped.name
      p defined?(Scoped::X)
      p X
      p Scoped.nest
    RUBY

    _(result).must_answer <<~'OUT'
      Module
      "Readers"
      []
      "Greet"
      [:hello, :hi, :who]
      [:secret]
      "greet"
      "hello"
      "hello"
      "world"
      [Host, Readers, Greet, Object]
      true
      Greet
      Val
      "deep"
      "deeper"
      "Outer::Inner"
      [:Inner]
      "Scoped"
      nil
      1
      []
    OUT
  end

  it "parse warning duplicate key" do
    result = ze0(<<~'RUBY')
      # Ruby warns at PARSE time when a literal hash key is written twice: the
      # second value wins silently, so the warning is the only sign. It names the
      # line the surviving value is on, which is not always the line of the key it
      # overwrote.
      #
      # These are the only warnings zeo forwards. They arrive on stderr before any
      # program output, which is where CRuby prints them too -- see the sidecar
      # golden.

      # --- a hash literal ----------------------------------------------------------
      p({ k: 1, k: 2 })
      p({ "s" => 1, "s" => 2 })
      p({ 1 => :a, 1 => :b })

      # --- across lines: the warning points at the WINNER ---------------------------
      p({
        dup: 1,
        other: 2,
        dup: 3,
      })

      # --- keyword arguments are the same list ------------------------------------
      def capture(**opts) = opts
      p capture(a: 1, a: 2)

      # --- a splat colliding with a literal pair ----------------------------------
      p({ x: 0, **{ x: 9 } })
      p capture(**{ y: 1 }, y: 2)

      # --- inside a method body, and inside a block -------------------------------
      def build = { m: 1, m: 2 }
      p build
      p [1].map { { b: 1, b: 2 } }

      # --- three of the same key warn twice ---------------------------------------
      p({ t: 1, t: 2, t: 3 })

      # --- keys that only LOOK duplicated do not warn ------------------------------
      p({ a: 1, b: 2 })
      p({ "a" => 1, a: 2 })
      p({ 1 => :int, "1" => :str, :"1" => :sym })
      n = 1
      p({ n => :first, 2 => :second })
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      {k: 2}
      {"s" => 2}
      {1 => :b}
      {dup: 3, other: 2}
      {a: 2}
      {x: 9}
      {y: 2}
      {m: 2}
      [{b: 2}]
      {t: 3}
      {a: 1, b: 2}
      {"a" => 1, a: 2}
      {1 => :int, "1" => :str, "1": :sym}
      {1 => :first, 2 => :second}
    OUT
      core/object/slicing_test.rb:11: warning: key :k is duplicated and overwritten on line 11
      core/object/slicing_test.rb:12: warning: key "s" is duplicated and overwritten on line 12
      core/object/slicing_test.rb:13: warning: key 1 is duplicated and overwritten on line 13
      core/object/slicing_test.rb:17: warning: key :dup is duplicated and overwritten on line 19
      core/object/slicing_test.rb:24: warning: key :a is duplicated and overwritten on line 24
      core/object/slicing_test.rb:27: warning: key :x is duplicated and overwritten on line 27
      core/object/slicing_test.rb:28: warning: key :y is duplicated and overwritten on line 28
      core/object/slicing_test.rb:31: warning: key :m is duplicated and overwritten on line 31
      core/object/slicing_test.rb:33: warning: key :b is duplicated and overwritten on line 33
      core/object/slicing_test.rb:36: warning: key :t is duplicated and overwritten on line 36
      core/object/slicing_test.rb:36: warning: key :t is duplicated and overwritten on line 36
    ERR
  end

  it "runtime class with a superclass is a real class" do
    result = ze0(<<~'RUBY')
      # A class built at runtime runs its body as a block, and its directives are
      # rewritten into the self-sends that block serves (`lower::defs::
      # runtime_directive_spelling`). `tests/runtime_class_body_directives.rb` shows
      # that working for `Class.new do ... end`.
      #
      # Giving the class a runtime SUPERCLASS used to break five separate things, in
      # both spellings. None of them was a compile error -- every one lowered, ran,
      # and answered wrongly -- which is why this file exists.
      #
      #   CLASS METHODS were not inherited at all. `class_methods` is a FLAT table,
      #   on the stated ground that compile-time materialization already copies every
      #   inherited `def self.x` onto each subclass. A class born at runtime was never
      #   in that pass, so its table was empty and nothing walked past it:
      #   `Class.new(Base).retired` raised however ordinary `retired` was. Dispatch
      #   now falls back to the ancestor walk, the class-method twin of `lookup_mro`.
      #
      #   PREPEND landed in `ancestors` -- correctly first -- and never took over
      #   dispatch. A module's bodies are in neither the flat table nor `own_impls`:
      #   `emit_user_module_bridges` registers them as VALUE METHODS on the module's
      #   own id, which `super`'s walk probes and `walk_runtime_class` did not. It
      #   reached the module's position, found empty tables, and carried on.
      #
      #   `private :m` NAMING A METHOD THE SAME BODY DEFINES is retagged onto the
      #   `def` at lowering time, so no directive node survives for the rewrite. On
      #   the static path the mark rides the `Scope` into the dispatch row; here the
      #   `def` becomes a runtime definition that carries no visibility, so it has to
      #   be re-spoken as a send. Same for `private_class_method`, on the singleton.
      #
      #   `class << self; undef x; end` tombstoned `x` under the SINGLETON's id, and
      #   nothing on the class-method path looks at a singleton id. The retirement
      #   now lands in the owner's class-method space (`OverlayEntry::class_undefs`).
      #
      #   A CONSTANT resolves its owner from the enclosing cref at compile time, and
      #   a runtime class body is a block whose cref is whatever encloses it --
      #   `Object` at the top level. `OPEN = :visible` wrote `Object::OPEN`. It is
      #   re-pointed at the block's `self`, which is the class being built; a nested
      #   `class Inner` needs the same, and gets it in `runtime_nested_class`.
      #
      #   The READ needs re-pointing too, and this file only checked `Sub::OPEN` from
      #   OUTSIDE at first. A bare constant lowers to a name codegen resolves against
      #   the lexically-enclosing class, so once the write moved to the built class
      #   the two looked in different places: `def reads_open = OPEN` raised
      #   `uninitialized constant`. `rescope_body_constants` moves it, and the two
      #   positions need different scopes -- in the body `self` IS the class, while
      #   in a `def` the class has to be named through the constant holding it,
      #   because that constant is not assigned until the whole body has run.
      #
      # Only the `class` KEYWORD spelling opens a cref. `Class.new do NAME = v end`
      # is a plain block whose cref is the enclosing one, so ruby writes the constant
      # on `Object` there -- checked at the bottom, since re-pointing it would be
      # just as wrong in the other direction.
      #
      # The three compiler panics that led here (danger, gitlab-labkit,
      # activeadmin_settings_cached) are fixed and separate: those reached codegen
      # through directives the rewrite table had no row for at all.

      class Base
        def size = 1
        def self.retired = :retired
      end

      module Front
        def size = "front(#{super})"
      end

      def parent_of(x) = x ? Base : Object

      # --- `Class.new(Super) do ... end` -------------------------------------------
      Made = Class.new(Base) do
        def size = 2
        prepend Front
      end

      p Made.ancestors.first
      p Made.new.size
      p Made.retired

      # --- `class Sub < <expr>` ----------------------------------------------------
      class Sub < parent_of(true)
        OPEN = :visible

        def size = 2
        def wide = :wide
        def self.internal = :internal
        def self.own_retired = :own_retired
        def reads_open = OPEN
        def self.reads_open = OPEN
        def builds_inner = Inner.new.a
        SEEN_IN_BODY = OPEN

        prepend Front
        private :wide
        private_class_method :internal

        class << self
          undef own_retired
        end

        class Inner
          def a = :a
        end
      end

      p Sub.new.size
      p [Sub.new.respond_to?(:wide), Sub.new.respond_to?(:wide, true)]
      p Sub.singleton_class.private_method_defined?(:internal)
      p Sub.respond_to?(:own_retired)
      p Sub::OPEN
      p Sub::Inner.new.a
      p Sub.retired
      p Sub.new.reads_open
      p Sub.reads_open
      p Sub.new.builds_inner
      p Sub::SEEN_IN_BODY
      p Object.const_defined?(:OPEN, false)

      # --- `Class.new do ... end` opens NO cref -------------------------------------
      Blocky = Class.new do
        BLOCK_LEVEL = :block_level
        def reads_it = BLOCK_LEVEL
      end
      p Blocky.new.reads_it
      p Object.const_defined?(:BLOCK_LEVEL, false)
      p Blocky.const_defined?(:BLOCK_LEVEL, false)
    RUBY

    _(result).must_answer <<~'OUT'
      Front
      "front(2)"
      :retired
      "front(2)"
      [false, true]
      true
      false
      :visible
      :a
      :retired
      :visible
      :visible
      :a
      :visible
      false
      :block_level
      true
      false
    OUT
  end

  it "singleton class surrogate is a class" do
    result = ze0(<<~'RUBY')
      # A singleton class IS a Class in ruby. zeo's compile-time `#<Class:self>`
      # surrogate -- the class a `class << self` body's constants, `def`s and
      # residual statements register under -- was filed as a MODULE, because holding
      # constants was all the registry first needed of it. Every question about its
      # own identity then answered the other way, including in user-visible text.
      #
      # Registering it as a class is the whole fix: `superclass: None` puts Object
      # behind it, and nothing in the MRO depended on the module-ness (`class <<
      # self` items dispatch through the singleton tables, not the surrogate's
      # ancestry).
      class K
        class << self
          NEEDS_A_SURROGATE = true
          def a = :a
        end
      end
      p K.singleton_class.class
      p K.singleton_class.is_a?(Class)
      p K.singleton_class.instance_of?(Module)
      p K.singleton_class.is_a?(Module)
      p K.a
      p K.singleton_class.const_get(:NEEDS_A_SURROGATE)
      p K.const_defined?(:NEEDS_A_SURROGATE)

      # It reaches user-visible text: a private class method's NoMethodError names
      # the receiver's kind.
      class Priv
        class << self
          class << self
            private
            def hidden = :hidden
          end
        end
      end
      begin
        Priv.singleton_class.hidden
      rescue NoMethodError => e
        p e.message
      end

      # A body with no constant at all mints the surrogate too, and answers alike.
      class Plain
        class << self
          def b = :b
        end
      end
      p Plain.singleton_class.class
      p Plain.b

      # An ORDINARY module is untouched by the change.
      module Mod; end
      p Mod.class
      p Mod.is_a?(Class)
      p Mod.singleton_class.class
    RUBY

    _(result).must_answer <<~'OUT'
      Class
      true
      false
      true
      :a
      true
      false
      "private method 'hidden' called for class #<Class:Priv>"
      Class
      :b
      Module
      false
      Class
    OUT
  end
end
