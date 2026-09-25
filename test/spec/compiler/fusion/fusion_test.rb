# frozen_string_literal: true

require "spec_helper"

describe "Fusion programs" do
  it "array flatten typed elements" do
    result = zr(<<~'RUBY')
      # Array#flatten on a typed-array-of-typed-array concatenates the inner
      # arrays into one flat typed array, for Integer, String and Float elements
      # (the pr_geohash gem's neighbors does map{...}.flatten over string cells).
      ints = [[1, 2], [3, 4]]
      p ints.flatten
      puts ints.flatten.length

      strs = [["a", "b"], ["c", "d"]]
      p strs.flatten
      puts strs.flatten.length

      floats = [[1.0, 2.0], [3.5, 4.5]]
      p floats.flatten
      puts floats.flatten.length

      # Uneven inner lengths and an empty inner array.
      mixed = [["x"], [], ["y", "z"]]
      p mixed.flatten
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      4
      ["a", "b", "c", "d"]
      4
      [1.0, 2.0, 3.5, 4.5]
      4
      ["x", "y", "z"]
    OUT
  end

  it "a splice of negative length raises IndexError" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # negative length raises IndexError
      begin
        a = [1, 2, 3, 4]
        a[1, -2] = [9]
      rescue IndexError => e
        puts "#{e.class}: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      IndexError: negative length (-2)
    OUT
  end

  it "the start and length scalar form raises IndexError for a negative length too" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # negative length via the start,len scalar form too
      begin
        a = [1, 2, 3]
        a[0, -1] = 5
      rescue IndexError => e
        puts "#{e.class}: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      IndexError: negative length (-1)
    OUT
  end

  it "a splice into a frozen array raises FrozenError" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # splicing into a frozen array raises FrozenError
      begin
        a = [1, 2, 3].freeze
        a[0, 1] = [9]
      rescue FrozenError => e
        puts e.class
      end

    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
    OUT
  end

  it "a splice starting before the front raises IndexError" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # a start before the front raises IndexError
      begin
        a = [1, 2, 3]
        a[-9, 1] = [0]
      rescue IndexError => e
        puts e.class
      end

    RUBY

    _(result).must_answer <<~'OUT'
      IndexError
    OUT
  end

  it "a splice through a poly receiver raises the same exceptions" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # poly receiver (an element that is a typed array at runtime): same exceptions.
      # negative length
      begin
        a = [[1, 2, 3], "x"]
        a[0][1, -1] = [9]
      rescue IndexError => e
        puts "#{e.class}: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      IndexError: negative length (-1)
    OUT
  end

  it "a poly receiver raises for a start before the front as well" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # start before the front
      begin
        a = [[1, 2, 3], "x"]
        a[0][-5, 1] = [9]
      rescue IndexError => e
        puts "#{e.class}: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      IndexError: index -5 too small for array; minimum: -3
    OUT
  end

  it "a range whose begin is before the front raises RangeError, not IndexError" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # a range whose begin is before the front raises RangeError (not IndexError)
      begin
        a = [[1, 2, 3], "x"]
        a[0][-10..1] = [9]
      rescue RangeError => e
        puts "#{e.class}: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      RangeError: -10..1 out of range
    OUT
  end

  it "an endless range whose begin is before the front raises RangeError too" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # an endless range whose begin is before the front raises RangeError too
      begin
        a = [[1, 2, 3], "x"]
        a[0][-10..] = [9]
      rescue RangeError => e
        puts "#{e.class}: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      RangeError: -10.. out of range
    OUT
  end

  it "promoting a frozen typed array to poly still raises FrozenError" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # promoting a frozen typed array still raises FrozenError
      begin
        a = [[1, 2, 3].freeze, "x"]
        a[0][1, 1] = ["s"]
      rescue FrozenError => e
        puts e.class
      end

    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
    OUT
  end

  it "frozen is reported before a negative length" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # check ORDER matches CRuby: frozen wins over negative length...
      begin
        a = [1, 2, 3].freeze
        a[1, -1] = [9]
      rescue => e
        puts e.class
      end

    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
    OUT
  end

  it "frozen is reported before a start that is too small" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # ...over a too-small index...
      begin
        a = [1, 2, 3].freeze
        a[-9, 1] = [9]
      rescue => e
        puts e.class
      end

    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
    OUT
  end

  it "frozen is reported before a range that is out of its receiver" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # ...and over an out-of-range range (typed receiver)
      begin
        a = [1, 2, 3].freeze
        a[-9..0] = [1]
      rescue => e
        puts e.class
      end

    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
    OUT
  end

  it "the poly runtime path reports the same checks in the same order" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # the same order through the poly runtime path
      begin
        a = [[1, 2, 3].freeze, "x"]
        a[0][1, -1] = [9]
      rescue => e
        puts e.class
      end
      begin
        a = [[1, 2, 3].freeze, "x"]
        a[0][-10..1] = [9]
      rescue => e
        puts e.class
      end

    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
      FrozenError
    OUT
  end

  it "a negative length is reported before a start that is too small" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # negative length is reported before a too-small index (CRuby checks length first)
      begin
        a = [1, 2, 3]
        a[-9, -1] = [5]
      rescue IndexError => e
        puts "#{e.class}: #{e.message}"
      end
      begin
        y = [1, "x"]
        y[-9, -1] = [5]
      rescue IndexError => e
        puts "#{e.class}: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      IndexError: negative length (-1)
      IndexError: negative length (-1)
    OUT
  end

  it "a typed receiver raises RangeError for a range beginning before the front" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # a range beginning before -len raises RangeError on a typed receiver too
      begin
        a = [1, 2, 3]
        a[-9..0] = [1]
      rescue RangeError => e
        puts "#{e.class}: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      RangeError: -9..0 out of range
    OUT
  end

  it "a typed receiver splices a beginless and an endless range" do
    result = zr(<<~'RUBY')
      # Array#[]= splice exceptional cases: exact CRuby exception class + message.

      # typed receivers handle beginless / endless range splices
      b = [1, 2, 3]
      b[..1] = [9]
      p b
      b = [1, 2, 3]
      b[1..] = [8]
      p b
    RUBY

    _(result).must_answer <<~'OUT'
      [9, 3]
      [1, 8]
    OUT
  end

  it "array splice kinds" do
    result = zr(<<~'RUBY')
      # Array#[start, len] = replacement across element kinds: the equal-length
      # overwrite (the fast path) and the growing / shrinking / clamped forms.
      a = [1, 2, 3, 4, 5]
      a[1, 3] = [9, 9, 9]
      p a
      a[0, 2] = [7]
      p a
      a[2, 0] = [5, 5]
      p a
      b = ["x", "y", "z"]
      b[1, 2] = ["p", "q"]
      p b
      c = [1.5, 2.5, 3.5]
      c[0, 2] = [9.5, 8.5]
      p c
      d = [1, "a", :b]
      d[1, 1] = ["z"]
      p d
      e = [1, 2, 3]
      e[1, 5] = [8]
      p e
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 9, 9, 9, 5]
      [7, 9, 9, 5]
      [7, 9, 5, 5, 9, 5]
      ["x", "p", "q"]
      [9.5, 8.5, 3.5]
      [1, "z", :b]
      [1, 8]
    OUT
  end

  it "array splice to ary" do
    result = zr(<<~'RUBY')
      # A splice RHS that defines to_ary is coerced through it (CRuby rb_ary_to_ary):
      # the coercion's elements are spliced, while the expression value stays the
      # object as written. An object without to_ary inserts as a single element.
      class IntPair
        def initialize(a, b); @a = a; @b = b; end
        def to_ary; [@a, @b]; end
      end

      class Tagged
        def initialize(v); @v = v; end
        def to_ary; ["<", @v, ">"]; end
      end

      class Opaque
        def initialize(v); @v = v; end
      end

      # typed receiver, to_ary elements match the element kind: stays typed
      a = [1, 2, 3]
      a[1, 1] = IntPair.new(7, 8)
      p a

      # range form
      b = [1, 2, 3, 4]
      b[1..2] = IntPair.new(9, 9)
      p b

      # mixed to_ary elements widen the receiver, then splice faithfully
      c = [1, 2, 3]
      c[1, 1] = Tagged.new(5)
      p c

      # an object without to_ary inserts as one element (widening the receiver)
      d = [1, 2, 3]
      d[0, 2] = Opaque.new(1)
      p d.length
      p d[1]

      # a poly receiver (array element that is an array at runtime) coerces too
      e = [[1, 2, 3], "x"]
      e[0][1, 1] = IntPair.new(4, 5)
      p e[0]

      # value position: the expression value is the object itself, not the coercion
      f = [1, 2, 3]
      r = (f[1, 1] = IntPair.new(6, 6))
      p r.is_a?(IntPair)
      p f
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 7, 8, 3]
      [1, 9, 9, 4]
      [1, "<", 5, ">", 3]
      2
      3
      [1, 4, 5, 3]
      true
      [1, 6, 6, 3]
    OUT
  end

  it "array transpose typed elements" do
    result = zr(<<~'RUBY')
      # Array#transpose on a nested array swaps rows and columns, for Integer,
      # String and Float elements (pr_geohash's GeoHash.decode ends with
      # latlng.transpose over floats).
      ints = [[1, 2, 3], [4, 5, 6]]
      p ints.transpose

      floats = [[1.0, 2.0], [3.0, 4.0]]
      p floats.transpose
      puts floats.transpose[0][0]
      puts floats.transpose[1][1]

      strs = [["a", "b"], ["c", "d"]]
      p strs.transpose

      # Square and single-row matrices.
      sq = [[1, 2], [3, 4]]
      p sq.transpose
      one = [["x", "y", "z"]]
      p one.transpose
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 4], [2, 5], [3, 6]]
      [[1.0, 3.0], [2.0, 4.0]]
      1.0
      4.0
      [["a", "c"], ["b", "d"]]
      [[1, 3], [2, 4]]
      [["x"], ["y"], ["z"]]
    OUT
  end

  it "autoload nested in a module eagerly splices the feature file" do
    result = zr(<<~'RUBY', files: beside("autoload_nested/lib/greeter.rb", "autoload_nested/main.rb"))
      # `autoload :Const, "feature"` is treated as a compile-time
      # require -- the loader's eager pre-pass splices the feature file (at any
      # structural nesting) so the constant is defined; the `autoload` call
      # itself is a no-op. Documented divergence from CRuby's laziness (loads at
      # the autoload site, not first access), but observationally identical for
      # a definitional autoloaded file.

      $LOAD_PATH.unshift(File.expand_path("autoload_nested/lib", __dir__))
      require_relative "autoload_nested/main"
    RUBY

    _(result).must_answer "hi bob\n"
  end

  it "case in class check pattern binds and statically narrows to int" do
    result = zr(<<~'RUBY')
      # `Integer => n` both binds `n` AND statically narrows its type for the
      # rest of the arm's body -- `n + 1` should take the native `Int`
      # arithmetic fast path, not a runtime Poly fallback.

      case 5
      in Integer => n
        puts n + 1
      end
    RUBY

    _(result).must_answer "6\n"
  end

  it "case in nested array pattern narrows each element" do
    result = zr(<<~'RUBY')
      case [[1, "a"], [2, "b"]]
      in [[Integer => n1, String => s1], [Integer => n2, String => s2]]
        puts "#{n1}#{s1} #{n2}#{s2}"
      end
    RUBY

    _(result).must_answer "1a 2b\n"
  end

  it "cls method specialization boxer" do
    result = zr(<<~'RUBY')
      class Base
        def self.from_row(row)
          instance = new
          if row.is_a?(CommentRow)
            instance.commenter = row.commenter
          elsif row.is_a?(ArticleRow)
            instance.title = row.title
          end
          instance
        end

        def []=(field, value)
          case field
          when :commenter then @commenter = value
          when :title then @title = value
          when :body then @body = value
          end
        end
      end

      class Comment < Base
        attr_accessor :commenter
        attr_accessor :body
      end

      class Article < Base
        attr_accessor :title
      end

      class CommentRow
        attr_reader :commenter
        def initialize(c); @commenter = c; end
      end

      class ArticleRow
        attr_reader :title
        def initialize(t); @title = t; end
      end

      seed = Comment.new
      seed[:body] = 42
      seed[:commenter] = "x"

      c = Comment.from_row(CommentRow.new("alice"))
      a = Article.from_row(ArticleRow.new("title!"))
      puts c.commenter
      puts a.title
    RUBY

    _(result).must_answer "alice\ntitle!\n"
  end

  it "cmethod transitive specialization" do
    result = zr(<<~'RUBY')
      # A class method called on a subclass must specialize through a non-overriding
      # intermediate, so an implicit-self chain reaching an override resolves to the
      # subclass version, not the abstract base.
      class Base
        def self.table_name
          raise "#{name}.table_name must be overridden"
        end
        def self.adapter_all
          "[" + table_name + "]"
        end
        def self.all
          adapter_all          # transitive: all -> adapter_all -> table_name
        end
        def self.last
          "last-of-" + all     # one more hop
        end
      end
      class Article < Base
        def self.table_name; "articles"; end
      end
      class User < Base
        def self.table_name; "users"; end
      end
      puts Article.last
      puts User.last
      puts Article.all
      puts User.adapter_all

      # the direct (1-hop) case must keep working
      class B2
        def self.label;    raise "abstract"; end
        def self.describe; label; end
      end
      class S2 < B2
        def self.label; "s2-label"; end
      end
      puts S2.describe
    RUBY

    _(result).must_answer <<~'OUT'
      last-of-[articles]
      last-of-[users]
      [articles]
      [users]
      s2-label
    OUT
  end

  it "const recv yield inline" do
    result = zr(<<~'RUBY')
      # A yield-based method called with a block on a constant receiver. The constant
      # holds an instance (not a class name), so the inline path must fall through to
      # instance-method lookup rather than treating it as a class method -- otherwise
      # the call referenced an unemitted function and failed to link.
      class Bag
        def initialize(a)
          @a = a
        end
        def each
          @a.each { |x| yield x }
        end
        def sum_each
          s = 0
          @a.each { |x| s += x }
          s
        end
      end

      NUMS = Bag.new([1, 2, 3])
      NUMS.each { |x| print x, " " }
      puts
      p NUMS.sum_each        # 6

      PAIRS = Bag.new([[1, 2], [3, 4]])
      PAIRS.each do |pair|
        pair.each { |y| print y, " " }
      end
      puts
    RUBY

    _(result).must_answer "1 2 3 \n6\n1 2 3 4 \n"
  end

  it "container fast path argument may reassign its receiver" do
    result = zr(<<~'RUBY')
      # The container fast paths (`a << x`, `a[i] = v`, `h[k] = v`, `a.length`,
      # `a.pop`, `h[k]`) BORROW a plain hoisted receiver instead of cloning it --
      # but the borrow is live while the arguments evaluate, and an argument that
      # reassigns the receiver's own local is perfectly good Ruby. Each line below
      # does exactly that, and each must answer what CRuby answers rather than
      # failing to compile with E0506.
      a = [1]
      a << (a = [9]; 2)
      p a
      b = [1, 2]
      b[0] = (b = [7, 8]; 5)
      p b
      h = { x: 1 }
      h[:y] = (h = { z: 3 }; 4)
      p h
      c = [1, 2, 3]
      p c.length + (c = []; 0)
      d = [5]
      p d[(d = [6, 7]; 0)]
      e = [1]
      p e.pop + (e = [2]; 0)
      f = { a: 1 }
      p f[(f = { b: 2 }; :a)].inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [9]
      [7, 8]
      {z: 3}
      3
      5
      1
      "1"
    OUT
  end

  it "data define inline receiver" do
    result = zr(<<~'RUBY')
      a = Data.define(:x, :y).new(1, 2)
      p a
      p a.x
      p a.y
      p(Data.define(:x, :y).class)
      p(Data.define(:x, :y).members)
      b = Struct.new(:a, :b).new(3, 4)
      p b.a
      p b.b
      p(Struct.new(:m, :n).members)
      # named form still works
      Pt = Data.define(:lat, :lng)
      p Pt.new(10, 20)
    RUBY

    _(result).must_answer <<~'OUT'
      #<data x=1, y=2>
      1
      2
      Class
      [:x, :y]
      3
      4
      [:m, :n]
      #<data Pt lat=10, lng=20>
    OUT
  end

  it "empty hash int key narrowing" do
    result = zr(<<~'RUBY')
      # An empty {} local written with Integer keys must settle on an int-keyed
      # hash variant even when the first value is an empty container literal
      # (such as `[]`).
      class G
        def self.bucket(ids)
          grouped = {}
          ids.each do |k|
            grouped[k] = [] if grouped[k].nil?
            grouped[k] << k
          end
          grouped.length
        end
      end

      puts G.bucket([1, 2, 2, 3])
      h = {}
      h[5] = []
      h[5] << "a"
      h[6] = []
      p h.length
      p h[5]
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      ["a"]
    OUT
  end

  it "eval of a literal string runs inline" do
    result = zr(<<~'RUBY')
      puts eval("1 + 2")
    RUBY

    _(result).must_answer "3\n"
  end

  it "exception objects expose their typed introspection accessors" do
    result = zr(<<~'RUBY')
      # KeyError#key, NameError#name/#receiver, NoMethodError#name/#args/#receiver,
      # UncaughtThrowError#tag/#value, and Exception#detailed_message -- populated
      # both at the raise site (a failed fetch / missing method / const miss /
      # uncaught throw) and from an explicit constructor. Byte-verified against
      # ruby 4.0.6.

      begin; {}.fetch(:sym); rescue KeyError => e; p e.key; end
      begin; {}.fetch(42); rescue KeyError => e; p e.key; end
      e = NoMethodError.new("msg", :meth, [1, 2]); p e.args; p e.name; p e.message
      p NoMethodError.new("m2", :other).args
      p NameError.new("nm", :sym).name
      p NameError.new("nm").name
      begin; "s".no_such; rescue NoMethodError => e; p e.receiver; p e.name; p e.args; end
      begin; nil.foo(1); rescue NoMethodError => n; p n.name; end
      begin; TypeError.new("m").name; rescue NoMethodError => e; puts e.class; end
      begin; Object.const_get(:Nope); rescue NameError => e; p e.name; p e.receiver; end
      begin; Nonexistent; rescue NameError => e; p e.name; end
      v = begin; throw :y; rescue UncaughtThrowError => e; e.tag; end; p v
      w = begin; throw :z, 7; rescue UncaughtThrowError => e; e.value; end; p w
      begin; raise "boom"; rescue => e; p e.detailed_message; end
      begin; raise RuntimeError; rescue => e; p e.detailed_message; end
    RUBY

    _(result).must_answer <<~'OUT'
      :sym
      42
      [1, 2]
      :meth
      "msg"
      nil
      :sym
      nil
      "s"
      :no_such
      []
      :foo
      NoMethodError
      :Nope
      Object
      :Nonexistent
      :y
      7
      "boom (RuntimeError)"
      "RuntimeError (RuntimeError)"
    OUT
  end

  it "exception typed accessors" do
    result = zr(<<~'RUBY')
      # Typed exception accessors: NameError#name/#receiver, NoMethodError#args,
      # KeyError#key/#receiver (raised and keyword-constructed), UncaughtThrowError
      # #tag/#value, SystemExit#status/#success?, and Exception#detailed_message.
      begin; Object.const_get(:Nope); rescue NameError => e; p e.name; p e.receiver; end
      begin; "s".no_such(1, 2); rescue NoMethodError => e; p e.name; p e.args; p e.receiver; end
      begin; {"a" => 1}.fetch("z"); rescue KeyError => e; p e.key; p e.receiver; end
      ke = KeyError.new("m", key: :k, receiver: {1 => 2}); p [ke.key, ke.receiver]
      v = begin; throw :t, 42; rescue UncaughtThrowError => e; [e.tag, e.value]; end; p v
      se = SystemExit.new(3, "done"); p [se.status, se.success?, se.message]
      p SystemExit.new.success?
      begin; raise "boom"; rescue => e; p e.detailed_message; end
    RUBY

    _(result).must_answer <<~'OUT'
      :Nope
      Object
      :no_such
      [1, 2]
      "s"
      "z"
      {"a" => 1}
      [:k, {1 => 2}]
      [:t, 42]
      [3, false, "done"]
      true
      "boom (RuntimeError)"
    OUT
  end

  it "freeze and frozen predicate work on a poly typed receiver" do
    result = zr(<<~'RUBY')
      # A method parameter is always generically typed, so `freeze`/`frozen?`
      # take the universal path, not one of the type-gated fast paths.

      class Once
        def run(x)
          x.freeze
          puts x.frozen?
        end
      end
      Once.new.run([1])
      Once.new.run(42)
    RUBY

    _(result).must_answer "true\ntrue\n"
  end

  it "fused accumulator survives break and raise" do
    result = zr(<<~'RUBY')
      # The value-consuming fused kinds keep a heap accumulator (map/select's
      # result array, sum's generic lane, inject's running value) in a slot the
      # epilogue releases. A `break` abandons the half-built accumulator; a
      # raise unwinds past the loop entirely; a site inside an enclosing loop
      # re-enters with the abandoned value still in the slot. Each shape must
      # free exactly once -- the leakcheck leg is the real assertion here.

      arr = [3, 1, 4, 1, 5]

      # break mid-map answers the break value; the half-built array is freed.
      p(arr.map { |e| break :stopped if e == 4; e.to_s })

      # ...and re-entering the same site (an enclosing loop) must release the
      # abandoned accumulator before seeding a fresh one.
      2.times do |i|
        r = arr.map { |e| break :inner if e == 4 && i == 0; e * i }
        p r
      end

      # A raise inside the body unwinds through the landing, which owns the
      # release. The rescue proves the program continues cleanly after.
      begin
        arr.map { |e| raise "boom #{e}" if e == 5; e }
      rescue RuntimeError => ex
        p ex.message
      end

      # sum's generic lane holds a heap accumulator when the fold leaves
      # numbers; a raise from the generic `+` frees it.
      begin
        arr.sum { |e| e == 4 ? :sym : e }
      rescue TypeError => ex
        puts "TypeError from the generic lane"
      end

      # inject's accumulator is replaced every iteration; break abandons the
      # current one.
      p(arr.inject("") { |a, e| break :cut if e == 5; a + e.to_s })

      # select/reject build their answer from re-fetched ORIGINAL elements.
      p(arr.select { |e| break [] if e == 5; e > 2 })
      p(arr.reject { |e| e > 2 })
    RUBY

    _(result).must_answer <<~'OUT'
      :stopped
      :inner
      [3, 1, 4, 1, 5]
      "boom 5"
      TypeError from the generic lane
      :cut
      []
      [1, 1]
    OUT
  end

  it "fused find answers the original element" do
    result = zr(<<~'RUBY')
      arr = [1, 2, 3, 4]

      # The element that surfaces is the one the array held, not whatever the body
      # left in the param -- the same rule `select`/`reject` obey.
      p arr.find { |x| y = x; x = 99; y > 2 }
      p arr.detect { |x| x == 1 }
      p arr.find { |x| false }
      p [].find { true }

      # The block is not called again once one answers.
      seen = []
      p arr.find { |x| seen << x; x > 2 }
      p seen

      # `break` overrides the whole call; `next v` supplies the iteration's value.
      p(arr.find { |x| break :broke })
      p(arr.find { |x| next x > 3 })

      # A live view: what the body appends is walked too.
      live = [1, 2, 3]
      walked = []
      p live.find { |x| walked << x; live << 9 if x == 1; x == 9 }
      p walked

      # An `ifnone` argument is a different method shape and takes the dynamic row.
      p arr.find(proc { :nope }) { |x| false }

      # A nested escaping block capturing the param keeps a per-iteration binding.
      store = []
      p arr.find { |x| store << -> { x }; x == 2 }
      p store.map(&:call)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      1
      nil
      nil
      3
      [1, 2, 3]
      :broke
      4
      9
      [1, 2, 3, 9]
      :nope
      2
      [1, 2]
    OUT
  end

  it "fused predicate stops at the first answer" do
    result = zr(<<~'RUBY')
      arr = [1, 2, 3, 4]

      p arr.all? { |x| x > 0 }
      p arr.all? { |x| x > 2 }
      p arr.any? { |x| x > 3 }
      p arr.any? { |x| x > 9 }
      p arr.none? { |x| x > 9 }
      p arr.none? { |x| x > 3 }

      # An empty receiver never calls the block, and each kind has its own answer.
      p [].all? { false }
      p [].any? { true }
      p [].none? { true }

      # Truthiness, not equality: `nil` is falsy and any object is truthy.
      p arr.all? { |x| x }
      p arr.any? { |x| nil }
      p arr.none? { |x| nil }

      # How many elements each one actually reaches.
      c = 0
      p arr.any? { |x| c += 1; x >= 2 }
      p c
      c = 0
      p arr.all? { |x| c += 1; x <= 2 }
      p c
      c = 0
      p arr.none? { |x| c += 1; x >= 3 }
      p c

      # `count` counts the truthy block values, and its argument form is a
      # different method shape that takes the dynamic row.
      p arr.count { |x| x > 2 }
      p arr.count { |x| nil }
      p [].count { true }
      p arr.count(2)
      p arr.count

      # A pattern argument is also a different shape.
      p arr.any?(Integer)
      p arr.all?(Integer)
      p arr.none?(String)

      # The block sees a live view.
      live = [1, 2, 3]
      p live.count { |x| live.pop; true }
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      true
      false
      true
      false
      true
      true
      false
      true
      true
      2
      false
      3
      false
      3
      2
      0
      0
      1
      4
      true
      true
      true
      2
    OUT
  end

  it "implicit alloc site holder specialization" do
    result = zr(<<~'RUBY')
      RowA = Struct.new(:id, :name)
      RowB = Struct.new(:id, :label)

      class Holder
        def initialize(record)
          @record = record
        end

        def record
          @record
        end
      end

      holder_a = Holder.new(RowA.new(1, "alpha"))
      holder_b = Holder.new(RowB.new(2, "beta"))

      puts holder_a.record.name
      puts holder_b.record.label
      puts holder_a.record.id + holder_b.record.id
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      beta
      3
    OUT
  end

  it "implicit alloc site ivar helper return specialization" do
    result = zr(<<~'RUBY')
      RowA = Struct.new(:id, :name)
      RowB = Struct.new(:id, :row_a_id, :label)

      class HelperStore
        def initialize
          @records = []
          @next_id = 1
        end

        def insert(record)
          record.id = @next_id
          @next_id = @next_id + 1
          @records << record
          record
        end
      end

      class AStore
        def initialize
          @helper = HelperStore.new
        end

        def add(name)
          @helper.insert(RowA.new(0, name))
        end
      end

      class BStore
        def initialize
          @helper = HelperStore.new
        end

        def add(row_a_id, label)
          @helper.insert(RowB.new(0, row_a_id, label))
        end
      end

      a_store = AStore.new
      b_store = BStore.new

      row_a = a_store.add("alpha")
      row_b = b_store.add(row_a.id, "beta")

      puts row_a.name
      puts row_b.label
      puts row_a.id + row_b.row_a_id
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      beta
      2
    OUT
  end

  it "implicit alloc site store specialization" do
    result = zr(<<~'RUBY')
      RowA = Struct.new(:id, :name)
      RowB = Struct.new(:id, :label)

      class Store
        def initialize
          @records = []
        end

        def add(record)
          @records << record
          record
        end

        def first
          @records[0]
        end
      end

      rows_a = Store.new
      rows_b = Store.new

      rows_a.add(RowA.new(1, "alpha"))
      rows_b.add(RowB.new(2, "beta"))

      puts rows_a.first.name
      puts rows_b.first.label
      puts rows_a.add(RowA.new(3, "next")).id
      puts rows_b.add(RowB.new(4, "again")).id
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      beta
      3
      4
    OUT
  end

  it "implicit conversions are duck typed through to ary to hash and to proc" do
    result = zr(<<~'RUBY')
      class Pair
        def initialize(a, b)
          @a = a
          @b = b
        end
        def to_ary = [@a, @b]
      end
      class Opts
        def to_hash = { a: 1, b: 2 }
      end
      class Dbl
        def to_proc = ->(x) { x * 2 }
      end

      # to_ary: block auto-splat, multi-assign, and a splice RHS.
      def one(v)
        yield v
      end
      p(one(Pair.new(1, 2)) { |a, b| [a, b] })
      x, y = Pair.new(3, 4)
      p [x, y]
      arr = [1, 2, 3]
      arr[1, 1] = Pair.new(7, 8)
      p arr

      # to_hash: a `**` splat.
      def take(a:, b:) = [a, b]
      p take(**Opts.new)

      # to_proc: an `&` block argument.
      p [1, 2].map(&Dbl.new)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [3, 4]
      [1, 7, 8, 3]
      [1, 2]
      [2, 4]
    OUT
  end

  it "inherited factory poly param narrow attr" do
    result = zr(<<~'RUBY')
      # An inherited factory (`Base.create`) forwards `new(attrs)` with a Hash, so
      # the subclass ctor parameter gets values of more than one type across its
      # call sites. The inherited attr_accessor field `id` holds an Integer (from
      # `@id = 0`). The `self.id = id` setter writes that parameter into the field.
      class Base
        attr_accessor :id

        def initialize
          @id = 0
        end

        def self.create(attrs = {})
          new(attrs)
        end
      end

      class Article < Base
        def initialize(id = 0)
          self.id = id
        end
      end

      puts Article.new(7).id
    RUBY

    _(result).must_answer "7\n"
  end

  it "inline struct superclass loses its native rows" do
    result = zr(<<~'RUBY')
      # `class T < Struct.new(:b)` -- an INLINE anonymous struct as the superclass.
      # The class is minted at RUNTIME, and a runtime class's dispatch walk probed
      # each ancestor's overlay, registry and value rows but never its NATIVE table,
      # which is the only place a builtin's own rows live. So a `module Enumerable`
      # reopen answered `size` from two positions FARTHER out than `Struct#size`.
      #
      # The named spelling (`S = Struct.new(:b); class T < S; end`) compiles to a
      # real class and never took that walk.
      module Enumerable
        def size
          :enum_size
        end

        def only_enum
          :enum_only
        end
      end

      class T < Struct.new(:b)
      end

      p T.new(2).size
      p T.new(2).only_enum
      p T.instance_method(:size).owner.to_s
      p T.ancestors.map { |c| c.name.inspect }

      S = Struct.new(:c)
      class U < S
      end
      p U.new(3).size

      # A runtime class's OWN definition still wins over the nearer builtin row.
      K = Class.new(Struct.new(:d)) do
        def size = :own
      end
      p K.new(1).size

      # A runtime subclass of a value-backed builtin reaches its rows THROUGH the
      # payload, so each builtin method works on an instance of it.
      A2 = Class.new(Array)
      p [A2.new([1, 2, 3]).size, A2.new([1, 2]).first, A2.new([1]).class == A2]
      S3 = Class.new(String)
      p [S3.new("abc").length, S3.new("abc").upcase]
      H2 = Class.new(Hash)
      p H2.new.size

      # ...and a module included at RUNTIME still layers above them.
      module Louder
        def upcase = :louder
      end
      S4 = Class.new(String)
      S4.include(Louder)
      p S4.new("x").upcase

      # `super` from a runtime class reaches the builtin row.
      S5 = Class.new(String) do
        def upcase = "<#{super}>"
      end
      p S5.new("hi").upcase
    RUBY

    _(result).must_answer <<~'OUT'
      1
      :enum_only
      "Struct"
      ["\"T\"", "nil", "\"Struct\"", "\"Enumerable\"", "\"Object\"", "\"Kernel\"", "\"BasicObject\""]
      1
      :own
      [3, 1, true]
      [3, "ABC"]
      0
      :louder
      "<HI>"
    OUT
  end

  it "inlined param cell binding" do
    result = zr(<<~'RUBY')
      # A parameter of an inlined yielding method that an inner block CAPTURES. The
      # block and the method body read and write the same variable.
      #
      # Two receivers so the call cannot fold to one target: the block that assigns
      # the captured parameter is inlined once per candidate.
      class Conn
        def run(x)
          yield x
        end
      end

      class Other
        def run(x)
          yield x + 1
        end
      end

      class Fetch
        def request(url, obj)
          obj.run(url) do |r|
            url = url + r
          end
          yield url
        end
      end

      p Fetch.new.request(1, Conn.new) { |v| v }
      p Fetch.new.request(1, Other.new) { |v| v }

      # The same shape where the captured parameter is a String rather than an int,
      # so the cell carries a pointer.
      class Joiner
        def run(s)
          yield s
        end
      end

      class Build
        def make(head, obj)
          obj.run("-") do |sep|
            head = head + sep
          end
          head
        end
      end
      p Build.new.make("a", Joiner.new)

      # A parameter captured by a proc that outlives the call: the cell has to be the
      # storage both sides see.
      class Keep
        def run(n)
          yield n
        end
      end

      class Hold
        def grab(seed, obj)
          box = nil
          obj.run(seed) do |k|
            seed = seed + k
            box = proc { seed }
          end
          [seed, box.call]
        end
      end
      p Hold.new.grab(2, Keep.new)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      3
      "a-"
      [4, 4]
    OUT
  end

  it "integer bit predicates and string bytesplice" do
    result = zr(<<~'RUBY')
      p 0b1010.allbits?(0b0010)
      p 0b1010.allbits?(0b0110)
      p 0b1010.anybits?(0b0110)
      p 0b1010.nobits?(0b0101)
      s = "hello"; s.bytesplice(0, 2, "XY"); p s
      t = "hello"; t.bytesplice(1..2, "__"); p t
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      "XYllo"
      "h__lo"
    OUT
  end

  it "interp local narrowed key" do
    result = zr(<<~'RUBY')
      module Db
        def self.prepare(sql)
        end
        def self.column_value(stmt, i)
        end
        def self.column_count(stmt)
        end
        def self.column_name(stmt, i)
        end
      end
      module ActiveRecord
        class << self
          attr_accessor :adapter
          def self.find_by!(conditions)
            ActiveRecord.adapter.where(table_name, conditions.to_h).map { |row| instantiate(row) }
          end
        end
      end
      module ActiveRecord
        class Relation
          def where(condition)
          end
          def to_a
            rows = ActiveRecord.adapter.select_rows(to_sql)
          end
          def map
            to_a.map { |x| yield x }
          end
          def update_all(updates)
            set_sql = if updates.is_a?(Hash)
            end
          end
          def to_sql
          end
        end
      end
      module SqliteAdapter
        def self.where(table, conditions)
          sql = "SELECT * FROM #{table}"
          sql += " WHERE #{build_where(conditions)}" unless conditions.empty?
          sql
        end
        def self.select_rows(sql)
          stmt = Db.prepare(sql)
          rows = []
          ncols = Db.column_count(stmt)
          names = []
          i = 0
          while i < ncols
            names.push(Db.column_name(stmt, i))
            row = {}
            while i < ncols
              row[names[i]] = Db.column_value(stmt, i)
            end
            rows << row
          end
          rows
        end
        def self.build_where(conditions)
          conditions.map { |k, v| "#{k} = #{escape_value(v)}" }.join(" AND ")
        end
        def self.escape_value(v)
        end
      end
      ActiveRecord.adapter = SqliteAdapter
      class QueryCountTest
        def test_articles_index_is_two_queries_not_n_plus_one
          per_article = {}
          unless per_article.empty?
          end
        end
        def test_rechaining_a_loaded_relation_requeries
          rel = ActiveRecord::Relation.new
          ids = [1]
          rel.where("id = #{ids[0]}")
        end
      end
      QueryCountTest.new.test_rechaining_a_loaded_relation_requeries
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "isa narrow" do
    result = zr(<<~'RUBY')
      # `if v.is_a?(K)` narrows a poly v to K's concrete type inside the then-branch,
      # so a method only SOME union members define dispatches correctly instead of
      # aborting "undefined method 'M' for poly".
      #
      # A poly parameter unioned across Array | String | Integer could not call
      # `v.to_a` (Array-only) -- it dispatched over the whole union and aborted at
      # runtime. Inside `if v.is_a?(Array)` the runtime type is proven, so reads of v
      # narrow to a concrete type (unboxed at the read site, the machinery the nil
      # guards already use). Array narrows to a poly array via a runtime normalizer,
      # since a boxed array can be any element-typed representation.

      # 1. Array-only method under an is_a?(Array) guard (gap 12).
      def f(v)
        return v.to_a if v.is_a?(Array)
        v.to_s
      end
      p f([1, 2])                 #=> [1, 2]
      p f("x")                    #=> "x"
      p f(7)                      #=> "7"

      # 2. is_a?/elsif chain, each arm a different type (gap 3 shape).
      def g(v)
        if v.is_a?(String)
          v.upcase
        elsif v.is_a?(Array)
          v.map { |e| e * 2 }
        else
          v.to_s
        end
      end
      p g("hi")                   #=> "HI"
      p g([1, 2])                 #=> [2, 4]
      p g(9)                      #=> "9"

      # 3. Recursive, multi-type return (the original gap 3 program).
      def enc(v)
        if v.is_a?(String)
          out = "\""
          v.each_char { |c| out = out + c }
          out + "\""
        elsif v.is_a?(Array)
          "[" + v.map { |e| enc(e) }.join(",") + "]"
        else
          v.to_s
        end
      end
      p enc(["ab", "cd"])         #=> "[\"ab\",\"cd\"]"

      # 4. Integer / Float narrowing to primitive ops.
      def h(v)
        v.is_a?(Integer) ? v * 10 : v.to_s
      end
      p h(5)                      #=> 50
      p h("q")                    #=> "q"
      def flt(v)
        v.is_a?(Float) ? v + 1.0 : v.to_s
      end
      p flt(2.5)                  #=> 3.5
      p flt("z")                  #=> "z"

      # 5. Array narrowing works across element representations.
      def sa(v)
        v.is_a?(Array) ? v.first : nil
      end
      p sa(["a", "b"])            #=> "a"
      p sa([1.5, 2.5])            #=> 1.5

      # 6. kind_of? is an alias.
      def k(v)
        v.kind_of?(String) ? v.length : -1
      end
      p k("hello")                #=> 5
      p k(42)                     #=> -1

      # 7. Soundness: a write inside the branch disables narrowing (no miscompile).
      def wr(v)
        if v.is_a?(Array)
          v = v.to_a
          v.length
        else
          0
        end
      end
      p wr([1, 2, 3])             #=> 3

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      "x"
      "7"
      "HI"
      [2, 4]
      "9"
      "[\"ab\",\"cd\"]"
      50
      "q"
      3.5
      "z"
      "a"
      1.5
      5
      -1
      3
      done
    OUT
  end

  it "three methods that each build a line and push it keep their own buffers" do
    result = zr(<<~'RUBY')
      class Res
        attr_accessor :cookies
        def initialize
          @cookies = [""]
          @cookies.pop
        end

        def store(name, value)
          line = name + "=" + value
          line << "; HttpOnly"
          @cookies.push(line)
        end

        def set_cookie(name, value)
          line = name + "=" + value
          line << "; Path=/"
          @cookies.push(line)
        end

        def apply_cookie(name, value)
          line = name + "=" + value
          line << "; Secure"
          @cookies.push(line)
        end
      end

      res = Res.new
      res.store("flash", "hello")
      res.set_cookie("sid", "42")
      res.apply_cookie("theme", "dark")
      res.cookies.each { |line| puts "Set-Cookie: " + line }
    RUBY

    _(result).must_answer <<~'OUT'
      Set-Cookie: flash=hello; HttpOnly
      Set-Cookie: sid=42; Path=/
      Set-Cookie: theme=dark; Secure
    OUT
  end

  it "an unresolved constant in extend raises NameError from the class body, at run time" do
    result = zr(<<~'RUBY')
      # `include`/`extend`/`prepend` are ordinary method calls, so an unresolved
      # target is a RUNTIME NameError raised from the class body -- on the directive's
      # own line, with the enclosing bodies below it -- not a compile-time rejection.
      module Sock
        extend FFI
        ffi_lib "c"
        attach_function :puts_c, :puts, [:str], :int
      end

      class Boot
        def start
          if Missing::CONF.cert.length > 0
            Sock.puts_c(Missing::CONF.cert)
          end
          deadline = Time.now.to_i + timeout_seconds
          deadline
        end
      end

      puts "ok"
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      compiler/fusion/fusion_test.rb:5:in '<module:Sock>': uninitialized constant Sock::FFI (NameError)

        extend FFI
               ^^^
      	from compiler/fusion/fusion_test.rb:4:in '<main>'
    ERR
  end

  it "ivar int table narrowing" do
    result = zr(<<~'RUBY')
      # An @ivar holding a table of int arrays gets the typed nested representation
      # (an Array of Integer Arrays), but only when EVERY reference to it is an
      # op the narrowing models, from the owning class itself. An ivar's references
      # span the whole class and escape through readers, returns and arguments, and a
      # missed one is not a lost optimization -- it is a wrong type for the value.
      # Each class below is one way out; only the last modeled one may narrow, and
      # all of them must answer as CRuby does.
      class A1
        attr_reader :t
        def initialize(n) = @t = Array.new(n) { Array.new(n, 0) }
      end
      p A1.new(2).t.map { |r| r.length }

      # 2. the table returned bare from a method
      class A2
        def initialize(n) = @t = Array.new(n) { Array.new(n, 0) }
        def rows = @t
      end
      p A2.new(2).rows.length

      # 3. the table passed to another method
      class A3
        def initialize(n) = @t = Array.new(n) { Array.new(n, 0) }
        def go = count(@t)
        def count(x) = x.length
      end
      p A3.new(3).go

      # 4. an unmodeled op on the table
      class A4
        def initialize(n) = @t = Array.new(n) { Array.new(n, 0) }
        def go
          s = 0
          @t.each { |r| s += r.length }
          s
        end
      end
      p A4.new(3).go

      # 5. a subclass reading the parent's table
      class A5
        def initialize(n) = @t = Array.new(n) { Array.new(n, 0) }
      end
      class A5b < A5
        def peek = @t[0][0]
      end
      p A5b.new(2).peek

      # 6. the modeled shape: should narrow
      class A6
        def initialize(n)
          @n = n
          @t = Array.new(n) { Array.new(n, 0) }
        end
        def bump
          i = 0
          while i < @n
            @t[i][i] = @t[i][i] + i
            i += 1
          end
          self
        end
        def sum
          s = 0
          r = 0
          while r < @n
            row = @t[r]
            c = 0
            while c < @n
              s += row[c]
              c += 1
            end
            r += 1
          end
          s
        end
      end
      p A6.new(5).bump.sum

      # 7. mixed element types: not an int table
      class A7
        def initialize(n) = @t = Array.new(n) { ["a", 1] }
        def go = @t[0][0]
      end
      p A7.new(2).go

      # 8. an array LITERAL of int arrays, the shape optcarrot's @nmt_mem has: the
      # ivar write gets the same nested form as the other writes to the ivar.
      class A8
        def initialize
          @m = [[1, 2], [3, 4]]
        end
        def go
          @m[0][1] = @m[0][1] + 10
          @m[0][1] + @m[1][0] + @m.length
        end
      end
      p A8.new.go
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 2]
      2
      3
      9
      0
      10
      "a"
      17
    OUT
  end

  it "ivar orwrite raiseall typed slot" do
    result = zr(<<~'RUBY')
      # `@x ||= recv.map { ... }` where recv is nil, so the RHS can only raise.
      # @x holds an Array from another assignment. The or-write raises
      # NoMethodError at run time like CRuby.
      class Store
        def taggings; @data; end
        def seed(d); @memo = d; end
        def compute
          @memo ||= taggings.reject { |x| false }.map { |x| x }
        end
      end
      s = Store.new
      begin
        p s.compute
      rescue NoMethodError => e
        p e.class
      end
      s2 = Store.new
      s2.seed([10, 20])
      p s2.compute
    RUBY

    _(result).must_answer "NoMethodError\n[10, 20]\n"
  end

  it "keywords refused message" do
    result = zr(<<~'RUBY')
      # `**nil` in a signature declares that the method takes NO keywords. Passing
      # some is `ArgumentError: no keywords accepted`; zr reports an arity error
      # instead, having folded the keywords into a trailing positional Hash.
      #
      # The distinction is the point of the syntax (ruby 3.0): before it, a method
      # with no keyword parameters silently accepted `f(1, b: 2)` as a Hash argument,
      # and `**nil` is how you say that the old behaviour is not wanted. zr's message
      # -- "wrong number of arguments (given 2, expected 1)" -- describes exactly the
      # conversion `**nil` exists to forbid, so the diagnosis points the reader at the
      # wrong problem.
      #
      # Passing a real Hash positionally still has to work, which is the line below
      # that must keep answering.

      def nokw(a, **nil) = a

      begin
        nokw(1, b: 2)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end

      p nokw(1)
      p nokw({b: 2})

      def nokw_splat(*a, **nil) = a
      begin
        nokw_splat(1, b: 2)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end
      p nokw_splat(1, {b: 2})
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: no keywords accepted
      1
      {b: 2}
      ArgumentError: no keywords accepted
      [1, {b: 2}]
    OUT
  end

  it "narrow and predicate" do
    result = zr(<<~'RUBY')
      # `if v.is_a?(C) && other_cond` narrows `v` to C inside the
      # then-arm just like the bare `if v.is_a?(C)` form. So a call
      # inside the then-arm passes a C to the callee.

      def consume(s)
        s.length
      end

      class C
        attr_accessor :n
        def initialize; @n = 1; end
      end

      arr = ["hello", C.new]
      v = arr[0]
      allow = true
      if v.is_a?(String) && allow
        puts consume(v)
      end
    RUBY

    _(result).must_answer "5\n"
  end

  it "narrowed element local pin" do
    result = zr(<<~'RUBY')
      # The FIRST line pins the tie order of `Array#sort!`: this comparator orders by
      # a pair of ranks, so ties are common, and the answer is whatever the C library
      # leaves behind. zr sorts through the same `qsort_r` that CRuby's `ruby_qsort`
      # calls. That makes the line PER PLATFORM, so there are two goldens:
      # `.expected` is macOS, `.linux.expected` linux.
      #
      # The SECOND line is the main check:
      #
      # A local bound from a container read (`pair_a = pairs[a]`, where `pairs` is a
      # table of int arrays) is narrowed to the element type. The type analysis
      # settles, and each method keeps its element types.

      def sort_pairs(n)
        rank = Array.new(n) { |i| (n - i) % 3 }
        pairs = Array.new(n) { |i| [rank[i], rank[(i + 1) % n]] }
        sa = Array.new(n) { |i| i }

        sa.sort! do |a, b|
          pair_a = pairs[a]
          pair_b = pairs[b]
          if pair_a[0] != pair_b[0]
            pair_a[0] <=> pair_b[0]
          else
            pair_a[1] <=> pair_b[1]
          end
        end

        ranks = Array.new(n, 0)
        i = 1
        while i < n
          prev_pair = pairs[sa[i - 1]]
          curr_pair = pairs[sa[i]]
          ranks[sa[i]] = ranks[sa[i - 1]] + (prev_pair != curr_pair ? 1 : 0)
          i += 1
        end
        [sa, ranks]
      end

      p sort_pairs(8)
      p sort_pairs(3)
    RUBY

    _(result).must_answer <<~'OUT', linux: <<~'LINUX'
      [[2, 5, 4, 1, 7, 3, 6, 0], [3, 1, 0, 3, 1, 0, 3, 2]]
      [[0, 2, 1], [0, 2, 1]]
    OUT
      [[2, 5, 1, 4, 7, 3, 0, 6], [3, 1, 0, 3, 1, 0, 3, 2]]
      [[0, 2, 1], [0, 2, 1]]
    LINUX
  end

  it "nested array element narrows" do
    result = zr(<<~'RUBY')
      # an element read off a nested array narrows past the first level
      rows = [[2026, 5, 1]]
      m = rows[0][1]
      p (1...m).reduce(0) { |s, i| s + i }
      p (1..m).inject(0) { |s, i| s + i }
      p (1...m).reverse_each.to_a
      p (1...m).sum
      p (1...m).to_a
      strs = [["a", "b"]]
      sv = strs[0][1]
      p sv.upcase
      fl = [[1.5, 2.5]]
      fv = fl[0][1]
      p fv + 1
    RUBY

    _(result).must_answer <<~'OUT'
      10
      15
      [4, 3, 2, 1]
      10
      [1, 2, 3, 4]
      "B"
      3.5
    OUT
  end

  it "nil typed equality" do
    result = zr(<<~'RUBY')
      # Two operands whose STATIC type is nil (calls the analyzer proves return
      # nil) compare like literal nils: nil == nil is true, != is false, and both
      # expressions still evaluate for their effects (the counter increments).
      $calls = 0
      def probe(x)
        $calls += 1
        nil
      end

      p probe(1) == probe(2)
      p probe(3) != probe(4)
      # One operand a literal nil: the non-literal side must still evaluate.
      p probe(5) == nil
      p nil == probe(6)
      p $calls
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      6
    OUT
  end

  it "numbered params work through the times inline path" do
    result = zr("3.times { puts _1 * 10 }\n")

    _(result).must_answer <<~'OUT'
      0
      10
      20
    OUT
  end

  it "param narrow from body call" do
    result = zr(<<~'RUBY')
      # Body-side type narrowing: if a method's parameter is referenced in the
      # body via `param.<m>` where `<m>` is defined on exactly one user class
      # (and isn't a common operator / built-in-overlap method like
      # `length`/`each`/`+`/...), the param gets the type of that class.
      #
      # This matters for methods that are only called through a receiver whose
      # type is known only at run time (e.g. through `obj.method(:m)` or a call
      # on an element of a mixed Array). Then no call site gives the type.

      class CPU
        def peek_a(addr); addr * 2 + 1; end
        def cycles_advance(n); n + 100; end
      end

      # Two separate methods that each take a CPU param. The narrow comes
      # from the body's method-call shapes.

      def fetch(cpu, addr)
        cpu.peek_a(addr)        # peek_a is only on CPU → narrow cpu to CPU
      end

      def step(cpu, n)
        cpu.cycles_advance(n)   # cycles_advance only on CPU → narrow
      end

      c = CPU.new
      puts fetch(c, 7)          # 15
      puts step(c, 3)           # 103
    RUBY

    _(result).must_answer "15\n103\n"
  end

  it "pattern rest from typed array" do
    result = zr(<<~'RUBY')
      # A pattern's `*rest` bound from a poly scrutinee that holds a typed array.
      def m(v)
        case v
        in [f, *r] then "#{f} +#{r.inspect}"
        in Integer then "int"
        end
      end
      puts m([1, 2, 3])
      puts m([1.5, 2.5])
      puts m(%w[a b c])
      puts m([1, "a", nil])
      puts m(7)

      def tail(v)
        case v
        in [*init, last] then "#{init.inspect} #{last}"
        in Integer then "int"
        end
      end
      puts tail([1, 2, 3])
      puts tail(%w[x y])

      def mid(v)
        case v
        in [a, *m, z] then "#{a} #{m.inspect} #{z}"
        in Integer then "int"
        end
      end
      puts mid([1, 2, 3, 4])
      puts mid([1.0, 2.0])

      def find(v)
        case v
        in [*pre, 3, *post] then "#{pre.inspect} | #{post.inspect}"
        in Integer then "int"
        end
      end
      puts find([1, 2, 3, 4, 5])
      puts find([3])
    RUBY

    _(result).must_answer <<~'OUT'
      1 +[2, 3]
      1.5 +[2.5]
      a +["b", "c"]
      1 +["a", nil]
      int
      [1, 2] 3
      ["x"] y
      1 [2, 3] 4
      1.0 [] 2.0
      [1, 2] | [4, 5]
      [] | []
    OUT
  end

  it "raise before a fused loop reaches the landing" do
    result = zr(<<~'RUBY', env: {"ZR_TEST_RT_LEAKCHECK" => "1"})

      # The landing block is shared: `Fx::new` creates ONE of it and every
      # `Fx::fallible` branches there, so a raise anywhere in a method reaches the
      # same epilogue that a normal return does -- and that epilogue releases every
      # slot in `fx.locals` unconditionally.
      #
      # A fused `n.times` loop takes no run-time guard. Here a raise comes BEFORE
      # the loop, so the method reaches the landing without ever running the
      # block. The block parameter's slot must hold a value that is safe to
      # release at that point. This pins the path.
      #
      # Runs under `ZR_TEST_RT_LEAKCHECK=1`; the printed output is the same either way.
      #
      # LIMIT: a bad release on this path does not always show. What this example
      # adds is coverage of the path, so a LOUD failure on it is caught.

      def raises_before_a_loop(obj)
        obj.no_such_method
        3.times { |i| p i }
      rescue NoMethodError => e
        e.class
      end

      def raises_before_a_range_loop(obj)
        obj.no_such_method
        (0...3).each { |i| p i }
      rescue NoMethodError => e
        e.class
      end

      p raises_before_a_loop(Object.new)
      p raises_before_a_range_loop(Object.new)
    RUBY

    _(result).must_answer "NoMethodError\nNoMethodError\n"
  end

  it "raise unless isa narrow" do
    result = zr(<<~'RUBY')
      # `raise ... unless x.is_a?(C)` (and the equivalent
      # `if !x.is_a?(C); raise ...; end` shape) is a definite-throw
      # type assertion: when control reaches the statement after the
      # guard, `x` is provably of class `C`. For example:
      #
      #   def process(x)
      #     raise TypeError, "expected A" unless x.is_a?(A)
      #     puts x.body
      #   end
      #
      # After the guard, `x.body` is A#body, which answers a String, and
      # not B#body, which answers an Integer. The narrow holds for the rest
      # of the method body.

      class A
        attr_accessor :body
        def initialize; @body = "from-A"; end
      end

      class B
        attr_accessor :body
        def initialize; @body = 42; end
      end

      def pick(n)
        n > 0 ? A.new : B.new
      end

      def process_unless(x)
        raise "expected A" unless x.is_a?(A)
        puts x.body
      end

      def process_if_negated(x)
        if !x.is_a?(A)
          raise "expected A"
        end
        puts x.body
      end

      # Both spellings should resolve identically -- a single call to
      # A#body.
      process_unless(pick(1))
      process_if_negated(pick(1))

      # Multiple guards in sequence accumulate narrows.
      class S
        attr_accessor :name
        def initialize; @name = "sized"; end
      end

      def render(s, t)
        raise "expected S" unless s.is_a?(S)
        raise "expected S" unless t.is_a?(S)
        puts s.name + "/" + t.name
      end

      render(S.new, S.new)
    RUBY

    _(result).must_answer <<~'OUT'
      from-A
      from-A
      sized/sized
    OUT
  end

  it "random is seeded reproducible and typed" do
    result = zr(<<~'RUBY')
      p(Random.new(42).rand(1000) == Random.new(42).rand(1000))
      p(Random.new(1).rand(1000) != Random.new(2).rand(1000))
      p Random.new(5).rand(10).class
      p Random.new(5).rand(2.5).class
      p Random.new(5).rand.class
      p((r = Random.new(9).rand(6)) >= 0 && r < 6)
      p Random.new(1).bytes(8).bytesize
      p Random.new(123).seed
      p Random.new(3.9).seed
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      Integer
      Float
      Float
      true
      8
      123
      3
    OUT
  end

  it "range predicate typed argument" do
    result = zr(<<~'RUBY')
      b = "x"
      p((1..5).cover?(b))
      def g; "x"; end
      p((1..5).cover?(g))
      b = [1]; p((1..5).cover?(b))
      b = { a: 1 }; p((1..5).include?(b))
      b = :sym; p((1..5).member?(b))
      b = nil;  p((1..5) === b)
      b = 3;    p((1..5).cover?(b))
      b = 2.5;  p((1..5).cover?(b))

      # a Range operand: cover? is containment, === and include? are not
      p((1..5).cover?(1...6))
      p((1..5).cover?(2..9))
      p((1..5).cover?(1.0..5.0))
      p((1..5).cover?(1.0...5.5))
      p((1...5).cover?(1..4))
      p((1..5) === (1.0..5.0))
      p((1..5).include?(1..2))
      r = ((1..5).eql?(1.0..5.0) rescue $!.class); p r
      fr = (1.0..5.0); r = ((1..5).eql?(fr) rescue $!.class); p r
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
      false
      false
      true
      true
      true
      false
      true
      false
      true
      false
      false
      false
      false
    OUT
  end

  it "redefinition reaches a typed direct call site" do
    result = zr(<<~'RUBY')
      class Other
        def unrelated = 0
      end

      class N
        def initialize(v)
          @v = v
        end
        attr_reader :v
        def step(a) = @v + a
      end

      n = N.new(10)
      puts n.step(1)
      puts n.v

      Other.define_method(:unrelated) { 1 }
      puts n.step(2)
      puts n.v

      N.define_method(:step) { |a| @v * a }
      puts n.step(3)

      N.attr_accessor :v
      n.v = 99
      puts n.v
      puts n.step(1)

      o = N.new(5)
      def o.step(a) = -a
      puts o.step(4)
      puts n.step(4)

      module Doubler
        def step(a) = 1000 + a
      end
      N.prepend(Doubler)
      puts n.step(5)
      puts N.new(1).step(6)
    RUBY

    _(result).must_answer <<~'OUT'
      11
      10
      12
      10
      30
      99
      99
      -4
      396
      1005
      1006
    OUT
  end

  it "require under a statically false engine guard is pruned not spliced" do
    result = zr(<<~'RUBY')
      # `require X if RUBY_ENGINE == "jruby"` names another engine's code; a
      # whole-program AOT compiler eager-splices every literal require it sees,
      # but this one's guard folds statically false on CRuby-targeting zr, so
      # the target must be PRUNED, not spliced (splicing would fail to resolve
      # it). The program compiles and the guarded require is simply dead.

      require "no_such_engine_lib_xyz" if RUBY_ENGINE == "jruby"
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "respond to on a poly typed rescue binding" do
    result = zr(<<~'RUBY')
      # `e` (a rescue clause's exception binding) is never narrowed to a
      # concrete class -- exercises
      # `respond_to?`'s runtime `class_id()` fallback path, not the
      # statically-known-class one the test above exercises.

      begin
        raise "boom"
      rescue => e
        puts e.respond_to?(:message)
        puts e.respond_to?(:not_a_thing)
      end
    RUBY

    _(result).must_answer "true\nfalse\n"
  end

  it "runtime private on typed receiver" do
    result = zr(<<~'RUBY')
      # Visibility is a RUNTIME property in ruby: `private :name` re-marks a method
      # that already exists, and every later call sees the new mark.
      #
      # A call whose receiver class zr knows at compile time is a direct call to the
      # generated function, and it decided visibility once -- when it was emitted. So
      # the names a runtime visibility verb could re-mark join the same
      # `Compiler::runtime_patches` set a runtime `define_method` feeds, and the fold
      # stands down for them. The dynamic path already asked the runtime per call.
      #
      # A class-body `private :m` is untouched: lowering retags the `def` in place,
      # so no call survives for the scan to see.

      class Late
        def open_now = :open
        def stays = :stays
      end

      holder = Late.new
      p holder.open_now

      Late.send(:private, :open_now)

      begin
        p holder.open_now
      rescue NoMethodError => e
        puts e.message
      end

      # Reachable without an explicit receiver, and through `send`, exactly as before.
      class Late
        def reach = open_now
      end
      p holder.reach
      p holder.send(:open_now)

      # ...and promotable again.
      Late.send(:public, :open_now)
      p holder.open_now

      # `protected` is the third state, and takes a LIST.
      class Pair
        def a = 1
        def b = 2
        def c = 3
        def sum(other) = other.a + other.b
      end
      x = Pair.new
      y = Pair.new
      p x.sum(y)
      Pair.send(:protected, :a, :b)
      p x.sum(y)
      begin
        x.a
      rescue NoMethodError => e
        puts e.message
      end
      p x.c

      # The class-method twin.
      class Fact
        def self.build = :built
        def self.keep = :kept
      end
      p Fact.build
      Fact.send(:private_class_method, :build)
      begin
        Fact.build
      rescue NoMethodError => e
        puts e.message
      end
      p Fact.keep

      # A class body's own `private` still folds -- nothing about it is deferred.
      class Body
        def shown = :shown
        def hidden = :hidden
        private :hidden
      end
      p Body.new.shown
      begin
        Body.new.hidden
      rescue NoMethodError => e
        puts e.message
      end
      p Body.private_instance_methods(false)
    RUBY

    _(result).must_answer <<~'OUT'
      :open
      private method 'open_now' called for an instance of Late
      :open
      :open
      :open
      3
      3
      protected method 'a' called for an instance of Pair
      3
      :built
      private method 'build' called for class Fact
      :kept
      :shown
      private method 'hidden' called for an instance of Body
      [:hidden]
    OUT
  end

  it "safe nav specialized miss" do
    result = zr(<<~'RUBY')
      # A miss on a Hash or Array lookup answers nil, so a `&.` on the result answers
      # nil, not `false`, as in CRuby. A `&.` whose callee answers true or false (the
      # predicates that take an argument, `nil?`) answers that value on a hit.

      h = { "a" => "abc" }
      p h["zz"]
      p h["zz"]&.empty?
      p h["zz"]&.start_with?("a")
      p h["zz"]&.end_with?("c")
      p h["zz"]&.include?("a")
      p h["zz"]&.nil?
      p h["zz"]&.eql?("abc")
      p h["zz"]&.to_s
      p h["zz"]&.size
      p h["zz"]&.bytesize
      p h["zz"]&.upcase
      p h["a"]&.empty?
      p h["a"]&.start_with?("a")
      p h["a"]&.nil?

      g = { "a" => 1 }
      p g["zz"]&.positive?
      p g["zz"]&.zero?
      p g["a"]&.positive?
      p g["zz"].nil?
      p g["zz"] || 9

      f = { "a" => 1.5 }
      p f["zz"]&.positive?
      p f["a"]&.positive?

      a = ["abc"]
      p a[5]&.empty?
      p a[5]&.start_with?("a")
      p a[5]&.size
      p a[5]&.upcase
      p a[0]&.empty?

      # a nil in the literal forces the poly representation -- the control that was
      # already right
      m = { "a" => "abc", "b" => nil }
      p m["zz"]&.empty?
      p({ "a" => "abc" }.fetch("zz", nil)&.empty?)

      # a poly receiver: the value arm renders a raw C bool for every one of these
      def pred(v) = v&.start_with?("a")
      def tail(v) = v&.end_with?("c")
      def isnil(v) = v&.nil?
      def has(v) = v&.include?("a")
      def blank(v) = v&.empty?
      def same(v) = v&.eql?("abc")
      def kind(v) = v&.instance_of?(String)
      def bytes(v) = v&.bytesize
      def as_i(v) = v&.to_i
      def as_f(v) = v&.to_f

      ["abc", nil].each do |v|
        p pred(v)
        p tail(v)
        p isnil(v)
        p has(v)
        p blank(v)
        p same(v)
        p kind(v)
        p bytes(v)
      end

      [3, nil].each do |v|
        p as_i(v)
        p as_f(v)
      end

      # an object receiver keeps its own nil, and a nilable ivar reaching a predicate
      class Box
        attr_reader :text
        def initialize(t)
          @text = t
        end
      end

      def peek(b) = b.text&.empty?
      p peek(Box.new("abc"))
      p peek(Box.new(nil))

      # an object receiver that may be nil: the guard's nil arm is a real nil, not
      # the predicate's false
      class Node
        def initialize(a)
          @a = a
          @kids = [1, 2]
        end

        def leaf? = @kids.empty?
        def name = @a
      end

      def find(x) = x > 0 ? Node.new("n") : nil
      p find(1)&.leaf?
      p find(-1)&.leaf?
      p find(-1)&.name

      # a by-value struct is never nil, so the call still dispatches -- but its
      # answer has to be boxed to sit in the poly slot the widening asks for
      class Flag
        def initialize(b) = @b = b
        def on? = @b
      end

      def flagged(x) = Flag.new(x)
      p flagged(true)&.on?
      p flagged(false)&.on?

      # The conversions CRuby answers FOR nil: a miss handed to one of them is nil,
      # and nil answers to_i as 0 and to_f as 0.0 rather than passing the sentinel on
      n = { "a" => 1 }
      p n["zz"].to_i
      p n["zz"].to_f
      p n["zz"].to_s
      p n["zz"].inspect
      p n["zz"].nil?
      p n["a"].to_i
      p n["a"].to_f
      p 5.to_i
      p 5.to_f
      p([1][5].to_i)
      p([1][0].to_i)

      # and the predicates CRuby REFUSES on nil: a miss answered false where the
      # program should have seen a NoMethodError
      def try
        yield
      rescue NoMethodError => e
        e.class
      end

      p try { n["zz"].positive? }
      p try { n["zz"].zero? }
      p try { n["zz"].even? }
      p try { n["a"].positive? }
      p try { n["a"].even? }
      p 4.even?
      p 4.positive?
      p 0.zero?
      p(-1.negative?)
      p try { { "a" => "abc" }["zz"].empty? }
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      false
      true
      false
      nil
      nil
      true
      true
      9
      nil
      true
      nil
      nil
      nil
      nil
      false
      nil
      nil
      true
      true
      false
      true
      false
      true
      true
      3
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      3
      3.0
      nil
      nil
      false
      nil
      false
      nil
      nil
      true
      false
      0
      0.0
      ""
      "nil"
      true
      1
      1.0
      5
      5.0
      0
      1
      NoMethodError
      NoMethodError
      NoMethodError
      true
      false
      true
      true
      true
      true
      NoMethodError
    OUT
  end

  it "shared string into typed array" do
    result = zr(<<~'RUBY')
      # A shared-mutable string pushed into an Array of Strings.
      #
      # A string that is both aliased and mutated in place goes into the Array with
      # its bytes, and each element reads back as the String that went in.
      #
      # The Array is in an ivar, which keeps its String element type. A local
      # Array can get mixed elements instead.

      class Holder
        attr_accessor :items, :map

        def initialize
          @items = [""]      # type seed; a bare [] infers an IntArray
          @items.pop
          @map = { "seed" => "" }
          @map.delete("seed")
        end
      end

      def built(x)
        s = +""
        s << "v"
        s << x
        s
      end

      h = Holder.new
      h.items << built("1")
      puts "after <<:   " + h.items[0]
      h.items.push(built("2"))
      h.items.unshift(built("0"))
      h.items.insert(1, built("x"))
      p h.items
      h.items.each { |e| puts "in each:    " + e }

      h.map["k"] = built("m")
      p h.map["k"]

      h.items.concat([built("c")])
      p h.items.last
      p h.items.join(",")
      p h.items.length

      # the reporter's shape, verbatim in spirit
      s = +""
      s << "b"
      s << "=2"
      h2 = Holder.new
      h2.items << s
      puts "reporter:   " + h2.items[0]
    RUBY

    _(result).must_answer <<~'OUT'
      after <<:   v1
      ["v0", "vx", "v1", "v2"]
      in each:    v0
      in each:    vx
      in each:    v1
      in each:    v2
      "vm"
      "vc"
      "v0,vx,v1,v2,vc"
      5
      reporter:   b=2
    OUT
  end

  it "singleton row beats a specialized builtin path" do
    result = zr(<<~'RUBY')
      a = [1, 2, 3]
      b = [4, 5, 6]

      p a[0]
      p b[0]
      a.each { |x| print x }
      puts

      def a.[](i) = -1

      def a.each
        yield 99
        self
      end

      p a[0]
      p b[0]
      a.each { |x| print x }
      puts
      b.each { |x| print x }
      puts

      class Wrapped < Array
      end
      w = Wrapped.new([7, 8])
      p w[1]
      p a[1]

      module Shout
        def [](i) = 1000 + i
      end
      b.extend(Shout)
      p b[1]
      p a[1]
      p Wrapped.new([9])[0]
    RUBY

    _(result).must_answer <<~'OUT'
      1
      4
      123
      -1
      4
      99
      456
      8
      -1
      1001
      -1
      9
    OUT
  end

  it "spliced files locals stay isolated through control flow" do
    result = zr(<<~'RUBY', files: beside("spliced_locals/inner.rb"))
      # Real Ruby gives every `require`d file its own top-level local scope. zr
      # splices every file into one `Program`, so it renames each file's top-level
      # locals to keep them apart. That renaming walk had a hand-written arm for
      # every node kind an assignment can hide behind -- `if`, `while`, `case`,
      # `begin`, a literal -- each cloning the body vector it walked. Collapsing
      # them onto one descent has to keep reaching all of those positions: a name
      # missed there is renamed at its assignment and NOT at its read, or the other
      # way round, and the two files silently share a binding.
      #
      # This file assigns the same names the required one does, from inside each
      # control-flow shape, and both must keep their own values.
      name = "outer"
      count = 0

      if name == "outer"
        count = 1
      end

      while count < 3
        count += 1
      end

      case count
      when 3 then tag = "three"
      else tag = "other"
      end

      begin
        parts = ["a", "b"]
      rescue StandardError
        parts = []
      end

      interp = "#{name}-#{count}-#{tag}"
      listed = [name, count, tag].map { |v| v.to_s }

      require_relative "spliced_locals/inner"

      p [name, count, tag, parts, interp, listed]
      p inner_report
    RUBY

    _(result).must_answer <<~'OUT'
      ["inner", 202, "two-oh-two", ["x"], "inner-202-two-oh-two", ["inner", "202", "two-oh-two"]]
      ["outer", 3, "three", ["a", "b"], "outer-3-three", ["outer", "3", "three"]]
      :inner_ran
    OUT
  end

  it "string splice family" do
    result = zr(<<~'RUBY')
      # String#bytesplice and String#slice!(Regexp): byte-range replacement
      # returning self, and regexp slicing returning the removed match while
      # mutating the receiver and setting the match registers.

      def bs(s, i, n, rep)
        t = s.dup
        r = t.bytesplice(i, n, rep)
        [r, t, r == t]
      end

      # happy: replace, insert (len 0), delete (empty replacement)
      p bs("hello world", 0, 3, "XYZ")
      p bs("hello", 1, 0, "--")
      p bs("hello", 1, 3, "")

      # edge: negative start counts from the end; length clamps past the end
      p bs("hello", -2, 2, "LO")
      p bs("hello", 1, 99, "!")
      p bs("", 0, 0, "seed")

      # value position: the result chains like self
      def bs_chain(s)
        t = s.dup
        t.bytesplice(0, 1, "J").upcase
      end
      p bs_chain("hello")

      # exceptional: CRuby's IndexError contracts
      def bs_err(s, i, n, rep)
        t = s.dup
        t.bytesplice(i, n, rep)
      rescue IndexError => e
        "#{e.class}: #{e.message}"
      end
      p bs_err("abc", 0, -1, "x")
      p bs_err("abc", 5, 1, "x")
      p bs_err("abc", -9, 1, "x")

      def sl(s)
        t = s.dup
        r = t.slice!(/\d+/)
        [r, t]
      end

      # happy: removed match + mutated receiver; miss leaves both alone
      p sl("ab12cd")
      p sl("no digits")
      p sl("12ab34")

      # registers: capture groups from the sliced match survive
      def sl_caps(s)
        t = s.dup
        t.slice!(/(\w+)@(\w+)/)
        [$1, $2]
      end
      p sl_caps("mail: user@example end")

      # ivar receiver in statement position
      class SliceBox
        def initialize(s); @s = s; end
        def chomp_digits!; @s.slice!(/\d+/); @s; end
      end
      p SliceBox.new("v1.2.3").chomp_digits!
    RUBY

    _(result).must_answer <<~'OUT'
      ["XYZlo world", "XYZlo world", true]
      ["h--ello", "h--ello", true]
      ["ho", "ho", true]
      ["helLO", "helLO", true]
      ["h!", "h!", true]
      ["seed", "seed", true]
      "JELLO"
      "IndexError: negative length -1"
      "IndexError: index 5 out of string"
      "IndexError: index -9 out of string"
      ["12", "abcd"]
      [nil, "no digits"]
      ["12", "ab34"]
      ["user", "example"]
      "v.2.3"
    OUT
  end

  it "string split inline arg gc root" do
    result = zr(<<~'RUBY')
      # Inline split arguments must stay valid across compiled split calls with
      # GC-managed pressure nearby. The pressure loop grows retained int arrays so
      # runtime allocation and collection paths are exercised before each split.

      def churn_gc
        keep = []
        while GC.stat["bytes"] <= GC.stat["threshold"] && keep.length < 64
          chunk = []
          j = 0
          while j < 65536
            chunk << j
            j = j + 1
          end
          keep << chunk
        end
        keep
      end

      def same_strings(a, b)
        if a.length != b.length
          return false
        end

        i = 0
        while i < a.length
          if a[i] != b[i]
            return false
          end
          i = i + 1
        end

        true
      end

      lines = []
      i = 0
      while i < 40
        lines << i.to_s
        i = i + 1
      end

      data = lines.join(10.chr)
      keep = churn_gc

      plain = data.split(10.chr)
      keep = []
      keep2 = churn_gc
      positive = data.split(10.chr, 2)
      keep2 = []
      keep3 = churn_gc
      negative = (data + 10.chr).split(10.chr, -1)
      keep3 = []

      tail = []
      i = 1
      while i < lines.length
        tail << lines[i]
        i = i + 1
      end

      expected_positive = []
      expected_positive << lines[0]
      expected_positive << tail.join(10.chr)

      expected_negative = []
      i = 0
      while i < lines.length
        expected_negative << lines[i]
        i = i + 1
      end
      expected_negative << ""

      ok = same_strings(plain, lines)
      ok = ok && same_strings(positive, expected_positive)
      ok = ok && same_strings(negative, expected_negative)

      puts(ok ? "ok" : "bad")
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      compiler/fusion/fusion_test.rb:7:in 'Object#churn_gc': undefined method '<=' for nil (NoMethodError)

        while GC.stat["bytes"] <= GC.stat["threshold"] && keep.length < 64
                               ^^
      	from compiler/fusion/fusion_test.rb:43:in '<main>'
    ERR
  end

  it "typed array include cross type" do
    result = zr(<<~'RUBY')
      # Array#include? on a typed array with a wrong-type
      # argument returns false.
      puts [1, 2, 3].include?("hello")
      puts [1, 2, 3].include?(2)
      puts ["a", "b", "c"].include?(42)
      puts ["a", "b", "c"].include?("b")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
    OUT
  end

  it "chomp, delete, squeeze and count take a separator that answers to_str" do
    result = zr(<<~'RUBY')
      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      p "a-b-".chomp(Sep.new)
      s = String.new("a-b")
      p [s.chomp!(Sep.new), s]
      p "a".ljust(4, Sep.new)
      p "a".rjust(4, Sep.new)
      p "a".center(5, Sep.new)
      p "a-b".index(Sep.new, 0)
      p "a-b-".rindex(Sep.new)
      p "a-b-".rindex(Sep.new, 2)
      p "\xff".scrub(Sep.new) == "-"
      p String.new("\xff").scrub!(Sep.new) == "-"
      p "a-b-c".split(Sep.new, 2)
      p "a-b-c".split(Sep.new)
      p "a".upto(Sep.new).to_a.size
      class Fmt
        def to_str
          "a"
        end
      end
      p "ab".unpack1(Fmt.new)
      p String.new("abc").bytesplice(0, 1, Sep.new)
      p Time.utc(2000).strftime(Sep.new)
      p String.new(Sep.new)
      p Regexp.escape(Sep.new)
      p format(Sep.new)
      p sprintf(Sep.new)
      ENV["SPINEL_SLOT"] = "v"
      class Key
        def to_str
          "SPINEL_SLOT"
        end
      end
      p ENV[Key.new]
      p ENV.key?(Key.new)
      p ENV.store(Key.new, "w")
      p ENV.delete(Key.new)
      class Cmd
        def to_str
          "true"
        end
      end
      p system(Cmd.new)
      p err { "abc".rindex(1) }
      p err { "abc".ljust(4, 1) }
      p err { "a-b".chomp(1) }
      p err { "abc".split(1) }
      p err { format(1) }
      p err { Time.utc(2000).strftime(1) }
      p err { Regexp.escape(1) }
      p err { String.new(1) }

    RUBY

    _(result).must_answer <<~'OUT'
      "a-b"
      [nil, "a-b"]
      "a---"
      "---a"
      "--a--"
      1
      3
      1
      true
      true
      ["a", "b-c"]
      ["a", "b", "c"]
      0
      "a"
      "-bc"
      "-"
      "-"
      "\\-"
      "-"
      "-"
      "v"
      true
      "w"
      "w"
      true
      [TypeError, "no implicit conversion of Integer into String"]
      [TypeError, "no implicit conversion of Integer into String"]
      [TypeError, "no implicit conversion of Integer into String"]
      [TypeError, "wrong argument type Integer (expected Regexp)"]
      [TypeError, "no implicit conversion of Integer into String"]
      [TypeError, "no implicit conversion of Integer into String"]
      [TypeError, "no implicit conversion of Integer into String"]
      [TypeError, "no implicit conversion of Integer into String"]
    OUT
  end

  it "slice! and the index rows take an index that answers to_int" do
    result = zr(<<~'RUBY')
      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      s = String.new("a-b")
      class Fmt
        def to_str
          "a"
        end
      end
      ENV["SPINEL_SLOT"] = "v"
      class Key
        def to_str
          "SPINEL_SLOT"
        end
      end
      class Cmd
        def to_str
          "true"
        end
      end

      a = [1, 2, 3]
      p [a.slice!(Idx.new, Idx.new), a]
      p 8[Idx.new]
      p 1 << Idx.new
      p 8 >> Idx.new
      p Time.at(Idx.new).to_i
      p Time.utc(2000, Idx.new, Idx.new).month
      p Time.local(2000, Idx.new, Idx.new).day
      p Random.new(1).rand(Idx.new).class
      p Random.rand(Idx.new).class
      p [1, 2].each_slice(Idx.new).to_a
      p [[1, 2], 3].dig(Idx.new)
      m = /(a)(b)/.match("ab")
      p [m.begin(Idx.new), m.end(Idx.new), m.offset(Idx.new), m.byteoffset(Idx.new), m.values_at(Idx.new)]
      p /a/.match?("ba", Idx.new)
      p err { [1, 2].cycle("x") { } }
      p err { Random.rand("x") }
      p err { a.slice!("x", 1) }
      p err { 8["x"] }
      p err { [1, 2].each_slice("x") { }; :no }
      p err { Time.at([1]) }
      p err { File.utime("x", "x", "nope") }
      p err { 1.0.quo("x") }
      p err { Math.sqrt("x") }
      p err { Math.sqrt(nil) }
      p err { Math.sqrt(Sep.new) }

    RUBY

    _(result).must_answer <<~'OUT'
      [[2], [1, 3]]
      0
      2
      4
      1
      1
      1
      Integer
      Integer
      [[1], [2]]
      3
      [0, 1, [0, 1], [0, 1], ["a"]]
      true
      [TypeError, "no implicit conversion of String into Integer"]
      [TypeError, "no implicit conversion of String into Integer"]
      [TypeError, "no implicit conversion of String into Integer"]
      [TypeError, "no implicit conversion of String into Integer"]
      [TypeError, "no implicit conversion of String into Integer"]
      [TypeError, "can't convert Array into an exact number"]
      [TypeError, "can't convert String into time"]
      [TypeError, "String can't be coerced into Float"]
      [TypeError, "can't convert String into Float"]
      [TypeError, "can't convert nil into Float"]
      [TypeError, "can't convert Sep into Float"]
    OUT
  end

  it "dig and fetch take a key that answers to_str" do
    result = zr(<<~'RUBY')
      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      s = String.new("a-b")
      class Fmt
        def to_str
          "a"
        end
      end
      ENV["SPINEL_SLOT"] = "v"
      class Key
        def to_str
          "SPINEL_SLOT"
        end
      end
      class Cmd
        def to_str
          "true"
        end
      end

      a = [1, 2, 3]
      m = /(a)(b)/.match("ab")

      h = { 1 => 2 }
      p h.dig("a")
      p h.dig(1.0)
      p h.fetch("a", 9)
      p h.except("a")
      p h.slice("a", 1)
      p h.values_at("a", 1)
      p h.has_value?("x")
      p h.has_value?(2.0)
      p h.assoc("a")
      p err { h.fetch("a") }
      p err { h.fetch_values(1, :b) }
      sh = { "a" => 1 }
      p sh.assoc(2)
      p sh.dig(:a)
      p [1, 2].count("x")
      p [1, 2].all?("x")
      p [].all?("x")
      p [1, 2].any?("x")
      p [1, 2].none?("x")
      p [1, 2].one?("x")
      p [1, 2].delete("x")
      p [1, 2].delete("x") { :none }
      p ["a"].delete(1)
      p [1, 2].index("x")
      p [1, 2].rindex(:y)
      p (1..2).include?("x")
      p (1..2) === "x"
      p (1..2).member?(nil)
      p (1..2).eql?("x")
      p (1..2).count("x")
      p [1, 2.0].count(2)
      p [1, 2].count(1.0)

    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      9
      {1 => 2}
      {1 => 2}
      [nil, 2]
      false
      true
      nil
      [KeyError, "key not found: \"a\""]
      [KeyError, "key not found: :b"]
      nil
      nil
      0
      false
      true
      false
      true
      false
      nil
      :none
      nil
      nil
      nil
      false
      false
      false
      false
      0
      1
      1
    OUT
  end

  it "count takes a bignum argument and finds none of it" do
    result = zr(<<~'RUBY')
      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      s = String.new("a-b")
      class Fmt
        def to_str
          "a"
        end
      end
      ENV["SPINEL_SLOT"] = "v"
      class Key
        def to_str
          "SPINEL_SLOT"
        end
      end
      class Cmd
        def to_str
          "true"
        end
      end

      a = [1, 2, 3]
      m = /(a)(b)/.match("ab")

      h = { 1 => 2 }
      sh = { "a" => 1 }

      p [1, 2].count(2**100)

    RUBY

    _(result).must_answer <<~'OUT'
      0
    OUT
  end

  it "zip and product take an argument that answers to_ary" do
    result = zr(<<~'RUBY')
      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      s = String.new("a-b")
      class Fmt
        def to_str
          "a"
        end
      end
      ENV["SPINEL_SLOT"] = "v"
      class Key
        def to_str
          "SPINEL_SLOT"
        end
      end
      class Cmd
        def to_str
          "true"
        end
      end

      a = [1, 2, 3]
      m = /(a)(b)/.match("ab")

      h = { 1 => 2 }
      sh = { "a" => 1 }


      class Pair
        def to_ary
          [1, 2]
        end
      end

      class Tbl
        def to_hash
          { "b" => 2 }
        end
      end

      class Pair
        def to_ary
          [1, 2]
        end
      end

      class Tbl
        def to_hash
          { "b" => 2 }
        end
      end

      class Inert
      end
      p [3, 4].zip(Pair.new)
      p [3, 4].product(Pair.new)
      p({ "a" => 1 }.merge(Tbl.new))
      p err { [1].zip(5) }
      p err { [1].zip(nil) }
      p err { [1].zip(Inert.new) }
      p err { [1].product("x") }
      p err { { "a" => 1 }.merge(5) }
      p err { { "a" => 1 }.merge(Inert.new) }
      p({ "a" => 1 }[Sep.new])

    RUBY

    _(result).must_answer <<~'OUT'
      [[3, 1], [4, 2]]
      [[3, 1], [3, 2], [4, 1], [4, 2]]
      {"a" => 1, "b" => 2}
      [TypeError, "wrong argument type Integer (must respond to :each)"]
      [TypeError, "wrong argument type NilClass (must respond to :each)"]
      [TypeError, "wrong argument type Inert (must respond to :each)"]
      [TypeError, "no implicit conversion of String into Array"]
      [TypeError, "no implicit conversion of Integer into Hash"]
      [TypeError, "no implicit conversion of Inert into Hash"]
      nil
    OUT
  end

  it "the receiver converts before the argument does" do
    result = zr(<<~'RUBY')
      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      s = String.new("a-b")
      class Fmt
        def to_str
          "a"
        end
      end
      ENV["SPINEL_SLOT"] = "v"
      class Key
        def to_str
          "SPINEL_SLOT"
        end
      end
      class Cmd
        def to_str
          "true"
        end
      end

      a = [1, 2, 3]
      m = /(a)(b)/.match("ab")

      h = { 1 => 2 }
      sh = { "a" => 1 }


      class Pair
        def to_ary
          [1, 2]
        end
      end

      class Tbl
        def to_hash
          { "b" => 2 }
        end
      end

      class Inert
      end

      def trace(label, value)
        puts label
        value
      end
      p trace("recv", [1]).product(trace("arg", [2]))

    RUBY

    _(result).must_answer <<~'OUT'
      recv
      arg
      [[1, 2]]
    OUT
  end

  it "File.utime takes nil for a time, and refuses a value it cannot convert" do
    result = zr(<<~'RUBY')
      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      s = String.new("a-b")
      class Fmt
        def to_str
          "a"
        end
      end
      ENV["SPINEL_SLOT"] = "v"
      class Key
        def to_str
          "SPINEL_SLOT"
        end
      end
      class Cmd
        def to_str
          "true"
        end
      end

      a = [1, 2, 3]
      m = /(a)(b)/.match("ab")

      h = { 1 => 2 }
      sh = { "a" => 1 }


      class Pair
        def to_ary
          [1, 2]
        end
      end

      class Tbl
        def to_hash
          { "b" => 2 }
        end
      end

      class Inert
      end

      def trace(label, value)
        puts label
        value
      end

      path = "/tmp/spinel_typed_slot_conversion.txt"
      File.write(path, "x")
      p File.utime(nil, nil, path)
      File.delete(path)
      p Time.utc(2000, 5, nil)
      p Time.utc(2000, 5, 6, nil, nil, nil).min
      p err { Random.rand(nil) }
      p err { 1.0.quo(nil) }
      p err { 1.0.quo(:s) }
      p err { 7.0.fdiv(Sep.new) }
      p err { 7.fdiv("x") }
      p "a1b2c".split(/\d/) { |x| p x }
      p err { "a b".split(true) }

    RUBY

    _(result).must_answer <<~'OUT'
      1
      2000-05-01 00:00:00 UTC
      0
      [ArgumentError, "invalid argument - "]
      [TypeError, "nil can't be coerced into Float"]
      [TypeError, ":s can't be coerced into Float"]
      [TypeError, "Sep can't be coerced into Float"]
      [TypeError, "String can't be coerced into Integer"]
      "a"
      "b"
      "c"
      "a1b2c"
      [TypeError, "wrong argument type true (expected Regexp)"]
    OUT
  end

  it "fetch, dig and values_at each ask their key once" do
    result = zr(<<~'RUBY')
      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      s = String.new("a-b")
      class Fmt
        def to_str
          "a"
        end
      end
      ENV["SPINEL_SLOT"] = "v"
      class Key
        def to_str
          "SPINEL_SLOT"
        end
      end
      class Cmd
        def to_str
          "true"
        end
      end

      a = [1, 2, 3]
      m = /(a)(b)/.match("ab")

      h = { 1 => 2 }
      sh = { "a" => 1 }


      class Pair
        def to_ary
          [1, 2]
        end
      end

      class Tbl
        def to_hash
          { "b" => 2 }
        end
      end

      class Inert
      end

      def trace(label, value)
        puts label
        value
      end

      path = "/tmp/spinel_typed_slot_conversion.txt"
      File.write(path, "x")
      File.delete(path)

      calls = 0
      mk = -> { calls += 1; "k" }
      p [h.fetch(mk.call, 0), h.dig(mk.call), h.values_at(mk.call), calls]

    RUBY

    _(result).must_answer <<~'OUT'
      [0, nil, [nil], 3]
    OUT
  end

  it "sleep refuses a value it cannot convert into a time interval" do
    result = zr(<<~'RUBY')
      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      s = String.new("a-b")
      class Fmt
        def to_str
          "a"
        end
      end
      ENV["SPINEL_SLOT"] = "v"
      class Key
        def to_str
          "SPINEL_SLOT"
        end
      end
      class Cmd
        def to_str
          "true"
        end
      end

      a = [1, 2, 3]
      m = /(a)(b)/.match("ab")

      h = { 1 => 2 }
      sh = { "a" => 1 }


      class Pair
        def to_ary
          [1, 2]
        end
      end

      class Tbl
        def to_hash
          { "b" => 2 }
        end
      end

      class Inert
      end

      def trace(label, value)
        puts label
        value
      end

      path = "/tmp/spinel_typed_slot_conversion.txt"
      File.write(path, "x")
      File.delete(path)

      calls = 0
      mk = -> { calls += 1; "k" }

      p err { sleep(true) }
      p err { sleep(:s) }
      p err { File.utime(false, false, "/nonexistent") }

    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "can't convert TrueClass into time interval"]
      [TypeError, "can't convert Symbol into time interval"]
      [TypeError, "can't convert FalseClass into time"]
    OUT
  end

  it "Regexp.escape takes a Symbol" do
    result = zr(<<~'RUBY')
      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      s = String.new("a-b")
      class Fmt
        def to_str
          "a"
        end
      end
      ENV["SPINEL_SLOT"] = "v"
      class Key
        def to_str
          "SPINEL_SLOT"
        end
      end
      class Cmd
        def to_str
          "true"
        end
      end

      a = [1, 2, 3]
      m = /(a)(b)/.match("ab")

      h = { 1 => 2 }
      sh = { "a" => 1 }


      class Pair
        def to_ary
          [1, 2]
        end
      end

      class Tbl
        def to_hash
          { "b" => 2 }
        end
      end

      class Inert
      end

      def trace(label, value)
        puts label
        value
      end

      path = "/tmp/spinel_typed_slot_conversion.txt"
      File.write(path, "x")
      File.delete(path)

      calls = 0
      mk = -> { calls += 1; "k" }


      p Regexp.escape(:"a.b")

    RUBY

    _(result).must_answer <<~'OUT'
      "a\\.b"
    OUT
  end

  it "a to_str that answers nil reaches the row's own refusal" do
    result = zr(<<~'RUBY')
      class Sep
        def to_str
          "-"
        end
      end

      class Idx
        def to_int
          1
        end
      end

      def err
        yield
      rescue StandardError => e
        [e.class, e.message]
      end

      s = String.new("a-b")
      class Fmt
        def to_str
          "a"
        end
      end
      ENV["SPINEL_SLOT"] = "v"
      class Key
        def to_str
          "SPINEL_SLOT"
        end
      end
      class Cmd
        def to_str
          "true"
        end
      end

      a = [1, 2, 3]
      m = /(a)(b)/.match("ab")

      h = { 1 => 2 }
      sh = { "a" => 1 }


      class Pair
        def to_ary
          [1, 2]
        end
      end

      class Tbl
        def to_hash
          { "b" => 2 }
        end
      end

      class Inert
      end

      def trace(label, value)
        puts label
        value
      end

      path = "/tmp/spinel_typed_slot_conversion.txt"
      File.write(path, "x")
      File.delete(path)

      calls = 0
      mk = -> { calls += 1; "k" }



      class Needle
        def to_str
          puts "to_str asked"
          "b"
        end
      end
      misses = { "k" => "abcb" }
      p err { misses["zz"].rindex(Needle.new) }
    RUBY

    _(result).must_answer <<~'OUT'
      [NoMethodError, "undefined method 'rindex' for nil"]
    OUT
  end

  it "uncaptured inlined times param keeps the plain fast path" do
    result = zr(<<~'RUBY')
      # When NOTHING captures the `.times` param it
      # stays a plain per-iteration `let` (no cell), and `break`/`next` inside
      # the inlined block keep working via literal labels.

      total = 0
      5.times { |i| total += i }
      puts total
      r = 5.times { |i| break i * 2 if i == 3 }
      p r
    RUBY

    _(result).must_answer "10\n6\n"
  end

  it "unresolved into typed hash slot" do
    result = zr(<<~'RUBY')
      # An unresolved constant on the rhs, stored into a hash with String values
      # in VALUE position (the method tail). The NameError raise fires before the
      # store.
      class K
        def initialize = @h = { "x" => "y" }
        def put(k, v)
          @h[k] = Undef.compute(v)
        end
      end
      begin
        K.new.put("a", "b")
      rescue NameError => e
        puts e.class
      end
    RUBY

    _(result).must_answer "NameError\n"
  end
end
