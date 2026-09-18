# frozen_string_literal: true

require "spec_helper"

describe "Hash programs" do
  it "braced hash in the open mode slot is a mode" do
    result = ze0(<<~'RUBY')
      # A Hash written with BRACES is a positional argument; only keywords are
      # options.
      #
      # `IO.new(fd, {external_encoding: "EUC-JP"})` hands the MODE slot a Hash, and
      # CRuby answers `TypeError: no implicit conversion of Hash into String` --
      # `rb_scan_args_kw` is told to use the caller's own semantics, so the mark the
      # caller left on the Hash is what separates the two calls. `File.open` reads its
      # mode the same way.
      #
      # Zeo peeled ANY trailing Hash off a `**kwrest` row, which could not tell them
      # apart. The strict peel (`**opts!`) takes only a Hash the caller marked,
      # leaving a braced one where the caller put it -- in the mode slot, where
      # converting it to a String is the whole of CRuby's answer.
      require "tmpdir"
      require "fileutils"

      DIR = Dir.mktmpdir("zeo_braced_mode")
      SRC = File.join(DIR, "src.txt")
      File.binwrite(SRC, "hello\n")

      def row(name)
        puts "#{name}\t#{yield.inspect}"
      rescue StandardError => e
        puts "#{name}\t#{e.class}: #{e.message}"
      end

      def encs(io)
        [io.external_encoding&.name, io.internal_encoding&.name]
      end

      OPTS = { external_encoding: "EUC-JP" }.freeze

      # --- braced: a positional, so it is a mode ----------------------------------
      row("IO.new braced")        { IO.new(IO.sysopen(SRC), { external_encoding: "EUC-JP" }) }
      row("IO.new braced var")    { IO.new(IO.sysopen(SRC), OPTS) }
      row("File.open braced")     { File.open(SRC, { external_encoding: "EUC-JP" }) }
      row("File.open braced mode"){ File.open(SRC, { mode: "r" }) }

      # --- keywords: the options ---------------------------------------------------
      row("IO.new keywords") do
        io = IO.new(IO.sysopen(SRC), external_encoding: "EUC-JP")
        r = encs(io)
        io.close
        r
      end
      row("IO.new double-splat") do
        io = IO.new(IO.sysopen(SRC), **OPTS)
        r = encs(io)
        io.close
        r
      end
      row("File.open keywords")   { File.open(SRC, external_encoding: "EUC-JP") { |f| encs(f) } }
      row("File.open double-splat") { File.open(SRC, **OPTS) { |f| encs(f) } }
      # A hashrocket pair with no braces is still keywords, which is the spelling
      # irb's `IO.open(fd, :external_encoding => enc)` uses.
      row("File.open hashrocket") { File.open(SRC, :external_encoding => "EUC-JP") { |f| encs(f) } }
      # ...and a mode BESIDE the keywords keeps its own slot.
      row("mode then keywords")   { File.open(SRC, "r", external_encoding: "EUC-JP") { |f| encs(f) } }

      FileUtils.remove_entry(DIR)
      puts "ran to the end"
    RUBY

    _(result).must_answer <<~'OUT'
      IO.new braced	TypeError: no implicit conversion of Hash into String
      IO.new braced var	TypeError: no implicit conversion of Hash into String
      File.open braced	TypeError: no implicit conversion of Hash into String
      File.open braced mode	TypeError: no implicit conversion of Hash into String
      IO.new keywords	["EUC-JP", nil]
      IO.new double-splat	["EUC-JP", nil]
      File.open keywords	["EUC-JP", nil]
      File.open double-splat	["EUC-JP", nil]
      File.open hashrocket	["EUC-JP", nil]
      mode then keywords	["EUC-JP", nil]
      ran to the end
    OUT
  end

  it "class frozen false hash delete block and default record separator" do
    result = ze0(<<~'RUBY')
      # A user class (and a core class) reports frozen? == false. Hash#delete
      # calls its block when the key is absent. $/ defaults to "\n".

      class C001; end
      p C001.frozen?
      p Integer.frozen?
      d = { a: 1, b: 2 }
      p d.delete(:b)
      p d.delete(:z) { |k| "gone #{k}" }
      p $/
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      2
      "gone z"
      "\n"
    OUT
  end

  it "class ivar save restore" do
    _(ze0(<<~'RUBY')).must_answer "2\n"
      # A capture-style save/restore of a class-ivar whose type widens to poly under
      # whole-program pressure. @query_log is written a bare `[]` (poly-array), pushed
      # strings (str-array), and restored from `prev`; those heterogeneous writes merge
      # the slot to poly. The `prev = @query_log` local must widen to poly with it --
      # otherwise codegen emits an unsound `sp_StrArray *` <- `sp_RbVal` (issue #1793).
      class Db
        @query_log = nil
        def self.capture_sql
          prev = @query_log
          log = []
          @query_log = log
          begin
            yield
          ensure
            @query_log = prev
          end
          log
        end
        def self.record_query(sql)
          @query_log.push(sql) unless @query_log.nil?
        end
      end

      class ArticlesTest
        def test_index
          sql = Db.capture_sql { Db.record_query("SELECT 1"); Db.record_query("SELECT 2") }
          sql.length
        end
      end
      p ArticlesTest.new.test_index
    RUBY
  end

  it "crashers 536" do
    result = ze0(<<~'RUBY')
      # #536. Three crashers:
      #
      # 1. `[].sample` on an empty IntArray emitted `rand() %
      #    sp_IntArray_length(...)` which becomes `rand() % 0` (SIGFPE
      #    under -O0, UB elsewhere). The receiver was also evaluated
      #    twice, allocating a fresh IntArray on each call. Fix: per-
      #    prefix `sp_<X>_sample` helper that guards `len <= 0` and
      #    returns the slot's zero value (0 / 0.0 / NULL / sp_box_nil).
      #
      # 2. `[1,2,3,2].union` (no args) compiled the call as
      #    `sp_IntArray_union(arr, 0)`. The runtime then dereferenced
      #    the null second-arg pointer. Fix: NULL-guard the second-arg
      #    walk in `sp_IntArray_union` / `sp_FloatArray_union` /
      #    `sp_StrArray_union` so the no-args form reduces to dedup.
      #
      # 3. `{ 0 => false, a: 1 }` (mixed IntegerNode + SymbolNode keys)
      #    fell through to `str_poly_hash` and codegen handed the
      #    integer key directly to `sp_StrPolyHash_set`, which read it
      #    as `const char *` -- segfault on the next access. Fix:
      #    detect mixed-shape keys and use `poly_poly_hash` so both key
      #    and value carry their own tag.

      # Empty Array#sample returns nil, matching CRuby (was the zero value; #2322).
      puts [].sample.inspect

      # No-args Array#union reduces to dedup.
      puts [1, 2, 3, 2].union.inspect

      # Mixed-key hash literal builds via poly_poly_hash.
      h = { 0 => false, a: 1 }
      puts h.size
      puts h[:a]
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      [1, 2, 3]
      2
      1
    OUT
  end

  it "data hash key" do
    result = ze0(<<~'RUBY')
      P = Data.define(:x, :y)
      p({ P.new(1, 2) => "a" }[P.new(1, 2)])
      h = { P.new(1, 2) => "a" }; p(h[P.new(1, 2)])
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      "a"
    OUT
  end

  it "dir chdir block form restores the previous directory" do
    result = ze0(<<~'RUBY')
      # `Dir.chdir`'s block form restores the previous directory afterwards.

      dir = File.join(ENV.fetch("TMPDIR", "/tmp"), "zeo_e2e_chdir_#{Process.pid}")
      Dir.mkdir(dir)
      begin
        before = Dir.pwd
        Dir.chdir(dir) do
          p Dir.pwd != before
        end
        p Dir.pwd == before
      ensure
        Dir.rmdir(dir)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
    OUT
  end

  it "empty hash const value" do
    result = ze0(<<~'RUBY')
      # An empty hash literal as a receiver ({}.freeze) types as the same str-keyed
      # poly hash codegen emits for a bare {} -- without it the constant was dropped
      # from codegen entirely (reads raised "uninitialized constant", and a typed
      # ivar's `|| CONST` fallback broke the C build).
      class C
        EMPTY = {}.freeze
        def initialize
          @h = nil
        end
        def read
          @h || EMPTY
        end
      end
      p C.new.read
      p C::EMPTY.empty?
      p C::EMPTY.size
      TOP = {}.freeze
      p TOP
    RUBY

    _(result).must_answer <<~'OUT'
      {}
      true
      0
      {}
    OUT
  end

  it "empty hash int int no widen" do
    result = ze0(<<~'RUBY')
      # `h = {}; h[parts[0]] = v` where `parts` comes from a `split` result
      # (or any expression that returns str_array). Two pre-fix shapes
      # combined:
      #
      # 1. kt="int" + vt="int" — pass-0 promote_empty_hash_for widened to
      #    poly_poly_hash via the catch-all. Now defers (returns "") so the
      #    second pass with the key resolved as string produces
      #    str_int_hash.
      # 2. kt="int" + vt="string" — pass-0 promoted to int_str_hash, and
      #    the refine_locals merge had no rule to upgrade int_str_hash to
      #    str_str_hash when pass 1 resolved the key as string. Added
      #    int_str_hash → str_str_hash / sym_str_hash widening rules.
      #
      # Sibling check: a literal-keyed `h = {}; h[200] = "OK"` (legitimate
      # int-keyed-string-valued) keeps int_str_hash.

      def build_str_keyed_int_val(s)
        parts = s.split("/")
        h = {}
        h[parts[0]] = 1
        h
      end

      def build_str_keyed_str_val(s)
        parts = s.split("/")
        h = {}
        h[parts[0]] = "v"
        h
      end

      def build_int_keyed
        h = {}
        h[200] = "OK"
        h[404] = "NotFound"
        h
      end

      h1 = build_str_keyed_int_val("a/b")
      puts h1["a"]            # 1

      h1b = build_str_keyed_str_val("a/b")
      puts h1b["a"]           # v

      h2 = build_int_keyed
      puts h2[200]            # OK
      puts h2[404]            # NotFound
    RUBY

    _(result).must_answer <<~'OUT'
      1
      v
      OK
      NotFound
    OUT
  end

  it "empty hash key context" do
    result = ze0(<<~'RUBY')
      # An empty Hash literal bound to a local takes its variant from the key it is
      # indexed with, not the StrPolyHash fallback.
      h = {}
      p h.fetch(1, "d")
      g = {}
      p g.fetch(:sym, "s")
      begin
        k = {}
        k.fetch(:missing)
      rescue KeyError => e
        p e.key
      end
      begin
        n = {}
        n.fetch(99)
      rescue KeyError => e
        p e.key
      end
      s = {}
      p s.fetch("str", 0)
      # writes still drive the variant when present
      w = {}
      w[:a] = 1
      p w
    RUBY

    _(result).must_answer <<~'OUT'
      "d"
      "s"
      :missing
      99
      0
      {a: 1}
    OUT
  end

  it "empty hash nonscalar key" do
    result = ze0(<<~'RUBY')
      # A bare `{}` takes the hash variant its KEY selects. The rule knew Symbol,
      # String, Integer and poly keys; every other kind fell through to the
      # StrPolyHash default, which put the key straight into a `const char *` slot
      # and the C compiler reported it against generated code (#4000):
      #
      #   error: initialization of 'const char *' from incompatible pointer type
      #          'sp_IntArray *'
      #
      # The reported spelling had an EMPTY array as the key, which is the harder
      # half: it infers no kind at all, yet it is still a pointer once emitted.
      p(
        [].each do
          {}.fetch [], 0
        end
      )

      class T
        def arr_key
          {}.fetch([1, 2], 0)
        end

        def empty_arr_key
          {}.fetch([], 0)
        end

        def empty_hash_key
          {}.fetch({}, 0)
        end

        def float_key
          {}.fetch(1.5, 0)
        end

        def nil_key
          {}.fetch(nil, 0)
        end

        def obj_key
          {}.fetch(Object.new, 0)
        end
      end

      t = T.new
      p t.arr_key
      p t.empty_arr_key
      p t.empty_hash_key
      p t.float_key
      p t.nil_key
      p t.obj_key

      # and the widened variant really holds those keys, not just compiles
      h = {}
      h[[1, 2]] = "pair"
      h[1.5] = "float"
      h[nil] = "nil"
      p h[[1, 2]]
      p h[1.5]
      p h[nil]
      p h.fetch([9], "miss")
      p h.key?([1, 2])
      p h.dig([1, 2])
      p h.size
    RUBY

    _(result).must_answer <<~'OUT'
      []
      0
      0
      0
      0
      0
      0
      "pair"
      "float"
      "nil"
      "miss"
      true
      "pair"
      3
    OUT
  end

  it "find ifnone tally hash and min max by count" do
    result = ze0(<<~'RUBY')
      p [1, 2, 3].find(-> { -1 }) { |x| x > 10 }
      p [1, 20, 3].find(-> { -1 }) { |x| x > 10 }
      p [1, nil, 3].find(-> { :fallback }) { |x| x.nil? }
      h = Hash.new(0)
      p [1, 1, 2, 3, 3, 3].tally(h)
      p h
      p [5, 5, 6].tally({ 5 => 10 })
      p %w[bbbb a ccc dd].max_by(2, &:length)
      p %w[bbbb a ccc dd].min_by(2, &:length)
      p [1, 2, 3].min_by(0) { |n| n }
      begin
        [1, 2, 3].max_by(-1) { |n| n }
      rescue ArgumentError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      20
      nil
      {1 => 2, 2 => 1, 3 => 3}
      {1 => 2, 2 => 1, 3 => 3}
      {5 => 12, 6 => 1}
      ["bbbb", "ccc"]
      ["a", "dd"]
      []
      "negative size (-1)"
    OUT
  end

  it "for over hash and bigint when" do
    result = ze0(<<~'RUBY')
      # for over a hash iterates [key, value] pairs in insertion order; a Bignum
      # scrutinee matches a Bignum when-literal by value.
      k = 0
      l = 0
      for i, j in { 1 => 10, 2 => 20 }
        k += i
        l += j
      end
      p k
      p l
      for pair in { "a" => 1 }
        p pair
      end
      huge = 1267650600228229401496703205376
      case huge
      when 1267650600228229401496703205376 then puts "big"
      else puts "no"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      3
      30
      ["a", 1]
      big
    OUT
  end

  it "frozen literal hash key" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true
      # A frozen source literal carries a real string header (the 0xf1 marker
      # promises one for the hash cache); baked onto bare rodata the cached-hash
      # read landed in neighboring rodata, so a literal Hash key missed entries
      # whose equal-content keys were built at runtime.
      h = {}
      "apple,banana,cherry".split(",").each { |w| h[w] = w.length }
      literal_key = "banana"
      puts h[literal_key]
      puts h[literal_key.dup]
      p "banana".frozen?
      begin
        literal_key << "!"
      rescue FrozenError, RuntimeError
        puts "frozen enforced"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
      true
      frozen enforced
    OUT
  end

  it "hash and builtin types" do
    result = ze0(<<~'RUBY')
      h = {}
      h[:a] = 1
      h[:b] = 2
      h[:c] = 3
      h[:a] = 99
      puts h
      puts h.length

      pairs = {}
      pairs[[1, 2]] = "one-two"
      pairs[[3, 4]] = "three-four"
      puts pairs[[1, 2]]
      puts pairs[[3, 4]]

      x = 5
      puts x.is_a?(Integer)
      puts x.is_a?(String)
      puts x.is_a?(Object)
      puts x.kind_of?(Integer)

      arr = [1, 2, 3]
      puts arr.is_a?(Array)
      puts arr.is_a?(Hash)

      r = 1..5
      puts r.is_a?(Range)

      sym = :foo
      puts sym.is_a?(Symbol)

      puts nil.is_a?(NilClass)
      puts true.is_a?(TrueClass)
      puts false.is_a?(FalseClass)

      class Checker
        def check(v)
          v.is_a?(Integer)
        end
      end
      c = Checker.new
      puts c.check(5)
      puts c.check("hi")
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 99, b: 2, c: 3}
      3
      one-two
      three-four
      true
      false
      true
      true
      true
      false
      true
      true
      true
      true
      true
      true
      false
    OUT
  end

  it "hash class bracket constructor" do
    result = ze0(<<~'RUBY')
      p Hash[]
      p Hash[1, 2, 3, 4]
      p Hash[[[:a, 1], [:b, 2]]]
      p Hash[{ x: 1 }]
    RUBY

    _(result).must_answer <<~'OUT'
      {}
      {1 => 2, 3 => 4}
      {a: 1, b: 2}
      {x: 1}
    OUT
  end

  it "hash clear" do
    result = ze0(<<~'RUBY')
      h1 = { a: 1, b: 2, c: 3 }
      h1.clear
      puts h1.size
      puts h1.empty?

      h2 = { "a" => 1, "b" => 2 }
      h2.clear
      puts h2.size

      h3 = { x: "one", y: "two" }
      h3.clear
      puts h3.size

      h4 = { a: 1, b: "x" }
      h4.clear
      puts h4.size

      h5 = { "a" => 1, "b" => "x" }
      h5.clear
      puts h5.size

      h6 = { "a" => "one", "b" => "two" }
      h6.clear
      puts h6.size

      h7 = { 1 => "one", 2 => "two" }
      h7.clear
      puts h7.size

      h8 = { 1 => "one", 2 => 2 }
      h8.clear
      puts h8.size

      h9 = { "a" => "one", 2 => 2 }
      h9.clear
      puts h9.size

      # After clear, can write again — slot reset works
      h_rw = { a: 1, b: 2 }
      h_rw.clear
      h_rw[:z] = 99
      puts h_rw[:z]
      puts h_rw.size
    RUBY

    _(result).must_answer <<~'OUT'
      0
      true
      0
      0
      0
      0
      0
      0
      0
      0
      99
      1
    OUT
  end

  it "hash compound assign more" do
    result = ze0(<<~'RUBY')
      # Hash#[] op= for string-valued and poly-valued typed hashes.

      # sym_str_hash: += str → concat.
      h = {a: "hello", b: "world"}
      h[:a] += "!"
      puts h[:a]

      # str_str_hash: += str → concat.
      h2 = {"a" => "hello", "b" => "world"}
      h2["a"] += "!"
      puts h2["a"]

      # sym_poly_hash: += int on a hash whose values are mixed.
      h3 = {a: 1, b: 2.0}
      h3[:a] += 10
      puts h3[:a]

      # str_poly_hash: += int.
      h4 = {"a" => 1, "b" => 2.0}
      h4["a"] += 10
      puts h4["a"]
    RUBY

    _(result).must_answer <<~'OUT'
      hello!
      hello!
      11
      11
    OUT
  end

  it "hash ctor merge clone transform" do
    result = ze0(<<~'RUBY')
      # The Hash[] constructor, multi-argument merge/merge!, Array#clone's frozen
      # flag, inline Hash.new(default) arguments, Array#slice!(i)/(range),
      # transform_values!/transform_keys! and transform_keys(mapping), and
      # multi-candidate start_with?/end_with?.
      p Hash[[[:a, 1], [:b, 2]]]
      p Hash[:a, 1, :b, 2]
      p({ a: 1 }.merge({ b: 2 }, { c: 3 }))
      h = { a: 1 }
      h.merge!({ b: 2 }, { c: 3 })
      p h
      a = [1, 2, 3].freeze
      p a.clone.frozen?
      p a.dup.frozen?
      p a.clone(freeze: false).frozen?
      p [1, 2, 2, 3].each_with_object(Hash.new(0)) { |x, acc| acc[x] += 1 }
      b = [1, 2, 3, 4]
      p b.slice!(1)
      p b.slice!(1..2)
      p b
      hv = { a: 1, b: 2 }
      hv.transform_values! { |v| v * 10 }
      p hv
      hk = { a: 1, b: 2 }
      hk.transform_keys! { |k| k.to_s }
      p hk
      p({ a: 1, b: 2 }.transform_keys(a: :x))
      p "hello".start_with?("x", "he")
      p "test.rb".end_with?(".py", ".rb")
      p "abc".start_with?("z", "q")
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2}
      {a: 1, b: 2}
      {a: 1, b: 2, c: 3}
      {a: 1, b: 2, c: 3}
      true
      false
      false
      {1 => 1, 2 => 2, 3 => 1}
      2
      [3, 4]
      [1]
      {a: 10, b: 20}
      {"a" => 1, "b" => 2}
      {x: 1, b: 2}
      true
      true
      false
    OUT
  end

  it "hash default" do
    result = ze0(<<~'RUBY')
      # `Hash.new` accepts a per-instance default that a missing key falls back to.

      # A default VALUE: every missing key reads back as it (without being stored).
      counts = Hash.new(0)
      %w[a b a c a b].each { |w| counts[w] += 1 }
      p counts                                  # {"a" => 3, "b" => 2, "c" => 1}
      p counts["missing"]                       # 0
      p counts.size                             # 3 -- the miss above stored nothing

      # A default BLOCK is called with the hash and the missing key, and commonly
      # memoizes by writing the computed value back into the hash.
      squares = Hash.new { |h, k| h[k] = k * k }
      p squares[4]                              # 16
      p squares[9]                              # 81
      p squares                                 # {4 => 16, 9 => 81}

      # With neither, a missing key is nil, and `default` reports what was set.
      plain = Hash.new
      p plain[:nope]                            # nil
      p Hash.new("fallback").default            # "fallback"
    RUBY

    _(result).must_answer <<~'OUT'
      {"a" => 3, "b" => 2, "c" => 1}
      0
      3
      16
      81
      {4 => 16, 9 => 81}
      nil
      "fallback"
    OUT
  end

  it "hash fetch keyerror" do
    result = ze0(<<~'RUBY')
      # Issue #914: Hash#fetch without a default raises KeyError on
      # a missing key, not 0.
      h = {a: 1}

      # With a default — works as before.
      puts h.fetch(:missing, "default")
      puts h.fetch(:a)

      # Without a default — should raise KeyError.
      begin
        h.fetch(:missing)
        puts "no exception"
      rescue KeyError
        puts "caught KeyError"
      end

      # String-keyed hash.
      h2 = {"x" => 1}
      begin
        h2.fetch("y")
      rescue KeyError
        puts "str-hash caught"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      default
      1
      caught KeyError
      str-hash caught
    OUT
  end

  it "hash insert during each raises" do
    result = ze0(<<~'RUBY')
      # Ruby forbids adding a new key to a Hash while iterating it: RuntimeError
      # "can't add a new key into hash during iteration". zeo's Hash#each takes no
      # iteration borrow, so the insert silently succeeds. Updating an EXISTING key
      # stays legal on both sides (the control below).
      h = { a: 1, b: 2 }
      begin
        h.each { |k, v| h[:c] = 3 }
      rescue RuntimeError => e
        puts "insert: #{e.message}"
      end
      puts h.key?(:c).inspect

      h2 = { a: 1 }
      h2.each { |k, v| h2[:a] = 99 }
      puts h2[:a]
    RUBY

    _(result).must_answer <<~'OUT'
      insert: can't add a new key into hash during iteration
      false
      99
    OUT
  end

  it "hash invert" do
    result = ze0(<<~'RUBY')
      # Hash#invert — swap keys and values.
      # str_int_hash → poly_poly_hash, str_str_hash → str_str_hash,
      # sym_int_hash → poly_poly_hash, int_str_hash → str_str_hash.
      # All typed hash variants must compile and produce correct output.

      h1 = {"a" => 1, "b" => 2}
      p h1.invert

      h2 = {a: 1, b: 2}
      p h2.invert

      h3 = {"a" => "b", "c" => "d"}
      p h3.invert

      h4 = {1 => "a", 2 => "b"}
      p h4.invert
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => "a", 2 => "b"}
      {1 => :a, 2 => :b}
      {"b" => "a", "d" => "c"}
      {"a" => 1, "b" => 2}
    OUT
  end

  it "hash itself enum nil" do
    result = ze0(<<~'RUBY')
      h = { a: 1 }
      p h.itself
      e = [1, 2, 3].each
      p e.nil?
      pr = ->(x) { x }
      p pr.respond_to?(:call)
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1}
      false
      true
    OUT
  end

  it "hash key via intermediate local" do
    _(ze0(<<~'RUBY')).must_answer "3\n"
      # Sibling to #443. `h[pp[1..]] = ap` where pp/ap are intermediate
      # locals (themselves split-result elements) had the hash inferred
      # as str_int_hash instead of str_str_hash. Root cause: the
      # refine_method_body_locals 2-pass merge resolved pp's type
      # (str_array element → string), but the merge happened AFTER the
      # pass-2 scan_locals run. Inside that pass-2 scan, infer_type(pp)
      # read pp's pass-1 type (still "int" because pa wasn't declared
      # during pass 1) from global scope, so `h[pp[1..]] = ap` promoted
      # the empty hash to int_str_hash and the merge dropped the
      # correction.
      #
      # Fix: add a pass-3 scan_locals to refine_method_body_locals,
      # run after the merge has corrected intermediate-local types in
      # scope. The third pass re-resolves nested-CallNode key/value
      # expressions (pp[1..], pp.upcase, etc.) against the merged
      # scope, picking up the right hash variant.

      def build(a, b)
        pa = a.split("/")
        pb = b.split("/")
        h = {}
        i = 0
        while i < pa.length
          pp = pa[i]
          ap = pb[i]
          h[pp + "_k"] = ap
          i += 1
        end
        h.length
      end

      puts build("a/b/c", "x/y/z")
    RUBY
  end

  it "hash literal" do
    result = ze0(<<~'RUBY')
      h = { a: 1, b: 2 }
      puts(h[:a])
      puts(h[:b])
      puts(h[:missing])
      h[:c] = 3
      puts(h[:c])
      h[:a] = 10
      puts(h[:a])
      puts(h.length)
      puts(h.size)
      puts(h)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2

      3
      10
      3
      3
      {a: 10, b: 2, c: 3}
    OUT
  end

  it "hash literal indexing and mutation" do
    result = ze0(<<~'RUBY')
      h = { a: 1, b: 2 }
      puts(h[:a])
      puts(h[:b])
      puts(h[:missing])
      h[:c] = 3
      puts(h[:c])
      h[:a] = 10
      puts(h[:a])
      puts(h.length)
      puts(h.size)
      puts(h)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2

      3
      10
      3
      3
      {a: 10, b: 2, c: 3}
    OUT
  end

  it "hash merge bang" do
    result = ze0(<<~'RUBY')
      # In-place Hash#merge! / #update mutate the receiver and return it.
      # Per-variant helpers keep each receiver's concrete hash type (a single shared
      # helper would unify every variant to a poly-valued hash).
      def hsym(x); x; end   # symbol-keyed, int-valued
      def hpol(x); x; end   # symbol-keyed, mixed (poly) values
      def hstr(x); x; end   # string-keyed, int-valued

      # basic merge! adds the other hash's pairs
      a = hsym({a: 1})
      a.merge!({c: 3})
      p a                 # {a: 1, c: 3}

      # update is an alias; both return the receiver itself
      b = hsym({a: 1})
      r = b.update({b: 2})
      p [r, b]            # [{a: 1, b: 2}, {a: 1, b: 2}]

      # a conflicting key is resolved by the block (key, old, new)
      cf = hsym({a: 1, b: 2})
      cf.merge!({b: 10, c: 3}) { |k, old, new| old + new }
      p cf                # {a: 1, b: 12, c: 3}

      # without a block, the other hash wins on a conflict
      ov = hsym({a: 1, b: 2})
      ov.merge!({b: 99})
      p ov                # {a: 1, b: 99}

      # merging an empty hash is a no-op
      em = hsym({a: 1})
      p em.merge!({})     # {a: 1}

      # chaining works because each call returns the receiver
      ch = hsym({a: 1})
      ch.merge!({b: 2}).merge!({c: 3})
      p ch                # {a: 1, b: 2, c: 3}

      # poly-valued receiver accepts further pairs
      pv = hpol({a: 1, b: "x"})
      pv.merge!({c: 9})
      p pv                # {a: 1, b: "x", c: 9}

      # string-keyed receiver
      sk = hstr({"a" => 1})
      sk.update({"b" => 2})
      p sk                # {"a" => 1, "b" => 2}
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, c: 3}
      [{a: 1, b: 2}, {a: 1, b: 2}]
      {a: 1, b: 12, c: 3}
      {a: 1, b: 99}
      {a: 1}
      {a: 1, b: 2, c: 3}
      {a: 1, b: "x", c: 9}
      {"a" => 1, "b" => 2}
    OUT
  end

  it "hash merge except splat" do
    result = ze0(<<~'RUBY')
      hs001 = [{ b: 2 }]
      p({ a: 1 }.merge(*hs001))
      ks002 = [:a]
      p({ a: 1, b: 2 }.except(*ks002))
      p({ a: 1 }.merge({ b: 2 }))
      p({ a: 1, b: 2 }.except(:a))
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2}
      {b: 2}
      {a: 1, b: 2}
      {b: 2}
    OUT
  end

  it "hash merge splat" do
    result = ze0(<<~'RUBY')
      hs = [{ b: 2 }]
      h = { a: 1 }
      h.merge!(*hs)
      p h
      hs2 = [{ b: 2 }, { c: 3 }]
      h2 = { a: 1 }
      h2.update(*hs2)
      p h2
      g = { "a" => 1 }
      gs = [{ "b" => 2 }]
      g.merge!(*gs)
      p g
      k = { a: 1 }
      k.merge!({ b: 2 })
      p k
      ks = [:a]
      p({ a: 1, b: 2 }.except(*ks))
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2}
      {a: 1, b: 2, c: 3}
      {"a" => 1, "b" => 2}
      {a: 1, b: 2}
      {b: 2}
    OUT
  end

  it "hash merge variants" do
    result = ze0(<<~'RUBY')
      # Hash#merge on poly_poly, int_int, and int_str hash variants (str-keyed already
      # worked). Frozen-constant receivers infer as poly_poly; ints exercise int-keyed
      # variants. A trailing flat_map mirrors the originating gem's use.
      A = { "x" => ["a"] }.freeze
      B = { "y" => ["b"] }.freeze
      C = A.merge(B).flat_map { |k, vs| vs.map { |v| k + v } }
      puts C.length
      puts C.sort.join(",")

      ii = { 1 => 10 }.merge({ 2 => 20 })
      puts ii.length
      puts ii[2]

      is = { 1 => "one" }.merge({ 2 => "two" })
      puts is[1]
      puts is[2]

      # later keys win on overlap (receiver value overwritten by argument)
      ov = { 1 => 10 }.merge({ 1 => 99, 3 => 30 })
      puts ov[1]
      puts ov.length
    RUBY

    _(result).must_answer <<~'OUT'
      2
      xa,yb
      2
      20
      one
      two
      99
      2
    OUT
  end

  it "hash mixed key writes" do
    result = ze0(<<~'RUBY')
      h1 = { a: 1 }
      h1["x"] = 9
      p h1

      h2 = { "a" => 1 }
      h2[:b] = 2
      p h2
      p h2.keys

      h3 = { 1 => 2 }
      h3[:x] = 3
      p h3

      h4 = { 1 => 2 }
      h4["x"] = 3
      p h4

      h5 = { a: 1 }
      h5.store("x", 9)
      p h5

      h6 = { a: 1 }
      h6.update({ "x" => 9 })
      p h6

      h7 = { a: 1 }
      k = "x"
      h7[k] = 9
      p h7

      h8 = Hash.new
      h8[:a] = 1
      h8["x"] = 9
      p h8

      h9 = {}
      h9[:a] = 1
      h9["x"] = 9
      p h9

      s1 = { a: 1 }
      s1[:b] = 2
      p s1

      s2 = { "a" => 1 }
      s2["b"] = 2
      p s2

      s3 = { a: 1 }
      s3[1] = 9
      p s3

      s4 = { a: 1 }
      s4[2.5] = 9
      p s4

      s5 = { a: 1, "x" => 9 }
      p s5
      p({ a: 1 }.merge({ "x" => 9 }))
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, "x" => 9}
      {"a" => 1, b: 2}
      ["a", :b]
      {1 => 2, x: 3}
      {1 => 2, "x" => 3}
      {a: 1, "x" => 9}
      {a: 1, "x" => 9}
      {a: 1, "x" => 9}
      {a: 1, "x" => 9}
      {a: 1, "x" => 9}
      {a: 1, b: 2}
      {"a" => 1, "b" => 2}
      {a: 1, 1 => 9}
      {a: 1, 2.5 => 9}
      {a: 1, "x" => 9}
      {a: 1, "x" => 9}
    OUT
  end

  it "hash new param default" do
    result = ze0(<<~'RUBY')
      def f001(n001, memo001 = Hash.new)
        memo001[n001] = n001
        memo001
      end
      p f001(1)
      def f002(n, memo = Hash.new(0))
        memo[n] += 1
        memo
      end
      p f002(:a)
      h003 = Hash.new
      h003[:a] = 1
      p h003
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => 1}
      {a: 1}
      {a: 1}
    OUT
  end

  it "hash projection and inplace methods" do
    result = ze0(<<~'RUBY')
      h = { a: 1, b: 2, c: 3 }
      p h.values_at(:a, :c)
      p h.assoc(:b)
      p h.rassoc(2)
      p({ a: 1, b: nil, c: 3 }.compact)
      y = { a: 1, b: 2, c: 3 }; p y.shift; p y
      p({ a: 1, b: 2 }.select! { |_k, v| v > 1 })
      z = { a: 1, b: 2 }; z.transform_values! { |v| v * 10 }; p z
      p({ a: 1, b: 2 } <= { a: 1, b: 2, c: 3 })
      p({ a: 1, b: 2, c: 3 } > { a: 1 })
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3]
      [:b, 2]
      [:b, 2]
      {a: 1, c: 3}
      [:a, 1]
      {b: 2, c: 3}
      {b: 2}
      {a: 10, b: 20}
      true
      true
    OUT
  end

  it "hash shorthand" do
    result = ze0(<<~'RUBY')
      # Hash shorthand `{ x:, y: }` (Ruby 3.1+): an AssocNode whose value is
      # implicit. Prism wraps the implicit value in a PM_IMPLICIT_NODE that
      # carries the actual LocalVariableReadNode (or MethodCallNode for an
      # undeclared name) as its `value` child. spinel_parse unwraps the
      # ImplicitNode at the AST boundary so the codegen never sees the
      # wrapper, which means the shorthand reuses the existing
      # AssocNode + LocalVariableReadNode compile path with zero codegen
      # change.

      # 1. Two-key shorthand from int-valued locals.
      x = 10
      y = 20
      nums = {x:, y:}
      puts nums[:x]
      # 10
      puts nums[:y]
      # 20

      # 2. Single-key shorthand returned from a method body.
      def make_pair(weight)
        {weight:}
      end

      h = make_pair(42)
      puts h[:weight]
      # 42

      # 3. Mixing shorthand and explicit pair (same value type — int).
      n = 7
      m = 11
      total = {n:, m:, sum: 18}
      puts total[:n]
      # 7
      puts total[:m]
      # 11
      puts total[:sum]
      # 18
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      42
      7
      11
      18
    OUT
  end

  it "hash temp gc root" do
    _(ze0(<<~'RUBY')).must_answer "ok\n"
      # #689: Hash temporaries created from `{}` literals must be GC-rooted
      # before subsequent allocations, otherwise GC may reclaim them mid-
      # expression and the consuming call reads NULL+offset.
      #
      # Simulates the failing pattern: two hash literals constructed in
      # sequence, the first consumed by a helper that allocates more.

      def two_hashes(a, b)
        a.length + b.length
      end

      # Drive GC by allocating between binding and consumption.
      i = 0
      while i < 5000
        h1 = {"x" => 1, "y" => 2}
        h2 = {"a" => 3, "b" => 4}
        # Allocate strings to force GC pressure between the two hash
        # literals (the same pattern that #689 hits with stylesheet_link_tag).
        filler = "filler-" + i.to_s + "-" + i.to_s
        if two_hashes(h1, h2) != 4
          puts "broken at #{i}"
          exit 1
        end
        i += 1
      end
      puts "ok"
    RUBY
  end

  it "hash transform group" do
    result = ze0(<<~'RUBY')
      # Hash#flat_map / #filter_map / #partition / #group_by build collections from
      # the |key, value| pairs: flat_map concatenates the per-entry arrays,
      # filter_map keeps truthy block values, partition splits into matching and
      # remaining pairs, and group_by buckets pairs by the block value. Helpers are
      # monomorphic so the runtime walk is exercised without widening to poly.

      def flat_kv(h)   = h.flat_map { |k, v| [k, v] }
      def flat_dup(h)  = h.flat_map { |k, v| [v, v] }
      def fmap_big(h)  = h.filter_map { |k, v| v if v > 1 }
      def fmap_key(h)  = h.filter_map { |k, v| k }
      def part_even(h) = h.partition { |k, v| v.even? }
      def part_str(h)  = h.partition { |k, v| v > 1 }
      def group_even(h) = h.group_by { |k, v| v.even? }
      def group_mod(h)  = h.group_by { |k, v| v % 3 }

      p flat_kv({ a: 1, b: 2 })
      p flat_dup({ a: 1, b: 2 })
      p fmap_big({ a: 1, b: 2, c: 3 })
      p fmap_key({ a: 1, b: 2 })
      p part_even({ a: 1, b: 2, c: 3, d: 4 })
      p part_str({ "a" => 1, "b" => 2, "c" => 3 })
      p group_even({ a: 1, b: 2, c: 3 })
      p group_mod({ a: 1, b: 2, c: 3, d: 4 })
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 1, :b, 2]
      [1, 1, 2, 2]
      [2, 3]
      [:a, :b]
      [[[:b, 2], [:d, 4]], [[:a, 1], [:c, 3]]]
      [[["b", 2], ["c", 3]], [["a", 1]]]
      {false => [[:a, 1], [:c, 3]], true => [[:b, 2]]}
      {1 => [[:a, 1], [:d, 4]], 2 => [[:b, 2]], 0 => [[:c, 3]]}
    OUT
  end

  it "hash transform keys bang" do
    result = ze0(<<~'RUBY')
      # Hash#transform_keys! / transform_values! on a direct literal (KieranP #2355)
      p({ a: 1, b: 2 }.transform_keys!(&:to_s))       # key type sym -> str
      p({ a: 1, b: 2 }.transform_keys! { |k| k.to_s })
      p({ a: 1, b: 2 }.transform_values!(&:to_s))
      p({ a: 1, b: 2 }.transform_keys! { |k| k })
      h = { a: 1, b: 2 }
      h.transform_values! { |v| v * 10 }               # variable form (same variant)
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      {"a" => 1, "b" => 2}
      {"a" => 1, "b" => 2}
      {a: "1", b: "2"}
      {a: 1, b: 2}
      {a: 10, b: 20}
    OUT
  end

  it "hash values at fetch values" do
    result = ze0(<<~'RUBY')
      # Hash#values_at / #fetch_values on typed hashes. Each key is looked up
      # and the values collected into an array; values_at yields nil for a
      # missing key, fetch_values raises KeyError. Results box into a
      # poly_array so mixed value types and nil coexist.
      h = {a: 1, b: 2, c: 3}
      p h.values_at(:a, :c)
      p h.values_at(:a, :c, :d)
      p h.fetch_values(:a, :b, :c)

      s = {"x" => 10, "y" => 20}
      p s.values_at("x", "z")

      ss = {a: "one", b: "two"}
      p ss.values_at(:a, :b, :c)

      pp = {a: 1, b: "two", c: nil}
      p pp.values_at(:a, :b, :c, :d)

      begin
        h.fetch_values(:a, :z)
      rescue KeyError
        puts "KeyError raised"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3]
      [1, 3, nil]
      [1, 2, 3]
      [10, nil]
      ["one", "two", nil]
      [1, "two", nil, nil]
      KeyError raised
    OUT
  end

  it "hash variant returns" do
    result = ze0(<<~'RUBY')
      # Hash methods flowing through user-method returns: compact, flatten,
      # each_with_index, each_with_object with an empty {} seed, Hash[pairs]
      # with a non-literal argument, and chunk grouping consecutive pairs.
      def fc(h)
        g = h.compact
        g
      end
      def fl(h); h.flatten; end
      def fw(h)
        r = []
        h.each_with_index { |pair, i| r << [i, pair[0]] }
        r
      end
      def fo(h)
        h.each_with_object({}) { |(k, v), acc| acc[v] = v * v }
      end
      def fb(a); Hash[a]; end
      def fk(h)
        h.chunk { |k, v| v.even? }.to_a
      end
      def fs(h)
        h.chunk { |k, v| v[0] }.to_a
      end
      def fn(h)
        h.chunk { |k, v| v.zero? ? nil : :pos }.to_a
      end
      def fa(h)
        h.chunk { |k, v| :_alone }.to_a
      end

      p fc({a: 1, b: nil, c: 3})     # {a: 1, c: 3}
      p fc({x: nil})                 # {}
      p fl({a: 1, b: 2})             # [:a, 1, :b, 2]
      p fw({a: 1, b: 2})             # [[0, :a], [1, :b]]
      p fo({a: 1, b: 2})             # {1 => 1, 2 => 4}
      p fb([[:a, 1], [:b, 2]])       # {a: 1, b: 2}
      p fk({a: 1, b: 2, c: 4})       # [[false, [[:a, 1]]], [true, [[:b, 2], [:c, 4]]]]
      p fk({a: 2, b: 4, c: 6})       # one all-true run
      p fs({"x" => "apple", "y" => "avocado", "z" => "berry"})  # grouped by first letter
      p fn({a: 1, b: 0, c: 3})       # nil key drops the pair and splits the run
      p fa({a: 1, b: 1})             # :_alone chunks each pair separately
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, c: 3}
      {}
      [:a, 1, :b, 2]
      [[0, :a], [1, :b]]
      {1 => 1, 2 => 4}
      {a: 1, b: 2}
      [[false, [[:a, 1]]], [true, [[:b, 2], [:c, 4]]]]
      [[true, [[:a, 2], [:b, 4], [:c, 6]]]]
      [["a", [["x", "apple"], ["y", "avocado"]]], ["b", [["z", "berry"]]]]
      [[:pos, [[:a, 1]]], [:pos, [[:c, 3]]]]
      [[:_alone, [[:a, 1]]], [:_alone, [[:b, 1]]]]
    OUT
  end

  it "int hash missing nil check" do
    result = ze0(<<~'RUBY')
      # Consumption-site nil-awareness for int-valued hashes (#801): a missing
      # key is nil in Ruby. The read stays typed `int` (making it int? cascades
      # through the self-host compiler), but at direct nil-check sites the
      # missing key is reported via has_key. Covers `.nil?`, and the already-
      # working `== nil` / `|| fallback`, across str_int / sym_int / int_int.

      si = {a: 1, b: 2}
      puts si[:zzz].nil?       # true
      puts si[:a].nil?         # false
      puts (si[:zzz] == nil)   # true
      puts (si[:zzz] || 99)    # 99
      puts (si[:a] || 99)      # 1

      sti = {"x" => 1}
      puts sti["y"].nil?       # true
      puts sti["x"].nil?       # false
      puts (sti["y"] || 7)     # 7

      ii = {1 => 10, 2 => 20}
      puts ii[9].nil?          # true
      puts ii[1].nil?          # false
      puts (ii[9] == nil)      # true
      puts (ii[9] || 5)        # 5

      # Present keys still behave as plain ints
      puts (si[:a] + 100)      # 101
      puts ii[2]               # 20
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      99
      1
      true
      false
      7
      true
      false
      true
      5
      101
      20
    OUT
  end

  it "int int hash keys values" do
    result = ze0(<<~'RUBY')
      # Hash#keys / #values on an Integer=>Integer hash (the IntIntHash variant had no
      # keys/values runtime helper: keys link-failed and values was a codegen reject).
      def id(x) = x

      m = {}
      m[1] = 10
      m[2] = 20
      m[3] = 30
      p m.keys
      p m.values
      p m.keys.sum
      p m.values.sum

      # through a method receiver (non-literal path)
      h = id({5 => 50, 6 => 60})
      p h.keys
      p h.values

      # keys/values compose with array methods
      p h.keys.map { |k| k * 2 }
      p h.values.max

      # single-entry literal int=>int hash
      g = {7 => 1}
      p g.keys
      p g.values

      # clear empties it: keys/values stay consistent (empty int arrays)
      g.clear
      p g.keys
      p g.values
      p g.keys.sum

      # re-populating after clear reflects the new entries in insertion order
      g[9] = 90
      g[8] = 80
      p g.keys
      p g.values
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [10, 20, 30]
      6
      60
      [5, 6]
      [50, 60]
      [10, 12]
      60
      [7]
      [1]
      []
      []
      0
      [9, 8]
      [90, 80]
    OUT
  end

  it "int int hash literal" do
    result = ze0(<<~'RUBY')
      # Int-keyed, int-valued hash literals build a native IntIntHash
      # (previously misrouted to StrIntHash, passing int keys as char* and
      # crashing). Reads, []= writes, and length all work.
      h = {1 => 10, 2 => 20, 3 => 30}
      puts h[1]
      puts h[2]
      puts h[3]
      h[4] = 40
      puts h[4]
      puts h.length
      h[2] = 222
      puts h[2]
      puts h.length
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      40
      4
      222
      4
    OUT
  end

  it "kernel hash frozen conformance" do
    result = ze0(<<~'RUBY', path: "core/hash/kernel_hash_frozen_conformance.rb")

      # Hash#all?/any?/none?/one? with a CLASS pattern is a kind-of test over the
      # [key, value] pairs; comparing the pair to the class value by equality
      # answered false for every pair
      h = { a: 1, b: 2 }
      p h.all?(Array)
      p h.any?(Array)
      p h.none?(Array)
      p h.one?(Array)
      p h.all?(String)
      p h.any?([:a, 1])

      # fetch: a block supersedes a positional default, as CRuby's warning says
      p({ a: 1 }.fetch(:z, 9) { |k| k })
      p({ a: 1 }.fetch(:z, 9))
      p({ a: 1 }.fetch(:z) { |k| k })
      p({ a: 1 }.fetch(:a, 9))

      # an op-assign is a write, so a frozen receiver refuses it
      class Counter
        def initialize; @n = 1; end
        def n; @n; end
        def bump; @n += 1; end
        def set(v); @n = v; end
      end

      c = Counter.new.freeze
      r = (c.bump rescue $!.class); p r
      p c.n
      r = (c.set(5) rescue $!.class); p r
      p c.n

      live = Counter.new
      live.bump
      p live.n

      # printf goes through the Ruby formatter, so a Symbol or nil reaches %s as a
      # value rather than a raw slot, and %p / %<name> / %{name} mean what they mean
      printf("%s\n", :sym)
      printf("%s|\n", nil)
      printf("%p\n", nil)
      printf("%<n>04d\n", n: 7)
      printf("%{k}\n", k: 3)
      printf("%05.2f %x %s\n", 1.5, 255, "s")

      # Kernel#Hash takes an empty Hash literal
      r = (Hash({}) rescue $!.class); p r
      p Hash({ a: 1 })
      p Hash([])
      p Hash(nil)
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/hash/kernel_hash_frozen_conformance.rb:14: warning: block supersedes default value argument\n"
      true
      true
      false
      false
      false
      true
      :z
      9
      :z
      1
      FrozenError
      1
      FrozenError
      1
      2
      sym
      |
      nil
      0007
      3
      01.50 ff s
      {}
      {a: 1}
      {}
      {}
    OUT
  end

  it "module ivar empty hash reset" do
    result = ze0(<<~'RUBY')
      # A module class method that resets a module-level hash ivar back to
      # `{}` used to emit the default `sp_StrIntHash_new()` regardless of
      # the slot's actual variant. When the slot was promoted to e.g.
      # sym_poly_hash by other writes, the reset path mismatched the
      # const's declared type at C compile.
      #
      # Two failures in one shape:
      #   1. Wrong constructor — empty_hash_coerce' s container-typed `_new()`
      #      logic wasn't consulted for module class methods because
      #      @current_class_idx was -1 (modules don't enter the class scope).
      #   2. Wrong LHS — `self->iv_X` for a module class method is dangling
      #      (no self). ivar_lhs already routes `@X` inside `Mod_cls_*` to
      #      `cst_<Mod>_<X>`; the codegen path was hardcoded to
      #      `self->` and bypassed it.

      module Counters
        @counts = {}

        def self.add(name, n)
          @counts[name] = (@counts[name] || 0) + n
        end

        def self.fetch(name)
          @counts[name] || 0
        end

        def self.reset!
          @counts = {}
        end
      end

      Counters.add(:apples, 3)
      Counters.add(:oranges, 5)
      puts Counters.fetch(:apples)
      puts Counters.fetch(:oranges)
      Counters.reset!
      puts Counters.fetch(:apples)
      Counters.add(:apples, 7)
      puts Counters.fetch(:apples)

      # Array variant — same shape: module-level @list = [] in reset.
      module Events
        @list = []

        def self.record(s)
          @list << s
        end

        def self.first
          @list[0] || ""
        end

        def self.reset!
          @list = []
        end
      end

      Events.record("one")
      Events.record("two")
      puts Events.first
      Events.reset!
      puts Events.first
      Events.record("after_reset")
      puts Events.first
    RUBY

    _(result).must_answer <<~'OUT'
      3
      5
      0
      7
      one

      after_reset
    OUT
  end

  it "module ivar hash" do
    result = ze0(<<~'RUBY')
      # Issue #303: a module ivar initialized to an empty hash literal
      # (`@slots = {}`) used to freeze its inferred type as `str_int_hash`
      # (the empty-hash default) even when the module's class methods
      # wrote a sym → string mapping into it. Result: the storage decl
      # said `sp_StrIntHash *` but every `set` / `get` site emitted
      # typed-mismatched calls (sym key into string-key hash, string
      # value into int-value hash).
      #
      # Fix: a refinement pass in generate_code (after param inference
      # stabilizes) walks each module's class-method bodies for
      # `@<iname>[k] = v` writes and picks the most specific hash shape
      # from the observed key + value types. Same idea for arrays via
      # `@<iname> << v` / `@<iname>.push(v)`.

      module M
        @slots = {}

        def self.set(k, v)
          @slots[k] = v
          nil
        end

        def self.get(k)
          @slots[k] || ""
        end

        def self.size
          @slots.length
        end
      end

      M.set(:foo, "bar")
      M.set(:baz, "qux")
      puts M.get(:foo)         # bar
      puts M.get(:baz)         # qux
      puts M.get(:missing)     # (empty default)
      puts M.size              # 2

      # Empty array literal — same refinement applies via `<<` writes.
      module N
        @items = []

        def self.add(s)
          @items << s
        end

        def self.read(i)
          @items[i]
        end

        def self.size
          @items.length
        end
      end

      N.add("alpha")
      N.add("beta")
      N.add("gamma")
      puts N.size              # 3
      puts N.read(0)           # alpha
      puts N.read(2)           # gamma
    RUBY

    _(result).must_answer <<~'OUT'
      bar
      qux

      2
      3
      alpha
      gamma
    OUT
  end

  it "respond to honours a singleton visibility" do
    result = ze0(<<~'RUBY')
      # `respond_to?` and `defined?(obj.m)` answer true for a PRIVATE per-object
      # singleton method, where CRuby answers false and nil.
      #
      # `responds_to_value` short-circuits on
      # `object_has_singleton_method(recv, name)` and returns true without ever
      # asking what visibility that row carries -- the class-side walk below it
      # applies the `include_all` rule, the per-object probe above it does not.
      # `defined?(obj.m)` reaches the same probe through `responds_to_or_missing`.

      def try(label)
        p [label, yield]
      rescue NoMethodError, NameError => e
        p [label, :raised, e.class.to_s]
      end

      module MFa
        module_function
        def helper = :helper
      end
      o = Object.new.extend(MFa)
      try(:respond)     { o.respond_to?(:helper) }
      try(:respond_all) { o.respond_to?(:helper, true) }
      try(:defined)     { defined?(o.helper) }

      r = Object.new
      def r.later = :later
      r.singleton_class.send(:private, :later)
      try(:r_respond)     { r.respond_to?(:later) }
      try(:r_respond_all) { r.respond_to?(:later, true) }
      try(:r_defined)     { defined?(r.later) }
      r.singleton_class.send(:public, :later)
      try(:r_back)        { r.respond_to?(:later) }

      module Prot
        def pm = :pm
        protected :pm
      end
      q = Object.new.extend(Prot)
      # A PROTECTED one is hidden from the default `respond_to?` too -- CRuby's
      # rule is "public only" unless `include_all`.
      try(:prot_respond)  { q.respond_to?(:pm) }
    RUBY

    _(result).must_answer <<~'OUT'
      [:respond, false]
      [:respond_all, true]
      [:defined, nil]
      [:r_respond, false]
      [:r_respond_all, true]
      [:r_defined, nil]
      [:r_back, true]
      [:prot_respond, false]
    OUT
  end

  it "runtime empty double splat contributes no trailing hash" do
    result = ze0(<<~'RUBY')
      # `foo(1, **h)` with an empty `h` passes just `1` -- the trailing hash
      # is pushed only when non-empty. This is about a RUNTIME-empty hash, not
      # the literal `**{}`, so it can't be decided at lowering time. Pushing
      # unconditionally silently handed the callee an extra `{}`.

      def foo(*z); z; end
      def c(h); foo(1, **h); end
      p c({})
      p c({k: 2})

      def kw(*z); z; end
      def d(h); kw(**h); end
      p d({})

      def both(h); foo(1, k: 1, **h); end
      p both({})
      p both({j: 2})
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [1, {k: 2}]
      []
      [1, {k: 1}]
      [1, {k: 1, j: 2}]
    OUT
  end

  it "splat forward keeps hash positional" do
    result = ze0(<<~'RUBY')
      def sink(a = 1, *rest, k: 2, **kw) = [a, rest, k, kw]

      def capture(*args) = args
      p capture(9, k: 3)

      def forward(*args) = sink(*args)
      p forward(9, k: 3)
    RUBY

    _(result).must_answer <<~'OUT'
      [9, {k: 3}]
      [9, [{k: 3}], 2, {}]
    OUT
  end

  it "subclass sees only the calls ruby makes" do
    result = ze0(<<~'RUBY')
      # Which of Hash's own methods its methods call on a subclass: every
      # method Hash defines is wrapped to log a call made from inside another,
      # and each is then called once on a fresh receiver. CRuby calls one by
      # dispatch only where it means to, and ze0's core, written in Ruby, has
      # to call no more and no fewer. Written by `rake gen:dispatch`.

      class Probe < Hash
        CALLING = []
        LOG = []
        [:<, :<=, :==, :>, :>=, :[], :[]=, :all?, :any?, :assoc, :chain, :chunk, :chunk_while, :clear, :collect, :collect_concat, :compact, :compact!, :compare_by_identity, :compare_by_identity?, :count, :cycle, :deconstruct_keys, :default, :default=, :default_proc, :default_proc=, :delete, :delete_if, :detect, :dig, :drop, :drop_while, :each, :each_cons, :each_entry, :each_key, :each_pair, :each_slice, :each_value, :each_with_index, :each_with_object, :empty?, :entries, :eql?, :except, :fetch, :fetch_values, :filter, :filter!, :filter_map, :find, :find_all, :find_index, :first, :flat_map, :flatten, :freeze, :grep, :grep_v, :group_by, :has_key?, :has_value?, :hash, :include?, :initialize_copy, :inject, :inspect, :invert, :keep_if, :key, :key?, :keys, :lazy, :length, :map, :max, :max_by, :member?, :merge, :merge!, :min, :min_by, :minmax, :minmax_by, :none?, :one?, :partition, :rassoc, :reduce, :rehash, :reject, :reject!, :replace, :reverse_each, :select, :select!, :shift, :size, :slice, :slice_after, :slice_before, :slice_when, :sort, :sort_by, :store, :sum, :take, :take_while, :tally, :to_a, :to_h, :to_hash, :to_proc, :to_s, :to_set, :transform_keys, :transform_keys!, :transform_values, :transform_values!, :uniq, :update, :value?, :values, :values_at, :zip].each do |m|
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
        r = Probe.new.tap { |h| h[:a] = 1; h[:b] = 2 }
        Probe::LOG.clear
        begin
          yield r
        rescue StandardError => e
          Probe::LOG << "raised #{e.class}"
        end
        puts "#{name}: #{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
      end

      call("<") { |r| r.__send__(:<, {a: 1}) { |*x| x.first } }
      call("<=") { |r| r.__send__(:<=, {a: 1}) { |*x| x.first } }
      call("==") { |r| r.__send__(:==, 1) { |*x| x.first } }
      call(">") { |r| r.__send__(:>, {a: 1}) { |*x| x.first } }
      call(">=") { |r| r.__send__(:>=, {a: 1}) { |*x| x.first } }
      call("[]") { |r| r.__send__(:[], 1) { |*x| x.first } }
      call("[]=") { |r| r.__send__(:[]=, 0, 1) { |*x| x.first } }
      call("all?") { |r| r.all?() { |*x| x.first } }
      call("any?") { |r| r.any?() { |*x| x.first } }
      call("assoc") { |r| r.assoc(1) { |*x| x.first } }
      call("chain") { |r| r.chain() { |*x| x.first } }
      call("chunk") { |r| r.chunk() { |*x| x.first } }
      call("chunk_while") { |r| r.chunk_while() { |*x| x.first } }
      call("clear") { |r| r.clear() { |*x| x.first } }
      call("collect") { |r| r.collect() { |*x| x.first } }
      call("collect_concat") { |r| r.collect_concat() { |*x| x.first } }
      call("compact") { |r| r.compact() { |*x| x.first } }
      call("compact!") { |r| r.compact!() { |*x| x.first } }
      call("compare_by_identity") { |r| r.compare_by_identity() { |*x| x.first } }
      call("compare_by_identity?") { |r| r.compare_by_identity?() { |*x| x.first } }
      call("count") { |r| r.count() { |*x| x.first } }
      call("deconstruct_keys") { |r| r.deconstruct_keys(1) { |*x| x.first } }
      call("default") { |r| r.default() { |*x| x.first } }
      call("default=") { |r| r.__send__(:default=, 1) { |*x| x.first } }
      call("default_proc") { |r| r.default_proc() { |*x| x.first } }
      call("default_proc=") { |r| r.__send__(:default_proc=, :a) { |*x| x.first } }
      call("delete") { |r| r.delete(1) { |*x| x.first } }
      call("delete_if") { |r| r.delete_if() { |*x| x.first } }
      call("detect") { |r| r.detect() { |*x| x.first } }
      call("dig") { |r| r.dig(1) { |*x| x.first } }
      call("drop") { |r| r.drop(1) { |*x| x.first } }
      call("drop_while") { |r| r.drop_while() { |*x| x.first } }
      call("each") { |r| r.each() { |*x| x.first } }
      call("each_cons") { |r| r.each_cons(1) { |*x| x.first } }
      call("each_entry") { |r| r.each_entry() { |*x| x.first } }
      call("each_key") { |r| r.each_key() { |*x| x.first } }
      call("each_pair") { |r| r.each_pair() { |*x| x.first } }
      call("each_slice") { |r| r.each_slice(1) { |*x| x.first } }
      call("each_value") { |r| r.each_value() { |*x| x.first } }
      call("each_with_index") { |r| r.each_with_index() { |*x| x.first } }
      call("each_with_object") { |r| r.each_with_object(1) { |*x| x.first } }
      call("empty?") { |r| r.empty?() { |*x| x.first } }
      call("entries") { |r| r.entries() { |*x| x.first } }
      call("eql?") { |r| r.eql?(1) { |*x| x.first } }
      call("except") { |r| r.except() { |*x| x.first } }
      call("fetch") { |r| r.fetch(1) { |*x| x.first } }
      call("fetch_values") { |r| r.fetch_values() { |*x| x.first } }
      call("filter") { |r| r.filter() { |*x| x.first } }
      call("filter!") { |r| r.filter!() { |*x| x.first } }
      call("filter_map") { |r| r.filter_map() { |*x| x.first } }
      call("find") { |r| r.find() { |*x| x.first } }
      call("find_all") { |r| r.find_all() { |*x| x.first } }
      call("find_index") { |r| r.find_index() { |*x| x.first } }
      call("first") { |r| r.first() { |*x| x.first } }
      call("flat_map") { |r| r.flat_map() { |*x| x.first } }
      call("flatten") { |r| r.flatten() { |*x| x.first } }
      call("grep") { |r| r.grep(1) { |*x| x.first } }
      call("grep_v") { |r| r.grep_v(1) { |*x| x.first } }
      call("group_by") { |r| r.group_by() { |*x| x.first } }
      call("has_key?") { |r| r.has_key?(1) { |*x| x.first } }
      call("has_value?") { |r| r.has_value?(1) { |*x| x.first } }
      call("hash") { |r| r.hash() { |*x| x.first } }
      call("include?") { |r| r.include?(1) { |*x| x.first } }
      call("initialize_copy") { |r| r.initialize_copy({a: 1}) { |*x| x.first } }
      call("inject") { |r| r.inject() { |*x| x.first } }
      call("inspect") { |r| r.inspect() { |*x| x.first } }
      call("invert") { |r| r.invert() { |*x| x.first } }
      call("keep_if") { |r| r.keep_if() { |*x| x.first } }
      call("key") { |r| r.key(1) { |*x| x.first } }
      call("key?") { |r| r.key?(1) { |*x| x.first } }
      call("keys") { |r| r.keys() { |*x| x.first } }
      call("lazy") { |r| r.lazy() { |*x| x.first } }
      call("length") { |r| r.length() { |*x| x.first } }
      call("map") { |r| r.map() { |*x| x.first } }
      call("max") { |r| r.max() }
      call("max_by") { |r| r.max_by() { |*x| x.first } }
      call("member?") { |r| r.member?(1) { |*x| x.first } }
      call("merge") { |r| r.merge() { |*x| x.first } }
      call("merge!") { |r| r.merge!() { |*x| x.first } }
      call("min") { |r| r.min() }
      call("min_by") { |r| r.min_by() { |*x| x.first } }
      call("minmax") { |r| r.minmax() }
      call("minmax_by") { |r| r.minmax_by() { |*x| x.first } }
      call("none?") { |r| r.none?() { |*x| x.first } }
      call("one?") { |r| r.one?() { |*x| x.first } }
      call("partition") { |r| r.partition() { |*x| x.first } }
      call("rassoc") { |r| r.rassoc(1) { |*x| x.first } }
      call("reduce") { |r| r.reduce() { |*x| x.first } }
      call("rehash") { |r| r.rehash() { |*x| x.first } }
      call("reject") { |r| r.reject() { |*x| x.first } }
      call("reject!") { |r| r.reject!() { |*x| x.first } }
      call("replace") { |r| r.replace({a: 1}) { |*x| x.first } }
      call("reverse_each") { |r| r.reverse_each() { |*x| x.first } }
      call("select") { |r| r.select() { |*x| x.first } }
      call("select!") { |r| r.select!() { |*x| x.first } }
      call("shift") { |r| r.shift() { |*x| x.first } }
      call("size") { |r| r.size() { |*x| x.first } }
      call("slice") { |r| r.slice() { |*x| x.first } }
      call("slice_after") { |r| r.slice_after() { |*x| x.first } }
      call("slice_before") { |r| r.slice_before() { |*x| x.first } }
      call("slice_when") { |r| r.slice_when() { |*x| x.first } }
      call("sort") { |r| r.sort() }
      call("sort_by") { |r| r.sort_by() { |*x| x.first } }
      call("store") { |r| r.store(0, 1) { |*x| x.first } }
      call("sum") { |r| r.sum([1, 2]) { |*x| x.first } }
      call("take") { |r| r.take(1) { |*x| x.first } }
      call("take_while") { |r| r.take_while() { |*x| x.first } }
      call("tally") { |r| r.tally() { |*x| x.first } }
      call("to_a") { |r| r.to_a() { |*x| x.first } }
      call("to_h") { |r| r.to_h() }
      call("to_hash") { |r| r.to_hash() { |*x| x.first } }
      call("to_proc") { |r| r.to_proc() { |*x| x.first } }
      call("to_s") { |r| r.to_s() { |*x| x.first } }
      call("to_set") { |r| r.to_set() { |*x| x.first } }
      call("transform_keys") { |r| r.transform_keys() { |*x| x.first } }
      call("transform_keys!") { |r| r.transform_keys!() { |*x| x.first } }
      call("transform_values") { |r| r.transform_values() { |*x| x.first } }
      call("transform_values!") { |r| r.transform_values!() { |*x| x.first } }
      call("uniq") { |r| r.uniq() { |*x| x.first } }
      call("update") { |r| r.update() { |*x| x.first } }
      call("value?") { |r| r.value?(1) { |*x| x.first } }
      call("values") { |r| r.values() { |*x| x.first } }
      call("values_at") { |r| r.values_at() { |*x| x.first } }
      call("zip") { |r| r.zip() { |*x| x.first } }

    RUBY

    _(result).must_answer <<~'OUT'
      []: []->default
      all?: all?->each
      collect: collect->each
      collect_concat: collect_concat->each
      count: count->each
      detect: detect->each
      dig: dig->default
      drop: drop->each
      drop_while: drop_while->each
      each_cons: each_cons->size each_cons->each
      each_entry: each_entry->each
      each_slice: each_slice->size each_slice->each
      each_with_index: each_with_index->each
      each_with_object: each_with_object->each
      entries: entries->each
      filter_map: filter_map->each
      find: find->each
      find_all: find_all->each
      find_index: find_index->each
      first: first->each
      flat_map: flat_map->each
      grep: grep->each
      grep_v: grep_v->each
      group_by: group_by->each
      initialize_copy: raised NoMethodError
      inject: inject->each
      map: map->each
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
      reverse_each: reverse_each->each
      sort: sort->each
      sort_by: sort_by->each
      sum: sum->each
      take: take->each
      take_while: take_while->each
      tally: tally->each
      to_set: to_set->each_entry each_entry->each
      uniq: uniq->each
      zip: zip->each
    OUT
  end

  it "super missing hash slot" do
    result = ze0(<<~'RUBY')
      class Rec
        def as_json
          h = super
          h[:x] = 1
          h
        end
      end
      begin
        puts Rec.new.as_json.length
      rescue NoMethodError => e
        puts "raised"
        puts e.message.include?("as_json")
      end
    RUBY

    _(result).must_answer <<~'OUT'
      raised
      true
    OUT
  end

  it "thread value hash tail" do
    result = ze0(<<~'RUBY')
      # The tail expression of a Thread body is boxed into the thread's yielded_value
      # through an open/close pair that knew the scalars, the arrays and the objects
      # and NOT the hashes -- so a body whose value is a Hash#each emitted a bare
      # assignment from sp_StrIntHash * with an unbalanced close paren after it
      # (#4081). The generic boxer handles every kind, which is what the by-value
      # struct tail had already needed (#3587).
      t1 = Thread.new { { "a" => 1 }.each { |w, n| } }
      p t1.value.class

      t2 = Thread.new { { 1 => "a" }.each_pair { |k, v| } }
      p t2.value.class

      t3 = Thread.new { { "a" => 1 } }
      p t3.value.class

      # the kinds that already worked
      t4 = Thread.new { [1, 2].each { |x| } }
      p t4.value.class
      t5 = Thread.new { (1..3).each { |x| } }
      p t5.value.class
      t6 = Thread.new { "abc" }
      p t6.value
      t7 = Thread.new { [1, 2] }
      p t7.value
      t8 = Thread.new { 42 }
      p t8.value

      # a trailing expression after the each, which was the reported workaround
      t9 = Thread.new { { "a" => 1 }.each { |w, n| }; 7 }
      p t9.value
    RUBY

    _(result).must_answer <<~'OUT'
      Hash
      Hash
      Hash
      Array
      Range
      "abc"
      [1, 2]
      42
      7
    OUT
  end

  it "trailing keywords become a positional hash when the callee has no keyword params" do
    result = ze0(<<~'RUBY')
      # Ruby's keywords-to-positional-hash conversion, still true in 3+: with
      # no keyword params and no `**kwrest` declared, trailing keywords are
      # not keywords at all -- they are one positional Hash. This is what
      # makes the classic options-hash idiom work, and it was raising
      # `unknown keyword: :a` for a method that has no keywords to be
      # unknown. A callee that DOES declare keywords keeps the real check.

      def m(opts = {}); opts; end
      p m(a: 1, b: 2)
      p m({a: 1})
      p m
      class C
        def initialize(opts = {}); @o = opts; end
        attr_reader :o
      end
      p C.new(a: 1).o
      def k(x:); x; end
      begin
        k(x: 1, zz: 2)
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2}
      {a: 1}
      {}
      {a: 1}
      ArgumentError: unknown keyword: :zz
    OUT
  end

  it "transform keys symproc" do
    result = ze0(<<~'RUBY')
      # Hash#transform_keys whose block changes the key to a Symbol must produce a
      # symbol-keyed hash, not keep the receiver's string-keyed variant.
      #
      # `{ "a" => 1 }.transform_keys(&:to_sym)` inferred the result as the receiver's
      # type (there is no sym-scalar hash variant, so ty_hash_of(Symbol, Int) was
      # UNKNOWN and fell back to the string-keyed receiver type), then emitted a
      # string-keyed hash and passed the transformed sp_sym key to a const char *
      # setter -- an incompatible-pointer C error. Symbol keys yield a SymPolyHash.

      # 1. String keys -> symbols (int and string values).
      p({ "a" => 1, "b" => 2 }.transform_keys(&:to_sym))      #=> {a: 1, b: 2}
      p({ "a" => "x", "b" => "y" }.transform_keys(&:to_sym))  #=> {a: "x", b: "y"}

      # 2. Symbol keys -> strings.
      p({ a: 1, b: 2 }.transform_keys(&:to_s))                #=> {"a" => 1, "b" => 2}

      # 3. Integer keys -> strings.
      p({ 1 => "a", 2 => "b" }.transform_keys(&:to_s))        #=> {"1" => "a", "2" => "b"}

      # 4. An explicit block still works.
      p({ "a" => 1 }.transform_keys { |k| k.upcase })         #=> {"A" => 1}

      # 5. Through a method param.
      def tk(h) = h.transform_keys(&:to_sym)
      p tk({ "x" => 10, "y" => 20 })                          #=> {x: 10, y: 20}

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2}
      {a: "x", b: "y"}
      {"a" => 1, "b" => 2}
      {"1" => "a", "2" => "b"}
      {"A" => 1}
      {x: 10, y: 20}
      done
    OUT
  end

  it "uniq user eql hash" do
    result = ze0(<<~'RUBY')
      # Array#uniq dedups by the user-defined eql?/hash (like CRuby), not by identity;
      # a class without eql? still dedups by identity, and == is unaffected.
      class P
        attr_reader :n
        def initialize(n); @n = n; end
        def eql?(o); o.is_a?(P) && n == o.n; end
        def hash; n.hash; end
      end
      p [P.new(1), P.new(1)].uniq.size
      p [P.new(1), P.new(2), P.new(1)].uniq.size
      p [P.new(1), P.new(1)].uniq.map(&:n)
      class Q
        def initialize(n); @n = n; end
      end
      p [Q.new(1), Q.new(1)].uniq.size
      a = P.new(5)
      p [a, a].uniq.size
      p(P.new(1) == P.new(1))
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      [1]
      2
      1
      false
    OUT
  end

  it "value subclass of hash with super initialize" do
    result = ze0(<<~'RUBY')
      # A `Hash` subclass with a `super` in `initialize` (D3): `super(0)` seeds the
      # default value on the payload, and inherited `[]`/`[]=`/`size` work.

      class Counter < Hash
        def initialize
          super(0)
        end
        def bump(k); self[k] += 1; end
      end
      c = Counter.new
      c.bump(:a); c.bump(:a); c.bump(:b)
      puts c[:a]
      puts c[:b]
      puts c[:missing]
      p c
      puts c.class
      puts c.size
    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      0
      {a: 2, b: 1}
      Counter
      2
    OUT
  end

  it "value type hash id" do
    result = ze0(<<~'RUBY')
      a = Complex(2, 3)
      p(a.hash == a.hash)
      p(a.hash == Complex(2, 3).hash)
      r = (1..3)
      p(r.hash == r.hash)
      p a.object_id.is_a?(Integer)
      require 'set'
      s = Set[1, 2, 3]
      p(s.hash == s.hash)
      class C; end
      c = C.new
      p(c.hash == c.hash)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
    OUT
  end
end
