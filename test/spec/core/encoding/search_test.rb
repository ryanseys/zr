# frozen_string_literal: true

require "spec_helper"

describe "Encoding: searching and matching" do
  it "broken needle never matches" do
    result = zr(<<~'RUBY')
      # A needle that is not valid in its encoding never matches, as CRuby's
      # rb_str_index decides; a prefix or a suffix must end or start on a
      # character boundary.
      def t = yield rescue [$!.class, $!.message]

      s = "é\xA9x"
      p t { s.include?("\xA9") }, t { s.index("\xA9") }, t { s.byteindex("\xA9") }, t { s.rindex("\xA9") }
      p t { s.partition("\xA9") }, t { "é\xA9x".index("x") }
      p t { "é".start_with?("\xC3") }, t { "é".delete_prefix("\xC3") }, t { "aé".end_with?("\xA9") }, t { "aé".delete_suffix("\xA9") }
      w = "é\xA9é"
      p t { w.index("\xA9") }, t { w.byteindex("\xA9") }, t { "\xA9é".index("\xA9") }, t { w.rindex("é") }, t { w.byterindex("\xA9") }
      p t { "aé".start_with?("a") }, t { "aé".end_with?("é") }, t { "aéb".rindex("é") }, t { "ééé".index("é", 1) }

    RUBY

    _(result).must_answer <<~'OUT'
      false
      nil
      nil
      nil
      ["é\xA9x", "", ""]
      2
      false
      "é"
      false
      "aé"
      nil
      nil
      nil
      2
      nil
      true
      true
      1
      1
    OUT
  end

  it "encode to an unknown encoding names the converter" do
    result = zr(<<~'RUBY')
      # `String#encode` to an unknown encoding raises
      # Encoding::ConverterNotFoundError naming the pair ("code converter not
      # found (UTF-8 to NO-SUCH-ENC)"); zr routes through the registry lookup
      # first and raises ArgumentError ("unknown encoding name"). The Converter
      # and Encoding.find paths already match -- only #encode misroutes. (Found
      # by the 2026-08-24 probe sweep.)
      begin
        "a".encode("NO-SUCH-ENC")
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      begin
        Encoding::Converter.new("UTF-8", "NO-SUCH-ENC")
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      begin
        Encoding.find("NO-SUCH-ENC")
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Encoding::ConverterNotFoundError: code converter not found (UTF-8 to NO-SUCH-ENC)
      Encoding::ConverterNotFoundError: code converter not found (UTF-8 to NO-SUCH-ENC)
      ArgumentError: unknown encoding name - NO-SUCH-ENC
    OUT
  end

  it "issue posix alpha class ascii only" do
    result = zr(<<~'RUBY')
      # The POSIX bracket class `[[:alpha:]]` (and presumably its siblings) only
      # matches ASCII letters in zr's regex engine -- CRuby's onig engine matches
      # any Unicode letter (e.g. "e" with an accent) against `[[:alpha:]]`.
      p "café".match?(/\A[[:alpha:]]+\z/)
      p "abc".match?(/\A[[:alpha:]]+\z/)
      p "é".match?(/[[:alpha:]]/)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
    OUT
  end

  it "issue word char class ascii scope" do
    result = zr(<<~'RUBY')
      # `\w` in a regex should only match ASCII word characters ([a-zA-Z0-9_]) by
      # default in CRuby's onig engine, excluding accented/Unicode letters. zr's
      # `\w` is Unicode-aware and matches "e" with an accent too.
      p "café bar".scan(/\w+/)
    RUBY

    _(result).must_answer "[\"caf\", \"bar\"]\n"
  end

  it "match answers in the subjects encoding" do
    result = zr(<<~'RUBY')
      # Every string a match hands back carries the SUBJECT's encoding, not the
      # engine's. zr decodes a haystack to UTF-8 to search it, but a binary or
      # Latin-1 subject still gets groups in its own encoding.
      #
      # The rows cover `String#match`, `Regexp#match`, `=~`, `$~`, `String#[]`
      # and `partition`.

      b = "café".b
      l = "\xe9x".force_encoding("ISO-8859-1")

      def show(label)
        puts format("%-34s %s", label, (yield).inspect)
      rescue => e
        puts format("%-34s %s", label, "#{e.class}")
      end

      show("Regexp#match group")      { /ca(f)/.match(b)[1].encoding.to_s }
      show("Regexp#match whole")      { /ca(f)/.match(b)[0].encoding.to_s }
      show("Regexp#match pre")        { /a(f)/.match(b).pre_match.encoding.to_s }
      show("Regexp#match post")       { /a(f)/.match(b).post_match.encoding.to_s }
      show("Regexp#match latin1")     { /(.)/.match(l)[1].encoding.to_s }
      show("String#match group")      { b.match(/ca(f)/)[1].encoding.to_s }
      show("Regexp#=~ then $1")       { (/ca(f)/ =~ b; $1.encoding.to_s) }
      show("String#=~ then $1")       { (b =~ /ca(f)/; $1.encoding.to_s) }
      show("$~[0]")                   { (/ca(f)/ =~ b; $~[0].encoding.to_s) }
      show("$~.pre_match")            { (/a(f)/ =~ b; $~.pre_match.encoding.to_s) }
      show("String#scan")             { b.scan(/c(a)/).flatten.first.encoding.to_s }
      show("String#[] regexp")        { b[/ca(f)/, 1].encoding.to_s }
      show("String#slice regexp")     { b.slice(/caf/).encoding.to_s }
      show("String#split")            { b.split(/f/).first.encoding.to_s }
      show("gsub block match arg")    { b.gsub(/a/) { |m| break m.encoding.to_s } }
      show("gsub block $1")           { b.gsub(/(a)/) { break $1.encoding.to_s } }
      show("sub result")              { b.sub(/a/, "x").encoding.to_s }
      show("String#match? no md")     { b.match?(/ca(f)/) }
      show("named capture")           { /c(?<g>a)/.match(b)[:g].encoding.to_s }
      show("named_captures")          { /c(?<g>a)/.match(b).named_captures["g"].encoding.to_s }
      show("captures")                { /c(a)(f)/.match(b).captures.first.encoding.to_s }
      show("values_at")               { /c(a)(f)/.match(b).values_at(1).first.encoding.to_s }
      show("MatchData#string")        { /ca(f)/.match(b).string.encoding.to_s }
      show("MatchData#to_a")          { /ca(f)/.match(b).to_a.first.encoding.to_s }
      show("partition")               { b.partition(/a/)[1].encoding.to_s }
      show("rpartition")              { b.rpartition(/a/)[1].encoding.to_s }
      # A Symbol subject answers in the encoding the Symbol itself reports.
      show("Symbol subject")          { /(b)/.match(:abc)[1].encoding.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      Regexp#match group                 "ASCII-8BIT"
      Regexp#match whole                 "ASCII-8BIT"
      Regexp#match pre                   "ASCII-8BIT"
      Regexp#match post                  "ASCII-8BIT"
      Regexp#match latin1                "ISO-8859-1"
      String#match group                 "ASCII-8BIT"
      Regexp#=~ then $1                  "ASCII-8BIT"
      String#=~ then $1                  "ASCII-8BIT"
      $~[0]                              "ASCII-8BIT"
      $~.pre_match                       "ASCII-8BIT"
      String#scan                        "ASCII-8BIT"
      String#[] regexp                   "ASCII-8BIT"
      String#slice regexp                "ASCII-8BIT"
      String#split                       "ASCII-8BIT"
      gsub block match arg               "ASCII-8BIT"
      gsub block $1                      "ASCII-8BIT"
      sub result                         "ASCII-8BIT"
      String#match? no md                true
      named capture                      "ASCII-8BIT"
      named_captures                     "ASCII-8BIT"
      captures                           "ASCII-8BIT"
      values_at                          "ASCII-8BIT"
      MatchData#string                   "ASCII-8BIT"
      MatchData#to_a                     "ASCII-8BIT"
      partition                          "ASCII-8BIT"
      rpartition                         "ASCII-8BIT"
      Symbol subject                     "US-ASCII"
    OUT
  end

  it "match group keeps the haystacks encoding" do
    result = zr(<<~'RUBY')
      binary = "café".b
      latin1 = "\xe9".force_encoding("ISO-8859-1")

      def show(label)
        puts format("%-32s %s", label, (yield).inspect)
      rescue => e
        puts format("%-32s %s", label, e.class)
      end

      show("group keeps haystack") { /ca(f)/.match(binary)[1].encoding.to_s }
      show("group keeps latin1")   { /(.)/.match(latin1)[1].encoding.to_s }
      show("whole match")          { /ca(f)/.match(binary)[0].encoding.to_s }
      show("pre_match")            { /ca(f)/.match(binary).pre_match.encoding.to_s }
      show("post_match")           { /ca(f)/.match(binary).post_match.encoding.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      group keeps haystack             "ASCII-8BIT"
      group keeps latin1               "ISO-8859-1"
      whole match                      "ASCII-8BIT"
      pre_match                        "ASCII-8BIT"
      post_match                       "ASCII-8BIT"
    OUT
  end

  it "matchdata values at byteoffset" do
    result = zr(<<~'RUBY')
      # MatchData#values_at selects groups by index (nil for a group that did not
      # participate); #byteoffset/#bytebegin/#byteend report raw byte positions (the
      # char-based #begin/#end/#offset already worked). The MatchData receiver is
      # routed through a method param.
      def md(x); x; end

      m = md("a1b2c3".match(/(\d)(\w)(\d)/))
      p m.values_at(1, 3)
      p m.values_at(0, 2)
      p m.byteoffset(0)
      p m.byteoffset(2)
      p m.bytebegin(1)
      p m.byteend(1)

      # a non-participating optional group yields nil in values_at and in the
      # byte-offset accessors (mirroring the char-based begin/end/offset)
      n = md("x".match(/(\d)?(x)/))
      p n.values_at(1, 2)
      p n.bytebegin(1)
      p n.byteend(1)
      p n.byteoffset(1)
    RUBY

    _(result).must_answer <<~'OUT'
      ["1", "2"]
      ["1b2", "b"]
      [1, 4]
      [2, 3]
      1
      2
      [nil, "x"]
      nil
      nil
      [nil, nil]
    OUT
  end

  it "regexp invalid byte match" do
    result = zr(<<~'RUBY')
      begin
        "\xff".force_encoding("UTF-8") =~ /a/
        p :no_raise
      rescue ArgumentError => e
        p e.class
      end
    RUBY

    _(result).must_answer "ArgumentError\n"
  end

  it "regexp match checks the haystacks encoding" do
    result = zr(<<~'RUBY')
      utf8 = "café"
      binary = utf8.b
      latin1 = "\xe9".force_encoding("ISO-8859-1")

      def show(label)
        puts format("%-32s %s", label, (yield).inspect)
      rescue => e
        puts format("%-32s %s", label, e.class)
      end

      show("fixed re vs binary")     { /café/ =~ binary }
      show("fixed re match binary")  { /café/.match(binary) }
      show("fixed re vs latin1")     { /café/ =~ latin1 }
      show("ascii re vs binary")     { /caf/ =~ binary }
      show("String#=~ binary")       { binary =~ /café/ }
      show("scan keeps haystack")    { binary.scan(/./).first.encoding.to_s }
      show("split keeps haystack")   { binary.split(/f/).first.encoding.to_s }
      show("ascii re on latin1")     { latin1.sub(/z/, "y").encoding.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      fixed re vs binary               Encoding::CompatibilityError
      fixed re match binary            Encoding::CompatibilityError
      fixed re vs latin1               Encoding::CompatibilityError
      ascii re vs binary               0
      String#=~ binary                 Encoding::CompatibilityError
      scan keeps haystack              "ASCII-8BIT"
      split keeps haystack             "ASCII-8BIT"
      ascii re on latin1               "ISO-8859-1"
    OUT
  end

  it "the word boundary and the POSIX brackets read unicode, not ASCII" do
    result = zr(<<~'RUBY')
      p "日本語" =~ /\b/
      p "日本語".scan(/\b/).size
      p "日本語" =~ /\B/
      p "こんにちは world" =~ /\bworld\b/
      p "café" =~ /\bcafé\b/
      p "あa" =~ /a\b/
      p "λx" =~ /\b/
      p "日本語です" =~ /\b語/

      p "日本語" =~ /[[:word:]]/
      p "日本語" =~ /[[:alpha:]]/
      p "aあx" =~ /[[:^alpha:]]x/
      p "１２３" =~ /[[:digit:]]+/
      p "Ω" =~ /[[:upper:]]/
      p "ω" =~ /[[:lower:]]/
      p "　" =~ /[[:space:]]/
      p "。" =~ /[[:punct:]]/
      p "aあ" =~ /[[:^ascii:]]/
      p "abc" =~ /[[:^ascii:]]/

      p "日本語" =~ /\w/
      p "日本語" =~ /\W/

      p "Ā" =~ /[[:lower:]]/i
      p "ā" =~ /[[:upper:]]/i

      p "µ" =~ /[[:word:]]/
      p "µ".scan(/\b/).size

      p "hello world" =~ /\bworld\b/
      p "hello".scan(/\b/).size
      p "abc123" =~ /[[:^digit:]]+/
      p "a_b" =~ /\A[[:word:]]+\z/
      p "[[:alpha:]]" =~ /\A\[\[:alpha:\]\]\z/
      p "x" =~ /[[:xdigit:]]/
      p "あ" =~ /[[:xdigit:]]/
    RUBY

    _(result).must_answer <<~'OUT'
      0
      2
      1
      6
      0
      1
      0
      nil
      0
      0
      nil
      0
      0
      0
      0
      0
      1
      nil
      nil
      0
      0
      0
      0
      2
      6
      2
      0
      0
      0
      nil
      nil
    OUT
  end

  it "regexp unicode escape" do
    result = zr(<<~'RUBY')
      # A \u escape in a regexp names one character: /µ/ does not match the text
      # "u00b5", and /\u{3042}/ is not a quantifier on `u`.
      p("µ" =~ /µ/ ? true : false)
      p("u00b5" =~ /µ/ ? true : false)
      p("µ" =~ /[µ]/ ? true : false)
      p("あ" =~ /\u{3042}/ ? true : false)
      p("ab" =~ /\u{61 62}/ ? true : false)
      p("abb".match(/\u{61 62}+/)[0])
      p("aaa".match(/a+/)[0])
      p("a" =~ /[\u{61 62}-z]/ ? true : false)
      p("y" =~ /[\u{61 62}-z]/ ? true : false)
      p("A" =~ /A/i ? true : false)
      p("a" =~ /A/i ? true : false)
      p "aあb".gsub(/\u{3042}/, "-")

      ["\\u", "\\u6", "\\u{}", "\\u{ }", "\\u{d800}", "\\u{110000}", "\\u{0000061}", "\\u{61,62}"]. each do |src|
        begin
          Regexp.new(src)
          puts "#{src}: ok"
        rescue => e
          puts "#{src}: #{e.class}"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      "abb"
      "aaa"
      true
      true
      true
      true
      "a-b"
      \u: RegexpError
      \u6: RegexpError
      \u{}: RegexpError
      \u{ }: RegexpError
      \u{d800}: RegexpError
      \u{110000}: RegexpError
      \u{0000061}: RegexpError
      \u{61,62}: RegexpError
    OUT
  end

  it "string ascii7 fast index" do
    result = zr(<<~'RUBY')
      # Indexing a string that holds only 7-bit bytes is byte indexing: #length is
      # the byte length and s[i] is the byte at i. A bit in the string header
      # records that all bytes are 7-bit.
      #
      # The bit says nothing about encoding. It is a fact about the BYTES, and
      # every operation that can change the bytes clears it.
      #
      # What this program checks is the clearing. A string measured while it is
      # 7-bit, then given a byte that is not, has to answer the new truth.

      s = String.new("abc")
      p s.length
      p s[1]
      s << "é"
      p s.length
      p s[3]
      p s.chars
      p s.bytesize

      # in-place, same length
      t = String.new("abcdef")
      p t.length
      t[2] = "é"
      p t.length
      p t[2]

      # setbyte: no length change at all, so only the content invariant catches it
      y = String.new("abc")
      p y.length
      y.setbyte(1, 233)
      p y.bytesize
      p y.bytes

      # replace
      u = String.new("abc")
      p u.length
      u.replace("éé")
      p u.length
      p u[0]

      # a grow that reallocates the buffer
      g = String.new("abc")
      p g.length
      40.times { g << "x" }
      g << "é"
      p g.length
      p g[-1]

      # through the shared-mutable handle a block capture turns it into
      buf = String.new("abcd")
      p buf.length
      pr = proc { buf << "é" }
      pr.call
      p buf.length
      p buf[4]
      p buf.chars.length

      # a BINARY string keeps its own path: the two tags must not be confused
      b = [200, 65].pack("C*")
      p b.length
      p b.encoding.to_s
      p b.bytes
      p b.b.length
      p b[0].bytes

      # slices are measured in their own right
      z = String.new("hello world")
      p z.length
      p z[0, 5].length
      p z[6, 5][1]

      # and a genuinely multi-byte string is never flagged
      m = "日本語"
      p m.length
      p m.bytesize
      p m[1]
      p m.chars
      m2 = String.new("日本語")
      m2 << "x"
      p m2.length
      p m2[3]

      # mixed, measured before and after
      x = String.new("abc")
      p x.length
      x << "日"
      p x.length
      p x[3]
      x << "d"
      p x.length
      p x[4]
    RUBY

    _(result).must_answer <<~'OUT'
      3
      "b"
      4
      "é"
      ["a", "b", "c", "é"]
      5
      6
      6
      "é"
      3
      3
      [97, 233, 99]
      3
      2
      "é"
      3
      44
      "é"
      4
      5
      "é"
      5
      2
      "ASCII-8BIT"
      [200, 65]
      2
      [200]
      11
      5
      "o"
      3
      9
      "本"
      ["日", "本", "語"]
      4
      "x"
      3
      4
      "日"
      5
      "d"
    OUT
  end

  it "string byteindex" do
    result = zr(<<~'RUBY')
      # String#byteindex/#byterindex return BYTE offsets (not codepoint indices),
      # with byte-offset start/pos arguments; nil on miss.
      p "abcabc".byteindex("b")
      p "abcabc".byteindex("b", 2)
      p "café".byteindex("f")
      p "café".byteindex("é")
      p "hello".byteindex("z")
      p "hello".byteindex("")
      p "abcabc".byterindex("b")
      p "abcabc".byterindex("b", 3)
      p "café".byteindex("f", -2)
      p "aaa".byteindex("a", 1)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      4
      2
      3
      nil
      0
      4
      1
      nil
      1
    OUT
  end

  it "index and include? find no match inside a double-byte character" do
    result = zr(<<~'RUBY')
      %w[GBK CP949 GB18030 Shift_JIS Big5].each do |enc|
        s = "\xA0z".b.force_encoding(enc)
        s = "\x81z".b.force_encoding(enc) unless s.valid_encoding?
        z = "z".force_encoding(enc)
        p [enc, s.valid_encoding?, s.length, s.index(z), s.include?(z), s.rindex(z)]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["GBK", true, 1, nil, false, nil]
      ["CP949", true, 1, nil, false, nil]
      ["GB18030", true, 1, nil, false, nil]
      ["Shift_JIS", true, 1, nil, false, nil]
      ["Big5", false, 2, 1, true, 1]
    OUT
  end
end
