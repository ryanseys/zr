# frozen_string_literal: true

require "spec_helper"

describe "String: substitution" do
  it "gsub bang without a replacement answers an enumerator" do
    result = zr(<<~'RUBY')
      e = (+"hello world").gsub!(1)
      p e.class
      class P < String; end
      e2 = P.new("hello").gsub!("l")
      p e2.class
      p((+"hello").each_line.to_a)
      begin; (+"a").replace(1); rescue TypeError => e; p e.message; end
      begin; (+"a").replace(nil); rescue TypeError => e; p e.message; end
      o = Object.new; def o.to_str = "conv"
      p((+"a").replace(o))
      p (+"abc").gsub!(/b/).to_a

    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      Enumerator
      ["hello"]
      "no implicit conversion of Integer into String"
      "no implicit conversion of nil into String"
      "conv"
      ["b"]
    OUT
  end

  it "poly delete upcase chain" do
    result = zr(<<~'RUBY')
      # String#delete then #upcase on a value that widened to poly, in a program
      # where a user class (the bundled Set) also defines `delete`: the poly delete
      # must keep the string possibility (unify with the class dispatch) instead of
      # binding exclusively to the user class, and the boxed string transforms must
      # stay poly-typed. Doom's texture parser hits this chain on WAD name fields:
      # `data[offset, 8].delete("\x00").upcase`.
      require 'set'

      def maybe(s)
        return nil if s.empty?
        s
      end

      s = Set.new([1, :two])
      s.delete(1)
      p s.size

      data = maybe("ab\x00\x00cd\x00\x00")
      name = data[0, 4].delete("\x00").upcase
      puts name
      puts data[4, 4].delete("\x00").upcase

      # delete through a poly slot that actually holds the Set.
      mix = [s, "str"]
      ps = mix[0]
      ps.delete(2)
      p s.size

      # ... and one that holds a string.
      puts mix[1].delete("t")

      # The other boxed string transforms on a poly value.
      y = maybe(" Hi ")
      puts y.strip
      puts y.reverse.strip
      p maybe("word").upcase
    RUBY

    _(result).must_answer <<~'OUT'
      1
      AB
      CD
      1
      sr
      Hi
      iH
      "WORD"
    OUT
  end

  it "str delete count negation" do
    result = zr(<<~'RUBY')
      # String#delete and String#count with ^-negated charset
      # ^ at the start inverts the charset meaning.

      # delete: normal charset
      puts "hello".delete("l").inspect
      # delete: negated charset
      puts "hello".delete("^l").inspect

      # count: normal charset
      puts "hello".count("l")
      # count: negated charset
      puts "hello".count("^l")

      # a lone "^" is the literal caret, not negation
      puts "a^b^c".delete("^").inspect
      puts "a^b^c".count("^")
    RUBY

    _(result).must_answer <<~'OUT'
      "heo"
      "ll"
      2
      3
      "abc"
      2
    OUT
  end

  it "str squeeze arg" do
    result = zr(<<~'RUBY')
      # String#squeeze with charset argument
      # The argument restricts which characters get squeezed.
      # "a" squeezes only 'a', "^a" squeezes everything except 'a'.

      # no-arg squeeze (all consecutive)
      puts "aaabbbccc".squeeze.inspect
      # single char
      puts "aaabbbccc".squeeze("a").inspect
      # multiple chars
      puts "aaabbbccc".squeeze("ab").inspect
      # range
      puts "aaabbbccc".squeeze("a-c").inspect
      # negated set
      puts "aaabbbccc".squeeze("^a").inspect
      # no change case
      puts "abc".squeeze("a").inspect
      # a lone "^" is the literal caret, not a negation
      puts "aaa^^^bbb".squeeze("^").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "abc"
      "abbbccc"
      "abccc"
      "abc"
      "aaabc"
      "abc"
      "aaa^bbb"
    OUT
  end

  it "str tr negation" do
    result = zr(<<~'RUBY')
      # String#tr / tr_s with ^-negation in from-set
      # ^ at the start of from-set inverts which chars get translated.

      # tr with ^-negation
      puts "abc".tr("^a", "x").inspect
      puts "hello".tr("^aeiou", ".").inspect
      # tr without negation (positional mapping)
      puts "hello".tr("el", "ip").inspect
      # tr_s with ^-negation
      puts "hello".tr_s("^aeiou", ".").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "axx"
      ".e..o"
      "hippo"
      ".e.o"
    OUT
  end

  it "swapcase, delete_prefix and delete_suffix each answer a new string" do
    result = zr(<<~'RUBY')
      # String#swapcase, #delete_prefix, and #delete_suffix return new strings. Each
      # has a runtime helper already; this exercises the typed-String dispatch arms and
      # the inferred String return type (so the results chain and print). Receivers go
      # through a method param to defeat constant-folding.
      def ss(x); x; end

      # swapcase flips the case of each letter, leaving non-letters alone
      p ss("Hello World").swapcase
      p ss("aBcDeF 123").swapcase
      p ss("").swapcase

      # delete_prefix / delete_suffix remove a leading/trailing match, else unchanged
      p ss("hello").delete_prefix("he")
      p ss("hello").delete_prefix("xx")
      p ss("hello").delete_suffix("lo")
      p ss("hello").delete_suffix("xx")

      # they return Strings, so results chain
      p ss("hello").delete_prefix("he").delete_suffix("lo")
      p ss("Hello").swapcase.delete_prefix("h")

      # a non-literal argument works too
      affix = ss("foo")
      p ss("foobar").delete_prefix(affix)
    RUBY

    _(result).must_answer <<~'OUT'
      "hELLO wORLD"
      "AbCdEf 123"
      ""
      "llo"
      "hello"
      "hel"
      "hello"
      "l"
      "ELLO"
      "bar"
    OUT
  end

  it "a backslash in a tr or count character set escapes the next character rather than opening a range" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # A character-set escape in a String method argument is not expanded, so
      # the range collapses.
      #
      # A backslash in a tr/count/delete/squeeze character set escapes the next
      # character, so "a\\-b" holds the three members a, - and b rather than the
      # range a..b. The set parser had no escape at all.
      p "a-b".tr("a\\-b", "*")
      p "a-b".count("a\\-b")
      p "a-b".delete("a\\-b")
      p "abc".tr("a-c", "x")
      p "a-b".tr("-", "_")
      p "a\\b".count("\\\\")
      p "abc".count("a-c")
      p "hello".delete("l")
      p "hello".squeeze("l")
      p "hello".tr("el", "ip")
    RUBY

    _(result).must_answer <<~'OUT'
      "***"
      3
      ""
      "xxx"
      "a_b"
      1
      3
      "heo"
      "helo"
      "hippo"
    OUT
  end

  it "delete_prefix! and delete_suffix! change the receiver, and a frozen literal raises" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true
      # String#delete_prefix! / delete_suffix! on a mutable_str mutate in
      # place and return the receiver. On a frozen string literal they
      # raise FrozenError, consistent with chomp! / upcase! et al.
      s = String.new("hello")
      s.delete_prefix!("hel")
      puts s.to_s

      s2 = String.new("hello")
      s2.delete_suffix!("llo")
      puts s2.to_s

      # Non-matching prefix/suffix leaves the string unchanged.
      s3 = String.new("hello")
      s3.delete_prefix!("xyz")
      puts s3.to_s

      # Frozen string literals raise FrozenError.
      begin
        "hello".delete_prefix!("hel")
        puts "BUG: delete_prefix! no raise"
      rescue FrozenError => e
        puts "delete_prefix!: " + e.message
      end
      begin
        "hello".delete_suffix!("llo")
        puts "BUG: delete_suffix! no raise"
      rescue FrozenError => e
        puts "delete_suffix!: " + e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      lo
      he
      hello
      delete_prefix!: can't modify frozen String: "hello"
      delete_suffix!: can't modify frozen String: "hello"
    OUT
  end

  it "a blockless gsub is an Enumerator, and each_line takes any separator" do
    result = zr(<<~'RUBY')
      # Blockless String#gsub(/re/) is an Enumerator over the matches, and
      # each_line(sep) / lines(sep) split on an arbitrary separator (kept on
      # each segment) like CRuby.
      p "aaa".gsub(/a/).to_a
      p "a1b2".gsub(/\d/).to_a
      p "1-2-3".each_line("-").to_a
      p "1-2-3".lines("-")
      e = "x,y".each_line(",")
      p e.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "a", "a"]
      ["1", "2"]
      ["1-", "2-", "3"]
      ["1-", "2-", "3"]
      ["x,", "y"]
    OUT
  end

  it "replace, prepend, insert and clear change the string a local holds" do
    result = zr(<<~'RUBY')
      # String#replace / prepend / insert / clear mutate a string held in a
      # local variable. The analyzer widens such a local to a mutable_str
      # (or, for clear, reassigns it), so these match CRuby instead of being
      # no-ops. Both string-literal locals and String.new receivers work.
      s = "abc"
      s.replace("xyz")
      p s

      s2 = "world"
      s2.prepend("hello ")
      p s2

      s3 = "hlo"
      s3.insert(1, "el")
      p s3

      s4 = "hello"
      s4.clear
      p s4.length

      # String.new receivers mutate through the same paths.
      m = String.new("abc")
      m.replace("xyz")
      m.prepend("> ")
      p m

      m2 = String.new("hello")
      m2.clear
      p m2.length

      # insert with a negative index counts from the end.
      s5 = "abcd"
      s5.insert(-2, "X")
      p s5
    RUBY

    _(result).must_answer <<~'OUT'
      "xyz"
      "hello world"
      "hello"
      0
      "> xyz"
      0
      "abcXd"
    OUT
  end

  it "squeeze shrinks the header, so length and bytes report what is left" do
    result = zr(<<~'RUBY')
      # Issue #921: String#squeeze shrinks the heap-string header
      # so length / bytes report the post-squeeze size, not the
      # pre-squeeze allocation.
      s = "aaabbbccc"
      result = s.squeeze
      puts result.length
      puts result.bytes.inspect
      puts result.inspect

      # Trailing NULs leak the GC marker byte; ensure none.
      puts "xxxxx".squeeze.length
      puts "xxxxx".squeeze
    RUBY

    _(result).must_answer <<~'OUT'
      3
      [97, 98, 99]
      "abc"
      1
      x
    OUT
  end

  it "tr! answers nil when nothing moved, and the receiver when something did" do
    result = zr(<<~'RUBY')
      p (+"Hello").tr!("l", "l")
      p (+"Hello").tr!("z", "y")
      p (+"Hello").tr!("l", "L")
    RUBY

    _(result).must_answer <<~'OUT'
      "Hello"
      nil
      "HeLLo"
    OUT
  end

  it "a character repeated in tr's from takes its last corresponding to" do
    result = zr(<<~'RUBY')
      # A char repeated in `from` takes its LAST corresponding `to` char
      # (CRuby's rule) -- previously the FIRST mapping wrongly won.

      p "a___b".tr("___", ".+-")
      p "abcaa".tr("aa", "xy")
      p "abcd".tr("abc", "x")
    RUBY

    _(result).must_answer <<~'OUT'
      "a---b"
      "ybcyy"
      "xxxd"
    OUT
  end

  it "sub and gsub read a replacement in its own encoding" do
    result = zr(<<~'RUBY')
      # sub and gsub read a replacement's backslashes as CRuby's rb_reg_regsub
      # reads them: a character at a time in the replacement's own encoding,
      # so UTF-16 and UTF-32 replacements fill in their groups and a
      # Shift_JIS trail byte 0x5C is no backslash. What the pieces join into
      # follows the encodings of the text, the replacement and the groups.
      def show(label)
        value = yield
        p [label, value.encoding.name, value.b]
      rescue StandardError => e
        p [label, e.class, e.message]
      end

      show(:named_ref) { "ab".sub(/(?<x>a)/, "[\\k<x>]") }
      show(:unknown_name) { "ab".sub(/(?<x>a)/, "[\\k<y>]") }
      show(:open_name) { "ab".sub(/(?<x>a)/, "[\\k<x]") }
      show(:bare_k) { "ab".sub(/(a)/, "[\\k]") }
      show(:k_then_x) { "ab".sub(/(a)/, "[\\kx]") }
      show(:trailing) { "ab".sub(/a/, "x\\") }
      show(:double) { "ab".sub(/a/, "x\\\\y") }
      show(:past_groups) { "ab".sub(/(a)/, "[\\9]") }
      show(:plus_none) { "ab".sub(/a/, "[\\+]") }
      show(:plus_last) { "abc".sub(/(a)(x)?(b)?/, "[\\+]") }
      show(:numbered_under_names) { "ab".sub(/(?<x>a)(b)/, "[\\1|\\2]") }
      show(:string_pattern) { "ab".sub("a", "[\\0|\\1|\\&|\\`|\\']") }
      show(:string_pattern_name) { "ab".sub("a", "[\\k<a>]") }
      show(:duplicate_names) { "xy".gsub(/(?<a>x)|(?<a>y)/, "<\\k<a>>") }
      show(:other_escape) { "ab".sub(/a/, "\\q\\n") }
      show(:escaped_multibyte) { "ab".sub(/a/, "\\é") }
      show(:name_multibyte) { "ab".sub(/(?<é>a)/, "\\k<é>") }

      sjis = ->(s) { s.encode("Shift_JIS") }
      show(:sjis_trail) { sjis.("表a").sub(sjis.("a"), sjis.("表0")) }
      show(:sjis_group) { sjis.("表a").sub(Regexp.new(sjis.("(表)")), sjis.("\\1\\1")) }
      show(:sjis_gsub) { sjis.("ソ表ソ").gsub(Regexp.new(sjis.("ソ")), sjis.("表\\0")) }

      %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].each do |enc|
        u = ->(s) { s.encode(enc) }
        text = u.("héllo wörld")
        show(:"#{enc}_groups") { text.sub(Regexp.new(u.("(h)(é)")), u.("<\\2\\1\\0>")) }
        show(:"#{enc}_named") { text.gsub(Regexp.new(u.("(?<v>[éö])")), u.("[\\k<v>]")) }
        show(:"#{enc}_pre_post") { text.sub(Regexp.new(u.(" ")), u.("|\\'|\\`|")) }
        show(:"#{enc}_backslashes") { text.sub(Regexp.new(u.("o")), u.("\\\\\\x\\")) }
        show(:"#{enc}_plain") { text.gsub(Regexp.new(u.("l")), u.("L")) }
        show(:"#{enc}_bad_name") { text.sub(Regexp.new(u.("(?<v>h)")), u.("\\k<w>")) }
        show(:"#{enc}_open_name") { text.sub(Regexp.new(u.("(?<v>h)")), u.("\\k<v")) }
      end

      show(:utf16_into_utf8) { "abc".gsub("b", "x".encode("UTF-16LE")) }
      show(:utf16_into_utf8_sub_at_start) { "bc".sub("b", "x".encode("UTF-16LE")) }
      show(:utf16_into_utf8_sub_mid) { "abc".sub("b", "x".encode("UTF-16LE")) }
      show(:euc_into_ascii_utf8) { "abc".sub("b", "字".encode("EUC-JP")) }
      show(:euc_into_utf8) { "aéc".sub("c", "字".encode("EUC-JP")) }
      show(:euc_into_utf8_gsub) { "aéc".gsub("c", "字".encode("EUC-JP")) }
      show(:utf8_into_binary) { "a\xFFc".b.sub("c", "é") }
      show(:utf8_into_binary_gsub) { "abc".b.gsub("b", "é") }
      show(:group_of_binary) { "a\xFFc".b.sub(/(\xFF)/n, "é\\1") }
      show(:ascii_repl_utf16) { "héllo".encode("UTF-16LE").sub(Regexp.new("l".encode("UTF-16LE")), "L") }
      show(:block_utf16) { "abc".encode("UTF-32BE").gsub(Regexp.new("b".encode("UTF-32BE"))) { |m| m + m } }
      show(:hash_euc) { "abc".gsub(/b/, "b" => "字".encode("EUC-JP")) }
      show(:sub_bang) { s = +"hello".encode("UTF-16BE"); s.sub!(Regexp.new("(l+)".encode("UTF-16BE")), "<\\1>".encode("UTF-16BE")); s }
      show(:gsub_bang) { s = +"hello".encode("UTF-32LE"); s.gsub!(Regexp.new("l".encode("UTF-32LE")), "\\0\\0".encode("UTF-32LE")); s }

    RUBY

    _(result).must_answer <<~'OUT'
      [:named_ref, "UTF-8", "[a]b"]
      [:unknown_name, IndexError, "undefined group name reference: y"]
      [:open_name, RuntimeError, "invalid group name reference format"]
      [:bare_k, "UTF-8", "[\\k]b"]
      [:k_then_x, "UTF-8", "[\\kx]b"]
      [:trailing, "UTF-8", "x\\b"]
      [:double, "UTF-8", "x\\yb"]
      [:past_groups, "UTF-8", "[]b"]
      [:plus_none, "UTF-8", "[]b"]
      [:plus_last, "UTF-8", "[b]c"]
      [:numbered_under_names, "UTF-8", "[|]"]
      [:string_pattern, "UTF-8", "[a||a||b]b"]
      [:string_pattern_name, IndexError, "undefined group name reference: a"]
      [:duplicate_names, "UTF-8", "<x><y>"]
      [:other_escape, "UTF-8", "\\q\\nb"]
      [:escaped_multibyte, "UTF-8", "\\\xC3\xA9b"]
      [:name_multibyte, "UTF-8", "ab"]
      [:sjis_trail, "Shift_JIS", "\x95\\\x95\\0"]
      [:sjis_group, "Shift_JIS", "\x95\\\x95\\a"]
      [:sjis_gsub, "Shift_JIS", "\x95\\\x83\\\x95\\\x95\\\x83\\"]
      [:"UTF-16LE_groups", "UTF-16LE", "<\x00\xE9\x00h\x00h\x00\xE9\x00>\x00l\x00l\x00o\x00 \x00w\x00\xF6\x00r\x00l\x00d\x00"]
      [:"UTF-16LE_named", "UTF-16LE", "h\x00[\x00\xE9\x00]\x00l\x00l\x00o\x00 \x00w\x00[\x00\xF6\x00]\x00r\x00l\x00d\x00"]
      [:"UTF-16LE_pre_post", "UTF-16LE", "h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d\x00|\x00h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d\x00"]
      [:"UTF-16LE_backslashes", "UTF-16LE", "h\x00\xE9\x00l\x00l\x00\\\x00\\\x00x\x00\\\x00 \x00w\x00\xF6\x00r\x00l\x00d\x00"]
      [:"UTF-16LE_plain", "UTF-16LE", "h\x00\xE9\x00L\x00L\x00o\x00 \x00w\x00\xF6\x00r\x00L\x00d\x00"]
      [:"UTF-16LE_bad_name", IndexError, "undefined group name reference: w"]
      [:"UTF-16LE_open_name", RuntimeError, "invalid group name reference format"]
      [:"UTF-16BE_groups", "UTF-16BE", "\x00<\x00\xE9\x00h\x00h\x00\xE9\x00>\x00l\x00l\x00o\x00 \x00w\x00\xF6\x00r\x00l\x00d"]
      [:"UTF-16BE_named", "UTF-16BE", "\x00h\x00[\x00\xE9\x00]\x00l\x00l\x00o\x00 \x00w\x00[\x00\xF6\x00]\x00r\x00l\x00d"]
      [:"UTF-16BE_pre_post", "UTF-16BE", "\x00h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d\x00|\x00h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d"]
      [:"UTF-16BE_backslashes", "UTF-16BE", "\x00h\x00\xE9\x00l\x00l\x00\\\x00\\\x00x\x00\\\x00 \x00w\x00\xF6\x00r\x00l\x00d"]
      [:"UTF-16BE_plain", "UTF-16BE", "\x00h\x00\xE9\x00L\x00L\x00o\x00 \x00w\x00\xF6\x00r\x00L\x00d"]
      [:"UTF-16BE_bad_name", IndexError, "undefined group name reference: w"]
      [:"UTF-16BE_open_name", RuntimeError, "invalid group name reference format"]
      [:"UTF-32LE_groups", "UTF-32LE", "<\x00\x00\x00\xE9\x00\x00\x00h\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00>\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
      [:"UTF-32LE_named", "UTF-32LE", "h\x00\x00\x00[\x00\x00\x00\xE9\x00\x00\x00]\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00[\x00\x00\x00\xF6\x00\x00\x00]\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
      [:"UTF-32LE_pre_post", "UTF-32LE", "h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00|\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
      [:"UTF-32LE_backslashes", "UTF-32LE", "h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00\\\x00\x00\x00\\\x00\x00\x00x\x00\x00\x00\\\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
      [:"UTF-32LE_plain", "UTF-32LE", "h\x00\x00\x00\xE9\x00\x00\x00L\x00\x00\x00L\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00L\x00\x00\x00d\x00\x00\x00"]
      [:"UTF-32LE_bad_name", IndexError, "undefined group name reference: w"]
      [:"UTF-32LE_open_name", RuntimeError, "invalid group name reference format"]
      [:"UTF-32BE_groups", "UTF-32BE", "\x00\x00\x00<\x00\x00\x00\xE9\x00\x00\x00h\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00>\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
      [:"UTF-32BE_named", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00[\x00\x00\x00\xE9\x00\x00\x00]\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00[\x00\x00\x00\xF6\x00\x00\x00]\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
      [:"UTF-32BE_pre_post", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00|\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
      [:"UTF-32BE_backslashes", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00\\\x00\x00\x00\\\x00\x00\x00x\x00\x00\x00\\\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
      [:"UTF-32BE_plain", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00L\x00\x00\x00L\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00L\x00\x00\x00d"]
      [:"UTF-32BE_bad_name", IndexError, "undefined group name reference: w"]
      [:"UTF-32BE_open_name", RuntimeError, "invalid group name reference format"]
      [:utf16_into_utf8, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and UTF-16LE"]
      [:utf16_into_utf8_sub_at_start, "UTF-16LE", "x\x00c"]
      [:utf16_into_utf8_sub_mid, "UTF-16LE", "ax\x00c"]
      [:euc_into_ascii_utf8, "EUC-JP", "a\xBB\xFAc"]
      [:euc_into_utf8, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and EUC-JP"]
      [:euc_into_utf8_gsub, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and EUC-JP"]
      [:utf8_into_binary, Encoding::CompatibilityError, "incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8"]
      [:utf8_into_binary_gsub, "UTF-8", "a\xC3\xA9c"]
      [:group_of_binary, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)"]
      [:ascii_repl_utf16, Encoding::CompatibilityError, "incompatible character encodings: UTF-16LE and UTF-8"]
      [:block_utf16, "UTF-32BE", "\x00\x00\x00a\x00\x00\x00b\x00\x00\x00b\x00\x00\x00c"]
      [:hash_euc, "EUC-JP", "a\xBB\xFAc"]
      [:sub_bang, "UTF-16BE", "\x00h\x00e\x00<\x00l\x00l\x00>\x00o"]
      [:gsub_bang, "UTF-32LE", "h\x00\x00\x00e\x00\x00\x00l\x00\x00\x00l\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00"]
    OUT
  end

  it "tr family counts characters not bytes" do
    result = zr(<<~'RUBY')
      # tr, tr_s, count, delete and squeeze read a spec as characters, so a
      # multibyte character is one member of the set and one place in the
      # replacement. A range spans codepoints.
      p "あいう".tr("い", "X")
      p "あいう".tr("あ-う", "A-C")
      p "あいあいあ".count("あ")
      p "あいあいあ".delete("い")
      p "ああいいうう".squeeze
      p "あいう".count("^あ")
      p "あいう".delete("^あ")
      p "あいあ".squeeze("あ")
      p "\u{1F600}b".tr("\u{1F600}", "X")
      p "あああいいい".tr_s("あい", "AI")

      # The ASCII rules are unchanged.
      p "hello".tr("el", "ip")
      p "abc".tr("aa", "XY")
      p "abc".tr("^a", "Z")
      p "abc".tr("a-", "X")
      p "a-c".tr("\\-", "X")
      p "abc".tr("a", "")
      p "abc".tr("^", "X")
      p "abcdef".tr("a-cd", "1-4")
      p "abc".count("a-c", "^b")
      begin
        "abc".tr("c-a", "X")
      rescue ArgumentError => e
        p e.message
      end
      begin
        "abc".count(1)
      rescue TypeError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "あXう"
      "ACC"
      3
      "あああ"
      "あいう"
      2
      "あ"
      "あいあ"
      "Xb"
      "AI"
      "hippo"
      "Ybc"
      "aZZ"
      "Xbc"
      "aXc"
      "bc"
      "abc"
      "1234ef"
      2
      "invalid range \"c-a\" in string transliteration"
      "no implicit conversion of Integer into String"
    OUT
  end

  it "tr squeeze negation split block and chomp paragraph" do
    result = zr(<<~'RUBY')
      # `^`-negated tr/squeeze sets, split's block form (yields fields, returns
      # the receiver), and chomp("") paragraph mode.

      p "abc".tr("^a", "x")
      p "hello".tr("^aeiou", ".")
      p "aaabbbccc".squeeze("^a")
      p "aaa^^^bbb".squeeze("^")
      r = []
      "a,b,c".split(",") { |p| r << p.upcase }
      p r
      acc = 0
      ret = "aa-bbb-c".split("-") { |p| acc += p.length }
      p acc
      p ret.equal?("aa-bbb-c".dup) == false && ret == "aa-bbb-c"
      p "hello\r\n\r\n".chomp("")
      p "hello\r".chomp("")
    RUBY

    _(result).must_answer <<~'OUT'
      "axx"
      ".e..o"
      "aaabc"
      "aaa^bbb"
      ["A", "B", "C"]
      6
      true
      "hello"
      "hello\r"
    OUT
  end
end
