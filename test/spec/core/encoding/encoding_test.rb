# frozen_string_literal: true

require "spec_helper"

describe "Encoding programs" do
  it "append codepoint empty literal" do
    result = ze0(<<~'RUBY')
      # Five surfaces from the conformance wave, four of which crashed.

      # String#<< and #concat take an Integer as a codepoint. It was passed through
      # the string slot, so the integer arrived at the concatenation as a pointer.
      s = +"abc"
      p(s << 100)
      p s
      t = +"x"
      t.concat(233)
      p t
      u = +"q"
      u << 100 << 101
      p u
      v = +"n"
      v.append_as_bytes(100)
      p v

      # A relational operator against a non-String is Comparable's ArgumentError
      # (its <=> answered nil), not a comparison against the operand as a pointer
      p(("a" < 1 rescue $!.message))
      p(("a" > nil rescue $!.message))
      p(("a" >= 3.5 rescue $!.class))
      p(("a" <=> 1))
      p("a" < "b")

      # An empty Hash literal settles at its own variant, which is rarely the
      # receiver's: merging it handed one hash struct to another's reader
      p({ 1 => 2 }.merge({}))
      p({ "a" => 1 }.merge({}))
      p({ a: 1 }.merge({}))
      p({ 1 => 2 }.merge({ 3 => 4 }))

      # print of an empty Array or Hash literal: no container variant claimed it
      print([]); print("\n")
      print({}); print("\n")
      print([1, 2]); print("\n")

      # nil never matches: Regexp#match answers nil and match? false, rather than
      # walking off a NULL subject
      p(/a/.match(nil))
      p(/a/.match?(nil))
      p(/a/ =~ nil)
      x = nil
      p(/a/.match(x))
      p(/a/ =~ x)
      p(/a/.match("a"))
      p((/a/ =~ 5 rescue $!.class))
    RUBY

    _(result).must_answer <<~'OUT'
      "abcd"
      "abcd"
      "xé"
      "qde"
      "nd"
      "comparison of String with 1 failed"
      "comparison of String with nil failed"
      ArgumentError
      nil
      true
      {1 => 2}
      {"a" => 1}
      {a: 1}
      {1 => 2, 3 => 4}
      []
      {}
      [1, 2]
      nil
      false
      nil
      nil
      nil
      #<MatchData "a">
      TypeError
    OUT
  end

  it "carrier utf8 encodings map their emoji" do
    result = ze0(<<~'RUBY')
      # UTF8-DoCoMo, UTF8-KDDI and UTF8-SoftBank are UTF-8 whose private-use
      # emoji ruby maps to and from Unicode's own, by the tables of
      # enc/trans/emoji-exchange-tbl.rb. This runtime carries no such tables
      # yet, so a conversion that names one of them stops by name.
      ["☀", "\u{1F4A9}", "aé日"].each do |text|
        %w[UTF8-DoCoMo UTF8-KDDI UTF8-SoftBank].each do |carrier|
          p [carrier, (text.encode(carrier).b rescue $!.message)]
        end
      end
      p "\u{E63E}".dup.force_encoding("UTF8-DoCoMo").encode("UTF-8")
      p "\u{E488}".dup.force_encoding("UTF8-KDDI").encode("UTF-8")
      p "\u{E6A0}".dup.force_encoding("UTF8-DoCoMo").encode("UTF-8", undef: :replace)
      p "\u{E63E}".dup.force_encoding("UTF8-DoCoMo").encode("UTF8-KDDI").b

    RUBY

    _(result).must_answer <<~'OUT'
      ["UTF8-DoCoMo", "\xEE\x98\xBE"]
      ["UTF8-KDDI", "\xEE\x92\x88"]
      ["UTF8-SoftBank", "\xEE\x81\x8A"]
      ["UTF8-DoCoMo", "U+1F4A9 from UTF-8 to UTF8-DoCoMo"]
      ["UTF8-KDDI", "\xEE\x93\xB5"]
      ["UTF8-SoftBank", "\xEE\x81\x9A"]
      ["UTF8-DoCoMo", "a\xC3\xA9\xE6\x97\xA5"]
      ["UTF8-KDDI", "a\xC3\xA9\xE6\x97\xA5"]
      ["UTF8-SoftBank", "a\xC3\xA9\xE6\x97\xA5"]
      "☀"
      "☀"
      "�"
      "\xEE\x92\x88"
    OUT
  end

  it "empty receivers concat keeps a compatible encoding" do
    result = ze0(<<~'RUBY')
      # ruby's concatenation negotiation for an EMPTY receiver: an
      # ascii-compatible empty string keeps its OWN encoding when the addition is
      # 7-bit ("".b << "abc" stays BINARY), and adopts the addition's encoding
      # only when the addition needs it -- including a wide encoding, whose bytes
      # may all be 7-bit and whose tag still wins.
      def row(l, r)
        s = l.dup
        s << r
        [s.encoding.to_s, s.bytesize]
      rescue Encoding::CompatibilityError
        [:compat_error]
      end

      p row("".b, "hello")
      p row("".b, "héllo")
      p row("x".b, "hello")
      p row("x".b, "héllo")
      p row(+"", "hi".b)
      p row(+"", "h\xC3\xA9".b)
      p row(+"abc", "h\xC3\xA9".b)
      p row(+"abc", "hi".b)
      p row("é".b, "hé")
      p row(+"héllo", "".b)
      p row("".encode("US-ASCII"), "hé")
      p row("".encode("US-ASCII"), "hi")
      p row("".b, "hi".encode("US-ASCII"))
      p row("".encode("UTF-16LE"), "abc")
      p row("".b, "ab".encode("UTF-16LE"))
      p row("".b, "".encode("UTF-16LE"))
      p row("".encode("EUC-JP"), "héllo")
      p row("".b, "héllo".encode("EUC-JP"))
      p [("x".b << 233).encoding.to_s, ("x".b << 233).bytes]
      p [(+"x" << 233).encoding.to_s, (+"x" << 233).bytes]
    RUBY

    _(result).must_answer <<~'OUT'
      ["ASCII-8BIT", 5]
      ["UTF-8", 6]
      ["ASCII-8BIT", 6]
      ["UTF-8", 7]
      ["UTF-8", 2]
      ["ASCII-8BIT", 3]
      ["ASCII-8BIT", 6]
      ["UTF-8", 5]
      [:compat_error]
      ["UTF-8", 6]
      ["UTF-8", 3]
      ["US-ASCII", 2]
      ["ASCII-8BIT", 2]
      ["UTF-8", 3]
      ["UTF-16LE", 4]
      ["ASCII-8BIT", 0]
      ["UTF-8", 6]
      ["EUC-JP", 7]
      ["ASCII-8BIT", [120, 233]]
      ["UTF-8", [120, 195, 169]]
    OUT
  end

  it "compatible? answers by which side is empty, which is 7-bit, and the order the two are asked in" do
    result = ze0(<<~'RUBY')
      # `Encoding.compatible?` over the shapes that decide it: which side is empty,
      # which side is 7-bit, and whether either encoding is ascii-compatible. The
      # order the two sides are asked in IS the answer -- two ascii-only strings
      # take the FIRST one's encoding, and an empty second side always yields.

      A = {
        "u8-ascii"  => "abc".dup.force_encoding("UTF-8"),
        "u8-wide"   => "é".dup.force_encoding("UTF-8"),
        "u8-empty"  => "".dup.force_encoding("UTF-8"),
        "l1-ascii"  => "abc".dup.force_encoding("ISO-8859-1"),
        "l1-high"   => "\xe9".dup.force_encoding("ISO-8859-1"),
        "l1-empty"  => "".dup.force_encoding("ISO-8859-1"),
        "us-ascii"  => "abc".dup.force_encoding("US-ASCII"),
        "u8-broken" => "\xff".dup.force_encoding("UTF-8"),
        "16be"      => "\x00a".dup.force_encoding("UTF-16BE"),
        "16be-empty"=> "".dup.force_encoding("UTF-16BE"),
      }
      A.each do |ka, a|
        A.each do |kb, b|
          r = Encoding.compatible?(a, b)
          puts "#{ka}\t#{kb}\t#{r ? r.name : "nil"}"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      u8-ascii	u8-ascii	UTF-8
      u8-ascii	u8-wide	UTF-8
      u8-ascii	u8-empty	UTF-8
      u8-ascii	l1-ascii	UTF-8
      u8-ascii	l1-high	ISO-8859-1
      u8-ascii	l1-empty	UTF-8
      u8-ascii	us-ascii	UTF-8
      u8-ascii	u8-broken	UTF-8
      u8-ascii	16be	nil
      u8-ascii	16be-empty	UTF-8
      u8-wide	u8-ascii	UTF-8
      u8-wide	u8-wide	UTF-8
      u8-wide	u8-empty	UTF-8
      u8-wide	l1-ascii	UTF-8
      u8-wide	l1-high	nil
      u8-wide	l1-empty	UTF-8
      u8-wide	us-ascii	UTF-8
      u8-wide	u8-broken	UTF-8
      u8-wide	16be	nil
      u8-wide	16be-empty	UTF-8
      u8-empty	u8-ascii	UTF-8
      u8-empty	u8-wide	UTF-8
      u8-empty	u8-empty	UTF-8
      u8-empty	l1-ascii	UTF-8
      u8-empty	l1-high	ISO-8859-1
      u8-empty	l1-empty	UTF-8
      u8-empty	us-ascii	UTF-8
      u8-empty	u8-broken	UTF-8
      u8-empty	16be	UTF-16BE
      u8-empty	16be-empty	UTF-8
      l1-ascii	u8-ascii	ISO-8859-1
      l1-ascii	u8-wide	UTF-8
      l1-ascii	u8-empty	ISO-8859-1
      l1-ascii	l1-ascii	ISO-8859-1
      l1-ascii	l1-high	ISO-8859-1
      l1-ascii	l1-empty	ISO-8859-1
      l1-ascii	us-ascii	ISO-8859-1
      l1-ascii	u8-broken	UTF-8
      l1-ascii	16be	nil
      l1-ascii	16be-empty	ISO-8859-1
      l1-high	u8-ascii	ISO-8859-1
      l1-high	u8-wide	nil
      l1-high	u8-empty	ISO-8859-1
      l1-high	l1-ascii	ISO-8859-1
      l1-high	l1-high	ISO-8859-1
      l1-high	l1-empty	ISO-8859-1
      l1-high	us-ascii	ISO-8859-1
      l1-high	u8-broken	nil
      l1-high	16be	nil
      l1-high	16be-empty	ISO-8859-1
      l1-empty	u8-ascii	ISO-8859-1
      l1-empty	u8-wide	UTF-8
      l1-empty	u8-empty	ISO-8859-1
      l1-empty	l1-ascii	ISO-8859-1
      l1-empty	l1-high	ISO-8859-1
      l1-empty	l1-empty	ISO-8859-1
      l1-empty	us-ascii	ISO-8859-1
      l1-empty	u8-broken	UTF-8
      l1-empty	16be	UTF-16BE
      l1-empty	16be-empty	ISO-8859-1
      us-ascii	u8-ascii	US-ASCII
      us-ascii	u8-wide	UTF-8
      us-ascii	u8-empty	US-ASCII
      us-ascii	l1-ascii	US-ASCII
      us-ascii	l1-high	ISO-8859-1
      us-ascii	l1-empty	US-ASCII
      us-ascii	us-ascii	US-ASCII
      us-ascii	u8-broken	UTF-8
      us-ascii	16be	nil
      us-ascii	16be-empty	US-ASCII
      u8-broken	u8-ascii	UTF-8
      u8-broken	u8-wide	UTF-8
      u8-broken	u8-empty	UTF-8
      u8-broken	l1-ascii	UTF-8
      u8-broken	l1-high	nil
      u8-broken	l1-empty	UTF-8
      u8-broken	us-ascii	UTF-8
      u8-broken	u8-broken	UTF-8
      u8-broken	16be	nil
      u8-broken	16be-empty	UTF-8
      16be	u8-ascii	nil
      16be	u8-wide	nil
      16be	u8-empty	UTF-16BE
      16be	l1-ascii	nil
      16be	l1-high	nil
      16be	l1-empty	UTF-16BE
      16be	us-ascii	nil
      16be	u8-broken	nil
      16be	16be	UTF-16BE
      16be	16be-empty	UTF-16BE
      16be-empty	u8-ascii	UTF-8
      16be-empty	u8-wide	UTF-8
      16be-empty	u8-empty	UTF-16BE
      16be-empty	l1-ascii	ISO-8859-1
      16be-empty	l1-high	ISO-8859-1
      16be-empty	l1-empty	UTF-16BE
      16be-empty	us-ascii	US-ASCII
      16be-empty	u8-broken	UTF-8
      16be-empty	16be	UTF-16BE
      16be-empty	16be-empty	UTF-16BE
    OUT
  end

  it "a well-known Encoding constant compares equal to the encoding a string carries" do
    result = ze0(<<~'RUBY')
      # Well-known Encoding constants resolve to the matching boxed encoding value,
      # so `str.encoding == Encoding::UTF_8` compiles and compares (it used to emit
      # an sp_Class from the uninitialized-constant fallback into a bool context).
      p("x".encoding == Encoding::UTF_8)
      p("x".encoding == Encoding::US_ASCII)
      p(Encoding::UTF_8 == Encoding::UTF_8)
      p(Encoding::UTF_8 == Encoding::BINARY)
      s = "abc"
      if s.encoding == Encoding::UTF_8
        puts "utf8"
      else
        puts "other"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      utf8
    OUT
  end

  it "encodings" do
    result = ze0(<<~'RUBY')
      # A Ruby String is bytes PLUS an encoding that says how to read them. The
      # Encoding engine here supports UTF-8, US-ASCII, ASCII-8BIT (BINARY), and
      # ISO-8859-1 (Latin-1); the design extends to more by adding a table row.

      # --- every string reports its encoding -------------------------------------
      p "hello".encoding            # #<Encoding:UTF-8>   -- the default script encoding
      p __ENCODING__                # #<Encoding:UTF-8>   -- ...which __ENCODING__ echoes

      # --- the same bytes read two ways ------------------------------------------
      euro = "€"               # the € sign
      p euro.bytes                  # [226, 130, 172]  -- three UTF-8 bytes
      p euro.bytesize               # 3   -- BYTES
      p euro.length                 # 1   -- CHARACTERS
      p euro.ascii_only?            # false
      p "hello".ascii_only?         # true

      # --- #b reinterprets the bytes as raw binary (ASCII-8BIT) ------------------
      raw = euro.b
      p raw.encoding                # #<Encoding:BINARY (ASCII-8BIT)>
      p raw.bytesize                # 3
      p raw.length                  # 3   -- now every byte is its own "character"

      # --- force_encoding re-tags WITHOUT changing bytes -------------------------
      # Reading UTF-8's multi-byte € as US-ASCII leaves the bytes invalid.
      mislabeled = euro.dup.force_encoding("US-ASCII")
      p mislabeled.encoding         # #<Encoding:US-ASCII>
      p mislabeled.valid_encoding?  # false  -- 0x80+ bytes aren't valid US-ASCII

      # --- the Encoding class and its constants ----------------------------------
      p Encoding::UTF_8             # #<Encoding:UTF-8>
      p Encoding::UTF_8.name        # "UTF-8"
      p Encoding::ASCII_8BIT.names  # ["ASCII-8BIT", "BINARY"]
      p Encoding.default_external   # #<Encoding:UTF-8>
      p Encoding.find("BINARY")     # #<Encoding:BINARY (ASCII-8BIT)>  -- alias lookup
      # An ASCII-only string is compatible with any ascii-compatible encoding.
      p Encoding.compatible?("plain ascii", euro)   # #<Encoding:UTF-8>

      # --- encode TRANSCODES the bytes between encodings -------------------------
      accented = "café"        # "café" in UTF-8 (é is two bytes)
      latin1 = accented.encode(Encoding::ISO_8859_1)
      p latin1.encoding             # #<Encoding:ISO-8859-1>
      p latin1.bytes                # [99, 97, 102, 233]  -- é is now ONE Latin-1 byte
      p latin1.encode(Encoding::UTF_8) == accented   # true  -- round trip

      # A character with no target representation raises...
      begin
        accented.encode(Encoding::US_ASCII)
      rescue Encoding::UndefinedConversionError => e
        puts "raised: #{e.class}"
      end
      # ...unless you ask for replacement.
      p accented.encode(Encoding::US_ASCII, undef: :replace)          # "caf?"
      p 'a<b>&c'.encode(Encoding::US_ASCII, xml: :text)               # "a&lt;b&gt;&amp;c"

      # --- Symbols and Regexps carry an encoding too -----------------------------
      p :hello.encoding             # #<Encoding:US-ASCII>  -- all-ASCII default
      p :café.encoding              # #<Encoding:UTF-8>
      p(/ab+/.encoding)             # #<Encoding:US-ASCII>
    RUBY

    _(result).must_answer <<~'OUT'
      #<Encoding:UTF-8>
      #<Encoding:UTF-8>
      [226, 130, 172]
      3
      1
      false
      true
      #<Encoding:BINARY (ASCII-8BIT)>
      3
      3
      #<Encoding:US-ASCII>
      false
      #<Encoding:UTF-8>
      "UTF-8"
      ["ASCII-8BIT", "BINARY"]
      #<Encoding:UTF-8>
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:UTF-8>
      #<Encoding:ISO-8859-1>
      [99, 97, 102, 233]
      true
      raised: Encoding::UndefinedConversionError
      "caf?"
      "a&lt;b&gt;&amp;c"
      #<Encoding:US-ASCII>
      #<Encoding:UTF-8>
      #<Encoding:US-ASCII>
    OUT
  end

  it "file read applies external and internal encodings" do
    result = ze0(<<~'RUBY')
      # File.read tags bytes with the external encoding (default UTF-8), or a
      # requested one; binread is always ASCII-8BIT; binwrite round-trips raw
      # bytes. Verified against ruby 4.0.6.

      require "tmpdir"
      Dir.mktmpdir do |dir|
        path = File.join(dir, "f.txt")
        File.write(path, "café")
        p File.read(path).encoding
        p File.read(path).bytesize
        p File.binread(path).encoding
        p File.binread(path).bytes
        p File.read(path, encoding: "ISO-8859-1").encoding
        p File.read(path, encoding: "ISO-8859-1").bytes
        File.binwrite(path, [0, 255, 128].pack("C*"))
        p File.binread(path).bytes
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<Encoding:UTF-8>
      5
      #<Encoding:BINARY (ASCII-8BIT)>
      [99, 97, 102, 195, 169]
      #<Encoding:ISO-8859-1>
      [99, 97, 102, 195, 169]
      [0, 255, 128]
    OUT
  end

  it "float hex encoding isa bool wave10" do
    result = ze0(<<~'RUBY')
      # Float() hex-float strings, Symbol#encoding, is_a?(Object) on typed
      # user objects, and boolean & | ^ with arbitrary (truthy) operands.
      p(Float("0x1p4"))
      p(Float("0x1.8p1"))
      p(:a.encoding)
      p("x".encoding)
      class K118; end
      o = K118.new
      p o.is_a?(Object)
      p o.is_a?(BasicObject)
      p o.kind_of?(Object)
      p(true & 5)
      p(false | "x")
      p(true ^ nil)
      p(Float("0xa"))
      r = (Float("0x1p") rescue "bad"); p r
      r2 = (Float("0xp4") rescue "bad"); p r2
    RUBY

    _(result).must_answer <<~'OUT'
      16.0
      3.0
      #<Encoding:US-ASCII>
      #<Encoding:UTF-8>
      true
      true
      true
      true
      true
      true
      10.0
      "bad"
      "bad"
    OUT
  end

  it "force encoding symbol argument" do
    result = ze0(<<~'RUBY')
      begin
        (+"x").force_encoding(:a)
      rescue TypeError => e
        p e.class
      end
    RUBY

    _(result).must_answer "TypeError\n"
  end

  it "frozen string refuses force encoding" do
    result = ze0(<<~'RUBY')
      # `String#force_encoding` on a frozen string raises FrozenError -- even
      # when the new encoding equals the current one. zeo answers the string
      # silently: force_encoding skips the frozen guard every other mutator
      # has. (Found by the 2026-08-24 probe sweep.)
      f = "x".freeze
      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { f.force_encoding("ASCII-8BIT") }
      show { f.force_encoding("UTF-8") }
      p f.encoding.name
    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError: can't modify frozen String: "x"
      FrozenError: can't modify frozen String: "x"
      "UTF-8"
    OUT
  end

  it "io encoding" do
    result = ze0(<<~'RUBY')
      # Reading a file yields a string tagged with an ENCODING. A text read
      # (File.read) tags the bytes with the EXTERNAL encoding (UTF-8 by default,
      # or one you request) without validating them; a binary read (File.binread)
      # always yields raw ASCII-8BIT bytes. Writes emit the bytes verbatim.

      require "tmpdir"   # Dir.mktmpdir -- a built-in feature here (a no-op require)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "note.txt")
        File.write(path, "café")   # 5 bytes: c a f + the two UTF-8 bytes of é

        # --- text read: tagged with the external encoding -------------------------
        text = File.read(path)
        p text.encoding            # #<Encoding:UTF-8>   -- the default external
        p text.bytesize            # 5

        # --- binary read: always ASCII-8BIT, no interpretation --------------------
        raw = File.binread(path)
        p raw.encoding             # #<Encoding:BINARY (ASCII-8BIT)>
        p raw.bytes                # [99, 97, 102, 195, 169]

        # --- request a specific external encoding ---------------------------------
        latin = File.read(path, encoding: "ISO-8859-1")
        p latin.encoding           # #<Encoding:ISO-8859-1>  -- same bytes, retagged
        p latin.bytes              # [99, 97, 102, 195, 169]

        # ...and an internal encoding TRANSCODES on the way in.
        utf = File.read(path, external_encoding: "ISO-8859-1", internal_encoding: "UTF-8")
        p utf.encoding             # #<Encoding:UTF-8>
        p utf.bytesize             # 7  -- the two Latin-1 high bytes became UTF-8

        # --- binwrite round-trips arbitrary bytes ---------------------------------
        File.binwrite(path, [0, 255, 128, 10].pack("C*"))
        p File.binread(path).bytes # [0, 255, 128, 10]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<Encoding:UTF-8>
      5
      #<Encoding:BINARY (ASCII-8BIT)>
      [99, 97, 102, 195, 169]
      #<Encoding:ISO-8859-1>
      [99, 97, 102, 195, 169]
      #<Encoding:UTF-8>
      7
      [0, 255, 128, 10]
    OUT
  end

  it "io nul bytes" do
    result = ze0(<<~'RUBY')
      r, w = IO.pipe
      w.write("hello\0world")
      w.close
      data = r.read(100)
      puts "got " + data.length.to_s + " bytes"
      p data.bytes.length
      p data[5].ord
      r.close

      path = "/tmp/sp_nul_file_#{Process.pid}"
      File.write(path, "a\0b\0c")
      s = File.read(path)
      p s.length
      p s.bytes
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      got 11 bytes
      11
      0
      5
      [97, 0, 98, 0, 99]
    OUT
  end

  it "io shovel chains binary and text arguments byte faithfully" do
    result = ze0(<<~'RUBY')
      path = "/tmp/zeo_e2e_binshovel_#{Process.pid}"
      File.open(path, "wb") { |f| f << 180.chr << "a" }
      p File.binread(path).bytes
      File.delete(path)
      p STDOUT.write("")
    RUBY

    _(result).must_answer "[180, 97]\n0\n"
  end

  it "io write sends raw bytes and answers the byte count" do
    result = ze0(<<~'RUBY')
      # 1 binary byte + 2 UTF-8 bytes for "é" + 2 display bytes for 42 = 5;
      # the count is BYTES, not characters.

      path = "/tmp/zeo_e2e_binwrite_#{Process.pid}"
      File.open(path, "wb") { |f| p f.write(180.chr, "é", 42) }
      p File.binread(path).bytes
      File.delete(path)
    RUBY

    _(result).must_answer "5\n[180, 195, 169, 52, 50]\n"
  end

  it "iso2022jp kddi converts through its stateless form" do
    result = ze0(<<~'RUBY')
      # ISO-2022-JP-KDDI is stateless-ISO-2022-JP-KDDI's characters between
      # escapes, written and read as String#encode and a Converter do.
      def t(s, to, **o)
        r = s.encode(to, **o)
        p [r.encoding.name, r.b]
      rescue => e
        p [e.class, e.message]
      end
      k = ->(s) { s.b.force_encoding("ISO-2022-JP-KDDI") }
      t "日本a", "ISO-2022-JP-KDDI"
      t "a日☀b", "ISO-2022-JP-KDDI"
      t "é", "ISO-2022-JP-KDDI", undef: :replace
      t "ｱ日", "ISO-2022-JP-KDDI", undef: :replace
      t k["\e$B\x21\x21\e(B"], "UTF-8"
      t k["a\e$BF|"], "UTF-8"
      t k["\e$BF\e(B"], "UTF-8"
      t k["\xC3"], "UTF-8"
      t k["\e$B\x7F\x21\e(B"], "UTF-8"
      t k["\e(Ia\e(B"], "UTF-8"
      t k["\e$BF|\e(Jx"], "EUC-JP"
      t "\x92\xC6\xFC".b.force_encoding("stateless-ISO-2022-JP-KDDI"), "ISO-2022-JP-KDDI"
      t "日".encode("EUC-JP"), "ISO-2022-JP-KDDI"
      ec = Encoding::Converter.new("UTF-8", "ISO-2022-JP-KDDI")
      p ec.convert("日a").b, ec.finish.b
      p Encoding::Converter.new("ISO-2022-JP-KDDI", "UTF-8").convert(k["\e$BF|\e(B"])

    RUBY

    _(result).must_answer <<~'OUT'
      ["ISO-2022-JP-KDDI", "\e$BF|K\\\e(Ba"]
      ["ISO-2022-JP-KDDI", "a\e$BF|uA\e(Bb"]
      ["ISO-2022-JP-KDDI", "?"]
      ["ISO-2022-JP-KDDI", "?\e$BF|\e(B"]
      ["UTF-8", "\xE3\x80\x80"]
      ["UTF-8", "a\xE6\x97\xA5"]
      [Encoding::InvalidByteSequenceError, "\"F\" followed by \"\\e\" on ISO-2022-JP-KDDI"]
      [Encoding::InvalidByteSequenceError, "\"\\xC3\" on ISO-2022-JP-KDDI"]
      [Encoding::InvalidByteSequenceError, "\"\\x7F\" on ISO-2022-JP-KDDI"]
      [Encoding::InvalidByteSequenceError, "\"\\e(\" followed by \"I\" on ISO-2022-JP-KDDI"]
      ["EUC-JP", "\xC6\xFCx"]
      ["ISO-2022-JP-KDDI", "\e$BF|\e(B"]
      ["ISO-2022-JP-KDDI", "\e$BF|\e(B"]
      "\e$BF|\e(Ba"
      ""
      "日"
    OUT
  end

  it "append_as_bytes, bytesplice and scrub! answer the new text on a frozen receiver" do
    result = ze0(<<~'RUBY')
      s1 = "abc"; r1 = (s1.append_as_bytes("de") rescue $!.class); p r1
      s2 = "hello"; r2 = (s2.bytesplice(0, 2, "HE") rescue $!.class); p r2
      s3 = "hello"; r3 = (s3.bytesplice(0..1, "HE") rescue $!.class); p r3
      s4 = "abc\x80def"; r4 = (s4.scrub!("?") rescue $!.class); p r4
      p "abc\x80def".scrub("?")
      m1 = +"abc"; m1.append_as_bytes("de"); p m1
      m2 = +"hello"; m2.bytesplice(0, 2, "HE"); p m2
    RUBY

    _(result).must_answer <<~'OUT'
      "abcde"
      "HEllo"
      "HEllo"
      "abc?def"
      "abc?def"
      "abcde"
      "HEllo"
    OUT
  end

  it "encode! and force_encoding answer the receiver's text on a frozen string" do
    result = ze0(<<~'RUBY')
      s1 = "hello"; r1 = (s1.encode!("UTF-8") rescue $!.class); p r1
      s2 = "hello"; r2 = (s2.force_encoding("UTF-8") rescue $!.class); p r2
      p "hello".encode("UTF-8")
      p "hello".b
      m = +"hello"; p m.force_encoding("UTF-8"); p m.encode!("UTF-8")
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "hello"
      "hello"
      "hello"
      "hello"
      "hello"
    OUT
  end

  it "scrub! answers the string whether or not there was anything to scrub" do
    result = ze0(<<~'RUBY')
      s1 = "hello"; r1 = (s1.scrub! rescue $!.class); p r1
      s2 = "hello"; r2 = (s2.scrub!("?") rescue $!.class); p r2
      p("hello".scrub!)
      s3 = "abc\x80def"; r3 = (s3.scrub!("?") rescue $!.class); p r3
      m = +"abc\x80def"; p m.scrub!("?")
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "hello"
      "hello"
      "abc?def"
      "abc?def"
    OUT
  end

  it "issue string ops on broken encoding" do
    result = ze0(<<~'RUBY')
      # Ruby REFUSES a String operation that has to READ characters when the
      # receiver's bytes are not valid in its own encoding. zeo renders a bad byte as
      # U+FFFD (`StrBuf::to_utf8_lossy`) and used to answer anyway.
      #
      # The gate is selective, exactly as CRuby's is: `#length`, `#chars`, `#reverse`,
      # `#lstrip`, `#index`, `#slice` and friends count or move by bytes and answer
      # fine on a broken string. Only a row that interprets a character raises -- and
      # it raises in one of four shapes, because CRuby reaches the check from four
      # different places. All oracle-verified.

      s = "caf\xC3 x".dup.force_encoding("UTF-8")
      p s.valid_encoding?

      def show(label)
        r = yield
        puts "#{label}\tOK #{r.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}\t#{e.class}\t#{e.message}"
      end

      # ArgumentError "input string invalid" -- the case-mapping family, which
      # raises out of the case-fold pass rather than the encoding check.
      show("upcase")     { s.upcase }
      show("downcase")   { s.downcase }
      show("capitalize") { s.capitalize }
      show("swapcase")   { s.swapcase }
      show("casecmp?")   { s.casecmp?("x") }

      # ArgumentError "invalid byte sequence in UTF-8" -- everything that walks
      # characters to do its work.
      show("squeeze")   { s.squeeze }
      show("codepoints"){ s.codepoints }
      show("count")     { s.count("x") }
      show("delete")    { s.delete("x") }
      show("tr")        { s.tr("x", "y") }
      show("scan")      { s.scan(/x/) }
      show("split")     { s.split(" ") }
      show("sub")       { s.sub(/x/, "y") }
      show("gsub")      { s.gsub(/x/, "y") }
      show("match")     { s.match(/x/) }
      show("normalize") { s.unicode_normalize }

      # Encoding::CompatibilityError -- `strip`/`rstrip` scan BACKWARD and reach the
      # check through `rb_enc_check`. `lstrip` scans forward and does not raise.
      show("strip")  { s.strip }
      show("rstrip") { s.rstrip }
      show("lstrip") { s.lstrip }

      # EncodingError -- a symbol carries its bytes, so ruby refuses to mint one it
      # could not spell back, and echoes the would-be symbol.
      show("to_sym") { s.to_sym }
      show("intern") { s.intern }

      # The rows that deliberately do NOT gate.
      show("length")  { s.length }
      show("size")    { s.size }
      show("chars")   { s.chars }
      show("bytes")   { s.bytes.size }
      show("reverse") { s.reverse.bytes.size }
      show("chomp")   { s.chomp.bytes.size }
      show("index")   { s.index("x") }
      show("include") { s.include?("x") }
      show("slice")   { s.slice(0, 2) }
      show("ord")     { s.ord }
      show("succ")    { s.succ.bytes.size }
      show("b")       { s.b.encoding }
      show("valid")   { s.valid_encoding? }
      show("ascii")   { s.ascii_only? }

      # `#encode` is the converter's own error, and it names the byte that broke the
      # sequence: a valid multi-byte PREFIX reports what followed it, a byte that is
      # no lead at all is plain, and a prefix cut off by end-of-string is incomplete.
      {
        "C3_space"  => "a\xC3 b",
        "C3_end"    => "a\xC3",
        "FF_space"  => "a\xFF b",
        "E3_81_sp"  => "a\xE3\x81 b",
        "E3_81_end" => "a\xE3\x81",
        "C2_41"     => "a\xC2Ab",
        "C0_space"  => "a\xC0 b",
        "F5_space"  => "a\xF5 b",
        "80_alone"  => "a\x80b",
        "E0_80"     => "a\xE0\x80b",
        "ED_A0"     => "a\xED\xA0\x80b",
        "F4_90"     => "a\xF4\x90\x80\x80b",
      }.each do |label, bytes|
        show(label) { bytes.dup.force_encoding("UTF-8").encode("UTF-16").bytes.size }
      end

      # A VALID string is untouched by any of it.
      ok = "café x"
      p [ok.upcase, ok.strip, ok.to_sym, ok.count("é"), ok.split(" ")]
    RUBY

    _(result).must_answer <<~'OUT'
      false
      upcase	ArgumentError	input string invalid
      downcase	ArgumentError	input string invalid
      capitalize	ArgumentError	input string invalid
      swapcase	ArgumentError	input string invalid
      casecmp?	ArgumentError	input string invalid
      squeeze	ArgumentError	invalid byte sequence in UTF-8
      codepoints	ArgumentError	invalid byte sequence in UTF-8
      count	ArgumentError	invalid byte sequence in UTF-8
      delete	ArgumentError	invalid byte sequence in UTF-8
      tr	ArgumentError	invalid byte sequence in UTF-8
      scan	ArgumentError	invalid byte sequence in UTF-8
      split	ArgumentError	invalid byte sequence in UTF-8
      sub	ArgumentError	invalid byte sequence in UTF-8
      gsub	ArgumentError	invalid byte sequence in UTF-8
      match	ArgumentError	invalid byte sequence in UTF-8
      normalize	ArgumentError	invalid byte sequence in UTF-8
      strip	Encoding::CompatibilityError	invalid byte sequence in UTF-8
      rstrip	Encoding::CompatibilityError	invalid byte sequence in UTF-8
      lstrip	OK "caf\xC3 x"
      to_sym	EncodingError	invalid symbol in encoding UTF-8 :"caf\xC3 x"
      intern	EncodingError	invalid symbol in encoding UTF-8 :"caf\xC3 x"
      length	OK 6
      size	OK 6
      chars	OK ["c", "a", "f", "\xC3", " ", "x"]
      bytes	OK 6
      reverse	OK 6
      chomp	OK 6
      index	OK 5
      include	OK true
      slice	OK "ca"
      ord	OK 99
      succ	OK 6
      b	OK #<Encoding:BINARY (ASCII-8BIT)>
      valid	OK false
      ascii	OK false
      C3_space	Encoding::InvalidByteSequenceError	"\xC3" followed by " " on UTF-8
      C3_end	Encoding::InvalidByteSequenceError	incomplete "\xC3" on UTF-8
      FF_space	Encoding::InvalidByteSequenceError	"\xFF" on UTF-8
      E3_81_sp	Encoding::InvalidByteSequenceError	"\xE3\x81" followed by " " on UTF-8
      E3_81_end	Encoding::InvalidByteSequenceError	incomplete "\xE3\x81" on UTF-8
      C2_41	Encoding::InvalidByteSequenceError	"\xC2" followed by "A" on UTF-8
      C0_space	Encoding::InvalidByteSequenceError	"\xC0" on UTF-8
      F5_space	Encoding::InvalidByteSequenceError	"\xF5" on UTF-8
      80_alone	Encoding::InvalidByteSequenceError	"\x80" on UTF-8
      E0_80	Encoding::InvalidByteSequenceError	"\xE0" followed by "\x80" on UTF-8
      ED_A0	Encoding::InvalidByteSequenceError	"\xED" followed by "\xA0" on UTF-8
      F4_90	Encoding::InvalidByteSequenceError	"\xF4" followed by "\x90" on UTF-8
      ["CAFÉ X", "café x", :"café x", 1, ["café", "x"]]
    OUT
  end

  it "multibyte cjk encodings walk transcode and error shapes" do
    result = ze0(<<~'RUBY')
      # The multibyte CJK rows (Shift_JIS / Windows-31J / EUC-JP / GBK / Big5):
      # structural walking is CRuby-faithful (a valid-but-unmapped pair is a real
      # character), mapping via encoding_rs; char ops, transcode round trips,
      # Integer#chr / << codepoint splits, and all three
      # InvalidByteSequenceError message forms. Verbatim ruby 4.0.6 output.

      sj = "あいz".encode("Shift_JIS")
      p sj.bytes
      p sj.length
      p sj.valid_encoding?
      p sj
      p sj.reverse.bytes
      p sj[0]&.bytes
      p sj.encode("UTF-8")
      e = "日本語".encode("EUC-JP")
      p e.bytes
      p e.length
      p e.encode("UTF-8")
      g = "中文".encode("GBK")
      p g.bytes
      b5 = "中文".encode("Big5")
      p b5.bytes
      p g.encode("Big5") == b5
      w = "アｱ".encode("Windows-31J")
      p w.bytes
      p w.encoding
      p 0x82A0.chr(Encoding::Shift_JIS).bytes
      s2 = "".force_encoding("Shift_JIS"); s2 << 0x82A0; s2 << 65; p s2.bytes
      begin; 0x8200.chr(Encoding::Shift_JIS); rescue RangeError => ex; puts ex.message; end
      bad = 0x82.chr.force_encoding("Shift_JIS")
      p bad.valid_encoding?
      p bad.length
      p bad
      begin; bad.encode("UTF-8"); rescue Encoding::InvalidByteSequenceError => ex; puts ex.message; end
      begin; (0x82.chr + 0x00.chr).force_encoding("Shift_JIS").encode("UTF-8"); rescue Encoding::InvalidByteSequenceError => ex; puts ex.message; end
      begin; (0x82.chr + "z").force_encoding("Shift_JIS").encode("UTF-8"); rescue Encoding::UndefinedConversionError => ex; puts ex.message; end
      kana = 0xB1.chr.force_encoding("Shift_JIS")
      p kana.length
      p kana.encode("UTF-8")
    RUBY

    _(result).must_answer <<~'OUT'
      [130, 160, 130, 162, 122]
      3
      true
      "\x{82A0}\x{82A2}z"
      [122, 130, 162, 130, 160]
      [130, 160]
      "あいz"
      [198, 252, 203, 220, 184, 236]
      3
      "日本語"
      [214, 208, 206, 196]
      [164, 164, 164, 229]
      true
      [131, 65, 177]
      #<Encoding:Windows-31J>
      [130, 160]
      [130, 160, 65]
      invalid codepoint 0x8200 in Shift_JIS
      false
      1
      "\x82"
      incomplete "\x82" on Shift_JIS
      "\x82" followed by "\x00" on Shift_JIS
      "\x82z" from Shift_JIS to UTF-8
      1
      "ｱ"
    OUT
  end

  it "mutable str force encoding return" do
    result = ze0(<<~'RUBY')
      # Sequel to #441. The original fix gated force_encoding/encode/b
      # return-type inference on `recv == "string"`, which left the
      # `sp_String *` (mutable_str) receiver case unfixed. Codegen for
      # mutable_str dispatches the inner call against `rc + "->data"`,
      # so force_encoding's body emits `return lv_out->data` — a
      # `const char *`. The function signature still committed to
      # mrb_int from the default infer_call_type fallback, tripping
      # the C compile with int-from-pointer.
      #
      # Add the mutable_str arm: return "string" (the body's `->data`
      # value type), keeping the C signature aligned with the emitted
      # return expression.

      def build_via_mutable
        out = String.new
        out << "ab"
        out << "cd"
        out.force_encoding("UTF-8")
      end

      puts build_via_mutable
    RUBY

    _(result).must_answer "abcd\n"
  end

  it "poly each byte" do
    result = ze0(<<~'RUBY')
      # `each_byte` / `each_codepoint` with a block on a receiver only known to be a
      # String at run time. The poly path served each_char but not these, so the call
      # fell through to NoMethodError.

      def pick(f, s)
        f ? s : 42
      end

      v = pick(true, "hello")
      n = 0
      v.each_byte { |b| n += b }
      p n
      c = 0
      v.each_codepoint { |cp| c += cp }
      p c
    RUBY

    _(result).must_answer "532\n532\n"
  end

  it "poly string binary methods" do
    result = ze0(<<~'RUBY')
      # String#bytes / #unpack1 on a value that widened to poly (a method with
      # multiple return paths) must dispatch to the String impl, not raise
      # "undefined method for poly".
      def poly_bin
        return @c if @c
        s = [65, 66, 67, 0, 255].pack('C*')
        @c = s
        s
      end
      d = poly_bin
      puts d.bytes.inspect
      puts d[0, 3].bytes.inspect
      def poly_txt
        return @t if @t
        s = "abc"
        @t = s
        s
      end
      puts poly_txt.codepoints.inspect
      def poly_hdr
        return @h if @h
        s = [1234].pack('V')
        @h = s
        s
      end
      puts poly_hdr.unpack1('V')
    RUBY

    _(result).must_answer <<~'OUT'
      [65, 66, 67, 0, 255]
      [65, 66, 67]
      [97, 98, 99]
      1234
    OUT
  end

  it "poly string encoding" do
    result = ze0(<<~'RUBY')
      # `encoding` on a String reached through a POLY receiver. The concrete String
      # arm has answered it since #723 and the poly dispatch had no entry, so a
      # String read out of a poly array raised NoMethodError naming its own class:
      # "undefined method 'encoding' for an instance of String".
      #
      # Adding the arm was half of it. The call still had no inferred type, so
      # emit_boxed's untyped arm rendered `(expr, sp_box_nil())` -- it evaluated the
      # answer and threw it away, and the Encoding came back nil. Same shape as
      # 96c32858's write payload.

      a = ["abc", 1][0]
      p a.encoding
      p a.encoding.to_s
      p a.encoding == Encoding::UTF_8

      b = [[65].pack("C"), 1][0]
      p b.encoding.to_s

      h = { "k" => "abc" }
      p h["k"].encoding.to_s

      def enc_of(v) = v.encoding.to_s
      puts enc_of("abc")
      puts enc_of([65].pack("C"))

      # the concrete arm still answers
      p "abc".encoding
      p "abc".encoding.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      #<Encoding:UTF-8>
      "UTF-8"
      true
      "ASCII-8BIT"
      "UTF-8"
      UTF-8
      ASCII-8BIT
      #<Encoding:UTF-8>
      "UTF-8"
    OUT
  end

  it "regexp encoding introspection" do
    result = ze0(<<~'RUBY')
      # Regexp introspection: #encoding (was silently ""), #fixed_encoding?, and
      # Regexp.linear_time? (both previously rejected at compile time).

      # An ASCII-only regexp is US-ASCII and not fixed-encoding.
      p(/abc/.encoding.name)      # "US-ASCII"
      p(/abc/.encoding)           # #<Encoding:US-ASCII>
      p(/abc/.fixed_encoding?)    # false
      p(/a(b)c/.fixed_encoding?)  # false

      # A regexp with multibyte UTF-8 source is UTF-8 and fixed-encoding.
      p(/café/.encoding.name)  # "UTF-8"
      p(/café/.fixed_encoding?) # true

      # Regexp.linear_time?: true for backref-free patterns, false when a
      # backreference (which defeats the linear matcher) is present.
      p Regexp.linear_time?(/abc/)              # true
      p Regexp.linear_time?(/(a|b)*c/)          # true
      p Regexp.linear_time?(/(a)\1/)            # false  (numbered backref)
      p Regexp.linear_time?(/(?<n>\w+)\k<n>/)   # false  (named backref)

      # Backref-like syntax inside a [...] class is octal / literal, not a real
      # backreference, so the pattern stays linear; a real backref after the class
      # still trips (escaped brackets inside the class are handled too).
      p Regexp.linear_time?(/[\1]/)             # true   (\1 is octal in a class)
      p Regexp.linear_time?(/[a-z\k<x>]/)       # true   (\k literal in a class)
      p Regexp.linear_time?(/[\1](a)\1/)        # false  (class \1 ignored; real \1 caught)
      p Regexp.linear_time?(/[\]]\1(a)/)        # false  (escaped ] in class, then backref)

      # Non-literal regexp (routed through a method) defaults to the supported
      # ASCII domain.
      def s(x); x; end
      p s(/xyz/).encoding.name      # "US-ASCII"
      p s(/xyz/).fixed_encoding?    # false
      p Regexp.linear_time?(s(/xyz/))  # true
    RUBY

    _(result).must_answer <<~'OUT'
      "US-ASCII"
      #<Encoding:US-ASCII>
      false
      false
      "UTF-8"
      true
      true
      true
      false
      false
      true
      true
      false
      false
      "US-ASCII"
      false
      true
    OUT
  end

  it "single byte transcoding round trips and error shapes" do
    result = ze0(<<~'RUBY')
      pl = "żółć gęś"
      w = pl.encode("Windows-1250")
      p w.bytes
      p w.encoding.name
      p w.encode("UTF-8") == pl
      r = "привет".encode("Windows-1251")
      p r.bytes
      p r.encode("KOI8-R").bytes
      p "€uro".encode("ISO-8859-15").bytes
      b = 0x81.chr.force_encoding("Windows-1252")
      begin; b.encode("UTF-8"); rescue Encoding::UndefinedConversionError => e; puts e.message; end
      begin; b.encode("KOI8-R"); rescue Encoding::UndefinedConversionError => e; puts e.message; end
      p b.encode("UTF-8", undef: :replace)
      begin; "щ".encode("Windows-1252"); rescue Encoding::UndefinedConversionError => e; puts e.message; end
      s = (0xE9.chr + 0x81.chr + "ab").force_encoding("Windows-1252")
      p s
      p (0xE9.chr + "ab").force_encoding("Windows-1252").encode("UTF-8")
    RUBY

    _(result).must_answer <<~'OUT'
      [191, 243, 179, 230, 32, 103, 234, 156]
      "Windows-1250"
      true
      [239, 240, 232, 226, 229, 242]
      [208, 210, 201, 215, 197, 212]
      [164, 117, 114, 111]
      "\x81" to UTF-8 in conversion from Windows-1252 to UTF-8
      "\x81" to UTF-8 in conversion from Windows-1252 to UTF-8 to KOI8-R
      "�"
      U+0449 to WINDOWS-1252 in conversion from UTF-8 to WINDOWS-1252
      "\xE9\x81ab"
      "éab"
    OUT
  end

  it "source file is bytes not utf8" do
    result = ze0(<<~'RUBY', files: beside("source_bytes/latin1_comment.rb"))
      # Ruby source is a byte stream, not text. CRuby reads a file with the
      # default UTF-8 source encoding and simply SKIPS a byte that is not valid
      # UTF-8 when it sits in a comment -- only code has to decode. A required
      # library whose copyright line carries a Latin-1 (c) therefore loads, and
      # every definition in it is reachable.
      require_relative "source_bytes/latin1_comment"

      puts Greeter.new.hello
      p Greeter.instance_method(:hello).arity
    RUBY

    _(result).must_answer "hi\n0\n"
  end

  it "stdout receives a binary strings raw byte" do
    result = ze0(<<~'RUBY')
      # The harness captures stdout lossily, so the RAW 0xB4 byte surfaces
      # as one U+FFFD replacement char -- whereas a promoted output
      # (0xC2 0xB4) would decode "cleanly" as U+00B4. The replacement char IS
      # the proof the byte reached the fd untouched; the byte-count return
      # (1, not 2) pins it from a second angle.

      n = $stdout.write(180.chr)
      puts
      p n
    RUBY

    _(result).must_answer "\xB4\n1\n".b
  end

  it "str force encoding return" do
    result = ze0(<<~'RUBY')
      # `def f(s); s.force_encoding(...); end` whose body's last
      # expression is `force_encoding` (a receiver passthrough at codegen)
      # previously had its return type inferred as mrb_int — the function
      # signature returned mrb_int while the body returned a const char *.
      #
      # Codegen already lowers force_encoding (and encode / b) as a
      # receiver passthrough at line 13953; the analyze side just had no
      # matching infer_call_type arm, so the call's static type fell back
      # to "int". Add force_encoding / encode / b to infer_call_type's
      # string-recv arm so the return type carries through.

      def normalize(s)
        s.force_encoding("UTF-8")
      end

      def utf8_to_bin(s)
        s.encode("ASCII-8BIT")
      end

      def to_binary(s)
        s.b
      end

      puts normalize("hello")
      puts utf8_to_bin("world")
      puts to_binary("bytes")
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      world
      bytes
    OUT
  end

  it "string append as bytes int" do
    result = ze0(<<~'RUBY')
      # String#append_as_bytes accepts Integer byte values (100 -> "d") as well as
      # Strings, and a mix of both.
      a = "abc"; a.append_as_bytes(100, 101); p a
      b = "x"; b.append_as_bytes("y", 122); p b
      c = "".dup; c.append_as_bytes(72, 73); p c
    RUBY

    _(result).must_answer <<~'OUT'
      "abcde"
      "xyz"
      "HI"
    OUT
  end

  it "string append binary safe" do
    result = ze0(<<~'RUBY')
      # String#<< must preserve embedded NUL bytes: a mutable string's payload buffer
      # is length-tracked (a header on the 0xfd buffer), not NUL-terminated, so
      # appending content that begins with (or contains) 0x00 keeps every byte.
      # (matz/spinel#1479)

      a = "a"; a << "\x00"
      puts a.length                 # 2

      b = "a"; b << 0.chr
      puts b.length                 # 2

      c = String.new
      c << 126.chr; c << 0.chr; c << 200.chr
      puts c.length                 # 3
      puts c.bytes.inspect          # [126, 0, 200]

      # Operand carrying an interior NUL.
      d = "x"
      d << "\x7e\x00\xc8"
      puts d.bytesize               # 4
      puts d.bytes.inspect          # [120, 126, 0, 200]

      # A WebSocket extended-length header (0x7e 0x00 <lo>) survives the emit path.
      payload = "y" * 130
      frame = String.new
      frame << 0x81.chr << 0x7e.chr << ((payload.bytesize >> 8) & 0xFF).chr << (payload.bytesize & 0xFF).chr
      frame << payload
      puts frame.bytesize           # 134
      puts frame.getbyte(2)         # 0
      puts frame.getbyte(3)         # 130

      # Mutating via <<, then reading the escaped value (length over a const char*).
      e = "ab"
      e << 0.chr
      e << "cd"
      puts e.length                 # 5
      puts (e + "!").bytesize       # 6

      # String#+ (already binary-safe) still agrees.
      puts ("a" + "\x00").length    # 2
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      3
      [126, 0, 200]
      4
      [120, 126, 0, 200]
      134
      0
      130
      5
      6
      2
    OUT
  end

  it "string encode newline option" do
    result = ze0(<<~'RUBY')
      # `String#encode`'s newline-rewrite options are ignored: zeo returns the
      # input unchanged for `newline: :cr`/`:crlf` and the `cr_newline:`/
      # `crlf_newline:` spellings, where ruby rewrites the newlines.
      # `universal_newline: true` already agrees. Hypothesis: the encode option
      # parser (`builtins/string.rs::parse_encode_opts`) reads the universal
      # option only. (Found by the 2026-08-24 probe sweep.)
      p "a\nb".encode("UTF-8", newline: :cr)
      p "a\nb".encode("UTF-8", newline: :crlf)
      p "a\nb".encode("UTF-8", crlf_newline: true)
      p "a\r\nb".encode("UTF-8", universal_newline: true)
    RUBY

    _(result).must_answer <<~'OUT'
      "a\rb"
      "a\r\nb"
      "a\r\nb"
      "a\nb"
    OUT
  end

  it "string encoding" do
    result = ze0(<<~'RUBY')
      # Issue #723. `.encoding` returns the source label (spinel uses
      # UTF-8 throughout) as a small Encoding value.

      puts "hello".encoding
      puts "x".encode.encoding
      puts "y".b.encoding
      puts "hello".encoding.class
      puts "hello".encoding.name
    RUBY

    _(result).must_answer <<~'OUT'
      UTF-8
      UTF-8
      ASCII-8BIT
      Encoding
      UTF-8
    OUT
  end

  it "string encoding ivar wire and roundtrip" do
    result = ze0(<<~'RUBY')
      # A String's `I`-wrapper carries its encoding -- `E => true` (UTF-8),
      # `E => false` (US-ASCII), `encoding => "<name>"` (other), and NO wrapper
      # for ASCII-8BIT. The encoding survives a round-trip.

      def wire(x) = Marshal.dump(x).bytes.join(",")
      def rt(x) = Marshal.load(Marshal.dump(x))
      puts wire("abc")
      puts wire("abc".b)
      puts wire("abc".encode("US-ASCII"))
      puts wire("café")
      puts wire("abc".encode("Shift_JIS"))
      puts rt("café").encoding.name
      puts rt("abc".b).encoding.name
      puts rt("abc".encode("Shift_JIS")).encoding.name
      puts rt("hello")
    RUBY

    _(result).must_answer <<~'OUT'
      4,8,73,34,8,97,98,99,6,58,6,69,84
      4,8,34,8,97,98,99
      4,8,73,34,8,97,98,99,6,58,6,69,70
      4,8,73,34,10,99,97,102,195,169,6,58,6,69,84
      4,8,73,34,8,97,98,99,6,58,13,101,110,99,111,100,105,110,103,34,14,83,104,105,102,116,95,74,73,83
      UTF-8
      ASCII-8BIT
      Shift_JIS
      hello
    OUT
  end

  it "string new builds empty and copied buffers with encoding" do
    result = ze0(<<~'RUBY')
      p String.new
      p String.new("hi")
      p String.new.encoding.name
      p String.new("x", encoding: "ASCII-8BIT").encoding.name
    RUBY

    _(result).must_answer <<~'OUT'
      ""
      "hi"
      "ASCII-8BIT"
      "ASCII-8BIT"
    OUT
  end

  it "string plus concatenates raw bytes under the compatibility rule" do
    result = ze0(<<~'RUBY')
      s = 181.chr + "\n"
      p s.encoding
      p s.bytes
      a = "x".encode("US-ASCII")
      p (a + "y").encoding
      p ("y" + a).encoding
      p ("abc" + 200.chr).encoding
    RUBY

    _(result).must_answer <<~'OUT'
      #<Encoding:BINARY (ASCII-8BIT)>
      [181, 10]
      #<Encoding:US-ASCII>
      #<Encoding:UTF-8>
      #<Encoding:BINARY (ASCII-8BIT)>
    OUT
  end

  it "string replace adopts the sources bytes and encoding" do
    result = ze0(<<~'RUBY')
      # ruby's `rb_str_replace` copies the source's bytes AND encoding onto the
      # receiver -- no transcoding, whatever encoding the receiver was born with.
      b = +"seed"
      b.replace("h\xC3\xA9".b)
      p [b.encoding.to_s, b.bytes]

      x = +"seed"
      x.replace("hi".b)
      p [x.encoding.to_s, x.bytes]

      u = +"".b
      u.replace("héllo")
      p [u.encoding.to_s, u.bytesize]

      f = (+"seed").replace("h\xC3\xA9".b)
      p [f.force_encoding("UTF-8"), f.bytes]
    RUBY

    _(result).must_answer <<~'OUT'
      ["ASCII-8BIT", [104, 195, 169]]
      ["ASCII-8BIT", [104, 105]]
      ["UTF-8", 6]
      ["hé", [104, 195, 169]]
    OUT
  end

  it "string scrub with a block" do
    result = ze0(<<~'RUBY')
      # `String#scrub` ignores its BLOCK: zeo substitutes the default replacement
      # where ruby yields each invalid byte run and splices the block's result.
      # The no-argument and string-argument forms agree. (Found by the 2026-08-24
      # probe sweep.)
      p "a\xFFb".scrub { |c| "<#{c.unpack1('H*')}>" }
      p "\xC3(ok".scrub { |c| "[#{c.bytes.join(',')}]" }
    RUBY

    _(result).must_answer <<~'OUT'
      "a<ff>b"
      "[195](ok"
    OUT
  end

  it "string shovel appends bytes and codepoints in the receivers encoding" do
    result = ze0(<<~'RUBY')
      # `"".b << 181` is the single raw byte 0xB5; a UTF-8 receiver encodes
      # the codepoint (an emoji is 4 bytes); a binary append composes.

      b = "".b
      b << 181
      p b.bytes
      u = +"xy"
      u << 0x1F600
      p u.bytesize
      c = 180.chr
      c << 5.chr
      p c.bytes
    RUBY

    _(result).must_answer <<~'OUT'
      [181]
      6
      [180, 5]
    OUT
  end

  it "xml attr escapes the apostrophe" do
    result = ze0(<<~'RUBY')
      # xml: :attr escapes the apostrophe as &apos;, as enc/trans/escape.trans
      # does, both through String#encode and through a Converter.

      p "a'b\"<&>".encode(xml: :attr)
      p "a'b\"<&>".encode(xml: :text)
      p "a'b".encode("UTF-16LE", xml: :attr).encode("UTF-8")
      ec = Encoding::Converter.new("UTF-8", "EUC-JP", xml: :attr)
      p ec.convert("it's")
      p ec.finish

    RUBY

    _(result).must_answer <<~'OUT'
      "\"a&apos;b&quot;&lt;&amp;&gt;\""
      "a'b\"&lt;&amp;&gt;"
      "\"a&apos;b\""
      "\"it&apos;s"
      "\""
    OUT
  end

  it "writes GB18030 and CESU-8 past the two bytes they start with" do
    result = ze0(<<~'RUBY')
      # GB18030 holds every Unicode character: the ones a two-byte row
      # does not name take four bytes, whether or not they are past the
      # BMP. CESU-8 writes a character past the BMP as its two
      # surrogates, three bytes each, where UTF-8 writes four.
      def bytes(text, name) = text.encode(name).bytes.map { |b| b.to_s(16) }

      p bytes("\u{10000}", "GB18030")
      p bytes("\u{20BB7}", "GB18030")
      p bytes("\u{4E00}", "GB18030")
      p bytes("\u{00A5}", "GB18030")
      p "\u{20BB7}\u{4E00}A".encode("GB18030").length
      p "\u{20BB7}A".encode("GB18030").each_char.map(&:bytesize)
      p "\u{20BB7}\u{4E00}A".encode("GB18030").encode("UTF-8")
      p "\x95\x32\x82\x36".dup.force_encoding("GB18030").encode("UTF-8").ord.to_s(16)

      p bytes("\u{10000}", "CESU-8")
      p bytes("\u{4E00}", "CESU-8")
      p "\u{10000}A".encode("CESU-8").length
      p "\u{1D11E}x".encode("CESU-8").encode("UTF-8")
      p "\xED\xA0\x80\xED\xB0\x80".dup.force_encoding("CESU-8").encode("UTF-8").ord.to_s(16)
    RUBY

    _(result).must_answer <<~'OUT'
      ["90", "30", "81", "30"]
      ["95", "34", "b2", "35"]
      ["d2", "bb"]
      ["81", "30", "84", "36"]
      3
      [4, 1]
      "𠮷一A"
      "20000"
      ["ed", "a0", "80", "ed", "b0", "80"]
      ["e4", "b8", "80"]
      2
      "𝄞x"
      "10000"
    OUT
  end

  it "encode with invalid: :replace replaces bad bytes of a US-ASCII or UTF-8 source" do
    result = ze0(<<~'RUBY')
      def t(s, to, **o)
        r = s.encode(to, **o)
        p [r, r.encoding]
      rescue => e
        p [e.class, e.message]
      end
      t "a\xE9".force_encoding("US-ASCII"), "UTF-8", invalid: :replace
      t "a\xE9b", "UTF-8", invalid: :replace
      t "a\xE9b", "UTF-8", invalid: :replace, replace: "?"
      t "a\xE9b", "UTF-16LE", invalid: :replace
      t "a\xE9b".force_encoding("US-ASCII"), "ISO-8859-1", invalid: :replace
    RUBY

    _(result).must_answer <<~'OUT'
      ["a�", #<Encoding:UTF-8>]
      ["a�b", #<Encoding:UTF-8>]
      ["a?b", #<Encoding:UTF-8>]
      ["a\uFFFDb", #<Encoding:UTF-16LE>]
      ["a?b", #<Encoding:ISO-8859-1>]
    OUT
  end

  it "encode with invalid: :replace keeps the byte after a bad lead byte of a double-byte encoding" do
    result = ze0(<<~'RUBY')
      def t(bytes, from)
        r = bytes.b.force_encoding(from).encode("UTF-8", invalid: :replace)
        p [from, r]
      rescue => e
        p [from, e.class, e.message]
      end
      t "\x81\x30", "Shift_JIS"
      t "\x81\x7F", "GBK"
      t "\xA1\x30", "Big5"
      t "\x81\x30", "CP949"
      t "\xA1\x30", "EUC-JP"
      t "\xA1\x30", "EUC-KR"
      t "\x81\x30", "Windows-31J"
    RUBY

    _(result).must_answer <<~'OUT'
      ["Shift_JIS", "�0"]
      ["GBK", "�\u007F"]
      ["Big5", "�0"]
      ["CP949", "�0"]
      ["EUC-JP", "�0"]
      ["EUC-KR", "�0"]
      ["Windows-31J", "�0"]
    OUT
  end

  it "encode with invalid: :replace replaces for GB18030, CESU-8, UTF8-MAC, ISO-2022-JP and the BOM encodings" do
    result = ze0(<<~'RUBY')
      def t(bytes, from, to = "UTF-8")
        r = bytes.b.force_encoding(from).encode(to, invalid: :replace)
        p [from, r]
      rescue => e
        p [from, e.class, e.message]
      end
      t "\x81\x30", "GB18030"
      t "\xED\xA0\xBDA", "CESU-8"
      t "a\xFF", "UTF8-MAC"
      t "a\e$Bx", "ISO-2022-JP"
      t "\xFF\xFEa\x00\x00\xD8", "UTF-16"
      t "\xFF\xFE\x00\x00a\x00\x00\x00\x00\xD8\x00\x00", "UTF-32"
    RUBY

    _(result).must_answer <<~'OUT'
      ["GB18030", "�"]
      ["CESU-8", "�A"]
      ["UTF8-MAC", "a?"]
      ["ISO-2022-JP", "a�"]
      ["UTF-16", "a�"]
      ["UTF-32", "a�"]
    OUT
  end

  it "the newline options of encode to UTF-16" do
    result = ze0(<<~'RUBY')
      def t(s, to, **o)
        r = s.encode(to, **o)
        p [r.b, r.encoding]
      rescue => e
        p [e.class, e.message]
      end
      t "a\nb", "UTF-16LE", crlf_newline: true
      t "a\r\nb", "UTF-16BE", universal_newline: true
      t "a\nb", "UTF-32LE", cr_newline: true
      t "a\r\nb".encode("UTF-16LE"), "UTF-8", universal_newline: true
    RUBY

    _(result).must_answer <<~'OUT'
      ["a\x00\r\x00\n\x00b\x00", #<Encoding:UTF-16LE>]
      ["\x00a\x00\n\x00b", #<Encoding:UTF-16BE>]
      ["a\x00\x00\x00\r\x00\x00\x00b\x00\x00\x00", #<Encoding:UTF-32LE>]
      ["a\nb", #<Encoding:UTF-8>]
    OUT
  end

  it "an Encoding::Converter to CESU-8 or to UTF-16" do
    result = ze0(<<~'RUBY')
      def t(from, to, s)
        c = Encoding::Converter.new(from, to)
        r = c.convert(s) + c.finish
        p [to, r.b]
      rescue => e
        p [to, e.class, e.message]
      end
      t "UTF-8", "CESU-8", "日"
      t "UTF-8", "CESU-8", "\u{1F600}"
      t "UTF-8", "UTF-16", "a"
      t "UTF-8", "UTF-32", "a"
      p "a".encode("UTF-16").b
    RUBY

    _(result).must_answer <<~'OUT'
      ["CESU-8", "\xE6\x97\xA5"]
      ["CESU-8", "\xED\xA0\xBD\xED\xB8\x80"]
      ["UTF-16", "\xFE\xFF\x00a"]
      ["UTF-32", "\x00\x00\xFE\xFF\x00\x00\x00a"]
      "\xFE\xFF\x00a"
    OUT
  end

  it "a newline or xml option to an encoding with no converter raises" do
    result = ze0(<<~'RUBY')
      def t(to, **o)
        r = "a<b".encode(to, **o)
        p [to, r.b]
      rescue => e
        p [to, e.class, e.message]
      end
      t "EUC-TW", xml: :text
      t "Emacs-Mule", crlf_newline: true
      t "GB1988", xml: :attr
      t "macThai", xml: :text
      t "EUC-TW"
    RUBY

    _(result).must_answer <<~'OUT'
      ["EUC-TW", Encoding::ConverterNotFoundError, "code converter not found (UTF-8 to EUC-TW with xml_text)"]
      ["Emacs-Mule", Encoding::ConverterNotFoundError, "code converter not found (UTF-8 to Emacs-Mule with crlf_newline)"]
      ["GB1988", Encoding::ConverterNotFoundError, "code converter not found (UTF-8 to GB1988 with xml_attr_content,xml_attr_quote)"]
      ["macThai", Encoding::ConverterNotFoundError, "code converter not found (UTF-8 to macThai with xml_text)"]
      ["EUC-TW", "a<b"]
    OUT
  end

  it "a dummy encoding refuses case mapping and concatenation, and inspect escapes each byte" do
    result = ze0(<<~'RUBY')
      %w[UTF-7 UTF-16 ISO-2022-JP IBM037].each do |enc|
        s = "abc".b.force_encoding(enc)
        r = [enc, s.inspect]
        r << (s.upcase rescue [$!.class, $!.message])
        r << (s.downcase rescue [$!.class, $!.message])
        r << ((s + "d") rescue [$!.class, $!.message])
        p r
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["UTF-7", "\"\\x61\\x62\\x63\"", [Encoding::CompatibilityError, "incompatible encoding with this operation: UTF-7"], [Encoding::CompatibilityError, "incompatible encoding with this operation: UTF-7"], [Encoding::CompatibilityError, "incompatible character encodings: UTF-7 and UTF-8"]]
      ["UTF-16", "\"\\x61\\x62\\x63\"", [Encoding::CompatibilityError, "incompatible encoding with this operation: UTF-16"], [Encoding::CompatibilityError, "incompatible encoding with this operation: UTF-16"], [Encoding::CompatibilityError, "incompatible character encodings: UTF-16 and UTF-8"]]
      ["ISO-2022-JP", "\"\\x61\\x62\\x63\"", [Encoding::CompatibilityError, "incompatible encoding with this operation: ISO-2022-JP"], [Encoding::CompatibilityError, "incompatible encoding with this operation: ISO-2022-JP"], [Encoding::CompatibilityError, "incompatible character encodings: ISO-2022-JP and UTF-8"]]
      ["IBM037", "\"\\x61\\x62\\x63\"", [Encoding::CompatibilityError, "incompatible encoding with this operation: IBM037"], [Encoding::CompatibilityError, "incompatible encoding with this operation: IBM037"], [Encoding::CompatibilityError, "incompatible character encodings: IBM037 and UTF-8"]]
    OUT
  end

  it "scrub and grapheme_clusters of broken UTF-32" do
    result = ze0(<<~'RUBY')
      s = "a\x00\x00\x00\xFF\xFF\xFF\xFFb\x00\x00".b.force_encoding("UTF-32LE")
      p [s.valid_encoding?, (s.scrub("?") rescue [$!.class, $!.message])]
      p s.scrub.b
      p s.grapheme_clusters.size
      p s.chars.size
    RUBY

    _(result).must_answer <<~'OUT'
      [false, [Encoding::CompatibilityError, "incompatible character encodings: UTF-32LE and UTF-8"]]
      "a\x00\x00\x00\xFD\xFF\x00\x00\xFD\xFF\x00\x00"
      2
      3
    OUT
  end
end
