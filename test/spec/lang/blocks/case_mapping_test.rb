# frozen_string_literal: true

require "spec_helper"

describe "Blocks: case mapping" do
  it "block forward two level" do
    result = ze0(<<~'RUBY')
      def outer(&b)
        inner(&b)
      end
      def inner(&b)
        [1, 2].map(&b)
      end
      tri = ->(x) { x * 3 }
      p outer(&tri)
      p(outer { |x| x * 4 })

      def a3(&b) = a2(&b)
      def a2(&b) = a1(&b)
      def a1(&b) = [1, 2].map(&b)
      p a3(&tri)
      p(a3 { |x| x + 1 })

      def s_outer(&b) = s_inner(&b)
      def s_inner(&b) = ["a", "bb"].map(&b)
      len = ->(s) { s.length }
      p s_outer(&len)
      p(s_outer { |s| s.upcase })

      def y_outer(&b) = y_inner(&b)
      def y_inner(&b) = y_leaf(&b)
      def y_leaf
        yield 5
      end
      p y_outer(&tri)
      p(y_outer { |x| x + 100 })

      def twice(&b)
        [10].map(&b) + inner(&b)
      end
      p twice(&tri)
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 6]
      [4, 8]
      [3, 6]
      [2, 3]
      [1, 2]
      ["A", "BB"]
      15
      105
      [30, 3, 6]
    OUT
  end

  it "block forward value callable" do
    result = ze0(<<~'RUBY')
      # A callable *value* forwarded with `&` to an iterator -- `recv.<iter>(&f)` where
      # `f` is a Proc value, a Method object, or the method's own `&block` param -- is
      # desugared to `recv.<iter> { |x| f.call(x) }`, so it lowers through the normal
      # block emitters for ANY iterator and element type, not a per-iterator special
      # case. Receivers are method params so the receiver type is only known at runtime
      # (no constant-folding of the literal away).
      def ints(a, sq, odd, big)
        p a.map(&sq)        # Proc value -> int map
        p a.select(&odd)    # predicate select
        p a.reject(&odd)    # predicate reject
        total = 0
        acc = ->(x) { total += x }
        a.each(&acc)        # statement-form each (side effect)
        p total
        p a.map(&big)       # Proc passed in as a method parameter
      end

      # A broad iterator surface, all through the one desugar: aggregates and
      # scalar-returning iterators, not just map/select.
      def aggregates(a, key, pred)
        p a.sort_by(&key)
        p a.min_by(&key)
        p a.max_by(&key)
        p a.partition(&pred)
        p a.find(&pred)
        p a.count(&pred)
      end

      # String elements (a limitation the older value-callable path could not handle):
      # the result type is known because the proc is a local lambda, so its return
      # type is inferred. A proc passed *as a parameter* carries no inferred return
      # type, so a non-int result there is out of scope (it mistypes for literal
      # blocks too -- a separate proc-param return-inference gap).
      def strings(words)
        up = ->(s) { s.upcase }
        p words.map(&up)
      end

      def ranges(sq)
        p (1..4).map(&sq)   # range receiver, not an array
      end

      # An inline `&->(x){...}` lambda is equivalent to the block itself; it forwards
      # like any callable (the int element cases; a non-int result shares the
      # proc-param return-inference gap noted above).
      def inline_lambdas(a)
        p a.map(&->(x) { x * 3 })
        p a.find(&->(x) { x > 2 })
        p a.count(&->(x) { x.odd? })
      end

      # Method objects: `&m` (a local Method value) and `&method(:m)` (inline).
      def dbl(x) = x * 2
      def positive?(x) = x > 0
      def methods_forward(a)
        m = method(:dbl)
        p a.map(&m)
        p a.select(&method(:positive?))
        p a.map(&method(:dbl))
      end

      # Forwarding the method's own `&block` parameter to an iterator -- the canonical
      # "pass the block along" pattern (previously a hard "unsupported call").
      def relay_map(a, &b)
        a.map(&b)
      end
      def relay_each(a, &b)
        a.each(&b)
      end
      def relay_select(a, &b)
        a.select(&b)
      end

      square = ->(x) { x * x }
      ints([1, 2, 3, 4], square, ->(x) { x.odd? }, ->(x) { x + 100 })
      aggregates([3, 1, 4, 2], ->(x) { -x }, ->(x) { x.even? })
      strings(["ab", "cd"])
      ranges(square)
      inline_lambdas([1, 2, 3, 4])
      methods_forward([-1, 2, -3, 4])
      p relay_map([1, 2, 3]) { |x| x + 1 }
      collected = []
      relay_each([1, 2, 3]) { |x| collected << x * 10 }
      p collected
      p relay_select([1, 2, 3, 4]) { |x| x.even? }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 4, 9, 16]
      [1, 3]
      [2, 4]
      10
      [101, 102, 103, 104]
      [4, 3, 2, 1]
      4
      1
      [[4, 2], [3, 1]]
      4
      2
      ["AB", "CD"]
      [1, 4, 9, 16]
      [3, 6, 9, 12]
      3
      2
      [-2, 4, -6, 8]
      [2, 4]
      [-2, 4, -6, 8]
      [2, 3, 4]
      [10, 20, 30]
      [2, 4]
    OUT
  end

  it "block local shadows later outer" do
    result = ze0(<<~'RUBY')
      # Ruby's block-local rule is TEXTUAL: a name assigned inside a block is
      # block-local unless the enclosing scope assigned it EARLIER in the source.
      # zeo's capture analysis (codegen::captures::collect_escaping_captures) is
      # order-blind -- it unions every name an escaping block touches against every
      # name the scope assigns ANYWHERE, so a block-local that happens to share a
      # name with a LATER outer local becomes a shared Captured cell. The block's
      # write then leaks into the outer variable. The same misclassification makes
      # `Ractor.new { e = 1 }` refuse isolation when main rescue-binds an `e`
      # further down. Fix: the capture set must only admit names whose outer
      # assignment PRECEDES the block textually.
      b = proc { x = 1; x }
      x = 5
      b.call
      p x

      r = proc { note = "inner"; note.upcase }
      p r.call
      note = "outer"
      p note
    RUBY

    _(result).must_answer <<~'OUT'
      5
      "INNER"
      "outer"
    OUT
  end

  it "each's block parameter shadows an outer String local of the same name" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- each on int_array, outer string v (the original report) ---
      def f1
        v = "hello"
        [1, 2, 3].each do |v|
          puts v * 10
        end
        puts v
      end
      f1
      # 10
      # 20
      # 30
      # hello

    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      hello
    OUT
  end

  it "each_with_index's index parameter shadows an outer String local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- each_with_index, outer string i ---
      def f2
        i = "outer"
        ["a", "b"].each_with_index do |s, i|
          puts s + i.to_s
        end
        puts i
      end
      f2
      # a0
      # b1
      # outer

    RUBY

    _(result).must_answer <<~'OUT'
      a0
      b1
      outer
    OUT
  end

  it "each_with_index over Strings shadows an outer Integer local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- each_with_index on str_array, outer int i ---
      def f3
        i = 99
        ["a", "b", "c"].each_with_index do |s, i|
          puts s + ":" + i.to_s
        end
        puts i
      end
      f3
      # a:0
      # b:1
      # c:2
      # 99

    RUBY

    _(result).must_answer <<~'OUT'
      a:0
      b:1
      c:2
      99
    OUT
  end

  it "map's block parameter shadows an outer String local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- map on int_array, outer string i ---
      def f4
        i = "outer"
        out = [10, 20, 30].map { |i| i + 1 }
        puts out[0]               # 11
        puts out[1]               # 21
        puts out[2]               # 31
        puts i                    # outer
      end
      f4

    RUBY

    _(result).must_answer <<~'OUT'
      11
      21
      31
      outer
    OUT
  end

  it "map over Strings shadows an outer Integer local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- map on str_array, outer int s ---
      def f5
        s = 42
        words = ["a", "b", "c"]
        up = words.map { |s| s.upcase }
        puts up[0]                # A
        puts up[1]                # B
        puts up[2]                # C
        puts s                    # 42
      end
      f5

    RUBY

    _(result).must_answer <<~'OUT'
      A
      B
      C
      42
    OUT
  end

  it "select's block parameter shadows an outer String local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- select on int_array, outer string n ---
      def f6
        n = "kept"
        out = [1, 2, 3, 4].select { |n| n > 2 }
        puts out.length           # 2
        puts out[0]               # 3
        puts out[1]               # 4
        puts n                    # kept
      end
      f6

    RUBY

    _(result).must_answer <<~'OUT'
      2
      3
      4
      kept
    OUT
  end

  it "reject's block parameter shadows an outer String local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- reject on int_array, outer string n ---
      def f7
        n = "drop"
        out = [1, 2, 3, 4].reject { |n| n > 2 }
        puts out.length           # 2
        puts out[0]               # 1
        puts out[1]               # 2
        puts n                    # drop
      end
      f7

    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      2
      drop
    OUT
  end

  it "partition's block parameters shadow an outer String local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- partition on int_array, outer string n ---
      def f8
        n = "outer"
        parts = [1, 2, 3, 4, 5].partition { |n| n > 2 }
        puts parts[0].length      # 3
        puts parts[0][0]          # 3
        puts parts[0][1]          # 4
        puts parts[0][2]          # 5
        puts parts[1].length      # 2
        puts parts[1][0]          # 1
        puts parts[1][1]          # 2
        puts n                    # outer
      end
      f8

    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      4
      5
      2
      1
      2
      outer
    OUT
  end

  it "partition over Strings shadows an outer Integer local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- partition on str_array, outer int x ---
      def f9
        x = 99
        parts = ["a", "bb", "ccc"].partition { |x| x.length > 1 }
        puts parts[0].length      # 2
        puts parts[0][0]          # bb
        puts parts[0][1]          # ccc
        puts parts[1].length      # 1
        puts parts[1][0]          # a
        puts x                    # 99
      end
      f9

    RUBY

    _(result).must_answer <<~'OUT'
      2
      bb
      ccc
      1
      a
      99
    OUT
  end

  it "each_char's block parameter shadows an outer Integer local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- each_char on string, outer int c ---
      def f10
        c = 7
        "abc".each_char do |c|
          puts c + "!"
        end
        puts c
      end
      f10
      # a!
      # b!
      # c!
      # 7

    RUBY

    _(result).must_answer <<~'OUT'
      a!
      b!
      c!
      7
    OUT
  end

  it "each_byte's block parameter shadows an outer String local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- each_byte on string, outer string b ---
      def f11
        b = "kept"
        "AB".each_byte do |b|
          puts b + 1
        end
        puts b
      end
      f11
      # 66
      # 67
      # kept

    RUBY

    _(result).must_answer <<~'OUT'
      66
      67
      kept
    OUT
  end

  it "cycle with a count shadows an outer String local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- cycle on int_array with count, outer string x ---
      def f12
        x = "outer"
        [1, 2].cycle(2) do |x|
          puts x * 10
        end
        puts x
      end
      f12
      # 10
      # 20
      # 10
      # 20
      # outer

    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      10
      20
      outer
    OUT
  end

  it "scan with a block shadows an outer Integer local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- scan with block on string, outer int m ---
      def f13
        m = 99
        "a1b2c3".scan(/\d+/) do |m|
          puts m + "!"
        end
        puts m
      end
      f13
      # 1!
      # 2!
      # 3!
      # 99

    RUBY

    _(result).must_answer <<~'OUT'
      1!
      2!
      3!
      99
    OUT
  end

  it "each_slice's block parameter shadows an outer String local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- each_slice on int_array, outer string v ---
      def f14
        v = "hello"
        [1, 2, 3, 4].each_slice(2) do |v|
          puts v.length
        end
        puts v
      end
      f14
      # 2
      # 2
      # hello

    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      hello
    OUT
  end

  it "each_cons's block parameter shadows an outer Integer local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- each_cons on str_array, outer int c ---
      def f15
        c = 7
        ["a", "b", "c", "d"].each_cons(3) do |c|
          puts c.length
        end
        puts c
      end
      f15
      # 3
      # 3
      # 7

    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      7
    OUT
  end

  it "tap's block parameter shadows an outer String local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- tap on int receiver, outer string v ---
      def f16
        v = "hello"
        42.tap do |v|
          puts v + 1
        end
        puts v
      end
      f16
      # 43
      # hello

    RUBY

    _(result).must_answer <<~'OUT'
      43
      hello
    OUT
  end

  it "tap over a String shadows an outer Integer local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- tap on string receiver, outer int s ---
      def f17
        s = 99
        "abc".tap do |s|
          puts s + "!"
        end
        puts s
      end
      f17
      # abc!
      # 99

    RUBY

    _(result).must_answer <<~'OUT'
      abc!
      99
    OUT
  end

  it "then's block parameter shadows an outer String local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- then on int receiver, outer string v ---
      def f18
        v = "hello"
        out = 42.then { |v| v + 1 }
        puts out
        puts v
      end
      f18
      # 43
      # hello

    RUBY

    _(result).must_answer <<~'OUT'
      43
      hello
    OUT
  end

  it "yield_self's block parameter shadows an outer Float local" do
    result = ze0(<<~'RUBY')
      # Block parameters shadow outer differently-typed locals correctly.
      # Without push_scope/declare_var around the block body compile, infer_type
      # returned the outer scope's type for the block param, dispatching the
      # wrong runtime call (e.g. sp_str_repeat for an int param).

      # --- yield_self with int receiver returning string, outer float v ---
      def f19
        v = 3.14
        out = 42.yield_self { |v| v.to_s + "!" }
        puts out
        puts v
      end
      f19
      # 42!
      # 3.14
    RUBY

    _(result).must_answer <<~'OUT'
      42!
      3.14
    OUT
  end

  it "class body local captured by block" do
    result = ze0(<<~'RUBY')
      # A class body is an ordinary Ruby scope with ordinary locals, and a block
      # written in it closes over them -- optparse builds its whole accept table this
      # way (`yesno = CompletingHash.new; %w[- no].each { |el| yesno[el] = false }`),
      # so rubygems' every option parse depends on it.
      class CompletingHash < Hash
        def complete(key) = self[key]
      end

      class Host
        yesno = CompletingHash.new
        %w[- no false].each { |el| yesno[el] = false }
        %w[+ yes true].each { |el| yesno[el] = true }
        yesno["nil"] = false
        TABLE = yesno

        # Mutated by the block, then read back outside it.
        count = 0
        3.times { count += 1 }
        COUNT = count

        # A local first ASSIGNED inside the block is block-owned, and does not leak.
        [1].each { fresh = :inside }
        LEAKED = defined?(fresh)

        # Nested blocks reach the same binding.
        seen = []
        [[1, 2], [3]].each { |row| row.each { |v| seen << v } }
        SEEN = seen

        # ...and a method defined in the same body does NOT see the class body's
        # locals, matching Ruby's scope rules.
        def self.reads_table = TABLE
      end

      p Host::TABLE.class
      p Host::TABLE.sort.to_h
      p Host::TABLE.complete("no")
      p Host::COUNT
      p Host::LEAKED
      p Host::SEEN
      p Host.reads_table.size

      # The same shape inside a module body.
      module Registry
        entries = {}
        %w[a b].each { |k| entries[k] = k.upcase }
        ENTRIES = entries
      end
      p Registry::ENTRIES

      # ...and a block that outlives the body still sees the binding.
      class Deferred
        pending = []
        ADD = ->(v) { pending << v }
        READ = -> { pending }
      end
      Deferred::ADD.call(1)
      Deferred::ADD.call(2)
      p Deferred::READ.call
    RUBY

    _(result).must_answer <<~'OUT'
      CompletingHash
      {"+" => true, "-" => false, "false" => false, "nil" => false, "no" => false, "true" => true, "yes" => true}
      false
      3
      nil
      [1, 2, 3]
      7
      {"a" => "A", "b" => "B"}
      [1, 2]
    OUT
  end

  it "lambda named param type" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A Holder holds a lambda that closed over the Holder.
      # At exit: cycle leak: 2 objects (Holder x1, Proc x1)
      IDX  = ->(v) { v[0] }
      SIZE = ->(v) { v.size }
      SUM  = ->(v) { v.sum }
      p IDX.call([7])
      p SIZE.call([7, 8])
      p SUM.call([1, 2, 3])

      class Holder
        def initialize
          @fn = ->(v) { v.size }
        end
        def run(x)
          @fn.call(x)
        end
      end
      p Holder.new.run([1, 2, 3])

      STR = ->(s) { s.upcase }
      p STR.call("ab")
      p STR.("cd")
      p STR["ef"]

      CONST_LAMBDA = ->(v) { v.class.to_s }
      local_lambda = ->(v) { v.class.to_s }
      p CONST_LAMBDA.call([7])
      p local_lambda.call([7])

      RE_F = ->(re) { re.source }
      p RE_F.call(/b/)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      2
      6
      3
      "AB"
      "CD"
      "EF"
      "Array"
      "Array"
      "b"
    OUT
  end

  it "lambda takes a literal block or a lambda" do
    result = ze0(<<~'RUBY')
      # The widened sweep behind `lambda_requires_a_literal_block`: every route a
      # block can reach `Kernel#lambda` by.
      #
      # Three outcomes, and the middle one is the part a narrow reading misses.
      # An iseq handler -- a `{ }` written at the site that invokes `lambda` --
      # becomes a lambda. A proc handler that IS ALREADY a lambda comes back
      # unchanged, which is why `&lam`, `&method(:m)` and `&:sym` all pass.
      # Anything else is refused.
      #
      # `RProc::is_literal_block` carries the first fact: every emitter-built proc
      # sets it, the `&expr` conversion clears it, and `public_send`/`Method#call`
      # clear it because both re-wrap the block as a proc handler where `send`
      # forwards the iseq handler unchanged.

      def try(label)
        p [label, yield]
      rescue ArgumentError, LocalJumpError, NoMethodError => e
        p [label, e.class, e.message]
      end

      pr = proc { |a| a }
      lam = ->(a) { a }
      def forward(&b) = lambda(&b)
      def relay(&b) = b
      def m_one(x) = x

      try(:no_block)        { lambda }
      try(:literal)         { lambda { 1 }.lambda? }
      try(:literal_do)      { lambda do 1 end.lambda? }
      try(:arrow)           { lam.lambda? }
      try(:proc_obj)        { pr.lambda? }
      try(:proc_literal)    { proc { 1 }.lambda? }
      try(:from_proc)       { lambda(&pr).lambda? }
      try(:from_lambda)     { lambda(&lam).lambda? }
      try(:from_method)     { lambda(&method(:m_one)).lambda? }
      try(:from_symbol)     { lambda(&:upcase).lambda? }
      try(:forwarded)       { forward { 1 }.lambda? }
      try(:relayed)         { lambda(&relay { 1 }).lambda? }
      try(:send_literal)    { Kernel.send(:lambda) { 1 }.lambda? }
      try(:send_amp)        { Kernel.send(:lambda, &pr).lambda? }
      try(:public_literal)  { Kernel.public_send(:lambda) { 1 }.lambda? }
      try(:method_call)     { Kernel.method(:lambda).call { 1 }.lambda? }
      try(:instance_exec)   { Object.new.instance_exec { lambda { 1 }.lambda? } }
      try(:nested)          { [1].map { lambda { 2 }.lambda? }.first }
      try(:in_define)       { (Class.new { define_method(:go) { lambda { 3 }.lambda? } }).new.go }
      try(:reuse)           { l = lambda { 1 }; lambda(&l).lambda? }
      try(:proc_new)        { Proc.new { 1 }.lambda? }
      try(:lambda_in_block) { [1].each { |_| lambda { 4 } }.class }
    RUBY

    _(result).must_answer <<~'OUT'
      [:no_block, ArgumentError, "tried to create Proc object without a block"]
      [:literal, true]
      [:literal_do, true]
      [:arrow, true]
      [:proc_obj, false]
      [:proc_literal, false]
      [:from_proc, ArgumentError, "the lambda method requires a literal block"]
      [:from_lambda, true]
      [:from_method, true]
      [:from_symbol, true]
      [:forwarded, ArgumentError, "the lambda method requires a literal block"]
      [:relayed, ArgumentError, "the lambda method requires a literal block"]
      [:send_literal, true]
      [:send_amp, ArgumentError, "the lambda method requires a literal block"]
      [:public_literal, ArgumentError, "the lambda method requires a literal block"]
      [:method_call, ArgumentError, "the lambda method requires a literal block"]
      [:instance_exec, true]
      [:nested, true]
      [:in_define, true]
      [:reuse, true]
      [:proc_new, false]
      [:lambda_in_block, Array]
    OUT
  end

  it "proc args published at call" do
    result = ze0(<<~'RUBY')
      # A Proc's boxed arguments ride ONE global side channel, so publishing them
      # belongs to the call rather than to the statement above it. As prelude lines,
      # two Proc calls in one expression both published before either ran, and the
      # first call read the second's arguments -- which a composed Proc's first stage
      # saw as nil, since the publish for its own stage had been cleared (#4059).
      strip = ->(s) { s.strip }
      down  = ->(s) { s.downcase }
      fwd = strip >> down
      p fwd.call("  AB  ")
      p(fwd.call("  AB  ") == fwd.call("  AB  "))

      # two DIFFERENT arguments in one expression: each call has to see its own
      add = ->(a, b) { a + b }
      p(add.call(1, 2) + add.call(10, 20))
      p [add.call(1, 2), add.call(3, 4), add.call(5, 6)]

      # a plain (uncomposed) lambda on both sides
      up = ->(s) { s.upcase }
      p(up.call("a") + up.call("b"))

      # nested: the inner call publishes while the outer one is being built
      wrap = ->(s) { "[#{s}]" }
      p wrap.call(wrap.call("x"))

      # three stages composed, called twice in one expression
      back = down << strip
      p(back.call("  CD  ") == back.call("  CD  "))
      p [fwd.call("  EF  "), back.call("  GH  ")]
    RUBY

    _(result).must_answer <<~'OUT'
      "ab"
      true
      33
      [3, 7, 11]
      "AB"
      "[[x]]"
      true
      ["ef", "gh"]
    OUT
  end

  it "proc compose intermediate type" do
    result = ze0(<<~'RUBY')
      a = ->(n) { n.to_s }
      b = ->(s) { s.length }
      p((a >> b).call(100))
      c = ->(s) { s.upcase }
      d = ->(n) { "n#{n}" }
      p((c << d).call(5))
      # variable-bound composition
      comp = a >> b
      p(comp.call(42))
    RUBY

    _(result).must_answer <<~'OUT'
      3
      "N5"
      2
    OUT
  end

  it "proc escaped arg types" do
    result = ze0(<<~'RUBY')
      # A proc/lambda passed as a positional argument escapes into an opaque method
      # parameter and is called through the generic type-erased proc ABI. Its own
      # argument types are not statically knowable, so a Float argument must survive
      # (an int-typed slot would truncate it to 0).
      def call1(pr, x) = pr.call(x)
      def call2(pr, a, b) = pr.call(a, b)

      puts call1(->(a) { a * 2 }, 0.25)
      puts call1(->(a) { a * 2 }, 3)
      puts call2(->(a, b) { a + b }, 0.5, 0.25)
      puts call1(->(s) { s.upcase }, "hi")
      puts call1(proc { |a| a * 10 }, 0.1)

      r = call1(->(a) { a * 2 }, 1.5)
      puts(r + 1)
    RUBY

    _(result).must_answer <<~'OUT'
      0.5
      6
      0.75
      HI
      1.0
      4.0
    OUT
  end

  it "proc from container literal" do
    result = ze0(<<~'RUBY')
      # A container literal builds itself in the statement prelude, so an emitter that
      # writes a prelude line and renders an expression straight into it spliced the
      # literal's construction into the middle of that line -- not C at all. The
      # receiver of a poly `.call` is where this showed: a table of lambdas written
      # where it is used, indexed and called in one expression (#4065).
      def render(style, value)
        { plain: ->(v) { v.to_s }, quoted: ->(v) { "\"#{v}\"" } }[style].call(value)
      end
      puts render(:plain, 42)
      puts render(:quoted, "hi")

      # the Array form of the same shape
      def pick(i, v)
        [->(x) { x * 2 }, ->(x) { x + 100 }][i].call(v)
      end
      p pick(0, 21)
      p pick(1, 21)

      # a string-keyed table, and one whose values are method objects
      def by_name(n)
        { "up" => ->(s) { s.upcase }, "down" => ->(s) { s.downcase } }[n].call("MiXeD")
      end
      p by_name("up")
      p by_name("down")

      # nested one level deeper
      def nested(k)
        { outer: { inner: ->(x) { x - 1 } } }[k][:inner].call(10)
      end
      p nested(:outer)
    RUBY

    _(result).must_answer <<~'OUT'
      42
      "hi"
      42
      121
      "MIXED"
      "mixed"
      9
    OUT
  end
end
