# frozen_string_literal: true

require "spec_helper"

describe "Control programs" do
  it "and arm returns nil" do
    result = ze0(<<~'RUBY')
      # An arm with no C VALUE cannot sit in a C conditional beside a typed sibling:
      # a method whose body is `nil` compiles to a void function, and `a && a.analyze`
      # put that call straight into one arm of `? :` whose other arm is an sp_Att *.
      # The poly sibling boxed it, which is why only a TYPED sibling ever saw this --
      # `a ? a.analyze : nil` worked while `a ? a.analyze : a` did not (#4163).
      class Att
        def analyze = nil
        def name = "n"
        def count = 3
      end

      class Holder
        attr_accessor :att
        def ensure_analyzed
          att && att.analyze     # what `att&.analyze` lowers to
        end
      end

      a = Att.new
      p(a && a.analyze)
      p(a ? a.analyze : a)
      p(a ? a.analyze : nil)
      p(nil && a.analyze)
      p(a && a.name)
      p(a && a.count)
      p((a || a.analyze).name)

      h = Holder.new
      h.att = a
      p h.ensure_analyzed
      h.att = nil
      p h.ensure_analyzed

      s = "x"
      p(s && a.analyze)
      n = 5
      p(n && a.analyze)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      "n"
      3
      "n"
      nil
      nil
      nil
      nil
    OUT
  end

  it "and or empty literal" do
    result = ze0(<<~'RUBY')
      # An empty `[]` / `{}` on the right of `&&` / `||` carries no element type of
      # its own, so it caches UNKNOWN and ty_unify() dropped it, answering the LEFT
      # operand's type. The array construction was then emitted into that slot: for
      # a bool left the value came back as the bool, and for an Integer left the C
      # compiler refused the program outright.
      #
      # The nil-left shape already worked (#3462); this is every other left.
      def show(l, v); puts "#{l}: #{v.inspect}"; end

      show("true && []",     true && [])
      show("true && {}",     true && {})
      show("false && []",    false && [])
      show("1 && []",        1 && [])
      show("'s' && []",      "s" && [])
      show("nil && []",      nil && [])
      show("true || []",     true || [])
      show("nil || []",      nil || [])
      show("false || []",    false || [])
      show("1 || []",        1 || [])
      show("nil || {}",      nil || {})

      # a non-empty literal in the same position was never affected
      show("true && [1]",    true && [1])
      show("true && {1=>2}", true && {1 => 2})

      # the value is a real container, not just one that prints right
      r = true && []
      r << 1
      show("mutated", r)
      h = true && {}
      h["k"] = 1
      show("hash mutated", h)
      show("size", (true && []).size)
      show("each", (true && []).each { |x| x })

      # chains and method bodies reach the same emitter
      show("chain", true && [] || ["x"])
      show("nested", true && (false || []))
      def f(flag); flag && []; end
      show("m true", f(true))
      show("m false", f(false))
      def g(flag); flag || {}; end
      show("g nil", g(nil))
      show("g 1", g(1))
    RUBY

    _(result).must_answer <<~'OUT'
      true && []: []
      true && {}: {}
      false && []: false
      1 && []: []
      's' && []: []
      nil && []: nil
      true || []: true
      nil || []: []
      false || []: []
      1 || []: 1
      nil || {}: {}
      true && [1]: [1]
      true && {1=>2}: {1 => 2}
      mutated: [1]
      hash mutated: {"k" => 1}
      size: 0
      each: []
      chain: []
      nested: []
      m true: []
      m false: false
      g nil: {}
      g 1: 1
    OUT
  end

  it "and short circuit nil" do
    result = ze0(<<~'RUBY')
      # A short-circuiting `&&` over a scalar left operand yields that operand's nil,
      # so nil? answers true and compact drops it. `||` keeps a truthy left as itself.
      s = "a"
      i = s.rindex("/")
      v = i && s.upcase
      p v
      p v.nil?
      p [v, "z"].compact
      p [v, "z"].filter_map { |x| x }
      j = s.rindex("a")
      w = j && s.upcase
      p w
      p w.nil?
      f = [].first
      u = f && 1.5
      p u.nil?
      q = i && [1, 2]
      p q.nil?
      r = i || 7
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      ["z"]
      ["z"]
      "A"
      false
      true
      true
      7
    OUT
  end

  it "ast translator answers unknown for some shapes" do
    result = ze0(<<~'RUBY')
      # `RubyVM::AbstractSyntaxTree` maps prism's node kinds onto CRuby's NODE_*
      # names, and the mapping is INCOMPLETE: an unmapped kind answers a node of
      # type `:UNKNOWN` with its location intact and no children, so a walker sees
      # a leaf where CRuby has a subtree.
      #
      # The translator is deliberately a TOTAL function -- an unmapped kind
      # degrades to an honest leaf rather than raising, because walkers recurse
      # `children` -- and that is the right default. What is missing is the
      # mappings themselves: `case`/`when` and `begin`/`rescue` are two of them, and
      # they cost 9 of the 13 nodes CRuby reports for the program below.
      #
      # Each mapped shape is oracle-verified by `tests/rubyvm_ast.rb`, so closing
      # this is adding rows in that style, one kind at a time, not a redesign.
      #
      # NOT part of this gap, and worth keeping apart: `Node#node_id`. zeo numbers
      # its own nodes post-order, and CRuby's AST ids are a DIFFERENT scheme from
      # prism's own (`nil.nope` is prism id 3 for the call, CRuby AST id 1), so
      # neither zeo's numbering nor prism's would serve. See
      # `rubyvm_iseq_serialization.rb`.
      #
      # Oracle: 13 nodes, and no `:UNKNOWN` among them.
      src = <<~RB
        case 1
        when Integer then :a
        else :b
        end
        begin
          1
        rescue
          2
        end
      RB
      def count(n)
        return 0 unless n.is_a?(RubyVM::AbstractSyntaxTree::Node)
        1 + n.children.sum { |c| count(c) }
      end
      def kinds(n, acc = [])
        return acc unless n.is_a?(RubyVM::AbstractSyntaxTree::Node)
        acc << n.type
        n.children.each { |c| kinds(c, acc) }
        acc
      end
      ast = RubyVM::AbstractSyntaxTree.parse(src)
      p count(ast)
      p kinds(ast).uniq.sort
    RUBY

    _(result).must_answer "13\n[:BLOCK, :CASE, :CONST, :INTEGER, :LIST, :RESBODY, :RESCUE, :SCOPE, :SYM, :WHEN]\n"
  end

  it "bang mutator return value" do
    result = ze0(<<~'RUBY')
      # A successful in-place String mutation returns the receiver. The "did it
      # change?" test compared the buffer with the new content AFTER writing it back
      # -- and the comparison operand was sp_String_cstr, a pointer INTO the buffer
      # rather than a snapshot of it -- so every successful mutation compared equal
      # and answered nil (#4014). Printing the two separately hid it.
      a = +"abc"
      v = a.sub!("b", "*")
      p [a, v]

      a = +"abc"
      v = a.gsub!("b", "*")
      p [a, v]

      a = +"abc"
      v = a.upcase!
      p [a, v]

      a = +"abc"
      v = a.sub!("b", "*")
      p [v, a]

      # a mutation that changes nothing still answers nil
      a = +"abc"
      p [a, a.sub!("z", "*")]
      a = +"ABC"
      p [a, a.upcase!]
      a = +"abc"
      p [a.downcase!, a.downcase!]
      a = +" x "
      p [a.strip!, a.strip!]

      # and the non-nil-on-no-change mutators answer the receiver either way
      a = +"abc"
      p [a.reverse!, a]
    RUBY

    _(result).must_answer <<~'OUT'
      ["a*c", "a*c"]
      ["a*c", "a*c"]
      ["ABC", "ABC"]
      ["a*c", "a*c"]
      ["abc", nil]
      ["ABC", nil]
      [nil, nil]
      ["x", nil]
      ["cba", "cba"]
    OUT
  end

  it "bare regexp condition matches the last read line" do
    result = ze0(<<~'RUBY')
      # A regexp literal written where a condition goes is not the object: ruby
      # rewrites it into a match against `$_`, the last line `gets` read, and the
      # condition is the match POSITION or nil. `~re` is the same operator spelled
      # out, so the two lines below answer alike.
      #
      # Ruby warns on the form, and the warning is level-sensitive: a PLAIN regexp
      # warns in a plain run, an INTERPOLATED one only under `-w`. Both render the
      # same sentence, so the node kind is what tells them apart.

      $_ = "hello world"

      p(/hello/ ? :yes : :no)
      p(~/hello/)
      p(/world/ ? :yes : :no)
      p(/nope/ ? :yes : :no)

      puts "modifier" if /lo w/

      # The match sets `$~` and its family, as an explicit `=~` does.
      p $~[0] if /w(or)ld/
      p $1

      # An INTERPOLATED regexp is the same match, and warns only under `-w`.
      part = "wor"
      p(/#{part}ld/ ? :interpolated : :no)

      # A Symbol `$_` matches -- `=~` takes one -- and a nil `$_` simply does not.
      # Anything else raises, which is `=~`'s own rule rather than a special one:
      # `Regexp#~` spells the same idea and answers nil there instead.
      $_ = :hello
      p(/hell/ ? :symbol : :no)
      $_ = nil
      p(/hello/ ? :yes : :no)
      $_ = 42
      begin
        p(/4/ ? :yes : :no)
      rescue TypeError => e
        p e.message
      end
      p(~/4/)
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      :yes
      0
      :yes
      :no
      modifier
      "world"
      "or"
      :interpolated
      :symbol
      :no
      "no implicit conversion of Integer into String"
      nil
    OUT
      lang/control/control_test.rb:12: warning: regex literal in condition
      lang/control/control_test.rb:14: warning: regex literal in condition
      lang/control/control_test.rb:15: warning: regex literal in condition
      lang/control/control_test.rb:17: warning: regex literal in condition
      lang/control/control_test.rb:20: warning: regex literal in condition
      lang/control/control_test.rb:31: warning: regex literal in condition
      lang/control/control_test.rb:33: warning: regex literal in condition
      lang/control/control_test.rb:36: warning: regex literal in condition
    ERR
  end

  it "begin and end" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # `BEGIN { }` runs before the rest of the file, in the order the file
      # writes them. `END { }` runs at exit, last registered first, which is
      # the queue `at_exit` shares.

      puts "main"
      BEGIN { puts "begin one" }
      END { puts "end one" }
      BEGIN { puts "begin two" }
      END { puts "end two" }
      at_exit { puts "at_exit" }
      puts "done"

      # A `BEGIN` shares the top-level names, so what it writes is there after.
      BEGIN { started = :yes }
      p defined?(started)

      # An `END` reads the enclosing names by reference, so it sees the value
      # they hold at exit, not the one they held where it was written.
      counter = 1
      END { puts "end saw counter=#{counter}" }
      counter = 2
    RUBY

    _(result).must_answer <<~'OUT'
      begin one
      begin two
      main
      done
      "local-variable"
      end saw counter=2
      at_exit
      end two
      end one
    OUT
  end

  it "bigint poly container" do
    result = ze0(<<~'RUBY')
      # A bigint value stored in a heterogeneous (poly) Array or Hash used to box as
      # nil, because the poly value (sp_RbVal) had no bigint tag. With SP_TAG_BIGINT it
      # is a first-class poly element: display, ==, include?, and hash-key all work.
      # (b is promoted to bigint by the self-referential multiply in the while loop,
      # so this holds in every overflow mode.)
      b = 1
      i = 0
      while i < 70
        b = b * 2
        i = i + 1
      end
      b2 = 1
      j = 0
      while j < 70
        b2 = b2 * 2
        j = j + 1
      end

      arr = [1, "x", b]
      p arr
      puts arr.include?(b2)        # equality across the boxed bigint
      puts arr[2] == b2

      h = { small: 5, big: b }
      p h
      puts h[:big] == b2

      # bigint as a hash key
      hk = {}
      hk[b] = "found"
      p hk[b2]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, "x", 1180591620717411303424]
      true
      true
      {small: 5, big: 1180591620717411303424}
      true
      "found"
    OUT
  end

  it "bigint propagation chain" do
    result = ze0(<<~'RUBY')
      # Stress test: bigint propagation through a chain of dependent locals.
      # `a` starts int but is promoted to bigint by `a = a * 2` inside the
      # while loop (detected by scan_bigint_in_loop). Subsequent assignments
      # `b = a + 1`, `c = b + 1`, ... force scan_bigint_propagate to walk
      # the dependency chain over multiple fixed-point iterations. Verifies
      # the loop converges far below the 256-iteration safety cap and that
      # the oscillation guard does not trigger on legitimate monotonic
      # propagation.

      a = 1
      i = 0
      while i < 50
        a = a * 2
        i = i + 1
      end

      b = a + 1
      c = b + 1
      d = c + 1
      e = d + 1
      f = e + 1
      g = f + 1
      h = g + 1

      puts a > 0
      puts b > 0
      puts c > 0
      puts d > 0
      puts e > 0
      puts f > 0
      puts g > 0
      puts h > 0
      puts (h - a) == 7
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "bigint return int literal" do
    result = ze0(<<~'RUBY')
      # A method whose return slot promoted to Bigint (an accumulator multiply under
      # --int-overflow=promote) but whose early guard returns a plain int literal
      # used to emit `return 0LL` through the sp_Bigint* slot -- a NULL pointer that
      # segfaulted the caller's first sp_bigint_cmp (tep's proxy retry loop). The
      # int value must wrap into a real bigint at the return boundary.
      class RetryPolicy
        attr_accessor :base_backoff_ms, :backoff_multiplier
        def initialize
          @base_backoff_ms = 0
          @backoff_multiplier = 2
        end
        def backoff_for(attempt)
          if @base_backoff_ms <= 0
            return 0
          end
          d = @base_backoff_ms
          i = 0
          while i < attempt
            d = d * @backoff_multiplier
            i += 1
          end
          d
        end
      end

      class Base
        def retry_policy
          RetryPolicy.new
        end
        def handle(attempt)
          policy = retry_policy
          backoff = policy.backoff_for(attempt)
          if backoff > 0
            puts "sleep"
            puts backoff
          else
            puts "no sleep"
          end
        end
      end

      class Sub < Base
        def retry_policy
          p = RetryPolicy.new
          p.base_backoff_ms = 100
          p
        end
      end

      Base.new.handle(1)   # zero base -> the early `return 0` path
      Sub.new.handle(0)    # 100 * 2**0
      Sub.new.handle(3)    # 100 * 2**3
      Sub.new.handle(62)   # overflows mrb_int: the promotion that types the slot
    RUBY

    _(result).must_answer <<~'OUT'
      no sleep
      sleep
      100
      sleep
      800
      sleep
      461168601842738790400
    OUT
  end

  it "boolean short circuit" do
    result = ze0(<<~'RUBY')
      x = 5
      y = 3
      puts((x > y) && :yes)
      puts((x < y) && :yes)
      puts((x < y) || :fallback)
      puts((x > y) || :fallback)
      puts(!(x > y))
      puts(!(x < y))
    RUBY

    _(result).must_answer <<~'OUT'
      yes
      false
      fallback
      true
      false
      true
    OUT
  end

  it "case fallthrough returns nil" do
    result = ze0(<<~'RUBY')
      # Issue #707: case without `else` returns nil on fallthrough.
      puts (case 99; when 1; "one"; end).inspect
      puts (case 1; when 1; "one"; end).inspect
      puts (case "x"; when "a"; 42; end).inspect
      puts (case "a"; when "a"; 42; end).inspect

      # With else clause - unchanged behavior.
      puts (case 99; when 1; "one"; else; "other"; end)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "one"
      nil
      42
      other
    OUT
  end

  it "case when splat" do
    result = ze0(<<~'RUBY')
      # `when *list` spreads the list the way a call site's splat does: a plain
      # value is one candidate and nil is none. With a subject each candidate
      # answers `===`; without one, its own truth is the test.
      def kind(value, candidates)
        case value
        when *candidates then :hit
        else :miss
        end
      end

      p kind(1, [1, 2])
      p kind(9, [1, 2])
      p kind(5, 5)
      p kind(5, nil)
      p kind(5, 4..6)
      p kind("s", [Integer, String])

      def any_of(*flags)
        case
        when *flags then :yes
        else :no
        end
      end

      p any_of(false, nil)
      p any_of(false, 1)
      p any_of

      # The candidates run in order and stop at the first hit.
      def loud(tag, value)
        puts "test #{tag}"
        value
      end

      case 2
      when *[loud("first", 1)], *[loud("second", 2)], *[loud("third", 3)] then puts "matched"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      :hit
      :miss
      :hit
      :miss
      :hit
      :hit
      :no
      :yes
      :no
      test first
      test second
      matched
    OUT
  end

  it "case when with and without a subject" do
    result = ze0(<<~'RUBY')
      day = :tue
      case day
      when :sat, :sun
        puts :weekend
      when :mon, :tue, :wed, :thu, :fri
        puts :weekday
      else
        puts :unknown
      end

      n = 7
      case
      when n < 0
        puts :negative
      when n == 0
        puts :zero
      else
        puts :positive
      end

      x = :z
      case x
      when :a
        puts :got_a
      else
        puts :fallback
      end
    RUBY

    _(result).must_answer <<~'OUT'
      weekday
      positive
      fallback
    OUT
  end

  it "catch throw through loop" do
    result = ze0(<<~'RUBY')
      # throw from inside `loop` passes through loop's StopIteration handler (a
      # non-local unwind in transit, like every begin/rescue passes it through);
      # a break-less loop as the catch body tail types as nil and rides the slot.
      i = 0
      catch(:done) do
        loop do
          i += 1
          throw :done if i > 4
        end
      end
      p i
      r = catch(:x) do
        loop do
          throw :x, 42
        end
      end
      p r
    RUBY

    _(result).must_answer "5\n42\n"
  end

  it "if, elsif, case, while, until, the modifiers and a rescue all take the branch they should" do
    result = ze0(<<~'RUBY', path: "ze0/control_flow.rb")
      def grade(n)
        if n >= 90
          "A"
        elsif n >= 80
          "B"
        elsif n >= 70
          "C"
        else
          "F"
        end
      end

      def classify(n)
        if n < 0
          if n < -10
            "very negative"
          else
            "negative"
          end
        else
          if n == 0
            "zero"
          elsif n > 10
            "big"
          else
            "small"
          end
        end
      end

      i = 0
      s = 0
      while i < 100
        s = s + i
        i = i + 1
      end
      puts s

      n = 10
      f = 1
      while n > 1
        f = f * n
        n = n - 1
      end
      puts f

      w = while false do end
      p w

      i = 0
      until i == 3
        i = i + 1
      end
      p i

      unless i == 3
        puts "no"
      else
        puts "yes"
      end

      unless i == 4
        puts "not four"
      end

      z = until true do end
      p z

      puts grade(95)
      puts grade(85)
      puts grade(75)
      puts grade(10)

      x = if 1 < 2 then 10 else 20 end
      puts x
      y = if 1 > 2 then 10 end
      p y
      puts(if false then 1 else 2 end)

      puts classify(-20)
      puts classify(-5)
      puts classify(0)
      puts classify(5)
      puts classify(50)

      # `begin` with no clause is a grouping, and the memo shape ze0's own
      # sources are full of.
      memo = {}
      memo[:k] ||= begin
        1 + 1
      end
      p memo

      def catch_it
        raise "boom"
      rescue => e
        "caught #{e.class}: #{e.message}"
      end
      p catch_it

      def by_class(err)
        begin
          raise err, "m"
        rescue TypeError, ArgumentError => x
          "listed #{x.class}"
        rescue StandardError
          "standard"
        end
      end
      p by_class(ArgumentError), by_class(TypeError), by_class(RuntimeError)

      p(begin
        raise "b"
      rescue
        42
      end)

      p(begin
        7
      rescue
        :caught
      else
        :fine
      end)

      begin
        raise "outer"
      rescue => a
        begin
          raise "inner"
        rescue => b
          p $!.message
        end
        p $!.message, a.message, b.message
      end
      p $!

      class Fussy < StandardError
        def initialize(msg = "fussy") = super
      end

      begin
        begin
          raise Fussy
        rescue ArgumentError
          p :never
        end
      rescue Fussy => e
        p e.message, e.class
      end

      def deep = raise("down there")
      def shallow
        deep
      rescue => e
        e.backtrace.first(2)
      end
      p shallow

      def early
        begin
          raise "x"
        rescue => e
          return "returned #{e.message}"
        end
        :never
      end
      p early, $!

      acc = [1, 2, 3].map do |i|
        begin
          raise "e#{i}" if i == 2
          i
        rescue => e
          next e.message
        end
      end
      p acc

      stopped = [1, 2].each do |i|
        begin
          raise "x"
        rescue
          break :stopped
        end
      end
      p stopped

      i = 0
      seen = []
      while i < 3
        begin
          raise "e" if i == 1
          seen << i
        rescue => e
          seen << e.message
        end
        i += 1
      end
      p seen
    RUBY

    _(result).must_answer <<~'OUT'
      4950
      3628800
      nil
      3
      yes
      not four
      nil
      A
      B
      C
      F
      10
      nil
      2
      very negative
      negative
      zero
      small
      big
      {k: 2}
      "caught RuntimeError: boom"
      "listed ArgumentError"
      "listed TypeError"
      "standard"
      42
      :fine
      "inner"
      "outer"
      "outer"
      "inner"
      nil
      "fussy"
      Fussy
      ["ze0/control_flow.rb:152:in 'Object#deep'", "ze0/control_flow.rb:154:in 'Object#shallow'"]
      "returned x"
      nil
      [1, "e2", 3]
      :stopped
      [0, "e", 2]
    OUT
  end

  it "each entry returns receiver" do
    result = ze0(<<~'RUBY')
      # Enumerable#each_entry answers the receiver, like #each.
      #
      # It had no emitter at all for a Hash or a Range, and answered nil for an Array
      # and a Dir, so chaining off the result raised NoMethodError on a value that in
      # Ruby is the enumerable itself.
      #
      # On any receiver whose #each yields ONE value per element -- every builtin
      # enumerable -- each_entry IS each, so it is renamed to one. A user Enumerable
      # is left alone: its #each may `yield a, b`, and there the two differ (see
      # docs/limitations.md).

      # our own directory, not a platform-specific one; the name never reaches the
      # output, only the entries do
      dir = "/tmp/sp_each_entry_#{Process.pid}"
      Dir.mkdir(dir) unless Dir.exist?(dir)
      File.write(File.join(dir, "a.txt"), "x")

      d = Dir.new(dir)
      p d.each_entry { |e| }.class
      d.close

      d = Dir.new(dir)
      seen = []
      d.each_entry { |e| seen.push(e) }
      p seen.sort
      d.close

      File.delete(File.join(dir, "a.txt"))
      Dir.rmdir(dir)

      # the builtin enumerables, each answering itself
      arr = [1, 2, 3]
      p arr.each_entry { |x| }.class
      p(arr.each_entry { |x| }.equal?(arr))

      h = { "a" => 1, "b" => 2 }
      p h.each_entry { |pair| }.class

      r = (1..3)
      p r.each_entry { |x| }.class

      # the elements are what #each yields, in order
      acc = []
      arr.each_entry { |x| acc.push(x * 2) }
      p acc

      pairs = []
      h.each_entry { |k, v| pairs.push([k, v]) }
      p pairs

      # a user Enumerable keeps its own path and still answers itself
      class Trio
        include Enumerable

        def each
          yield 1
          yield 2
          yield 3
        end
      end

      t = Trio.new
      p t.each_entry { |x| }.class
      got = []
      t.each_entry { |x| got.push(x) }
      p got
    RUBY

    _(result).must_answer <<~'OUT'
      Dir
      [".", "..", "a.txt"]
      Array
      true
      Hash
      Range
      [2, 4, 6]
      [["a", 1], ["b", 2]]
      Trio
      [1, 2, 3]
    OUT
  end

  it "each return value" do
    result = ze0(<<~'RUBY')
      # Block-form each (and each_value/each_key/each_pair/each_with_index/
      # reverse_each) returns its receiver, so the value composes and chains.
      r = [1, 2, 3].each { |x| x }
      p r
      b = [1, 2, 3].each { |x| x }.map { |x| x * 2 }
      p b
      h = { a: 1 }.each_value { |v| v }
      p h.size
      k = { a: 1, b: 2 }.each_key { |x| x }
      p k.keys
      w = [1, 2].each_with_index { |x, i| x }
      p w
      v = [3, 4].reverse_each { |x| x }
      p v
      sum = 0
      res = (1..3).each { |i| sum += i }
      p sum
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [2, 4, 6]
      1
      [:a, :b]
      [1, 2]
      [3, 4]
      6
    OUT
  end

  it "end block registers once per site" do
    result = ze0(<<~'RUBY')
      # `END { }` registers its block the first time its site runs and never
      # again, however often the site is reached; two sites register two.
      3.times { END { puts "end in a loop" } }
      2.times do |i|
        END { puts "second site" }
      end
      puts "body"

    RUBY

    _(result).must_answer <<~'OUT'
      body
      second site
      end in a loop
    OUT
  end

  it "enum for each" do
    result = ze0(<<~'RUBY')
      # enum_for(:each) / to_enum materializes a user class's #each into an array, so
      # the full Enumerable surface (to_a/map/select/count/...) works on a class that
      # only defines #each. The compiler synthesizes a per-class helper that drives
      # the (lowered) #each with a collector block.
      class Bag
        include Enumerable

        def initialize
          @items = []
        end

        def add(x)
          @items << x
          self
        end

        def each
          @items.each { |x| yield x }
        end
      end

      class Counter
        def initialize(n)
          @n = n
        end

        def each
          i = 1
          while i <= @n
            yield i
            i += 1
          end
        end
      end

      b = Bag.new
      b.add("apple").add("banana").add("cherry")

      p b.enum_for(:each).to_a
      p b.to_enum.to_a
      p b.enum_for(:each).map { |s| s.upcase }
      p b.to_enum.select { |s| s.length > 5 }
      puts b.enum_for(:each).count
      puts b.enum_for(:each).include?("banana")

      c = Counter.new(4)
      p c.enum_for(:each).to_a
      p c.to_enum.map { |n| n * n }
      puts c.enum_for(:each).select { |n| n.even? }.length
    RUBY

    _(result).must_answer <<~'OUT'
      ["apple", "banana", "cherry"]
      ["apple", "banana", "cherry"]
      ["APPLE", "BANANA", "CHERRY"]
      ["banana", "cherry"]
      3
      true
      [1, 2, 3, 4]
      [1, 4, 9, 16]
      2
    OUT
  end

  it "flat map poly return" do
    result = ze0(<<~'RUBY')
      # flat_map whose block value is not statically an array -- a bare poly, or a mix
      # of array and scalar as in `cond ? sub_array : scalar` -- follows CRuby: an array
      # value is spliced one level, a scalar is appended as-is. Distinct per-case
      # helpers keep each receiver's element type clean; the method param defeats
      # constant folding of the receiver.
      def pa(x) = x
      def pb(x) = x
      def pc(x) = x
      def pe(x) = x

      p pa([1, [2, 3], 4]).flat_map { |e| e.is_a?(Array) ? e : e }        # [1, 2, 3, 4]
      p pb([1, [2, 3], 4]).flat_map { |e| e.is_a?(Array) ? e : [e, e] }   # [1, 1, 2, 3, 4, 4]
      p pc([:x, [:y, :z], :w]).flat_map { |e| e.is_a?(Array) ? e : e }    # [:x, :y, :z, :w]

      # a `next` that carries a mixed value flattens like the tail
      p pe([1, [2], 3]).flat_map { |e| next e if e.is_a?(Array); e }      # [1, 2, 3]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [1, 1, 2, 3, 4, 4]
      [:x, :y, :z, :w]
      [1, 2, 3]
    OUT
  end

  it "for loops" do
    result = ze0(<<~'RUBY')
      sum = 0
      for i in 1..5
        sum += i
      end
      puts sum
      puts i

      arr = [10, 20, 30]
      for el in arr
        puts el
      end

      # Over a hash, `for k, v` destructures each pair; `for pair` takes it whole.
      total = 0
      for k, v in { "a" => 1, "b" => 2, "c" => 3 }
        total += v
        puts "#{k}:#{v}"
      end
      p total

      for pair in { x: 10, y: 20 }
        p pair
      end

      # A parenthesized range or array iterates just like the bare form.
      psum = 0
      for n in (1..3)
        psum += n
      end
      p psum

      for e in ([9, 8])
        p e
      end

      # A `for` loop evaluates to the collection it iterated (unless the body
      # `break`s with a value).
      p(for x in [1, 2, 3]; end)     # [1, 2, 3]
      p(for x in [1, 2]; break :done; end)   # :done
    RUBY

    _(result).must_answer <<~'OUT'
      15
      5
      10
      20
      30
      a:1
      b:2
      c:3
      6
      [:x, 10]
      [:y, 20]
      6
      9
      8
      [1, 2, 3]
      :done
    OUT
  end

  it "for var two element types" do
    result = ze0(<<~'RUBY')
      # A `for` loop variable is an ordinary local, so two loops binding the same
      # name share one C slot. It was typed from whichever loop the pass reached
      # last, and the other then assigned a String element into an sp_int slot. The
      # slot now holds the union of every loop's element type, and a typed array's
      # element is boxed into it (#4168).
      def cmd(models)
        out = []
        for n in models.keys.sort
          out.push(n)
        end
        for n in [1, 2]
          out.push(n)
        end
        for n in (0..1)
          out.push(n)
        end
        for n in [1.5]
          out.push(n)
        end
        out
      end
      p cmd({ "b" => 1, "a" => 2 })

      # single loop of each kind still keeps its concrete slot
      def one
        t = 0
        for i in [1, 2, 3]
          t += i
        end
        s = ""
        for w in ["x", "y"]
          s += w
        end
        [t, s]
      end
      p one

      # a for over a range and over a hash
      h = { "k" => 1 }
      for pair in h
        p pair
      end
      for a, b in [[1, 2], [3, 4]]
        p [a, b]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", 1, 2, 0, 1, 1.5]
      [6, "xy"]
      ["k", 1]
      [1, 2]
      [3, 4]
    OUT
  end

  it "loop answers with the value its break was given" do
    result = ze0(<<~'RUBY')
      r = loop { break 42 }
      puts r.inspect
      puts r.class

      r2 = loop {
        x = 0
        loop { x += 1; break if x > 3 }
        break x
      }
      puts r2.inspect

      i = 0
      loop { i += 1; break if i >= 5 }
      puts i
    RUBY

    _(result).must_answer <<~'OUT'
      42
      Integer
      4
      5
    OUT
  end

  it "ignore case flag" do
    result = ze0(<<~'RUBY')
      puts "HELLO".match?(/hello/i)
      puts "HELLO".match?(/hello/)
    RUBY

    _(result).must_answer "true\nfalse\n"
  end

  it "TrueClass and FalseClass are the classes a boolean matches in a case" do
    result = ze0(<<~'RUBY')
      b = true
      p(TrueClass === b)
      p(case b when TrueClass then :yes else :no end)
      f = false
      p(FalseClass === f)
      p(TrueClass === f)
      p(Integer === 5)
      p(Integer === b)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      :yes
      true
      false
      true
      false
    OUT
  end

  it "filter_map keeps what the block answers and drops what is nil" do
    result = ze0(<<~'RUBY')
      h = {a: 1, b: 2}
      p h.filter_map { |k, v| [k, v] if v > 1 }
      p h.filter_map { |k, v| v * 10 if v > 1 }
      p [1, 2, 3].filter_map { |x| [x] if x.odd? }
      p({x: 5}.filter_map { |k, v| nil })
    RUBY

    _(result).must_answer <<~'OUT'
      [[:b, 2]]
      [20]
      [[1], [3]]
      []
    OUT
  end

  it "break takes a value out of a while loop" do
    result = ze0(<<~'RUBY')
      list, kept = ["--", "x"], []
      while (i = list.shift)
        case i
        when "--" then break kept.concat(list)
        end
      end
      p kept
      n = 0
      while true
        break (n += 5)
      end
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      ["x"]
      5
    OUT
  end

  it "a lambda whose body ends after a loop answers its tail" do
    result = ze0(<<~'RUBY')
      g = ->() { loop { break }; 42 }
      p g.call
      h = ->() { r = []; loop { break }; [r, 1] }
      p h.call
      k = ->() { v = 0; loop { v += 1; break if v > 2 }; v }
      p k.call
      pr = proc { loop { break }; :done }
      p pr.call
    RUBY

    _(result).must_answer <<~'OUT'
      42
      [[], 1]
      3
      :done
    OUT
  end

  it "iterator tail returns receiver" do
    result = ze0(<<~'RUBY')
      def each001(h001); h001.each { |k001, v001| nil }; end
      p each001({ "a" => 1 })

      def each002(a002); a002.each { |x002| nil }; end
      p each002([1, 2])

      def each003(r003); r003.each { |x003| nil }; end
      p each003(1..2)

      def each004(n004); n004.times { |i004| nil }; end
      p each004(2)

      l005 = ->(h005) { h005.each { |k005, v005| nil } }
      p l005.call({ "a" => 1 })

      def each006(h006); if true then h006.each { |k006, v006| nil } else h006 end; end
      p each006({ "a" => 1 })

      def ep(h); h.each_pair { |k, v| nil }; end
      p ep({ "a" => 1 })

      def ek(h); h.each_key { |k| nil }; end
      p ek({ "a" => 1 })

      def ev(h); h.each_value { |v| nil }; end
      p ev({ "a" => 1 })

      def ewi(a); a.each_with_index { |x, i| nil }; end
      p ewi([1, 2])

      def re(a); a.reverse_each { |x| nil }; end
      p re([1, 2])

      def es(a); a.each_slice(2) { |x| nil }; end
      p es([1, 2, 3])

      def up(n); n.upto(3) { |i| nil }; end
      p up(1)

      def st(n); n.step(5, 2) { |i| nil }; end
      p st(1)

      # these were already right; keep them pinned
      def ec(s); s.each_char { |ch| nil }; end
      p ec("ab")

      def mp(a); a.map { |x| x * 2 }; end
      p mp([1, 2])

      def each017(h017); return h017.each { |k017, v017| nil }; end
      p each017({ "a" => 1 })

      def each018(h018); r018 = h018.each { |k018, v018| nil }; r018; end
      p each018({ "a" => 1 })
    RUBY

    _(result).must_answer <<~'OUT'
      {"a" => 1}
      [1, 2]
      1..2
      2
      {"a" => 1}
      {"a" => 1}
      {"a" => 1}
      {"a" => 1}
      {"a" => 1}
      [1, 2]
      [1, 2]
      [1, 2, 3]
      1
      1
      "ab"
      [2, 4]
      {"a" => 1}
      {"a" => 1}
    OUT
  end

  it "jump values" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # A `return`, `next` or `break` that carries more than one value answers
      # one Array, and a lone `*xs` does too.

      def pair = return 1, 2
      def three
        return 3, 4, 5
      end
      def spread(a)
        return *a
      end
      def leading(a)
        return 1, *a
      end
      p pair
      p three
      p spread([7, 8])
      p spread([9])
      p leading([2, 3])

      # The same rule for the two jumps a block writes.
      p([1].map { next 5, 6 })
      def broken
        [1, 2].each { break 7, 8 }
      end
      p broken
      p [1, 2].map { |i| next i, i }

      # One value stays one value, and none is nil.
      def single = return 1
      def bare
        return
      end
      p single
      p bare
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [3, 4, 5]
      [7, 8]
      [9]
      [1, 2, 3]
      [[5, 6]]
      [7, 8]
      [[1, 1], [2, 2]]
      1
      nil
    OUT
  end

  it "loop bigint return" do
    result = ze0(<<~'RUBY')
      # A method whose loop-carried local is bigint-promoted (d = d * 2) and then
      # returned must have a bigint (sp_Bigint *) return type, not void. Bigint was
      # missing from is_scalar_ret and c_type_name, so such methods emitted
      # `static void` and any use of the result was a hard C error.
      def doublings(n)
        d = 1
        i = 0
        while i < n
          d = d * 2
          i += 1
        end
        d
      end
      puts doublings(100)

      def factorial(n)
        r = 1
        i = 1
        while i <= n
          r = r * i
          i += 1
        end
        r
      end
      puts factorial(30)
      x = doublings(3)
      puts(x > 0 ? "positive" : "nonpositive")
    RUBY

    _(result).must_answer <<~'OUT'
      1267650600228229401496703205376
      265252859812191058636308480000000
      positive
    OUT
  end

  it "not and the gates on every receiver" do
    result = ze0(<<~'RUBY')
      # `not` and `!` on every kind of receiver, before and after the classes
      # nil, true and false stand under gain a `!` of their own, and mixed
      # with the operators whose gates flip on redefinition.
      vals = [nil, false, true, 0, 1, -1, 1.5, 0.0, :sym, "", "s", [], {}, Object.new, 1 << 70, (1..2), Struct.new(:a).new(1)]
      show = ->(tag) { p [tag, vals.map { |v| !v }, vals.map { |v| not v }, vals.map { |v| !!v }] }
      show.(:plain)
      class TrueClass
        def !
          :not_true
        end
      end
      show.(:true_redefined)
      class TrueClass
        remove_method :!
      end
      module Kernel
        def !
          :kernel_not
        end
      end
      show.(:kernel)
      module Kernel
        remove_method :!
      end
      class Integer
        alias_method :plus_before, :+
        def !
          :int_not
        end
        def +(o) = :plus
      end
      show.(:integer)
      p 1 + 2, 1.5 + 2, (not 1), !1, !2.5
      class Integer
        remove_method :!
        alias_method :+, :plus_before
      end
      p 1 + 2, !1, (not nil)
      class BasicObject
        alias_method :bang_before, :!
        def !
          :basic
        end
      end
      show.(:basic)
      class BasicObject
        alias_method :!, :bang_before
        remove_method :bang_before
      end
      show.(:restored)
      x = nil
      p((not x), (not not x), (!x ? 1 : 2), [x].map(&:!), (not (x.nil? and true)))



    RUBY

    _(result).must_answer <<~'OUT'
      [:plain, [true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false], [true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false], [false, false, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true]]
      [:true_redefined, [true, true, :not_true, false, false, false, false, false, false, false, false, false, false, false, false, false, false], [true, true, :not_true, false, false, false, false, false, false, false, false, false, false, false, false, false, false], [:not_true, :not_true, false, true, true, true, true, true, true, true, true, true, true, true, true, true, true]]
      [:kernel, [:kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not], [:kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not], [:kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not, :kernel_not]]
      [:integer, [true, true, false, :int_not, :int_not, :int_not, false, false, false, false, false, false, false, false, :int_not, false, false], [true, true, false, :int_not, :int_not, :int_not, false, false, false, false, false, false, false, false, :int_not, false, false], [false, false, true, false, false, false, true, true, true, true, true, true, true, true, false, true, true]]
      :plus
      3.5
      :int_not
      :int_not
      false
      3
      false
      true
      [:basic, [:basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic], [:basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic], [:basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic, :basic]]
      [:restored, [true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false], [true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false], [false, false, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true]]
      true
      false
      1
      [true]
      false
    OUT
  end

  it "not stays inline for nil true and false" do
    result = ze0(<<~'RUBY')
      # `not v` and `!v` answer inline for nil, true and false while none of
      # their classes redefines `!`; any other receiver sends `!` through its
      # own site, so a class with its own `!` answers, and a `!` written on
      # NilClass, Object or BasicObject reaches the three too.
      class Yes
        def !
          :custom
        end
      end
      class Quiet < BasicObject
        def !
          :quiet
        end
      end
      p (not nil), (not true), (not false), !nil, !0, !"", ![], !Yes.new, !Quiet.new, (not Yes.new)
      p [nil, false, true, 1, :a].map { |v| not v }
      def loud(x) = (not x)
      p loud(false), loud(Yes.new)
      class Object
        def !
          :object
        end
      end
      p (not nil), (not true), (not false), !3, !"s", (not Yes.new)
      class Object
        remove_method :!
      end
      class NilClass
        def !
          :nil_not
        end
      end
      p (not nil), (not true), (not false), !nil, !!nil
      class NilClass
        remove_method :!
      end
      p (not nil), (not 1), loud(nil)
      o = Object.new
      def o.!
        :single
      end
      p (not o), !o

    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      false
      false
      false
      :custom
      :quiet
      :custom
      [true, true, false, false, false]
      true
      :custom
      :object
      :object
      :object
      :object
      :object
      :custom
      :nil_not
      false
      true
      :nil_not
      false
      true
      false
      true
      :single
      :single
    OUT
  end

  it "not user object" do
    result = ze0(<<~'RUBY')
      class Obj
        def initialize; @x = 7; end
      end
      p(!Obj.new)
      p(not Obj.new)
      o = Obj.new
      p(!o)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
    OUT
  end

  it "parenthesized body ending in self returns self" do
    result = ze0(<<~'RUBY')
      # `def m = (@x = 2; self)` -- a `Seq` whose tail is `self`. The `Seq`
      # block emitted its tail unboxed (`Arc<Concrete>`) while every consumer
      # of a `Seq` (which always infers `Poly`) expects a boxed `RubyValue` --
      # an E0308 in `Ok(...)` position. The `Seq` now boxes its own tail.

      class C
        def initialize = (@x = 1)
        def tap_self = (@x = 2; self)
        attr_reader :x
      end
      c = C.new
      p c.tap_self.equal?(c)
      p c.x
    RUBY

    _(result).must_answer "true\n2\n"
  end

  it "poly recv while family" do
    result = ze0(<<~'RUBY')
      # find_all / take_while / drop_while on a receiver only known to be a
      # container at run time. select and reject had an arm; these three fell
      # through to the loud NoMethodError.
      rows = [[1, 2, 4, 5], { "a" => 1, "b" => 2 }, "x"]

      arr = rows[0]
      p arr.take_while { |x| x < 4 }
      p arr.drop_while { |x| x < 4 }
      p arr.find_all { |x| x > 2 }
      p arr.select { |x| x > 2 }
      p arr.reject { |x| x > 2 }

      # find_all is not a third spelling of select: on a Hash it answers the pairs
      # as an Array, where select answers a Hash.
      h = rows[1]
      p h.take_while { |k, n| n < 2 }
      p h.drop_while { |k, n| n < 2 }
      p h.find_all { |k, n| n > 1 }
      p h.select { |k, n| n > 1 }

      # and each answers nil through a safe-nav guard
      def pick(n) = n > 0 ? [1, 2, 4, 5] : nil
      [1, 0].each do |k|
        v = pick(k)
        p v&.take_while { |x| x < 4 }
        p v&.drop_while { |x| x < 4 }
        p v&.find_all { |x| x > 2 }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [4, 5]
      [4, 5]
      [4, 5]
      [1, 2]
      [["a", 1]]
      [["b", 2]]
      [["b", 2]]
      {"b" => 2}
      [1, 2]
      [4, 5]
      [4, 5]
      nil
      nil
      nil
    OUT
  end

  it "poly size user return" do
    result = ze0(<<~'RUBY')
      # `size` / `length` on a poly receiver answers an Integer -- unless a user class
      # owns the name and answers something else, in which case the call is a union.
      # The dispatch always emits the builtin length arms (a symbol, a string, every
      # array and hash kind), so pinning the call to Integer left their sp_int and
      # the user arm's own return meeting in one C slot:
      #
      #   error: assignment to 'sp_int' from 'sp_PolyArray *'
      #
      # Only a DISAGREEING user return widens it. A user `size` that answers an
      # Integer already agrees with the builtins, and widening every `poly.size`
      # would box a count the whole program reads as a number.
      class Widget
        def size(extra = nil) = [1, extra]
      end
      class Counter
        def size = 7
      end
      def mk(f) = f ? Widget.new : [1, 2]
      def mk2(f) = f ? Counter.new : [1, 2]
      p mk(true).size
      p mk(false).size
      p mk2(true).size
      p mk2(false).size
      p [Widget.new, [1,2]][0].size
      p [Widget.new, [1,2]][1].size
      p [Counter.new, "ab"][1].size
      v = mk(true)
      p v.size
      p v.size.class
      p({a: 1, b: 2}.size)
      p [1,2,3].size
      p "abc".size
      p :sym.size
    RUBY

    _(result).must_answer <<~'OUT'
      [1, nil]
      2
      7
      2
      [1, nil]
      2
      2
      [1, nil]
      Array
      2
      3
      3
      3
    OUT
  end

  it "promote block loop bigint" do
    result = ze0(<<~'RUBY')
      # promote-only: an accumulator multiplied inside a block-iteration loop grows
      # past 64 bits. In --int-overflow=promote the analyzer widens it to bigint
      # (the same self-referential-multiply detection used for `while`, extended to
      # block loops); in raise/wrap mode this would raise, so the test is filtered
      # out of those runs by the Makefile.

      # .times block, `acc = acc * x` form
      f = 1
      25.times { |i| f = f * (i + 1) }
      puts f

      # range#each block
      g = 1
      (1..30).each { |k| g = g * 2 }
      puts g

      # .times block, operator-assign on a captured accumulator (bigint cell)
      h = 1
      40.times { h *= 3 }
      puts h
    RUBY

    _(result).must_answer <<~'OUT'
      15511210043330985984000000
      1073741824
      12157665459056928801
    OUT
  end

  it "safe nav arg iterators" do
    result = ze0(<<~'RUBY')
      # `v&.each_slice(n) { }` / `v&.each_cons(n) { }`. The re-dispatch materializes
      # the boxed receiver into a poly array and re-enters the call so the array
      # emitters serve it -- and poking the receiver's cached type is not enough to
      # make them: under the guard, the re-emission asks the inference again and
      # re-establishes the receiver as poly, so they declined and the call fell
      # through to NoMethodError. The node is pinned for the inference now.
      def pick(n) = n > 0 ? [1, 2, 4, 5] : nil
      def hash_or_nil(n) = n > 0 ? { "a" => 1, "b" => 2 } : nil

      [1, 0].each do |k|
        v = pick(k)
        p v&.each_slice(2) { |s| s }
        p v&.each_cons(2) { |s| s }
        h = hash_or_nil(k)
        p h&.each_slice(1) { |s| s }
        p h&.each_cons(1) { |s| s }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 4, 5]
      [1, 2, 4, 5]
      {"a" => 1, "b" => 2}
      {"a" => 1, "b" => 2}
      nil
      nil
      nil
      nil
    OUT
  end

  it "safe nav no c nil result" do
    result = ze0(<<~'RUBY')
      # A `&.` whose answer has no C nil to hold one -- a Class, a Symbol, a Rational,
      # a Complex -- has to be poly, the way a C bool already had to be. The rules
      # that said so were placed by position in the inference chain, so the names
      # resolved earlier (`class` at the object arm, `to_sym` at the String arm) kept
      # their concrete type while the emitted guard boxed nil into it anyway.

      def klass(v) = v&.class
      def as_sym(v) = v&.to_sym
      def ident(v) = v&.object_id

      ["abc", nil].each do |v|
        p klass(v)
        p as_sym(v)
        p ident(v).nil?
      end

      # the types that DO have a C nil keep it, and keep their concrete type: the
      # guard's nil arm is the array's NULL, the string's NULL, the int's sentinel
      def letters(v) = v&.chars
      def up(v) = v&.upcase
      def len(v) = v&.size

      ["abc", nil].each do |v|
        p letters(v)
        p up(v)
        p len(v)
      end

      # a Class answer flowing on: the widened value still reads as a Class
      p klass("x") == String
      p klass(nil) == String
      p klass(nil).nil?
      p as_sym("x") == :x
      p as_sym(nil).nil?
    RUBY

    _(result).must_answer <<~'OUT'
      String
      :abc
      false
      nil
      nil
      true
      ["a", "b", "c"]
      "ABC"
      3
      nil
      nil
      nil
      true
      false
      true
      true
      true
    OUT
  end

  it "safe nav operator write" do
    result = ze0(<<~'RUBY')
      # `o&.v op= rhs` runs nothing at all when the receiver is nil -- not the
      # read, not the right-hand side -- and answers nil. The receiver itself is
      # evaluated exactly once, before the guard.
      class Box
        attr_accessor :v

        def initialize(v) = @v = v
      end

      def watch(tag, value)
        puts "eval #{tag}"
        value
      end

      empty = nil
      p(empty&.v ||= 8)
      p(empty&.v &&= 8)
      p(empty&.v += 1)
      p(empty&.v = 3)

      blank = Box.new(nil)
      p(blank&.v ||= 8)
      p(blank.v)

      counter = Box.new(2)
      p(counter&.v += 1)
      p(counter&.v &&= 9)
      p(counter.v)

      p(watch("nil receiver", nil)&.v ||= watch("skipped", 1))
      p(watch("real receiver", Box.new(nil))&.v ||= watch("taken", 5))

      # `&.` guards nil alone, so `false` still takes the call and raises.
      begin
        false&.v ||= 1
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      8
      8
      3
      9
      9
      eval nil receiver
      nil
      eval real receiver
      eval taken
      5
      undefined method 'v' for false
    OUT
  end

  it "safe nav or nil" do
    result = ze0(<<~'RUBY')
      class Inner005
        def opacity005; 0.5; end
        def name005; "hi"; end
        def size005; 3; end
      end

      class Outer005
        def initialize(c005); @c005 = c005; end
        def value005(override005); override005 || @c005&.opacity005; end
        def name005(override005); override005 || @c005&.name005; end
        def size005(override005); override005 || @c005&.size005; end
      end

      p Outer005.new(Inner005.new).value005(nil)
      p Outer005.new(nil).value005(nil)
      p Outer005.new(nil).value005(1.5)
      p Outer005.new(Inner005.new).name005(nil)
      p Outer005.new(nil).name005(nil)
      p Outer005.new(Inner005.new).size005(nil)
      p Outer005.new(nil).size005(nil)
    RUBY

    _(result).must_answer <<~'OUT'
      0.5
      nil
      1.5
      "hi"
      nil
      3
      nil
    OUT
  end

  it "safe nav predicate" do
    result = ze0(<<~'RUBY')
      x = nil
      p(x&.positive?)
      def f(v)
        v&.positive? ? "y" : "n"
      end
      puts f(5)
      puts f(nil)
      y = 5
      p(y&.positive?)
      p(y&.zero?)
      p(y&.abs)
      s = nil
      p(s&.empty?)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      y
      n
      true
      false
      5
      nil
    OUT
  end

  it "safe navigation" do
    result = ze0(<<~'RUBY')
      class Box
        def initialize(value)
          @value = value
        end
        def value
          @value
        end
      end

      b = Box.new(:present)
      puts(b&.value)
    RUBY

    _(result).must_answer "present\n"
  end

  it "safe navigation returns nil" do
    result = ze0(<<~'RUBY')
      # Issue #701: safe navigation `&.` on nil returns nil.

      # Literal nil receiver — short-circuits without warning.
      v1 = nil&.foo
      puts v1.inspect

      # Dynamic nullable receiver — short-circuits when nil, dispatches when not.
      def maybe_str(b)
        b ? "hello" : nil
      end

      puts maybe_str(true)&.upcase
      puts maybe_str(false)&.upcase.inspect

      # Non-nil case — `&.` behaves identical to `.`.
      s = "world"
      puts s&.length

      # Hash recv (typed nullable from RBS / return inference).
      def maybe_hash(b)
        return nil unless b
        h = {}
        h["k"] = "v"
        h
      end

      puts maybe_hash(true)&.length
      puts maybe_hash(false)&.length.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      HELLO
      nil
      5
      1
      nil
    OUT
  end

  it "safe navigation target writes only to a receiver" do
    result = ze0(<<~'RUBY')
      # A safe-navigation target writes only when its receiver is not nil:
      # `rescue => o&.x` and `for o&.x in list`.
      class Box
        attr_accessor :x
      end

      o = Box.new
      begin
        raise "boom"
      rescue => o&.x
      end
      p o.x.message

      n = nil
      begin
        raise "boom"
      rescue => n&.x
      end
      p n

      q = Box.new
      for q&.x in [1, 2]; end
      p q.x

      z = nil
      for z&.x in [1, 2]; end
      p z

    RUBY

    _(result).must_answer <<~'OUT'
      "boom"
      nil
      2
      nil
    OUT
  end

  it "ternary" do
    result = ze0(<<~'RUBY')
      n = 7
      puts(n > 5 ? :big : :small)
    RUBY

    _(result).must_answer "big\n"
  end

  it "then block always breaks" do
    result = ze0(<<~'RUBY')
      # A `then` block whose body always `break`s completes normally nowhere, so it
      # published no result type and the value slot the block substrate writes was
      # declared `void`, which cannot declare a C variable. The break delivers its
      # value through the break stack, so the slot is dead on that path -- it just
      # has to have a type. A body that CAN fall through was always fine, which is
      # what the conditional-break lines below hold in place.
      p 1.then { next 2 }
      p 1.tap { next 2 }
      p 1.tap { break 2 }
      p [1].each { break 2 }
      p 1.then { |x| break 2 if x == 1; 3 }
      p 1.then { |x| break 2 if x == 9; 3 }
      p "s".then { break }
      p [1,2].map { |x| x.then { break 9 } }
      def m
        r = 1.then { break 5 }
        r
      end
      p m
      h = {"k" => 1}
      p h.then { break [] }
      p 2.then { break 3.5 }
    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      2
      2
      2
      3
      nil
      [9, 9]
      5
      []
      3.5
    OUT
  end

  it "void value and case" do
    result = ze0(<<~'RUBY')
      # A value-form && / || whose unified type is nil/void, and a case whose
      # scrutinee is an empty container literal, must not declare a `void` C temp
      # (an empty `()` operand or `[]` scrutinee has no scalar storage type).
      p((() && true))
      p((true && ()))
      p((() and true))
      p((true or ()))
      r = case []
          when [] then "empty"
          else "other"
          end
      p r
      h = case {}
          when {} then "eh"
          else "oh"
          end
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      true
      "empty"
      "eh"
    OUT
  end
end
