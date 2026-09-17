# frozen_string_literal: true

require "spec_helper"

describe "Numeric: searching and matching" do
  it "bignum index answers nil instead of raising" do
    result = ze0(<<~'RUBY', path: "core/numeric/a_bignum_index_answers_nil_instead_of_raising.rb")
      # `[1, 2][1..2**70]` and `"ab"[1..2**70]` answer `nil` where ruby raises
      # `RangeError: bignum too big to convert into 'long'`.
      #
      # The index conversion narrows a `BigInt` to a machine integer and treats
      # the overflow as "out of bounds", so the call falls into the ordinary
      # nil-for-a-missing-slice answer instead of reporting that the index itself
      # is unrepresentable. Ruby draws the line the other way: an index that
      # cannot be a `long` is an ERROR, not a miss, because the two mean different
      # things to a caller -- `nil` says "no such element", `RangeError` says "that
      # is not an index".
      #
      # It is narrow, and the shape of what still agrees says how narrow: a bare
      # bignum index (`[1,2][2**70]`), a bignum LENGTH (`slice(0, 2**70)`), and
      # `first`/`take`/`drop`/`fill`/`rotate`/`values_at`/`dig` with one all match
      # ruby already. Only the RANGE form of the index is wrong, on `Array` and on
      # `String`.
      #
      # Its sibling is `a_bignum_range_endpoint_is_not_an_integer_range.rb`: this
      # file is about a range zeo declines to convert, that one about a range zeo
      # declines to walk.
      #
      # Oracle: a bignum index raises.
      B = 2**70
      begin
        p [1, 2][1..B]
      rescue RangeError => e
        p [:ary, e.class, e.message]
      end
      begin
        p "ab"[1..B]
      rescue RangeError => e
        p [:str, e.class, e.message]
      end
      p [1, 2][B].inspect
      p [1, 2].slice(0, B)
      p [1, 2].first(B)
      p [1, 2].values_at(B)
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/numeric/a_bignum_index_answers_nil_instead_of_raising.rb:34:in '<main>': bignum too big to convert into 'long' (RangeError)\n", status: 1
      [:ary, RangeError, "bignum too big to convert into 'long'"]
      [:str, RangeError, "bignum too big to convert into 'long'"]
    OUT
  end

  it "index op write nested" do
    result = ze0(<<~'RUBY')
      # Compound assignment to a nested (2-D) indexed slot: `m[a][c] OP= v`.
      # The receiver `m[a]` is a poly-typed index expression, so the op-write
      # goes through the poly-receiver arm of IndexOperatorWriteNode with an
      # int (or dynamic) key. Previously only sym/str keys were supported and
      # this failed to compile with "unsupported index operator assignment
      # (poly-recv, non-sym/str key)".

      # Float elements, int keys via loop variables.
      def accumulate
        m = [[0.0, 0.0], [0.0, 0.0]]
        a = 0
        while a < 2
          c = 0
          while c < 2
            m[a][c] += 1.5
            c += 1
          end
          a += 1
        end
        m
      end
      p accumulate            # [[1.5, 1.5], [1.5, 1.5]]

      # Int elements, several operators; receiver index is a computed expression.
      def int_ops
        m = [[8, 9], [10, 11]]
        i = 0
        m[i][0] /= 2
        m[i][1] %= 4
        m[i + 1][0] <<= 2
        m[i + 1][1] |= 4
        m
      end
      p int_ops               # [[4, 1], [40, 15]]

      # Chained ops on the same slot inside a loop.
      def chained
        m = [[1, 2], [3, 4]]
        i = 0
        while i < 2
          j = 0
          while j < 2
            m[i][j] *= 10
            m[i][j] -= 1
            j += 1
          end
          i += 1
        end
        m
      end
      p chained               # [[9, 19], [29, 39]]

      # Hash-of-arrays: the inner receiver `h[k]` is poly, the final key is int.
      def hash_of_arrays
        h = { "a" => [1, 2] }
        k = "a"
        i = 1
        h[k][i] += 5
        h["a"]
      end
      p hash_of_arrays        # [1, 7]

      # Three levels deep: `m[a][0][1] += v`.
      def deep
        m = [[[0, 0]], [[0, 0]]]
        a = 0
        while a < 2
          m[a][0][1] += 7
          a += 1
        end
        m
      end
      p deep                  # [[[0, 7]], [[0, 7]]]
    RUBY

    _(result).must_answer <<~'OUT'
      [[1.5, 1.5], [1.5, 1.5]]
      [[4, 1], [40, 15]]
      [[9, 19], [29, 39]]
      [1, 7]
      [[[0, 7]], [[0, 7]]]
    OUT
  end

  it "int bracket skip sym idx" do
    result = ze0(<<~'RUBY')
      # Issue #314 (Roundhouse warnings family): `Integer#[idx]` codegen
      # fired for ANY `[]` call on an int-typed receiver, including the
      # common shape:
      #
      #   def self.from_raw(row)
      #     instance.id = row[:id] || 0
      #     ...
      #   end
      #
      # where `row` is an unpinned param whose type defaults to "int". The
      # `row[:id]` then lowered to `(row >> SPS_id) & 1` — shifting a
      # 64-bit int by the symbol's interned id (commonly >= 64) is
      # undefined behavior under -Wshift-count-overflow, and even when it
      # happens to compile the value is garbage.
      #
      # Fix: gate the bit-extract on the index's inferred type. A non-int
      # / non-poly index (typically a Symbol or String literal) is hash /
      # array subscript, never Integer-bit indexing — fall through to
      # the unresolved-call placeholder so the C compile sees the right
      # diagnostic instead of a warning + UB.

      # Genuine bit indexing — must still work.
      n = 0b1010
      puts n[0]                # 0
      puts n[1]                # 1
      puts n[2]                # 0
      puts n[3]                # 1

      # Hash-subscript shape on an unpinned param — the bug's repro.
      # Without the fix, `row[:k]` emits `(row >> SPS_k) & 1` and gcc/
      # clang flag the shift count. With the fix, this falls through to
      # the unresolved-call placeholder (the param type is unknown to
      # spinel here, since the function is never called), which is the
      # correct behavior — compilation succeeds without the bogus
      # bit-extract.
      def from_raw(row)
        row[:id] || 0
      end

      puts "compiled-cleanly"
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      0
      1
      compiled-cleanly
    OUT
  end

  it "integer bit index clamped" do
    result = ze0(<<~'RUBY')
      # Integer#[i] with an out-of-range bit index: the emitted C shift is
      # clamped (sp_int_bit), so i >= 64 reads the sign fill and a negative
      # index is 0 -- the literal-folded form was an undefined C shift that
      # only LOOKED right on x86's masked shifts.
      puts 5[100]
      puts 5[64]
      puts 5[63]
      puts 5[-1]
      puts 5[0]
      puts 5[2]
      puts(-1[100])
      puts(-5[64])
      i = 100
      puts 5[i]
      puts(-1[i])
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      0
      0
      1
      1
      1
      1
      0
      1
    OUT
  end

  it "integer operator redefinition" do
    result = ze0(<<~'RUBY')
      # The Integer lane of the operator fast-path suppression: a reopened
      # Integer#== wins at literal sites and poly sites; + and include? keep
      # their native paths.
      class Integer
        def ==(other) = "int-eq(#{self},#{other})"
      end
      p 3 == 3
      p 3 + 4
      p [1, 2].include?(2)
      y = [5].first
      p y == 5
    RUBY

    _(result).must_answer <<~'OUT'
      "int-eq(3,3)"
      7
      true
      "int-eq(5,5)"
    OUT
  end

  it "math extended" do
    result = ze0(<<~'RUBY')
      # Math hyperbolic/inverse-hyperbolic, gamma/lgamma, erf/erfc, frexp/ldexp --
      # backed by the same system libm CRuby's Math uses, so values match exactly.
      rd = ->(x) { x.round(10) }

      puts rd.(Math.sinh(1.0))
      puts rd.(Math.cosh(1.0))
      puts rd.(Math.tanh(1.0))
      puts rd.(Math.asinh(2.0))
      puts rd.(Math.acosh(2.0))
      puts rd.(Math.atanh(0.5))
      p Math.atanh(1.0)            # pole -> Infinity, not a DomainError

      # gamma: exact factorials for small positive integers, ±0/±inf special cases.
      puts Math.gamma(6.0)         # 120.0
      puts rd.(Math.gamma(0.5))
      p Math.gamma(0.0)            # +Infinity
      p Math.gamma(172).infinite? # overflow -> Infinity

      # lgamma -> [log|gamma|, sign]; poles give [Infinity, ±1].
      p Math.lgamma(0.5).map { |v| v.is_a?(Float) ? rd.(v) : v }
      p Math.lgamma(-1.0)

      # frexp/ldexp are exact inverses.
      p Math.frexp(8.0)           # [0.5, 4]
      puts Math.ldexp(0.75, 3)    # 6.0

      puts rd.(Math.erf(0.5))
      puts rd.(Math.erfc(0.5))

      # Domain errors (verbatim CRuby message).
      begin
        Math.gamma(-2.0)
      rescue Math::DomainError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1.1752011936
      1.5430806348
      0.761594156
      1.4436354752
      1.3169578969
      0.5493061443
      Infinity
      120.0
      1.7724538509
      Infinity
      1
      [0.5723649429, 1]
      [Infinity, 1]
      [0.5, 4]
      6.0
      0.5204998778
      0.4795001222
      Numerical argument is out of domain - gamma
    OUT
  end

  it "math hyperbolic gamma and frexp family" do
    result = ze0(<<~'RUBY')
      # Backed by the system libm CRuby also calls, so values match exactly;
      # gamma uses an exact factorial table + ±0/±inf/negative-integer rules.

      puts Math.tanh(1.0).round(10)
      puts Math.acosh(2.0).round(10)
      p Math.atanh(1.0)
      puts Math.gamma(6.0)
      p Math.gamma(0.0)
      p Math.lgamma(-1.0)
      p Math.frexp(8.0)
      puts Math.ldexp(0.75, 3)
      begin; Math.gamma(-2.0); rescue Math::DomainError => e; puts e.message; end
    RUBY

    _(result).must_answer <<~'OUT'
      0.761594156
      1.3169578969
      Infinity
      120.0
      Infinity
      [Infinity, 1]
      [0.5, 4]
      6.0
      Numerical argument is out of domain - gamma
    OUT
  end

  it "operator reopened above integer still wins" do
    result = ze0(<<~'RUBY')
      # The operator fast path stands down when a user reopen redefines the
      # operator on the fast-path MRO, and BOTH numeric lanes gate the one
      # decision: the boxed shape tests both tags, so a site cannot know which arm
      # it will take.
      #
      # `Integer#<=>` is the oracle's own, so redefining `Numeric#<=>` below does
      # NOT change what an Integer answers -- it is here because the redefinition
      # still has to suppress the fast path, and the answers must stay ruby's.

      class Numeric
        def <=>(other) = "num-cmp"
      end

      p(1 <=> 2)
      p(1.5 <=> 2)
      x = [3].first
      p(x <=> 4)

      # `Float#-` IS reached, and suppressing it must not change what Integer
      # subtraction answers.
      class Float
        def -(other) = "float-minus"
      end
      p(2.0 - 1.0)
      p(5 - 1)
      y = [7.5].first
      p(y - 0.5)

      # Operators nobody touched keep their native paths.
      p(6 + 7)
      p(6 * 7)
      p(6 < 7)
      p(2.5 + 0.25)
      p([1, 2].include?(2))

      # A redefinition reached through a variable receiver, not a literal.
      def apply(a, b) = a <=> b
      p apply(1, 2)
      p apply(1.0, 2.0)
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      -1
      -1
      "float-minus"
      4
      "float-minus"
      13
      42
      true
      2.75
      true
      -1
      -1
    OUT
  end
end
