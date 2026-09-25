# frozen_string_literal: true

require "spec_helper"

describe "Enumerable: regressions" do
  it "dig nested poly array" do
    result = zr(<<~'RUBY')
      # Array#dig walks through nested arrays of mixed element types with
      # Integer keys, and gives the leaf value.

      p [[1, [2, "3"]]].dig(0, 1, 1) == "3"   # true (string leaf)
      p [[1, [2, "3"]]].dig(0, 0) == 1        # true (int leaf)
      p [[1, [2, "3"]]].dig(0, 1, 0) == 2     # true
      p [[1, [2, "3"]]].dig(0, 1, 5).nil?     # true (OOB at the last step)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
    OUT
  end

  it "each cons map chain fusion" do
    result = zr(<<~'RUBY')
      # `arr.each_cons(n)` called without a block returns an Enumerator in
      # CRuby. When the very next call is a terminal like
      # `.map { |pair| ... }`, the Enumerator is consumed immediately and
      # the result is the same as a map over each window.
      #
      # The terminal block may take the window as a single param
      # (`|pair|`) or destructure it (`|(a, b)|`, binds individual locals).

      # T1: plain |pair| form, scalar block result
      p [1, 2, 3, 4].each_cons(2).map { |pair| pair[0] + pair[1] }

      # T2: destructure |(a, b)|, scalar block result
      p [10, 20, 30, 40].each_cons(2).map { |(a, b)| b - a }

      # T3: |pair| with array-returning block -> result is an Array of Arrays
      p [1, 2, 3].each_cons(2).map { |pair| [pair[0], pair[1]] }

      # T4: empty / short receiver (length < n) -> empty result
      p [1].each_cons(2).map { |pair| pair[0] }
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 5, 7]
      [10, 10, 10]
      [[1, 2], [2, 3]]
      []
    OUT
  end

  it "each cons with index map chain fusion" do
    result = zr(<<~'RUBY')
      # Three-step `arr.each_cons(n).with_index(off).map { ... }` chain. CRuby
      # returns an Enumerator from each_cons, then another from
      # with_index, and consumes both at the terminal .map. The index
      # starts at `off` (default 0) and goes up by one after each pair.
      #
      # Block param shapes:
      #   |pair, i|       -- pair is the sub-array, i is the Integer index
      #   |(a, b), i|     -- nested destructure of pair into individual
      #                      window elements, trailing i as Integer index

      # T1: |pair, i| with explicit offset
      p [10, 20, 30, 40].each_cons(2).with_index(1).map { |pair, i| pair[0] + pair[1] + i }

      # T2: |(a, b), i| destructure, explicit offset
      p [10, 20, 30, 40].each_cons(2).with_index(1).map { |(a, b), i| b - a + i }

      # T3: default offset (0)
      p [1, 2, 3].each_cons(2).with_index.map { |pair, i| pair[1] - pair[0] + i }

      # T4: block returns array -> result is an Array of Arrays
      p [1, 2, 3, 4].each_cons(2).with_index(1).map { |(a, b), i| [b - a, i] }
    RUBY

    _(result).must_answer <<~'OUT'
      [31, 52, 73]
      [11, 12, 13]
      [1, 2]
      [[1, 1], [1, 2], [1, 3]]
    OUT
  end

  it "env fetch" do
    result = zr(<<~'RUBY')
      # `ENV.fetch(key, default)` returns the env value when
      # set, otherwise `default`.

      # ---- unset / default branch ----

      # Literal default.
      puts ENV.fetch("DEFINITELY_UNSET_VAR_XYZ_42", "fallback-value")

      # Default expression need not be a literal.
      default = "computed-default"
      puts ENV.fetch("ANOTHER_UNSET_VAR_XYZ_42", default)

      # Default by string concatenation.
      puts ENV.fetch("THIRD_UNSET_VAR_XYZ_42", "pre-" + "fix")

      # ---- set / retrieval branch ----
      # The test does not set a var itself. HOME is always exported by
      # POSIX `make` and in CI, so the test uses it as the "set" probe. It
      # only asserts "non-empty + not the fallback string" so that it
      # stays portable across runners (the home value differs per machine).
      # If fetch gave the default for a set var, this prints
      # "set=fallback-not-used".
      home = ENV.fetch("HOME", "fallback-not-used")
      if home.length > 0 && home != "fallback-not-used"
        puts "set=ok"
      else
        puts "set=" + home
      end

      # Symmetric: an unset var with a literal default gives the default,
      # not an empty string.
      maybe = ENV.fetch("DEFINITELY_UNSET_VAR_ABC_99", "fallback-used")
      puts "unset=" + maybe
    RUBY

    _(result).must_answer <<~'OUT'
      fallback-value
      computed-default
      pre-fix
      set=ok
      unset=fallback-used
    OUT
  end

  it "equality should be true" do
    result = zr(<<~'RUBY')
      # A corpus of `should be true` expressions. Each line is an
      # independent equality predicate, and CRuby returns true for all
      # twelve.

      p ({} == {})                                     # 01
      p ({a: 1} == {a: 1})                             # 02
      p ({:a= => 1} == {:"a=" => 1})                   # 03
      p ({:a! => 1} == {:"a!" => 1})                   # 04
      p ({:a? => 1} == {:"a?" => 1})                   # 05
      a = [1] ; a.shift ; a << :foo ; p (a == [:foo])  # 06
      p ([42, { foo: :bar }].dig(1, :foo) == :bar)     # 07
      a2 = [1, 2, 3, 4, 5] ; p ((a2[2, 3] = 10) == 10) # 08
      p ("hello".chars == ['h', 'e', 'l', 'l', 'o'])   # 09
      p "abc\r\n".chomp(nil) == "abc\r\n"              # 10
      p ((/(.)(.)(.)/ =~ "abc") == 0)                  # 11
      p ((1..).send(:include?, 2.4) == true)           # 12
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
      true
      true
      true
    OUT
  end

  it "fiber storage assign expr" do
    result = zr(<<~'RUBY')
      # `(Fiber[:k] = v)` as an expression returns the assigned value,
      # matching MRI's `(h[k]=v) => v` semantics. The expression form is
      # different from the statement form `Fiber[:k] = v`: the RHS must
      # reach the outer assignment.

      x = (Fiber[:n] = 42)
      puts x                # 42 — value of the assignment expression
      puts Fiber[:n]        # 42 — confirms the write also took effect

      # Chained: `Fiber[:a] = Fiber[:b] = 7`. Right-to-left associativity
      # makes `Fiber[:b] = 7` evaluate first (yielding 7), then
      # `Fiber[:a] = 7`.
      Fiber[:a] = Fiber[:b] = 7
      puts Fiber[:a]
      puts Fiber[:b]
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      7
      7
    OUT
  end

  it "ptr array null guards" do
    result = zr(<<~'RUBY')
      # The full chain `each_cons(n).with_index(off).map { ... }` followed by
      # `.drop.take.max[i]` gives CRuby's `3`. Each step gets the array that
      # the step before it makes.

      q = [100, 90, 82, 70, 65]
      a = 2
      b = 4
      p q.each_cons(2).with_index(1).map { |(x, y), i| [x - y, i] }.drop(a - 1).take(b - a + 1).max[1]
    RUBY

    _(result).must_answer "3\n"
  end

  it "ptr array pop" do
    result = zr(<<~'RUBY')
      # `Array#pop` on a nested array (an Array of Integer Arrays) removes
      # the last element, and a later push adds to the array.

      a = [[1, 2]]
      puts "before pop: #{a.inspect}"
      a.pop
      puts "after  pop: #{a.inspect}"
      a.push([3, 4])
      puts "after push: #{a.inspect}"

      # Seed-and-pop idiom: array typed as Array<String> via the seed,
      # then drained and used as an accumulator.
      b = ["seed"]
      b.pop
      b.push("real")
      b.push("data")
      puts b.inspect

      # Multiple pops drain the array.
      c = [[10], [20], [30]]
      c.pop
      c.pop
      puts c.length
    RUBY

    _(result).must_answer <<~'OUT'
      before pop: [[1, 2]]
      after  pop: []
      after push: [[3, 4]]
      ["real", "data"]
      1
    OUT
  end

  it "puts mixed ternary" do
    result = zr(<<~'RUBY')
      # `puts cond ? :sym : int` prints the value of the arm that runs:
      # the Symbol's name, or the Integer. Each arm keeps its own type.

      a = 2
      puts a%2>0 ? :odd : a    # else: prints "2"

      b = 3
      puts b%2>0 ? :odd : b    # then: prints "odd"

      # Float vs string
      c = 1.5
      puts c > 0 ? "positive" : c  # then: "positive"
      puts c > 5 ? "big" : c       # else: 1.5
    RUBY

    _(result).must_answer <<~'OUT'
      2
      odd
      positive
      1.5
    OUT
  end

  it "sym array" do
    result = zr(<<~'RUBY')
      # Symbol array
      a = [:red, :green, :blue]
      puts a.length
      a.each { |s| puts s }

      # [] access
      puts a[0]
      puts a[2]

      # Also sym_int_hash each
      h = {x: 10, y: 20}
      h.each do |k, v|
        puts k.to_s + "=" + v.to_s
      end
    RUBY

    _(result).must_answer <<~'OUT'
      3
      red
      green
      blue
      red
      blue
      x=10
      y=20
    OUT
  end

  it "sym array empty push" do
    result = zr(<<~'RUBY')
      # An empty `[]` followed by `push(:sym)`: element access gives the
      # Symbols, and `puts` prints their names.

      syms = []
      syms.push(:tag)
      syms.push(:more)
      puts syms[0]      # tag
      puts syms[1]      # more
      puts syms.length  # 2

      # `<<` form should behave the same.
      syms2 = []
      syms2 << :alpha
      syms2 << :beta
      puts syms2[0]     # alpha
      puts syms2[1]     # beta
    RUBY

    _(result).must_answer <<~'OUT'
      tag
      more
      2
      alpha
      beta
    OUT
  end

  it "sym array full" do
    result = zr(<<~'RUBY')
      # Full Symbol array test
      a = [:red, :green, :blue, :yellow]

      # Basic access
      puts a.length       # 4
      puts a[0]           # red
      puts a[3]           # yellow
      puts a[-1]          # yellow

      # each
      a.each { |s| puts s }
      # red green blue yellow

      # push
      a.push(:purple)
      puts a.length       # 5

      # pop
      v = a.pop
      puts v              # purple

      # include?
      puts a.include?(:red)   # true
      puts a.include?(:pink)  # false

      # map
      b = a.map { |s| s.to_s }
      puts b.length       # 4
      puts b[0]           # red

      # select
      c = a.select { |s| s.to_s.length > 4 }
      puts c.length       # 2

      # each_with_index
      a.each_with_index do |s, i|
        if i == 0
          puts s          # red
        end
      end

      # sort (by symbol name, lexical)
      d = [:cherry, :apple, :banana]
      d_sorted = d.sort
      puts d_sorted[0]    # apple
      puts d_sorted[1]    # banana
      puts d_sorted[2]    # cherry

      # puts of a Symbol array
      puts a              # should print each element on its own line
    RUBY

    _(result).must_answer <<~'OUT'
      4
      red
      yellow
      yellow
      red
      green
      blue
      yellow
      5
      purple
      true
      false
      4
      red
      2
      red
      apple
      banana
      cherry
      red
      green
      blue
      yellow
    OUT
  end

  it "sym hash" do
    result = zr(<<~'RUBY')
      # Symbol-keyed hashes: Symbol keys are distinct from String keys.
      # Cover both Integer-valued and String-valued shapes — same
      # operator surface, different value types — in one file, with
      # different local names for the two hashes.

      # Int values
      hi = {a: 1, b: 2, c: 3}
      puts hi[:a]            # 1
      puts hi[:b]            # 2
      puts hi.length         # 3
      puts hi.has_key?(:a)   # true
      puts hi.has_key?(:z)   # false
      puts hi.empty?         # false
      hi[:d] = 4
      puts hi[:d]            # 4
      puts hi.length         # 4

      # String values
      hs = {name: "Alice", role: "admin"}
      puts hs[:name]              # Alice
      puts hs[:role]              # admin
      puts hs.length              # 2
      puts hs.has_key?(:name)     # true
      puts hs.has_key?(:unknown)  # false
      hs[:email] = "a@b.c"
      puts hs[:email]             # a@b.c
      puts hs.length              # 3
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      true
      false
      false
      4
      4
      Alice
      admin
      2
      true
      false
      a@b.c
      3
    OUT
  end

  it "sym hash keys values" do
    result = zr(<<~'RUBY')
      # keys / values for sym-keyed hash variants plus str_poly_hash.

      # sym_int_hash
      h1 = {a: 1, b: 2, c: 3}
      puts h1.keys.inspect
      puts h1.values.inspect
      puts h1.keys.length
      puts h1.values.length

      # sym_str_hash
      h2 = {name: "Alice", role: "admin"}
      puts h2.keys.inspect
      puts h2.values.inspect

      # sym_poly_hash (mixed value types)
      h3 = {name: "Alice", age: 30, active: true}
      puts h3.keys.inspect
      puts h3.values.inspect

      # str_poly_hash (string keys, mixed values)
      h4 = {"name" => "Alice", "age" => 30, "active" => true}
      puts h4.keys.inspect
      puts h4.values.inspect

      h1.keys.each do |k1|
        puts k1
      end
      h2.values.each do |sv|
        puts sv
      end
      h3.keys.each do |k3|
        puts k3
      end
      h3.values.each do |pv|
        puts pv
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, :b, :c]
      [1, 2, 3]
      3
      3
      [:name, :role]
      ["Alice", "admin"]
      [:name, :age, :active]
      ["Alice", 30, true]
      ["name", "age", "active"]
      ["Alice", 30, true]
      a
      b
      c
      Alice
      admin
      name
      age
      active
      Alice
      30
      true
    OUT
  end

  it "sym methods" do
    result = zr(<<~'RUBY')
      # Symbol methods
      puts :hello.to_s        # hello
      puts :hello.length      # 5
      puts :hello.empty?      # false
      puts (:a == :a)         # true
      puts (:a == :b)         # false
      puts (:a != :b)         # true

      # String#to_sym → Symbol
      s = "dynamic".to_sym
      puts s                  # dynamic

      # to_sym on literal (compile-time interned)
      t = "hello".to_sym
      puts t                  # hello

      # Symbol#to_sym is identity
      puts :foo.to_sym        # foo

      # Symbol#<=> (lexical)
      puts (:apple <=> :banana)  # -1
      puts (:banana <=> :apple)  # 1
      puts (:apple <=> :apple)   # 0

      # Kernel#p with symbol
      p :hello                # :hello
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      5
      false
      true
      false
      true
      dynamic
      hello
      foo
      -1
      1
      0
      :hello
    OUT
  end

  it "sym poly" do
    result = zr(<<~'RUBY')
      # A mixed-type array; `puts` on a Symbol element prints its name.
      arr = [1, "two", :three, 4.0, true]
      arr.each { |v| puts v }
    RUBY

    _(result).must_answer <<~'OUT'
      1
      two
      three
      4.0
      true
    OUT
  end

  it "sym semantics" do
    result = zr(<<~'RUBY')
      # Ruby semantic requirements that Phase 2 satisfies

      # 0. Symbol is distinct from String
      puts :a == "a"            # false
      puts "a" == :a            # false
      puts :a != "a"            # true

      # 1. Same symbol is equal to itself
      puts :foo == :foo         # true

      # 2. Different symbols are not equal
      puts :foo == :bar         # false

      # 3. Symbol-keyed hash distinguishes sym keys (Ruby semantics)
      h = {a: 1, b: 2}
      puts h.has_key?(:a)       # true
      puts h.has_key?(:z)       # false
      puts h.has_key?("a")      # false - sym key hash, string arg

      # 3b. {a:1}[:a] finds it
      puts h[:a]                # 1

      # 4. to_sym idempotent on Symbol
      puts :foo.to_sym == :foo  # true

      # 5. String#to_sym + Symbol#to_s round trip
      puts "hello".to_sym.to_s  # hello

      # 6. Interned symbol identity ("foo" interns to same ID as :foo)
      puts "foo".to_sym == :foo # true
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
      true
      false
      true
      false
      false
      1
      true
      hello
      true
    OUT
  end

  it "symbol upcase downcase" do
    result = zr(<<~'RUBY')
      # Symbol#upcase and Symbol#downcase return symbols by upper/lower-casing
      # the symbol's name string and interning the result again, as
      # String#upcase / #downcase do for a String.

      # Symbol#upcase
      puts :hello.upcase
      puts :HELLO.upcase
      puts :MixedCase.upcase
      puts :a.upcase
      puts :_.upcase

      # Symbol#downcase
      puts :HELLO.downcase
      puts :hello.downcase
      puts :MixedCase.downcase
      puts :Z.downcase

      # Round trip — sym -> upper -> lower returns to original lower form
      puts :foo.upcase.downcase
      puts :BAR.downcase.upcase

      # Re-intern stability — equal pre/post-case symbols stay equal
      puts :Hello.upcase == :HELLO
      puts :Hello.downcase == :hello
      puts :a.upcase != :A.downcase
    RUBY

    _(result).must_answer <<~'OUT'
      HELLO
      HELLO
      MIXEDCASE
      A
      _
      hello
      hello
      mixedcase
      z
      foo
      BAR
      true
      true
      true
    OUT
  end

  it "__ENCODING__ names the source's encoding as its canonical name" do
    result = zr(<<~'RUBY')
      # SourceEncodingNode — the `__ENCODING__` keyword.
      #
      # Sources are UTF-8; __ENCODING__ is an Encoding value whose to_s
      # returns the canonical name.

      puts __ENCODING__.to_s
    RUBY

    _(result).must_answer "UTF-8\n"
  end

  it "custom enumerable wave10" do
    result = zr(<<~'RUBY')
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end
      p Nums.new(3, 1, 2).entries
      n = Nums.new(3, 1, 2)
      p(n.sum { |x| x * 2 })
      p Nums.new(1, 2, 3, 4).each_cons(2).to_a
      p Nums.new(1, 2, 3, 4, 5).each_slice(2).to_a
      p Nums.new(1, 2, 4, 5).chunk_while { |a, b| b - a == 1 }.to_a
      p Nums.new(3, 1, 2).lazy.map { |x| x * 2 }.first(2)
      p Nums.new(3, 1, 2).minmax_by { |x| x }
      Nums.new(1, 2, 3).cycle(2) { |x| p x }
      p Nums.new(1, 1, 2, 3, 3).chunk { |x| x }.to_a
      p Nums.new(1, 2, 4, 5).slice_when { |a, b| b - a > 1 }.to_a
      # blockless map / range no-block enumerator chains
      m = [1, 2, 3].map
      p m.size
      p m.class
      p m
      p([1, 2, 3].map.with_index { |x, i| [x, i] })
      p((1..5).each_with_index.to_a)
      p((1..3).cycle.first(7))
      p((1..3).map.with_index { |x, i| [x, i] })
      p((1..6).each_slice(2))
      r19 = (2..4)
      p r19.each_with_index.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 1, 2]
      12
      [[1, 2], [2, 3], [3, 4]]
      [[1, 2], [3, 4], [5]]
      [[1, 2], [4, 5]]
      [6, 2]
      [1, 3]
      1
      2
      3
      1
      2
      3
      [[1, [1, 1]], [2, [2]], [3, [3, 3]]]
      [[1, 2], [4, 5]]
      3
      Enumerator
      #<Enumerator: [1, 2, 3]:map>
      [[1, 0], [2, 1], [3, 2]]
      [[1, 0], [2, 1], [3, 2], [4, 3], [5, 4]]
      [1, 2, 3, 1, 2, 3, 1]
      [[1, 0], [2, 1], [3, 2]]
      #<Enumerator: 1..6:each_slice(2)>
      [[2, 0], [3, 1], [4, 2]]
    OUT
  end

  it "Random.urandom draws from a stream that advances between calls" do
    result = zr(<<~'RUBY')
      # Random.urandom draws from a persistent advancing stream (re-seeding per call
      # gave the same byte within a second, so a zero byte never appeared).
      p (0...50).map { Random.urandom(1).bytes[0] }.uniq.size > 1
      p Random.urandom(4).bytesize
    RUBY

    _(result).must_answer "true\n4\n"
  end

  it "Hash#map hands the block a key and a value, or the pair as one array" do
    result = zr(<<~'RUBY')
      def render(v)
        return v.to_s unless v.is_a?(Hash)
        "{" + v.map { |k, val| "#{k}=#{render(val)}" }.join(",") + "}"
      end
      p render({ "a" => 1, "b" => { "c" => 2, "d" => 3 } })
      p render({ 1 => 10, 2 => 20 })
      h = { "x" => 1, "y" => 2 }
      p h.map { |k, val| [k, val * 10] }
      p h.map { |pair| pair.inspect }
    RUBY

    _(result).must_answer <<~'OUT'
      "{a=1,b={c=2,d=3}}"
      "{1=10,2=20}"
      [["x", 10], ["y", 20]]
      ["[\"x\", 1]", "[\"y\", 2]"]
    OUT
  end

  it "each over an array of pairs splits each pair into two block parameters" do
    result = zr(<<~'RUBY')
      table = [[1000, "M"], [4, "IV"], [1, "I"]]
      out = ""
      table.each { |num, sym| out += sym }
      p out
    RUBY

    _(result).must_answer "\"MIVI\"\n"
  end

  it "a breadth-first search keeps its visited nodes in a Set" do
    result = zr(<<~'RUBY')
      # A BFS keeping a visited Set compiled: `node == goal` (node poly, from
      # queue.shift) no longer widens Set#=='s `other` param to Symbol via the
      # poly-comparison arg binding, so Set#subset?'s `other.include?` stays typed.
      require "set"

      GRAPH = {
        a: [:b, :c],
        b: [:a, :d, :e],
        c: [:a, :f],
        d: [:b],
        e: [:b, :f],
        f: [:c, :e],
      }

      def shortest_path(graph, start, goal)
        queue = [start]
        visited = Set[start]
        parent = {}
        until queue.empty?
          node = queue.shift
          break if node == goal
          graph[node].each do |nbr|
            next if visited.include?(nbr)
            visited.add(nbr)
            parent[nbr] = node
            queue << nbr
          end
        end

        path = [goal]
        path.unshift(parent[path.first]) while parent.key?(path.first)
        path
      end

      p shortest_path(GRAPH, :a, :f)
      p shortest_path(GRAPH, :d, :c)
      p shortest_path(GRAPH, :a, :a)
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, :c, :f]
      [:d, :b, :a, :c]
      [:a]
    OUT
  end

  it "drop, reject and select on an each_with_index enumerator answer with the pairs" do
    result = zr(<<~'RUBY')
      # Chaining #drop / #reject onto an each_with_index Enumerator: materialize the
      # pairs and apply the array operation.
      a = [1.0, 2.0, 3.0]
      p a.each_with_index.drop(1).map { |c, i| c * i }
      p a.each_with_index.drop(1)
      p a.each_with_index.reject { |c, i| i == 0 }
      p a.each_with_index.select { |c, i| i > 0 }
    RUBY

    _(result).must_answer <<~'OUT'
      [2.0, 6.0]
      [[2.0, 1], [3.0, 2]]
      [[2.0, 1], [3.0, 2]]
      [[2.0, 1], [3.0, 2]]
    OUT
  end

  it "a constant bound to an empty Hash takes writes and keeps them" do
    result = zr(<<~'RUBY')
      TBL = {}
      "abc".each_char.with_index { |ch, i| TBL[ch] = i }

      def parse(s, base)
        s.each_char.reduce(0) { |acc, ch| acc * base + TBL[ch] }
      end

      p parse("bca", 10)

      # a constant empty hash with direct writes
      T2 = {}
      T2["a"] = 1
      p T2["a"]

      # a constant empty hash never written still has a slot
      T3 = {}
      p T3.size
      p T3.empty?

      # symbol-keyed constant
      T4 = {}
      T4[:k] = "v"
      p T4[:k]
      p T4
    RUBY

    _(result).must_answer <<~'OUT'
      120
      1
      0
      true
      "v"
      {k: "v"}
    OUT
  end

  it "reduce keeps a Complex accumulator while folding an array of Complex" do
    result = zr(<<~'RUBY')
      # reduce with a Complex initial accumulator, folding over a poly array: the
      # block's `acc + z` (z a Complex read out of the poly array, hence poly) keeps
      # the accumulator typed Complex by coercing the poly operand.
      zs = [Complex(1, 2), Complex(3, -4)]
      total = zs.reduce(Complex(0, 0)) { |acc, z| acc + z }
      p total
      ws = [Complex(2, 0), Complex(0, 3), Complex(1, 1)]
      prod = ws.reduce(Complex(1, 0)) { |acc, z| acc * z }
      p prod
    RUBY

    _(result).must_answer "(4-2i)\n(-6+6i)\n"
  end

  it "Complex#real and #imaginary answer through a map over a mixed array" do
    result = zr(<<~'RUBY')
      p [Complex(1, 2), Complex(3, 4)].map { |z| z.real }
      p [Complex(1, 2), Complex(3.5, 4)].map { |z| z.imaginary }
      p [Complex(1.0, 2), 5].map { |z| z.real }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3]
      [2, 4]
      [1.0, 5]
    OUT
  end

  it "a Hash splatted with ** fills the method's keyword parameters" do
    result = zr(<<~'RUBY')
      def rect(width:, height:) = width * height
      configs = [{ width: 2, height: 3 }, { width: 5, height: 5 }]
      p configs.map { |c| rect(**c) }
    RUBY

    _(result).must_answer "[6, 25]\n"
  end

  it "sum and map over a range subscript a nested array twice by the same index" do
    result = zr(<<~'RUBY')
      # Iterating a Range twice with a nested-index block (a poly-valued grid read):
      # the sum-with-block and map-with-block forms both give the diagonal.
      grid = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
      diag_sum = (0...grid.length).sum { |i| grid[i][i] }
      diag = (0...grid.length).map { |i| grid[i][i] }
      p diag_sum
      p diag
    RUBY

    _(result).must_answer "15\n[1, 5, 9]\n"
  end

  it "bsearch answers over an array built at run time, not only over a literal" do
    result = zr(<<~'RUBY')
      def ins(arr, v) = arr.insert(0, v)
      s = []
      [5, 2, 8].each { |n| ins(s, n) }
      p s.bsearch { |x| x >= 4 }
      p [1, 2, 5, 8].bsearch { |x| x >= 4 }
      t = []
      t << 2
      t << 4
      t << 9
      p t.bsearch { |x| x >= 4 }
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      4
    OUT
  end

  it "Kernel#rand answers a non-negative Integer for a large bound" do
    result = zr(<<~'RUBY')
      [[1000000, :a], [500000, :b]].each do |odds, name|
        r = rand(odds)
        p r.class
        p r >= 0
        p(r == 0 || r > 0)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      true
      true
      Integer
      true
      true
    OUT
  end

  it "each_line and each_char with no block chain into an eager block method" do
    result = zr(<<~'RUBY')
      # each_char/each_line (blockless) followed by an eager block method desugars to
      # chars/lines, so the block param types as String -- a multiple assignment from
      # String#split inside the block resolves.
      p "a,1\nb,2\n".each_line.map { |l| k, v = l.strip.split(","); k }
      p "hello".each_char.map { |c| c.upcase }
      p "1,2\n3,4\n".each_line.map { |l| a, b = l.strip.split(","); a.to_i + b.to_i }
      p "abcde".each_char.select { |c| c > "b" }
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      ["H", "E", "L", "L", "O"]
      [3, 7]
      ["c", "d", "e"]
    OUT
  end

  it "reduce keeps a Symbol accumulator read back out of a nested Hash" do
    result = zr(<<~'RUBY')
      # reduce with a Symbol accumulator whose block value is read from a nested Hash
      # (of mixed value types): the block value becomes the next accumulator.
      T = { a: { "0" => :a, "1" => :b }, b: { "0" => :a, "1" => :b } }
      p "01".chars.reduce(:a) { |s, c| T[s][c] }
      p "10".chars.reduce(:a) { |s, c| T[s][c] }
    RUBY

    _(result).must_answer ":b\n:a\n"
  end

  it "find and detect answer nil when the block accepts nothing" do
    result = zr(<<~'RUBY')
      p [[1, 2], [3, 4]].map { |row| row.find { |n| n > 2 } }
      p [["a", "bb"], ["ccc"]].map { |row| row.find { |s| s.length > 1 } }
      p [[1, 2], [3, 4]].map { |row| row.detect { |n| n > 5 } }
    RUBY

    _(result).must_answer <<~'OUT'
      [nil, 3]
      ["bb", "ccc"]
      [nil, nil]
    OUT
  end

  it "map(&:reverse) reverses an array element and a string element alike" do
    result = zr(<<~'RUBY')
      p [[1, 2], [3, 4]].map(&:reverse)
      p ["ab", "cd"].map(&:reverse)
      p [[1, 2], "xy"].map(&:reverse)
    RUBY

    _(result).must_answer <<~'OUT'
      [[2, 1], [4, 3]]
      ["ba", "dc"]
      [[2, 1], "yx"]
    OUT
  end

  it "a two-parameter block splits each pair, whatever the pair holds" do
    result = zr(<<~'RUBY')
      pairs = [["ab", "cd"]]
      pairs.each { |a, b| p a.chars; p b.chars }
      p [["xy", 1]].map { |s, n| s.chars }
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      ["c", "d"]
      [["x", "y"]]
    OUT
  end

  it "each_cons(2) hands its window to a two-parameter block" do
    result = zr(<<~'RUBY')
      # each_cons(2).map { |a, b| ... } over an Integer array: the window's
      # elements bind to the two block params, one element each.
      codes = (0...8).map { |n| n * 2 }
      d = codes.each_cons(2).map { |a, b| a + b }
      w = codes.last
      p d
      p w
      p [1.0, 2.0, 3.0].each_cons(2).map { |a, b| a * b }
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 6, 10, 14, 18, 22, 26]
      14
      [2.0, 6.0]
    OUT
  end

  it "transpose after map(&:reverse) turns rows into reversed columns" do
    result = zr(<<~'RUBY')
      p [[1, 2, 3], [4, 5, 6]].map(&:reverse).transpose
      p [[1, 2], [3, 4]].transpose
      p [["a", "b"], ["c", "d"]].transpose
      p [[1, 2, 3], [4, 5, 6], [7, 8, 9]].map(&:reverse).transpose
    RUBY

    _(result).must_answer <<~'OUT'
      [[3, 6], [2, 5], [1, 4]]
      [[1, 3], [2, 4]]
      [["a", "c"], ["b", "d"]]
      [[3, 6, 9], [2, 5, 8], [1, 4, 7]]
    OUT
  end

  it "a multiple assignment from a method's array return feeds a slice" do
    result = zr(<<~'RUBY')
      def ms(nums)
        [nums[0], 0, nums.length]
      end
      best, lo, hi = ms([5, 6, 7, 8])
      d = [0, 10, 20, 30, 40]
      p d[lo..hi]
      sums = [[1, 2], [3, 4]].map { |a| ms(a).first }
      p sums
      strs = ["a", "b", "c", "d"]
      p strs[lo..hi]
      p d[lo, 2]
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 10, 20, 30, 40]
      [1, 3]
      ["a", "b", "c", "d"]
      [0, 10]
    OUT
  end

  it "each_with_object and flat_map round-trip a query string" do
    result = zr(<<~'RUBY')
      def parse(qs)
        qs.split("&").each_with_object({}) do |pair, params|
          key, value = pair.split("=", 2)
          value = "" if value.nil?
          (params[key] ||= []) << value
        end
      end

      def build(params)
        params.flat_map { |key, values| values.map { |v| "#{key}=#{v}" } }.join("&")
      end

      puts build(parse("a=1&b=2"))
      p build({ "q" => ["ruby"] })
    RUBY

    _(result).must_answer <<~'OUT'
      a=1&b=2
      "q=ruby"
    OUT
  end

  it "map(&:sort) sorts each row of a nested array" do
    result = zr(<<~'RUBY')
      p [[3, 1, 2], [6, 4, 5]].map(&:sort)
      p({ a: [3, 1], b: [2, 4] }.map { |k, v| v.sort })
      p [[9, 7, 8]].map { |row| row.sort }
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2, 3], [4, 5, 6]]
      [[1, 3], [2, 4]]
      [[7, 8, 9]]
    OUT
  end

  it "a String destructured out of a pair keeps its String methods" do
    result = zr(<<~'RUBY')
      # The chars/split result of a String destructured from a pair, captured (map /
      # returned): the auto-splat gives the String param a real String, and its
      # String methods work.
      r = [["ab", "cd"]].map { |a, b| a.chars }
      p r
      p [["a,b", "c"]].map { |a, b| a.split(",") }
      p [["ab", "cd"]].map { |a, b| a.chars.length }
      p [[:x, :y]].map { |a, b| a.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      [["a", "b"]]
      [["a", "b"]]
      [2]
      ["x"]
    OUT
  end

  it "reject, select, filter and each_index work on an array that arrived as a block parameter" do
    result = zr(<<~'RUBY')
      # reject / select / filter / each_index on an Array that is a block param of an
      # outer map (a poly value only known to be an array at runtime).
      p([[1, 2, 0], [3, 0, 4]].map { |row| row.reject(&:zero?) })
      p([[1, 2, 0]].map { |r| r.select { |x| x > 1 } })
      p([[1, 2, 0]].map { |r| r.filter { |x| x > 0 } })
      p([[[1, 2], [3, 0]]].map { |r| r.reject { |a, b| b == 0 } })
      p([[10, 20, 30]].map { |row| s = 0; row.each_index { |i| s += i }; s })
      # an unused each_index param must not bind an undeclared local
      p([[10, 20, 30]].map { |row| c = 0; row.each_index { |i| c += 1 }; c })
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [3, 4]]
      [[2]]
      [[1, 2]]
      [[[1, 2]]]
      [3]
      [3]
    OUT
  end

  it "a lazy prime sieve over an endless range answers its first five" do
    result = zr(<<~'RUBY')
      primes = (2..Float::INFINITY).lazy.select { |n| (2..Math.sqrt(n)).none? { |d| n % d == 0 } }
      p primes.first(5)
    RUBY

    _(result).must_answer "[2, 3, 5, 7, 11]\n"
  end

  it "reduce takes its operator as a Symbol read from a variable" do
    result = zr(<<~'RUBY')
      # Array#reduce with a non-constant Symbol operator (a |sym| block param):
      # fold through a runtime operator dispatch, yielding a boxed poly.
      p [:+, :-, :*].map { |sym| [10, 3].reduce(sym) }
      p [:+, :*].map { |s| [2, 3, 4].reduce(10, s) }
      ops = [:&, :|]
      p ops.map { |o| [6, 3].reduce(o) }
      p [:+, :-].map { |s| [1.0, 2.0].reduce(s) }
      # literal and static-local forms are unchanged
      p [2, 3, 4].reduce(:+)
      p [2, 3, 4].reduce(10, :*)
    RUBY

    _(result).must_answer <<~'OUT'
      [13, 7, 30]
      [19, 240]
      [2, 7]
      [3.0, -1.0]
      9
      240
    OUT
  end

  it "reduce folds booleans with &, | and ^" do
    result = zr(<<~'RUBY')
      bits = [true, false, true]
      p bits.reduce(:&)
      p bits.reduce(:|)
      p bits.reduce(:^)
      p [1,3,5,7].reduce(:&)
      p [1,2,4].reduce(:|)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      1
      7
    OUT
  end

  it "lazy uniq, chunk_while and with_index answer without forcing the source" do
    result = zr(<<~'RUBY')
      p([1, 1, 2, 3, 3].lazy.uniq.to_a)
      p([1, 2, 4, 5, 7].lazy.chunk_while { |a, b| b - a == 1 }.to_a)
      p([10, 20, 30].lazy.with_index.to_a)
      p([1, 1, 2].each.uniq)
      p([1, 2, 3].lazy.map { |x| x * 2 }.to_a)
      p((1..Float::INFINITY).lazy.select { |x| x % 5 == 0 }.first(2))
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [[1, 2], [4, 5], [7]]
      [[10, 0], [20, 1], [30, 2]]
      [1, 2]
      [2, 4, 6]
      [5, 10]
    OUT
  end

  it "first on an enumerator takes one element, or the first n" do
    result = zr(<<~'RUBY')
      p([1, 2, 3].each.first)
      p([1, 2, 3].each.first(2))
      p([1, 2, 3].each_with_index.first)
      p([1, 2, 3].lazy.map { |x| x * 2 }.first)
      p([].lazy.map { |x| x }.first)
      p((1..Float::INFINITY).lazy.select { |x| x % 7 == 0 }.first)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [1, 2]
      [1, 0]
      2
      nil
      7
    OUT
  end

  it "compact and zip work on an enumerator" do
    result = zr(<<~'RUBY')
      p([1, nil, 2, nil].each.compact)
      p([1, 2, 3].each.zip([4, 5, 6]))
    RUBY

    _(result).must_answer "[1, 2]\n[[1, 4], [2, 5], [3, 6]]\n"
  end

  it "a lazy chain over an empty array answers empty" do
    result = zr(<<~'RUBY')
      p([].lazy.map { |x| x * 2 }.to_a)
      p([].lazy.to_a)
      p([].lazy.first(2))
      p([].lazy.select { |x| x > 0 }.first(2))
      p([1, 2, 3].lazy.to_a)
      p([1, 2, 3].lazy.map { |x| x * 2 }.to_a)
      p([1, 2, 3].lazy.select { |x| x > 1 }.first(2))
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      []
      []
      [1, 2, 3]
      [2, 4, 6]
      [2, 3]
    OUT
  end

  it "to_s on a nested array is its inspect" do
    result = zr(<<~'RUBY')
      [[:x, :y]].each { |e| p e.to_s }
      x = [[:x, :y]]
      p x[0].to_s
      p [[:a], [:b, :c]].map(&:to_s)
      p [[1, 2], [:s]].map(&:to_s)
      p [[:x, :y]].to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "[:x, :y]"
      "[:x, :y]"
      ["[:a]", "[:b, :c]"]
      ["[1, 2]", "[:s]"]
      "[[:x, :y]]"
    OUT
  end

  it "a lazy chain bound to a local stays lazy" do
    result = zr(<<~'RUBY')
      b = [10, 20, 30].lazy.map { |x| x + 1 }
      p(b.first(2))
      c = [1, 2, 3].lazy
      p(c.map { |x| x * 2 }.to_a)
      d = (1..Float::INFINITY).lazy.select { |x| x % 3 == 0 }
      p(d.first(3))
      e = [1, 2, 3, 4].lazy
      p(e.select { |x| x.even? }.to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      [11, 21]
      [2, 4, 6]
      [3, 6, 9]
      [2, 4]
    OUT
  end

  it "merge with a conflict block folds a list of hashes down to one" do
    result = zr(<<~'RUBY')
      p [{ a: 1 }, { b: 2 }, { a: 3 }].reduce({}) { |acc, hh| acc.merge(hh) { |_k, o, n| o + n } }
      p [{ a: 1 }, { a: 2 }].reduce({}) { |acc, hh| acc.merge(hh) { |k, o, n| "#{k}:#{o + n}" } }
      p [{ a: 1 }, { b: 2 }, { c: 3 }].reduce({}) { |acc, hh| acc.merge(hh) { |k, o, n| o + n } }
      p [{ a: 1 }].reduce({}) { |acc, hh| acc.merge(hh) { |k, o, n| o + n } }
      p [{ "a" => 1 }, { "b" => 2 }, { "a" => 3 }].reduce({}) { |acc, hh| acc.merge(hh) { |k, o, n| o + n } }
      p({ a: 1 }.merge({ a: 3 }) { |k, o, n| o + n })
      # empty-array reduce({}) returns the seed in the result's variant, not garbage
      p [].reduce({}) { |acc, hh| acc.merge(hh) { |k, o, n| o + n } }
      p [].reduce({}) { |a, b| a }
      p [].reduce([]) { |a, b| a }
      # array / hash valued conflict block (the value expr allocates)
      p [{ a: 1 }, { a: "x" }].reduce({}) { |acc, hh| acc.merge(hh) { |k, o, n| [o, n] } }
      p [{ a: 1 }, { a: 2 }].reduce({}) { |acc, hh| acc.merge(hh) { |k, o, n| { x: o, y: n } } }
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 4, b: 2}
      {a: "a:3"}
      {a: 1, b: 2, c: 3}
      {a: 1}
      {"a" => 4, "b" => 2}
      {a: 4}
      {}
      {}
      []
      {a: [1, "x"]}
      {a: {x: 1, y: 2}}
    OUT
  end

  it "a String range iterates through succ" do
    result = zr(<<~'RUBY')
      r = []
      ("a".."c").each { |x| r << x }
      p r
      p ("a".."e").select { |s| s > "b" }
      p ("a".."c").map { |s| s.upcase }
      p ("a".."d").find { |s| s == "c" }
      p ("aa".."ac").to_a
      # int and float ranges unchanged
      sum = 0
      (1..5).each { |n| sum += n }
      p sum
      p (1..3).map { |n| n * 2 }
      fr = []
      (1.0..3.0).step(1.0) { |x| fr << x }
      p fr
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      ["c", "d", "e"]
      ["A", "B", "C"]
      "c"
      ["aa", "ab", "ac"]
      15
      [2, 4, 6]
      [1.0, 2.0, 3.0]
    OUT
  end

  it "reduce takes gcd and lcm as the folding operator" do
    result = zr(<<~'RUBY')
      p [12, 18, 24].reduce(:gcd)
      p [2, 3, 4].reduce(:lcm)
      p [1, 2, 3].reduce(:+)
      p [1, 2, 3].reduce(10, :+)
    RUBY

    _(result).must_answer <<~'OUT'
      6
      12
      6
      16
    OUT
  end

  it "lazy compact and zip answer what their eager forms answer" do
    result = zr(<<~'RUBY')
      p([1, nil, 2].lazy.compact.to_a)
      p([1, 2, 3].lazy.zip([4, 5, 6]).to_a)
      p([1, 2, 3].lazy.map { |x| x * 2 }.to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [[1, 4], [2, 5], [3, 6]]
      [2, 4, 6]
    OUT
  end

  it "a lazy select or reject over an empty array answers empty" do
    result = zr(<<~'RUBY')
      p([].lazy.select { |x| true }.first(2))
      p([].lazy.reject { |x| false }.to_a)
      p([1, 2].lazy.select { |x| true }.first(2))
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      [1, 2]
    OUT
  end

  it "next, return and break after an unless guard leave the block where they stand" do
    result = zr(<<~'RUBY')
      def crash(*values)
        result = []
        values.each do
          next unless _1.is_a?(String)
          result << _1.match?(/x/)
        end
        result
      end
      p crash("axb", 5, "y", "xx")

      # return unless form, explicit param
      def first_string(*values)
        values.each do |v|
          next unless v.is_a?(String)
          return v.upcase
        end
        nil
      end
      p first_string(1, 2, "hello", "world")

      # break unless
      def find_int(arr)
        found = nil
        arr.each do |e|
          break unless e.is_a?(Integer)
          found = e * 2
        end
        found
      end
      p find_int([10, 20])
      p find_int(["x", 5])
    RUBY

    _(result).must_answer <<~'OUT'
      [true, false, true]
      "HELLO"
      40
      nil
    OUT
  end

  it "a joined string survives a collection between the store and the read" do
    result = zr(<<~'RUBY')
      # Two GC bugs behind a StringIO/wrap program:
      #  1. a join with no separator must give a String that the GC can mark.
      #  2. the String that Array#join returns must stay valid after a GC, also
      #     when the program stores it and reads it later.
      def build(chars)
        buf = []
        chars.each { |c| buf << c }
        buf.join            # no separator; result stored below and re-joined later
      end

      lines = []
      50.times do |i|
        chars = []
        10.times { |k| chars << ((97 + (i + k) % 26).chr) }
        lines << build(chars)     # force many allocations between store and use
        ("a".."z").to_a          # churn the GC (String#succ)
      end
      p lines.length
      p lines.first.length
      p lines.join("|").length
      puts "ok"
    RUBY

    _(result).must_answer <<~'OUT'
      50
      10
      549
      ok
    OUT
  end

  it "each_index and each_with_index answer through an outer map" do
    result = zr(<<~'RUBY')
      p [[1, 2]].map { |row| row.each_index.map { |c| c } }
      # each_with_index.sum inside an outer map:
      p [[10, 20, 30]].map { |row| row.each_with_index.sum { |v, i| v * i } }
      # => [80]

      # each_index.map on a local array:
      a = [1, 2]
      p a.each_index.map { |c| c }
      # => [0, 1]
    RUBY

    _(result).must_answer <<~'OUT'
      [[0, 1]]
      [80]
      [0, 1]
    OUT
  end

  it "a lazy each_cons over a range answers its first windows" do
    result = zr("p (2..10).lazy.each_cons(2).first(3)\n")

    _(result).must_answer "[[2, 3], [3, 4], [4, 5]]\n"
  end

  it "reduce with an Integer seed over floats answers a Float" do
    result = zr(<<~'RUBY')
      p [1.0, 2.0].reduce(0, :+)
      p [1.0, 2.0, 3.0].reduce(1, :*)
      p [1, 2].reduce(0, :+)
      p [1.5, 2.5].reduce(0, :+)
      p (1..3).reduce(0, :+)
      p [1.0, 2.0].reduce(:+)
    RUBY

    _(result).must_answer <<~'OUT'
      3.0
      6.0
      3
      4.0
      6
      3.0
    OUT
  end

  it "map over pairs builds a Rational out of each" do
    result = zr(<<~'RUBY')
      fracs = [[6, 8], [10, 15]]
      p fracs.map { |n, d| g = n.gcd(d); Rational(n / g, d / g) }
    RUBY

    _(result).must_answer "[(3/4), (2/3)]\n"
  end

  it "inject with a Rational seed folds parsed fractions" do
    result = zr(<<~'RUBY')
      def to_frac(str)
        num, den = str.split("/").map(&:to_i)
        Rational(num, den || 1)
      end
      exprs = [["1/2", "+", "1/3"]]
      exprs.each { |a, op, b| p to_frac(a) }
      total = exprs.map { |a, _, _| to_frac(a) }.inject(Rational(0), :+)
      p total
    RUBY

    _(result).must_answer "(1/2)\n(1/2)\n"
  end

  it "each(&:clear) empties every element, array or hash" do
    result = zr(<<~'RUBY')
      items = [[1], {a: 1}]
      items.each(&:clear)
      p items

      mixed = [[1, 2], {a: 1}, [3]]
      mixed.each(&:clear)
      p mixed

      h = {x: 1}
      p [h].map(&:clear)
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      [[], {}]
      [[], {}, []]
      [{}]
      {}
    OUT
  end

  it "reduce with a zero seed keeps the element's type, Rational or Float" do
    result = zr(<<~'RUBY')
      p([Rational(1, 2), Rational(1, 4)].reduce(0, :+))
      p([2, -3].inject(0) { |a, c| a + Rational(1, 2) })
      p([1, 2, 3].reduce(0, :+))
      p([1.0, 2.0].reduce(0, :+))
      p([Rational(1, 2), Rational(1, 4)].reduce(Rational(0, 1), :+))
      p([1, 2, 3].inject(0) { |a, x| a + x })
    RUBY

    _(result).must_answer <<~'OUT'
      (3/4)
      (1/1)
      6
      3.0
      (3/4)
      6
    OUT
  end

  it "ljust, rjust and center work on a string read out of a container" do
    result = zr(<<~'RUBY')
      s = [["a", "b"]][0][0]
      p(s.ljust(3))
      p(s.rjust(3))
      p(s.center(5))
      p(s.ljust(5, "*"))
      p(s.rjust(5, "ab"))
      p(s.center(7, "-"))
      p(s.upcase)
      h = {k: ["x", "y"]}
      t = h[:k][0]
      p(t.ljust(4))
      pair = [["hi", 1]].map { |k, _v| k.ljust(4) }
      p(pair)
    RUBY

    _(result).must_answer <<~'OUT'
      "a  "
      "  a"
      "  a  "
      "a****"
      "ababa"
      "---a---"
      "A"
      "x   "
      ["hi  "]
    OUT
  end

  it "chunk groups neighbouring elements by the block's value" do
    result = zr(<<~'RUBY')
      p (1..8).chunk { |x| x.even? }.to_a
      p (1..5).chunk { |x| x % 3 }.to_a
      p (1..6).chunk { |x| x < 4 }.map { |k, xs| [k, xs.sum] }
    RUBY

    _(result).must_answer <<~'OUT'
      [[false, [1]], [true, [2]], [false, [3]], [true, [4]], [false, [5]], [true, [6]], [false, [7]], [true, [8]]]
      [[1, [1]], [2, [2]], [0, [3]], [1, [4]], [2, [5]]]
      [[true, 6], [false, 15]]
    OUT
  end

  it "a string stored in a container is the same object, so a later append shows through" do
    result = zr(<<~'RUBY')
      # Shared-mutable strings: a container-stored string is the same object, so
      # later in-place mutation is visible through the container and equal? is
      # object identity.
      s1 = "hi"
      arr = [s1]
      s1 << "!"
      p arr[0]
      p arr[0].equal?(s1)
      h = { k: s1 }
      s1 << "?"
      p h[:k]

      # consumers of the container-read handle
      a = "abc"
      box = [a, "z", 1]
      a << "def"
      puts "#{box[0]}!"
      p box[0].upcase
      p box[0] + "X"
      p box.include?("abcdef")
      p box.join("-")
      box.each { |x| puts x }
      p box[0].length
      p box[0] == "abcdef"
      p box[0] == a
      p box[0].class

      # in-place append THROUGH the container read
      box[0] << "g"
      p a

      # hash value + string-keyed hash
      v = "x"
      hs = { "k" => v }
      v << "y"
      hs.each { |k, w| puts "#{k}=#{w}" }

      # push-store shape + sort/mul/cmp via the handle
      seed = "ab"
      acc = []
      acc << seed
      seed << "c"
      p acc[0]
      p ["b", seed, "a"].sort
      p seed * 2
      p seed <=> "abd"
    RUBY

    _(result).must_answer <<~'OUT'
      "hi!"
      true
      "hi!?"
      abcdef!
      "ABCDEF"
      "abcdefX"
      true
      "abcdef-z-1"
      abcdef
      z
      1
      6
      true
      true
      String
      "abcdefg"
      k=xy
      "abc"
      ["a", "abc", "b"]
      "abcabc"
      -1
    OUT
  end

  it "bytesplice and append_as_bytes reach the string through every binding that holds it" do
    result = zr(<<~'RUBY')
      # The last three corner cases (P6): bytesplice/append_as_bytes share,
      # poly-container iteration mutates string elements via runtime dispatch,
      # and guard-narrowed poly receivers keep the shared handle.
      s = +"hello"
      t = s
      s.bytesplice(0, 1, "J")
      p t
      u = +"ab"
      v = u
      u.append_as_bytes("c", 100)
      p v
      box = [+"xy"]
      box[0].bytesplice(0, 1, "Z")
      p box
      arr = [+"s1", +"s2", 3]
      arr.each { |x| x << "!" if x.is_a?(String) }
      p arr
    RUBY

    _(result).must_answer <<~'OUT'
      "Jello"
      "abcd"
      ["Zy"]
      ["s1!", "s2!", 3]
    OUT
  end

  it "a block parameter holds the element itself, so an in-place mutator reaches the container" do
    result = zr(<<~'RUBY')
      # Iteration-variable mutation (P6): the block binding holds the element
      # handle, so in-place mutators reach the container's elements.
      arr = [+"a", +"b"]
      arr.each { |x| x << "!" }
      p arr
      s = +"s0"
      lst = [s, +"t0"]
      lst.each { |x| x.upcase! }
      p lst
      p s
      ws = [+"x", +"y"]
      ws.each_with_index { |w, i| w << i.to_s }
      p ws
    RUBY

    _(result).must_answer <<~'OUT'
      ["a!", "b!"]
      ["S0", "T0"]
      "S0"
      ["x0", "y1"]
    OUT
  end

  it "slice_when and chunk_while cut a range where the block says" do
    result = zr(<<~'RUBY')
      p((1..10).slice_when { |i, j| j.even? }.to_a)
      p((1..8).chunk_while { |i, j| j == i + 1 }.map { |r| r.sum })
      p((1..8).chunk_while { |i, j| j == i + 1 }.to_a)
      p((1..4).each.with_index(5).to_a)
      p((1..4).each.with_index.to_a)
      p((1..4).map.with_index { |v, i| v * i })
    RUBY

    _(result).must_answer <<~'OUT'
      [[1], [2, 3], [4, 5], [6, 7], [8, 9], [10]]
      [36]
      [[1, 2, 3, 4, 5, 6, 7, 8]]
      [[1, 5], [2, 6], [3, 7], [4, 8]]
      [[1, 0], [2, 1], [3, 2], [4, 3]]
      [0, 2, 6, 12]
    OUT
  end

  it "rounding a small negative float answers positive zero" do
    result = zr(<<~'RUBY')
      p((-0.0001).round(2))
      p((-0.0).round(3))
      p((0.0).round(3))
      p((1.567).round(2))
      p((-1.567).round(2))
      x = -0.0001
      p(x.round(2))
      a = [-0.0001, 2.5]
      p(a.map { |v| v }.first.round(2))
    RUBY

    _(result).must_answer <<~'OUT'
      0.0
      -0.0
      0.0
      1.57
      -1.57
      0.0
      0.0
    OUT
  end

  it "zip, map and inject fold a float array down to a Float" do
    result = zr(<<~'RUBY')
      a = [3.0, 4.0]
      p a.zip(a).map { |x, y| x * y }.inject(0, :+)
      p [9.0, 16.0].inject(0, :+)
      p a.zip(a).map { |x, y| x * y }.inject(0.0, :+)
      p [1, 2, 3].inject(0, :+)
      p [1.5, 2.5].inject(0, :+)
    RUBY

    _(result).must_answer <<~'OUT'
      25.0
      25.0
      25.0
      6
      4.0
    OUT
  end

  it "the each_with_index terminals work on a parameter defaulted to an empty array" do
    result = zr(<<~'RUBY')
      # each_with_index terminals over a union-typed (defaulted `= []`) receiver.
      def safe?(placement = [])
        placement.each_with_index.all? { |c, r| c > r }
      end
      p safe?([1, 2, 3])
      p safe?([5, 0, 9])

      def idx_map(a = [])
        a.each_with_index.map { |c, r| c + r }
      end
      p idx_map([1, 2, 3])

      def big_count(a = [])
        a.each_with_index.count { |c, r| c > r }
      end
      p big_count([5, 0, 9])
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      [1, 3, 5]
      2
    OUT
  end

  it "a global array keeps what a method pushed onto it" do
    result = zr(<<~'RUBY')
      $clients = []
      def add(x) = $clients << x
      def show
        $clients.each { |c| p c }
      end
      add("a")
      add("b")
      show
      p $clients.size
      p $clients
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      "b"
      2
      ["a", "b"]
    OUT
  end

  it "Lazy#each_cons yields its windows on demand, so an endless source is workable" do
    result = zr(<<~'RUBY')
      # `Enumerator::Lazy#each_cons` is itself lazy: it yields windows on demand
      # rather than materializing the source, so an infinite range is workable and
      # `first(n)` stops the source.
      r = ((1..Float::INFINITY).lazy.select { |n| n > 2 }.each_cons(2).first(3) rescue $!.class)
      p r
      p((1..10).lazy.each_cons(3).first(2))
      p((1..Float::INFINITY).lazy.select { |n| n.even? }.each_cons(2).first(2))
      p((1..8).lazy.select { |n| n > 3 }.each_cons(2).to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      [[3, 4], [4, 5], [5, 6]]
      [[1, 2, 3], [2, 3, 4]]
      [[2, 4], [4, 6]]
      [[4, 5], [5, 6], [6, 7], [7, 8]]
    OUT
  end

  it "Lazy#each_cons stays lazy through map and through a second lazy" do
    result = zr(<<~'RUBY')
      # The same laziness, through a longer chain
      # (`each_cons(2).map { }.first(3)` and a re-`lazy`-ed select).
      r = (1..Float::INFINITY).lazy.each_cons(2).map { |a, b| a + b }.first(3)
      p r
      lz = (1..Float::INFINITY).lazy.each_cons(2)
      p lz.first(3)
      p((1..Float::INFINITY).lazy.each_cons(2).lazy.select { |a, b| b - a == 1 }.first(2))
      p((1..8).lazy.select { |n| n.odd? }.each_cons(2).map { |a, b| a * b }.to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 5, 7]
      [[1, 2], [2, 3], [3, 4]]
      [[1, 2], [2, 3]]
      [3, 15, 35]
    OUT
  end

  it "Comparable sorts a mixed array of subclasses through the one <=> they share" do
    result = zr(<<~'RUBY')
      class Shape
        include Comparable
        def area; 0; end
        def <=>(other); area <=> other.area; end
      end
      class Rectangle < Shape
        def initialize(a); @a = a; end
        def area; @a; end
      end
      class Circle < Shape
        def initialize(a); @a = a; end
        def area; @a; end
      end

      shapes = [Rectangle.new(3), Circle.new(1), Rectangle.new(2)]
      p shapes.sort.map(&:area)
      p shapes.min.area
      p shapes.max.area
      p(Rectangle.new(4) > Rectangle.new(2))
      p(Rectangle.new(4) < Circle.new(9))
      p(Circle.new(1).clamp(Rectangle.new(2), Rectangle.new(5)).area)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      1
      3
      true
      true
      2
    OUT
  end

  it "a lazy chain bound to a local is still lazy when each_cons reads it back" do
    result = zr(<<~'RUBY')
      # The same laziness, with the lazy chain bound
      # to a local first -- the round trip through a variable keeps the Lazy.
      s = (1..Float::INFINITY).lazy.select { |x| x > 3 }
      p s.each_cons(2).first(2)
    RUBY

    _(result).must_answer "[[4, 5], [5, 6]]\n"
  end

  it "an endless prime sieve stays lazy through a local and a second lazy" do
    result = zr(<<~'RUBY')
      # The local round trip again, re-`lazy`-ed afterwards.
      # The source is an infinite prime sieve with an inner scan, so any lost
      # laziness here is unbounded work.
      s = (2..Float::INFINITY).lazy.select { |n| (2...n).none? { |d| n % d == 0 } }
      p s.each_cons(2).lazy.first(2)
      s2 = (2..30).lazy.select { |n| (2...n).none? { |d| n % d == 0 } }
      p s2.each_cons(2).lazy.first(2)
    RUBY

    _(result).must_answer "[[2, 3], [3, 5]]\n[[2, 3], [3, 5]]\n"
  end

  it "struct enumerable wave8" do
    result = zr(<<~'RUBY')
      # Struct: Enumerable via synthesized #each/#each_pair, size/length,
      # deconstruct_keys, [] with string keys, multi-key dig, member []=,
      # ctor arity ArgumentError, class-level members, class-in-variable new.
      Pt141 = Struct.new(:x, :y)
      p(Pt141.new(3, 4).map { |v| v * 2 })
      p(Pt141.new(3, 4).each { |v| p v })
      p(Pt141.new(3, 4).select { |v| v > 3 })
      p(Pt141.new(3, 4).sum)
      p(Pt141.new(3, 4).min)
      p(Pt141.new(3, 4).include?(4))
      Pt142 = Struct.new(:x, :y)
      p(Pt142.new(10, 20)["x"])
      p(Pt142.new(10, 20)[:y])
      p(Pt142.new(10, 20)[0])
      In142 = Struct.new(:x)
      Ou142 = Struct.new(:pt)
      n = Ou142.new(In142.new(1))
      p(n.dig(:pt, :x))
      Pt145 = Struct.new(:x, :y)
      pt = Pt145.new(1, 2)
      pt[0] = 99
      pt[:y] = 88
      p pt
      Pt143 = Struct.new(:x, :y)
      r = (begin; Pt143.new(1, 2, 3); "no error"; rescue ArgumentError; "argerror"; end); p r
      Kk144 = Struct.new(:a, :b)
      p(Kk144.members)
      k = Kk144
      inst = k.new(1, 2)
      p inst.a
      Pk = Struct.new(:a, :b)
      Pk.new(1, 2).each_pair { |k, v| p [k, v] }
      p Pk.new(1, 2).size
      p Pk.new(1, 2).length
      p Pk.new(1, 2).deconstruct_keys([:a])
      p Pk.new(1, 2).deconstruct_keys(nil)
    RUBY

    _(result).must_answer <<~'OUT'
      [6, 8]
      3
      4
      #<struct Pt141 x=3, y=4>
      [4]
      7
      3
      true
      10
      20
      10
      1
      #<struct Pt145 x=99, y=88>
      "argerror"
      [:a, :b]
      1
      [:a, 1]
      [:b, 2]
      2
      2
      {a: 1}
      {a: 1, b: 2}
    OUT
  end
end
