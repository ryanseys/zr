# frozen_string_literal: true

require "spec_helper"

describe "IO: characters" do
  it "getc, readchar and each_char read one character in the read encoding" do
    result = zr(<<~'RUBY')
      # getc, readchar and each_char read one character in the read encoding:
      # the external one, binary under "rb", and the internal one after a
      # conversion.
      path = "/tmp/zr_spec_chars.txt"
      File.binwrite(path, "aéあ")
      File.open(path) { |f| p [f.getc, f.getc, f.readchar, f.getc].map { [_1, _1&.encoding] } }
      File.open(path, "rb") { |f| p f.each_char.to_a }
      File.open(path, "r:BINARY") { |f| p [f.getc, f.external_encoding] }
      File.open(path, "r:iso-8859-1") { |f| p f.each_char.first(3) }
      File.open(path, "r:iso-8859-1:utf-8") { |f| p f.each_char.to_a }
      File.open(path, "rb:utf-8") { |f| p f.getc }
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      [["a", #<Encoding:UTF-8>], ["é", #<Encoding:UTF-8>], ["あ", #<Encoding:UTF-8>], [nil, nil]]
      ["a", "\xC3", "\xA9", "\xE3", "\x81", "\x82"]
      ["a", #<Encoding:BINARY (ASCII-8BIT)>]
      ["a", "\xC3", "\xA9"]
      ["a", "Ã", "©", "ã", "\u0081", "\u0082"]
      "a"
    OUT
  end

  it "a byte that starts no character comes back alone, and a cut character keeps the bytes it has" do
    result = zr(<<~'RUBY')
      # A byte that starts no character comes back alone, and a character that
      # the stream ends inside comes back with the bytes it has.
      def pipe(data)
        r, w = IO.pipe
        w.write(data.b)
        w.close
        r
      end
      p pipe("\xE3\x81a").each_char.to_a
      p pipe("\xE3\x81").each_char.to_a
      p pipe("\xff\xfe").each_char.map(&:valid_encoding?)
      p pipe("aé").each_codepoint.to_a
      p((pipe("a\xff").each_codepoint.to_a rescue $!))
      p pipe("abc").each_char.with_index.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      ["\xE3", "\x81", "a"]
      ["\xE3\x81"]
      [false, false]
      [97, 233]
      #<ArgumentError: invalid byte sequence in UTF-8>
      [["a", 0], ["b", 1], ["c", 2]]
    OUT
  end

  it "ungetc takes a String or an unsigned code point, and ungetbyte a byte modulo 256" do
    result = zr(<<~'RUBY')
      # ungetc takes a String or a code point in the read encoding, as an
      # unsigned int; ungetbyte takes a byte modulo 256, and nil puts back
      # nothing. Both need a stream that reads.
      def pipe(data)
        r, w = IO.pipe
        w.write(data)
        w.close
        r
      end
      [-1, 2**32, -2**31, -2**31 - 1, :x, nil, 0xe9, "é"].each do |c|
        r = pipe("ab")
        p [(r.ungetc(c) rescue $!), (r.getc rescue $!)]
      end
      r = pipe("ab")
      p [r.ungetbyte(0x141), r.getc, r.ungetbyte(nil), r.ungetbyte("xy"), r.read]
      _, w = IO.pipe
      p((w.ungetc("a") rescue $!))
    RUBY

    _(result).must_answer <<~'OUT'
      [#<RangeError: invalid codepoint 0xFFFFFFFF in UTF-8>, "a"]
      [#<RangeError: integer 4294967296 too big to convert to 'unsigned int'>, "a"]
      [#<RangeError: 2147483648 out of char range>, "a"]
      [#<RangeError: integer -2147483649 too small to convert to 'unsigned int'>, "a"]
      [#<TypeError: no implicit conversion of Symbol into String>, "a"]
      [#<TypeError: no implicit conversion of nil into String>, "a"]
      [nil, "é"]
      [nil, "é"]
      [nil, "A", nil, nil, "xyab"]
      #<IOError: not opened for reading>
    OUT
  end

  it "a limit that ends inside a character reads on to its end in any multibyte encoding" do
    result = zr(<<~'RUBY')
      # A limit that ends inside a character reads on to its end, in every
      # multibyte encoding, not only UTF-8.
      def pipe(data, enc = nil)
        r, w = IO.pipe
        r.set_encoding(enc) if enc
        w.write(data.b)
        w.close
        r
      end
      r = pipe("\xA4\xA2\xA4\xA4\n", "euc-jp")
      p [r.gets(1), r.gets(1), r.gets(1)]
      r = pipe("\x82\xa0\x82\xa2", "shift_jis")
      p [r.gets(1), r.gets(3)]
      r = pipe("あい")
      p [r.gets(1), r.gets(2), r.gets(4)]
    RUBY

    _(result).must_answer <<~'OUT'
      ["\x{A4A2}", "\x{A4A4}", "\n"]
      ["\x{82A0}", "\x{82A2}"]
      ["あ", "い", nil]
    OUT
  end

  it "chomp takes the separator only from a line that ends with it" do
    result = zr(<<~'RUBY')
      # chomp: takes "\n" and one "\r" before it, a paragraph's "\n\n", or the
      # given separator, and only from a line that ends with it.
      def pipe(data)
        r, w = IO.pipe
        w.write(data)
        w.close
        r
      end
      p pipe("a\r").gets(chomp: true)
      p pipe("a\nb").gets(nil, chomp: true)
      p pipe("a\n\n\nb\n\nc").each_line("", chomp: true).to_a
      p pipe("a\n").each_line("", chomp: true).to_a
      p pipe("a\r\r\n").each_line(chomp: true).to_a
      p pipe("axyb").each_line("xy", chomp: true).to_a
      p pipe("abc\n").each_line(3, chomp: true).to_a
      p pipe("ab\r\n").each_line(3, chomp: true).to_a
      p pipe("a\r\nb\r\n").each_line("\n", chomp: true).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      "a\r"
      "a\nb"
      ["a", "b", "c"]
      ["a\n"]
      ["a\r"]
      ["a", "b"]
      ["abc", ""]
      ["ab\r", ""]
      ["a", "b"]
    OUT
  end

  it "the default separator is written in the stream's encoding, and another must be compatible" do
    result = zr(<<~'RUBY')
      # The default separator is written in the stream's encoding, and any
      # other separator must be compatible with it. A separator counts only
      # where a character starts.
      path = "/tmp/zr_spec_utf16.txt"
      File.binwrite(path, "h\x00i\x00\n\x00x\x00")
      File.open(path, "rb:utf-16le") { |f| p [f.gets, f.gets].map { [_1, _1.encoding] } }
      File.open(path, "rb:utf-16le") { |f| p((f.gets("\n") rescue $!)) }
      File.open(path, "rb:utf-16le") { |f| p f.each_char.to_a }
      File.delete(path)
      def pipe(data, enc = nil)
        r, w = IO.pipe
        r.set_encoding(enc) if enc
        w.write(data.b)
        w.close
        r
      end
      p((pipe("ab").gets("b".encode("utf-16le")) rescue $!))
      p((pipe("ab").gets("é".encode("iso-8859-1")) rescue $!))
      p pipe("aéb").gets("é")
      p pipe("\x82\x40\x40x", "shift_jis").gets("@")
    RUBY

    _(result).must_answer <<~'OUT'
      [["hi\n", #<Encoding:UTF-16LE>], ["x", #<Encoding:UTF-16LE>]]
      #<ArgumentError: encoding mismatch: UTF-16LE IO with UTF-8 RS>
      ["h", "i", "\n", "x"]
      #<ArgumentError: encoding mismatch: UTF-8 IO with UTF-16LE RS>
      #<ArgumentError: encoding mismatch: UTF-8 IO with ISO-8859-1 RS>
      "aé"
      "\x{8240}@"
    OUT
  end
end
