# frozen_string_literal: true

require "spec_helper"

describe "Array programs" do
  it "array and hash try convert" do
    result = ze0(<<~'RUBY')
      p Array.try_convert([1, 2])
      p Array.try_convert("no")
      p Hash.try_convert({ a: 1 })
      p Hash.try_convert(5)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      nil
      {a: 1}
      nil
    OUT
  end

  it "array delete returns matched element" do
    result = ze0(<<~'RUBY')
      class Always
        def ==(o) = true
        def inspect = "#<Always>"
      end

      a = [Always.new]
      p a.delete(1)
      p a
      p [1, 2].delete(1)
      p [1, 2].delete(9)
      p [1, 2].delete(9) { :blk }
    RUBY

    _(result).must_answer <<~'OUT'
      #<Always>
      []
      1
      nil
      :blk
    OUT
  end

  it "array fill offset check" do
    result = ze0(<<~'RUBY')
      # fill(value, start[, length]): start and length are offsets, and a value with
      # no integer conversion is CRuby's TypeError. They went into the offset slot
      # as-is, so a String start read as a pointer and the fill quietly did nothing.
      p(([1,2].fill(0,"x") rescue $!.message))
      p(([1,2].fill(0,nil)))
      p(([1,2,3].fill(0,1)))
      p([1,2,3].fill(9))
      p([1,2,3].fill(9,1,1))
      p((["a"].fill("z",:s) rescue $!.message))
    RUBY

    _(result).must_answer <<~'OUT'
      "no implicit conversion of String into Integer"
      [0, 0]
      [1, 0, 0]
      [9, 9, 9]
      [1, 9, 3]
      "no implicit conversion of Symbol into Integer"
    OUT
  end

  it "array fill widen" do
    result = ze0(<<~'RUBY')
      # Array#fill whose value another element kind cannot hold must widen the array,
      # not store the value's raw bits (an int array filled with :a held garbage).
      a = [1, 2, 3]
      a.fill(:a)
      p a
      b = [1, 2, 3, 4]
      b.fill(:z, 2)
      p b
      c = [1, "x", 2]
      c.fill("y")
      p c
      d = [1, 2, 3]
      d.fill(9)
      p d
      e = [1.0, 2.0]
      e.fill(0.5)
      p e
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, :a, :a]
      [1, 2, :z, :z]
      ["y", "y", "y"]
      [9, 9, 9]
      [0.5, 0.5]
    OUT
  end

  it "array frozen mutate raises" do
    result = ze0(<<~'RUBY')
      # Array mutating methods on frozen arrays must raise FrozenError.
      # IntArray#pop/#shift already had the guard; FloatArray, StrArray,
      # and the reverse_bang/sort_bang/shuffle_bang/rotate_bang/delete_at
      # /delete/insert methods were missing it.

      # IntArray
      a = [1, 2, 3]
      a.freeze
      begin; a.reverse!; puts "BUG int reverse!"; rescue FrozenError; puts "int reverse!"; end
      begin; a.sort!; puts "BUG int sort!"; rescue FrozenError; puts "int sort!"; end
      begin; a.shuffle!; puts "BUG int shuffle!"; rescue FrozenError; puts "int shuffle!"; end
      begin; a.rotate!(1); puts "BUG int rotate!"; rescue FrozenError; puts "int rotate!"; end
      begin; a.delete_at(0); puts "BUG int delete_at"; rescue FrozenError; puts "int delete_at"; end
      begin; a.delete(1); puts "BUG int delete"; rescue FrozenError; puts "int delete"; end

      # FloatArray
      f = [1.5, 2.5, 3.5]
      f.freeze
      begin; f.reverse!; puts "BUG float reverse!"; rescue FrozenError; puts "float reverse!"; end
      begin; f.sort!; puts "BUG float sort!"; rescue FrozenError; puts "float sort!"; end
      begin; f.shuffle!; puts "BUG float shuffle!"; rescue FrozenError; puts "float shuffle!"; end
      begin; f.rotate!(1); puts "BUG float rotate!"; rescue FrozenError; puts "float rotate!"; end
      begin; f.pop; puts "BUG float pop"; rescue FrozenError; puts "float pop"; end
      begin; f.shift; puts "BUG float shift"; rescue FrozenError; puts "float shift"; end

      # StrArray
      s = ["a", "b", "c"]
      s.freeze
      begin; s.reverse!; puts "BUG str reverse!"; rescue FrozenError; puts "str reverse!"; end
      begin; s.sort!; puts "BUG str sort!"; rescue FrozenError; puts "str sort!"; end
      begin; s.shuffle!; puts "BUG str shuffle!"; rescue FrozenError; puts "str shuffle!"; end
      begin; s.rotate!(1); puts "BUG str rotate!"; rescue FrozenError; puts "str rotate!"; end
      begin; s.pop; puts "BUG str pop"; rescue FrozenError; puts "str pop"; end
      begin; s.delete_at(0); puts "BUG str delete_at"; rescue FrozenError; puts "str delete_at"; end
      begin; s.delete("a"); puts "BUG str delete"; rescue FrozenError; puts "str delete"; end
      begin; s.insert(0, "z"); puts "BUG str insert"; rescue FrozenError; puts "str insert"; end
    RUBY

    _(result).must_answer <<~'OUT'
      int reverse!
      int sort!
      int shuffle!
      int rotate!
      int delete_at
      int delete
      float reverse!
      float sort!
      float shuffle!
      float rotate!
      float pop
      float shift
      str reverse!
      str sort!
      str shuffle!
      str rotate!
      str pop
      str delete_at
      str delete
      str insert
    OUT
  end

  it "array frozen mutation raises" do
    result = ze0(<<~'RUBY')
      # Every mutating Array method raises FrozenError on a frozen receiver.

      a = [1, 2, 3].freeze
      def caught(a, name)
        yield
        "BUG #{name}"
      rescue FrozenError => e
        e.message
      end
      p caught(a, "reverse!") { a.reverse! }
      p caught(a, "sort!") { a.sort! }
      p caught(a, "delete") { a.delete(1) }
      p caught(a, "insert") { a.insert(0, 9) }
      p caught(a, "clear") { a.clear }
      p caught(a, "pop") { a.pop }
      p caught(a, "select!") { a.select! { true } }
    RUBY

    _(result).must_answer <<~'OUT'
      "can't modify frozen Array: [1, 2, 3]"
      "can't modify frozen Array: [1, 2, 3]"
      "can't modify frozen Array: [1, 2, 3]"
      "can't modify frozen Array: [1, 2, 3]"
      "can't modify frozen Array: [1, 2, 3]"
      "can't modify frozen Array: [1, 2, 3]"
      "can't modify frozen Array: [1, 2, 3]"
    OUT
  end

  it "array gap is nil" do
    result = ze0(<<~'RUBY')
      # `a[n] = v` past the end fills the gap with nil, not the element type's zero
      # value (#3836).
      a = ["x"]
      a[3] = "y"
      p a
      b = [1]
      b[3] = 5
      p b
      f = [1.0]
      f[2] = 2.0
      p f
      p a[1]
      p b[1]
      p f[1]
      p a.compact
      p b.compact
    RUBY

    _(result).must_answer <<~'OUT'
      ["x", nil, nil, "y"]
      [1, nil, nil, 5]
      [1.0, nil, 2.0]
      nil
      nil
      nil
      ["x", "y"]
      [1, 5]
    OUT
  end

  it "array include calls element equality" do
    result = ze0(<<~'RUBY')
      class Boom
        def ==(o) = raise("cmp")
      end

      begin
        p [Boom.new].include?(1)
      rescue RuntimeError => e
        p [:raised, e.message]
      end

      begin
        p [Boom.new].index(1)
      rescue RuntimeError => e
        p [:raised, e.message]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:raised, "cmp"]
      [:raised, "cmp"]
    OUT
  end

  it "array join nested" do
    result = ze0(<<~'RUBY')
      # Array#join flattens nested arrays recursively with the same separator.
      p [1, [2, 3], 4].join("-")
      p [[1, 2], [3, 4]].join(",")
      p [1, [2, [3, 4]]].join
      p [[1], "a", [2, [3]]].join("|")
      p [1, 2, 3].join("-")
    RUBY

    _(result).must_answer <<~'OUT'
      "1-2-3-4"
      "1,2,3,4"
      "1234"
      "1|a|2|3"
      "1-2-3"
    OUT
  end

  it "array join poly separator" do
    _(ze0(<<~'RUBY')).must_answer "MyApp : Dash\n"
      # Array#join's separator must be a const char*; when the separator widens to
      # poly (an ivar/reader unified to poly across the program), it has to be
      # coerced with sp_poly_to_s rather than passed raw -- otherwise sp_*Array_join
      # gets an sp_RbVal where a const char* is expected (incompatible pointer type).
      class P
        def initialize(app, sep)
          @app = app
          @sep = sep
        end
        def app
          @app || "fallback"
        end
        def sep
          @sep
        end
        def render
          [app, "Dash"].compact.join(sep)
        end
      end

      puts P.new("MyApp", " : ").render
      P.new("X", 5)   # a second call site with a non-string separator widens @sep to poly
    RUBY
  end

  it "array join recursive and delete block" do
    result = ze0(<<~'RUBY')
      # join flattens nested arrays under the same separator; delete's not-found
      # block supplies the answer.

      p [1, [2, [3, 4]], 5].join("-")
      p [[1], "a", [2, [3]]].join("|")
      p ["a", "b"].delete("z") { "missing" }
      p ["a", "b"].delete("a") { "missing" }
      p [1, 2].delete(9)
    RUBY

    _(result).must_answer <<~'OUT'
      "1-2-3-4-5"
      "1|a|2|3"
      "missing"
      "a"
      nil
    OUT
  end

  it "array literal" do
    result = ze0(<<~'RUBY')
      a = [1, 2, 3]
      puts(a[0])
      puts(a[2])
      puts(a[-1])
      puts(a[10])
      a[1] = 99
      puts(a[1])
      puts(a.length)
      puts(a.size)

      rest = [3, 4]
      b = [1, 2, *rest, 5]
      puts(b.length)
      puts(b[2])
      puts(b[4])
    RUBY

    _(result).must_answer <<~'OUT'
      1
      3
      3

      99
      3
      3
      5
      3
      5
    OUT
  end

  it "array literal indexing and mutation" do
    result = ze0(<<~'RUBY')
      a = [1, 2, 3]
      puts(a[0])
      puts(a[2])
      puts(a[-1])
      puts(a[10])
      a[1] = 99
      puts(a[1])
      puts(a.length)
      puts(a.size)

      rest = [3, 4]
      b = [1, 2, *rest, 5]
      puts(b.length)
      puts(b[2])
      puts(b[4])
    RUBY

    _(result).must_answer <<~'OUT'
      1
      3
      3

      99
      3
      3
      5
      3
      5
    OUT
  end

  it "array mul negative raises" do
    result = ze0(<<~'RUBY')
      # Array#* with a negative count raises ArgumentError (was: silently []).
      w = %w[a] * 0
      p w
      begin
        %w[a] * -3
      rescue ArgumentError => e
        puts "AE2: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      []
      AE2: negative argument
    OUT
  end

  it "array new bare receiver" do
    result = ze0(<<~'RUBY')
      p Array.new.frozen?
      p Array.new.class
      p Array.new.size
      p Array.new.empty?
      p Array.new(0).size
      a = Array.new
      p a.size
      a = Array.new
      a << 1
      p a
      p a.shift(1)
      b = Array.new
      p b.pop(1)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      Array
      0
      true
      0
      0
      [1]
      [1]
      []
    OUT
  end

  it "array new container default" do
    result = ze0(<<~'RUBY')
      # Array.new(n, <empty container literal>) fills every slot with ONE
      # shared container object (CRuby aliasing: mutating a[0] shows in a[1]).
      p Array.new(2, [])
      p Array.new(2, {})
      a = Array.new(2, [])
      a[0] << 1
      p a
      p Array.new(3, 7)
      p Array.new(2, "s")
    RUBY

    _(result).must_answer <<~'OUT'
      [[], []]
      [{}, {}]
      [[1], [1]]
      [7, 7, 7]
      ["s", "s"]
    OUT
  end

  it "array optional and variadic arities" do
    result = ze0(<<~'RUBY')
      # The builtin tables used to hardcode a single arity and reject the
      # optional-`n` and variadic forms Ruby accepts: `last(n)`, `sample(n)`,
      # the block form of `rindex`, the fill span forms, and the variadic
      # set-op siblings `union`/`intersection`/`difference` (distinct from the
      # binary `|`/`&`/`-`). All oracle-verified against ruby 4.0.6.

      p [1, 2, 3].last(2)
      p [1, 2, 3].last(0)
      p [1, 2, 3].last(5)
      p [1, 2, 3, 2].rindex { |x| x < 3 }
      p [1, 2, 3, 2].rindex(2)
      p [1, 2, 3].union
      p [1, 2, 3].union([2, 3], [4])
      p [1, 2, 3, 4].intersection([2, 3, 4], [3, 4, 5])
      p [1, 2, 3].difference([2], [4])
      p [1, 1, 2].difference([2])
      a = [0, 0, 0]; a.fill(9); p a
      a = [0, 0, 0]; a.fill(9, 1, 1); p a
      a = [1, 2, 3]; a.fill(9, 1, 5); p a
      a = [1, 2, 3]; a.fill { |i| i }; p a
      a = [1, 2, 3, 4, 5]; a.fill(-2) { |i| i * 10 }; p a
      p [1, 2, 3].sample(2).length
      p [1, 2, 3].sample(5).sort
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3]
      []
      [1, 2, 3]
      3
      3
      [1, 2, 3]
      [1, 2, 3, 4]
      [3, 4]
      [1, 3]
      [1, 1]
      [9, 9, 9]
      [0, 9, 0]
      [1, 9, 9, 9, 9, 9]
      [0, 1, 2]
      [1, 2, 3, 30, 40]
      2
      [1, 2, 3]
    OUT
  end

  it "array product multi arg" do
    result = ze0(<<~'RUBY')
      # Array#product with two or more array arguments builds the n-way Cartesian
      # product (one element from each input, in order). Previously only the single
      # argument form had a codegen arm; 2+ arguments were rejected.
      p [1, 2].product([3, 4], [5, 6])          # 8 triples
      p [1, 2].product([3, 4])                   # single-arg form still works
      p [1, 2, 3].product([4, 5], [6])           # mixed lengths
      p [1].product([2], [3], [4])               # four inputs -> one 4-tuple
      p [1, 2].product([3, 4], [])               # an empty input -> empty product

      # Non-literal receiver and arguments (defeats constant folding).
      def prod(a, b, c); a.product(b, c); end
      p prod([1, 2], [3, 4], [5, 6])

      # String and mixed element types.
      p ["a", "b"].product([1, 2], [:x])         # tuples carry each element's type
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 3, 5], [1, 3, 6], [1, 4, 5], [1, 4, 6], [2, 3, 5], [2, 3, 6], [2, 4, 5], [2, 4, 6]]
      [[1, 3], [1, 4], [2, 3], [2, 4]]
      [[1, 4, 6], [1, 5, 6], [2, 4, 6], [2, 5, 6], [3, 4, 6], [3, 5, 6]]
      [[1, 2, 3, 4]]
      []
      [[1, 3, 5], [1, 3, 6], [1, 4, 5], [1, 4, 6], [2, 3, 5], [2, 3, 6], [2, 4, 5], [2, 4, 6]]
      [["a", 1, :x], ["a", 2, :x], ["b", 1, :x], ["b", 2, :x]]
    OUT
  end

  it "array setop assign" do
    result = ze0(<<~'RUBY')
      # Array set-operation op-assign: `a |= b` (union), `a &= b` (intersection),
      # `a -= b` (difference) desugar to `a = a OP b`, mirroring the already-working
      # binary operators. Values route through a per-kind identity method so each
      # local keeps a concrete array type and the typed runtime helper is exercised
      # rather than a compile-time fold.
      def ai(x); x; end   # Integer arrays
      def aw(x); x; end   # String arrays
      def af(x); x; end   # Float arrays
      def am(x); x; end   # poly arrays

      # Integer arrays
      g = ai([1, 2, 3])
      g |= ai([3, 4])
      p g
      g &= ai([1, 4])
      p g
      g -= ai([4])
      p g

      # String arrays
      w = aw(["a", "b"])
      w |= aw(["b", "c"])
      p w
      w -= aw(["a"])
      p w

      # Float arrays
      f = af([1.0, 2.0])
      f |= af([2.0, 3.0])
      p f

      # poly arrays
      m = am([1, "a", 2])
      m |= am(["a", 3])
      p m

      # union dedups preserving first-seen order
      d = ai([1, 2, 2, 3])
      d |= ai([3, 3, 4])
      p d

      # empty rhs
      e = ai([1, 2, 3])
      e &= []
      p e
      e2 = ai([1, 2, 3])
      e2 |= []
      p e2
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [1, 4]
      [1]
      ["a", "b", "c"]
      ["b", "c"]
      [1.0, 2.0, 3.0]
      [1, "a", 2, 3]
      [1, 2, 3, 4]
      []
      [1, 2, 3]
    OUT
  end

  it "array to h pairs" do
    result = ze0(<<~'RUBY')
      # Array#to_h (pair form) builds a hash from [key, value] sub-arrays. Each pair
      # may itself be a homogeneous typed array (IntArray for [1, 2], StrArray for
      # ["a", "b"]) or a mixed PolyArray, so the element extraction must dispatch on
      # the pair's own array kind rather than assuming PolyArray.
      p [[1, 2], [3, 4]].to_h
      p [["a", 1], ["b", 2]].to_h
      p [["a", "x"], ["b", "y"]].to_h
      p [[:x, 10], [:y, 20]].to_h

      # A non-literal receiver (routed through a method parameter) cannot have its
      # pair element types resolved statically, so the keys/values stay boxed and
      # still render correctly.
      def to_h_of(pairs)
        pairs.to_h
      end
      p to_h_of([["k", 1], ["m", 2]])
      p to_h_of([[1, 10], [2, 20]])
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => 2, 3 => 4}
      {"a" => 1, "b" => 2}
      {"a" => "x", "b" => "y"}
      {x: 10, y: 20}
      {"k" => 1, "m" => 2}
      {1 => 10, 2 => 20}
    OUT
  end

  it "begin rescue array body" do
    result = ze0(<<~'RUBY')
      r001 = (begin; a001 = [1].freeze; a001 << 2; rescue FrozenError => e001; e001.class; end)
      p r001

      r002 = (begin; a002 = 1; a002; rescue => e002; e002.class; end); p r002   # => 1
      r003 = (begin; a003 = [1]; a003; rescue; 0; end); p r003                  # => [1]
      p(begin; a004 = [1]; a004; rescue; 0; end)                                # => [1]
      r005 = ([1].freeze << 2 rescue $!.class); p r005                          # => FrozenError

      r = (begin; a = [1]; a << 2; rescue => e; 99; end); p r
      r = (begin; a = [1]; a.push(2); rescue => e; e.class; end); p r
      r = (begin; s = "x".freeze; s << "y"; rescue FrozenError => e; e.class; end); p r
      r = (begin; h = { k: 1 }; h.size; rescue => e; e.class; end); p r
    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
      1
      [1]
      [1]
      FrozenError
      [1, 2]
      [1, 2]
      FrozenError
      1
    OUT
  end

  it "bsearch find any mixed" do
    result = ze0(<<~'RUBY')
      p((1..100).bsearch { |x| x*x >= 50 ? x*x - 50 : nil })
      p((0..100).bsearch { |x| 100 - x*x })
      p((1..10).bsearch { |x| x >= 4 })
      p((1..100).bsearch { |x| x < 8 ? 1 : (x == 8 ? 0 : -1) })
      p [1, 3, 7, 9, 12].bsearch { |x| x < 9 ? nil : (x == 9 ? 0 : -1) }
      p [1, 3, 7, 9, 12].bsearch { |x| x - 7 }
      p((1..10).bsearch { |x| x - 8 })
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      10
      4
      8
      9
      7
      nil
    OUT
  end

  it "call site splat expands an array into positional arguments" do
    result = ze0(<<~'RUBY')
      class Adder
        def add3(a, b, c)
          a + b + c
        end
      end
      a = Adder.new
      arr = [1, 2, 3]
      puts a.add3(*arr)
      puts a.add3(1, *[2, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
    OUT
  end

  it "case in value nested array" do
    _(ze0(<<~'RUBY')).must_answer "[1, 2, 3, 4]\n"
      # A nested-array case/in used in value position (its result assigned).
      def s(x); x; end
      r = case s([1, [2, 3], 4])
          in [a, [b, c], d] then [a, b, c, d]
          end
      p r
    RUBY
  end

  it "data not diggable" do
    result = ze0(<<~'RUBY')
      D = Data.define(:v)
      r = ([D.new(2)].dig(0, :v) rescue $!.class)
      p r

      r = (D.new(2).dig(:v) rescue $!.class); p r          # Ruby: NoMethodError   Spinel: 2
      h = { k: D.new(2) }
      r = (h.dig(:k, :v) rescue $!.class); p r             # Ruby: TypeError       Spinel: 2

      S = Struct.new(:w)
      p([S.new(3)].dig(0, :w))                             # => 3
      r = ([1].dig(0, 0) rescue $!.class); p r             # => TypeError
      r = ([1.5].dig(0, 0) rescue $!.class); p r           # => TypeError
      r = ({ a: 1 }.dig(:a, :b) rescue $!.class); p r      # => TypeError

      S9 = Struct.new(:v)
      p([S9.new(4)].dig(0, :v))
      p({ k: S9.new(5) }.dig(:k, :v))
      p(S9.new(6).dig(:v))
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      NoMethodError
      TypeError
      3
      TypeError
      TypeError
      TypeError
      4
      5
      6
    OUT
  end

  it "dig with splat keys" do
    result = ze0(<<~'RUBY')
      # dig(*keys) walks a key list only known at run time, for both Hash and Array
      # receivers and from behind a method boundary.
      h = { server: { host: "x", port: 8080 } }
      keys = [:server, :host]
      p h.dig(*keys)
      p h.dig(:server, :port)
      p h.dig(*[:server, :nope])
      p h.dig(*[:nope, :host])
      a = [[1, [2, 3]]]
      ak = [0, 1, 0]
      p a.dig(*ak)
      def look(hh, ks)
        hh.dig(*ks)
      end
      p look(h, [:server, :host])
      p look(h, [:server])
    RUBY

    _(result).must_answer <<~'OUT'
      "x"
      8080
      nil
      nil
      2
      "x"
      {host: "x", port: 8080}
    OUT
  end

  it "empty array const" do
    result = ze0(<<~'RUBY')
      # A constant bound to an EMPTY array literal has no element type to read off the
      # literal. That left it typed UNKNOWN, which downstream does not read as
      # "unknown" but as UNDEFINED: every reference reported the constant as defined
      # nowhere and raised NameError, where CRuby answers the array. Filling it through
      # `CONST[i] = v` -- the table-building shape -- is now element evidence like
      # `push`, and a constant with no evidence at all still gets the default an empty
      # literal bound to a local gets.
      EMPTY = []
      def read_empty; EMPTY; end
      p read_empty

      TABLE = []
      TABLE[0] = :zero
      TABLE[2] = :two
      def read_table; TABLE; end
      p read_table

      class Codes
        BY_ID = []
        def self.record(id, name)
          BY_ID[id] = name
        end
      end
      Codes.record(1, "one")
      Codes.record(3, "three")
      p Codes::BY_ID

      # Element evidence still wins over the default: pushed ints stay an int array.
      NUMS = []
      NUMS.push(1)
      NUMS.push(2)
      def read_nums; NUMS; end
      p read_nums
      p read_nums.sum
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [:zero, nil, :two]
      [nil, "one", nil, "three"]
      [1, 2]
      3
    OUT
  end

  it "empty array dup slot" do
    result = ze0(<<~'RUBY')
      # `[].dup` is a copy of nothing, so it is a new empty array -- and it has to be
      # built at the target's type. Emitted as an ordinary call it took the empty
      # literal's own default kind and wrote an sp_IntArray into a poly-array slot,
      # where the frozen flag read out of the wrong field.
      a = [].dup
      p a.frozen?
      p a
      a << 1
      a << :two
      p a

      b = []
      p b.frozen?

      c = [].clone
      p c.frozen?
      c << "x"
      p c

      d = [1, 2].dup
      p d
      p d.frozen?
      e = [1, 2].freeze
      p e.clone.frozen?
      p e.dup.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      []
      [1, :two]
      false
      false
      ["x"]
      [1, 2]
      false
      true
      false
    OUT
  end

  it "empty array literal receiver" do
    result = ze0(<<~'RUBY')
      # An empty `[]` literal used directly as a receiver has no element type, and
      # the forms below had no arm that would claim it, so the call was refused
      # outright. They join the receivers that settle on an empty poly array.
      p([].each_with_index.to_a)
      p([].frozen?)
      p([].partition { |pa| pa })
      p([].take_while { |tw| tw })
      p([].drop_while { |dw| dw })

      # the forms that already worked keep working
      p([].min)
      p([].sum)
      p([].size)
      p([] + [1, 2])
      p([].map { |ma| ma })
      p([].each_slice(2).to_a)
      p([].join("-"))

      # and a non-empty literal receiver is unchanged
      p([1, 2].each_with_index.to_a)
      p([1, 2].frozen?)
      p([1, 2].partition { |pb| pb > 1 })
    RUBY

    _(result).must_answer <<~'OUT'
      []
      false
      [[], []]
      []
      []
      nil
      0
      0
      [1, 2]
      []
      []
      ""
      [[1, 0], [2, 1]]
      false
      [[2], [1]]
    OUT
  end

  it "empty array push container elem" do
    result = ze0(<<~'RUBY')
      # `rows = []` followed by `rows << <container>` (where the pushed
      # value is a Hash or another Array, not a primitive) used to leave
      # `rows` typed as int_array — sp_IntArray_push then errored with
      # "incompatible pointer to integer conversion".
      #
      # #412 added the int_array → typed-array upgrade in scan_locals's
      # push observation for primitive element types (str_array,
      # float_array, sym_array, obj_X_ptr_array, poly_array). Container
      # element types (Hash, nested Array) fell through to the bottom
      # default and stayed at int_array.
      #
      # Fix: extend the push observation to recognise hash-type and
      # array-type arg types and promote to poly_array (spinel has no
      # <hash>_ptr_array or <array>_ptr_array_ptr_array slot — boxed
      # poly_array is the canonical container-of-containers shape, same
      # as the literal `[{...}, {...}]` inference at
      # infer_array_elem_type_from_ids).

      def build_hash_rows
        rows = []
        rows << { "k" => "v" }
        rows << { "k" => "v2" }
        rows.length
      end

      def build_nested_arrays
        outer = []
        inner = [1, 2]
        outer << inner
        outer << [3, 4]
        outer.length
      end

      puts build_hash_rows         # 2
      puts build_nested_arrays     # 2
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
    OUT
  end

  it "enum terminal chunk zip lazy" do
    result = ze0(<<~'RUBY')
      # Enumerator terminals over slice/chunk enumerators, string byte enumerator,
      # boolean chunk keys, zip with a Range argument, and lazy take(n).to_a.
      p "hi".each_byte.to_a
      p [1, 2, 3, 4].each_slice(2).count
      p [1, 2, 3, 4].each_slice(2).to_h
      p [1, 2, 3].each_cons(2).count
      p [1, 1, 2, 3].chunk { |x| x }.map { |k, v| k }
      p [1, 2, 3, 4].chunk { |x| x.even? }.to_a
      p [1, 2, 3].zip(4..6)
      p [1, 2].zip([3, 4], 5..6)
      p (1..Float::INFINITY).lazy.map { |x| x * x }.take(3).to_a
      p [1, 2, 3, 4].take(2).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [104, 105]
      2
      {1 => 2, 3 => 4}
      2
      [1, 2, 3]
      [[false, [1]], [true, [2]], [false, [3]], [true, [4]]]
      [[1, 4], [2, 5], [3, 6]]
      [[1, 3, 5], [2, 4, 6]]
      [1, 4, 9]
      [1, 2]
    OUT
  end

  it "eval collections arrays hashes ranges" do
    result = ze0(<<~'RUBY')
      puts eval("[1, 2, 3, 4].length".dup)
      puts eval("{ a: 1, b: 2 }.length".dup)
      puts eval("(1..5).to_a.inspect".dup)
    RUBY

    _(result).must_answer <<~'OUT'
      4
      2
      [1, 2, 3, 4, 5]
    OUT
  end

  it "exception class array inspect" do
    result = ze0(<<~'RUBY')
      # An exception's #class is a real Class object: it inspects bare (not quoted)
      # inside a container, renders as its name via to_s/name, and compares by identity.
      begin
        raise ArgumentError, "x"
      rescue => e
        p [e.class, e.message]       # [ArgumentError, "x"]
        p e.class                    # ArgumentError
        puts e.class.to_s            # ArgumentError
        puts e.class.name            # ArgumentError
        p e.class == ArgumentError   # true
        p e.class == RuntimeError    # false
      end

      # a builtin default-message exception
      begin
        raise "boom"
      rescue => e
        p [e.class, e.message]       # [RuntimeError, "boom"]
      end

      # a user-defined exception subclass reifies to its own Class
      class MyErr < StandardError; end
      begin
        raise MyErr, "oops"
      rescue => e
        p [e.class, e.message]       # [MyErr, "oops"]
        p e.class == MyErr           # true
        puts e.class.name            # MyErr
      end

      # the class survives flowing through a method and boxing alongside other kinds
      def id(v); v; end
      begin
        raise TypeError, "nope"
      rescue => e
        p [1, id(e).class, :ok]      # [1, TypeError, :ok]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "x"]
      ArgumentError
      ArgumentError
      ArgumentError
      true
      false
      [RuntimeError, "boom"]
      [MyErr, "oops"]
      true
      MyErr
      [1, TypeError, :ok]
    OUT
  end

  it "explicit nil size argument converts" do
    result = ze0(<<~'RUBY')
      # `first`, `last`, `pop`, `shift` and `sample` tell an absent count from
      # one given as nil: the absent one takes the whole-receiver form, and an
      # explicit nil goes through the same conversion any other value does.
      def err
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
      err { [1, 2, 3].first(nil) }
      err { [1, 2, 3].last(nil) }
      err { [1, 2, 3].sample(nil) }
      err { [1, 2, 3].shift(nil) }
      err { [1, 2, 3].pop(nil) }
      err { [1, 2, 3].each_entry.first(nil) }
      err { "abc".chars.first(nil) }
      err { "abc".split(",", nil) }
      err { [1].pack(1) }
      err { "A".unpack(1) }
      err { [1, 2, 3].each_slice(nil).to_a }

      # The absent forms are unchanged.
      p [[1, 2, 3].first, [1, 2, 3].last, [1, 2, 3].first(2), [1, 2, 3].last(2)]
      p [[1, 2, 3].pop, [1, 2, 3].shift]

      # A comparison reads the other side as a Hash.
      err { {} < 1 }
      err { {} <= 1 }
      err { {} > 1 }
      err { {} >= 1 }
      p [{ a: 1 } > {}, {} < { a: 1 }, { a: 1 } >= { a: 1 }]
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion of Integer into String
      TypeError: no implicit conversion of Integer into String
      TypeError: no implicit conversion from nil to integer
      [1, 3, [1, 2], [2, 3]]
      [3, 1]
      TypeError: no implicit conversion of Integer into Hash
      TypeError: no implicit conversion of Integer into Hash
      TypeError: no implicit conversion of Integer into Hash
      TypeError: no implicit conversion of Integer into Hash
      [true, true, true]
    OUT
  end

  it "float round digits cruby" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at fa06b601.
      #
      # `Float#round(n)` with a positive digit count rounds by scaling with a power
      # of ten, so the SCALED product's own representation error becomes part of
      # the value:
      #
      #   64.781995.round(5)   CRuby 64.782   zeo 64.78199
      #
      # `64.781995 * 1e5` is `6478199.4999999991`, so the digit that should round
      # up rounds down. CRuby does not scale: `flo_round` works from the decimal
      # representation for exactly this reason.
      #
      # The negative twin diverges the same way, and `round(2)`/`round(3)` agree --
      # so this only shows at the digit counts where the scaled product lands near
      # a half.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix, not zeo's divergence above.
      #
      # Rounding at a positive digit count by scaling with a power of ten reads the
      # scaled product's own representation error as part of the value: 64.781995 *
      # 1e5 is 6478199.4999999991, so the digit that should round up rounds down and
      # the answer comes out a decimal short. Each form compensates the way CRuby
      # compensates, and the compensations differ per form on purpose.
      vals = [44.781995, -44.781995, 64.781995, -64.781995, 2.675, -2.675, 1.005,
              0.5, 1.5, 2.5, -1.5, 65.1848, 32.669, -85320.29, 66471.846,
              123456789.987654321, 0.1, 1e-8, -1e-8]
      vals.each do |v|
        p [v.round(5), v.round(2), v.floor(3), v.ceil(3), v.truncate(3),
           v.round(3, half: :even), v.round(3, half: :down), v.round(3, half: :up)]
      end

      # digit counts at and below zero answer an Integer, unchanged by any of this
      p [1234.5678.round(0), 1234.5678.round(-2), (-1234.5678).round(-2),
         1234.5678.floor(-2), 1234.5678.ceil(-2), 1234.5678.truncate(-2)]

      # a digit count only known at run time takes the same route
      n = 5
      p [64.781995.round(n), 64.781995.floor(n), 64.781995.ceil(n), 64.781995.truncate(n)]

      # past the value's reach the value is answered unchanged
      p [1.0e20.round(5), 1.0e-300.round(5), 0.0.round(5), (-0.0).round(5)]
    RUBY

    _(result).must_answer <<~'OUT'
      [44.782, 44.78, 44.781, 44.782, 44.781, 44.782, 44.782, 44.782]
      [-44.782, -44.78, -44.782, -44.781, -44.781, -44.782, -44.782, -44.782]
      [64.782, 64.78, 64.781, 64.782, 64.781, 64.782, 64.782, 64.782]
      [-64.782, -64.78, -64.782, -64.781, -64.781, -64.782, -64.782, -64.782]
      [2.675, 2.68, 2.675, 2.675, 2.675, 2.675, 2.675, 2.675]
      [-2.675, -2.68, -2.675, -2.675, -2.675, -2.675, -2.675, -2.675]
      [1.005, 1.01, 1.005, 1.005, 1.005, 1.005, 1.005, 1.005]
      [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
      [1.5, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5]
      [2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5]
      [-1.5, -1.5, -1.5, -1.5, -1.5, -1.5, -1.5, -1.5]
      [65.1848, 65.18, 65.184, 65.185, 65.184, 65.185, 65.185, 65.185]
      [32.669, 32.67, 32.669, 32.669, 32.669, 32.669, 32.669, 32.669]
      [-85320.29, -85320.29, -85320.29, -85320.29, -85320.29, -85320.29, -85320.29, -85320.29]
      [66471.846, 66471.85, 66471.846, 66471.847, 66471.846, 66471.846, 66471.846, 66471.846]
      [123456789.98765, 123456789.99, 123456789.987, 123456789.988, 123456789.987, 123456789.988, 123456789.988, 123456789.988]
      [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]
      [0.0, 0.0, 0.0, 0.001, 0.0, 0.0, 0.0, 0.0]
      [0.0, 0.0, -0.001, 0.0, 0.0, 0.0, 0.0, 0.0]
      [1235, 1200, -1200, 1200, 1300, 1200]
      [64.782, 64.78199, 64.782, 64.78199]
      [1.0e+20, 0.0, 0.0, -0.0]
    OUT
  end

  it "float round ndigits return type" do
    result = ze0(<<~'RUBY')
      # Float#ceil/floor/round/truncate return type is value-based on a
      # literal ndigits, matching CRuby: Integer when ndigits <= 0 (or
      # absent), Float when > 0. (A non-literal ndigits stays Float.) Values
      # stay numerically correct. See docs/float-rounding.md.

      # no-arg -> Integer
      puts 1.9.ceil.class
      puts 1.9.floor.class
      puts 1.5.round.class
      puts 1.9.truncate.class

      # any ndigits arg -> Float
      puts 1.9.ceil(0).class
      puts 1.9.ceil(-1).class
      puts 1.111.ceil(1).class
      puts 1.9.round(0).class
      puts 1.9.round(-1).class
      puts 1.234.round(2).class
      puts 1.9.truncate(-1).class

      # numerically-correct values
      puts 1.9.ceil
      puts 1.234.round(2)
      puts 1.999.floor(1)
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      Integer
      Integer
      Integer
      Integer
      Integer
      Float
      Integer
      Integer
      Float
      Integer
      2
      1.23
      1.9
    OUT
  end

  it "float round truncate ndigits" do
    result = ze0(<<~'RUBY')
      # Float#round/#truncate/#floor/#ceil with a runtime ndigits argument choose the
      # class the way CRuby does: Integer when ndigits <= 0, Float when ndigits > 0.
      def rnd(x, n); x.round(n); end
      def trc(x, n); x.truncate(n); end
      def flr(x, n); x.floor(n); end
      p rnd(2.5, 0).class
      p rnd(1234.5678, -2)
      p rnd(3.14159, 2)
      p rnd(3.14159, 2).class
      p trc(3.14159, 0)
      p trc(1234.5, -2)
      p trc(9.87, 1)
      p flr(37.4, -1)
      # Extreme ndigits: the 10**n scale factor overflows to Inf; the result must stay
      # CRuby-faithful (value unchanged for large n > 0, 0 for large n <= 0) not NaN.
      p rnd(1.23, 400)
      p rnd(1.23, -400)
      p trc(2.5, 1000)
      p flr(9.9, -500)
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      1200
      3.14
      Float
      3
      1200
      9.8
      30
      1.23
      0
      2.5
      0
    OUT
  end

  it "gc root elided array slot" do
    result = ze0(<<~'RUBY')
      # A poly local proven to hold only a poly array or nil does not need a GC root:
      # its index read takes the runtime's inline array arm, which neither allocates
      # nor re-enters Ruby, so the element stays reachable from the container it was
      # read out of. Codegen drops the root for that local, which is what lets the
      # C compiler keep it in a register. The shape below is optcarrot's sprite map:
      # a nil-filled table whose entries are handed out of a preallocated buffer.
      class Sprites
        def initialize(n)
          @map = [nil] * n
          @buf = (0...n).map { [false, false, 0] }
          @n = n
        end

        def clear
          @n.times { |i| @map[i] = nil }
        end

        def place(i, behind, zero, colour)
          s = @map[i] = @buf[i]
          s[0] = behind
          s[1] = zero
          s[2] = colour
          s
        end

        # the read whose root the elision targets: `s` is nil or one of @buf's rows
        def pixel(i, base)
          out = base
          s = @map[i]
          if s
            out = s[2] if base % 4 == 0
            out = s[2] unless s[0]
            out = -out if s[1]
          end
          out
        end
      end

      sp = Sprites.new(8)
      p sp.pixel(0, 4)
      sp.place(0, false, false, 9)
      sp.place(3, true, false, 7)
      sp.place(5, false, true, 6)
      p sp.pixel(0, 4)
      p sp.pixel(3, 4)
      p sp.pixel(5, 4)
      p sp.pixel(1, 4)
      p sp.pixel(0, 5)

      # the same reads with a collection forced between them: an elided root must not
      # have been the only thing keeping the row alive
      GC.start
      p sp.pixel(0, 4)
      junk = []
      200.times { |k| junk << "pressure #{k}" * 4 }
      GC.start
      p sp.pixel(3, 4)
      p sp.pixel(5, 4)
      p junk.length

      sp.clear
      p sp.pixel(0, 4)
      sp.place(2, false, false, 3)
      GC.start
      p sp.pixel(2, 4)

      # The destructuring shape, where the value lives in a temp rather than a named
      # local: a pair read out of a frozen lookup table and split across two slots.
      # The temp's proof has to come out of the container ivar, which is filled from
      # a hash whose values are array literals.
      class Lut
        def initialize(n)
          entries = {}
          @lut = (0...n).map { |i|
            entries[i] ||= [i * 2, i * 3]
            entries[i]
          }.freeze
          @a = 0
          @b = 0
        end

        def load(i)
          @a, @b = @lut[i]
          @a + @b
        end
      end

      lut = Lut.new(6)
      p lut.load(0)
      p lut.load(4)
      GC.start
      p lut.load(4)
      noise = []
      150.times { |k| noise << [k, "s#{k}"] }
      GC.start
      p lut.load(5)
      p noise.length
    RUBY

    _(result).must_answer <<~'OUT'
      4
      9
      7
      -6
      4
      9
      9
      7
      -6
      200
      4
      3
      0
      20
      20
      25
      150
    OUT
  end

  it "hash dig applies the hashs own default" do
    result = ze0(<<~'RUBY')
      p Hash.new(0).dig(:x)
      p Hash.new { |h, k| "blk#{k}" }.dig(:x)

      h = Hash.new { |hh, k| hh[k] = Hash.new(9) }
      p h.dig(:a, :b)

      p Hash.new({ z: 3 }).dig(:x, :z)
      p({ a: { b: 1 } }.dig(:a, :b))
      p({ a: 1 }.dig(:b))
      p [1, 2].dig(5)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      "blkx"
      9
      3
      1
      nil
      nil
    OUT
  end

  it "int array bracket assign expr" do
    result = ze0(<<~'RUBY')
      # `arr[i] = v` in *expression* position on int_array. The stmt-
      # form is handled by `compile_bracket_assign`; in rvalue chains
      # like `outer = arr[i] = rhs`, the call lands in the expression
      # dispatcher and was previously unresolved (warning + literal 0).
      #
      # Surfaced via optcarrot PPU's `@io_latch = @sp_ram[@regs_oam] = io_latch_mask(data)`
      # shape — the `sp_ram[idx] = mask` write is also the rvalue
      # assigned to `@io_latch`.

      a = [10, 20, 30, 40, 50]

      # Chained assignment: `b` should pick up the rhs (Ruby []= returns rhs).
      b = a[2] = 999

      puts a[0]
      puts a[1]
      puts a[2]   # mutated
      puts a[3]
      puts a[4]
      puts b      # 999

      # Index/value side-effect ordering: each subexpression evaluated once.
      i = 0
      def bump_i_to_3
        3
      end

      c = a[bump_i_to_3] = 7777
      puts a[3]
      puts c
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      999
      40
      50
      999
      7777
      7777
    OUT
  end

  it "int ceil floor round truncate ndigits" do
    result = ze0(<<~'RUBY')
      # Integer#ceil/floor/round/truncate with ndigits argument.
      # Without ndigits these return self; with negative ndigits they
      # round to the nearest 10^(-ndigits). Previously spinel silently
      # emitted 0 for any call with an argument.

      p 1234.ceil(-2)       # 1300
      p 1234.floor(-2)      # 1200
      p 1234.round(-2)      # 1200
      p 1234.truncate(-2)   # 1200
      p -1234.ceil(-2)      # -1200
      p -1234.floor(-2)     # -1300
      p -1234.truncate(-2)  # -1200
      p 1255.ceil(-2)       # 1300
      p 1255.floor(-2)      # 1200
      p 5.round(-1)         # 10
      p 1234.ceil(0)        # 1234 (positive ndigits: no-op)
      p 1234.round(2)       # 1234
    RUBY

    _(result).must_answer <<~'OUT'
      1300
      1200
      1200
      1200
      -1200
      -1300
      -1200
      1300
      1200
      10
      1234
      1234
    OUT
  end

  it "int keyed hash lookup as array" do
    result = ze0(<<~'RUBY')
      # A Hash literal whose keys are the consecutive non-negative
      # integers 0..N-1 lowers to an internal Array. The runtime has no
      # `int_<X>_hash` slot, so a literal like
      #
      #   {0 => [...], 1 => [...]}
      #
      # previously fell through to the str_int_hash default and the
      # `[]` lookup miscompiled (warning: cannot resolve call to
      # 'length' on int — emitting 0 — followed by a runtime segfault
      # when the lookup chain dereferences the literal `0` as a pointer).
      #
      # Detection is AST-shape-only (IntegerNode keys with literal values
      # 0,1,...N-1 in source order). Any deviation (gap key, duplicate
      # key, non-integer key, splat) opts back into the regular
      # str_int_hash codegen, so existing hash literals are unchanged.

      TBL = {0 => [3, 7, 2, 6], 1 => [4, 0, 5, 1]}
      puts TBL[0].length      # 4
      puts TBL[1][2]          # 5
    RUBY

    _(result).must_answer <<~'OUT'
      4
      5
    OUT
  end

  it "integer digits accepts a bignum base" do
    result = ze0(<<~'RUBY')
      # A bignum base is valid (the value simply fits in one digit when it is
      # smaller than the base); only radix < 2 is an ArgumentError.

      b = 2 ** 70
      p 255.digits(b)
      p 255.digits(b).class
    RUBY

    _(result).must_answer <<~'OUT'
      [255]
      Array
    OUT
  end

  it "interp array container" do
    result = ze0(<<~'RUBY')
      # String interpolation of typed-array containers.
      #
      # `93d04586` fixed Symbol interpolation (`"#{:foo}"` -> `"foo"`).
      # This extends the same idea to typed array containers: `#{arr}`
      # previously fell through the default int path and printed the
      # pointer as a long long (e.g. "4318536016") instead of CRuby's
      # `Array#to_s` shape.
      #
      # Each Array variant has an existing `sp_*Array_inspect` runtime
      # helper that emits the bracketed form `[elem, elem, ...]` byte-
      # identical to CRuby; we just route to it from compile_interpolated.

      # int_array
      ints = [1, 2, 3]
      puts "ints: #{ints}"

      # str_array
      strs = ["a", "b", "c"]
      puts "strs: #{strs}"

      # sym_array
      syms = [:x, :y, :z]
      puts "syms: #{syms}"

      # float_array
      floats = [1.5, 2.5, 3.5]
      puts "floats: #{floats}"

      # poly_array (heterogeneous)
      mix = [1, "two", :three, nil]
      puts "mix: #{mix}"

      # Empty arrays
      puts "empty ints: #{[]}"

      # Nested arrays
      puts "nested: #{[[1, 2], [3, 4]]}"

      # nil interpolation (CRuby: empty string, not "0")
      n = nil
      puts "n: '#{n}'"
    RUBY

    _(result).must_answer <<~'OUT'
      ints: [1, 2, 3]
      strs: ["a", "b", "c"]
      syms: [:x, :y, :z]
      floats: [1.5, 2.5, 3.5]
      mix: [1, "two", :three, nil]
      empty ints: []
      nested: [[1, 2], [3, 4]]
      n: ''
    OUT
  end

  it "ivar array filled from outside" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A Syn holds its source Neu and that Neu's `syns_out` holds the Syn back.
      # At exit: cycle leak: 10 objects (Array x4, Syn x4, Neu x2)
      class Syn
        attr_accessor :weight, :src
        def initialize(src); @src = src; @weight = 0.5; end
      end
      class Neu
        attr_accessor :syns_in, :syns_out, :output
        def initialize; @syns_in = []; @syns_out = []; @output = 1.0; end
      end
      class Net
        def initialize(n)
          @a = (1..n).map { Neu.new }
          @b = (1..n).map { Neu.new }
          @a.each do |src|
            @b.each do |dst|
              s = Syn.new(src)
              src.syns_out << s
              dst.syns_in << s
            end
          end
        end
        def upd(rate)
          @b.each do |nu|
            nu.syns_in.each do |s|
              s.weight += rate * 0.1 * s.src.output
            end
          end
        end
        def show
          p @b[0].syns_in.length
          p @b[0].syns_in[0].weight.round(3)
          p @a[0].syns_out[0].src.output
        end
      end
      n = Net.new(2)
      n.upd(1.0)
      n.show

      class Bag
        attr_reader :items
        def initialize; @items = []; end
      end
      b = Bag.new
      b.items << "x"
      b.items << "y"
      p b.items.length
      p b.items[0].upcase
      p b.items.join("-")
    RUBY

    _(result).must_answer <<~'OUT'
      2
      0.6
      1.0
      2
      "X"
      "x-y"
    OUT
  end

  it "ivar array pushed through boxed param" do
    result = ze0(<<~'RUBY')
      # `@rows = []` carries no element evidence, so it takes the empty-array
      # default (an int array). A helper that pushes objects into it through a
      # parameter shares that storage, and the ivar has to widen with it -- the
      # parameter arrives BOXED here, so the container the callee pushes into is
      # invisible at the call, and nothing widened the ivar. The push then failed at
      # run time with "no implicit conversion of Scenario into Integer".
      #
      # The typed-parameter form of this is #3154; this is the same hazard with the
      # container hidden behind the box. Found while testing #4130.
      Scenario = Struct.new(:key)

      class Sheet
        def initialize
          @rows = []
        end

        def fill
          row(@rows, "a")
          row(@rows, "b")
          @rows
        end

        def row(rows, said)
          rows.push(Scenario.new(said))
        end

        def rows = @rows
      end

      s = Sheet.new
      p s.fill.length
      p s.rows.map { |r| r.key }
      p s.rows.first.key

      # A reader that hands the ivar out sees the widened array too.
      p Sheet.new.fill.map { |r| r.key }

      # An ivar that really does hold ints keeps its typed representation: the
      # widening is driven by what the helper pushes, not by being passed at all.
      class Counter
        def initialize
          @ns = []
        end

        def fill
          add(@ns, 1)
          add(@ns, 2)
          @ns
        end

        def add(ns, n)
          ns.push(n)
        end
      end

      p Counter.new.fill
      p Counter.new.fill.sum
    RUBY

    _(result).must_answer <<~'OUT'
      2
      ["a", "b"]
      "a"
      ["a", "b"]
      [1, 2]
      3
    OUT
  end

  it "kernel array coercion" do
    result = ze0(<<~'RUBY')
      # Kernel#Array(x): nil becomes [], an array passes through (preserving its
      # element type), and any other value is wrapped in a one-element array. The
      # wrapped cases route through the runtime coercion; an argument statically
      # known to be an array is returned directly.
      def ints(a); a; end

      p Array(nil)
      p Array([1, 2, 3])
      p Array(1)
      p Array("x")
      p Array(:sym)
      p Array(3.5)
      p Array(ints([4, 5, 6]))

      # a poly argument is dispatched at run time (nil / array / scalar)
      def coerce(x); Array(x); end
      p coerce(nil)
      p coerce(7)
      p coerce([8, 9])
      p coerce("z")

      # an existing array is returned by identity, not copied: mutating the result of
      # Array(arr) is visible through the original (a poly array reached at run time).
      pa = [1, "a"]
      r = coerce(pa)
      r.push("z")
      p pa.length

      # a scalar argument yields a precisely typed array, so a typed-array operation
      # applies directly to the result.
      p Array(5).sum
      p Array(2.5).first
      p Array("hi").first.upcase
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [1, 2, 3]
      [1]
      ["x"]
      [:sym]
      [3.5]
      [4, 5, 6]
      []
      [7]
      [8, 9]
      ["z"]
      3
      5
      2.5
      "HI"
    OUT
  end

  it "keyword hash in an array literal is an element" do
    result = ze0(<<~'RUBY')
      # Keywords at the end of an array literal make one Hash element. When
      # they are only `**` splats and come out empty, no element is added.
      p [1, a: 2]
      p [a: 1, b: 2]
      h = {}
      p [**h], [1, **h]
      g = {x: 1}
      p [**g], [1, **g, **h]
      p [1, **h, c: 3]

    RUBY

    _(result).must_answer <<~'OUT'
      [1, {a: 2}]
      [{a: 1, b: 2}]
      []
      [1]
      [{x: 1}]
      [1, {x: 1}]
      [1, {c: 3}]
    OUT
  end

  it "mapped array mutable elements" do
    result = ze0(<<~'RUBY')
      # `["a"].map { |s| s.dup }` fills the array with fresh mutable strings exactly
      # as `["a".dup]` does, and the shared-mutable machinery has to read the two
      # shapes the same way. Only the literal was: the store analysis knew array and
      # hash literals, push / << / []=, and not the array a collecting iterator
      # builds. So an element of a mapped array kept the plain value representation,
      # and mutating it was refused or silently dropped (#4037):
      #
      #   overlay = ["abc"].map(&:dup)
      #   overlay[0][1] = "*"      # undefined method '[]=' for an instance of String
      #   overlay[0] << "d"        # no error, mutation dropped
      overlay = ["abc"].map(&:dup)
      overlay[0][1] = "*"
      p overlay

      a = ["abc"].map { |s| s.dup }
      a[0] << "d"
      p a

      b = ["abc"].map(&:dup)
      s = b[0]
      s[1] = "*"
      p b
      p b[0].respond_to?(:[]=)
      p b[0].frozen?

      c = ["abc"].map(&:dup)
      c.each { |e| e << "!" }
      p c

      d = %w[a b].map(&:dup)
      d[1] << "z"
      p d

      # a transforming map answers a fresh string too
      e = ["abc"].map { |s| s.upcase }
      e[0] << "d"
      p e

      # and the literal shapes that already worked
      g = ["abc".dup]
      g[0] << "d"
      p g
      h = [String.new("abc")]
      h[0][1] = "*"
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      ["a*c"]
      ["abcd"]
      ["a*c"]
      true
      false
      ["abc!"]
      ["a", "bz"]
      ["ABCd"]
      ["abcd"]
      ["a*c"]
    OUT
  end

  it "minmax by array key" do
    result = ze0(<<~'RUBY')
      p [1, 2].min_by { |x| [x] }
      p [1, 2].max_by { |x| [x] }
      p [[3, 1], [1, 2]].min_by { |a| a }
      p [[3, 1], [1, 2]].max_by { |a| a }
      p ["b", "aa"].min_by { |s| [s.length, s] }
      p [1, 2, 3].min_by { |x| [x % 2, x] }
      p [1, 2].min_by { |x| x }
      p ["b", "a"].min_by { |s| s }
      require "set"
      p Set.new([1, 2]).min_by { |x| [x] }
      p({ a: 1, b: 2 }.min_by { |k, v| [v] })
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      [1, 2]
      [3, 1]
      "b"
      2
      1
      "a"
      1
      [:a, 1]
    OUT
  end

  it "module const array widen" do
    _(ze0(<<~'RUBY')).must_answer "2\n"
      # Issue #333: a module-level array constant initialized as an empty
      # literal (`LOG = []`) was typed as `sp_IntArray *`, regardless of
      # how it was used. A later `LOG << some_hash` then emitted
      # `sp_IntArray_push(cst_M_LOG, hash_ptr)`, mistyping the pointer as
      # mrb_int.
      #
      # Fix: extend the existing `refine_module_ivar_types` pass (which
      # already handled `@slots = {}` shape per #303) to also walk
      # `ConstantWriteNode` declarations like `LOG = []`. The companion
      # scanner `scan_module_const_writes` walks the module's class
      # methods for `LOG << v` / `LOG[k] = v` / `LOG.push(v)` shapes
      # rooted at a `ConstantReadNode` receiver. Body locals (`entry =
      # {...}; LOG << entry`) are also declared in the temporary scope so
      # `infer_type` resolves the pushed value's actual hash/obj type
      # instead of the int default.
      #
      # Surfaced via Roundhouse's `module Broadcasts; LOG = []; ... LOG <<
      # entry` pattern.

      module Broadcasts
        module_function
        LOG = []

        def record(action)
          entry = { action: action, target: "x" }
          LOG << entry
        end

        def size
          LOG.length
        end
      end

      Broadcasts.record(:append)
      Broadcasts.record(:replace)
      puts Broadcasts.size           # 2
    RUBY
  end

  it "multi write ivar const from array rhs" do
    result = ze0(<<~'RUBY')
      # `compile_multi_write`'s int_array-returning RHS branch (RHS is a
      # non-literal expression that evaluates to an array, e.g.
      # `.map { ... }`, a method call) only emitted assignments for
      # `LocalVariableTargetNode` targets — `InstanceVariableTargetNode`
      # and `ConstantTargetNode` targets were silently dropped. The C
      # code compiled fine, but the ivars / constants stayed at their
      # default values.
      #
      # Repro: `@a, @b = [10, 20].map { |x| x + 1 }` where the targets
      # are ivars. Master emitted neither write, so c.a / c.b returned 0.
      #
      # (Constant-target coverage requires the multi-write-to-constants
      # parser support, which lives in a sibling PR; the InstanceVariable
      # fix here is independent and lands first.)

      # (1) ivar targets, RHS is .map
      class C1
        def initialize
          @a, @b = [10, 20].map { |x| x + 1 }
        end
        attr_reader :a, :b
      end
      c = C1.new
      puts c.a              # 11
      puts c.b              # 21

      # (2) mixed: local + ivar from one int_array RHS.
      class C2
        def initialize
          local, @i = [1, 2].map { |x| x * 10 }
          @captured_local = local
        end
        attr_reader :i, :captured_local
      end
      c2 = C2.new
      puts c2.captured_local  # 10
      puts c2.i               # 20

      # (3) ivar targets where the RHS is a top-level method returning
      # a fresh array. The intervening method-boundary forces the
      # `sp_IntArray *` rhs path (RHS is not a literal ArrayNode).
      def make_pair
        [7, 8]
      end
      class C3
        attr_reader :x, :y
        def initialize
          @x, @y = make_pair
        end
      end
      c3 = C3.new
      puts c3.x   # 7
      puts c3.y   # 8
    RUBY

    _(result).must_answer <<~'OUT'
      11
      21
      10
      20
      7
      8
    OUT
  end

  it "non overridden inherited initialize flattens ivars onto the subclass struct" do
    _(ze0(<<~'RUBY')).must_answer "40\n"
      class Parent
        def initialize(x)
          @x = x
        end
      end
      class Child < Parent
        def show
          @x * 10
        end
      end
      puts Child.new(4).show
    RUBY
  end

  it "obj array param accumulator" do
    result = ze0(<<~'RUBY')
      # An accumulator array mutated through an INSTANCE-method parameter and read
      # back by element must round-trip its objects intact. The object-array
      # narrowing pass built interprocedural edges only for free functions, so an
      # instance method's param narrowed to an unboxed sp_PtrArray while every
      # caller's local stayed a boxed poly array -- push wrote raw pointers where
      # boxed values were read, and an ivar getter through the broken box returned
      # 0 (and an :float_array FFI marshal NULL: the toy 72-tensor no-op init).
      class Mat2
        attr_accessor :nrows, :flat
        def initialize
          @nrows = 4
          @flat = [1.0, 2.0, 3.0, 4.0]
        end
      end

      class Eng
        def alloc_w(inits, m)
          inits.push(m)
          m
        end

        def up(m)
          puts "#{m.nrows} #{m.flat.inspect}"
        end

        def go
          inits = []
          alloc_w(inits, Mat2.new)
          alloc_w(inits, Mat2.new)
          gk = 0
          while gk < 2
            up(inits[gk])
            gk = gk + 1
          end
          inits.length
        end
      end

      e = Eng.new
      p e.go
      e.up(Mat2.new)   # a concrete local through the same method keeps working
    RUBY

    _(result).must_answer <<~'OUT'
      4 [1.0, 2.0, 3.0, 4.0]
      4 [1.0, 2.0, 3.0, 4.0]
      2
      4 [1.0, 2.0, 3.0, 4.0]
    OUT
  end

  it "open class array builtin" do
    _(ze0(<<~'RUBY')).must_answer "Array\n"
      # Built-in class reopens should not be collected as user classes.
      # Array uses the boxed open-class receiver path rather than emitting
      # a fake sp_Array struct.

      class Array
        def marker
          self.class.name
        end
      end

      puts [1, 2].marker
    RUBY
  end

  it "recursive array flatten overflows" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A self-containing array, which is what `flatten` is supposed to refuse.
      # At exit: cycle leak: 1 objects (Array x1)
      # A self-referential array kills the process with a native stack overflow where
      # ruby raises `ArgumentError: tried to flatten recursive array`.
      #
      # A `flatten` that recurses per nested Array with no record of what it has
      # already entered runs the native stack out on `a << a`. Ruby tracks the
      # arrays currently being flattened and raises on re-entry (`rb_ary_flatten`,
      # using its recursion guard).
      #
      # `inspect` and `==` already handle the same cycle -- both answer correctly
      # below -- so the guard exists elsewhere in the runtime and `flatten` simply
      # does not use it. An abort is the worst failure mode available: nothing can
      # rescue it, and the exit status is a signal rather than 1.

      a = [1]
      a << a
      p a.inspect
      p a == a.dup

      begin
        a.flatten
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end

      # The depth-limited form stops before re-entry and must NOT raise.
      p a.flatten(1).size
    RUBY

    _(result).must_answer <<~'OUT'
      "[1, [...]]"
      true
      ArgumentError: tried to flatten recursive array
      3
    OUT
  end

  it "recursive array join aborts" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Two rings: `a << a`, and `b << [2, b]` whose inner array is the third array. The nested one is the row that proves the guard is a stack.
      # At exit: cycle leak: 3 objects (Array x3)
      # `Array#join` on a self-referential array raises ArgumentError
      # ("recursive array join"). It used to abort the process: the receiver's
      # lock was still held when the nested join re-entered it, which is a
      # re-entrant container access, and in a release build that aliases rather
      # than asserting.
      #
      # The guard is only half the fix. Hoisting the payload clone OUT of the
      # recursive call's argument list is the other half, and the SOUNDNESS half
      # -- the caller-side rule the whole bug class comes down to is: never hold
      # a `.lock()` inside a call-argument expression that also contains the
      # recursive call.

      a = [1]
      a << a
      begin
        a.join(",")
      rescue ArgumentError => e
        puts e.message
      end

      # Nested one level deeper, so the guard has to be a STACK and not a flag
      # on the receiver.
      b = [1]
      b << [2, b]
      begin
        b.join(",")
      rescue ArgumentError => e
        puts e.message
      end

      # A sibling is not a cycle: the same array twice is legal, and stays legal.
      # This is what a monotonic visited-set would break.
      c = [1, 2]
      p [c, c].join(",")
      p [c, [c, c]].join("-")

      # Every ordinary join still works, including the nested and separatorless
      # forms.
      p [1, [2, [3, 4]], 5].join("-")
      p [1, [2]].join
      p [].join(",")
      p [[], [[]]].join(",")
    RUBY

    _(result).must_answer <<~'OUT'
      recursive array join
      recursive array join
      "1,2,1,2"
      "1-2-1-2-1-2"
      "1-2-3-4-5"
      "12"
      ""
      ","
    OUT
  end

  it "rest and post params bind a real array" do
    result = ze0(<<~'RUBY')
      class Collector
        def count(*nums)
          nums.length
        end
        def between(a, *mid, z)
          "#{a}-#{mid.length}-#{z}"
        end
      end
      c = Collector.new
      puts c.count(1, 2, 3)
      puts c.count
      puts c.between(1, 2, 3, 9)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      0
      1-2-9
    OUT
  end

  it "splatting a non array follows rubys to a rules" do
    result = ze0(<<~'RUBY')
      # Splatting a non-Array is ordinary Ruby, not an error -- it used to
      # PANIC ("expected an Array to splat"), taking down `a, b = *1`.
      # `[*"str"]` is the case worth pinning: it looks like it should split
      # into characters and doesn't, because String has no `to_a`. Probing
      # respond_to? rather than special-casing types gets that right, and
      # gets a user class with its own to_a right too.

      p [*1]
      p [*nil]
      p [*[1, 2]]
      p [*{a: 1}]
      p [*"str"]
      p [*(1..3)]
      class HasToA; def to_a; [7, 8]; end; end
      p [*HasToA.new]
      class NoToA; end
      p([*NoToA.new].size)
      p [*:sym]
      a, b = *1
      p [a, b]
      c, d = *nil
      p [c, d]
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      []
      [1, 2]
      [[:a, 1]]
      ["str"]
      [1, 2, 3]
      [7, 8]
      1
      [:sym]
      [1, nil]
      [nil, nil]
    OUT
  end

  it "struct dig missing key" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Struct#dig with an unknown member raises NameError where ruby answers nil.
      #
      S = Struct.new(:a, :b)
      s = S.new(1, 2)
      p s.dig(:zz)
      p s.dig(5)
      p s.dig("a")
      p s.dig(:a)
      k = :a
      p s.dig(k)
      i = 1
      s[i] = 9
      p s.b
      v = (s[i] = 7)
      p v
      k2 = :a
      w = (s[k2] = 8)
      p w
      p s.values_at
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      1
      1
      1
      9
      7
      8
      []
    OUT
  end

  it "struct dig multi key" do
    result = ze0(<<~'RUBY')
      Node001 = Struct.new(:val, :kids)
      t001 = Node001.new(1, [Node001.new(2, [])])
      p t001.dig(1, 0, 0)
      p t001.dig(1, 0)
      p t001.dig(1, 0).val
      p t001.kids[0].dig(0)
      p t001.dig(:kids, 0, :val)
      p t001.dig(0)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      #<struct Node001 val=2, kids=[]>
      2
      2
      2
      1
    OUT
  end

  it "struct dig paths" do
    result = ze0(<<~'RUBY')
      # dig through and into a Struct.
      Leaf = Struct.new(:v)
      Box = Struct.new(:label, :items)

      # a Struct member holding an array: the member's array kind had no C name for
      # a poly array, and the NULL went straight into the emitted symbol
      b = Box.new("x", [Leaf.new(2)])
      p b.dig(1, 0)
      p b.dig(:items, 0)
      p b.dig(0)
      p b.dig(:label)

      # a Struct read out of a container is diggable, by member name or by offset;
      # it was refused, and a String or Symbol key reached the offset slot as a
      # pointer
      a = [Leaf.new(2)]
      p a.dig(0)
      p a.dig(0, "v")
      p a.dig(0, :v)
      p a.dig(0, 0)
      p a.dig(1, :v)

      h = { k: Leaf.new(5) }
      p h.dig(:k, :v)

      # nested structs still resolve at compile time
      Inner = Struct.new(:c)
      Outer = Struct.new(:b)
      p Outer.new(Inner.new(7)).dig(:b, :c)

      # a scalar intermediate is still a TypeError
      p(([[1]].dig(0, 0, 0) rescue $!.class))
    RUBY

    _(result).must_answer <<~'OUT'
      #<struct Leaf v=2>
      #<struct Leaf v=2>
      "x"
      "x"
      #<struct Leaf v=2>
      2
      2
      2
      nil
      5
      7
      TypeError
    OUT
  end

  it "struct empty array member" do
    result = ze0(<<~'RUBY')
      # an empty array literal as a Data/Struct member takes the member's type
      P = Data.define(:name, :deps)
      a = P.new(name: "x", deps: ["d1"])
      b = P.new(name: "y", deps: [])
      p [a.deps, b.deps]
      S1 = Struct.new(:name, :deps)
      c1 = S1.new("x", [:s1])
      d1 = S1.new("y", [])
      p [c1.deps, d1.deps]
      S2 = Struct.new(:v)
      p [S2.new([1.5]).v, S2.new([]).v]
      S3 = Struct.new(:v)
      p [S3.new([[1]]).v, S3.new([]).v]
      S4 = Struct.new(:v)
      p [S4.new([1]).v, S4.new([]).v]
    RUBY

    _(result).must_answer <<~'OUT'
      [["d1"], []]
      [[:s1], []]
      [[1.5], []]
      [[[1]], []]
      [[1], []]
    OUT
  end

  it "subclass sees only the calls ruby makes" do
    result = ze0(<<~'RUBY')
      # Which of Array's own methods its methods call on a subclass: every
      # method Array defines is wrapped to log a call made from inside another,
      # and each is then called once on a fresh receiver. CRuby calls one by
      # dispatch only where it means to, and ze0's core, written in Ruby, has
      # to call no more and no fewer. Written by `rake gen:dispatch`.

      class Probe < Array
        CALLING = []
        LOG = []
        [:&, :*, :+, :-, :<<, :<=>, :==, :[], :[]=, :all?, :any?, :append, :assoc, :at, :bsearch, :bsearch_index, :chain, :chunk, :chunk_while, :clear, :collect, :collect!, :collect_concat, :combination, :compact, :compact!, :concat, :count, :cycle, :deconstruct, :delete, :delete_at, :delete_if, :detect, :difference, :dig, :drop, :drop_while, :each, :each_cons, :each_entry, :each_index, :each_slice, :each_with_index, :each_with_object, :empty?, :entries, :eql?, :fetch, :fetch_values, :fill, :filter, :filter!, :filter_map, :find, :find_all, :find_index, :first, :flat_map, :flatten, :flatten!, :freeze, :grep, :grep_v, :group_by, :hash, :include?, :index, :initialize_copy, :inject, :insert, :inspect, :intersect?, :intersection, :join, :keep_if, :last, :lazy, :length, :map, :map!, :max, :max_by, :member?, :min, :min_by, :minmax, :minmax_by, :none?, :one?, :pack, :partition, :permutation, :pop, :prepend, :product, :push, :rassoc, :reduce, :reject, :reject!, :repeated_combination, :repeated_permutation, :replace, :reverse, :reverse!, :reverse_each, :rfind, :rindex, :rotate, :rotate!, :sample, :select, :select!, :shift, :shuffle, :shuffle!, :size, :slice, :slice!, :slice_after, :slice_before, :slice_when, :sort, :sort!, :sort_by, :sort_by!, :sum, :take, :take_while, :tally, :to_a, :to_ary, :to_h, :to_s, :to_set, :transpose, :union, :uniq, :uniq!, :unshift, :values_at, :zip, :|].each do |m|
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
        r = Probe.new([3, 1, 2])
        Probe::LOG.clear
        begin
          yield r
        rescue StandardError => e
          Probe::LOG << "raised #{e.class}"
        end
        puts "#{name}: #{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
      end

      call("&") { |r| r.__send__(:&, [1, 2]) { |*x| x.first } }
      call("*") { |r| r.__send__(:*, 1) { |*x| x.first } }
      call("+") { |r| r.__send__(:+, [1, 2]) { |*x| x.first } }
      call("-") { |r| r.__send__(:-, [1, 2]) { |*x| x.first } }
      call("<<") { |r| r.__send__(:<<, 1) { |*x| x.first } }
      call("<=>") { |r| r.__send__(:<=>, 1) { |*x| x.first } }
      call("==") { |r| r.__send__(:==, 1) { |*x| x.first } }
      call("[]") { |r| r.__send__(:[], 1) { |*x| x.first } }
      call("[]=") { |r| r.__send__(:[]=, 0, 1) { |*x| x.first } }
      call("all?") { |r| r.all?() { |*x| x.first } }
      call("any?") { |r| r.any?() { |*x| x.first } }
      call("append") { |r| r.append() { |*x| x.first } }
      call("assoc") { |r| r.assoc(1) { |*x| x.first } }
      call("at") { |r| r.at(1) { |*x| x.first } }
      call("bsearch") { |r| r.bsearch() { |*x| x.first } }
      call("bsearch_index") { |r| r.bsearch_index() { |*x| x.first } }
      call("chain") { |r| r.chain() { |*x| x.first } }
      call("chunk") { |r| r.chunk() { |*x| x.first } }
      call("chunk_while") { |r| r.chunk_while() { |*x| x.first } }
      call("clear") { |r| r.clear() { |*x| x.first } }
      call("collect") { |r| r.collect() { |*x| x.first } }
      call("collect!") { |r| r.collect!() { |*x| x.first } }
      call("collect_concat") { |r| r.collect_concat() { |*x| x.first } }
      call("combination") { |r| r.combination(1) { |*x| x.first } }
      call("compact") { |r| r.compact() { |*x| x.first } }
      call("compact!") { |r| r.compact!() { |*x| x.first } }
      call("concat") { |r| r.concat() { |*x| x.first } }
      call("count") { |r| r.count() { |*x| x.first } }
      call("deconstruct") { |r| r.deconstruct() { |*x| x.first } }
      call("delete") { |r| r.delete(1) { |*x| x.first } }
      call("delete_at") { |r| r.delete_at(1) { |*x| x.first } }
      call("delete_if") { |r| r.delete_if() { |*x| x.first } }
      call("detect") { |r| r.detect() { |*x| x.first } }
      call("difference") { |r| r.difference() { |*x| x.first } }
      call("dig") { |r| r.dig(1) { |*x| x.first } }
      call("drop") { |r| r.drop(1) { |*x| x.first } }
      call("drop_while") { |r| r.drop_while() { |*x| x.first } }
      call("each") { |r| r.each() { |*x| x.first } }
      call("each_cons") { |r| r.each_cons(1) { |*x| x.first } }
      call("each_entry") { |r| r.each_entry() { |*x| x.first } }
      call("each_index") { |r| r.each_index() { |*x| x.first } }
      call("each_slice") { |r| r.each_slice(1) { |*x| x.first } }
      call("each_with_index") { |r| r.each_with_index() { |*x| x.first } }
      call("each_with_object") { |r| r.each_with_object(1) { |*x| x.first } }
      call("empty?") { |r| r.empty?() { |*x| x.first } }
      call("entries") { |r| r.entries() { |*x| x.first } }
      call("eql?") { |r| r.eql?(1) { |*x| x.first } }
      call("fetch") { |r| r.fetch(1) { |*x| x.first } }
      call("fetch_values") { |r| r.fetch_values() { |*x| x.first } }
      call("fill") { |r| r.fill() { |*x| x.first } }
      call("filter") { |r| r.filter() { |*x| x.first } }
      call("filter!") { |r| r.filter!() { |*x| x.first } }
      call("filter_map") { |r| r.filter_map() { |*x| x.first } }
      call("find") { |r| r.find() { |*x| x.first } }
      call("find_all") { |r| r.find_all() { |*x| x.first } }
      call("find_index") { |r| r.find_index() { |*x| x.first } }
      call("first") { |r| r.first() { |*x| x.first } }
      call("flat_map") { |r| r.flat_map() { |*x| x.first } }
      call("flatten") { |r| r.flatten() { |*x| x.first } }
      call("flatten!") { |r| r.flatten!() { |*x| x.first } }
      call("grep") { |r| r.grep(1) { |*x| x.first } }
      call("grep_v") { |r| r.grep_v(1) { |*x| x.first } }
      call("group_by") { |r| r.group_by() { |*x| x.first } }
      call("hash") { |r| r.hash() { |*x| x.first } }
      call("include?") { |r| r.include?(1) { |*x| x.first } }
      call("index") { |r| r.index() { |*x| x.first } }
      call("initialize_copy") { |r| r.initialize_copy([1, 2]) { |*x| x.first } }
      call("inject") { |r| r.inject() { |*x| x.first } }
      call("insert") { |r| r.insert(1) { |*x| x.first } }
      call("inspect") { |r| r.inspect() { |*x| x.first } }
      call("intersect?") { |r| r.intersect?([1, 2]) { |*x| x.first } }
      call("intersection") { |r| r.intersection() { |*x| x.first } }
      call("join") { |r| r.join() { |*x| x.first } }
      call("keep_if") { |r| r.keep_if() { |*x| x.first } }
      call("last") { |r| r.last() { |*x| x.first } }
      call("lazy") { |r| r.lazy() { |*x| x.first } }
      call("length") { |r| r.length() { |*x| x.first } }
      call("map") { |r| r.map() { |*x| x.first } }
      call("map!") { |r| r.map!() { |*x| x.first } }
      call("max") { |r| r.max() { |*x| x.first } }
      call("max_by") { |r| r.max_by() { |*x| x.first } }
      call("member?") { |r| r.member?(1) { |*x| x.first } }
      call("min") { |r| r.min() { |*x| x.first } }
      call("min_by") { |r| r.min_by() { |*x| x.first } }
      call("minmax") { |r| r.minmax() { |*x| x.first } }
      call("minmax_by") { |r| r.minmax_by() { |*x| x.first } }
      call("none?") { |r| r.none?() { |*x| x.first } }
      call("one?") { |r| r.one?() { |*x| x.first } }
      call("pack") { |r| r.pack("l") { |*x| x.first } }
      call("partition") { |r| r.partition() { |*x| x.first } }
      call("permutation") { |r| r.permutation() { |*x| x.first } }
      call("pop") { |r| r.pop() { |*x| x.first } }
      call("prepend") { |r| r.prepend() { |*x| x.first } }
      call("product") { |r| r.product() { |*x| x.first } }
      call("push") { |r| r.push() { |*x| x.first } }
      call("rassoc") { |r| r.rassoc(1) { |*x| x.first } }
      call("reduce") { |r| r.reduce() { |*x| x.first } }
      call("reject") { |r| r.reject() { |*x| x.first } }
      call("reject!") { |r| r.reject!() { |*x| x.first } }
      call("repeated_combination") { |r| r.repeated_combination(1) { |*x| x.first } }
      call("repeated_permutation") { |r| r.repeated_permutation(1) { |*x| x.first } }
      call("replace") { |r| r.replace([1, 2]) { |*x| x.first } }
      call("reverse") { |r| r.reverse() { |*x| x.first } }
      call("reverse!") { |r| r.reverse!() { |*x| x.first } }
      call("reverse_each") { |r| r.reverse_each() { |*x| x.first } }
      call("rfind") { |r| r.rfind() { |*x| x.first } }
      call("rindex") { |r| r.rindex() { |*x| x.first } }
      call("rotate") { |r| r.rotate() { |*x| x.first } }
      call("rotate!") { |r| r.rotate!() { |*x| x.first } }
      call("sample") { |r| r.sample() { |*x| x.first } }
      call("select") { |r| r.select() { |*x| x.first } }
      call("select!") { |r| r.select!() { |*x| x.first } }
      call("shift") { |r| r.shift() { |*x| x.first } }
      call("shuffle") { |r| r.shuffle() { |*x| x.first } }
      call("shuffle!") { |r| r.shuffle!() { |*x| x.first } }
      call("size") { |r| r.size() { |*x| x.first } }
      call("slice") { |r| r.slice(1) { |*x| x.first } }
      call("slice!") { |r| r.slice!(1) { |*x| x.first } }
      call("slice_after") { |r| r.slice_after() { |*x| x.first } }
      call("slice_before") { |r| r.slice_before() { |*x| x.first } }
      call("slice_when") { |r| r.slice_when() { |*x| x.first } }
      call("sort") { |r| r.sort() { |*x| x.first } }
      call("sort!") { |r| r.sort!() { |*x| x.first } }
      call("sort_by") { |r| r.sort_by() { |*x| x.first } }
      call("sort_by!") { |r| r.sort_by!() { |*x| x.first } }
      call("sum") { |r| r.sum() { |*x| x.first } }
      call("take") { |r| r.take(1) { |*x| x.first } }
      call("take_while") { |r| r.take_while() { |*x| x.first } }
      call("tally") { |r| r.tally() { |*x| x.first } }
      call("to_a") { |r| r.to_a() { |*x| x.first } }
      call("to_ary") { |r| r.to_ary() { |*x| x.first } }
      call("to_s") { |r| r.to_s() { |*x| x.first } }
      call("to_set") { |r| r.to_set() { |*x| x.first } }
      call("union") { |r| r.union() { |*x| x.first } }
      call("uniq") { |r| r.uniq() { |*x| x.first } }
      call("uniq!") { |r| r.uniq!() { |*x| x.first } }
      call("unshift") { |r| r.unshift() { |*x| x.first } }
      call("values_at") { |r| r.values_at() { |*x| x.first } }
      call("zip") { |r| r.zip() { |*x| x.first } }
      call("|") { |r| r.__send__(:|, [1, 2]) { |*x| x.first } }

    RUBY

    _(result).must_answer <<~'OUT'
      collect_concat: collect_concat->each
      each_cons: each_cons->size each_cons->each
      each_entry: each_entry->each
      each_slice: each_slice->size each_slice->each
      each_with_index: each_with_index->each
      each_with_object: each_with_object->each
      entries: entries->each
      filter_map: filter_map->each
      find_all: find_all->each
      flat_map: flat_map->each
      grep: grep->each
      grep_v: grep_v->each
      group_by: group_by->each
      initialize_copy: raised NoMethodError
      inject: inject->each
      max_by: max_by->each
      member?: member?->each
      min_by: min_by->each
      minmax: minmax->each
      minmax_by: minmax_by->each
      partition: partition->each
      reduce: reduce->each
      sort_by: sort_by->each
      sort_by!: sort_by!->sort_by sort_by->each
      tally: tally->each
    OUT
  end

  it "value subclass of array" do
    result = ze0(<<~'RUBY')
      # A user subclass of `Array` (D3) is the native `ValueSubclass` wrapping an
      # array payload: inherited methods (`push`/`<<`/`size`/`each`/`map`) run
      # against it, self-returning mutators re-wrap to the subclass while a NEW
      # collection (`map`) is a plain `Array`, and a custom method sees the elements.

      class Stack < Array
        def peek; last; end
      end
      s = Stack.new
      s.push(1)
      s << 2
      p s
      puts s.size
      puts s.peek
      puts s.class
      puts s.push(3).class
      puts s.map { |x| x * 2 }.inspect
      puts s.map { |x| x }.class
      puts s.is_a?(Array)
      puts Stack.new([9, 8]).size
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      2
      2
      Stack
      Stack
      [2, 4, 6]
      Array
      true
      2
    OUT
  end
end
