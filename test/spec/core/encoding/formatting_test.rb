# frozen_string_literal: true

require "spec_helper"

describe "Encoding: formatting and inspection" do
  it "broken and binary strings inspect with hex escapes" do
    result = ze0(<<~'RUBY')
      # A byte that isn't a character in the string's encoding renders as
      # \xNN, and the cross-encoding equality rule keeps ASCII-only strings
      # equal across encodings. Cross-checked against ruby 4.0.6.

      p "abc".b == "abc"
      p "abc".b.encoding
      s = "\xff\x80".b
      p s.valid_encoding?
      puts s.inspect
      puts "caf\xe9".force_encoding("ISO-8859-1").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      true
      #<Encoding:BINARY (ASCII-8BIT)>
      true
      "\xFF\x80"
      "caf\xE9"
    OUT
  end

  it "carrier character reads as more than one code point" do
    result = ze0(<<~'RUBY')
      # The carriers' own encodings hold characters that stand for more than
      # one code point: a flag is two regional letters, and a keycap is a digit
      # with a mark after it. One character in, two out, so a table of code
      # points is not enough to read them.
      [["SJIS-KDDI", "\xF3\x48"], ["SJIS-SoftBank", "\xF2\xD9"], ["SJIS-DoCoMo", "\xF9\x85"]].each do |name, bytes|
        text = bytes.dup.force_encoding(name)
        up = text.encode("UTF-8")
        p [name, text.length, up.length, up.codepoints.map { |point| format("U+%04X", point) }]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      ["SJIS-KDDI", 1, 2, ["U+1F1EA", "U+1F1F8"]]
      ["SJIS-SoftBank", 1, 2, ["U+0023", "U+20E3"]]
      ["SJIS-DoCoMo", 1, 2, ["U+0023", "U+20E3"]]
    OUT
  end

  it "compatible takes every object that carries an encoding" do
    result = ze0(<<~'RUBY')
      # Encoding.compatible? takes a String, a Symbol, a Regexp, an IO or an
      # Encoding, as enc_compatible_p does, and anything else answers nil.
      p Encoding.default_external
      p Encoding.compatible?(Encoding.default_external, "false")
      p Encoding.compatible?(Encoding::UTF_8, false.inspect)
      p false.inspect.encoding, 6.inspect.encoding, [1].inspect.encoding, "é".inspect.encoding
      p Encoding.compatible?(Encoding::UTF_8, "x".encode("US-ASCII"))
      p Encoding.compatible?(Encoding::UTF_8, "é".b)
      p Encoding.compatible?(Encoding::US_ASCII, "é")
      p Encoding.compatible?(Encoding::UTF_8, Encoding::US_ASCII)
      p Encoding.compatible?("a", Encoding::UTF_8)
      p Encoding.compatible?(Encoding::UTF_16LE, "a")
      p Encoding.compatible?(:sym, "é"), Encoding.compatible?(/a/, "é".encode("ISO-8859-1")), Encoding.compatible?(STDOUT, "x"), Encoding.compatible?(1, "x")
      p Encoding.compatible?("é", "ü".encode("ISO-8859-1")), Encoding.compatible?("a".b, "é"), Encoding.compatible?("é".b, "a"), Encoding.compatible?("", "é".b)
      p Encoding.compatible?(Encoding::UTF_8, Encoding::ISO_8859_1), Encoding.compatible?(Encoding::UTF_16LE, Encoding::UTF_8)


    RUBY

    _(result).must_answer <<~'OUT'
      #<Encoding:UTF-8>
      #<Encoding:UTF-8>
      #<Encoding:US-ASCII>
      #<Encoding:US-ASCII>
      #<Encoding:US-ASCII>
      #<Encoding:US-ASCII>
      #<Encoding:UTF-8>
      #<Encoding:US-ASCII>
      nil
      #<Encoding:UTF-8>
      #<Encoding:UTF-8>
      #<Encoding:UTF-8>
      nil
      #<Encoding:UTF-8>
      #<Encoding:ISO-8859-1>
      nil
      nil
      nil
      #<Encoding:UTF-8>
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:BINARY (ASCII-8BIT)>
      nil
      nil
    OUT
  end

  it "encode decorators" do
    result = ze0(<<~'RUBY')
      # `String#encode`'s decorators, and where they land in a NON-ascii target.
      # The replacement text and the XML markup are both rendered INTO the target,
      # so a UTF-16 result gets whole code units rather than stray ASCII bytes --
      # and `xml: :attr` writes a whole attribute, quotes included.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("xml attr") { %(a"b<c).encode("EUC-JP", xml: :attr) }
      show("xml text") { %(a"b<c).encode("EUC-JP", xml: :text) }
      show("xml attr undef") { "あ".encode("US-ASCII", xml: :attr) }
      show("universal") { "a\r\nb\rc".encode("EUC-JP", universal_newline: true) }
      show("crlf") { "a\nb".encode("EUC-JP", crlf_newline: true) }
      show("cr") { "a\nb".encode("EUC-JP", cr_newline: true) }
      show("utf16 invalid replace") do
        "a\xffb".dup.force_encoding("UTF-8").encode("UTF-16BE", invalid: :replace).bytes
      end
      show("utf32 invalid replace") do
        "a\xffb".dup.force_encoding("UTF-8").encode("UTF-32BE", invalid: :replace).bytes
      end
      show("utf16 xml attr") { %(a"b).encode("UTF-16BE", xml: :attr).bytes }
      show("utf16 undef replace") { "あ".encode("US-ASCII", undef: :replace) }
      show("replace text into utf16") do
        "a\xffb".dup.force_encoding("UTF-8").encode("UTF-16BE", invalid: :replace, replace: "!").bytes
      end
    RUBY

    _(result).must_answer <<~'OUT'
      xml attr: "\"a&quot;b&lt;c\""
      xml text: "a\"b&lt;c"
      xml attr undef: "\"&#x3042;\""
      universal: "a\nb\nc"
      crlf: "a\r\nb"
      cr: "a\rb"
      utf16 invalid replace: [0, 97, 255, 253, 0, 98]
      utf32 invalid replace: [0, 0, 0, 97, 0, 0, 255, 253, 0, 0, 0, 98]
      utf16 xml attr: [0, 34, 0, 97, 0, 38, 0, 113, 0, 117, 0, 111, 0, 116, 0, 59, 0, 98, 0, 34]
      utf16 undef replace: "?"
      replace text into utf16: [0, 97, 0, 33, 0, 98]
    OUT
  end

  it "encode to the same encoding" do
    result = ze0(<<~'RUBY')
      # `str.encode(enc)` where str is ALREADY in enc is a no-op in ruby -- no byte
      # validation happens, invalid bytes ride through untouched. zeo runs the
      # transcoder anyway and raises InvalidByteSequenceError on the bad bytes.
      s = "\xFF\xFE".dup.force_encoding("UTF-8")
      r = s.encode("UTF-8", "UTF-8")
      puts r.bytes.inspect
      puts r.encoding

      t = "ok".encode("UTF-8")
      puts t
    RUBY

    _(result).must_answer <<~'OUT'
      [255, 254]
      UTF-8
      ok
    OUT
  end

  it "encoding convert" do
    result = ze0(<<~'RUBY')
      # The encoding tables are linked: transcoding, byte inspection and the
      # encoding registry all answer in the binary.
      s = "héllo wörld"
      puts s.encoding
      latin = s.encode("ISO-8859-1")
      puts latin.bytesize
      puts latin.encode("UTF-8")
      p "\xC3\xA9".dup.force_encoding("UTF-8").valid_encoding?
      p "\xFF".dup.force_encoding("UTF-8").valid_encoding?
      puts Encoding::UTF_8.name
    RUBY

    _(result).must_answer <<~'OUT'
      UTF-8
      11
      héllo wörld
      true
      false
      UTF-8
    OUT
  end

  it "encoding converter" do
    result = ze0(<<~'RUBY')
      # The stateful face of the same engine `String#encode` runs on -- one
      # `Encoding::Converter`, fed a piece at a time. Note the wording of this
      # first line: `# Encoding::Converter` would read as a magic comment, since
      # ruby sees `coding:` in it and tries the encoding named `:Converter`.
      #
      # The difference from `String#encode` is only WHERE a conversion can stop, so this
      # exercises every way it can -- a chunk boundary inside a character, a
      # malformed sequence, a character the target cannot hold, and a full
      # destination buffer.

      EC = Encoding::Converter

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("own singleton") { EC.singleton_methods(false).sort }
      show("own instance") { EC.instance_methods(false).sort }
      show("constants") { EC.constants.sort }
      show("INVALID_MASK") { EC::INVALID_MASK }
      show("UNDEF_HEX_CHARREF") { EC::UNDEF_HEX_CHARREF }
      show("PARTIAL_INPUT") { EC::PARTIAL_INPUT }
      show("AFTER_OUTPUT") { EC::AFTER_OUTPUT }
      show("XML_ATTR_QUOTE_DECORATOR") { EC::XML_ATTR_QUOTE_DECORATOR }

      # Construction, and every way it refuses.
      show("new") { EC.new("UTF-8", "EUC-JP") }
      show("new encodings") { EC.new(Encoding::UTF_8, Encoding::EUC_JP) }
      show("new one arg") { EC.new("UTF-8") }
      show("new symbol") { EC.new(:"UTF-8", :"EUC-JP") }
      show("new unknown") { EC.new("nope", "UTF-8") }
      show("new same") { EC.new("UTF-8", "UTF-8") }
      show("new same + decorator") { EC.new("UTF-8", "UTF-8", universal_newline: true) }
      show("new two newlines") { EC.new("UTF-8", "EUC-JP", crlf_newline: true, universal_newline: true) }
      show("new no-conversion") { EC.new("", "") }
      show("new decorator only") { EC.new("", "", universal_newline: true) }

      # What it says about itself.
      show("source_encoding") { EC.new("UTF-8", "EUC-JP").source_encoding }
      show("destination_encoding") { EC.new("UTF-8", "EUC-JP").destination_encoding }
      show("no-conversion source") { EC.new("", "").source_encoding }
      show("inspect") { EC.new("UTF-8", "EUC-JP").inspect }
      show("inspect decorated") { EC.new("UTF-8", "EUC-JP", crlf_newline: true).inspect }
      show("inspect xml attr") { EC.new("UTF-8", "EUC-JP", xml: :attr).inspect }
      show("inspect no-conversion") { EC.new("", "").inspect }
      show("inspect decorator only") { EC.new("", "", crlf_newline: true).inspect }
      show("== same") { EC.new("UTF-8", "EUC-JP") == EC.new("UTF-8", "EUC-JP") }
      show("== different") { EC.new("UTF-8", "EUC-JP") == EC.new("UTF-8", "UTF-16BE") }
      show("== non-converter") { EC.new("UTF-8", "EUC-JP") == 1 }

      # The converter path: one hop where a direct converter exists, a pivot
      # through UTF-8 where it does not, and three hops for the stateful JIS row.
      show("convpath direct") { EC.new("UTF-8", "EUC-JP").convpath }
      show("convpath pivot") { EC.search_convpath("ISO-8859-1", "EUC-JP") }
      show("convpath sjis-euc") { EC.search_convpath("Shift_JIS", "EUC-JP") }
      show("convpath jis") { EC.search_convpath("ISO-2022-JP", "UTF-8") }
      show("convpath long") { EC.search_convpath("Windows-1252", "ISO-2022-JP") }
      show("convpath decorated") { EC.search_convpath("UTF-8", "EUC-JP", universal_newline: true) }
      show("convpath xml") { EC.search_convpath("UTF-8", "EUC-JP", xml: :attr) }
      show("convpath same") { EC.search_convpath("UTF-8", "UTF-8") }
      show("convpath decorator only") { EC.new("", "", crlf_newline: true).convpath }

      show("asciicompat 2022") { EC.asciicompat_encoding("ISO-2022-JP") }
      show("asciicompat utf16") { EC.asciicompat_encoding(Encoding::UTF_16BE) }
      show("asciicompat ibm037") { EC.asciicompat_encoding("IBM037") }
      show("asciicompat cesu8") { EC.asciicompat_encoding("CESU-8") }
      show("asciicompat utf8") { EC.asciicompat_encoding("UTF-8") }
      show("asciicompat utf8-mac") { EC.asciicompat_encoding("UTF8-MAC") }
      show("asciicompat unknown") { EC.asciicompat_encoding("nope") }

      # Converting, one chunk at a time.
      show("convert") { EC.new("UTF-8", "EUC-JP").convert("あい").bytes }
      show("convert encoding") { EC.new("UTF-8", "EUC-JP").convert("a").encoding }
      show("convert split") do
        c = EC.new("UTF-8", "EUC-JP")
        [c.convert("\xE3\x81").bytes, c.convert("\x82").bytes, c.finish.bytes]
      end
      show("convert undef") { EC.new("UTF-8", "US-ASCII").convert("é") }
      show("convert undef replaced") { EC.new("UTF-8", "US-ASCII", undef: :replace).convert("é") }
      show("convert invalid") { EC.new("UTF-8", "EUC-JP").convert("\xFF") }
      show("convert invalid replaced") { EC.new("UTF-8", "EUC-JP", invalid: :replace).convert("\xFF").bytes }
      show("convert after finish") do
        c = EC.new("UTF-8", "EUC-JP")
        c.finish
        c.convert("a")
      end
      show("convert non-string") { EC.new("UTF-8", "EUC-JP").convert(1) }
      show("finish truncated") do
        c = EC.new("UTF-8", "EUC-JP")
        c.convert("a\xE3\x81")
        c.finish
      end
      show("finish truncated replaced") do
        c = EC.new("UTF-8", "EUC-JP", invalid: :replace)
        c.convert("a\xE3\x81")
        c.finish.bytes
      end
      show("finish closes jis") do
        c = EC.new("UTF-8", "ISO-2022-JP")
        [c.convert("あ").bytes, c.finish.bytes]
      end

      # The decorators.
      show("crlf") { EC.new("UTF-8", "EUC-JP", crlf_newline: true).convert("a\nb").bytes }
      show("cr") { EC.new("UTF-8", "EUC-JP", cr_newline: true).convert("a\nb").bytes }
      show("universal") { EC.new("", "", universal_newline: true).convert("a\r\nb") }
      show("universal cr only") { EC.new("", "", universal_newline: true).convert("a\rb") }
      show("universal split") do
        c = EC.new("", "", universal_newline: true)
        [c.convert("a\r"), c.convert("\nb")]
      end
      show("xml text") { EC.new("UTF-8", "EUC-JP", xml: :text).convert("<a&b>").bytes }
      show("xml attr") { EC.new("UTF-8", "EUC-JP", xml: :attr).convert(%(a"b)).bytes }
      show("flags integer") do
        EC.new("UTF-8", "EUC-JP", EC::INVALID_REPLACE | EC::UNDEF_REPLACE).convert("\xFF").bytes
      end
      show("flags universal") { EC.new("", "", EC::UNIVERSAL_NEWLINE_DECORATOR).convert("a\r\nb") }

      # The replacement text.
      show("replacement euc") { EC.new("UTF-8", "EUC-JP").replacement }
      show("replacement euc encoding") { EC.new("UTF-8", "EUC-JP").replacement.encoding }
      show("replacement utf8") { EC.new("EUC-JP", "UTF-8").replacement }
      show("replacement utf16") { EC.new("UTF-8", "UTF-16BE").replacement.bytes }
      show("replacement set") do
        c = EC.new("UTF-8", "US-ASCII", undef: :replace)
        c.replacement = "!"
        [c.replacement, c.convert("é")]
      end
      show("replacement unrepresentable") do
        c = EC.new("UTF-8", "US-ASCII")
        c.replacement = "あ"
      end

      # The low-level form names how it stopped instead of raising.
      show("primitive whole") do
        c = EC.new("UTF-8", "EUC-JP")
        src = +"あいう"
        dst = +""
        [c.primitive_convert(src, dst), src.bytes, dst.bytes]
      end
      show("primitive truncated") do
        c = EC.new("UTF-8", "EUC-JP")
        src = +"a\xE3\x81"
        dst = +""
        [c.primitive_convert(src, dst), src.bytes, dst.bytes, c.primitive_errinfo]
      end
      show("primitive partial input") do
        c = EC.new("UTF-8", "EUC-JP")
        src = +"a\xE3\x81"
        dst = +""
        r = c.primitive_convert(src, dst, nil, nil, EC::PARTIAL_INPUT)
        [r, src.bytes, dst.bytes, c.primitive_errinfo]
      end
      show("primitive invalid") do
        c = EC.new("UTF-8", "EUC-JP")
        src = +"a\xFFb"
        dst = +""
        [c.primitive_convert(src, dst), src.bytes, dst.bytes, c.primitive_errinfo, c.last_error.class]
      end
      show("primitive undefined") do
        c = EC.new("UTF-8", "US-ASCII")
        src = +"aéb"
        dst = +""
        [c.primitive_convert(src, dst), src.bytes, dst.bytes, c.primitive_errinfo]
      end
      show("primitive offset") do
        c = EC.new("UTF-8", "EUC-JP")
        src = +"あ"
        dst = +"keep"
        [c.primitive_convert(src, dst, 2), dst.bytes]
      end
      show("errinfo fresh") { EC.new("UTF-8", "EUC-JP").primitive_errinfo }
      show("last_error fresh") { EC.new("UTF-8", "EUC-JP").last_error }
      show("putback") { EC.new("UTF-8", "EUC-JP").putback.bytes }

      show("insert_output") do
        c = EC.new("UTF-8", "EUC-JP")
        [c.insert_output("X"), c.convert("a").bytes]
      end
      show("insert_output converts") do
        c = EC.new("UTF-8", "EUC-JP")
        c.insert_output("あ")
        c.finish.bytes
      end
    RUBY

    _(result).must_answer <<~'OUT'
      own singleton: [:asciicompat_encoding, :search_convpath]
      own instance: [:==, :convert, :convpath, :destination_encoding, :finish, :insert_output, :inspect, :last_error, :primitive_convert, :primitive_errinfo, :putback, :replacement, :replacement=, :source_encoding]
      constants: [:AFTER_OUTPUT, :CRLF_NEWLINE_DECORATOR, :CR_NEWLINE_DECORATOR, :INVALID_MASK, :INVALID_REPLACE, :LF_NEWLINE_DECORATOR, :PARTIAL_INPUT, :UNDEF_HEX_CHARREF, :UNDEF_MASK, :UNDEF_REPLACE, :UNIVERSAL_NEWLINE_DECORATOR, :XML_ATTR_CONTENT_DECORATOR, :XML_ATTR_QUOTE_DECORATOR, :XML_TEXT_DECORATOR]
      INVALID_MASK: 15
      UNDEF_HEX_CHARREF: 48
      PARTIAL_INPUT: 131072
      AFTER_OUTPUT: 262144
      XML_ATTR_QUOTE_DECORATOR: 1048576
      new: #<Encoding::Converter: UTF-8 to EUC-JP>
      new encodings: #<Encoding::Converter: UTF-8 to EUC-JP>
      new one arg: ArgumentError: wrong number of arguments (given 1, expected 2..3)
      new symbol: TypeError: no implicit conversion of Symbol into String
      new unknown: Encoding::ConverterNotFoundError: code converter not found (nope to UTF-8)
      new same: Encoding::ConverterNotFoundError: code converter not found (UTF-8 to UTF-8)
      new same + decorator: Encoding::ConverterNotFoundError: code converter not found (UTF-8 to UTF-8 with universal_newline)
      new two newlines: Encoding::ConverterNotFoundError: code converter not found (UTF-8 to EUC-JP with universal_newline,crlf_newline)
      new no-conversion: #<Encoding::Converter: no-conversion>
      new decorator only: #<Encoding::Converter: universal_newline>
      source_encoding: #<Encoding:UTF-8>
      destination_encoding: #<Encoding:EUC-JP>
      no-conversion source: nil
      inspect: "#<Encoding::Converter: UTF-8 to EUC-JP>"
      inspect decorated: "#<Encoding::Converter: UTF-8 to EUC-JP with crlf_newline>"
      inspect xml attr: "#<Encoding::Converter: UTF-8 to EUC-JP with xml_attr_content,xml_attr_quote>"
      inspect no-conversion: "#<Encoding::Converter: no-conversion>"
      inspect decorator only: "#<Encoding::Converter: crlf_newline>"
      == same: true
      == different: false
      == non-converter: nil
      convpath direct: [[#<Encoding:UTF-8>, #<Encoding:EUC-JP>]]
      convpath pivot: [[#<Encoding:ISO-8859-1>, #<Encoding:UTF-8>], [#<Encoding:UTF-8>, #<Encoding:EUC-JP>]]
      convpath sjis-euc: [[#<Encoding:Shift_JIS>, #<Encoding:EUC-JP>]]
      convpath jis: [[#<Encoding:ISO-2022-JP (dummy)>, #<Encoding:stateless-ISO-2022-JP>], [#<Encoding:stateless-ISO-2022-JP>, #<Encoding:EUC-JP>], [#<Encoding:EUC-JP>, #<Encoding:UTF-8>]]
      convpath long: [[#<Encoding:Windows-1252>, #<Encoding:UTF-8>], [#<Encoding:UTF-8>, #<Encoding:EUC-JP>], [#<Encoding:EUC-JP>, #<Encoding:stateless-ISO-2022-JP>], [#<Encoding:stateless-ISO-2022-JP>, #<Encoding:ISO-2022-JP (dummy)>]]
      convpath decorated: [[#<Encoding:UTF-8>, #<Encoding:EUC-JP>], "universal_newline"]
      convpath xml: [[#<Encoding:UTF-8>, #<Encoding:EUC-JP>], "xml_attr_content_escape", "xml_attr_quote"]
      convpath same: Encoding::ConverterNotFoundError: code converter not found (UTF-8 to UTF-8)
      convpath decorator only: ["crlf_newline"]
      asciicompat 2022: #<Encoding:stateless-ISO-2022-JP>
      asciicompat utf16: #<Encoding:UTF-8>
      asciicompat ibm037: #<Encoding:ISO-8859-1>
      asciicompat cesu8: #<Encoding:UTF-8>
      asciicompat utf8: nil
      asciicompat utf8-mac: nil
      asciicompat unknown: nil
      convert: [164, 162, 164, 164]
      convert encoding: #<Encoding:EUC-JP>
      convert split: [[], [164, 162], []]
      convert undef: Encoding::UndefinedConversionError: U+00E9 from UTF-8 to US-ASCII
      convert undef replaced: "?"
      convert invalid: Encoding::InvalidByteSequenceError: "\xFF" on UTF-8
      convert invalid replaced: [63]
      convert after finish: ArgumentError: converter already finished
      convert non-string: TypeError: no implicit conversion of Integer into String
      finish truncated: Encoding::InvalidByteSequenceError: incomplete "\xE3\x81" on UTF-8
      finish truncated replaced: [63]
      finish closes jis: [[27, 36, 66, 36, 34], [27, 40, 66]]
      crlf: [97, 13, 10, 98]
      cr: [97, 13, 98]
      universal: "a\nb"
      universal cr only: "a\nb"
      universal split: ["a", "\nb"]
      xml text: [38, 108, 116, 59, 97, 38, 97, 109, 112, 59, 98, 38, 103, 116, 59]
      xml attr: [34, 97, 38, 113, 117, 111, 116, 59, 98]
      flags integer: [63]
      flags universal: "a\nb"
      replacement euc: "?"
      replacement euc encoding: #<Encoding:US-ASCII>
      replacement utf8: "�"
      replacement utf16: [239, 191, 189]
      replacement set: ["!", "!"]
      replacement unrepresentable: Encoding::UndefinedConversionError: replacement character setup failed
      primitive whole: [:finished, [], [164, 162, 164, 164, 164, 166]]
      primitive truncated: [:incomplete_input, [], [97], [:incomplete_input, "UTF-8", "EUC-JP", "\xE3\x81", ""]]
      primitive partial input: [:source_buffer_empty, [], [97], [:source_buffer_empty, nil, nil, nil, nil]]
      primitive invalid: [:invalid_byte_sequence, [98], [97], [:invalid_byte_sequence, "UTF-8", "EUC-JP", "\xFF", ""], Encoding::InvalidByteSequenceError]
      primitive undefined: [:undefined_conversion, [98], [97], [:undefined_conversion, "UTF-8", "US-ASCII", "\xC3\xA9", ""]]
      primitive offset: [:finished, [107, 101, 164, 162]]
      errinfo fresh: [:source_buffer_empty, nil, nil, nil, nil]
      last_error fresh: nil
      putback: []
      insert_output: [nil, [88, 97]]
      insert_output converts: [164, 162]
    OUT
  end

  it "encoding converter buffer full" do
    result = ze0(<<~'RUBY')
      # A converter's `#primitive_convert` cuts at CRuby's own point under a
      # `dst_bytesize` limit. (This first line avoids naming the class outright:
      # ruby would read `coding:` inside it as a magic comment.)
      #
      # This was a gap. zeo used to refuse the first character whose bytes would not
      # fit and consume nothing more, so its source kept every character that did
      # not convert while CRuby's was shorter. `ConvState` now holds the output
      # produced past the limit and drains it ahead of the next conversion, which is
      # what makes the INTERMEDIATE state agree and not just the end state.
      #
      # Both rows below are pinned: where the cut falls, and what a drain answers.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("cut point") do
        c = Encoding::Converter.new("UTF-8", "EUC-JP")
        src = +"あいう"
        dst = +""
        [c.primitive_convert(src, dst, 0, 2), src.bytes, dst.bytes]
      end

      # Draining reaches the same place: all six bytes, in order.
      show("drained") do
        c = Encoding::Converter.new("UTF-8", "EUC-JP")
        src = +"あいう"
        dst = +""
        c.primitive_convert(src, dst, 0, 2)
        [c.primitive_convert(src, dst, dst.bytesize, 10), src.bytes, dst.bytes]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      cut point: [:destination_buffer_full, [227, 129, 134], [164, 162]]
      drained: [:finished, [], [164, 162, 164, 164, 164, 166]]
    OUT
  end

  it "encoding registered only" do
    result = ze0(<<~'RUBY')
      # The multibyte mapping tables landed, so the rows below convert exactly as
      # CRuby does: EUC-KR, GB18030, GB2312, CP949, Big5-HKSCS, UTF8-MAC, eucJP-ms
      # and CP51932 all round-trip here.
      #
      # What still answers `Encoding::ConverterNotFoundError` answers it under ruby
      # TOO, which is why this is a pinned agreement and not a gap: EUC-TW, and the
      # single-byte rows CRuby itself registers with no transcoder of its own
      # (`Windows-1258`, `macThai` and their two siblings).
      #
      # The point of the file is that a registered-only row stays complete in every
      # OTHER way -- `#length`, `#valid_encoding?` and the reflection surface answer
      # whatever ruby answers. See `EncKind::Registered`.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("EUC-KR encode") { "가".encode("EUC-KR").bytes }
      show("EUC-KR decode") { "\xB0\xA1".dup.force_encoding("EUC-KR").encode("UTF-8") }
      show("GB18030 decode") { "\xB0\xA1".dup.force_encoding("GB18030").encode("UTF-8") }
      show("GB2312 decode") { "\xB0\xA1".dup.force_encoding("GB2312").encode("UTF-8") }
      show("EUC-TW decode") { "\xC4\xE9".dup.force_encoding("EUC-TW").encode("UTF-8") }
      show("CP949 decode") { "\xB0\xA1".dup.force_encoding("CP949").encode("UTF-8") }
      show("Big5-HKSCS decode") { "\xA4\x40".dup.force_encoding("Big5-HKSCS").encode("UTF-8") }
      show("UTF8-MAC decode") { "\x65\xCC\x81".dup.force_encoding("UTF8-MAC").encode("UTF-8") }
      show("eucJP-ms decode") { "\xA4\xA2".dup.force_encoding("eucJP-ms").encode("UTF-8") }
      show("CP51932 decode") { "\xA4\xA2".dup.force_encoding("CP51932").encode("UTF-8") }

      # The four single-byte rows CRuby registers with no transcoder of its own
      # raise the SAME class there, which is why they are registered-only here too.
      show("Windows-1258 decode") { "\xFE".dup.force_encoding("Windows-1258").encode("UTF-8") }
      show("macThai decode") { "\xA1".dup.force_encoding("macThai").encode("UTF-8") }

      # Reflection is unaffected -- these rows are complete in every other way.
      show("EUC-KR length") { "\xB0\xA1".dup.force_encoding("EUC-KR").length }
      show("EUC-TW valid?") { "\xC4\xE9".dup.force_encoding("EUC-TW").valid_encoding? }
    RUBY

    _(result).must_answer <<~'OUT'
      EUC-KR encode: [176, 161]
      EUC-KR decode: "가"
      GB18030 decode: "啊"
      GB2312 decode: "啊"
      EUC-TW decode: Encoding::ConverterNotFoundError: code converter not found (EUC-TW to UTF-8)
      CP949 decode: "가"
      Big5-HKSCS decode: "一"
      UTF8-MAC decode: "é"
      eucJP-ms decode: "あ"
      CP51932 decode: "あ"
      Windows-1258 decode: Encoding::ConverterNotFoundError: code converter not found (Windows-1258 to UTF-8)
      macThai decode: Encoding::ConverterNotFoundError: code converter not found (macThai to UTF-8)
      EUC-KR length: 1
      EUC-TW valid?: true
    OUT
  end

  it "encoding rides through format and padding" do
    result = ze0(<<~'RUBY')
      # The encoding a derived String carries, across the four places that build
      # one out of two others: interpolation, `%`/`format`, `Array#pack` and the
      # `ljust`/`rjust`/`center` family.
      #
      # The rule is one rule -- CRuby's `rb_enc_check`. An ASCII-only side never
      # moves the answer, because every encoding zeo carries is ASCII-compatible;
      # two non-ASCII sides in different encodings do not combine at all, and that
      # is an `Encoding::CompatibilityError`.
      #
      # zeo used to tag every one of these UTF-8, which lost the receiver's
      # encoding, lost the argument's, and never raised.

      def show(label)
        v = yield
        puts format("%-34s %s", label, v.is_a?(String) ? "#{v.encoding} #{v.bytes.inspect}" : v.inspect)
      rescue => e
        puts format("%-34s %s", label, e.class)
      end

      utf8   = "café"
      binary = utf8.b
      ascii  = "abc"
      latin1 = "\xe9".force_encoding("ISO-8859-1")

      # -- interpolation ---------------------------------------------------------
      show("interp ascii + latin1")   { "#{ascii}#{latin1}" }
      show("interp latin1 + ascii")   { "#{latin1}#{ascii}" }
      show("interp utf8 + latin1")    { "#{utf8}#{latin1}" }
      show("interp ascii only")       { "#{ascii}#{ascii}" }
      show("interp binary")           { "#{ascii}#{binary}" }

      # -- format ----------------------------------------------------------------
      show("%s ascii fmt, binary arg") { "%s" % binary }
      show("%s latin1 fmt, ascii arg") { "%s".force_encoding("ISO-8859-1") % ascii }
      show("%d binary fmt")            { "%d".b % 5 }
      show("%s no substitution")       { "plain".b % [] }
      show("%s two args, one binary")  { "%s%s" % [ascii, binary] }
      show("%s incompatible pair")     { "%s%s" % [utf8, latin1] }
      show("format() keeps it")        { format("%s", binary) }

      # -- pack ------------------------------------------------------------------
      # A template starts at US-ASCII and only ever moves down: `m`/`M`/`u` write
      # ASCII text, `U` lifts to UTF-8, and anything writing raw bytes pins the
      # answer at ASCII-8BIT.
      show("pack empty")               { [].pack("") }
      show("pack m")                   { ["hi"].pack("m0") }
      show("pack U")                   { [233].pack("U*") }
      show("pack U then m")            { [65, "hi"].pack("Um") }
      show("pack U then C")            { [65, 66].pack("UC") }
      show("pack C")                   { [65].pack("C*") }

      # -- padding ---------------------------------------------------------------
      show("ljust latin1 pad")         { ascii.ljust(5, latin1) }
      show("rjust latin1 pad")         { ascii.rjust(5, latin1) }
      show("center latin1 pad")        { ascii.center(5, latin1) }
      show("ljust already wide")       { ascii.ljust(1, latin1) }
      show("ljust incompatible")       { utf8.ljust(9, latin1) }
      show("ljust incompatible, wide") { utf8.ljust(1, latin1) }

      # -- the comparison the same rule decides ----------------------------------
      show("binary <=> utf8")          { binary <=> utf8 }
      show("utf8 <=> binary")          { utf8 <=> binary }
      show("ascii binary <=> ascii")   { ascii.b <=> ascii }
      p [utf8, binary, ascii].sort.map { _1.encoding.to_s }

      # -- transcoding out of BINARY --------------------------------------------
      # Binary has no invalid byte, so a high byte is a valid character with no
      # mapping: `:undef` territory, not `:invalid`.
      show("binary high byte to utf8") { binary.encode("UTF-8") }
      puts(begin
        binary.encode("UTF-8")
      rescue => e
        "#{e.class}: #{e.message}"
      end)
    RUBY

    _(result).must_answer <<~'OUT'
      interp ascii + latin1              ISO-8859-1 [97, 98, 99, 233]
      interp latin1 + ascii              ISO-8859-1 [233, 97, 98, 99]
      interp utf8 + latin1               Encoding::CompatibilityError
      interp ascii only                  UTF-8 [97, 98, 99, 97, 98, 99]
      interp binary                      ASCII-8BIT [97, 98, 99, 99, 97, 102, 195, 169]
      %s ascii fmt, binary arg           ASCII-8BIT [99, 97, 102, 195, 169]
      %s latin1 fmt, ascii arg           ISO-8859-1 [97, 98, 99]
      %d binary fmt                      ASCII-8BIT [53]
      %s no substitution                 ASCII-8BIT [112, 108, 97, 105, 110]
      %s two args, one binary            ASCII-8BIT [97, 98, 99, 99, 97, 102, 195, 169]
      %s incompatible pair               Encoding::CompatibilityError
      format() keeps it                  ASCII-8BIT [99, 97, 102, 195, 169]
      pack empty                         US-ASCII []
      pack m                             US-ASCII [97, 71, 107, 61]
      pack U                             UTF-8 [195, 169]
      pack U then m                      UTF-8 [65, 97, 71, 107, 61, 10]
      pack U then C                      ASCII-8BIT [65, 66]
      pack C                             ASCII-8BIT [65]
      ljust latin1 pad                   ISO-8859-1 [97, 98, 99, 233, 233]
      rjust latin1 pad                   ISO-8859-1 [233, 233, 97, 98, 99]
      center latin1 pad                  ISO-8859-1 [233, 97, 98, 99, 233]
      ljust already wide                 UTF-8 [97, 98, 99]
      ljust incompatible                 Encoding::CompatibilityError
      ljust incompatible, wide           Encoding::CompatibilityError
      binary <=> utf8                    -1
      utf8 <=> binary                    1
      ascii binary <=> ascii             0
      ["UTF-8", "ASCII-8BIT", "UTF-8"]
      binary high byte to utf8           Encoding::UndefinedConversionError
      Encoding::UndefinedConversionError: "\xC3" from ASCII-8BIT to UTF-8
    OUT
  end

  it "format binary" do
    result = ze0(<<~'RUBY')
      # "%b" / "%B" binary conversion in String#% / format / sprintf. Previously the
      # binary conversion was unsupported and emitted the literal spec (e.g. "%b").
      def s(x); x; end

      # --- basics ---
      p("%b" % 10)        # 1010
      p("%b" % 0)         # 0
      p("%b" % 1)         # 1
      p("%B" % 10)        # 1010
      p("%b" % 255)       # 11111111

      # --- width (space-padded, zero-padded, left-justified, too-narrow) ---
      p("%5b" % 10)       # " 1010"
      p("%8b" % 10)       # "    1010"
      p("%1b" % 10)       # "1010" (width < length: no truncation)
      p("%08b" % 10)      # "00001010"
      p("%-8b|" % 10)     # "1010    |"

      # --- flags on non-negatives ---
      p("%+b" % 10)       # +1010
      p("% b" % 10)       # " 1010"
      p("%#b" % 10)       # 0b1010
      p("%#B" % 10)       # 0B1010
      p("%#b" % 0)        # 0      (# prefix omitted for zero)
      p("%+08b" % 10)     # +0001010
      p("% 08b" % 10)     # " 0001010"
      p("%-#10b|" % 10)   # "0b1010    |"
      p("%#010b" % 10)    # 0b00001010

      # --- precision (minimum digits; disables 0-flag) ---
      p("%.8b" % 5)       # 00000101
      p("%.0b" % 0)       # ""      (zero with precision 0 is empty)
      p("%.1b" % 0)       # 0
      p("%.3b" % 10)      # 1010    (precision < length: no truncation)
      p("%.0b" % 5)       # 101
      p("%10.8b" % 5)     # "  00000101"
      p("%-10.8b|" % 5)   # "00000101  |"
      p("%#.8b" % 5)      # 0b00000101
      p("%#.4b" % 0)      # 0000
      p("%05.3b" % 0)     # "  000"

      # --- negatives without a sign flag: two's-complement ".." notation ---
      p("%b" % -1)        # ..1
      p("%b" % -2)        # ..10
      p("%b" % -5)        # ..1011
      p("%.8b" % -5)      # ..111011
      p("%#b" % -5)       # 0b..1011
      p("%10b" % -5)      # "    ..1011"
      p("%-10b|" % -5)    # "..1011    |"
      p("%010b" % -5)     # ..11111011   (zero-pad fills with the sign bit 1)
      p("%012b" % -5)     # ..1111111011
      p("%#010b" % -5)    # 0b..111011

      # --- negatives WITH a sign flag: signed magnitude ("-101"), not ".." ---
      p("%+b" % -5)       # -101
      p("% b" % -5)       # -101
      p("%+.8b" % -5)     # -00000101
      p("%+08b" % -5)     # -0000101
      p("%+10b" % -5)     # "      -101"
      p("%+#b" % -5)      # -0b101

      # --- large precision exercises the digit buffer (this path overflowed the
      #     stack before the buffers were sized to the output ceiling) ---
      p("%.100b" % 5)     # 97 zeros then 101
      p("%.64b" % -5)     # ".." then 1-padded body to 64 chars
      p("%.128b" % 1)     # 127 zeros then 1

      # --- routing: multi-arg, method-routed value, format, sprintf ---
      p("%b and %b" % [5, 6])   # "101 and 110"
      p("v=%b" % s(6))          # "v=110"
      p(format("%08b", 42))     # 00101010
      p(sprintf("%b", 255))     # 11111111
      p("%b" % s(-3))           # ..101
    RUBY

    _(result).must_answer <<~'OUT'
      "1010"
      "0"
      "1"
      "1010"
      "11111111"
      " 1010"
      "    1010"
      "1010"
      "00001010"
      "1010    |"
      "+1010"
      " 1010"
      "0b1010"
      "0B1010"
      "0"
      "+0001010"
      " 0001010"
      "0b1010    |"
      "0b00001010"
      "00000101"
      ""
      "0"
      "1010"
      "101"
      "  00000101"
      "00000101  |"
      "0b00000101"
      "0000"
      "  000"
      "..1"
      "..10"
      "..1011"
      "..111011"
      "0b..1011"
      "    ..1011"
      "..1011    |"
      "..11111011"
      "..1111111011"
      "0b..111011"
      "-101"
      "-101"
      "-00000101"
      "-0000101"
      "      -101"
      "-0b101"
      "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101"
      "..11111111111111111111111111111111111111111111111111111111111011"
      "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
      "101 and 110"
      "v=110"
      "00101010"
      "11111111"
      "..101"
    OUT
  end

  it "format binary precision and twos complement negatives" do
    result = ze0(<<~'RUBY')
      # %b honors precision (min digits, disabling the 0-flag) and renders
      # negatives in CRuby's infinite two's-complement ".." notation, switching
      # to signed magnitude under a sign flag.

      p("%08b" % 10)
      p("%.8b" % 5)
      p("%#010b" % 10)
      p("%05.3b" % 0)
      p("%b" % -5)
      p("%.8b" % -5)
      p("%010b" % -5)
      p("%#010b" % -5)
      p("%+b" % -5)
      p("%+08b" % -5)
    RUBY

    _(result).must_answer <<~'OUT'
      "00001010"
      "00000101"
      "0b00001010"
      "  000"
      "..1011"
      "..111011"
      "..11111011"
      "0b..111011"
      "-101"
      "-0000101"
    OUT
  end

  it "gb18030 cesu 8 and ibm037 follow their rules" do
    result = ze0(<<~'RUBY')
      # GB18030's four-byte characters count through Unicode in order, CESU-8
      # writes a character past the BMP as two surrogates of three bytes each,
      # and IBM037 holds ISO-8859-1's bytes in EBCDIC order. UTF-7 and
      # ISO-2022-JP-2 have no converter in ruby at all.
      p "ñ€\u{1F600}".encode("GB18030").b, "\x81\x30\x8A\x39\x95\x32\x82\x36".force_encoding("GB18030").encode("UTF-8")
      p "\x84\x31\xA4\x39".force_encoding("GB18030").encode("UTF-8"), "\x90\x30\x81\x30".force_encoding("GB18030").encode("UTF-8").ord.to_s(16)
      ["\x84\x31\xA5\x30", "\xE3\x32\x9A\x36", "\x81\x30", "\x81\x30\x81", "\x81\x30x0"].each do |bad|
        begin
          p bad.dup.force_encoding("GB18030").encode("UTF-8")
        rescue => e
          p [e.class, e.message]
        end
      end
      p "\xE3\x32\x9A\x36".force_encoding("GB18030").encode("UTF-8", undef: :replace)
      p "\u{1F600}".encode("CESU-8").b, "日".encode("CESU-8").b, "\xED\xA0\xBD\xED\xB8\x80".force_encoding("CESU-8").encode("UTF-8")
      ["\xED\xA0\xBD", "\xED\xB8\x80", "\xE6\x97", "\xF0\x9F\x98\x80", "\xED\xA0\xBDx"].each do |bad|
        begin
          p bad.dup.force_encoding("CESU-8").encode("UTF-8")
        rescue => e
          p [e.class, e.message]
        end
      end
      p "éaZ".encode("IBM037").b, ("日".encode("IBM037") rescue $!.message), "\xC1\x81".force_encoding("IBM037").encode("UTF-8")
      p (0..255).map(&:chr).join.force_encoding("IBM037").encode("UTF-8").bytesize
      p ("a".encode("UTF-7") rescue $!), ("a".encode("ISO-2022-JP-2") rescue $!)

    RUBY

    _(result).must_answer <<~'OUT'
      "\x810\x8A9\xA2\xE3\x949\xFC6"
      "ñ𠀀"
      "\uFFFF"
      "10000"
      [Encoding::UndefinedConversionError, "\"\\x841\\xA50\" from GB18030 to UTF-8"]
      [Encoding::UndefinedConversionError, "\"\\xE32\\x9A6\" from GB18030 to UTF-8"]
      [Encoding::InvalidByteSequenceError, "incomplete \"\\x810\" on GB18030"]
      [Encoding::InvalidByteSequenceError, "incomplete \"\\x810\\x81\" on GB18030"]
      [Encoding::InvalidByteSequenceError, "\"\\x810\" followed by \"x\" on GB18030"]
      "�"
      "\xED\xA0\xBD\xED\xB8\x80"
      "\xE6\x97\xA5"
      "😀"
      [Encoding::InvalidByteSequenceError, "incomplete \"\\xED\\xA0\\xBD\" on CESU-8"]
      [Encoding::InvalidByteSequenceError, "\"\\xED\" followed by \"\\xB8\" on CESU-8"]
      [Encoding::InvalidByteSequenceError, "incomplete \"\\xE6\\x97\" on CESU-8"]
      [Encoding::InvalidByteSequenceError, "\"\\xF0\" on CESU-8"]
      [Encoding::InvalidByteSequenceError, "\"\\xED\\xA0\\xBD\" followed by \"x\" on CESU-8"]
      "Q\x81\xE9"
      "U+65E5 to ISO-8859-1 in conversion from UTF-8 to ISO-8859-1 to IBM037"
      "Aa"
      384
      #<Encoding::ConverterNotFoundError: code converter not found (UTF-8 to UTF-7)>
      #<Encoding::ConverterNotFoundError: code converter not found (UTF-8 to ISO-2022-JP-2)>
    OUT
  end

  it "issue symbol loses encoding" do
    result = ze0(<<~'RUBY')
      # A Symbol remembers the encoding of the String it came from, so
      # `str.to_sym.to_s` answers that encoding and those bytes.
      #
      # This was a gap. The interner used to key on `&'static str` and store nothing
      # else, so `Symbol::intern` was handed `to_utf8_lossy` text and the encoding
      # was gone by the time the id existed. Ruby interns by BYTES plus encoding --
      # `:"caf\xE9"` in ISO-8859-1 and the same bytes in UTF-8 are two different
      # symbols -- and so does zeo now.
      #
      # Each row pins the round trip for one non-UTF-8 encoding.
      {
        "latin1" => "caf\xE9 x".dup.force_encoding("ISO-8859-1"),
        "binary" => "caf\xE9 x".dup.force_encoding("ASCII-8BIT"),
        "koi8"   => "\xC1\xC2 x".dup.force_encoding("KOI8-R"),
        "eucjp"  => "\xA4\xA2\xA4\xA4 x".dup.force_encoding("EUC-JP"),
      }.each do |k, s|
        back = s.to_sym.to_s
        puts "#{k}\t#{back.encoding} #{back.bytes.inspect}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      latin1	ISO-8859-1 [99, 97, 102, 233, 32, 120]
      binary	ASCII-8BIT [99, 97, 102, 233, 32, 120]
      koi8	KOI8-R [193, 194, 32, 120]
      eucjp	EUC-JP [164, 162, 164, 164, 32, 120]
    OUT
  end

  it "multibyte string walks every lead byte as onigmo does" do
    result = ze0(<<~'RUBY')
      # A String in a legacy multibyte encoding finds where each character
      # ends by the lead-byte lengths and state tables of CRuby's enc/*.c:
      # GB18030's four-byte characters all through their range, EUC-TW's
      # planes, Emacs-Mule's leading codes, CESU-8's surrogate pairs, and
      # the replicas that read as the encoding they copy. A character the text
      # ends inside, or a byte that cannot follow its lead, reads as broken
      # bytes, and scrub replaces a run of them as CRuby groups it.
      def walk(bytes, enc)
        s = bytes.b.force_encoding(enc)
        [s.valid_encoding?, s.length, s.each_char.map(&:bytesize), s.scrub("?").b]
      end

      gb = ["\x81\x30\x81\x30", "\x84\x31\xA4\x39", "\x84\x31\xA5\x30", "\x90\x30\x81\x30", "\xE3\x32\x9A\x35",
            "\xFE\x39\xFE\x39", "\x81\x40", "\xFE\xFE", "\x81\x7F", "\x81\x30\x81", "\x81\x30", "\x81", "\x80", "\xFF", "\x81\x30\x7F\x30"]
      gb.each { |b| p walk("a#{b}z", "GB18030") }

      tw = ["\xA1\xA1", "\x8E\xA1\xA1\xA1", "\x8E\xA2\xFE\xFE", "\x8E\xB0\xA1\xA1", "\x8E\xA1\xA1", "\x8E\xA1", "\x8E", "\xA1", "\x8F\xA1\xA1"]
      tw.each { |b| p walk("a#{b}z", "EUC-TW") }

      mule = ["\x81\xA1", "\x92\xA4\xA2", "\x9A\xA0\xA1", "\x9C\xF0\xA1\xA1", "\x9D\xF5\xA1\xA1", "\x9E\xA1", "\x92\xA4", "\x80"]
      mule.each { |b| p walk("a#{b}z", "Emacs-Mule"), walk("a#{b}z", "stateless-ISO-2022-JP") }

      cesu = ["\xC3\xA9", "\xE3\x81\x82", "\xED\xA0\x80\xED\xB0\x80", "\xED\xA0\x80", "\xED\xB0\x80", "\xF0\x9F\x98\x80", "\xED\xA0\x80\xED", "\xC0\x80"]
      cesu.each { |b| p walk("a#{b}z", "CESU-8") }

      jp = ["\x8F\xA1\xA1", "\x8E\xB1", "\x8E\xA0", "\xA1\xA1", "\xA1", "\x8F\xA1", "\xFF\xA1"]
      %w[EUC-JP eucJP-ms CP51932 EUC-JIS-2004].each { |enc| jp.each { |b| p walk("a#{b}z", enc) } }

      sjis = ["\x81\x40", "\x81\x7F", "\x81\xFC", "\xA1", "\xDF", "\xE0\x40", "\xFC\xFC", "\xFD\x40", "\x80", "\xA0", "\x81"]
      %w[Shift_JIS Windows-31J MacJapanese SJIS-KDDI].each { |enc| sjis.each { |b| p walk("a#{b}z", enc) } }

      two = ["\x81\x41", "\x81\x5A", "\x81\x61", "\x81\x7F", "\xA1\x40", "\xA1\xA1", "\xFE\xFE", "\xFE\x30", "\x80\x40", "\xFF\xA1", "\xC8"]
      %w[Big5 Big5-HKSCS Big5-UAO CP950 CP951 GBK CP949 EUC-KR GB2312 GB12345].each { |enc| two.each { |b| p walk("a#{b}z", enc) } }

      text = "a\x95\x32\x82\x36b\xA2\xE3".b.force_encoding("GB18030")
      p text.chars.map(&:bytes), text.reverse.b, text[1], text.byteindex("b"), text.index("b"), text.chop.bytesize
      p text.encode("UTF-8"), "\u{20000}€".encode("GB18030").chars.map(&:bytesize)
      p "a\x80\x81\x30".b.force_encoding("GB18030").scrub { |b| "<#{b.bytes.join(',')}>" }, "a\x80\x8F\xA1".b.force_encoding("EUC-JP").scrub
      p "a\xED\xA0\x80".b.force_encoding("CESU-8").scrub, "a\xFF".b.force_encoding("UTF8-MAC").scrub, "a\xFF".b.force_encoding("US-ASCII").scrub, "a\xFF".scrub
      p text.ljust(8,"\x81\x30\x81\x30".b.force_encoding("GB18030")).length, text.center(6).bytesize, text.each_grapheme_cluster.count


    RUBY

    _(result).must_answer <<~'OUT'
      [true, 3, [1, 4, 1], "a\x810\x810z"]
      [true, 3, [1, 4, 1], "a\x841\xA49z"]
      [true, 3, [1, 4, 1], "a\x841\xA50z"]
      [true, 3, [1, 4, 1], "a\x900\x810z"]
      [true, 3, [1, 4, 1], "a\xE32\x9A5z"]
      [true, 3, [1, 4, 1], "a\xFE9\xFE9z"]
      [true, 3, [1, 2, 1], "a\x81@z"]
      [true, 3, [1, 2, 1], "a\xFE\xFEz"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [false, 4, [1, 1, 1, 2], "a?z"]
      [false, 4, [1, 1, 1, 1], "a?z"]
      [true, 2, [1, 2], "a\x81z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 6, [1, 1, 1, 1, 1, 1], "a?\x7F0z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [true, 3, [1, 4, 1], "a\x8E\xA1\xA1\xA1z"]
      [true, 3, [1, 4, 1], "a\x8E\xA2\xFE\xFEz"]
      [true, 3, [1, 4, 1], "a\x8E\xB0\xA1\xA1z"]
      [false, 4, [1, 1, 2, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a?z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 4, [1, 1, 2, 1], "a?\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\x81\xA1z"]
      [true, 3, [1, 2, 1], "a\x81\xA1z"]
      [true, 3, [1, 3, 1], "a\x92\xA4\xA2z"]
      [true, 3, [1, 3, 1], "a\x92\xA4\xA2z"]
      [false, 5, [1, 1, 1, 1, 1], "a???z"]
      [false, 5, [1, 1, 1, 1, 1], "a???z"]
      [true, 3, [1, 4, 1], "a\x9C\xF0\xA1\xA1z"]
      [true, 3, [1, 4, 1], "a\x9C\xF0\xA1\xA1z"]
      [true, 3, [1, 4, 1], "a\x9D\xF5\xA1\xA1z"]
      [true, 3, [1, 4, 1], "a\x9D\xF5\xA1\xA1z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [false, 4, [1, 1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a?z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 3, [1, 1, 1], "a?z"]
      [true, 3, [1, 2, 1], "a\xC3\xA9z"]
      [true, 3, [1, 3, 1], "a\xE3\x81\x82z"]
      [true, 3, [1, 6, 1], "a\xED\xA0\x80\xED\xB0\x80z"]
      [false, 5, [1, 1, 1, 1, 1], "a?z"]
      [false, 5, [1, 1, 1, 1, 1], "a???z"]
      [false, 6, [1, 1, 1, 1, 1, 1], "a????z"]
      [false, 6, [1, 1, 1, 1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [true, 3, [1, 3, 1], "a\x8F\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\x8E\xB1z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [true, 3, [1, 3, 1], "a\x8F\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\x8E\xB1z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [true, 3, [1, 3, 1], "a\x8F\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\x8E\xB1z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [true, 3, [1, 3, 1], "a\x8F\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\x8E\xB1z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [true, 3, [1, 2, 1], "a\x81@z"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [true, 3, [1, 2, 1], "a\x81\xFCz"]
      [true, 3, [1, 1, 1], "a\xA1z"]
      [true, 3, [1, 1, 1], "a\xDFz"]
      [true, 3, [1, 2, 1], "a\xE0@z"]
      [true, 3, [1, 2, 1], "a\xFC\xFCz"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 3, [1, 1, 1], "a?z"]
      [true, 2, [1, 2], "a\x81z"]
      [true, 3, [1, 2, 1], "a\x81@z"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [true, 3, [1, 2, 1], "a\x81\xFCz"]
      [true, 3, [1, 1, 1], "a\xA1z"]
      [true, 3, [1, 1, 1], "a\xDFz"]
      [true, 3, [1, 2, 1], "a\xE0@z"]
      [true, 3, [1, 2, 1], "a\xFC\xFCz"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 3, [1, 1, 1], "a?z"]
      [true, 2, [1, 2], "a\x81z"]
      [true, 3, [1, 2, 1], "a\x81@z"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [true, 3, [1, 2, 1], "a\x81\xFCz"]
      [true, 3, [1, 1, 1], "a\xA1z"]
      [true, 3, [1, 1, 1], "a\xDFz"]
      [true, 3, [1, 2, 1], "a\xE0@z"]
      [true, 3, [1, 2, 1], "a\xFC\xFCz"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 3, [1, 1, 1], "a?z"]
      [true, 2, [1, 2], "a\x81z"]
      [true, 3, [1, 2, 1], "a\x81@z"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [true, 3, [1, 2, 1], "a\x81\xFCz"]
      [true, 3, [1, 1, 1], "a\xA1z"]
      [true, 3, [1, 1, 1], "a\xDFz"]
      [true, 3, [1, 2, 1], "a\xE0@z"]
      [true, 3, [1, 2, 1], "a\xFC\xFCz"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 3, [1, 1, 1], "a?z"]
      [true, 2, [1, 2], "a\x81z"]
      [false, 4, [1, 1, 1, 1], "a?Az"]
      [false, 4, [1, 1, 1, 1], "a?Zz"]
      [false, 4, [1, 1, 1, 1], "a?az"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [true, 3, [1, 2, 1], "a\xA1@z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\xFE\xFEz"]
      [false, 4, [1, 1, 1, 1], "a?0z"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 3, [1, 1, 2], "a?\xA1z"]
      [true, 2, [1, 2], "a\xC8z"]
      [false, 4, [1, 1, 1, 1], "a?Az"]
      [false, 4, [1, 1, 1, 1], "a?Zz"]
      [false, 4, [1, 1, 1, 1], "a?az"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [true, 3, [1, 2, 1], "a\xA1@z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\xFE\xFEz"]
      [false, 4, [1, 1, 1, 1], "a?0z"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 3, [1, 1, 2], "a?\xA1z"]
      [true, 2, [1, 2], "a\xC8z"]
      [false, 4, [1, 1, 1, 1], "a?Az"]
      [false, 4, [1, 1, 1, 1], "a?Zz"]
      [false, 4, [1, 1, 1, 1], "a?az"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [true, 3, [1, 2, 1], "a\xA1@z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\xFE\xFEz"]
      [false, 4, [1, 1, 1, 1], "a?0z"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 3, [1, 1, 2], "a?\xA1z"]
      [true, 2, [1, 2], "a\xC8z"]
      [false, 4, [1, 1, 1, 1], "a?Az"]
      [false, 4, [1, 1, 1, 1], "a?Zz"]
      [false, 4, [1, 1, 1, 1], "a?az"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [true, 3, [1, 2, 1], "a\xA1@z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\xFE\xFEz"]
      [false, 4, [1, 1, 1, 1], "a?0z"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 3, [1, 1, 2], "a?\xA1z"]
      [true, 2, [1, 2], "a\xC8z"]
      [false, 4, [1, 1, 1, 1], "a?Az"]
      [false, 4, [1, 1, 1, 1], "a?Zz"]
      [false, 4, [1, 1, 1, 1], "a?az"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [true, 3, [1, 2, 1], "a\xA1@z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\xFE\xFEz"]
      [false, 4, [1, 1, 1, 1], "a?0z"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 3, [1, 1, 2], "a?\xA1z"]
      [true, 2, [1, 2], "a\xC8z"]
      [true, 3, [1, 2, 1], "a\x81Az"]
      [true, 3, [1, 2, 1], "a\x81Zz"]
      [true, 3, [1, 2, 1], "a\x81az"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [true, 3, [1, 2, 1], "a\xA1@z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\xFE\xFEz"]
      [false, 4, [1, 1, 1, 1], "a?0z"]
      [true, 4, [1, 1, 1, 1], "a\x80@z"]
      [false, 3, [1, 1, 2], "a?\xA1z"]
      [true, 2, [1, 2], "a\xC8z"]
      [true, 3, [1, 2, 1], "a\x81Az"]
      [true, 3, [1, 2, 1], "a\x81Zz"]
      [true, 3, [1, 2, 1], "a\x81az"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\xFE\xFEz"]
      [false, 4, [1, 1, 1, 1], "a?0z"]
      [true, 4, [1, 1, 1, 1], "a\x80@z"]
      [false, 3, [1, 1, 2], "a?\xA1z"]
      [true, 2, [1, 2], "a\xC8z"]
      [false, 4, [1, 1, 1, 1], "a?Az"]
      [false, 4, [1, 1, 1, 1], "a?Zz"]
      [false, 4, [1, 1, 1, 1], "a?az"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\xFE\xFEz"]
      [false, 4, [1, 1, 1, 1], "a?0z"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a?Az"]
      [false, 4, [1, 1, 1, 1], "a?Zz"]
      [false, 4, [1, 1, 1, 1], "a?az"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\xFE\xFEz"]
      [false, 4, [1, 1, 1, 1], "a?0z"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [false, 3, [1, 1, 1], "a?z"]
      [false, 4, [1, 1, 1, 1], "a?Az"]
      [false, 4, [1, 1, 1, 1], "a?Zz"]
      [false, 4, [1, 1, 1, 1], "a?az"]
      [false, 4, [1, 1, 1, 1], "a?\x7Fz"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [true, 3, [1, 2, 1], "a\xA1\xA1z"]
      [true, 3, [1, 2, 1], "a\xFE\xFEz"]
      [false, 4, [1, 1, 1, 1], "a?0z"]
      [false, 4, [1, 1, 1, 1], "a?@z"]
      [false, 4, [1, 1, 1, 1], "a??z"]
      [false, 3, [1, 1, 1], "a?z"]
      [[97], [149, 50, 130, 54], [98], [162, 227]]
      "\xA2\xE3b\x952\x826a"
      "\x{95328236}"
      5
      2
      6
      "a𠀀b€"
      [4, 2]
      "a<128><129,48>"
      "a??"
      "a?"
      "a?"
      "a?"
      "a�"
      8
      10
      4
    OUT
  end

  it "open encoding option warns or raises" do
    result = ze0(<<~'RUBY')
      # The two rules an open-time encoding argument follows, which are not the same
      # rule and are not derivable from each other.
      #
      #   * A SPEC -- a mode string's `:ext[:int]` tail, or a String `encoding:` --
      #     goes through CRuby's `parse_mode_enc`. A name it does not know WARNS and
      #     leaves the slot at its default.
      #   * `external_encoding:` / `internal_encoding:` go through `rb_to_encoding`.
      #     A name they do not know RAISES.
      #
      # And a spec's internal half spelled `-` asks for NO transcoding rather than
      # naming an encoding: `Encoding.find("-")` raises, so looking it up would warn
      # about a spelling that is correct. zeo raised where ruby warns, and warned
      # about `-`, so `File.open(f, "r:UTF-8:-")` -- the shape irb reads its history
      # file with -- printed a warning ruby does not.
      require "tmpdir"
      require "fileutils"

      DIR = Dir.mktmpdir("zeo_open_enc")
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

      # --- a spec warns ------------------------------------------------------------
      row("mode tail unknown")     { File.open(SRC, "r:NoSuchEnc") { |f| encs(f) } }
      row("encoding: unknown")     { File.open(SRC, "r", encoding: "NoSuchEnc") { |f| encs(f) } }
      row("encoding: pair, internal unknown") { File.open(SRC, "r", encoding: "UTF-8:NoSuchEnc") { |f| encs(f) } }
      row("read encoding: unknown"){ File.read(SRC, encoding: "NoSuchEnc") }

      # --- an encoding ARGUMENT raises --------------------------------------------
      row("external_encoding: unknown")  { File.open(SRC, "r", external_encoding: "NoSuchEnc") { |f| encs(f) } }
      row("internal_encoding: unknown")  { File.open(SRC, "r", internal_encoding: "NoSuchEnc") { |f| encs(f) } }
      row("read external_encoding: unknown") { File.read(SRC, external_encoding: "NoSuchEnc") }
      # `-` is not a name, so it is not one here either.
      row("external_encoding: -")        { File.open(SRC, "r", external_encoding: "-") { |f| encs(f) } }
      row("Encoding.find(-)")            { Encoding.find("-") }

      # --- `-` means no transcoding -----------------------------------------------
      row("mode tail ext:-")       { File.open(SRC, "r:EUC-JP:-") { |f| encs(f) } }
      row("mode tail utf8:-")      { File.open(SRC, "r:UTF-8:-") { |f| encs(f) } }
      row("mode tail utf8:- reads"){ File.open(SRC, "r:UTF-8:-", &:read) }
      row("internal_encoding: -")  { File.open(SRC, "r", external_encoding: "EUC-JP", internal_encoding: "-") { |f| encs(f) } }
      row("encoding: ext:-")       { File.open(SRC, "r", encoding: "EUC-JP:-") { |f| encs(f) } }
      row("read mode: ext:-")      { File.read(SRC, mode: "r:UTF-8:-") }
      row("readlines mode: ext:-") { File.readlines(SRC, mode: "r:UTF-8:-") }
      row("read internal: -")      { File.read(SRC, external_encoding: "EUC-JP", internal_encoding: "-").encoding.name }

      # --- naming an encoding in both places is refused ---------------------------
      row("mode tail and encoding:")          { File.open(SRC, "r:EUC-JP", encoding: "UTF-8") { |f| encs(f) } }
      row("mode tail and external_encoding:") { File.open(SRC, "r:EUC-JP", external_encoding: "UTF-8") { |f| encs(f) } }

      # --- perm and options are BOTH optional and both trail the mode -------------
      DST = File.join(DIR, "dst.txt")
      row("open with perm and opts") { File.open(DST, "w", 0o600, external_encoding: "EUC-JP") { |f| encs(f) } }
      row("perm still applied")      { format("%o", File.stat(DST).mode & 0o777) }
      row("open with opts, no perm") { File.open(DST, "w", external_encoding: "EUC-JP") { |f| encs(f) } }

      FileUtils.remove_entry(DIR)
      puts "ran to the end"
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      mode tail unknown	["UTF-8", nil]
      encoding: unknown	["UTF-8", nil]
      encoding: pair, internal unknown	["UTF-8", nil]
      read encoding: unknown	"hello\n"
      external_encoding: unknown	ArgumentError: unknown encoding name - NoSuchEnc
      internal_encoding: unknown	ArgumentError: unknown encoding name - NoSuchEnc
      read external_encoding: unknown	ArgumentError: unknown encoding name - NoSuchEnc
      external_encoding: -	ArgumentError: unknown encoding name - -
      Encoding.find(-)	ArgumentError: unknown encoding name - -
      mode tail ext:-	["EUC-JP", nil]
      mode tail utf8:-	["UTF-8", nil]
      mode tail utf8:- reads	"hello\n"
      internal_encoding: -	["EUC-JP", nil]
      encoding: ext:-	["EUC-JP", nil]
      read mode: ext:-	"hello\n"
      readlines mode: ext:-	["hello\n"]
      read internal: -	"EUC-JP"
      mode tail and encoding:	ArgumentError: encoding specified twice
      mode tail and external_encoding:	ArgumentError: encoding specified twice
      open with perm and opts	["EUC-JP", nil]
      perm still applied	"600"
      open with opts, no perm	["EUC-JP", nil]
      ran to the end
    OUT
      core/encoding/formatting_test.rb:33: warning: Unsupported encoding NoSuchEnc ignored
      core/encoding/formatting_test.rb:34: warning: Unsupported encoding NoSuchEnc ignored
      core/encoding/formatting_test.rb:35: warning: Unsupported encoding NoSuchEnc ignored
      core/encoding/formatting_test.rb:36: warning: Unsupported encoding NoSuchEnc ignored
    ERR
  end

  it "open mode string carries its encodings" do
    result = ze0(<<~'RUBY', files: {"open_mode/sample.txt" => "hello\n"})
      # A mode string is `access[:extenc[:intenc]]`, and everything after the first
      # `:` names encodings rather than access.
      #
      # zeo matched the WHOLE string against its access table, so `File.open(path,
      # "r:UTF-8")` raised `ArgumentError: invalid access mode` before it touched the
      # filesystem -- and `"r:big5"` holds a `b`, so a scan for the binary flag
      # called that one binmode. Bundler reads every gemspec through
      # `Gem.open_file(file, "r:UTF-8:-")`, which is how this surfaced.
      #
      # Three asymmetries here are CRuby's and none is derivable from the others: a
      # `b` does NOT force ASCII-8BIT once the tail names an encoding; naming one in
      # both the mode string and an `encoding:` keyword is an error rather than a
      # precedence rule; and an unknown name in the TAIL warns and falls back where
      # the keyword raises.

      def t(label)
        print label.ljust(30)
        p(yield)
      rescue StandardError => e
        p [e.class, e.message]
      end

      path = File.join(__dir__, "open_mode", "sample.txt")

      t("r:UTF-8") { File.open(path, "r:UTF-8", &:external_encoding).to_s }
      t("r:UTF-8:UTF-16") { File.open(path, "r:UTF-8:UTF-16") { |h| [h.external_encoding.to_s, h.internal_encoding.to_s] } }
      t("rb:UTF-8") { File.open(path, "rb:UTF-8") { |h| [h.binmode?, h.external_encoding.to_s] } }
      t("rb") { File.open(path, "rb") { |h| [h.binmode?, h.external_encoding.to_s] } }
      t("r:bom|utf-8") { File.open(path, "r:bom|utf-8", &:external_encoding).to_s }
      t("named twice") { File.open(path, "r:UTF-8", encoding: "Shift_JIS", &:external_encoding).to_s }
      t("bad access mode") { File.open(path, "zz") { 1 } }
      t("mode: keyword tail") { File.read(path, mode: "r:UTF-8").encoding.to_s }
      t("the bytes still read") { File.open(path, "r:UTF-8", &:read) }
    RUBY

    _(result).must_answer <<~'OUT'
      r:UTF-8                       "UTF-8"
      r:UTF-8:UTF-16                ["UTF-8", "UTF-16"]
      rb:UTF-8                      [true, "UTF-8"]
      rb                            [true, "ASCII-8BIT"]
      r:bom|utf-8                   "UTF-8"
      named twice                   [ArgumentError, "encoding specified twice"]
      bad access mode               [ArgumentError, "invalid access mode zz"]
      mode: keyword tail            "UTF-8"
      the bytes still read          "hello\n"
    OUT
  end

  it "regexp flag letter picks an encoding" do
    result = ze0(<<~'RUBY')
      # A Regexp literal's trailing letter may name an ENCODING -- `/n`, `/e`, `/s`,
      # `/u` -- and that is observable three ways at once: `#options` reports it as a
      # bit, `#encoding` names it, and `#fixed_encoding?` answers whether the pattern
      # is pinned to one.
      #
      # `/e` and `/s` used to be a clean rejection and `/n` and `/u` were treated as
      # harmless no-ops, which they are not: they reported 0 options, US-ASCII, and
      # false. ruby2ruby and ruby_parser both OPEN by reading those bits back out of
      # four throwaway patterns, and they are the reason the numbers here matter.

      # `/n` sets NOENCODING (32); the other three set FIXEDENCODING (16). None of
      # them touch the i/x/m bits, which stay 1/2/4 and combine.
      p [/x/n.options, /x/e.options, /x/s.options, /x/u.options]
      p [/x/.options, /x/i.options, /x/x.options, /x/m.options, /x/mix.options]
      p [/x/in.options, /x/me.options, /x/xu.options]

      # ruby2ruby's own four lines, verbatim in shape.
      ENC_NONE = /x/n.options
      ENC_EUC  = /x/e.options
      ENC_SJIS = /x/s.options
      ENC_UTF8 = /x/u.options
      p [ENC_NONE, ENC_EUC, ENC_SJIS, ENC_UTF8]

      # `#encoding` answers the pinned one. `/n` and a plain literal answer what their
      # own source bytes compute to -- US-ASCII for an ASCII-only pattern.
      p [/x/e.encoding, /x/s.encoding, /x/u.encoding, /x/n.encoding, /x/.encoding]

      # `fixed_encoding?` is true for the three that PIN an encoding. `/n` declares
      # the opposite -- encoding-agnostic -- so it is false.
      p [/x/e.fixed_encoding?, /x/s.fixed_encoding?, /x/u.fixed_encoding?]
      p [/x/n.fixed_encoding?, /x/.fixed_encoding?]

      # A non-ASCII pattern with no flag at all is still fixed-encoding: its own bytes
      # pin it.
      p [/café/.fixed_encoding?, /café/.encoding]

      # The flag changes nothing about MATCHING for an ASCII pattern. action_policy
      # writes `/s` where it means ruby's `/m` -- ruby reads it as Windows-31J, so the
      # dot does NOT cross a newline, and the pattern still matches ordinary text.
      p(/^\s*binding\.(pry|irb)\s*$/s =~ "  binding.pry  ")
      p(/a.b/s =~ "a\nb")
      p(/a.b/m =~ "a\nb")

      # ... and it composes with the flags that do change matching.
      p(/A/ie =~ "a")
      p(/A B/xu =~ "AB")
      p(/a.b/mn =~ "a\nb")

      # The letter survives onto an INTERPOLATED literal too.
      part = "b"
      re = /a#{part}c/u
      p [re.options, re.encoding, re.fixed_encoding?, re =~ "abc"]

      # `Regexp.new` has no spelling for these letters, so a runtime-built regexp is
      # never encoding-pinned.
      built = Regexp.new("x")
      p [built.options, built.encoding, built.fixed_encoding?]

      # `#source` is the pattern alone -- the flags are not part of it.
      p [/x/e.source, /x/imx.source]

      # `#inspect` puts back only `n`, and sorts it after m/i/x. The other three
      # print bare: the encoding rides on the object, not on its printed source.
      p [/x/n.inspect, /x/e.inspect, /x/s.inspect, /x/u.inspect]
      p [/x/mix.inspect, /x/mixn.inspect, /x/nm.inspect]

      # `#to_s` -- the embeddable `(?flags-flags:...)` form -- carries none of them.
      p [/x/n.to_s, /x/e.to_s, /x/mi.to_s]
    RUBY

    _(result).must_answer <<~'OUT'
      [32, 16, 16, 16]
      [0, 1, 2, 4, 7]
      [33, 20, 18]
      [32, 16, 16, 16]
      [#<Encoding:EUC-JP>, #<Encoding:Windows-31J>, #<Encoding:UTF-8>, #<Encoding:US-ASCII>, #<Encoding:US-ASCII>]
      [true, true, true]
      [false, false]
      [true, #<Encoding:UTF-8>]
      0
      nil
      0
      0
      0
      0
      [16, #<Encoding:UTF-8>, true, 0]
      [0, #<Encoding:US-ASCII>, false]
      ["x", "x"]
      ["/x/n", "/x/", "/x/", "/x/"]
      ["/x/mix", "/x/mixn", "/x/mn"]
      ["(?-mix:x)", "(?-mix:x)", "(?mi-x:x)"]
    OUT
  end

  it "__ENCODING__ is an Encoding value, so it compares and keys a hash as one" do
    result = ze0(<<~'RUBY')
      # Issue #843. `__ENCODING__` should behave like an Encoding value,
      # not a plain String.

      puts __ENCODING__.class
      puts __ENCODING__.name
      puts __ENCODING__.to_s
      puts __ENCODING__.is_a?(Encoding)
      puts __ENCODING__ == __ENCODING__
      puts __ENCODING__ != "UTF-8"

      values = [__ENCODING__, 1]
      puts values[0]

      enc_hash = {}
      enc_hash[__ENCODING__] = 7
      puts enc_hash[__ENCODING__]

      mixed = ARGV.length > 0 ? __ENCODING__ : 1
      puts mixed
    RUBY

    _(result).must_answer <<~'OUT'
      Encoding
      UTF-8
      UTF-8
      true
      true
      true
      UTF-8
      7
      1
    OUT
  end

  it "string encoding preserved" do
    result = ze0(<<~'RUBY')
      # A derived string keeps the RECEIVER's encoding and its raw bytes.
      #
      # The strip/pad/chop/tr/delete/squeeze family used to compute over
      # `to_utf8_lossy` text and rebuild with `str_value`, which tags UTF-8 -- so
      # `"caf\xE9".force_encoding("ISO-8859-1").strip` came back UTF-8 with `é` as
      # two bytes where ruby keeps ISO-8859-1 and one. `chars`/`each_char` slice the
      # raw bytes instead of decoding, and `codepoints` answers the number the
      # receiver's own encoding gives a character, not the Unicode scalar.

      def show(label)
        v = yield
        s = v.is_a?(String) ? "#{v.encoding} #{v.bytes.inspect}" : v.inspect
        puts "#{label}\t#{s}"
      end

      {
        "latin1" => "caf\xE9 x".dup.force_encoding("ISO-8859-1"),
        "binary" => "caf\xE9 x".dup.force_encoding("ASCII-8BIT"),
        "koi8"   => "\xC1\xC2 x".dup.force_encoding("KOI8-R"),
        "eucjp"  => "\xA4\xA2\xA4\xA4 x".dup.force_encoding("EUC-JP"),
      }.each do |k, s|
        show("#{k}/strip")      { s.strip }
        show("#{k}/lstrip")     { s.lstrip }
        show("#{k}/rstrip")     { s.rstrip }
        show("#{k}/chop")       { s.chop }
        show("#{k}/center9")    { s.center(9, ".") }
        show("#{k}/ljust9")     { s.ljust(9, ".") }
        show("#{k}/rjust9")     { s.rjust(9, ".") }
        show("#{k}/delete_x")   { s.delete("x") }
        show("#{k}/squeeze")    { s.squeeze }
        show("#{k}/tr")         { s.tr("x", "z") }
        # Printed directly, not through `show`: `show` reports its argument's own
        # encoding, and `Array#inspect` answers US-ASCII in ruby where zeo answers
        # UTF-8 -- a separate divergence this test is not about.
        puts "#{k}/chars\t#{s.chars.map { |c| "#{c.encoding} #{c.bytes.inspect}" }}"
        puts "#{k}/codepoints\t#{s.codepoints}"
      end

      # The regexp-backed family: every field and every match is a slice of the
      # receiver's own text, so it carries the receiver's encoding even though the
      # splitter and the regexp engine both work in decoded UTF-8.
      {
        "latin1" => "caf\xE9 x".dup.force_encoding("ISO-8859-1"),
        "binary" => "caf\xE9 x".dup.force_encoding("ASCII-8BIT"),
        "koi8"   => "\xC1\xC2 x".dup.force_encoding("KOI8-R"),
        "eucjp"  => "\xA4\xA2\xA4\xA4 x".dup.force_encoding("EUC-JP"),
      }.each do |k, s|
        show("#{k}/sub")   { s.sub("x", "y") }
        show("#{k}/gsub")  { s.gsub("x", "y") }
        show("#{k}/sub_re") { s.sub(/x/, "y") }
        puts "#{k}/split_sp\t#{s.split(" ").map { |f| "#{f.encoding} #{f.bytes.inspect}" }}"
        puts "#{k}/split_empty\t#{s.split("").map { |f| "#{f.encoding} #{f.bytes.inspect}" }}"
        puts "#{k}/scan\t#{s.scan(/x/).map { |f| "#{f.encoding} #{f.bytes.inspect}" }}"
      end

      # Match groups are slices of the receiver's own text, so they carry the
      # receiver's encoding: the engine decodes to UTF-8 and MatchData remembers
      # what it decoded FROM.
      {
        "latin1" => "caf\xE9 x".dup.force_encoding("ISO-8859-1"),
        "koi8"   => "\xC1\xC2 x".dup.force_encoding("KOI8-R"),
        "eucjp"  => "\xA4\xA2\xA4\xA4 x".dup.force_encoding("EUC-JP"),
      }.each do |k, s|
        show("#{k}/match0")   { s.match(/x/)[0] }
        show("#{k}/match_pre") { s.match(/x/).pre_match }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      latin1/strip	ISO-8859-1 [99, 97, 102, 233, 32, 120]
      latin1/lstrip	ISO-8859-1 [99, 97, 102, 233, 32, 120]
      latin1/rstrip	ISO-8859-1 [99, 97, 102, 233, 32, 120]
      latin1/chop	ISO-8859-1 [99, 97, 102, 233, 32]
      latin1/center9	ISO-8859-1 [46, 99, 97, 102, 233, 32, 120, 46, 46]
      latin1/ljust9	ISO-8859-1 [99, 97, 102, 233, 32, 120, 46, 46, 46]
      latin1/rjust9	ISO-8859-1 [46, 46, 46, 99, 97, 102, 233, 32, 120]
      latin1/delete_x	ISO-8859-1 [99, 97, 102, 233, 32]
      latin1/squeeze	ISO-8859-1 [99, 97, 102, 233, 32, 120]
      latin1/tr	ISO-8859-1 [99, 97, 102, 233, 32, 122]
      latin1/chars	["ISO-8859-1 [99]", "ISO-8859-1 [97]", "ISO-8859-1 [102]", "ISO-8859-1 [233]", "ISO-8859-1 [32]", "ISO-8859-1 [120]"]
      latin1/codepoints	[99, 97, 102, 233, 32, 120]
      binary/strip	ASCII-8BIT [99, 97, 102, 233, 32, 120]
      binary/lstrip	ASCII-8BIT [99, 97, 102, 233, 32, 120]
      binary/rstrip	ASCII-8BIT [99, 97, 102, 233, 32, 120]
      binary/chop	ASCII-8BIT [99, 97, 102, 233, 32]
      binary/center9	ASCII-8BIT [46, 99, 97, 102, 233, 32, 120, 46, 46]
      binary/ljust9	ASCII-8BIT [99, 97, 102, 233, 32, 120, 46, 46, 46]
      binary/rjust9	ASCII-8BIT [46, 46, 46, 99, 97, 102, 233, 32, 120]
      binary/delete_x	ASCII-8BIT [99, 97, 102, 233, 32]
      binary/squeeze	ASCII-8BIT [99, 97, 102, 233, 32, 120]
      binary/tr	ASCII-8BIT [99, 97, 102, 233, 32, 122]
      binary/chars	["ASCII-8BIT [99]", "ASCII-8BIT [97]", "ASCII-8BIT [102]", "ASCII-8BIT [233]", "ASCII-8BIT [32]", "ASCII-8BIT [120]"]
      binary/codepoints	[99, 97, 102, 233, 32, 120]
      koi8/strip	KOI8-R [193, 194, 32, 120]
      koi8/lstrip	KOI8-R [193, 194, 32, 120]
      koi8/rstrip	KOI8-R [193, 194, 32, 120]
      koi8/chop	KOI8-R [193, 194, 32]
      koi8/center9	KOI8-R [46, 46, 193, 194, 32, 120, 46, 46, 46]
      koi8/ljust9	KOI8-R [193, 194, 32, 120, 46, 46, 46, 46, 46]
      koi8/rjust9	KOI8-R [46, 46, 46, 46, 46, 193, 194, 32, 120]
      koi8/delete_x	KOI8-R [193, 194, 32]
      koi8/squeeze	KOI8-R [193, 194, 32, 120]
      koi8/tr	KOI8-R [193, 194, 32, 122]
      koi8/chars	["KOI8-R [193]", "KOI8-R [194]", "KOI8-R [32]", "KOI8-R [120]"]
      koi8/codepoints	[193, 194, 32, 120]
      eucjp/strip	EUC-JP [164, 162, 164, 164, 32, 120]
      eucjp/lstrip	EUC-JP [164, 162, 164, 164, 32, 120]
      eucjp/rstrip	EUC-JP [164, 162, 164, 164, 32, 120]
      eucjp/chop	EUC-JP [164, 162, 164, 164, 32]
      eucjp/center9	EUC-JP [46, 46, 164, 162, 164, 164, 32, 120, 46, 46, 46]
      eucjp/ljust9	EUC-JP [164, 162, 164, 164, 32, 120, 46, 46, 46, 46, 46]
      eucjp/rjust9	EUC-JP [46, 46, 46, 46, 46, 164, 162, 164, 164, 32, 120]
      eucjp/delete_x	EUC-JP [164, 162, 164, 164, 32]
      eucjp/squeeze	EUC-JP [164, 162, 164, 164, 32, 120]
      eucjp/tr	EUC-JP [164, 162, 164, 164, 32, 122]
      eucjp/chars	["EUC-JP [164, 162]", "EUC-JP [164, 164]", "EUC-JP [32]", "EUC-JP [120]"]
      eucjp/codepoints	[42146, 42148, 32, 120]
      latin1/sub	ISO-8859-1 [99, 97, 102, 233, 32, 121]
      latin1/gsub	ISO-8859-1 [99, 97, 102, 233, 32, 121]
      latin1/sub_re	ISO-8859-1 [99, 97, 102, 233, 32, 121]
      latin1/split_sp	["ISO-8859-1 [99, 97, 102, 233]", "ISO-8859-1 [120]"]
      latin1/split_empty	["ISO-8859-1 [99]", "ISO-8859-1 [97]", "ISO-8859-1 [102]", "ISO-8859-1 [233]", "ISO-8859-1 [32]", "ISO-8859-1 [120]"]
      latin1/scan	["ISO-8859-1 [120]"]
      binary/sub	ASCII-8BIT [99, 97, 102, 233, 32, 121]
      binary/gsub	ASCII-8BIT [99, 97, 102, 233, 32, 121]
      binary/sub_re	ASCII-8BIT [99, 97, 102, 233, 32, 121]
      binary/split_sp	["ASCII-8BIT [99, 97, 102, 233]", "ASCII-8BIT [120]"]
      binary/split_empty	["ASCII-8BIT [99]", "ASCII-8BIT [97]", "ASCII-8BIT [102]", "ASCII-8BIT [233]", "ASCII-8BIT [32]", "ASCII-8BIT [120]"]
      binary/scan	["ASCII-8BIT [120]"]
      koi8/sub	KOI8-R [193, 194, 32, 121]
      koi8/gsub	KOI8-R [193, 194, 32, 121]
      koi8/sub_re	KOI8-R [193, 194, 32, 121]
      koi8/split_sp	["KOI8-R [193, 194]", "KOI8-R [120]"]
      koi8/split_empty	["KOI8-R [193]", "KOI8-R [194]", "KOI8-R [32]", "KOI8-R [120]"]
      koi8/scan	["KOI8-R [120]"]
      eucjp/sub	EUC-JP [164, 162, 164, 164, 32, 121]
      eucjp/gsub	EUC-JP [164, 162, 164, 164, 32, 121]
      eucjp/sub_re	EUC-JP [164, 162, 164, 164, 32, 121]
      eucjp/split_sp	["EUC-JP [164, 162, 164, 164]", "EUC-JP [120]"]
      eucjp/split_empty	["EUC-JP [164, 162]", "EUC-JP [164, 164]", "EUC-JP [32]", "EUC-JP [120]"]
      eucjp/scan	["EUC-JP [120]"]
      latin1/match0	ISO-8859-1 [120]
      latin1/match_pre	ISO-8859-1 [99, 97, 102, 233, 32]
      koi8/match0	KOI8-R [120]
      koi8/match_pre	KOI8-R [193, 194, 32]
      eucjp/match0	EUC-JP [120]
      eucjp/match_pre	EUC-JP [164, 162, 164, 164, 32]
    OUT
  end

  it "string inspect invalid utf8" do
    result = ze0(<<~'RUBY')
      # String#inspect escapes a byte that is not part of a valid UTF-8 sequence as
      # \xNN, the way CRuby renders it. Passing the raw byte through made the inspect
      # output itself invalid UTF-8, so a terminal drew U+FFFD -- inspect lost the one
      # thing it was being asked about. Found while sweeping the nil-sentinel receiver
      # surface, where 128.chr.inspect was the odd answer out.

      # invalid bytes, alone and embedded
      p "a\x80b"
      p "a\xffb"
      p "\xc3"
      p "\xe3\x81"
      p "\x80"
      p "\xff\xfe"

      # valid sequences still pass through unchanged
      p "café"
      p "é"
      p "日本語"
      p "\u{1F600}"
      p "abc"
      p "a\tb\nc"

      # a BINARY string escapes every high byte
      p [200, 300].pack("C*")
      p "abc".b

      # the escaped form does not change the string itself
      p "a\x80b".bytes
      p "a\x80b".bytesize
      p "café".bytes
    RUBY

    _(result).must_answer <<~'OUT'
      "a\x80b"
      "a\xFFb"
      "\xC3"
      "\xE3\x81"
      "\x80"
      "\xFF\xFE"
      "café"
      "é"
      "日本語"
      "😀"
      "abc"
      "a\tb\nc"
      "\xC8,"
      "abc"
      [97, 128, 98]
      3
      [99, 97, 102, 195, 169]
    OUT
  end

  it "string lshift int codepoint" do
    result = ze0(<<~'RUBY')
      # Issue #882: `s << int` appends the UTF-8 character with that
      # codepoint (per MRI). Previously appended the integer's decimal
      # digits.
      s = String.new("hello")
      s << 33
      puts s.inspect
      s2 = String.new("ab")
      s2 << 12354
      puts s2.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "hello!"
      "abあ"
    OUT
  end

  it "string scrub" do
    result = ze0(<<~'RUBY')
      # String#scrub replaces invalid UTF-8 bytes with the given
      # replacement (or U+FFFD by default).
      puts "\xff".scrub("?")
      puts "a\xffb".scrub("?")
      puts "valid".scrub("?")
      # Default replacement (U+FFFD = "\xEF\xBF\xBD") is 3 bytes.
      puts "\xff".scrub.bytes.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      ?
      a?b
      valid
      [239, 191, 189]
    OUT
  end

  it "symbol inspect nonascii" do
    result = ze0(<<~'RUBY')
      p :café
      p :café.inspect
      v = :café; p v
      p :λ
      p :"a b"
      p :"1a"
      p :"😀"
      p :café.upcase
      h = { café: 1 }
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      :café
      ":café"
      :café
      :λ
      :"a b"
      :"1a"
      :😀
      :CAFÉ
      {café: 1}
    OUT
  end
end
