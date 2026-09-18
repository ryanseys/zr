# frozen_string_literal: true

require "spec_helper"

describe "Hash: pattern matching" do
  it "case in hash binding" do
    result = ze0(<<~'RUBY')
      # case/in in value position with hash-pattern `=> name` bindings must bind.
      def s(x); x; end
      r = case s({name: "x", age: 5})
          in {name: String => n, age: Integer => a} then [n, a]
          end
      p r
      r2 = case s({name: "y", age: 9})
           in {name: String => n} then n
           end
      p r2
    RUBY

    _(result).must_answer <<~'OUT'
      ["x", 5]
      "y"
    OUT
  end

  it "case in hash pattern" do
    result = ze0(<<~'RUBY')
      # A hash pattern in `case/in` binds each value target (shorthand `{k:}`, `{k: v}`,
      # and capture `{k: Class => v}`) and matches only when the scrutinee is a hash
      # holding every key with each value matching its sub-pattern. Previously the
      # bindings came back nil. Each scrutinee routes through its own method param so
      # the runtime path runs; separate helpers keep each hash variant concrete.

      # class check + capture binding (the canonical form)
      def h1(x); x; end
      case h1({name: "x", age: 5})
      in {name: String => n, age: Integer => a} then p [n, a]   # ["x", 5]
      end

      # shorthand binding `{k:}`
      def h2(x); x; end
      case h2({a: 1, b: 2})
      in {a:, b:} then p [a, b]                                  # [1, 2]
      end

      # value class selects the arm
      def h3(x); x; end
      case h3({k: 5})
      in {k: String} then p :str
      in {k: Integer} then p :int                               # :int
      end

      # missing key -> no match
      def h4(x); x; end
      case h4({a: 1})
      in {b:} then p :y
      else p :no                                                 # :no
      end

      # value-binding to a named local (not shorthand)
      def h5(x); x; end
      case h5({n: "bob", role: "dev"})
      in {n: name, role: r} then p [name, r]                    # ["bob", "dev"]
      end

      # a non-matching class on a present key -> fall through
      def h6(x); x; end
      case h6({id: "abc"})
      in {id: Integer => i} then p i
      else p :nomatch                                            # :nomatch
      end

      # value bound from a poly-valued hash where the local is used as an array: the
      # binding must coerce to the array type, not assign a boxed value to a pointer.
      def h7(x); x; end
      case h7({items: [1, 2, 3], tag: "t"})
      in {items: arr} then p arr.sum                            # 6
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["x", 5]
      [1, 2]
      :int
      :no
      ["bob", "dev"]
      :nomatch
      6
    OUT
  end

  it "case in hash pattern binds value and rest" do
    result = ze0(<<~'RUBY')
      h = { a: 1, b: 2, c: 3 }
      case h
      in { a: Integer => av, **rest }
        puts av
        puts rest.length
      end
    RUBY

    _(result).must_answer "1\n2\n"
  end

  it "case in hash pattern no more keys rejects extra keys" do
    result = ze0(<<~'RUBY')
      case { a: 1 }
      in { a: 1, **nil }
        puts "exact match"
      end
      case { a: 1, b: 2 }
      in { a: 1, **nil }
        puts "should not print"
      else
        puts "extra keys rejected"
      end
    RUBY

    _(result).must_answer "exact match\nextra keys rejected\n"
  end

  it "case in hash pattern object" do
    result = ze0(<<~'RUBY')
      # Hash-pattern deconstruction in case/in: Struct/Data scrutinees route
      # through the synthesized deconstruct_keys, and the pattern-bound locals
      # carry usable types (boxed for object members, the variant's value type
      # for hash scrutinees).

      D = Data.define(:x, :y)
      def dsum(d); case d; in {x:, y:}; x + y; end; end
      p dsum(D.new(x: 3, y: 4))

      # a subset of the keys matches
      def dx(d); case d; in {x:}; x; end; end
      p dx(D.new(x: 9, y: 1))

      # literal value constraint picks the arm; bindings still work
      def dlit(d)
        case d
        in {x: 0, y:}; "zero #{y}"
        in {x:, y:}; "x #{x} y #{y}"
        end
      end
      p dlit(D.new(x: 0, y: 5))
      p dlit(D.new(x: 2, y: 5))

      S = Struct.new(:a, :b)
      def ssum(s); case s; in {a:, b:}; a + b; end; end
      p ssum(S.new(10, 20))

      # an unmatched constraint falls through to else
      def dnm(d)
        case d
        in {x: 100}; "hundred"
        else; "other"
        end
      end
      p dnm(D.new(x: 1, y: 2))

      # hash scrutinee bindings keep the variant's value type
      def hsum(h); case h; in {a:, b:}; a + b; end; end
      p hsum({a: 1, b: 2})

      def hjoin(h); case h; in {n:}; n * 2; end; end
      p hjoin({n: "ab"})

      # guards can read the bound variables
      def dguard(d)
        case d
        in {x:, y:} if x > y; "x>y"
        in {x:, y:}; "x<=y"
        end
      end
      p dguard(D.new(x: 5, y: 1))
      p dguard(D.new(x: 1, y: 5))
    RUBY

    _(result).must_answer <<~'OUT'
      7
      9
      "zero 5"
      "x 2 y 5"
      30
      "other"
      3
      "abab"
      "x>y"
      "x<=y"
    OUT
  end

  it "hash all pattern" do
    result = ze0(<<~'RUBY')
      # Hash#all?/any?/none?/one? with a pattern argument (KieranP #2338)
      p({ a: 1 }.all?([:a, 1]))
      p({ a: 1, b: 2 }.all?([:a, 1]))
      p({ a: 1, b: 2 }.any?([:b, 2]))
      p({ a: 1, b: 2 }.none?([:c, 3]))
      p({ a: 1, b: 2 }.one?([:a, 1]))
      p({ "a" => 1 }.all?(["a", 1]))
      p({ 1 => 10, 2 => 20 }.all?([1, 10]))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      true
      false
    OUT
  end

  it "hash pattern class union" do
    result = ze0(<<~'RUBY')
      # A hash pattern whose subject is a UNION of two user classes. The match reads
      # the subject through the runtime to_h hook, which knew only Struct and Data --
      # a user-defined #deconstruct_keys had no arm there, so no pattern matched and
      # the else raised, naming the very class the first pattern covers (#4019). With
      # ONE class the subject type is static and the method is called directly, which
      # is why the union was needed to see it.
      class Node
        def deconstruct_keys(keys) = to_h
      end

      class Lit < Node
        def initialize(v) = @v = v
        def to_h = { kind: :lit, value: @v }
      end

      class Col < Node
        def initialize(n) = @n = n
        def to_h = { kind: :col, value: @n }
      end

      def ev(node)
        case node
        in { kind: :lit, value: } then "lit #{value}"
        in { kind: :col, value: } then "col #{value}"
        else raise ArgumentError, "bad node #{node.class}"
        end
      end

      p ev(Lit.new(1))
      p ev(Col.new("x"))

      # the same shape without a shared base class, and reached through a container
      class Lit2
        def initialize(v) = @v = v
        def deconstruct_keys(keys) = { kind: :lit, value: @v }
      end

      class Col2
        def initialize(n) = @n = n
        def deconstruct_keys(keys) = { kind: :col, value: @n }
      end

      def ev2(node)
        case node
        in { kind: :lit, value: } then "lit #{value}"
        in { kind: :col, value: } then "col #{value}"
        else "none"
        end
      end

      p ev2(Lit2.new(2))
      p ev2(Col2.new("y"))
      p [Lit2.new(3), Col2.new("z")].map { |n| ev2(n) }

      # a Struct and a Data still answer their own members
      S = Struct.new(:a)
      def es(n)
        case n
        in { a: } then "s #{a}"
        else "none"
        end
      end
      p es(S.new(3))

      D = Data.define(:b)
      def ed(n)
        case n
        in { b: } then "d #{b}"
        else "none"
        end
      end
      p ed(D.new(b: 4))

      # a class with no deconstruct_keys still falls to the else arm
      class Plain; end
      p ev2(Plain.new)
    RUBY

    _(result).must_answer <<~'OUT'
      "lit 1"
      "col x"
      "lit 2"
      "col y"
      ["lit 3", "col z"]
      "s 3"
      "d 4"
      "none"
    OUT
  end

  it "oneline in hash" do
    result = ze0(<<~'RUBY')
      # One-line `expr in pattern` with a hash pattern and a class-checked capture.
      def s(x); x; end
      data = s({x: 5})
      matched = (data in {x: Integer => xv}); p matched
      b = (data in {x: Integer}); p b
      c = (data in {x: String});  p c
      d = (data in {y: Integer}); p d
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
    OUT
  end

  it "oneline in hash presence" do
    result = ze0(<<~'RUBY')
      # A bare `k:` in a one-line hash pattern is a presence-only test (no value
      # constraint); a `k: Class` check still constrains the value.
      def s(x); x; end
      h = s({a: 1, b: 2})
      p (h in {a:})
      p (h in {a:, b:})
      p (h in {c:})
      p (h in {a: Integer, b: Integer})
      p (h in {a: String})
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
    OUT
  end
end
