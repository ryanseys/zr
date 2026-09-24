# frozen_string_literal: true

require "spec_helper"

describe "String: frozen literals" do
  it "array frozen slice bang" do
    result = zr(<<~'RUBY')
      # Array#slice! must raise FrozenError on a frozen array (Gemini
      # follow-up to #1029: slice! was the remaining unguarded mutator).
      a = [1, 2, 3]
      a.freeze
      begin
        a.slice!(0, 1)
        puts "BUG: no raise"
      rescue FrozenError
        puts "int slice!"
      end

      s = ["a", "b", "c"]
      s.freeze
      begin
        s.slice!(1, 1)
        puts "BUG: no raise"
      rescue FrozenError
        puts "str slice!"
      end
    RUBY

    _(result).must_answer "int slice!\nstr slice!\n"
  end

  it "follows the magic comment rules" do
    result = zr(<<~'RUBY')
      # frozen-string-literal: TRUE
      # The magic comment reads as CRuby reads it: `-` and `_` alike, and the
      # value in any case. Adjacent strings and a heredoc with no
      # interpolation are literals too; an interpolated string is not.
      p "x".frozen?
      p ("a" "b").frozen?
      p <<~HEREDOC.frozen?
        heredoc
      HEREDOC
      p "i#{1}".frozen?
      p "same".equal?("same")
      p __FILE__.frozen?
      p %w[a b].all?(&:frozen?)

    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      true
      true
      true
    OUT
  end

  it "frozen string double shovel" do
    result = zr(<<~'RUBY')
      s001 = +"x"; s001.freeze
      p(begin; s001 << "y"; rescue FrozenError => e001; e001.receiver; end)
      p(begin; s001 << "y"; rescue FrozenError => e002; e002.receiver; end)
      s2 = +"a"; s2 << "b"; p s2
      s3 = "c".dup; s3.freeze; r3 = (begin; s3 << "d"; rescue FrozenError; :fz; end); p r3
      p s3.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      "x"
      "x"
      "ab"
      :fz
      true
    OUT
  end

  it "frozen string global survives gc" do
    result = zr(<<~'RUBY')
      # A heap string frozen by .freeze and bound to a constant is rooted via
      # sp_mark_user_globals, but the string-pool sweeper (sp_str_sweep) only kept
      # 0xfc-marked strings and freed the frozen (0xf1) one -- a GC use-after-free
      # on the next collect. Frozen globals must survive collection. (#1449)
      VERSION = "0.8.0".freeze
      NAME = ("spinel-" + "rt").freeze
      GC.start
      GC.start
      sum = 0.0
      i = 0
      while i < 50000
        a = [1.0, 2.0, 3.0, 4.0]
        sum += a[0]
        i += 1
      end
      GC.start
      puts VERSION
      puts NAME
      puts(sum > 0.0)
    RUBY

    _(result).must_answer <<~'OUT'
      0.8.0
      spinel-rt
      true
    OUT
  end

  it "frozen string literal default" do
    result = zr(<<~'RUBY')
      # fsl-true is Spinel's DEFAULT (no pragma in this file): literals are frozen,
      # mutation raises, and +"" / String.new / interpolation give mutable strings
      # that keep the full shared-mutation semantics.
      p "lit".frozen?
      s = "m"
      begin
        s << "!"
        puts "BUG: no raise"
      rescue FrozenError => e
        puts e.message
      end

      m = +"base"
      t = m
      m << "!"
      p t
      p m.equal?(t)

      n = String.new("n")
      arr = [n]
      n.upcase!
      p arr[0]

      who = "world"
      i = "hello #{who}"
      i << "!"
      p i
    RUBY

    _(result).must_answer <<~'OUT'
      false
      BUG: no raise
      "base!"
      true
      "N"
      "hello world!"
    OUT
  end

  it "frozen string literal gc root" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      first = "first literal"
      second = "second literal"

      GC.start

      puts first
      puts second
    RUBY

    _(result).must_answer "first literal\nsecond literal\n"
  end

  it "frozen string literal per file" do
    result = zr(<<~'RUBY', files: beside("frozen_literal/helper_frozen.rb", "frozen_literal/helper_plain.rb"))
      # Per-file frozen_string_literal: each literal carries its OWN file's pragma,
      # not the entry file's. helper_frozen.rb has the pragma; this entry file and
      # helper_plain.rb do not.
      require_relative "frozen_literal/helper_frozen"
      require_relative "frozen_literal/helper_plain"

      p frozen_helper_lit.frozen?   # true  -- literal from the pragma file
      p plain_helper_lit.frozen?    # false -- literal from a plain file
      p "entry lit".frozen?         # false -- entry has no pragma

      # mutating a pragma-file literal raises even when called from a plain file
      begin
        frozen_helper_mutate
        puts "BUG: no raise"
      rescue FrozenError => e
        puts e.message
      end

      # a plain-file literal stays mutable
      p plain_helper_build
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      can't modify frozen String: "helper buf"
      "plain!"
    OUT
  end

  it "frozen string literal per file rev" do
    result = zr(<<~'RUBY', files: beside("frozen_literal/helper_plain.rb"))
      # frozen_string_literal: true
      # Reverse direction: pragma entry + plain helper. The helper's literals stay
      # unfrozen and mutable; the entry's literals are frozen.
      require_relative "frozen_literal/helper_plain"

      p "entry lit".frozen?         # true
      p plain_helper_lit.frozen?    # false
      p plain_helper_build          # helper literals stay mutable
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      "plain!"
    OUT
  end

  it "frozen string literal pragma" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true
      # With the magic comment, string literals are frozen: frozen? is true and
      # mutation raises FrozenError (including through the mutable-string-buffer
      # optimization, which is disabled for pragma literals).
      def s(x); x; end

      p "abc".frozen?            # true
      p s("via method").frozen?  # true -- literal stays frozen through a call
      x = "local"
      p x.frozen?                # true
      p "interp #{1 + 1}".frozen?  # false -- interpolation builds a new string
      p "".frozen?               # true -- empty literal
      p :sym.frozen?             # true (symbols always)
      p [1, 2].frozen?           # false (array literal not affected by the pragma)

      # dup produces an unfrozen copy
      p "abc".dup.frozen?        # false

      # mutating a frozen literal raises; without the pragma this local would take
      # the in-place string-buffer path
      buf = "abc"
      begin
        buf << "y"
        puts "BUG: << did not raise"
      rescue FrozenError => e
        puts e.message
      end

      # a dup'd copy mutates freely
      cpy = "abc".dup
      cpy << "y"
      p cpy

      # synthesized strings are not literals: Symbol#to_s and Integer#to_s stay
      # unfrozen under the pragma
      p :sym.to_s.frozen?        # false
      p 42.to_s.frozen?          # false
      p __FILE__.frozen?         # true -- __FILE__ is a literal of its file
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      true
      true
      false
      false
      can't modify frozen String: "abc"
      "abcy"
      false
      false
      true
    OUT
  end

  it "frozen string literal pragma freezes literals" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true
      p "abc".frozen?
      p "interp #{1 + 1}".frozen?
      p "abc".dup.frozen?
      buf = "abc"
      begin; buf << "y"; rescue FrozenError => e; puts e.message; end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      can't modify frozen String: "abc"
    OUT
  end

  it "frozen strings" do
    result = zr(<<~'RUBY')
      # Frozen strings: `-@`/`#dedup` interning and the frozen-mutation guard.

      # `-@` / `#dedup` intern by content: equal contents share one immortal frozen
      # object.
      p((-"hello").equal?(-"hello"))                 # true
      p("a".dedup.equal?("a".dedup))                 # true
      p(("he" + "llo").dedup.equal?("hello".dedup))  # true -- computed content interns

      # `-@` on an already-frozen string returns the receiver itself.
      a = "abc".freeze
      p((-a).equal?(a))                              # true

      # Different content interns to different objects.
      p((-"x").equal?(-"y"))                         # false
      p((-"frozen").frozen?)                         # true

      # Byte length counts real bytes, including an embedded NUL (nothing truncates).
      nul = "a\u0000b"
      p nul.bytesize                                 # 3
      p nul.dedup.bytesize                           # 3
      p("a\u0000b".dedup.equal?("a\u0000b".dedup))   # true

      # A frozen string raises on in-place mutation.
      begin
        (-"immutable") << "!"
      rescue FrozenError => e
        puts e.message                               # can't modify frozen String: "immutable"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      false
      true
      3
      3
      true
      can't modify frozen String: "immutable"
    OUT
  end

  it "hash string key snapshot" do
    result = zr(<<~'RUBY')
      # A String KEY is snapshotted on store: the hash keeps a frozen copy, so
      # mutating the string you stored under can never rewrite a key already in the
      # table. A stored VALUE is the opposite -- the shared handle, mutable through
      # the hash. Both halves matter, so both are asserted here.

      # --- the snapshot, through every way a key gets in ---------------------------
      k = "key"

      literal = { k => 1 }
      assign = {}
      assign[k] = 1
      stored = {}
      stored.store(k, 1)
      merged = {}.merge(k => 1)
      built = [[k, 1]].to_h
      bracketed = Hash[k, 1]
      folded = [k].each_with_object({}) { |s, h| h[s] = 1 }

      k << "-mut"

      p literal.keys, assign.keys, stored.keys, merged.keys
      p built.keys, bracketed.keys, folded.keys
      p k

      # The copy is frozen; the caller's string is untouched.
      h = {}
      s = "fresh"
      h[s] = 1
      p h.keys.first.frozen?
      p s.frozen?
      p h.keys.first.equal?(s)

      # An already-frozen key needs no copy -- it is stored as-is.
      f = "immutable".freeze
      h2 = { f => 1 }
      p h2.keys.first.equal?(f)

      # Lookup still works by content after the caller mutates its own string.
      h3 = {}
      name = "ada"
      h3[name] = 1
      name << "!"
      p h3["ada"]
      p h3["ada!"]
      p h3.size

      # --- the copy carries the key's own encoding, not a UTF-8 reinterpretation ---
      bin = "caf\xC3\xA9".b
      h4 = { bin => :binary }
      p h4.keys.first.encoding
      p h4.keys.first.bytes
      p h4.keys.first == bin

      # --- identity keying keeps YOUR object: its identity IS the key --------------
      h5 = {}.compare_by_identity
      id_key = "same"
      h5[id_key] = 1
      h5["same"] = 2
      p h5.size
      p h5.keys.first.equal?(id_key)
      p h5.keys.first.frozen?

      # --- VALUES stay shared: mutation through the hash is visible ----------------
      v = { k: "value" }
      v[:k] << "!"
      p v[:k]
      shared = "outer"
      v[:s] = shared
      v[:s].upcase!
      p shared
      p v[:s].frozen?

      # --- non-String keys are stored as-is ----------------------------------------
      arr = [1, 2]
      h6 = { arr => :a }
      arr << 3
      p h6.keys
      p h6.keys.first.equal?(arr)

      # --- dup/clone of a hash keep the frozen keys, no re-copy --------------------
      h7 = { "d" => 1 }
      p h7.dup.keys.first.equal?(h7.keys.first)
      p h7.clone.keys.first.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      ["key"]
      ["key"]
      ["key"]
      ["key"]
      ["key"]
      ["key"]
      ["key"]
      "key-mut"
      true
      false
      false
      true
      1
      nil
      1
      #<Encoding:BINARY (ASCII-8BIT)>
      [99, 97, 102, 195, 169]
      true
      2
      true
      false
      "value!"
      "OUTER"
      false
      [[1, 2, 3]]
      true
      true
      true
    OUT
  end

  it "interned literals" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true
      # Frozen literals and symbols live in the binary's data section and keep
      # their identity across uses.
      A = "shared literal"
      B = "shared literal"
      puts A.frozen?, A.equal?(B)
      SYMS = %i[alpha beta gamma].freeze
      p SYMS
      p SYMS.map(&:to_s).map(&:frozen?)
      p :alpha.equal?("alpha".to_sym)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      [:alpha, :beta, :gamma]
      [false, false, false]
      true
    OUT
  end

  it "is not deduplicated" do
    result = zr(<<~'RUBY')
      # `"lit".freeze` on a string LITERAL answers the interned fstring, so two of
      # them are the SAME object -- and CRuby REFUSES a singleton on one.
      #
      # The two halves ship together on purpose. Interning without the refusal would
      # let a program attach a singleton to a string another part of the program is
      # also holding, which is worse than the divergence it fixes.
      #
      # The rule is a COMPILE-TIME one about the literal RECEIVER, not about
      # `String#freeze`: CRuby compiles `<string literal>.freeze` to
      # `opt_str_freeze`, which answers the fstring table's entry. Freezing a string
      # that arrived any other way (`s = +"x"; s.freeze`) allocates nothing and
      # dedups nothing, on both engines.
      #
      # zr already had the pool -- `String#-@` interns and `-"lit"` was correct --
      # so the fold routes a literal `.freeze` into the same entry the
      # `# frozen_string_literal: true` path already uses. It is guarded on `freeze`
      # not being reopened, exactly as CRuby guards `opt_str_freeze` on its own
      # redefinition flag.
      #
      # The refusal asks by object IDENTITY, not by a flag: the pool holds one
      # string per (bytes, encoding), so being interned means being THAT object.
      # All three singleton-CREATING surfaces refuse; the reading ones do not.
      p "lit".freeze.equal?("lit".freeze)
      p (-"lit").equal?(-"lit")
      p "lit".freeze.frozen?

      s = +"built"
      s.freeze
      p s.equal?("built".freeze)

      begin
        "lit".freeze.singleton_class
      rescue => e
        p [e.class, e.message]
      end

      t = +"unshared"
      t.freeze
      p t.singleton_class.equal?(t.singleton_class)

      # The sweep.

      # All three singleton-creating surfaces refuse; reading ones answer.
      f = "shared".freeze
      [[:singleton_class, -> { f.singleton_class }],
       [:define_singleton_method, -> { f.define_singleton_method(:x) { 1 } }],
       [:extend, -> { f.extend(Module.new) }],
       [:singleton_methods, -> { f.singleton_methods }],
       [:dup_then_singleton, -> { f.dup.singleton_class }]].each do |name, probe|
        begin
          p [name, probe.call.class]
        rescue => e
          p [name, e.class, e.message]
        end
      end

      # An interpolated literal is a fresh string every time: nothing to intern.
      x = 1
      p ["a#{x}b".freeze.equal?("a#{x}b".freeze), "a#{x}b".freeze.frozen?]

      # The fold answers the same object `-@` does -- one pool, not two.
      p "pool".freeze.equal?(-"pool")
      p "pool".freeze.equal?("pool".dup.freeze)

      # Mutating an fstring raises, and names it.
      begin
        "immutable".freeze << "x"
      rescue => e
        p [e.class, e.message]
      end

      # An empty literal and a literal holding a NUL byte both intern by content.
      p ["".freeze.equal?("".freeze), "a\0b".freeze.equal?("a\0b".freeze)]

      # Equal content in DIFFERENT encodings is not the same object.
      p "enc".freeze.equal?("enc".dup.force_encoding("ASCII-8BIT").freeze)

      # A frozen literal is still `==` to an unfrozen twin.
      p ["eq".freeze == +"eq", "eq".freeze.eql?(+"eq")]

    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      [TypeError, "can't define singleton"]
      true
      [:singleton_class, TypeError, "can't define singleton"]
      [:define_singleton_method, TypeError, "can't define singleton"]
      [:extend, TypeError, "can't define singleton"]
      [:singleton_methods, Array]
      [:dup_then_singleton, Class]
      [false, true]
      true
      false
      [FrozenError, "can't modify frozen String: \"immutable\""]
      [true, true]
      false
      [true, true]
    OUT
  end

  it "is one shared string" do
    result = zr(<<~'RUBY')
      # `"lit".freeze` at any site answers the one frozen String the fstring
      # table holds for those bytes, as -"lit" and String#dedup do: the core
      # rows ruby defines on String itself leave the literal fast path alone.
      p "lit".freeze.equal?("lit".freeze), (-"lit").equal?(-"lit"), (-"lit").equal?("lit".freeze), "x".dedup.equal?("x".freeze)
      p nil === nil, [1].freeze.frozen?, "a".freeze.frozen?

    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "nil string receiver raises" do
    result = zr(<<~'RUBY')
      v = ENV["NO_SUCH_1664"]
      begin; v.length; rescue NoMethodError => e; puts "length: #{e.message}"; end
      begin; v.upcase; rescue NoMethodError => e; puts "upcase: #{e.message}"; end
      begin; v.split(","); rescue NoMethodError => e; puts "split: #{e.message}"; end
      begin; v[0]; rescue NoMethodError => e; puts "slice: #{e.message}"; end
      begin; v.empty?; rescue NoMethodError => e; puts "empty?: #{e.message}"; end
      begin; v.include?("x"); rescue NoMethodError => e; puts "include?: #{e.message}"; end
      begin; v + "x"; rescue NoMethodError => e; puts "plus: #{e.message}"; end
      begin; "x" + v; rescue TypeError => e; puts "plus_nil_arg: TypeError"; end
      begin; v.to_str; rescue NoMethodError => e; puts "to_str: #{e.message}"; end
      begin; v.strip; rescue NoMethodError => e; puts "strip: #{e.message}"; end
      begin; v.index("x"); rescue NoMethodError => e; puts "index: #{e.message}"; end
      begin; v.chars; rescue NoMethodError => e; puts "chars: #{e.message}"; end
      puts v.to_s.inspect
      puts v.to_i
      puts v.dup.nil?
      puts v.frozen?
      puts v.inspect
      a = ["a", v, "b"]
      puts a.join("-")
    RUBY

    _(result).must_answer <<~'OUT'
      length: undefined method 'length' for nil
      upcase: undefined method 'upcase' for nil
      split: undefined method 'split' for nil
      slice: undefined method '[]' for nil
      empty?: undefined method 'empty?' for nil
      include?: undefined method 'include?' for nil
      plus: undefined method '+' for nil
      plus_nil_arg: TypeError
      to_str: undefined method 'to_str' for nil
      strip: undefined method 'strip' for nil
      index: undefined method 'index' for nil
      chars: undefined method 'chars' for nil
      ""
      0
      true
      true
      nil
      a--b
    OUT
  end

  it "short strings live in their cell" do
    result = zr(<<~'RUBY')
      # A String of up to 87 bytes keeps them in its own cell; growing past
      # that moves them to a buffer, and every way of writing keeps the
      # bytes right across the move and back.
      s = +"a" * 80
      s << "b" * 20
      puts s.size, s[78, 5]
      s.replace("short")
      puts s, s.size
      s << "x" * 200
      puts s.size, s[-3..]
      s.replace("tiny")
      puts s.dup, s.clone.frozen?, s.dup << "!"
      t = s.dup
      t[1, 2] = "ZZZZZZZZZZ" * 10
      puts t.size, t[0, 4], s
      u = +"seed"
      100.times { |i| u.append_as_bytes(i.chr) }
      puts u.bytesize, u.getbyte(4), u.getbyte(103)
      v = String.new("abc", capacity: 500)
      v << "d" * 90
      puts v.size, v.encoding
      w = "".dup
      w.replace(w)
      puts w.inspect
      x = "abc".dup
      x.replace(x)
      x.insert(1, "Z" * 100)
      puts x.size, x[0, 3], x[-2..]
      y = ("k" * 50).freeze
      puts y.frozen?, y.dup.size, (y + y).size, (y + y + y).size
      z = 3.times.map { |i| "row #{i}" * 20 }
      puts z.map(&:size).inspect, z[2][0, 5]
      require "objspace"
      puts ObjectSpace.memsize_of("x") <= ObjectSpace.memsize_of("x" * 1000)
      puts ObjectSpace.memsize_of("x" * 1000) > 1000

    RUBY

    _(result).must_answer <<~'OUT'
      100
      aabbb
      short
      5
      205
      xxx
      tiny
      false
      tiny!
      102
      tZZZ
      tiny
      104
      0
      99
      93
      UTF-8
      ""
      103
      aZZ
      bc
      true
      50
      100
      150
      [100, 100, 100]
      row 2
      true
      true
    OUT
  end

  it "str method nil arg no segv" do
    result = zr(<<~'RUBY')
      # #504. Several String methods receiving the wrong arg shape used
      # to SEGV. CRuby raises ArgumentError; spinel can't raise but we
      # should at least not crash. Codegen emits compile_arg0 -> "0"
      # (NULL) for missing args and the runtime helpers then ran
      # strlen(NULL) or worse.
      #
      # Fix: NULL guards in sp_str_count / sp_str_delete /
      # sp_str_rindex / sp_str_concat; setbyte (which would have
      # written through a read-only string literal) is now warned and
      # returns 0 without mutating; rindex with a regex arg routes
      # through the new sp_re_rindex helper instead of the plain
      # string-substring path; `<<` on a string return-types as
      # `string` instead of falling through to the catch-all `int`.

      # count / rindex / include? / start_with? / end_with? with no arg
      # (NULL at C level): spinel now raises TypeError, matching CRuby's
      # nil-arg path more closely than the old silent sentinel return.
      begin
        "foo".count
        puts "BUG count: no raise"
      rescue TypeError => e
        puts "count: #{e.message}"
      end
      p "foo".delete   # CRuby: ArgumentError. spinel: "foo" unchanged (was: SEGV)
      p "foo".rindex(/missing/)  # CRuby + spinel post-#532: nil. (was: -1)
      p "abcdabcd".rindex(/c/)   # CRuby & spinel: 6 (new sp_re_rindex helper)
      begin
        "foo".send(:<<)          # CRuby: ArgumentError. spinel: FrozenError (after #886)
        puts "no raise"
      rescue FrozenError => e
        puts "send-lshift: " + e.message
      end

      # setbyte on a literal: WITHOUT the frozen_string_literal magic comment a
      # literal is mutable (CRuby); the write copies the static bytes and rebinds
      # the variable (#2029). A frozen-string-literal file or an explicit .freeze
      # still raises (pinned by bundle_classd_43).
      (str = "a")
      begin
        str.setbyte(0, 98)
        puts "literal not frozen: " + str
      rescue FrozenError => e
        puts "frozen literal: " + e.message
      end
      str2 = "a".dup
      str2.setbyte(0, 98)
      puts str2  # "b" (heap, mutates)
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      core/string/frozen_test.rb:19:in 'String#count': wrong number of arguments (given 0, expected 1+) (ArgumentError)

          caller: core/string/frozen_test.rb:19
          |   "foo".count
                   ^^^^^^
      	from core/string/frozen_test.rb:19:in '<main>'
    ERR
  end

  it "five String rows answer only where CRuby answers, and raise where it raises" do
    result = zr(<<~'RUBY')
      # Five String surfaces that answered where CRuby refuses, or refused where
      # CRuby answers.

      # an empty pad is rejected whatever the width -- the no-op width case used to
      # return the receiver before looking at the pad
      r = ("hi".ljust(5, "") rescue $!.class); p r
      r = ("hi".rjust(5, "") rescue $!.class); p r
      r = ("hi".center(5, "") rescue $!.class); p r
      r = ("hi".ljust(1, "") rescue $!.class); p r
      p "hi".ljust(5, ".")
      p "hi".rjust(5, ".")
      p "hi".center(6, ".")

      # a radix outside 2..36 is an error, not a silent fallback to 10
      r = ("12".to_i(1) rescue $!.class); p r
      r = ("12".to_i(37) rescue $!.class); p r
      p "12".to_i(0)
      p "ff".to_i(16)
      p "12".to_i

      # both prefix predicates take any number of candidates, so none is false
      p "hello".start_with?
      p "hello".end_with?
      p "hello".start_with?("he")
      p "hello".end_with?("lo", "xx")

      # #b answers a fresh mutable copy, not the frozen receiver
      p "abc".b.frozen?
      s = "abc".b
      s << "d"
      p s

      # `str =~ str` is a TypeError, not a missing method
      r = ("hello" =~ "l" rescue $!.class); p r
      p("hello" =~ /l/)
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      "hi..."
      "...hi"
      "..hi.."
      ArgumentError
      ArgumentError
      12
      255
      12
      false
      false
      true
      true
      false
      "abcd"
      TypeError
      2
    OUT
  end

  it "clone keeps the frozen state, and dup always answers an unfrozen string" do
    result = zr(<<~'RUBY')
      # String#clone preserves the frozen state; String#dup always returns unfrozen.
      def id(x) = x

      # clone keeps frozen, dup clears it
      p id("x").freeze.clone.frozen?     # true
      p id("x").freeze.dup.frozen?       # false
      # unfrozen original: both stay unfrozen
      p id("abc").clone.frozen?          # false
      p id("abc").dup.frozen?            # false
      # value is preserved across clone
      p id("hi").freeze.clone            # "hi"
      # through a local variable
      s = "y".freeze
      c = s.clone
      p c.frozen?                        # true
      p c                                # "y"
      d = s.dup
      p d.frozen?                        # false
      # a frozen clone still raises on mutation
      begin
        c << "z"
      rescue FrozenError => e
        p e.class                        # FrozenError
      end
      # literal receiver
      p "lit".freeze.clone.frozen?       # true
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      false
      "hi"
      true
      "y"
      false
      FrozenError
      true
    OUT
  end

  it "to_f reads underscores, clear answers a value, byteslice answers nil past the end, === refuses a non-String" do
    result = zr(<<~'RUBY')
      # String conformance: to_f underscores, -@ frozen, clear as a value,
      # byteslice OOB->nil / boundary / Range, === with a non-String arg.
      p "1_000.5".to_f
      p "3.14".to_f
      p "abc".to_f
      p "x".-@.frozen?
      s = "abc"; v = s.clear; p v; p s
      p "abc".byteslice(5)
      p "abc".byteslice(3)
      p "abc".byteslice(2)
      p "abc".byteslice(3, 0)
      p "hello".byteslice(1..3)
      p "hello".byteslice(2..)
      p "hello".byteslice(10..12)
      p("abc" === nil)
      p("abc" === "abc")
      p("abc" === "xyz")
    RUBY

    _(result).must_answer <<~'OUT'
      1000.5
      3.14
      0.0
      true
      ""
      ""
      nil
      nil
      "c"
      ""
      "ell"
      "llo"
      nil
      false
      true
      false
    OUT
  end

  it "-@ on a string already frozen answers the receiver itself" do
    result = zr(<<~'RUBY')
      # String#-@ on an already-frozen string returns the receiver itself (#2630).
      a = "abc".freeze
      p((-a).equal?(a))
      c = -"xyz"
      p((-c).equal?(c))
    RUBY

    _(result).must_answer "true\ntrue\n"
  end

  it "-@ interns by content, so two dedups of equal contents answer one object" do
    result = zr(<<~'RUBY')
      # String#-@ / #dedup interns by content: two dedups of equal contents return
      # the same immortal frozen object (#2462).
      p("hello".dedup.equal?("hello".dedup))
      p((-"world").equal?(-"world"))
      p(("he" + "llo").dedup.equal?("hello".dedup))   # computed string interns too
      p("".dedup.equal?("".dedup))
      p((-"a").equal?(-"b"))                            # different contents differ
      p("frozen".dedup.frozen?)
      p(-"frozen")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      false
      true
      "frozen"
    OUT
  end

  it "insert, prepend and << on a frozen literal raise FrozenError, and String.new stays mutable" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true
      # Issue #886: Mutating methods on a frozen string literal raise
      # FrozenError per MRI. spinel string literals are always frozen.
      # Mutable strings (String.new("...")) keep working via the
      # mutable_str arm.
      begin
        "hello".insert(0, "X")
        puts "BUG: insert no raise"
      rescue FrozenError => e
        puts "insert: " + e.message
      end
      begin
        "hello".prepend("X")
        puts "BUG: prepend no raise"
      rescue FrozenError => e
        puts "prepend: " + e.message
      end
      begin
        "hello" << "Y"
        puts "BUG: << no raise"
      rescue FrozenError => e
        puts "<<: " + e.message
      end

      # Mutable strings still work.
      s = String.new("hi")
      s << "!"
      puts s
    RUBY

    _(result).must_answer <<~'OUT'
      insert: can't modify frozen String: "hello"
      prepend: can't modify frozen String: "hello"
      <<: can't modify frozen String: "hello"
      hi!
    OUT
  end

  it "a parameter appended to with << lands the append in the caller's variable" do
    result = zr(<<~'RUBY')
      # A string param mutated via `<<` is a byref out-param: the append lands in
      # the caller's variable, like CRuby's shared-object semantics (the classic
      # pass-an-output-buffer serializer pattern).
      def append(s)
        s << "world"
      end
      str = "hello".dup
      append(str)
      puts str

      # transitive: a wrapper that passes its param on into a byref slot
      def inner(s)
        s << "!"
      end
      def outer(s)
        inner(s)
      end
      a = "x".dup
      outer(a)
      puts a

      # the mutator's return value is the receiver, usable alongside the mutation
      def bang(s)
        s << "?"
      end
      b = "y".dup
      r = bang(b)
      puts b
      puts r

      # only the mutated param rides byref; its sibling stays a plain value
      def tag(buf, label)
        buf << "["
        buf << label
        buf << "]"
      end
      t = "".dup
      tag(t, "hi")
      puts t

      # a non-lvalue argument still compiles (CRuby's mutation is equally
      # invisible to the caller there)
      bang("zzz".dup)
      puts "lit ok"

      # a plain rebind keeps value semantics: CRuby `s = ...` rebinds the local,
      # invisible to the caller, so the param must NOT ride byref
      def rebind(s)
        s = "gone"
        s << "!"
      end
      u = "keep".dup
      rebind(u)
      puts u

      # repeated appends through a call inside a block (build-a-buffer loop)
      def ser(buf, n)
        buf << n.to_s
        buf << ","
      end
      o = "".dup
      3.times { |i| ser(o, i) }
      puts o

      # a caller variable that is also captured by a proc (celled) passes its cell
      w = "p".dup
      f = proc { w << "c" }
      bang(w)
      f.call
      puts w

      # element assignment is an in-place mutator too
      def fix(s)
        s[0] = "X"
      end
      e = "abc".dup
      fix(e)
      puts e

      # a frozen argument raises FrozenError from inside the callee, like CRuby
      frozen = "locked".freeze
      begin
        bang(frozen)
      rescue FrozenError
        puts "FrozenError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      helloworld
      x!
      y?
      y?
      [hi]
      lit ok
      keep
      0,1,2,
      p?c
      Xbc
      FrozenError
    OUT
  end

  it "strings and collections" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      def wrap(x)
        "<#{x}>"
      end

      name = "world"
      count = 3
      puts "hello, #{name}! #{count} #{count * 2} #{1 + 2}"
      puts "#{wrap(1)} #{wrap("two")} #{wrap(nil)}"
      puts "no interpolation at all"
      puts "trailing #{name}"
      puts "#{name} leading"

      letters = ["a", "b", "c"]
      p letters
      p letters.length
      p letters[0]
      p letters.reverse
      p [1, [2, 3], [], nil, true, :sym, 4.5]
      p [].empty?

      sizes = { "small" => 1, "large" => 9 }
      p sizes
      p sizes["large"]
      p sizes.keys
      p sizes.values
      p({ a: 1, b: [2, 3] })
      p({})

      p (1..4).to_a
      p (1...4).to_a
      p (1..4).include?(2)
      p ("a".."d").to_a

      s = "abc"
      p s.upcase
      p s + "def"
      p s * 2
      s += "!"
      p s
      p "#{s.length} #{letters.size} #{sizes.size}"

      # The magic comment above: a literal is one frozen object, an
      # interpolated string is fresh, and `+` and `dup` both unfreeze.
      p "abc".frozen?
      p "abc".equal?("abc")
      p "#{name}".frozen?
      p (+"abc").frozen?
      p "abc".dup.frozen?

      # Splats spread through ruby's own `to_a` and `to_hash` rules.
      xs = [2, 3]
      p [1, *xs, 4]
      p [*xs]
      p [*xs, *xs]
      p [*nil]
      p [*1]
      p [*(1..3)]
      p [*{ a: 1 }]

      kw = { a: 1, b: 2 }
      p({ **kw })
      p({ c: 0, **kw })
      p({ **kw, a: 9 })
      p({ **kw, **kw })

      # `&.` answers nil without calling, on nil ALONE.
      none = nil
      p none&.size
      p "abc"&.size
      p false&.to_s
      p none&.map { |v| v }
      p [4, 5]&.map { |v| v * 2 }
      p({ a: { b: 1 } }[:a]&.fetch(:b))
      p({ a: { b: 1 } }[:z]&.fetch(:b))

      # Adjacent literals are one string.
      one = 1
      p "x#{one}" \
        "y#{one + 1}"
      p "left" "right"
    RUBY

    _(result).must_answer <<~'OUT'
      hello, world! 3 6 3
      <1> <two> <>
      no interpolation at all
      trailing world
      world leading
      ["a", "b", "c"]
      3
      "a"
      ["c", "b", "a"]
      [1, [2, 3], [], nil, true, :sym, 4.5]
      true
      {"small" => 1, "large" => 9}
      9
      ["small", "large"]
      [1, 9]
      {a: 1, b: [2, 3]}
      {}
      [1, 2, 3, 4]
      [1, 2, 3]
      true
      ["a", "b", "c", "d"]
      "ABC"
      "abcdef"
      "abcabc"
      "abc!"
      "4 3 2"
      true
      true
      false
      false
      false
      [1, 2, 3, 4]
      [2, 3]
      [2, 3, 2, 3]
      []
      [1]
      [1, 2, 3]
      [[:a, 1]]
      {a: 1, b: 2}
      {c: 0, a: 1, b: 2}
      {a: 9, b: 2}
      {a: 1, b: 2}
      nil
      3
      "false"
      nil
      [8, 10]
      1
      nil
      "x1y2"
      "leftright"
    OUT
  end

  it "symbol nil bool float batch" do
    result = zr(<<~'RUBY')
      # Symbol#intern/#name(frozen)/#casecmp(String), boolean & | ^ with Integer,
      # clone(freeze:) on immutable values, Float comparison/to_int/coerce edges,
      # nil <=> / rationalize / =~ / !~.

      # Symbol
      p(:hello.intern)
      s = :hello
      p(s.intern)
      p(:hello.name.frozen?)
      p(:hello.name)
      p(:HELLO.casecmp("hello"))
      p(:HELLO.casecmp?("hello"))
      p(:abc.casecmp(:ABD))
      p(:abc.casecmp?(:ABC))

      # true/false & | ^ with an Integer operand (0 is truthy)
      p(true & 0)
      p(true & 2)
      p(false | 0)
      p(true ^ 0)
      p(false ^ 0)
      a = true
      b = 0
      p(a & b)

      # clone(freeze:) on immutable values
      p(true.clone.class)
      p(true.clone(freeze: true).class)
      p(false.clone(freeze: true).class)
      p(nil.clone(freeze: true).class)
      p(1.clone(freeze: true).class)

      # Float comparisons with non-numeric operands raise ArgumentError
      f = 1.5
      begin
        p(f < nil)
      rescue => e
        p e.class
      end
      begin
        p(f > Object.new)
      rescue => e
        p e.class
      end

      # Float#to_int on Infinity/NaN raises FloatDomainError like to_i
      begin
        p(Float::INFINITY.to_int)
      rescue => e
        p e.class
      end
      begin
        p(Float::NAN.to_int)
      rescue => e
        p e.class
      end
      p(3.9.to_int)

      # Float#coerce with Rational/Complex arguments
      p(1.0.coerce(Rational(1, 2)))
      p(2.0.coerce(Complex(1, 0)))
      p(1.0.coerce(2))

      # nil <=> / rationalize / =~ / !~
      p(nil <=> nil)
      p(nil <=> 1)
      p(nil.rationalize)
      p(nil =~ /x/)
      p(nil !~ /x/)
    RUBY

    _(result).must_answer <<~'OUT'
      :hello
      :hello
      true
      "hello"
      nil
      nil
      -1
      true
      true
      true
      true
      false
      true
      true
      TrueClass
      TrueClass
      FalseClass
      NilClass
      Integer
      ArgumentError
      ArgumentError
      FloatDomainError
      FloatDomainError
      3
      [0.5, 1.0]
      [1.0, 2.0]
      [2.0, 1.0]
      0
      nil
      (0/1)
      nil
      true
    OUT
  end

  it "warns on its first change" do
    result = zr(<<~'RUBY')
      # A String literal in a file that sets no frozen_string_literal is
      # chilled: not frozen, but +@ copies it, and its first change warns when
      # deprecation warnings are on. Symbol#to_s chills its String too.

      s = "abc"
      t = +s
      p t.equal?(s), s.frozen?
      t << "x"
      p s
      u = +"lit"
      p((+u).equal?(u))
      Warning[:deprecated] = true
      %w[upcase! downcase! capitalize! swapcase! reverse! strip! squeeze! succ! chop! chomp! lstrip! clear].each do |m|
        x = "Abc "
        x.public_send(m)
      end
      [
        -> { a = "a"; a.concat("b") },
        -> { a = "a"; a.replace("b") },
        -> { a = "a"; a[0] = "b" },
        -> { a = "a"; a.insert(0, "b") },
        -> { a = "a"; a.prepend("b") },
        -> { a = "a"; a.force_encoding("BINARY") },
        -> { a = "a"; a.setbyte(0, 66) },
        -> { a = "a"; a.sub!("a", "b") },
        -> { a = "a"; a.gsub!("a", "b") },
        -> { a = "a"; a.tr!("a", "b") },
        -> { a = "a"; a.slice!(0) },
        -> { a = "a"; a.encode!("UTF-16LE") },
        -> { a = "a"; a.instance_variable_set(:@x, 1) },
        -> { a = "a"; a.freeze; p a.frozen? },
        -> { a = "a"; b = a.clone(freeze: false); b << "x" },
        -> { a = "a"; b = a.dup; b << "x" },
        -> { a = "a"; p a.frozen?; b = -a; p b.frozen? },
        -> { a = :sym.to_s; a << "!" },
        -> { a = :sym.name; p a.frozen? },
        -> { a = "a" "b"; a << "c" },
        -> { a = 'q'; a << "c" },
        -> { a = <<~X; a << "y" },
          text
        X
      ]
      .each_with_index { |f, i| $stderr.puts i; f.call }
      $VERBOSE = nil
      x = "v"
      x << "w"

    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      false
      false
      "abc"
      true
      true
      false
      true
      true
    OUT
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/frozen_test.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      0
      core/string/frozen_test.rb:18: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      1
      core/string/frozen_test.rb:19: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      2
      core/string/frozen_test.rb:20: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      3
      core/string/frozen_test.rb:21: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      4
      core/string/frozen_test.rb:22: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      5
      core/string/frozen_test.rb:23: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      6
      core/string/frozen_test.rb:24: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      7
      core/string/frozen_test.rb:25: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      8
      core/string/frozen_test.rb:26: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      9
      core/string/frozen_test.rb:27: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      10
      core/string/frozen_test.rb:28: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      11
      core/string/frozen_test.rb:29: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      12
      core/string/frozen_test.rb:30: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      13
      14
      15
      16
      17
      core/string/frozen_test.rb:35: warning: string returned by :sym.to_s will be frozen in the future
      18
      19
      core/string/frozen_test.rb:37: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      20
      core/string/frozen_test.rb:38: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      21
      core/string/frozen_test.rb:39: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
    ERR
  end

  it "a core method answers a frozen String or a fresh one as ruby does" do
    result = zr(<<~'RUBY')
      # Each answer's frozen? beside the expression that made it: the core's
      # literals are frozen, so a method that answers one must answer what
      # ruby's C answers, a fresh String or a frozen one.
      Point = Struct.new(:x)
      Pair = Data.define(:a)
      answers = {
        "nil.to_s" => nil.to_s, "true.to_s" => true.to_s, "false.to_s" => false.to_s,
        "nil.inspect" => nil.inspect, "true.inspect" => true.inspect,
        "1.to_s" => 1.to_s, "12.to_s(2)" => 12.to_s(2), "(2**70).to_s" => (2**70).to_s,
        "1.5.to_s" => 1.5.to_s, "Float::INFINITY.to_s" => Float::INFINITY.to_s, "Float::NAN.inspect" => Float::NAN.inspect,
        "(0.0/-1).to_s" => (0.0 / -1).to_s,
        "Rational(1, 2).to_s" => Rational(1, 2).to_s, "Complex(1, 2).to_s" => Complex(1, 2).to_s,
        "Complex(1, 2).inspect" => Complex(1, 2).inspect,
        ":a.to_s" => :a.to_s, ":a.name" => :a.name, ":a.inspect" => :a.inspect,
        "[1].inspect" => [1].inspect, "[].inspect" => [].inspect, "[].join" => [].join, "[1, 2].join" => [1, 2].join,
        "{}.inspect" => {}.inspect, "{a: 1}.to_s" => { a: 1 }.to_s,
        "(1..2).to_s" => (1..2).to_s, "(1..2).inspect" => (1..2).inspect,
        "Point.new(1).inspect" => Point.new(1).inspect, "Pair.new(a: 1).inspect" => Pair.new(a: 1).inspect,
        "Encoding::UTF_8.name" => Encoding::UTF_8.name, "Encoding::UTF_8.to_s" => Encoding::UTF_8.to_s,
        "Encoding::UTF_8.inspect" => Encoding::UTF_8.inspect, "Encoding::UTF_8.names.first" => Encoding::UTF_8.names.first,
        "Encoding.name_list.first" => Encoding.name_list.first, "Encoding.locale_charmap" => Encoding.locale_charmap,
        "ARGF.to_s" => ARGF.to_s, "ARGF.filename" => ARGF.filename,
        "$stdout.inspect" => $stdout.inspect, "Thread.current.status" => Thread.current.status,
        "Thread.current.inspect.class" => Thread.current.inspect,
        "RuntimeError.new.message" => RuntimeError.new.message, "StandardError.new.message" => StandardError.new.message,
        "a core raise's message" => (begin; [].first(-1); rescue => e; e.message; end),
        "a ZeroDivisionError's message" => (begin; 1 / 0; rescue => e; e.message; end),
        "a KeyError's message" => (begin; {}.fetch(:k); rescue => e; e.message; end),
        "a TypeError's message" => (begin; 1 + nil; rescue => e; e.message; end),
        "File.basename" => File.basename("/a/b.rb"), "File.extname" => File.extname("a.rb"), "File.extname('a')" => File.extname("a"),
        "File.dirname" => File.dirname("a"), "File.join" => File.join("a", "b"), "File.expand_path('/')" => File.expand_path("/"),
        "File::SEPARATOR" => File::SEPARATOR, "RUBY_VERSION" => RUBY_VERSION,
        "format" => format("%d", 1), "'%s' % 1" => "%s" % 1, "[1].pack('C')" => [1].pack("C"), "[].pack('C*')" => [].pack("C*"),
        "65.chr" => 65.chr, "200.chr" => 200.chr, "'ab'.b" => "ab".b, "'abc'[0]" => "abc"[0],
        "Time.at(0).utc.zone" => Time.at(0).utc.zone, "Time.at(0).utc.to_s" => Time.at(0).utc.to_s,
        "Time.at(0).utc.inspect" => Time.at(0).utc.inspect, "strftime" => Time.at(0).utc.strftime("%Y"),
        "strftime('')" => Time.at(0).utc.strftime(""),
        "Signal.signame(2)" => Signal.signame(2), "Signal.list.keys.first" => Signal.list.keys.first,
        "Comparable.name" => Comparable.name, "Integer.to_s" => Integer.to_s, "Integer.inspect" => Integer.inspect,
        "Process.clock_gettime unit" => Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second).class.name,
        "''.center(3)" => "".center(3), "'a'.ljust(1)" => "a".ljust(1), "'a' * 0" => "a" * 0,
        "[nil].join" => [nil].join, "[[1]].to_s" => [[1]].to_s,
        "1.0.round.to_s" => 1.0.round.to_s, "Integer.sqrt(4).to_s" => Integer.sqrt(4).to_s,
        "Random.new(1).bytes(0)" => Random.new(1).bytes(0),
        "'é'.unicode_normalize" => "é".unicode_normalize, "'a'.encode('UTF-16LE')" => "a".encode("UTF-16LE"),
        "GC.stat.keys.first.to_s" => GC.stat.keys.first.to_s, "ObjectSpace.count_objects.keys.first.to_s" => ObjectSpace.count_objects.keys.first.to_s,
        "__method__.to_s" => __method__.to_s, "Set[1].inspect" => Set[1].inspect, "Set[].to_s" => Set[].to_s
      }
      answers.each { |name, value| puts "#{name}: #{value.is_a?(String) ? value.frozen? : value.class}" }
    RUBY

    _(result).must_answer <<~'OUT'
      nil.to_s: true
      true.to_s: true
      false.to_s: true
      nil.inspect: false
      true.inspect: true
      1.to_s: false
      12.to_s(2): false
      (2**70).to_s: false
      1.5.to_s: false
      Float::INFINITY.to_s: false
      Float::NAN.inspect: false
      (0.0/-1).to_s: false
      Rational(1, 2).to_s: false
      Complex(1, 2).to_s: false
      Complex(1, 2).inspect: false
      :a.to_s: false
      :a.name: true
      :a.inspect: false
      [1].inspect: false
      [].inspect: false
      [].join: false
      [1, 2].join: false
      {}.inspect: false
      {a: 1}.to_s: false
      (1..2).to_s: false
      (1..2).inspect: false
      Point.new(1).inspect: false
      Pair.new(a: 1).inspect: false
      Encoding::UTF_8.name: true
      Encoding::UTF_8.to_s: true
      Encoding::UTF_8.inspect: false
      Encoding::UTF_8.names.first: true
      Encoding.name_list.first: true
      Encoding.locale_charmap: false
      ARGF.to_s: false
      ARGF.filename: false
      $stdout.inspect: false
      Thread.current.status: false
      Thread.current.inspect.class: false
      RuntimeError.new.message: false
      StandardError.new.message: false
      a core raise's message: false
      a ZeroDivisionError's message: false
      a KeyError's message: false
      a TypeError's message: false
      File.basename: false
      File.extname: false
      File.extname('a'): false
      File.dirname: false
      File.join: false
      File.expand_path('/'): false
      File::SEPARATOR: true
      RUBY_VERSION: true
      format: false
      '%s' % 1: false
      [1].pack('C'): false
      [].pack('C*'): false
      65.chr: false
      200.chr: false
      'ab'.b: false
      'abc'[0]: false
      Time.at(0).utc.zone: false
      Time.at(0).utc.to_s: false
      Time.at(0).utc.inspect: false
      strftime: false
      strftime(''): false
      Signal.signame(2): false
      Signal.list.keys.first: true
      Comparable.name: true
      Integer.to_s: false
      Integer.inspect: false
      Process.clock_gettime unit: true
      ''.center(3): false
      'a'.ljust(1): false
      'a' * 0: false
      [nil].join: false
      [[1]].to_s: false
      1.0.round.to_s: false
      Integer.sqrt(4).to_s: false
      Random.new(1).bytes(0): false
      'é'.unicode_normalize: false
      'a'.encode('UTF-16LE'): false
      GC.stat.keys.first.to_s: false
      ObjectSpace.count_objects.keys.first.to_s: false
      __method__.to_s: true
      Set[1].inspect: false
      Set[].to_s: false
    OUT
  end

  it "a literal under frozen_string_literal sends no freeze, even where String#freeze is redefined" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true
      class String
        def freeze = raise("String#freeze called")
      end
      a = "lit"
      b = "lét"
      c = "#{1}x"
      p a, a.frozen?, a.equal?("lit"), b, b.frozen?, c.frozen?
      p [1, 2].inspect, :sym.to_s, "x" * 2
      puts "done"
      begin
        "lit".dup.freeze
      rescue => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "lit"
      true
      true
      "lét"
      true
      false
      "[1, 2]"
      "sym"
      "xx"
      done
      "String#freeze called"
    OUT
  end
end
