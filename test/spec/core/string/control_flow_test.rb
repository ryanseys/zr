# frozen_string_literal: true

require "spec_helper"

describe "String: control flow" do
  it "case when string range nil bound" do
    result = zr(<<~'RUBY')
      # A nil endpoint of a string range (here an unset String ivar, which reads as a
      # NULL slot) is an OPEN bound under Range#=== / case-when, exactly like CRuby:
      # `(nil.."m") === "c"` is true. The endpoint must not be dereferenced by strcmp,
      # and must widen its side rather than fail the match.
      class Bounds
        def initialize(set_lo, set_hi)
          @lo = "d" if set_lo
          @hi = "m" if set_hi
        end
        def classify(s)
          case s
          when @lo..@hi then "in"
          else "out"
          end
        end
      end

      p Bounds.new(false, true).classify("c")   # open lower, "c" <= "m"  -> in
      p Bounds.new(false, true).classify("z")   # open lower, "z" >  "m"  -> out
      p Bounds.new(true, false).classify("f")   # "f" >= "d", open upper  -> in
      p Bounds.new(true, false).classify("a")   # "a" <  "d"              -> out
      p Bounds.new(true, true).classify("g")    # "d" <= "g" <= "m"       -> in
      p Bounds.new(false, false).classify("x")  # both open               -> in
    RUBY

    _(result).must_answer <<~'OUT'
      "in"
      "out"
      "in"
      "out"
      "in"
      "in"
    OUT
  end

  it "default nil param with str return" do
    result = zr(<<~'RUBY')
      # A method with `default = nil` whose body also returns a String from
      # another path: the function return type was `const char *` (string?)
      # but the param slot stayed `mrb_int` (the literal nil's int default),
      # so `return default` failed C compile. Fixed in #447.

      class Bag
        def initialize
          @data = {}
          @data["a"] = "alpha"
        end

        def fetch(key, default = nil)
          return @data[key] if @data.key?(key)
          default
        end
      end

      b = Bag.new
      puts b.fetch("a")
      puts b.fetch("missing").nil?

      # Top-level method variant.
      def lookup(map, key, default = nil)
        return map[key] if map.key?(key)
        default
      end

      m = { "x" => "ex" }
      puts lookup(m, "x")
      puts lookup(m, "z").nil?
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      true
      ex
      true
    OUT
  end

  it "loop do end with break value" do
    result = zr(<<~'RUBY')
      i = 0
      result = loop do
        i += 1
        break i * 10 if i == 3
      end
      puts result
    RUBY

    _(result).must_answer "30\n"
  end

  it "method return mixed int string" do
    result = zr(<<~'RUBY')
      # A method whose return paths mix a genuine int (an int literal or a
      # param-sourced int ivar) with a string must box its return to poly so
      # the int arm is not silently returned through the string pointer slot.
      class Record
        def initialize(id, name)
          @id = id
          @name = name
        end

        # Both arms are ivar reads; the unify picks "string", hiding the int
        # @id arm inside the tail IfNode.
        def [](field)
          if field == 0
            @id
          else
            @name
          end
        end
      end

      r = Record.new(7, "hi")
      puts r[0]
      puts r[1]
      p r[0]
      p r[1]

      # Int literal buried in a branch, string in the other.
      class Tagged
        def initialize(s)
          @s = s
        end

        def value(numeric)
          if numeric
            100
          else
            @s
          end
        end
      end

      t = Tagged.new("text")
      puts t.value(true)
      puts t.value(false)
      p t.value(true)
      p t.value(false)

      # The exact reported shape: a case/when field lookup over literal-init
      # ivars of mixed types.
      class Row
        def initialize
          @id = 7
          @name = "hi"
        end

        def [](field)
          case field
          when :id then @id
          when :name then @name
          end
        end
      end

      p Row.new[:id]
      p Row.new[:name]
    RUBY

    _(result).must_answer <<~'OUT'
      7
      hi
      7
      "hi"
      100
      text
      100
      "text"
      7
      "hi"
    OUT
  end

  it "module cls method string return" do
    result = zr(<<~'RUBY')
      # Issue #127: a module-level singleton method (`module M; def self.X; ... end; end`)
      # whose body returns a non-int value used to be typed as `mrb_int` at every
      # call site. Capturing to a local emitted `mrb_int = const char *` (compile
      # error under -Werror); inline `puts M.X` compiled but printed the pointer
      # as an integer. The class form (same shape inside `class C`) already worked.
      # Fix is in `infer_constant_recv_type`: walk `@meth_return_types` for
      # `<Module>_cls_<method>` the same way the class branch walks `@cls_cmeth_returns`.

      # 1. Module + def self + String return + local capture — the failing shape.
      module M1
        def self.greet
          "hello"
        end
      end

      s = M1.greet
      puts s                              # hello

      # 2. Module + def self + String return + inline puts — same root, different consumer.
      module M2
        def self.greet
          "world"
        end
      end

      puts M2.greet                       # world

      # 3. Module + def self + Float return — non-int isn't string-specific.
      module M3
        def self.pi
          3.14
        end
      end

      puts M3.pi                          # 3.14

      # 4. Class + def self + String return — the path that already worked. Regression guard.
      class C1
        def self.greet
          "from class"
        end
      end

      t = C1.greet
      puts t                              # from class

      # 5. Top-level def returning String — separate inference path. Regression guard.
      def top_greet
        "top"
      end

      u = top_greet
      puts u                              # top
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      world
      3.14
      from class
      top
    OUT
  end

  it "next value each slice" do
    result = zr(<<~'RUBY')
      # `next <value>` through each_slice(n).map contributes the value.
      p [1, 2, 3, 4].each_slice(2).map { |a, b| next 0 if a == 1; a + b }   # [0, 7]
      p [1, 2, 3, 4, 5].each_slice(2).map { |a, b| a }                      # [1, 3, 5]
    RUBY

    _(result).must_answer "[0, 7]\n[1, 3, 5]\n"
  end

  it "param widens when body assigns string" do
    result = zr(<<~'RUBY')
      # A method body that reassigns one of its parameters to a value
      # of an incompatible type (here: int call sites + string body
      # write) needs the param's slot widened to `poly` so the
      # generated C can hold both shapes via sp_RbVal. Without the
      # widening the parameter slot stays at the call-site-inferred
      # `mrb_int`, and the body's `lv_x = "forever"` assignment is
      # `mrb_int = const char *` — rejected by gcc under
      # `-Wint-conversion`.

      class Logger
        def report(label, hclk)
          hclk = "forever" if hclk == 4294967295
          puts label
          puts hclk
        end
      end

      l = Logger.new
      l.report("running", 1234)
      l.report("running", 4294967295)
      l.report("done", 17)
    RUBY

    _(result).must_answer <<~'OUT'
      running
      1234
      running
      forever
      done
      17
    OUT
  end

  it "str array max min by" do
    result = zr(<<~'RUBY')
      # Issue #863: max_by / min_by on String arrays return the element,
      # not the score (and not 0).
      puts ["hello", "hi", "goodbye"].max_by { |s| s.length }
      puts ["hello", "hi", "goodbye"].min_by { |s| s.length }
      # Negation flips the ordering.
      puts ["a", "bb", "ccc"].max_by { |s| -s.length }
    RUBY

    _(result).must_answer <<~'OUT'
      goodbye
      hi
      a
    OUT
  end

  it "oct is a lenient base-8 parse: whitespace, a sign, a base prefix and underscore separators" do
    result = zr(<<~'RUBY')
      # String#oct is a lenient Integer(str, 8)-style parse: leading whitespace, an
      # optional sign, an optional base prefix (0x/0b/0o/0d or a leading 0 = octal),
      # and single underscore separators between digits. Spinel previously mishandled
      # a sign before a base prefix, dropped underscore separators, and ignored the 0d
      # prefix.
      def o(x); x.oct; end

      p o("777")        # 511
      p o("17")         # 15
      p o("-0b1010")    # -10  (sign before base prefix)
      p o("+17")        # 15
      p o("1_0")        # 8    (underscore separator, octal)
      p o("0x1f")       # 31
      p o("0o17")       # 15
      p o("0b11")       # 3
      p o("0d99")       # 99   (0d = decimal prefix)
      p o("  0b11")     # 3    (leading whitespace)
      p o("0xff_ff")    # 65535
      p o("0b1_1")      # 3

      # Lenient stops and invalid forms return what was parsed (or 0).
      p o("88")         # 0    (8 is not an octal digit)
      p o("17x")        # 15   (stops at 'x')
      p o("1_")         # 1    (trailing underscore)
      p o("1__0")       # 1    (doubled underscore stops)
      p o("_1")         # 0    (leading underscore)
      p o("0b_1")       # 0    (underscore right after prefix)
      p o("")           # 0
    RUBY

    _(result).must_answer <<~'OUT'
      511
      15
      -10
      15
      8
      31
      15
      3
      99
      3
      65535
      3
      0
      15
      1
      1
      0
      0
      0
    OUT
  end
end
