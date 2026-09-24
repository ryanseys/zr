# frozen_string_literal: true

require "spec_helper"

describe "Set programs" do
  it "array element set bad index" do
    result = zr(<<~'RUBY')
      a1 = [1, 2]
      p(begin; a1["x"] = 9; rescue TypeError => e; e.message; end)
      p a1

      a2 = [1, 2]
      p(begin; a2[:s] = 9; rescue TypeError => e; e.message; end)
      p a2

      a3 = [1, 2]
      p(begin; a3[nil] = 9; rescue TypeError => e; e.message; end)
      p a3

      a4 = [1, 2]
      p(begin; a4[[0]] = 9; rescue TypeError => e; e.message; end)

      a5 = ["x"]
      p(begin; a5["y"] = "z"; rescue TypeError => e; e.message; end)
      p a5

      a6 = [1, 2]
      i = "x"
      p(begin; a6[i] = 9; rescue TypeError => e; e.message; end)

      a7 = [1, 2]
      a7[0] = 9
      a7[1.5] = 8
      p a7

      b = [1, 2]
      p(begin; b["x"] = 9; rescue TypeError => e; e.message; end)
      b = ["z"]
      p b

      c = [1, 2]
      p(begin; c[:s] = 9; rescue TypeError => e; e.message; end)
      c = ["z"]
      p c

      d = [1, 2]
      p(begin; d[nil] = 9; rescue TypeError => e; e.message; end)
      d = ["z"]
      p d

      f = [1, 2]
      f[1.5] = 7
      f = ["z"]
      p f
    RUBY

    _(result).must_answer <<~'OUT'
      "no implicit conversion of String into Integer"
      [1, 2]
      "no implicit conversion of Symbol into Integer"
      [1, 2]
      "no implicit conversion from nil to integer"
      [1, 2]
      "no implicit conversion of Array into Integer"
      "no implicit conversion of String into Integer"
      ["x"]
      "no implicit conversion of String into Integer"
      [9, 8]
      "no implicit conversion of String into Integer"
      ["z"]
      "no implicit conversion of Symbol into Integer"
      ["z"]
      "no implicit conversion from nil to integer"
      ["z"]
      ["z"]
    OUT
  end

  it "array set ops" do
    result = zr(<<~'RUBY')
      # Named Array set operations: variadic union/intersection/difference and the
      # intersect? predicate. (The |/&/- operators and the single-argument named
      # forms already worked; these add the multi-argument fold and intersect?.)
      # Per-type helpers keep each receiver's concrete element type.
      def ai(x); x; end   # int array
      def as(x); x; end   # string array
      def af(x); x; end   # float array
      def ap(x); x; end   # poly (mixed) array

      # union folds across every argument, keeping first occurrence, de-duped
      p ai([1, 2, 3]).union([2, 3], [3, 4])            # [1, 2, 3, 4]
      p ai([1, 2, 3]).union([3, 4])                    # [1, 2, 3, 4]  (single arg still works)

      # intersection keeps elements present in the receiver and every argument
      p ai([1, 2, 3, 4]).intersection([2, 3, 4], [3, 4, 5])  # [3, 4]

      # difference removes every element found in any argument
      p ai([1, 2, 3, 4]).difference([2], [4])          # [1, 3]
      p ai([1, 2, 3]).difference([2])                  # [1, 3]  (single arg still works)

      # intersect? is true when the receiver and the argument share any element
      p ai([1, 2, 3]).intersect?([3, 4])               # true
      p ai([1, 2, 3]).intersect?([7, 8])               # false
      p ai([1, 2, 3]).intersect?([])                   # false (empty argument)

      # string arrays
      p as(["a", "b"]).union(["b", "c"], ["c", "d"])   # ["a", "b", "c", "d"]
      p as(["a", "b", "c"]).intersect?(["c", "z"])     # true

      # float arrays
      p af([1.0, 2.0, 3.0]).difference([2.0], [3.0])   # [1.0]

      # poly (mixed) arrays, with poly-typed arguments
      p ap([1, "b", 3]).union([3, "x"], ["y", 9])      # [1, "b", 3, "x", "y", 9]
      p ap([1, "b", 3, "x"]).difference([3, "q"], ["x", 0])  # [1, "b"]
      p ap([1, "b", 3]).intersect?(["b", 9])           # true
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [1, 2, 3, 4]
      [3, 4]
      [1, 3]
      [1, 3]
      true
      false
      false
      ["a", "b", "c", "d"]
      true
      [1.0]
      [1, "b", 3, "x", "y", 9]
      [1, "b"]
      true
    OUT
  end

  it "array set ops poly operand" do
    result = zr(<<~'RUBY')
      # An Array set operation whose OPERAND is poly -- a value whose static type
      # widened, not a poly array. The four diverged three ways: `&` and `|` had no
      # arm and would not compile, `-` was typed as arithmetic and reached
      # sp_poly_sub, which had no array case and answered "no implicit conversion of
      # Array into Array" on two real Arrays, and only `+` was right. The operand is
      # coerced at run time now: an Array becomes the poly array the set-op
      # primitives take, anything else raises the TypeError CRuby raises. #3475.
      def pick(flag) = flag ? [1, 2] : "x"
      def picks(flag) = flag ? ["s", "t"] : 1
      def bad(flag) = flag ? "x" : [1]

      # poly-array receiver
      a = [1, "s"]
      b = pick(true)
      p(a & b)
      p(a | b)
      p(a - b)
      p(a + b)
      p(a.intersection(b))
      p(a.union(b))
      p(a.difference(b))

      # int-array receiver
      i = [1, 2, 3]
      p(i & b)
      p(i | b)
      p(i - b)

      # str-array receiver
      s = ["s", "t", "u"]
      c = picks(true)
      p(s & c)
      p(s | c)
      p(s - c)

      # float-array receiver, poly holding an int array
      f = [1.5, 2.5]
      p((f - b).length)

      # the operand is not an Array at run time: CRuby's TypeError
      p((i & bad(true) rescue $!.class))
      p((i | bad(true) rescue $!.class))
      p((i - bad(true) rescue $!.class))

      # and when it is
      p(i & bad(false))

      # empty operand
      e = pick(false)
      p([1, 2] - (e.is_a?(String) ? [] : []))
      # The Rails shape the issue came from: a facade that delegates the set
      # operations to its materialised records, with an untyped parameter.
      class Relation
        def initialize(rows) = @rows = rows
        def to_a = @rows
        def +(other) = to_a + other
        def &(other) = to_a & other
        def |(other) = to_a | other
        def -(other) = to_a - other
      end

      r = Relation.new([1, "s", 2])
      p(r + [2, 3])
      p(r & [2, 3])
      p(r | [2, 3])
      p(r - [2, 3])
      p((r & "nope" rescue $!.class))
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [1, "s", 2]
      ["s"]
      [1, "s", 1, 2]
      [1]
      [1, "s", 2]
      ["s"]
      [1, 2]
      [1, 2, 3]
      [3]
      ["s", "t"]
      ["s", "t", "u"]
      ["u"]
      2
      TypeError
      TypeError
      TypeError
      [1]
      [1, 2]
      [1, "s", 2, 2, 3]
      [2]
      [1, "s", 2, 3]
      [1, "s"]
      TypeError
    OUT
  end

  it "array zero arg set ops" do
    result = zr(<<~'RUBY')
      a = [1, 2, 3]
      p a.difference
      p a.intersection
      p a.fetch_values
      p a.union
      b = ["x", "y"]
      p b.difference
      p b.intersection
      p [].difference
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3]
      []
      [1, 2, 3]
      ["x", "y"]
      ["x", "y"]
      []
    OUT
  end

  it "binmode does not set the binary encoding" do
    result = zr(<<~'RUBY')
      # `#binmode` returns the stream and changes nothing. In ruby it puts the
      # stream in binary mode, which sets the external encoding to `ASCII-8BIT`,
      # and everything read from it comes back binary.
      #
      #   StringIO.new("a").binmode.external_encoding   ruby ASCII-8BIT  zeo UTF-8
      #   File#binmode                                  the same
      #
      # On a platform with no newline translation the OTHER half of binary mode is
      # a no-op, which is presumably why this looked harmless: nothing about the
      # BYTES changes. The encoding does, and that is observable everywhere the
      # bytes are later interpreted -- a string written to a binmode stream comes
      # back tagged UTF-8 in zeo, so a caller that binmodes a stream precisely to
      # stop it interpreting bytes still gets them interpreted.
      #
      # `File.binread` already answers ASCII-8BIT, so the encoding-carrying
      # machinery is there; `binmode` simply does not reach it.
      #
      # Oracle: binmode means binary.
      require "stringio"
      require "tempfile"
      p StringIO.new("a").binmode.external_encoding.to_s
      s = StringIO.new("".dup)
      s.binmode
      s.write("é")
      p s.string.encoding.to_s
      f = Tempfile.new("bm")
      f.binmode
      p f.external_encoding.to_s
      f.close!
    RUBY

    _(result).must_answer <<~'OUT'
      "ASCII-8BIT"
      "ASCII-8BIT"
      "ASCII-8BIT"
    OUT
  end

  it "const set validates the name" do
    result = zr(<<~'RUBY')
      # `const_set` validates the constant name ("wrong constant name lower");
      # zeo sets the lowercase constant. `const_get` already validates. And
      # `remove_const` on a missing name prints the RECEIVER in its NameError
      # ("constant #<Module:0x...>::Nope not defined"); zeo names only the
      # constant. (Found by the 2026-08-24 probe sweep.)
      begin
        Module.new.const_set(:lower, 1)
        puts "set succeeded"
      rescue NameError => e
        puts e.message
      end
      begin
        Module.new.send(:remove_const, :Nope)
      rescue NameError => e
        puts e.message.sub(/0x[0-9a-f]+/, "0xN")
      end
    RUBY

    _(result).must_answer "wrong constant name lower\nconstant #<Module:0xN>::Nope not defined\n"
  end

  it "container read combined set map bang" do
    result = zr(<<~'RUBY')
      # The combined container-read shapes coexist in one program: with Set
      # required, a poly map! call used to (a) force set.rb's each into a bogus
      # recursive-yield reject, and (b) silently miss the builtin-array arm in
      # the user-method block dispatch (#3234).
      require 'set'
      m = [[1, 2], [3, 4]]; m[1].map! { |x| x * 10 }; p m
      h = { a: Set.new([1, 2, 3]) }
      p h[:a].map { |x| x }
      s2 = Set.new([1, 2])
      hs = { b: s2 }
      hs[:b].map! { |x| x + 5 }
      p s2.to_a.sort
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [30, 40]]
      [1, 2, 3]
      [6, 7]
    OUT
  end

  it "container read set enumerable" do
    result = zr(<<~'RUBY')
      # A Set read out of a container (poly receiver) iterates through the
      # generated to_a hook: map/select run over its elements, inject(:op)
      # folds through the numeric tower (#3234).
      require 'set'
      h = { a: Set.new([1, 2, 3]) }
      p h[:a].map { |x| x }
      p h[:a].select { |x| x > 1 }
      p h[:a].inject(:+)
      p h[:a].inject(:*)
      p [[1, 2, 3]][0].inject(:+)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [2, 3]
      6
      6
      6
    OUT
  end

  it "enumerable to set param" do
    result = zr(<<~'RUBY')
      # Enumerable#to_set through method parameters: the receiver reaches
      # Set.new intact (including via chained-call receivers), the result
      # dedups, prints, and supports set algebra.
      require "set"

      def ts_int(a) = a.to_set
      s1 = ts_int([1, 2, 2, 3])
      p s1.class
      p s1.size
      p s1.include?(2)
      p s1

      def ts_str(a) = a.to_set
      p ts_str(%w[a b a]).size

      def ts_poly(a) = a.to_set
      p ts_poly([1, "one", :one, 1]).size

      p (1..4).to_set.size

      def union(a, b) = a.to_set | b.to_set
      p union([1, 2], [2, 3]).sort

      direct = Set.new([5, 6, 5])
      p direct.size
      p Set.new.empty?
    RUBY

    _(result).must_answer <<~'OUT'
      Set
      3
      true
      Set[1, 2, 3]
      2
      3
      4
      [1, 2, 3]
      2
      true
    OUT
  end

  it "exception ivar set by a custom initialize survives the raise" do
    result = zr(<<~'RUBY')
      class Detailed < StandardError
        def initialize(field)
          @field = field
          super("invalid #{field}")
        end
        attr_reader :field
      end
      begin
        raise Detailed.new("email")
      rescue Detailed => e
        p [e.message, e.field]
      end
    RUBY

    _(result).must_answer "[\"invalid email\", \"email\"]\n"
  end

  it "frozen instance variable set" do
    result = zr(<<~'RUBY')
      class Cell
        def initialize; @n = 1; end
        def n; @n; end
      end
      d001 = Cell.new.freeze
      r001 = (d001.instance_variable_set(:@n, 7) rescue $!.class)
      p r001
      p d001.n

      class Counter
        attr_accessor :m
        def initialize; @n = 1; @m = 1; end
        def n; @n; end
        def bump; @n += 1; end
        def plain; @n = @n + 1; end
      end
      c002 = Counter.new.freeze
      r002 = (c002.bump rescue $!.class); p r002                            # => FrozenError
      r003 = (c002.plain rescue $!.class); p r003                           # => FrozenError
      r004 = (begin; c002.m = 5; rescue => e004; e004.class; end); p r004   # => FrozenError
      p c002.n                                                              # => 1
    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
      1
      FrozenError
      FrozenError
      FrozenError
      1
    OUT
  end

  it "inference method set" do
    result = zr(<<~'RUBY')
      # Parameter type inference must pick a class whose surface contains
      # ALL methods called on the param, regardless of class definition
      # order. Issue #35: previously the inferer locked in the first class
      # matching ANY single reader, ignoring later accesses, so swapping
      # Block and Cell changed the outcome.

      class Block
        attr_reader :x

        def initialize(x)
          @x = x
        end
      end

      class Cell
        attr_reader :x, :block

        def initialize
          @x = 0
        end

        def block=(block)
          @block = block
        end
      end

      def move_to(other)
        other.block = Block.new(other.x)
        other
      end

      c = Cell.new
      move_to(c)
      puts c.x         # 0
      puts c.block.x   # 0
    RUBY

    _(result).must_answer "0\n0\n"
  end

  it "instance variable set value class" do
    result = zr(<<~'RUBY')
      # `self.instance_variable_set` mutates the receiver, so the class cannot keep
      # the by-value representation (the write would land on a copy and be lost).
      class C
        def initialize; @z = 0; end
        def set; self.instance_variable_set(:@z, 5); end
        def get; @z; end
      end
      c = C.new
      c.set
      p c.get
      p c.instance_variable_get(:@z)

      class D
        def initialize; @a = 1; end
        def bump; self.instance_variable_set(:@a, @a + 10); end
        def a; @a; end
      end
      d = D.new
      d.bump
      d.bump
      p d.a
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      21
    OUT
  end

  it "issue scan block last match not set" do
    result = zr(<<~'RUBY')
      # String#scan with a block is supposed to set `$~` (and $1, $~.pre_match,
      # etc) to the current match on each iteration, the same way #sub/#gsub with
      # a block do. zeo leaves `$~` nil inside the scan block instead of updating
      # it per match.
      s = "1a2b3c"
      results = []
      s.scan(/\d/) { results << $~[0] }
      p results
    RUBY

    _(result).must_answer "[\"1\", \"2\", \"3\"]\n"
  end

  it "ivar get set literal" do
    result = zr(<<~'RUBY')
      class Box
        def initialize
          @v = 0
          @name = "box"
        end
        def v = @v
      end

      # receiver via a method param exercises a non-folded object receiver
      def setget(b)
        b.instance_variable_set(:@v, 99)
        b.instance_variable_get(:@v)
      end

      b = Box.new
      b.instance_variable_set(:@v, 42)
      puts b.instance_variable_get(:@v)
      puts b.v
      puts setget(Box.new)

      # instance_variable_set evaluates to the assigned value
      x = b.instance_variable_set(:@v, 7)
      puts x
      puts b.v

      # a String name resolves the same as a symbol
      puts b.instance_variable_get("@name")

      # an undefined but valid @-name reads as nil (CRuby returns nil for an unset ivar)
      p b.instance_variable_get(:@missing)

      # a name without a leading @ raises NameError at runtime
      begin; b.instance_variable_get(:x); rescue => e; puts "#{e.class}: #{e.message}"; end
      begin; b.instance_variable_set(:y, 1); rescue => e; puts "#{e.class}: #{e.message}"; end
      begin; b.instance_variable_get("z"); rescue => e; puts "#{e.class}: #{e.message}"; end
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      99
      7
      7
      box
      nil
      NameError: 'x' is not allowed as an instance variable name
      NameError: 'y' is not allowed as an instance variable name
      NameError: 'z' is not allowed as an instance variable name
    OUT
  end

  it "marshal round trip set" do
    result = zr(<<~'RUBY')
      require "set"
      p Marshal.load(Marshal.dump(Set[1, 2])).to_a.sort
    RUBY

    _(result).must_answer "[1, 2]\n"
  end

  it "module class var reflection set" do
    result = zr(<<~'RUBY')
      # class_variable_set with a literal name DECLARES the cvar when the class has
      # no such write (CRuby creates it on the fly), and class_variables lists the
      # registered ones, own + ancestors (#2719).
      class C; @@x = 5; end
      C.class_variable_set(:@@y, 9)
      p C.class_variable_get(:@@y)
      p C.class_variables.sort
      p C.class_variable_get(:@@x)
      c2 = C
      c2.class_variable_set(:@@y, 11)
      p C.class_variable_get(:@@y)
    RUBY

    _(result).must_answer <<~'OUT'
      9
      [:@@x, :@@y]
      5
      11
    OUT
  end

  it "module const set" do
    result = zr(<<~'RUBY')
      # Module#const_set with a literal name re-assigns the constant (#2675). A
      # constant is a compile-time C global, so an existing one can be stored into;
      # a name the program never writes has no storage, and the global's type is
      # fixed at its definition -- both of those report a specific diagnostic.
      class Box; X = 1; S = "a"; F = 1.5; end
      p Box.const_set(:X, 99)     # returns the value, as CRuby does
      p Box::X
      p Box.const_set(:S, "zz")
      p Box::S
      p Box.const_set(:F, 2.5)
      p Box::F
      Y = 10
      Object.const_set(:Y, 20)
      p Y
      p Box.const_get(:X)         # const_get sees the store
      p Box.const_set("X", 7)     # a String name works like a Symbol one
      p Box::X
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      99
      99
      "zz"
      "zz"
      2.5
      2.5
      20
      99
      7
      7
    OUT
      stdlib/set/set_test.rb:6: warning: already initialized constant Box::X
      stdlib/set/set_test.rb:5: warning: previous definition of X was here
      stdlib/set/set_test.rb:8: warning: already initialized constant Box::S
      stdlib/set/set_test.rb:5: warning: previous definition of S was here
      stdlib/set/set_test.rb:10: warning: already initialized constant Box::F
      stdlib/set/set_test.rb:5: warning: previous definition of F was here
      stdlib/set/set_test.rb:13: warning: already initialized constant Y
      stdlib/set/set_test.rb:12: warning: previous definition of Y was here
      stdlib/set/set_test.rb:16: warning: already initialized constant Box::X
      stdlib/set/set_test.rb:6: warning: previous definition of X was here
    ERR
  end

  it "reduce array set ops" do
    result = zr(<<~'RUBY')
      # Folding an array of arrays with `&` or `|`: the block parameters are boxed
      # when the receiver is a local, and the poly operator read them as integer
      # bitwise arithmetic, so the fold answered 0 (#3966).
      l = [[1, 2], [2, 3], [2, 5]]
      p l.reduce { |a, b| a & b }
      p l.reduce { |a, b| a | b }
      p l.inject { |a, b| a & b }
      p l.reduce([1, 2, 9]) { |a, b| a & b }
      p l.reduce([]) { |a, b| a | b }
      s = [%w[a b], %w[b c]]
      p s.reduce { |a, b| a & b }
      p s.reduce { |a, b| a | b }
      m = [[1, 2], ["a", 2]]
      p m.reduce { |a, b| a & b }
      p [1, 3, 7].reduce { |a, b| a & b }
      p [1, 2, 4].reduce { |a, b| a | b }
      p [true, true].reduce { |a, b| a & b }
      p [[1, 2]].reduce { |a, b| a & b }
      p l.reduce(:&)
      p l.reduce(:|)
    RUBY

    _(result).must_answer <<~'OUT'
      [2]
      [1, 2, 3, 5]
      [2]
      [2]
      [1, 2, 3, 5]
      ["b"]
      ["a", "b", "c"]
      [2]
      1
      7
      true
      [1, 2]
      [2]
      [1, 2, 3, 5]
    OUT
  end

  it "regexp class set range" do
    result = zr(<<~'RUBY')
      def show(pat, chars)
        re = Regexp.new(pat)
        p [pat, chars.select { |ch| ch =~ re }]
      rescue RegexpError
        p [pat, :RegexpError]
      end

      show('[a-\d]', ["a", "b", "d", "5", "-"])
      show('[\d-z]', ["0", "-", "z"])
      show('[\w-z]', ["a", "_", "-", "z"])
      show('[a-\w]', ["a", "w", "-"])
      show('[\d-9]', ["0", "9", "-"])
      show('[[:alpha:]-z]', ["a", "-", "z"])
      show('[\s-z]', [" ", "-", "z"])
      show('[^\d-z]', ["0", "-", "z"])

      show('[-\w]', ["-", "a", "5"])
      show('[\w-]', ["-", "a", "5"])
      show('[-\d-]', ["-", "5", "a"])
      show('[[:alpha:]-]', ["a", "-", "5"])
      show('[-[:digit:]]', ["-", "5", "a"])
      show('[\d\-z]', ["0", "-", "z", "m"])
      show('[-a]', ["-", "a"])
      show('[a-]', ["-", "a"])
      show('[a-z]', ["a", "m", "z", "-"])
      show('[0-9\w]', ["0", "a", "-"])
      show('[\w0-9]', ["0", "a", "-"])
      show('[\d\w]', ["0", "a", "-"])
      show('[[:alpha:]_]', ["a", "_", "-"])
      show('[^\w-]', ["-", "a", "5", "!"])
    RUBY

    _(result).must_answer <<~'OUT'
      ["[a-\\d]", :RegexpError]
      ["[\\d-z]", :RegexpError]
      ["[\\w-z]", :RegexpError]
      ["[a-\\w]", :RegexpError]
      ["[\\d-9]", :RegexpError]
      ["[[:alpha:]-z]", :RegexpError]
      ["[\\s-z]", :RegexpError]
      ["[^\\d-z]", :RegexpError]
      ["[-\\w]", ["-", "a", "5"]]
      ["[\\w-]", ["-", "a", "5"]]
      ["[-\\d-]", ["-", "5"]]
      ["[[:alpha:]-]", ["a", "-"]]
      ["[-[:digit:]]", ["-", "5"]]
      ["[\\d\\-z]", ["0", "-", "z"]]
      ["[-a]", ["-", "a"]]
      ["[a-]", ["-", "a"]]
      ["[a-z]", ["a", "m", "z"]]
      ["[0-9\\w]", ["0", "a"]]
      ["[\\w0-9]", ["0", "a"]]
      ["[\\d\\w]", ["0", "a"]]
      ["[[:alpha:]_]", ["a", "_"]]
      ["[^\\w-]", ["!"]]
    OUT
  end

  it "& and - enumerate the operand, so the result follows the operand's order" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # A Set algebra operation over a non-Set Enumerable does not preserve
      # ruby's result order.
      #
      require 'set'

      # The intersection and difference ENUMERATE the operand and consult the
      # receiver, so a Hash operand contributes its [key, value] pairs and the result
      # follows the operand's order. Asking the operand for #include? instead read a
      # Hash by key, and kept the receiver's order.
      p((Set[1, 2] & { 1 => :a }).to_a)
      p((Set[1, 2] - { 1 => :a }).to_a)
      p((Set[[:a, 1]] & { a: 1 }).to_a)
      p((Set[[:a, 1]] - { a: 1 }).to_a)

      p((Set[1, 2] & [2, 1]).to_a)
      p((Set[1, 2, 3] & [3, 1]).to_a)
      p((Set[1, 2] - [2]).to_a)
      p((Set[1, 2] & Set[2, 3]).to_a)
      p((Set[1, 2] - Set[2, 3]).to_a)
      p((Set[1, 2] & []).to_a)
      p((Set[1, 2] - []).to_a)
      p((Set[1, 2] | { 3 => :c }).to_a)
      p((Set[1, 2] ^ Set[2, 3]).to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [1, 2]
      [[:a, 1]]
      []
      [2, 1]
      [3, 1]
      [1]
      [2]
      [1]
      []
      [1, 2]
      [1, 2, [3, :c]]
      [1, 3]
    OUT
  end

  it "Exception#set_backtrace names an Array of String or of Location in its TypeError" do
    result = zr(<<~'RUBY')
      # `Exception#set_backtrace`'s TypeError names what ruby 4 accepts: "an
      # Array of String or an Array of Thread::Backtrace::Location"; zeo's
      # message still offers "a single String" (an older contract). (Found by
      # the 2026-08-24 probe sweep.)
      begin
        RuntimeError.new.set_backtrace(42)
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer "backtrace must be an Array of String or an Array of Thread::Backtrace::Location\n"
  end

  it "Set.new drops the equal elements, and each, include? and << answer over what is left" do
    result = zr(<<~'RUBY')
      # The bundled `set` library: construction from an array (with de-duplication of
      # equal scalar elements), iteration, membership, and mutation.
      require 'set'

      s = Set.new([:a, :b, :a, :c, :b])
      p s.size            # 3 (duplicates dropped)
      p s.length          # 3
      p s.empty?          # false
      p s.include?(:b)    # true
      p s.member?(:z)     # false

      s.each { |x| print x, " " }
      puts

      s << :d
      s.add(:a)           # already present, no-op
      p s.size            # 4
      p s.include?(:d)    # true

      p Set.new.empty?    # true (no argument)

      # integers dedup the same way
      n = Set.new([1, 2, 2, 3, 1])
      total = 0
      n.each { |x| total += x }
      p total             # 6
      p n.size            # 3
    RUBY

    _(result).must_answer "3\n3\nfalse\ntrue\nfalse\na b c \n4\ntrue\ntrue\n6\n3\n"
  end

  it "a two-parameter block auto-splats an Array element on map, each, select and sum" do
    result = zr(<<~'RUBY')
      require "set"

      s = Set.new([[1, 2]])
      p s.map { |r, c| [r, c] }
      s.each { |r, c| p [r, c] }
      p s.map { |r, c| r }
      p s.select { |r, c| r == 1 }.to_a
      p s.sum { |r, c| r }
      p s.sort_by { |r, c| r }

      t = Set.new([1, 2])
      p t.map { |x| x + 1 }
      t.each { |x| p x }

      h = { a: 1 }
      h.each { |k, v| p [k, v] }
      p [[3, 4]].map { |r, c| [r, c] }

      class Y
        def initialize(d); @d = d; end
        def each
          i = 0
          while i < @d.size
            yield @d[i]
            i += 1
          end
          self
        end
      end
      Y.new([[5, 6]]).each { |r, c| p [r, c] }
      Y.new([7]).each { |r, c| p [r, c] }
      Y.new([[8, 9]]).each { |x| p x }
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2]]
      [1, 2]
      [1]
      [[1, 2]]
      1
      [[1, 2]]
      [2, 3]
      1
      2
      [:a, 1]
      [[3, 4]]
      [5, 6]
      [7, nil]
      [8, 9]
    OUT
  end

  it "Set[...] builds a set from its arguments and drops the duplicates" do
    result = zr(<<~'RUBY')
      # Set[...] class-method constructor (CRuby's Set.[]).
      require "set"

      s = Set[1, 2, 3, 2, 1]
      puts s.size
      puts s.include?(2)
      puts s.include?(9)

      empty = Set[]
      puts empty.empty?

      t = Set["a", "b", "a"]
      puts t.size
      t << "c"
      puts t.size
    RUBY

    _(result).must_answer <<~'OUT'
      3
      true
      false
      true
      2
      3
    OUT
  end

  it "max, min and sort take a comparator block, and max takes a count" do
    result = zr(<<~'RUBY')
      require 'set'
      p(Set[3, 1, 2].max { |x, y| y <=> x })
      p(Set[3, 1, 2].min { |x, y| y <=> x })
      p(Set[3, 1, 2].sort { |x, y| y <=> x })
      p([3,1,2].max { |x, y| y <=> x })
      p(Set[3,1,2].max(2))
      p(Set[3,1,2].sort_by { |x| -x })
    RUBY

    _(result).must_answer <<~'OUT'
      1
      3
      [3, 2, 1]
      1
      [3, 2]
      [3, 2, 1]
    OUT
  end

  it "flatten!, replace and reset mutate in place, and every combinator takes an Array operand" do
    result = zr(<<~'RUBY')
      # Set mutators (flatten!/replace/reset), combinators with Array operands,
      # and mixed Set/Array arguments reaching the same combinator call site.
      require 'set'

      # flatten! merges nested sets in place; returns nil when already flat
      s = Set[Set[1, 2], Set[3]]
      s.flatten!
      p s.to_a.sort
      p Set[1, 2].flatten!

      # replace swaps the contents; reset returns self
      s2 = Set[1, 2, 3]
      p s2.replace([4, 5]).to_a.sort
      p s2.reset.to_a.sort

      # - / difference with an Array operand
      p((Set[1, 2, 3] - [2]).to_a.sort)
      p(Set[1, 2, 3].difference([2, 3]).to_a.sort)
      p((Set[1, 2, 3] - Set[2]).to_a.sort)

      # the same combinator fed both an Array and a Set in one program
      p((Set[1, 2] | [3, 4]).to_a.sort)
      p((Set[1, 2] | Set[2, 3]).to_a.sort)
      p((Set[1, 2] & [2, 3]).to_a.sort)
      p((Set[1, 2] & Set[2]).to_a.sort)
      p((Set[1, 2] ^ [2, 3]).to_a.sort)
      p((Set[1, 2] ^ Set[2, 3]).to_a.sort)
      p((Set[1, 2] + [3]).to_a.sort)
      p(Set[1, 2].union(Set[5]).to_a.sort)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      nil
      [4, 5]
      [4, 5]
      [1, 3]
      [1]
      [1, 3]
      [1, 2, 3, 4]
      [1, 2, 3]
      [2]
      [2]
      [1, 3]
      [1, 3]
      [1, 2, 3]
      [1, 2, 5]
    OUT
  end

  it "size, include?, |, subset? and map answer on a set built from a literal" do
    result = zr(<<~'RUBY')
      s = Set[3, 1, 2, 1]
      p s.size
      p s.include?(2)
      p (Set[1, 2] | Set[2, 3]).to_a.sort
      p Set[1, 2].subset?(Set[1, 2, 3])
      p s.map { |x| x * 2 }.sort
    RUBY

    _(result).must_answer <<~'OUT'
      3
      true
      [1, 2, 3]
      true
      [2, 4, 6]
    OUT
  end

  it "delete is a no-op for a missing element and returns the set, so it chains" do
    result = zr(<<~'RUBY')
      require 'set'

      s = Set.new
      s.add(1)
      s.add(2)
      s << 3
      s.add(2)
      puts s.size
      puts s.include?(2)

      s.delete(2)
      puts s.include?(2)
      puts s.size

      # deleting a missing key is a no-op and still returns the set (chainable)
      s.delete(99).add(4)
      puts s.size
      puts s.include?(4)
      puts s.member?(1)
      puts s.empty?
    RUBY

    _(result).must_answer <<~'OUT'
      3
      true
      false
      2
      3
      true
      true
      false
    OUT
  end

  it "add, delete, the four operators, subset?, == and the Enumerable methods answer in one run" do
    result = zr(<<~'RUBY')
      require "set"

      s = Set.new([1, 2, 3, 2, 1])
      puts s.size
      puts s.include?(2)
      s.add(4)
      s << 5
      s.delete(3)
      puts s.to_a.length
      puts s.member?(3)

      a = Set.new([1, 2, 3])
      b = Set.new([3, 4])
      puts (a | b).size
      puts (a & b).to_a.length
      puts (a - b).size
      puts (a ^ b).size
      puts a.subset?(Set.new([1, 2, 3, 9]))
      puts Set.new([3, 2, 1]) == Set.new([1, 2, 3])
      puts a == b

      doubled = a.map { |x| x * 2 }
      puts doubled.length
      puts a.select { |x| x > 1 }.length
      puts a.any? { |x| x > 2 }
      puts a.all? { |x| x > 0 }
      puts a.count
      puts Set.new.empty?
    RUBY

    _(result).must_answer <<~'OUT'
      3
      true
      4
      false
      4
      1
      2
      3
      true
      true
      false
      3
      2
      true
      true
      3
      true
    OUT
  end

  it "divide groups by a one-parameter block's value and by a two-parameter block's relation" do
    result = zr(<<~'RUBY')
      require 'set'
      s = Set[1, 2, 3, 4, 5, 6]
      p s.divide { |x| x % 3 }.map { |sub| sub.to_a.sort }.sort
      p Set[1, 2, 3, 4].divide { |x, y| (x - y).abs == 1 }.map { |sub| sub.to_a.sort }.sort
      p Set[1, 2, 3].divide { |x, y| x - y == 1 }.map { |sub| sub.to_a.sort }.sort
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 4], [2, 5], [3, 6]]
      [[1, 2, 3, 4]]
      [[1], [2], [3]]
    OUT
  end

  it "a blockless each is an Enumerator, and the constructor takes any Enumerable including one" do
    result = zr(<<~'RUBY')
      require 'set'

      # A blockless Set#each raised LocalJumpError -- the method is written with
      # yield -- where CRuby answers an Enumerator, and the constructor refused an
      # Enumerator operand because nothing said an Enumerator is enumerable.

      # a blockless Set#each is an Enumerator over the members
      p Set[1, 2].each.to_a

      # the constructor takes any Enumerable, including an Enumerator
      p Set.new([1, 2].each).to_a
      p Set.new([1, 2]).to_a
      p Set.new((1..3)).to_a
      p Set.new({ a: 1 }).to_a
      p Set.new([1, 2]) { |x| x * 2 }.to_a
      p Set.new(Set[5, 6]).to_a

      # the block form and the rest of the surface are unchanged
      r = []
      Set[3, 4].each { |x| r << x }
      p r
      p Set[1, 2].map { |x| x + 1 }
      p Set[1, 2].to_a
      p Set[1, 2].include?(2)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2]
      [1, 2]
      [1, 2, 3]
      [[:a, 1]]
      [2, 4]
      [5, 6]
      [3, 4]
      [2, 3]
      [1, 2]
      true
    OUT
  end

  it "keep_if and delete_if return the receiver, and select! and reject! return nil when nothing moved" do
    result = zr(<<~'RUBY')
      require "set"

      # subtract / replace (in place, return self)
      s = Set[1, 2, 3, 4]
      p s.subtract([2, 3]).to_a.sort
      p s.replace([9, 8, 8, 7]).to_a.sort

      # flatten / flatten!
      nested = Set[Set[1, 2], Set[3, Set[4]]]
      p nested.flatten.to_a.sort
      f = Set[Set[1, 2], Set[3]]
      p f.flatten!.to_a.sort
      p Set[1, 2].flatten!

      # map! / collect!
      m = Set[1, 2, 3]
      m.map! { |x| x * 10 }
      p m.to_a.sort

      # select! / filter! / keep_if
      sel = Set[1, 2, 3, 4]
      p sel.select! { |x| x.even? }.to_a.sort
      p Set[2, 4].select! { |x| x.even? } # no change -> nil
      kept = Set[1, 2, 3, 4]
      p kept.keep_if { |x| x.odd? }.equal?(kept)

      # reject! / delete_if
      rej = Set[1, 2, 3, 4]
      p rej.reject! { |x| x.even? }.to_a.sort
      p Set[1, 3].reject! { |x| x.even? } # no change -> nil
      del = Set[1, 2, 3, 4]
      p del.delete_if { |x| x.even? }.equal?(del)

      # classify
      p Set[1, 2, 3, 4, 5].classify { |x| x % 3 }.transform_values { |v| v.to_a.sort }

      # divide (one-arg groups by value; two-arg strongly-connected components)
      p Set[1, 2, 3, 4].divide { |i| i % 3 }.map { |grp| grp.to_a.sort }.sort
      p Set[1, 2, 3, 4].divide { |x, y| (x - y).abs == 1 }.map { |grp| grp.to_a.sort }.sort
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 4]
      [7, 8, 9]
      [1, 2, 3, 4]
      [1, 2, 3]
      nil
      [10, 20, 30]
      [2, 4]
      nil
      true
      [1, 3]
      nil
      true
      {1 => [1, 4], 2 => [2, 5], 0 => [3]}
      [[1, 4], [2], [3]]
      [[1, 2, 3, 4]]
    OUT
  end

  it "a frozen set refuses every mutator with FrozenError, and an unfrozen one still mutates" do
    result = zr(<<~'RUBY')
      require 'set'

      # A frozen Set refuses every mutation, as CRuby's does. The element array is a
      # private ivar, so freezing the Set itself was invisible to the mutators and
      # every one of them went through.

      a = Set[1, 2].freeze
      p((a.add(3) rescue $!.class))
      p((a << 4 rescue $!.class))
      p((a.delete(1) rescue $!.class))
      p((a.merge([9]) rescue $!.class))
      p((a.subtract([2]) rescue $!.class))
      p((a.replace([7]) rescue $!.class))
      p(a.to_a)
      p((a.clear rescue $!.class))
      p((a.add?(5) rescue $!.class))
      p((a.delete?(1) rescue $!.class))
      p((a.keep_if { |x| x > 1 } rescue $!.class))
      p((a.delete_if { |x| x > 1 } rescue $!.class))
      p((a.map! { |x| x } rescue $!.class))
      p a.to_a
      p a.frozen?

      # an unfrozen Set still mutates
      b = Set[1, 2]
      b.add(3)
      b << 4
      b.delete(1)
      p b.to_a
      p b.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
      FrozenError
      FrozenError
      FrozenError
      FrozenError
      FrozenError
      [1, 2]
      FrozenError
      FrozenError
      FrozenError
      FrozenError
      FrozenError
      FrozenError
      [1, 2]
      true
      [2, 3, 4]
      false
    OUT
  end

  it "the Enumerable methods, the comparison operators and to_set answer across the API" do
    result = zr(<<~'RUBY')
      require 'set'
      p(Set[1, 2, 3].select { |x| x > 1 })
      p(Set[1,2,3].reject { |x| x.even? })
      p(Set[1,2,3].find { |x| x > 1 })
      p(Set[1,2,3].count { |x| x.odd? })
      p(Set[1,2,3].sum)
      p(Set[3,1,2].min)
      p(Set[3,1,2].max)
      p(Set[1,2,3].inject(:+))
      p(Set[1,2,3].group_by { |x| x.odd? })
      p(Set[1,2,3].filter_map { |x| x*10 if x.odd? })
      s = Set[1, 2]; t = Set[1, 2]; p(s == t)
      p(Set[1, 2] == Set[2, 1])
      p(Set[1, 2] == Set[1, 2, 3])
      p(Set[1, 2] == [1, 2])
      p(Set[1, 2].add?(3))
      p(Set[1, 2].add?(2))
      p(Set[1, 2, 3].delete?(2))
      p(Set[1, 2, 3].delete?(9))
      p(Set[1, 2].merge([3, 4]))
      p(Set[1, 2, 3].subtract([2, 3]))
      p(Set[1, 2, 3] ^ Set[2, 3, 4])
      p(Set[1, 2] < Set[1, 2, 3])
      p(Set[1, 2, 3] > Set[1, 2])
      p(Set[1, 2] < Set[1, 2])
      p(Set[1, 2].proper_subset?(Set[1, 2, 3]))
      p(Set[1, 2, 3].proper_superset?(Set[1, 2]))
      p(Set[1, 2].disjoint?(Set[3, 4]))
      p(Set[1, 2].intersect?(Set[2, 3]))
      p(Set[1, 2, 3] === 2)
      p(Set[1, 2] <=> Set[1, 2, 3])
      p(Set[1, 2, 3] <=> Set[1, 2])
      p(Set[1, 2] <=> Set[1, 2])
      p(Set[1, 2] <=> Set[3, 4])
      s = Set[1, 2, 3]
      s.clear
      p s
      p(Set[1, 2, 3].classify { |x| x.odd? })
      p(Set[1, 2, 3].divide { |x| x.odd? })
      p(Set[Set[1, 2], Set[3]].flatten)
      p [1, 2, 2, 3].to_set
      p((1..4).to_set)
      p %w[a b a].to_set
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3]
      [1, 3]
      2
      2
      6
      1
      3
      6
      {true => [1, 3], false => [2]}
      [10, 30]
      true
      true
      false
      false
      Set[1, 2, 3]
      nil
      Set[1, 3]
      nil
      Set[1, 2, 3, 4]
      Set[1]
      Set[1, 4]
      true
      true
      false
      true
      true
      true
      true
      true
      -1
      1
      0
      nil
      Set[]
      {true => Set[1, 3], false => Set[2]}
      Set[Set[1, 3], Set[2]]
      Set[1, 2, 3]
      Set[1, 2, 3]
      Set[1, 2, 3, 4]
      Set["a", "b"]
    OUT
  end

  it "FrozenError names the receiver, and a binary operator on a subclass answers the subclass" do
    result = zr(<<~'RUBY')
      # Two Set rows: the FrozenError names the receiver ("can't modify
      # frozen Set: Set[1]"), and a binary op on a Set SUBCLASS answers the
      # subclass. (Found by the 2026-08-24 probe sweep.)
      require "set"
      begin
        Set[1].freeze.add(2)
      rescue FrozenError => e
        puts e.message
      end
      k = Class.new(Set)
      p (k[1] | Set[2]).class == k
    RUBY

    _(result).must_answer "can't modify frozen Set: Set[1]\ntrue\n"
  end

  it "Set.new takes the Array that map returns, and a plain class takes the same shape" do
    result = zr(<<~'RUBY')
      require "set"

      s = Set.new([1, 2])
      t = Set.new(s.map { |x| x + 1 })
      p t.to_a

      u = Set.new([[1, 2]])
      p Set.new(u.map { |x| x }).size
      p Set.new(u.to_a.map { |r, c| [r, c] }).size

      m = s.map { |x| x * 10 }
      p Set.new(m).to_a

      class Box
        def initialize(enum = nil)
          @data = []
          if enum
            src = enum.to_a
            if block_given?
              src.each { |x| @data << yield(x) }
            else
              src.each { |x| @data << x }
            end
          end
        end
        def items = @data
        def each_mapped
          r = []
          i = 0
          while i < @data.length
            r << yield(@data[i])
            i += 1
          end
          r
        end
      end

      b = Box.new([1, 2])
      p Box.new(b.each_mapped { |x| x + 1 }).items
      p Box.new(b.each_mapped { |x| x * 3 }) { |y| y + 100 }.items
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3]
      1
      1
      [10, 20]
      [2, 3]
      [103, 106]
    OUT
  end

  it "a search asks == while a set operation asks eql?, so [1.0] - [1] keeps the Float" do
    result = zr(<<~'RUBY')
      # Ruby splits its container rows in two, and the split is observable.
      #
      #   A SEARCH asks `==`  -- `include?`, `index`, `rindex`, `count`,
      #                          `delete`, `assoc`, `rassoc`, `Hash#value?`.
      #   A SET OP asks `eql?` -- `-`, `&`, `|`, `intersection`, `difference`,
      #                          `union`, `intersect?`, `uniq`, `Hash#slice`,
      #                          `Hash#except`, `Array#eql?`, `Struct#eql?`.
      #
      # `1.0` against `1` separates the two: they are `==` but not `eql?`. Zeo
      # drove every row with `==`, so a set operation answered the search's
      # answer -- `[1.0] - [1]` came back EMPTY where ruby keeps the Float. That
      # is a silently wrong answer on an ordinary mixed-numeric list.
      #
      # The same one rule covers a user class too: an object defining only `==`
      # (no `eql?`/`hash`) is its own key, so a set operation keeps both copies
      # while a search still finds either.
      def show(name) = (puts "#{name}\t#{(yield).inspect}" rescue puts "#{name}\t#{$!.class}")

      # --- The searches: `==`, so a Float finds an Integer ---------------------
      show("include?")    { [1.0].include?(1) }
      show("index")       { [1.0].index(1) }
      show("rindex")      { [1.0].rindex(1) }
      show("count")       { [1.0].count(1) }
      show("delete")      { [1.0].delete(1) }
      show("assoc")       { [[1.0, :x]].assoc(1) }
      show("rassoc")      { [[:x, 1.0]].rassoc(1) }
      show("ary ==")      { [1.0] == [1] }
      show("hash value?") { { a: 1.0 }.value?(1) }
      show("hash key")    { { a: 1.0 }.key(1) }
      show("hash ==")     { { a: 1.0 } == { a: 1 } }
      show("hash <=")     { { a: 1.0 } <= { a: 1 } }
      show("enum count")  { [1.0].each_entry.count(1) }
      show("enum index")  { [1.0].each_entry.find_index(1) }
      show("enum incl?")  { [1.0].each_entry.include?(1) }

      # --- The set operations: `eql?`, so it does not -------------------------
      show("-")            { [1.0] - [1] }
      show("&")            { [1.0] & [1] }
      show("|")            { [1.0] | [1] }
      show("intersection") { [1.0].intersection([1]) }
      show("difference")   { [1.0].difference([1]) }
      show("union")        { [1.0].union([1]) }
      show("intersect?")   { [1.0].intersect?([1]) }
      show("uniq")         { [1.0, 1].uniq }
      show("enum uniq")    { [1.0, 1].each_entry.uniq }
      show("ary eql?")     { [1.0].eql?([1]) }
      show("hash eql?")    { { a: 1.0 }.eql?({ a: 1 }) }
      show("hash slice")   { { 1.0 => :x }.slice(1) }
      show("hash except")  { { 1.0 => :x }.except(1) }

      # `slice` walks the ARGUMENTS and `except` walks the receiver, so the two
      # do not answer the same order for the same pair of keys.
      show("slice order")  { { a: 1, b: 2 }.slice(:b, :a) }
      show("except order") { { a: 1, b: 2 }.except(:zz) }
      show("slice absent") { { a: 1 }.slice(:zz) }

      S = Struct.new(:x)
      show("struct ==")    { S.new(1.0) == S.new(1) }
      show("struct eql?")  { S.new(1.0).eql?(S.new(1)) }

      # --- A user class defining only `==` ------------------------------------
      class OnlyEq
        def initialize(n) = @n = n
        def ==(o) = o.is_a?(OnlyEq) && o.n == @n
        protected def n = @n
        def inspect = "OnlyEq(#{@n})"
      end
      a, b = OnlyEq.new(1), OnlyEq.new(1)
      show("user include?") { [a].include?(b) }
      show("user count")    { [a].count(b) }
      show("user -")        { [a] - [b] }
      show("user &")        { [a] & [b] }
      show("user |")        { [a] | [b] }
      show("user uniq")     { [a, b].uniq.size }

      # --- A user class defining `hash` and `eql?` the ordinary way -----------
      class Both
        def initialize(n) = @n = n
        def hash = 1                     # deliberately colliding
        def eql?(o) = o.is_a?(Both) && o.n == @n
        def ==(o) = eql?(o)
        protected def n = @n
        def inspect = "Both(#{@n})"
      end
      c, d = Both.new(1), Both.new(2)
      show("both uniq")   { [c, d].uniq.size }
      show("both hash")   { { c => 1, d => 2 }.size }
      show("both -")      { [c, d] - [c] }
      show("both &")      { [c, d] & [c] }
      show("both |")      { [c] | [d] }
      show("both slice")  { { c => 1, d => 2 }.slice(Both.new(1)) }
      show("both except") { { c => 1, d => 2 }.except(Both.new(1)) }
    RUBY

    _(result).must_answer <<~'OUT'
      include?	true
      index	0
      rindex	0
      count	1
      delete	1.0
      assoc	[1.0, :x]
      rassoc	[:x, 1.0]
      ary ==	true
      hash value?	true
      hash key	:a
      hash ==	true
      hash <=	true
      enum count	1
      enum index	0
      enum incl?	true
      -	[1.0]
      &	[]
      |	[1.0, 1]
      intersection	[]
      difference	[1.0]
      union	[1.0, 1]
      intersect?	false
      uniq	[1.0, 1]
      enum uniq	[1.0, 1]
      ary eql?	false
      hash eql?	false
      hash slice	{}
      hash except	{1.0 => :x}
      slice order	{b: 2, a: 1}
      except order	{a: 1, b: 2}
      slice absent	{}
      struct ==	true
      struct eql?	false
      user include?	true
      user count	1
      user -	[OnlyEq(1)]
      user &	[]
      user |	[OnlyEq(1), OnlyEq(1)]
      user uniq	2
      both uniq	2
      both hash	2
      both -	[Both(2)]
      both &	[Both(1)]
      both |	[Both(1), Both(2)]
      both slice	{Both(1) => 1}
      both except	{Both(2) => 2}
    OUT
  end

  it "&, | and - build fresh sets, and subset? and superset? compare membership" do
    result = zr(<<~'RUBY')
      # Set operators and queries over the array-backed bundled set: & | - build
      # fresh sets, subset?/superset? compare membership, to_a/map expose the
      # elements (map returns an Array, as in CRuby).
      require "set"
      a = Set[1, 2, 3]
      b = Set[2, 3, 4]
      p (a & b).size
      p (a | b).size
      p (a - b).size
      p a.subset?(b)
      p Set[2, 3].subset?(a)
      p a.superset?(Set[1, 2])
      p Set[1, 2].to_a.sort
      p Set[1, 2, 3].map { |x| x * 2 }.sort
      p (a & b).to_a.sort
      p (a | b).to_a.sort
      p (a - b).to_a.sort
      p a.intersection(b).size
      p a.union(b).size
      p a.difference(b).size
    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      1
      false
      true
      true
      [1, 2]
      [2, 4, 6]
      [2, 3]
      [1, 2, 3, 4]
      [1]
      2
      4
      1
    OUT
  end

  it "the containment predicates take a set and raise ArgumentError on anything else" do
    result = zr(<<~'RUBY')
      # The containment predicates take a Set and nothing else: CRuby answers
      # ArgumentError("value must be a set"). Passing an Array reached the operand's
      # own #subset?, which does not exist on one, and refused to compile at all.
      require 'set'

      r = (Set[1, 2] >= [1] rescue $!.class); p r
      r = (Set[1, 2] >= [1] rescue $!.message); p r
      r = (Set[1, 2] > [1] rescue $!.class); p r
      r = (Set[1, 2] <= [1, 2, 3] rescue $!.class); p r
      r = (Set[1, 2] < [1, 2, 3] rescue $!.class); p r
      r = (Set[1, 2].subset?([1, 2, 3]) rescue $!.class); p r
      r = (Set[1, 2].superset?([1]) rescue $!.class); p r

      # a Set operand keeps answering
      p(Set[1, 2] >= Set[1])
      p(Set[1] <= Set[1, 2])
      p(Set[1, 2] > Set[1])
      p(Set[1, 2] < Set[1])
      p(Set[1, 2].superset?(Set[1, 2]))
      p(Set[1, 2].proper_superset?(Set[1, 2]))
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      "value must be a set"
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      true
      true
      true
      false
      true
      false
    OUT
  end

  it "a Range is an operand for every combinator, and for merge, subtract and replace" do
    result = zr(<<~'RUBY')
      require 'set'
      p((Set[1, 2] & (2..4)).to_a)
      p((Set[1, 2] | (2..4)).to_a)
      p((Set[1, 2] + (2..4)).to_a)
      p(Set[1,2].union(2..4).to_a)
      p(Set[1,2].intersection(2..4).to_a)
      p((Set["a", "b"] & ("a".."c")).to_a)
      p(Set.new(1..3).to_a)
      s = Set[1]; s.merge(2..3); p s.to_a
      t = Set[1,2,3]; t.subtract(2..3); p t.to_a
      u = Set[9]; u.replace(1..2); p u.to_a
      p((Set[1,2,3] - (2..4)).to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      [2]
      [1, 2, 3, 4]
      [1, 2, 3, 4]
      [1, 2, 3, 4]
      [2]
      ["a", "b"]
      [1, 2, 3]
      [1, 2, 3]
      [1]
      [1, 2]
      [1]
    OUT
  end

  it "subtract, flatten, map!, select!, reject!, classify and divide each answer" do
    result = zr(<<~'RUBY')
      require "set"
      s = Set[1, 2, 3, 4]
      p s.subtract([2, 3]).to_a.sort
      p s.replace([9, 8, 8, 7]).to_a.sort
      p Set[Set[1, 2], Set[3, Set[4]]].flatten.to_a.sort
      p Set[Set[1, 2], Set[3]].flatten!.to_a.sort
      p Set[1, 2].flatten!
      m = Set[1, 2, 3]; m.map! { |x| x * 10 }; p m.to_a.sort
      p Set[1, 2, 3, 4].select! { |x| x.even? }.to_a.sort
      p Set[2, 4].select! { |x| x.even? }
      p Set[1, 2, 3, 4].reject! { |x| x.even? }.to_a.sort
      p Set[1, 2, 3, 4, 5].classify { |x| x % 3 }.transform_values { |v| v.to_a.sort }
      p Set[1, 2, 3, 4].divide { |i| i % 3 }.map { |g| g.to_a.sort }.sort
      p Set[1, 2, 3, 4].divide { |x, y| (x - y).abs == 1 }.map { |g| g.to_a.sort }.sort
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 4]
      [7, 8, 9]
      [1, 2, 3, 4]
      [1, 2, 3]
      nil
      [10, 20, 30]
      [2, 4]
      nil
      [1, 3]
      {1 => [1, 4], 2 => [2, 5], 0 => [3]}
      [[1, 4], [2], [3]]
      [[1, 2, 3, 4]]
    OUT
  end

  it "Set#reset, Thread.list, Module#const_set and the exception accessors that take data" do
    result = zr(<<~'RUBY')
      # Set#reset, Thread.list, Module#const_set, and the exception accessors that
      # take keyword/positional data: KeyError(key:/receiver:), SystemExit(status),
      # LocalJumpError#reason, FrozenError#receiver.

      require "set"
      p Set[1, 2, 3].reset.to_a.sort
      p Thread.list.all? { |t| t.is_a?(Thread) }
      module Box; end
      p Box.const_set(:X, 99)
      p Box::X
      ke = KeyError.new("m", key: :k, receiver: {1 => 2})
      p [ke.key, ke.receiver, ke.message]
      p [SystemExit.new(2).status, SystemExit.new(2).success?, SystemExit.new.success?, SystemExit.new(true, "bye").message]
      s = "x".freeze
      begin; s << "y"; rescue FrozenError => e; p e.receiver; end
      def mm; yield; end
      begin; mm; rescue LocalJumpError => e; p [e.reason, e.exit_value]; end
      begin; {}.fetch(:z); rescue KeyError => e; p e.key; end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      true
      99
      99
      [:k, {1 => 2}, "m"]
      [2, false, true, "bye"]
      "x"
      [:noreason, nil]
      :z
    OUT
  end

  it "small api matchdata size set join complex i method source location" do
    result = zr(<<~'RUBY')
      # Small API wins: MatchData#size/#length, Set#join, the Complex::I
      # imaginary-unit constant (and that it multiplies to -1), and Method's
      # source_location/super_method (nil for a builtin, matching CRuby's C-method).

      require "set"
      m = "2026-06".match(/(\d+)-(\d+)/)
      p m.size
      p m.length
      p Set[1, 2, 3].join("-")
      p Complex::I
      p(Complex::I * Complex::I)
      p 5.method(:+).source_location
      p 5.method(:+).super_method
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      "1-2-3"
      (0+1i)
      (-1+0i)
      nil
      nil
    OUT
  end

  it "struct valuesat hash set init wave10" do
    result = zr(<<~'RUBY')
      # Struct#values_at (index and range keys) and #hash (value equality).
      Pt = Struct.new(:x, :y, :z)
      a = Pt.new(1, 2, 3)
      p a.values_at(0, 2)
      p a.values_at(0..1)
      b = Pt.new(1, 2, 3)
      p(a.hash == b.hash)
      c = Pt.new(9, 2, 3)
      p(a.hash == c.hash)
      require 'set'
      t = Set.new([1, 2, 2, 3])
      p t
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3]
      [1, 2]
      true
      false
      Set[1, 2, 3]
    OUT
  end

  it "subclass sees only the calls ruby makes" do
    result = zr(<<~'RUBY')
      # Which of Set's own methods its methods call on a subclass: every
      # method Set defines is wrapped to log a call made from inside another,
      # and each is then called once on a fresh receiver. CRuby calls one by
      # dispatch only where it means to, and zr's core, written in Ruby, has
      # to call no more and no fewer. Written by `rake gen:dispatch`.

      class Probe < Set
        CALLING = []
        LOG = []
        [:&, :+, :-, :<, :<<, :<=, :<=>, :==, :===, :>, :>=, :^, :add, :add?, :all?, :any?, :chain, :chunk, :chunk_while, :classify, :clear, :collect, :collect!, :collect_concat, :compact, :compare_by_identity, :compare_by_identity?, :count, :cycle, :delete, :delete?, :delete_if, :detect, :difference, :disjoint?, :divide, :drop, :drop_while, :each, :each_cons, :each_entry, :each_slice, :each_with_index, :each_with_object, :empty?, :entries, :eql?, :filter, :filter!, :filter_map, :find, :find_all, :find_index, :first, :flat_map, :flatten, :flatten!, :grep, :grep_v, :group_by, :hash, :include?, :initialize_copy, :inject, :inspect, :intersect?, :intersection, :join, :keep_if, :lazy, :length, :map, :map!, :max, :max_by, :member?, :merge, :min, :min_by, :minmax, :minmax_by, :none?, :one?, :partition, :proper_subset?, :proper_superset?, :reduce, :reject, :reject!, :replace, :reset, :reverse_each, :select, :select!, :size, :slice_after, :slice_before, :slice_when, :sort, :sort_by, :subset?, :subtract, :sum, :superset?, :take, :take_while, :tally, :to_a, :to_h, :to_s, :to_set, :union, :uniq, :zip, :|].each do |m|
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
        r = Probe.new([1, 2, 3])
        Probe::LOG.clear
        begin
          yield r
        rescue StandardError => e
          Probe::LOG << "raised #{e.class}"
        end
        puts "#{name}: #{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
      end

      call("&") { |r| r.__send__(:&, [1, 2]) { |*x| x.first } }
      call("+") { |r| r.__send__(:+, [1, 2]) { |*x| x.first } }
      call("-") { |r| r.__send__(:-, [1, 2]) { |*x| x.first } }
      call("<<") { |r| r.__send__(:<<, 1) { |*x| x.first } }
      call("<=>") { |r| r.__send__(:<=>, 1) { |*x| x.first } }
      call("==") { |r| r.__send__(:==, 1) { |*x| x.first } }
      call("===") { |r| r.__send__(:===, 1) { |*x| x.first } }
      call("^") { |r| r.__send__(:^, [1, 2]) { |*x| x.first } }
      call("add") { |r| r.add(1) { |*x| x.first } }
      call("add?") { |r| r.add?(1) { |*x| x.first } }
      call("all?") { |r| r.all?() { |*x| x.first } }
      call("any?") { |r| r.any?() { |*x| x.first } }
      call("chain") { |r| r.chain() { |*x| x.first } }
      call("chunk") { |r| r.chunk() { |*x| x.first } }
      call("chunk_while") { |r| r.chunk_while() { |*x| x.first } }
      call("classify") { |r| r.classify() { |*x| x.first } }
      call("clear") { |r| r.clear() { |*x| x.first } }
      call("collect") { |r| r.collect() { |*x| x.first } }
      call("collect!") { |r| r.collect!() { |*x| x.first } }
      call("collect_concat") { |r| r.collect_concat() { |*x| x.first } }
      call("compact") { |r| r.compact() { |*x| x.first } }
      call("compare_by_identity") { |r| r.compare_by_identity() { |*x| x.first } }
      call("compare_by_identity?") { |r| r.compare_by_identity?() { |*x| x.first } }
      call("count") { |r| r.count() { |*x| x.first } }
      call("delete") { |r| r.delete(1) { |*x| x.first } }
      call("delete?") { |r| r.delete?(1) { |*x| x.first } }
      call("delete_if") { |r| r.delete_if() { |*x| x.first } }
      call("detect") { |r| r.detect() { |*x| x.first } }
      call("difference") { |r| r.difference([1, 2]) { |*x| x.first } }
      call("disjoint?") { |r| r.disjoint?([1, 2]) { |*x| x.first } }
      call("divide") { |r| r.divide() { |*x| x.first } }
      call("drop") { |r| r.drop(1) { |*x| x.first } }
      call("drop_while") { |r| r.drop_while() { |*x| x.first } }
      call("each") { |r| r.each() { |*x| x.first } }
      call("each_cons") { |r| r.each_cons(1) { |*x| x.first } }
      call("each_entry") { |r| r.each_entry() { |*x| x.first } }
      call("each_slice") { |r| r.each_slice(1) { |*x| x.first } }
      call("each_with_index") { |r| r.each_with_index() { |*x| x.first } }
      call("each_with_object") { |r| r.each_with_object(1) { |*x| x.first } }
      call("empty?") { |r| r.empty?() { |*x| x.first } }
      call("entries") { |r| r.entries() { |*x| x.first } }
      call("eql?") { |r| r.eql?(1) { |*x| x.first } }
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
      call("inject") { |r| r.inject() { |*x| x.first } }
      call("inspect") { |r| r.inspect() { |*x| x.first } }
      call("intersect?") { |r| r.intersect?([1, 2]) { |*x| x.first } }
      call("intersection") { |r| r.intersection([1, 2]) { |*x| x.first } }
      call("join") { |r| r.join() { |*x| x.first } }
      call("keep_if") { |r| r.keep_if() { |*x| x.first } }
      call("lazy") { |r| r.lazy() { |*x| x.first } }
      call("length") { |r| r.length() { |*x| x.first } }
      call("map") { |r| r.map() { |*x| x.first } }
      call("map!") { |r| r.map!() { |*x| x.first } }
      call("max") { |r| r.max() { |*x| x.first } }
      call("max_by") { |r| r.max_by() { |*x| x.first } }
      call("member?") { |r| r.member?(1) { |*x| x.first } }
      call("merge") { |r| r.merge() { |*x| x.first } }
      call("min") { |r| r.min() { |*x| x.first } }
      call("min_by") { |r| r.min_by() { |*x| x.first } }
      call("minmax") { |r| r.minmax() { |*x| x.first } }
      call("minmax_by") { |r| r.minmax_by() { |*x| x.first } }
      call("none?") { |r| r.none?() { |*x| x.first } }
      call("one?") { |r| r.one?() { |*x| x.first } }
      call("partition") { |r| r.partition() { |*x| x.first } }
      call("reduce") { |r| r.reduce() { |*x| x.first } }
      call("reject") { |r| r.reject() { |*x| x.first } }
      call("reject!") { |r| r.reject!() { |*x| x.first } }
      call("replace") { |r| r.replace([1, 2]) { |*x| x.first } }
      call("reset") { |r| r.reset() { |*x| x.first } }
      call("reverse_each") { |r| r.reverse_each() { |*x| x.first } }
      call("select") { |r| r.select() { |*x| x.first } }
      call("select!") { |r| r.select!() { |*x| x.first } }
      call("size") { |r| r.size() { |*x| x.first } }
      call("slice_after") { |r| r.slice_after() { |*x| x.first } }
      call("slice_before") { |r| r.slice_before() { |*x| x.first } }
      call("slice_when") { |r| r.slice_when() { |*x| x.first } }
      call("sort") { |r| r.sort() { |*x| x.first } }
      call("sort_by") { |r| r.sort_by() { |*x| x.first } }
      call("subtract") { |r| r.subtract([1, 2]) { |*x| x.first } }
      call("sum") { |r| r.sum() { |*x| x.first } }
      call("take") { |r| r.take(1) { |*x| x.first } }
      call("take_while") { |r| r.take_while() { |*x| x.first } }
      call("tally") { |r| r.tally() { |*x| x.first } }
      call("to_a") { |r| r.to_a() { |*x| x.first } }
      call("to_s") { |r| r.to_s() { |*x| x.first } }
      call("to_set") { |r| r.to_set() { |*x| x.first } }
      call("union") { |r| r.union([1, 2]) { |*x| x.first } }
      call("uniq") { |r| r.uniq() { |*x| x.first } }
      call("zip") { |r| r.zip() { |*x| x.first } }
      call("|") { |r| r.__send__(:|, [1, 2]) { |*x| x.first } }

    RUBY

    _(result).must_answer <<~'OUT'
      &: &->include? &->add &->include? &->add
      +: +->initialize_copy +->merge merge->add merge->add
      -: -->initialize_copy -->subtract subtract->delete subtract->delete
      ^: ^->merge merge->add merge->add ^->each each->delete? delete?->include? delete?->delete each->delete? delete?->include? delete?->delete each->delete? delete?->include? each->add
      add?: add?->include?
      all?: all?->each
      any?: any?->each
      classify: classify->each each->add each->add each->add
      collect: collect->each
      collect!: collect!->each each-><< each-><< each-><< collect!->replace
      collect_concat: collect_concat->each
      compact: compact->each
      count: count->each
      delete?: delete?->include? delete?->delete
      delete_if: delete_if->select select->each delete_if->delete delete_if->delete delete_if->delete
      detect: detect->each
      difference: difference->initialize_copy difference->subtract subtract->delete subtract->delete
      disjoint?: disjoint?->intersect? intersect?->===
      divide: divide->hash divide->hash divide->hash
      drop: drop->each
      drop_while: drop_while->each
      each_cons: each_cons->size each_cons->each
      each_entry: each_entry->each
      each_slice: each_slice->size each_slice->each
      each_with_index: each_with_index->each
      each_with_object: each_with_object->each
      entries: entries->each
      filter: filter->each
      filter!: filter!->size filter!->keep_if keep_if->reject reject->each filter!->size
      filter_map: filter_map->each
      find: find->each
      find_all: find_all->each
      find_index: find_index->each
      first: first->each
      flat_map: flat_map->each
      flatten: flatten->each each->add each->add each->add
      flatten!: flatten!->any? any?->each
      grep: grep->each
      grep_v: grep_v->each
      group_by: group_by->each
      inject: inject->each
      inspect: inspect->to_a
      intersect?: intersect?->===
      intersection: intersection->include? intersection->add intersection->include? intersection->add
      join: join->to_a
      keep_if: keep_if->reject reject->each
      map: map->each
      map!: map!->each each-><< each-><< each-><< map!->replace
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
      reject!: reject!->size reject!->delete_if delete_if->select select->each delete_if->delete delete_if->delete delete_if->delete reject!->size
      replace: replace->clear replace->merge merge->add merge->add
      reverse_each: reverse_each->each
      select: select->each
      select!: select!->size select!->keep_if keep_if->reject reject->each select!->size
      sort: sort->each
      sort_by: sort_by->each
      subtract: subtract->delete subtract->delete
      sum: sum->each
      take: take->each
      take_while: take_while->each
      tally: tally->each
      to_s: to_s->to_a
      to_set: to_set->each_entry each_entry->each
      union: union->initialize_copy union->merge merge->add merge->add
      uniq: uniq->each
      zip: zip->each
      |: |->initialize_copy |->merge merge->add merge->add
    OUT
  end

  it "to set forms" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Enumerable#to_set does not apply the block form, so the untransformed
      # elements land in the set.
      #
      require 'set'
      p([1, 2].to_set.to_set.to_a)
      s = [1, 2].to_set
      p s.to_set.to_a
      p [3, 4].to_set { |x| x * 2 }.to_a rescue p $!.class
      t = Set[1,2]
      p t.to_set.equal?(t)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2]
      [6, 8]
      true
    OUT
  end

  it "universal reflection and to set" do
    result = zr(<<~'RUBY')
      class Point
        def initialize(x, y)
          @x = x
          @y = y
        end
      end
      pt = Point.new(3, 4)
      p pt.instance_variables
      p pt.instance_variable_set(:@x, 99)
      p pt.instance_variable_get(:@x)
      p pt.instance_variable_defined?(:@y)
      p pt.instance_variable_defined?(:@z)
      p 42.instance_variables
      p 42.singleton_methods
      p 42.respond_to?(:instance_variable_get)
      p 42.send(:instance_variables)
      p [1, 2, 2, 3].to_set
      p (1..3).to_set
      p({ a: 1, b: 2 }.to_set.size)
      p(/x/.timeout)
      p Regexp.timeout
    RUBY

    _(result).must_answer <<~'OUT'
      [:@x, :@y]
      99
      99
      true
      false
      []
      []
      true
      []
      Set[1, 2, 3]
      Set[1, 2, 3]
      2
      nil
      nil
    OUT
  end

  it "user to set not rewritten" do
    result = zr(<<~'RUBY')
      # `enum.to_set` desugars to `Set.new(enum.to_a)`, but a class that defines its
      # OWN to_set has to keep it. The rewrite used to run before class collection,
      # so it could not tell, and rewrote every to_set in the program: a method
      # returning a Hash of pending writes became a Set, and the error landed on
      # whatever the real return type supported, several lines below the call.
      require "set"

      class Jar
        def initialize
          @out = {}
        end
        def []=(k, v)
          @out[k] = v
          v
        end
        def to_set          # NOT Enumerable#to_set
          @out
        end
      end

      jar = Jar.new
      jar["a"] = "1"
      jar["b"] = "2"
      h = jar.to_set
      p h.keys
      p h["b"]
      p h.class.to_s

      # ... while a real Enumerable receiver in the SAME program still desugars
      s = [3, 1, 3, 2].to_set
      p s.class.to_s
      p s.size
      p s.include?(3)
      p (1..4).to_set.size
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      "2"
      "Hash"
      "Set"
      3
      true
      4
    OUT
  end
end
