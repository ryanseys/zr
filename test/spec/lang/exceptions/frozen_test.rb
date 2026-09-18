# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: frozen literals" do
  it "ensure" do
    result = ze0(<<~'RUBY', path: "ensure.rb")
      # frozen_string_literal: true

      # `ensure` runs its clause on the way out however the body leaves: a
      # normal finish, a raise, or a jump the clause stands between.

      log = []

      def guard(log)
        log << :body
        :done
      ensure
        log << :ensured
      end

      p guard(log), log

      def raiser(log)
        log << :body
        raise ArgumentError, "boom"
      ensure
        log << :ensured
      end

      begin
        raiser(log)
      rescue ArgumentError => e
        p e.message
      end
      p log

      # The clause runs after the `rescue` has already answered.
      x = begin
        Integer("nope")
      rescue ArgumentError
        :rescued
      ensure
        log << :inner
      end
      p x, log

      # `$!` names the exception being carried while the clause runs, and nil
      # when nothing is being carried.
      def carried
        raise "up"
      ensure
        p $!.message
      end

      begin
        carried
      rescue RuntimeError => e
        p e.message
      end

      def quiet
        :fine
      ensure
        p $!
      end
      p quiet

      # A raise from the clause itself wins over the one it was carrying.
      def replaced
        raise ArgumentError, "first"
      ensure
        raise TypeError, "second"
      end

      begin
        replaced
      rescue TypeError => e
        p e.class, e.message
      end

      # A `next` written in a block inside the body lands in that block and
      # never crosses the clause.
      def counted(log)
        [1, 2, 3].map do |n|
          next 0 if n == 2

          n
        end
      ensure
        log << :counted
      end
      p counted(log), log
      # `value rescue fallback` is one bare clause over one expression, and a
      # bare clause is `StandardError`: anything above it still leaves.
      def boom = raise(ArgumentError, "no")
      def fatal = raise(NotImplementedError, "up")

      p((boom rescue :caught))
      p(([1, 2].fetch(9) rescue :missing))
      p(((1 + 1) rescue :never))

      taken = boom rescue :assigned
      p taken

      @held = boom rescue :ivar
      p @held

      def returns_early
        return boom rescue :returned
      end
      p returns_early

      begin
        p((fatal rescue :never))
      rescue NotImplementedError => e
        p e.message
      end

      # The fallback is an ordinary expression, and it may raise in its turn.
      begin
        p((boom rescue fatal))
      rescue NotImplementedError => e
        p e.message
      end

      # `$!` is the exception for the fallback's whole run, and gone after.
      p((boom rescue $!.message))
      p $!

      # One modifier inside another: the inner one catches first.
      p((boom rescue (boom rescue :inner)))
      # A jump the clause stands between travels as a signal, and the clause
      # turns it back into the jump it was once it has run.
      def crossed(log)
        out = []
        i = 0
        while i < 5
          i += 1
          begin
            next if i == 2
            break if i == 4

            out << i
          ensure
            log << [:crossed, i]
          end
        end
        out
      end
      p crossed(log), log

      # Two clauses in a row: each runs, outermost last.
      def twice
        seen = []
        [1, 2, 3].each do |n|
          begin
            begin
              break if n == 3
            ensure
              seen << [:inner, n]
            end
          ensure
            seen << [:outer, n]
          end
        end
        seen
      end
      p twice

      # In a block the clause stands in front of the block's own boundary, so
      # `next` still answers the block and `break` still leaves the send.
      def in_a_block
        [1, 2, 3].map do |n|
          begin
            next :skipped if n == 2

            n
          ensure
            print "n#{n} "
          end
        end
      end
      p in_a_block

      def broken
        [1, 2, 3].each do |n|
          begin
            break :stopped if n == 2
          ensure
            print "b#{n} "
          end
        end
      end
      p broken

      # `break` supplies the loop's own value across the clause.
      def valued
        i = 0
        while true
          i += 1
          begin
            break i * 10
          ensure
            print "v "
          end
        end
      end
      p valued

    RUBY

    _(result).must_answer <<~'OUT'
      :done
      [:body, :ensured]
      "boom"
      [:body, :ensured, :body, :ensured]
      :rescued
      [:body, :ensured, :body, :ensured, :inner]
      "up"
      "up"
      nil
      :fine
      TypeError
      "second"
      [1, 0, 3]
      [:body, :ensured, :body, :ensured, :inner, :counted]
      :caught
      :missing
      2
      :assigned
      :ivar
      :returned
      "up"
      "up"
      "no"
      nil
      :inner
      [1, 3]
      [:body, :ensured, :body, :ensured, :inner, :counted, [:crossed, 1], [:crossed, 2], [:crossed, 3], [:crossed, 4]]
      [[:inner, 1], [:outer, 1], [:inner, 2], [:outer, 2], [:inner, 3], [:outer, 3]]
      n1 n2 n3 [1, :skipped, 3]
      b1 b2 :stopped
      v 10
    OUT
  end

  it "exception freeze" do
    result = ze0(<<~'RUBY')
      # freeze on an exception was a no-op and frozen? a hard-coded false, so an
      # exception the program froze itself still read back unfrozen.
      p(RuntimeError.new("f").freeze.frozen?)
      e = RuntimeError.new("f").freeze
      p e.frozen?
      class S1 < StandardError; end
      s = S1.new("x").freeze
      p s.frozen?
      p "a".freeze.frozen?
      p RuntimeError.new("g").frozen?
      begin
        raise "boom"
      rescue => x
        p x.frozen?
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      false
      false
    OUT
  end

  it "frozen error is caught by a runtime error rescue" do
    result = ze0(<<~'RUBY')
      g = [1].freeze
      begin
        g[0] = 2
      rescue RuntimeError => e
        puts "runtime-rescued"
      end
    RUBY

    _(result).must_answer "runtime-rescued\n"
  end

  it "a frozen Array and a frozen Hash refuse every write" do
    result = ze0(<<~'RUBY')
      a = [1, 2, 3].freeze
      puts a.frozen?
      begin
        a << 4
      rescue FrozenError
        puts "array << raised"
      end
      begin
        a[0] = 9
      rescue FrozenError
        puts "array []= raised"
      end
      begin
        a.push(5)
      rescue FrozenError
        puts "array push raised"
      end
      puts a.inspect

      b = [1, 2, 3]
      puts b.frozen?
      b << 4
      b[0] = 9
      puts b.inspect

      s = ["x", "y"].freeze
      begin
        s << "z"
      rescue FrozenError
        puts "str_array << raised"
      end
      puts s.inspect

      h = {a: 1}.freeze
      puts h.frozen?
      begin
        h[:b] = 2
      rescue FrozenError
        puts "hash []= raised"
      end

      g = {a: 1}
      puts g.frozen?
      g[:b] = 2
      puts g.length
    RUBY

    _(result).must_answer <<~'OUT'
      true
      array << raised
      array []= raised
      array push raised
      [1, 2, 3]
      false
      [9, 2, 3, 4]
      str_array << raised
      ["x", "y"]
      true
      hash []= raised
      false
      2
    OUT
  end

  it "a frozen String refuses every write, and freeze after the fact is enough" do
    result = ze0(<<~'RUBY')
      s = "hello".freeze
      puts s.frozen?
      begin
        s << " world"
      rescue FrozenError
        puts "<<: raised"
      end
      begin
        s.insert(0, "X")
      rescue FrozenError
        puts "insert: raised"
      end
      begin
        s.prepend("X")
      rescue FrozenError
        puts "prepend: raised"
      end
      begin
        s.replace("X")
      rescue FrozenError
        puts "replace: raised"
      end
      puts s

      s2 = "hello".dup
      puts s2.frozen?
      s2 << " world"
      puts s2

      s3 = String.new("abc")
      puts s3.frozen?
      s3.freeze
      puts s3.frozen?
      begin
        s3 << "d"
      rescue FrozenError
        puts "post-freeze: raised"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      <<: raised
      insert: raised
      prepend: raised
      replace: raised
      hello
      false
      hello world
      false
      true
      post-freeze: raised
    OUT
  end

  it "make shareable deep freezes a nested object graph that then crosses" do
    result = ze0(<<~'RUBY')
      # The plan's own listed scenario: object -> array -> object, every node
      # frozen by one make_shareable, the whole graph then crossing a Ractor
      # boundary by reference and dispatching on the far side.

      class Node
        def initialize(v, child)
          @v = v
          @child = child
        end
        def v; @v; end
      end
      leaf = Node.new(3, nil)
      root = Node.new(1, [leaf])
      Ractor.make_shareable(root)
      puts root.frozen?
      puts leaf.frozen?
      puts Ractor.shareable?(root)
      sink = Ractor.new do
        got = Ractor.receive
        got.send(:v)
      end
      sink.send(root)
      puts sink.value
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      true
      true
      true
      1
    OUT
      lang/exceptions/frozen_test.rb:18: warning: Ractor API is experimental and may change in future versions of Ruby.
    ERR
  end

  it "name validation family" do
    result = ze0(<<~'RUBY')
      # The reflection surface validates the NAMES it is given, through one
      # shared set of predicates rather than sixteen separate remembered checks.
      #
      # The five promoted gaps beside this file each cover one row. This covers
      # the RULES, which is where the next miss would come from -- and three of
      # them are surprising enough to be worth pinning:
      #
      #   * an identifier takes no trailing `?`/`!`/`=` (`attr_accessor :x?` is
      #     refused), while non-ASCII letters ARE identifier characters;
      #   * a constant is a SINGLE segment for `const_set` and a PATH for
      #     `const_get`, so `const_set("A::B")` is a wrong-name error rather than
      #     a nested write;
      #   * the NAME is checked before FROZEN, and per ARGUMENT rather than once
      #     up front, both of which are observable.

      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message.sub(/0x[0-9a-f]+/, "0xN")}"
      end

      # --- Instance-variable names ----------------------------------------------
      o = Object.new
      show { o.instance_variable_get("@@bad") }
      show { o.instance_variable_get("@1x") }
      show { o.instance_variable_get("@") }
      show { o.instance_variable_get("x") }
      show { o.instance_variable_set("@@bad", 1) }
      show { o.instance_variable_defined?("@@bad") }
      # Valid, including a non-ASCII name.
      show { o.instance_variable_set(:@ok, 1) }
      show { o.instance_variable_get(:@ok) }
      show { o.instance_variable_set(:@日本, 2) }
      show { o.instance_variable_get(:@日本) }
      show { o.instance_variables }

      # --- Constant names -------------------------------------------------------
      show { Module.new.const_set(:lower, 1) }
      show { Module.new.const_set("A::B", 1) }
      show { Module.new.const_set("", 1) }
      show { Module.new.const_set("1A", 1) }
      show { Module.new.const_set(:Ok, 1) }
      show { Module.new.const_get(:lower) }
      show { Module.new.send(:remove_const, :Nope) }
      # `const_get` takes a PATH where `const_set` takes a segment.
      show { Object.const_get("Comparable") }

      # --- Attribute names ------------------------------------------------------
      show { Class.new { attr_accessor :"1bad" } }
      show { Class.new { attr_accessor :"x?" } }
      show { Class.new { attr_accessor :"x!" } }
      show { Class.new { attr_accessor 1 } }
      # The name is checked per ARGUMENT: `:ok` is defined, and then it raises.
      show do
        c = Class.new
        begin
          c.send(:attr_accessor, :ok, :"1bad")
        rescue NameError
          nil
        end
        c.instance_methods(false).sort
      end
      # A frozen class given a BAD name says NameError, not FrozenError.
      show { Class.new.freeze.send(:attr_accessor, :"1bad") }
      show { Class.new.freeze.send(:attr_accessor, :ok) }

      # --- Module arguments -----------------------------------------------------
      show { Class.new { include String } }
      show { Class.new { include 1 } }
      show { Class.new { prepend String } }
      show { Object.new.extend(String) }
      show do
        m = Module.new
        m.send(:include, m)
      end
      show do
        m = Module.new
        n = Module.new { include m }
        m.send(:include, n)
      end
      # Every argument is validated BEFORE any is spliced.
      show do
        c = Class.new
        begin
          c.send(:include, Comparable, String)
        rescue TypeError
          nil
        end
        c.ancestors.include?(Comparable)
      end
      # Frozen sits between the type check and the cycle check.
      show { Class.new.freeze.send(:include, String) }
      show { Class.new.freeze.send(:include, Comparable) }

      # --- Superclasses ---------------------------------------------------------
      show { Class.new(Comparable) }
      show { Class.new(1) }
      show { Class.new(Class) }
      show { Class.new(Object.new.singleton_class) }
      # LEGAL, and both used to be conflated with the refusals: `Module` is a
      # Class, it is just not a module instance.
      show { Class.new(Module).ancestors.include?(Module) }
      show { Class.new(BasicObject).ancestors.include?(BasicObject) }
      show { Class.new(String).new("hi") }
    RUBY

    _(result).must_answer <<~'OUT'
      NameError: '@@bad' is not allowed as an instance variable name
      NameError: '@1x' is not allowed as an instance variable name
      NameError: '@' is not allowed as an instance variable name
      NameError: 'x' is not allowed as an instance variable name
      NameError: '@@bad' is not allowed as an instance variable name
      NameError: '@@bad' is not allowed as an instance variable name
      1
      1
      2
      2
      [:@ok, :@日本]
      NameError: wrong constant name lower
      NameError: wrong constant name A::B
      NameError: wrong constant name 
      NameError: wrong constant name 1A
      1
      NameError: wrong constant name lower
      NameError: constant #<Module:0xN>::Nope not defined
      Comparable
      NameError: invalid attribute name '1bad'
      NameError: invalid attribute name 'x?'
      NameError: invalid attribute name 'x!'
      TypeError: 1 is not a symbol nor a string
      [:ok, :ok=]
      NameError: invalid attribute name '1bad'
      FrozenError: can't modify frozen Class: #<Class:0xN>
      TypeError: wrong argument type Class (expected Module)
      TypeError: wrong argument type Integer (expected Module)
      TypeError: wrong argument type Class (expected Module)
      TypeError: wrong argument type Class (expected Module)
      ArgumentError: cyclic include detected
      ArgumentError: cyclic include detected
      false
      TypeError: wrong argument type Class (expected Module)
      FrozenError: can't modify frozen Class: #<Class:0xN>
      TypeError: superclass must be an instance of Class (given an instance of Module)
      TypeError: superclass must be an instance of Class (given an instance of Integer)
      TypeError: can't make subclass of Class
      TypeError: can't make subclass of singleton class
      true
      true
      "hi"
    OUT
  end

  it "no method error names a singleton receiver" do
    result = ze0(<<~'RUBY')
      # A `NoMethodError` names its receiver one of two ways, and which one is
      # decided by whether the receiver has a SINGLETON CLASS: `an instance of K`
      # without, `#<K:0xADDR>` with. Materializing one is the whole trigger --
      # a bare `singleton_class` call flips it, removing the last `def obj.m`
      # does not flip it back, and `freeze` never flips it.
      #
      # The address form is `rb_any_to_s`, so it ignores a `to_s` or an
      # `inspect` the class defines. That matters beyond cosmetics: building
      # this message must run no user code, which is what lets a blank-slate
      # receiver report its own missing method instead of failing a second
      # lookup while describing the first.
      class K
        def to_s = "K-TO-S"
        def inspect = "K-INSPECT"
      end
      module M; end

      def why(label)
        yield
      rescue NoMethodError => e
        puts "#{label}: #{e.message}"
      end

      why("plain") { K.new.nope }
      why("frozen") { K.new.freeze.nope }

      k = K.new
      def k.mine; end
      why("own def") { k.nope }

      e = K.new
      e.extend(M)
      why("extended") { e.nope }

      s = K.new
      s.singleton_class
      why("singleton_class asked for") { s.nope }

      r = K.new
      def r.gone; end
      r.singleton_class.send(:remove_method, :gone)
      why("last singleton method removed") { r.nope }

      str = +"text"
      def str.mine; end
      why("string") { str.nope }

      arr = [1, 2]
      def arr.mine; end
      why("array") { arr.nope }

      why("class") { K.nope }
      why("module") { M.nope }
      why("nil") { nil.nope }
      why("true") { true.nope }
      why("integer") { 5.nope }
      why("main") { self.nope }
    RUBY

    _(result).must_answer <<~'OUT'
      plain: undefined method 'nope' for an instance of K
      frozen: undefined method 'nope' for an instance of K
      own def: undefined method 'nope' for #<K:0xADDR>
      extended: undefined method 'nope' for #<K:0xADDR>
      singleton_class asked for: undefined method 'nope' for #<K:0xADDR>
      last singleton method removed: undefined method 'nope' for #<K:0xADDR>
      string: undefined method 'nope' for #<String:0xADDR>
      array: undefined method 'nope' for #<Array:0xADDR>
      class: undefined method 'nope' for class K
      module: undefined method 'nope' for module M
      nil: undefined method 'nope' for nil
      true: undefined method 'nope' for true
      integer: undefined method 'nope' for an instance of Integer
      main: undefined method 'nope' for main
    OUT
  end

  it "reopening a frozen class raises" do
    result = ze0(<<~'RUBY')
      # A REOPEN of a frozen class is a `FrozenError` and its body never runs -- so
      # the methods that body would have installed do not exist. zeo's compile-time
      # tables already carry them, so the guard retires them at the reopen's own
      # position. Gated on the program calling `freeze` at all: without one the shape
      # is unreachable and no name loses its static dispatch.
      class Fz
        def already = :already
      end
      Fz.freeze

      begin
        class Fz
          def x = :x
          def y = :y
        end
      rescue FrozenError => e
        p [e.class, e.message]
      end

      p Fz.frozen?
      p Fz.instance_methods(false).sort
      p Fz.method_defined?(:x)
      p Fz.new.respond_to?(:x)
      begin; Fz.new.x; rescue NoMethodError => e; p e.class; end
      # The body's earlier definition is untouched.
      p Fz.new.already

      # An UNFROZEN class reopens normally.
      class Ok
        def a = :a
      end
      class Ok
        def b = :b
      end
      p Ok.new.a
      p Ok.new.b
      p Ok.instance_methods(false).sort

      # A module reopen refuses the same way.
      module Mz
        def m = :m
      end
      Mz.freeze
      begin
        module Mz
          def n = :n
        end
      rescue FrozenError => e
        p [e.class, e.message]
      end
      p Mz.instance_methods(false)

      # A frozen class still answers every ordinary reflection.
      p Fz.name
      p Fz.superclass.to_s
      p Fz.new.class.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      [FrozenError, "can't modify frozen Class: Fz"]
      true
      [:already]
      false
      false
      NoMethodError
      :already
      :a
      :b
      [:a, :b]
      [FrozenError, "can't modify frozen Module: Mz"]
      [:m]
      "Fz"
      "Object"
      "Fz"
    OUT
  end

  it "rescue and writes" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # `retry` runs the whole `begin` again, leaving the clause it is written
      # in -- and the `$!` that clause holds -- behind.

      tries = 0
      begin
        tries += 1
        raise "boom" if tries < 3
        p [:ok, tries]
      rescue
        retry
      end

      def flaky
        n = 0
        begin
          n += 1
          raise ArgumentError if n < 2
          n
        rescue ArgumentError
          retry
        end
      end
      p flaky

      # A `*errs` spreads its elements in, so how many classes a clause names
      # is a run-time fact.
      errs = [TypeError, ArgumentError]
      begin
        raise ArgumentError, "bad"
      rescue *errs => e
        p [:caught, e.class, e.message]
      end

      begin
        raise "plain"
      rescue *errs
        p :never
      rescue => e
        p [:standard, e.message]
      end

      # The binding is an ordinary write target, so an ivar or a global takes
      # a reference of its own.
      class Holder
        attr_reader :e

        def run
          raise "held"
        rescue => @e
          @e.message
        end
      end
      h = Holder.new
      p h.run
      p h.e.message

      begin
        raise "global"
      rescue => $caught
      end
      p $caught.message

      # A write answers the value ASSIGNED, whatever the setter returns.
      class Box
        attr_accessor :v

        def w=(x)
          @v = x
          :ignored
        end

        def []=(_k, x)
          @v = x
          :ignored
        end
      end
      b = Box.new
      p(b.w = 3)
      p(b[1] = 4)
      p(b.v ||= 9)
      p(b.v += 1)

      # Safe navigation: a nil receiver answers nil and runs nothing.
      o = nil
      p(o&.v = 3)
      p(b&.v = 11)
      p(b&.v ||= 12)
      p(b&.v += 1)
      p b.v
    RUBY

    _(result).must_answer <<~'OUT'
      [:ok, 3]
      2
      [:caught, ArgumentError, "bad"]
      [:standard, "plain"]
      "held"
      "held"
      "global"
      3
      4
      4
      5
      nil
      11
      11
      12
      12
    OUT
  end

  it "shareable predicate is deep" do
    result = ze0(<<~'RUBY')
      # A frozen container holding an UNFROZEN element is not shareable --
      # CRuby's frozen-and-everything-reachable-shareable rule.

      arr = ["mut"]
      arr.freeze
      puts Ractor.shareable?(arr)
      Ractor.make_shareable(arr)
      puts Ractor.shareable?(arr)
    RUBY

    _(result).must_answer "false\ntrue\n"
  end
end
