# frozen_string_literal: true

require "spec_helper"

describe "Encoding: packing and unpacking" do
  it "array combinatorics and binary search" do
    result = ze0(<<~'RUBY')
      p [1, 2, 3].combination(2).to_a
      p [1, 2, 3].combination(0).to_a
      p [1, 2, 3].combination(4).to_a
      p [1, 2, 3].permutation(2).to_a
      p [1, 2].permutation.to_a
      r = []
      [1, 2, 3].combination(2) { |c| r << c }
      p r
      p [1, 2, 3].each_index.to_a
      p [1, 2, 3, 4].bsearch { |x| x >= 3 }
      p [1, 2, 3, 4].bsearch { |x| x >= 9 }
      p [1, 2, 3, 4].bsearch_index { |x| x >= 3 }
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [1, 3], [2, 3]]
      [[]]
      []
      [[1, 2], [1, 3], [2, 1], [2, 3], [3, 1], [3, 2]]
      [[1, 2], [2, 1]]
      [[1, 2], [1, 3], [2, 3]]
      [0, 1, 2]
      3
      nil
      2
    OUT
  end

  it "big5 refuses cyrillic" do
    result = ze0(<<~'RUBY')
      # Encoding Cyrillic to Big5: CRuby's strict Big5 has no Cyrillic rows and
      # refuses with UndefinedConversionError; zeo's WHATWG table maps them (the
      # HKSCS-adjacent region), so it encodes MORE than ruby. The inverse
      # direction of the decided Big5-HKSCS divergence in docs/COMPATIBILITY.md.
      # (Found by the 2026-08-24 probe sweep.)
      begin
        p "Жи".encode("Big5").unpack1("H*")
      rescue Encoding::UndefinedConversionError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer "Encoding::UndefinedConversionError: U+0416 from UTF-8 to Big5\n"
  end

  it "binary read mode encoding" do
    result = ze0(<<~'RUBY')
      require "tmpdir"

      Dir.mktmpdir do |d|
        f = File.join(d, "m.txt")
        File.write(f, "abc")
        p File.open(f, "rb") { |io| io.read.encoding.name }
        p File.open(f, "r", encoding: "BINARY") { |io| io.read.encoding.name }
        p File.binread(f).encoding.name
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "ASCII-8BIT"
      "ASCII-8BIT"
      "ASCII-8BIT"
    OUT
  end

  it "binary string fidelity" do
    result = ze0(<<~'RUBY')
      # Binary strings must survive every operation that copies or moves them.
      #
      # This is a REGRESSION SUITE for one recurring defect, not a feature test.
      # Several methods used to rebuild a String from its "display text" -- decoding
      # the bytes as UTF-8 and re-encoding them -- which silently rewrites any byte
      # that isn't valid UTF-8. It corrupts both ways:
      #
      #   0x8b  ->  0xEF 0xBF 0xBD   (lossy decode: replaced with U+FFFD)
      #   0x8b  ->  0xC2 0x8B        (Latin-1 promotion: re-encoded, length changed)
      #
      # It has been found and fixed in `String#+`, `Array#join`, `String#dup`,
      # `StringIO`, and `IO#read` at different times. Each fix without a test let the
      # next one through, so every operation that touches bytes is pinned here.
      #
      # The bytes below are a real gzip header: 0x8b and 0xc8 are both invalid UTF-8
      # on their own, which is what makes them the case that catches this.
      RAW = [0x1f, 0x8b, 0x08, 0x00, 0xc8].pack("C*")

      def show(label)
        print "#{label}: "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      show("pack") { [RAW.bytes, RAW.encoding.to_s, RAW.bytesize] }

      # Copying.
      show("dup") { RAW.dup.bytes }
      show("clone") { RAW.clone.bytes }
      show("dup encoding") { RAW.dup.encoding.to_s }
      show("+@") { (+RAW).bytes }

      # Concatenation and splitting.
      show("plus") { (RAW[0, 2] + RAW[2..]).bytes }
      show("join") { [RAW[0, 2], RAW[2..]].join.bytes }
      show("join nested") { [[RAW[0, 2]], [RAW[2..]]].join.bytes }
      show("join separator") { [RAW[0, 1], RAW[1, 1]].join(RAW[4, 1]).bytes }
      show("slice") { RAW[1, 3].bytes }
      show("each_byte") { RAW.each_byte.to_a }
      show("bytes reverse") { RAW.reverse.bytes }
      show("append") { (+"").tap { |s| s << RAW }.bytes }
      show("multiply") { (RAW[1, 1] * 3).bytes }

      # In-place byte edits.
      show("setbyte") { RAW.dup.tap { |s| s.setbyte(4, 0x37) }.bytes }
      show("getbyte") { [RAW.getbyte(1), RAW.getbyte(4)] }

      # Arrays and hashes carrying binary values.
      show("array round-trip") { [RAW].first.bytes }
      show("hash value") { { k: RAW }[:k].bytes }
      show("array pack/unpack") { RAW.unpack("C*").pack("C*").bytes }

      # Files, both APIs.
      show("binwrite/binread") do
        File.binwrite("binary_fidelity_tmp.bin", RAW)
        File.binread("binary_fidelity_tmp.bin").bytes
      end
      show("File#write then #read") do
        File.open("binary_fidelity_tmp.bin", "wb") { |f| f.write(RAW) }
        File.open("binary_fidelity_tmp.bin", "rb") { |f| f.read.bytes }
      end
      show("File#read(n)") do
        File.open("binary_fidelity_tmp.bin", "rb") { |f| f.read(3).bytes }
      end
      show("File#read(n) encoding") do
        File.open("binary_fidelity_tmp.bin", "rb") { |f| f.read(3).encoding.to_s }
      ensure
        File.unlink("binary_fidelity_tmp.bin")
      end

      # StringIO, which is a byte buffer that has to remember what its bytes mean.
      require "stringio"
      show("StringIO string") { StringIO.new(RAW).string.bytes }
      show("StringIO read") { StringIO.new(RAW).read.bytes }
      show("StringIO read enc") { StringIO.new(RAW).read.encoding.to_s }
      show("StringIO read(n)") { StringIO.new(RAW).read(3).bytes }
      show("StringIO read(n) enc") { StringIO.new(RAW).read(3).encoding.to_s }
      show("StringIO getc") { StringIO.new(RAW).getc.bytes }
      show("StringIO write") { StringIO.new("".b).tap { |io| io.write(RAW) }.string.bytes }
      show("StringIO gets") { StringIO.new(RAW + "\n".b).gets.bytes }
      show("StringIO readlines") { StringIO.new(RAW).readlines.map(&:bytes) }

      # A UTF-8 buffer must keep ITS encoding and its character boundaries -- the
      # fixes above must not have turned everything into bytes.
      show("utf8 StringIO getc") { StringIO.new("éa").getc }
      show("utf8 StringIO read enc") { StringIO.new("éa").read.encoding.to_s }
      show("utf8 dup") { "é".dup.encoding.to_s }
      show("utf8 join") { ["é", "a"].join }
    RUBY

    _(result).must_answer <<~'OUT'
      pack: [[31, 139, 8, 0, 200], "ASCII-8BIT", 5]
      dup: [31, 139, 8, 0, 200]
      clone: [31, 139, 8, 0, 200]
      dup encoding: "ASCII-8BIT"
      +@: [31, 139, 8, 0, 200]
      plus: [31, 139, 8, 0, 200]
      join: [31, 139, 8, 0, 200]
      join nested: [31, 139, 8, 0, 200]
      join separator: [31, 200, 139]
      slice: [139, 8, 0]
      each_byte: [31, 139, 8, 0, 200]
      bytes reverse: [200, 0, 8, 139, 31]
      append: [31, 139, 8, 0, 200]
      multiply: [139, 139, 139]
      setbyte: [31, 139, 8, 0, 55]
      getbyte: [139, 200]
      array round-trip: [31, 139, 8, 0, 200]
      hash value: [31, 139, 8, 0, 200]
      array pack/unpack: [31, 139, 8, 0, 200]
      binwrite/binread: [31, 139, 8, 0, 200]
      File#write then #read: [31, 139, 8, 0, 200]
      File#read(n): [31, 139, 8]
      File#read(n) encoding: "ASCII-8BIT"
      StringIO string: [31, 139, 8, 0, 200]
      StringIO read: [31, 139, 8, 0, 200]
      StringIO read enc: "ASCII-8BIT"
      StringIO read(n): [31, 139, 8]
      StringIO read(n) enc: "ASCII-8BIT"
      StringIO getc: [31]
      StringIO write: [31, 139, 8, 0, 200]
      StringIO gets: [31, 139, 8, 0, 200, 10]
      StringIO readlines: [[31, 139, 8, 0, 200]]
      utf8 StringIO getc: "é"
      utf8 StringIO read enc: "UTF-8"
      utf8 dup: "UTF-8"
      utf8 join: "éa"
    OUT
  end

  it "binary string length bytes" do
    result = ze0(<<~'RUBY')
      # A binary string (invalid UTF-8, e.g. a binary-mode read) counts its length in
      # bytes (Ruby ASCII-8BIT semantics), matching bytesize -- not UTF-8 codepoints.
      bin = [0x00, 0x80, 0xC0, 0xFF, 0x41, 0xFE].pack('C*')
      puts "size=#{bin.size} bytesize=#{bin.bytesize}"
      # valid UTF-8 text still counts codepoints
      txt = "abc"
      puts "txt size=#{txt.size} bytesize=#{txt.bytesize}"
      # valid *multibyte* UTF-8: size counts codepoints while bytesize counts bytes,
      # so the two must differ -- this exercises the char-count path (unlike ASCII,
      # where size == bytesize would pass either way).
      snow = "☃"          # snowman, one codepoint, three UTF-8 bytes
      puts "snow size=#{snow.size} bytesize=#{snow.bytesize}"
      acc = "café"        # "cafe" with an accent: four codepoints, five bytes
      puts "acc size=#{acc.size} bytesize=#{acc.bytesize}"
      mix = "aé☃z"   # ascii + 2-byte + 3-byte + ascii = 4 chars, 7 bytes
      puts "mix size=#{mix.size} bytesize=#{mix.bytesize}"
      # a longer binary blob
      blob = ([0xAA] * 100).pack('C*')
      puts "blob size=#{blob.size}"
    RUBY

    _(result).must_answer <<~'OUT'
      size=6 bytesize=6
      txt size=3 bytesize=3
      snow size=1 bytesize=3
      acc size=4 bytesize=5
      mix size=4 bytesize=7
      blob size=100
    OUT
  end

  it "binmode means binary" do
    result = ze0(<<~'RUBY')
      # `#binmode` is not a no-op. The newline half of binary mode is one on
      # Unix, which is presumably why this looked harmless -- but the ENCODING
      # half is not: CRuby's `rb_io_binmode` and `strio_binmode` retag the stream
      # ASCII-8BIT, and a caller binmodes a stream precisely so that nothing
      # interprets the bytes.
      #
      # The second rule here is `external_encoding`'s: CRuby asks WRITABLE, not
      # write-only, so a stream opened `"w+"` (every Tempfile) answers nil until
      # something says what its bytes are to be read as.
      require "stringio"
      require "tempfile"
      s = StringIO.new("héllo")
      p [s.external_encoding.to_s, s.string.encoding.to_s]
      s.binmode
      p [s.external_encoding.to_s, s.read.encoding.to_s, s.string.encoding.to_s]
      s.rewind
      p s.read.bytes.length
      w = StringIO.new(+"")
      w.binmode
      w.write("é")
      p [w.string.encoding.to_s, w.string.bytesize]
      f = Tempfile.new("zeo_binmode")
      f.write("é")
      f.flush
      f.rewind
      p [f.external_encoding.to_s, f.read.encoding.to_s]
      f.rewind
      f.binmode
      p [f.external_encoding.to_s, f.internal_encoding.inspect, f.read.encoding.to_s, f.binmode?]
      f.close!
      g = File.open("/tmp/zeo_binmode_golden.bin", "wb")
      g.write("\xff\xfe".b)
      g.close
      p File.binread("/tmp/zeo_binmode_golden.bin").encoding.to_s
      h = File.open("/tmp/zeo_binmode_golden.bin")
      h.binmode
      p [h.external_encoding.to_s, h.read.encoding.to_s]
      h.close
      File.delete("/tmp/zeo_binmode_golden.bin")
    RUBY

    _(result).must_answer <<~'OUT'
      ["UTF-8", "UTF-8"]
      ["ASCII-8BIT", "ASCII-8BIT", "ASCII-8BIT"]
      6
      ["ASCII-8BIT", 2]
      ["", "UTF-8"]
      ["ASCII-8BIT", "nil", "ASCII-8BIT", true]
      "ASCII-8BIT"
      ["ASCII-8BIT", "ASCII-8BIT"]
    OUT
  end

  it "carriers exchange emoji in one step" do
    result = ze0(<<~'RUBY')
      # The carriers' UTF-8 encodings exchange their emoji with each other and
      # with Unicode in one step, and a failure words them as ruby does.
      def t(s, to, **o)
        r = s.encode(to, **o)
        p [r.encoding.name, r.b]
      rescue => e
        p [e.class, e.message, (e.error_bytes rescue nil), (e.error_char rescue nil), (e.source_encoding_name rescue nil), (e.destination_encoding_name rescue nil)]
      end
      d = ->(s) { s.b.force_encoding("UTF8-DoCoMo") }
      k = ->(s) { s.b.force_encoding("UTF8-KDDI") }
      t "\u{1F4A9}", "UTF8-DoCoMo"
      t d["\u{E6A0}"], "UTF-8"
      t d["\u{E6A0}"], "UTF8-KDDI"
      t d["\u{E6A0}"], "UTF8-KDDI", undef: :replace
      t d["\u{E6A0}"], "EUC-JP"
      t d["\u{E63E}"], "EUC-JP"
      t d["\u{E63E}"], "Shift_JIS"
      t d["a\xFFb"], "UTF-8"
      t d["a\xFFb"], "UTF8-KDDI"
      t d["a\xE3\x81"], "UTF8-KDDI"
      t "a\xFFb", "UTF8-KDDI"
      t "a\xFF\u{1F4A9}", "UTF8-KDDI", invalid: :replace, undef: :replace
      t "\u{1F4A9}", "UTF8-DoCoMo", undef: :replace, replace: "X"
      t "\u{1F4A9}", "UTF8-DoCoMo", fallback: {"\u{1F4A9}" => "P"}
      t "日\u{2600}", "UTF8-SoftBank", xml: :text
      t "\u{1F4A9}<", "UTF8-DoCoMo", xml: :text
      t k["\u{E488}\u{E4F5}"], "UTF-8"

    RUBY

    _(result).must_answer <<~'OUT'
      [Encoding::UndefinedConversionError, "U+1F4A9 from UTF-8 to UTF8-DoCoMo", nil, "💩", "UTF-8", "UTF8-DoCoMo"]
      [Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" from UTF8-DoCoMo to UTF-8", nil, "\uE6A0", "UTF8-DoCoMo", "UTF-8"]
      [Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" from UTF8-DoCoMo to UTF8-KDDI", nil, "\uE6A0", "UTF8-DoCoMo", "UTF8-KDDI"]
      ["UTF8-KDDI", "?"]
      [Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF-8 in conversion from UTF8-DoCoMo to UTF-8 to EUC-JP", nil, "\uE6A0", "UTF8-DoCoMo", "UTF-8"]
      [Encoding::UndefinedConversionError, "U+2600 to EUC-JP in conversion from UTF8-DoCoMo to UTF-8 to EUC-JP", nil, "☀", "UTF-8", "EUC-JP"]
      [Encoding::UndefinedConversionError, "U+2600 to Shift_JIS in conversion from UTF8-DoCoMo to UTF-8 to Shift_JIS", nil, "☀", "UTF-8", "Shift_JIS"]
      [Encoding::InvalidByteSequenceError, "\"\\xFF\" on UTF8-DoCoMo", "\xFF", nil, "UTF8-DoCoMo", "UTF-8"]
      [Encoding::InvalidByteSequenceError, "\"\\xFF\" on UTF8-DoCoMo", "\xFF", nil, "UTF8-DoCoMo", "UTF8-KDDI"]
      [Encoding::InvalidByteSequenceError, "incomplete \"\\xE3\\x81\" on UTF8-DoCoMo", "\xE3\x81", nil, "UTF8-DoCoMo", "UTF8-KDDI"]
      [Encoding::InvalidByteSequenceError, "\"\\xFF\" on UTF-8", "\xFF", nil, "UTF-8", "UTF8-KDDI"]
      ["UTF8-KDDI", "a?\xEE\x93\xB5"]
      ["UTF8-DoCoMo", "X"]
      ["UTF8-DoCoMo", "P"]
      ["UTF8-SoftBank", "\xE6\x97\xA5\xEE\x81\x8A"]
      ["UTF8-DoCoMo", "&#x1F4A9;&lt;"]
      [Encoding::UndefinedConversionError, "\"\\xEE\\x93\\xB5\" from UTF8-KDDI to UTF-8", nil, "\uE4F5", "UTF8-KDDI", "UTF-8"]
    OUT
  end

  it "carriers shift jis converts through their utf8" do
    skip "the carrier tables hold Unicode's code points, so an emoji with no Unicode one stops mid-conversion"

    result = ze0(<<~'RUBY')

      # Ruby converts SJIS-DoCoMo, SJIS-KDDI, SJIS-SoftBank and
      # stateless-ISO-2022-JP-KDDI through the carrier's own UTF-8, whose emoji
      # are private-use code points: an emoji with no Unicode one still crosses
      # between them, and a failure names each step. This runtime's tables for
      # them hold Unicode's code points, read through UTF-8, so such an emoji
      # stops, and a failure names one step.
      def t(s, to, **o)
        r = s.encode(to, **o)
        p [r.encoding.name, r.b]
      rescue => e
        p [e.class, e.message, (e.error_bytes rescue nil), (e.error_char rescue nil), e.source_encoding_name, e.destination_encoding_name]
      end
      full_moon = "\u{E6A0}".encode("UTF8-DoCoMo", "UTF-8").encode("SJIS-DoCoMo")
      p full_moon.b
      t full_moon, "UTF-8"
      t full_moon, "UTF8-DoCoMo"
      t full_moon, "UTF8-KDDI"
      t full_moon, "EUC-JP"
      t full_moon, "SJIS-KDDI"
      t "\u{1F4A9}", "SJIS-DoCoMo"
      t "é", "SJIS-DoCoMo"
      t "é", "SJIS-KDDI"
      t "é", "SJIS-SoftBank"
      t "\xFF".b.force_encoding("SJIS-DoCoMo"), "UTF-8"
      t "\x81".b.force_encoding("SJIS-DoCoMo"), "UTF-8"
      t "é".encode("EUC-JP"), "SJIS-DoCoMo" rescue p $!
      t "ア".encode("EUC-JP"), "SJIS-DoCoMo"
      t "\u{E6A0}".b.force_encoding("UTF8-DoCoMo"), "SJIS-DoCoMo"
      t "\u{E6A0}".b.force_encoding("UTF8-DoCoMo"), "stateless-ISO-2022-JP-KDDI"
      t "é", "stateless-ISO-2022-JP-KDDI"
      t "\u{1F4A9}", "stateless-ISO-2022-JP-KDDI"
      t "\x92\xF5\xC1".b.force_encoding("stateless-ISO-2022-JP-KDDI"), "UTF-8"
      t "\x92\xFF\xC1".b.force_encoding("stateless-ISO-2022-JP-KDDI"), "UTF-8"
      t "é", "SJIS-DoCoMo", undef: :replace
      t full_moon, "UTF-8", undef: :replace
      t full_moon, "UTF-8", fallback: ->(c) { p [c.encoding, c.b]; "M" }
      t "é", "SJIS-DoCoMo", fallback: ->(c) { p [c.encoding, c.b]; "E" }
      t "ア".encode("SJIS-KDDI"), "SJIS-DoCoMo"
      [full_moon, "日".encode("SJIS-DoCoMo")].each { |s| p Encoding::Converter.new(s.encoding, "UTF-8").convpath }
      p Encoding::Converter.search_convpath("SJIS-KDDI", "SJIS-DoCoMo")
      p Encoding::Converter.search_convpath("stateless-ISO-2022-JP-KDDI", "SJIS-KDDI")

    RUBY

    _(result).must_answer <<~'OUT'
      "\xF9D"
      [Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF-8 in conversion from SJIS-DoCoMo to UTF8-DOCOMO to UTF-8", nil, "\uE6A0", "UTF8-DoCoMo", "UTF-8"]
      ["UTF8-DoCoMo", "\xEE\x9A\xA0"]
      [Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF8-KDDI in conversion from SJIS-DoCoMo to UTF8-DOCOMO to UTF8-KDDI", nil, "\uE6A0", "UTF8-DoCoMo", "UTF8-KDDI"]
      [Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF-8 in conversion from SJIS-DoCoMo to UTF8-DOCOMO to UTF-8 to EUC-JP", nil, "\uE6A0", "UTF8-DoCoMo", "UTF-8"]
      [Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF8-KDDI in conversion from SJIS-DoCoMo to UTF8-DOCOMO to UTF8-KDDI to SJIS-KDDI", nil, "\uE6A0", "UTF8-DoCoMo", "UTF8-KDDI"]
      [Encoding::UndefinedConversionError, "U+1F4A9 to UTF8-DoCoMo in conversion from UTF-8 to UTF8-DoCoMo to SJIS-DOCOMO", nil, "💩", "UTF-8", "UTF8-DoCoMo"]
      [Encoding::UndefinedConversionError, "\"\\xC3\\xA9\" to SJIS-DOCOMO in conversion from UTF-8 to UTF8-DoCoMo to SJIS-DOCOMO", nil, "\u00E9", "UTF8-DOCOMO", "SJIS-DOCOMO"]
      [Encoding::UndefinedConversionError, "\"\\xC3\\xA9\" to SJIS-KDDI in conversion from UTF-8 to UTF8-KDDI to SJIS-KDDI", nil, "\u00E9", "UTF8-KDDI", "SJIS-KDDI"]
      [Encoding::UndefinedConversionError, "\"\\xC3\\xA9\" to SJIS-SoftBank in conversion from UTF-8 to UTF8-SoftBank to SJIS-SoftBank", nil, "\u00E9", "UTF8-SoftBank", "SJIS-SoftBank"]
      [Encoding::InvalidByteSequenceError, "\"\\xFF\" on SJIS-DOCOMO", "\xFF", nil, "SJIS-DOCOMO", "UTF8-DOCOMO"]
      [Encoding::InvalidByteSequenceError, "incomplete \"\\x81\" on SJIS-DOCOMO", "\x81", nil, "SJIS-DOCOMO", "UTF8-DOCOMO"]
      [Encoding::UndefinedConversionError, "\"\\xC3\\xA9\" to SJIS-DOCOMO in conversion from EUC-JP to UTF-8 to UTF8-DoCoMo to SJIS-DOCOMO", nil, "\u00E9", "UTF8-DOCOMO", "SJIS-DOCOMO"]
      ["SJIS-DoCoMo", "\x83A"]
      ["SJIS-DoCoMo", "\xF9D"]
      [Encoding::UndefinedConversionError, "\"\\xEE\\x9A\\xA0\" to UTF8-KDDI in conversion from UTF8-DoCoMo to UTF8-KDDI to stateless-ISO-2022-JP-KDDI", nil, "\uE6A0", "UTF8-DoCoMo", "UTF8-KDDI"]
      [Encoding::UndefinedConversionError, "\"\\xC3\\xA9\" to stateless-ISO-2022-JP-KDDI in conversion from UTF-8 to UTF8-KDDI to stateless-ISO-2022-JP-KDDI", nil, "\u00E9", "UTF8-KDDI", "stateless-ISO-2022-JP-KDDI"]
      ["stateless-ISO-2022-JP-KDDI", "\x92\xF6\xD0"]
      ["UTF-8", "\xE2\x98\x80"]
      [Encoding::InvalidByteSequenceError, "\"\\x92\" followed by \"\\xFF\" on stateless-ISO-2022-JP-KDDI", "\x92", nil, "stateless-ISO-2022-JP-KDDI", "UTF8-KDDI"]
      ["SJIS-DoCoMo", "?"]
      ["UTF-8", "\xEF\xBF\xBD"]
      [#<Encoding:UTF8-DoCoMo>, "\xEE\x9A\xA0"]
      ["UTF-8", "M"]
      [#<Encoding:UTF8-DoCoMo>, "\xC3\xA9"]
      ["SJIS-DoCoMo", "E"]
      ["SJIS-DoCoMo", "\x83A"]
      [[#<Encoding:SJIS-DoCoMo>, #<Encoding:UTF8-DoCoMo>], [#<Encoding:UTF8-DoCoMo>, #<Encoding:UTF-8>]]
      [[#<Encoding:SJIS-DoCoMo>, #<Encoding:UTF8-DoCoMo>], [#<Encoding:UTF8-DoCoMo>, #<Encoding:UTF-8>]]
      [[#<Encoding:SJIS-KDDI>, #<Encoding:UTF8-KDDI>], [#<Encoding:UTF8-KDDI>, #<Encoding:UTF8-DoCoMo>], [#<Encoding:UTF8-DoCoMo>, #<Encoding:SJIS-DoCoMo>]]
      [[#<Encoding:stateless-ISO-2022-JP-KDDI>, #<Encoding:UTF8-KDDI>], [#<Encoding:UTF8-KDDI>, #<Encoding:SJIS-KDDI>]]
    OUT
  end

  it "character a converter refuses is still one character" do
    result = ze0(<<~'RUBY')
      # Ruby answers two questions about a multibyte String from two tables, and
      # they disagree. Where a character ends comes from the encoding itself
      # (onigmo's mbclen), so CP51932 reads 8F A1 A1 as ONE character and calls
      # the String valid. What a character converts to comes from the
      # transcoder, and CP51932's has no 8F form at all: the conversion refuses
      # the 8F alone, and names that one byte. stateless-ISO-2022-JP does the
      # same the other way round, with a two-byte character its own converter
      # will not read.
      [["CP51932", "\x8F\xA1\xA1"], ["stateless-ISO-2022-JP", "\x81\xA0"]].each do |name, bytes|
        text = bytes.dup.force_encoding(name)
        p [name, text.length, text.valid_encoding?, text.bytes.size]
        begin
          text.encode("UTF-8")
        rescue Encoding::InvalidByteSequenceError => e
          puts "#{e.class}: #{e.message}"
          p [e.error_bytes, e.readagain_bytes, e.incomplete_input?]
        end
      end
      # A character the encoding holds and gives no code point is the other
      # failure, and it names the character, not the bytes.
      begin
        "\x8F\xA1\xA1".dup.force_encoding("EUC-JP").encode("UTF-8")
      rescue Encoding::UndefinedConversionError => e
        puts "#{e.class}: #{e.message}"
        p [e.error_char.bytes, e.source_encoding_name, e.destination_encoding_name]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      ["CP51932", 1, true, 3]
      Encoding::InvalidByteSequenceError: "\x8F" on CP51932
      ["\x8F", nil, false]
      ["stateless-ISO-2022-JP", 1, true, 2]
      Encoding::InvalidByteSequenceError: "\x81" on stateless-ISO-2022-JP
      ["\x81", nil, false]
      Encoding::UndefinedConversionError: "\x8F\xA1\xA1" from EUC-JP to UTF-8
      [[143, 161, 161], "EUC-JP", "UTF-8"]
    OUT
  end

  it "converter reads a stateful source in pieces" do
    result = ze0(<<~'RUBY')
      # A Converter reads a stateful source a piece at a time: an escape in one
      # piece sets how the bytes of the next one read.
      %w[ISO-2022-JP CP50220 CP50221 ISO-2022-JP-KDDI].each do |name|
        ec = Encoding::Converter.new(name, "UTF-8")
        p ec.convpath
        p ec.convert("a\e$BF|".b)
        p ec.convert("K\\\e(B".b)
        p ec.finish
        src = +"\e$BF|K\\\e(Bx\e$B".b
        dst = +""
        ec = Encoding::Converter.new(name, "UTF-8")
        p ec.primitive_convert(src, dst), dst, src, ec.primitive_errinfo
      rescue => e
        p e
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [[#<Encoding:ISO-2022-JP (dummy)>, #<Encoding:stateless-ISO-2022-JP>], [#<Encoding:stateless-ISO-2022-JP>, #<Encoding:EUC-JP>], [#<Encoding:EUC-JP>, #<Encoding:UTF-8>]]
      "a日"
      "本"
      ""
      :finished
      "日本x"
      ""
      [:finished, nil, nil, nil, nil]
      [[#<Encoding:CP50220 (dummy)>, #<Encoding:CP51932>], [#<Encoding:CP51932>, #<Encoding:UTF-8>]]
      "a日"
      "本"
      ""
      :finished
      "日本x"
      ""
      [:finished, nil, nil, nil, nil]
      [[#<Encoding:CP50221 (dummy)>, #<Encoding:CP51932>], [#<Encoding:CP51932>, #<Encoding:UTF-8>]]
      "a日"
      "本"
      ""
      :finished
      "日本x"
      ""
      [:finished, nil, nil, nil, nil]
      [[#<Encoding:ISO-2022-JP-KDDI (dummy)>, #<Encoding:stateless-ISO-2022-JP-KDDI>], [#<Encoding:stateless-ISO-2022-JP-KDDI>, #<Encoding:UTF8-KDDI>], [#<Encoding:UTF8-KDDI>, #<Encoding:UTF-8>]]
      "a日"
      "本"
      ""
      :finished
      "日本x"
      ""
      [:finished, nil, nil, nil, nil]
    OUT
  end

  it "default encodings are settable" do
    result = ze0(<<~'RUBY')
      # Encoding.default_external= and default_internal= set what a stream that
      # names no encoding reads and converts to, what "external", "filesystem"
      # and "internal" name, and what a bare String#encode converts to.

      path = "the_default_encodings_are_settable.txt"
      File.binwrite(path, "caf\xC3\xA9\n")
      p Encoding.default_external, Encoding.default_internal
      a = File.open(path)
      p Encoding.default_external = "ISO-8859-1"
      p Encoding.default_external
      p Encoding.find("external"), Encoding.find("filesystem"), Encoding.find("locale")
      p Encoding::UTF_8.names, Encoding::ISO_8859_1.names
      p Encoding.aliases.values_at("external", "filesystem", "locale", "internal")
      s = File.read(path)
      p s.encoding, s.bytes.size
      p a.external_encoding, a.read.encoding
      a.close
      File.open(path) { |f| p f.external_encoding, f.internal_encoding, f.gets.encoding }
      p Encoding.default_internal = Encoding::UTF_8
      p Encoding.default_internal, Encoding.find("internal")
      p Encoding::UTF_8.names
      File.open(path) do |f|
        p f.external_encoding, f.internal_encoding
        line = f.gets
        p line.encoding, line.bytes
      end
      File.open(path, "w") { |f| p f.external_encoding, f.internal_encoding; f.write "é" }
      p File.binread(path)
      File.open(path, "r:BINARY") { |f| p f.external_encoding, f.internal_encoding, f.read.encoding }
      File.open(path, "r:ISO-8859-1") { |f| p f.external_encoding, f.internal_encoding }
      p Encoding.default_internal = nil
      p Encoding.find("internal"), Encoding.aliases["internal"], Encoding.name_list.count("internal")
      begin
        Encoding.default_external = nil
      rescue => e
        p e
      end
      begin
        Encoding.default_external = "nope"
      rescue => e
        p e
      end
      begin
        Encoding.default_internal = 1
      rescue => e
        p e
      end
      p "x".encode.encoding
      Encoding.default_external = Encoding::UTF_8
      p File.read(path).encoding
      File.delete(path)
      $VERBOSE = true
      Encoding.default_external = "UTF-8"
      Encoding.default_internal = nil
      Encoding.default_external = "ISO-8859-1" if true
      Encoding.default_internal = Encoding::UTF_8
      File.open("the_default_encodings_are_settable_2.txt", "w") { |f| p f.external_encoding, f.internal_encoding; p f.write("é"); p "é".encode(f.external_encoding) }
      p File.binread("the_default_encodings_are_settable_2.txt")
      File.delete("the_default_encodings_are_settable_2.txt")
      s = "\xff".force_encoding("EUC-JP")
      Encoding.default_internal = nil
      p s.encode, s.encode.encoding
      p "a\xff<".encode(xml: :text)
      Encoding.default_internal = "UTF-16LE"
      p "a\xff".encode

    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      #<Encoding:UTF-8>
      nil
      "ISO-8859-1"
      #<Encoding:ISO-8859-1>
      #<Encoding:ISO-8859-1>
      #<Encoding:ISO-8859-1>
      #<Encoding:UTF-8>
      ["UTF-8", "CP65001", "locale"]
      ["ISO-8859-1", "ISO8859-1", "external", "filesystem"]
      ["ISO-8859-1", "ISO-8859-1", "UTF-8", nil]
      #<Encoding:ISO-8859-1>
      6
      #<Encoding:ISO-8859-1>
      #<Encoding:ISO-8859-1>
      #<Encoding:ISO-8859-1>
      nil
      #<Encoding:ISO-8859-1>
      #<Encoding:UTF-8>
      #<Encoding:UTF-8>
      #<Encoding:UTF-8>
      ["UTF-8", "CP65001", "locale", "internal"]
      #<Encoding:ISO-8859-1>
      #<Encoding:UTF-8>
      #<Encoding:UTF-8>
      [99, 97, 102, 195, 131, 194, 169, 10]
      #<Encoding:ISO-8859-1>
      #<Encoding:UTF-8>
      "\xE9"
      #<Encoding:BINARY (ASCII-8BIT)>
      nil
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:ISO-8859-1>
      #<Encoding:UTF-8>
      nil
      nil
      nil
      1
      #<ArgumentError: default external can not be nil>
      #<ArgumentError: unknown encoding name - nope>
      #<TypeError: no implicit conversion of Integer into String>
      #<Encoding:UTF-8>
      #<Encoding:UTF-8>
      #<Encoding:ISO-8859-1>
      #<Encoding:UTF-8>
      1
      "\xE9"
      "\xE9"
      "\xFF"
      #<Encoding:EUC-JP>
      "a\xFF&lt;"
      "a\uFFFD"
    OUT
      core/encoding/packing_test.rb:53: warning: setting Encoding.default_external
      core/encoding/packing_test.rb:54: warning: setting Encoding.default_internal
      core/encoding/packing_test.rb:55: warning: setting Encoding.default_external
      core/encoding/packing_test.rb:56: warning: setting Encoding.default_internal
      core/encoding/packing_test.rb:61: warning: setting Encoding.default_internal
      core/encoding/packing_test.rb:64: warning: setting Encoding.default_internal
    ERR
  end

  it "encoding utf16 dummy" do
    result = ze0(<<~'RUBY')
      # The dummy UTF-16/UTF-32 encodings (no endianness in the name): encoding
      # TO one writes a BOM then big-endian code units; decoding FROM one reads
      # the endianness off the BOM, and without a BOM the bytes are an invalid
      # sequence. The tag is the dummy encoding itself, not the BE/LE row.
      p "hello".encode("UTF-16")
      s = "あ".encode("UTF-16")
      p [s.encoding, s.unpack1("H*"), s.encoding.dummy?]
      p s.encode("UTF-8")
      p "あ".encode("UTF-32").unpack1("H*")
      p "\xFE\xFF\x30\x42".b.force_encoding("UTF-16").encode("UTF-8")
      begin
        "a\x00".b.force_encoding("UTF-16").encode("UTF-8")
      rescue => e
        p [e.class, e.message]
      end
      p Encoding::UTF_16.names
      p [Encoding::UTF_16.dummy?, Encoding::UTF_16BE.dummy?]
    RUBY

    _(result).must_answer <<~'OUT'
      "\xFE\xFF\x00\x68\x00\x65\x00\x6C\x00\x6C\x00\x6F"
      [#<Encoding:UTF-16 (dummy)>, "feff3042", true]
      "あ"
      "0000feff00003042"
      "あ"
      [Encoding::InvalidByteSequenceError, "\"a\\x00\" on UTF-16"]
      ["UTF-16"]
      [true, false]
    OUT
  end

  it "euc jp encodes jis x 0212" do
    result = ze0(<<~'RUBY')
      # Encoding "é" (and other Latin letters) to EUC-JP: CRuby reaches JIS X
      # 0212 (the SS3 plane -- bytes 8f ab b1); zeo's encoder (encoding_rs's
      # WHATWG table, which is decode-only for JIS X 0212) refuses with
      # UndefinedConversionError. Related to but distinct from the DECIDED
      # ISO-2022-JP divergence in docs/COMPATIBILITY.md. (Found by the
      # 2026-08-24 probe sweep.)
      p "é".encode("EUC-JP").unpack1("H*")
      p "é".encode("EUC-JP").encode("UTF-8") == "é"
    RUBY

    _(result).must_answer <<~'OUT'
      "8fabb1"
      true
    OUT
  end

  it "integer chr encoding" do
    result = ze0(<<~'RUBY')
      # Integer#chr: CRuby-strict range check for the byte form (RangeError outside
      # 0..255) and real UTF-8 encoding for chr(Encoding::UTF_8) -- previously the
      # encoding argument was dropped and the codepoint silently truncated to one
      # byte (0x3042.chr(UTF_8) yielded "B").
      p 65.chr
      p 0x3042.chr(Encoding::UTF_8)
      p 0x80.chr(Encoding::UTF_8).bytes
      p 0x7FF.chr(Encoding::UTF_8).bytes
      p 0xFFFF.chr(Encoding::UTF_8).bytes
      p 0x10FFFF.chr(Encoding::UTF_8).bytes
      p 65.chr(Encoding::UTF_8)
      p 65.chr(Encoding::US_ASCII)
      p 200.chr(Encoding::ASCII_8BIT).bytes
      [-1, 256, 0x3042].each do |n|
        begin
          n.chr
          puts "#{n}.chr: ok"
        rescue RangeError => e
          puts "#{n}.chr: RangeError: #{e.message}"
        end
      end
      [-1, 0xD800, 0x110000].each do |n|
        begin
          n.chr(Encoding::UTF_8)
          puts "#{n}.chr(UTF_8): ok"
        rescue RangeError => e
          puts "#{n}.chr(UTF_8): RangeError: #{e.message}"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "A"
      "あ"
      [194, 128]
      [223, 191]
      [239, 191, 191]
      [244, 143, 191, 191]
      "A"
      "A"
      [200]
      -1.chr: RangeError: -1 out of char range
      256.chr: RangeError: 256 out of char range
      12354.chr: RangeError: 12354 out of char range
      -1.chr(UTF_8): RangeError: -1 out of char range
      55296.chr(UTF_8): RangeError: invalid codepoint 0xD800 in UTF-8
      1114112.chr(UTF_8): RangeError: 1114112 out of char range
    OUT
  end

  it "io binary write paths" do
    result = ze0(<<~'RUBY')
      # Every route a String can take to a write. A String carries its own byte
      # count, so an embedded NUL must not truncate the write -- and the answer must
      # not depend on which spelling of the receiver or which write form was used.
      # NUL is framing, not an exotic case: a WebSocket length field, a PNG header,
      # any packed binary record.
      require "stringio"

      BIN = "AB\x00CD"
      LEAD = "\x00AB"

      path = "spinel_binwrite_#{Process.pid}.tmp"

      # File#write, single and multi-arg
      File.open(path, "wb") { |f| f.write(BIN) }
      puts File.binread(path).bytes.inspect

      File.open(path, "wb") { |f| p f.write(BIN, LEAD) }
      puts File.binread(path).bytes.inspect

      # a payload whose FIRST byte is NUL wrote nothing at all
      File.open(path, "wb") { |f| p f.write(LEAD) }
      puts File.binread(path).bytes.inspect

      # IO#<<
      File.open(path, "wb") { |f| f << BIN }
      puts File.binread(path).bytes.inspect

      # IO.copy_stream: the source read is a marked heap string with NULs in it
      src = path + ".src"
      File.binwrite(src, BIN + LEAD)
      IO.copy_stream(src, path)
      puts File.binread(path).bytes.inspect

      # a non-String argument still stringifies
      File.open(path, "wb") { |f| f.write(1234) }
      puts File.binread(path).bytes.inspect

      File.delete(path)
      File.delete(src)
    RUBY

    _(result).must_answer <<~'OUT'
      [65, 66, 0, 67, 68]
      8
      [65, 66, 0, 67, 68, 0, 65, 66]
      3
      [0, 65, 66]
      [65, 66, 0, 67, 68]
      [65, 66, 0, 67, 68, 0, 65, 66]
      [49, 50, 51, 52]
    OUT
  end

  it "iso 2022 jp family converts through its stateless form" do
    result = ze0(<<~'RUBY')
      # The ISO-2022-JP family converts through its stateless multibyte encoding:
      # each run of two-byte characters stands behind its escape, CP50221 holds
      # halfwidth katakana as a set of its own and CP50220 writes them fullwidth,
      # and each failure names the step of the path it stopped in.
      s = "abc日本"
      j = s.encode("ISO-2022-JP")
      p j.b.unpack1("H*"), j.encoding, j.encode("UTF-8"), "日\n本".encode("ISO-2022-JP").b
      p "日本".encode("CP50221").b, "日本".encode("CP50220").b, "ｱｲ日".encode("CP50221").b, "ｱｲ日".encode("CP50220").b
      p "ｶﾞｷﾞﾊﾟﾟｳﾞﾞカﾞ".encode("CP50220").force_encoding("CP50220").encode("UTF-8")
      p "①".encode("CP50221").b, "日本".encode("EUC-JP").encode("ISO-2022-JP").b
      p "\e$BF|\e(B".force_encoding("ISO-2022-JP").encode("EUC-JP").b, "ab\e$BF|".force_encoding("ISO-2022-JP").encode("UTF-8")
      p "\e(I12\e(B".force_encoding("CP50221").encode("UTF-8"), "\e(J\\~\e(B".force_encoding("ISO-2022-JP").encode("UTF-8")
      p "é".encode("ISO-2022-JP", undef: :replace).b, "é".encode("ISO-2022-JP", invalid: :replace, undef: :replace, replace: "*").b
      ["é", "\u{1F600}", "ｱ"].each { |c| begin; c.encode("ISO-2022-JP"); rescue => e; p [e.class, e.message, e.error_char, e.source_encoding_name, e.destination_encoding_name]; end }
      ["\e$B\x7f\x7f\e(B", "\e$Z", "\e$B\nF|", "\e(Ia", "ab\e", "\e$B\x2F\x7E", "\e$BF\x10", "\e$BF", "\x80", "\e("].each do |bad|
        begin
          bad.dup.force_encoding("ISO-2022-JP").encode("UTF-8")
        rescue => e
          p [e.class, e.message]
        end
      end
      ["\e(I\x60", "\x80"].each { |bad| begin; bad.dup.force_encoding("CP50221").encode("UTF-8"); rescue => e; p [e.class, e.message]; end }
      p "\e$B".force_encoding("ISO-2022-JP").encode("UTF-8")

    RUBY

    _(result).must_answer <<~'OUT'
      "6162631b2442467c4b5c1b2842"
      #<Encoding:ISO-2022-JP (dummy)>
      "abc日本"
      "\e$BF|\e(B\n\e$BK\\\e(B"
      "\e$BF|K\\\e(B"
      "\e$BF|K\\\e(B"
      "\e(I12\e$BF|\e(B"
      "\e$B%\"%$F|\e(B"
      "ガギパ゜ウ゛゛カ゛"
      "\e$B-!\e(B"
      "\e$BF|K\\\e(B"
      "\xC6\xFC"
      "ab日"
      "ｱｲ"
      "\\~"
      "?"
      "*"
      [Encoding::UndefinedConversionError, "\"\\x8F\\xAB\\xB1\" to stateless-ISO-2022-JP in conversion from UTF-8 to EUC-JP to stateless-ISO-2022-JP to ISO-2022-JP", "\x{8FABB1}", "EUC-JP", "stateless-ISO-2022-JP"]
      [Encoding::UndefinedConversionError, "U+1F600 to EUC-JP in conversion from UTF-8 to EUC-JP to stateless-ISO-2022-JP to ISO-2022-JP", "😀", "UTF-8", "EUC-JP"]
      [Encoding::UndefinedConversionError, "\"\\x8E\\xB1\" to stateless-ISO-2022-JP in conversion from UTF-8 to EUC-JP to stateless-ISO-2022-JP to ISO-2022-JP", "\x{8EB1}", "EUC-JP", "stateless-ISO-2022-JP"]
      [Encoding::InvalidByteSequenceError, "\"\\x7F\" on ISO-2022-JP"]
      [Encoding::InvalidByteSequenceError, "\"\\e$\" followed by \"Z\" on ISO-2022-JP"]
      [Encoding::InvalidByteSequenceError, "\"\\n\" on ISO-2022-JP"]
      [Encoding::InvalidByteSequenceError, "\"\\e(\" followed by \"I\" on ISO-2022-JP"]
      [Encoding::InvalidByteSequenceError, "incomplete \"\\e\" on ISO-2022-JP"]
      [Encoding::UndefinedConversionError, "\"\\xAF\\xFE\" to UTF-8 in conversion from ISO-2022-JP to stateless-ISO-2022-JP to EUC-JP to UTF-8"]
      [Encoding::InvalidByteSequenceError, "\"F\" followed by \"\\x10\" on ISO-2022-JP"]
      [Encoding::InvalidByteSequenceError, "incomplete \"F\" on ISO-2022-JP"]
      [Encoding::InvalidByteSequenceError, "\"\\x80\" on ISO-2022-JP"]
      [Encoding::InvalidByteSequenceError, "incomplete \"\\e(\" on ISO-2022-JP"]
      [Encoding::InvalidByteSequenceError, "\"`\" on CP50221"]
      [Encoding::InvalidByteSequenceError, "\"\\x80\" on CP51932"]
      ""
    OUT
  end

  it "magic comment encoding" do
    result = ze0(<<~'RUBY')
      # encoding: ISO-8859-1
      # A `# encoding:` magic comment on the first line (or the second, after a
      # shebang) sets the SCRIPT ENCODING: the encoding every string literal in the
      # file is tagged with, and the one `__ENCODING__` reports. The default, with
      # no such comment, is UTF-8.

      # `__ENCODING__` echoes the script encoding declared above.
      p __ENCODING__            # #<Encoding:ISO-8859-1>

      # Every string literal is born in that encoding...
      s = "hello"
      p s.encoding              # #<Encoding:ISO-8859-1>
      p s.bytes                 # [104, 101, 108, 108, 111]  -- ASCII bytes, Latin-1 tag

      # ...so it is Latin-1-compatible, not UTF-8.
      p s.encoding == Encoding::ISO_8859_1   # true
      p s.force_encoding("UTF-8").encoding   # #<Encoding:UTF-8>  -- retag if you want

      # A literal can still be transcoded like any other string.
      p "café".encode(Encoding::UTF_8).encoding   # #<Encoding:UTF-8>
    RUBY

    _(result).must_answer <<~'OUT'
      #<Encoding:ISO-8859-1>
      #<Encoding:ISO-8859-1>
      [104, 101, 108, 108, 111]
      true
      #<Encoding:UTF-8>
      #<Encoding:UTF-8>
    OUT
  end

  it "magic comment sets the script encoding" do
    result = ze0(<<~'RUBY')
      # encoding: ISO-8859-1
      # A `# encoding:` comment on the first line tags every string literal and
      # __ENCODING__ with that encoding. Verified against ruby 4.0.6. (The
      # source must start with the comment, so no leading newline here.)

      p __ENCODING__
      p "hi".encoding
      p "hi".encoding == Encoding::ISO_8859_1
      p "hi".bytes
    RUBY

    _(result).must_answer <<~'OUT'
      #<Encoding:ISO-8859-1>
      #<Encoding:ISO-8859-1>
      true
      [104, 105]
    OUT
  end

  it "pack float native and encoding directives" do
    result = ze0(<<~'RUBY')
      p [1.5].pack("D").bytes
      p [1.5].pack("G").bytes
      p [3.14].pack("d").unpack("d")
      p [1].pack("l!").bytesize
      p [1].pack("i").bytesize
      p [1].pack("j").bytesize
      p ["hello world"].pack("M")
      p ["hi there folks"].pack("u").unpack("u")
      p(["hi there folks"].pack("u").unpack("u") == ["hi there folks"])
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 0, 0, 0, 0, 0, 248, 63]
      [63, 248, 0, 0, 0, 0, 0, 0]
      [3.14]
      8
      4
      8
      "hello world=\n"
      ["hi there folks"]
      true
    OUT
  end

  it "pack utf8" do
    result = ze0(<<~'RUBY')
      # Array#pack("U*") encodes integer codepoints as UTF-8. The runtime
      # `U` directive was missing, so pack returned an empty string.
      p [0x1E0A].pack("U*").bytes       # E1 B8 8A
      p [0x3042].pack("U*").bytes       # E3 81 82  (HIRAGANA A)
      p [104, 105].pack("U*")           # "hi" (ASCII, 1 byte each)
      p [0x1F600].pack("U*").bytes      # F0 9F 98 80 (4-byte emoji)
      p [65, 0x3042, 66].pack("U*").bytes
      p [0x7F].pack("U*").bytes         # boundary: last 1-byte
      p [0x80].pack("U*").bytes         # boundary: first 2-byte
      p [0x800].pack("U*").bytes        # boundary: first 3-byte
      p [].pack("U*")                   # empty array -> ""
      p [97].pack("U")                  # single, no count
    RUBY

    _(result).must_answer <<~'OUT'
      [225, 184, 138]
      [227, 129, 130]
      "hi"
      [240, 159, 152, 128]
      [65, 227, 129, 130, 66]
      [127]
      [194, 128]
      [224, 160, 128]
      ""
      "a"
    OUT
  end

  it "print of binary chr strings reaches the file byte for byte" do
    result = ze0(<<~'RUBY')
      path = "/tmp/zeo_e2e_binprint_#{Process.pid}"
      File.open(path, "wb") { |f| f.print 180.chr, 0.chr, 255.chr }
      p File.binread(path).bytes
      File.delete(path)
    RUBY

    _(result).must_answer "[180, 0, 255]\n"
  end

  it "puts of binary strings adds newlines without reencoding" do
    result = ze0(<<~'RUBY')
      # The second argument already ends in a newline BYTE -- `puts` must
      # not double it, and the 0xB5 byte must survive un-promoted.

      path = "/tmp/zeo_e2e_binputs_#{Process.pid}"
      File.open(path, "wb") { |f| f.puts 180.chr, (181.chr + "\n") }
      p File.binread(path).bytes
      File.delete(path)
    RUBY

    _(result).must_answer "[180, 10, 181, 10]\n"
  end

  it "random urandom binary length" do
    result = ze0(<<~'RUBY')
      # Random.urandom hands back binary bytes, so #length is the byte count. spinel
      # keeps no per-string encoding tag and counts UTF-8 code points whenever the
      # bytes happen to spell valid UTF-8 -- true of about 1.5% of 4-byte draws, which
      # then reported a length short of the requested size. #3474.
      p 2000.times.any? { Random.urandom(4).length != 4 }
      p 2000.times.any? { Random.urandom(4).bytesize != 4 }
      p 2000.times.any? { Random.urandom(4).bytes.size != 4 }
      p 2000.times.any? { Random.urandom(4).chars.size != 4 }
      p 2000.times.any? { Random.urandom(4).size != 4 }
      p Random.urandom(0).length
      p Random.urandom(32).length
      s = Random.urandom(8)
      p s.length == s.bytesize
      p s.dup.length == 8
      p s[0, 8].bytesize
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
      false
      0
      32
      true
      true
      8
    OUT
  end

  it "regexp multibyte literal atom" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at fa06b601.
      #
      # A multibyte literal in a pattern is emitted one BYTE at a time, so each
      # byte becomes an atom of its own and a quantifier binds to the last one:
      # `/あ+/` compiles as the lead bytes followed by a repeat of the final byte.
      #
      # The visible result is a match that returns bytes which are not a character:
      # `"ĀĀ"` where CRuby answers `"あ"`.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix, not zeo's divergence above.
      #
      # A literal is emitted one byte at a time, so a character above 127 made each
      # of its bytes an atom of its own and a quantifier bound to the last one:
      # /あ+/ compiled as the lead byte followed by a repeat of the final
      # continuation byte. Ported from mruby-regexp (bcacba1e1).
      p("ああ" =~ /あ+/ ? $~[0] : nil)
      p("ああ" =~ /あ{2}/ ? true : false)
      p "ああxあ".scan(/あ+/)
      p "ĀĀ".match(/Ā+/)[0]
      p "ĀĀ".match?(/Ā{2}/)
      p("あか" =~ /あ|か/ ? $~[0] : nil)
      p("aあb" =~ /a.b/ ? true : false)
      p "aあbあc".gsub(/あ/, "-")
      p("ああ" =~ /\あ+/ ? $~[0] : nil)
      p "あいう".index(/い/)
    RUBY

    _(result).must_answer <<~'OUT'
      "ああ"
      true
      ["ああ", "あ"]
      "ĀĀ"
      true
      "あ"
      true
      "a-b-c"
      "ああ"
      1
    OUT
  end

  it "setbyte nul bytes" do
    result = ze0(<<~'RUBY')
      # Regression: String#setbyte sized the receiver with strlen, which stops at
      # the first NUL byte. An all-NUL buffer (the pack("C*") byte-buffer pattern)
      # measured length 0, so every setbyte raised IndexError despite length/
      # bytesize correctly reporting the stored length. setbyte must use the
      # NUL-safe stored length like getbyte/bytesize do.

      # all-NUL buffer: previously every call here raised IndexError
      s = Array.new(5, 0).pack("C*")
      puts "len=#{s.length}"
      s.setbyte(0, 65)
      s.setbyte(4, 90)
      puts s.bytes.inspect

      # NUL-prefixed buffer, negative index counts from the true end
      t = [0, 0, 66, 0].pack("C*")
      t.setbyte(-1, 67)
      t.setbyte(0, 68)
      puts t.bytes.inspect

      # out-of-range past the stored length still raises
      begin
        s.setbyte(5, 1)
        puts "no error"
      rescue IndexError => e
        puts "IndexError: #{e.message}"
      end

      # setbyte return value is the byte written
      puts s.setbyte(1, 200)
      puts s.bytes.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      len=5
      [65, 0, 0, 0, 90]
      [68, 0, 66, 67]
      IndexError: index 5 out of string
      200
      [65, 200, 0, 0, 90]
    OUT
  end

  it "string binary char table" do
    result = ze0(<<~'RUBY')
      # `s[i]` on a BINARY string used to allocate: the shared 1-byte substring table
      # is a static array whose entries carry no header (marker 0xff), and the
      # ASCII-8BIT tag lives in a header -- so keeping the tag meant building a real
      # string per index. That was 2.3x, and none of it was the indexing: 220M of the
      # 226M difference was malloc, free, and the GC sweep walking what they left.
      #
      # A second static table carries a header, under a marker that says "static
      # storage WITH a header" (0xfb). It joins the group that has a header and stays
      # out of the group that is a mutable heap string, so nothing sweeps it, nothing
      # mutates it in place, and its length is real -- which also puts byte 0 in the
      # table, where strlen had made it the empty string.

      b = [200, 65, 0, 255].pack("C*")
      p b.bytesize
      p b[0].bytes
      p b[1].bytes
      p b[2].bytes
      p b[3].bytes
      p b[0].encoding.to_s
      p b[1].encoding.to_s
      p b[0].length
      p b[2].length
      p b[2].bytesize
      p b[0] == b[0]
      p b[1] == "A"
      p b[0].inspect
      p b[2].inspect

      # the slice is not frozen, and mutating a copy must not poison the shared entry
      x = b[1]
      p x.frozen?
      y = x.dup
      y << "z"
      p y
      p b[1].bytes
      p b[1] == "A"

      w2 = b[1].dup
      w2.setbyte(0, 66)
      p w2.bytes
      p b[1].bytes

      # as Hash keys
      h = {}
      h[b[0]] = 1
      h[b[1]] = 2
      p h.size
      p h[b[0]]

      # the entries survive collection: they are static, so the mark must skip them
      kept = []
      2000.times do |i|
        kept.push(b[i % 4]) if (i % 97).zero?
        raise "bad" unless b[i % 4].bytesize == 1
      end
      p kept.length
      p kept.map { |c| c.bytes[0] }.uniq.sort
      p b.bytes

      # and the ASCII table is untouched
      s = String.new("abc")
      p s[1]
      p s[1].encoding.to_s
      p s[1] == "b"
      p s[1].frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      4
      [200]
      [65]
      [0]
      [255]
      "ASCII-8BIT"
      "ASCII-8BIT"
      1
      1
      1
      true
      true
      "\"\\xC8\""
      "\"\\x00\""
      false
      "Az"
      [65]
      true
      [66]
      [65]
      2
      1
      21
      [0, 65, 200, 255]
      [200, 65, 0, 255]
      "b"
      "UTF-8"
      true
      false
    OUT
  end

  it "string binary tag" do
    result = ze0(<<~'RUBY')
      b = "café".b
      p b.length
      p "café".length
      p b.bytesize
      p b.chars
      p b.encoding.to_s
      p "café".encoding.to_s
      p b.frozen?
      p b.b.length

      q = [200, 300].pack("C*")
      p q
      p q.encoding.to_s
      p q.length

      s = "café".b
      s << "x"
      p s
      p s.encoding.to_s

      big = "café".b
      20.times { big << "0123456789" }
      p big.encoding.to_s
      p big.length
      p big[0, 6]
      pk = [200, 300].pack("C*")
      3.times { pk << "z" }
      p pk
      p pk.length

      u = String.new("café")
      u << "x"
      p u
      p u.encoding.to_s
      p u.length
      p("caf" + "é")
      v = String.new("café")
      3.times { v << "y" }
      p v.length
      p v.encoding.to_s

      p("abc".b == "abc")
      p("abc".b.eql?("abc"))
      p("abc".b <=> "abc")
      p("abc".b.hash == "abc".hash)
      p("café".b == "café")
      p("café".b.eql?("café"))
      p("café".b <=> "café")
      p("café" <=> "café".b)
      p("café".b.hash == "café".hash)
      p("café".b == "café".b)
      p("café" == "café")
      p("abc".b == "abd")
      p([200, 300].pack("C*") == [200, 300].pack("C*"))

      h = {}
      h["café"] = 1
      h["café".b] = 2
      p h.size
      p h["café"]
      g = {}
      g["abc"] = 1
      g["abc".b] = 2
      p g.size
      p g["abc"]

      p ["café".b, "café", "abc"].sort.length
      p ["café".b, "café"].uniq.length
      p ["abc".b, "abc"].uniq.length
    RUBY

    _(result).must_answer <<~'OUT'
      5
      4
      5
      ["c", "a", "f", "\xC3", "\xA9"]
      "ASCII-8BIT"
      "UTF-8"
      false
      5
      "\xC8,"
      "ASCII-8BIT"
      2
      "caf\xC3\xA9x"
      "ASCII-8BIT"
      "ASCII-8BIT"
      205
      "caf\xC3\xA90"
      "\xC8,zzz"
      5
      "caféx"
      "UTF-8"
      5
      "café"
      7
      "UTF-8"
      true
      true
      0
      true
      false
      false
      -1
      1
      false
      true
      true
      false
      true
      2
      1
      1
      2
      3
      2
      1
    OUT
  end

  it "string binary tag sources" do
    result = ze0(<<~'RUBY')
      # spinel has two encodings, UTF-8 and ASCII-8BIT, and one rule for which is
      # which: a string is ASCII-8BIT when the PROGRAM ASKED FOR BYTES. CRuby's third
      # encoding, US-ASCII, carries only "these bytes are 7-bit" -- measurably nothing
      # else, since compatibility keys on the content being 7-bit rather than on the
      # encoding's identity -- and spinel carries that as a header bit with no name.
      #
      # pack and String#b followed the rule. Marshal.dump, Random#bytes, binread,
      # unpack and force_encoding did not: they answered UTF-8 over byte data, which
      # is not only the wrong name. The tag makes #length count bytes, so
      # `Random.bytes(8).length` was under 8 whenever the draw happened to be valid
      # UTF-8 -- about three times in a thousand.

      File.write("/tmp/_sp_enc_test.bin", "abc")

      # the ones that ask for bytes
      puts [65].pack("C").encoding.to_s
      puts "abc".b.encoding.to_s
      puts Marshal.dump(1).encoding.to_s
      puts Random.bytes(4).encoding.to_s
      puts File.binread("/tmp/_sp_enc_test.bin").encoding.to_s
      puts IO.binread("/tmp/_sp_enc_test.bin").encoding.to_s
      puts "abc".unpack("a*")[0].encoding.to_s
      puts "abc".unpack("A*")[0].encoding.to_s
      puts "abc".unpack("Z*")[0].encoding.to_s
      puts "abc".dup.force_encoding("ASCII-8BIT").encoding.to_s
      puts "abc".dup.force_encoding(Encoding::BINARY).encoding.to_s
      puts "abc".dup.force_encoding(Encoding::ASCII_8BIT).encoding.to_s

      # the ones that do not
      puts File.read("/tmp/_sp_enc_test.bin").encoding.to_s
      puts "abc".encoding.to_s
      puts "abc".upcase.encoding.to_s
      puts [65].pack("C").dup.force_encoding("UTF-8").encoding.to_s

      # BINARY and ASCII-8BIT are one encoding, not two
      p Encoding::BINARY == Encoding::ASCII_8BIT
      p Encoding::BINARY.to_s
      p Encoding::ASCII_8BIT.to_s

      # the tag is load-bearing: a byte count, not a character count
      bad = 0
      1000.times { bad += 1 if Random.bytes(8).length != 8 }
      p bad
      m = Marshal.dump([1, 2, 3])
      p m.length == m.bytesize
      b = File.binread("/tmp/_sp_enc_test.bin")
      p b.length

      # a String reached through a poly array answers #encoding: the poly dispatch
      # had no arm for it, so it raised NoMethodError naming its own class -- and
      # once it had one, the call had no type, so emit_boxed's untyped arm rendered
      # `(expr, sp_box_nil())` and threw the answer away
      a = ["abc", 1][0]
      p a.encoding
      p a.encoding.to_s
      h = { "k" => [65].pack("C") }
      p h["k"].encoding.to_s
      def enc_of(v) = v.encoding.to_s
      puts enc_of("abc")
      puts enc_of([65].pack("C"))
    RUBY

    _(result).must_answer <<~'OUT'
      ASCII-8BIT
      ASCII-8BIT
      ASCII-8BIT
      ASCII-8BIT
      ASCII-8BIT
      ASCII-8BIT
      ASCII-8BIT
      ASCII-8BIT
      ASCII-8BIT
      ASCII-8BIT
      ASCII-8BIT
      ASCII-8BIT
      UTF-8
      UTF-8
      UTF-8
      UTF-8
      true
      "ASCII-8BIT"
      "ASCII-8BIT"
      0
      true
      3
      #<Encoding:UTF-8>
      "UTF-8"
      "ASCII-8BIT"
      UTF-8
      ASCII-8BIT
    OUT
  end

  it "string bytes crypt" do
    result = ze0(<<~'RUBY')
      # String#append_as_bytes and String#crypt.

      # append_as_bytes: integers contribute their low byte, strings their bytes.
      s = "abc".dup
      s.append_as_bytes("de")
      p s
      s = "x".dup
      s.append_as_bytes(0x41, 0x42, "CD", 256)
      p s.bytes
      p s.encoding

      # Negative and big integers wrap to a single low byte.
      s = "x".dup
      s.append_as_bytes(-1, 2**70)
      p s.bytes

      # Encoding is preserved (a binary receiver stays binary).
      s = "hi".b
      s.append_as_bytes(0xFF)
      p s.encoding

      # A non String/Integer argument is a TypeError.
      begin
        "x".dup.append_as_bytes(:sym)
      rescue TypeError => e
        puts e.message
      end

      # crypt: the host crypt(3) hash, ASCII-8BIT result.
      p "password".crypt("ab")
      p "password".crypt("ab").encoding

      # crypt validates the salt and rejects a NUL in the key.
      begin; "x".crypt("a"); rescue ArgumentError => e; puts e.message; end
      begin; "x".crypt(""); rescue ArgumentError => e; puts e.message; end
      begin; "x\0y".crypt("ab"); rescue ArgumentError => e; puts e.message; end
    RUBY

    _(result).must_answer <<~'OUT'
      "abcde"
      [120, 65, 66, 67, 68, 0]
      #<Encoding:UTF-8>
      [120, 255, 0]
      #<Encoding:BINARY (ASCII-8BIT)>
      wrong argument type Symbol (expected String or Integer)
      "abJnggxhB/yWI"
      #<Encoding:BINARY (ASCII-8BIT)>
      salt too short (need >=2 bytes)
      salt too short (need >=2 bytes)
      string contains null byte
    OUT
  end

  it "string byteslice" do
    result = ze0(<<~'RUBY')
      # String#byteslice: byte-indexed substring. Negative start counts from
      # the end. (Out-of-range yields "" like slice, not CRuby's nil, so it is
      # not exercised here.)
      puts "hello".byteslice(0, 3)
      puts "hello".byteslice(1, 3)
      puts "hello".byteslice(-2, 1)
      puts "hello".byteslice(1)
      puts "hello".byteslice(0, 5)
      puts "hello".byteslice(2, 100)
    RUBY

    _(result).must_answer <<~'OUT'
      hel
      ell
      l
      e
      hello
      llo
    OUT
  end

  it "string nul bytes" do
    result = ze0(<<~'RUBY')
      # Embedded NUL bytes survive frozen-string operations (dedup / .freeze): the
      # 0xf1 frozen marker carries the real byte length, so nothing truncates at NUL.
      s = "a\u0000b"
      p s.bytesize
      p(s == "a\u0000c")
      p(s == "a\u0000b")
      d = s.dedup
      p d.bytesize
      p(d == s)
      p("a\u0000b".dedup.equal?("a\u0000b".dedup))
      f = "x\u0000y".freeze
      p f.bytesize
      h = { s => 1 }
      h["a\u0000c"] = 2
      p h.size
    RUBY

    _(result).must_answer <<~'OUT'
      3
      false
      true
      3
      true
      true
      3
      2
    OUT
  end

  it "string search binary" do
    result = ze0(<<~'RUBY')
      # String#include?/#index/#rindex must be byte-oriented and NUL-transparent:
      # spinel Strings can carry embedded NULs (pack, socket reads), so a strstr-
      # backed search that stops at the first NUL diverges from CRuby (issue #1778).
      z = [0].pack("C*")
      s = "user" + z + "app" + z + "tail"
      puts s.include?("app" + z)   # needle contains a NUL
      puts s.include?("tail")      # plain needle after the haystack's first NUL
      puts s.index("tail")
      puts s.index("app")
      puts s.rindex("app")
      # ordinary (NUL-free) searches are unchanged
      puts "hello world".include?("lo wo")
      puts "hello world hello".index("hello", 3)
      puts "hello world hello".rindex("hello")
      puts "café テスト".index("テスト")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      9
      5
      5
      true
      12
      12
      5
    OUT
  end

  it "string times repeats raw bytes keeping the encoding" do
    result = ze0(<<~'RUBY')
      r = 180.chr * 3
      p r.bytes
      p r.encoding
      p ("ab" * 2)
    RUBY

    _(result).must_answer <<~'OUT'
      [180, 180, 180]
      #<Encoding:BINARY (ASCII-8BIT)>
      "abab"
    OUT
  end

  it "string unicode" do
    result = ze0(<<~'RUBY')
      # String grapheme clusters and Unicode normalization.

      # Grapheme clusters group a base character with its combining marks, and treat
      # regional-indicator flags and ZWJ emoji sequences as single clusters.
      combined = "áé"          # a + combining acute, e + combining acute
      p combined.grapheme_clusters
      p combined.grapheme_clusters.length
      p "café".grapheme_clusters.length
      p "🇯🇵👨‍👩‍👧".grapheme_clusters

      # each_grapheme_cluster yields each cluster; blockless gives an Enumerator.
      out = []
      combined.each_grapheme_cluster { |g| out << g }
      p out
      p combined.each_grapheme_cluster.to_a

      # Normalization: NFC composes, NFD decomposes, NFKC/NFKD also fold compatibility.
      decomposed = "é"                # e + combining acute
      p decomposed.unicode_normalize.bytes  # default :nfc -> single é codepoint
      p decomposed.unicode_normalize(:nfd).length
      p "ﬁ".unicode_normalize(:nfkc)         # fi ligature -> "fi"
      p "①".unicode_normalize(:nfkd)         # circled 1 -> "1"

      # unicode_normalized? tests membership in a form.
      p "é".unicode_normalized?              # composed, already NFC
      p decomposed.unicode_normalized?       # decomposed, not NFC
      p decomposed.unicode_normalized?(:nfd) # ...but is NFD

      # An unknown form raises ArgumentError.
      begin
        "x".unicode_normalize(:bogus)
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["á", "é"]
      2
      4
      ["🇯🇵", "👨‍👩‍👧"]
      ["á", "é"]
      ["á", "é"]
      [195, 169]
      2
      "fi"
      "1"
      true
      false
      true
      Invalid normalization form bogus.
    OUT
  end

  it "string upto and byte indexing methods" do
    result = ze0(<<~'RUBY')
      p "a8".upto("b1").to_a
      r = []
      "a".upto("e") { |x| r << x }
      p r
      p "hello".byteindex("l")
      p "hello".byteindex("l", 3)
      p "hello".byterindex("l")
      p "hello".byterindex("l", 2)
      p "hello".byteslice(1, 3)
      p "café".byteslice(0, 3)
      p "hello".byteslice(-2, 2)
      p "hello".byteslice(10)
    RUBY

    _(result).must_answer <<~'OUT'
      ["a8", "a9", "b0", "b1"]
      ["a", "b", "c", "d", "e"]
      2
      3
      3
      2
      "ell"
      "caf"
      "lo"
      nil
    OUT
  end

  it "strings keep their encodings" do
    result = ze0(<<~'RUBY')
      # A String keeps the encoding ruby gives it: a partial read, and any
      # read in binary mode, is binary; +s and -s keep it; a codepoint appends
      # by the String's encoding; reverse walks characters, an invalid byte
      # one of them.
      def t = yield rescue [$!.class, $!.message]

      path = "strings_keep_their_encodings.tmp"
      File.binwrite(path, "\xff\xfeab\nc".b)
      p t { File.open(path) { |f| f.read(1).encoding } }, t { File.open(path) { |f| f.read.encoding } }, t { File.open(path, "rb") { |f| f.read.encoding } }
      p t { File.open(path, "rb") { |f| f.binmode? } }, t { File.open(path) { |f| f.binmode? } }, t { File.open(path) { |f| f.binmode; [f.binmode?, f.read.encoding] } }
      p t { File.open(path, "r:UTF-8") { |f| f.read(2).encoding } }, t { File.open(path) { |f| f.read(0).encoding } }
      p t { File.open(path) { |f| f.gets.encoding } }, t { File.open(path, "rb") { |f| f.gets.encoding } }
      File.delete(path)

      p t { (+"\xff".b.freeze).encoding }, t { (-"\xff".b).encoding }
      p t { (+"").force_encoding("US-ASCII") << 200 }, t { ((+"").force_encoding("US-ASCII") << 200).encoding }, t { +"" << 0xD800 }, t { (+"") << 0x1F600 }
      p t { "a\x80".reverse }, t { "aé".reverse }, t { "\xE3\x81a".reverse }

    RUBY

    _(result).must_answer <<~'OUT'
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:UTF-8>
      #<Encoding:BINARY (ASCII-8BIT)>
      true
      false
      [true, #<Encoding:BINARY (ASCII-8BIT)>]
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:UTF-8>
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:BINARY (ASCII-8BIT)>
      "\xC8"
      #<Encoding:BINARY (ASCII-8BIT)>
      [RangeError, "invalid codepoint 0xD800 in UTF-8"]
      "😀"
      "\x80a"
      "éa"
      "a\x81\xE3"
    OUT
  end

  it "symbol multibyte length" do
    result = ze0(<<~'RUBY')
      # Symbol#length / #size count characters, not bytes, for multibyte
      # symbol names.
      p :αβγ.length
      p :café.size
      p :abc.length
      p :"".size rescue p :abc.size
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      3
      0
    OUT
  end
end
