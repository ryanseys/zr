# frozen_string_literal: true

require "spec_helper"

describe "Pattern programs" do
  it "array mul string" do
    result = zr(<<~'RUBY')
      # `Array * sep` (String arg) is equivalent to Array#join(sep) and
      # returns a string. Previously spinel routed it through the int-repeat
      # path which treated the string pointer as a loop count.
      puts ([1, 2, 3] * ",")
      puts ([1, 2, 3] * ",").inspect
      puts ([1, 2, 3] * "")
      puts (["a", "b", "c"] * "-")
    RUBY

    _(result).must_answer <<~'OUT'
      1,2,3
      "1,2,3"
      123
      a-b-c
    OUT
  end

  it "for multi var" do
    result = zr(<<~'RUBY')
      # `for a, b in coll` destructures each element into multiple LVs.
      for a, b in [[1, 2], [3, 4]]
        puts "#{a}, #{b}"
      end

      for x, y, z in [[1, 2, 3], [4, 5, 6]]
        puts "#{x},#{y},#{z}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1, 2
      3, 4
      1,2,3
      4,5,6
    OUT
  end

  it "symbol inspect spl marker" do
    result = zr(<<~'RUBY')
      # Symbol#inspect literal prefix must use SPL marker so sp_str_byte_len's
      # s[-1] marker check is well-defined (avoids -O2 __builtin_trap).
      puts :hello.inspect          # :hello

      sym = :world
      puts sym.inspect             # :world

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      :hello
      :world
      done
    OUT
  end

  it "split no arg ws" do
    result = zr(<<~'RUBY')
      # #507. `s.split` (no arg) used to emit `sp_str_split(s, 0)` and
      # segfault at strlen(NULL) -- new sp_str_split_ws helper matches
      # Ruby's whitespace-mode split (no arg / nil arg form).
      p "1 2 3".split
      p "  leading  trailing  ".split
      p "a\tb\nc".split          # mixed whitespace
      p "".split                  # empty
      p "abc".split(nil)          # explicit nil arg -> same as no-arg
      p "a,b,c".split(",")        # non-whitespace sep (regression guard)
    RUBY

    _(result).must_answer <<~'OUT'
      ["1", "2", "3"]
      ["leading", "trailing"]
      ["a", "b", "c"]
      []
      ["abc"]
      ["a", "b", "c"]
    OUT
  end

  it "scalar zero truthiness" do
    result = zr(<<~'RUBY')
      idx = 0
      if idx
        puts "local zero truthy"
      else
        puts "local zero falsey"
      end

      lookup = { "zero" => 0 }
      value = lookup["zero"]
      if value
        puts "hash zero truthy"
      else
        puts "hash zero falsey"
      end

      width = 0 || 800
      puts width
    RUBY

    _(result).must_answer <<~'OUT'
      local zero truthy
      hash zero truthy
      0
    OUT
  end

  it "reduce sym op" do
    result = zr(<<~'RUBY')
      # #506. `[1,2,3,4].reduce(:*)` previously fell through unresolved
      # on int_array. Codegen now folds the symbol-arg form inline for
      # binary arithmetic / bitwise ops on int_array.
      p [1, 2, 3, 4].reduce(:*)    # 24
      p [1, 2, 3, 4].reduce(:+)    # 10
      p [10, 1, 2].reduce(:-)      # 7
      p [5, 3].inject(:%)          # 2
      p [12, 10].inject(:&)        # 8
      p [5, 3].inject(:|)          # 7
      p [5, 3].inject(:^)          # 6
      p [42].reduce(:+)            # 42 (single-element)
      p [].reduce(:+)              # nil (empty seedless fold, matching CRuby)
    RUBY

    _(result).must_answer <<~'OUT'
      24
      10
      7
      2
      8
      7
      6
      42
      nil
    OUT
  end

  it "array of hash lit" do
    result = zr(<<~'RUBY')
      # Issue #402: array literal of hash literals (`[{n: 3}, {n: 1}]`)
      # was typed as `sp_IntArray *` (the bottom default), but the
      # elements were emitted as `sp_SymIntHash *`. Fix: inference
      # recognises hash-typed elements and returns `poly_array`.
      arr = [{n: 3}, {n: 1}, {n: 2}]
      puts arr.length          # 3
      puts arr[0][:n].to_s     # 3
      puts arr[1][:n].to_s     # 1
      puts arr[2][:n].to_s     # 2

      mixed = [{a: 1}, {b: "x"}]
      puts mixed.length        # 2
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      1
      2
      2
    OUT
  end

  it "integer div" do
    result = zr(<<~'RUBY')
      # basic
      puts 7.div(2)
      puts 10.div(5)

      # exact
      puts 6.div(3)

      # negative -- floor division rounds toward -infinity
      puts((-7).div(2))
      puts 7.div(-2)
      puts((-7).div(-2))

      # zero dividend
      puts 0.div(3)

      # one
      puts 1.div(1)
      puts((-1).div(1))

      # large
      puts 1000001.div(1000)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      2
      -4
      -4
      3
      0
      1
      -1
      1000
    OUT
  end

  it "case in value position" do
    result = zr(<<~'RUBY')
      # case/in used as a value: assignment RHS, method receiver, and method-return
      # position. Pre-fix this hit "unsupported expression: CaseMatchNode" (or
      # silently produced nil when in return position).

      def describe(x)
        s = case x
            in [a, b] then "pair #{a},#{b}"
            in [a] then "one #{a}"
            else "other"
            end
        s
      end
      puts describe([1, 2])
      puts describe([5])
      puts describe([])

      def total(x)
        (case x
         in [a, b] then [a, b]
         else [0]
         end).sum
      end
      p total([3, 4])
      p total([9])
    RUBY

    _(result).must_answer <<~'OUT'
      pair 1,2
      one 5
      other
      7
      0
    OUT
  end

  it "flat map poly receiver" do
    result = zr(<<~'RUBY')
      # flat_map on a poly receiver -- a value whose array-ness is only known at
      # runtime (a recursive parameter, or a `case ... end` whose arms mix arrays and
      # scalars). The receiver is coerced to a poly array at runtime, so the recursive
      # tree-flattening idiom works.
      def flatten_tree(a)
        a.flat_map { |node| node.is_a?(Array) ? flatten_tree(node) : node }
      end
      p flatten_tree([1, [2, [3, 4]], 5])        # [1, 2, 3, 4, 5]

      def prep(dish)
        case dish
        in [*head, :a, :b, *tail]
          [head, :ab, tail]
        else
          dish
        end.flat_map { |node| node.is_a?(Array) ? prep(node) : node }
      end
      p prep([:x, :a, :b, :y])                    # [:x, :ab, :y]
      p prep([:p, :q])                            # [:p, :q]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4, 5]
      [:x, :ab, :y]
      [:p, :q]
    OUT
  end

  it "a hash pattern matches a scrutinee whose type is only known at run time" do
    result = zr(<<~'RUBY')
      # A hash pattern in case/in must match a poly scrutinee at runtime (checking
      # the value is a hash with the required keys), not fail closed.
      def f(v)
        case v
        in [x, y]
          "array #{x},#{y}"
        in { r: }
          "hash r=#{r}"
        else
          "other"
        end
      end
      p f([3, 4])
      p f({ r: 10 })
      p f(5)

      # value sub-patterns (a literal, a class check) also match on a poly scrutinee
      def g(v)
        case v
        in { status: "ok", code: c }
          "ok #{c}"
        in { r: Integer => n }
          "int #{n}"
        else
          "other"
        end
      end
      p g({ status: "ok", code: 200 })
      p g({ r: 42 })
      p g({ r: "x" })
    RUBY

    _(result).must_answer <<~'OUT'
      "array 3,4"
      "hash r=10"
      "other"
      "ok 200"
      "int 42"
      "other"
    OUT
  end

  it "a Hash does not match an array pattern" do
    result = zr(<<~'RUBY')
      # A Hash must not match an array pattern `[x, y]` (a Hash has no #deconstruct
      # in CRuby); the array-pattern condition requires an array-kind poly value.
      def f(v)
        case v
        in [x, y] then "array #{x},#{y}"
        in { r: } then "hash #{r}"
        else "other"
        end
      end
      p f([3, 4])
      p f({ a: 1, r: 10 })
      p f({ r: 9 })
      p f([[1, 2], [3, 4]])
      p f("str")
    RUBY

    _(result).must_answer <<~'OUT'
      "array 3,4"
      "hash 10"
      "hash 9"
      "array [1, 2],[3, 4]"
      "other"
    OUT
  end

  it "a guard on an in clause falls through to the next pattern" do
    result = zr(<<~'RUBY')
      def describe7(event)
        case event
        in { type: :move, dx:, dy: } if dx == 0 && dy == 0 then "no movement"
        in { type: :move, dx:, dy: } then "move by #{dx},#{dy}"
        in { type: :stop } | { type: :halt } then "stopping"
        else "unknown"
        end
      end
      puts describe7({ type: :move, dx: 0, dy: 0 })
      puts describe7({ type: :halt })
    RUBY

    _(result).must_answer "no movement\nstopping\n"
  end

  it "a reduce accumulator widens to hold what the pattern-matching reducer answers" do
    result = zr(<<~'RUBY')
      # A method returning a hash, folded once via reduce (concrete seed) and once
      # pushed via each_with_object (poly), widens to poly; the reduce accumulator
      # must widen to match rather than assigning the boxed result into a concrete
      # hash slot.
      def reducer(state, action)
        case action
        in { type: :inc, by: }
          state.merge(count: state[:count] + by)
        else
          state
        end
      end
      actions = [{ type: :inc, by: 5 }]
      final = actions.reduce({ count: 0 }) { |s, a| reducer(s, a) }
      puts final[:count]
      history = actions.each_with_object([{ count: 0 }]) do |action, acc|
        acc << reducer(acc.last, action)
      end
      puts history.length
    RUBY

    _(result).must_answer "5\n2\n"
  end

  it "underscore name may bind inside an alternation" do
    result = zr(<<~'RUBY')
      # Ruby refuses a binding inside a `|` alternation -- `in [1, x] | [3, 4]` is
      # a SyntaxError -- but it carves out every name beginning with `_`. Both
      # `in [301 | 302, :post] | [303, _]` and `in [1, _v] | [9, 9]` are Syntax OK,
      # and the local is simply nil when the branch that named it is not the one
      # that matched.
      #
      # zr treated an underscore name as an ordinary binding and rejected the
      # clause, claiming to match real Ruby. It rejected `net/imap`,
      # `sass-embedded` and every openai-shaped API client.

      def redirect?(status, method)
        case [status, method]
        in [301 | 302, :post] | [303, _]
          "redirect"
        else
          "other"
        end
      end

      p redirect?(301, :post)
      p redirect?(302, :post)
      p redirect?(303, :get)
      p redirect?(200, :get)

      def space(options)
        case options
        in { whiteness: _ } | { blackness: _ }
          "HWB"
        in { saturation: _ } | { lightness: _ }
          "HSL"
        else
          "none"
        end
      end

      p space({ whiteness: 1 })
      p space({ blackness: 1 })
      p space({ lightness: 2 })
      p space({})

      # The name still binds, and reads back nil from the branch that never set it.
      def named(v)
        case v
        in [1, _payload] | [9, 9]
          _payload
        else
          :no
        end
      end

      p named([1, 42])
      p named([9, 9])
      p named([5, 5])
    RUBY

    _(result).must_answer <<~'OUT'
      "redirect"
      "redirect"
      "redirect"
      "other"
      "HWB"
      "HWB"
      "HSL"
      "none"
      42
      nil
      :no
    OUT
  end
end
