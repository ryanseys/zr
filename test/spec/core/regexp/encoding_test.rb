# frozen_string_literal: true

require "spec_helper"

describe "Regexp: encodings" do
  it "ascii escape inside a bracket class folds past ascii" do
    result = ze0(<<~'RUBY')
      p "ſ" =~ /[\w]/i
      p "K" =~ /[\w]/i
      p "ſ" =~ /[\w&&[a-z]]/i
      p "K" =~ /(?a)[[:word:]]/i
      p "ſ" =~ /[a-z\w]/i
      p "ſ" =~ /[^\W]/i
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      0
      nil
    OUT
  end

  it "class under i folds across ascii as onigmo does" do
    result = ze0(<<~'RUBY')
      # Under /i a class folds a character across ASCII (s and the long s, k and
      # the Kelvin sign) only where the class holds it by something other than
      # \w, [[:word:]], \p{ASCII} or a POSIX bracket read as ASCII.
      chars = ["s", "S", "ſ", "k", "K", "K", "é", "É", "ǅ", "ß", "ss", "1", "_", " ", "µ", "Μ"]
      pats = [/[\w]/i, /[\W]/i, /[^\w]/i, /[^\W]/i, /[a-z]/i, /[k]/i, /[s]/i, /[\w&&[^a-z]]/i, /[[:alpha:]]/i, /[[:^alpha:]]/i,
              /(?a)[[:alpha:]]/i, /(?a)[[:^alpha:]]/i, /(?u)[\w]/i, /[\p{ASCII}]/i, /[\P{ASCII}]/i, /[\d\w]/i, /[[:word:]]/i, /[ſ]/i,
              /[K]/i, /\w/i, /[a-z\W]/i, /[[:lower:]]/i, /(?a)[[:upper:]]/i, /[\s\w]/i, /[\w-]/i, /[-\w]/i, /[\wµ]/i,
              /[^[:^word:]]/i, /[[\w]]/i, /[a[\w]]/i, /(?i:[\w])/, /[\h]/i, /(?d)[\w]/i, /\A[\w]+\z/i]
      pats.each do |re|
        puts "#{re.inspect}: #{chars.map { |c| (c =~ re) ? 1 : 0 }.join}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      /[\w]/i: 1101100000111000
      /[\W]/i: 0010011111100111
      /[^\w]/i: 0010011111000111
      /[^\W]/i: 1101100000111000
      /[a-z]/i: 1111110000100000
      /[k]/i: 0001110000000000
      /[s]/i: 1110000000100000
      /[\w&&[^a-z]]/i: 1101100000111000
      /[[:alpha:]]/i: 1111111111100011
      /[[:^alpha:]]/i: 0000000000011100
      /(?a)[[:alpha:]]/i: 1101100000100000
      /(?a)[[:^alpha:]]/i: 0010011111111111
      /(?u)[\w]/i: 1111111111111011
      /[\p{ASCII}]/i: 1101100000111100
      /[\P{ASCII}]/i: 0010011111100011
      /[\d\w]/i: 1101100000111000
      /[[:word:]]/i: 1111111111111011
      /[ſ]/i: 1110000000100000
      /[K]/i: 0001110000000000
      /\w/i: 1101100000111000
      /[a-z\W]/i: 1111111111100111
      /[[:lower:]]/i: 1111111111100011
      /(?a)[[:upper:]]/i: 1101100000100000
      /[\s\w]/i: 1101100000111100
      /[\w-]/i: 1101100000111000
      /[-\w]/i: 1101100000111000
      /[\wµ]/i: 1101100000111011
      /[^[:^word:]]/i: 1111111111111011
      /[[\w]]/i: 1101100000111000
      /[a[\w]]/i: 1101100000111000
      /(?i:[\w])/: 1101100000111000
      /[\h]/i: 0000000000010000
      /(?d)[\w]/i: 1101100000111000
      /\A[\w]+\z/i: 1101100000111000
    OUT
  end

  it "onigmo unicode and backtracking edges" do
    result = ze0(<<~'RUBY')
      # Onigmo's own answers at the edges a port gets wrong: grapheme clusters,
      # multi-character case folds, property aliases, ASCII-range options in
      # classes, recursion with a level, absent groups, look-behind alternation
      # lengths, a backward search over multibyte text, \G under StringScanner,
      # and a line anchor at the end of text.
      require "strscan"

      p "🇯🇵🇺🇸👨‍👩‍👧e\u0301\r\n".scan(/\X/)
      p "e\u0301x".match(/\A\X/)[0].bytes
      p ["ss" =~ /ß/i, "ß" =~ /ss/i, "ﬁ" =~ /fi/i, "FI" =~ /ﬁ/i, "İ" =~ /i̇/i]
      p ["Ab" =~ /\p{Lu}\p{Ll}/, "a" =~ /\p{L}/, "日" =~ /\p{Han}/, "日" =~ /\p{In_CJK_Unified_Ideographs}/, "a" =~ /\p{^Alpha}/]
      p ["é" =~ /(?a)\w/, "é" =~ /(?u)\w/, "é" =~ /(?a)[\w]/, "é" =~ /[[:alpha:]]/, "é" =~ /(?a)[[:alpha:]]/, "é" =~ /(?a:\b)é/]
      p "((a))".match(/\A(?<p>\((?<i>\g<p>|a)\))\z/)&.captures
      p "abba".match(/\A(?<a>.)(?<b>.)\k<b>\k<a>\z/)&.named_captures
      p "xyyx".match(/\A(?<r>|.\g<r>\k<r+0>)\z/)&.[](0)
      p "/* a */ b */".match(%r{/\*(?~\*/)\*/})[0]
      p ["xab".match(/(?<=a|xa)b/)&.begin(0), "ab" =~ /(?<!c|dd)b/]
      p "日本語日本".rindex(/日/), "日本語日本".rindex(/本/, 3)
      s = StringScanner.new("aab")
      p [s.scan(/\Ga/), s.scan(/\Ga/), s.scan(/\Gb/), s.pos]
      p ["ab\ncd\n".rindex(/$/), "ab\n" =~ /\n$/, "\n" =~ /^$/, "ab\n".scan(/$/).size]
      p "a\nb".match(/a$\n^b/m)&.[](0)
      p ("(" * 100 + "a" + ")" * 100).then { |pat| Regexp.new(pat).match("a").size }
      p "aaa".match(/(a)(?:\1|b)*/)[0]

    RUBY

    _(result).must_answer <<~'OUT'
      ["🇯🇵", "🇺🇸", "👨‍👩‍👧", "é", "\r\n"]
      [101, 204, 129]
      [0, 0, 0, 0, 0]
      [0, 0, 0, 0, nil]
      [nil, 0, nil, 0, nil, nil]
      ["((a))", "(a)"]
      {"a" => "a", "b" => "b"}
      nil
      "/* a */"
      [2, 1]
      3
      1
      ["a", "a", "b", 3]
      [6, 2, 0, 2]
      "a\nb"
      101
      "aaa"
    OUT
  end

  it "reads each single byte encoding with its own classes and folds" do
    result = ze0(<<~'RUBY')
      # A Regexp over text in a single-byte encoding reads each byte with that
      # encoding's own tables: its word and POSIX classes, its lower-case
      # table under /i, and a sharp s that folds to "ss" where the encoding
      # says so. An encoding ruby replicates from ASCII-8BIT (IBM437,
      # macRoman, ...) knows ASCII alone.
      def re(source, enc, options = 0) = Regexp.new(source.encode(enc), options | Regexp::FIXEDENCODING)
      def show(match) = match && [match.byteoffset(0), match[0].encode("UTF-8")]

      latin = "Ünïcödé Straße".encode("ISO-8859-1")
      p show(re("\\w+", "ISO-8859-1").match(latin)), latin.scan(re("[[:upper:]]", "ISO-8859-1")).size
      p show(re("strasse", "ISO-8859-1", Regexp::IGNORECASE).match(latin)), show(re("ünï", "ISO-8859-1", Regexp::IGNORECASE).match(latin))
      p show(re("ß", "ISO-8859-1", Regexp::IGNORECASE).match("STRASSE".encode("ISO-8859-1")))
      p show(re("SS", "ISO-8859-15", Regexp::IGNORECASE).match("straße".encode("ISO-8859-15")))

      greek = "Καλημέρα ΚΌΣΜΕ".encode("ISO-8859-7")
      p show(re("κόσμε", "ISO-8859-7", Regexp::IGNORECASE).match(greek)), greek.scan(re("[[:lower:]]+", "ISO-8859-7")).map { _1.encode("UTF-8") }
      p show(re("\\w+$", "Windows-1253").match("Γειά σου".encode("Windows-1253")))

      cyrillic = "Привет МИР".encode("KOI8-R")
      p show(re("мир", "KOI8-R", Regexp::IGNORECASE).match(cyrillic)), cyrillic.split(re("\\s", "KOI8-R")).map { _1.encode("UTF-8") }
      p show(re("[а-я]+", "Windows-1251", Regexp::IGNORECASE).match("ПРИВЕТ".encode("Windows-1251")))
      p show(re("ї", "KOI8-U", Regexp::IGNORECASE).match("Ї".encode("KOI8-U")))
      p show(re("\\bмир\\b", "ISO-8859-5").match("привет мир!".encode("ISO-8859-5")))

      p show(re("ı", "Windows-1254", Regexp::IGNORECASE).match("I".encode("Windows-1254"))), show(re("i", "ISO-8859-9", Regexp::IGNORECASE).match("İ".encode("ISO-8859-9")))
      p show(re("ą+", "ISO-8859-2", Regexp::IGNORECASE).match("ĄĄą".encode("ISO-8859-2"))), show(re("ž", "Windows-1250", Regexp::IGNORECASE).match("Ž".encode("Windows-1250")))
      p show(re("š", "Windows-1257", Regexp::IGNORECASE).match("Š".encode("Windows-1257"))), show(re("ŵ", "ISO-8859-14", Regexp::IGNORECASE).match("Ŵ".encode("ISO-8859-14")))
      p show(re("\\w", "ISO-8859-6").match("ب".encode("ISO-8859-6"))), show(re("\\w", "ISO-8859-8").match("א".encode("ISO-8859-8")))
      p show(re("[[:alpha:]]", "TIS-620").match("ก".encode("TIS-620"))), show(re("\\w", "Windows-1255").match("א".encode("Windows-1255")))

      ibm = "\x80\x81ab".dup.force_encoding("IBM437")
      p re("\\w+", "IBM437").match(ibm).byteoffset(0), re("[\\x80-\\xff]+".b.force_encoding("IBM437"), "IBM437").match(ibm)&.byteoffset(0)
      p re("é", "macRoman", Regexp::IGNORECASE).match("É".encode("macRoman"))&.byteoffset(0)
      p "abc\xFF".dup.force_encoding("US-ASCII").valid_encoding?, (/b/ =~ "ab".encode("US-ASCII"))
      p (re("\\xe9".b, "ISO-8859-1") =~ "caf\xE9".dup.force_encoding("ISO-8859-1"))


    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], "n"]
      2
      [[8, 14], "Straße"]
      [[0, 3], "Ünï"]
      [[4, 6], "SS"]
      [[4, 5], "ß"]
      [[9, 14], "ΚΌΣΜΕ"]
      ["αλημέρα"]
      nil
      [[7, 10], "МИР"]
      ["Привет", "МИР"]
      [[0, 6], "ПРИВЕТ"]
      [[0, 1], "Ї"]
      [[7, 10], "мир"]
      nil
      [[0, 1], "İ"]
      [[0, 3], "ĄĄą"]
      [[0, 1], "Ž"]
      [[0, 1], "Š"]
      [[0, 1], "Ŵ"]
      nil
      nil
      [[0, 1], "ก"]
      nil
      [2, 4]
      [0, 2]
      nil
      false
      1
      3
    OUT
  end

  it "regex posix class" do
    result = ze0(<<~'RUBY')
      # POSIX bracket classes [[:name:]] inside char classes (W9 / B49).
      # Previously parsed as the literal set of characters in ":name:", so
      # they never matched. Now they compile to the corresponding ASCII ranges.

      # scan over each of the required class names
      p "Hi 12".scan(/[[:alpha:]]+/)
      p "a1 b2".scan(/[[:digit:]]+/)
      p "ab 12 CD".scan(/[[:alnum:]]+/)
      p "a\tb c\nd".scan(/[[:space:]]+/)
      p "Hello, World".scan(/[[:upper:]]/)
      p "Hello, World".scan(/[[:lower:]]/)

      # negated class: [^[:digit:]]
      p "a1b2c3".scan(/[^[:digit:]]+/)

      # combined with literals and ranges in the same bracket expression
      p "a1_b2".scan(/[[:alpha:]_]+/)

      # plain single match (not scan)
      p(/[[:alpha:]]+/.match("  word42")[0])
      p("42abc".match(/[[:alpha:]]+/)[0])

      # Non-constant subject path: route the subject string through a method
      # parameter so the call is not constant-folded at compile time, forcing
      # the runtime regex engine to evaluate the POSIX class. Both scan and a
      # single match are exercised.
      def scan_class(str) = str.scan(/[[:alpha:]]+/)
      def match_class(str) = str.match(/[[:digit:]]+/)[0]
      def scan_negated(str) = str.scan(/[^[:digit:]]+/)
      p scan_class("Hi 12")
      p match_class("a1 b2")
      p scan_negated("a1b2c3")

      # In-class negation [:^name:] (distinct from enclosing [^...]).
      p "a1b2c3 ".scan(/[[:^digit:]]/)
      p "Hello9".scan(/[[:^alpha:]]/)
      p "a1_ X".scan(/[[:^word:]]/)

      # [:ascii:] matches the ASCII range 0x00-0x7f.
      p "aZ9!".scan(/[[:ascii:]]/)

      # An unrecognized POSIX class name is a RegexpError, matching CRuby. The
      # error is only catchable through the dynamic (Regexp.new) path; a bad
      # literal aborts at load time like any other invalid regex literal.
      begin
        Regexp.new("[[:bogus:]]")
        puts "no error"
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["Hi"]
      ["1", "2"]
      ["ab", "12", "CD"]
      ["\t", " ", "\n"]
      ["H", "W"]
      ["e", "l", "l", "o", "o", "r", "l", "d"]
      ["a", "b", "c"]
      ["a", "_b"]
      "word"
      "abc"
      ["Hi"]
      "1"
      ["a", "b", "c"]
      ["a", "b", "c", " "]
      ["9"]
      [" "]
      ["a", "Z", "9", "!"]
      RegexpError: invalid POSIX bracket type: /[[:bogus:]]/
    OUT
  end

  it "regexp class and struct wire and roundtrip" do
    result = ze0(<<~'RUBY')
      # `/` (regexp source + option byte, `I`-wrapped for encoding), `c`/`m`
      # (class/module reference), and `S` (Struct: class symbol, member count,
      # member/value pairs).

      def wire(x) = Marshal.dump(x).bytes.join(",")
      def rt(x) = Marshal.load(Marshal.dump(x))
      puts wire(/ab.c/im)
      r = rt(/a\d+b/i)
      puts r.source
      puts r.options
      puts wire(String)
      p rt(String)
      p rt(Comparable)
      S = Struct.new(:a, :b)
      puts wire(S.new(1, 2))
      st = rt(S.new(10, "x"))
      p [st.a, st.b]
    RUBY

    _(result).must_answer <<~'OUT'
      4,8,73,47,9,97,98,46,99,5,6,58,6,69,70
      a\d+b
      1
      4,8,99,11,83,116,114,105,110,103
      String
      Comparable
      4,8,83,58,6,83,7,58,6,97,105,6,58,6,98,105,7
      [10, "x"]
    OUT
  end

  it "regexp control escape" do
    result = ze0(<<~'RUBY')
      # `\M-X`, `\C-X` and `\cX` are RUBY'S escapes, not the engine's. `re.c`
      # decodes them before the engine ever sees the pattern: `\M-` sets bit 0x80,
      # `\C-`/`\c` mask with 0x1f, and the two nest. The pattern's own encoding then
      # decides whether the byte they name is a whole character -- which is why
      # `\M-a` (0xE1) is "too short" in UTF-8, where it is half a character, and
      # `\M-\C-a` (0x81) is "invalid", a byte no UTF-8 character can start with.
      #
      # `#source` keeps the escape AS WRITTEN whatever the engine was handed.

      def t(label)
        r = begin
          yield.inspect
        rescue Exception => e
          "#{e.class}: #{e.message}"
        end
        puts format("%-22s %s", label, r)
      end

      t("M-a") { Regexp.new("\\M-a") =~ "a" }
      t("M-C-a") { Regexp.new("\\M-\\C-a") =~ "a" }
      t("in extended mode") { Regexp.new("\\M-a", Regexp::EXTENDED) }
      t("in a class") { Regexp.new("[\\M-a]") }

      t("C-a matches") { Regexp.new("\\C-a") =~ "\x01" }
      t("cA matches") { Regexp.new("\\cA") =~ "\x01" }
      t("C-a source") { Regexp.new("\\C-a").source.bytes }
      t("cA source") { Regexp.new("\\cA").source.bytes }
      t("C-a in a class") { Regexp.new("[\\C-a]") =~ "\x01" }

      t("M bare") { Regexp.new("\\M") }
      t("M- bare") { Regexp.new("\\M-") }
      t("c bare") { Regexp.new("\\c") }
      t("C bare") { Regexp.new("\\C") }
      t("Ca, no dash") { Regexp.new("\\Ca") }
      t("duplicate meta") { Regexp.new("\\M-\\M-a") }
      t("duplicate control") { Regexp.new("\\C-\\C-a") }

      # The inner escape may be any of the ordinary byte escapes.
      t("C- of an octal") { Regexp.new("\\C-\\101") =~ "\x01" }
      t("C- of a hex") { Regexp.new("\\C-\\x41") =~ "\x01" }
      t("C- of a tab") { Regexp.new("\\C-\\t") =~ "\x09" }
      t("bad hex") { Regexp.new("\\C-\\xZZ") }
      t("unknown inner") { Regexp.new("\\C-\\q") }

      # A doubled backslash is a literal backslash, not a prefix.
      t("escaped backslash M") { Regexp.new("\\\\M-a") =~ "\\M-a" }
    RUBY

    _(result).must_answer <<~'OUT'
      M-a                    RegexpError: too short escaped multibyte character: /\M-a/
      M-C-a                  RegexpError: invalid multibyte escape: /\M-\C-a/
      in extended mode       RegexpError: too short escaped multibyte character: /\M-a/x
      in a class             RegexpError: too short escaped multibyte character: /[\M-a]/
      C-a matches            0
      cA matches             0
      C-a source             [92, 67, 45, 97]
      cA source              [92, 99, 65]
      C-a in a class         0
      M bare                 RegexpError: too short meta escape: /\M/
      M- bare                RegexpError: too short meta escape: /\M-/
      c bare                 RegexpError: too short control escape: /\c/
      C bare                 RegexpError: too short control escape: /\C/
      Ca, no dash            RegexpError: too short control escape: /\Ca/
      duplicate meta         RegexpError: duplicate meta escape: /\M-\M-a/
      duplicate control      RegexpError: duplicate control escape: /\C-\C-a/
      C- of an octal         0
      C- of a hex            0
      C- of a tab            0
      bad hex                RegexpError: invalid hex escape: /\C-\xZZ/
      unknown inner          RegexpError: unexpected escape sequence: /\C-\q/
      escaped backslash M    0
    OUT
  end

  it "regexp methods read wide and legacy text by characters" do
    result = ze0(<<~'RUBY')
      # Every String method that takes a Regexp reads wide and legacy text a
      # character at a time: scan, split, index and rindex, byteindex,
      # partition, slice and []=, start_with?, match and match?, sub! and
      # gsub! with a Hash and a block, and the offsets a MatchData answers in
      # characters. UTF-16 and UTF-32 in both orders, CESU-8, GB18030, the
      # JIS and Korean and Chinese encodings, and a single-byte one.
      def shown(v)
        case v
        when String then v.valid_encoding? && v.encoding != Encoding::BINARY ? [v.encoding.name, v.encode("UTF-8")] : [v.encoding.name, v.b]
        when Array then v.map { |x| shown(x) }
        when Hash then v.to_h { |k, x| [shown(k), shown(x)] }
        when MatchData then [shown(v.to_a), v.begin(0), v.end(0), v.byteoffset(0), shown(v.pre_match), shown(v.post_match)]
        else v
        end
      end

      def show(label)
        p [label, shown(yield)]
      rescue StandardError => e
        p [label, e.class, e.message.b]
      end

      SAMPLES = {
        "UTF-16LE" => "Grüße, 世界! 😀 end", "UTF-16BE" => "Grüße, 世界! 😀 end",
        "UTF-32LE" => "Grüße, 世界! 😀 end", "UTF-32BE" => "Grüße, 世界! 😀 end",
        "CESU-8" => "Grüße, 世界! 😀 end", "GB18030" => "Grüße, 世界! 😀 end",
        "EUC-JP" => "カナ, 世界! ａ end", "Shift_JIS" => "カナ, 世界! ソ表 end", "Windows-31J" => "カナ, 世界! ①② end",
        "Big5" => "中文, 世界! 測試 end", "GBK" => "中文, 世界! 测试 end", "EUC-KR" => "한국, 세계! 어 end",
        "CP949" => "한국, 세계! 똠 end", "ISO-8859-7" => "Καλη, μέρα! ΑΒ end",
      }.freeze

      SAMPLES.each do |name, sample|
        e = ->(s) { s.encode(name) }
        r = ->(s) { Regexp.new(e.(s)) }
        text = e.(sample)
        word = sample[/\A[^,]+/]
        show(:"#{name}_scan") { text.scan(r.("\\S+")) }
        show(:"#{name}_scan_groups") { text.scan(r.("(\\S)(\\S)")) }
        show(:"#{name}_scan_empty") { e.(word).scan(r.("")).size }
        show(:"#{name}_split") { text.split(r.(",?\\s+")) }
        show(:"#{name}_split_empty") { e.(word).split(r.("")) }
        show(:"#{name}_split_limit") { text.split(r.("\\s"), 2) }
        show(:"#{name}_split_groups") { text.split(r.("(,)")) }
        show(:"#{name}_split_string") { text.split(e.(" ")) }
        show(:"#{name}_index") { [text.index(r.("!")), text.index(r.("\\s"), 5), text.rindex(r.("\\s")), text.rindex(r.("\\s"), 5)] }
        show(:"#{name}_byteindex") { [text.byteindex(r.("!")), text.byterindex(r.("\\s")), text.byteindex(e.("end"))] }
        show(:"#{name}_partition") { text.partition(r.(",\\s")) + text.rpartition(r.("\\s")) }
        show(:"#{name}_slice") { [text[r.("\\S+$")], text[r.("(\\S)(\\S)"), 2], text.slice(r.("!"))] }
        show(:"#{name}_start_with") { [text.start_with?(r.(word[0])), text.start_with?(r.("\\s")), text.end_with?(e.("end"))] }
        show(:"#{name}_match") { [text.match(r.("\\s(\\S+)\\s"), 3), text.match?(r.("!")), text =~ r.("!"), $~ && $~.begin(0)] }
        show(:"#{name}_match_at") { r.("\\S").match(text, 2) }
        show(:"#{name}_named") { m = r.("(?<a>\\S+),\\s(?<b>\\S+)").match(text); [m.named_captures, m.begin(:b), m.end(:a), m.values_at(1, 2)] }
        show(:"#{name}_sub_bang") { t = text.dup; [t.sub!(r.("\\s"), e.("_")), t.sub!(r.("zzz"), e.("_"))] }
        show(:"#{name}_gsub_hash") { text.gsub(r.("[!,]"), e.("!") => e.("?"), e.(",") => e.(";")) }
        show(:"#{name}_gsub_block") { text.gsub(r.("\\S+")) { |w| e.("<") + w + e.(">") } }
        show(:"#{name}_gsub_backref") { text.gsub(r.("(\\S)(\\S*)"), e.("\\2\\1")) }
        show(:"#{name}_aset") { t = text.dup; t[r.("\\s(\\S+)\\s"), 1] = e.("X"); t }
        show(:"#{name}_slice_bang") { t = text.dup; [t.slice!(r.("\\S+$")), t] }
        show(:"#{name}_delete_prefix") { [text.delete_prefix(e.(word)), text.delete_suffix(e.(" end"))] }
        show(:"#{name}_last_match") { text =~ r.("(\\S+)!"); [$1, $`, $', Regexp.last_match(0)] }
        show(:"#{name}_escape_union") { [Regexp.escape(e.("a.b")), Regexp.union(r.("a"), e.("."))] }
        show(:"#{name}_each_line") { e.("a\nb\n\nc").each_line.to_a + e.("a\nb\n\nc").each_line("").to_a + e.("a--b").each_line(e.("--")).to_a }
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [:"UTF-16LE_scan", [["UTF-16LE", "Grüße,"], ["UTF-16LE", "世界!"], ["UTF-16LE", "😀"], ["UTF-16LE", "end"]]]
      [:"UTF-16LE_scan_groups", [[["UTF-16LE", "G"], ["UTF-16LE", "r"]], [["UTF-16LE", "ü"], ["UTF-16LE", "ß"]], [["UTF-16LE", "e"], ["UTF-16LE", ","]], [["UTF-16LE", "世"], ["UTF-16LE", "界"]], [["UTF-16LE", "e"], ["UTF-16LE", "n"]]]]
      [:"UTF-16LE_scan_empty", 6]
      [:"UTF-16LE_split", [["UTF-16LE", "Grüße"], ["UTF-16LE", "世界!"], ["UTF-16LE", "😀"], ["UTF-16LE", "end"]]]
      [:"UTF-16LE_split_empty", [["UTF-16LE", "G"], ["UTF-16LE", "r"], ["UTF-16LE", "ü"], ["UTF-16LE", "ß"], ["UTF-16LE", "e"]]]
      [:"UTF-16LE_split_limit", [["UTF-16LE", "Grüße,"], ["UTF-16LE", "世界! 😀 end"]]]
      [:"UTF-16LE_split_groups", [["UTF-16LE", "Grüße"], ["UTF-16LE", ","], ["UTF-16LE", " 世界! 😀 end"]]]
      [:"UTF-16LE_split_string", [["UTF-16LE", "Grüße,"], ["UTF-16LE", "世界!"], ["UTF-16LE", "😀"], ["UTF-16LE", "end"]]]
      [:"UTF-16LE_index", [9, 6, 12, nil]]
      [:"UTF-16LE_byteindex", [18, 26, 28]]
      [:"UTF-16LE_partition", [["UTF-16LE", "Grüße"], ["UTF-16LE", ", "], ["UTF-16LE", "世界! 😀 end"], ["UTF-16LE", "Grüße, 世界! 😀"], ["UTF-16LE", " "], ["UTF-16LE", "end"]]]
      [:"UTF-16LE_slice", [["UTF-16LE", "end"], ["UTF-16LE", "r"], ["UTF-16LE", "!"]]]
      [:"UTF-16LE_start_with", [true, false, true]]
      [:"UTF-16LE_match", [[[["UTF-16LE", " 世界! "], ["UTF-16LE", "世界!"]], 6, 11, [12, 22], ["UTF-16LE", "Grüße,"], ["UTF-16LE", "😀 end"]], true, 9, 9]]
      [:"UTF-16LE_match_at", [[["UTF-16LE", "ü"]], 2, 3, [4, 6], ["UTF-16LE", "Gr"], ["UTF-16LE", "ße, 世界! 😀 end"]]]
      [:"UTF-16LE_named", IndexError, "undefined group name reference: b"]
      [:"UTF-16LE_sub_bang", [["UTF-16LE", "Grüße,_世界! 😀 end"], nil]]
      [:"UTF-16LE_gsub_hash", ["UTF-16LE", "Grüße; 世界? 😀 end"]]
      [:"UTF-16LE_gsub_block", ["UTF-16LE", "<Grüße,> <世界!> <😀> <end>"]]
      [:"UTF-16LE_gsub_backref", ["UTF-16LE", "rüße,G 界!世 😀 nde"]]
      [:"UTF-16LE_aset", ["UTF-16LE", "Grüße, X 😀 end"]]
      [:"UTF-16LE_slice_bang", [["UTF-16LE", "end"], ["UTF-16LE", "Grüße, 世界! 😀 "]]]
      [:"UTF-16LE_delete_prefix", [["UTF-16LE", ", 世界! 😀 end"], ["UTF-16LE", "Grüße, 世界! 😀"]]]
      [:"UTF-16LE_last_match", [["UTF-16LE", "世界"], ["UTF-16LE", "Grüße, "], ["UTF-16LE", " 😀 end"], ["UTF-16LE", "世界!"]]]
      [:"UTF-16LE_escape_union", [["UTF-16LE", "a\\.b"], /( ? - m i x : a ) | \ . /]]
      [:"UTF-16LE_each_line", [["UTF-16LE", "a\n"], ["UTF-16LE", "b\n"], ["UTF-16LE", "\n"], ["UTF-16LE", "c"], ["UTF-16LE", "a\nb\n\n"], ["UTF-16LE", "c"], ["UTF-16LE", "a--"], ["UTF-16LE", "b"]]]
      [:"UTF-16BE_scan", [["UTF-16BE", "Grüße,"], ["UTF-16BE", "世界!"], ["UTF-16BE", "😀"], ["UTF-16BE", "end"]]]
      [:"UTF-16BE_scan_groups", [[["UTF-16BE", "G"], ["UTF-16BE", "r"]], [["UTF-16BE", "ü"], ["UTF-16BE", "ß"]], [["UTF-16BE", "e"], ["UTF-16BE", ","]], [["UTF-16BE", "世"], ["UTF-16BE", "界"]], [["UTF-16BE", "e"], ["UTF-16BE", "n"]]]]
      [:"UTF-16BE_scan_empty", 6]
      [:"UTF-16BE_split", [["UTF-16BE", "Grüße"], ["UTF-16BE", "世界!"], ["UTF-16BE", "😀"], ["UTF-16BE", "end"]]]
      [:"UTF-16BE_split_empty", [["UTF-16BE", "G"], ["UTF-16BE", "r"], ["UTF-16BE", "ü"], ["UTF-16BE", "ß"], ["UTF-16BE", "e"]]]
      [:"UTF-16BE_split_limit", [["UTF-16BE", "Grüße,"], ["UTF-16BE", "世界! 😀 end"]]]
      [:"UTF-16BE_split_groups", [["UTF-16BE", "Grüße"], ["UTF-16BE", ","], ["UTF-16BE", " 世界! 😀 end"]]]
      [:"UTF-16BE_split_string", [["UTF-16BE", "Grüße,"], ["UTF-16BE", "世界!"], ["UTF-16BE", "😀"], ["UTF-16BE", "end"]]]
      [:"UTF-16BE_index", [9, 6, 12, nil]]
      [:"UTF-16BE_byteindex", [18, 26, 28]]
      [:"UTF-16BE_partition", [["UTF-16BE", "Grüße"], ["UTF-16BE", ", "], ["UTF-16BE", "世界! 😀 end"], ["UTF-16BE", "Grüße, 世界! 😀"], ["UTF-16BE", " "], ["UTF-16BE", "end"]]]
      [:"UTF-16BE_slice", [["UTF-16BE", "end"], ["UTF-16BE", "r"], ["UTF-16BE", "!"]]]
      [:"UTF-16BE_start_with", [true, false, true]]
      [:"UTF-16BE_match", [[[["UTF-16BE", " 世界! "], ["UTF-16BE", "世界!"]], 6, 11, [12, 22], ["UTF-16BE", "Grüße,"], ["UTF-16BE", "😀 end"]], true, 9, 9]]
      [:"UTF-16BE_match_at", [[["UTF-16BE", "ü"]], 2, 3, [4, 6], ["UTF-16BE", "Gr"], ["UTF-16BE", "ße, 世界! 😀 end"]]]
      [:"UTF-16BE_named", IndexError, "undefined group name reference: b"]
      [:"UTF-16BE_sub_bang", [["UTF-16BE", "Grüße,_世界! 😀 end"], nil]]
      [:"UTF-16BE_gsub_hash", ["UTF-16BE", "Grüße; 世界? 😀 end"]]
      [:"UTF-16BE_gsub_block", ["UTF-16BE", "<Grüße,> <世界!> <😀> <end>"]]
      [:"UTF-16BE_gsub_backref", ["UTF-16BE", "rüße,G 界!世 😀 nde"]]
      [:"UTF-16BE_aset", ["UTF-16BE", "Grüße, X 😀 end"]]
      [:"UTF-16BE_slice_bang", [["UTF-16BE", "end"], ["UTF-16BE", "Grüße, 世界! 😀 "]]]
      [:"UTF-16BE_delete_prefix", [["UTF-16BE", ", 世界! 😀 end"], ["UTF-16BE", "Grüße, 世界! 😀"]]]
      [:"UTF-16BE_last_match", [["UTF-16BE", "世界"], ["UTF-16BE", "Grüße, "], ["UTF-16BE", " 😀 end"], ["UTF-16BE", "世界!"]]]
      [:"UTF-16BE_escape_union", [["UTF-16BE", "a\\.b"], / ( ? - m i x : a ) | \ ./]]
      [:"UTF-16BE_each_line", [["UTF-16BE", "a\n"], ["UTF-16BE", "b\n"], ["UTF-16BE", "\n"], ["UTF-16BE", "c"], ["UTF-16BE", "a\nb\n\n"], ["UTF-16BE", "c"], ["UTF-16BE", "a--"], ["UTF-16BE", "b"]]]
      [:"UTF-32LE_scan", [["UTF-32LE", "Grüße,"], ["UTF-32LE", "世界!"], ["UTF-32LE", "😀"], ["UTF-32LE", "end"]]]
      [:"UTF-32LE_scan_groups", [[["UTF-32LE", "G"], ["UTF-32LE", "r"]], [["UTF-32LE", "ü"], ["UTF-32LE", "ß"]], [["UTF-32LE", "e"], ["UTF-32LE", ","]], [["UTF-32LE", "世"], ["UTF-32LE", "界"]], [["UTF-32LE", "e"], ["UTF-32LE", "n"]]]]
      [:"UTF-32LE_scan_empty", 6]
      [:"UTF-32LE_split", [["UTF-32LE", "Grüße"], ["UTF-32LE", "世界!"], ["UTF-32LE", "😀"], ["UTF-32LE", "end"]]]
      [:"UTF-32LE_split_empty", [["UTF-32LE", "G"], ["UTF-32LE", "r"], ["UTF-32LE", "ü"], ["UTF-32LE", "ß"], ["UTF-32LE", "e"]]]
      [:"UTF-32LE_split_limit", [["UTF-32LE", "Grüße,"], ["UTF-32LE", "世界! 😀 end"]]]
      [:"UTF-32LE_split_groups", [["UTF-32LE", "Grüße"], ["UTF-32LE", ","], ["UTF-32LE", " 世界! 😀 end"]]]
      [:"UTF-32LE_split_string", [["UTF-32LE", "Grüße,"], ["UTF-32LE", "世界!"], ["UTF-32LE", "😀"], ["UTF-32LE", "end"]]]
      [:"UTF-32LE_index", [9, 6, 12, nil]]
      [:"UTF-32LE_byteindex", [36, 48, 52]]
      [:"UTF-32LE_partition", [["UTF-32LE", "Grüße"], ["UTF-32LE", ", "], ["UTF-32LE", "世界! 😀 end"], ["UTF-32LE", "Grüße, 世界! 😀"], ["UTF-32LE", " "], ["UTF-32LE", "end"]]]
      [:"UTF-32LE_slice", [["UTF-32LE", "end"], ["UTF-32LE", "r"], ["UTF-32LE", "!"]]]
      [:"UTF-32LE_start_with", [true, false, true]]
      [:"UTF-32LE_match", [[[["UTF-32LE", " 世界! "], ["UTF-32LE", "世界!"]], 6, 11, [24, 44], ["UTF-32LE", "Grüße,"], ["UTF-32LE", "😀 end"]], true, 9, 9]]
      [:"UTF-32LE_match_at", [[["UTF-32LE", "ü"]], 2, 3, [8, 12], ["UTF-32LE", "Gr"], ["UTF-32LE", "ße, 世界! 😀 end"]]]
      [:"UTF-32LE_named", IndexError, "undefined group name reference: b"]
      [:"UTF-32LE_sub_bang", [["UTF-32LE", "Grüße,_世界! 😀 end"], nil]]
      [:"UTF-32LE_gsub_hash", ["UTF-32LE", "Grüße; 世界? 😀 end"]]
      [:"UTF-32LE_gsub_block", ["UTF-32LE", "<Grüße,> <世界!> <😀> <end>"]]
      [:"UTF-32LE_gsub_backref", ["UTF-32LE", "rüße,G 界!世 😀 nde"]]
      [:"UTF-32LE_aset", ["UTF-32LE", "Grüße, X 😀 end"]]
      [:"UTF-32LE_slice_bang", [["UTF-32LE", "end"], ["UTF-32LE", "Grüße, 世界! 😀 "]]]
      [:"UTF-32LE_delete_prefix", [["UTF-32LE", ", 世界! 😀 end"], ["UTF-32LE", "Grüße, 世界! 😀"]]]
      [:"UTF-32LE_last_match", [["UTF-32LE", "世界"], ["UTF-32LE", "Grüße, "], ["UTF-32LE", " 😀 end"], ["UTF-32LE", "世界!"]]]
      [:"UTF-32LE_escape_union", [["UTF-32LE", "a\\.b"], /(   ?   -   m   i   x   :   a   )   |   \   .   /]]
      [:"UTF-32LE_each_line", [["UTF-32LE", "a\n"], ["UTF-32LE", "b\n"], ["UTF-32LE", "\n"], ["UTF-32LE", "c"], ["UTF-32LE", "a\nb\n\n"], ["UTF-32LE", "c"], ["UTF-32LE", "a--"], ["UTF-32LE", "b"]]]
      [:"UTF-32BE_scan", [["UTF-32BE", "Grüße,"], ["UTF-32BE", "世界!"], ["UTF-32BE", "😀"], ["UTF-32BE", "end"]]]
      [:"UTF-32BE_scan_groups", [[["UTF-32BE", "G"], ["UTF-32BE", "r"]], [["UTF-32BE", "ü"], ["UTF-32BE", "ß"]], [["UTF-32BE", "e"], ["UTF-32BE", ","]], [["UTF-32BE", "世"], ["UTF-32BE", "界"]], [["UTF-32BE", "e"], ["UTF-32BE", "n"]]]]
      [:"UTF-32BE_scan_empty", 6]
      [:"UTF-32BE_split", [["UTF-32BE", "Grüße"], ["UTF-32BE", "世界!"], ["UTF-32BE", "😀"], ["UTF-32BE", "end"]]]
      [:"UTF-32BE_split_empty", [["UTF-32BE", "G"], ["UTF-32BE", "r"], ["UTF-32BE", "ü"], ["UTF-32BE", "ß"], ["UTF-32BE", "e"]]]
      [:"UTF-32BE_split_limit", [["UTF-32BE", "Grüße,"], ["UTF-32BE", "世界! 😀 end"]]]
      [:"UTF-32BE_split_groups", [["UTF-32BE", "Grüße"], ["UTF-32BE", ","], ["UTF-32BE", " 世界! 😀 end"]]]
      [:"UTF-32BE_split_string", [["UTF-32BE", "Grüße,"], ["UTF-32BE", "世界!"], ["UTF-32BE", "😀"], ["UTF-32BE", "end"]]]
      [:"UTF-32BE_index", [9, 6, 12, nil]]
      [:"UTF-32BE_byteindex", [36, 48, 52]]
      [:"UTF-32BE_partition", [["UTF-32BE", "Grüße"], ["UTF-32BE", ", "], ["UTF-32BE", "世界! 😀 end"], ["UTF-32BE", "Grüße, 世界! 😀"], ["UTF-32BE", " "], ["UTF-32BE", "end"]]]
      [:"UTF-32BE_slice", [["UTF-32BE", "end"], ["UTF-32BE", "r"], ["UTF-32BE", "!"]]]
      [:"UTF-32BE_start_with", [true, false, true]]
      [:"UTF-32BE_match", [[[["UTF-32BE", " 世界! "], ["UTF-32BE", "世界!"]], 6, 11, [24, 44], ["UTF-32BE", "Grüße,"], ["UTF-32BE", "😀 end"]], true, 9, 9]]
      [:"UTF-32BE_match_at", [[["UTF-32BE", "ü"]], 2, 3, [8, 12], ["UTF-32BE", "Gr"], ["UTF-32BE", "ße, 世界! 😀 end"]]]
      [:"UTF-32BE_named", IndexError, "undefined group name reference: b"]
      [:"UTF-32BE_sub_bang", [["UTF-32BE", "Grüße,_世界! 😀 end"], nil]]
      [:"UTF-32BE_gsub_hash", ["UTF-32BE", "Grüße; 世界? 😀 end"]]
      [:"UTF-32BE_gsub_block", ["UTF-32BE", "<Grüße,> <世界!> <😀> <end>"]]
      [:"UTF-32BE_gsub_backref", ["UTF-32BE", "rüße,G 界!世 😀 nde"]]
      [:"UTF-32BE_aset", ["UTF-32BE", "Grüße, X 😀 end"]]
      [:"UTF-32BE_slice_bang", [["UTF-32BE", "end"], ["UTF-32BE", "Grüße, 世界! 😀 "]]]
      [:"UTF-32BE_delete_prefix", [["UTF-32BE", ", 世界! 😀 end"], ["UTF-32BE", "Grüße, 世界! 😀"]]]
      [:"UTF-32BE_last_match", [["UTF-32BE", "世界"], ["UTF-32BE", "Grüße, "], ["UTF-32BE", " 😀 end"], ["UTF-32BE", "世界!"]]]
      [:"UTF-32BE_escape_union", [["UTF-32BE", "a\\.b"], /   (   ?   -   m   i   x   :   a   )   |   \   ./]]
      [:"UTF-32BE_each_line", [["UTF-32BE", "a\n"], ["UTF-32BE", "b\n"], ["UTF-32BE", "\n"], ["UTF-32BE", "c"], ["UTF-32BE", "a\nb\n\n"], ["UTF-32BE", "c"], ["UTF-32BE", "a--"], ["UTF-32BE", "b"]]]
      [:"CESU-8_scan", [["CESU-8", "Grüße,"], ["CESU-8", "世界!"], ["CESU-8", "😀"], ["CESU-8", "end"]]]
      [:"CESU-8_scan_groups", [[["CESU-8", "G"], ["CESU-8", "r"]], [["CESU-8", "ü"], ["CESU-8", "ß"]], [["CESU-8", "e"], ["CESU-8", ","]], [["CESU-8", "世"], ["CESU-8", "界"]], [["CESU-8", "e"], ["CESU-8", "n"]]]]
      [:"CESU-8_scan_empty", 6]
      [:"CESU-8_split", [["CESU-8", "Grüße"], ["CESU-8", "世界!"], ["CESU-8", "😀"], ["CESU-8", "end"]]]
      [:"CESU-8_split_empty", [["CESU-8", "G"], ["CESU-8", "r"], ["CESU-8", "ü"], ["CESU-8", "ß"], ["CESU-8", "e"]]]
      [:"CESU-8_split_limit", [["CESU-8", "Grüße,"], ["CESU-8", "世界! 😀 end"]]]
      [:"CESU-8_split_groups", [["CESU-8", "Grüße"], ["CESU-8", ","], ["CESU-8", " 世界! 😀 end"]]]
      [:"CESU-8_split_string", [["CESU-8", "Grüße,"], ["CESU-8", "世界!"], ["CESU-8", "😀"], ["CESU-8", "end"]]]
      [:"CESU-8_index", [9, 6, 12, nil]]
      [:"CESU-8_byteindex", [15, 23, 24]]
      [:"CESU-8_partition", [["CESU-8", "Grüße"], ["CESU-8", ", "], ["CESU-8", "世界! 😀 end"], ["CESU-8", "Grüße, 世界! 😀"], ["CESU-8", " "], ["CESU-8", "end"]]]
      [:"CESU-8_slice", [["CESU-8", "end"], ["CESU-8", "r"], ["CESU-8", "!"]]]
      [:"CESU-8_start_with", [true, false, true]]
      [:"CESU-8_match", [[[["CESU-8", " 世界! "], ["CESU-8", "世界!"]], 6, 11, [8, 17], ["CESU-8", "Grüße,"], ["CESU-8", "😀 end"]], true, 9, 9]]
      [:"CESU-8_match_at", [[["CESU-8", "ü"]], 2, 3, [2, 4], ["CESU-8", "Gr"], ["CESU-8", "ße, 世界! 😀 end"]]]
      [:"CESU-8_named", [{["CESU-8", "a"] => ["CESU-8", "Grüße"], ["CESU-8", "b"] => ["CESU-8", "世界!"]}, 7, 5, [["CESU-8", "Grüße"], ["CESU-8", "世界!"]]]]
      [:"CESU-8_sub_bang", [["CESU-8", "Grüße,_世界! 😀 end"], nil]]
      [:"CESU-8_gsub_hash", ["CESU-8", "Grüße; 世界? 😀 end"]]
      [:"CESU-8_gsub_block", ["CESU-8", "<Grüße,> <世界!> <😀> <end>"]]
      [:"CESU-8_gsub_backref", ["CESU-8", "rüße,G 界!世 😀 nde"]]
      [:"CESU-8_aset", ["CESU-8", "Grüße, X 😀 end"]]
      [:"CESU-8_slice_bang", [["CESU-8", "end"], ["CESU-8", "Grüße, 世界! 😀 "]]]
      [:"CESU-8_delete_prefix", [["CESU-8", ", 世界! 😀 end"], ["CESU-8", "Grüße, 世界! 😀"]]]
      [:"CESU-8_last_match", [["CESU-8", "世界"], ["CESU-8", "Grüße, "], ["CESU-8", " 😀 end"], ["CESU-8", "世界!"]]]
      [:"CESU-8_escape_union", [["US-ASCII", "a\\.b"], /(?-mix:a)|\./]]
      [:"CESU-8_each_line", [["CESU-8", "a\n"], ["CESU-8", "b\n"], ["CESU-8", "\n"], ["CESU-8", "c"], ["CESU-8", "a\nb\n\n"], ["CESU-8", "c"], ["CESU-8", "a--"], ["CESU-8", "b"]]]
      [:GB18030_scan, [["GB18030", "Grüße,"], ["GB18030", "世界!"], ["GB18030", "😀"], ["GB18030", "end"]]]
      [:GB18030_scan_groups, [[["GB18030", "G"], ["GB18030", "r"]], [["GB18030", "ü"], ["GB18030", "ß"]], [["GB18030", "e"], ["GB18030", ","]], [["GB18030", "世"], ["GB18030", "界"]], [["GB18030", "e"], ["GB18030", "n"]]]]
      [:GB18030_scan_empty, 6]
      [:GB18030_split, [["GB18030", "Grüße"], ["GB18030", "世界!"], ["GB18030", "😀"], ["GB18030", "end"]]]
      [:GB18030_split_empty, [["GB18030", "G"], ["GB18030", "r"], ["GB18030", "ü"], ["GB18030", "ß"], ["GB18030", "e"]]]
      [:GB18030_split_limit, [["GB18030", "Grüße,"], ["GB18030", "世界! 😀 end"]]]
      [:GB18030_split_groups, [["GB18030", "Grüße"], ["GB18030", ","], ["GB18030", " 世界! 😀 end"]]]
      [:GB18030_split_string, [["GB18030", "Grüße,"], ["GB18030", "世界!"], ["GB18030", "😀"], ["GB18030", "end"]]]
      [:GB18030_index, [9, 6, 12, nil]]
      [:GB18030_byteindex, [15, 21, 22]]
      [:GB18030_partition, [["GB18030", "Grüße"], ["GB18030", ", "], ["GB18030", "世界! 😀 end"], ["GB18030", "Grüße, 世界! 😀"], ["GB18030", " "], ["GB18030", "end"]]]
      [:GB18030_slice, [["GB18030", "end"], ["GB18030", "r"], ["GB18030", "!"]]]
      [:GB18030_start_with, [true, false, true]]
      [:GB18030_match, [[[["GB18030", " 世界! "], ["GB18030", "世界!"]], 6, 11, [10, 17], ["GB18030", "Grüße,"], ["GB18030", "😀 end"]], true, 9, 9]]
      [:GB18030_match_at, [[["GB18030", "ü"]], 2, 3, [2, 4], ["GB18030", "Gr"], ["GB18030", "ße, 世界! 😀 end"]]]
      [:GB18030_named, [{["GB18030", "a"] => ["GB18030", "Grüße"], ["GB18030", "b"] => ["GB18030", "世界!"]}, 7, 5, [["GB18030", "Grüße"], ["GB18030", "世界!"]]]]
      [:GB18030_sub_bang, [["GB18030", "Grüße,_世界! 😀 end"], nil]]
      [:GB18030_gsub_hash, ["GB18030", "Grüße; 世界? 😀 end"]]
      [:GB18030_gsub_block, ["GB18030", "<Grüße,> <世界!> <😀> <end>"]]
      [:GB18030_gsub_backref, ["GB18030", "rüße,G 界!世 😀 nde"]]
      [:GB18030_aset, ["GB18030", "Grüße, X 😀 end"]]
      [:GB18030_slice_bang, [["GB18030", "end"], ["GB18030", "Grüße, 世界! 😀 "]]]
      [:GB18030_delete_prefix, [["GB18030", ", 世界! 😀 end"], ["GB18030", "Grüße, 世界! 😀"]]]
      [:GB18030_last_match, [["GB18030", "世界"], ["GB18030", "Grüße, "], ["GB18030", " 😀 end"], ["GB18030", "世界!"]]]
      [:GB18030_escape_union, [["US-ASCII", "a\\.b"], /(?-mix:a)|\./]]
      [:GB18030_each_line, [["GB18030", "a\n"], ["GB18030", "b\n"], ["GB18030", "\n"], ["GB18030", "c"], ["GB18030", "a\nb\n\n"], ["GB18030", "c"], ["GB18030", "a--"], ["GB18030", "b"]]]
      [:"EUC-JP_scan", [["EUC-JP", "カナ,"], ["EUC-JP", "世界!"], ["EUC-JP", "ａ"], ["EUC-JP", "end"]]]
      [:"EUC-JP_scan_groups", [[["EUC-JP", "カ"], ["EUC-JP", "ナ"]], [["EUC-JP", "世"], ["EUC-JP", "界"]], [["EUC-JP", "e"], ["EUC-JP", "n"]]]]
      [:"EUC-JP_scan_empty", 3]
      [:"EUC-JP_split", [["EUC-JP", "カナ"], ["EUC-JP", "世界!"], ["EUC-JP", "ａ"], ["EUC-JP", "end"]]]
      [:"EUC-JP_split_empty", [["EUC-JP", "カ"], ["EUC-JP", "ナ"]]]
      [:"EUC-JP_split_limit", [["EUC-JP", "カナ,"], ["EUC-JP", "世界! ａ end"]]]
      [:"EUC-JP_split_groups", [["EUC-JP", "カナ"], ["EUC-JP", ","], ["EUC-JP", " 世界! ａ end"]]]
      [:"EUC-JP_split_string", [["EUC-JP", "カナ,"], ["EUC-JP", "世界!"], ["EUC-JP", "ａ"], ["EUC-JP", "end"]]]
      [:"EUC-JP_index", [6, 7, 9, 3]]
      [:"EUC-JP_byteindex", [10, 14, 15]]
      [:"EUC-JP_partition", [["EUC-JP", "カナ"], ["EUC-JP", ", "], ["EUC-JP", "世界! ａ end"], ["EUC-JP", "カナ, 世界! ａ"], ["EUC-JP", " "], ["EUC-JP", "end"]]]
      [:"EUC-JP_slice", [["EUC-JP", "end"], ["EUC-JP", "ナ"], ["EUC-JP", "!"]]]
      [:"EUC-JP_start_with", [true, false, true]]
      [:"EUC-JP_match", [[[["EUC-JP", " 世界! "], ["EUC-JP", "世界!"]], 3, 8, [5, 12], ["EUC-JP", "カナ,"], ["EUC-JP", "ａ end"]], true, 6, 6]]
      [:"EUC-JP_match_at", [[["EUC-JP", ","]], 2, 3, [4, 5], ["EUC-JP", "カナ"], ["EUC-JP", " 世界! ａ end"]]]
      [:"EUC-JP_named", [{["EUC-JP", "a"] => ["EUC-JP", "カナ"], ["EUC-JP", "b"] => ["EUC-JP", "世界!"]}, 4, 2, [["EUC-JP", "カナ"], ["EUC-JP", "世界!"]]]]
      [:"EUC-JP_sub_bang", [["EUC-JP", "カナ,_世界! ａ end"], nil]]
      [:"EUC-JP_gsub_hash", ["EUC-JP", "カナ; 世界? ａ end"]]
      [:"EUC-JP_gsub_block", ["EUC-JP", "<カナ,> <世界!> <ａ> <end>"]]
      [:"EUC-JP_gsub_backref", ["EUC-JP", "ナ,カ 界!世 ａ nde"]]
      [:"EUC-JP_aset", ["EUC-JP", "カナ, X ａ end"]]
      [:"EUC-JP_slice_bang", [["EUC-JP", "end"], ["EUC-JP", "カナ, 世界! ａ "]]]
      [:"EUC-JP_delete_prefix", [["EUC-JP", ", 世界! ａ end"], ["EUC-JP", "カナ, 世界! ａ"]]]
      [:"EUC-JP_last_match", [["EUC-JP", "世界"], ["EUC-JP", "カナ, "], ["EUC-JP", " ａ end"], ["EUC-JP", "世界!"]]]
      [:"EUC-JP_escape_union", [["US-ASCII", "a\\.b"], /(?-mix:a)|\./]]
      [:"EUC-JP_each_line", [["EUC-JP", "a\n"], ["EUC-JP", "b\n"], ["EUC-JP", "\n"], ["EUC-JP", "c"], ["EUC-JP", "a\nb\n\n"], ["EUC-JP", "c"], ["EUC-JP", "a--"], ["EUC-JP", "b"]]]
      [:Shift_JIS_scan, [["Shift_JIS", "カナ,"], ["Shift_JIS", "世界!"], ["Shift_JIS", "ソ表"], ["Shift_JIS", "end"]]]
      [:Shift_JIS_scan_groups, [[["Shift_JIS", "カ"], ["Shift_JIS", "ナ"]], [["Shift_JIS", "世"], ["Shift_JIS", "界"]], [["Shift_JIS", "ソ"], ["Shift_JIS", "表"]], [["Shift_JIS", "e"], ["Shift_JIS", "n"]]]]
      [:Shift_JIS_scan_empty, 3]
      [:Shift_JIS_split, [["Shift_JIS", "カナ"], ["Shift_JIS", "世界!"], ["Shift_JIS", "ソ表"], ["Shift_JIS", "end"]]]
      [:Shift_JIS_split_empty, [["Shift_JIS", "カ"], ["Shift_JIS", "ナ"]]]
      [:Shift_JIS_split_limit, [["Shift_JIS", "カナ,"], ["Shift_JIS", "世界! ソ表 end"]]]
      [:Shift_JIS_split_groups, [["Shift_JIS", "カナ"], ["Shift_JIS", ","], ["Shift_JIS", " 世界! ソ表 end"]]]
      [:Shift_JIS_split_string, [["Shift_JIS", "カナ,"], ["Shift_JIS", "世界!"], ["Shift_JIS", "ソ表"], ["Shift_JIS", "end"]]]
      [:Shift_JIS_index, [6, 7, 10, 3]]
      [:Shift_JIS_byteindex, [10, 16, 17]]
      [:Shift_JIS_partition, [["Shift_JIS", "カナ"], ["Shift_JIS", ", "], ["Shift_JIS", "世界! ソ表 end"], ["Shift_JIS", "カナ, 世界! ソ表"], ["Shift_JIS", " "], ["Shift_JIS", "end"]]]
      [:Shift_JIS_slice, [["Shift_JIS", "end"], ["Shift_JIS", "ナ"], ["Shift_JIS", "!"]]]
      [:Shift_JIS_start_with, [true, false, true]]
      [:Shift_JIS_match, [[[["Shift_JIS", " 世界! "], ["Shift_JIS", "世界!"]], 3, 8, [5, 12], ["Shift_JIS", "カナ,"], ["Shift_JIS", "ソ表 end"]], true, 6, 6]]
      [:Shift_JIS_match_at, [[["Shift_JIS", ","]], 2, 3, [4, 5], ["Shift_JIS", "カナ"], ["Shift_JIS", " 世界! ソ表 end"]]]
      [:Shift_JIS_named, [{["Shift_JIS", "a"] => ["Shift_JIS", "カナ"], ["Shift_JIS", "b"] => ["Shift_JIS", "世界!"]}, 4, 2, [["Shift_JIS", "カナ"], ["Shift_JIS", "世界!"]]]]
      [:Shift_JIS_sub_bang, [["Shift_JIS", "カナ,_世界! ソ表 end"], nil]]
      [:Shift_JIS_gsub_hash, ["Shift_JIS", "カナ; 世界? ソ表 end"]]
      [:Shift_JIS_gsub_block, ["Shift_JIS", "<カナ,> <世界!> <ソ表> <end>"]]
      [:Shift_JIS_gsub_backref, ["Shift_JIS", "ナ,カ 界!世 表ソ nde"]]
      [:Shift_JIS_aset, ["Shift_JIS", "カナ, X ソ表 end"]]
      [:Shift_JIS_slice_bang, [["Shift_JIS", "end"], ["Shift_JIS", "カナ, 世界! ソ表 "]]]
      [:Shift_JIS_delete_prefix, [["Shift_JIS", ", 世界! ソ表 end"], ["Shift_JIS", "カナ, 世界! ソ表"]]]
      [:Shift_JIS_last_match, [["Shift_JIS", "世界"], ["Shift_JIS", "カナ, "], ["Shift_JIS", " ソ表 end"], ["Shift_JIS", "世界!"]]]
      [:Shift_JIS_escape_union, [["US-ASCII", "a\\.b"], /(?-mix:a)|\./]]
      [:Shift_JIS_each_line, [["Shift_JIS", "a\n"], ["Shift_JIS", "b\n"], ["Shift_JIS", "\n"], ["Shift_JIS", "c"], ["Shift_JIS", "a\nb\n\n"], ["Shift_JIS", "c"], ["Shift_JIS", "a--"], ["Shift_JIS", "b"]]]
      [:"Windows-31J_scan", [["Windows-31J", "カナ,"], ["Windows-31J", "世界!"], ["Windows-31J", "①②"], ["Windows-31J", "end"]]]
      [:"Windows-31J_scan_groups", [[["Windows-31J", "カ"], ["Windows-31J", "ナ"]], [["Windows-31J", "世"], ["Windows-31J", "界"]], [["Windows-31J", "①"], ["Windows-31J", "②"]], [["Windows-31J", "e"], ["Windows-31J", "n"]]]]
      [:"Windows-31J_scan_empty", 3]
      [:"Windows-31J_split", [["Windows-31J", "カナ"], ["Windows-31J", "世界!"], ["Windows-31J", "①②"], ["Windows-31J", "end"]]]
      [:"Windows-31J_split_empty", [["Windows-31J", "カ"], ["Windows-31J", "ナ"]]]
      [:"Windows-31J_split_limit", [["Windows-31J", "カナ,"], ["Windows-31J", "世界! ①② end"]]]
      [:"Windows-31J_split_groups", [["Windows-31J", "カナ"], ["Windows-31J", ","], ["Windows-31J", " 世界! ①② end"]]]
      [:"Windows-31J_split_string", [["Windows-31J", "カナ,"], ["Windows-31J", "世界!"], ["Windows-31J", "①②"], ["Windows-31J", "end"]]]
      [:"Windows-31J_index", [6, 7, 10, 3]]
      [:"Windows-31J_byteindex", [10, 16, 17]]
      [:"Windows-31J_partition", [["Windows-31J", "カナ"], ["Windows-31J", ", "], ["Windows-31J", "世界! ①② end"], ["Windows-31J", "カナ, 世界! ①②"], ["Windows-31J", " "], ["Windows-31J", "end"]]]
      [:"Windows-31J_slice", [["Windows-31J", "end"], ["Windows-31J", "ナ"], ["Windows-31J", "!"]]]
      [:"Windows-31J_start_with", [true, false, true]]
      [:"Windows-31J_match", [[[["Windows-31J", " 世界! "], ["Windows-31J", "世界!"]], 3, 8, [5, 12], ["Windows-31J", "カナ,"], ["Windows-31J", "①② end"]], true, 6, 6]]
      [:"Windows-31J_match_at", [[["Windows-31J", ","]], 2, 3, [4, 5], ["Windows-31J", "カナ"], ["Windows-31J", " 世界! ①② end"]]]
      [:"Windows-31J_named", [{["Windows-31J", "a"] => ["Windows-31J", "カナ"], ["Windows-31J", "b"] => ["Windows-31J", "世界!"]}, 4, 2, [["Windows-31J", "カナ"], ["Windows-31J", "世界!"]]]]
      [:"Windows-31J_sub_bang", [["Windows-31J", "カナ,_世界! ①② end"], nil]]
      [:"Windows-31J_gsub_hash", ["Windows-31J", "カナ; 世界? ①② end"]]
      [:"Windows-31J_gsub_block", ["Windows-31J", "<カナ,> <世界!> <①②> <end>"]]
      [:"Windows-31J_gsub_backref", ["Windows-31J", "ナ,カ 界!世 ②① nde"]]
      [:"Windows-31J_aset", ["Windows-31J", "カナ, X ①② end"]]
      [:"Windows-31J_slice_bang", [["Windows-31J", "end"], ["Windows-31J", "カナ, 世界! ①② "]]]
      [:"Windows-31J_delete_prefix", [["Windows-31J", ", 世界! ①② end"], ["Windows-31J", "カナ, 世界! ①②"]]]
      [:"Windows-31J_last_match", [["Windows-31J", "世界"], ["Windows-31J", "カナ, "], ["Windows-31J", " ①② end"], ["Windows-31J", "世界!"]]]
      [:"Windows-31J_escape_union", [["US-ASCII", "a\\.b"], /(?-mix:a)|\./]]
      [:"Windows-31J_each_line", [["Windows-31J", "a\n"], ["Windows-31J", "b\n"], ["Windows-31J", "\n"], ["Windows-31J", "c"], ["Windows-31J", "a\nb\n\n"], ["Windows-31J", "c"], ["Windows-31J", "a--"], ["Windows-31J", "b"]]]
      [:Big5_scan, [["Big5", "中文,"], ["Big5", "世界!"], ["Big5", "測試"], ["Big5", "end"]]]
      [:Big5_scan_groups, [[["Big5", "中"], ["Big5", "文"]], [["Big5", "世"], ["Big5", "界"]], [["Big5", "測"], ["Big5", "試"]], [["Big5", "e"], ["Big5", "n"]]]]
      [:Big5_scan_empty, 3]
      [:Big5_split, [["Big5", "中文"], ["Big5", "世界!"], ["Big5", "測試"], ["Big5", "end"]]]
      [:Big5_split_empty, [["Big5", "中"], ["Big5", "文"]]]
      [:Big5_split_limit, [["Big5", "中文,"], ["Big5", "世界! 測試 end"]]]
      [:Big5_split_groups, [["Big5", "中文"], ["Big5", ","], ["Big5", " 世界! 測試 end"]]]
      [:Big5_split_string, [["Big5", "中文,"], ["Big5", "世界!"], ["Big5", "測試"], ["Big5", "end"]]]
      [:Big5_index, [6, 7, 10, 3]]
      [:Big5_byteindex, [10, 16, 17]]
      [:Big5_partition, [["Big5", "中文"], ["Big5", ", "], ["Big5", "世界! 測試 end"], ["Big5", "中文, 世界! 測試"], ["Big5", " "], ["Big5", "end"]]]
      [:Big5_slice, [["Big5", "end"], ["Big5", "文"], ["Big5", "!"]]]
      [:Big5_start_with, [true, false, true]]
      [:Big5_match, [[[["Big5", " 世界! "], ["Big5", "世界!"]], 3, 8, [5, 12], ["Big5", "中文,"], ["Big5", "測試 end"]], true, 6, 6]]
      [:Big5_match_at, [[["Big5", ","]], 2, 3, [4, 5], ["Big5", "中文"], ["Big5", " 世界! 測試 end"]]]
      [:Big5_named, [{["Big5", "a"] => ["Big5", "中文"], ["Big5", "b"] => ["Big5", "世界!"]}, 4, 2, [["Big5", "中文"], ["Big5", "世界!"]]]]
      [:Big5_sub_bang, [["Big5", "中文,_世界! 測試 end"], nil]]
      [:Big5_gsub_hash, ["Big5", "中文; 世界? 測試 end"]]
      [:Big5_gsub_block, ["Big5", "<中文,> <世界!> <測試> <end>"]]
      [:Big5_gsub_backref, ["Big5", "文,中 界!世 試測 nde"]]
      [:Big5_aset, ["Big5", "中文, X 測試 end"]]
      [:Big5_slice_bang, [["Big5", "end"], ["Big5", "中文, 世界! 測試 "]]]
      [:Big5_delete_prefix, [["Big5", ", 世界! 測試 end"], ["Big5", "中文, 世界! 測試"]]]
      [:Big5_last_match, [["Big5", "世界"], ["Big5", "中文, "], ["Big5", " 測試 end"], ["Big5", "世界!"]]]
      [:Big5_escape_union, [["US-ASCII", "a\\.b"], /(?-mix:a)|\./]]
      [:Big5_each_line, [["Big5", "a\n"], ["Big5", "b\n"], ["Big5", "\n"], ["Big5", "c"], ["Big5", "a\nb\n\n"], ["Big5", "c"], ["Big5", "a--"], ["Big5", "b"]]]
      [:GBK_scan, [["GBK", "中文,"], ["GBK", "世界!"], ["GBK", "测试"], ["GBK", "end"]]]
      [:GBK_scan_groups, [[["GBK", "中"], ["GBK", "文"]], [["GBK", "世"], ["GBK", "界"]], [["GBK", "测"], ["GBK", "试"]], [["GBK", "e"], ["GBK", "n"]]]]
      [:GBK_scan_empty, 3]
      [:GBK_split, [["GBK", "中文"], ["GBK", "世界!"], ["GBK", "测试"], ["GBK", "end"]]]
      [:GBK_split_empty, [["GBK", "中"], ["GBK", "文"]]]
      [:GBK_split_limit, [["GBK", "中文,"], ["GBK", "世界! 测试 end"]]]
      [:GBK_split_groups, [["GBK", "中文"], ["GBK", ","], ["GBK", " 世界! 测试 end"]]]
      [:GBK_split_string, [["GBK", "中文,"], ["GBK", "世界!"], ["GBK", "测试"], ["GBK", "end"]]]
      [:GBK_index, [6, 7, 10, 3]]
      [:GBK_byteindex, [10, 16, 17]]
      [:GBK_partition, [["GBK", "中文"], ["GBK", ", "], ["GBK", "世界! 测试 end"], ["GBK", "中文, 世界! 测试"], ["GBK", " "], ["GBK", "end"]]]
      [:GBK_slice, [["GBK", "end"], ["GBK", "文"], ["GBK", "!"]]]
      [:GBK_start_with, [true, false, true]]
      [:GBK_match, [[[["GBK", " 世界! "], ["GBK", "世界!"]], 3, 8, [5, 12], ["GBK", "中文,"], ["GBK", "测试 end"]], true, 6, 6]]
      [:GBK_match_at, [[["GBK", ","]], 2, 3, [4, 5], ["GBK", "中文"], ["GBK", " 世界! 测试 end"]]]
      [:GBK_named, [{["GBK", "a"] => ["GBK", "中文"], ["GBK", "b"] => ["GBK", "世界!"]}, 4, 2, [["GBK", "中文"], ["GBK", "世界!"]]]]
      [:GBK_sub_bang, [["GBK", "中文,_世界! 测试 end"], nil]]
      [:GBK_gsub_hash, ["GBK", "中文; 世界? 测试 end"]]
      [:GBK_gsub_block, ["GBK", "<中文,> <世界!> <测试> <end>"]]
      [:GBK_gsub_backref, ["GBK", "文,中 界!世 试测 nde"]]
      [:GBK_aset, ["GBK", "中文, X 测试 end"]]
      [:GBK_slice_bang, [["GBK", "end"], ["GBK", "中文, 世界! 测试 "]]]
      [:GBK_delete_prefix, [["GBK", ", 世界! 测试 end"], ["GBK", "中文, 世界! 测试"]]]
      [:GBK_last_match, [["GBK", "世界"], ["GBK", "中文, "], ["GBK", " 测试 end"], ["GBK", "世界!"]]]
      [:GBK_escape_union, [["US-ASCII", "a\\.b"], /(?-mix:a)|\./]]
      [:GBK_each_line, [["GBK", "a\n"], ["GBK", "b\n"], ["GBK", "\n"], ["GBK", "c"], ["GBK", "a\nb\n\n"], ["GBK", "c"], ["GBK", "a--"], ["GBK", "b"]]]
      [:"EUC-KR_scan", [["EUC-KR", "한국,"], ["EUC-KR", "세계!"], ["EUC-KR", "어"], ["EUC-KR", "end"]]]
      [:"EUC-KR_scan_groups", [[["EUC-KR", "한"], ["EUC-KR", "국"]], [["EUC-KR", "세"], ["EUC-KR", "계"]], [["EUC-KR", "e"], ["EUC-KR", "n"]]]]
      [:"EUC-KR_scan_empty", 3]
      [:"EUC-KR_split", [["EUC-KR", "한국"], ["EUC-KR", "세계!"], ["EUC-KR", "어"], ["EUC-KR", "end"]]]
      [:"EUC-KR_split_empty", [["EUC-KR", "한"], ["EUC-KR", "국"]]]
      [:"EUC-KR_split_limit", [["EUC-KR", "한국,"], ["EUC-KR", "세계! 어 end"]]]
      [:"EUC-KR_split_groups", [["EUC-KR", "한국"], ["EUC-KR", ","], ["EUC-KR", " 세계! 어 end"]]]
      [:"EUC-KR_split_string", [["EUC-KR", "한국,"], ["EUC-KR", "세계!"], ["EUC-KR", "어"], ["EUC-KR", "end"]]]
      [:"EUC-KR_index", [6, 7, 9, 3]]
      [:"EUC-KR_byteindex", [10, 14, 15]]
      [:"EUC-KR_partition", [["EUC-KR", "한국"], ["EUC-KR", ", "], ["EUC-KR", "세계! 어 end"], ["EUC-KR", "한국, 세계! 어"], ["EUC-KR", " "], ["EUC-KR", "end"]]]
      [:"EUC-KR_slice", [["EUC-KR", "end"], ["EUC-KR", "국"], ["EUC-KR", "!"]]]
      [:"EUC-KR_start_with", [true, false, true]]
      [:"EUC-KR_match", [[[["EUC-KR", " 세계! "], ["EUC-KR", "세계!"]], 3, 8, [5, 12], ["EUC-KR", "한국,"], ["EUC-KR", "어 end"]], true, 6, 6]]
      [:"EUC-KR_match_at", [[["EUC-KR", ","]], 2, 3, [4, 5], ["EUC-KR", "한국"], ["EUC-KR", " 세계! 어 end"]]]
      [:"EUC-KR_named", [{["EUC-KR", "a"] => ["EUC-KR", "한국"], ["EUC-KR", "b"] => ["EUC-KR", "세계!"]}, 4, 2, [["EUC-KR", "한국"], ["EUC-KR", "세계!"]]]]
      [:"EUC-KR_sub_bang", [["EUC-KR", "한국,_세계! 어 end"], nil]]
      [:"EUC-KR_gsub_hash", ["EUC-KR", "한국; 세계? 어 end"]]
      [:"EUC-KR_gsub_block", ["EUC-KR", "<한국,> <세계!> <어> <end>"]]
      [:"EUC-KR_gsub_backref", ["EUC-KR", "국,한 계!세 어 nde"]]
      [:"EUC-KR_aset", ["EUC-KR", "한국, X 어 end"]]
      [:"EUC-KR_slice_bang", [["EUC-KR", "end"], ["EUC-KR", "한국, 세계! 어 "]]]
      [:"EUC-KR_delete_prefix", [["EUC-KR", ", 세계! 어 end"], ["EUC-KR", "한국, 세계! 어"]]]
      [:"EUC-KR_last_match", [["EUC-KR", "세계"], ["EUC-KR", "한국, "], ["EUC-KR", " 어 end"], ["EUC-KR", "세계!"]]]
      [:"EUC-KR_escape_union", [["US-ASCII", "a\\.b"], /(?-mix:a)|\./]]
      [:"EUC-KR_each_line", [["EUC-KR", "a\n"], ["EUC-KR", "b\n"], ["EUC-KR", "\n"], ["EUC-KR", "c"], ["EUC-KR", "a\nb\n\n"], ["EUC-KR", "c"], ["EUC-KR", "a--"], ["EUC-KR", "b"]]]
      [:CP949_scan, [["CP949", "한국,"], ["CP949", "세계!"], ["CP949", "똠"], ["CP949", "end"]]]
      [:CP949_scan_groups, [[["CP949", "한"], ["CP949", "국"]], [["CP949", "세"], ["CP949", "계"]], [["CP949", "e"], ["CP949", "n"]]]]
      [:CP949_scan_empty, 3]
      [:CP949_split, [["CP949", "한국"], ["CP949", "세계!"], ["CP949", "똠"], ["CP949", "end"]]]
      [:CP949_split_empty, [["CP949", "한"], ["CP949", "국"]]]
      [:CP949_split_limit, [["CP949", "한국,"], ["CP949", "세계! 똠 end"]]]
      [:CP949_split_groups, [["CP949", "한국"], ["CP949", ","], ["CP949", " 세계! 똠 end"]]]
      [:CP949_split_string, [["CP949", "한국,"], ["CP949", "세계!"], ["CP949", "똠"], ["CP949", "end"]]]
      [:CP949_index, [6, 7, 9, 3]]
      [:CP949_byteindex, [10, 14, 15]]
      [:CP949_partition, [["CP949", "한국"], ["CP949", ", "], ["CP949", "세계! 똠 end"], ["CP949", "한국, 세계! 똠"], ["CP949", " "], ["CP949", "end"]]]
      [:CP949_slice, [["CP949", "end"], ["CP949", "국"], ["CP949", "!"]]]
      [:CP949_start_with, [true, false, true]]
      [:CP949_match, [[[["CP949", " 세계! "], ["CP949", "세계!"]], 3, 8, [5, 12], ["CP949", "한국,"], ["CP949", "똠 end"]], true, 6, 6]]
      [:CP949_match_at, [[["CP949", ","]], 2, 3, [4, 5], ["CP949", "한국"], ["CP949", " 세계! 똠 end"]]]
      [:CP949_named, [{["CP949", "a"] => ["CP949", "한국"], ["CP949", "b"] => ["CP949", "세계!"]}, 4, 2, [["CP949", "한국"], ["CP949", "세계!"]]]]
      [:CP949_sub_bang, [["CP949", "한국,_세계! 똠 end"], nil]]
      [:CP949_gsub_hash, ["CP949", "한국; 세계? 똠 end"]]
      [:CP949_gsub_block, ["CP949", "<한국,> <세계!> <똠> <end>"]]
      [:CP949_gsub_backref, ["CP949", "국,한 계!세 똠 nde"]]
      [:CP949_aset, ["CP949", "한국, X 똠 end"]]
      [:CP949_slice_bang, [["CP949", "end"], ["CP949", "한국, 세계! 똠 "]]]
      [:CP949_delete_prefix, [["CP949", ", 세계! 똠 end"], ["CP949", "한국, 세계! 똠"]]]
      [:CP949_last_match, [["CP949", "세계"], ["CP949", "한국, "], ["CP949", " 똠 end"], ["CP949", "세계!"]]]
      [:CP949_escape_union, [["US-ASCII", "a\\.b"], /(?-mix:a)|\./]]
      [:CP949_each_line, [["CP949", "a\n"], ["CP949", "b\n"], ["CP949", "\n"], ["CP949", "c"], ["CP949", "a\nb\n\n"], ["CP949", "c"], ["CP949", "a--"], ["CP949", "b"]]]
      [:"ISO-8859-7_scan", [["ISO-8859-7", "Καλη,"], ["ISO-8859-7", "μέρα!"], ["ISO-8859-7", "ΑΒ"], ["ISO-8859-7", "end"]]]
      [:"ISO-8859-7_scan_groups", [[["ISO-8859-7", "Κ"], ["ISO-8859-7", "α"]], [["ISO-8859-7", "λ"], ["ISO-8859-7", "η"]], [["ISO-8859-7", "μ"], ["ISO-8859-7", "έ"]], [["ISO-8859-7", "ρ"], ["ISO-8859-7", "α"]], [["ISO-8859-7", "Α"], ["ISO-8859-7", "Β"]], [["ISO-8859-7", "e"], ["ISO-8859-7", "n"]]]]
      [:"ISO-8859-7_scan_empty", 5]
      [:"ISO-8859-7_split", [["ISO-8859-7", "Καλη"], ["ISO-8859-7", "μέρα!"], ["ISO-8859-7", "ΑΒ"], ["ISO-8859-7", "end"]]]
      [:"ISO-8859-7_split_empty", [["ISO-8859-7", "Κ"], ["ISO-8859-7", "α"], ["ISO-8859-7", "λ"], ["ISO-8859-7", "η"]]]
      [:"ISO-8859-7_split_limit", [["ISO-8859-7", "Καλη,"], ["ISO-8859-7", "μέρα! ΑΒ end"]]]
      [:"ISO-8859-7_split_groups", [["ISO-8859-7", "Καλη"], ["ISO-8859-7", ","], ["ISO-8859-7", " μέρα! ΑΒ end"]]]
      [:"ISO-8859-7_split_string", [["ISO-8859-7", "Καλη,"], ["ISO-8859-7", "μέρα!"], ["ISO-8859-7", "ΑΒ"], ["ISO-8859-7", "end"]]]
      [:"ISO-8859-7_index", [10, 5, 14, 5]]
      [:"ISO-8859-7_byteindex", [10, 14, 15]]
      [:"ISO-8859-7_partition", [["ISO-8859-7", "Καλη"], ["ISO-8859-7", ", "], ["ISO-8859-7", "μέρα! ΑΒ end"], ["ISO-8859-7", "Καλη, μέρα! ΑΒ"], ["ISO-8859-7", " "], ["ISO-8859-7", "end"]]]
      [:"ISO-8859-7_slice", [["ISO-8859-7", "end"], ["ISO-8859-7", "α"], ["ISO-8859-7", "!"]]]
      [:"ISO-8859-7_start_with", [true, false, true]]
      [:"ISO-8859-7_match", [[[["ISO-8859-7", " μέρα! "], ["ISO-8859-7", "μέρα!"]], 5, 12, [5, 12], ["ISO-8859-7", "Καλη,"], ["ISO-8859-7", "ΑΒ end"]], true, 10, 10]]
      [:"ISO-8859-7_match_at", [[["ISO-8859-7", "λ"]], 2, 3, [2, 3], ["ISO-8859-7", "Κα"], ["ISO-8859-7", "η, μέρα! ΑΒ end"]]]
      [:"ISO-8859-7_named", [{["ISO-8859-7", "a"] => ["ISO-8859-7", "Καλη"], ["ISO-8859-7", "b"] => ["ISO-8859-7", "μέρα!"]}, 6, 4, [["ISO-8859-7", "Καλη"], ["ISO-8859-7", "μέρα!"]]]]
      [:"ISO-8859-7_sub_bang", [["ISO-8859-7", "Καλη,_μέρα! ΑΒ end"], nil]]
      [:"ISO-8859-7_gsub_hash", ["ISO-8859-7", "Καλη; μέρα? ΑΒ end"]]
      [:"ISO-8859-7_gsub_block", ["ISO-8859-7", "<Καλη,> <μέρα!> <ΑΒ> <end>"]]
      [:"ISO-8859-7_gsub_backref", ["ISO-8859-7", "αλη,Κ έρα!μ ΒΑ nde"]]
      [:"ISO-8859-7_aset", ["ISO-8859-7", "Καλη, X ΑΒ end"]]
      [:"ISO-8859-7_slice_bang", [["ISO-8859-7", "end"], ["ISO-8859-7", "Καλη, μέρα! ΑΒ "]]]
      [:"ISO-8859-7_delete_prefix", [["ISO-8859-7", ", μέρα! ΑΒ end"], ["ISO-8859-7", "Καλη, μέρα! ΑΒ"]]]
      [:"ISO-8859-7_last_match", [["ISO-8859-7", "μέρα"], ["ISO-8859-7", "Καλη, "], ["ISO-8859-7", " ΑΒ end"], ["ISO-8859-7", "μέρα!"]]]
      [:"ISO-8859-7_escape_union", [["US-ASCII", "a\\.b"], /(?-mix:a)|\./]]
      [:"ISO-8859-7_each_line", [["ISO-8859-7", "a\n"], ["ISO-8859-7", "b\n"], ["ISO-8859-7", "\n"], ["ISO-8859-7", "c"], ["ISO-8859-7", "a\nb\n\n"], ["ISO-8859-7", "c"], ["ISO-8859-7", "a--"], ["ISO-8859-7", "b"]]]
    OUT
  end

  it "regexp new takes its encoding from the source and the flags" do
    result = ze0(<<~'RUBY')
      # `Regexp.new(string, integer)`: the integer's FIXEDENCODING and
      # NOENCODING bits count, as rb_reg_initialize_str reads them, and the
      # encoding comes from the source and its escapes as rb_reg_preprocess
      # finds it -- a non-ASCII source fixes it, `\xff` in a UTF-8 source is an
      # invalid multibyte escape, `/n` with a non-ASCII character refuses, and
      # the source keeps US-ASCII when it is plain ASCII. None of it shows as
      # an instance variable.
      [0, 16, 32, 33, 48, 64, 7, 23].each do |o|
        ["a", "é", "\\xff"].each do |s|
          r = begin
            Regexp.new(s, o)
          rescue RegexpError => e
            next p [o, s, e]
          end
          p [o, s, r.options, r.encoding, r.fixed_encoding?, r.inspect, r.source.encoding]
        end
      end
      p Regexp.new(/a/u).options, Regexp.new(/a/n).options, Regexp.new(/a/u).encoding, Regexp.new(/a/n).encoding
      p /a/n.instance_variables, /a/u.instance_variables, Regexp.new("a", 16).instance_variables

    RUBY

    _(result).must_answer <<~'OUT'
      [0, "a", 0, #<Encoding:US-ASCII>, false, "/a/", #<Encoding:US-ASCII>]
      [0, "é", 16, #<Encoding:UTF-8>, true, "/é/", #<Encoding:UTF-8>]
      [0, "\\xff", #<RegexpError: invalid multibyte escape: /\xff/>]
      [16, "a", 16, #<Encoding:UTF-8>, true, "/a/", #<Encoding:UTF-8>]
      [16, "é", 16, #<Encoding:UTF-8>, true, "/é/", #<Encoding:UTF-8>]
      [16, "\\xff", #<RegexpError: invalid multibyte escape: /\xff/>]
      [32, "a", 32, #<Encoding:US-ASCII>, false, "/a/n", #<Encoding:US-ASCII>]
      [32, "é", #<RegexpError: /.../n has a non escaped non ASCII character in non ASCII-8BIT script: /é/>]
      [32, "\\xff", 48, #<Encoding:BINARY (ASCII-8BIT)>, true, "/\\xff/n", #<Encoding:BINARY (ASCII-8BIT)>]
      [33, "a", 33, #<Encoding:US-ASCII>, false, "/a/in", #<Encoding:US-ASCII>]
      [33, "é", #<RegexpError: /.../n has a non escaped non ASCII character in non ASCII-8BIT script: /é/i>]
      [33, "\\xff", 49, #<Encoding:BINARY (ASCII-8BIT)>, true, "/\\xff/in", #<Encoding:BINARY (ASCII-8BIT)>]
      [48, "a", 48, #<Encoding:BINARY (ASCII-8BIT)>, true, "/a/n", #<Encoding:BINARY (ASCII-8BIT)>]
      [48, "é", #<RegexpError: /.../n has a non escaped non ASCII character in non ASCII-8BIT script: /é/>]
      [48, "\\xff", 48, #<Encoding:BINARY (ASCII-8BIT)>, true, "/\\xff/n", #<Encoding:BINARY (ASCII-8BIT)>]
      [64, "a", 0, #<Encoding:US-ASCII>, false, "/a/", #<Encoding:US-ASCII>]
      [64, "é", 16, #<Encoding:UTF-8>, true, "/é/", #<Encoding:UTF-8>]
      [64, "\\xff", #<RegexpError: invalid multibyte escape: /\xff/>]
      [7, "a", 7, #<Encoding:US-ASCII>, false, "/a/mix", #<Encoding:US-ASCII>]
      [7, "é", 23, #<Encoding:UTF-8>, true, "/é/mix", #<Encoding:UTF-8>]
      [7, "\\xff", #<RegexpError: invalid multibyte escape: /\xff/mix>]
      [23, "a", 23, #<Encoding:UTF-8>, true, "/a/mix", #<Encoding:UTF-8>]
      [23, "é", 23, #<Encoding:UTF-8>, true, "/é/mix", #<Encoding:UTF-8>]
      [23, "\\xff", #<RegexpError: invalid multibyte escape: /\xff/mix>]
      16
      32
      #<Encoding:UTF-8>
      #<Encoding:US-ASCII>
      []
      []
      []
    OUT
  end

  it "regexp new three args" do
    result = ze0(<<~'RUBY')
      begin
        p Regexp.new("a", nil, "n").encoding.name
      rescue ArgumentError, TypeError => e
        p e.class
      end
    RUBY

    _(result).must_answer "ArgumentError\n"
  end

  it "regexp over a multibyte legacy encoding reads characters" do
    result = ze0(<<~'RUBY')
      # A Regexp over EUC-JP, Shift_JIS or Windows-31J text reads it a character
      # at a time, with that encoding's own classes and case folds: `.` takes a
      # whole two-byte character. The engine carries Onigmo's UTF-8 and ASCII
      # encodings only, so text in any other multibyte encoding is read a byte
      # at a time.
      def re(source, enc, options = 0) = Regexp.new(source.encode(enc), options)
      euc = "日本語テキスト".encode("EUC-JP")
      p euc.scan(re(".", "EUC-JP")).size, euc =~ re("語", "EUC-JP"), euc.index(re("テ", "EUC-JP"))
      p re(".", "EUC-JP").match(euc)[0].bytesize, re("\\w+", "EUC-JP").match(euc)&.[](0)&.bytesize
      sjis = "表示ソフト".encode("Shift_JIS")
      p re(".", "Shift_JIS").match(sjis)[0].bytesize, re("\\\\", "Shift_JIS") =~ sjis, sjis.split(re("", "Shift_JIS")).size
      p re("ト", "Windows-31J").match("ソフト".encode("Windows-31J")).begin(0)
      p re("[ア-ン]+", "EUC-JP").match("カタカナ".encode("EUC-JP"))[0].bytesize
      p re("ａ", "EUC-JP", Regexp::IGNORECASE) =~ "Ａ".encode("EUC-JP")
      p "ｶﾀｶﾅ".encode("Shift_JIS").scan(re(".", "Shift_JIS")).size

    RUBY

    _(result).must_answer <<~'OUT'
      7
      2
      3
      2
      nil
      2
      nil
      5
      2
      8
      0
      4
    OUT
  end

  it "regexp over east asian encodings reads their characters" do
    result = ze0(<<~'RUBY')
      # A Regexp over Japanese, Chinese or Korean text in a legacy multibyte
      # encoding reads whole characters of it: one to four bytes as the
      # encoding lays them out, a search that steps back onto a character's
      # first byte, the JIS encodings' kana and kanji properties, and their
      # fullwidth, Greek and Cyrillic case folds. Replicas (eucJP-ms, CP932,
      # CP950, GB2312, ...) read as the encoding they copy.
      # MacJapanese has no converter of its own; its bytes are Shift_JIS's.
      def conv(text, enc) = enc == "MacJapanese" ? text.encode("Shift_JIS").force_encoding(enc) : text.encode(enc)
      def re(source, enc, options = 0) = Regexp.new(conv(source, enc), options | Regexp::FIXEDENCODING)
      def utf8(s) = s.encoding.name == "MacJapanese" ? s.dup.force_encoding("Shift_JIS").encode("UTF-8") : s.encode("UTF-8")
      def show(match) = match && [match.byteoffset(0), utf8(match[0])]

      %w[EUC-JP eucJP-ms CP51932 Shift_JIS Windows-31J SJIS-DoCoMo MacJapanese].each do |enc|
        text = conv("カタカナとひらがな、漢字ＡＢＣαβγ ｶﾀｶﾅ ДЖ", enc)
        p enc, text.scan(re(".", enc)).size, show(re("\\p{Hiragana}+", enc).match(text)), show(re("\\p{Han}+", enc).match(text))
        p show(re("\\p{Katakana}+$", enc).match(conv("カナ ｶﾅ", enc))), show(re("ａｂｃ", enc, Regexp::IGNORECASE).match(text))
        p show(re("ΑΒΓ", enc, Regexp::IGNORECASE).match(text)), show(re("дж", enc, Regexp::IGNORECASE).match(text))
        p text.index(re("ひ", enc)), text.rindex(re("カ", enc)), text.split(re("、", enc)).size, show(re("\\w+$", enc).match(text))
        p show(re("(?<=漢)字", enc).match(text)), utf8(text.gsub(re("[かが]", enc), conv("*", enc)))
        p show(re("\\\\", enc).match(conv("表\\示", enc))), re("ソ", enc).match(conv("表ソ", enc))&.byteoffset(0)
      end

      p show(re("\\p{Latin}+", "EUC-JP").match("ｘ ＸＹ".encode("EUC-JP"))), show(re(".", "EUC-JP").match("丨".encode("EUC-JP")))

      %w[Big5 CP950 Big5-HKSCS Big5-UAO GBK CP936 GB18030 EUC-KR GB2312 GB12345 CP949].each do |enc|
        sample = { "Big5" => "中文字元，測試", "GBK" => "中文字符，测试", "GB18030" => "中文字符，测试\u{20000}€",
                   "EUC-KR" => "한국어 문자열", "CP949" => "한국어 똠방각하" }
        base = { "CP950" => "Big5", "Big5-HKSCS" => "Big5", "Big5-UAO" => "Big5", "CP936" => "GBK", "GB2312" => "GBK", "GB12345" => "GBK" }
        source = sample.fetch(base.fetch(enc, enc)) { sample.fetch("EUC-KR") }
        source = "中文字符" if enc.start_with?("GB2312", "GB12345")
        text = source.encode(enc)
        chars = source.each_char.to_a
        p enc, text.scan(re(".", enc)).size, show(re("#{chars[1]}(.)", enc).match(text)), text.rindex(re(chars[0], enc))
        p text.index(re(chars.last, enc)), show(re("\\w+", enc).match(text)), show(re("[#{chars[0]}#{chars[2]}]+", enc).match(text))
        p show(re("(?<!#{chars[0]})#{chars[2]}", enc).match(text)), text.split(re(chars[1], enc)).map(&:bytesize)
      end

      # EUC-TW has no converter: its characters are written as bytes, two for
      # plane 1 and four (0x8E, the plane, two bytes) for the others.
      def tw(bytes) = bytes.dup.force_encoding("EUC-TW")
      text = tw("\xC4\xA1\xC4\xA2a\x8E\xA2\xA1\xA1\xC5\xE3 \xC4\xA1")
      p text.scan(Regexp.new(tw("."))).map(&:bytesize), text.rindex(Regexp.new(tw("\xC4\xA1"))), Regexp.new(tw("\xC4\xA2(.)")).match(text)&.byteoffset(0)
      p Regexp.new(tw("\\w+")).match(text).byteoffset(0), Regexp.new(tw("(?<=\x8E\xA2\xA1\xA1)\xC5\xE3")).match(text)&.byteoffset(0), text.split(Regexp.new(tw("a"))).map(&:bytesize)
      four = tw("\x8E\xA2\xA1\xA1a")
      p four.valid_encoding?, Regexp.new(tw(".")).match(four).byteoffset(0), (Regexp.new(tw("a")) =~ four)
      mule = "a\x92\xA4\xA2b\x81\xA1".dup.force_encoding("Emacs-Mule")
      p mule.valid_encoding?, mule.scan(Regexp.new(".".force_encoding("Emacs-Mule"))).map(&:bytesize)
      p Regexp.new("b".force_encoding("stateless-ISO-2022-JP")).match(mule.dup.force_encoding("stateless-ISO-2022-JP"))&.byteoffset(0)
      gb = "a\x81\x30\x81\x30b".dup.force_encoding("GB18030")
      p gb.valid_encoding?, gb.scan(re(".", "GB18030")).map(&:bytesize), gb.rindex(re("\\w", "GB18030"))


    RUBY

    _(result).must_answer <<~'OUT'
      "EUC-JP"
      26
      [[8, 18], "とひらがな"]
      [[20, 24], "漢字"]
      [[5, 9], "ｶﾅ"]
      [[24, 30], "ＡＢＣ"]
      [[30, 36], "αβγ"]
      [[46, 50], "ДЖ"]
      5
      2
      2
      nil
      [[22, 24], "字"]
      "カタカナとひら*な、漢字ＡＢＣαβγ ｶﾀｶﾅ ДЖ"
      [[2, 3], "\\"]
      [2, 4]
      "eucJP-ms"
      26
      [[8, 18], "とひらがな"]
      [[20, 24], "漢字"]
      [[5, 9], "ｶﾅ"]
      [[24, 30], "ＡＢＣ"]
      [[30, 36], "αβγ"]
      [[46, 50], "ДЖ"]
      5
      2
      2
      nil
      [[22, 24], "字"]
      "カタカナとひら*な、漢字ＡＢＣαβγ ｶﾀｶﾅ ДЖ"
      [[2, 3], "\\"]
      [2, 4]
      "CP51932"
      26
      [[8, 18], "とひらがな"]
      [[20, 24], "漢字"]
      [[5, 9], "ｶﾅ"]
      [[24, 30], "ＡＢＣ"]
      [[30, 36], "αβγ"]
      [[46, 50], "ДЖ"]
      5
      2
      2
      nil
      [[22, 24], "字"]
      "カタカナとひら*な、漢字ＡＢＣαβγ ｶﾀｶﾅ ДЖ"
      [[2, 3], "\\"]
      [2, 4]
      "Shift_JIS"
      26
      [[8, 18], "とひらがな"]
      [[20, 24], "漢字"]
      nil
      [[24, 30], "ＡＢＣ"]
      [[30, 36], "αβγ"]
      [[42, 46], "ДЖ"]
      5
      2
      2
      nil
      [[22, 24], "字"]
      "カタカナとひら*な、漢字ＡＢＣαβγ ｶﾀｶﾅ ДЖ"
      [[2, 3], "\\"]
      [2, 4]
      "Windows-31J"
      26
      [[8, 18], "とひらがな"]
      [[20, 24], "漢字"]
      nil
      [[24, 30], "ＡＢＣ"]
      [[30, 36], "αβγ"]
      [[42, 46], "ДЖ"]
      5
      2
      2
      nil
      [[22, 24], "字"]
      "カタカナとひら*な、漢字ＡＢＣαβγ ｶﾀｶﾅ ДЖ"
      [[2, 3], "\\"]
      [2, 4]
      "SJIS-DoCoMo"
      26
      [[8, 18], "とひらがな"]
      [[20, 24], "漢字"]
      nil
      [[24, 30], "ＡＢＣ"]
      [[30, 36], "αβγ"]
      [[42, 46], "ДЖ"]
      5
      2
      2
      nil
      [[22, 24], "字"]
      "カタカナとひら*な、漢字ＡＢＣαβγ ｶﾀｶﾅ ДЖ"
      [[2, 3], "\\"]
      [2, 4]
      "MacJapanese"
      26
      [[8, 18], "とひらがな"]
      [[20, 24], "漢字"]
      nil
      [[24, 30], "ＡＢＣ"]
      [[30, 36], "αβγ"]
      [[42, 46], "ДЖ"]
      5
      2
      2
      nil
      [[22, 24], "字"]
      "カタカナとひら*な、漢字ＡＢＣαβγ ｶﾀｶﾅ ДЖ"
      [[2, 3], "\\"]
      [2, 4]
      [[0, 2], "ｘ"]
      [[0, 3], "丨"]
      "Big5"
      7
      [[2, 6], "文字"]
      0
      6
      nil
      [[0, 2], "中"]
      [[4, 6], "字"]
      [2, 10]
      "CP950"
      7
      [[2, 6], "文字"]
      0
      6
      nil
      [[0, 2], "中"]
      [[4, 6], "字"]
      [2, 10]
      "Big5-HKSCS"
      7
      [[2, 6], "文字"]
      0
      6
      nil
      [[0, 2], "中"]
      [[4, 6], "字"]
      [2, 10]
      "Big5-UAO"
      7
      [[2, 6], "文字"]
      0
      6
      nil
      [[0, 2], "中"]
      [[4, 6], "字"]
      [2, 10]
      "GBK"
      7
      [[2, 6], "文字"]
      0
      6
      nil
      [[0, 2], "中"]
      [[4, 6], "字"]
      [2, 10]
      "CP936"
      7
      [[2, 6], "文字"]
      0
      6
      nil
      [[0, 2], "中"]
      [[4, 6], "字"]
      [2, 10]
      "GB18030"
      9
      [[2, 6], "文字"]
      0
      8
      nil
      [[0, 2], "中"]
      [[4, 6], "字"]
      [2, 16]
      "EUC-KR"
      7
      [[2, 6], "국어"]
      0
      6
      nil
      [[0, 2], "한"]
      [[4, 6], "어"]
      [2, 9]
      "GB2312"
      4
      [[2, 6], "文字"]
      0
      3
      nil
      [[0, 2], "中"]
      [[4, 6], "字"]
      [2, 4]
      "GB12345"
      4
      [[2, 6], "文字"]
      0
      3
      nil
      [[0, 2], "中"]
      [[4, 6], "字"]
      [2, 4]
      "CP949"
      8
      [[2, 6], "국어"]
      0
      7
      nil
      [[0, 2], "한"]
      [[4, 6], "어"]
      [2, 11]
      [2, 2, 1, 4, 2, 1, 2]
      6
      [2, 5]
      [4, 5]
      [9, 11]
      [4, 9]
      true
      [0, 4]
      1
      true
      [1, 3, 1, 2]
      [4, 5]
      true
      [1, 4, 1]
      2
    OUT
  end

  it "regexp over utf16 and utf32 text reads wide characters" do
    result = ze0(<<~'RUBY')
      # A Regexp written in UTF-16 or UTF-32 reads text of that encoding a
      # character at a time: two or four bytes, a surrogate pair as one
      # character, a newline as the character U+000A, and Unicode's classes,
      # properties and case folds. Its source, inspect and errors show the
      # pattern's own characters. CESU-8 reads a character past the BMP as its
      # two three-byte surrogates.
      def u(text, enc) = text.encode(enc)
      def show(match) = match && [match.byteoffset(0), match[0].encode("UTF-8")]

      %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].each do |enc|
        text = u("Grüße, 世界!\nδύο 😀 lines\n", enc)
        re = Regexp.new(u("(\\w+), (\\p{Han}+)", enc))
        m = re.match(text)
        p enc, m.byteoffset(0), m.captures.map { _1.encode("UTF-8") }, m.pre_match.bytesize, m.begin(2)
        p text.scan(Regexp.new(u(".", enc))).size, text.scan(Regexp.new(u("^\\S+", enc))).map { _1.encode("UTF-8") }
        p show(Regexp.new(u("GRÜSSE", enc), Regexp::IGNORECASE).match(text)), show(Regexp.new(u("ΔΎΟ", enc), Regexp::IGNORECASE).match(text))
        p show(Regexp.new(u("\\X\\s+lines$", enc)).match(text)), text.index(Regexp.new(u("😀", enc))), text.rindex(Regexp.new(u("\\w", enc)))
        p text.gsub(Regexp.new(u("[aeiouüύ]", enc)), u("*", enc)).encode("UTF-8"), text.split(Regexp.new(u("\\n", enc))).size
        p Regexp.new(u("\\bl\\w+", enc)).match(text)&.byteoffset(0), (Regexp.new(u("\\A\\p{Upper}", enc)) =~ text)
        p Regexp.new(u("a+b", enc)).source.encoding, Regexp.new(u("a+b", enc)).source.bytesize
      end

      cesu = "x\u{1F600}y".encode("CESU-8")
      p cesu.bytesize, Regexp.new("x(.)y".encode("CESU-8")).match(cesu).byteoffset(1), cesu.scan(Regexp.new(".".encode("CESU-8"))).size
      p Regexp.new("\\p{Emoji}".encode("CESU-8")).match(cesu)&.byteoffset(0)

      # A warning shows a wide pattern a byte at a time.
      $VERBOSE = true
      Regexp.new(u("[aa]]", "UTF-16LE"))
      Regexp.new(u("x**", "UTF-32BE"))
      $VERBOSE = false

      begin
        Regexp.new(u("(?<n>a)\\k<m>", "UTF-16LE"))
      rescue RegexpError => e
        p e.message.encoding, e.message.bytesize
      end
      begin
        Regexp.new(u("\\p{Nope}", "UTF-32BE"))
      rescue RegexpError => e
        p e.message.encoding, e.message.b[0, 40]
      end
      p (Regexp.new(u("a", "UTF-16LE")) =~ "a") rescue p $!.class, $!.message


    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/regexp/encoding_test.rb:29: warning: character class has duplicated range: /\\x5b\\x00\\x61\\x00\\x61\\x00\\x5d\\x00\\x5d\\x00/\ncore/regexp/encoding_test.rb:29: warning: regular expression has ']' without escape: /\\x5b\\x00\\x61\\x00\\x61\\x00\\x5d\\x00\\x5d\\x00/\ncore/regexp/encoding_test.rb:30: warning: regular expression has redundant nested repeat operator '*': /\\x00\\x00\\x00\\x78\\x00\\x00\\x00\\x2a\\x00\\x00\\x00\\x2a/\n"
      "UTF-16LE"
      [8, 18]
      ["e", "世界"]
      8
      7
      21
      ["Grüße,", "δύο"]
      [[0, 10], "Grüße"]
      [[22, 28], "δύο"]
      [[30, 46], "😀 lines"]
      15
      21
      "Gr*ß*, 世界!\nδ*ο 😀 l*n*s\n"
      2
      [36, 46]
      0
      #<Encoding:UTF-16LE>
      6
      "UTF-16BE"
      [8, 18]
      ["e", "世界"]
      8
      7
      21
      ["Grüße,", "δύο"]
      [[0, 10], "Grüße"]
      [[22, 28], "δύο"]
      [[30, 46], "😀 lines"]
      15
      21
      "Gr*ß*, 世界!\nδ*ο 😀 l*n*s\n"
      2
      [36, 46]
      0
      #<Encoding:UTF-16BE>
      6
      "UTF-32LE"
      [16, 36]
      ["e", "世界"]
      16
      7
      21
      ["Grüße,", "δύο"]
      [[0, 20], "Grüße"]
      [[44, 56], "δύο"]
      [[60, 88], "😀 lines"]
      15
      21
      "Gr*ß*, 世界!\nδ*ο 😀 l*n*s\n"
      2
      [68, 88]
      0
      #<Encoding:UTF-32LE>
      12
      "UTF-32BE"
      [16, 36]
      ["e", "世界"]
      16
      7
      21
      ["Grüße,", "δύο"]
      [[0, 20], "Grüße"]
      [[44, 56], "δύο"]
      [[60, 88], "😀 lines"]
      15
      21
      "Gr*ß*, 世界!\nδ*ο 😀 l*n*s\n"
      2
      [68, 88]
      0
      #<Encoding:UTF-32BE>
      12
      8
      [1, 7]
      3
      [1, 7]
      #<Encoding:UTF-16LE>
      56
      #<Encoding:UTF-32BE>
      "invalid character property name {Nope}: "
      Encoding::CompatibilityError
      "incompatible encoding regexp match (UTF-16LE regexp with UTF-8 string)"
    OUT
  end

  it "a binary subject matches no word boundary and no POSIX bracket" do
    result = ze0(<<~'RUBY')
      p "\xB5".b =~ /\b/
      p "\xB5".b =~ /[[:word:]]/
      p "\xC2\xB5".b =~ /[[:word:]]/
      p "\xC2\xB5".b.scan(/\b/).size
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      0
    OUT
  end

  it "subject of another encoding compiles the pattern again" do
    result = ze0(<<~'RUBY')
      # A pattern that fixed no encoding reads a subject of another encoding
      # by compiling its source again under the subject's (rb_reg_prepare_re):
      # the escapes decode as that encoding's characters, a byte no character
      # of it holds is refused at the match, and the compile stays the
      # pattern's until a subject of yet another encoding asks.

      def try(re, subject)
        m = re.match(subject)
        m ? [m[0].bytes, m.begin(0)] : nil
      rescue ArgumentError, Encoding::CompatibilityError => e
        [e.class, e.message]
      end

      loose = Regexp.new('\A[\xff]'.dup.force_encoding("US-ASCII"))
      p [loose.encoding, loose.fixed_encoding?]
      p try(loose, "abc")
      p try(loose, "\xff".b)
      p try(loose, "é")
      p try(loose, "abc")

      # A comment's high byte is nothing to US-ASCII, and not a character of
      # UTF-8 once a subject compiles the pattern under it.
      latin = Regexp.new("(?#\xE9)b".dup.force_encoding("ISO-8859-1"))
      p [latin.encoding, latin.source.bytes]
      p try(latin, "ab")
      p try(latin, "\xE9b".dup.force_encoding("ISO-8859-1"))
      p try(latin, "ab")
      p try(latin, "éb")

      # `\xE3\x81\x82` is one character under UTF-8 and three bytes under BINARY.
      octets = Regexp.new('\xE3\x81\x82.', Regexp::NOENCODING)
      p [octets.encoding, octets.options]
      p try(octets, "\xE3\x81\x82\x80".b)
      $stderr.puts "--"
      p try(octets, "あい")
      p try(/./n, "あ")

      # A fixed pattern refuses a subject past ASCII in another encoding.
      fixed = /é./
      p try(fixed, "éa".encode("ISO-8859-1"))
      p try(fixed, "ab".encode("UTF-16LE"))
      p try(fixed, "ab".b)

    RUBY

    _(result).must_answer <<~'OUT', stderr: "--\ncore/regexp/encoding_test.rb:8: warning: historical binary regexp match /.../n against UTF-8 string\n"
      [#<Encoding:US-ASCII>, false]
      nil
      [[255], 0]
      [ArgumentError, "regexp preprocess failed: invalid multibyte escape"]
      [ArgumentError, "regexp preprocess failed: invalid multibyte escape"]
      [#<Encoding:US-ASCII>, [40, 63, 35, 233, 41, 98]]
      [[98], 1]
      [[98], 1]
      [ArgumentError, "regexp preprocess failed: invalid multibyte character"]
      [ArgumentError, "regexp preprocess failed: invalid multibyte character"]
      [#<Encoding:BINARY (ASCII-8BIT)>, 48]
      [[227, 129, 130, 128], 0]
      [Encoding::CompatibilityError, "incompatible encoding regexp match (BINARY (ASCII-8BIT) regexp with UTF-8 string)"]
      [[227, 129, 130], 0]
      [Encoding::CompatibilityError, "incompatible encoding regexp match (UTF-8 regexp with ISO-8859-1 string)"]
      [Encoding::CompatibilityError, "incompatible encoding regexp match (UTF-8 regexp with UTF-16LE string)"]
      nil
    OUT
  end
end
