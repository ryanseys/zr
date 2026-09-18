# frozen_string_literal: true

require "spec_helper"

describe "Blocks: evaluating a string" do
  it "eval control flow yields last expression" do
    result = ze0(<<~'RUBY')
      src = "if 1 < 2 then :yes else :no end"; puts eval(src)
    RUBY

    _(result).must_answer "yes\n"
  end

  it "eval yield needs a def not a block" do
    result = ze0(<<~'RUBY')
      # `Invalid yield`: which snippet shapes carry a block channel and which do not.
      # A `def` opens one, so a `yield` under it compiles however deeply it is
      # nested. Nothing else does -- a lambda, an ordinary block, and a
      # `define_method` block are all refused, and refused at COMPILE time, before
      # the snippet runs a statement.
      #
      # zeo got two of these wrong, in opposite directions.
      #
      # A `class << self` body lowers to BOTH a `DefMethod` and the
      # `define_method`-shaped `Lambda` that installs it at run time, sharing one
      # body. The walk arrived through the Lambda, where a guard on the `DefMethod`
      # NODE never fires -- so the def's own `yield` was refused. That is bundler's
      # shape: `time.rb`'s `class << self; def strptime(...) ... yield(year)` made
      # `require "bundler/setup"` refuse the whole file.
      #
      # The other direction: a literal `define_method(:x) { ... }` desugars into a
      # `DefMethod` too, and guarding on the node alone let its block's `yield`
      # through, where ruby refuses. `is_def` is what tells the two apart.

      SRCS = [
        "def f1; yield; end",
        "def g1; if true; yield; end; end",
        "module M1; class << self; def t(n); yield n; end; end; end",
        "module M2; def self.t(n); yield n; end; end",
        "class K1; def t; [1].each { yield }; end; end",
        "-> { yield }",
        "[1].each { yield }",
        "yield",
        "class C1; define_method(:x) { yield }; end",
        "class C2; class << self; define_method(:x) { yield }; end; end",
      ]

      i = 0
      while i < SRCS.size
        src = SRCS[i]
        begin
          eval(src)
          puts "compiles  #{src}"
        rescue SyntaxError
          puts "refused   #{src}"
        rescue StandardError => e
          puts "#{e.class}  #{src}"
        end
        i += 1
      end

      # The refusal is a catchable SyntaxError naming the yield's own line.
      begin
        eval("1\n2\nyield\n")
      rescue SyntaxError => e
        puts e.message.split(": ").last
      end

      # ...and a `def` written in the snippet really does yield when called.
      eval("def zz(n); yield n; end")
      p zz(3) { |v| v + 1 }
    RUBY

    _(result).must_answer <<~'OUT'
      compiles  def f1; yield; end
      compiles  def g1; if true; yield; end; end
      compiles  module M1; class << self; def t(n); yield n; end; end; end
      compiles  module M2; def self.t(n); yield n; end; end
      compiles  class K1; def t; [1].each { yield }; end; end
      refused   -> { yield }
      refused   [1].each { yield }
      refused   yield
      refused   class C1; define_method(:x) { yield }; end
      refused   class C2; class << self; define_method(:x) { yield }; end; end
      Invalid yield
      4
    OUT
  end

  it "instance eval block params" do
    result = ze0(<<~'RUBY')
      # instance_eval block-param shapes: self-bound first arg, extras
      # bind to nil. Lifted sp_ieval_<N> still takes only `self`.

      # ---- 1. Explicit-empty `{ || ... }` ----
      class Box
        def initialize
          @v = 0
        end

        def v
          @v
        end
      end

      b1 = Box.new
      b1.instance_eval { || @v = 42 }
      puts b1.v               # 42

      b1.instance_eval { @v = 7 }
      puts b1.v               # 7

      # ---- 2. Single self-bound `{ |x| ... }` (read) ----
      class Counter
        def initialize
          @n = 0
        end

        def add(k)
          @n = @n + k
        end

        def n
          @n
        end
      end

      c = Counter.new
      c.instance_eval { |me| me.add(5) }
      puts c.n                # 5

      c.instance_eval { |obj| obj.add(3); obj.add(7) }
      puts c.n                # 15

      # ---- 3. Extras default nil `{ |x, y, z| ... }` ----
      class Foo
        def value
          42
        end
      end

      f = Foo.new
      puts f.instance_eval { |a| a.value }              # 42
      puts f.instance_eval { |a, b| a.value }           # 42
      puts f.instance_eval { |a, b, c| a.value }        # 42

      # ---- 4. Self-bound write `{ |x| x = ...; x.method }` ----
      # Reassigning x rebinds the local, not the block's self -- a
      # keeps only the first add.
      a = Counter.new
      a.instance_eval { |x|
        x.add(1)
        x = Counter.new
        x.add(10)
        x.add(20)
      }
      puts a.n                # 1

      # ---- 5. Numbered param `{ _1.method }` ----
      class Tally
        def initialize
          @x = 0
        end

        def bump
          @x = @x + 1
        end

        def add(k)
          @x = @x + k
        end

        def x
          @x
        end
      end

      t = Tally.new
      t.instance_eval { _1.bump }
      t.instance_eval { _1.bump }
      t.instance_eval { _1.add(10) }
      puts t.x                # 12

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      7
      5
      15
      42
      42
      42
      1
      12
      done
    OUT
  end

  it "issue eval arg forwarding in proc" do
    result = ze0(<<~'RUBY')
      # `def m(...)` inside a proc built by `eval` -- forwardable's `def_delegators`
      # generates exactly this and `module_eval`s the result, so every gem that
      # delegates (csv, others) depends on it. The eval-VM's parser rejects the
      # `(...)` forwarding here and reports `unexpected 'do', ignoring it`.
      class C; end
      src = "proc do\n  def a3(...)\n    _ = \"z\"\n    _.upcase(...)\n  end\nend"
      C.module_eval(&eval(src))
      p C.new.a3

      # The same method spelled without forwarding compiles fine, which is what
      # narrows the blame to `(...)`.
      class D; end
      D.module_eval(&eval("proc do\n  def ok(*args)\n    \"z\".upcase(*args)\n  end\nend"))
      p D.new.ok
    RUBY

    _(result).must_answer <<~'OUT'
      "Z"
      "Z"
    OUT
  end

  it "nested block needs the binding self" do
    result = ze0(<<~'RUBY')
      # A block nested inside another block, in a program that anywhere asks a Proc
      # for its `binding`. The inner Proc's construction carries a Binding of the
      # scope it is WRITTEN in -- the outer block -- and that Binding holds the
      # outer block's `self`. Zeo built the Binding in the outer block's own
      # prelude, inside the closure that captures by value, while the outer block
      # took no `self` parameter of its own because nothing it does mentions
      # `self`. So the closure swallowed the method's receiver whole: a closure
      # cannot consume a value it only captures, and the method lost it for good.
      #
      # irb is written this way throughout -- `irb.suspend_name(path) { |io|
      # irb.suspend_input_method(io) { |back_io| ... } }` in ext/loader.rb -- and it
      # accounted for 41 of the 51 compile errors the vendored gem produced.
      class Wrapper
        def wrap
          yield "w"
        end
      end

      class Host
        def initialize
          @tag = "t"
        end

        def run(path)
          w = Wrapper.new
          acc = []
          w.wrap do |a|
            acc << path
            w.wrap do |b|
              acc << (a + b)
            end
          end
          [acc, @tag]
        end

        # The same nesting where the inner block is a lambda, and where the outer
        # one really does reach for the Binding.
        def peek
          w = Wrapper.new
          seen = nil
          w.wrap do |a|
            inner = -> { a.upcase }
            seen = binding.local_variables.sort
            inner.call
          end
          seen
        end
      end

      h = Host.new
      p h.run("a")
      p h.peek

      # What made the whole scope a binding scope in the first place.
      p proc { 1 }.binding.class
      p proc { 1 }.binding.receiver.class

      # The receiver a nested block's Binding reports is the enclosing `self`, not
      # the block's own -- the value that used to be moved away.
      class Reporter
        def call
          outer = nil
          [1].each do |x|
            outer = proc { x }.binding.receiver
          end
          outer
        end
      end

      p Reporter.new.call.class
    RUBY

    _(result).must_answer <<~'OUT'
      [["a", "ww"], "t"]
      [:a, :inner, :seen, :w]
      Binding
      Object
      Reporter
    OUT
  end

  it "proc binding" do
    result = ze0(<<~'RUBY')
      # `Proc#binding` answers the scope the block was WRITTEN in -- that scope's
      # `self` and its locals, shared by reference, never the block's own locals
      # (which do not exist until it runs). A proc with no Ruby scope behind it is
      # CRuby's "C level Proc".

      def make
        a = 1
        pr = proc { b = 2; a }
        pr
      end

      puts "-- the defining scope --"
      pb = make.binding
      p pb.class
      p pb.local_variables
      p pb.local_variable_get(:a)
      p pb.receiver.class
      p pb.source_location.first.end_with?("proc_binding.rb")
      p pb.frozen?

      puts "-- one environment, distinct objects --"
      pr = proc { }
      p pr.binding.equal?(pr.binding)
      p pr.binding.local_variable_defined?(:pr)

      puts "-- shared with the running proc --"
      def counted
        c = 5
        pr = proc { c += 1 }
        pr.call
        [pr.binding.local_variable_get(:c), c]
      end
      p counted

      puts "-- lambdas and block parameters keep theirs too --"
      l = lambda { |q| q }
      p l.binding.class
      p l.binding.local_variables
      def taking(&b) = b
      p taking { 1 }.binding.local_variables

      puts "-- the proc's OWN binding is a different scope --"
      def two
        o = 1
        inner = proc { i = 2; binding }
        [inner.binding.local_variables, inner.call.local_variables]
      end
      p two

      puts "-- a proc with no Ruby scope --"
      begin
        :upcase.to_proc.binding
      rescue ArgumentError => e
        p [e.class, e.message]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      -- the defining scope --
      Binding
      [:a, :pr]
      1
      Object
      true
      false
      -- one environment, distinct objects --
      false
      true
      -- shared with the running proc --
      [6, 6]
      -- lambdas and block parameters keep theirs too --
      Binding
      [:pb, :pr, :l, :e]
      [:pb, :pr, :l, :e]
      -- the proc's OWN binding is a different scope --
      [[:o, :inner], [:i, :o, :inner]]
      -- a proc with no Ruby scope --
      [ArgumentError, "Can't create Binding from C level Proc"]
    OUT
  end

  it "proc recursive" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A proc reaching itself through a captured local.
      # At exit: cycle leak: 4 objects (Proc x2, cell x2)
      # A proc/lambda that refers to its own binding recurses through the
      # captured cell. Each body has a single recursive `.call` per expression;
      # two poly-returning proc calls in one expression (e.g. naive fib) instead
      # exercise the shared poly-return slot, an orthogonal limitation.
      fact = proc { |n| n <= 1 ? 1 : n * fact.call(n - 1) }
      p fact.call(5)

      f = ->(n) { n <= 1 ? 1 : n * f.call(n - 1) }
      p f.call(6)
    RUBY

    _(result).must_answer <<~'OUT'
      120
      720
    OUT
  end

  it "runtime eval defines methods and runs blocks" do
    result = ze0(<<~'PROGRAM')
      # The M8 eval-VM tail: `def` inside `eval`/`class_eval`/`instance_eval`
      # (installing on the right definee), optional+rest+keyword params, `return`
      # and `yield` in an eval-defined method, and blocks + auto-splat passed to
      # calls inside eval. Each source is non-literal (held in a variable / built
      # with a heredoc) so it runs through the runtime `eval`, not the inline
      # splice. Output oracle-verified verbatim.

      code = <<~RUBY
        def calc(a, b = 10, *rest)
          return a + b if rest.empty?
          a + b + rest.sum
        end
      RUBY
      eval(code)
      puts calc(1)
      puts calc(1, 2, 3, 4)
      eval("def each_twice; yield 1; yield 2; end")
      out = []
      each_twice { |n| out << n * 10 }
      p out
      class Widget; end
      Widget.class_eval("def name; \"widget\"; end")
      puts Widget.new.name
      obj = Object.new
      obj.instance_eval("def secret; 42; end")
      puts obj.secret
      p Object.new.respond_to?(:secret)
      eval("def kw(a, x:, y: 5); [a, x, y]; end")
      p kw(1, x: 2)
      begin; kw(1); rescue ArgumentError => e; puts e.message; end
      begin; calc; rescue ArgumentError => e; puts e.message; end
      p eval("[1, 2, 3].map { |x| x * 2 }")
      p eval("[[1, 2], [3, 4]].map { |a, b| a + b }")
      p eval("def foo; end")
    PROGRAM

    _(result).must_answer <<~'OUT'
      11
      10
      [10, 20]
      widget
      42
      false
      [1, 2, 5]
      missing keyword: :x
      wrong number of arguments (given 0, expected 1+)
      [2, 4, 6]
      [3, 7]
      :foo
    OUT
  end
end
