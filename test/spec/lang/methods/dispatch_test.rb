# frozen_string_literal: true

require "spec_helper"

describe "Methods: dispatch" do
  it "and nullable container poly" do
    result = ze0(<<~'RUBY')
      # The value form of `a && b` / `a || b` widens both arms to the unified
      # result type. When the left is a nullable container pointer (hash or
      # array) and the result is poly, the kept-left arm must box the temp;
      # it previously emitted the raw pointer, producing a C ternary with
      # mismatched operand types (sp_RbVal vs sp_PolyPolyHash *). A NULL
      # pointer boxes to nil so the widened value stays falsy. Shape from the
      # Doom gem's player_physics.rb: `picked && picked[idx]` where
      # `picked = @item_pickup&.picked_up` is a Hash or nil.

      class Pickup
        attr_reader :picked_up

        def initialize
          @picked_up = {}
        end

        def mark(idx)
          @picked_up[idx] = true
        end
      end

      class Game
        def initialize(pickup)
          @item_pickup = pickup
        end

        def check(idx)
          picked = @item_pickup&.picked_up
          if picked && picked[idx]
            puts "picked #{idx}"
          else
            puts "free #{idx}"
          end
        end

        def value_of(idx)
          picked = @item_pickup&.picked_up
          picked && picked[idx]
        end
      end

      pickup = Pickup.new
      pickup.mark(1)
      Game.new(pickup).check(1)
      Game.new(pickup).check(2)
      Game.new(nil).check(1)
      p Game.new(pickup).value_of(1)
      p Game.new(nil).value_of(1)

      # Same shape over a nullable poly array left.
      class Holder
        attr_reader :items

        def initialize
          @items = []
        end

        def add(v)
          @items << v
        end
      end

      class User
        def initialize(holder)
          @holder = holder
        end

        def peek(idx)
          items = @holder&.items
          v = items && items[idx]
          if v
            puts "got #{v}"
          else
            puts "none"
          end
        end
      end

      h = Holder.new
      h.add("a")
      h.add(7)
      User.new(h).peek(0)
      User.new(h).peek(1)
      User.new(h).peek(5)
      User.new(nil).peek(0)

      # `||` keeps a truthy container left in a poly result.
      class Fallback
        def initialize(holder)
          @holder = holder
        end

        def items_or_flag
          items = @holder&.items
          items || :missing
        end
      end

      p Fallback.new(h).items_or_flag
      p Fallback.new(nil).items_or_flag
    RUBY

    _(result).must_answer <<~'OUT'
      picked 1
      free 2
      free 1
      true
      nil
      got a
      got 7
      none
      none
      ["a", 7]
      :missing
    OUT
  end

  it "builtin class method dispatch" do
    result = ze0(<<~'RUBY')
      # A `def self.x` added to a REOPENED builtin -- or written in a `class << Time`
      # body -- is a class method like any other, so it has to answer a DYNAMIC send
      # too, not only a call zeo resolved statically. It used to answer just the
      # static one: `Time.tag` worked while `Time.__send__(:tag)` and the `self.tag`
      # inside a sibling class method both raised NoMethodError.
      class Time
        def self.tag = "time-tag"
        def self.via_self = self.tag
        def self.via_send = __send__(:tag)
        def self.via_const = Time.tag
        def self.bare = tag
      end

      class String
        class << String
          def label = "string-label"
          def relay = self.label
        end
      end

      p Time.tag
      p Time.via_self
      p Time.via_send
      p Time.via_const
      p Time.bare
      p String.label
      p String.relay

      # Reached through a variable, which is the case codegen cannot resolve at all.
      [Time, String].each { |k| p k.respond_to?(k == Time ? :tag : :label) }
      holder = Time
      p holder.tag
      p holder.public_send(:tag)

      # Reflection agrees: the method sits on the singleton class.
      # (`Time.method(:tag).owner` is left out -- zeo answers the class where ruby
      # answers its singleton class, for a USER class equally, so it is a separate
      # divergence rather than anything this file is about.)
      p Time.singleton_methods.include?(:tag)
      p String.singleton_methods.include?(:label)
      p Time.singleton_class.instance_methods(false).include?(:tag)
      p Time.method(:tag).arity
      p Time.respond_to?(:tag)
      p Time.respond_to?(:no_such_tag)

      # An argument-taking one, and a block-taking one, both through the dynamic path.
      class Array
        def self.doubled(n) = n * 2
        def self.wrap = yield 3
      end
      p Array.__send__(:doubled, 21)
      p Array.__send__(:wrap) { |v| v + 1 }
      p Array.method(:doubled).arity

      # A module reopen takes the same path.
      module Comparable
        def self.mark = :marked
      end
      p Comparable.__send__(:mark)
      p Comparable.singleton_methods.include?(:mark)

      # The builtin's OWN class methods still answer, and a user row beats nothing it
      # should not: `Time.now` is untestable but `Integer.sqrt` is exact.
      p Integer.__send__(:sqrt, 17)
    RUBY

    _(result).must_answer <<~'OUT'
      "time-tag"
      "time-tag"
      "time-tag"
      "time-tag"
      "time-tag"
      "string-label"
      "string-label"
      true
      true
      "time-tag"
      "time-tag"
      true
      true
      true
      0
      true
      false
      42
      4
      1
      :marked
      true
      4
    OUT
  end

  it "call op write poly recv" do
    result = ze0(<<~'RUBY')
      # `recv.attr op= value` where the receiver is only known as a poly value
      # (doom: `sector.ceiling_height -= speed` on a sector pulled out of a hash).
      class Sector
        attr_accessor :height, :count, :name, :flags
        def initialize(height, count, name, flags)
          @height = height
          @count = count
          @name = name
          @flags = flags
        end
      end

      # widen: routing the instance through a hash value leaves the local poly-typed
      def pick(h)
        h[:sector]
      end

      # mixed int/float heights and int/nil flags widen those ivars themselves,
      # doom-style
      h = { sector: Sector.new(64.0, 3, "lift", 1), other: Sector.new(8, 1, "door", nil) }
      obj = pick(h)

      obj.height -= 1.5
      puts obj.height
      obj.count += 2
      puts obj.count
      obj.height *= 2
      puts obj.height
      obj.count *= 5
      puts obj.count
      obj.height /= 4.0
      puts obj.height
      obj.count -= 1
      puts obj.count
      obj.name += "!"
      puts obj.name
      # bitwise op on a widened (boxed) slot
      obj.flags |= 6
      puts obj.flags
      # string += with a poly rhs (mixed-value hash lookup)
      mix = { s: "?", n: 1 }
      obj.name += mix[:s]
      puts obj.name
      puts h[:sector].height
      puts h[:sector].count
      puts h[:sector].name
      puts h[:sector].flags
    RUBY

    _(result).must_answer <<~'OUT'
      62.5
      5
      125.0
      25
      31.25
      24
      lift!
      7
      lift!?
      31.25
      24
      lift!?
      7
    OUT
  end

  it "dispatch unused param nil" do
    result = ze0(<<~'RUBY')
      # Virtual dispatch on a poly receiver into a method whose parameter is unused
      # (so its type never resolves) and is passed nil. The unused param is poly in
      # the callee signature; the dispatch arg temp must be a boxed poly, not a `void`
      # temp. Regression: `void _t = 0;` -> C compile error.
      class Base
        def hook(a, b)
          "base:#{a}"
        end
      end
      class Child < Base
        def hook(a, b)
          "child:#{a}"
        end
      end
      def run(x)
        x.hook("p", nil)
      end
      [Base.new, Child.new].each { |it| puts run(it) }

      # also exercise a second unused poly param fed a poly value
      class Sink
        def take(x, y, z)
          "#{x}"
        end
      end
      class Sink2 < Sink
        def take(x, y, z)
          "2:#{x}"
        end
      end
      vals = ["a", 1]              # poly elements
      def drive(s, v)
        s.take("hi", v, nil)
      end
      [Sink.new, Sink2.new].each { |s| puts drive(s, vals[0]) }

      # self-dispatch: a method forwards to a self method that subclasses override,
      # with an unused nil-fed param (the tep proxy hook shape). Exercises the
      # object/self-receiver dispatch path (vs the poly-receiver one above).
      class Proxy
        def forward
          before_forward("req", nil)
        end
        def before_forward(a, b)
          "base:#{a}"
        end
      end
      class GuardProxy < Proxy
        def before_forward(a, b)
          "guard:#{a}"
        end
      end
      [Proxy.new, GuardProxy.new].each { |p| puts p.forward }
    RUBY

    _(result).must_answer <<~'OUT'
      base:p
      child:p
      hi
      2:hi
      base:req
      guard:req
    OUT
  end

  it "kwargs collapse poly receiver" do
    result = ze0(<<~'RUBY')
      # A braceless keyword-argument call collapses into the callee's first unfilled
      # POSITIONAL parameter when no declared keyword parameter takes a key. Reached
      # through a POLY receiver the arms matched keywords by name only, so an
      # optional positional silently kept its default -- no TypeError, no
      # ArgumentError, no diagnostic -- and a required one made every arm look like
      # an arity mismatch, dropping the whole switch (#4030):
      #
      #   undefined method 'where' for an instance of R (NoMethodError)
      #
      # The shape is ActiveRecord::Relation#where reached off a union-returning
      # #select, which is where it was reported.
      #
      # Two more, found while fixing it: a callee with BOTH an optional positional
      # and a rest gave the hash to both, and a callee with two optional positionals
      # gave it to both of those.
      class R
        def initialize
          @log = []
        end
        # union return -> a poly receiver for the next call in the chain
        def select(*specs)
          return [1, 2] if specs.empty?
          self
        end
        def where(condition = nil, *args)
          @log << [condition.class.to_s, args.size]
          self
        end
        def req(condition)
          @log << ["req", condition.class.to_s]
          self
        end
        def opt_only(condition = nil)
          @log << ["opt", condition.class.to_s]
          self
        end
        def kw(a: 0, b: 1)
          @log << ["kw", a, b]
          self
        end
        def mixed(first, opts = nil)
          @log << ["mixed", first.to_s, opts.class.to_s]
          self
        end
        def kwrest(**kw)
          @log << ["kwrest", kw.size]
          self
        end
        def rest_only(*args)
          @log << ["rest", args.size, args.last.class.to_s]
          self
        end
        def two_opt(a = nil, b = nil)
          @log << ["two_opt", a.class.to_s, b.class.to_s]
          self
        end
        def report
          p @log
        end
      end

      def poly = R.new.select(:id)

      poly.where(merged_story_id: 1).report
      poly.where({ merged_story_id: 1 }).report
      poly.where("literal").report
      poly.where.report
      poly.req(k: 1).report
      poly.opt_only(k: 1).report
      poly.kw(a: 9).report
      poly.mixed("x", k: 1).report
      poly.kwrest(k: 1, j: 2).report
      poly.rest_only(k: 1).report
      poly.rest_only("a", k: 1).report
      poly.two_opt(k: 1).report

      # and the same shapes on a statically-known receiver
      R.new.where(merged_story_id: 1).report
      R.new.req(k: 1).report
      R.new.rest_only(k: 1).report
      R.new.two_opt(k: 1).report
      R.new.mixed("x", k: 1).report

      # a free function, the third path
      def fn(condition = nil, *args)
        p [condition.class.to_s, args.size]
      end
      fn(k: 1)
      fn("s", k: 1)
      def fn2(a = nil, b = nil) = p [a.class.to_s, b.class.to_s]
      fn2(k: 1)
    RUBY

    _(result).must_answer <<~'OUT'
      [["Hash", 0]]
      [["Hash", 0]]
      [["String", 0]]
      [["NilClass", 0]]
      [["req", "Hash"]]
      [["opt", "Hash"]]
      [["kw", 9, 1]]
      [["mixed", "x", "Hash"]]
      [["kwrest", 2]]
      [["rest", 1, "Hash"]]
      [["rest", 2, "Hash"]]
      [["two_opt", "Hash", "NilClass"]]
      [["Hash", 0]]
      [["req", "Hash"]]
      [["rest", 1, "Hash"]]
      [["two_opt", "Hash", "NilClass"]]
      [["mixed", "x", "Hash"]]
      ["Hash", 0]
      ["String", 1]
      ["Hash", "NilClass"]
    OUT
  end

  it "kwargs instance dispatch" do
    result = ze0(<<~'RUBY')
      # Keyword args through the instance-method dispatch path: a `**kwrest` callee
      # collects literal keywords and merged `**hash` forwards; a named keyword
      # param extracts from a forwarded `**hash` (absent key -> default); a
      # positional param whose NAME matches a forwarded key still takes the
      # provided positional (it never steals the key). Same rules emit_args_filled
      # applies to free-function calls.
      class Sink
        def note_mutation(op, node, **info)
          puts "#{op}:#{node}:#{info[:parent]}:#{info[:index]}:#{info[:key]}"
        end

        def named(op, parent: "none", index: 0)
          puts "named #{op}:#{parent}:#{index}"
        end

        def note(op, node, **info)
          note_mutation(op, node, **info)
        end

        def relay(op, **info)
          named(op, **info)
        end
      end

      s = Sink.new
      s.note_mutation(:ext, "n0", key: "href")
      s.note(:fwd, "n1", parent: "P", index: 3)
      s.note(:bare, "n2")
      s.relay(:r1, parent: "Q")
      s.relay(:r2)

      # a positional param named like a forwarded key takes the positional
      class Pos
        def take(parent, **info)
          puts "pos #{parent}:#{info[:parent]}"
        end
        def go(**info) = take("given", **info)
      end
      Pos.new.go(parent: "fromkw")
    RUBY

    _(result).must_answer <<~'OUT'
      ext:n0:::href
      fwd:n1:P:3:
      bare:n2:::
      named r1:Q:0
      named r2:none:0
      pos given:fromkw
    OUT
  end

  it "method added dispatch watermark" do
    result = ze0(<<~'RUBY')
      # A definition hook sees the class only as far as it has been built. The
      # REFLECTION half of that is `tests/method_added_watermark.rb`; this is the
      # DISPATCH half -- calling a method written below the `def` the hook is
      # reporting must miss, exactly as if it were not there yet.
      #
      # The two are different machines. Reflection asks `not_yet_defined` on its way
      # to an answer it was already computing. Dispatch resolves through an inline
      # cache and the flattened method tables, so the same question has to be asked
      # ahead of the cache -- one relaxed atomic load, and the whole call takes the
      # slow route only while a hook is actually running.

      class Base
        def shared = "from Base"
      end

      class Probe < Base
        def self.method_added(name)
          return unless name == :first
          [-> { new.later },
           -> { new.send(:later) },
           -> { new.public_send(:later) },
           -> { instance_method(:later) },
           -> { new.method(:later) },
           -> { new.respond_to?(:later) },
           -> { method_defined?(:later) },
           -> { instance_methods(false).sort },
           # An INHERITED name is untouched: ruby hides only what exists nowhere
           # yet, so `Base#shared` still answers though `Probe#shared` is below.
           -> { new.shared },
           # ...and so does anything the class never redefines at all.
           -> { new.to_s.class }].each do |f|
            begin
              puts "  ok: #{f.call.inspect}"
            rescue => e
              puts "  #{e.class}: #{e.message}"
            end
          end
        end

        def first = 1
        def later = 2
        def shared = "from Probe"
      end

      puts "== and every one of them answers once the class is whole"
      p [Probe.new.later, Probe.new.shared, Probe.instance_methods(false).sort]

      puts "== method_missing still gets its chance"
      class WithMM
        def self.method_added(name)
          return unless name == :one
          puts "  #{new.two}"
        end

        def method_missing(name, *args) = "method_missing(#{name})"
        def respond_to_missing?(name, priv = false) = true

        def one = 1
        def two = 2
      end
      p WithMM.new.two

      puts "== the truncation lifts as soon as the hook returns"
      class Sequential
        def self.method_added(name)
          puts "  added #{name}, b reachable: #{new.respond_to?(:b)}"
        end

        def a = 1
        def b = 2
      end
      p [Sequential.new.a, Sequential.new.b]

      puts "== an unrelated class is never truncated"
      class Other
        def wide = "other"
      end

      class Narrow
        def self.method_added(name)
          return unless name == :x
          puts "  Other#wide -> #{Other.new.wide}"
        end

        def x = 1
        def wide = "narrow"
      end
      p [Narrow.new.wide, Other.new.wide]
    RUBY

    _(result).must_answer "  NoMethodError: undefined method 'later' for an instance of Probe\n  NoMethodError: undefined method 'later' for an instance of Probe\n  NoMethodError: undefined method 'later' for an instance of Probe\n  NameError: undefined method 'later' for class 'Probe'\n  NameError: undefined method 'later' for class 'Probe'\n  ok: false\n  ok: false\n  ok: [:first]\n  ok: \"from Base\"\n  ok: String\n== and every one of them answers once the class is whole\n[2, \"from Probe\", [:first, :later, :shared]]\n== method_missing still gets its chance\n  method_missing(two)\n2\n== the truncation lifts as soon as the hook returns\n  added a, b reachable: false\n  added b, b reachable: true\n[1, 2]\n== an unrelated class is never truncated\n  Other#wide -> other\n[\"narrow\", \"other\"]\n"
  end

  it "nil default param widens to poly" do
    result = ze0(<<~'RUBY')
      # `def f(x = nil)` should keep nil observable at the no-arg call
      # site, even when other call sites supply a non-nullable scalar
      # (symbol / int / float / bool). Pre-fix the per-call-site
      # unifier picked the typed `at` over the `nil` default, so the
      # param's C storage was the scalar type and `f()` defaulted the
      # missing arg to that scalar's zero value (`sp_sym 0`, `mrb_int
      # 0`, etc.) — the user's `x.nil?` branch became dead code.
      # Issue #634 shape A.

      def f(x = nil)
        if x.nil?
          "branch: nil"
        else
          "branch: not-nil (#{x.to_s})"
        end
      end

      puts f()
      puts f(:foo)

      def g(n = nil)
        n.nil? ? "no-int" : "int=#{n.to_s}"
      end

      puts g()
      puts g(42)
    RUBY

    _(result).must_answer <<~'OUT'
      branch: nil
      branch: not-nil (foo)
      no-int
      int=42
    OUT
  end

  it "operators on dynamic operands fall through to dispatch" do
    result = ze0(<<~'RUBY')
      # The old "isn't supported yet for non-Int/Float operands" panic is now
      # dynamic dispatch: String#+ via send_value's table, and a user class's
      # own operator method chained through a Poly intermediate (`a << 1`
      # returns self as Poly; the second `<<` dispatches dynamically).

      module Cat
        def self.concat2(a, b)
          a + b
        end
      end
      puts Cat.concat2("foo", "bar")
      class Acc
        def initialize
          @items = []
        end
        def <<(item)
          @items << item
          self
        end
        def size
          @items.length
        end
      end
      a = Acc.new
      a << 1 << 2 << 3
      puts a.size
    RUBY

    _(result).must_answer <<~'OUT'
      foobar
      3
    OUT
  end

  it "poly dispatch builtin" do
    result = ze0(<<~'RUBY')
      # Polymorphic dispatch over a parameter typed `poly` should pick the
      # right `[]` based on the runtime type — a user class's `def [](x)`
      # for Foo.new, sp_IntArray_get for an Array literal.

      class Foo
        def [](x)
          42
        end
      end

      def read0(a)
        a[0]
      end

      puts read0(Foo.new)
      puts read0([100, 200, 300])
    RUBY

    _(result).must_answer <<~'OUT'
      42
      100
    OUT
  end

  it "poly dispatch builtin all" do
    result = ze0(<<~'RUBY')
      # Issue #78: poly dispatch and runtime helpers reaching all built-in
      # array types (not just IntArray). When a `poly` slot can hold any of
      # Int/Float/Str/Sym arrays plus user-class instances, dispatch on
      # `length` / `size` must pick the right helper per cls_id; `puts` /
      # `to_s` over a poly value must inspect the array, not print a raw
      # pointer.

      # A `length` poly dispatch — every built-in array type contributes a
      # branch returning mrb_int.
      def lenof(a)
        a.length
      end

      class Box
        def length; 99; end
      end

      puts lenof([1, 2, 3])         # 3   (IntArray)
      puts lenof([1.0, 2.0, 3.0])   # 3   (FloatArray)
      puts lenof(["a", "b", "c"])   # 3   (StrArray)
      puts lenof([:x, :y])          # 2   (SymArray)
      puts lenof(Box.new)           # 99  (user-class branch)

      # sp_poly_puts / sp_poly_to_s handle every built-in array tag: a poly
      # value carrying e.g. a FloatArray now prints via sp_FloatArray_inspect
      # instead of the raw-pointer fallback. The reach of the param-widening
      # inference (calling `show` with several built-in array types in turn)
      # is a separate concern; this test only verifies that the runtime
      # helpers route correctly when the poly already holds an array.
      mixed = [1, 2.0, "x"]   # forces poly_array; each element via sp_poly_puts
      mixed.each { |e| p e }
      # 1
      # 2.0
      # "x"
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      3
      2
      99
      1
      2.0
      "x"
    OUT
  end

  it "poly dispatch builtin container arm" do
    result = ze0(<<~'RUBY')
      # A call polymorphic over a builtin container and a user class that shadows the
      # same method name lost the builtin arm. The non-yielding reads (first, last,
      # keys, values) were pinned to the user class's return type and left every
      # builtin tag on the dispatch's raise default, so a genuine Array or Hash
      # raised NoMethodError. The yielding ones (map, select) did run the block, but
      # the block was never classified as lifted, so its writes to enclosing locals
      # went to a copy and were lost. #3459, following #3409.
      class Shadow
        def first; nil; end
        def last; nil; end
        def keys; nil; end
        def values; nil; end
        def map; nil; end
        def select; nil; end
        def size; nil; end
        def length; nil; end
        def each; nil; end
      end
      class Src
        def self.hash_of(w)
          if w
            h = {}
            h["a"] = 1
            h
          else
            Shadow.new
          end
        end
        def self.arr(w)
          w ? [3, 1, 2] : Shadow.new
        end
      end
      a = Src.arr(true)
      h = Src.hash_of(true)
      p a.first
      p a.last
      p h.keys
      p h.values
      n = 0
      a.map { |x| n = n + 1 }
      p n
      m = 0
      a.select { |x| m = m + 1; x > 1 }
      p m
      p a.size
      p a.length
      p h.size
      e = 0
      a.each { |x| e = e + 1 }
      p e
      p a.map { |x| x * 2 }
      p a.select { |x| x > 1 }
      s = Src.arr(false)
      p s.first
      p s.map

      # The reads the general mechanism reaches once a user class owns the name:
      # analyze widens the union to poly and the dispatch's builtin arm re-enters the
      # ordinary emission, so the builtin receiver answers exactly as it would with
      # no user class in the program.
      class Shadow2
        def min; :S; end
        def max; :S; end
        def sum; :S; end
        def sort; :S; end
        def reverse; :S; end
        def index(x); :S; end
      end
      class Src2
        def self.arr(w) = w ? [3, 1, 2] : Shadow2.new
      end
      b = Src2.arr(true)
      p b.min
      p b.max
      p b.sum
      p b.sort
      p b.reverse
      p b.index(1)
      p Src2.arr(false).min
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      ["a"]
      [1]
      3
      3
      3
      3
      1
      3
      [6, 2, 4]
      [3, 2]
      nil
      nil
      1
      3
      6
      [1, 2, 3]
      [2, 1, 3]
      1
      :S
    OUT
  end

  it "poly dispatch builtin enum arm" do
    result = ze0(<<~'RUBY')
      # A builtin Array receiver at a dispatch that exists only because a user class
      # defines the same name.
      #
      # A block-carrying call on a builtin is normally served by splicing the block
      # inline. That is not available once a user candidate takes the block as a real
      # proc: the proc is materialized once and shared by every arm, and a second
      # spliced copy would disagree with whichever arm ran. So the builtin had no arm
      # at all and fell through to the raise -- NoMethodError on an Array, at a site
      # where the call is plainly Array#map.
      #
      # The mirror of it is just as wrong and silent: the element-loop emitters walk
      # a poly receiver as a container without asking whether a user class owns the
      # name, so the user object iterated as an empty array and the call answered
      # nothing. Only the cls_id dispatch can serve both, so those emitters decline
      # to it and it grew a builtin arm that drives the same materialized proc.
      #
      # Reachable at all only since a yielding method became dispatchable.

      class Rel
        def map
          out = []
          [1, 2].each { |x| out << yield(x) }
          out
        end

        def select
          out = []
          [1, 2, 3].each { |x| out << x if yield(x) }
          out
        end

        def reject
          out = []
          [1, 2, 3].each { |x| out << x unless yield(x) }
          out
        end

        def group_by
          h = {}
          [1, 2, 3, 4].each do |x|
            k = yield(x)
            h[k] = [] unless h.key?(k)
            h[k] << x
          end
          h
        end

        def each
          yield 7
          yield 8
          self
        end

        def find
          yield 1
          :rel_find
        end

        def find_index
          yield 1
          -7
        end

        def min_by
          yield 1
          :rel_min
        end

        def max_by
          yield 1
          :rel_max
        end

        def partition
          yield 1
          [[:a], [:b]]
        end

        def sum
          yield 1
          -8
        end

        def any?
          yield 1
          false
        end

        def all?
          yield 1
          false
        end

        def none?
          yield 1
          false
        end

        def take_while
          yield 1
          [:tw]
        end

        def drop_while
          yield 1
          [:dw]
        end

        def flat_map
          yield 1
          [:fm]
        end

        def each_with_index
          yield 1
          [:ewi]
        end

        # a non-yielding, blockless method of an Enumerable name: the dispatch still
        # exists, and the builtin arm has to materialize the block itself because no
        # candidate asked for one
        def sort_by
          [9]
        end

        def count
          -1
        end
      end

      def pick(n)
        n == 1 ? Rel.new : [3, 4, 5, 6]
      end

      p pick(1).map { |x| x * 2 }
      p pick(2).map { |x| x * 2 }

      p pick(1).select { |x| x > 1 }
      p pick(2).select { |x| x > 4 }

      p pick(1).reject { |x| x > 1 }
      p pick(2).reject { |x| x > 4 }

      p pick(1).group_by { |x| x % 2 }
      p pick(2).group_by { |x| x % 2 }

      seen = []
      pick(1).each { |x| seen << x }
      pick(2).each { |x| seen << x }
      p seen

      # Array#each answers the receiver
      p pick(2).each { |x| x }

      p pick(1).find { |x| x > 0 }
      p pick(2).find { |x| x > 4 }
      p pick(1).find_index { |x| x > 0 }
      p pick(2).find_index { |x| x > 4 }
      p pick(1).min_by { |x| -x }
      p pick(2).min_by { |x| -x }
      p pick(1).max_by { |x| -x }
      p pick(2).max_by { |x| -x }
      p pick(1).partition { |x| x.odd? }
      p pick(2).partition { |x| x.odd? }
      p pick(1).sum { |x| x }
      p pick(2).sum { |x| x * 10 }
      p pick(1).any? { |x| x > 0 }
      p pick(2).any? { |x| x > 5 }
      p pick(2).all? { |x| x > 5 }
      p pick(2).none? { |x| x > 9 }
      p pick(1).take_while { |x| true }
      p pick(2).take_while { |x| x < 5 }
      p pick(2).drop_while { |x| x < 5 }
      p pick(1).flat_map { |x| [x] }
      p pick(2).flat_map { |x| [x, x] }
      p pick(1).each_with_index { |x, i| x }
      p pick(2).each_with_index { |x, i| x }

      # no candidate asked for the block, so the builtin arm materializes it
      p pick(1).sort_by { |x| -x }
      p pick(2).sort_by { |x| -x }
      p pick(1).count { |x| x.even? }
      p pick(2).count { |x| x.even? }

      # a captured local through the builtin arm: the proc is the one the user arm
      # would have taken, so its capture cell has to work here too
      base = 100
      p pick(2).map { |x| base + x }

      # strings, so the element rides the pointer channel
      def pick_s(n)
        n == 1 ? Rel.new : ["a", "bb", "ccc"]
      end

      p pick_s(2).map { |s| s.length }
      p pick_s(2).sort_by { |s| -s.length }
      p pick_s(2).group_by { |s| s.length.odd? }

      # a Hash receiver: entries arrive as [k, v] pairs, and a two-parameter block
      # autosplats them the way a spliced loop would
      def pick_h(n)
        n == 1 ? Rel.new : { "a" => 1, "b" => 2 }
      end

      p pick_h(2).map { |k, v| "#{k}#{v}" }
      p pick_h(2).select { |k, v| v > 1 }
      acc = []
      pick_h(2).each { |k, v| acc << k }
      p acc
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4]
      [6, 8, 10, 12]
      [2, 3]
      [5, 6]
      [1]
      [3, 4]
      {1 => [1, 3], 0 => [2, 4]}
      {1 => [3, 5], 0 => [4, 6]}
      [7, 8, 3, 4, 5, 6]
      [3, 4, 5, 6]
      :rel_find
      5
      -7
      2
      :rel_min
      6
      :rel_max
      3
      [[:a], [:b]]
      [[3, 5], [4, 6]]
      -8
      180
      false
      true
      false
      true
      [:tw]
      [3, 4]
      [5, 6]
      [:fm]
      [3, 3, 4, 4, 5, 5, 6, 6]
      [:ewi]
      [3, 4, 5, 6]
      [9]
      [6, 5, 4, 3]
      -1
      2
      [103, 104, 105, 106]
      [1, 2, 3]
      ["ccc", "bb", "a"]
      {true => ["a", "ccc"], false => ["bb"]}
      ["a1", "b2"]
      {"b" => 2}
      ["a", "b"]
    OUT
  end

  it "poly dispatch inherited method" do
    result = ze0(<<~'RUBY')
      # Parent defines a method, child inherits it.
      # Calling the method via a poly-typed parameter must dispatch
      # to the parent's method body for both parent and child instances.

      class A
        def x
          "from-x"
        end
      end

      class B < A
      end

      def call_x(e)
        e.x
      end

      puts call_x(A.new)
      puts call_x(B.new)
    RUBY

    _(result).must_answer <<~'OUT'
      from-x
      from-x
    OUT
  end

  it "poly dispatch keyword args" do
    result = ze0(<<~'RUBY')
      # Keyword arguments through a poly-receiver method dispatch bind by name,
      # not position (#3268): the trailing keyword hash used to flow into the
      # *rest / first keyword slot, garbling both.
      class Config
        attr_reader :log
        def initialize = @log = []
        def str(*opts, default: nil, required: false) = log << [:str, opts, default, required]
        def num(x, scale: 2) = log << [:num, x, scale]
        def any(**kw) = log << [:any, kw]
        def mix(a, *rest, flag: false, **extra) = log << [:mix, a, rest, flag, extra]
      end

      def run(&) = Config.new.tap { |c| yield c }.log

      p run { _1.str "--a", "--b", default: "x", required: true }
      p run { _1.str "--c" }
      p run { _1.num 7 }
      p run { _1.num 7, scale: 5 }
      p run { _1.any a: 1, b: "two" }
      p run { _1.mix 1, 2, 3, flag: true, other: "x" }
    RUBY

    _(result).must_answer <<~'OUT'
      [[:str, ["--a", "--b"], "x", true]]
      [[:str, ["--c"], nil, false]]
      [[:num, 7, 2]]
      [[:num, 7, 5]]
      [[:any, {a: 1, b: "two"}]]
      [[:mix, 1, [2, 3], true, {other: "x"}]]
    OUT
  end

  it "poly dispatch reader unbox" do
    result = ze0(<<~'RUBY')
      # A length-like poly method dispatch fixes its result slot to mrb_int, but an
      # attr-reader arm can name a poly-typed ivar (a struct member fed from a poly
      # source): the read must unbox into the scalar slot, mirroring the method-arm
      # coercion (doom: `@file.read(entry.size)` on a WAD directory entry whose
      # fields come from String#unpack1).
      E = Struct.new(:offset, :size, :name)

      class Box
        def initialize(n)
          @n = n
        end

        def bump!
          @n += 1
        end

        def size
          @n
        end
      end

      def lookup(arr, n)
        arr.find { |e| e.name == n }
      end

      meta = [4, "x"]
      arr = [E.new(0, meta[0], "A"), "sentinel"]
      entry = lookup(arr, "A")
      if entry
        n = entry.size
        p n + 1
      end

      b = Box.new(3)
      b.bump!
      p b.size
    RUBY

    _(result).must_answer <<~'OUT'
      5
      4
    OUT
  end

  it "poly dispatch splat args" do
    result = ze0(<<~'RUBY')
      # A *rest splat method reached through the poly cls_id dispatch (a receiver
      # that may be one of several user classes) must collect the trailing
      # call-site arguments into an Array, exactly like a concrete-receiver call.
      # Regression: the poly-dispatch arm passed the raw scalar temp straight into
      # the sp_PolyArray* slot, a C type error (issue #2457).
      class Rel
        def where(q, *args)
          "Rel[#{q}](#{args.inspect})"
        end
      end
      class Scope
        def where(q, *args)
          "Scope[#{q}](#{args.inspect})"
        end
      end

      [Rel.new, Scope.new].each do |o|
        puts o.where("id != ?")
        puts o.where("id != ?", 5)
        puts o.where("a = ? AND b = ?", 1, "two")
        puts o.where("mixed", :sym, 3.5, nil)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Rel[id != ?]([])
      Rel[id != ?]([5])
      Rel[a = ? AND b = ?]([1, "two"])
      Rel[mixed]([:sym, 3.5, nil])
      Scope[id != ?]([])
      Scope[id != ?]([5])
      Scope[a = ? AND b = ?]([1, "two"])
      Scope[mixed]([:sym, 3.5, nil])
    OUT
  end

  it "poly dispatch uninstantiated arm" do
    result = ze0(<<~'RUBY')
      # The poly-dispatch switch drops the `case` arm of a class that is never
      # instantiated (no value can carry its cls_id). The critical case: a base class
      # that is itself never `.new`'d but whose method is inherited by an instantiated
      # subclass must keep that method -- it is referenced through the subclass's arm,
      # even though the base's own arm is dropped. Also exercises a same-named method
      # on a genuinely-unused class (its arm and method both go away).
      class Base
        def kind; "base"; end
      end
      class Sub < Base            # instantiated; inherits Base#kind
      end
      class Unused                # never instantiated; same method name
        def kind; "unused"; end
      end

      items = [Sub.new, Sub.new]  # poly elements; only Sub is instantiated
      items.each do |x|
        puts x.kind               # poly dispatch -> Sub arm -> inherited Base#kind
      end

      # A directly-instantiated class with an overriding method, alongside the base.
      class Animal
        def speak; "..."; end
      end
      class Dog < Animal
        def speak; "woof"; end
      end
      zoo = [Dog.new, Animal.new]  # both instantiated here
      zoo.each { |a| puts a.speak }
    RUBY

    _(result).must_answer <<~'OUT'
      base
      base
      woof
      ...
    OUT
  end

  it "poly dispatch user return widens" do
    result = ze0(<<~'RUBY')
      # A poly receiver's dispatch emits the user class's arm AND the builtin arms
      # into ONE C temp, so the call's type has to be one both can hold. Some arms
      # asked that question and the rest did not, which is why the answer depended on
      # which name you picked: `Chain#join` answering a Chain came back through the
      # builtin's `const char *` as `.v.s` and printed "", `def to_i = "seven"` did
      # not compile, and `def empty? = 0` came back as false -- 0 is truthy in Ruby.
      #
      # The question is now asked from both sides: on the way out of the poly section
      # (does a user return disagree with the type this arm chose) and at the user
      # dispatch (does the builtin surface disagree with what the user arms agreed
      # on). This program walks the names the report enumerated, so a new arm that
      # pins a concrete type has to survive them.

      class B_join
        def join(*p) = "seven"
      end

      def p_join(v)
        v.join("b")
      end

      p p_join(B_join.new)
      p p_join(["x", "y"])

      class B_to_i
        def to_i = "seven"
      end

      def p_to_i(v)
        v.to_i
      end

      p p_to_i(B_to_i.new)
      p p_to_i("12")

      class B_to_f
        def to_f = 7
      end

      def p_to_f(v)
        v.to_f
      end

      p p_to_f(B_to_f.new)
      p p_to_f("1.5")

      class B_empty
        def empty? = 0
      end

      def p_empty(v)
        v.empty?
      end

      p p_empty(B_empty.new)
      p p_empty([])

      class B_index
        def index(x) = "seven"
      end

      def p_index(v)
        v.index("a")
      end

      p p_index(B_index.new)
      p p_index(["a", "b"])

      class B_rindex
        def rindex(x) = "seven"
      end

      def p_rindex(v)
        v.rindex("a")
      end

      p p_rindex(B_rindex.new)
      p p_rindex(["a", "b"])

      class B_findindex
        def find_index(x) = "seven"
      end

      def p_findindex(v)
        v.find_index("a")
      end

      p p_findindex(B_findindex.new)
      p p_findindex(["a", "b"])

      class B_pack
        def pack(x) = "seven"
      end

      def p_pack(v)
        v.pack("C*")
      end

      p p_pack(B_pack.new)
      p p_pack([65, 66])

      class B_size
        def size = "seven"
      end

      def p_size(v)
        v.size
      end

      p p_size(B_size.new)
      p p_size([1, 2])

      class B_length
        def length = "seven"
      end

      def p_length(v)
        v.length
      end

      p p_length(B_length.new)
      p p_length([1, 2])

      class B_includep
        def include?(x) = 0
      end

      def p_includep(v)
        v.include?(1)
      end

      p p_includep(B_includep.new)
      p p_includep([1])

      class B_memberp
        def member?(x) = 0
      end

      def p_memberp(v)
        v.member?(1)
      end

      p p_memberp(B_memberp.new)
      p p_memberp([1])

      # the reproduction: a method that answers an object of its own class, reached
      # through a widened receiver, with the receiver's own arm running (@asked is 1)
      class Chain
        def initialize(text)
          @text = text
          @asked = 0
        end

        attr_reader :asked

        def to_s = @text

        def join(*parts)
          @asked += 1
          parts.reduce(self) { |acc, part| Chain.new("#{acc}/#{part}") }
        end
      end

      def joined(value)
        value.join("b")
      end

      chain = Chain.new("/tmp")
      p "#{joined(chain)}"
      p chain.asked
      p joined(["x", "y"])

      # a user arm that AGREES keeps the concrete type: this is what must not widen,
      # or every poly.size boxes a count the whole program reads as a number
      class Counted
        def size = 3
        def length = 4
      end

      def sized(v) = v.size
      def lengthed(v) = v.length
      p sized(Counted.new)
      p sized([1, 2])
      p lengthed(Counted.new)
      p lengthed("abcde")
    RUBY

    _(result).must_answer <<~'OUT'
      "seven"
      "xby"
      "seven"
      12
      7
      1.5
      0
      true
      "seven"
      0
      "seven"
      0
      "seven"
      0
      "seven"
      "AB"
      "seven"
      2
      "seven"
      2
      0
      true
      0
      true
      "/tmp/b"
      1
      "xby"
      3
      2
      4
      5
    OUT
  end

  it "poly dispatch yield method" do
    result = ze0(<<~'RUBY')
      # A yielding method reached through a poly receiver.
      #
      # Blocks are fused, not passed: with a known receiver the method body is
      # inlined at the call site with the block spliced into the yield. That leaves
      # no symbol to call, so a poly dispatch dropped the arm and raised
      # NoMethodError naming a class that plainly defines the method -- and with it
      # went the whole block API of any class reached through a union.
      #
      # Such a method now also gets a second, ordinary definition taking the block as
      # an sp_Proc *, with `yield` lowered to a call on it. Monomorphic call sites
      # keep the splice; only the poly path pays for the closure.
      #
      # The clone is typed independently of the inlined original: its yield answers
      # poly, so everything the yield feeds widens with it and one body serves every
      # call site. That is what lets a yield nested inside a block work, and what
      # lets two sites pass blocks of differing result type.

      class A
        def go
          yield 5
        end

        def guarded
          block_given? ? yield(1) : 99
        end

        def early
          yield 1
          return 42
        end

        def withargs(a, b)
          yield a + b
        end

        def twice
          yield(1) + yield(2)
        end
      end

      class B
        def go
          0
        end

        def guarded
          -1
        end

        def early
          -3
        end

        def withargs(a, b)
          a - b
        end

        def twice
          -4
        end
      end

      def pick(n)
        n == 1 ? A.new : B.new
      end

      p pick(1).go { |v| v % 2 }
      p pick(2).go { |v| v % 2 }

      p pick(1).guarded { |v| v + 100 }
      p pick(1).guarded
      p pick(2).guarded

      p pick(1).early { |v| v }
      p pick(2).early { |v| v }

      p pick(1).withargs(3, 4) { |s| s * 10 }
      p pick(2).withargs(3, 4) { |s| s * 10 }

      p pick(1).twice { |v| v * 3 }
      p pick(2).twice { |v| v * 3 }

      # a monomorphic call to the same method still fuses
      a = A.new
      p a.go { |v| v + 1 }
      p a.twice { |v| v }

      # a yield nested inside a block of the method's own body: the clone's locals
      # widen with the yield, so `t` is a boxed carrier rather than an mrb_int
      class Looper
        def looped
          t = 0
          3.times { |i| t += yield(i) }
          t
        end
      end

      class NoLoop
        def looped
          -2
        end
      end

      def pick_l(n)
        n == 1 ? Looper.new : NoLoop.new
      end

      p pick_l(1).looped { |i| i * 2 }
      p pick_l(2).looped { |i| i * 2 }

      # two poly call sites whose blocks answer different types: one clone serves
      # both, because its yield is poly and each site unboxes into its own slot
      p pick(1).go { |v| v % 2 }
      p pick(1).go { |v| "s#{v}" }
      p pick(2).go { |v| "s#{v}" }
    RUBY

    _(result).must_answer <<~'OUT'
      1
      0
      101
      99
      -1
      42
      -3
      70
      -1
      9
      -4
      6
      3
      6
      -2
      1
      "s5"
      0
    OUT
  end

  it "poly dispatch yielding method" do
    result = ze0(<<~'RUBY')
      # A polymorphic (untyped) receiver's method dispatch enumerates every user
      # class defining that method name. A class whose definition *yields* is inlined
      # at its call sites and never emitted as a standalone function, so the dispatch
      # must drop its `case` arm instead of calling an absent symbol (which would
      # dangle at link). Here `Cache#fetch` yields and is never the actual receiver;
      # `Flash#fetch` is a plain method. The poly receiver below (read out of an
      # array, so its static type is the top type) reaches a `fetch` dispatch that
      # enumerates both -- only the linkable arm may be emitted.
      class Cache
        def fetch(key, opts = {})
          yield
        end
      end

      class Flash
        def fetch(key, default = nil)
          default
        end
      end

      arr = []
      h = {}
      h["x"] = "1"
      arr << h
      sub = arr[0]
      puts sub.fetch("x", "0").to_s
      puts sub.fetch("absent", "default").to_s
    RUBY

    _(result).must_answer <<~'OUT'
      1
      default
    OUT
  end

  it "poly empty with user method" do
    result = ze0(<<~'RUBY')
      # Defining an instance `empty?` must not drop the builtin String/Array `empty?`
      # from the polymorphic `empty?` dispatch: a poly receiver was lowered to a
      # cls_id switch built only from user `empty?` methods, so a String (or Array)
      # receiver fell through and `empty?` returned false. Sibling of #1437. The
      # dispatch must also carry the builtin tag/cls_id arms.
      class Flasher
        def empty?
          false
        end
      end

      def pick(c)
        c ? "" : "x"
      end
      def pickarr(c)
        c ? [] : [1]
      end

      puts pick(true).empty?     # true
      puts pick(false).empty?    # false
      puts pickarr(true).empty?  # true
      puts pickarr(false).empty? # false
      puts Flasher.new.empty?    # false  (user method still dispatches)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      false
    OUT
  end

  it "poly face nilable param" do
    result = ze0(<<~'RUBY')
      # A parameter that may also receive nil boxes its value, and the boxed face has
      # to answer the names the real class does: Hash#key, the Array#fill mutator, and
      # the two-argument String#index/#rindex all raised NoMethodError (#4149).
      def hash_key(x) = x.key(1)
      def arr_fill(x) = x.fill(9)
      def str_index(x) = x.index("b", 2)
      def str_rindex(x) = x.rindex("b", 3)
      def str_index_miss(x) = x.index("z", 1)

      p hash_key(true ? { "a" => 1 } : nil)

      a = [1, 2, 3, 4]
      p arr_fill(true ? a : nil)
      p a   # fill mutates the receiver, not a copy

      p str_index(true ? "abcabc" : nil)
      p str_rindex(true ? "abcabc" : nil)
      p str_index_miss(true ? "abcabc" : nil)
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      [9, 9, 9, 9]
      [9, 9, 9, 9]
      4
      1
      nil
    OUT
  end

  it "poly method args" do
    result = ze0(<<~'RUBY')
      # Polymorphic method dispatch must pass arguments through to the
      # selected class's method. Before this fix, `compile_poly_method_call`
      # emitted `sp_<Class>_<method>((sp_<Class> *)recv.v.p)` with no
      # argument list — the call-site arguments were dropped on the floor.

      class Doubler
        def call(x)
          x * 2
        end
      end

      class Tripler
        def call(x)
          x * 3
        end
      end

      def apply(a, x)
        a.call(x)
      end

      puts apply(Doubler.new, 5)
      puts apply(Tripler.new, 5)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      15
    OUT
  end

  it "poly method mixed return" do
    result = ze0(<<~'RUBY')
      # Poly dispatch where user classes disagree on the method's return
      # type. `Foo#name` returns int, `Bar#name` returns string. The result
      # of `a.name` is genuinely polymorphic — the dispatcher must use
      # sp_RbVal as the result type and box each branch's return value.

      class Foo
        def name
          42
        end
      end

      class Bar
        def name
          "bar"
        end
      end

      def show(a)
        a.name
      end

      puts show(Foo.new)
      puts show(Bar.new)
    RUBY

    _(result).must_answer <<~'OUT'
      42
      bar
    OUT
  end

  it "poly multi write index target" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      # 
      # A maze grid: every Cell2 holds the neighbours that hold it back.
      # At exit: cycle leak: 16 objects (Array x8, Cell2 x8)
      class Cell1
        attr_accessor :alive, :neighbors
        def initialize; @alive = false; @neighbors = []; end
        def link(c); @neighbors << c; end
        def cnt; @neighbors.count { |n| n.alive }; end
      end
      class Cell2
        attr_accessor :kind, :neighbors, :x, :y
        def initialize(x, y); @x = x; @y = y; @kind = 0; @neighbors = []; end
      end
      class Maze
        attr_accessor :cells
        def initialize(w, h)
          @w = w; @h = h
          @cells = Array.new(@h) { |y| Array.new(@w) { |x| Cell2.new(x, y) } }
          update_neighbors
        end
        def update_neighbors
          @cells.each_with_index do |row, y|
            row.each_with_index do |cell, x|
              if x > 0 && y > 0 && x < @w - 1 && y < @h - 1
                cell.neighbors << @cells[y - 1][x]
                cell.neighbors << @cells[y + 1][x]
                4.times do
                  i = 0
                  j = 1
                  cell.neighbors[i], cell.neighbors[j] = cell.neighbors[j], cell.neighbors[i]
                end
              end
            end
          end
        end
      end
      m = Maze.new(4, 4)
      p m.cells[1][1].neighbors.length
      a = Cell1.new
      a.link(Cell1.new)
      p a.cnt
    RUBY

    _(result).must_answer <<~'OUT'
      2
      0
    OUT
  end

  it "poly predicate dispatch" do
    result = ze0(<<~'RUBY')
      # all?/any?/none?/one? on a POLY receiver (a value the analyzer can only type
      # as poly, here a heterogeneous hash get) dispatch over the boxed array at
      # runtime instead of raising "undefined method for poly".
      h = { "nums" => [1, 2, 3], "label" => "x" }
      vals = h["nums"]
      p vals.all? { |v| !v.nil? }
      p vals.any? { |v| v.nil? }
      p vals.none? { |v| v.nil? }
      p vals.one? { |v| !v.nil? }
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
    OUT
  end

  it "poly predicate method dispatch" do
    result = ze0(<<~'RUBY')
      # all?/any?/none?/one? on a POLY receiver whose elements are used via a METHOD
      # DISPATCH (a struct element's reader) inside the block, not just a direct
      # predicate on the block param (which test/poly_predicate_dispatch.rb covers).
      # The param stays boxed as poly and `c.key` dispatches by class id -- the shape a
      # real object list (e.g. a reconciler's child nodes) takes.
      class Item
        def initialize(k)
          @k = k
        end

        def key = @k
      end
      h = { "items" => [Item.new("a"), Item.new(nil)], "label" => "x" }
      items = h["items"]
      p items.all? { |c| !c.key.nil? }
      p items.any? { |c| c.key.nil? }
      p items.none? { |c| c.key.nil? }
      p items.one? { |c| c.key.nil? }
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
    OUT
  end

  it "poly receiver kwargs into rest" do
    result = ze0(<<~'RUBY')
      # A keyword hash that no declared keyword parameter consumes degrades to one
      # positional hash at the tail of a *rest. The poly-dispatch arm did not do
      # that, so a call through a polymorphic receiver ran with no arguments at all
      # (#3528, the #3503 shape one call path further out).
      class Rel
        def initialize
          @parts = []
        end

        def order(*parts)
          @parts.concat(parts)
          self
        end

        def parts
          @parts
        end
      end

      class Other
        def order(*parts)
          self
        end
      end

      def take(r)
        r.order(id: :desc)
      end

      things = [Rel.new, Other.new]
      p take(things[0]).parts

      # positional and keyword together, on a fresh receiver so the parts are this
      # call's alone
      def take2(r)
        r.order(:a, id: :desc)
      end
      fresh = [Rel.new, Other.new]
      p take2(fresh[0]).parts

      # a declared keyword param still consumes it rather than degrading
      class Kw
        def initialize
          @seen = nil
        end

        def order(*parts, id: :none)
          @seen = [parts, id]
          self
        end

        def seen
          @seen
        end
      end

      def take3(r)
        r.order(id: :desc)
      end
      kws = [Kw.new, Kw.new]
      p take3(kws[0]).seen
    RUBY

    _(result).must_answer <<~'OUT'
      [{id: :desc}]
      [:a, {id: :desc}]
      [[], :desc]
    OUT
  end

  it "poly self deref" do
    result = ze0(<<~'RUBY')
      # Polymorphic dispatch where the called method dereferences `self`.
      # `cls_id` used to share memory with `v.p` inside the sp_RbVal union,
      # so writing cls_id after v.p clobbered the low 32 bits of the pointer.
      # Methods that touch instance fields then crashed (SIGSEGV).
      # Methods that did not touch self happened to work, masking the bug.

      class C
        attr_accessor :n
        def initialize(n)
          @n = n
        end
        def name
          @n.to_s
        end
      end

      class D
        def name
          "other"
        end
      end

      def show(o)
        o.name
      end

      puts show(C.new(42))
      puts show(D.new)
    RUBY

    _(result).must_answer <<~'OUT'
      42
      other
    OUT
  end

  it "poly user each index" do
    result = ze0(<<~'RUBY')
      # The blockless index enumerators on a poly receiver built an Enumerator over
      # the object without asking whether a user class owns the name: the method was
      # never entered, its side effects were dropped, and iterating the result
      # yielded nothing. The typing rule above it deliberately answers Enumerator
      # because a boxed receiver can always be an Array (#4021) -- true, and the
      # reason the user arm's own answer has nowhere to go unless the call is poly.
      class Rows
        def initialize
          @seen = []
        end

        attr_reader :seen

        def each_index
          @seen.push(:ran)
          [7]
        end
      end

      def indices(v) = v.each_index

      r = Rows.new
      got = indices(r)
      p r.seen
      p got.to_a
      got.each { |x| p x }

      p indices([1, 2]).to_a
      p indices(["a", "b", "c"]).to_a

      class Pairs
        def each_with_index
          ["p"]
        end
      end

      def pairs(v) = v.each_with_index
      p pairs(Pairs.new).to_a
      p pairs([1, 2]).to_a

      # with no user class in sight the enumerators are what they were
      p [1, 2, 3].each_index.to_a
      p [1, 2].each_with_index.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [:ran]
      [7]
      7
      [0, 1]
      [0, 1, 2]
      ["p"]
      [[1, 0], [2, 1]]
      [0, 1, 2]
      [[1, 0], [2, 1]]
    OUT
  end

  it "poly user join dispatch" do
    result = ze0(<<~'RUBY')
      # A poly receiver whose class defines `join`: the dedicated poly-join arm
      # answered the receiver's #to_s and never entered the method, because it did not
      # ask whether a user class owned the name the way its neighbours do (#4071). The
      # call has to dispatch, and an Array reaching the same call still has to join.
      class Row
        def initialize = @ran = false
        attr_reader :ran

        def join(sep)
          @ran = true
          "row" + sep
        end
      end

      def joined(v) = v.join("-")

      r = Row.new
      p joined(r)
      p r.ran
      p joined(["x", "y"])
      p joined([1, 2])

      # the zero-argument form reaches the other dispatch, whose array arms had to be
      # added alongside the user ones
      class Glue
        def join = "glue"
      end

      def j0(v) = v.join

      p j0(Glue.new)
      p j0(["a", "b"])
      p j0([1, 2])
    RUBY

    _(result).must_answer <<~'OUT'
      "row-"
      true
      "x-y"
      "1-2"
      "glue"
      "ab"
      "12"
    OUT
  end

  it "poly zero arg container reduction" do
    result = ze0(<<~'RUBY')
      # `arr.sum` on a receiver only known at run time, where a USER class owns the
      # name too (`Node#sum`). The dispatch switch covers user classes only, so a
      # real Array fell through to the NoMethodError default.

      class Node
        def initialize(v)
          @v = v
        end

        def sum
          @v
        end
      end

      class Table
        attr_accessor :total, :lo, :hi
        def initialize(*args)
          if args.size == 1 && args[0].is_a?(Array)
            frequencies = args[0]
            @total = frequencies.sum
            @lo = frequencies.min
            @hi = frequencies.max
          else
            @total = 0
            @lo = 0
            @hi = 0
          end
        end
      end

      t = Table.new([3, 1, 2])
      p t.total
      p t.lo
      p t.hi
      p Table.new.total
      p Node.new(5).sum
    RUBY

    _(result).must_answer <<~'OUT'
      6
      1
      3
      0
      5
    OUT
  end

  it "runtime visibility marks govern dynamic dispatch" do
    result = ze0(<<~'RUBY')
      # Runtime `Module#private`/`public`/`protected` with name arguments
      # (`class_eval { private :m }`): marks land in the overlay and govern the
      # DYNAMIC paths -- `respond_to?`, `public_send`, plain `send` -- with the
      # return shapes, NameError timing, and an alias inheriting its source's
      # runtime-marked visibility all oracle-verified verbatim. (Static call
      # sites with literal names resolve visibility at compile time and don't
      # see runtime marks -- the documented AOT boundary -- so every probe here
      # uses a computed name.)

      class C
        def m
          1
        end
        def m2
          2
        end
      end
      p C.class_eval { private :m }
      p C.class_eval { private :m, :m2 }
      sym = :m
      p C.new.respond_to?(sym)
      begin
        C.new.public_send(sym)
      rescue NoMethodError => e
        puts e.message
      end
      p C.new.send(sym)
      p C.class_eval { public "m" }
      p C.new.respond_to?(sym)
      p C.new.public_send(sym)
      class D
        def p1
          3
        end
      end
      D.class_eval { protected :p1 }
      psym = :p1
      begin
        D.new.public_send(psym)
      rescue NoMethodError => e
        puts e.message
      end
      begin
        C.class_eval { private :nope }
      rescue NameError => e
        puts e.message
      end
      class Al
        def hidden
          4
        end
      end
      Al.class_eval { private :hidden }
      Al.class_eval { [[:hidden2, :hidden]].each { |a, b| alias_method(a, b) } }
      h2 = :hidden2
      begin
        Al.new.public_send(h2)
      rescue NoMethodError => e
        puts e.message
      end
      p Al.new.send(h2)
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      :m
      [:m, :m2]
      false
      private method 'm' called for an instance of C
      1
      "m"
      true
      1
      protected method 'p1' called for an instance of D
      undefined method 'nope' for class 'C'
      private method 'hidden2' called for an instance of Al
      4
      done
    OUT
  end

  it "safe nav poly dispatch" do
    result = ze0(<<~'RUBY')
      # safe navigation on a poly receiver must dispatch the method through the
      # poly runtime-class switch, not drop it and return the receiver (#3269).
      class Flag
        def fn? = false
        def name = "flg"
      end
      class Crash
        def parse(argument)
          @flags = [Flag.new]
          @flags.first&.fn?
        end
      end
      raise "FAIL" unless !Crash.new.parse("-qv")

      arr = [Object.new, "hello", 42, nil]
      p arr[1]&.upcase
      p arr[2]&.to_s
      p arr[3]&.length
      p arr[1]&.length
      flags = [Flag.new]
      p flags.first&.fn?
      p flags.first&.name
      p [].first&.fn?
      puts "OK"
    RUBY

    _(result).must_answer <<~'OUT'
      "HELLO"
      "42"
      nil
      5
      false
      "flg"
      nil
      OK
    OUT
  end

  it "splat destructure poly" do
    result = ze0(<<~'RUBY')
      # Splat destructure with a poly_array RHS — Gemini concern on PR #116:
      # the runtime-slice path of compile_multi_write_splat had no case for
      # poly_array, so it fell through to sp_IntArray_get / sp_IntArray_slice
      # and the C compile rejected the type mismatch. With the fix the path
      # uses sp_PolyArray_get / sp_PolyArray_slice for poly_array RHS.

      def heterogeneous
        ["alpha", 1, "beta", 2.5, "gamma"]
      end

      # Trailing splat — splat target is a sp_PolyArray * holding the tail.
      a, b, *rest = heterogeneous
      puts a              # alpha
      puts rest.length    # 3

      # Leading splat — splat target holds the head, then two scalar tails.
      *head, y, z = heterogeneous
      puts head.length    # 3
      puts z              # gamma
      puts y              # 2.5  (Ruby) — verifies float scalar from poly RHS

      # Middle splat — most exercise of the slice + bracketing helpers.
      p, *mid, q = heterogeneous
      puts mid.length     # 3
      puts p              # alpha
      puts q              # gamma
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      3
      3
      gamma
      2.5
      3
      alpha
      gamma
    OUT
  end

  it "top level def is callable from a class body and a class method" do
    result = ze0(<<~'RUBY')
      # `self` in a class body/class method is the CLASS OBJECT -- there's no
      # concrete receiver to clone, so implicit-self dispatch must go through
      # `RubyValue::Class`, not an invalid `self.clone()`.

      def helper(tag)
        "helped-#{tag}"
      end
      class AtBody
        RESULT = helper("body")
      end
      class Factory
        def self.build
          helper("class-method")
        end
      end
      puts AtBody::RESULT
      puts Factory.build
    RUBY

    _(result).must_answer <<~'OUT'
      helped-body
      helped-class-method
    OUT
  end

  it "virtual dispatch void override" do
    _(ze0(<<~'RUBY')).must_answer "sub\n"
      # An implicit-self call to a void method that subclasses override must dispatch
      # on the runtime class, not bind statically to the base implementation.
      class Base
        def run
          validate
        end
        def validate
          puts "base"
        end
      end
      class Sub < Base
        def validate
          puts "sub"
        end
      end
      Sub.new.run
    RUBY
  end

  it "virtual dispatch void override empty base" do
    _(ze0(<<~'RUBY')).must_answer "sub-ran\n"
      # Empty void base body, overridden in a subclass: the implicit-self call from
      # the base method must still reach the subclass override.
      class Base
        def run; validate; end
        def validate; end
      end
      class Sub < Base
        def validate; puts "sub-ran"; end
      end
      Sub.new.run
    RUBY
  end
end
