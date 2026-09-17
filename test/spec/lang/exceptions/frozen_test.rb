# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: frozen literals" do
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
    _(ze0(<<~'RUBY')).must_answer "runtime-rescued\n"
      g = [1].freeze
      begin
        g[0] = 2
      rescue RuntimeError => e
        puts "runtime-rescued"
      end
    RUBY
  end

  it "i918" do
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

  it "i972" do
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
    result = ze0(<<~'RUBY', path: "lang/exceptions/make_shareable_deep_freezes_a_nested_object_graph_that_then_crosses.rb")
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

    _(result).must_answer <<~'OUT', stderr: "lang/exceptions/make_shareable_deep_freezes_a_nested_object_graph_that_then_crosses.rb:18: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
      true
      true
      true
      1
    OUT
  end

  it "name validation family" do
    _(ze0(<<~'RUBY')).must_answer "NameError: '@@bad' is not allowed as an instance variable name\nNameError: '@1x' is not allowed as an instance variable name\nNameError: '@' is not allowed as an instance variable name\nNameError: 'x' is not allowed as an instance variable name\nNameError: '@@bad' is not allowed as an instance variable name\nNameError: '@@bad' is not allowed as an instance variable name\n1\n1\n2\n2\n[:@ok, :@日本]\nNameError: wrong constant name lower\nNameError: wrong constant name A::B\nNameError: wrong constant name \nNameError: wrong constant name 1A\n1\nNameError: wrong constant name lower\nNameError: constant #<Module:0xN>::Nope not defined\nComparable\nNameError: invalid attribute name '1bad'\nNameError: invalid attribute name 'x?'\nNameError: invalid attribute name 'x!'\nTypeError: 1 is not a symbol nor a string\n[:ok, :ok=]\nNameError: invalid attribute name '1bad'\nFrozenError: can't modify frozen Class: #<Class:0xN>\nTypeError: wrong argument type Class (expected Module)\nTypeError: wrong argument type Integer (expected Module)\nTypeError: wrong argument type Class (expected Module)\nTypeError: wrong argument type Class (expected Module)\nArgumentError: cyclic include detected\nArgumentError: cyclic include detected\nfalse\nTypeError: wrong argument type Class (expected Module)\nFrozenError: can't modify frozen Class: #<Class:0xN>\nTypeError: superclass must be an instance of Class (given an instance of Module)\nTypeError: superclass must be an instance of Class (given an instance of Integer)\nTypeError: can't make subclass of Class\nTypeError: can't make subclass of singleton class\ntrue\ntrue\n\"hi\"\n"
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

    _(result).must_answer <<~'OUT'
      false
      true
    OUT
  end
end
