# frozen_string_literal: true

require "spec_helper"

describe "Pack: packing and unpacking" do
  it "array pack returns string" do
    result = zr(<<~'RUBY')
      arr = [72, 105]
      result = arr.pack("C*")
      puts result.length
      puts result
    RUBY

    _(result).must_answer "2\nHi\n"
  end

  it "array pack string unpack" do
    result = zr(<<~'RUBY')
      # Array#pack and String#unpack with the common
      # numeric/string format specifiers.
      puts "ABC".unpack("C*").inspect
      puts [65, 66, 67].pack("C*")

      # Multi-spec format.
      puts [255, 0x1234].pack("Cn").bytes.inspect
      puts "\xff\x12\x34".unpack("Cn").inspect

      # String specs.
      puts ["hello", 42].pack("a5N").bytes.length    # 5 + 4 = 9
      puts "hello\x00\x00\x00*".unpack("a5N").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [65, 66, 67]
      ABC
      [255, 18, 52]
      [255, 4660]
      9
      ["hello", 42]
    OUT
  end

  it "every core directive round-trips, and the result's encoding follows what was written" do
    result = zr(<<~'RUBY')
      # Array#pack / String#unpack across the integer, string, base64, hex,
      # BER and UTF-8 directives. Verified against ruby 4.0.7.

      p [65, 66, 67].pack("C*")
      p [258].pack("v").bytes
      p [258].pack("S>").bytes
      p [-1].pack("l").bytes
      p "\x00\x00\x00\x01".unpack("N")
      p "\xff\xff\xff\xff".unpack("l")
      p "\xff\xff\xff\xff".unpack("L")
      p ["hi"].pack("a5").bytes
      p ["hi"].pack("A5").bytes
      p "abc\0de".unpack("Z*")
      p ["hello world"].pack("m")
      p "aGVsbG8=\n".unpack("m")
      p ["ff01"].pack("H*").bytes
      p [300].pack("w").bytes
      p [12354].pack("U")
      p "あ".unpack("U*")
      p [65].pack("C").encoding
      p [12354].pack("U").encoding
    RUBY

    _(result).must_answer <<~'OUT'
      "ABC"
      [2, 1]
      [1, 2]
      [255, 255, 255, 255]
      [1]
      [-1]
      [4294967295]
      [104, 105, 0, 0, 0]
      [104, 105, 32, 32, 32]
      ["abc"]
      "aGVsbG8gd29ybGQ=\n"
      ["hello"]
      [255, 1]
      [130, 44]
      "あ"
      [12354]
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:UTF-8>
    OUT
  end

  it "B, b, x, X and @ write bits and move the cursor, and the result carries an encoding" do
    result = zr(<<~'RUBY')
      # `Array#pack`'s bit-string and position directives, and the encoding the
      # result carries. `unpack` had all of these; `pack` was missing `B`, `b` and
      # `x` entirely and raised `unsupported pack directive`.

      def show(label)
        puts format("%-22s %s", label, (yield).inspect)
      rescue => e
        puts format("%-22s %s: %s", label, e.class, e.message.to_s[0, 44])
      end

      show("B bit string")      { ["01000001"].pack("B*").bytes }
      show("b bit string")      { ["10000010"].pack("b*").bytes }
      show("B partial byte")    { ["0100"].pack("B*").bytes }
      show("b partial byte")    { ["1000"].pack("b*").bytes }
      show("B fixed count")     { ["01000001"].pack("B4").bytes }
      show("B non-binary char") { ["0x0y"].pack("B*").bytes }
      show("B round trip")      { ["01000001"].pack("B*").unpack1("B*") }
      show("b round trip")      { ["10000010"].pack("b*").unpack1("b*") }
      show("x null pad")        { [].pack("x3").bytes }
      show("x default")         { [].pack("x").bytes }
      show("x between")         { [65, 66].pack("CxC").bytes }
      show("X back up")         { [65, 66].pack("CCX").bytes }
      show("@ absolute")        { [65].pack("C@4").bytes }

      # The result's encoding: a template starts at US-ASCII and only moves down.
      # `m`/`M`/`u` write ASCII text, `U` lifts to UTF-8, anything writing raw
      # bytes pins it at ASCII-8BIT.
      show("empty template")    { [].pack("").encoding.to_s }
      show("B encoding")        { ["01"].pack("B*").encoding.to_s }
      show("x encoding")        { [].pack("x").encoding.to_s }
      show("m encoding")        { ["hi"].pack("m0").encoding.to_s }
      show("M encoding")        { ["hi"].pack("M").encoding.to_s }
      show("u encoding")        { ["hi"].pack("u").encoding.to_s }
      show("U encoding")        { [233].pack("U*").encoding.to_s }
      show("U then m")          { [65, "hi"].pack("Um").encoding.to_s }
      show("m then U")          { ["hi", 65].pack("mU").encoding.to_s }
      show("U then C")          { [65, 66].pack("UC").encoding.to_s }
      show("C encoding")        { [65].pack("C*").encoding.to_s }
      show("@ encoding")        { [].pack("@2").encoding.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      B bit string           [65]
      b bit string           [65]
      B partial byte         [64]
      b partial byte         [1]
      B fixed count          [64]
      B non-binary char      [16]
      B round trip           "01000001"
      b round trip           "10000010"
      x null pad             [0, 0, 0]
      x default              [0]
      x between              [65, 0, 66]
      X back up              [65]
      @ absolute             [65, 0, 0, 0]
      empty template         "US-ASCII"
      B encoding             "ASCII-8BIT"
      x encoding             "ASCII-8BIT"
      m encoding             "US-ASCII"
      M encoding             "US-ASCII"
      u encoding             "US-ASCII"
      U encoding             "UTF-8"
      U then m               "UTF-8"
      m then U               "UTF-8"
      U then C               "ASCII-8BIT"
      C encoding             "ASCII-8BIT"
      @ encoding             "ASCII-8BIT"
    OUT
  end

  it "p and P write a machine pointer and keep the string it points at reachable" do
    result = zr(<<~'RUBY')
      # `p` and `P` write a MACHINE POINTER, so the packed string has to keep the
      # strings it points at reachable: CRuby hangs them off the result in a hidden
      # ivar and `unpack` looks the pointer up there, handing back THE ORIGINAL
      # STRING OBJECT -- which is why `p`'s answer keeps that string's encoding and
      # is `equal?` to it. A pointer no list explains is an error, but a NULL one is
      # just nil, so eight zero bytes unpack fine.
      #
      # `P<n>`'s count is a WIDTH, not a repeat: it checks the buffer is at least
      # that long, then writes one pointer and consumes one element.

      def t(label)
        r = begin
          yield.inspect
        rescue Exception => e
          "#{e.class}: #{e.message}"
        end
        puts format("%-14s %s", label, r)
      end

      t("p size") { ["x"].pack("p").bytesize }
      t("p enc") { ["x"].pack("p").encoding.to_s }
      t("p ivars") { ["x"].pack("p").instance_variables }
      t("p rt") { ["hello"].pack("p").unpack1("p") }
      t("p rt enc") { ["hello"].pack("p").unpack1("p").encoding.to_s }
      t("p identity") { a = "who"; [a].pack("p").unpack1("p").equal?(a) }
      t("p2 size") { ["a", "b"].pack("p2").bytesize }
      t("p2 rt") { ["a", "b"].pack("p2").unpack("p2") }
      t("p star") { ["a", "b"].pack("p*").unpack("p*") }
      t("p nil") { [nil].pack("p").bytes }
      t("p nilptr") { [nil].pack("p").unpack1("p") }
      t("p nonstr") { [1].pack("p") }
      t("p frozen") { ["x"].pack("p").frozen? }
      t("p dup rt") { s = ["hey"].pack("p"); s.dup.unpack1("p") }
      t("p unassoc") { ("\x00" * 8).unpack1("p") }
      t("p junk") { ("\x01" * 8).unpack1("p") }

      t("P5 size") { ["hello"].pack("P5").bytesize }
      t("P5 rt") { ["hello"].pack("P5").unpack1("P5") }
      t("P no len") { ["hello"].pack("P").unpack1("P") }
      t("P big len") { ["hi"].pack("P").unpack1("P9") }
      t("P short") { ["hi"].pack("P9") }
      t("P nil") { [nil].pack("P").bytes }
      t("P unassoc") { ("\x00" * 8).unpack1("P5") }

      t("mixed") { ["ab", 7].pack("pN").unpack("pN") }
    RUBY

    _(result).must_answer <<~'OUT'
      p size         8
      p enc          "ASCII-8BIT"
      p ivars        []
      p rt           "hello"
      p rt enc       "UTF-8"
      p identity     true
      p2 size        16
      p2 rt          ["a", "b"]
      p star         ["a", "b"]
      p nil          [0, 0, 0, 0, 0, 0, 0, 0]
      p nilptr       nil
      p nonstr       TypeError: no implicit conversion of Integer into String
      p frozen       false
      p dup rt       "hey"
      p unassoc      nil
      p junk         ArgumentError: no associated pointer
      P5 size        8
      P5 rt          "hello"
      P no len       "h"
      P big len      "hi"
      P short        ArgumentError: too short buffer for P(2 for 9)
      P nil          [0, 0, 0, 0, 0, 0, 0, 0]
      P unassoc      nil
      mixed          ["ab", 7]
    OUT
  end

  it "<, >, ! and _ modify the directive before them rather than being read as one" do
    result = zr(<<~'RUBY')
      # Array#pack / String#unpack: honor the '<' (little-endian), '>'
      # (big-endian), '!' and '_' (native size) directive modifiers.
      # A modifier belongs to the directive before it and is not a directive
      # itself, so pack('l<l<l<l<') keeps all four elements. The doom gem
      # packs an SDL_Rect this way.

      # Round-trip: all four values must survive.
      p [1, 2, 3, 4].pack('l<l<l<l<').unpack('l<l<l<l<')

      # Byte-level pack checks (native is little-endian).
      p [0x01020304].pack('l>').bytes
      p [0x01020304].pack('l<').bytes
      p [0x0102].pack('s>').bytes
      p [0x0102].pack('s<').bytes
      p [0x0102030405060708].pack('q>').bytes
      p [0x0102030405060708].pack('q<').bytes
      p [-2].pack('l>').bytes

      # Unsigned variants.
      p [0xFFFE].pack('S>').bytes
      p [0xFFFE].pack('S<').bytes
      p [0xDEADBEEF].pack('L>').bytes
      p [0xDEADBEEF].pack('L<').bytes
      p [0x0102030405060708].pack('Q>').bytes

      # '!' and '_' select the native size; for s/S (16-bit) and q/Q (64-bit)
      # that matches the plain directive, and they must be consumed, not
      # treated as directives themselves.
      p [1, 2].pack('s!s_').bytes
      p [7].pack('s!').bytes
      p [9].pack('q!').bytes

      # Count and '*' still parse after a modifier.
      p [1, 2, 3].pack('l<3').bytes
      p [1, 2].pack('S<*').bytes

      # Cross-check against the fixed-endian directives.
      p [0x0102].pack('n').bytes == [0x0102].pack('S>').bytes
      p [0x0102].pack('v').bytes == [0x0102].pack('S<').bytes
      p [0x01020304].pack('N').bytes == [0x01020304].pack('L>').bytes
      p [0x01020304].pack('V').bytes == [0x01020304].pack('L<').bytes

      # Unpack with modifiers.
      p "\x01\x02\x03\x04".unpack('l>')
      p "\x01\x02\x03\x04".unpack('l<')
      p "\x01\x02".unpack('s>')
      p "\xFF\xFE".unpack('s>')
      p "\xFF\xFE".unpack('S>')
      p "\x01\x02\x03\x04\x05\x06\x07\x08".unpack('q>')
      p "\x01\x02\x03\x04\x05\x06\x07\x08".unpack('Q>')
      p "\x01\x00\x02\x00\x03\x00".unpack('S<3')
      p "\x2A\x00".unpack('s!')

      # Mixed (poly) array path: a string element alongside the modified directive.
      p ['abc', 0x01020304].pack('a3l>').bytes

      # Note: repeated endian modifiers ("l><") raise RangeError in CRuby, so
      # they cannot appear here (expected output is ruby-generated).
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [1, 2, 3, 4]
      [4, 3, 2, 1]
      [1, 2]
      [2, 1]
      [1, 2, 3, 4, 5, 6, 7, 8]
      [8, 7, 6, 5, 4, 3, 2, 1]
      [255, 255, 255, 254]
      [255, 254]
      [254, 255]
      [222, 173, 190, 239]
      [239, 190, 173, 222]
      [1, 2, 3, 4, 5, 6, 7, 8]
      [1, 0, 2, 0]
      [7, 0]
      [9, 0, 0, 0, 0, 0, 0, 0]
      [1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0]
      [1, 0, 2, 0]
      true
      true
      true
      true
      [16909060]
      [67305985]
      [258]
      [-2]
      [65534]
      [72623859790382856]
      [72623859790382856]
      [1, 2, 3]
      [42]
      [97, 98, 99, 1, 2, 3, 4]
    OUT
  end

  it "the float directives write IEEE-754 in the width and byte order they name" do
    result = zr(<<~'RUBY')
      # Array#pack on a Float array and the float/double directives (#pack_unpack_directives):
      # D/d/F/f native, E/e little-endian, G/g big-endian. String#unpack reads
      # the same directives back, so unpack("G") decodes what pack("G") wrote.

      # double directives: exact hex of the 8-byte IEEE-754 encoding
      puts [1.5].pack("G").unpack1("H*")
      puts [1.5].pack("E").unpack1("H*")
      puts [1.5].pack("D").unpack1("H*")
      puts [1.5].pack("d").unpack1("H*")

      # single precision (a value exactly representable in float32)
      puts [-2.5].pack("g").unpack1("H*")
      puts [-2.5].pack("e").unpack1("H*")
      puts [-2.5].pack("f").unpack1("H*")
      puts [-2.5].pack("F").unpack1("H*")

      # star count and unpack round-trip
      s = [1.5, -0.25, 1024.0].pack("G*")
      puts s.bytesize
      puts s.unpack("G*").inspect
      puts [3.25, 7.5].pack("e2").unpack("e2").inspect

      # integer directives truncate the Float toward zero, as CRuby's coercion does
      puts [1.5].pack("C*").bytes.inspect
      puts [-3.75, 200.9].pack("c2").unpack("c2").inspect

      # an Int-array receiver promotes to double under a float directive
      puts [1, 2].pack("G2").unpack("G*").inspect

      # poly (mixed int/float) receiver
      mixed = [1, 2.5]
      puts mixed.pack("E2").unpack("E*").inspect

      # an explicit count past the end pads with nil, like the integer directives
      puts "\x3F\xF8\x00\x00\x00\x00\x00\x00".unpack("GG").inspect

      # unpack1 with a literal single float directive types as an unboxed Float
      # (an_unpack1_lit_type), so the result participates in float arithmetic
      pair = [1.5, 2.25].pack("G2")
      v = pair.unpack1("G")
      puts (v * 2).inspect
      puts pair.unpack1("G", offset: 8).inspect

      # NaN / Infinity under an integer directive raise FloatDomainError, and a
      # finite double beyond the int64 range wraps modulo 2**64 (CRuby coerces
      # through an exact Integer; a plain C cast would be undefined behaviour)
      begin
        [Float::NAN].pack("C")
      rescue FloatDomainError => e
        puts "nan: #{e}"
      end
      begin
        [-Float::INFINITY].pack("q")
      rescue FloatDomainError => e
        puts "inf: #{e}"
      end
      puts [2.0e19].pack("Q").unpack1("Q")
      puts [-2.0e19].pack("q").unpack1("q")
      puts [1.0e300].pack("Q").unpack1("Q")

      # unpack1 with a literal float directive on too-short input returns nil
      # (not 0.0): unpack pads the missing values with nil
      puts "".unpack1("G").inspect
      puts "\x00\x00".unpack1("e").inspect
      puts [9.5].pack("G").unpack1("G").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      3ff8000000000000
      000000000000f83f
      000000000000f83f
      000000000000f83f
      c0200000
      000020c0
      000020c0
      000020c0
      24
      [1.5, -0.25, 1024.0]
      [3.25, 7.5]
      [1]
      [-3, -56]
      [1.0, 2.0]
      [1.0, 2.5]
      [1.5, nil]
      3.0
      2.25
      nan: NaN
      inf: -Infinity
      1553255926290448384
      -1553255926290448384
      0
      nil
      nil
      9.5
    OUT
  end

  it "an integer directive truncates a Float toward zero and refuses NaN and Infinity" do
    result = zr(<<~'RUBY')
      # An integer pack directive truncates a Float toward zero (CRuby coerces
      # through an exact Integer, so a value past the i64 range wraps modulo
      # 2**64 rather than saturating); NaN/Infinity raise FloatDomainError.

      p [1.5].pack("C*").bytes
      p [-3.75, 200.9].pack("c2").unpack("c2")
      p [2.0e19].pack("Q").unpack1("Q")
      p [-2.0e19].pack("q").unpack1("q")
      p [1.0e300].pack("Q").unpack1("Q")
      begin; [Float::NAN].pack("C"); rescue FloatDomainError => e; puts "nan: #{e}"; end
      begin; [-Float::INFINITY].pack("q"); rescue FloatDomainError => e; puts "inf: #{e}"; end
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [-3, -56]
      1553255926290448384
      -1553255926290448384
      0
      nan: NaN
      inf: -Infinity
    OUT
  end

  it "the native-size, quoted-printable and uuencode directives each round-trip" do
    result = zr(<<~'RUBY')
      # Array#pack / String#unpack: float, native-size, quoted-printable, uuencode.

      # IEEE-754 floats: D/d/E doubles, G big-endian double, F/f/e single, g BE single.
      p [1.5].pack("D").bytes
      p [1.5].pack("G").bytes
      p [1.5].pack("F").bytes
      p [3.14].pack("d").unpack("d")
      p [1.0, 2.0, 3.0].pack("E*").unpack("E*")

      # Native-size modifiers: l!/L! widen to a native long; i/I and j/J are new.
      p [1].pack("l!").bytesize
      p [1].pack("i").bytesize
      p [1].pack("j").bytesize
      p [1].pack("l_").bytesize

      # Quoted-printable (M) and uuencode (u), plus their round-trips.
      p ["hello world"].pack("M")
      p ["a=b c"].pack("M")
      p "caf=C3=A9=\n".unpack("M")
      p ["hello"].pack("u")
      p ["The quick brown fox"].pack("u")
      p ["hello world foo"].pack("u").unpack("u")
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 0, 0, 0, 0, 0, 248, 63]
      [63, 248, 0, 0, 0, 0, 0, 0]
      [0, 0, 192, 63]
      [3.14]
      [1.0, 2.0, 3.0]
      8
      4
      8
      8
      "hello world=\n"
      "a=3Db c=\n"
      ["caf\xC3\xA9"]
      "%:&5L;&\\`\n"
      "35&AE('%U:6-K(&)R;W=N(&9O>```\n"
      ["hello world foo"]
    OUT
  end

  it "a template is directive letters with an optional count, and unpack reverses pack" do
    result = zr(<<~'RUBY')
      # `Array#pack` serializes elements into a byte string by a TEMPLATE of
      # directive letters; `String#unpack` reverses it. Each directive optionally
      # takes a count (a number, or `*` for "the rest").

      # --- integers, with width and endianness -----------------------------------
      # C/S/L/Q are 8/16/32/64-bit; lowercase c/s/l/q are the signed forms.
      p [65, 66, 67].pack("C*")          # "ABC"  -- one byte each
      p [258].pack("S>").bytes           # [1, 2]    -- 16-bit, big-endian (S>)
      p [258].pack("v").bytes            # [2, 1]    -- 16-bit, little-endian (v)
      p [1].pack("N").bytes              # [0, 0, 0, 1]  -- 32-bit big-endian
      p [-1].pack("l").bytes             # [255, 255, 255, 255]  -- signed 32-bit

      # ...and back the other way:
      p "ABC".unpack("C*")               # [65, 66, 67]
      p "\x00\x00\x00\x01".unpack("N")   # [1]
      p "\xff\xff\xff\xff".unpack("l")   # [-1]   -- signed
      p "\xff\xff\xff\xff".unpack("L")   # [4294967295] -- unsigned

      # --- string fields: a (null pad), A (space pad), Z (null-terminated) --------
      p ["hi"].pack("a5").bytes          # [104, 105, 0, 0, 0]
      p ["hi"].pack("A5").bytes          # [104, 105, 32, 32, 32]
      p ["hi"].pack("Z*").bytes          # [104, 105, 0]
      p "abc\0\0".unpack("A5")           # ["abc"]  -- A strips trailing NUL/space
      p "abc\0de".unpack("Z*")           # ["abc"]  -- Z stops at the first NUL

      # --- Base64 (m), hex (H), BER (w), UTF-8 codepoints (U) ---------------------
      p ["hello world"].pack("m")        # "aGVsbG8gd29ybGQ=\n"
      p "aGVsbG8=\n".unpack("m")          # ["hello"]
      p ["ff01"].pack("H*").bytes        # [255, 1]  -- hex pairs -> bytes
      p "\xff\x01".unpack("H*")          # ["ff01"]
      p [300].pack("w").bytes            # [130, 44] -- BER compressed integer
      p "あ".unpack("U*")             # [12354]   -- decode UTF-8 codepoints
      p [12354].pack("U")                # "あ"

      # --- the result encoding ----------------------------------------------------
      # pack yields binary bytes, except an all-`U` template yields UTF-8.
      p [65].pack("C").encoding          # #<Encoding:BINARY (ASCII-8BIT)>
      p [12354].pack("U").encoding       # #<Encoding:UTF-8>
    RUBY

    _(result).must_answer <<~'OUT'
      "ABC"
      [1, 2]
      [2, 1]
      [0, 0, 0, 1]
      [255, 255, 255, 255]
      [65, 66, 67]
      [1]
      [-1]
      [4294967295]
      [104, 105, 0, 0, 0]
      [104, 105, 32, 32, 32]
      [104, 105, 0]
      ["abc"]
      ["abc"]
      "aGVsbG8gd29ybGQ=\n"
      ["hello"]
      [255, 1]
      ["ff01"]
      [130, 44]
      [12354]
      "あ"
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:UTF-8>
    OUT
  end

  it "X, @ and a count move unpack's cursor, and moving past the start raises" do
    result = zr(<<~'RUBY')
      p "abcdef".unpack("a2X2a4")
      p "hello".unpack("@2a*")
      r1 = ("abc".unpack("%C3") rescue $!.class)
      p r1
      p "abcdef".unpack("a2@0a3")
      p "abcd".unpack("C2X1C1")
      p ["ab"].pack("a2X1")
      p [65, 66].pack("C@3C")
      p [1, 2, 3].pack("C3")
      p [1, 2, 3].pack("C3").bytes
      r2 = ("abc".unpack("X5C") rescue $!.class)
      p r2
    RUBY

    _(result).must_answer <<~'OUT'
      ["ab", "abcd"]
      ["llo"]
      ArgumentError
      ["ab", "abc"]
      [97, 98, 98]
      "a"
      "A\x00\x00B"
      "\x01\x02\x03"
      [1, 2, 3]
      ArgumentError
    OUT
  end

  it "str unpack gc root" do
    result = zr(<<~'RUBY')
      # String#unpack1 on a fresh, unrooted substring must root that input across
      # unpack's internal allocations: without it, a GC triggered inside unpack
      # frees the substring and a reused slot corrupts the read.
      blob = ([0] * 200).pack('C*') + [0x11223344, 0x55667788].pack('V*') + ([0] * 200).pack('C*')
      vals = []
      20000.times do |i|
        vals << blob[200, 4].unpack1('V')
        vals << blob[204, 4].unpack1('V')
      end
      puts vals.uniq.sort.map { |v| v.to_s(16) }.inspect
      puts vals.length

      # The FORMAT string is just as exposed: unpack walks `fmt` across the same
      # per-element allocations. Pass a freshly-built, unrooted format string against
      # a stable (rooted) source so that if `fmt` were left unrooted, the GC would
      # free it mid-parse and the second field would read from a reused slot.
      src = blob[200, 8]
      ok = 0
      20000.times do
        pair = src.unpack('V' * 2)
        ok += 1 if pair[0] == 0x11223344 && pair[1] == 0x55667788
      end
      puts ok
    RUBY

    _(result).must_answer <<~'OUT'
      ["11223344", "55667788"]
      40000
      20000
    OUT
  end

  it "unpack at an offset reads the string in place" do
    result = zr(<<~'RUBY')
      # unpack and unpack1 with `offset:` read the receiver in place. `@` and
      # `X` count from the String's start, not from the offset; a chunk is
      # binary whatever the receiver's encoding.
      def show(label)
        v = yield
        v = [v, v.encoding] if v.is_a?(String)
        puts "#{label}: #{v.inspect}"
      rescue => e
        puts "#{label}: #{e.class}: #{e.message}"
      end

      str = "héllo wörld\x00tail".dup
      show("a") { str.unpack1("a3", offset: 1) }
      show("Z") { str.unpack("Z*Z*", offset: 7) }
      show("A") { "ab  \0 cd".unpack("A5a*", offset: 1) }
      show("@") { str.unpack("@2a2", offset: 3) }
      show("@ past") { str.unpack("@20a", offset: 3) }
      show("X") { str.unpack("a2X2a1", offset: 3) }
      show("X to the start") { str.unpack("Xa", offset: 3) }
      show("X past the start") { str.unpack("X4", offset: 3) }
      show("x past") { str.unpack("x40", offset: 3) }
      show("U") { str.unpack("U*", offset: 2) }
      show("U inside a character") { str.unpack("U", offset: 2) }
      show("m") { "xxaGVsbG8=".unpack1("m", offset: 2) }
      show("C") { str.unpack("C*", offset: 14) }
      show("n") { "\x00\x01\x02\x03".b.unpack("nn", offset: 1) }
      show("q") { ("\x01" * 20).b.unpack("q*", offset: 3) }
      show("H") { "\xAB\xCD\xEF".b.unpack1("H*", offset: 1) }
      show("B") { "\xAB\xCD".b.unpack1("B*", offset: 1) }
      show("w") { "\x00\x81\x01".b.unpack("w*", offset: 1) }
      show("at the end") { str.unpack("a*", offset: str.bytesize) }
      show("negative") { str.unpack("a", offset: -1) }
      show("past the end") { str.unpack("a", offset: 100) }

      class Sub < String
        def byteslice(*) = "nope"
        def getbyte(*) = 0
      end
      show("a subclass") { Sub.new("abcd").unpack("a2C", offset: 1) }
      show("a block") { r = []; "abcd".unpack("C*", offset: 2) { |c| r << c }; r }

    RUBY

    _(result).must_answer <<~'OUT'
      a: ["\xC3\xA9l", #<Encoding:BINARY (ASCII-8BIT)>]
      Z: ["w\xC3\xB6rld", "tail"]
      A: ["b", "cd"]
      @: ["\xA9l"]
      @ past: ArgumentError: @ outside of string
      X: ["ll", "l"]
      X to the start: ["\xA9"]
      X past the start: ArgumentError: X outside of string
      x past: ArgumentError: x outside of string
      U: ArgumentError: malformed UTF-8 character
      U inside a character: ArgumentError: malformed UTF-8 character
      m: ["hello", #<Encoding:BINARY (ASCII-8BIT)>]
      C: [116, 97, 105, 108]
      n: [258, nil]
      q: [72340172838076673, 72340172838076673]
      H: ["cdef", #<Encoding:US-ASCII>]
      B: ["11001101", #<Encoding:US-ASCII>]
      w: [129]
      at the end: [""]
      negative: ArgumentError: offset can't be negative
      past the end: ArgumentError: offset outside of string
      a subclass: ["bc", 100]
      a block: [99, 100]
    OUT
  end

  it "unpack bit string directives" do
    result = zr(<<~'RUBY')
      p "abcd".unpack("B8")
      p "abcd".unpack("b8")
      p "abcd".unpack("B*").first.length
    RUBY

    _(result).must_answer <<~'OUT'
      ["01100001"]
      ["10000110"]
      32
    OUT
  end

  it "unpack offset keyword starts mid string" do
    result = zr(<<~'RUBY')
      # `unpack`/`unpack1` accept `offset:`; `offset == bytesize` yields the
      # empty tail (nil), past-the-end raises, negative raises.

      pair = [1.5, 2.25].pack("G2")
      p pair.unpack1("G", offset: 8)
      p pair.unpack("G", offset: 8)
      p "abc".unpack("C", offset: 3)
      begin; "abc".unpack("C", offset: 5); rescue ArgumentError => e; puts e.message; end
      begin; "abc".unpack("C", offset: -1); rescue ArgumentError => e; puts e.message; end
    RUBY

    _(result).must_answer <<~'OUT'
      2.25
      [2.25]
      [nil]
      offset outside of string
      offset can't be negative
    OUT
  end

  it "unpack skip and position directives" do
    result = zr(<<~'RUBY')
      p "abcd".unpack("x2a*")
      p "abc".unpack("@1a*")
      p "abc".unpack("a1@0a1")
    RUBY

    _(result).must_answer <<~'OUT'
      ["cd"]
      ["bc"]
      ["a", "a"]
    OUT
  end

  it "unpack1 literal format" do
    result = zr(<<~'RUBY')
      # String#unpack1 with a literal single-directive format: the directive fixes
      # the extracted value's type, so the result no longer stays poly. Doom's WAD
      # reader depends on this for header fields: `@num_lumps = data[4, 4].unpack1('V')`
      # then `@num_lumps.times.map { ... }`.
      data = [7, 300].pack('V2')
      n = data.unpack1('V')
      p n
      p n.times.map { |i| i * 2 }
      p data[4, 4].unpack1('V')
      p [-2].pack('s<').unpack1('s<')
      p [65534].pack('v').unpack1('v')
      p [200].pack('C').unpack1('C')

      # A non-literal format stays on the boxed path.
      fmt = 'V'
      p data.unpack1(fmt)

      # Multi-directive and string-directive formats keep the boxed poly result.
      p data.unpack1('VV')
      p "ABCD".unpack1('a4').length

      # Doom's directory shape: a count read via unpack1 drives times.map into a
      # poly-array ivar that is later mutated.
      class Hdr
        attr_reader :items

        def initialize(raw)
          @count = raw.unpack1('V')
          @items = @count.times.map { |i| i.even? ? i : "s#{i}" }
        end

        def add(x)
          @items << x
        end
      end

      h = Hdr.new([3].pack('V'))
      h.add("s")
      p h.items
    RUBY

    _(result).must_answer <<~'OUT'
      7
      [0, 2, 4, 6, 8, 10, 12]
      300
      -2
      65534
      200
      7
      7
      4
      [0, "s1", 2, "s"]
    OUT
  end
end
