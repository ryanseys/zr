# frozen_string_literal: true

require "spec_helper"

describe "Constants: defining and naming methods" do
  it "const alias path receiver" do
    result = ze0(<<~'RUBY')
      # A constant-path receiver whose LEAF is a module/class alias resolves to
      # the aliased target, like the simple-constant receiver form already does.
      module Outer
        module Util
          def self.five = 5
          def self.echo(s) = s
        end
        OC = Util
      end

      p Outer::OC.five
      p Outer::OC.echo("hi")
      p Outer::Util.five
      X = Outer::Util
      p X.five
    RUBY

    _(result).must_answer <<~'OUT'
      5
      "hi"
      5
      5
    OUT
  end

  it "const alias reached only by new" do
    result = ze0(<<~'RUBY')
      # A constant aliasing a class, defined in a LEXICAL PARENT and reached only
      # through `.new` from a class nested inside it. The ownership collector saw a
      # bare `Fast` read but not `Fast.new`, so the name got no ownership entry and
      # codegen's runtime fallback looked it up on the referencing class -- a
      # `NameError` for a constant that is plainly in scope. prism's serializer is
      # written exactly this way (`FastStringIO = ::StringIO`, then
      # `FastStringIO.new` inside its `Loader`).
      module M
        module S
          Fast = ::String

          class Loader
            def build = Fast.new("hi")
          end
        end
      end
      p M::S::Loader.new.build

      # A bare read of the same name elsewhere in the class used to be what made it
      # work -- it must keep working, and must not be what makes it work.
      module N
        module T
          Fast = ::String

          class Loader
            def named = Fast
            def build = Fast.new("ok")
          end
        end
      end
      p N::T::Loader.new.named
      p N::T::Loader.new.build

      # The same shape one level deeper, and through a qualified path.
      module U
        Wrapped = ::Array

        module V
          class Maker
            def build = Wrapped.new(2, 0)
            def qualified = ::U::Wrapped.new(1, 9)
          end
        end
      end
      p U::V::Maker.new.build
      p U::V::Maker.new.qualified
    RUBY

    _(result).must_answer <<~'OUT'
      "hi"
      String
      "ok"
      [0, 0]
      [9]
    OUT
  end

  it "nested definition ignores an outer const alias" do
    result = ze0(<<~'RUBY')
      # A class/module DEFINITION binds its name in the immediately enclosing scope.
      # Ruby never searches outward for it, so a `NAME = SomeClass` alias written in
      # another scope is a different constant and cannot be what the definition
      # reopens. zeo used to consult a whole-program scan of every `NAME = ...` here,
      # unscoped, first match wins -- which bound these to the alias instead.

      # 1. An alias in an OUTER scope, to a class, vs a nested MODULE of that name.
      module Mongoid
        class Boolean; end
        module Fields
          Boolean = Mongoid::Boolean
        end
        module Extensions
          module Boolean
            def self.evolve(v) = !!v
          end
        end
      end
      p Mongoid::Boolean.class
      p Mongoid::Extensions::Boolean.class
      p Mongoid::Boolean.equal?(Mongoid::Extensions::Boolean)
      p Mongoid::Extensions::Boolean.evolve(1)

      # 2. A TOP-LEVEL module of the same name vs a nested class.
      module HTML; end
      class Thor
        module Shell
          class Basic
            def kind = :basic
          end
          class HTML < Basic
            def kind = :html
          end
        end
      end
      p Thor::Shell::HTML.superclass
      p Thor::Shell::HTML.new.kind
      p HTML.class

      # 3. A top-level alias vs a nested class with a DIFFERENT superclass -- the
      #    shape that reported `superclass mismatch for class ParseError`.
      module Racc
        class ParseError < StandardError; end
      end
      ParseError = Racc::ParseError
      class OptionParser
        class ParseError < RuntimeError; end
      end
      p ParseError.superclass
      p OptionParser::ParseError.superclass
      p ParseError.equal?(OptionParser::ParseError)

      # 4. The alias reopen this machinery exists for still works: a bare TOP-LEVEL
      #    definition whose name is a top-level alias reopens the aliased class.
      module Tagged
        def tagged = :yes
      end
      INT_ALIAS = 1.class
      class INT_ALIAS
        include Tagged
      end
      p 7.tagged
      p INT_ALIAS.equal?(Integer)
    RUBY

    _(result).must_answer <<~'OUT'
      Class
      Module
      false
      true
      Thor::Shell::Basic
      :html
      Module
      StandardError
      RuntimeError
      false
      :yes
      true
    OUT
  end

  it "remove const on a pending autoload answers nil" do
    result = ze0(<<~'RUBY')
      # remove_const on a name whose autoload has not run answers nil, and
      # the name forgets its file as well as its row.
      module Box
        autoload :Later, "/nonexistent/later_for_remove_const.rb"
      end
      p Box.autoload?(:Later), Box.const_defined?(:Later)
      p Box.send(:remove_const, :Later)
      p Box.autoload?(:Later), Box.const_defined?(:Later), Box.constants
      begin
        Box.send(:remove_const, :Later)
      rescue NameError => e
        p e.message
      end

    RUBY

    _(result).must_answer <<~'OUT'
      "/nonexistent/later_for_remove_const.rb"
      true
      nil
      nil
      false
      []
      "constant Box::Later not defined"
    OUT
  end

  it "scoped const alias in a case arm resolves" do
    result = ze0(<<~'RUBY')
      # A `NAME = SomeModule` write inside a class or module body binds the name
      # whatever container it is written in -- a `case` arm here, but a `begin` body
      # or a block just as much. Only the `if` shape was recorded, so `include
      # Ordered` below raised `uninitialized constant Ns::Uses::Ordered` where CRuby
      # includes Comparable.
      module Ns
        case ENV.fetch("ZEO_BASE", "a")
        when "a" then Ordered = Comparable
        else Ordered = Comparable
        end

        class Uses
          include Ordered
          def <=>(other) = 0
        end
      end

      p Ns::Uses.ancestors.include?(Comparable)
      p Ns::Uses.new == Ns::Uses.new
    RUBY

    _(result).must_answer "true\ntrue\n"
  end

  it "top level alias and undef target object" do
    result = ze0(<<~'RUBY')
      # `alias` and `undef` at TOP LEVEL, where the implicit target is `Object` --
      # top-level `def` defines a private method on Object, so the keywords that
      # alias or remove one have to reopen the same class. Both were class-body-only
      # and reached the generic "unsupported syntax" rejection out there.

      def greet
        "hi"
      end
      alias hello greet
      puts hello
      puts greet

      def doomed
        "here"
      end
      undef doomed
      puts respond_to?(:doomed, true)
      begin
        doomed
      rescue NameError
        puts "NameError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      hi
      false
      NameError
    OUT
  end

  it "toplevel alias" do
    result = ze0(<<~'RUBY')
      # A top-level `alias b a`: the alias collector only walked class and module
      # bodies, so the new name was never registered and calling it raised NameError.
      def t1; 1; end
      alias t2 t1
      p t2
      p t1

      def add(a, b); a + b; end
      alias plus add
      p plus(2, 3)
      p add(2, 3)

      def greet(n = "x"); "hi #{n}"; end
      alias hello greet
      p hello
      p hello("y")

    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      5
      5
      "hi x"
      "hi y"
    OUT
  end

  it "toplevel name collides with runtime" do
    result = ze0(<<~'RUBY')
      # A top-level method mangles to `sp_<name>`, which is the runtime's own
      # namespace: `def str_hash` collided with sp_str_hash and the generated C did
      # not compile (#3973). Such a name is emitted with an `rb_` infix now.
      def str_hash
        1
      end
      def poly_add(a, b)
        a + b
      end
      def gc_stat = "mine"
      def box_it(x) = [x]
      def my_helper(v) = v * 2
      def plain = 7
      p str_hash
      p poly_add(1, 2)
      p gc_stat
      p box_it(3)
      p my_helper(4)
      p plain
      alias str_hash2 str_hash
      p str_hash2
      module M
        def self.str_hash = 9
      end
      p M.str_hash
    RUBY

    _(result).must_answer <<~'OUT'
      1
      3
      "mine"
      [3]
      8
      7
      1
      9
    OUT
  end

  it "undef const scalar position" do
    result = ze0(<<~'RUBY')
      # An unresolved constant read lowers to a runtime NameError raise whose C
      # value is an sp_Class; used in a scalar slot (Array.new count, array index,
      # int/float arithmetic operand) the struct used to leak into the generated C
      # and fail the compile ("incompatible types ... using type 'sp_Class'").
      # CRuby raises NameError at runtime -- and only when the read executes.

      module Params
      end

      def by_count
        Array.new(Params::FRI_FINAL_MAX_LEN) { |i| i }
      end

      def by_index
        [1, 2][Params::FOO]
      end

      def by_float_arith
        1.5 * Params::RATIO
      end

      def by_int_arith
        2 * Params::N
      end

      # defined but never called: the undefined constant must stay silent
      def never_called
        Array.new(Params::UNUSED) { |i| i }
      end

      [1, 2].each do |unused|
        # loop so the rescue sites emit once but run twice: the raise is per-read
        begin
          by_count
        rescue NameError => e
          puts e.message
        end
      end

      begin
        by_index
      rescue NameError => e
        puts e.message
      end

      begin
        by_float_arith
      rescue NameError => e
        puts e.message
      end

      begin
        by_int_arith
      rescue NameError => e
        puts e.message
      end

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      uninitialized constant Params::FRI_FINAL_MAX_LEN
      uninitialized constant Params::FRI_FINAL_MAX_LEN
      uninitialized constant Params::FOO
      uninitialized constant Params::RATIO
      uninitialized constant Params::N
      done
    OUT
  end
end
