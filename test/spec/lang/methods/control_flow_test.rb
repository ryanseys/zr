# frozen_string_literal: true

require "spec_helper"

describe "Methods: control flow" do
  it "ackermann" do
    result = zr(<<~'RUBY')
      def ack(m, n)
        if m == 0
          n + 1
        elsif n == 0
          ack(m - 1, 1)
        else
          ack(m - 1, ack(m, n - 1))
        end
      end
      puts ack(2, 3)
      puts ack(3, 3)
    RUBY

    _(result).must_answer "9\n61\n"
  end

  it "class method int table arg" do
    result = zr(<<~'RUBY')
      # A namespace module whose methods are all `self.` ones passes a table of int
      # arrays between two of them. Emission resolves `M.consume(...)` through the
      # class-method chain, so the narrowing pass has to resolve it the same way --
      # otherwise the argument is an unattributable escape, the table stays a boxed
      # poly array, and every helper it feeds binds a boxed parameter.
      class F
        def self.mul(a, b)
          (a * b) % 97
        end
      end

      class M
        def self.consume(rows, s)
          acc = 0
          i = 0
          while i < rows.length
            row = rows[i]
            acc += F.mul(row[0], s)
            i += 1
          end
          acc
        end
      end

      rows = Array.new(4) { |c| [c, c + 1, c + 2] }
      p M.consume(rows, 3)
    RUBY

    _(result).must_answer "18\n"
  end

  it "fib" do
    result = zr(<<~'RUBY')
      def fib(n)
        if n < 2
          n
        else
          fib(n - 1) + fib(n - 2)
        end
      end
      puts fib(20)
    RUBY

    _(result).must_answer "6765\n"
  end

  it "module singleton new user method" do
    result = zr(<<~'RUBY')
      # `module M; def self.new(x); ...; end; end` defines a user-level
      # class method, NOT a constructor (modules can't be instantiated).
      # `M.new(args)` returns what the method returns, as a sibling method
      # on the same module (`def self.edit`) does.

      module Views
        module Articles
          def self.new(x)
            "rendered_#{x}"
          end

          def self.edit(x)
            "edited_#{x}"
          end
        end
      end

      puts Views::Articles.new("a")
      puts Views::Articles.edit("b")
    RUBY

    _(result).must_answer "rendered_a\nedited_b\n"
  end

  it "nonlocal return from proc unwinds the home method" do
    result = zr(<<~'RUBY')
      # A non-lambda Proc's `return` returns from its creating method (live
      # home), including through builtin iterators and `yield`; a lambda's is
      # local.

      def simple; proc { return 30 }.call; 40; end
      p simple
      def cond(x); proc { return "yes" if x > 0 }.call; "no"; end
      p cond(5); p cond(-1)
      def multi; proc { return 1, 2, 3 }.call; [9]; end
      p multi
      def thru_each; proc { [1,2,3].each { |x| return x*10 if x==2 }; :none }.call; end
      p thru_each
      def thru_ewi; proc { [10,20,30].each_with_index { |v,i| return i if v==20 }; -1 }.call; end
      p thru_ewi
      def gives; yield; end
      def via_yield; gives { return 55 }; 66; end
      p via_yield
      def inner; proc { return "IR" }.call; "IN"; end
      def outer; x = inner; proc { return "O:#{x}" }.call; "ON"; end
      p outer
      def cd(n, acc); proc { return acc if n==0 }.call; cd(n-1, acc+n); end
      p cd(5, 0)
      def with_lambda; -> { return 30 }.call; 40; end
      p with_lambda
      def dbl(x); proc { return x*2 }.call; -1; end
      s = 0; 300.times { |i| s += dbl(i) }; p s
    RUBY

    _(result).must_answer <<~'OUT'
      30
      "yes"
      "no"
      [1, 2, 3]
      20
      1
      55
      "O:IR"
      15
      40
      89700
    OUT
  end

  it "param inference if predicate" do
    result = zr(<<~'RUBY')
      # A parameter whose only uses are in an if-predicate or an else-branch.
      # Those uses must count when the compiler infers the parameter's type
      # from the method body.
      #
      # Body shape:
      #   def update(p)
      #     if p.title.nil?      # predicate uses p
      #       nil
      #     else
      #       self.title = p.title   # else-branch uses p
      #     end
      #   end
      #
      # Two user classes (P, Other) define `title`, so a wrong guess picks the
      # wrong class.

      class P
        def title
          @title
        end
        def title=(v)
          @title = v
        end
        def body
          @body
        end
        def body=(v)
          @body = v
        end
      end

      class App
        # `p` is used ONLY inside the if-predicate (`p.title.nil?`),
        # nowhere in the IfNode's body or else-branch.
        def status(p)
          if p.title.nil?
            "no-title"
          else
            "has-title"
          end
        end
      end

      # IMPORTANT: don't call `App#status` directly — a call site would
      # give `p` its type. The test checks that inference from the body
      # works without a call site, when two user classes (P, Other)
      # define `title`.

      class Other
        def title; "wrong"; end
      end

      # Pin both classes' instances at the top level so they appear in
      # the symbol table.
      o = Other.new
      puts o.title             # wrong

      q = P.new
      q.title = "hello"
      puts q.title             # hello

      # `App#status` is defined but never called, so only its body
      # gives `p`'s type.
      puts "compiled-cleanly"
    RUBY

    _(result).must_answer <<~'OUT'
      wrong
      hello
      compiled-cleanly
    OUT
  end

  it "splat return" do
    result = zr(<<~'RUBY')
      # `return *x` returns the splat-to-array of x: a scalar wraps in a one-element
      # array, an array stays itself, nil becomes [].
      def f(x); return *x; end
      p f(1)              # [1]
      p f([1, 2, 3])      # [1, 2, 3]
      p f(nil)            # []
      p f("hi")           # ["hi"]
      p f([])             # []

      # The returned array is a real Array usable downstream.
      p f(5).map { |n| n * 2 }        # [10]
      p f([1, 2]).sum                 # 3

      # A conditional splat return alongside an ordinary return keeps both typed as
      # an array (the method return unifies to a poly array).
      def g(x)
        return *x if x
        [0]
      end
      p g(3)              # [3]
      p g(nil)            # [0]

      # A conditional splat return whose other branch is a non-array (scalar) forces
      # the method return type to poly (not a poly array), so the splat value is
      # boxed rather than array-typed. It must still splat-to-array correctly.
      def hp(cond, x)
        return *x if cond
        1
      end
      p hp(true, [1, 2])  # [1, 2]
      p hp(false, nil)    # 1
      p hp(true, 5)       # [5]
      p hp(true, nil)     # []
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [1, 2, 3]
      []
      ["hi"]
      []
      [10]
      3
      [3]
      [0]
      [1, 2]
      1
      [5]
      []
    OUT
  end

  it "tak" do
    result = zr(<<~'RUBY')
      def tak(x, y, z)
        if y < x
          tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y))
        else
          z
        end
      end
      puts tak(18, 12, 6)
    RUBY

    _(result).must_answer "7\n"
  end
end
