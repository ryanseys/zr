# frozen_string_literal: true

require "spec_helper"

describe "Range programs" do
  it "bundle misc c 31" do
    result = ze0(<<~'RUBY')
      # Bundled tests:
      #   - str_rindex_optional_narrow
      #   - string_new_array_literal
      #   - string_split_with_limit

      # === str_rindex_optional_narrow ===
      def t_str_rindex_optional_narrow
        # Issue #645: `slash = p.rindex("/")` followed by a nil-check
        # ternary used to leak sp_RbVal into sp_str_sub_range_r (which
        # expects mrb_int):
        #
        #   tail = slash == nil ? p : p[(slash + 1)..(p.length - 1)]
        #
        # Root cause: spinel widened `String#rindex` return to "poly"
        # unconditionally (sp_str_rindex_poly returns sp_RbVal), even
        # when the arg was a plain string. `slash + 1` then went through
        # sp_poly_add and the result couldn't pass as the mrb_int start
        # arg.
        #
        # Fix: split rindex like index — plain-string arg returns int?
        # via sp_str_rindex_opt (SP_INT_NIL sentinel), regex arg stays
        # on sp_re_rindex_poly. The nil-check narrow (#645 infra) then
        # applies.
        
        p = "abc/def"
        slash = p.rindex("/")
        tail = slash == nil ? p : p[(slash + 1)..(p.length - 1)]
        puts tail
        
        # not-found case
        p2 = "no_slash_here"
        slash2 = p2.rindex("/")
        tail2 = slash2 == nil ? p2 : p2[(slash2 + 1)..(p2.length - 1)]
        puts tail2
        
        # multiple separators — rindex finds the last
        p3 = "a/b/c/d"
        puts p3.rindex("/").inspect
        slash3 = p3.rindex("/")
        puts slash3 == nil ? "none" : p3[(slash3 + 1)..(p3.length - 1)]
        
        # zero-position match
        puts "/foo".rindex("/")
      end
      t_str_rindex_optional_narrow

      # === string_new_array_literal ===
      def t_string_new_array_literal
        # #519. `[String.new]` (and `[s]` where `s = String.new`) used to
        # infer as `int_array`, then codegen emitted
        # `sp_IntArray_push(arr, sp_String_new(""))` -- C type mismatch.
        #
        # Fix: `infer_array_elem_type_from_ids` now has a `mutable_str` arm
        # that lowers the literal to `mutable_str_ptr_array` (a sp_PtrArray
        # of sp_String*). The generic `<X>_ptr_array` codegen path handles
        # length / push / pop / [] for the new slot.
        #
        # `["", String.new]` (mixed string-literal + mutable_str) still
        # widens to poly_array because the literal witness flips et to
        # "string" first and the all-string check fails.
        
        arr = [String.new]
        puts arr.length
        
        s = String.new
        arr2 = [s]
        puts arr2.length
        
        # Mixed: literal + String.new -> poly_array. Both elements show up.
        mixed = ["", String.new]
        puts mixed.length
      end
      t_string_new_array_literal

      # === string_split_with_limit ===
      def t_string_split_with_limit
        # String#split with a positive `limit` argument caps the result at
        # `limit` elements; the last element keeps the unsplit remainder.
        # Pre-fix spinel's two-arg split fell through to sp_str_split, which
        # ignored the limit and split exhaustively. Issue #619 puzzle 2.
        p "hi!".split("", 2) == ["h", "i!"]
        p "a,b,c,d".split(",", 2) == ["a", "b,c,d"]
        p "a,b,c,d".split(",", 3) == ["a", "b", "c,d"]
        p "abc".split("", 1) == ["abc"]                     # limit=1 keeps the whole string
        p "abc".split("", 3) == ["a", "b", "c"]             # limit == #chars, exact split
        p "a,b,c".split(",", -1) == ["a", "b", "c"]         # negative limit -> full split
      end
      t_string_split_with_limit

    RUBY

    _(result).must_answer <<~'OUT'
      def
      no_slash_here
      5
      d
      0
      1
      1
      2
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "case" do
    result = ze0(<<~'RUBY')
      # Test case/when, unless, next, default args

      def describe(n)
        case n
        when 1
          "one"
        when 2, 3
          "two or three"
        when 4..6
          "four to six"
        else
          "other"
        end
      end

      puts describe(1)
      puts describe(3)
      puts describe(5)
      puts describe(9)

      # unless
      x = 10
      unless x > 20
        puts "small"
      end

      # next in loop
      total = 0
      i = 0
      while i < 10
        i += 1
        next if i % 3 == 0
        total += i
      end
      puts total  # 1+2+4+5+7+8+10 = 37

      # default args
      def greet(name, greeting = "Hello")
        puts greeting
        puts name
      end
      greet("world")
      greet("Ruby", "Hi")
    RUBY

    _(result).must_answer <<~'OUT'
      one
      two or three
      four to six
      other
      small
      37
      Hello
      world
      Hi
      Ruby
    OUT
  end

  it "case in range pattern" do
    result = ze0(<<~'RUBY')
      # A range pattern in `case/in` matches by membership (===), honoring
      # exclusivity and beginless/endless bounds, instead of being treated as an
      # unconditional match (which previously selected the wrong arm). Scrutinees
      # route through a method param so the runtime path runs. Separate helpers per
      # scrutinee kind (int/float/poly) keep the param type concrete.
      def si(x); x; end   # int
      def sf(x); x; end   # float
      def sp(x); x; end   # poly

      def classify(n)
        case si(n)
        in 0..3 then "low"
        in 4..10 then "mid"
        in 11.. then "high"
        else "neg"
        end
      end
      p classify(2)    # "low"
      p classify(5)    # "mid"
      p classify(50)   # "high"
      p classify(-1)   # "neg"

      # exclusive end: 3 is NOT in 0...3
      def excl(n)
        case si(n)
        in 0...3 then "lo"
        in 3..9 then "hi"
        end
      end
      p excl(2)        # "lo"
      p excl(3)        # "hi"

      # beginless / endless ranges
      def beginless(n)
        case si(n)
        in ..0 then "neg"
        in 1.. then "pos"
        end
      end
      p beginless(-5)  # "neg"
      p beginless(9)   # "pos"

      # float scrutinee and bounds
      def grade(x)
        case sf(x)
        in 0.0...0.5 then "F"
        in 0.5..1.0 then "P"
        end
      end
      p grade(0.25)    # "F"
      p grade(0.75)    # "P"

      # range pattern with a capture binding
      case si(7)
      in (5..10) => v then p v   # 7
      end

      # poly scrutinee (element of a poly array) still matches a range
      case sp([1, "x"]).first
      in 0..3 then puts "a"
      in 4..9 then puts "b"
      end                # a
    RUBY

    _(result).must_answer <<~'OUT'
      "low"
      "mid"
      "high"
      "neg"
      "lo"
      "hi"
      "neg"
      "pos"
      "F"
      "P"
      7
      a
    OUT
  end

  it "case in range pattern 2" do
    result = ze0(<<~'RUBY')
      case 5
      in 1..10
        puts "in range"
      end
      case 15
      in 1..10
        puts "in range"
      else
        puts "out of range"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      in range
      out of range
    OUT
  end

  it "collections convert and walk as cruby does" do
    result = ze0(<<~'RUBY')
      # A Range walks anything with succ, an Integer toward a Float end too.
      # Enumerable#uniq and Set#count take their blocks; collect names its own
      # enumerator; with_index reads nil as 0. A Struct keeps a keyword Hash
      # as a value when it has values by position too; one clamp argument
      # must be a Range; Array() falls back to to_a; the set operators and
      # Queue.new convert as CRuby does; ENV answers the Hash methods.
      def t = yield rescue [$!.class, $!.message]

      p t { (1...3.5).to_a }, t { (1..3.0).to_a }, t { (1.5..3).to_a }
      Day = Struct.new(:n) do
        include Comparable
        def succ = Day.new(n + 1)
        def <=>(other) = n <=> other.n
      end
      p t { (Day.new(1)..Day.new(3)).map(&:n) }, t { (Day.new(1)...Day.new(3)).map(&:n) }, t { (:a..:c).to_a }, t { (:a..).first(2) }
      p t { (1..6).uniq { _1 % 3 } }, t { [1, -1, 2].uniq!(&:abs) }, t { Set[1, 2, 3].count(&:odd?) }, t { Set[1, 2, 3].count(2) }, t { Set[1, 2].count }
      p t { [1, 2].collect.inspect }, t { [1, 2].each.with_index(nil).to_a }, t { [5, 6].each.with_index(1.5).to_a }

      S = Struct.new(:a, :b)
      p t { S.new(1, b: 2).b }, t { S.new(a: 1, b: 2).b }, t { Struct.new(:a, keyword_init: false).new(a: 1).a }
      p t { 5.clamp(3) }, t { 5.clamp(nil) }, t { 5.clamp(1..3) }, t { 5.clamp(1..) }

      class ToAryNil
        def to_ary = nil
        def to_a = [:fallback]
      end

      class ToAryOne
        def to_ary = 1
      end
      p t { Array(ToAryNil.new) }, t { Array(ToAryOne.new) }, t { Array(nil) }, t { Array(1..2) }
      p t { [1] - nil }, t { [1] - 1 }, t { [1] & nil }, t { [1] | nil }, t { [1, 2] - [2] }, t { [1].each_entry.drop(-1) }, t { [1].each_entry.drop(nil) }
      p t { Queue.new(1..3).size }, t { Queue.new(5) }, t { Queue.new([1]).pop }

      ENV["ZR_P9_A"] = "zr-p9-one"
      ENV["ZR_P9_B"] = "zr-p9-two"
      p t { ENV.value?("zr-p9-two") }, t { ENV.has_value?("nope") }, t { ENV.value?(1) }, t { ENV.invert["zr-p9-one"] }, t { ENV.except("ZR_P9_A").key?("ZR_P9_A") }
      p t { ENV.reject! { false } }, t { ENV.select! { true } }, t { ENV.filter! { true } }, t { ENV.keep_if { true }.equal?(ENV) }
      p t { ENV.delete_if { |k, _| k == "ZR_P9_B" }.equal?(ENV) }, t { ENV["ZR_P9_B"] }, t { ENV.reject! { |k, _| k == "ZR_P9_A" }.equal?(ENV) }, t { ENV["ZR_P9_A"] }
      p t { ENV.rehash }, t { ENV.delete_if.class }, t { ENV.filter!.class }, t { ENV.replace({"A" => 1}) }

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3]
      [TypeError, "can't iterate from Float"]
      [1, 2, 3]
      [1, 2]
      [:a, :b, :c]
      [:a, :b]
      [1, 2, 3]
      [1, 2]
      2
      1
      2
      "#<Enumerator: [1, 2]:collect>"
      [[1, 0], [2, 1]]
      [[5, 1], [6, 2]]
      {b: 2}
      2
      {a: 1}
      [TypeError, "wrong argument type Integer (expected Range)"]
      [TypeError, "wrong argument type nil (expected Range)"]
      3
      5
      [:fallback]
      [TypeError, "can't convert ToAryOne to Array (ToAryOne#to_ary gives Integer)"]
      []
      [1, 2]
      [TypeError, "no implicit conversion of nil into Array"]
      [TypeError, "no implicit conversion of Integer into Array"]
      [TypeError, "no implicit conversion of nil into Array"]
      [TypeError, "no implicit conversion of nil into Array"]
      [1]
      [ArgumentError, "attempt to drop negative size"]
      [TypeError, "no implicit conversion from nil to integer"]
      3
      [TypeError, "can't convert Integer into Array"]
      1
      true
      false
      nil
      "ZR_P9_A"
      false
      nil
      nil
      nil
      true
      true
      nil
      true
      nil
      nil
      Enumerator
      Enumerator
      [TypeError, "no implicit conversion of Integer into String"]
    OUT
  end

  it "endless method" do
    result = ze0(<<~'RUBY')
      # Endless methods (Ruby 3.0+): `def name(args) = expr` is shorthand for
      # a single-expression method body. Prism flattens this to the same
      # DefNode shape as a regular def with a one-statement StatementsNode
      # body, so the existing codegen path supports it transparently. This
      # test pins that contract — if a future Prism upgrade emits a distinct
      # node type (e.g. SingleLineMethodDefinitionNode), the test breaks
      # loudly instead of silently regressing.

      # 1. Plain integer return.
      def double(x) = x * 2
      puts double(21)
      # 42

      # 2. String return with interpolation.
      def greet(name) = "hello, #{name}"
      puts greet("world")
      # hello, world

      # 3. Self-recursive endless method (still expressible, since the body
      #    is one expression).
      def fact(n) = n <= 1 ? 1 : n * fact(n - 1)
      puts fact(5)
      # 120

      # 4. No-arg endless method.
      def answer = 42
      puts answer
      # 42

      # 5. Endless method using a block-passing call.
      def doubled_max(arr) = arr.map { |x| x * 2 }.max
      puts doubled_max([1, 4, 2])
      # 8

      # 6. Class endless method (instance + class methods).
      class Box
        def self.unit = 1
        def initialize(v); @v = v; end
        def double = @v * 2
        def name = "Box"
      end

      puts Box.unit
      # 1
      puts Box.new(7).double
      # 14
      puts Box.new(0).name
      # Box

      # 7. Boolean-returning endless method.
      def positive?(n) = n > 0
      puts positive?(10)
      # true
      puts positive?(-1)
      # false

      # 8. Method composition (one endless method calling another).
      def square(x) = x * x
      def square_of_sum(a, b) = square(a + b)
      puts square_of_sum(2, 3)
      # 25
    RUBY

    _(result).must_answer <<~'OUT'
      42
      hello, world
      120
      42
      8
      1
      14
      Box
      true
      false
      25
    OUT
  end

  it "endless method definition" do
    _(ze0(<<~'RUBY')).must_answer "42\n"
      class Calc
        def double(x) = x * 2
      end
      puts Calc.new.double(21)
    RUBY
  end

  it "endless method rescue" do
    result = ze0(<<~'RUBY')
      # Endless method with rescue modifier:
      #   def name(args) = expr rescue fallback
      # Combines `def foo(x) = expr` (already supported) with the postfix
      # `rescue` modifier. This test
      # pins int-typed-return shapes.

      # Plain endless + rescue with Integer() conversion
      def parse_int(s) = Integer(s) rescue 0
      puts parse_int("42")
      puts parse_int("abc")
      puts parse_int("0")
      puts parse_int("-7")

      # Explicit-raise rescue trigger. Pre-fix the test was `half(n) = n / 2`,
      # which never raises (0/2 == 0) and so never exercised the rescue path.
      # Uses an explicit raise() so the rescue trigger is independent of the
      # integer-division-by-zero machinery (covered separately in
      # test/integer_div_by_zero.rb). The raise lives inside a helper so the
      # endless body is a single call expression — keeps codegen happy and
      # exercises the cross-frame rescue path.
      def assert_pos(n)
        n < 0 ? raise("negative") : n
      end
      def safe(n) = assert_pos(n) rescue -1
      puts safe(10)
      puts safe(-5)
      puts safe(0)

      # Nested call with rescue
      def chain(s) = s.to_i + 1 rescue 0
      puts chain("99")
      puts chain("zero")
      puts chain("-1")
    RUBY

    _(result).must_answer <<~'OUT'
      42
      0
      0
      -7
      10
      -1
      0
      100
      1
      0
    OUT
  end

  it "endless method rescue modifier" do
    result = ze0(<<~'RUBY')
      class Unsafe
        def op(n)
          raise "negative" if n < 0
          n * 2
        end
      end
      class Calc
        def safe_op(n) = Unsafe.new.op(n) rescue -1
      end
      c = Calc.new
      puts c.safe_op(5)
      puts c.safe_op(-5)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      -1
    OUT
  end

  it "enumerator produce endless generator" do
    result = ze0(<<~'RUBY')
      # Enumerator.produce(initial) { |prev| ... } yields initial, then each
      # block result, forever -- bounded by the consumer. Without initial, the
      # first value is block.call(nil).

      p(Enumerator.produce(1) { |n| n * 2 }.take(3))
      p(Enumerator.produce(1) { |n| n + 1 }.first(4))
      g = Enumerator.produce(0) { |n| n + 2 }
      p g.next
      p g.next
      e = Enumerator.produce { |n| (n || 0) + 1 }
      p e.take(3)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 4]
      [1, 2, 3, 4]
      0
      2
      [1, 2, 3]
    OUT
  end

  it "enumerator range" do
    result = ze0(<<~'RUBY')
      # Range#each with no block is an external Enumerator (#next/#peek/#rewind/#size),
      # but only when used that way: when it is the receiver of a collection method
      # (.to_a/.map/.select/.sum/...) it materializes to a typed array, so those chains
      # keep their fast unboxed path.

      e = (1..3).each
      p e.class
      p e.is_a?(Enumerator)
      p e.size

      p e.next
      p e.peek          # does not advance
      p e.next
      p e.next
      begin
        e.next
      rescue StopIteration
        puts "stopped"
      end
      e.rewind
      p e.next

      # direct chain to an enumerator method stays an enumerator
      p (5..7).each.next

      # loop terminates on StopIteration
      e2 = (10..13).each
      acc = 0
      loop { acc += e2.next }
      p acc
      puts "after"

      # collection chains still work (and stay typed/fast)
      p((1..3).each.to_a)
      p((1..4).each.map { |x| x * 2 })
      p((1..6).each.select(&:even?))
      p((1..4).each.sum)
      p((1..5).each.reduce(:+))
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      true
      3
      1
      2
      2
      3
      stopped
      1
      5
      46
      after
      [1, 2, 3]
      [2, 4, 6, 8]
      [2, 4, 6]
      10
      15
    OUT
  end

  it "flip flop latches" do
    result = ze0(<<~'RUBY')
      # A flip-flop is a LATCH, not a Range: true from the evaluation whose left
      # operand is truthy through the one whose right operand is. Two dots retest
      # the right operand in the very evaluation that turned it on; three wait.
      (1..10).each do |i|
        print i if (i == 3)..(i == 6)
      end
      puts
      (1..10).each do |i|
        print i if (i == 3)...(i == 3)
      end
      puts
      (1..10).each do |i|
        print i if (i == 3)..(i == 3)
      end
      puts
      lines = ["a", "START", "x", "y", "END", "b"]
      lines.each do |l|
        puts l if l == "START"..l == "END"
      end
      2.times do
        (1..5).each do |i|
          print i if (i == 2)..(i == 4)
        end
        puts
      end
    RUBY

    _(result).must_answer <<~'OUT'
      3456
      345678910
      3
      START
      x
      y
      END
      234
      234
    OUT
  end

  it "for loop over a range asks the range" do
    result = ze0(<<~'RUBY')
      # `for x in <range>` decides how to iterate from the range's ENDPOINTS, not
      # from the fact that it is a Range.
      #
      # Every shape below used to end the process with
      #   thread 'ruby-main' panicked: expected an Int, got c
      # because the lowering read both endpoints with `as_int_unchecked`. A String
      # range yields Strings, a Float or beginless one yields nothing (ruby raises a
      # catchable TypeError from `Range#each`), and an ENDLESS one has no end to
      # read at all.
      #
      # The last case is the subtle one: a range reaching the loop through a local
      # whose type is not statically Range still must not be COLLECTED, or an
      # endless one never finishes.

      for s in ("a".."c")
        puts s
      end

      r = ("x".."z")
      for t in r
        puts t
      end

      begin
        for f in (1.0..3.0)
          puts f
        end
      rescue TypeError => e
        puts "float: #{e.message}"
      end

      begin
        for b in (..5)
          puts b
        end
      rescue TypeError => e
        puts "beginless: #{e.message}"
      end

      # Endless, three ways in: a literal, a plainly Range-typed local, and a local
      # the compiler cannot call a Range (it held an exception first).
      for i in (1..)
        break if i > 2
      end
      puts "endless literal ok"

      e2 = (7..)
      n = 0
      for j in e2
        n += j
        break if j >= 9
      end
      p n

      begin
        raise TypeError, "widen"
      rescue TypeError => w
        w = (4..)
        m = 0
        for k in w
          m += k
          break if k >= 6
        end
        p m
      end

      # Bounded ranges are unchanged, literal and through variables, inclusive and
      # exclusive, and an empty one runs its body zero times.
      out = []
      for a in (1..3) do out << a end
      p out
      lo = 2
      hi = 5
      out = []
      for c in (lo...hi) do out << c end
      p out
      out = []
      p(for d in (3..1) do out << d end)
      p out
    RUBY

    _(result).must_answer <<~'OUT'
      a
      b
      c
      x
      y
      z
      float: can't iterate from Float
      beginless: can't iterate from NilClass
      endless literal ok
      24
      15
      [1, 2, 3]
      [2, 3, 4]
      3..1
      []
    OUT
  end

  it "immediates and ranges are always frozen" do
    result = ze0(<<~'RUBY')
      puts 1.frozen?
      puts 1.5.frozen?
      puts :sym.frozen?
      puts nil.frozen?
      puts true.frozen?
      puts (1..5).frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "issue 2925" do
    _(ze0(<<~'RUBY')).must_answer "5400\n"
      # A `sum` block whose value indexes an Array#find result is poly; the sum
      # must fold through the block (regression alongside #2913).
      table = [["h", 3600], ["m", 60]]
      p ["1h", "30m"].sum { |t| t[0...-1].to_i * table.find { |l, _| l == t[-1] }[1] }
    RUBY
  end

  it "issue 2938" do
    result = ze0(<<~'RUBY')
      # begin/end on a Range read out of a poly container: the poly receiver reads
      # the sp_Range endpoints instead of returning an opaque value.
      ranges = [(1..5), (10..20)]
      p ranges[0].begin + ranges[0].end
      p ranges[1].begin
      p ranges[1].end
    RUBY

    _(result).must_answer <<~'OUT'
      6
      10
      20
    OUT
  end

  it "issue 3070" do
    result = ze0(<<~'RUBY')
      puts ("a".."e").count
      puts ("a"..."e").count
      puts ("aa".."ad").count
    RUBY

    _(result).must_answer <<~'OUT'
      5
      4
      4
    OUT
  end

  it "issue 3084" do
    result = ze0(<<~'RUBY')
      s = "あいうえお"
      s.slice!(1)
      p s
      s2 = "あいうえお"
      s2.slice!(1, 2)
      p s2
      s3 = "あいうえお"
      s3.slice!(1..2)
      p s3
      r = "日本語ABC"
      r.slice!(0, 3)
      p r
      v = "あいうえお"
      removed = v.slice!(1, 2)
      p removed
      p v
      w = "café"
      w.slice!(-1)
      p w
    RUBY

    _(result).must_answer <<~'OUT'
      "あうえお"
      "あえお"
      "あえお"
      "ABC"
      "いう"
      "あえお"
      "caf"
    OUT
  end

  it "issue 3102" do
    result = ze0(<<~'RUBY')
      p(("a".."e").count { |s| s < "c" })
      p(("a".."e").count)
      p(("a".."e").count("b"))
      p((1..5).count { |i| i.even? })
    RUBY

    _(result).must_answer <<~'OUT'
      2
      5
      1
      2
    OUT
  end

  it "issue 3221" do
    result = ze0(<<~'RUBY')
      a = (2..5)
      r = rand(a)
      p (2..5).include?(r)
      b = (5..2)          # empty range in a variable -> nil, like CRuby
      p rand(b)
      c = (0...3)
      p (0...3).include?(rand(c))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      true
    OUT
  end

  it "lazy endless take while" do
    result = ze0(<<~'RUBY')
      p (1..Float::INFINITY).lazy.take_while { |x| x < 5 }.to_a
      p (1..).lazy.take_while { |x| x * x < 30 }.to_a
      p (1..Float::INFINITY).lazy.map { |x| x * 3 }.take_while { |x| x < 20 }.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [1, 2, 3, 4, 5]
      [3, 6, 9, 12, 15, 18]
    OUT
  end

  it "leaf methods" do
    result = ze0(<<~'RUBY')
      # A grab-bag of core leaf methods across String, Array, Hash, Symbol, Integer,
      # and Proc — each the whole of its behavior, oracle-checked.

      # Integer#[] — bit reference (LSB = 0), with (start, len) and range fields.
      p 0b1011[0]          # 1
      p 5[0, 2]            # 1  -- low two bits
      p 255[0..3]          # 15
      p 255[4..]           # 15 -- endless range shifts right
      p (-2)[0]            # 0  -- two's complement

      # Integer bit-mask predicates.
      p 0b1010.allbits?(0b0010)   # true
      p 0b1010.anybits?(0b0110)   # true
      p 0b1010.nobits?(0b0101)    # true

      # String leaves.
      p "hello".codepoints            # [104, 101, 108, 108, 111]
      p "hello".partition("l")        # ["he", "l", "lo"]
      p "hello".rpartition("l")       # ["hel", "l", "o"]
      p "TestName".delete_prefix("Test")   # "Name"
      p "file.rb".delete_suffix(".rb")     # "file"
      buf = +"mutable"; buf.clear; p buf   # ""
      name = "line\n"; p name.chomp!; p name.chomp!   # "line" then nil (no change)
      bs = "hello"; bs.bytesplice(0, 2, "XY"); p bs    # "XYllo"

      # Array combinatorics + set predicate + chaining.
      p [1, 2].repeated_permutation(2).to_a   # [[1,1],[1,2],[2,1],[2,2]]
      p [1, 2].repeated_combination(2).to_a   # [[1,1],[1,2],[2,2]]
      p [1, 2, 3].intersect?([3, 4])          # true
      p [1, 2].chain([3], [4]).to_a           # [1, 2, 3, 4]

      # Hash projections.
      p({ a: 1, b: 2, c: 3 }.slice(:a, :c))   # {a: 1, c: 3}
      p({ a: 1, b: 2, c: 3 }.except(:b))      # {a: 1, c: 3}
      p({ a: 1, b: 2 }.fetch_values(:a, :b))  # [1, 2]
      p({ a: 1, b: [2, 3] }.flatten)          # [:a, 1, :b, [2, 3]]

      # Symbol name access + case-insensitive compare.
      p :hello[1, 3]              # "ell"
      p :Hello.casecmp?(:hELLO)   # true

      # Proc composition.
      inc = ->(x) { x + 1 }
      dbl = ->(x) { x * 2 }
      p((inc >> dbl).call(3))   # 8  -- dbl(inc(3))
      p((inc << dbl).call(3))   # 7  -- inc(dbl(3))

      # Regexp source-escaping + flag bitmask.
      p Regexp.escape("a.b*c")   # "a\\.b\\*c"
      p(/abc/i.options)          # 1  -- IGNORECASE
      p(/abc/m.options)          # 4  -- MULTILINE

      # Complex cartesian constructor.
      p Complex.rect(3, 4)       # (3+4i)

      # Range binary search (find-minimum): first element the block accepts.
      p((1..100).bsearch { |x| x >= 40 })   # 40
      p((1..10).bsearch { |x| x >= 40 })    # nil
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      15
      15
      0
      true
      true
      true
      [104, 101, 108, 108, 111]
      ["he", "l", "lo"]
      ["hel", "l", "o"]
      "Name"
      "file"
      ""
      "line"
      nil
      "XYllo"
      [[1, 1], [1, 2], [2, 1], [2, 2]]
      [[1, 1], [1, 2], [2, 2]]
      true
      [1, 2, 3, 4]
      {a: 1, c: 3}
      {a: 1, c: 3}
      [1, 2]
      [:a, 1, :b, [2, 3]]
      "ell"
      true
      8
      7
      "a\\.b\\*c"
      1
      4
      (3+4i)
      40
      nil
    OUT
  end

  it "nil object id range cover and struct not equal" do
    result = ze0(<<~'RUBY')
      # nil.object_id is 4 (CRuby 4.0.6). Range#cover? accepts a Range argument
      # (containment). Struct#!= negates the struct's value == (not identity).

      p nil.object_id
      p((1..5).cover?(2..4))
      p((1..5).cover?(0..4))
      p((1..5).cover?(2..6))
      S = Struct.new(:a, :b)
      x = S.new(5, 6)
      p(x == S.new(5, 6))
      p(x != S.new(5, 6))
      p(x != S.new(5, 9))
    RUBY

    _(result).must_answer <<~'OUT'
      4
      true
      false
      false
      true
      false
      true
    OUT
  end

  it "open side counts as infinite without a walk" do
    result = ze0(<<~'RUBY')
      # A range with an open side holds an infinite count, and CRuby answers
      # that without a walk. An argument or a block counts the members that
      # match, so those walk and a side that cannot iterate raises. A walk
      # backwards names the end it cannot start from, which is the begin of a
      # beginless range.
      def t = yield rescue [$!.class, $!.message]

      p t { (..5).count }
      p t { (1..).count }
      p t { (..5.0).count }
      p t { (1..5).count }
      p t { ("a".."e").count }
      p t { (1.0..5.0).count }
      p t { (..5).count(3) }
      p t { (1..5).count { |x| x.odd? } }

      p t { (..5).reverse_each.first(3) }
      p t { (..5.0).reverse_each.first(2) }
      p t { (1..).reverse_each.first(2) }
      p t { (1.0..5.0).reverse_each.to_a }

    RUBY

    _(result).must_answer <<~'OUT'
      Infinity
      Infinity
      Infinity
      5
      5
      [TypeError, "can't iterate from Float"]
      [TypeError, "can't iterate from NilClass"]
      3
      [5, 4, 3]
      [TypeError, "can't iterate from NilClass"]
      [TypeError, "can't iterate from NilClass"]
      [TypeError, "can't iterate from Float"]
    OUT
  end

  it "overlap compares as range c does" do
    result = ze0(<<~'RUBY')
      pairs = [[0..2, 1..3], [0..2, 3..4], [0...3, 3..4], [0.., ..0], [..0, ..5], [..0, 1..], [5..1, 0..9], [1...1, 1..1], ["a".."c", "b".."z"], [1..2, "a".."b"], [nil..nil, 1..2], [(1..), (3..)], [1.0..2.5, 2.5..3]]
      pairs.each { |a, b| p [a, b, a.overlap?(b), b.overlap?(a)] }
      begin; (1..2).overlap?(3); rescue TypeError => e; p e.message; end
      class R < Range; def begin = raise("begin"); def end = raise("end"); end
      p R.new(1, 3).overlap?(R.new(2, 4))

    RUBY

    _(result).must_answer <<~'OUT'
      [0..2, 1..3, true, true]
      [0..2, 3..4, false, false]
      [0...3, 3..4, false, false]
      [0.., ..0, true, true]
      [..0, ..5, true, true]
      [..0, 1.., false, false]
      [5..1, 0..9, false, false]
      [1...1, 1..1, false, false]
      ["a".."c", "b".."z", true, true]
      [1..2, "a".."b", false, false]
      [nil..nil, 1..2, true, true]
      [1.., 3.., true, true]
      [1.0..2.5, 2.5..3, true, true]
      "wrong argument type Integer (expected Range)"
      true
    OUT
  end

  it "rand ranges and random equality" do
    result = ze0(<<~'RUBY')
      # Kernel#rand / Random#rand range semantics, and Random equality.

      # A range argument draws a value within it (Integer range -> Integer, a Float
      # endpoint -> Float). srand makes the draw deterministic, so assert membership.
      srand(3)
      p (1..1000).cover?(rand(1..1000))
      p (0.0...1.0).cover?(rand(0.0...1.0))

      # An empty or reversed range answers nil (NOT an error).
      p rand(5...5)
      p rand(5..3)
      p rand(2.0...2.0)

      # A beginless or endless range is a domain error.
      def caught
        yield
      rescue => e
        "#{e.class}: #{e.message}"
      end
      p caught { rand(1..) }
      p caught { rand(..5) }

      # A negative bound draws from [0, |n|).
      p rand(-3) >= 0
      p rand(-3) < 3

      # Random#== compares seed and stream position (not identity): two fresh
      # same-seed generators are equal until one draws.
      a = Random.new(1)
      b = Random.new(1)
      p a == b
      a.rand(100)
      p a == b
      p Random.new(1) == Random.new(2)
      p Random.new_seed.class
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      nil
      nil
      nil
      "Errno::EDOM: Numerical argument out of domain"
      "Errno::EDOM: Numerical argument out of domain"
      true
      true
      true
      false
      false
      Integer
    OUT
  end

  it "rand ranges edge cases and random equality" do
    result = ze0(<<~'RUBY')
      p rand(5...5)
      p rand(5..3)
      p rand(-3) >= 0
      srand(3); v = rand(1..1000); p (1..1000).cover?(v)
      p Random.new(1) == Random.new(1)
      p Random.new(1) == Random.new(2)
      r = Random.new(7); p r == r
      p Random.new_seed.class
      def t; yield; rescue => e; e.class; end
      p t { rand(1..) }
      p t { rand(..5) }
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      true
      true
      true
      false
      true
      Integer
      Errno::EDOM
      Errno::EDOM
    OUT
  end

  it "subclass sees only the calls ruby makes" do
    result = ze0(<<~'RUBY')
      # Which of Range's own methods its methods call on a subclass: every
      # method Range defines is wrapped to log a call made from inside another,
      # and each is then called once on a fresh receiver. CRuby calls one by
      # dispatch only where it means to, and ze0's core, written in Ruby, has
      # to call no more and no fewer. Written by tools/dispatch.rb.

      class Probe < Range
        CALLING = []
        LOG = []
        [:%, :==, :===, :all?, :any?, :begin, :bsearch, :chain, :chunk, :chunk_while, :collect, :collect_concat, :compact, :count, :cover?, :cycle, :detect, :drop, :drop_while, :each, :each_cons, :each_entry, :each_slice, :each_with_index, :each_with_object, :end, :entries, :eql?, :exclude_end?, :filter, :filter_map, :find, :find_all, :find_index, :first, :flat_map, :grep, :grep_v, :group_by, :hash, :include?, :initialize_copy, :inject, :inspect, :last, :lazy, :map, :max, :max_by, :member?, :min, :min_by, :minmax, :minmax_by, :none?, :one?, :overlap?, :partition, :reduce, :reject, :reverse_each, :select, :size, :slice_after, :slice_before, :slice_when, :sort, :sort_by, :step, :sum, :take, :take_while, :tally, :to_a, :to_h, :to_s, :to_set, :uniq, :zip].each do |m|
          define_method(m) do |*args, &blk|
            LOG << "#{CALLING.last}->#{m}" unless CALLING.empty?
            CALLING << m
            begin
              super(*args, &blk)
            ensure
              CALLING.pop
            end
          end
          ruby2_keywords(m)
        end
      end

      def call(name)
        r = Probe.new(1, 5)
        Probe::LOG.clear
        begin
          yield r
        rescue StandardError => e
          Probe::LOG << "raised #{e.class}"
        end
        puts "#{name}: #{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
      end

      call("%") { |r| r.__send__(:%, 1) { |*x| x.first } }
      call("==") { |r| r.__send__(:==, 1) { |*x| x.first } }
      call("===") { |r| r.__send__(:===, 1) { |*x| x.first } }
      call("all?") { |r| r.all?() { |*x| x.first } }
      call("any?") { |r| r.any?() { |*x| x.first } }
      call("begin") { |r| r.begin() { |*x| x.first } }
      call("bsearch") { |r| r.bsearch() { |*x| x.first } }
      call("chain") { |r| r.chain() { |*x| x.first } }
      call("chunk") { |r| r.chunk() { |*x| x.first } }
      call("chunk_while") { |r| r.chunk_while() { |*x| x.first } }
      call("collect") { |r| r.collect() { |*x| x.first } }
      call("collect_concat") { |r| r.collect_concat() { |*x| x.first } }
      call("compact") { |r| r.compact() { |*x| x.first } }
      call("count") { |r| r.count() { |*x| x.first } }
      call("cover?") { |r| r.cover?(1) { |*x| x.first } }
      call("detect") { |r| r.detect() { |*x| x.first } }
      call("drop") { |r| r.drop(1) { |*x| x.first } }
      call("drop_while") { |r| r.drop_while() { |*x| x.first } }
      call("each") { |r| r.each() { |*x| x.first } }
      call("each_cons") { |r| r.each_cons(1) { |*x| x.first } }
      call("each_entry") { |r| r.each_entry() { |*x| x.first } }
      call("each_slice") { |r| r.each_slice(1) { |*x| x.first } }
      call("each_with_index") { |r| r.each_with_index() { |*x| x.first } }
      call("each_with_object") { |r| r.each_with_object(1) { |*x| x.first } }
      call("end") { |r| r.end() { |*x| x.first } }
      call("entries") { |r| r.entries() { |*x| x.first } }
      call("eql?") { |r| r.eql?(1) { |*x| x.first } }
      call("exclude_end?") { |r| r.exclude_end?() { |*x| x.first } }
      call("filter") { |r| r.filter() { |*x| x.first } }
      call("filter_map") { |r| r.filter_map() { |*x| x.first } }
      call("find") { |r| r.find() { |*x| x.first } }
      call("find_all") { |r| r.find_all() { |*x| x.first } }
      call("find_index") { |r| r.find_index() { |*x| x.first } }
      call("first") { |r| r.first() { |*x| x.first } }
      call("flat_map") { |r| r.flat_map() { |*x| x.first } }
      call("grep") { |r| r.grep(1) { |*x| x.first } }
      call("grep_v") { |r| r.grep_v(1) { |*x| x.first } }
      call("group_by") { |r| r.group_by() { |*x| x.first } }
      call("hash") { |r| r.hash() { |*x| x.first } }
      call("include?") { |r| r.include?(1) { |*x| x.first } }
      call("inject") { |r| r.inject() { |*x| x.first } }
      call("inspect") { |r| r.inspect() { |*x| x.first } }
      call("last") { |r| r.last() { |*x| x.first } }
      call("lazy") { |r| r.lazy() { |*x| x.first } }
      call("map") { |r| r.map() { |*x| x.first } }
      call("max") { |r| r.max() { |*x| x.first } }
      call("max_by") { |r| r.max_by() { |*x| x.first } }
      call("member?") { |r| r.member?(1) { |*x| x.first } }
      call("min") { |r| r.min() { |*x| x.first } }
      call("min_by") { |r| r.min_by() { |*x| x.first } }
      call("minmax") { |r| r.minmax() { |*x| x.first } }
      call("minmax_by") { |r| r.minmax_by() { |*x| x.first } }
      call("none?") { |r| r.none?() { |*x| x.first } }
      call("one?") { |r| r.one?() { |*x| x.first } }
      call("overlap?") { |r| r.overlap?(1..2) { |*x| x.first } }
      call("partition") { |r| r.partition() { |*x| x.first } }
      call("reduce") { |r| r.reduce() { |*x| x.first } }
      call("reject") { |r| r.reject() { |*x| x.first } }
      call("reverse_each") { |r| r.reverse_each() { |*x| x.first } }
      call("select") { |r| r.select() { |*x| x.first } }
      call("size") { |r| r.size() { |*x| x.first } }
      call("slice_after") { |r| r.slice_after() { |*x| x.first } }
      call("slice_before") { |r| r.slice_before() { |*x| x.first } }
      call("slice_when") { |r| r.slice_when() { |*x| x.first } }
      call("sort") { |r| r.sort() { |*x| x.first } }
      call("sort_by") { |r| r.sort_by() { |*x| x.first } }
      call("step") { |r| r.step() { |*x| x.first } }
      call("sum") { |r| r.sum() { |*x| x.first } }
      call("take") { |r| r.take(1) { |*x| x.first } }
      call("take_while") { |r| r.take_while() { |*x| x.first } }
      call("tally") { |r| r.tally() { |*x| x.first } }
      call("to_a") { |r| r.to_a() { |*x| x.first } }
      call("to_s") { |r| r.to_s() { |*x| x.first } }
      call("to_set") { |r| r.to_set() { |*x| x.first } }
      call("uniq") { |r| r.uniq() { |*x| x.first } }
      call("zip") { |r| r.zip() { |*x| x.first } }

    RUBY

    _(result).must_answer <<~'OUT'
      all?: all?->each
      any?: any?->each
      collect: collect->each
      collect_concat: collect_concat->each
      compact: compact->each
      count: count->each
      detect: detect->each
      drop: drop->each
      drop_while: drop_while->each
      each_cons: each_cons->size each_cons->each
      each_entry: each_entry->each
      each_slice: each_slice->size each_slice->each
      each_with_index: each_with_index->each
      each_with_object: each_with_object->each
      entries: entries->each
      filter: filter->each
      filter_map: filter_map->each
      find: find->each
      find_all: find_all->each
      find_index: find_index->each
      flat_map: flat_map->each
      grep: grep->each
      grep_v: grep_v->each
      group_by: group_by->each
      inject: inject->each
      map: map->each
      max: max->each
      max_by: max_by->each
      min: min->each
      min_by: min_by->each
      minmax: minmax->each
      minmax_by: minmax_by->each
      none?: none?->each
      one?: one?->each
      partition: partition->each
      reduce: reduce->each
      reject: reject->each
      select: select->each
      sort: sort->each
      sort_by: sort_by->each
      sum: sum->each
      take: take->each
      take_while: take_while->each
      tally: tally->each
      to_a: to_a->each
      to_set: to_set->each_entry each_entry->each
      uniq: uniq->each
      zip: zip->each
    OUT
  end

  it "top level endless def" do
    _(ze0(<<~'RUBY')).must_answer "42\n"
      def double(x) = x * 2
      puts double(21)
    RUBY
  end
end
