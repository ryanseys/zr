# frozen_string_literal: true

require "spec_helper"

describe "Object: frozen literals" do
  it "bareword freeze" do
    result = ze0(<<~'RUBY')
      # Bareword freeze (implicit self) inside an instance method sets the
      # instance's GC-header frozen bit and returns self, so the defensive-freeze
      # idiom carries real state (frozen? reads it back; mutation raises).
      # Reads after freeze are unaffected.
      class Config
        def initialize(v)
          @v = v
          freeze
        end
        def v = @v
      end
      puts Config.new(42).v

      # freeze as an expression returns self, typed as the instance so it chains
      class Box
        def initialize
          @items = [1, 2, 3]
        end
        def seal = freeze
        def items = @items
      end
      puts Box.new.seal.items.inspect
    RUBY

    _(result).must_answer "42\n[1, 2, 3]\n"
  end

  it "bool nil immediate edges" do
    result = ze0(<<~'RUBY')
      # Immediate-receiver edges: <=> between equal bools/nils is 0 (#2733), a bool
      # has no #=~ so !~ raises (#2732), TrueClass/FalseClass/NilClass have no
      # allocator (#2751), and clone(freeze: false) cannot unfreeze an immediate
      # (#2764).
      p(true <=> true)
      p(false <=> false)
      p(true <=> false)
      p(nil <=> nil)
      r = (true !~ /x/ rescue $!.class); p r
      r = (TrueClass.new rescue $!.message); p r
      r = (FalseClass.new rescue $!.class); p r
      r = (NilClass.new rescue $!.message); p r
      r = (true.clone(freeze: false) rescue $!.message); p r
      r = (5.clone(freeze: false) rescue $!.message); p r
      r = (:a.clone(freeze: false) rescue $!.message); p r
      p("s".clone(freeze: false).frozen?)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      nil
      0
      NoMethodError
      "undefined method 'new' for class TrueClass"
      NoMethodError
      "undefined method 'new' for class NilClass"
      "can't unfreeze TrueClass"
      "can't unfreeze Integer"
      "can't unfreeze Symbol"
      false
    OUT
  end

  it "class clone dup are anonymous" do
    result = ze0(<<~'RUBY')
      # `Module#dup`/`#clone` on a CLASS return the SAME OBJECT in zeo --
      # `K.dup.equal?(K)` is true where ruby answers false. So the name is not
      # merely wrong, it is `K`'s own: renaming the copy would rename `K`.
      #
      # `Kernel#dup`/`#clone` (crates/zeo-rt/src/builtins/kernel.rs) route a MODULE
      # receiver to `runtime_meta::runtime_module_dup` and a CLASS receiver to
      # `recv.dup_value(false)`, which for a `RubyValue::Class` is a handle copy.
      # The comment there calls it "the documented handle-passthrough: copying one
      # means copying its instances' layout, which this AOT model has no way to
      # mint".
      #
      # That reason is now weaker than it reads, and this is the part worth
      # knowing before anyone re-scopes it: `Class.new(K)` ALREADY mints a working
      # anonymous runtime class -- verified, it answers `name == nil` and
      # `superclass == K`. So the layout problem is solved; what is missing is the
      # COPY. CRuby's `rb_mod_init_copy` moves the source's own method table,
      # constants and class-level ivars onto the new class (`clone` additionally
      # copies the singleton class and the frozen state; `dup` takes neither).
      #
      # A fix therefore looks like: mint through the same path `Class.new(K)` uses,
      # then copy `K`'s own rows rather than inheriting them. The risk to watch is
      # that zeo's compiled methods are registered per ClassId, so "copy the own
      # rows" means registering the same fn pointers under the new id -- which the
      # runtime overlay can already express (`define_method_own`), but which no
      # caller does in bulk today.
      class K; end
      p K.clone.name
      p K.dup.name
      p K.name
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      "K"
    OUT
  end

  it "class dup and clone are real copies" do
    result = ze0(<<~'RUBY')
      # `Class#dup`/`#clone` mint an ANONYMOUS class sharing the source's superclass
      # and mixins and carrying copies of its own rows, constants and class-level
      # state. Handing back the same handle made `K.dup.equal?(K)` true, so naming
      # the copy renamed `K` and editing it edited the original.
      class K
        X = 1
        @civ = :c
        @@cv = :cv
        def self.civ = @civ
        def self.cls = :cls
        def m = :m
        private def pm = :pm
      end

      d = K.dup
      c = K.clone
      p [d.name, c.name, K.name]
      p [d.equal?(K), c.equal?(K), d.equal?(c)]
      p [d.class, c.class]
      p d.superclass.to_s
      p [d.singleton_methods.sort, c.singleton_methods.sort]
      p [d.instance_variable_get(:@civ), c.civ]
      p [d.constants, d.const_get(:X)]
      p d.instance_methods(false).sort
      p d.private_instance_methods(false)
      p d.class_variable_get(:@@cv)
      p d.new.m
      p d.new.is_a?(K)
      p d.new.class.equal?(d)

      # Editing the copy leaves the source alone.
      d.const_set(:Y, 2)
      p [d.constants.sort, K.constants.sort]
      NamedCopy = K.dup
      p [NamedCopy.name, K.name]

      # Mixins ride along.
      module Mix
        def mx = :mx
      end
      class L
        include Mix
      end
      p L.dup.ancestors.map(&:to_s).drop(1)
      p L.dup.new.mx

      # A subclass copy keeps its real superclass.
      class Sub < K; end
      p Sub.dup.superclass.to_s
      p Sub.dup.new.m

      # `clone` carries the frozen state; `dup` never does.
      K.freeze
      p [K.dup.frozen?, K.clone.frozen?, K.clone(freeze: false).frozen?]

      # A MODULE copy still works the way it always did.
      p [Mix.dup.name, Mix.dup.equal?(Mix)]
      p Mix.dup.instance_methods(false)
    RUBY

    _(result).must_answer <<~'OUT'
      [nil, nil, "K"]
      [false, false, false]
      [Class, Class]
      "Object"
      [[:civ, :cls], [:civ, :cls]]
      [:c, :c]
      [[:X], 1]
      [:m]
      [:pm]
      :cv
      :m
      false
      true
      [[:X, :Y], [:X]]
      ["NamedCopy", "K"]
      ["Mix", "Object", "Kernel", "BasicObject"]
      :mx
      "K"
      :m
      [false, true, false]
      [nil, false]
      [:mx]
    OUT
  end

  it "clone honors the freeze keyword" do
    result = ze0(<<~'RUBY')
      a = "hi".freeze
      p a.clone.frozen?
      p a.clone(freeze: false).frozen?
      p a.clone(freeze: true).frozen?
      b = "yo"
      p b.clone.frozen?
      p b.clone(freeze: true).frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      true
    OUT
  end

  it "core rows live on the class ruby defines them on" do
    result = ze0(<<~'RUBY')
      # CRuby writes some rows on a class of its own even where they share the
      # function Kernel's row uses: `===` on nil, true, false and Symbol,
      # `freeze` on String, Array, Hash and Module, `dup` and `clone` on Proc
      # and the method classes. Main owns `using` and `ruby2_keywords`. Equal
      # methods share a hash, also through an alias of one C function.

      p singleton_class.private_instance_methods(false).sort
      p Kernel.private_instance_methods.include?(:using)
      def a(*args) = args
      ruby2_keywords :a
      p a(k: 1).last

      [NilClass, TrueClass, FalseClass, Symbol].each { |c| p [c, c.instance_method(:===).owner] }
      [String, Array, Hash, Module].each { |c| p [c, c.instance_method(:freeze).owner] }
      [Proc, Method, UnboundMethod].each { |c| p [c, c.instance_method(:dup).owner, c.instance_method(:clone).owner] }
      p String.instance_method(:dup).owner, Module.instance_method(:==).owner

      pr = proc { 1 }.freeze
      p pr.clone.frozen?, pr.dup.frozen?
      p nil === nil, true === true, :a === :a, false === nil, Module == Module

      um = String.instance_method(:size)
      p um.hash == String.instance_method(:size).hash
      p um.hash == String.instance_method(:length).hash
      p "a".method(:upcase).unbind.hash == String.instance_method(:upcase).hash
      p "a".method(:upcase).hash == "a".method(:upcase).hash

    RUBY

    _(result).must_answer <<~'OUT'
      [:define_method, :include, :private, :public, :ruby2_keywords, :using]
      false
      {k: 1}
      [NilClass, NilClass]
      [TrueClass, TrueClass]
      [FalseClass, FalseClass]
      [Symbol, Symbol]
      [String, String]
      [Array, Array]
      [Hash, Hash]
      [Module, Module]
      [Proc, Proc, Proc]
      [Method, Method, Method]
      [UnboundMethod, UnboundMethod, UnboundMethod]
      String
      Module
      true
      false
      true
      true
      true
      false
      true
      true
      true
      true
      false
    OUT
  end

  it "dup and clone on collections follow the frozen rule" do
    result = ze0(<<~'RUBY')
      # dup: fresh unfrozen payload (mutable even when the source is
      # frozen, and mutating it leaves the source untouched); clone:
      # carries the frozen flag.

      arr = [1].freeze
      d = arr.dup
      d << 2
      puts d.length
      puts arr.length
      puts d.frozen?
      puts arr.clone.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      false
      true
    OUT
  end

  it "empty literal freeze" do
    result = ze0(<<~'RUBY')
      # `[].freeze` is the frozen-empty-array idiom: the call must not be dropped,
      # and the array must be built at the slot's type (#3828).
      p [].freeze.frozen?
      p [1].freeze.frozen?
      p({}.freeze.frozen?)
      p "s".freeze.frozen?
      x = [].freeze
      p x.frozen?
      p x
      y = []
      y.freeze
      p y.frozen?
      EMPTY = [].freeze
      p EMPTY.frozen?
      begin
        x << 1
      rescue FrozenError
        puts "FrozenError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      []
      true
      true
      FrozenError
    OUT
  end

  it "freeze" do
    result = ze0(<<~'RUBY')
      # .freeze / .frozen? -- shallow freezing with catchable FrozenError

      a = [1, 2, 3]
      puts a.frozen?
      a.freeze
      puts a.frozen?
      begin
        a[0] = 9
      rescue FrozenError => e
        puts e.send(:message)
      end
      puts a[0]

      # freeze returns self, repeat freeze is a no-op
      names = ["a", "b"].freeze
      names.freeze
      puts names[0]
      puts names.length

      # shallow: a frozen container's elements stay mutable
      inner = [1, 2]
      outer = [inner]
      outer.freeze
      inner[0] = 99
      puts inner[0]

      # immediates and ranges are always frozen
      puts 1.frozen?
      puts :sym.frozen?
      puts nil.frozen?
      puts (1..5).frozen?

      # frozen hash and string
      h = { a: 1 }
      h.freeze
      begin
        h[:b] = 2
      rescue FrozenError => e
        puts e.send(:message)
      end

      s = "abc".freeze
      begin
        s[0] = "z"
      rescue FrozenError => e
        puts e.send(:message)
      end

      # frozen objects reject ivar writes
      class Counter
        def initialize
          @count = 0
        end
        def bump
          @count = @count + 1
        end
        def count
          @count
        end
      end

      c = Counter.new
      c.bump
      c.freeze
      begin
        c.bump
      rescue FrozenError
        puts "frozen counter"
      end
      puts c.count
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      can't modify frozen Array: [1, 2, 3]
      1
      a
      2
      99
      true
      true
      true
      true
      can't modify frozen Hash: {a: 1}
      can't modify frozen String: "abc"
      frozen counter
      1
    OUT
  end

  it "freeze is shallow so a frozen containers elements stay mutable" do
    result = ze0(<<~'RUBY')
      inner = [1, 2]
      b = [inner]
      b.freeze
      inner[0] = 99
      puts inner[0]
      puts b.frozen?
    RUBY

    _(result).must_answer "99\ntrue\n"
  end

  it "freeze user object" do
    result = ze0(<<~'RUBY')
      # freeze / frozen? on user instances: the bareword self-freeze idiom sets
      # real state, frozen? reads it back, and mutation after freeze raises
      # FrozenError with CRuby's message (address-normalized for comparison).
      def norm(e) = "#{e.class}: #{e.message.sub(/0x[0-9a-f]+/, '0xADDR')}"

      class Sealed
        attr_reader :x
        attr_writer :x
        def initialize
          @x = 1
          @tag = "s"
          freeze
        end
        def poke = (@x = 2)
        def poke_expr = (y = (@x = 3); y)
      end

      o = Sealed.new
      p o.frozen?
      p o.x
      begin
        o.poke
      rescue => e
        puts norm(e)
      end
      begin
        o.poke_expr
      rescue => e
        puts norm(e)
      end
      begin
        o.x = 5
      rescue => e
        puts norm(e)
      end
      p o.x

      class Lazy
        attr_accessor :v
        def initialize = (@v = 10)
        def seal = freeze
        def sealed? = frozen?
      end

      l = Lazy.new
      p l.sealed?
      l.v = 11
      p l.v
      l.seal
      p l.sealed?
      p l.frozen?
      begin
        l.v = 12
      rescue => e
        puts norm(e)
      end
      p l.v

      class OwnFreeze
        attr_reader :log
        def initialize = (@log = "clean")
        def freeze = (@log = "custom"; self)
      end

      f = OwnFreeze.new
      f.freeze
      p f.log
      p f.frozen?

      class Never
        attr_accessor :n
        def initialize = (@n = 0)
      end
      nv = Never.new
      nv.n = 7
      p nv.n
    RUBY

    _(result).must_answer <<~'OUT'
      true
      1
      FrozenError: can't modify frozen Sealed: #<Sealed:0xADDR @x=1, @tag="s">
      FrozenError: can't modify frozen Sealed: #<Sealed:0xADDR @x=1, @tag="s">
      FrozenError: can't modify frozen Sealed: #<Sealed:0xADDR @x=1, @tag="s">
      1
      false
      11
      true
      true
      FrozenError: can't modify frozen Lazy: #<Lazy:0xADDR @v=11>
      11
      "custom"
      false
      7
    OUT
  end

  it "frozen and object identity" do
    result = ze0(<<~'RUBY')
      # Object identity and freezing across the linked runtime's allocator.
      a = "mutable".dup
      b = a.dup
      p a == b, a.equal?(b)
      a.freeze
      p a.frozen?, b.frozen?
      begin
        a << "!"
      rescue FrozenError => e
        puts e.class
      end
      p 1.frozen?, :sym.frozen?, nil.frozen?
      p Object.new.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      FrozenError
      true
      true
      true
      false
    OUT
  end

  it "frozen class reopen" do
    result = ze0(<<~'RUBY')
      class Fz; end
      Fz.freeze
      begin
        class Fz
          def x; end
        end
      rescue FrozenError => e
        p e.class
      end
      p Fz.frozen?
      p Fz.instance_methods(false)
    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
      true
      []
    OUT
  end

  it "frozen collection mutator matrix matches cruby" do
    result = ze0(<<~'RUBY')
      # The full String/Array/Hash mutator matrix against a frozen receiver
      # -- every row's outcome (FrozenError, or legal like `str * 2`) is
      # verbatim ruby 4.0.6. Guard-ordering nuances included: `setbyte`
      # validates index/type BEFORE the frozen check; `transform_values!`
      # returns its blockless enumerator before it.

      def try(label)
        yield
        puts "#{label}: ok"
      rescue => e
        puts "#{label}: #{e.class}: #{e.message}"
      end

      s = "abc".freeze
      try("str <<") { s << "d" }
      try("str concat") { s.concat("d") }
      try("str insert") { s.insert(0, "x") }
      try("str prepend") { s.prepend("x") }
      try("str replace") { s.replace("x") }
      try("str clear") { s.clear }
      try("str chomp!") { s.chomp! }
      try("str chop!") { s.chop! }
      try("str squeeze!") { s.squeeze! }
      try("str strip!") { s.strip! }
      try("str lstrip!") { s.lstrip! }
      try("str rstrip!") { s.rstrip! }
      try("str sub!") { s.sub!(/a/, "z") }
      try("str gsub!") { s.gsub!(/a/, "z") }
      try("str tr!") { s.tr!("a", "z") }
      try("str tr_s!") { s.tr_s!("a", "z") }
      try("str delete!") { s.delete!("a") }
      try("str upcase!") { s.upcase! }
      try("str downcase!") { s.downcase! }
      try("str capitalize!") { s.capitalize! }
      try("str swapcase!") { s.swapcase! }
      try("str succ!") { s.succ! }
      try("str reverse!") { s.reverse! }
      try("str slice!") { s.slice!(0) }
      try("str []=") { s[0] = "z" }
      try("str setbyte") { s.setbyte(0, 122) }
      try("str *=(noop) freeze-safe read") { s * 2 }

      a = [3, 1, 2].freeze
      try("arr <<") { a << 4 }
      try("arr push") { a.push(4) }
      try("arr pop") { a.pop }
      try("arr shift") { a.shift }
      try("arr unshift") { a.unshift(0) }
      try("arr insert") { a.insert(0, 9) }
      try("arr []=") { a[0] = 9 }
      try("arr delete") { a.delete(1) }
      try("arr delete_at") { a.delete_at(0) }
      try("arr delete_if") { a.delete_if { true } }
      try("arr clear") { a.clear }
      try("arr compact!") { a.compact! }
      try("arr flatten!") { a.flatten! }
      try("arr uniq!") { a.uniq! }
      try("arr sort!") { a.sort! }
      try("arr sort_by!") { a.sort_by! { |x| x } }
      try("arr reverse!") { a.reverse! }
      try("arr rotate!") { a.rotate! }
      try("arr shuffle!") { a.shuffle! }
      try("arr map!") { a.map! { |x| x } }
      try("arr select!") { a.select! { true } }
      try("arr reject!") { a.reject! { false } }
      try("arr keep_if") { a.keep_if { true } }
      try("arr fill") { a.fill(0) }
      try("arr replace") { a.replace([1]) }
      try("arr concat") { a.concat([1]) }

      h = { k: 1 }.freeze
      try("hash []=") { h[:x] = 2 }
      try("hash store") { h.store(:x, 2) }
      try("hash delete") { h.delete(:k) }
      try("hash delete_if") { h.delete_if { true } }
      try("hash clear") { h.clear }
      try("hash merge!") { h.merge!({ b: 2 }) }
      try("hash update") { h.update({ b: 2 }) }
      try("hash reject!") { h.reject! { false } }
      try("hash select!") { h.select! { true } }
      try("hash keep_if") { h.keep_if { true } }
      try("hash compact!") { h.compact! }
      try("hash transform_keys!") { h.transform_keys!(&:to_s) }
      try("hash transform_values!") { h.transform_values! { |v| v } }
      try("hash replace") { h.replace({}) }
      try("hash default=") { h.default = 0 }
      try("hash shift") { h.shift }
    RUBY

    _(result).must_answer <<~'OUT'
      str <<: FrozenError: can't modify frozen String: "abc"
      str concat: FrozenError: can't modify frozen String: "abc"
      str insert: FrozenError: can't modify frozen String: "abc"
      str prepend: FrozenError: can't modify frozen String: "abc"
      str replace: FrozenError: can't modify frozen String: "abc"
      str clear: FrozenError: can't modify frozen String: "abc"
      str chomp!: FrozenError: can't modify frozen String: "abc"
      str chop!: FrozenError: can't modify frozen String: "abc"
      str squeeze!: FrozenError: can't modify frozen String: "abc"
      str strip!: FrozenError: can't modify frozen String: "abc"
      str lstrip!: FrozenError: can't modify frozen String: "abc"
      str rstrip!: FrozenError: can't modify frozen String: "abc"
      str sub!: FrozenError: can't modify frozen String: "abc"
      str gsub!: FrozenError: can't modify frozen String: "abc"
      str tr!: FrozenError: can't modify frozen String: "abc"
      str tr_s!: FrozenError: can't modify frozen String: "abc"
      str delete!: FrozenError: can't modify frozen String: "abc"
      str upcase!: FrozenError: can't modify frozen String: "abc"
      str downcase!: FrozenError: can't modify frozen String: "abc"
      str capitalize!: FrozenError: can't modify frozen String: "abc"
      str swapcase!: FrozenError: can't modify frozen String: "abc"
      str succ!: FrozenError: can't modify frozen String: "abc"
      str reverse!: FrozenError: can't modify frozen String: "abc"
      str slice!: FrozenError: can't modify frozen String: "abc"
      str []=: FrozenError: can't modify frozen String: "abc"
      str setbyte: FrozenError: can't modify frozen String: "abc"
      str *=(noop) freeze-safe read: ok
      arr <<: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr push: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr pop: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr shift: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr unshift: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr insert: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr []=: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr delete: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr delete_at: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr delete_if: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr clear: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr compact!: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr flatten!: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr uniq!: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr sort!: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr sort_by!: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr reverse!: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr rotate!: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr shuffle!: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr map!: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr select!: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr reject!: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr keep_if: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr fill: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr replace: FrozenError: can't modify frozen Array: [3, 1, 2]
      arr concat: FrozenError: can't modify frozen Array: [3, 1, 2]
      hash []=: FrozenError: can't modify frozen Hash: {k: 1}
      hash store: FrozenError: can't modify frozen Hash: {k: 1}
      hash delete: FrozenError: can't modify frozen Hash: {k: 1}
      hash delete_if: FrozenError: can't modify frozen Hash: {k: 1}
      hash clear: FrozenError: can't modify frozen Hash: {k: 1}
      hash merge!: FrozenError: can't modify frozen Hash: {k: 1}
      hash update: FrozenError: can't modify frozen Hash: {k: 1}
      hash reject!: FrozenError: can't modify frozen Hash: {k: 1}
      hash select!: FrozenError: can't modify frozen Hash: {k: 1}
      hash keep_if: FrozenError: can't modify frozen Hash: {k: 1}
      hash compact!: FrozenError: can't modify frozen Hash: {k: 1}
      hash transform_keys!: FrozenError: can't modify frozen Hash: {k: 1}
      hash transform_values!: FrozenError: can't modify frozen Hash: {k: 1}
      hash replace: FrozenError: can't modify frozen Hash: {k: 1}
      hash default=: FrozenError: can't modify frozen Hash: {k: 1}
      hash shift: FrozenError: can't modify frozen Hash: {k: 1}
    OUT
  end

  it "frozen mutation arg eval order" do
    result = ze0(<<~'RUBY')
      # Ruby evaluates a mutator's arguments before the call runs, so a
      # side-effecting argument (and an op-assign RHS) must still execute even when
      # the receiver is frozen and the mutation ultimately raises FrozenError. Each
      # "arg:X" must print BEFORE its "... raised" line.
      def note(x); puts "arg:#{x}"; x; end

      begin; "hi".freeze.concat(note("!")); rescue FrozenError; puts "concat raised"; end
      begin; "yo".freeze.prepend(note(">")); rescue FrozenError; puts "prepend raised"; end

      h = {n: 1}.freeze
      begin; h[:n] += note(9); rescue FrozenError; puts "hash raised"; end

      # sanity: the unfrozen path still evaluates the arg AND mutates
      m = "go"; m << note("!"); puts m
    RUBY

    _(result).must_answer <<~'OUT'
      arg:!
      concat raised
      arg:>
      prepend raised
      arg:9
      hash raised
      arg:!
      go!
    OUT
  end

  it "frozen predicate flips after freeze and freeze returns self" do
    result = ze0(<<~'RUBY')
      a = [1]
      puts a.frozen?
      b = a.freeze
      puts a.frozen?
      puts b.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
    OUT
  end

  it "generic object freeze clone and immutable unfreeze" do
    result = ze0(<<~'RUBY')
      # Object.new instances track frozen state (freeze/frozen?/clone-preserves);
      # clone(freeze: false) on an always-frozen immediate raises ArgumentError.

      o = Object.new
      p o.frozen?
      o.freeze
      p o.frozen?
      p o.clone.frozen?
      p o.dup.frozen?
      u = Object.new
      p u.clone(freeze: true).frozen?
      p u.clone(freeze: false).frozen?
      p((nil.clone(freeze: false) rescue $!.class))
      p((1.clone(freeze: false) rescue $!.class))
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      false
      true
      false
      ArgumentError
      ArgumentError
    OUT
  end

  it "method object freezes its entry" do
    result = ze0(<<~'RUBY')
      # A `Method`/`UnboundMethod` COPIES the method entry when it is taken, so a
      # later redefinition cannot change what it calls. That single fact is what makes
      # the wrap-and-redefine idiom terminate -- the canonical thing a `method_added`
      # hook is written to do. Re-resolving by name instead finds the wrapper and
      # recurses until the stack runs out.

      puts "== UnboundMethod#bind"
      class Z
        def m = "orig"
      end
      orig = Z.instance_method(:m)
      Z.send(:define_method, :m) { "wrapped(" + orig.bind(self).call + ")" }
      p Z.new.m

      puts "== UnboundMethod#bind_call"
      class Y
        def m = "orig"
      end
      o2 = Y.instance_method(:m)
      Y.class_eval { define_method(:m) { "w(" + o2.bind_call(self) + ")" } }
      p Y.new.m

      puts "== Object#method"
      class W
        def m = "orig"
      end
      w = W.new
      bound = w.method(:m)
      W.send(:define_method, :m) { "new" }
      p [bound.call, w.m]

      puts "== unbind and rebind still carries the frozen entry"
      class V
        def m = "orig"
      end
      v1, v2 = V.new, V.new
      taken = v1.method(:m)
      V.send(:define_method, :m) { "new" }
      p [taken.unbind.bind(v2).call, v2.m]

      puts "== the whole wrap-and-redefine hook, which is the point"
      class Traced
        def self.method_added(name)
          return if @wrapping
          @wrapping = true
          inner = instance_method(name)
          define_method(name) { |*a| "<#{inner.bind(self).call(*a)}>" }
          @wrapping = false
        end

        def first = "1st"
        def later(n) = "2nd:#{n}"
      end
      p [Traced.new.first, Traced.new.later(7)]

      puts "== super_method still resolves down the chain"
      class Base
        def greet = "base"
      end
      class Sub < Base
        def greet = "sub+" + super
      end
      mm = Sub.new.method(:greet)
      p [mm.call, mm.super_method.call, mm.owner, mm.super_method.owner]

      puts "== an alias keeps its own entry"
      class A
        def m = "first"
        alias_method :copy, :m
        def m = "second"
      end
      p [A.new.m, A.new.copy]
    RUBY

    _(result).must_answer <<~'OUT'
      == UnboundMethod#bind
      "wrapped(orig)"
      == UnboundMethod#bind_call
      "w(orig)"
      == Object#method
      ["orig", "new"]
      == unbind and rebind still carries the frozen entry
      ["orig", "new"]
      == the whole wrap-and-redefine hook, which is the point
      ["<1st>", "<2nd:7>"]
      == super_method still resolves down the chain
      ["sub+base", "base", Sub, Base]
      == an alias keeps its own entry
      ["second", "first"]
    OUT
  end

  it "module of module diamond dispatches and is a resolves transitively" do
    result = ze0(<<~'RUBY')
      # The exact shape zeo's OWN reflection gets wrong (verified by
      # running a repro against zeo's own binary): `D` included via two
      # separate paths (`B`/`C`, both including `D`) must be deduped to a
      # single shared position, and `is_a?(D)` must resolve `true` even
      # though `D` was never included DIRECTLY by `A`.

      module D
        def who
          "D"
        end
      end
      module B
        include D
      end
      module C
        include D
      end
      class A
        include B
        include C
      end
      class Unrelated
      end
      puts A.new.who
      puts A.new.is_a?(D)
      puts A.new.is_a?(B)
      puts A.new.is_a?(Unrelated)
    RUBY

    _(result).must_answer <<~'OUT'
      D
      true
      true
      false
    OUT
  end

  it "object freeze flag" do
    result = ze0(<<~'RUBY')
      class C; end
      o = C.new
      puts o.frozen?
      o.freeze
      puts o.frozen?
      S = Struct.new(:a)
      x = S.new(1)
      puts x.frozen?
      x.freeze
      puts x.frozen?
      y = S.new(2)
      puts y.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      false
    OUT
  end

  it "object freeze module isa" do
    result = ze0(<<~'RUBY')
      # freeze state on Proc/Enumerator; is_a? for included builtin modules
      # (KieranP #2362, #2363)
      a = ->(x) { x }
      p a.frozen?
      a.freeze
      p a.frozen?
      p a.freeze.equal?(a)
      e = [1].each
      p e.frozen?
      e.freeze
      p e.frozen?
      class Ver
        include Comparable
        attr_reader :n
        def initialize(n); @n = n; end
        def <=>(o); n <=> o.n; end
      end
      p Ver.new(5).is_a?(Comparable)
      class Sub < Ver; end
      p Sub.new(1).is_a?(Comparable)     # inherited include
      class Nums
        include Enumerable
        def each; yield 1; end
      end
      p Nums.new.is_a?(Enumerable)
      class Plain; end
      p Plain.new.is_a?(Comparable)
      module M; end
      class WithM; include M; end
      p WithM.new.is_a?(M)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      false
      true
      true
      true
      true
      false
      true
    OUT
  end

  it "repeated freeze is a silent no op" do
    result = ze0(<<~'RUBY')
      c = "hi"
      c.freeze
      c.freeze
      puts c.frozen?
    RUBY

    _(result).must_answer "true\n"
  end

  it "self freeze inside a method freezes the receiver" do
    result = ze0(<<~'RUBY')
      class Lockable
        def initialize
          @v = 1
        end
        def lock_it
          self.freeze
        end
        def set_v(n)
          @v = n
        end
        def v
          @v
        end
      end
      l = Lockable.new
      l.lock_it
      puts l.frozen?
      begin
        l.set_v(2)
      rescue FrozenError => e
        puts "frozen!"
      end
      puts l.v
    RUBY

    _(result).must_answer <<~'OUT'
      true
      frozen!
      1
    OUT
  end

  it "user defined freeze override wins over the builtin" do
    result = ze0(<<~'RUBY')
      # `freeze`/`frozen?` are ordinary overridable Kernel methods in real
      # Ruby -- a class's own definition must win over the universal dispatch.

      class Custom
        def freeze
          :custom
        end
      end
      puts Custom.new.freeze
    RUBY

    _(result).must_answer "custom\n"
  end

  it "user object freeze frozen and custom freeze returning self" do
    result = ze0(<<~'RUBY')
      # The `freeze_user_object` scenario end to end: a bareword self-`freeze`
      # in `initialize` sets real state, `frozen?` reads it back, mutation
      # after freeze raises FrozenError, and a user `def freeze = (@log =
      # "custom"; self)` (the `Seq`-tail-`self` shape whose codegen boxing was
      # the E0308) returns self, runs its body, and -- since it overrides the
      # real freeze -- leaves the object UNfrozen. (The FrozenError message's
      # inspect tail `#<Sealed:0x.. @x=1>` is a separate default-inspect gap,
      # so this asserts the message PREFIX, not the address/ivar detail.)

      class Sealed
        attr_accessor :x
        def initialize
          @x = 1
          freeze
        end
      end
      o = Sealed.new
      p o.frozen?
      begin
        o.x = 2
      rescue FrozenError => e
        puts "FrozenError: #{e.message.start_with?('can\'t modify frozen Sealed')}"
      end
      p o.x

      class OwnFreeze
        attr_reader :log
        def initialize = (@log = "clean")
        def freeze = (@log = "custom"; self)
      end
      f = OwnFreeze.new
      p f.freeze.equal?(f)
      p f.log
      p f.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      FrozenError: true
      1
      true
      "custom"
      false
    OUT
  end

  it "user value object freeze" do
    result = ze0(<<~'RUBY')
      # freeze on a user-defined VALUE-type instance (a small immutable scalar-ivar
      # class represented by value, sp_X, not a heap pointer). Stateful freeze reaches
      # for the object's GC-header bit, which a value struct does not carry; the mono
      # arm must fall back to the self-returning no-op instead of passing the struct
      # to sp_gc_freeze(void*). freeze compiles, returns self, and the object stays
      # usable; frozen? on a value object reads false but must still evaluate its
      # receiver so a side-effecting receiver expression is not discarded.
      class Point
        attr_reader :x, :y

        def initialize(x, y)
          @x = x
          @y = y
        end
      end

      pt = Point.new(3, 4)
      q = pt.freeze
      puts q.x
      puts q.y
      puts pt.x

      $calls = 0
      def make_point
        $calls += 1
        Point.new(5, 6)
      end

      puts make_point.frozen?
      puts $calls
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      3
      false
      1
    OUT
  end

  it "value type frozen" do
    result = ze0(<<~'RUBY')
      a = Complex(2, 3)
      p a.frozen?
      a.freeze
      p a.frozen?
      r = Rational(1, 2)
      p r.frozen?
      g = (1..3)
      p g.frozen?
      p 5.frozen?
      p :sym.frozen?
      p 1.5.frozen?
      p nil.frozen?
      p true.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      true
      true
    OUT
  end
end
