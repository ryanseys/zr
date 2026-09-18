# frozen_string_literal: true

require "spec_helper"

describe "String: regressions" do
  it "str array each" do
    result = ze0(<<~'RUBY')
      # Array#each on a str_array. The block param must shadow an outer
      # same-named mrb_int local. Body skips `puts i` to keep this scope-
      # shadow case separate from the format-specifier path.

      3.times do |i|
        puts i
      end
      foo = ["a", "b", "c"]
      n = 0
      foo.each { |i| n = n + 1 }
      puts n   # 3
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      2
      3
    OUT
  end

  it "str array map" do
    result = ze0(<<~'RUBY')
      # Array#map on a str_array. Issue #43: compile_map_expr had no
      # str_array branch, so `tt = foo.map { |s| ... }` silently emitted
      # `lv_tt = 0` and the subsequent iteration crashed.

      # String -> string map (the original failure mode)
      foo = ["a", "b", "c"]
      tt = foo.map { |s| s.upcase }
      tt.each { |t| puts t }   # A B C

      # String -> int map: codepoint length, returning int_array
      sizes = foo.map { |s| s.length }
      puts sizes.length         # 3
      puts sizes[0]             # 1
      puts sizes[1]             # 1
      puts sizes[2]             # 1

      # Original receiver is unchanged
      puts foo[0]               # a
      puts foo[1]               # b
      puts foo[2]               # c

      # .map { ... }.each { ... } chain (the issue's pattern)
      words = ["alpha", "beta", "gamma"]
      words.map { |w| w.upcase }.each { |w| puts w }   # ALPHA BETA GAMMA

      # Empty input
      empty = "".split(",")
      e2 = empty.map { |s| s.upcase }
      puts e2.length            # 0

      # Block parameter is block-local: reusing the same name as an outer
      # differently-typed local must not leak. Issue #43 originally hit this
      # (3.times do |i| ... end then foo.map {|i| ...} where the times-block
      # had typed lv_i as mrb_int).
      rs = []
      3.times do |i|
        rs << "row#{i}"
      end
      out = rs.map { |i| i.upcase }
      out.each { |line| puts line }   # ROW0 ROW1 ROW2
    RUBY

    _(result).must_answer <<~'OUT'
      A
      B
      C
      3
      1
      1
      1
      a
      b
      c
      ALPHA
      BETA
      GAMMA
      0
      ROW0
      ROW1
      ROW2
    OUT
  end

  it "str array range" do
    result = ze0(<<~'RUBY')
      # StrArray slicing: a[range] and a[start, len].
      # Same regression class as IntArray: a[1..2] failed to compile and
      # a[1, 2] silently dropped the second arg.

      a = "alpha,beta,gamma,delta,epsilon".split(",")

      # Range form
      b = a[1..3]
      puts b.length      # 3
      puts b[0]          # beta
      puts b[1]          # gamma
      puts b[2]          # delta

      # (start, len) form
      c = a[1, 2]
      puts c.length      # 2
      puts c[0]          # beta
      puts c[1]          # gamma

      # Negative start
      d = a[-2, 2]
      puts d.length      # 2
      puts d[0]          # delta
      puts d[1]          # epsilon

      # len exceeds remaining: clamped
      f = a[2, 100]
      puts f.length      # 3
      puts f[0]          # gamma
      puts f[2]          # epsilon

      # Bare a[i] still returns a string
      puts a[0]          # alpha
      puts a[-1]         # epsilon

      # Result is usable as a StrArray
      puts a[1..3].join(":")  # beta:gamma:delta
    RUBY

    _(result).must_answer <<~'OUT'
      3
      beta
      gamma
      delta
      2
      beta
      gamma
      2
      delta
      epsilon
      3
      gamma
      epsilon
      alpha
      epsilon
      beta:gamma:delta
    OUT
  end

  it "str format arr" do
    result = ze0(<<~'RUBY')
      # String#% with a str_array RHS, routed through sp_str_format_strarr.
      # The integer % path (sp_imod) is unchanged — only str_array RHS triggers
      # sprintf-style formatting.

      # Single placeholder
      puts "hello, %s!" % ["world"]            # hello, world!

      # Multiple placeholders
      puts "%s and %s" % ["a", "b"]            # a and b

      # %% literal
      puts "100%% of %s" % ["coverage"]        # 100% of coverage

      # %s after literal text
      puts "[%s][%s][%s]" % ["x", "y", "z"]    # [x][y][z]

      # Extra args are ignored (matches CRuby tolerant behavior)
      puts "%s" % ["a", "b", "c"]              # a

      # Format string with no placeholders, args ignored
      puts "no formatting here" % ["x"]        # no formatting here
    RUBY

    _(result).must_answer <<~'OUT'
      hello, world!
      a and b
      100% of coverage
      [x][y][z]
      a
      no formatting here
    OUT
  end

  it "str justify" do
    result = ze0(<<~'RUBY')
      # Test String#ljust, rjust, center with custom pad string

      # center with default (space) pad
      puts "hi".center(10)        #     hi
      puts "hi".center(9)         #    hi

      # center with single-char pad
      puts "hi".center(10, "-")   # ----hi----
      puts "hi".center(9,  "-")   # ---hi----

      # center with multi-char pad (cycling)
      puts "hi".center(10, "ab")  # ababhiabab
      puts "hi".center(9,  "ab")  # abahiabab

      # ljust with multi-char pad (cycling)
      puts "hi".ljust(8, "ab")    # hiababab
      puts "hi".ljust(8, "xyz")   # hixyzxyz

      # rjust with multi-char pad (cycling)
      puts "hi".rjust(8, "ab")    # abababhi
      puts "hi".rjust(8, "xyz")   # xyzxyzhi

      # no-op when string already long enough
      puts "hello".ljust(3, "x")  # hello
      puts "hello".rjust(3, "x")  # hello
      puts "hello".center(3, "x") # hello

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
          hi    
         hi    
      ----hi----
      ---hi----
      ababhiabab
      abahiabab
      hiababab
      hixyzxyz
      abababhi
      xyzxyzhi
      hello
      hello
      hello
      done
    OUT
  end

  it "strindex" do
    result = ze0(<<~'RUBY')
      s = "hello world"
      puts s[0]    # h
      puts s[6]    # w
      puts s[-1]   # d
      puts s[4]    # o
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      h
      w
      d
      o
      done
    OUT
  end

  it "string chop" do
    result = ze0(<<~'RUBY')
      # basic
      puts "hello".chop

      # crlf removed together
      puts "hello\r\n".chop

      # newline only
      puts "hello\n".chop

      # empty string
      puts "".chop

      # single char
      puts "x".chop

      # already no trailing newline
      puts "abc".chop
    RUBY

    _(result).must_answer <<~'OUT'
      hell
      hello
      hello


      ab
    OUT
  end

  it "string each byte" do
    result = ze0(<<~'RUBY')
      # String#each_byte iterates the bytes of a string. Mirrors each_char
      # but yields the (unsigned) byte value at each position rather than
      # a single-char substring. ASCII-only test pins parity with CRuby's
      # byte-level iteration. Multi-byte UTF-8 prints the underlying byte
      # values, not codepoints (matches CRuby).

      # ASCII string
      "ab".each_byte { |b| puts b }

      # Empty string yields nothing
      "".each_byte { |b| puts b }

      # Mixed alphabetic and digit
      "A1z".each_byte { |b| puts b }

      # Newline byte
      "a\n".each_byte { |b| puts b }

      # Multi-byte UTF-8 (Latin Small Letter E with Acute): byte iteration, not codepoint
      "é".each_byte { |b| puts b }

      # Counted iteration via accumulator
      total = 0
      "hello".each_byte { |b| total = total + b }
      puts total

      # String#each_byte returns the receiver (CRuby parity). Pre-fix Spinel's
      # each_byte was statement-only and the assignment dropped the value.
      total2 = 0
      ret = "hello".each_byte { |b| total2 = total2 + b }
      puts total2
      puts ret
    RUBY

    _(result).must_answer <<~'OUT'
      97
      98
      65
      49
      122
      97
      10
      195
      169
      532
      532
      hello
    OUT
  end

  it "string escape" do
    result = ze0(<<~'RUBY')
      # Literal backslash preservation — the original bug: "\\n" is two
      # bytes (backslash + n) in Ruby source-level escape, and length is 2.
      puts "\\n".length     # 2
      puts "a\\nb".length   # 4
      puts "\\\\".length    # 2

      # Standard runtime escape sequences must still work alongside the
      # fix — "\n" is one newline byte, "\t" tab, "\r" CR, "\"" quote.
      puts "\n".length      # 1
      puts "\t".length      # 1
      puts "\r".length      # 1
      puts "\"".length      # 1
      puts "a\nb".length    # 3

      # Mixed escapes — literal backslash AND a real newline in the same
      # string. "a\\nb\nc" = a, \, n, b, <newline>, c → length 6.
      puts "a\\nb\nc".length
    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      2
      1
      1
      1
      1
      3
      6
    OUT
  end

  it "string format single" do
    result = ze0(<<~'RUBY')
      # `"fmt" % value` (the single-value form of String#%) used to fall
      # through to sp_imod, which rejected the format string as a non-int.

      puts "%d" % 42
      puts "%05d" % 7
      puts "%.2f" % 3.14159
      puts "%s!" % "hello"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      00007
      3.14
      hello!
    OUT
  end

  it "string lines" do
    result = ze0(<<~'RUBY')
      # Tests String#lines preserves trailing newline on each piece (CRuby semantics).
      p "hello\nworld\n".lines
      p "hello\nworld".lines
      p "single line".lines
      p "".lines
      p "\n\n\n".lines
      puts "hello\nworld\n".lines.length
      puts "hello\nworld\n".lines[0]
      puts "hello\nworld\n".lines[1]
    RUBY

    _(result).must_answer <<~'OUT'
      ["hello\n", "world\n"]
      ["hello\n", "world"]
      ["single line"]
      []
      ["\n", "\n", "\n"]
      2
      hello
      world
    OUT
  end

  it "strings" do
    result = ze0(<<~'RUBY')
      # Test Symbol and String methods

      # Symbol
      s = :hello
      puts s  # hello

      # String methods
      str = "Hello, World!"
      puts str.length      # 13
      puts str.upcase      # HELLO, WORLD!
      puts str.downcase    # hello, world!
      puts str.include?("World")  # true
      puts str.include?("xyz")    # false

      # String concatenation
      a = "foo"
      b = "bar"
      c = a + b
      puts c  # foobar

      # to_s on integers
      n = 42
      puts n.to_s  # 42
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      13
      HELLO, WORLD!
      hello, world!
      true
      false
      foobar
      42
    OUT
  end

  it "strings2" do
    result = ze0(<<~'RUBY')
      # Test additional String methods

      str = "  Hello, World!  "
      puts str.strip           # "Hello, World!"
      puts str.chomp           # "  Hello, World!  " (no trailing newline)

      s = "hello world"
      puts s.capitalize        # "Hello world"
      puts s.reverse           # "dlrow olleh"
      puts s.count("lo")       # 5
      puts s.start_with?("hel")  # true
      puts s.end_with?("rld")    # true
      puts s.gsub("l", "L")   # heLLo worLd
      puts s.sub("o", "0")    # hell0 world
      puts s.split(" ").length # 2

      # String repeat
      puts "ha" * 3            # hahaha

      # String comparison
      puts "abc" == "abc"      # true
      puts "abc" == "def"      # false
      puts "abc" < "def"       # true
    RUBY

    _(result).must_answer <<~'OUT'
      Hello, World!
        Hello, World!  
      Hello world
      dlrow olleh
      5
      true
      true
      heLLo worLd
      hell0 world
      2
      hahaha
      true
      false
      true
    OUT
  end

  it "strings3" do
    result = ze0(<<~'RUBY')
      # Test additional string methods

      # ljust / rjust / center
      puts "hi".ljust(10)         # "hi        "
      puts "hi".rjust(10)         # "        hi"
      puts "hi".center(10)        # "    hi    "
      puts "hi".ljust(10, "*")    # "hi********"
      puts "hi".rjust(10, "0")    # "00000000hi"

      # lstrip / rstrip
      puts "  hello  ".lstrip     # "hello  "
      puts "  hello  ".rstrip     # "  hello"

      # tr / delete / squeeze
      puts "hello".tr("el", "ip")      # "hippo"
      puts "hello world".delete("lo")  # "he wrd"
      puts "aaabbbccc".squeeze          # "abc"

      # chars / bytes
      puts "abc".chars.length     # 3
      puts "abc".bytes.length     # 3

      # to_f
      puts ("3.14".to_f * 100).to_i  # 314

      # slice
      puts "hello"[1..3]          # "ell"
      puts "hello"[0, 2]          # "he"

      # hex / oct
      puts "ff".hex    # 255
      puts "77".oct    # 63

      # dup / freeze / frozen?
      s = "hello"
      puts s.dup       # "hello"
      puts s.freeze    # "hello"
      puts s.frozen?   # true

      # to_s
      puts "test".to_s  # "test"

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      hi        
              hi
          hi    
      hi********
      00000000hi
      hello  
        hello
      hippo
      he wrd
      abc
      3
      3
      314
      ell
      he
      255
      63
      hello
      hello
      true
      test
      done
    OUT
  end

  it "mutable str" do
    result = ze0(<<~'RUBY')
      # Mutable strings (sp_String): the `<<` mutation path, replace/clear,
      # index access, gsub/sub, split, ljust/rjust, downcase/strip/...,
      # start_with?/end_with?/empty?/include?, to_s/to_i. Combines what
      # was previously split across mutable_str.rb / _2.rb / _3.rb.

      # << (true mutation, not reassignment)
      a = "hello"
      a << " world"
      a << "!"
      puts a          # hello world!
      puts a.length   # 12

      # Build string incrementally
      buf = ""
      5.times do |i|
        buf << i.to_s
        buf << ","
      end
      puts buf        # 0,1,2,3,4,

      # upcase / reverse / include? on mutable receiver
      b = "Hello World"
      puts b.upcase                 # HELLO WORLD
      puts b.reverse                # dlroW olleH
      puts b.include?("World")      # true

      # replace / clear
      c = "hello"
      c.replace("world")
      puts c          # world
      c.clear
      puts c.length   # 0

      # [] on mutable string
      d = "abcdef"
      d << "ghi"
      puts d[0]       # a
      puts d[-1]      # i
      puts d.length   # 9

      # gsub on mutable receiver
      e = "hello"
      e << " world"
      puts e.gsub("o", "0")  # hell0 w0rld

      # split on mutable receiver
      f = "a"
      f << ",b,c"
      parts = f.split(",")
      puts parts.length  # 3

      # + creates a new string, does not mutate the receiver
      g = "foo"
      g << "bar"
      h = g + "baz"
      puts g        # foobar (unchanged)
      puts h        # foobarbaz

      # to_s on mutable receiver
      tst = "test"
      tst << "ing"
      puts tst.to_s   # testing

      # downcase / strip / capitalize / start_with? / end_with? / empty?
      j = ""
      j << "Hello"
      j << " "
      j << "World"
      puts j.length             # 11
      puts j.downcase           # hello world
      puts j.strip              # Hello World
      puts j.capitalize         # Hello world
      puts j.start_with?("Hello")  # true
      puts j.end_with?("World")    # true
      puts j.empty?             # false

      # sub / gsub on mutable receiver
      puts j.gsub("l", "r")        # Herro Worrd
      puts j.sub("World", "Ruby")  # Hello Ruby

      # to_i via mutable receiver
      n = ""
      n << "42"
      puts n.to_i    # 42

      # ljust / rjust
      t = ""
      t << "hi"
      puts t.ljust(10)   # "hi        "
      puts t.rjust(10)   # "        hi"

      # include?
      puts j.include?("World")  # true
      puts j.include?("xyz")    # false

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      hello world!
      12
      0,1,2,3,4,
      HELLO WORLD
      dlroW olleH
      true
      world
      0
      a
      i
      9
      hell0 w0rld
      3
      foobar
      foobarbaz
      testing
      11
      hello world
      Hello World
      Hello world
      true
      true
      false
      Herro Worrd
      Hello Ruby
      42
      hi        
              hi
      true
      false
      done
    OUT
  end

  it "str index range eq" do
    result = ze0(<<~'RUBY')
      # `s[i..i] == "/"` used to skip compile_string_method_expr's `[]`
      # RangeNode arm and hit the `s[i] == "/"` single-char fast path
      # instead (compile_eq_char_index), which cast the RangeNode to
      # mrb_int and emitted `lv_s[(mrb_int)sp_range_new(i, i)] == '/'` —
      # C compile failure ("aggregate value used where an integer was
      # expected"). Issue #644.
      #
      # Fix: the single-char fast path bails out when the `[]` arg is a
      # Range or a 2-arg `s[start, len]` form, so the call falls through
      # to the proper sp_str_sub_range dispatch + string compare.

      s = "abc/def"
      i = 3
      if s[i..i] == "/"
        puts "match"
      end

      # Range literal as the [] arg (no LV indirection).
      puts s[1..2]            # "bc"
      puts s[3..3] == "/"     # true

      # Exclusive range.
      puts s[3...4] == "/"    # true

      # `s[start, len]` 2-arg form must also fall through cleanly.
      puts s[3, 1] == "/"     # true
    RUBY

    _(result).must_answer <<~'OUT'
      match
      bc
      true
      true
      true
    OUT
  end

  it "str setbyte dup mutates" do
    result = ze0(<<~'RUBY')
      # `String#setbyte` on a heap-allocated string mutates in place.
      # Spinel adopts `# frozen_string_literal: true` semantics
      # globally: string literals are frozen (rodata-resident), so a
      # setbyte on a literal raises FrozenError; setbyte on a heap
      # buffer (from .dup, +, *, gsub, etc.) mutates as usual.
      #
      # This test pins the heap-mutate path. Literal -> FrozenError is
      # covered by test/str_setbyte_frozen_literal.

      # Dup'd string: setbyte mutates.
      s = "ab".dup
      s.setbyte(0, 67)  # 'C'
      s.setbyte(1, 68)  # 'D'
      puts s   # CD

      # String#+ produces a fresh heap buffer too.
      s2 = "x" + "y"
      s2.setbyte(0, 90)  # 'Z'
      puts s2  # Zy
    RUBY

    _(result).must_answer <<~'OUT'
      CD
      Zy
    OUT
  end

  it "string endless range" do
    result = ze0(<<~'RUBY')
      # #543. `s[1..]` (Ruby 2.6+ endless range) returned an empty
      # string under spinel-AOT instead of the substring from index 1
      # to end. CRuby returns "id" for ":id"[1..]; spinel returned "".
      # Trigger: the codegen lowered `s[1..]`'s RangeNode `right` (an
      # AST -1 sentinel meaning "no value") to literal `0`, then
      # `sp_str_sub_range_r(s, 1, 0, 0)` produced a zero-length slice.
      #
      # Sam Ruby caught this when Roundhouse's router stripped the
      # leading `:` from `:id` pattern segments via `pp[1..]` and the
      # capture key became "" -- every `/articles/N` 404'd because
      # params["id"] was always the default fallback.
      #
      # Fix: in the bracket-call's RangeNode branch, treat the AST -1
      # sentinel for the endpoints as the corresponding end:
      #   - missing left  -> "0"  (s[..k] == s[0..k])
      #   - missing right -> "-1" (s[k..] == s[k..-1])
      # The exclusive flag is ignored on the missing endpoint (CRuby
      # semantics: `s[1..]` == `s[1...]` == `s[1..-1]`).

      s = "hello"

      # Endless from inclusive lower bound.
      puts s[1..]      # ello
      puts s[1...]     # ello  (CRuby treats endless ... same as ..)
      puts s[-2..]     # lo

      # Beginless to inclusive upper bound.
      puts s[..2]      # hel
      puts s[...2]     # he   (exclusive upper)

      # The Sam Ruby repro shape: strip the leading char.
      pp = ":id"
      puts pp[1..]     # id
    RUBY

    _(result).must_answer <<~'OUT'
      ello
      ello
      lo
      hel
      he
      id
    OUT
  end

  it "string index from" do
    result = ze0(<<~'RUBY')
      # Regression: `String#index(sub, start)` 2-arg form.
      # Pre-fix the codegen ignored `start` and re-emitted the 1-arg
      # call, so a "find next dot after position N" walk all returned
      # the first match.
      #
      # Updated for #532: `String#index` now returns nil (not -1) for
      # not-found, matching CRuby. `puts nil.to_s` prints an empty
      # line; the walk-all-dots loop checks `pos.nil?` instead of
      # `pos < 0`.

      s = "a.b.c.d"

      # 1-arg form -- baseline.
      puts s.index(".").to_s          # 1

      # 2-arg form -- the fix.
      puts s.index(".", 0).to_s       # 1   (no skip, finds the same first dot)
      puts s.index(".", 1).to_s       # 1   (start at the dot itself, finds it)
      puts s.index(".", 2).to_s       # 3   (skip past the first dot, find the second)
      puts s.index(".", 4).to_s       # 5
      puts s.index(".", 6).to_s       # "" (nil.to_s; CRuby would print blank)

      # Negative start counts from end.
      puts s.index(".", -1).to_s      # "" (not found, nil.to_s)
      puts s.index(".", -2).to_s      # 5    (last dot)
      puts s.index(".", -100).to_s    # 1    (clamps to 0)

      # Out-of-range positive start.
      puts s.index(".", 100).to_s     # "" (not found, nil.to_s)

      # Multibyte: codepoint indexing, not byte indexing.
      m = "α.β.γ"
      puts m.index(".").to_s          # 1   (one cp before the first dot)
      puts m.index(".", 2).to_s       # 3   (after the first dot)

      # Walk-all-dots loop -- the JWT use case that surfaced this bug.
      # Idiomatic post-#532: `break if pos.nil?` instead of `pos < 0`.
      t = "header.payload.sig"
      i = 0
      positions = ""
      while true
        pos = t.index(".", i)
        if pos.nil?
          break
        end
        positions = positions + pos.to_s + ","
        i = pos.to_i + 1
      end
      puts positions                  # 6,14,
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      1
      3
      5


      5


      1
      3
      6,14,
    OUT
  end

  it "string index nullable" do
    result = ze0(<<~'RUBY')
      # #532. `String#index` / `String#rindex` previously returned
      # mrb_int with -1 as the not-found sentinel. The CRuby idiom
      #
      #   pos = body.index('"content"', i)
      #   break if pos.nil?
      #
      # silently broke because `pos.nil?` on a plain-int local is
      # always false (per #521's strict `int == nil`), so the loop
      # never exits and i wanders past the buffer.
      #
      # Fix: widen `String#index` / `String#rindex` to return sp_RbVal
      # (boxed nil for the -1 sentinel, boxed int for found). The
      # CRuby semantics now work end-to-end:
      # - `pos.nil?` / `pos == nil` / `pos != nil` via tag check
      # - `pos.inspect` via sp_poly_inspect (prints "nil" or the int)
      # - `while pos = s.index(...)` truthiness (boxed nil is falsy)
      #
      # Cost: downstream call sites that consume `pos` as a raw int
      # need to unbox. compile_expr_as_int / compile_arg0_as_int in
      # the codegen handle the int-expecting C helper signatures
      # (sp_str_sub_range etc.).

      s = "hello world"

      # Found and not-found inspect (formerly "6" / "-1"; now "6" / "nil").
      puts s.index("world").inspect    # 6
      puts s.index("xyz").inspect      # nil
      puts s.index("hello").inspect    # 0   (real index 0, not nil)

      # CRuby's nil-lens idiom now works without rewrites.
      pos = s.index("xyz")
      puts pos.nil?                    # true
      puts (pos == nil)                # true
      puts (pos != nil)                # false

      pos = s.index("hello")
      puts pos.nil?                    # false (real index 0 is NOT nil)
      puts (pos != nil)                # true

      # rindex inherits the same shape.
      puts "abcdabcd".rindex("c").inspect    # 6
      puts "abcdabcd".rindex("z").inspect    # nil

      # Walk-all idiom from the issue's GPT-2 BPE example.
      body = "header.payload.sig"
      i = 0
      positions = ""
      while true
        pos = body.index(".", i)
        break if pos.nil?
        positions = positions + pos.to_s + ","
        i = pos.to_i + 1
      end
      puts positions                   # 6,14,
    RUBY

    _(result).must_answer <<~'OUT'
      6
      nil
      0
      true
      true
      false
      false
      true
      6
      nil
      6,14,
    OUT
  end

  it "string index oob returns nil" do
    result = ze0(<<~'RUBY')
      # `"hello"[20]` (single-int index past the end) returns nil in CRuby,
      # not "". Pre-fix spinel's sp_str_sub_range fell through to its
      # OOB branch and returned the empty string, so a `.nil?` check
      # (or any `== nil` comparison) saw a non-NULL pointer and surfaced
      # false. Issue #619 puzzle 3.
      puts "hello"[20].nil?     # true
      puts "hello"[5].nil?      # true (at end of string, single-int index)
      puts "hello"[0].nil?      # false (in bounds)
      puts "hello"[4].nil?      # false (last char)
      puts "hello"[0]           # "h"
      puts "hello"[4]           # "o"
      puts "hello"[-1]          # "o" (negative index normalizes)
      puts "hello"[-99].nil?    # true (past start)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      h
      o
      o
      true
    OUT
  end

  it "string to i underscore" do
    result = ze0(<<~'RUBY')
      # CRuby's `String#to_i` accepts `_` between consecutive digits and
      # stops at the first non-digit. spinel previously emitted
      # `(mrb_int)atoll(s)` which stops at the first `_`, returning 1
      # for "1_2_3asdf" instead of 123. Now routes through
      # sp_str_to_i_cruby. Issue #619 puzzle 1.

      p("1_2_3asdf".to_i)
      p("-5_0".to_i)
      p("hello".to_i)
      p("  42  trailing".to_i)
      p("".to_i)
      p("0xFF".to_i)   # CRuby: 0 (only base-10 digits)
    RUBY

    _(result).must_answer <<~'OUT'
      123
      -50
      0
      42
      0
      0
    OUT
  end

  it "empty string to sym" do
    result = ze0(<<~'RUBY')
      # Empty-string interning: "".to_sym and the :"" literal must resolve to the
      # same symbol id (an empty symbol once broke the C build).
      p("".to_sym == :"")
      p(:"" == "".to_sym)
      p("abc".to_sym == :abc)
      p("".to_sym.to_s == "")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
    OUT
  end

  it "str each line chomp" do
    result = ze0(<<~'RUBY')
      # String#each_line(chomp: true) strips trailing line endings.
      "a\nb\nc".each_line(chomp: true) { |l| p l }
      puts "---"
      "a\nb\nc".each_line { |l| p l }
      puts "---"
      "x\r\ny\r\n".each_line(chomp: true) { |l| p l }
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      "b"
      "c"
      ---
      "a\n"
      "b\n"
      "c"
      ---
      "x"
      "y"
    OUT
  end

  it "str lines chomp" do
    result = ze0(<<~'RUBY')
      # String#lines(chomp: true) strips line endings from each line.
      # Without the chomp: keyword, line endings are preserved.

      puts "a\nb\nc".lines(chomp: true).inspect
      puts "a\nb\nc".lines.inspect
      puts "a\r\nb\r\nc\r\n".lines(chomp: true).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      ["a\n", "b\n", "c"]
      ["a", "b", "c"]
    OUT
  end

  it "str tr empty replacement" do
    result = ze0(<<~'RUBY')
      # String#tr / tr_s with empty replacement string
      # When the to-string is empty, matched characters are deleted.

      puts "abc".tr("a", "").inspect
      puts "abcdef".tr("a-c", "").inspect
      puts "aabbbccc".tr_s("ab", "").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "bc"
      "def"
      "ccc"
    OUT
  end

  it "string ascii only" do
    result = ze0(<<~'RUBY')
      # String#ascii_only? : true iff every byte is 7-bit ASCII.
      p "hello".ascii_only?
      p "héllo".ascii_only?
      p "".ascii_only?
      p "abc123!".ascii_only?
      p "あ".ascii_only?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      false
    OUT
  end

  it "string chomp separator" do
    result = ze0(<<~'RUBY')
      # Issue #881: String#chomp with an explicit separator argument
      # strips that suffix. Without the fix the arg was silently dropped
      # and the default newline rules were applied.
      puts "hello!".chomp("!").inspect
      puts "hello\n".chomp.inspect
      puts "hello\r\n".chomp.inspect
      puts "hello".chomp("!").inspect
      puts "hello\n\n".chomp("").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "hello"
      "hello"
      "hello"
      "hello"
    OUT
  end

  it "string codepoints" do
    result = ze0(<<~'RUBY')
      # Issue #903: String#codepoints returns int_array of UTF-8
      # codepoints (not bytes).
      puts "hello".codepoints.inspect
      puts "あ".codepoints.inspect
      puts "".codepoints.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [104, 101, 108, 108, 111]
      [12354]
      []
    OUT
  end

  it "string delete multi arg" do
    result = ze0(<<~'RUBY')
      # String#delete with multiple args deletes the intersection of the
      # charsets (each arg is a charset spec).
      p "hello".delete("l", "o")
      p "hello".delete("lo", "l")
      p "hello".delete("l", "h", "e")
      p "hello".delete("el", "ello")
      p "hello".delete("l")
      p "hello".delete("^l")
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "heo"
      "hello"
      "ho"
      "heo"
      "ll"
    OUT
  end

  it "string gsub empty pat" do
    result = ze0(<<~'RUBY')
      # Issue #850: String#gsub with empty pattern inserts the
      # replacement between every character (and at the start/end).
      # Pre-fix, empty pattern was a no-op.
      puts "hello".gsub("", "x")
      puts "abc".gsub("", "-")
    RUBY

    _(result).must_answer <<~'OUT'
      xhxexlxlxox
      -a-b-c-
    OUT
  end

  it "string range splat" do
    result = ze0(<<~'RUBY')
      # Splatting a string range into an array literal expands it into a
      # str_array (the runtime already has sp_StrArray_from_string_range; the
      # bug was the literal mis-typing to int_array and emitting a char*-in-
      # int-loop).
      p [*"a".."e"]
      p [*"a"..."d"]        # exclusive range drops the endpoint
      p [*"x".."z", "!"]    # splat-first, then a trailing literal
      p [*" ".."&"]         # the printable-ASCII idiom from the bug report
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c", "d", "e"]
      ["a", "b", "c"]
      ["x", "y", "z", "!"]
      [" ", "!", "\"", "#", "$", "%", "&"]
    OUT
  end

  it "string scan capture" do
    result = ze0(<<~'RUBY')
      # Issue #880: String#scan returns nested arrays for capture groups.

      puts "hello world".scan(/(\w+)/).inspect
      puts "a1 b22".scan(/([a-z]+)(\d+)/).inspect
      puts "hello world".scan(/\w+/).inspect
      puts "ab ac".scan(/a(?:b|c)/).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [["hello"], ["world"]]
      [["a", "1"], ["b", "22"]]
      ["hello", "world"]
      ["ab", "ac"]
    OUT
  end

  it "string spaceship" do
    result = ze0(<<~'RUBY')
      # Issue #900: String#<=> dispatches strcmp clamped to -1/0/1.
      # Pre-fix: always returned 0.
      puts "abc" <=> "abd"
      puts "abd" <=> "abc"
      puts "abc" <=> "abc"
      puts "ab" <=> "abc"
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      1
      0
      -1
    OUT
  end

  it "string squeeze multi arg" do
    result = ze0(<<~'RUBY')
      # String#squeeze with multiple args squeezes runs of chars in the
      # intersection of the charsets.
      p "aaabbbccc".squeeze("a", "b")
      p "aaabbbccc".squeeze("a", "ab")
      p "aaabbbccc".squeeze("abc")
      p "aaabbbccc".squeeze
    RUBY

    _(result).must_answer <<~'OUT'
      "aaabbbccc"
      "abbbccc"
      "abc"
      "abc"
    OUT
  end

  it "string strip nul" do
    result = ze0(<<~'RUBY')
      # String#strip / #lstrip / #rstrip remove the NUL byte along with ASCII
      # whitespace, matching CRuby.
      p "\0 abc \0".strip
      p "abc\0\0".rstrip
      p "\0\0abc".lstrip
      p "  \t\nx\r\f ".strip
      p "\0".strip
      p "no change".strip
    RUBY

    _(result).must_answer <<~'OUT'
      "abc"
      "abc"
      "abc"
      "x"
      ""
      "no change"
    OUT
  end

  it "string symbol itself" do
    result = ze0(<<~'RUBY')
      # Kernel#itself on string and symbol returns self.
      puts "hello".itself
      puts :foo.itself.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      :foo
    OUT
  end

  it "string tr s" do
    result = ze0(<<~'RUBY')
      # Issue #902: String#tr_s translates and squeezes adjacent
      # identical translated chars (untranslated runs keep their
      # duplicates).
      puts "hello".tr_s("l", "r")
      puts "aaabbbccc".tr_s("a", "x")
      # Without squeeze for comparison
      puts "hello".tr("l", "r")
      puts "aaabbb".tr_s("ab", "xy")
    RUBY

    _(result).must_answer <<~'OUT'
      hero
      xbbbccc
      herro
      xy
    OUT
  end

  it "string valid encoding" do
    result = ze0(<<~'RUBY')
      # String#valid_encoding? — true for ASCII / well-formed UTF-8,
      # false for invalid byte sequences.
      puts "hello".valid_encoding?
      puts "".valid_encoding?
      puts "日本語".valid_encoding?
      puts "\xff\xff".valid_encoding?
      puts "abc\xc3\x28".valid_encoding?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
    OUT
  end

  it "string with nul byte" do
    result = ze0(<<~'RUBY')
      # Issue #722: a string literal with an embedded NUL byte reports
      # the full length, and .bytes iterates all bytes (not strlen-
      # truncated at the NUL). Pre-fix the parser AST text format also
      # truncated the field at the NUL.
      puts "hello\0world".length
      puts "hello\0world".bytes.length
      puts "a\0b\0c".length
      puts "\0\0\0".length
    RUBY

    _(result).must_answer <<~'OUT'
      11
      11
      5
      3
    OUT
  end

  it "hash array string batch8" do
    result = ze0(<<~'RUBY')
      # Hash.try_convert, Array member?/entries/find_all/
      # grep(variable pattern or block)/chain, String tr_s!/delete_prefix!/
      # delete_suffix!/byteindex(Regexp)/dedup.

      # Hash class methods
      p(Hash.try_convert({ a: 1 }))
      p(Hash.try_convert("x"))
      p(Hash.try_convert(nil))

      # Array#member? (include? alias), #entries (to_a alias)
      p([1, nil, 2].member?(nil))
      p([].member?(1))
      p((1..3).member?(2))
      a = []
      p(a.entries)
      b = [1, 2]
      p(b.entries)

      # find_all is select (blockless enumerator chain and empty receiver)
      p([1, 2, 3].find_all.with_index { |x, i| i.even? })
      p([].find_all { |x| x > 0 })
      p([1, 2, 3, 4].find_all { |x| x.odd? })

      # grep/grep_v with variable Class/Range patterns and the block form
      cls = String
      p([1, "a", 2, "b"].grep(cls))
      r = 1..2
      p([1, "a", 2, "b"].grep(r))
      p([1, "a", 2, "b"].grep(Integer) { |x| x * 10 })
      p([1, "a", 2, "b"].grep_v(Integer))
      p([1, 2, 3].grep(2..3) { |x| x + 100 })

      # eager chain
      p([1, 2].chain([3, 4]).to_a)
      p([1, 2].chain([3], [4, 5]).to_a)

      # String bang mutators and byte searches
      p "hello".tr_s!("l", "r")
      p "hello".delete_prefix!("hel")
      p "hello".delete_suffix!("llo")
      p "abc".delete_prefix!("x")
      p "hello".byteindex("l")
      p "hello".byteindex(/l+/)
      p "hello".byterindex("l")
      p "hello".byterindex(/l+/)
      p "hello".byteindex(/x/)
      p "hello".dedup
      p "hello".dedup.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1}
      nil
      nil
      true
      false
      true
      []
      [1, 2]
      [1, 3]
      []
      [1, 3]
      ["a", "b"]
      [1, 2]
      [10, 20]
      ["a", "b"]
      [102, 103]
      [1, 2, 3, 4]
      [1, 2, 3, 4, 5]
      "hero"
      "lo"
      "he"
      nil
      2
      2
      3
      3
      nil
      "hello"
      true
    OUT
  end

  it "a root-scoped class constant is the === receiver for its own instances" do
    result = ze0(<<~'RUBY')
      p(::Integer === 7)
      p(::Integer === "x")
      p(::String === "a")
      p(::Float === 1.5)
      p(::Symbol === :s)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
    OUT
  end

  it "gsub and sub with a block hand the block the match and take what it answers" do
    result = ze0(<<~'RUBY')
      p "ab cd".gsub(/\b\w/) { |c| c.upcase }
      p "hello world".gsub(/\w+/) { |w| w.capitalize }
      p "a1b2c3".gsub(/(\d)/) { |m| ($1.to_i * 2).to_s }
      p "  x  ".gsub(/\bx\b/) { |m| "[#{m}]" }
      p "aaa".sub(/a/) { |m| "X" }
    RUBY

    _(result).must_answer <<~'OUT'
      "Ab Cd"
      "Hello World"
      "a2b4c6"
      "  [x]  "
      "Xaa"
    OUT
  end

  it "a multiple assignment destructures what a method returned" do
    result = ze0(<<~'RUBY')
      def k
        [5, [[1, 2, 3], [4, 5, 6]]]
      end
      total, chosen = k
      p total
      p chosen
      p chosen.sum { |_u, _v, w| w }

      def pair
        ["a", 7]
      end
      s, n = pair
      p s.upcase
      p n + 1
    RUBY

    _(result).must_answer <<~'OUT'
      5
      [[1, 2, 3], [4, 5, 6]]
      9
      "A"
      8
    OUT
  end

  it "flat_map flattens one level, whatever the block answers" do
    result = ze0(<<~'RUBY')
      p (1..3).flat_map { |x| x * 2 }
      p (1..3).flat_map { |x| [x, x] }
      p (1..4).flat_map { |x| x.even? ? [x, x] : x }
      p ("a".."c").flat_map { |s| s.upcase }
      p (1..3).collect_concat { |x| x + 1 }
      p [10, 20].flat_map { |x| x / 10 }
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6]
      [1, 1, 2, 2, 3, 3]
      [1, 2, 2, 3, 4, 4]
      ["A", "B", "C"]
      [2, 3, 4]
      [1, 2]
    OUT
  end

  it "each_line into each_with_object builds a Hash of the split lines" do
    result = ze0(<<~'RUBY')
      r = "a=b\nc=d".each_line.each_with_object({}) do |raw, config|
        key, value = raw.split("=", 2)
        config[key] = value
      end
      p r
    RUBY

    _(result).must_answer "{\"a\" => \"b\\n\", \"c\" => \"d\"}\n"
  end

  it "every in-place String mutator shows through an alias and through a container" do
    result = ze0(<<~'RUBY')
      # Shared-mutable strings: every in-place mutator shares through aliases and
      # containers (P1+P2 of the reference-semantics plan).
      s = "hello world"
      arr = [s]
      s << "!"
      s["world"] = "ruby"
      p arr[0]
      s.insert(0, ">> ")
      p arr[0]
      p s.slice!(0, 3)
      p arr[0]
      s.clear
      p arr[0]
      p arr[0].equal?(s)

      # bang-only alias set
      b1 = "low"
      b2 = b1
      b1.upcase!
      p b2
      # mixed alias set
      c1 = "a"
      c2 = c1
      c1 << "b"
      c1.upcase!
      p c2
      # replace via alias
      d1 = "abc"
      d2 = d1
      d1.replace("xyz")
      p d2
      # non-literal write into a shared set
      def make = "dyn" + "amic"
      e1 = make
      e2 = e1
      e1 << "!"
      p e2
      p e1.equal?(e2)
      # frozen source stays frozen through the handle
      f1 = make.freeze
      f2 = f1
      begin
        f1 << "x"
      rescue FrozenError
        p :frozen_ok
      end
      p f2
      # setbyte shares
      g1 = "Abc"
      g2 = g1
      g1.setbyte(0, 97)
      p g2
    RUBY

    _(result).must_answer <<~'OUT'
      "hello ruby!"
      ">> hello ruby!"
      ">> "
      "hello ruby!"
      ""
      true
      "LOW"
      "AB"
      "xyz"
      "dynamic!"
      true
      :frozen_ok
      "dynamic"
      "abc"
    OUT
  end

  it "concat through a reader fills the ivar array the constructor made" do
    result = ze0(<<~'RUBY')
      class Config
        def str(*opts) = add_flag(Flag.new(opts))
        def prepare! = @help_flag = add_flag(Flag.new(["x"]))
        def add_flag(flag) = flag
      end

      class Flag
        attr_reader :switches
        def initialize(opts)
          @switches = []
          switches.concat(opts)
        end
      end

      flag = Config.new.str("y")
      raise "FAIL" unless flag.switches == ["y"]
      puts "ok"
      f2 = Config.new.prepare!
      p f2.switches
    RUBY

    _(result).must_answer <<~'OUT'
      ok
      ["x"]
    OUT
  end

  it "a line built with + then appended to is stored whole" do
    result = ze0(<<~'RUBY')
      class Res
        attr_accessor :cookies
        def initialize
          @cookies = [""]
          @cookies.pop
        end

        def add(name, value)
          line = name + "=" + value
          line << "; HttpOnly"
          @cookies.push(line)
        end
      end

      res = Res.new
      res.add("flash", "hello")
      head = +""
      res.cookies.each do |line|
        head << "Set-Cookie: " + line + "\r\n"
      end
      print head

      class Res2
        attr_accessor :cookies
        def initialize
          @cookies = [""]
          @cookies.pop
        end

        def add(name, value)
          line = name + "=" + value
          ["; Path=/", "; HttpOnly", "; SameSite=Lax"].each { |a| line << a }
          @cookies.push(line)
        end
      end

      r2 = Res2.new
      r2.add("sid", "42")
      puts r2.cookies[0]
    RUBY

    _(result).must_answer <<~'OUT'
      Set-Cookie: flash=hello; HttpOnly
      sid=42; Path=/; HttpOnly; SameSite=Lax
    OUT
  end

  it "prepend and concat with no argument leave the string alone" do
    result = ze0(<<~'RUBY')
      m1 = +"hello"; r1 = (m1.prepend rescue $!.class); p r1
      f1 = "hello";  r2 = (f1.concat  rescue $!.class); p r2
      f2 = "hello";  r3 = (f2.prepend rescue $!.class); p r3
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "hello"
      "hello"
    OUT
  end

  it "string conformance batch3" do
    result = ze0(<<~'RUBY')
      # String#+ non-String -> TypeError; concat no-args -> self; match non-match
      # .class -> NilClass; frozen in-place bang -> FrozenError.
      p("ab".concat)
      begin; "a" + 1; rescue TypeError => e; puts e.message; end
      begin; "a" + nil; rescue TypeError => e; puts e.message; end
      begin; "a" + true; rescue TypeError => e; puts e.message; end
      p("a" + "b")
      p("hi".match(/z/).class)
      p("hi".match(/h/).class)
      s = "hi".freeze
      begin; s.upcase!; rescue FrozenError => e; puts "upcase!:#{e.class}"; end
      begin; s.sub!("h", "x"); rescue FrozenError => e; puts "sub!:#{e.class}"; end
      p s
    RUBY

    _(result).must_answer <<~'OUT'
      "ab"
      no implicit conversion of Integer into String
      no implicit conversion of nil into String
      no implicit conversion of true into String
      "ab"
      NilClass
      MatchData
      upcase!:FrozenError
      sub!:FrozenError
      "hi"
    OUT
  end

  it "string conformance batch4" do
    result = ze0(<<~'RUBY')
      # String conformance (KieranP #2308,#2310,#2312,#2313)
      p("hello".match?("l"))              # #2310 match? String pattern
      p("hello".match?("z"))
      p("hello".match("l").class)
      p("hello".match("z").class)
      p("a".gsub("a", "\\\\").bytes)      # #2312 doubled backslash collapse
      p("ab".gsub("a", "[\\&]"))
      p("a.b".sub(".", "\\\\"))
      p("\x02".inspect)                   # #2313 control byte -> \uNNNN
      p("\e".inspect)
      p("\a\b\t\n\v\f\r".inspect)
      p("\x00\x1c\x7f".inspect)
      begin                                # #2308 negative codepoint RangeError
        s = "a"; s << -1
        p :no_error
      rescue RangeError => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      MatchData
      NilClass
      [92]
      "[a]b"
      "a\\b"
      "\"\\u0002\""
      "\"\\e\""
      "\"\\a\\b\\t\\n\\v\\f\\r\""
      "\"\\u0000\\u001C\\u007F\""
      RangeError
    OUT
  end

  it "string conformance batch6" do
    result = ze0(<<~'RUBY')
      # String conformance (KieranP #2369, #2370)
      a = "abc".freeze
      p((-a).equal?(a))              # #2369 frozen receiver: -@ is identity
      s0 = "x" + "y"
      f = -s0
      p f.frozen?
      p((-("a" + "b")).equal?("a" + "b"))
      s = "hi"
      p(s[0] = "Y")                  # #2370 []= consumed as a value
      p s
      t = "hi"
      v = (t[0] = "Y")
      p v
      p t
      u = "hi"
      p(u[0, 2] = "AB")
      p u
      w = "abc"
      p(w["bc"] = "XY")
      p w
      x = "abcd"
      p(x[1..2] = "Z")
      p x
      p("abc".clear)                 # #2370 clear on a literal receiver
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      "Y"
      "Yi"
      "Y"
      "Yi"
      "AB"
      "AB"
      "XY"
      "aXY"
      "Z"
      "aZd"
      ""
    OUT
  end

  it "string conformance wave2" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # A String transform drops replacement characters ruby emits.
      #
      # Three more String surfaces from the conformance wave.

      # A Hash replacement in sub/gsub looks the match up with #[], so a miss takes
      # the hash's DEFAULT. The miss was hard-coded to the empty string.
      h = Hash.new("?")
      h["e"] = "3"
      p "hello".gsub(/[el]/, h)
      p "hello".sub(/[el]/, h)

      plain = { "e" => "3" }
      p "hello".gsub(/[el]/, plain)

      # `s[range] = v` with a beginless or endless bound: the sentinel was folded
      # through the negative-index fixup into a wild offset (RangeError)
      z = +"hello"
      z[..1] = "HE"
      p z

      y = +"hello"
      y[2..] = "LLO!"
      p y

      w = +"hello"
      w[1..2] = "X"
      p w

      v = +"hello"
      v[..-4] = "AB"
      p v

      u = +"hello"
      u[...2] = "Q"
      p u

      # split with a block iterates and answers the receiver, not the split array
      p("hello".split(",") { |piece| piece })
      out = []
      r = "a-b-c".split("-") { |piece| out << piece }
      p out
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      "h3??o"
      "h3llo"
      "h3o"
      "HEllo"
      "heLLO!"
      "hXlo"
      "ABllo"
      "Qllo"
      "hello"
      ["a", "b", "c"]
      "a-b-c"
    OUT
  end
end
