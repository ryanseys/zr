# frozen_string_literal: true

require "spec_helper"

describe "Classes: frozen literals" do
  it "anonymous class is named in messages" do
    result = zr(<<~'RUBY')
      # A class with no name shows as #<Class:0x...> wherever a message names
      # it: a missing method, inspect, a frozen object, a failed comparison.
      def show(label)
        answer = begin
          yield
        rescue => e
          "#{e.class}: #{e.message}"
        end
        puts "#{label}: #{answer.to_s.gsub(/0x\h+/, "0xXX")}"
      end

      anon = Class.new
      show("missing method") { anon.new.foo }
      show("inspect") { anon.new.inspect }
      show("to_s") { anon.new.to_s }
      show("ivars") { anon.new.tap { _1.instance_variable_set(:@a, 1) }.inspect }
      show("frozen") { anon.new.freeze.instance_variable_set(:@a, 1) }
      show("comparison") { 1 < anon.new }
      show("class") { anon.inspect }
      show("subclass") { Class.new(anon).new.inspect }
      show("error class") { raise Class.new(StandardError) }
      show("error to_s") { Class.new(StandardError).new.to_s }
      show("anonymous module") { Module.new.foo }
    RUBY

    _(result).must_answer <<~'OUT'
      missing method: NoMethodError: undefined method 'foo' for an instance of #<Class:0xXX>
      inspect: #<#<Class:0xXX>:0xXX>
      to_s: #<#<Class:0xXX>:0xXX>
      ivars: #<#<Class:0xXX>:0xXX @a=1>
      frozen: FrozenError: can't modify frozen #<Class:0xXX>: #<#<Class:0xXX>:0xXX>
      comparison: ArgumentError: comparison of Integer with #<Class:0xXX> failed
      class: #<Class:0xXX>
      subclass: #<#<Class:0xXX>:0xXX>
      error class: #<Class:0xXX>: #<Class:0xXX>
      error to_s: #<Class:0xXX>
      anonymous module: NoMethodError: undefined method 'foo' for module #<Module:0xXX>
    OUT
  end

  it "a class naming one the runtime carries reopens it, and the native half is still there" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A `class` or `module` naming one the runtime always carries REOPENS it.
      # The id is the backend's, so no row is minted beside it: the body runs
      # as a `class_eval` on the constant, and its `def`s install where they
      # stand.

      class Object
        def tagged = :tagged
      end

      class String
        def twice = self * 2
      end

      class Hash
        def shout = "#{size} pairs!"
      end

      module Enumerable
        def second = to_a[1]
      end

      class Integer
        def double = self * 2
      end

      p 1.tagged, :s.tagged
      p "ab".twice
      p({ a: 1 }.shout)
      p [1, 2, 3].second
      p 21.double

      # The reopen adds to the class; the native half is still there.
      p "ab".upcase, [1, 2].sum, ({ a: 1 }).keys

      # A `def` the reopen writes is a real method row on the builtin.
      p String.instance_method(:twice).owner
      p String.method_defined?(:twice)

      # A class written in a scope the RUNTIME owns takes the scope as it is
      # spelled, which is the fully-qualified name `Class.name` answers.
      require "digest"

      class Digest::Extra
        def go = :extra
      end

      p Digest::Extra.new.go
      p Digest::Extra.name

      # A `class << obj` body reaches the object's singleton class, so a macro
      # written there names one of its methods.
      module Registry
        class << self
          attr_accessor :tags
          alias labels tags
        end
      end

      Registry.tags = { a: 1 }
      p Registry.tags, Registry.labels
    RUBY

    _(result).must_answer <<~'OUT'
      :tagged
      :tagged
      "abab"
      "1 pairs!"
      2
      42
      "AB"
      3
      [:a]
      String
      true
      :extra
      "Digest::Extra"
      {a: 1}
      {a: 1}
    OUT
  end

  it "class macros" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # The `Module` verbs a class body calls to change what the class is.
      # zr answers `module_function` at compile time, because the rows it
      # writes exist before the body runs; the rest are ordinary sends to the
      # class the body is opening.

      module Sums
        module_function

        def double(n) = n * 2

        def quadruple(n) = double(double(n))
      end

      p Sums.double(3), Sums.quadruple(3)
      p Sums.singleton_methods.sort
      p Sums.private_instance_methods(false).sort

      # The mixin half: an includer gets the same methods, privately.
      class Adder
        include Sums

        def twice(n) = double(n)
      end

      p Adder.new.twice(5)

      begin
        Adder.new.double(1)
      rescue NoMethodError => e
        p e.message
      end

      # The positional form names `def`s already written above it, and answers
      # the names it took.
      module Mixed
        def kept = :kept
        def moved = :moved
        def also = :also

        module_function :moved
        module_function :also, :kept
      end

      p Mixed.moved, Mixed.also, Mixed.kept
      p Mixed.public_instance_methods(false)

      # `private_class_method` and its twin retag a class method where they
      # stand.
      class Vault
        def self.open = :open

        def self.combination = :s3cret
        private_class_method :combination

        def self.peek = combination
      end

      p Vault.open, Vault.peek

      begin
        Vault.combination
      rescue NoMethodError => e
        p e.message
      end

      p Vault.singleton_class.private_instance_methods(false)
      p Vault.private_instance_methods(false)

      class Vault
        public_class_method :combination
      end
      p Vault.combination

      # `define_method` installs a block as a method, and the block still
      # reads the names around it.
      class Greeter
        %w[morning evening].each do |part|
          define_method("good_#{part}") { "good #{part}" }
        end

        define_method(:shape) { |a, b = 2, *rest| [a, b, rest] }
      end

      p Greeter.new.good_morning, Greeter.new.good_evening
      p Greeter.new.shape(1), Greeter.new.shape(1, 5, 6)
      p Greeter.instance_method(:shape).parameters
      p Greeter.instance_methods(false).sort

      # The rest are plain sends: the runtime does the work, at the position
      # the statement stands.
      class Trimmed
        def gone = :gone
        def kept = :kept
        remove_method :gone
        const_set(:LIMIT, 7)
      end

      p Trimmed.new.kept, Trimmed::LIMIT

      begin
        Trimmed.new.gone
      rescue NoMethodError => e
        p e.message
      end

      class Base
        def shadowed = :base
      end

      class Blank < Base
        undef_method :shadowed
      end

      p Base.new.shadowed

      begin
        Blank.new.shadowed
      rescue NoMethodError => e
        p e.message
      end

      # `class_eval` and `instance_eval` take a block, whose `def` lands on
      # whatever the receiver opens.
      class Late
        def already = :already
      end

      Late.class_eval do
        def added = :added
        def reaches = already
      end

      p Late.new.added, Late.new.reaches

      one = Object.new
      one.instance_eval do
        @held = 9

        def mine = :mine
      end

      p one.mine, one.singleton_methods, one.instance_variable_get(:@held)
      p [1, 2, 3].instance_eval { size }
    RUBY

    _(result).must_answer <<~'OUT'
      6
      12
      [:double, :quadruple]
      [:double, :quadruple]
      10
      "private method 'double' called for an instance of Adder"
      :moved
      :also
      :kept
      []
      :open
      :s3cret
      "private method 'combination' called for class Vault"
      [:combination]
      []
      :s3cret
      "good morning"
      "good evening"
      [1, 2, []]
      [1, 5, [6]]
      [[:req, :a], [:opt, :b], [:rest, :rest]]
      [:good_evening, :good_morning, :shape]
      :kept
      7
      "undefined method 'gone' for an instance of Trimmed"
      :base
      "undefined method 'shadowed' for an instance of Blank"
      :added
      :already
      :mine
      [:mine]
      9
      3
    OUT
  end

  it "class reveal" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A class row registers its shape before the first statement runs, so
      # the MRO is static, but ruby makes the CONSTANT where the `class`
      # statement stands. Until then the name is a NameError.

      p defined?(Later)

      class Later
        def go = :later
      end

      p defined?(Later)
      p Later.new.go

      # A nested name appears when the body that writes it runs, not when the
      # enclosing class does.
      module Outer
        p defined?(Inner)
        class Inner
          def go = :inner
        end
        p defined?(Inner)
      end
      p Outer::Inner.new.go

      # A subclass names its superclass at the statement, so the order the
      # file writes them is the order they appear.
      class Parent; end
      class Child < Parent; end
      p Child.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "constant"
      :later
      nil
      "constant"
      :inner
      Parent
    OUT
  end

  it "method_added fires at the definition's own position, on a half-built class" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # ruby announces every definition to the class it landed on, at the
      # definition's own position. zr installs a declared `def` before the
      # program runs, so the announcement is made where the statement stands
      # instead -- through a probe, which is one atomic load when nothing
      # hooks it.

      class Watched
        def self.method_added(name) = puts("added #{name}")

        def one = 1
        def two = 2
      end

      # A reopen announces to the same hook.
      class Watched
        def three = 3
      end

      # The hook sees a HALF-built class: the methods below the definition are
      # still in the future.
      class Ordered
        def self.method_added(name)
          puts "#{name} sees #{instance_methods(false).sort.inspect}"
        end

        def a = 1
        def b = 2
        def c = 3
      end

      # A `def self.x` announces through the singleton hook instead.
      class Singly
        def self.singleton_method_added(name) = puts("singleton #{name}")

        def self.made = :made
        def plain = :plain
      end

      # The other two definition hooks a class body can carry.
      module Mixin
        def self.included(base) = puts("included in #{base}")
        def self.extended(base) = puts("extended #{base.class}")
      end

      class User
        include Mixin
      end

      Object.new.extend(Mixin)

      class Parent
        def self.inherited(child) = puts("inherited by #{child}")
      end

      class Child < Parent; end

      p Watched.instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT'
      added one
      added two
      added three
      a sees [:a]
      b sees [:a, :b]
      c sees [:a, :b, :c]
      singleton singleton_method_added
      singleton made
      included in User
      extended Object
      inherited by Child
      [:one, :three, :two]
    OUT
  end

  it "definition type errors" do
    result = zr(<<~'RUBY', path: "zr/definition_type_errors.rb")
      # frozen_string_literal: true

      # A definition ruby RAISES on is a definition that runs and raises, not a
      # program that cannot be compiled: the statement lowers to the `TypeError`
      # in its place, a `rescue` around it catches it, and the class stays
      # exactly as it was. Both message lines are ruby's, and the second names
      # where the CONSTANT was made -- the first declaring statement, so a
      # reopen leaves it standing.

      class Parent; end
      class Other; end

      class Bare; end
      begin
        class Bare < Parent; end
      rescue TypeError => e
        p [e.class, e.message]
      end
      p Bare.superclass.to_s

      # Restating the same parent is fine, and a bare reopen agrees with it by
      # saying nothing.
      class Kid < Parent
        def a = 1
      end
      class Kid < Parent
        def b = 2
      end
      class Kid
        def c = 3
      end
      k = Kid.new
      p [k.a, k.b, k.c, Kid.superclass.to_s]

      begin
        class Kid < Other; end
      rescue TypeError => e
        p e.message
      end

      # The KIND has to agree too, in both directions, and ruby names the LEAF.
      module Outer; end
      class Outer::Inner; end
      begin
        module Outer::Inner; end
      rescue TypeError => e
        p e.message
      end

      module Mixin
        def m = :m
      end
      begin
        class Mixin; end
      rescue TypeError => e
        p e.message
      end
      p Mixin.instance_of?(Module)

      # A builtin's kind and its parent are the runtime's, so both guards are
      # asked where the statement stands: a reopen may restate the real parent
      # and may not invent one.
      class String < Object
        def shout = upcase + "!"
      end
      p "hi".shout

      begin
        class String < Parent; end
      rescue TypeError => e
        p e.message
      end

      # `module String` is the same guard on the kind, and it is
      # `test/lang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb` that
      # holds it: ruby has no source location for a builtin, so the second line
      # is empty, and a program that ALSO reopens the class disagrees there.

      # The native exception hierarchy reopens the same way.
      class StandardError
        def tag = "[#{self.class.name}]"
      end

      begin
        raise ArgumentError, "bad"
      rescue => e
        p [e.tag, e.message]
      end

      begin
        module Comparable; end
      rescue TypeError => e
        p e.message
      end
      p Comparable.instance_of?(Module)
    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "superclass mismatch for class Bare"]
      "Object"
      [1, 2, 3, "Parent"]
      "superclass mismatch for class Kid"
      "Inner is not a module\nzr/definition_type_errors.rb:43: previous definition of Inner was here"
      "Mixin is not a class\nzr/definition_type_errors.rb:50: previous definition of Mixin was here"
      true
      "HI!"
      "superclass mismatch for class String"
      ["[ArgumentError]", "bad"]
      true
    OUT
  end

  it "frozen class or object refuses every change" do
    result = zr(<<~'RUBY')
      def try = (yield; :ok) rescue [$!.class, $!.message.sub(/0x\h+/, "0x")]

      o = Object.new.freeze
      p try { def o.x = 1 }
      p try { o.singleton_class.define_method(:y) { 1 } }
      p o.singleton_class.frozen?

      q = Object.new
      q.singleton_class
      q.freeze
      p q.singleton_class.frozen?, try { def q.z = 1 }

      class Foo; prepend Comparable; end
      Foo.freeze
      p try { class Foo; def x; end; end }
      p try { Foo.define_method(:z) { } }
      p try { Foo.send(:private, :to_s) }
      p try { Foo.send(:remove_method, :nope) }

      Fz = Class.new.freeze
      p Fz.singleton_class.frozen?
      p try { Fz::X = 1 }
      p try { Fz.const_set(:Y, 1) }
      p try { Fz.class_variable_set(:@@a, 1) }
      p try { Fz.send(:remove_const, :Nope) }
      p try { Fz.remove_class_variable(:@@nope) }

      class Fr; @@a = 1; end
      Fr.freeze
      p try { class Fr; @@a = 2; end }
      p Fr.class_variable_get(:@@a)

    RUBY

    _(result).must_answer <<~'OUT'
      [FrozenError, "can't modify frozen Object: #<Object:0x>"]
      [FrozenError, "can't modify frozen Object: #<Object:0x>"]
      true
      true
      [FrozenError, "can't modify frozen Object: #<Object:0x>"]
      [FrozenError, "can't modify frozen Class: Foo"]
      [FrozenError, "can't modify frozen Class: Foo"]
      [FrozenError, "can't modify frozen Class: Foo"]
      [FrozenError, "can't modify frozen Class: Foo"]
      true
      [FrozenError, "can't modify frozen Class: Fz"]
      [FrozenError, "can't modify frozen Class: Fz"]
      [FrozenError, "can't modify frozen Class: Fz"]
      [FrozenError, "can't modify frozen Class: Fz"]
      [FrozenError, "can't modify frozen Class: Fz"]
      [FrozenError, "can't modify frozen Class: Fr"]
      1
    OUT
  end

  it "frozen class refuses every definition verb" do
    result = zr(<<~'RUBY')
      # Every verb that would change a frozen class or module says so, and
      # `Regexp.allocate` answers an object with no pattern that names itself
      # at the first read.
      def err(label)
        print label, ": "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      class Fz
        def a = 1
      end
      Fz.freeze

      err("alias_method") { Fz.send(:alias_method, :b, :a) }
      err("undef_method") { Fz.send(:undef_method, :a) }
      err("remove_method") { Fz.send(:remove_method, :a) }
      err("private") { Fz.send(:private, :a) }
      err("public") { Fz.send(:public, :a) }
      err("protected") { Fz.send(:protected, :a) }
      err("define_method") { Fz.send(:define_method, :c) { 1 } }
      err("attr_accessor") { Fz.send(:attr_accessor, :d) }
      err("include") { Fz.include(Comparable) }
      err("prepend") { Fz.prepend(Comparable) }
      err("extend") { Fz.extend(Comparable) }
      err("const_set") { Fz.const_set(:K, 1) }
      err("private_constant") { Fz.send(:private_constant) }
      err("class_eval") { Fz.class_eval { def z = 1 } }
      err("ivar_set") { Fz.instance_variable_set(:@x, 1) }
      p Fz.new.a

      r = Regexp.allocate
      err("source") { r.source }
      err("options") { r.options }
      err("to_s") { r.to_s }
      err("names") { r.names }
      err("match") { r.match("a") }
      err("=~") { r =~ "a" }
      err("==") { r == // }
      p [r.frozen?, r.encoding, r.fixed_encoding?]
      err("MatchData.allocate") { MatchData.allocate }
      err("MatchData.new") { MatchData.new }
    RUBY

    _(result).must_answer <<~'OUT'
      alias_method: FrozenError: can't modify frozen Class: Fz
      undef_method: FrozenError: can't modify frozen Class: Fz
      remove_method: FrozenError: can't modify frozen Class: Fz
      private: FrozenError: can't modify frozen Class: Fz
      public: FrozenError: can't modify frozen Class: Fz
      protected: FrozenError: can't modify frozen Class: Fz
      define_method: FrozenError: can't modify frozen Class: Fz
      attr_accessor: FrozenError: can't modify frozen Class: Fz
      include: FrozenError: can't modify frozen Class: Fz
      prepend: FrozenError: can't modify frozen Class: Fz
      extend: FrozenError: can't modify frozen Class: Fz
      const_set: FrozenError: can't modify frozen Class: Fz
      private_constant: FrozenError: can't modify frozen Class: Fz
      class_eval: FrozenError: can't modify frozen Class: Fz
      ivar_set: FrozenError: can't modify frozen Class: Fz
      1
      source: TypeError: uninitialized Regexp
      options: TypeError: uninitialized Regexp
      to_s: TypeError: uninitialized Regexp
      names: TypeError: uninitialized Regexp
      match: TypeError: uninitialized Regexp
      =~: TypeError: uninitialized Regexp
      ==: TypeError: uninitialized Regexp
      [false, #<Encoding:BINARY (ASCII-8BIT)>, false]
      MatchData.allocate: NoMethodError: undefined method 'allocate' for class MatchData
      MatchData.new: NoMethodError: undefined method 'new' for class MatchData
    OUT
  end

  it "initialize containers" do
    result = zr(<<~'RUBY')
      # The container initialize family, in place -- oracle-pinned semantics
      # including the corners: Hash#initialize touches ONLY the default channel,
      # Set#initialize merges without a frozen check (a 4.0 CoreSet quirk).
      def err(label)
        yield
        puts "#{label}: no error"
      rescue => e
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # ---- Array
      a = [1, 2, 3]
      p a.send(:initialize, 2, 0).equal?(a)
      p a
      a.send(:initialize, 3) { |i| i * 2 }
      p a
      a.send(:initialize, 2)
      p a
      a.send(:initialize)
      p a
      b = [1]
      b.send(:initialize, [7, 8])
      p b
      err("ary frozen") { [1].freeze.send(:initialize, 2, 0) }
      c = [1]
      p c.send(:initialize_copy, [7, 8]).equal?(c)
      p c
      err("ary icopy type") { [1].send(:initialize_copy, "x") }

      # ---- Hash
      h = { a: 1 }
      p h.send(:initialize, 9).equal?(h)
      p [h, h[:missing]]
      h2 = { a: 1 }
      h2.send(:initialize) { |_, k| k.to_s }
      p [h2, h2[:zz]]
      err("hash frozen") { {}.freeze.send(:initialize) }
      h3 = { a: 1 }
      h3.send(:initialize_copy, { b: 2 })
      p h3
      h4 = {}
      h4.send(:initialize_copy, Hash.new(5))
      p h4[:zz]

      # ---- String
      s = +"abc"
      p s.send(:initialize, "xyz").equal?(s)
      p s
      s.send(:initialize)
      p s
      s.send(:initialize, "q", encoding: "ASCII-8BIT")
      p [s, s.encoding.name]
      s2 = +"abc"
      s2.send(:initialize, capacity: 100)
      p s2
      err("str frozen") { "abc".freeze.send(:initialize, "x") }
      s3 = +"a"
      s3.send(:initialize_copy, "zz")
      p s3

      # ---- Set (merges; skips the frozen check)
      st = Set[1, 2]
      st.send(:initialize, [7, 8])
      p st
      st2 = Set[1]
      st2.send(:initialize, [1, 2]) { |x| x * 10 }
      p st2
      fr = Set[1].freeze
      fr.send(:initialize, [2])
      p fr
      st3 = Set[1]
      st3.send(:initialize_copy, Set[9])
      p st3

      # Ownership: every row sits on its own class.
      %w[Array Hash String Set].each do |k|
        c = Object.const_get(k)
        print c.instance_method(:initialize).owner, " "
        puts c.instance_method(:initialize_copy).owner
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      [0, 0]
      [0, 2, 4]
      [nil, nil]
      []
      [7, 8]
      ary frozen: FrozenError: can't modify frozen Array: [1]
      true
      [7, 8]
      ary icopy type: TypeError: no implicit conversion of String into Array
      true
      [{a: 1}, 9]
      [{a: 1}, "zz"]
      hash frozen: FrozenError: can't modify frozen Hash: {}
      {b: 2}
      5
      true
      "xyz"
      "xyz"
      ["q", "ASCII-8BIT"]
      ""
      str frozen: FrozenError: can't modify frozen String: "abc"
      "zz"
      Set[1, 2, 7, 8]
      Set[1, 10, 20]
      Set[1, 2]
      Set[9]
      Array Array
      Hash Hash
      String String
      Set Set
    OUT
  end

  it "initialize handles" do
    result = zr(<<~'RUBY')
      # The mutable-handle initialize family: re-init genuinely re-seats the
      # receiver (Pathname/Dir/Enumerator family/File::Stat), oracle-pinned.
      def err(label)
        yield
        puts "#{label}: no error"
      rescue => e
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # ---- Pathname
      p1 = Pathname.new("/a")
      p1.send(:initialize, "/b")
      p p1.to_s
      p1.send(:initialize, Pathname.new("/c"))
      p p1.to_s
      err("pathname frozen") { Pathname.new("/a").freeze.send(:initialize, "/b") }
      err("pathname nul") { Pathname.new("/a").send(:initialize, "b\0c") }

      # ---- Dir
      d = Dir.new(".")
      d.send(:initialize, "/")
      p d.path
      p d.entries.include?("..")

      # ---- Enumerator family
      e = [1].each
      p e.send(:initialize) { |y| y << 5 }.equal?(e)
      p e.first(1)
      err("enum blockless") { [1].each.send(:initialize) }
      e2 = [1].each
      e2.send(:initialize_copy, [7, 8].each)
      p e2.to_a

      c = [1].each + [2].each
      c.send(:initialize, [9].each)
      p c.to_a
      c.send(:initialize_copy, [4].each + [5].each)
      p c.to_a

      g = Enumerator::Generator.new { |y| y << 1 }
      g.send(:initialize) { |y| y << 2 }
      p g.each { |v| break v }
      g2 = Enumerator::Generator.new { |y| y << 3 }
      g.send(:initialize_copy, g2)
      p g.each { |v| break v }

      pr = Enumerator.product([1])
      pr.send(:initialize, [7], [8])
      p pr.to_a
      pr.send(:initialize_copy, Enumerator.product([5], [6]))
      p pr.to_a

      lz = [1].lazy
      lz.send(:initialize, [2, 3]) { |y, v| y << v }
      p lz.first(1)
      err("lazy blockless") { [1].lazy.send(:initialize, [2]) }

      # ---- File: every open handle refuses re-init.
      f = File.open("/dev/null")
      err("file reinit") { f.send(:initialize, "/dev/zero") }
      f.close

      # ---- File::Stat
      st = File.stat(".")
      st2 = File.stat("..")
      st.send(:initialize_copy, st2)
      p st.directory?
      p File::Stat.instance_method(:initialize).arity

      # Ownership.
      p [Pathname, Dir, Enumerator, Enumerator::Chain, Enumerator::Generator,
         Enumerator::Product, Enumerator::Lazy, File::Stat, IO, File]
        .map { |c| c.instance_method(:initialize).owner }
      p [Enumerator, Enumerator::Chain, Enumerator::Generator, Enumerator::Product,
         File::Stat, IO].map { |c| c.instance_method(:initialize_copy).owner }
    RUBY

    _(result).must_answer <<~'OUT'
      "/b"
      "/c"
      pathname frozen: FrozenError: can't modify frozen Pathname: #<Pathname:/a>
      pathname nul: ArgumentError: path name contains null byte
      "/"
      true
      true
      [5]
      enum blockless: ArgumentError: tried to create Proc object without a block
      [7, 8]
      [9]
      [4, 5]
      2
      3
      [[7, 8]]
      [[5, 6]]
      [2]
      lazy blockless: ArgumentError: tried to call lazy new without a block
      file reinit: RuntimeError: reinitializing File
      true
      1
      [Pathname, Dir, Enumerator, Enumerator::Chain, Enumerator::Generator, Enumerator::Product, Enumerator::Lazy, File::Stat, IO, File]
      [Enumerator, Enumerator::Chain, Enumerator::Generator, Enumerator::Product, File::Stat, IO]
    OUT
  end

  it "initialize value types" do
    result = zr(<<~'RUBY')
      # The value-type and sync-primitive initialize family: for types frozen or
      # one-shot by construction, CRuby's refusals ARE the semantics.
      def err(label)
        yield
        puts "#{label}: no error"
      rescue => e
        puts "#{label}: #{e.class}: #{e.message}"
      end

      err("range reinit")   { (1..2).send(:initialize, 3, 4) }
      err("range icopy")    { (1..2).send(:initialize_copy, (2..9)) }
      err("regexp reinit")  { /x/.send(:initialize, "y") }
      err("regexp icopy")   { /x/.send(:initialize_copy, /y/) }
      err("time reinit")    { Time.now.send(:initialize) }
      err("time icopy")     { Time.now.send(:initialize_copy, Time.now) }
      err("class reinit")   { String.send(:initialize) }
      err("class anon")     { Class.new.send(:initialize) }
      err("conv reinit")    { Encoding::Converter.new("UTF-8", "EUC-JP").send(:initialize, "a", "b") }
      err("fiber reinit")   { Fiber.new { 1 }.send(:initialize) { 2 } }
      err("md icopy type")  { "ab".match(/a/).send(:initialize_copy, 3) }

      t = Thread.new { 1 }
      t.join
      begin
        t.send(:initialize) { 2 }
      rescue ThreadError => e
        puts "thread reinit: #{e.class}: #{e.message.split(" - ").first}"
      end

      # Struct: slot copy between same-class instances only.
      S1 = Struct.new(:a, :b)
      s = S1.new(1, 2)
      p s.send(:initialize_copy, S1.new(8, 9)).equal?(s)
      p s
      err("struct icopy class") { S1.new(1, 2).send(:initialize_copy, Struct.new(:x).new(5)) }

      # Data: frozen by construction, so the hook can only refuse.
      D1 = Data.define(:a)
      err("data icopy") { D1.new(a: 1).send(:initialize_copy, D1.new(a: 9)) }

      # Module: re-runs the body block on ANY module, answers nil.
      m = Module.new
      p m.send(:initialize) { def hi = 1 }
      p m.instance_methods(false)
      p Module.new.send(:initialize)
      mc = Module.new
      p mc.clone.send(:initialize_clone, mc).class

      # Sync primitives: permitted no-op / clear / rebound.
      mx = Mutex.new
      p mx.send(:initialize)
      p Mutex.new.freeze.send(:initialize)
      q = Queue.new
      q << 1
      q.send(:initialize)
      p q.size
      sq = SizedQueue.new(3)
      sq.send(:initialize, 5)
      p sq.max
      p ConditionVariable.new.send(:initialize)

      # Random: full-state copy resumes the same stream.
      r = Random.new(1)
      r.send(:initialize_copy, Random.new(2))
      p r.rand(100) == Random.new(2).rand(100)

      # Ownership rows.
      p [Range, Regexp, Time, Class, Module].map { |c| c.instance_method(:initialize).owner }
      p [Range, Regexp, Time, MatchData, Struct, Data].map { |c| c.instance_method(:initialize_copy).owner }
      p Module.instance_method(:initialize_clone).owner
    RUBY

    _(result).must_answer <<~'OUT'
      range reinit: FrozenError: can't modify frozen Range: 1..2
      range icopy: FrozenError: can't modify frozen Range: 1..2
      regexp reinit: FrozenError: can't modify frozen Regexp: /x/
      regexp icopy: FrozenError: can't modify frozen Regexp: /x/
      time reinit: TypeError: already initialized Time
      time icopy: TypeError: already initialized Time
      class reinit: TypeError: already initialized class
      class anon: TypeError: already initialized class
      conv reinit: TypeError: already initialized
      fiber reinit: RuntimeError: cannot initialize twice
      md icopy type: TypeError: initialize_copy should take same class object
      thread reinit: ThreadError: already initialized thread
      true
      #<struct S1 a=8, b=9>
      struct icopy class: TypeError: initialize_copy should take same class object
      data icopy: FrozenError: can't modify frozen D1: #<data D1 a=1>
      nil
      [:hi]
      nil
      Module
      nil
      nil
      0
      5
      nil
      true
      [Range, Regexp, Time, Class, Module]
      [Range, Regexp, Time, MatchData, Struct, Data]
      Module
    OUT
  end

  it "reopened builtins win" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # Integer arithmetic and comparison take an inline fast path, and `puts`
      # folds to the runtime's own writer. A user definition has to be able to
      # take either of them back: a reopen that redefines an operator anywhere
      # on Integer's fast-path MRO stands the whole fast path down, and any
      # `puts` this program defines stands the fold down.

      class Integer
        def +(other) = "int-plus(#{other})"
      end

      p 1 + 2
      p 1 - 2
      p 1 < 2

      module Comparable
        def <=>(other) = :spaceship
      end

      p(3 <=> 4)
      p 5 == 5

      class Logger
        def puts(msg) = "logged: #{msg}"

        def run = puts("hi")
      end

      p Logger.new.run

      module Kernel
        def puts(*a) = $stdout.write("K:#{a.join(",")}\n")
      end

      puts "a", "b"
    RUBY

    _(result).must_answer <<~'OUT'
      "int-plus(2)"
      -1
      true
      -1
      true
      "logged: hi"
      K:a,b
    OUT
  end

  it "runtime class bodies" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # A class made at run time has no row, so nothing written in its body can
      # be keyed by a compile-time id: a constant, a nested class, a class
      # variable and the reads of each go through the class VALUE instead.
      # `self` IS that class inside the body; a `def` reaches it through the
      # constant that names it, which is bound by the time any method can run.

      def base = Object

      class Foo < base
        VAL = 7

        include Comparable

        class Inner
          def deep = "deep"
        end

        @@count = 0

        def initialize = @@count += 1
        def a = VAL
        def use_inner = Inner.new.deep
        def self.count = @@count
      end

      p Foo::VAL
      p Foo.new.a
      p Foo.new.use_inner
      p Foo::Inner.new.deep
      p Foo.count
      p Foo.ancestors.take(3)

      # `< self` from inside a subclass body names THAT subclass, all the way
      # down, and each nested class belongs to the class the body is building.
      class Base
        def kind = :base

        class Middle < self
          def kind = :middle

          class Leaf < self
            def kind = :leaf
          end
        end
      end

      p Base::Middle::Leaf.ancestors.take(3)
      p [Base.new.kind, Base::Middle.new.kind, Base::Middle::Leaf.new.kind]

      # A NAMESPACE the run time decides: `class self::Task` writes onto
      # whichever object `self` is, so no scope this compile can name is
      # involved at all.
      module Holder
        def self.build(&blk) = class_eval(&blk)
      end

      Holder.build do
        class self::Task
          def run = "ran"
        end

        module self::Helpers
          def self.tag = :helper
        end

        class self::Timed < self::Task
          def run = "timed " + super
        end
      end
      p Holder::Task.new.run
      p Holder::Helpers.tag
      p Holder::Timed.new.run
      p Holder::Timed.superclass == Holder::Task

      # A reopened builtin is the same shape: its row is the runtime's, so the
      # body's constants and class variables take the same road.
      class Array
        LIMIT = 3
        @@made = 0

        def self.note = @@made += 1
        def capped = size > LIMIT ? LIMIT : size
      end

      p Array::LIMIT
      p [1, 2, 3, 4].capped
      p Array.note
      p defined?(Array::LIMIT)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      7
      "deep"
      "deep"
      2
      [Foo, Comparable, Object]
      [Base::Middle::Leaf, Base::Middle, Base]
      [:base, :middle, :leaf]
      "ran"
      :helper
      "timed ran"
      true
      3
      3
      1
      "constant"
    OUT
  end

  it "runtime defs" do
    result = zr(<<~'RUBY', path: "zr/runtime_defs.rb")
      # frozen_string_literal: true

      # A `def` the declaration pass does not reach has no row: which class it
      # lands on is not known until the statement runs. The body becomes a
      # lambda-shaped Proc and the runtime installs it on the definee that is
      # open, exactly as the interpreter resolves one.

      M = Module.new do
        def greet = "hi"

        def twice(n) = n * 2

        def each_twice
          yield 1
          yield 2
        end

        def kw(a, *rest, b: 2, &blk) = [a, b, rest, blk.nil?]

        def early(n)
          return :small if n < 3

          :big
        end

        def counted
          total = 0
          [1, 2, 3].each { |n| total += n }
          total
        end

        def boom = raise(ArgumentError, "from a runtime def")

        private

        def hidden = :hidden
      end

      o = Object.new
      o.extend(M)
      p o.greet, o.twice(3), o.early(1), o.early(9), o.counted
      p M.instance_methods(false).sort
      p M.private_instance_methods(false).sort
      p M.instance_method(:kw).parameters
      p M.instance_method(:kw).arity
      p M.instance_method(:greet).owner == M

      out = []
      o.each_twice { |n| out << n }
      p out
      p o.kw(1)
      p o.kw(1, 5, b: 9)

      begin
        o.kw
      rescue ArgumentError => e
        p e.message
      end

      begin
        o.boom
      rescue ArgumentError => e
        p e.message, e.backtrace.first
      end

      # A method body is its own scope: the name around it is invisible.
      outside = 41

      N = Module.new do
        def sees_nothing
          outside
        rescue NameError => e
          e.class.name
        end
      end

      p outside
      p Object.new.extend(N).sees_nothing

      # `Class.new` opens a class definee, so an `initialize` written here is
      # the new class's, private as ruby makes every `initialize`.
      C = Class.new do
        def initialize(v)
          @v = v
        end

        def value = @v
      end

      p C.new(7).value
      p C.instance_methods(false).sort
      p C.private_instance_methods(false).sort

      # An `if` is a statement like any other, so the `def` inside one is
      # installed when the branch runs -- on Object at the top level, privately,
      # and on the class inside a class body.
      if true
        def gated = "gated"
      end
      p gated, self.class.private_method_defined?(:gated)

      class Host
        if true
          def inner = "inner"
        end
      end
      p Host.new.inner
      p Host.private_method_defined?(:inner), Host.public_method_defined?(:inner)

      # A `def` inside a `def` installs on the same class, when the outer one
      # runs and not before.
      class Outer
        def make
          def made = "made"
          :ok
        end
      end
      p Outer.method_defined?(:made)
      p Outer.new.make, Outer.new.made
    RUBY

    _(result).must_answer <<~'OUT'
      "hi"
      6
      :small
      :big
      6
      [:boom, :counted, :each_twice, :early, :greet, :kw, :twice]
      [:hidden]
      [[:req, :a], [:rest, :rest], [:key, :b], [:block, :blk]]
      -2
      true
      [1, 2]
      [1, 2, [], true]
      [1, 9, [5], true]
      "wrong number of arguments (given 0, expected 1+)"
      "from a runtime def"
      "zr/runtime_defs.rb:32:in 'M#boom'"
      41
      "NameError"
      7
      [:value]
      [:initialize]
      "gated"
      true
      "inner"
      false
      true
      false
      :ok
      "made"
    OUT
  end

  it "runtime superclass" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `class Foo < <expr>` mints its class while the program runs, so no row
      # can carry it: the name is an ordinary constant holding what
      # `Class.new` answers, and the body's `def`s install where they stand.

      base = Struct.new(:a, :b)

      class Pair < base
        def sum = a + b
      end

      p Pair.new(1, 2).sum
      p Pair.name
      p Pair.superclass == base
      p Pair.ancestors.include?(Struct)

      # A superclass NAME the program assigns is the same thing: only the run
      # time knows what it holds.
      Parent = Class.new do
        def hi = :hi
      end

      class Kid < Parent
        def kid = :kid
      end

      p Kid.new.hi, Kid.new.kid, Kid.name, Kid.superclass == Parent

      # Nested, and the constant is what names the class.
      module Wrap
        Inner = Class.new

        class Deep < Inner
          def go = :deep
        end
      end

      p Wrap::Deep.new.go, Wrap::Deep.name

      # The hook fires, because `Class.new` fires it -- but during the mint,
      # where ruby fires it after the constant has named the class, so the
      # child is still anonymous there. `zr build` desugars the same way and
      # answers the same.
      Watcher = Class.new do
        def self.inherited(child) = puts("inherited: #{child.equal?(child)}")
      end

      class Seen < Watcher; end

      p Seen.superclass == Watcher, Seen.name

      # A later statement REOPENS what the first one made: there is still no
      # row to put the body's `def`s in, so the body runs on the constant.
      class Kid
        def second = :second
      end

      p Kid.new.kid, Kid.new.second

      # A `rescue` binds into a class variable or a scoped constant as
      # readily as into a local.
      class Holder
        @@last = nil

        def self.run
          raise "held"
        rescue => @@last
          @@last.message
        end
      end

      p Holder.run

      # A subclass of a class made at run time is made at run time too: its
      # parent has no row, so neither can it, however ordinary the `class`
      # statement looks.
      class Grand < Kid
        def grand = :grand
      end

      p Grand.new.grand, Grand.new.kid, Grand.superclass == Kid, Grand.name

      # The shape rspec's `FailedExampleNotification` has: a `Struct.new`
      # subclass with its own ivars, subclassed again.
      Row = Struct.new(:value)

      class Tagged < Row
        def initialize(value, tag = "t#{value}")
          @tag = tag
          super(value)
        end

        def show = [@tag, value]
      end

      class Retagged < Tagged
        def show2 = show + [self.class.name]
      end

      p Tagged.new(1).show
      p Retagged.new(2).show2
      p Retagged.new(3).instance_variables
    RUBY

    _(result).must_answer <<~'OUT'
      3
      "Pair"
      true
      true
      :hi
      :kid
      "Kid"
      true
      :deep
      "Wrap::Deep"
      inherited: true
      true
      "Seen"
      :kid
      :second
      "held"
      :grand
      :kid
      true
      "Grand"
      ["t1", 1]
      ["t2", 2, "Retagged"]
      [:@tag]
    OUT
  end

  it "small core classes" do
    result = zr(<<~'RUBY')
      # The small classes zr lacked: `GC::Profiler`, `Thread::Backtrace` (which is
      # what makes the `Location` it namespaces reachable at all), the sibling
      # `ObjectSpace::WeakKeyMap`, the `Random::Base`/`Random::Formatter` rungs
      # under `Random`, `Enumerator::Generator`/`Producer`, and the `Ractor` error
      # tree -- classes only, since zr runs no ractors.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end
      # GC::Profiler
      show("Profiler singleton") { GC::Profiler.singleton_methods(false).sort }
      show("Profiler enabled?") { GC::Profiler.enabled? }
      show("Profiler total_time") { GC::Profiler.total_time }
      show("Profiler result") { GC::Profiler.result }
      show("Profiler raw_data") { GC::Profiler.raw_data }
      show("Profiler clear") { GC::Profiler.clear }
      show("Profiler enable") { GC::Profiler.enable }
      show("Profiler enabled? after") { GC::Profiler.enabled? }
      show("Profiler disable") { GC::Profiler.disable }
      show("Profiler report") { GC::Profiler.report }
      # Thread::Backtrace
      show("Backtrace.limit") { Thread::Backtrace.limit }
      show("Backtrace singleton") { Thread::Backtrace.singleton_methods(false) }
      show("Backtrace constants") { Thread::Backtrace.constants }
      show("Location own") { Thread::Backtrace::Location.instance_methods(false).sort }
      show("caller_locations class") { caller_locations(0, 1).first.class }
      # WeakKeyMap
      show("WKM own") { ObjectSpace::WeakKeyMap.instance_methods(false).sort }
      show("WKM arities") { ObjectSpace::WeakKeyMap.instance_methods(false).sort.map { |n| ObjectSpace::WeakKeyMap.instance_method(n).arity } }
      m = ObjectSpace::WeakKeyMap.new
      k = "a"
      show("WKM set") { m[k] = 1 }
      show("WKM get eq") { m["a".dup] }
      show("WKM getkey") { m.getkey("a".dup).equal?(k) }
      show("WKM key?") { m.key?("a".dup) }
      show("WKM getkey missing") { m.getkey("zz") }
      show("WKM inspect") { m.inspect.sub(/0x\h+/,"0xADDR") }
      show("WKM int key") { m[1] = 1 }
      show("WKM sym key") { m[:s] = 1 }
      show("WKM nil key") { m[nil] = 1 }
      show("WKM float key") { m[1.5] = 1 }
      show("WKM bignum key") { m[2**70] = 1 }
      show("WKM array key") { m[[1]] = 2 }
      show("WKM delete") { m.delete(k) }
      show("WKM delete missing") { m.delete("zz") }
      show("WKM delete block") { m.delete("zz") { |x| [:miss, x] } }
      show("WKM clear") { m.clear.class }
      show("WKM after clear") { m["a"] }
      show("WKM new arity") { ObjectSpace::WeakKeyMap.new(1) }
      show("WKM frozen write") { f = ObjectSpace::WeakKeyMap.new; f.freeze; f["x"] = 1 }
      # Random
      show("Random.superclass") { Random.superclass }
      show("Random ancestors") { Random.ancestors.firsshow(5) }
      show("Random own") { Random.instance_methods(false).sort }
      show("Random::Base own") { Random::Base.instance_methods(false).sort }
      show("Random::Formatter own has rand") { Random::Formatter.instance_methods(false).include?(:rand) }
      show("rand owner") { Random.instance_method(:rand).owner }
      show("random_number owner") { Random.instance_method(:random_number).owner }
      show("Random.new(42).rand class") { Random.new(42).rand.class }
      show("Random.new(42).seed") { Random.new(42).seed }
      show("Random.new(42).bytes") { Random.new(42).bytes(4).bytesize }
      show("Random.new(42).random_number(10) class") { Random.new(42).random_number(10).class }
      # Ractor errors
      [Ractor::Error, Ractor::ClosedError, Ractor::IsolationError, Ractor::MovedError, Ractor::RemoteError, Ractor::UnsafeError].each do |c|
        show("#{c} ancestry") { c.ancestors.take_while { |a| a != Object }.map(&:to_s) }
      end
      show("rescue Ractor::ClosedError") { begin; raise Ractor::ClosedError, "x"; rescue Ractor::ClosedError => e; [e.class, e.message]; end }
      show("Ractor::Error is StandardError") { Ractor::Error.new("y").is_a?(StandardError) }
      show("Ractor constants") { (Ractor.constants & [:Error, :ClosedError, :IsolationError, :MovedError, :RemoteError, :UnsafeError]).sort }

      # `Enumerator::Generator` and `Enumerator::Producer` are the SOURCE objects
      # an enumerator holds, not enumerators: a generator answers `#each` and what
      # `Enumerable` derives from it, and nothing more.
      show("Generator to_a") { Enumerator::Generator.new { |y| y << 1; y << 2 }.to_a }
      show("Generator map") { Enumerator::Generator.new { |y| y << 1; y << 2 }.map { |x| x * 3 } }
      show("Generator ancestors") { Enumerator::Generator.ancestors.first(3) }
      show("Generator own") { Enumerator::Generator.instance_methods(false) }
      show("Generator each arity") { Enumerator::Generator.instance_method(:each).arity }
      show("Generator inspect") { Enumerator::Generator.new {}.inspect.sub(/0x\h+/, "0xADDR") }
      show("Generator no block") { Enumerator::Generator.new }
      show("Producer own") { Enumerator::Producer.instance_methods(false) }
      show("Producer each arity") { Enumerator::Producer.instance_method(:each).arity }
      show("Enumerator.new inspect") { Enumerator.new { |y| y << 1 }.inspect.sub(/0x\h+/, "0xADDR") }
      show("Enumerator.new to_a") { Enumerator.new { |y| y << 1; y << 2 }.to_a }
      show("Enumerator.new next") do
        e = Enumerator.new { |y| y << 1; y << 2 }
        [e.next, e.next]
      end
      show("Enumerator.new size") { Enumerator.new(3) { |y| y << 1 }.size }
      show("Enumerator.new size proc") { Enumerator.new(-> { 7 }) { |y| y << 1 }.size }
      show("produce class") { Enumerator.produce(1) { |x| x + 1 }.class }
      show("produce first") { Enumerator.produce(1) { |x| x + 1 }.first(3) }
      show("produce size") { Enumerator.produce(1) { |x| x + 1 }.size }
      show("produce inspect") { Enumerator.produce(1) { |x| x + 1 }.inspect.sub(/0x\h+/, "0xADDR") }
      show("Enumerator constants") { Enumerator.constants.sort }
    RUBY

    _(result).must_answer <<~'OUT'
      Profiler singleton: [:clear, :disable, :enable, :enabled?, :raw_data, :report, :result, :total_time]
      Profiler enabled?: false
      Profiler total_time: 0.0
      Profiler result: ""
      Profiler raw_data: nil
      Profiler clear: nil
      Profiler enable: nil
      Profiler enabled? after: true
      Profiler disable: nil
      Profiler report: nil
      Backtrace.limit: -1
      Backtrace singleton: [:limit]
      Backtrace constants: [:Location]
      Location own: [:absolute_path, :base_label, :inspect, :label, :lineno, :path, :to_s]
      caller_locations class: Thread::Backtrace::Location
      WKM own: [:[], :[]=, :clear, :delete, :getkey, :inspect, :key?]
      WKM arities: [1, 2, 0, 1, 1, 0, 1]
      WKM set: 1
      WKM get eq: 1
      WKM getkey: true
      WKM key?: true
      WKM getkey missing: nil
      WKM inspect: "#<ObjectSpace::WeakKeyMap:0xADDR size=1>"
      WKM int key: ArgumentError: WeakKeyMap keys must be garbage collectable
      WKM sym key: ArgumentError: WeakKeyMap keys must be garbage collectable
      WKM nil key: ArgumentError: WeakKeyMap keys must be garbage collectable
      WKM float key: ArgumentError: WeakKeyMap keys must be garbage collectable
      WKM bignum key: ArgumentError: WeakKeyMap keys must be garbage collectable
      WKM array key: 2
      WKM delete: 1
      WKM delete missing: nil
      WKM delete block: [:miss, "zz"]
      WKM clear: ObjectSpace::WeakKeyMap
      WKM after clear: nil
      WKM new arity: ArgumentError: wrong number of arguments (given 1, expected 0)
      WKM frozen write: 1
      Random.superclass: Random::Base
      Random ancestors: NoMethodError: undefined method 'firsshow' for an instance of Array
      Random own: [:==]
      Random::Base own: [:bytes, :rand, :seed]
      Random::Formatter own has rand: true
      rand owner: Random::Base
      random_number owner: Random::Formatter
      Random.new(42).rand class: Float
      Random.new(42).seed: 42
      Random.new(42).bytes: 4
      Random.new(42).random_number(10) class: Integer
      Ractor::Error ancestry: ["Ractor::Error", "RuntimeError", "StandardError", "Exception"]
      Ractor::ClosedError ancestry: ["Ractor::ClosedError", "StopIteration", "IndexError", "StandardError", "Exception"]
      Ractor::IsolationError ancestry: ["Ractor::IsolationError", "Ractor::Error", "RuntimeError", "StandardError", "Exception"]
      Ractor::MovedError ancestry: ["Ractor::MovedError", "Ractor::Error", "RuntimeError", "StandardError", "Exception"]
      Ractor::RemoteError ancestry: ["Ractor::RemoteError", "Ractor::Error", "RuntimeError", "StandardError", "Exception"]
      Ractor::UnsafeError ancestry: ["Ractor::UnsafeError", "Ractor::Error", "RuntimeError", "StandardError", "Exception"]
      rescue Ractor::ClosedError: [Ractor::ClosedError, "x"]
      Ractor::Error is StandardError: true
      Ractor constants: [:ClosedError, :Error, :IsolationError, :MovedError, :RemoteError, :UnsafeError]
      Generator to_a: [1, 2]
      Generator map: [3, 6]
      Generator ancestors: [Enumerator::Generator, Enumerable, Object]
      Generator own: [:each]
      Generator each arity: -1
      Generator inspect: "#<Enumerator::Generator:0xADDR>"
      Generator no block: LocalJumpError: no block given
      Producer own: [:each]
      Producer each arity: 0
      Enumerator.new inspect: "#<Enumerator: #<Enumerator::Generator:0xADDR>:each>"
      Enumerator.new to_a: [1, 2]
      Enumerator.new next: [1, 2]
      Enumerator.new size: 3
      Enumerator.new size proc: 7
      produce class: Enumerator
      produce first: [1, 2, 3]
      produce size: Infinity
      produce inspect: "#<Enumerator: #<Enumerator::Producer:0xADDR>:each>"
      Enumerator constants: [:ArithmeticSequence, :Chain, :Generator, :Lazy, :Producer, :Product, :Yielder]
    OUT
  end

  it "superclasses" do
    result = zr(<<~'RUBY', path: "zr/superclasses.rb")
      # frozen_string_literal: true

      # A superclass is a NAME, written as a bare constant or as a path. zr
      # resolves it outward from the class the statement is written in, the way
      # ruby resolves any constant, and hands the backend the fully-qualified
      # name it will assign an id to.

      module Outer
        class Base
          def kind = "base"
        end

        class Mid < Base
          def kind = "mid/#{super}"
        end
      end

      class Leaf < Outer::Mid
        def kind = "leaf/#{super}"
      end

      module Outer
        # `Mid` here names `Outer::Mid`, not a top-level `Mid`.
        class Deep < Mid
          def kind = "deep/#{super}"
        end
      end

      p Leaf.new.kind
      p Outer::Deep.new.kind
      p Leaf.superclass.to_s, Outer::Deep.superclass.to_s
      p Leaf.ancestors.take(4).map(&:to_s)
      p Outer::Mid.name, Outer::Deep.name

      # A class method is INHERITED: the runtime's class-method table walks no
      # ancestry, so the compile copies each one onto every subclass that does
      # not shadow it.
      class Trunk
        def self.tag = :trunk
        def self.shared = :from_trunk
      end

      class Branch < Trunk
        def self.tag = :branch
      end

      class Twig < Branch
      end

      p Trunk.tag, Branch.tag, Twig.tag
      p Trunk.shared, Branch.shared, Twig.shared
      p Twig.singleton_methods.sort
      p Twig.singleton_methods(false)
      p Twig.respond_to?(:tag)
      p Twig.method(:tag).owner

      # Each copy carries its own class, so a class-level `@x` stays where it
      # is read rather than pooling on the class that wrote the method.
      class Register
        def self.seen = @seen ||= []
        def self.note(v) = seen << v
      end

      class RegisterA < Register; end
      class RegisterB < Register; end

      RegisterA.note(1)
      RegisterB.note(2)
      p RegisterA.seen, RegisterB.seen, Register.seen

      # `BasicObject` is the root below the root: a class naming it inherits
      # neither Object's methods nor Kernel's, which is the whole point of
      # writing it.
      class Bare < BasicObject
        def two = 2
      end

      p Bare.superclass.to_s
      p Bare.ancestors.map(&:to_s)
      p Bare.new.two
      p Bare.instance_methods(false)
      Bare.new.respond_to?(:to_s)
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR', status: 1
      "leaf/mid/base"
      "deep/mid/base"
      "Outer::Mid"
      "Outer::Mid"
      ["Leaf", "Outer::Mid", "Outer::Base", "Object"]
      "Outer::Mid"
      "Outer::Deep"
      :trunk
      :branch
      :branch
      :from_trunk
      :from_trunk
      :from_trunk
      [:shared, :tag]
      []
      true
      #<Class:Branch>
      [1]
      [2]
      []
      "BasicObject"
      ["Bare", "BasicObject"]
      2
      [:two]
    OUT
      zr/superclasses.rb:82:in '<main>': undefined method 'respond_to?' for an instance of Bare (NoMethodError)

      Bare.new.respond_to?(:to_s)
              ^^^^^^^^^^^^
    ERR
  end
end
