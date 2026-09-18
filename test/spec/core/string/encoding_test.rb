# frozen_string_literal: true

require "spec_helper"

describe "String: encodings" do
  it "core string answers in us ascii" do
    result = ze0(<<~'RUBY')
      # The strings the core library builds from plain ASCII -- a number's
      # digits, nil's and true's names, an empty collection's inspect -- are
      # US-ASCII, not UTF-8, as rb_usascii_str_new makes them; a symbol's name
      # is US-ASCII when it is plain ASCII; the plain object form is binary.
      # Which encoding a string holds decides what joining it answers.
      rows = {
        "nil.to_s" => nil.to_s, "true.to_s" => true.to_s, "false.inspect" => false.inspect,
        "1.to_s" => 1.to_s, "(2**70).to_s" => (2**70).to_s, "1.5.to_s" => 1.5.to_s, "1.0.inspect" => 1.0.inspect,
        "1r.to_s" => 1r.to_s, "1i.inspect" => 1i.inspect, ":a.to_s" => :a.to_s, ":a.inspect" => :a.inspect,
        "nil.inspect" => nil.inspect, "[].inspect" => [].inspect, "[1].inspect" => [1].inspect, "{}.to_s" => {}.to_s,
        "(1..2).inspect" => (1..2).inspect, "Object.new.to_s" => Object.new.to_s, "Time.at(0).utc.to_s" => Time.at(0).utc.to_s,
        "3.chr" => 3.chr, "65.chr" => 65.chr, "255.chr" => 255.chr, "1.digits.inspect" => 1.digits.inspect,
        "12.to_s(2)" => 12.to_s(2), "format('%d', 1)" => format("%d", 1), "'%s' % 'a'" => "%s" % "a",
        "[1].join" => [1].join, "[].join" => [].join, "Integer.name" => Integer.name, "Comparable.to_s" => Comparable.to_s
      }
      rows.each { |label, value| puts "#{label}\t#{value.encoding}" }
      x = "a".b
      puts "joined\t#{"#{nil}#{x}".encoding} #{"#{1}#{x}".encoding} #{(1.to_s + "é").encoding} #{(+nil.to_s << "é".b).encoding}"

    RUBY

    _(result).must_answer <<~'OUT'
      nil.to_s	US-ASCII
      true.to_s	US-ASCII
      false.inspect	US-ASCII
      1.to_s	US-ASCII
      (2**70).to_s	US-ASCII
      1.5.to_s	US-ASCII
      1.0.inspect	US-ASCII
      1r.to_s	US-ASCII
      1i.inspect	US-ASCII
      :a.to_s	US-ASCII
      :a.inspect	US-ASCII
      nil.inspect	US-ASCII
      [].inspect	US-ASCII
      [1].inspect	US-ASCII
      {}.to_s	US-ASCII
      (1..2).inspect	US-ASCII
      Object.new.to_s	ASCII-8BIT
      Time.at(0).utc.to_s	US-ASCII
      3.chr	US-ASCII
      65.chr	US-ASCII
      255.chr	ASCII-8BIT
      1.digits.inspect	US-ASCII
      12.to_s(2)	US-ASCII
      format('%d', 1)	UTF-8
      '%s' % 'a'	UTF-8
      [1].join	US-ASCII
      [].join	US-ASCII
      Integer.name	US-ASCII
      Comparable.to_s	US-ASCII
      joined	ASCII-8BIT ASCII-8BIT UTF-8 ASCII-8BIT
    OUT
  end

  it "encode asks its fallback for an undefined character" do
    result = ze0(<<~'RUBY')
      # `fallback:` answers for each character the target has no room for:
      # a Hash, a Proc, a Method or anything that answers `[]`, given the
      # character in the encoding of the step that stopped.
      p "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>"x"})
      p "\u{1F600}".encode("EUC-JP", fallback: ->(c){ "y" })
      p "\u{1F600}a".encode("EUC-JP", fallback: {"\u{1F600}"=>"x"}.method(:[]))
      p "\u{1F600}".encode("ISO-8859-1", fallback: Hash.new { |h, k| k.bytesize.to_s })
      begin; "\u{1F600}".encode("EUC-JP", fallback: {}); rescue => e; p e; end
      begin; "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>"\u{1F601}"}); rescue => e; p e; end
      begin; "\xFF".encode("EUC-JP", "UTF-8", fallback: {"\xFF"=>"x"}); rescue => e; p e; end
      begin; "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>1}); rescue => e; p e; end
      p "\u{1F600}".encode("EUC-JP", fallback: 5) rescue p $!
      p "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>"x"}, undef: :replace)
      p "\xA4".b.force_encoding("ISO-8859-1").encode("US-ASCII", fallback: ->(c) { p [c, c.encoding]; "E" })
      p "é".encode("US-ASCII", fallback: ->(c) { "é" }) rescue p $!
      p "aア日".encode("Shift_JIS", "UTF-8").encode("ISO-8859-1", fallback: ->(c) { p [c.encoding, c.bytes]; "?" })
      p "\u{1F600}".encode("UTF-16LE", "UTF-8").encode("EUC-JP", fallback: ->(c) { p [c.encoding, c.bytes]; "?" })
      p "\x81".b.encode("UTF-8", fallback: ->(c) { p [c.encoding, c.bytes]; "B" })

    RUBY

    _(result).must_answer <<~'OUT'
      "x"
      "y"
      "xa"
      "4"
      #<Encoding::UndefinedConversionError: U+1F600 from UTF-8 to EUC-JP>
      #<ArgumentError: too big fallback string>
      #<Encoding::InvalidByteSequenceError: "\xFF" on UTF-8>
      #<TypeError: no implicit conversion of Integer into String>
      #<TypeError: no implicit conversion of String into Integer>
      "?"
      ["¤", #<Encoding:UTF-8>]
      "E"
      #<ArgumentError: too big fallback string>
      [#<Encoding:UTF-8>, [227, 130, 162]]
      [#<Encoding:UTF-8>, [230, 151, 165]]
      "a??"
      [#<Encoding:UTF-8>, [240, 159, 152, 128]]
      "?"
      [#<Encoding:BINARY (ASCII-8BIT)>, [129]]
      "B"
    OUT
  end

  it "grapheme clusters takes an invalid byte as a cluster" do
    result = ze0(<<~'RUBY')
      # grapheme_clusters matches \X from each place in turn, so a byte no
      # character holds is a cluster by itself; UTF-16 and UTF-32 cluster as
      # UTF-8 does, and an encoding that is not Unicode has characters alone.

      def show(s)
        c = s.grapheme_clusters
        p [c, c.map(&:encoding).uniq, s.each_grapheme_cluster.size]
      end
      show "a\xffb́c"
      show "\xff\xfe".b.force_encoding("UTF-8")
      show "é̂x\r\n👨‍👩‍👧🇯🇵"
      show "abc"
      show ""
      show "é".encode("UTF-16LE")
      show "a👍🏽b".encode("UTF-32BE")
      show "e\xCC\x81".b
      show "e\xCC\x81".force_encoding("US-ASCII")
      show "日本".encode("EUC-JP")
      class Sub < String; end
      show Sub.new("éx")
      r = +""
      "ab́".each_grapheme_cluster { |g| r << "[#{g}]" }
      p r

    RUBY

    _(result).must_answer <<~'OUT'
      [["a", "\xFF", "b́", "c"], [#<Encoding:UTF-8>], 4]
      [["\xFF", "\xFE"], [#<Encoding:UTF-8>], 2]
      [["é̂", "x", "\r\n", "👨‍👩‍👧", "🇯🇵"], [#<Encoding:UTF-8>], 5]
      [["a", "b", "c"], [#<Encoding:UTF-8>], 3]
      [[], [], 0]
      [["e\u0301"], [#<Encoding:UTF-16LE>], 1]
      [["a", "\u{1F44D}\u{1F3FD}", "b"], [#<Encoding:UTF-32BE>], 3]
      [["e", "\xCC", "\x81"], [#<Encoding:BINARY (ASCII-8BIT)>], 3]
      [["e", "\xCC", "\x81"], [#<Encoding:US-ASCII>], 3]
      [["\x{C6FC}", "\x{CBDC}"], [#<Encoding:EUC-JP>], 2]
      [["é", "x"], [#<Encoding:UTF-8>], 2]
      "[a][b́]"
    OUT
  end

  it "small string rules follow ruby" do
    result = ze0(<<~'RUBY')
      # Small String rules, each as ruby answers it.
      def t = yield rescue [$!.class, $!.message]

      o = Object.new
      def o.to_str = "x"
      def o.==(v) = (p [:asked, v]; true)
      S = Class.new(String)

      p t { s = +"aaabbb"; s.squeeze!("a"); s }, t { (+"a").prepend(1) }, t { "lit".freeze.send(:initialize, "x") }
      p t { "x" == o }, t { (+"a".encode("US-ASCII")).append_as_bytes("b").encoding }, t { ["ab"].pack("H*").unpack1("H*").encoding }
      p t { r = []; "abc".unpack("C*") { r << _1 }.inspect + r.inspect }, t { ["a\t"].pack("M") }, t { [1].pack("m") }
      p t { q = S.new("zzq").freeze; (-q).class }, t { (-"zzq".dup).class }, t { ({S.new("a") => 1}).keys[0].class }

    RUBY

    _(result).must_answer <<~'OUT'
      "abbb"
      [TypeError, "no implicit conversion of Integer into String"]
      [FrozenError, "can't modify frozen String: \"lit\""]
      [:asked, "x"]
      true
      #<Encoding:US-ASCII>
      #<Encoding:US-ASCII>
      "nil[97, 98, 99]"
      "a\t=\n"
      [TypeError, "no implicit conversion of Integer into String"]
      S
      String
      S
    OUT
  end

  it "the unicode case-mapping and normalization tables reach the binary's data" do
    result = ze0(<<~'RUBY')
      # Unicode case mapping and normalization tables reach the binary's data.
      puts "straße".upcase
      puts "İSTANBUL".downcase
      puts "ǆ".upcase, "ǆ".capitalize
      puts "ABC".swapcase
      puts "é" == "é".unicode_normalize(:nfc)
    RUBY

    _(result).must_answer <<~'OUT'
      STRASSE
      i̇stanbul
      Ǆ
      ǅ
      abc
      true
    OUT
  end

  it "dump writes a re-parseable literal and undump reads it back" do
    result = ze0(<<~'RUBY')
      # String#dump: a re-parseable literal; String#undump: its inverse.

      # Named control escapes and quoting.
      puts "hello".dump
      puts "tab\tnewline\nreturn\r".dump
      puts "bell\a back\b form\f vtab\v esc\e".dump
      puts "quote\"q back\\slash".dump

      # A NUL and other non-named control bytes become \xNN (uppercase).
      puts "null\0byte".dump
      puts "\x01\x02\x1f ctrl \x7f".dump

      # '#' is escaped only before an interpolation sigil.
      puts ("hash#" + "{x}").dump
      puts ("hash#" + "$g").dump
      puts ("hash#" + "@v").dump
      puts "hash#plain".dump

      # UTF-8 non-ASCII uses \u escapes (BMP as \uXXXX, astral as \u{...}).
      puts "café".dump
      puts "emoji😀".dump

      # A binary string uses \xNN for high bytes and keeps its encoding.
      puts "\xC3\xA9".b.dump

      # undump is the exact inverse.
      p "café".dump.undump
      p "café".dump.undump == "café"
      p "\x01\x02\x1f\x7f ctrl".dump.undump.bytes
      p "emoji😀".dump.undump
      p "\xC3\xA9".b.dump.undump == "\xC3\xA9".b

      # undump rejects malformed input.
      begin
        "not a dump".undump
      rescue RuntimeError => e
        puts "raised: #{e.message}"
      end
      begin
        "café".undump
      rescue RuntimeError => e
        puts "raised: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "tab\tnewline\nreturn\r"
      "bell\a back\b form\f vtab\v esc\e"
      "quote\"q back\\slash"
      "null\x00byte"
      "\x01\x02\x1F ctrl \x7F"
      "hash\#{x}"
      "hash\#$g"
      "hash\#@v"
      "hash#plain"
      "caf\u00E9"
      "emoji\u{1F600}"
      "\xC3\xA9"
      "café"
      true
      [1, 2, 31, 127, 32, 99, 116, 114, 108]
      "emoji😀"
      true
      raised: invalid dumped string; not wrapped with '"' nor '"...".force_encoding("...")' form
      raised: non-ASCII character detected
    OUT
  end

  it "String's own methods read wide and legacy text one character at a time" do
    result = ze0(<<~'RUBY')
      # String's own methods read wide and legacy text a character at a time:
      # length and each_char, reverse and slicing, justification, strip and
      # chomp with the encoding's own spaces and newlines, squeeze, count,
      # delete and tr over the encoding's characters, case mapping, succ,
      # inspect and dump, ord and codepoints, and lines in paragraph mode.
      def shown(v)
        case v
        when String then v.valid_encoding? && v.encoding != Encoding::BINARY ? [v.encoding.name, v.encode("UTF-8")] : [v.encoding.name, v.b]
        when Array then v.map { |x| shown(x) }
        else v
        end
      end

      def show(label)
        p [label, shown(yield)]
      rescue StandardError, NotImplementedError => e
        p [label, e.class, e.message.b]
      end

      SAMPLES = {
        "UTF-16LE" => " Grüße 世界😀\r\n\n\nend \n", "UTF-16BE" => " Grüße 世界😀\r\n\n\nend \n",
        "UTF-32LE" => " Grüße 世界😀\r\n\n\nend \n", "UTF-32BE" => " Grüße 世界😀\r\n\n\nend \n",
        "CESU-8" => " Grüße 世界😀\r\n\n\nend \n", "GB18030" => " Grüße 世界😀\r\n\n\nend \n",
        "EUC-JP" => " カナ 世界ａ\r\n\n\nend \n", "Shift_JIS" => " カナ ソ表\\\r\n\n\nend \n", "Big5" => " 中文 測試\r\n\n\nend \n",
        "GBK" => " 中文 测试\r\n\n\nend \n", "EUC-KR" => " 한국 세계\r\n\n\nend \n", "ISO-8859-7" => " Καλη ΑΒ\r\n\n\nend \n",
      }.freeze

      SAMPLES.each do |name, sample|
        e = ->(s) { s.encode(name) }
        text = e.(sample)
        show(:"#{name}_length") { [text.length, text.bytesize, text.chars.size, text.each_char.first(3), text.valid_encoding?, text.ascii_only?] }
        show(:"#{name}_reverse") { [text.reverse, text[2, 3], text[-4..], text.slice(1), text.byteslice(2, 4).valid_encoding?] }
        show(:"#{name}_justify") { [text.strip.center(20, e.("*")), text.strip.ljust(18), text.strip.rjust(18, e.("-="))] }
        show(:"#{name}_strip") { [text.strip, text.lstrip, text.rstrip, text.chomp, text.chop, text.chomp(e.("\n")), text.chomp(e.("d \n"))] }
        show(:"#{name}_lines") { [text.lines, text.lines(chomp: true), text.lines(e.("")), text.lines(e.(""), chomp: true), text.each_line(e.("e")).to_a] }
        show(:"#{name}_lines_default") { [text.lines($/).size, (text.lines("\n") rescue $!.class)] }
        show(:"#{name}_count") { [text.count(e.("e")), text.count(e.("a-z")), text.delete(e.(" ")), text.squeeze, text.squeeze(e.("\n"))] }
        show(:"#{name}_tr") { [text.tr(e.("a-y"), e.("b-z")), text.tr_s(e.("\n"), e.("|")), text.delete(e.("^a-z"))] }
        show(:"#{name}_case") { [text.upcase, text.downcase, text.swapcase, text.capitalize, text.upcase(:ascii)] }
        show(:"#{name}_casecmp") { [text.casecmp(text.upcase), text.casecmp?(text.upcase), text == text.dup, text.eql?(e.(sample))] }
        show(:"#{name}_succ") { [e.("az").succ, e.("zz").succ, text.strip.succ] }
        show(:"#{name}_inspect") { [text.inspect, text.dump] }
        show(:"#{name}_codepoints") { [text.ord, text.codepoints.first(8), text.sum, text.getbyte(1), text.hash == e.(sample).hash] }
        show(:"#{name}_index") { [text.index(e.("e")), text.rindex(e.("e")), text.byteindex(e.("end")), text.include?(e.("nd")), text.start_with?(e.(" ")), text.end_with?(e.("\n"))] }
        show(:"#{name}_split") { [text.split, text.split(e.("\n")), text.split(e.(""), 4), text.partition(e.(" ")), text.rpartition(e.(" "))] }
        show(:"#{name}_insert") { [text.dup.insert(2, e.("<>")), text.dup.prepend(e.(">")), text.dup << e.("!"), text * 2 == text + text] }
        show(:"#{name}_each_grapheme") { text.each_grapheme_cluster.first(4) }
        show(:"#{name}_scrub") { [text.scrub, (text.b + "\xFF".b).force_encoding(name).scrub.bytesize] }
        show(:"#{name}_unicode_normalize") { text.unicode_normalize(:nfd).length }
        show(:"#{name}_encode") { [text.encode("UTF-8").bytesize, text.encode("UTF-16LE").bytesize] }
      end

      # A UTF-16 or UTF-32 text that ends in broken units: the decoder's
      # tables say which bytes are invalid and which a longer text would
      # complete, and a bad byte inside a unit takes the rest of the unit.
      %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].each do |enc|
        ["  ", " ", "\x00 ", "\x00\x00 ", "\x00\x11  ", "   ", "\xD8\x00\x00\x00", "\x00\xD8\x00\x00", "\xDC\x00a", "\x00\xDCa", "\x00\xD8\x00\xDC"].each do |tail|
          s = ("a".encode(enc).b + tail.b).force_encoding(enc)
          label = :"#{enc}_tail_#{tail.unpack1('H*')}"
          show(label) do
            s.encode("UTF-8")
          rescue Encoding::InvalidByteSequenceError => e
            [e.message.b, e.error_bytes.b, e.readagain_bytes&.b, e.incomplete_input?]
          end
          show(:"#{label}_replaced") { [s.encode("UTF-8", invalid: :replace), s.valid_encoding?, s.length, s.scrub.bytesize, s.chars.map(&:bytesize)] }
        end
      end


    RUBY

    _(result).must_answer <<~'OUT'
      [:"UTF-16LE_length", [19, 40, 19, [["UTF-16LE", " "], ["UTF-16LE", "G"], ["UTF-16LE", "r"]], true, false]]
      [:"UTF-16LE_reverse", [["UTF-16LE", "\n dne\n\n\n\r😀界世 eßürG "], ["UTF-16LE", "rüß"], ["UTF-16LE", "nd \n"], ["UTF-16LE", "G"], true]]
      [:"UTF-16LE_justify", [["UTF-16LE", "**Grüße 世界😀\r\n\n\nend**"], ["UTF-16LE", "Grüße 世界😀\r\n\n\nend†"], ["UTF-16LE", "-=Grüße 世界😀\r\n\n\nend"]]]
      [:"UTF-16LE_strip", [["UTF-16LE", "Grüße 世界😀\r\n\n\nend"], ["UTF-16LE", "Grüße 世界😀\r\n\n\nend \n"], ["UTF-16LE", " Grüße 世界😀\r\n\n\nend"], ["UTF-16LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16LE", " Grüße 世界😀\r\n\n\nen"]]]
      [:"UTF-16LE_lines", [[["UTF-16LE", " Grüße 世界😀\r\n"], ["UTF-16LE", "\n"], ["UTF-16LE", "\n"], ["UTF-16LE", "end \n"]], [["UTF-16LE", " Grüße 世界😀\r"], ["UTF-16LE", ""], ["UTF-16LE", ""], ["UTF-16LE", "end "]], [["UTF-16LE", " Grüße 世界😀\r\n\n"], ["UTF-16LE", "end \n"]], [["UTF-16LE", " Grüße 世界😀"], ["UTF-16LE", "end \n"]], [["UTF-16LE", " Grüße"], ["UTF-16LE", " 世界😀\r\n\n\ne"], ["UTF-16LE", "nd \n"]]]]
      [:"UTF-16LE_lines_default", [4, Encoding::CompatibilityError]]
      [:"UTF-16LE_count", [2, 5, ["UTF-16LE", "Grüße世界😀\r\n\n\nend\n"], ["UTF-16LE", " Grüße 世界😀\r\nend \n"], ["UTF-16LE", " Grüße 世界😀\r\nend \n"]]]
      [:"UTF-16LE_tr", [["UTF-16LE", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["UTF-16LE", " Grüße 世界😀\r|end |"], ["UTF-16LE", "reend"]]]
      [:"UTF-16LE_case", [["UTF-16LE", " GRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-16LE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-16LE", " gRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-16LE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-16LE", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:"UTF-16LE_casecmp", [1, true, true, true]]
      [:"UTF-16LE_succ", [["UTF-16LE", "ba"], ["UTF-16LE", "aaa"], ["UTF-16LE", "Grüße 世界😀\r\n\n\nene"]]]
      [:"UTF-16LE_inspect", [["UTF-8", "\" Gr\\u00FC\\u00DFe \\u4E16\\u754C\\u{1F600}\\r\\n\\n\\nend \\n\""], ["ASCII-8BIT", "\" \\x00G\\x00r\\x00\\xFC\\x00\\xDF\\x00e\\x00 \\x00\\x16NLu=\\xD8\\x00\\xDE\\r\\x00\\n\\x00\\n\\x00\\n\\x00e\\x00n\\x00d\\x00 \\x00\\n\\x00\".dup.force_encoding(\"UTF-16LE\")"]]]
      [:"UTF-16LE_codepoints", [32, [32, 71, 114, 252, 223, 101, 32, 19990], 2013, 0, true]]
      [:"UTF-16LE_index", [5, 14, 30, true, true, true]]
      [:"UTF-16LE_split", [[["UTF-16LE", "Grüße"], ["UTF-16LE", "世界😀"], ["UTF-16LE", "end"]], [["UTF-16LE", " Grüße 世界😀\r"], ["UTF-16LE", ""], ["UTF-16LE", ""], ["UTF-16LE", "end "]], [["UTF-16LE", " "], ["UTF-16LE", "G"], ["UTF-16LE", "r"], ["UTF-16LE", "üße 世界😀\r\n\n\nend \n"]], [["UTF-16LE", ""], ["UTF-16LE", " "], ["UTF-16LE", "Grüße 世界😀\r\n\n\nend \n"]], [["UTF-16LE", " Grüße 世界😀\r\n\n\nend"], ["UTF-16LE", " "], ["UTF-16LE", "\n"]]]]
      [:"UTF-16LE_insert", [["UTF-16LE", " G<>rüße 世界😀\r\n\n\nend \n"], ["UTF-16LE", "> Grüße 世界😀\r\n\n\nend \n"], ["UTF-16LE", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:"UTF-16LE_each_grapheme", [["UTF-16LE", " "], ["UTF-16LE", "G"], ["UTF-16LE", "r"], ["UTF-16LE", "ü"]]]
      [:"UTF-16LE_scrub", [["UTF-16LE", " Grüße 世界😀\r\n\n\nend \n"], 42]]
      [:"UTF-16LE_unicode_normalize", 20]
      [:"UTF-16LE_encode", [28, 40]]
      [:"UTF-16BE_length", [19, 40, 19, [["UTF-16BE", " "], ["UTF-16BE", "G"], ["UTF-16BE", "r"]], true, false]]
      [:"UTF-16BE_reverse", [["UTF-16BE", "\n dne\n\n\n\r😀界世 eßürG "], ["UTF-16BE", "rüß"], ["UTF-16BE", "nd \n"], ["UTF-16BE", "G"], true]]
      [:"UTF-16BE_justify", [["UTF-16BE", "**Grüße 世界😀\r\n\n\nend**"], ["UTF-16BE", "Grüße 世界😀\r\n\n\nend†"], ["UTF-16BE", "-=Grüße 世界😀\r\n\n\nend"]]]
      [:"UTF-16BE_strip", [["UTF-16BE", "Grüße 世界😀\r\n\n\nend"], ["UTF-16BE", "Grüße 世界😀\r\n\n\nend \n"], ["UTF-16BE", " Grüße 世界😀\r\n\n\nend"], ["UTF-16BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16BE", " Grüße 世界😀\r\n\n\nen"]]]
      [:"UTF-16BE_lines", [[["UTF-16BE", " Grüße 世界😀\r\n"], ["UTF-16BE", "\n"], ["UTF-16BE", "\n"], ["UTF-16BE", "end \n"]], [["UTF-16BE", " Grüße 世界😀\r"], ["UTF-16BE", ""], ["UTF-16BE", ""], ["UTF-16BE", "end "]], [["UTF-16BE", " Grüße 世界😀\r\n\n"], ["UTF-16BE", "end \n"]], [["UTF-16BE", " Grüße 世界😀"], ["UTF-16BE", "end \n"]], [["UTF-16BE", " Grüße"], ["UTF-16BE", " 世界😀\r\n\n\ne"], ["UTF-16BE", "nd \n"]]]]
      [:"UTF-16BE_lines_default", [4, Encoding::CompatibilityError]]
      [:"UTF-16BE_count", [2, 5, ["UTF-16BE", "Grüße世界😀\r\n\n\nend\n"], ["UTF-16BE", " Grüße 世界😀\r\nend \n"], ["UTF-16BE", " Grüße 世界😀\r\nend \n"]]]
      [:"UTF-16BE_tr", [["UTF-16BE", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["UTF-16BE", " Grüße 世界😀\r|end |"], ["UTF-16BE", "reend"]]]
      [:"UTF-16BE_case", [["UTF-16BE", " GRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-16BE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-16BE", " gRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-16BE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-16BE", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:"UTF-16BE_casecmp", [1, true, true, true]]
      [:"UTF-16BE_succ", [["UTF-16BE", "ba"], ["UTF-16BE", "aaa"], ["UTF-16BE", "Grüße 世界😀\r\n\n\nene"]]]
      [:"UTF-16BE_inspect", [["UTF-8", "\" Gr\\u00FC\\u00DFe \\u4E16\\u754C\\u{1F600}\\r\\n\\n\\nend \\n\""], ["ASCII-8BIT", "\"\\x00 \\x00G\\x00r\\x00\\xFC\\x00\\xDF\\x00e\\x00 N\\x16uL\\xD8=\\xDE\\x00\\x00\\r\\x00\\n\\x00\\n\\x00\\n\\x00e\\x00n\\x00d\\x00 \\x00\\n\".dup.force_encoding(\"UTF-16BE\")"]]]
      [:"UTF-16BE_codepoints", [32, [32, 71, 114, 252, 223, 101, 32, 19990], 2013, 32, true]]
      [:"UTF-16BE_index", [5, 14, 30, true, true, true]]
      [:"UTF-16BE_split", [[["UTF-16BE", "Grüße"], ["UTF-16BE", "世界😀"], ["UTF-16BE", "end"]], [["UTF-16BE", " Grüße 世界😀\r"], ["UTF-16BE", ""], ["UTF-16BE", ""], ["UTF-16BE", "end "]], [["UTF-16BE", " "], ["UTF-16BE", "G"], ["UTF-16BE", "r"], ["UTF-16BE", "üße 世界😀\r\n\n\nend \n"]], [["UTF-16BE", ""], ["UTF-16BE", " "], ["UTF-16BE", "Grüße 世界😀\r\n\n\nend \n"]], [["UTF-16BE", " Grüße 世界😀\r\n\n\nend"], ["UTF-16BE", " "], ["UTF-16BE", "\n"]]]]
      [:"UTF-16BE_insert", [["UTF-16BE", " G<>rüße 世界😀\r\n\n\nend \n"], ["UTF-16BE", "> Grüße 世界😀\r\n\n\nend \n"], ["UTF-16BE", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:"UTF-16BE_each_grapheme", [["UTF-16BE", " "], ["UTF-16BE", "G"], ["UTF-16BE", "r"], ["UTF-16BE", "ü"]]]
      [:"UTF-16BE_scrub", [["UTF-16BE", " Grüße 世界😀\r\n\n\nend \n"], 42]]
      [:"UTF-16BE_unicode_normalize", 20]
      [:"UTF-16BE_encode", [28, 40]]
      [:"UTF-32LE_length", [19, 76, 19, [["UTF-32LE", " "], ["UTF-32LE", "G"], ["UTF-32LE", "r"]], true, false]]
      [:"UTF-32LE_reverse", [["UTF-32LE", "\n dne\n\n\n\r😀界世 eßürG "], ["UTF-32LE", "rüß"], ["UTF-32LE", "nd \n"], ["UTF-32LE", "G"], false]]
      [:"UTF-32LE_justify", Encoding::InvalidByteSequenceError, "incomplete \"  \" on UTF-32LE"]
      [:"UTF-32LE_strip", [["UTF-32LE", "Grüße 世界😀\r\n\n\nend"], ["UTF-32LE", "Grüße 世界😀\r\n\n\nend \n"], ["UTF-32LE", " Grüße 世界😀\r\n\n\nend"], ["UTF-32LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32LE", " Grüße 世界😀\r\n\n\nen"]]]
      [:"UTF-32LE_lines", [[["UTF-32LE", " Grüße 世界😀\r\n"], ["UTF-32LE", "\n"], ["UTF-32LE", "\n"], ["UTF-32LE", "end \n"]], [["UTF-32LE", " Grüße 世界😀\r"], ["UTF-32LE", ""], ["UTF-32LE", ""], ["UTF-32LE", "end "]], [["UTF-32LE", " Grüße 世界😀\r\n\n"], ["UTF-32LE", "end \n"]], [["UTF-32LE", " Grüße 世界😀"], ["UTF-32LE", "end \n"]], [["UTF-32LE", " Grüße"], ["UTF-32LE", " 世界😀\r\n\n\ne"], ["UTF-32LE", "nd \n"]]]]
      [:"UTF-32LE_lines_default", [4, Encoding::CompatibilityError]]
      [:"UTF-32LE_count", [2, 5, ["UTF-32LE", "Grüße世界😀\r\n\n\nend\n"], ["UTF-32LE", " Grüße 世界😀\r\nend \n"], ["UTF-32LE", " Grüße 世界😀\r\nend \n"]]]
      [:"UTF-32LE_tr", [["UTF-32LE", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["UTF-32LE", " Grüße 世界😀\r|end |"], ["UTF-32LE", "reend"]]]
      [:"UTF-32LE_case", [["UTF-32LE", " GRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-32LE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-32LE", " gRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-32LE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-32LE", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:"UTF-32LE_casecmp", [1, true, true, true]]
      [:"UTF-32LE_succ", [["UTF-32LE", "ba"], ["UTF-32LE", "aaa"], ["UTF-32LE", "Grüße 世界😀\r\n\n\nene"]]]
      [:"UTF-32LE_inspect", [["UTF-8", "\" Gr\\u00FC\\u00DFe \\u4E16\\u754C\\u{1F600}\\r\\n\\n\\nend \\n\""], ["ASCII-8BIT", "\" \\x00\\x00\\x00G\\x00\\x00\\x00r\\x00\\x00\\x00\\xFC\\x00\\x00\\x00\\xDF\\x00\\x00\\x00e\\x00\\x00\\x00 \\x00\\x00\\x00\\x16N\\x00\\x00Lu\\x00\\x00\\x00\\xF6\\x01\\x00\\r\\x00\\x00\\x00\\n\\x00\\x00\\x00\\n\\x00\\x00\\x00\\n\\x00\\x00\\x00e\\x00\\x00\\x00n\\x00\\x00\\x00d\\x00\\x00\\x00 \\x00\\x00\\x00\\n\\x00\\x00\\x00\".dup.force_encoding(\"UTF-32LE\")"]]]
      [:"UTF-32LE_codepoints", [32, [32, 71, 114, 252, 223, 101, 32, 19990], 1761, 0, true]]
      [:"UTF-32LE_index", [5, 14, 56, true, true, true]]
      [:"UTF-32LE_split", [[["UTF-32LE", "Grüße"], ["UTF-32LE", "世界😀"], ["UTF-32LE", "end"]], [["UTF-32LE", " Grüße 世界😀\r"], ["UTF-32LE", ""], ["UTF-32LE", ""], ["UTF-32LE", "end "]], [["UTF-32LE", " "], ["UTF-32LE", "G"], ["UTF-32LE", "r"], ["UTF-32LE", "üße 世界😀\r\n\n\nend \n"]], [["UTF-32LE", ""], ["UTF-32LE", " "], ["UTF-32LE", "Grüße 世界😀\r\n\n\nend \n"]], [["UTF-32LE", " Grüße 世界😀\r\n\n\nend"], ["UTF-32LE", " "], ["UTF-32LE", "\n"]]]]
      [:"UTF-32LE_insert", [["UTF-32LE", " G<>rüße 世界😀\r\n\n\nend \n"], ["UTF-32LE", "> Grüße 世界😀\r\n\n\nend \n"], ["UTF-32LE", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:"UTF-32LE_each_grapheme", [["UTF-32LE", " "], ["UTF-32LE", "G"], ["UTF-32LE", "r"], ["UTF-32LE", "ü"]]]
      [:"UTF-32LE_scrub", [["UTF-32LE", " Grüße 世界😀\r\n\n\nend \n"], 80]]
      [:"UTF-32LE_unicode_normalize", 20]
      [:"UTF-32LE_encode", [28, 40]]
      [:"UTF-32BE_length", [19, 76, 19, [["UTF-32BE", " "], ["UTF-32BE", "G"], ["UTF-32BE", "r"]], true, false]]
      [:"UTF-32BE_reverse", [["UTF-32BE", "\n dne\n\n\n\r😀界世 eßürG "], ["UTF-32BE", "rüß"], ["UTF-32BE", "nd \n"], ["UTF-32BE", "G"], false]]
      [:"UTF-32BE_justify", Encoding::InvalidByteSequenceError, "\"  \" on UTF-32BE"]
      [:"UTF-32BE_strip", [["UTF-32BE", "Grüße 世界😀\r\n\n\nend"], ["UTF-32BE", "Grüße 世界😀\r\n\n\nend \n"], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend"], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32BE", " Grüße 世界😀\r\n\n\nen"]]]
      [:"UTF-32BE_lines", [[["UTF-32BE", " Grüße 世界😀\r\n"], ["UTF-32BE", "\n"], ["UTF-32BE", "\n"], ["UTF-32BE", "end \n"]], [["UTF-32BE", " Grüße 世界😀\r"], ["UTF-32BE", ""], ["UTF-32BE", ""], ["UTF-32BE", "end "]], [["UTF-32BE", " Grüße 世界😀\r\n\n"], ["UTF-32BE", "end \n"]], [["UTF-32BE", " Grüße 世界😀"], ["UTF-32BE", "end \n"]], [["UTF-32BE", " Grüße"], ["UTF-32BE", " 世界😀\r\n\n\ne"], ["UTF-32BE", "nd \n"]]]]
      [:"UTF-32BE_lines_default", [4, Encoding::CompatibilityError]]
      [:"UTF-32BE_count", [2, 5, ["UTF-32BE", "Grüße世界😀\r\n\n\nend\n"], ["UTF-32BE", " Grüße 世界😀\r\nend \n"], ["UTF-32BE", " Grüße 世界😀\r\nend \n"]]]
      [:"UTF-32BE_tr", [["UTF-32BE", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["UTF-32BE", " Grüße 世界😀\r|end |"], ["UTF-32BE", "reend"]]]
      [:"UTF-32BE_case", [["UTF-32BE", " GRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-32BE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-32BE", " gRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-32BE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-32BE", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:"UTF-32BE_casecmp", [1, true, true, true]]
      [:"UTF-32BE_succ", [["UTF-32BE", "ba"], ["UTF-32BE", "aaa"], ["UTF-32BE", "Grüße 世界😀\r\n\n\nene"]]]
      [:"UTF-32BE_inspect", [["UTF-8", "\" Gr\\u00FC\\u00DFe \\u4E16\\u754C\\u{1F600}\\r\\n\\n\\nend \\n\""], ["ASCII-8BIT", "\"\\x00\\x00\\x00 \\x00\\x00\\x00G\\x00\\x00\\x00r\\x00\\x00\\x00\\xFC\\x00\\x00\\x00\\xDF\\x00\\x00\\x00e\\x00\\x00\\x00 \\x00\\x00N\\x16\\x00\\x00uL\\x00\\x01\\xF6\\x00\\x00\\x00\\x00\\r\\x00\\x00\\x00\\n\\x00\\x00\\x00\\n\\x00\\x00\\x00\\n\\x00\\x00\\x00e\\x00\\x00\\x00n\\x00\\x00\\x00d\\x00\\x00\\x00 \\x00\\x00\\x00\\n\".dup.force_encoding(\"UTF-32BE\")"]]]
      [:"UTF-32BE_codepoints", [32, [32, 71, 114, 252, 223, 101, 32, 19990], 1761, 0, true]]
      [:"UTF-32BE_index", [5, nil, 56, true, true, true]]
      [:"UTF-32BE_split", [[["UTF-32BE", "Grüße"], ["UTF-32BE", "世界😀"], ["UTF-32BE", "end"]], [["UTF-32BE", " Grüße 世界😀\r"], ["UTF-32BE", ""], ["UTF-32BE", ""], ["UTF-32BE", "end "]], [["UTF-32BE", " "], ["UTF-32BE", "G"], ["UTF-32BE", "r"], ["UTF-32BE", "üße 世界😀\r\n\n\nend \n"]], [["UTF-32BE", ""], ["UTF-32BE", " "], ["UTF-32BE", "Grüße 世界😀\r\n\n\nend \n"]], [["UTF-32BE", ""], ["UTF-32BE", ""], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend \n"]]]]
      [:"UTF-32BE_insert", [["UTF-32BE", " G<>rüße 世界😀\r\n\n\nend \n"], ["UTF-32BE", "> Grüße 世界😀\r\n\n\nend \n"], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:"UTF-32BE_each_grapheme", [["UTF-32BE", " "], ["UTF-32BE", "G"], ["UTF-32BE", "r"], ["UTF-32BE", "ü"]]]
      [:"UTF-32BE_scrub", [["UTF-32BE", " Grüße 世界😀\r\n\n\nend \n"], 80]]
      [:"UTF-32BE_unicode_normalize", 20]
      [:"UTF-32BE_encode", [28, 40]]
      [:"CESU-8_length", [19, 30, 19, [["CESU-8", " "], ["CESU-8", "G"], ["CESU-8", "r"]], true, false]]
      [:"CESU-8_reverse", [["CESU-8", "\n dne\n\n\n\r😀界世 eßürG "], ["CESU-8", "rüß"], ["CESU-8", "nd \n"], ["CESU-8", "G"], false]]
      [:"CESU-8_justify", [["CESU-8", "**Grüße 世界😀\r\n\n\nend**"], ["CESU-8", "Grüße 世界😀\r\n\n\nend  "], ["CESU-8", "-=Grüße 世界😀\r\n\n\nend"]]]
      [:"CESU-8_strip", [["CESU-8", "Grüße 世界😀\r\n\n\nend"], ["CESU-8", "Grüße 世界😀\r\n\n\nend \n"], ["CESU-8", " Grüße 世界😀\r\n\n\nend"], ["CESU-8", " Grüße 世界😀\r\n\n\nend "], ["CESU-8", " Grüße 世界😀\r\n\n\nend "], ["CESU-8", " Grüße 世界😀\r\n\n\nend "], ["CESU-8", " Grüße 世界😀\r\n\n\nen"]]]
      [:"CESU-8_lines", [[["CESU-8", " Grüße 世界😀\r\n"], ["CESU-8", "\n"], ["CESU-8", "\n"], ["CESU-8", "end \n"]], [["CESU-8", " Grüße 世界😀"], ["CESU-8", ""], ["CESU-8", ""], ["CESU-8", "end "]], [["CESU-8", " Grüße 世界😀\r\n\n"], ["CESU-8", "end \n"]], [["CESU-8", " Grüße 世界😀"], ["CESU-8", "end \n"]], [["CESU-8", " Grüße"], ["CESU-8", " 世界😀\r\n\n\ne"], ["CESU-8", "nd \n"]]]]
      [:"CESU-8_lines_default", [4, [["CESU-8", " Grüße 世界😀\r\n"], ["CESU-8", "\n"], ["CESU-8", "\n"], ["CESU-8", "end \n"]]]]
      [:"CESU-8_count", [2, 5, ["CESU-8", "Grüße世界😀\r\n\n\nend\n"], ["CESU-8", " Grüße 世界😀\r\nend \n"], ["CESU-8", " Grüße 世界😀\r\nend \n"]]]
      [:"CESU-8_tr", [["CESU-8", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["CESU-8", " Grüße 世界😀\r|end |"], ["CESU-8", "reend"]]]
      [:"CESU-8_case", [["CESU-8", " GRÜSSE 世界😀\r\n\n\nEND \n"], ["CESU-8", " grüße 世界😀\r\n\n\nend \n"], ["CESU-8", " gRÜSSE 世界😀\r\n\n\nEND \n"], ["CESU-8", " grüße 世界😀\r\n\n\nend \n"], ["CESU-8", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:"CESU-8_casecmp", [1, true, true, true]]
      [:"CESU-8_succ", [["CESU-8", "ba"], ["CESU-8", "aaa"], ["CESU-8", "Grüße 世界😀\r\n\n\nene"]]]
      [:"CESU-8_inspect", [["UTF-8", "\" Gr\\u00FC\\u00DFe \\u4E16\\u754C\\u{1F600}\\r\\n\\n\\nend \\n\""], ["CESU-8", "\" Gr\\xC3\\xBC\\xC3\\x9Fe \\xE4\\xB8\\x96\\xE7\\x95\\x8C\\xED\\xA0\\xBD\\xED\\xB8\\x80\\r\\n\\n\\nend \\n\""]]]
      [:"CESU-8_codepoints", [32, [32, 71, 114, 252, 223, 101, 32, 19990], 3700, 71, true]]
      [:"CESU-8_index", [5, 14, 25, true, true, true]]
      [:"CESU-8_split", [[["CESU-8", "Grüße"], ["CESU-8", "世界😀"], ["CESU-8", "end"]], [["CESU-8", " Grüße 世界😀\r"], ["CESU-8", ""], ["CESU-8", ""], ["CESU-8", "end "]], [["CESU-8", " "], ["CESU-8", "G"], ["CESU-8", "r"], ["CESU-8", "üße 世界😀\r\n\n\nend \n"]], [["CESU-8", ""], ["CESU-8", " "], ["CESU-8", "Grüße 世界😀\r\n\n\nend \n"]], [["CESU-8", " Grüße 世界😀\r\n\n\nend"], ["CESU-8", " "], ["CESU-8", "\n"]]]]
      [:"CESU-8_insert", [["CESU-8", " G<>rüße 世界😀\r\n\n\nend \n"], ["CESU-8", "> Grüße 世界😀\r\n\n\nend \n"], ["CESU-8", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:"CESU-8_each_grapheme", [["CESU-8", " "], ["CESU-8", "G"], ["CESU-8", "r"], ["CESU-8", "ü"]]]
      [:"CESU-8_scrub", [["CESU-8", " Grüße 世界😀\r\n\n\nend \n"], 31]]
      [:"CESU-8_unicode_normalize", Encoding::CompatibilityError, "Unicode Normalization not appropriate for CESU-8"]
      [:"CESU-8_encode", [28, 40]]
      [:GB18030_length, [19, 28, 19, [["GB18030", " "], ["GB18030", "G"], ["GB18030", "r"]], true, false]]
      [:GB18030_reverse, [["GB18030", "\n dne\n\n\n\r😀界世 eßürG "], ["GB18030", "rüß"], ["GB18030", "nd \n"], ["GB18030", "G"], false]]
      [:GB18030_justify, [["GB18030", "**Grüße 世界😀\r\n\n\nend**"], ["GB18030", "Grüße 世界😀\r\n\n\nend  "], ["GB18030", "-=Grüße 世界😀\r\n\n\nend"]]]
      [:GB18030_strip, [["GB18030", "Grüße 世界😀\r\n\n\nend"], ["GB18030", "Grüße 世界😀\r\n\n\nend \n"], ["GB18030", " Grüße 世界😀\r\n\n\nend"], ["GB18030", " Grüße 世界😀\r\n\n\nend "], ["GB18030", " Grüße 世界😀\r\n\n\nend "], ["GB18030", " Grüße 世界😀\r\n\n\nend "], ["GB18030", " Grüße 世界😀\r\n\n\nen"]]]
      [:GB18030_lines, [[["GB18030", " Grüße 世界😀\r\n"], ["GB18030", "\n"], ["GB18030", "\n"], ["GB18030", "end \n"]], [["GB18030", " Grüße 世界😀"], ["GB18030", ""], ["GB18030", ""], ["GB18030", "end "]], [["GB18030", " Grüße 世界😀\r\n\n"], ["GB18030", "end \n"]], [["GB18030", " Grüße 世界😀"], ["GB18030", "end \n"]], [["GB18030", " Grüße"], ["GB18030", " 世界😀\r\n\n\ne"], ["GB18030", "nd \n"]]]]
      [:GB18030_lines_default, [4, [["GB18030", " Grüße 世界😀\r\n"], ["GB18030", "\n"], ["GB18030", "\n"], ["GB18030", "end \n"]]]]
      [:GB18030_count, [2, 5, ["GB18030", "Grüße世界😀\r\n\n\nend\n"], ["GB18030", " Grüße 世界😀\r\nend \n"], ["GB18030", " Grüße 世界😀\r\nend \n"]]]
      [:GB18030_tr, [["GB18030", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["GB18030", " Grüße 世界😀\r|end |"], ["GB18030", "reend"]]]
      [:GB18030_case, [["GB18030", " GRüßE 世界😀\r\n\n\nEND \n"], ["GB18030", " grüße 世界😀\r\n\n\nend \n"], ["GB18030", " gRüßE 世界😀\r\n\n\nEND \n"], ["GB18030", " grüße 世界😀\r\n\n\nend \n"], ["GB18030", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:GB18030_casecmp, [0, true, true, true]]
      [:GB18030_succ, [["GB18030", "ba"], ["GB18030", "aaa"], ["GB18030", "Grüße 世界😀\r\n\n\nene"]]]
      [:GB18030_inspect, [["UTF-8", "\" Gr\\x{A8B9}\\x{81308938}e \\x{CAC0}\\x{BDE7}\\x{9439FC36}\\r\\n\\n\\nend \\n\""], ["GB18030", "\" Gr\\xA8\\xB9\\x810\\x898e \\xCA\\xC0\\xBD\\xE7\\x949\\xFC6\\r\\n\\n\\nend \\n\""]]]
      [:GB18030_codepoints, [32, [32, 71, 114, 43193, 2167441720, 101, 32, 51904], 2794, 71, true]]
      [:GB18030_index, [5, 14, 23, true, true, true]]
      [:GB18030_split, [[["GB18030", "Grüße"], ["GB18030", "世界😀"], ["GB18030", "end"]], [["GB18030", " Grüße 世界😀\r"], ["GB18030", ""], ["GB18030", ""], ["GB18030", "end "]], [["GB18030", " "], ["GB18030", "G"], ["GB18030", "r"], ["GB18030", "üße 世界😀\r\n\n\nend \n"]], [["GB18030", ""], ["GB18030", " "], ["GB18030", "Grüße 世界😀\r\n\n\nend \n"]], [["GB18030", " Grüße 世界😀\r\n\n\nend"], ["GB18030", " "], ["GB18030", "\n"]]]]
      [:GB18030_insert, [["GB18030", " G<>rüße 世界😀\r\n\n\nend \n"], ["GB18030", "> Grüße 世界😀\r\n\n\nend \n"], ["GB18030", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:GB18030_each_grapheme, [["GB18030", " "], ["GB18030", "G"], ["GB18030", "r"], ["GB18030", "ü"]]]
      [:GB18030_scrub, [["GB18030", " Grüße 世界😀\r\n\n\nend \n"], 29]]
      [:GB18030_unicode_normalize, 20]
      [:GB18030_encode, [28, 40]]
      [:"EUC-JP_length", [16, 21, 16, [["EUC-JP", " "], ["EUC-JP", "カ"], ["EUC-JP", "ナ"]], true, false]]
      [:"EUC-JP_reverse", [["EUC-JP", "\n dne\n\n\n\rａ界世 ナカ "], ["EUC-JP", "ナ 世"], ["EUC-JP", "nd \n"], ["EUC-JP", "カ"], false]]
      [:"EUC-JP_justify", [["EUC-JP", "***カナ 世界ａ\r\n\n\nend****"], ["EUC-JP", "カナ 世界ａ\r\n\n\nend     "], ["EUC-JP", "-=-=-カナ 世界ａ\r\n\n\nend"]]]
      [:"EUC-JP_strip", [["EUC-JP", "カナ 世界ａ\r\n\n\nend"], ["EUC-JP", "カナ 世界ａ\r\n\n\nend \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nend"], ["EUC-JP", " カナ 世界ａ\r\n\n\nend "], ["EUC-JP", " カナ 世界ａ\r\n\n\nend "], ["EUC-JP", " カナ 世界ａ\r\n\n\nend "], ["EUC-JP", " カナ 世界ａ\r\n\n\nen"]]]
      [:"EUC-JP_lines", [[["EUC-JP", " カナ 世界ａ\r\n"], ["EUC-JP", "\n"], ["EUC-JP", "\n"], ["EUC-JP", "end \n"]], [["EUC-JP", " カナ 世界ａ"], ["EUC-JP", ""], ["EUC-JP", ""], ["EUC-JP", "end "]], [["EUC-JP", " カナ 世界ａ\r\n\n"], ["EUC-JP", "end \n"]], [["EUC-JP", " カナ 世界ａ"], ["EUC-JP", "end \n"]], [["EUC-JP", " カナ 世界ａ\r\n\n\ne"], ["EUC-JP", "nd \n"]]]]
      [:"EUC-JP_lines_default", [4, [["EUC-JP", " カナ 世界ａ\r\n"], ["EUC-JP", "\n"], ["EUC-JP", "\n"], ["EUC-JP", "end \n"]]]]
      [:"EUC-JP_count", [1, 3, ["EUC-JP", "カナ世界ａ\r\n\n\nend\n"], ["EUC-JP", " カナ 世界ａ\r\nend \n"], ["EUC-JP", " カナ 世界ａ\r\nend \n"]]]
      [:"EUC-JP_tr", [["EUC-JP", " カナ 世界ａ\r\n\n\nfoe \n"], ["EUC-JP", " カナ 世界ａ\r|end |"], ["EUC-JP", "end"]]]
      [:"EUC-JP_case", [["EUC-JP", " カナ 世界ａ\r\n\n\nEND \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nend \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nEND \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nend \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nEND \n"]]]
      [:"EUC-JP_casecmp", [0, true, true, true]]
      [:"EUC-JP_succ", [["EUC-JP", "ba"], ["EUC-JP", "aaa"], ["EUC-JP", "カナ 世界ａ\r\n\n\nene"]]]
      [:"EUC-JP_inspect", [["UTF-8", "\" \\x{A5AB}\\x{A5CA} \\x{C0A4}\\x{B3A6}\\x{A3E1}\\r\\n\\n\\nend \\n\""], ["EUC-JP", "\" \\xA5\\xAB\\xA5\\xCA \\xC0\\xA4\\xB3\\xA6\\xA3\\xE1\\r\\n\\n\\nend \\n\""]]]
      [:"EUC-JP_codepoints", [32, [32, 42411, 42442, 32, 49316, 45990, 41953, 13], 2252, 165, true]]
      [:"EUC-JP_index", [11, 11, 16, true, true, true]]
      [:"EUC-JP_split", [[["EUC-JP", "カナ"], ["EUC-JP", "世界ａ"], ["EUC-JP", "end"]], [["EUC-JP", " カナ 世界ａ\r"], ["EUC-JP", ""], ["EUC-JP", ""], ["EUC-JP", "end "]], [["EUC-JP", " "], ["EUC-JP", "カ"], ["EUC-JP", "ナ"], ["EUC-JP", " 世界ａ\r\n\n\nend \n"]], [["EUC-JP", ""], ["EUC-JP", " "], ["EUC-JP", "カナ 世界ａ\r\n\n\nend \n"]], [["EUC-JP", " カナ 世界ａ\r\n\n\nend"], ["EUC-JP", " "], ["EUC-JP", "\n"]]]]
      [:"EUC-JP_insert", [["EUC-JP", " カ<>ナ 世界ａ\r\n\n\nend \n"], ["EUC-JP", "> カナ 世界ａ\r\n\n\nend \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nend \n!"], true]]
      [:"EUC-JP_each_grapheme", [["EUC-JP", " "], ["EUC-JP", "カ"], ["EUC-JP", "ナ"], ["EUC-JP", " "]]]
      [:"EUC-JP_scrub", [["EUC-JP", " カナ 世界ａ\r\n\n\nend \n"], 22]]
      [:"EUC-JP_unicode_normalize", Encoding::CompatibilityError, "Unicode Normalization not appropriate for EUC-JP"]
      [:"EUC-JP_encode", [26, 32]]
      [:Shift_JIS_length, [16, 20, 16, [["Shift_JIS", " "], ["Shift_JIS", "カ"], ["Shift_JIS", "ナ"]], true, false]]
      [:Shift_JIS_reverse, [["Shift_JIS", "\n dne\n\n\n\r\\表ソ ナカ "], ["Shift_JIS", "ナ ソ"], ["Shift_JIS", "nd \n"], ["Shift_JIS", "カ"], true]]
      [:Shift_JIS_justify, [["Shift_JIS", "***カナ ソ表\\\r\n\n\nend****"], ["Shift_JIS", "カナ ソ表\\\r\n\n\nend     "], ["Shift_JIS", "-=-=-カナ ソ表\\\r\n\n\nend"]]]
      [:Shift_JIS_strip, [["Shift_JIS", "カナ ソ表\\\r\n\n\nend"], ["Shift_JIS", "カナ ソ表\\\r\n\n\nend \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend "], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend "], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend "], ["Shift_JIS", " カナ ソ表\\\r\n\n\nen"]]]
      [:Shift_JIS_lines, [[["Shift_JIS", " カナ ソ表\\\r\n"], ["Shift_JIS", "\n"], ["Shift_JIS", "\n"], ["Shift_JIS", "end \n"]], [["Shift_JIS", " カナ ソ表\\"], ["Shift_JIS", ""], ["Shift_JIS", ""], ["Shift_JIS", "end "]], [["Shift_JIS", " カナ ソ表\\\r\n\n"], ["Shift_JIS", "end \n"]], [["Shift_JIS", " カナ ソ表\\"], ["Shift_JIS", "end \n"]], [["Shift_JIS", " カナ ソ表\\\r\n\n\ne"], ["Shift_JIS", "nd \n"]]]]
      [:Shift_JIS_lines_default, [4, [["Shift_JIS", " カナ ソ表\\\r\n"], ["Shift_JIS", "\n"], ["Shift_JIS", "\n"], ["Shift_JIS", "end \n"]]]]
      [:Shift_JIS_count, [1, 3, ["Shift_JIS", "カナソ表\\\r\n\n\nend\n"], ["Shift_JIS", " カナ ソ表\\\r\nend \n"], ["Shift_JIS", " カナ ソ表\\\r\nend \n"]]]
      [:Shift_JIS_tr, [["Shift_JIS", " カナ ソ表\\\r\n\n\nfoe \n"], ["Shift_JIS", " カナ ソ表\\\r|end |"], ["Shift_JIS", "end"]]]
      [:Shift_JIS_case, [["Shift_JIS", " カナ ソ表\\\r\n\n\nEND \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nEND \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nEND \n"]]]
      [:Shift_JIS_casecmp, [0, true, true, true]]
      [:Shift_JIS_succ, [["Shift_JIS", "ba"], ["Shift_JIS", "aaa"], ["Shift_JIS", "カナ ソ表\\\r\n\n\nene"]]]
      [:Shift_JIS_inspect, [["UTF-8", "\" \\x{834A}\\x{8369} \\x{835C}\\x{955C}\\\\\\r\\n\\n\\nend \\n\""], ["Shift_JIS", "\" \\x83J\\x83i \\x83\\\\\\x95\\\\\\\\\\r\\n\\n\\nend \\n\""]]]
      [:Shift_JIS_codepoints, [32, [32, 33610, 33641, 32, 33628, 38236, 92, 13], 1457, 131, true]]
      [:Shift_JIS_index, [11, 11, 15, true, true, true]]
      [:Shift_JIS_split, [[["Shift_JIS", "カナ"], ["Shift_JIS", "ソ表\\"], ["Shift_JIS", "end"]], [["Shift_JIS", " カナ ソ表\\\r"], ["Shift_JIS", ""], ["Shift_JIS", ""], ["Shift_JIS", "end "]], [["Shift_JIS", " "], ["Shift_JIS", "カ"], ["Shift_JIS", "ナ"], ["Shift_JIS", " ソ表\\\r\n\n\nend \n"]], [["Shift_JIS", ""], ["Shift_JIS", " "], ["Shift_JIS", "カナ ソ表\\\r\n\n\nend \n"]], [["Shift_JIS", " カナ ソ表\\\r\n\n\nend"], ["Shift_JIS", " "], ["Shift_JIS", "\n"]]]]
      [:Shift_JIS_insert, [["Shift_JIS", " カ<>ナ ソ表\\\r\n\n\nend \n"], ["Shift_JIS", "> カナ ソ表\\\r\n\n\nend \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend \n!"], true]]
      [:Shift_JIS_each_grapheme, [["Shift_JIS", " "], ["Shift_JIS", "カ"], ["Shift_JIS", "ナ"], ["Shift_JIS", " "]]]
      [:Shift_JIS_scrub, [["Shift_JIS", " カナ ソ表\\\r\n\n\nend \n"], 21]]
      [:Shift_JIS_unicode_normalize, Encoding::CompatibilityError, "Unicode Normalization not appropriate for Shift_JIS"]
      [:Shift_JIS_encode, [24, 32]]
      [:Big5_length, [15, 19, 15, [["Big5", " "], ["Big5", "中"], ["Big5", "文"]], true, false]]
      [:Big5_reverse, [["Big5", "\n dne\n\n\n\r試測 文中 "], ["Big5", "文 測"], ["Big5", "nd \n"], ["Big5", "中"], false]]
      [:Big5_justify, [["Big5", "****中文 測試\r\n\n\nend****"], ["Big5", "中文 測試\r\n\n\nend      "], ["Big5", "-=-=-=中文 測試\r\n\n\nend"]]]
      [:Big5_strip, [["Big5", "中文 測試\r\n\n\nend"], ["Big5", "中文 測試\r\n\n\nend \n"], ["Big5", " 中文 測試\r\n\n\nend"], ["Big5", " 中文 測試\r\n\n\nend "], ["Big5", " 中文 測試\r\n\n\nend "], ["Big5", " 中文 測試\r\n\n\nend "], ["Big5", " 中文 測試\r\n\n\nen"]]]
      [:Big5_lines, [[["Big5", " 中文 測試\r\n"], ["Big5", "\n"], ["Big5", "\n"], ["Big5", "end \n"]], [["Big5", " 中文 測試"], ["Big5", ""], ["Big5", ""], ["Big5", "end "]], [["Big5", " 中文 測試\r\n\n"], ["Big5", "end \n"]], [["Big5", " 中文 測試"], ["Big5", "end \n"]], [["Big5", " 中文 測試\r\n\n\ne"], ["Big5", "nd \n"]]]]
      [:Big5_lines_default, [4, [["Big5", " 中文 測試\r\n"], ["Big5", "\n"], ["Big5", "\n"], ["Big5", "end \n"]]]]
      [:Big5_count, [1, 3, ["Big5", "中文測試\r\n\n\nend\n"], ["Big5", " 中文 測試\r\nend \n"], ["Big5", " 中文 測試\r\nend \n"]]]
      [:Big5_tr, [["Big5", " 中文 測試\r\n\n\nfoe \n"], ["Big5", " 中文 測試\r|end |"], ["Big5", "end"]]]
      [:Big5_case, [["Big5", " 中文 測試\r\n\n\nEND \n"], ["Big5", " 中文 測試\r\n\n\nend \n"], ["Big5", " 中文 測試\r\n\n\nEND \n"], ["Big5", " 中文 測試\r\n\n\nend \n"], ["Big5", " 中文 測試\r\n\n\nEND \n"]]]
      [:Big5_casecmp, [0, true, true, true]]
      [:Big5_succ, [["Big5", "ba"], ["Big5", "aaa"], ["Big5", "中文 測試\r\n\n\nene"]]]
      [:Big5_inspect, [["UTF-8", "\" \\x{A4A4}\\x{A4E5} \\x{B4FA}\\x{B8D5}\\r\\n\\n\\nend \\n\""], ["Big5", "\" \\xA4\\xA4\\xA4\\xE5 \\xB4\\xFA\\xB8\\xD5\\r\\n\\n\\nend \\n\""]]]
      [:Big5_codepoints, [32, [32, 42148, 42213, 32, 46330, 47317, 13, 10], 2008, 164, true]]
      [:Big5_index, [10, 10, 14, true, true, true]]
      [:Big5_split, [[["Big5", "中文"], ["Big5", "測試"], ["Big5", "end"]], [["Big5", " 中文 測試\r"], ["Big5", ""], ["Big5", ""], ["Big5", "end "]], [["Big5", " "], ["Big5", "中"], ["Big5", "文"], ["Big5", " 測試\r\n\n\nend \n"]], [["Big5", ""], ["Big5", " "], ["Big5", "中文 測試\r\n\n\nend \n"]], [["Big5", " 中文 測試\r\n\n\nend"], ["Big5", " "], ["Big5", "\n"]]]]
      [:Big5_insert, [["Big5", " 中<>文 測試\r\n\n\nend \n"], ["Big5", "> 中文 測試\r\n\n\nend \n"], ["Big5", " 中文 測試\r\n\n\nend \n!"], true]]
      [:Big5_each_grapheme, [["Big5", " "], ["Big5", "中"], ["Big5", "文"], ["Big5", " "]]]
      [:Big5_scrub, [["Big5", " 中文 測試\r\n\n\nend \n"], 20]]
      [:Big5_unicode_normalize, Encoding::CompatibilityError, "Unicode Normalization not appropriate for Big5"]
      [:Big5_encode, [23, 30]]
      [:GBK_length, [15, 19, 15, [["GBK", " "], ["GBK", "中"], ["GBK", "文"]], true, false]]
      [:GBK_reverse, [["GBK", "\n dne\n\n\n\r试测 文中 "], ["GBK", "文 测"], ["GBK", "nd \n"], ["GBK", "中"], false]]
      [:GBK_justify, [["GBK", "****中文 测试\r\n\n\nend****"], ["GBK", "中文 测试\r\n\n\nend      "], ["GBK", "-=-=-=中文 测试\r\n\n\nend"]]]
      [:GBK_strip, [["GBK", "中文 测试\r\n\n\nend"], ["GBK", "中文 测试\r\n\n\nend \n"], ["GBK", " 中文 测试\r\n\n\nend"], ["GBK", " 中文 测试\r\n\n\nend "], ["GBK", " 中文 测试\r\n\n\nend "], ["GBK", " 中文 测试\r\n\n\nend "], ["GBK", " 中文 测试\r\n\n\nen"]]]
      [:GBK_lines, [[["GBK", " 中文 测试\r\n"], ["GBK", "\n"], ["GBK", "\n"], ["GBK", "end \n"]], [["GBK", " 中文 测试"], ["GBK", ""], ["GBK", ""], ["GBK", "end "]], [["GBK", " 中文 测试\r\n\n"], ["GBK", "end \n"]], [["GBK", " 中文 测试"], ["GBK", "end \n"]], [["GBK", " 中文 测试\r\n\n\ne"], ["GBK", "nd \n"]]]]
      [:GBK_lines_default, [4, [["GBK", " 中文 测试\r\n"], ["GBK", "\n"], ["GBK", "\n"], ["GBK", "end \n"]]]]
      [:GBK_count, [1, 3, ["GBK", "中文测试\r\n\n\nend\n"], ["GBK", " 中文 测试\r\nend \n"], ["GBK", " 中文 测试\r\nend \n"]]]
      [:GBK_tr, [["GBK", " 中文 测试\r\n\n\nfoe \n"], ["GBK", " 中文 测试\r|end |"], ["GBK", "end"]]]
      [:GBK_case, [["GBK", " 中文 测试\r\n\n\nEND \n"], ["GBK", " 中文 测试\r\n\n\nend \n"], ["GBK", " 中文 测试\r\n\n\nEND \n"], ["GBK", " 中文 测试\r\n\n\nend \n"], ["GBK", " 中文 测试\r\n\n\nEND \n"]]]
      [:GBK_casecmp, [0, true, true, true]]
      [:GBK_succ, [["GBK", "ba"], ["GBK", "aaa"], ["GBK", "中文 测试\r\n\n\nene"]]]
      [:GBK_inspect, [["UTF-8", "\" \\x{D6D0}\\x{CEC4} \\x{B2E2}\\x{CAD4}\\r\\n\\n\\nend \\n\""], ["GBK", "\" \\xD6\\xD0\\xCE\\xC4 \\xB2\\xE2\\xCA\\xD4\\r\\n\\n\\nend \\n\""]]]
      [:GBK_codepoints, [32, [32, 54992, 52932, 32, 45794, 51924, 13, 10], 2102, 214, true]]
      [:GBK_index, [10, 10, 14, true, true, true]]
      [:GBK_split, [[["GBK", "中文"], ["GBK", "测试"], ["GBK", "end"]], [["GBK", " 中文 测试\r"], ["GBK", ""], ["GBK", ""], ["GBK", "end "]], [["GBK", " "], ["GBK", "中"], ["GBK", "文"], ["GBK", " 测试\r\n\n\nend \n"]], [["GBK", ""], ["GBK", " "], ["GBK", "中文 测试\r\n\n\nend \n"]], [["GBK", " 中文 测试\r\n\n\nend"], ["GBK", " "], ["GBK", "\n"]]]]
      [:GBK_insert, [["GBK", " 中<>文 测试\r\n\n\nend \n"], ["GBK", "> 中文 测试\r\n\n\nend \n"], ["GBK", " 中文 测试\r\n\n\nend \n!"], true]]
      [:GBK_each_grapheme, [["GBK", " "], ["GBK", "中"], ["GBK", "文"], ["GBK", " "]]]
      [:GBK_scrub, [["GBK", " 中文 测试\r\n\n\nend \n"], 20]]
      [:GBK_unicode_normalize, Encoding::CompatibilityError, "Unicode Normalization not appropriate for GBK"]
      [:GBK_encode, [23, 30]]
      [:"EUC-KR_length", [15, 19, 15, [["EUC-KR", " "], ["EUC-KR", "한"], ["EUC-KR", "국"]], true, false]]
      [:"EUC-KR_reverse", [["EUC-KR", "\n dne\n\n\n\r계세 국한 "], ["EUC-KR", "국 세"], ["EUC-KR", "nd \n"], ["EUC-KR", "한"], false]]
      [:"EUC-KR_justify", [["EUC-KR", "****한국 세계\r\n\n\nend****"], ["EUC-KR", "한국 세계\r\n\n\nend      "], ["EUC-KR", "-=-=-=한국 세계\r\n\n\nend"]]]
      [:"EUC-KR_strip", [["EUC-KR", "한국 세계\r\n\n\nend"], ["EUC-KR", "한국 세계\r\n\n\nend \n"], ["EUC-KR", " 한국 세계\r\n\n\nend"], ["EUC-KR", " 한국 세계\r\n\n\nend "], ["EUC-KR", " 한국 세계\r\n\n\nend "], ["EUC-KR", " 한국 세계\r\n\n\nend "], ["EUC-KR", " 한국 세계\r\n\n\nen"]]]
      [:"EUC-KR_lines", [[["EUC-KR", " 한국 세계\r\n"], ["EUC-KR", "\n"], ["EUC-KR", "\n"], ["EUC-KR", "end \n"]], [["EUC-KR", " 한국 세계"], ["EUC-KR", ""], ["EUC-KR", ""], ["EUC-KR", "end "]], [["EUC-KR", " 한국 세계\r\n\n"], ["EUC-KR", "end \n"]], [["EUC-KR", " 한국 세계"], ["EUC-KR", "end \n"]], [["EUC-KR", " 한국 세계\r\n\n\ne"], ["EUC-KR", "nd \n"]]]]
      [:"EUC-KR_lines_default", [4, [["EUC-KR", " 한국 세계\r\n"], ["EUC-KR", "\n"], ["EUC-KR", "\n"], ["EUC-KR", "end \n"]]]]
      [:"EUC-KR_count", [1, 3, ["EUC-KR", "한국세계\r\n\n\nend\n"], ["EUC-KR", " 한국 세계\r\nend \n"], ["EUC-KR", " 한국 세계\r\nend \n"]]]
      [:"EUC-KR_tr", [["EUC-KR", " 한국 세계\r\n\n\nfoe \n"], ["EUC-KR", " 한국 세계\r|end |"], ["EUC-KR", "end"]]]
      [:"EUC-KR_case", [["EUC-KR", " 한국 세계\r\n\n\nEND \n"], ["EUC-KR", " 한국 세계\r\n\n\nend \n"], ["EUC-KR", " 한국 세계\r\n\n\nEND \n"], ["EUC-KR", " 한국 세계\r\n\n\nend \n"], ["EUC-KR", " 한국 세계\r\n\n\nEND \n"]]]
      [:"EUC-KR_casecmp", [0, true, true, true]]
      [:"EUC-KR_succ", [["EUC-KR", "ba"], ["EUC-KR", "aaa"], ["EUC-KR", "한국 세계\r\n\n\nene"]]]
      [:"EUC-KR_inspect", [["UTF-8", "\" \\x{C7D1}\\x{B1B9} \\x{BCBC}\\x{B0E8}\\r\\n\\n\\nend \\n\""], ["EUC-KR", "\" \\xC7\\xD1\\xB1\\xB9 \\xBC\\xBC\\xB0\\xE8\\r\\n\\n\\nend \\n\""]]]
      [:"EUC-KR_codepoints", [32, [32, 51153, 45497, 32, 48316, 45288, 13, 10], 2014, 199, true]]
      [:"EUC-KR_index", [10, 10, 14, true, true, true]]
      [:"EUC-KR_split", [[["EUC-KR", "한국"], ["EUC-KR", "세계"], ["EUC-KR", "end"]], [["EUC-KR", " 한국 세계\r"], ["EUC-KR", ""], ["EUC-KR", ""], ["EUC-KR", "end "]], [["EUC-KR", " "], ["EUC-KR", "한"], ["EUC-KR", "국"], ["EUC-KR", " 세계\r\n\n\nend \n"]], [["EUC-KR", ""], ["EUC-KR", " "], ["EUC-KR", "한국 세계\r\n\n\nend \n"]], [["EUC-KR", " 한국 세계\r\n\n\nend"], ["EUC-KR", " "], ["EUC-KR", "\n"]]]]
      [:"EUC-KR_insert", [["EUC-KR", " 한<>국 세계\r\n\n\nend \n"], ["EUC-KR", "> 한국 세계\r\n\n\nend \n"], ["EUC-KR", " 한국 세계\r\n\n\nend \n!"], true]]
      [:"EUC-KR_each_grapheme", [["EUC-KR", " "], ["EUC-KR", "한"], ["EUC-KR", "국"], ["EUC-KR", " "]]]
      [:"EUC-KR_scrub", [["EUC-KR", " 한국 세계\r\n\n\nend \n"], 20]]
      [:"EUC-KR_unicode_normalize", Encoding::CompatibilityError, "Unicode Normalization not appropriate for EUC-KR"]
      [:"EUC-KR_encode", [23, 30]]
      [:"ISO-8859-7_length", [17, 17, 17, [["ISO-8859-7", " "], ["ISO-8859-7", "Κ"], ["ISO-8859-7", "α"]], true, false]]
      [:"ISO-8859-7_reverse", [["ISO-8859-7", "\n dne\n\n\n\rΒΑ ηλαΚ "], ["ISO-8859-7", "αλη"], ["ISO-8859-7", "nd \n"], ["ISO-8859-7", "Κ"], true]]
      [:"ISO-8859-7_justify", [["ISO-8859-7", "***Καλη ΑΒ\r\n\n\nend***"], ["ISO-8859-7", "Καλη ΑΒ\r\n\n\nend    "], ["ISO-8859-7", "-=-=Καλη ΑΒ\r\n\n\nend"]]]
      [:"ISO-8859-7_strip", [["ISO-8859-7", "Καλη ΑΒ\r\n\n\nend"], ["ISO-8859-7", "Καλη ΑΒ\r\n\n\nend \n"], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend"], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend "], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend "], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend "], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nen"]]]
      [:"ISO-8859-7_lines", [[["ISO-8859-7", " Καλη ΑΒ\r\n"], ["ISO-8859-7", "\n"], ["ISO-8859-7", "\n"], ["ISO-8859-7", "end \n"]], [["ISO-8859-7", " Καλη ΑΒ"], ["ISO-8859-7", ""], ["ISO-8859-7", ""], ["ISO-8859-7", "end "]], [["ISO-8859-7", " Καλη ΑΒ\r\n\n"], ["ISO-8859-7", "end \n"]], [["ISO-8859-7", " Καλη ΑΒ"], ["ISO-8859-7", "end \n"]], [["ISO-8859-7", " Καλη ΑΒ\r\n\n\ne"], ["ISO-8859-7", "nd \n"]]]]
      [:"ISO-8859-7_lines_default", [4, [["ISO-8859-7", " Καλη ΑΒ\r\n"], ["ISO-8859-7", "\n"], ["ISO-8859-7", "\n"], ["ISO-8859-7", "end \n"]]]]
      [:"ISO-8859-7_count", [1, 3, ["ISO-8859-7", "ΚαληΑΒ\r\n\n\nend\n"], ["ISO-8859-7", " Καλη ΑΒ\r\nend \n"], ["ISO-8859-7", " Καλη ΑΒ\r\nend \n"]]]
      [:"ISO-8859-7_tr", [["ISO-8859-7", " Καλη ΑΒ\r\n\n\nfoe \n"], ["ISO-8859-7", " Καλη ΑΒ\r|end |"], ["ISO-8859-7", "end"]]]
      [:"ISO-8859-7_case", [["ISO-8859-7", " ΚΑΛΗ ΑΒ\r\n\n\nEND \n"], ["ISO-8859-7", " καλη αβ\r\n\n\nend \n"], ["ISO-8859-7", " κΑΛΗ αβ\r\n\n\nEND \n"], ["ISO-8859-7", " καλη αβ\r\n\n\nend \n"], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nEND \n"]]]
      [:"ISO-8859-7_casecmp", [1, true, true, true]]
      [:"ISO-8859-7_succ", [["ISO-8859-7", "ba"], ["ISO-8859-7", "aaa"], ["ISO-8859-7", "Καλη ΑΒ\r\n\n\nene"]]]
      [:"ISO-8859-7_inspect", [["UTF-8", "\" \\xCA\\xE1\\xEB\\xE7 \\xC1\\xC2\\r\\n\\n\\nend \\n\""], ["ISO-8859-7", "\" \\xCA\\xE1\\xEB\\xE7 \\xC1\\xC2\\r\\n\\n\\nend \\n\""]]]
      [:"ISO-8859-7_codepoints", [32, [32, 202, 225, 235, 231, 32, 193, 194], 1740, 202, true]]
      [:"ISO-8859-7_index", [12, 12, 12, true, true, true]]
      [:"ISO-8859-7_split", [[["ISO-8859-7", "Καλη"], ["ISO-8859-7", "ΑΒ"], ["ISO-8859-7", "end"]], [["ISO-8859-7", " Καλη ΑΒ\r"], ["ISO-8859-7", ""], ["ISO-8859-7", ""], ["ISO-8859-7", "end "]], [["ISO-8859-7", " "], ["ISO-8859-7", "Κ"], ["ISO-8859-7", "α"], ["ISO-8859-7", "λη ΑΒ\r\n\n\nend \n"]], [["ISO-8859-7", ""], ["ISO-8859-7", " "], ["ISO-8859-7", "Καλη ΑΒ\r\n\n\nend \n"]], [["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend"], ["ISO-8859-7", " "], ["ISO-8859-7", "\n"]]]]
      [:"ISO-8859-7_insert", [["ISO-8859-7", " Κ<>αλη ΑΒ\r\n\n\nend \n"], ["ISO-8859-7", "> Καλη ΑΒ\r\n\n\nend \n"], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend \n!"], true]]
      [:"ISO-8859-7_each_grapheme", [["ISO-8859-7", " "], ["ISO-8859-7", "Κ"], ["ISO-8859-7", "α"], ["ISO-8859-7", "λ"]]]
      [:"ISO-8859-7_scrub", [["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend \n"], 18]]
      [:"ISO-8859-7_unicode_normalize", Encoding::CompatibilityError, "Unicode Normalization not appropriate for ISO-8859-7"]
      [:"ISO-8859-7_encode", [23, 34]]
      [:"UTF-16LE_tail_2020", ["UTF-8", "a†"]]
      [:"UTF-16LE_tail_2020_replaced", [["UTF-8", "a†"], true, 2, 4, [2, 2]]]
      [:"UTF-16LE_tail_20", [["ASCII-8BIT", "incomplete \" \" on UTF-16LE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16LE_tail_20_replaced", [["UTF-8", "a�"], false, 2, 4, [2, 1]]]
      [:"UTF-16LE_tail_0020", ["UTF-8", "a "]]
      [:"UTF-16LE_tail_0020_replaced", [["UTF-8", "a "], true, 2, 4, [2, 2]]]
      [:"UTF-16LE_tail_000020", [["ASCII-8BIT", "incomplete \" \" on UTF-16LE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16LE_tail_000020_replaced", [["UTF-8", "a\u0000�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16LE_tail_00112020", ["UTF-8", "aᄀ†"]]
      [:"UTF-16LE_tail_00112020_replaced", [["UTF-8", "aᄀ†"], true, 3, 6, [2, 2, 2]]]
      [:"UTF-16LE_tail_202020", [["ASCII-8BIT", "incomplete \" \" on UTF-16LE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16LE_tail_202020_replaced", [["UTF-8", "a†�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16LE_tail_d8000000", ["UTF-8", "aØ\u0000"]]
      [:"UTF-16LE_tail_d8000000_replaced", [["UTF-8", "aØ\u0000"], true, 3, 6, [2, 2, 2]]]
      [:"UTF-16LE_tail_00d80000", [["ASCII-8BIT", "\"\\x00\\xD8\" followed by \"\\x00\\x00\" on UTF-16LE"], ["ASCII-8BIT", "\x00\xD8"], ["ASCII-8BIT", "\x00\x00"], false]]
      [:"UTF-16LE_tail_00d80000_replaced", [["UTF-8", "a�\u0000"], false, 3, 6, [2, 2, 2]]]
      [:"UTF-16LE_tail_dc0061", [["ASCII-8BIT", "incomplete \"a\" on UTF-16LE"], ["ASCII-8BIT", "a"], nil, true]]
      [:"UTF-16LE_tail_dc0061_replaced", [["UTF-8", "aÜ�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16LE_tail_00dc61", [["ASCII-8BIT", "\"\\x00\\xDC\" on UTF-16LE"], ["ASCII-8BIT", "\x00\xDC"], nil, false]]
      [:"UTF-16LE_tail_00dc61_replaced", [["UTF-8", "a��"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16LE_tail_00d800dc", ["UTF-8", "a𐀀"]]
      [:"UTF-16LE_tail_00d800dc_replaced", [["UTF-8", "a𐀀"], true, 2, 6, [2, 4]]]
      [:"UTF-16BE_tail_2020", ["UTF-8", "a†"]]
      [:"UTF-16BE_tail_2020_replaced", [["UTF-8", "a†"], true, 2, 4, [2, 2]]]
      [:"UTF-16BE_tail_20", [["ASCII-8BIT", "incomplete \" \" on UTF-16BE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16BE_tail_20_replaced", [["UTF-8", "a�"], false, 2, 4, [2, 1]]]
      [:"UTF-16BE_tail_0020", ["UTF-8", "a "]]
      [:"UTF-16BE_tail_0020_replaced", [["UTF-8", "a "], true, 2, 4, [2, 2]]]
      [:"UTF-16BE_tail_000020", [["ASCII-8BIT", "incomplete \" \" on UTF-16BE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16BE_tail_000020_replaced", [["UTF-8", "a\u0000�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16BE_tail_00112020", ["UTF-8", "a\u0011†"]]
      [:"UTF-16BE_tail_00112020_replaced", [["UTF-8", "a\u0011†"], true, 3, 6, [2, 2, 2]]]
      [:"UTF-16BE_tail_202020", [["ASCII-8BIT", "incomplete \" \" on UTF-16BE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16BE_tail_202020_replaced", [["UTF-8", "a†�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16BE_tail_d8000000", [["ASCII-8BIT", "\"\\xD8\\x00\" followed by \"\\x00\" on UTF-16BE"], ["ASCII-8BIT", "\xD8\x00"], ["ASCII-8BIT", "\x00"], false]]
      [:"UTF-16BE_tail_d8000000_replaced", [["UTF-8", "a�\u0000"], false, 3, 6, [2, 2, 2]]]
      [:"UTF-16BE_tail_00d80000", ["UTF-8", "aØ\u0000"]]
      [:"UTF-16BE_tail_00d80000_replaced", [["UTF-8", "aØ\u0000"], true, 3, 6, [2, 2, 2]]]
      [:"UTF-16BE_tail_dc0061", [["ASCII-8BIT", "\"\\xDC\\x00\" on UTF-16BE"], ["ASCII-8BIT", "\xDC\x00"], nil, false]]
      [:"UTF-16BE_tail_dc0061_replaced", [["UTF-8", "a��"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16BE_tail_00dc61", [["ASCII-8BIT", "incomplete \"a\" on UTF-16BE"], ["ASCII-8BIT", "a"], nil, true]]
      [:"UTF-16BE_tail_00dc61_replaced", [["UTF-8", "aÜ�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16BE_tail_00d800dc", ["UTF-8", "aØÜ"]]
      [:"UTF-16BE_tail_00d800dc_replaced", [["UTF-8", "aØÜ"], true, 3, 6, [2, 2, 2]]]
      [:"UTF-32LE_tail_2020", [["ASCII-8BIT", "incomplete \"  \" on UTF-32LE"], ["ASCII-8BIT", "  "], nil, true]]
      [:"UTF-32LE_tail_2020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 2]]]
      [:"UTF-32LE_tail_20", [["ASCII-8BIT", "incomplete \" \" on UTF-32LE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-32LE_tail_20_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 1]]]
      [:"UTF-32LE_tail_0020", [["ASCII-8BIT", "incomplete \"\\x00 \" on UTF-32LE"], ["ASCII-8BIT", "\x00 "], nil, true]]
      [:"UTF-32LE_tail_0020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 2]]]
      [:"UTF-32LE_tail_000020", [["ASCII-8BIT", "\"\\x00\\x00 \" on UTF-32LE"], ["ASCII-8BIT", "\x00\x00 "], nil, false]]
      [:"UTF-32LE_tail_000020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32LE_tail_00112020", [["ASCII-8BIT", "\"\\x00\\x11  \" on UTF-32LE"], ["ASCII-8BIT", "\x00\x11  "], nil, false]]
      [:"UTF-32LE_tail_00112020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32LE_tail_202020", [["ASCII-8BIT", "\"   \" on UTF-32LE"], ["ASCII-8BIT", "   "], nil, false]]
      [:"UTF-32LE_tail_202020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32LE_tail_d8000000", ["UTF-8", "aØ"]]
      [:"UTF-32LE_tail_d8000000_replaced", [["UTF-8", "aØ"], true, 2, 8, [4, 4]]]
      [:"UTF-32LE_tail_00d80000", [["ASCII-8BIT", "\"\\x00\\xD8\\x00\\x00\" on UTF-32LE"], ["ASCII-8BIT", "\x00\xD8\x00\x00"], nil, false]]
      [:"UTF-32LE_tail_00d80000_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32LE_tail_dc0061", [["ASCII-8BIT", "\"\\xDC\\x00a\" on UTF-32LE"], ["ASCII-8BIT", "\xDC\x00a"], nil, false]]
      [:"UTF-32LE_tail_dc0061_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32LE_tail_00dc61", [["ASCII-8BIT", "\"\\x00\\xDCa\" on UTF-32LE"], ["ASCII-8BIT", "\x00\xDCa"], nil, false]]
      [:"UTF-32LE_tail_00dc61_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32LE_tail_00d800dc", [["ASCII-8BIT", "\"\\x00\\xD8\\x00\\xDC\" on UTF-32LE"], ["ASCII-8BIT", "\x00\xD8\x00\xDC"], nil, false]]
      [:"UTF-32LE_tail_00d800dc_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32BE_tail_2020", [["ASCII-8BIT", "\"  \" on UTF-32BE"], ["ASCII-8BIT", "  "], nil, false]]
      [:"UTF-32BE_tail_2020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 2]]]
      [:"UTF-32BE_tail_20", [["ASCII-8BIT", "\" \" on UTF-32BE"], ["ASCII-8BIT", " "], nil, false]]
      [:"UTF-32BE_tail_20_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 1]]]
      [:"UTF-32BE_tail_0020", [["ASCII-8BIT", "\"\\x00 \" on UTF-32BE"], ["ASCII-8BIT", "\x00 "], nil, false]]
      [:"UTF-32BE_tail_0020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 2]]]
      [:"UTF-32BE_tail_000020", [["ASCII-8BIT", "incomplete \"\\x00\\x00 \" on UTF-32BE"], ["ASCII-8BIT", "\x00\x00 "], nil, true]]
      [:"UTF-32BE_tail_000020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32BE_tail_00112020", [["ASCII-8BIT", "\"\\x00\\x11  \" on UTF-32BE"], ["ASCII-8BIT", "\x00\x11  "], nil, false]]
      [:"UTF-32BE_tail_00112020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32BE_tail_202020", [["ASCII-8BIT", "\"   \" on UTF-32BE"], ["ASCII-8BIT", "   "], nil, false]]
      [:"UTF-32BE_tail_202020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32BE_tail_d8000000", [["ASCII-8BIT", "\"\\xD8\\x00\\x00\\x00\" on UTF-32BE"], ["ASCII-8BIT", "\xD8\x00\x00\x00"], nil, false]]
      [:"UTF-32BE_tail_d8000000_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32BE_tail_00d80000", [["ASCII-8BIT", "\"\\x00\\xD8\\x00\\x00\" on UTF-32BE"], ["ASCII-8BIT", "\x00\xD8\x00\x00"], nil, false]]
      [:"UTF-32BE_tail_00d80000_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32BE_tail_dc0061", [["ASCII-8BIT", "\"\\xDC\\x00a\" on UTF-32BE"], ["ASCII-8BIT", "\xDC\x00a"], nil, false]]
      [:"UTF-32BE_tail_dc0061_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32BE_tail_00dc61", [["ASCII-8BIT", "\"\\x00\\xDCa\" on UTF-32BE"], ["ASCII-8BIT", "\x00\xDCa"], nil, false]]
      [:"UTF-32BE_tail_00dc61_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32BE_tail_00d800dc", [["ASCII-8BIT", "\"\\x00\\xD8\\x00\\xDC\" on UTF-32BE"], ["ASCII-8BIT", "\x00\xD8\x00\xDC"], nil, false]]
      [:"UTF-32BE_tail_00d800dc_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
    OUT
  end

  it "String.new builds a fresh mutable buffer, copying a source's contents and encoding" do
    result = ze0(<<~'RUBY')
      # `String.new` builds a fresh, mutable String. With no argument it is an empty
      # ASCII-8BIT buffer; given a source string it copies that string's contents and
      # encoding, and an `encoding:` keyword overrides the result's encoding.
      p String.new                              # ""
      p String.new.encoding.name                # "ASCII-8BIT"

      p String.new("hello")                     # "hello"
      p String.new("hello").encoding.name       # "UTF-8"

      forced = String.new("bytes", encoding: "ASCII-8BIT")
      p forced.encoding.name                    # "ASCII-8BIT"

      # The copy is independent of its source.
      src = "abc"
      copy = String.new(src)
      copy << "d"
      p src                                     # "abc"
      p copy                                    # "abcd"
    RUBY

    _(result).must_answer <<~'OUT'
      ""
      "ASCII-8BIT"
      "hello"
      "UTF-8"
      "ASCII-8BIT"
      "abc"
      "abcd"
    OUT
  end

  it "capacity: and encoding: are hints, so the positional content survives them" do
    result = ze0(<<~'RUBY')
      # The capacity: and encoding keyword arguments to String.new are hints that do
      # not change the value -- the content is the leading positional argument. Spinel
      # previously dropped the content whenever a keyword argument was present,
      # returning "".
      def with_cap; String.new("x", capacity: 100); end
      p with_cap                     # "x"

      def only_cap; String.new(capacity: 50); end
      p only_cap                     # ""

      def plain; String.new("y"); end
      p plain                        # "y"

      def empty; String.new; end
      p empty                        # ""

      # The result is a mutable copy (a literal passed as content is not aliased).
      def mutable
        s = String.new("ab", capacity: 8)
        s << "c"
        s
      end
      p mutable                      # "abc"

      # Content from a variable, with a capacity hint.
      def from_var(seed); String.new(seed, capacity: 32); end
      p from_var("hello")            # "hello"
    RUBY

    _(result).must_answer <<~'OUT'
      "x"
      ""
      "y"
      ""
      "abc"
      "hello"
    OUT
  end

  it "a chained append evaluates each link once and lands every one on the base" do
    result = ze0(<<~'RUBY')
      # chained string appends (`s << a << b`) evaluate each link exactly once and
      # every append lands on the base. The tail form used to re-run the inner
      # links when emitting the return value (doubling the appended text, and
      # writing the doubled string back through a byref param); the value form
      # wrote back only the innermost link, so the base missed the later appends.

      # tail position, through a mutated parameter (the byref shape)
      def emit(buf, label)
        buf << "[" << label << "]"
      end

      s = +""
      emit(s, "ok")
      p s
      r = emit(s, "go")
      p r
      p s

      # value position: assignment keeps base and result in step
      t = +"x"
      u = (t << "a" << "b")
      p t
      p u

      # parenthesized links and a longer chain
      v = +""
      (v << "1") << "2" << "3"
      p v

      # int argument appends its codepoint character
      w = +"y"
      w << "-" << 33
      p w

      # ivar base
      class Sink
        def initialize
          @buf = +"<"
        end

        def push(a, b)
          @buf << a << b
        end
      end

      k = Sink.new
      p k.push("m", ">")

      # repeated tail chains accumulate (the serializer shape)
      def line(out, op, arg)
        out << op << " " << arg << "\n"
      end

      prog = +""
      line(prog, "LOAD", "a")
      line(prog, "JUMP", "top")
      print prog
    RUBY

    _(result).must_answer <<~'OUT'
      "[ok]"
      "[ok][go]"
      "[ok][go]"
      "xab"
      "xab"
      "123"
      "y-!"
      "<m>"
      LOAD a
      JUMP top
    OUT
  end

  it "try_convert asks only to_str, answers nil for anything else, and refuses a lying one" do
    result = ze0(<<~'RUBY')
      # `String.try_convert(obj)` -- the `to_str` check-conversion, exposed. Unlike
      # `String(obj)` it never falls back to `to_s` and never raises for an object
      # that simply isn't string-like; a lying `to_str` is the one error case.

      # Already a String: returned as-is (the same object, not a copy).
      s = "hello"
      p String.try_convert(s)
      p String.try_convert(s).equal?(s)

      # A subclass is already a String too -- and `try_convert` hands back the very
      # object, so it comes out still wearing its own class.
      class Name < String; end
      sub = Name.new("ada")
      p String.try_convert(sub).class
      p String.try_convert(sub).equal?(sub)

      # Defines `to_str`: converted through it.
      class Path
        def to_str = "/tmp/x"
      end
      p String.try_convert(Path.new)

      # ...and a `to_str` that answers a String SUBCLASS satisfies the check without
      # being flattened to a plain String.
      class Quacker
        def to_str = Name.new("quack")
      end
      p String.try_convert(Quacker.new).class

      # `to_s` alone is NOT the protocol -- only `to_str` is.
      class Labelled
        def to_s = "label"
      end
      p String.try_convert(Labelled.new)

      # No conversion at all: nil, never an exception.
      p String.try_convert(42)
      p String.try_convert(nil)
      p String.try_convert([1, 2])
      p String.try_convert(:sym)

      # A `to_str` that answers a non-String is the one raising case.
      class Liar
        def to_str = 42
      end
      begin
        String.try_convert(Liar.new)
      rescue TypeError => e
        puts e.message
      end

      # `to_str` answering nil reads as "no conversion", not as a lie.
      class Absent
        def to_str = nil
      end
      p String.try_convert(Absent.new)

      # The encoding of the converted string survives.
      p String.try_convert("caf\xC3\xA9".b).encoding
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      true
      Name
      true
      "/tmp/x"
      Name
      nil
      nil
      nil
      nil
      nil
      can't convert Liar to String (Liar#to_str gives Integer)
      nil
      #<Encoding:BINARY (ASCII-8BIT)>
    OUT
  end

  it "length, bytesize and slicing read the header's byte count, not up to the first NUL" do
    result = ze0(<<~'RUBY')
      # Spinel-allocated strings encode their byte length in the heap
      # header (sp_str_hdr.len), but several runtime helpers and one
      # codegen `bytesize` emit walked the buffer via NUL-terminated
      # strlen/`while(*p)` semantics. A `0.chr` value carrying a header
      # length of 1 with byte content `\x00` reported `length=0`,
      # `bytesize=0`, and sliced wrong past any embedded NUL.
      #
      # Fix: `sp_str_length` and `sp_utf8_byte_offset` consume the
      # header-tracked byte length instead of terminating at the first
      # NUL byte. `bytesize` codegen now emits
      # `sp_str_byte_len(...)` instead of `(mrb_int)strlen(...)`.
      # Issue #593.

      # Single-byte NUL.
      puts 0.chr.length              # 1
      puts 0.chr.bytesize            # 1
      puts 0.chr.ord                 # 0

      # Concat preserves NULs in the middle.
      b = 0.chr + 0xc8.chr
      puts b.length                  # 2
      puts b.bytesize                # 2
      puts b[0].ord                  # 0
      puts b[1].ord                  # 200 (0xc8)

      # Mixed ASCII + NUL + ASCII -- indexing past the NUL.
      c = "x" + 0.chr + "y"
      puts c.length                  # 3
      puts c[0].ord                  # 120 ('x')
      puts c[1].ord                  # 0
      puts c[2].ord                  # 121 ('y')

      # Progressive build with NUL in the middle.
      d = ""
      d = d + 0x81.chr
      d = d + 0x7e.chr
      d = d + 0x00.chr
      d = d + 0xc8.chr
      puts d.length                  # 4
      puts d[2].ord                  # 0
      puts d[3].ord                  # 200

      # Substring across NUL.
      e = d[0, 4]
      puts e.length                  # 4
      puts e[3].ord                  # 200
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      0
      2
      2
      0
      200
      3
      120
      0
      121
      4
      0
      200
      4
      200
    OUT
  end
end
