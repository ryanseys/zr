# frozen_string_literal: true

require "spec_helper"

describe "String: interpolation" do
  it "amp sym in string literals" do
    result = zr(<<~'RUBY')
      s = "count(&:alive)"
      puts s
      puts s.length
      puts(s == "count(&:alive)")
      h = <<~EOS
        filter(&:active) and .send(:reload)
      EOS
      puts h
      puts h.length
      t = 'single &:quoted'
      puts t
      puts "interp works: #{[1, 2].map(&:to_s).join(",")}"
      puts %w[&:a &:b].join(" ")
      puts "obj.send(:name)"
      # comment with &:ignored and .send(:ignored)
      d = <<~'SQL'
        SELECT count(&:x) .send(:y)
      SQL
      puts d
      puts [3, 1, 2].sort_by(&:abs).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      count(&:alive)
      14
      true
      filter(&:active) and .send(:reload)
      36
      single &:quoted
      interp works: 1,2
      &:a &:b
      obj.send(:name)
      SELECT count(&:x) .send(:y)
      [1, 2, 3]
    OUT
  end

  it "autoload interpolated dir feature" do
    result = zr(<<~'RUBY', files: beside("autoload_interp/sprocket.rb"))
      # `autoload :Const, "#{__dir__}/sibling"` -- how puma, rack and sidekiq name a
      # sibling file. zr splices the target at compile time, so the interpolation
      # has to fold then; only a plain literal and `File.expand_path` did.

      autoload :Sprocket, "#{__dir__}/autoload_interp/sprocket"
      autoload :Widget, "#{__dir__}/autoload_interp/sprocket"

      p Sprocket.size
      p Widget::NAME
      p Sprocket.is_a?(Class)
    RUBY

    _(result).must_answer <<~'OUT'
      42
      "widget"
      true
    OUT
  end

  it "backtick interpolates and runs a shell command" do
    result = zr(<<~'RUBY')
      # Interpolation shares the normal dstr path; a `;` forces the `/bin/sh -c`
      # path (shell metacharacter), while the bare word execs directly.

      name = "world"
      print `echo hi #{name}`
      print `echo a; echo b`
      puts $?.exited?
    RUBY

    _(result).must_answer <<~'OUT'
      hi world
      a
      b
      true
    OUT
  end

  it "hash shorthand and interpolated symbols" do
    result = zr(<<~'RUBY')
      x = 1
      name = "n"
      p({x:, name:})
      def kw(a:, b:); [a, b]; end
      a = 10
      b = 20
      p kw(a:, b:)
      w = "world"
      p :"hello_#{w}"
      p :"a#{1 + 1}b"
      p :"plain"
      p :"a#{1}b".class
    RUBY

    _(result).must_answer <<~'OUT'
      {x: 1, name: "n"}
      [10, 20]
      :hello_world
      :a2b
      :plain
      Symbol
    OUT
  end

  it "interp adjacent concat" do
    result = zr(<<~'RUBY')
      # adjacent string literals joined by backslash-continuation, each with its own
      # interpolation -- parses to nested InterpolatedStringNodes
      def svg(px, inner)
        "<a width='#{px}' " \
        "height='#{px}'>#{inner}</a>"
      end

      # three-way adjacency mixing plain and interpolated parts
      def three(a, b)
        "[" \
        "#{a}-#{b}" \
        "]"
      end

      # adjacency where one fragment is a plain literal (no interpolation)
      def tail(n)
        "n=#{n}" \
        " done"
      end

      puts svg(16, "x")
      puts three("L", "R")
      puts tail(7)
    RUBY

    _(result).must_answer <<~'OUT'
      <a width='16' height='16'>x</a>
      [L-R]
      n=7 done
    OUT
  end

  it "interp symbol" do
    result = zr(<<~'RUBY')
      # InterpolatedSymbolNode -- `:"foo_#{x}"`.
      #
      # Lowered to InterpolatedStringNode + sp_intern at codegen side.
      # The parser emits InterpolatedSymbolNode with parts; codegen
      # treats it like InterpolatedStringNode then routes through
      # the intern helper for symbol identity.

      x = "world"
      sym = :"hello_#{x}"
      puts sym                # hello_world

      n = 42
      sym2 = :"item_#{n}"
      puts sym2               # item_42

      # Symbol passed through a method
      def kind(s) = s.to_s
      puts kind(:"prefix_#{x}")   # prefix_world
    RUBY

    _(result).must_answer <<~'OUT'
      hello_world
      item_42
      prefix_world
    OUT
  end

  it "interpolate handles" do
    result = zr(<<~'RUBY')
      r, w = IO.pipe
      s = "#{r} #{w}"
      p s.start_with?("#<IO:")
      p s.include?(" #<IO:")
      pr = proc { 1 }
      p "#{pr}".start_with?("#<Proc:")
      f = Fiber.new { Fiber.yield 1 }
      p "#{f}".start_with?("#<Fiber:")
      e = [1, 2].each
      p "#{e}".start_with?("#<Enumerator")
      r.close
      w.close
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
    OUT
  end

  it "interpolated alias installs at runtime" do
    result = zr(<<~'RUBY')
      # The `alias` KEYWORD with an interpolated symbol -- `alias :"#{kind}_attr"
      # :"#{kind}_attrs"` -- has no compile-time spelling, but it is still just a
      # runtime install on the default definee, in class-body order.
      #
      # zr required a plain symbol and refused the whole file ("`alias`'s target
      # must be a plain method name") -- formal_wear builds its DSL in exactly
      # this loop.
      class Suit
        def tie_attrs
          ["windsor"]
        end

        kind = "tie"
        alias :"#{kind}_attr" :"#{kind}_attrs"
      end

      puts Suit.new.tie_attr.inspect

      # Top level: the same install onto Object.
      def given
        "given!"
      end

      adverb = "when"
      alias :"#{adverb}_step" :given
      puts when_step
    RUBY

    _(result).must_answer <<~'OUT'
      ["windsor"]
      given!
    OUT
  end

  it "interpolation multistmt" do
    result = zr(<<~'RUBY')
      # Issue #729. `"#{stmt1; stmt2; ...; stmtN}"` should evaluate every
      # statement in source order (for side effects) and use the LAST
      # statement's value in the string. spinel used to take stmts.first,
      # silently dropping later statements -- losing both their effects on
      # locals and the correct interpolation value.

      y = 0
      s = "#{y = 10; y = 20; y}"
      puts s
      puts y

      # Side effect persists outside the interpolation.
      counter = 0
      "#{counter += 1; counter += 1; counter += 1}"
      puts counter
    RUBY

    _(result).must_answer <<~'OUT'
      20
      20
      3
    OUT
  end

  it "interpolation symbol name" do
    result = zr(<<~'RUBY')
      # `"#{sym}"` should render the symbol's name, not its int id.
      # Pre-fix compile_interpolated had no symbol arm in its
      # type-dispatch switch, so the default int path emitted the raw
      # `sp_sym` value (`0`, `1`, ...) instead of routing through
      # sp_sym_to_s. Issue #633.

      s = :hello
      puts s
      puts "#{s}"
      puts s.to_s
      puts "x_#{s}_y"

      # Multiple symbols + literal mix in one interpolation.
      a = :alpha
      b = :beta
      puts "#{a}-#{b}"

      # Symbol from a method return; the call-site infers symbol type
      # and the same arm should fire.
      def make_sym
        :payload
      end
      puts "tag=#{make_sym}"
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      hello
      hello
      x_hello_y
      alpha-beta
      tag=payload
    OUT
  end

  it "module body string const interp" do
    result = zr(<<~'RUBY')
      # Interpolating a String constant defined in the same module/class body
      # must read the constant's value, not its raw pointer. Before, the
      # constant reference inside another constant's initializer was annotated
      # as Integer (the lexical scope was not set while caching the RHS), so
      # "v#{A}" emitted the pointer of A formatted as %lld.

      module M
        A = "33"
        V = "v#{A}"
      end
      puts M::V

      class C
        NAME = "spinel"
        GREETING = "hello #{NAME}"
      end
      puts C::GREETING

      # Chained-VERSION shape (e.g. libdatadog's VERSION = "#{LIB}.#{MAJOR}.#{MINOR}")
      module Lib
        LIB = "ddtrace"
        MAJOR = "1"
        MINOR = "2"
        VERSION = "#{LIB}-#{MAJOR}.#{MINOR}"
      end
      puts Lib::VERSION

      # Constant-to-constant value reference inside a body
      module V
        A = "hi"
        B = A
      end
      puts V::B

      # Control: an Integer constant interpolates as its number
      module I
        N = 33
        S = "n=#{N}"
      end
      puts I::S
    RUBY

    _(result).must_answer <<~'OUT'
      v33
      hello spinel
      ddtrace-1.2
      hi
      n=33
    OUT
  end

  it "a literal interpolates, indexes from either end, and takes an index write" do
    result = zr(<<~'RUBY')
      name = "world"
      greeting = "hello #{name}, #{1 + 2} times"
      puts(greeting)
      puts(greeting.length)
      puts(greeting[0])
      puts(greeting[-1])
      s = "cat"
      s[0] = "b"
      puts(s)
    RUBY

    _(result).must_answer <<~'OUT'
      hello world, 3 times
      20
      h
      s
      bat
    OUT
  end

  it "takes multi statement empty and braceless forms" do
    result = zr(<<~'RUBY')
      p "v=#{1; 2}"
      p "v=#{a = 3; a * 2}"
      p a
      p "x#{}y"
      $g = "glob"
      class C
        def initialize; @iv = "ivar"; end
        def show; "iv=#@iv g=#$g"; end
      end
      p C.new.show
    RUBY

    _(result).must_answer <<~'OUT'
      "v=2"
      "v=6"
      3
      "xy"
      "iv=ivar g=glob"
    OUT
  end
end
