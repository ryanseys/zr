# frozen_string_literal: true

require "spec_helper"

describe "Pattern: pattern matching" do
  it "case in alternation pattern matches any member" do
    result = ze0(<<~'RUBY')
      case 3
      in 1 | 2 | 3
        puts "small"
      else
        puts "big"
      end
      case 99
      in 1 | 2 | 3
        puts "small"
      else
        puts "big"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      small
      big
    OUT
  end

  it "case in bare bind pattern matches anything" do
    _(ze0(<<~'RUBY')).must_answer "bound: 42\n"
      case 42
      in x
        puts "bound: #{x}"
      end
    RUBY
  end

  it "case in begin value position" do
    result = ze0(<<~'RUBY')
      # A `case/in` whose value is the tail of a `begin` block. The matched arm falls
      # through there rather than returning, so it ran straight into the no-match
      # raise that follows the arms -- every such case/in answered
      # NoMatchingPatternError however well it had just matched (#4016). The rescue
      # in the report is not the trigger: a bare `begin` does it too, and the pattern
      # kind does not matter either.
      r = (begin; case 5; in Integer then :m; end; end)
      p r

      r = (begin; case 5; in Integer then :m; end; rescue => e; e.class; end)
      p r

      class K; end
      r = (begin; case K.new; in K then :m; end; rescue => e; e.class; end)
      p r

      S = Struct.new(:x)
      r = (begin; case S.new(1); in S then :m; end; rescue => e; e.class; end)
      p r

      D = Data.define(:x)
      r = (begin; case D.new(x: 1); in D then :m; end; rescue => e; e.class; end)
      p r
      r = (begin; case D.new(x: 1); in { x: 1 } then :m; end; rescue => e; e.class; end)
      p r

      # a member-less Data value, which is what the report reduced to
      DML = Data.define
      r = (begin; case DML.new; in DML then :matched; end; rescue NoMatchingPatternError => e; e.class; end)
      p r

      # a genuine no-match still raises, from inside a begin and outside one
      r = (begin; case 5; in String then :s; end; rescue => e; e.class; end)
      p r

      def g(x)
        case x
        in Integer then :i
        end
      end
      p g(1)
      p (g("a") rescue $!.class)

      # an else arm keeps winning over the raise
      r = (begin; case 5; in String then :s; else :other; end; end)
      p r

      # and the statement and value forms outside a begin are unchanged
      case 5
      in Integer then p :stmt
      end
      p (case 5; in Integer then :val; end)
    RUBY

    _(result).must_answer <<~'OUT'
      :m
      :m
      :m
      :m
      :m
      :m
      :matched
      NoMatchingPatternError
      :i
      NoMatchingPatternError
      :other
      :stmt
      :val
    OUT
  end

  it "case in capture of a bare bind can write the same subject to two names" do
    result = ze0(<<~'RUBY')
      # A real latent hazard this test guards against: `Capture(Bind(x), y)`
      # writes the SAME scrutinee into two different locals -- if either write
      # MOVED instead of CLONED the scrutinee, the second write would fail to
      # compile ("use of moved value"). See `emit_pattern_match`'s docs.

      case 5
      in x => y
        puts x
        puts y
      end
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
    OUT
  end

  it "case in deconstruct" do
    _(ze0(<<~'RUBY')).must_answer "[1, 2]\n"
      # case/in against a custom #deconstruct (array pattern).
      class Pt; def deconstruct; [1, 2]; end; end
      r = case Pt.new
          in [a, b] then [a, b]
          end
      p r
    RUBY
  end

  it "case in deconstruct absent" do
    _(ze0(<<~'RUBY')).must_answer "\"nomatch\"\n"
      # An array pattern against an object with no #deconstruct never matches; the
      # arm fails closed and the else branch is taken (as in CRuby).
      class NoDe; end
      r = case NoDe.new
          in [a, b] then "matched"
          else "nomatch"
          end
      p r
    RUBY
  end

  it "case in deconstruct keys" do
    _(ze0(<<~'RUBY')).must_answer "[1, 2]\n"
      # case/in against a custom #deconstruct_keys (hash pattern).
      class Qt; def deconstruct_keys(k); {x: 1, y: 2}; end; end
      r = case Qt.new
          in {x:, y:} then [x, y]
          end
      p r
    RUBY
  end

  it "case in find pattern locates a matching window" do
    result = ze0(<<~'RUBY')
      case [1, 2, 3, 4, 5]
      in [*, Integer => a, Integer => b, *]
        puts "#{a} #{b}"
      end
      case [10, 20, 30]
      in [*, 99, *]
        puts "found 99"
      else
        puts "not found"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1 2
      not found
    OUT
  end

  it "case in mixed result type" do
    result = ze0(<<~'RUBY')
      # A case/in expression whose clauses return different types unifies to a poly
      # value, so a binding arm keeps its own type instead of being coerced to a
      # sibling arm's type. The scrutinee flows through a helper to defeat folding.
      def s(x); x; end

      # value-pattern arm returns String, binding arm returns Integer
      r1 = case s(9)
           in 0 then "zero"
           in n then n
           end
      p r1                       # 9 (bare Integer, not "9")

      # binding arm first (String), value-pattern arm second (Integer)
      r2 = case s(1)
           in n then "s#{n}"
           in 2 then 200
           end
      p r2                       # "s1"

      # three arms mixing String / Integer / the bound value
      r3 = case s(5)
           in 0 then "zero"
           in 1 then 100
           in n then n
           end
      p r3                       # 5

      # a guard arm binding, mixed with a String arm
      r4 = case s(7)
           in x if x > 10 then "big"
           in x then x
           end
      p r4                       # 7

      # the matching arm is the String one -> value is the String
      r5 = case s(0)
           in 0 then "zero"
           in n then n
           end
      p r5                       # "zero"

      # a bare local-variable scrutinee: its type is reset during the inference
      # fixpoint, so the binding arm must recover it from the prior iteration
      v = 9
      r6 = case v
           in 0 then "zero"
           in n then n
           end
      p r6                       # 9 (bare Integer, not "9")
    RUBY

    _(result).must_answer <<~'OUT'
      9
      "s1"
      5
      7
      "zero"
      9
    OUT
  end

  it "case in nil true false literal patterns" do
    result = ze0(<<~'RUBY')
      case nil
      in nil
        puts "was nil"
      end
      case true
      in true
        puts "was true"
      end
      case false
      in false
        puts "was false"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      was nil
      was true
      was false
    OUT
  end

  it "case in object with no deconstruct falls through to else" do
    _(ze0(<<~'RUBY')).must_answer "no deconstruct, fell to else\n"
      # An array pattern asks `#deconstruct` at run time; a class without
      # one simply does not match (no raise), so the `else` arm runs.

      class Plain
      end
      o = Plain.new
      case o
      in [a, b]
        puts "matched"
      else
        puts "no deconstruct, fell to else"
      end
    RUBY
  end

  it "case in pin pattern matches only the pinned value" do
    _(ze0(<<~'RUBY')).must_answer "different\n"
      x = 5
      case 10
      in ^x
        puts "same as x"
      else
        puts "different"
      end
    RUBY
  end

  it "class pattern user object" do
    result = ze0(<<~'RUBY')
      class Base; end
      class Sub < Base; end

      def kind(o)
        case o
        in Sub then "sub"
        in Base then "base"
        else "other"
        end
      end
      p kind(Sub.new)
      p kind(Base.new)

      class Other; end
      o = Other.new
      case o
      in Base then p "wrong"
      else p "right"
      end

      E = Data.define
      r = (E.new in E)
      p r
      F = Data.define(:a)
      r = (F.new(a: 1) in F)
      p r
      r = (F.new(a: 1) in E)
      p r
      G = Struct.new(:a)
      r = (G.new(1) in G)
      p r
      E2 = Data.define
      e2 = E2.new
      case e2
      in E2 then p "empty data match"
      else p "empty data MISS"
      end

      F2 = Data.define(:a)
      f2 = F2.new(a: 1)
      case f2
      in F2 then p "data match"
      else p "data MISS"
      end

      G2 = Struct.new(:a)
      g2 = G2.new(1)
      case g2
      in G2 then p "struct match"
      else p "struct MISS"
      end

      class H2; end
      h2 = H2.new
      case h2
      in H2 then p "class match"
      else p "class MISS"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "sub"
      "base"
      "right"
      true
      true
      false
      true
      "empty data match"
      "data match"
      "struct match"
      "class match"
    OUT
  end

  it "every pattern form over one failure block" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # `case/in`, `expr in pattern` and `expr => pattern`. A pattern is a
      # chain of sub-checks over one shared failure block: it matches when it
      # reaches the end without jumping, and what it bound on the way survives
      # a later check's failure, as ruby's does.

      def kind(v)
        case v
        in Integer then :int
        in String then :str
        in nil then :nil
        in [1, 2] then :pair
        else :other
        end
      end

      p kind(1), kind("a"), kind(nil), kind([1, 2]), kind(:z)

      def shape(v)
        case v
        in [] then :empty
        in [Integer => n] then [:one, n]
        in [1, *rest, 9] then [:bracketed, rest]
        in [*, :mid, *] then :found
        in [a, [b, c]] then [:nested, a, b, c]
        in { name: String => nm, age: Integer } then [:person, nm]
        in { only: } then [:only, only]
        in { a: 1, **r } then [:rest, r]
        in {} then :empty_hash
        in 1..5 then :small
        in 10 | 20 | 30 then :round
        in Integer | Float => num then [:number, num]
        else :none
        end
      end

      [
        [], [7], [1, 2, 3, 9], [:x, :mid, :y], [1, [2, 3]],
        { name: "n", age: 3 }, { only: 5 }, { a: 1, b: 2 },
        {}, 3, 20, 4.5, :zz,
      ].each { |v| p shape(v) }

      # A class with the two protocols answers both an array and a hash
      # pattern. `**rest` hands `deconstruct_keys` nil, which is what tells it
      # the pattern will take everything.
      class Pair
        def initialize(a, b) = (@a, @b = a, b)
        def deconstruct = [@a, @b]
        def deconstruct_keys(keys) = { a: @a, b: @b, keys: keys }
      end

      pair = Pair.new("x", "y")

      case pair
      in [one, two] then p [:arr, one, two]
      end

      case pair
      in { a:, keys: } then p [:keys, a, keys]
      end

      case pair
      in { **all } then p [:all, all]
      end

      # A Struct, and one named through a scope.
      Point = Struct.new(:x, :y)
      p(case Point.new(1, 2)
        in Point[x, y] then [:brackets, x, y]
        end)
      p(case Point.new(3, 4)
        in Point(x:, y:) then [:parens, x, y]
        end)

      module Geo
        Line = Struct.new(:a, :b)
      end

      case Geo::Line.new(5, 6)
      in Geo::Line[a, b] then p [:scoped, a, b]
      end

      # A pin matches a value the pattern cannot spell, and any object whose
      # `===` answers.
      expected = 5
      case 5
      in ^expected then p :pinned
      end

      case 3
      in ^(1 + 2) then p :pinned_expression
      end

      over_three = ->(v) { v > 3 }
      case 5
      in ^over_three then p :pinned_proc
      end

      # A guard is its own reason: the pattern matched and the condition did
      # not.
      case [1, 2, 3]
      in [Integer => first, *] if first.positive? then p [:guard, first]
      end

      case [4]
      in [only] unless only.zero? then p [:unless, only]
      end

      p((1 in Integer))
      p(([1, 2] in [_, _]))
      p(({ a: 1 } in { a: Integer }))
      p((:z in Integer))

      held = { a: 1, b: 2 }
      held => { a: }
      p a

      # The bindings reach the scope around the `case`.
      case { name: "zeo", version: [0, 1, 0] }
      in { name: String => found, version: [major, minor, *] }
        nil
      end
      p found, major, minor

      # An arm with no body answers nil.
      p(case 1
        in Integer
        end)

      def first_string(list)
        case list
        in [*, String => s, *] then return s
        in [] then :empty
        else :none
        end
      end

      p first_string([1, "hit", 2]), first_string([]), first_string([1])

      # Every refusal names the same reason the runtime's own raise does.
      def refused
        yield
      rescue NoMatchingPatternKeyError => e
        [e.class, e.message, e.key, e.matchee]
      rescue NoMatchingPatternError => e
        [e.class, e.message]
      rescue TypeError, ArgumentError => e
        [e.class, e.message]
      end

      p refused { 5 => String }
      p refused { { a: 1 } => { b: } }

      p refused {
        case 9
        in String then 1
        in Float then 2
        end
      }

      p refused {
        case 9
        in String then 1
        end
      }

      p refused {
        case [1, 2]
        in [1] then :no
        end
      }

      p refused {
        case [1, 2, 3]
        in [*, 9, *] then :no
        end
      }

      p refused {
        case { a: 1, b: 2 }
        in { a:, **nil } then :no
        end
      }

      p refused {
        case({ a: 1 })
        in {} then :no
        end
      }

      p refused {
        case 1
        in Integer if false then :no
        end
      }

      class NotAnArray
        def deconstruct = :nope
      end

      class NotAHash
        def deconstruct_keys(_keys) = :nope
      end

      class Angry
        def ===(_other) = raise(ArgumentError, "from ===")
      end

      p refused {
        case NotAnArray.new
        in [x] then x
        end
      }

      p refused {
        case NotAHash.new
        in { a: } then a
        end
      }

      p refused {
        case 1
        in ^(Angry.new) then :no
        end
      }
    RUBY

    _(result).must_answer <<~'OUT'
      :int
      :str
      :nil
      :pair
      :other
      :empty
      [:one, 7]
      [:bracketed, [2, 3]]
      :found
      [:nested, 1, 2, 3]
      [:person, "n"]
      [:only, 5]
      [:rest, {b: 2}]
      :empty_hash
      :small
      :round
      :small
      :none
      [:arr, "x", "y"]
      [:keys, "x", [:a, :keys]]
      [:all, {a: "x", b: "y", keys: nil}]
      [:brackets, 1, 2]
      [:parens, 3, 4]
      [:scoped, 5, 6]
      :pinned
      :pinned_expression
      :pinned_proc
      [:guard, 1]
      [:unless, 4]
      true
      true
      true
      false
      1
      "zeo"
      0
      1
      nil
      "hit"
      :empty
      :none
      [NoMatchingPatternError, "5: String === 5 does not return true"]
      [NoMatchingPatternKeyError, "{a: 1}: key not found: :b", :b, {a: 1}]
      [NoMatchingPatternError, "9"]
      [NoMatchingPatternError, "9: String === 9 does not return true"]
      [NoMatchingPatternError, "[1, 2]: [1, 2] length mismatch (given 2, expected 1)"]
      [NoMatchingPatternError, "[1, 2, 3]: [1, 2, 3] does not match to find pattern"]
      [NoMatchingPatternError, "{a: 1, b: 2}: rest of {b: 2} is not empty"]
      [NoMatchingPatternError, "{a: 1}: {a: 1} is not empty"]
      [NoMatchingPatternError, "1: guard clause does not return true"]
      [TypeError, "deconstruct must return Array"]
      [TypeError, "deconstruct_keys must return Hash"]
      [ArgumentError, "from ==="]
    OUT
  end

  it "find pattern poly scrutinee" do
    result = ze0(<<~'RUBY')
      # A find pattern (`in [*head, x, y, *tail]`) against a poly scrutinee -- a value
      # not statically known to be an array (a recursive parameter, or one unified with
      # a scalar). It is coerced to a poly array at runtime; a non-array (or nil) never
      # matches, so the else arm runs.
      def f(dish)
        case dish
        in [*head, :a, :b, *tail]
          [head, :ab, tail]
        else
          dish
        end
      end
      p f([:x, :a, :b, :y])   # [[:x], :ab, [:y]]
      p f([:a, :b])           # [[], :ab, []]
      p f([:p, :q])           # [:p, :q]
      p f(:scalar)            # :scalar (a non-array never matches)

      # a statically non-array scrutinee never matches a find pattern (fail closed)
      def h(n)
        case n
        in [*_pre, :a, *_post] then :matched
        else :nomatch
        end
      end
      p h(42)       # :nomatch
      p h("hi")     # :nomatch
    RUBY

    _(result).must_answer <<~'OUT'
      [[:x], :ab, [:y]]
      [[], :ab, []]
      [:p, :q]
      :scalar
      :nomatch
      :nomatch
    OUT
  end

  it "find pattern tries each place afresh" do
    result = ze0(<<~'RUBY')
      # A find pattern tries its middle at each place in turn, and a nested
      # pattern there asks `deconstruct` of that place's element, not of the
      # first one it met.
      case [[1], [2]]
      in [*, [2], *] then p :ok
      end

      case [[1, 2], [3, 4], [5, 6]]
      in [*pre, [5, y], *post] then p [pre, y, post]
      end

      case [{k: 1}, {k: 2}]
      in [*, {k: 2 => two}, *] then p two
      end

      p(([[0], [9]] in [*, [9], *]))
      p(([[0], [8]] in [*, [9], *]))

    RUBY

    _(result).must_answer <<~'OUT'
      :ok
      [[[1, 2], [3, 4]], 6, []]
      2
      true
      false
    OUT
  end

  it "names the core classes whatever the program names" do
    result = ze0(<<~'RUBY')
      # What a pattern and a numeric literal build on is the core's own Array,
      # Hash, TypeError and Kernel, not whatever the program's scope names so,
      # and a class with no Kernel still makes `3r` and `2i`.
      module Shadows
        class Array; end
        class Hash; end
        class TypeError < StandardError; end
        class NoMatchingPatternError < StandardError; end

        case [1]
        in [x] then p x
        end

        case {a: 1}
        in {a:} then p a
        end

        begin
          case 5
          in [_] then p :no
          end
        rescue ::NoMatchingPatternError => e
          p e.class
        end

        odd = Object.new
        def odd.deconstruct = :nope
        begin
          case odd
          in [_] then p :no
          end
        rescue ::TypeError => e
          p [e.class, e.message]
        end
      end

      class Bare < BasicObject
        def values = [3r, 2i]
      end
      p Bare.new.values

    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      NoMatchingPatternError
      [TypeError, "deconstruct must return Array"]
      [(3/1), (0+2i)]
    OUT
  end

  it "one line in deconstruct" do
    result = ze0(<<~'RUBY')
      class N
        def deconstruct_keys(keys) = { kind: :binop, n: 1 }
      end
      r = (N.new in { kind: :binop })
      p r
      r = (N.new in { kind: :other })
      p r
      r = (N.new in { kind: :binop, n: 1 })
      p r

      class M
        def deconstruct = [1, 2]
      end
      r = (M.new in [1, 2])
      p r
      r = (M.new in [1, 3])
      p r

      S = Struct.new(:kind, :n)
      r = (S.new(:binop, 1) in { kind: :binop })
      p r
      r = (S.new(:binop, 1) in { kind: :other })
      p r

      D = Data.define(:kind)
      r = (D.new(kind: :binop) in { kind: :binop })
      p r

      case N.new
      in { kind: :binop } then p "case ok"
      else p "case miss"
      end

      r = ({ kind: :binop } in { kind: :binop })
      p r
      r = ([1, 2] in [1, 2])
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      false
      true
      false
      true
      "case ok"
      true
      true
    OUT
  end

  it "oneline in pattern bind" do
    result = ze0(<<~'RUBY')
      # A one-line boolean `expr in pattern` binds the pattern's captured locals in
      # the enclosing scope on a successful match (like `value => pattern`, but
      # returning a boolean instead of raising).
      x = [1, 2]
      if x in [a, b]
        puts "matched #{a} #{b}"
      else
        puts "no"
      end
      y = [10, 20, 30]
      if y in [head, *rest]
        puts "head=#{head} rest=#{rest.inspect}"
      end
      h = {name: "ruby", ver: 3}
      if h in {name: String => n, ver: Integer => v}
        puts "#{n} #{v}"
      end
      if 5 in Integer => q
        puts "q=#{q}"
      end
      z = [1, 2]
      puts((z in [Integer, Integer]) ? "ints" : "no")
      puts((z in [String, String]) ? "strs" : "no-match")
    RUBY

    _(result).must_answer <<~'OUT'
      matched 1 2
      head=10 rest=[20, 30]
      ruby 3
      q=5
      ints
      no-match
    OUT
  end

  it "parenthesized pattern is the pattern inside" do
    result = ze0(<<~'RUBY')
      # `(A | B)` in pattern position is just the alternation inside -- prism
      # wraps it in a ParenthesesNode, and the pattern walk must unwrap it both
      # where it stands alone and where a capture binds it.
      #
      # zeo's pattern lowering had no parentheses arm, so the node fell through
      # to the generic expression rejection ("unsupported syntax at \"Integer |
      # String\"") -- anthropic's credential reader and jpt's path parser both
      # spell it this way.
      config = { expires_in: 300 }
      case config
      in { expires_in: (Integer | String) => expires_in }
        puts "expires: #{expires_in}"
      end

      segments = ["@", "name", "first"]
      case segments
      in [("@" | "$"), *rest]
        puts "anchored, rest=#{rest.inspect}"
      end

      case 42
      in (Integer | Float)
        puts "numeric"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      expires: 300
      anchored, rest=["name", "first"]
      numeric
    OUT
  end

  it "pattern" do
    result = ze0(<<~'RUBY')
      # Test pattern matching (case/in)

      # Type-based matching
      def describe(val)
        case val
        in Integer
          "integer: #{val}"
        in String
          "string: #{val}"
        in Float
          "float"
        in true | false
          "boolean"
        in nil
          "nil"
        end
      end

      puts describe(42)       # integer: 42
      puts describe("hello")  # string: hello
      puts describe(3.14)     # float
      puts describe(true)     # boolean
      puts describe(nil)      # nil

      # Value matching
      def check(x)
        case x
        in 0
          "zero"
        in 1
          "one"
        in Integer
          "other int"
        end
      end

      puts check(0)   # zero
      puts check(1)   # one
      puts check(99)  # other int

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      integer: 42
      string: hello
      float
      boolean
      nil
      zero
      one
      other int
      done
    OUT
  end

  it "pattern deconstruct" do
    result = ze0(<<~'RUBY')
      # A user object used as a pattern-match scrutinee must be asked to deconstruct
      # itself: #deconstruct for an array pattern, #deconstruct_keys for a hash
      # pattern -- including value-type objects, which the lowering previously
      # excluded (they fell through to the reject path and raised "no pattern
      # matched"). A value-type object is passed to the deconstruct method by value;
      # a heap object by pointer.

      class Pt
        def initialize(x, y) = (@x, @y = x, y)
        def deconstruct = [@x, @y]
        def deconstruct_keys(k) = { x: @x, y: @y }
      end

      # 1. Array pattern via #deconstruct.
      case Pt.new(3, 4)
      in [a, b]; p [a, b]; end                 #=> [3, 4]

      # 2. Hash pattern via #deconstruct_keys.
      case Pt.new(1, 2)
      in { x:, y: }; p [x, y]; end             #=> [1, 2]

      # 3. Hash pattern with a subset of keys.
      case Pt.new(5, 6)
      in { x: }; p x; end                      #=> 5

      # 4. Array pattern with a guard.
      case Pt.new(7, 8)
      in [a, b] if a < b; p "ordered"; end     #=> "ordered"

      # 5. A literal element is value-checked against the deconstructed array.
      case Pt.new(9, 9)
      in [a, 9]; p "y=#{a}"; end               #=> "y=9"

      # 6. Arity drives which arm matches.
      r = case Pt.new(1, 2)
          in [a, b, c]; "three"
          in [a, b]; "two"
          end
      p r                                      #=> "two"

      # 7. An object without #deconstruct falls through (no crash).
      class Plain
        def initialize = (@v = 1)
      end
      res = case Plain.new
            in [a]; "arr"
            else; "else"
            end
      p res                                    #=> "else"

      # 8. A heap object (array ivar) with #deconstruct + a splat pattern.
      class Box
        def initialize(items) = (@items = items)
        def deconstruct = @items
      end
      case Box.new([10, 20, 30])
      in [x, *rest]; p [x, rest]; end          #=> [10, [20, 30]]

      # 9. Struct inline synthesis (no user-defined #deconstruct): array and hash.
      S = Struct.new(:x, :y)
      case S.new(100, 200)
      in [a, b]; p [a, b]; end                 #=> [100, 200]
      case S.new(300, 400)
      in { x:, y: }; p [x, y]; end             #=> [300, 400]

      # 10. Data inline synthesis (a pure value-type): array and hash.
      D = Data.define(:x, :y)
      case D.new(5, 6)
      in [a, b]; p [a, b]; end                 #=> [5, 6]
      case D.new(7, 8)
      in { x:, y: }; p [x, y]; end             #=> [7, 8]

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4]
      [1, 2]
      5
      "ordered"
      "y=9"
      "two"
      "else"
      [10, [20, 30]]
      [100, 200]
      [300, 400]
      [5, 6]
      [7, 8]
      done
    OUT
  end

  it "pattern element subpatterns" do
    result = ze0(<<~'RUBY')
      # Element sub-pattern checks and binding descent in container patterns:
      # class/alternation/range guards on array elements, nested hash patterns
      # under hashes and arrays, find patterns nested in hash values, and
      # capture bindings inside find windows.

      # class/constant element guards on a mixed (poly) array
      def cls_guard(x); case x; in [String, Integer]; :match; else :no; end; end
      p cls_guard([1, "s"])
      p cls_guard(["s", 1])

      # alternation as an array element (typed int array scrutinee)
      def alt_elem(x); case x; in [0 | 1 | 2]; "low"; else "other"; end; end
      p alt_elem([10])
      p alt_elem([1])

      # alternation as a hash value
      def alt_hval(h); case h; in {a: 1 | 2}; "onetwo"; else "other"; end; end
      p alt_hval({a: 3})
      p alt_hval({a: 2})

      # range as an array element
      def rng_elem(x); case x; in [1..5, y]; y; else :no; end; end
      p rng_elem([3, 9])
      p rng_elem([7, 9])

      # find pattern with a literal-plus-binding capture in the window
      def find_cap(xs); case xs; in [*, 3 => x, *]; x; else nil; end; end
      p find_cap([1, 2, 3, 4])
      p find_cap([1, 2])

      # find window splats bind
      def find_splats(xs)
        case xs
        in [*pre, 9, *post]; [pre, post]
        else nil
        end
      end
      p find_splats([1, 2, 9, 4])
      p find_splats([9])

      # find pattern nested inside a hash value
      def find_in_hash(x); case x; in {data: [*, y, *]}; y; end; end
      p find_in_hash({data: [1, 2, 3]})

      # nested hash-in-hash binding
      config = {a: {b: 42}}
      case config
      in {a: {b:}}
        p b
      end

      # hash-in-array element with binding
      def hash_in_arr(x); case x; in [{name:}]; name; else :no; end; end
      p hash_in_arr([{name: "z"}])
      p hash_in_arr([3])

      # nested value constraints pick the right arm
      def deep(x)
        case x
        in {a: {b: 0}}; "zero"
        in {a: {b:}}; "b #{b}"
        else "none"
        end
      end
      p deep({a: {b: 0}})
      p deep({a: {b: 7}})
      p deep({a: {c: 1}})
    RUBY

    _(result).must_answer <<~'OUT'
      :no
      :match
      "other"
      "low"
      "other"
      "onetwo"
      9
      :no
      3
      nil
      [[1, 2], [4]]
      [[], []]
      1
      42
      "z"
      :no
      "zero"
      "b 7"
      "none"
    OUT
  end

  it "pattern keys and nesting" do
    result = ze0(<<~'RUBY')
      # Two pattern-matching reports.
      #
      # A hash pattern naming specific keys calls `#deconstruct_keys` with an
      # Array of just those keys, reserving `nil` for a pattern that can take
      # everything (`**rest`, `**nil`, or no keys at all). Every match passed
      # `nil`, so an implementation that builds only what was asked for could not
      # tell the two cases apart -- and one that BRANCHES on nil took the wrong
      # branch.
      #
      # And `expr => pattern` has its own destructuring emitter, which binds
      # direct local targets only; a nested class pattern bound nothing and
      # raised nothing, so the local came out nil. Such a pattern is rewritten to
      # the one-arm `case ... in ... end` it is defined to mean.

      class Probe
        def deconstruct_keys(keys)
          p keys
          { a: 1, b: 2, c: 3 }
        end
      end

      case Probe.new
      in { a: } then puts "matched"
      end

      case Probe.new
      in { a:, c: } then puts "two"
      end

      case Probe.new
      in { **rest } then p rest.size
      end

      Probe.new => { b: bv }
      p bv

      class Node
        attr_reader :left
        def initialize(left) = @left = left
        def deconstruct_keys(keys) = { left: @left }
      end

      class Lit
        attr_reader :value
        def initialize(value) = @value = value
        def deconstruct_keys(keys) = { value: @value }
      end

      Node.new(Lit.new(1)) => { left: Lit(value: lv) }
      p lv

      Node.new(Lit.new(7)) => { left: { value: v2 } }
      p v2

      case Node.new(Lit.new(3))
      in { left: Lit(value: cv) } then p cv
      end

      # the flat shapes the dedicated emitter still handles
      { a: 1, b: 2 } => { a:, b: }
      p [a, b]
      [1, 2] => [x, y]
      p [x, y]

      begin
        Node.new(Lit.new(1)) => { left: Integer => bad }
      rescue NoMatchingPatternError, NoMatchingPatternKeyError => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:a]
      matched
      [:a, :c]
      two
      nil
      3
      [:b]
      2
      1
      7
      3
      [1, 2]
      [1, 2]
      NoMatchingPatternError
    OUT
  end

  it "pattern matching" do
    result = ze0(<<~'RUBY')
      case 5
      in Integer => n
        puts n + 1
      end

      case [1, 2, 3]
      in [Integer => a, *rest]
        puts a
        puts rest.length
      end

      case [1, 2, 3, 4, 5]
      in [*pre, 3, *post]
        puts pre.length
        puts post.length
      end

      x = 5
      case 10
      in ^x
        puts "same as x"
      else
        puts "different"
      end

      case 3
      in 1 | 2 | 3
        puts "small"
      else
        puts "big"
      end

      class Classifier
        def classify(v)
          case v
          in Integer => n if n % 2 == 0
            "even int #{n}"
          in Integer
            "odd int"
          in String
            "string"
          else
            "other"
          end
        end
      end
      c = Classifier.new
      puts c.classify(4)
      puts c.classify(3)
      puts c.classify("hi")

      h = { a: 1, b: 2, c: 3 }
      case h
      in { a: Integer => av, **rest }
        puts av
        puts rest.length
      end

      case { a: 1 }
      in { a: 1, **nil }
        puts "exact match"
      end

      case [1, 2, 3, 4, 5]
      in [*, Integer => mid1, Integer => mid2, *]
        puts "#{mid1} #{mid2}"
      end

      case 5
      in 1..10
        puts "in range"
      end

      class Point
        def initialize(x, y)
          @x = x
          @y = y
        end
        def deconstruct
          [@x, @y]
        end
        def deconstruct_keys(keys)
          { x: @x, y: @y }
        end
      end

      p1 = Point.new(1, 2)
      case p1
      in [px, py]
        puts "array: #{px}, #{py}"
      end
      case p1
      in Point(x:, y:)
        puts "constant: #{x}, #{y}"
      end

      if [1, 2] in [Integer, Integer]
        puts "matched predicate"
      end

      arr = [1, 2]
      arr => [first, second]
      puts first
      puts second

      case nil
      in nil
        puts "was nil"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      6
      1
      2
      2
      2
      different
      small
      even int 4
      odd int
      string
      1
      2
      exact match
      1 2
      in range
      array: 1, 2
      constant: 1, 2
      matched predicate
      1
      2
      was nil
    OUT
  end

  it "pattern methodobj kwsplat undersupply" do
    result = ze0(<<~'RUBY')
      # Under-supplied calls raise at runtime in value position, `Class => var`
      # bindings in typed-array patterns, hash-pattern **rest / **nil, Method
      # objects over builtin receivers, **hash degrading into *args, char-range
      # Enumerable methods, and String accumulators in each_with_object.
      def m(a, b) = a + b
      begin
        puts m(1)
      rescue ArgumentError => e
        puts "caught: #{e.message}"
      end
      def kw(a:, b:) = a + b
      begin
        puts kw(a: 1)
      rescue ArgumentError => e
        puts "caught: #{e.message}"
      end
      case [1, 2]
      in [Integer => x, Integer => y]
        p [x, y]
      end
      case [1, 2]
      in [Integer => x, String => y]
        p "wrong"
      else
        p "no match ok"
      end
      h = { a: 1, b: 2, c: 3 }
      case h
      in {a:, **rest}
        p a
        p rest
      end
      case { x: 1, y: 2 }
      in {x:, **nil}
        p "wrong"
      else
        p "nil rest rejects extras"
      end
      p "hello".method(:upcase).call
      p [1, 2, 3].method(:sum).call
      p 5.method(:abs).call
      mo = "hi".method(:upcase)
      p mo.class
      p mo.call
      def foo(*args); args; end
      hh = { x: 1 }
      p foo(**hh)
      p foo(1, **hh)
      def bar(*args, **opts); [args, opts]; end
      p bar(**hh)
      p ("a".."e").each_slice(2).to_a
      p ("a".."e").each_cons(2).to_a
      p ("a".."c").map { |s| s * 2 }
      p [1, 2, 3].each_with_object("") { |x, s| s << x.to_s }
      p [1, 2, 3].each_with_object("x") { |i, s| s << "-" }
    RUBY

    _(result).must_answer <<~'OUT'
      caught: wrong number of arguments (given 1, expected 2)
      caught: missing keyword: :b
      [1, 2]
      "no match ok"
      1
      {b: 2, c: 3}
      "nil rest rejects extras"
      "HELLO"
      6
      5
      Method
      "HI"
      [{x: 1}]
      [1, {x: 1}]
      [[], {x: 1}]
      [["a", "b"], ["c", "d"], ["e"]]
      [["a", "b"], ["b", "c"], ["c", "d"], ["d", "e"]]
      ["aa", "bb", "cc"]
      "123"
      "x---"
    OUT
  end

  it "pattern object deconstruct element types" do
    result = ze0(<<~'RUBY')
      # An array pattern over an object binds what its #deconstruct returns: the
      # elements used to default to Integer, so a Symbol element bound its boxed bits
      # as a small int (#3954).
      class Sym
        def deconstruct = [:x, :y]
      end
      case Sym.new
      in [a, b] then p [a, b]
      end

      class Mixed
        def deconstruct = ["s", 1]
      end
      case Mixed.new
      in [ma, mb] then p [ma, mb]
      end

      class Ints
        def deconstruct = [1, 2, 3]
      end
      case Ints.new
      in [ia, *irest] then p [ia, irest]
      end

      class Strs
        def deconstruct = %w[p q r]
      end
      case Strs.new
      in [sa, *srest] then p [sa, srest]
      end

      class Node
        def initialize(k, v)
          @k = k
          @v = v
        end
        def deconstruct = [@k, @v]
      end
      case Node.new(:binop, 7)
      in [k, v] then p [k, v]
      end

      # Two arms whose bindings share a name over different array kinds: the rest
      # slice takes the boxed form the required bindings already used.
      class I2; def deconstruct = [1, 2, 3]; end
      class S2; def deconstruct = %w[p q r]; end
      case I2.new
      in [h, *t] then p [h, t]
      end
      case S2.new
      in [h, *t] then p [h, t]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:x, :y]
      ["s", 1]
      [1, [2, 3]]
      ["p", ["q", "r"]]
      [:binop, 7]
      [1, [2, 3]]
      ["p", ["q", "r"]]
    OUT
  end

  it "pattern pin" do
    result = ze0(<<~'RUBY')
      # Pattern matching: PinnedExpressionNode + PinnedVariableNode.
      #
      # Pin patterns match the scrutinee by `==` against the value of an
      # existing local / ivar / arbitrary expression -- they do not bind
      # new variables. Both prism node types (PinnedVariableNode for `^var`
      # and PinnedExpressionNode for `^(expr)`) are routed through the
      # shared `@nd_expression` slot so the codegen treats them uniformly.

      # --- Pin against int local
      x = 42
      case 42
      in ^x
        puts "pin int match"
      in 0
        puts "zero"
      end

      # --- Pin miss falls through to next arm / else
      y = 10
      case 42
      in ^y
        puts "pin y match"
      else
        puts "no pin y"
      end

      # --- Pin against string local
      s = "hello"
      case "hello"
      in ^s
        puts "pin str match"
      end

      # Pin string miss
      t = "goodbye"
      case "hello"
      in ^t
        puts "pin t"
      else
        puts "no pin t"
      end

      # --- Pin against arbitrary expression `^(expr)`
      val = 7
      case 21
      in ^(val * 3)
        puts "pin expr 21"
      else
        puts "miss"
      end

      # Pin expression with method call
      def double(n)
        n * 2
      end
      case 14
      in ^(double(7))
        puts "pin call 14"
      end

      # --- Pin against symbol
      sym = :foo
      case :foo
      in ^sym
        puts "pin sym match"
      end

      # Symbol miss
      case :bar
      in ^sym
        puts "pin sym bar"
      else
        puts "no sym bar"
      end

      # --- Pin works alongside literal arms in same case
      mode = :verbose
      case :verbose
      in :quiet
        puts "q"
      in ^mode
        puts "pin mode hit"
      in :other
        puts "o"
      end

      # --- Pin against ivar
      class Box
        def initialize(v)
          @v = v
        end

        def matches(x)
          case x
          in ^@v
            "ivar match"
          else
            "no match"
          end
        end
      end

      b = Box.new(99)
      puts b.matches(99)
      puts b.matches(100)
    RUBY

    _(result).must_answer <<~'OUT'
      pin int match
      no pin y
      pin str match
      no pin t
      pin expr 21
      pin call 14
      pin sym match
      no sym bar
      pin mode hit
      ivar match
      no match
    OUT
  end

  it "pattern poly scrutinee bindings" do
    result = ze0(<<~'RUBY')
      # Array-pattern bindings against a poly/untyped VALUE scrutinee must be boxed
      # (poly), not int. A helper widened to an untyped return by extra call sites
      # used to type the rest slice / required element as int and reinterpret the
      # boxed element bits -> garbage output.

      def poly(a) = a

      # widen poly()'s inferred element union to include a nested-array type so the
      # return type collapses to untyped (the trigger for the original miscompile).
      _z1 = poly([1, 2, [3, 4]])
      _z2 = poly([1, 2, 5])

      # rest slice: pre must be a poly array of the leading elements.
      case poly([1, "x", 3, 4])
      in [*pre, last]; p [pre, last]; end          #=> [[1, "x", 3], 4]

      # required head + rest: first must keep its (boxed) value, rest the remainder.
      case poly(["x", 1, 2, 3])
      in [first, *rest]; p [first, rest]; end       #=> ["x", [1, 2, 3]]

      # a middle required between splats (FindPattern) on the same poly helper.
      case poly([1, "a", 2, "b", 3])
      in [*, mid, *]; p mid; end                    #=> 1  (first non-greedy middle)

      # regression: a Data value-type object still binds its members (non-splat).
      D = Data.define(:x, :y)
      case D.new(5, 6)
      in [a, b]; p [a, b]; end                      #=> [5, 6]
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, "x", 3], 4]
      ["x", [1, 2, 3]]
      1
      [5, 6]
    OUT
  end

  it "pattern post splat" do
    result = ze0(<<~'RUBY')
      # Array and find patterns must bind fixed elements that come AFTER a splat.
      #
      # The array-pattern lowering handled `requireds` (before the splat) and `rest`
      # (the splat), but ignored `posts` (fixed elements after the splat): the rest
      # slice greedily grabbed everything to the end, so `[*pre, last]` bound
      # pre=[1,2,3,4] and last=nil, and a post literal was never checked. The find
      # pattern (`[*, lit => x, *]`) only bound plain LocalVariableTargetNode window
      # elements, skipping a `lit => x` capture -- so x came back nil.
      #
      # Fix: count posts in the length check, value-check post literals from the tail,
      # slice the rest as the middle (drop the posts), and bind posts by index from the
      # end; bind a capture target in a find-pattern window.

      # 1. Splat then one fixed (typed array).
      case [1, 2, 3, 4]
      in [*pre, last]; p [pre, last]; end          #=> [[1, 2, 3], 4]

      # 2. Fixed, splat, fixed.
      case [1, 2, 3, 4]
      in [a, *mid, z]; p [a, mid, z]; end           #=> [1, [2, 3], 4]

      # 3. Two leading, splat, one trailing.
      case [1, 2, 3, 4, 5]
      in [x, y, *rest, w]; p [x, y, rest, w]; end    #=> [1, 2, [3, 4], 5]

      # 4. A post literal must match / mismatch drives the arm.
      case [1, 2, 9]
      in [*, 9]; p "matched"; end                    #=> "matched"
      case [1, 2, 8]
      in [*, 9]; p "no"
      else; p "fellthrough"; end                     #=> "fellthrough"

      # 5. Regression: leading fixed + trailing splat still works.
      case [1, 2, 3]
      in [first, *r]; p [first, r]; end              #=> [1, [2, 3]]

      # 6. Regression: exact (no rest) still works.
      case [1, 2]
      in [a, b]; p [a, b]; end                       #=> [1, 2]

      # 7. Find pattern: a `lit => x` capture binds x.
      case [1, 2, 3, 4]
      in [*, 3 => x, *]; p x; end                    #=> 3

      # 8. Find pattern with leading and trailing splats bound too.
      case [1, 2, 3, 4, 5]
      in [*hd, 3 => m, *tl]; p [hd, m, tl]; end       #=> [[1, 2], 3, [4, 5]]

      # 9. Poly array (routed through a single-call-site method to defeat
      #    const-folding while keeping the scrutinee cleanly poly).
      def poly(a) = a
      case poly([1, "x", 3, 4])
      in [*p2, l2]; p [p2, l2]; end                  #=> [[1, "x", 3], 4]

      # 10. Anonymous rest between fixed head and tail (typed array).
      case [1, 2, 3]
      in [first, *, last]; p [first, last]; end       #=> [1, 3]

      # A separate poly helper for the nested cases: sharing `poly` above would widen
      # its inferred element type to include a nested array, which is an orthogonal
      # poly-slice concern, not what these posts cases exercise.
      def pnest(a) = a

      # 11. A nested array pattern after a splat (poly) is shape-checked and its
      #     inner names bound.
      case pnest([1, 2, [3, 4]])
      in [*, [a, b]]; p [a, b]; end                   #=> [3, 4]

      # 12. A nested-array post whose element is not an array falls through.
      case pnest([1, 2, 5])
      in [*, [a, b]]; p "no"
      else; p "fell"; end                             #=> "fell"

      # 13. A `[a, b] => cap` capture after a splat binds the target and the inner names.
      case pnest([1, [2, 3]])
      in [*, [a, b] => cap]; p [a, b, cap]; end       #=> [2, 3, [2, 3]]

      # 14. A find pattern with a nested array window element binds its inner names.
      case pnest([1, [2, 3], 4])
      in [*, [a, b], *]; p [a, b]; end                #=> [2, 3]

      # 15. A typed array cannot hold a nested-array post, so it cannot match.
      case [1, 2, 3]
      in [*, [a, b]]; p "no"
      else; p "typed-fell"; end                       #=> "typed-fell"

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2, 3], 4]
      [1, [2, 3], 4]
      [1, 2, [3, 4], 5]
      "matched"
      "fellthrough"
      [1, [2, 3]]
      [1, 2]
      3
      [[1, 2], 3, [4, 5]]
      [[1, "x", 3], 4]
      [1, 3]
      [3, 4]
      "fell"
      [2, 3, [2, 3]]
      [2, 3]
      "typed-fell"
      done
    OUT
  end

  it "pattern rightward oneline" do
    result = ze0(<<~'RUBY')
      # Rightward pattern assignment (`expr => pattern`) with splats, posts, and
      # **rest captures, plus one-line `in` hash patterns carrying value
      # sub-patterns (literals, ranges, alternations).

      # rightward array destructure through a method boundary
      def pair_sum(x)
        x => [a, b]
        a + b
      end
      p pair_sum([3, 4])

      # middle splat: required, splat, post
      arr = [1, 2, 3, 4, 5]
      arr => [first, *middle, last]
      p [first, middle, last]

      # empty middle
      [10, 20] => [lo, *mid, hi]
      p [lo, mid, hi]

      # splat with two posts
      [1, 2, 3, 4] => [head, *body, y2, z2]
      p [head, body, y2, z2]

      # splat over a string array keeps the element kind
      %w[red green blue] => [c1, *cs]
      p c1
      p cs

      # trailing-comma implicit rest and unnamed splat: length is a floor (the extra
      # elements are absorbed), and neither binds a rest target
      [1, 2, 3] => [only,]
      p only
      [1, 2, 3] => [head2, *]
      p head2

      # too-short input raises NoMatchingPatternError
      begin
        [1] => [p1, *ps, p9]
        puts "matched"
      rescue NoMatchingPatternError => e
        puts e.class
      end

      # **rest captures the unlisted pairs
      h = { name: "a", x: 1, y: 2 }
      h => { name:, **rest }
      p name
      p rest

      # **rest is empty when every key is listed
      { k: 5 } => { k:, **left }
      p k
      p left

      # one-line `in` with value literals
      q = { a: 1 }
      pr = (q in { a: 1 }); p pr
      pr = (q in { a: 2 }); p pr
      pr = (q in { b: 1 }); p pr

      # range and alternation value sub-patterns
      r = { n: 7 }
      pr = (r in { n: 1..9 }); p pr
      pr = (r in { n: 10..20 }); p pr
      pr = (r in { n: 3 | 7 | 11 }); p pr
      pr = (r in { n: 4 | 8 }); p pr

      # string-valued
      s = { tag: "hot" }
      pr = (s in { tag: "hot" }); p pr
      pr = (s in { tag: "cold" }); p pr

      # class-valued keys still match
      pr = (q in { a: Integer }); p pr
      pr = (s in { tag: Integer }); p pr
    RUBY

    _(result).must_answer <<~'OUT'
      7
      [1, [2, 3, 4], 5]
      [10, [], 20]
      [1, [2], 3, 4]
      "red"
      ["green", "blue"]
      1
      1
      NoMatchingPatternError
      "a"
      {x: 1, y: 2}
      5
      {}
      true
      false
      false
      true
      false
      true
      false
      true
      false
      true
      false
    OUT
  end

  it "rightward assign object deconstruct" do
    result = ze0(<<~'RUBY')
      # `obj => pattern` on a class that defines #deconstruct_keys / #deconstruct binds
      # through the method, as case/in already did: the object used to fall to the
      # untyped path, where every binding was skipped and stayed nil (#3955).
      class N
        def deconstruct_keys(keys) = { kind: :binop, n: 1 }
      end
      N.new => { kind: }
      p kind
      N.new => { kind: k2, n: }
      p [k2, n]

      class A
        def deconstruct = [:x, "y", 3]
      end
      A.new => [a, b, cc]
      p [a, b, cc]

      class Ints
        def deconstruct = [1, 2, 3]
      end
      Ints.new => [h, *t]
      p [h, t]

      # Struct keeps binding through its synthesized members.
      S = Struct.new(:kind, :n)
      S.new(:binop, 1) => { kind: sk }
      p sk
      S.new(:binop, 1) => [sa, sb]
      p [sa, sb]
    RUBY

    _(result).must_answer <<~'OUT'
      :binop
      [:binop, 1]
      [:x, "y", 3]
      [1, [2, 3]]
      :binop
      [:binop, 1]
    OUT
  end
end
