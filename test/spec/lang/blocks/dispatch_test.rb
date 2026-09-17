# frozen_string_literal: true

require "spec_helper"

describe "Blocks: dispatch" do
  it "block forward poly" do
    result = ze0(<<~'RUBY')
      # Forwarding a callable value into poly-element collections. Now that poly
      # values round-trip through proc parameters, &proc / &lambda / &:sym / &method
      # forward into poly arrays, and a Method object forwards into Hash#each (the
      # [k, v] pair is passed as a single array argument through the array ABI).
      # Distinct per-type helpers keep the receiver element types monomorphic.
      def poly(a) = a
      def ints(a) = a

      mixed = poly([1, "two", :three, 4.5])

      # proc / lambda / sym / method values into a poly-array map
      dbl = ->(x) { [x, x] }
      p mixed.map(&dbl)                 # [[1, 1], ["two", "two"], [:three, :three], [4.5, 4.5]]
      p mixed.map(&:to_s)              # ["1", "two", "three", "4.5"]
      def insp(x) = x.inspect
      p mixed.map(&method(:insp))      # ["1", "\"two\"", ":three", "4.5"]

      # select over a poly array with a predicate proc value
      is_int = ->(x) { x.is_a?(Integer) }
      p mixed.select(&is_int)          # [1]

      # a forwarded proc with a non-int (String) return over an int array
      nums = ints([1, 2, 3])
      label = ->(x) { "n#{x}" }
      p nums.map(&label)               # ["n1", "n2", "n3"]

      # hash each / each_key / each_value forwarded to a Method object
      def show(pair) = p(pair)
      def showk(k) = p(k)
      def showv(v) = p(v)
      h = { a: 10, b: 20 }
      h.each(&method(:show))           # [:a, 10] / [:b, 20]
      h.each_key(&method(:showk))      # :a / :b
      h.each_value(&method(:showv))    # 10 / 20
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 1], ["two", "two"], [:three, :three], [4.5, 4.5]]
      ["1", "two", "three", "4.5"]
      ["1", "\"two\"", ":three", "4.5"]
      [1]
      ["n1", "n2", "n3"]
      [:a, 10]
      [:b, 20]
      :a
      :b
      10
      20
    OUT
  end

  it "block forward poly receiver" do
    result = ze0(<<~'RUBY')
      # A &block-forwarding method reached through an Array element (a typed array
      # element = concrete class; a heterogeneous array element = poly value): the
      # block must land, not drop to a C compile error or a silent zero iterations.
      class Roster
        def initialize; @items = {}; end
        def add(key, value); @items[key] = value; end
        def each_item(&block); @items.each_value(&block); end
      end

      # typed array element -> concrete Roster receiver
      wrapped = [Roster.new]
      wrapped[0].add(1, "x")
      count = 0
      wrapped[0].each_item { |v| count += 1 }
      puts "count=#{count}"

      # heterogeneous array element -> poly receiver
      def make_pair
        r = Roster.new
        r.add(1, "x")
        [r, { 1 => false }]
      end
      pair = make_pair
      roster = pair[0]
      c2 = 0
      roster.each_item { |v| c2 += 1 }
      puts "c2=#{c2}"
    RUBY

    _(result).must_answer <<~'OUT'
      count=1
      c2=1
    OUT
  end

  it "block forwarded into poly capture" do
    result = ze0(<<~'RUBY')
      # A block whose target hands it on to a poly receiver.
      #
      # `TreeNode#each` is yield-inlined -- its `&blk` calls are spliced at the call
      # site -- so nothing marked the block as escaping. But the spliced body ends in
      # `k.each(&blk)` on a poly receiver, and THAT dispatch materializes the block
      # as a real proc. Without cells for its captures the emitter had to refuse the
      # program; and the dispatch itself tried to build a fresh proc literal out of
      # the `&blk` forwarding rather than passing the proc it already names.
      #
      # The same shape through a constant receiver: a constant that names no class is
      # an ordinary value, so it is typed like any other receiver.

      class TreeNode
        def initialize(v)
          @v = v
          @kids = []
        end

        def add(n)
          @kids << n
          self
        end

        def each(&blk)
          blk.call(@v)
          @kids.each { |k| k.each(&blk) }
        end
      end

      def pick(flag)
        flag ? TreeNode.new(1).add(TreeNode.new(2)) : [3, 4]
      end

      src = pick(false)
      total = 0
      src.each do |x|
        total += x
      end
      p total

      src2 = pick(true)
      seen = []
      src2.each do |x|
        seen << x
      end
      p seen

      SRC = pick(true)
      CONFIG = begin
        hash = {}
        SRC.each do |x|
          hash[x] = x * 2
        end
        hash
      end
      p CONFIG.length
      p CONFIG[2]
    RUBY

    _(result).must_answer <<~'OUT'
      7
      [1, 2]
      2
      4
    OUT
  end

  it "count block poly pred" do
    result = ze0(<<~'RUBY')
      # count { |x| <poly value> } used the block value directly as a C condition;
      # a poly (sp_RbVal) predicate is a struct, invalid in `if (...)` (#1508).
      # Routing it through emit_cond makes any predicate a valid truthiness test.
      items = [1, nil, "x", false, 2, true]
      p items.count { |x| x }              # truthy: 1, "x", 2, true -> 4
      p items.count { |x| x.nil? }         # 1
      mixed = [1, "two", 3, "four", 5]
      p mixed.count { |x| x.is_a?(Integer) }
    RUBY

    _(result).must_answer <<~'OUT'
      4
      1
      3
    OUT
  end

  it "curry in poly slot" do
    result = ze0(<<~'RUBY')
      l001 = ->(x001) { x001 }
      r001 = (l001.curry rescue $!.class)
      p r001.class

      r002 = (begin; l001.curry; rescue; nil; end); p r002.class                          # Spinel: NilClass
      r003 = (l001.curry rescue nil); p r003.class                                        # Spinel: NilClass
      r004 = (l001.curry(1) rescue $!.class); p r004.class                                # Spinel: NilClass
      r005 = (->(a005, b005) { a005 + b005 }.curry rescue $!.class); p r005.class         # Spinel: NilClass
      fs006 = [->(x006) { x006 }]; r006 = (fs006[0].curry rescue $!.class); p r006.class  # Spinel: NilClass

      p((l001.curry rescue $!.class).call(5))   # Ruby: 5   Spinel: 0

      p(l001.curry.class)                                    # => Proc
      c007 = l001.curry; p c007.class                        # => Proc
      fs008 = [->(x008) { x008 }]
      p(fs008[0].curry.class)                                # => Proc
      r009 = (l001.arity rescue $!.class); p r009.class      # => Integer
      r010 = (l001.lambda? rescue $!.class); p r010.class    # => TrueClass
      r011 = (l001.to_proc rescue $!.class); p r011.class    # => Proc
      r012 = (l001.call(1) rescue $!.class); p r012.class    # => Integer
    RUBY

    _(result).must_answer <<~'OUT'
      Proc
      Proc
      Proc
      Proc
      Proc
      Proc
      5
      Proc
      Proc
      Proc
      Integer
      TrueClass
      Proc
      Integer
    OUT
  end

  it "forwarded proc to poly iterator" do
    result = ze0(<<~'RUBY')
      # `xs.each(&proc)` on a receiver whose type is only known at run time drove an
      # empty loop body: the appends simply vanished.
      def poly(n)
        n > 0 ? [5, 6] : nil
      end

      out = []
      k = proc { |v| out << v }
      poly(1).each(&k)
      p out

      def run(xs)
        acc = []
        xs.each do |row|
          h = proc { |v| acc << v }
          row.each(&h)
        end
        acc
      end

      p run([[1], [2, 3]])

      # the typed receivers keep working
      t = []
      g = proc { |v| t << v * 2 }
      [1, 2].each(&g)
      p t

      # each_with_index through the same path
      seen = []
      w = proc { |v, i| seen << "#{i}:#{v}" }
      poly(1).each_with_index(&w)
      p seen

      # value-returning forms take the same driver
      def poly2(n)
        n > 0 ? [1, 2, 3] : nil
      end

      dbl = proc { |v| v * 10 }
      p poly2(1).map(&dbl)
      odd = proc { |v| v.odd? }
      p poly2(1).select(&odd)
      p poly2(1).reject(&odd)
      p poly2(1).map(&:to_s)
      p poly2(1).find(&odd)
      p poly2(1).count(&odd)

      # a Hash receiver still answers its own face
      def polyh(n)
        n > 0 ? { "a" => 1, "b" => 2 } : nil
      end
      pair = proc { |k, v| "#{k}=#{v}" }
      p polyh(1).map(&pair)

      # non-integer elements through the same driver
      def polys(n)
        n > 0 ? ["a", "b"] : nil
      end
      up = proc { |v| v.upcase }
      p polys(1).map(&up)
      seen2 = []
      coll = proc { |v| seen2 << v }
      polys(1).each(&coll)
      p seen2
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 6]
      [1, 2, 3]
      [2, 4]
      ["0:5", "1:6"]
      [10, 20, 30]
      [1, 3]
      [2]
      ["1", "2", "3"]
      1
      2
      ["a=1", "b=2"]
      ["A", "B"]
      ["a", "b"]
    OUT
  end

  it "poly blockless each" do
    result = ze0(<<~'RUBY')
      [[1, 2]].each { |a001| p a001.each.to_a }
      p [[1, 2], [3]].map { |a| a.each.to_a }
      [[1, 2]].each { |a| e = a.each; p e.next; p e.next }
      [["x", "y"]].each { |a| p a.each.map { |s| s.upcase } }
      h = { k: [1, 2] }
      p h[:k].each.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [[1, 2], [3]]
      1
      2
      ["X", "Y"]
      [1, 2]
    OUT
  end

  it "poly count block arg hoist" do
    _(ze0(<<~'RUBY')).must_answer "2\n"
      # `cell.neighbors.count { |n| Kind.walkable?(n.kind) }` on a poly receiver.
      #
      # The count arm wrote "if (sp_poly_truthy(" into the statement stream and then
      # emitted the condition into that same buffer, so a rooted argument temp the
      # condition had to hoist -- a declaration -- landed in the middle of the
      # expression and the generated C did not parse.

      module Kind
        def self.walkable?(k)
          k == 1
        end
      end

      class Cell
        attr_accessor :kind, :neighbors
        def initialize(k)
          @kind = k
          @neighbors = []
        end

        def link(c)
          @neighbors << c
        end
      end

      class Blank
        attr_accessor :kind, :neighbors
        def initialize
          @kind = nil
          @neighbors = {}
        end
      end

      def pick(flag, k)
        flag ? Cell.new(k) : Blank.new
      end

      a = pick(true, 1)
      a.link(pick(true, 1))
      a.link(pick(true, 0))
      a.link(pick(true, 1))
      p a.neighbors.count { |n| Kind.walkable?(n.kind) }
    RUBY
  end

  it "poly dispatch block arg" do
    result = ze0(<<~'RUBY')
      # A poly receiver dispatching to a method that takes `&blk`.
      #
      # The dispatch built its arm from the parameter list alone, and a `&blk`
      # parameter is not in it -- so the call went out one argument short of the
      # function it named. Ill-typed C, caught only by -Werror.
      #
      # The proc is materialized once, ahead of the switch, and shared by every arm:
      # only one arm runs, so building it per candidate class would allocate a proc
      # per class for nothing.

      class A
        def go(&blk)
          blk ? 10 : -1
        end

        def label
          "A"
        end
      end

      class B
        def go(&blk)
          blk ? 20 : -2
        end

        def label
          "B"
        end
      end

      def pick(n)
        n == 1 ? A.new : B.new
      end

      p pick(1).go { |v| v }
      p pick(2).go { |v| v }
      p pick(1).go
      p pick(2).go

      # the same dispatch with no block involved still works
      p pick(1).label
      p pick(2).label

      # a method taking both parameters and a block
      class P
        def run(a, b, &blk)
          blk ? a + b : a - b
        end
      end

      class Q
        def run(a, b, &blk)
          blk ? a * b : 0
        end
      end

      def pick2(n)
        n == 1 ? P.new : Q.new
      end

      p pick2(1).run(3, 4) { |x| x }
      p pick2(2).run(3, 4) { |x| x }
      p pick2(1).run(3, 4)
      p pick2(2).run(3, 4)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      -1
      -2
      "A"
      "B"
      7
      12
      -1
      0
    OUT
  end

  it "poly dispatch block capture" do
    result = ze0(<<~'RUBY')
      # A block passed to a poly receiver, capturing an enclosing local.
      #
      # The dispatch materializes the block as a real proc once, ahead of the switch,
      # for any candidate that takes a real &block or is served by a proc-form clone.
      # That proc is as escaping as any other, so its captures need heap cells -- but
      # nothing decided that, because no single resolved method names the target the
      # way a monomorphic receiver does. Codegen then met a capture with no storage
      # and refused the whole call.
      #
      # Reachable only once a yielding method became poly-dispatchable at all: before
      # that the arm did not exist, so the same source raised NoMethodError at run
      # time instead.

      class A
        def each_x
          yield 1
          yield 2
        end
      end

      class B
        def each_x
          yield 10
        end
      end

      def pick(n)
        n == 1 ? A.new : B.new
      end

      # read of a captured hash
      h = { 1 => "one", 2 => "two", 10 => "ten" }
      out = []
      pick(1).each_x { |k| out << h[k] }
      pick(2).each_x { |k| out << h[k] }
      p out

      # write to a captured integer: the cell is what makes the write visible here
      total = 0
      pick(1).each_x { |k| total += k }
      p total
      pick(2).each_x { |k| total += k }
      p total

      # a captured string, reassigned in the block
      label = ""
      pick(1).each_x { |k| label = label + k.to_s }
      p label

      # the same, through a method taking a real &block rather than yielding
      class P
        def run(&blk)
          blk.call(3)
        end
      end

      class Q
        def run(&blk)
          blk.call(4)
        end
      end

      def pick2(n)
        n == 1 ? P.new : Q.new
      end

      base = 100
      p pick2(1).run { |v| base + v }
      p pick2(2).run { |v| base + v }

      acc = []
      pick2(1).run { |v| acc << v }
      pick2(2).run { |v| acc << v }
      p acc

      # a capture read only inside a block nested in the passed block
      mult = 3
      sums = []
      pick(1).each_x { |k| [k].each { |e| sums << e * mult } }
      p sums
    RUBY

    _(result).must_answer <<~'OUT'
      ["one", "two", "ten"]
      3
      13
      "12"
      103
      104
      [3, 4]
      [3, 6]
    OUT
  end

  it "poly filter bang stmt block" do
    result = ze0(<<~'RUBY')
      # In-place poly-array filters (select!/filter!/keep_if/reject!/delete_if)
      # emit their loop into g_pre and used to emit the block's terminal
      # condition directly into g_pre after writing `if (!`. A terminal that
      # itself lowers through g_pre -- a block ending in a multi-statement
      # if/else expression -- spliced its statements into the middle of the
      # `if` condition, producing invalid C (doom: @projectiles.reject! whose
      # block ends in `if hit ... else proj.x = new_x; ...; false end`).

      items = [1, "two", 3.5, "four", 5]
      moved = []
      ret = items.reject! do |it|
        if it.is_a?(String)
          true
        else
          moved << it
          false
        end
      end
      p items
      p moved
      p ret.nil?          # something was removed: reject! returns self

      # select! with the same terminal-if shape
      nums = [1, "a", 2, "b", 3]
      kept = []
      nums.select! do |n|
        if n.is_a?(Integer)
          kept << n * 10
          true
        else
          false
        end
      end
      p nums
      p kept

      # nothing removed: reject! answers nil, delete_if answers self
      b = [7, 8.5]
      p b.reject! { |x|
        if x.is_a?(String)
          true
        else
          moved << x
          false
        end
      }.nil?
      p b
      p moved
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3.5, 5]
      [1, 3.5, 5]
      false
      [1, 2, 3]
      [10, 20, 30]
      true
      [7, 8.5]
      [1, 3.5, 5, 7, 8.5]
    OUT
  end

  it "poly proc face" do
    result = ze0(<<~'RUBY')
      # The Proc face on a value read out of a container: lambda?, parameters, curry
      # and to_proc had no arm for a boxed Proc, so each raised NoMethodError.
      fs = [->(x) { x }]
      p fs[0].lambda?
      p fs[0].arity
      p fs[0].parameters
      p fs[0].curry.class
      p fs[0].to_proc.lambda?

      h = { a: ->(y) { y } }
      p h[:a].lambda?
      p h[:a].arity
      p h[:a].parameters

      ps = [proc { |z| z }]
      p ps[0].lambda?
      p ps[0].arity

      # the direct forms are unchanged
      f = ->(w) { w }
      p f.lambda?
      p f.arity
      p f.parameters
      p f.curry.class
    RUBY

    _(result).must_answer <<~'OUT'
      true
      1
      [[:req, :x]]
      Proc
      true
      true
      1
      [[:req, :y]]
      false
      1
      true
      1
      [[:req, :w]]
      Proc
    OUT
  end

  it "proc call kw and lead splat" do
    result = ze0(<<~'RUBY')
      # Variable-stored proc/lambda calls: keyword params bind boxed and type poly
      # (#2728), and a splat may sit anywhere among the arguments (#2729).
      f = ->(a, k:) { [a, k] }
      p(f.call(1, k: 2))
      g = ->(a, k: 9) { a + k }
      p(g.call(1))
      p(g.call(1, k: 5))
      h = ->(x, **kw) { [x, kw] }
      p(h.call(7, a: 1))
      f3 = ->(a, b, c) { a + b + c }
      rest = [2, 3]
      p(f3.call(1, *rest))
      p(f3.call(*[1, 2], 3))
      gv = ->(*xs) { xs.length }
      p(gv.call(1, *[2, 3], 4))
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      10
      6
      [7, {a: 1}]
      6
      6
      4
    OUT
  end

  it "proc poly call boxed result" do
    result = ze0(<<~'RUBY')
      # Calling a proc through a poly slot preserves the boxed result class: an
      # escaping lambda whose body is a container literal over a captured variable
      # returns the container, not a truncated scalar.
      def make
        x = 5
        [-> { [x] }]
      end
      c = make[0]
      p c.call

      def make_h
        y = 7
        [-> { { v: y } }]
      end
      p make_h[0].call

      def make_nested
        z = 3
        [-> { [[z], z + 1] }]
      end
      p make_nested[0].call

      def make_str
        s = "cap"
        [-> { s + "!" }]
      end
      p make_str[0].call

      def make_scalar
        n = 41
        [-> { n + 1 }]
      end
      p make_scalar[0].call

      procs = [-> { 1 }, -> { "two" }, -> { [3] }]
      p procs.map { |pr| pr.call }
    RUBY

    _(result).must_answer <<~'OUT'
      [5]
      {v: 7}
      [[3], 4]
      "cap!"
      42
      [1, "two", [3]]
    OUT
  end

  it "proc poly param" do
    result = ze0(<<~'RUBY')
      # Polymorphic (sp_RbVal) values flowing through proc parameters. A 16-byte
      # sp_RbVal does not fit the 8-byte mrb_int arg slot, so a poly arg rides the
      # _sp_proc_poly_args side-channel the call site publishes before the call.
      # Covers single/multi poly params, mixed poly+int, poly return, and the
      # re-entrancy case (a nested poly-proc call inside an arg list).
      def poly(a) = a

      vals = poly([1, "two", :three, 4.5])

      # single poly param, poly return
      id = ->(x) { x }
      vals.each { |e| p id.call(e) }

      # two poly params -> poly array; the first arg is itself a poly-proc call, so
      # publish-after-evaluate-all is what keeps the side-channel correct here
      pair = ->(x, y) { [x, y] }
      p pair.call(id.call(vals[0]), vals[1])     # [1, "two"]

      # mixed poly + int args in one call
      tag = ->(x, n) { [x, n * 2] }
      p tag.call(vals[2], 5)                      # [:three, 10]

      # poly param threaded through a second proc call inside the body
      wrap = ->(v) { id.call(v) }
      p wrap.call(vals[3])                        # 4.5
    RUBY

    _(result).must_answer <<~'OUT'
      1
      "two"
      :three
      4.5
      [1, "two"]
      [:three, 10]
      4.5
    OUT
  end

  it "proc poly value return" do
    result = ze0(<<~'RUBY')
      # A proc/lambda whose parameter is polymorphic (called with values of
      # differing type) and whose body returns that parameter must hand back the
      # value unchanged, not collapse it to 0. The value rides the proc-call poly
      # side-channel, which the call site must populate even for a concrete argument.
      f = proc { |x| x }
      p f.call(42)
      p f.call("hi")
      p f.call(:sym)
      p f.call(3.5)

      g = ->(x) { x }
      p g.call(7)
      p g.call("yo")

      double = lambda { |n| n }
      p double.call(100)
      p double.call("z")

      # Multi-argument proc: every argument (not just the first) must reach the callee
      # through the boxed side-channel; exercises the per-arg temp + root path.
      pair = proc { |a, b| "#{a}=#{b}" }
      p pair.call("x", "y")
      p pair.call(1, 2)

      # A proc returning a poly array built from its (poly) params.
      mk = proc { |a, b| [a, b] }
      r = mk.call(1, "two")
      p r

      # Heap args evaluated in sequence (a later allocating arg must not collect the
      # earlier one): each call boxes fresh strings into adjacent side-channel slots,
      # and the proc consumes all three. Returns an int so the check stays on the
      # argument path (the call's value is the concatenated length).
      widths = proc { |a, b, c| (a + b + c).length }
      10.times { |i| p widths.call("a#{i}", "bb#{i}", "ccc#{i}") }
    RUBY

    _(result).must_answer <<~'OUT'
      42
      "hi"
      :sym
      3.5
      7
      "yo"
      100
      "z"
      "x=y"
      "1=2"
      [1, "two"]
      9
      9
      9
      9
      9
      9
      9
      9
      9
      9
    OUT
  end

  it "proc returns class" do
    result = ze0(<<~'RUBY')
      # A proc whose value is a Class: the boxed result was cast to the sp_Class
      # struct through its void pointer, which is not valid C, so the program did not
      # compile. The runtime already had the reader.
      f = -> { 1.class }
      p f.call
      g = -> (x) { x.class }
      p g.call("s")
      p g.call([1])
      h = proc { String }
      p h.call
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      String
      Array
      String
    OUT
  end

  it "returned lambda param boxed" do
    result = ze0(<<~'RUBY')
      # `lambda { }` / `proc { }` escapes from a method exactly as `->() { }` does --
      # the caller has the same type-erased proc either way. Only the arrow spelling
      # was marked as escaping, so the method-call spellings' parameters defaulted to
      # int and a lambda returned from a method read a String argument as an Integer
      # (#4035):
      #
      #   undefined method 'length' for an instance of Integer (NoMethodError)
      def wrap_do(rules)
        lambda do |value|
          results = rules.map { |rule| rule.call(value) }
          results
        end
      end

      def wrap_brace(rules)
        lambda { |value| rules.map { |rule| rule.call(value) } }
      end

      def wrap_proc(rules)
        proc do |value|
          rules.map { |rule| rule.call(value) }
        end
      end

      def wrap_arrow(rules)
        ->(value) do
          rules.map { |rule| rule.call(value) }
        end
      end

      def wrap_return(rules)
        return lambda { |value| rules.map { |rule| rule.call(value) } }
      end

      len = ->(v) { v.length }
      p wrap_do([len]).call("countess")
      p wrap_brace([len]).call("countess")
      p wrap_proc([len]).call("countess")
      p wrap_arrow([len]).call("countess")
      p wrap_return([len]).call("countess")

      # a float argument, which an int slot would truncate rather than misread
      half = ->(v) { v / 2 }
      p wrap_do([half]).call(5.0)

      # several parameters, and a proc's auto-splat
      pair = proc { |a, b| [a, b] }
      p pair.call("x", 2)
      def make_pair = proc { |a, b| [a, b] }
      p make_pair.call("x", 2)
      p make_pair.call(["y", 3])
    RUBY

    _(result).must_answer <<~'OUT'
      [8]
      [8]
      [8]
      [8]
      [8]
      [2.5]
      ["x", 2]
      ["x", 2]
      ["y", 3]
    OUT
  end
end
