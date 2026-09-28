# frozen_string_literal: true

require "spec_helper"

describe "IO: newline decorators" do
  it "a text-mode read turns CRLF and CR into LF for lines, characters and a whole read, but not for read(length)" do
    result = zr(<<~'RUBY')
      # A text-mode read turns CRLF and a lone CR into LF, for lines,
      # characters and a read of the whole stream. read(length) gives the bytes
      # as they are.
      path = "/tmp/zr_spec_newline.txt"
      File.binwrite(path, "a\r\nb\rc\nd\r")
      File.open(path, "rt") { |f| p f.read }
      File.open(path, newline: :universal) { |f| p f.read }
      File.open(path, universal_newline: true) { |f| p f.read }
      File.open(path, "r", textmode: true) { |f| p f.read }
      File.open(path, "rt") { |f| p [f.gets, f.gets, f.gets, f.gets, f.gets] }
      File.open(path, "rt") { |f| p f.each_char.to_a }
      File.open(path, "rt") { |f| p [f.read(2), f.read(3), f.read] }
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      "a\nb\nc\nd\n"
      "a\nb\nc\nd\n"
      "a\nb\nc\nd\n"
      "a\nb\nc\nd\n"
      ["a\n", "b\n", "c\n", "d\n", nil]
      ["a", "\n", "b", "\n", "c", "\n", "d", "\n"]
      ["a\r", "\nb\r", "c\nd\n"]
    OUT
  end

  it "a write turns each newline into what crlf, cr or lf names, and universal changes nothing written" do
    result = zr(<<~'RUBY')
      # A write turns each "\n" into what crlf, cr or lf names, puts and print
      # included. The universal decorator changes nothing that is written, and
      # neither does "wt".
      path = "/tmp/zr_spec_newline_w.txt"
      File.open(path, "w", crlf_newline: true) { |f| f.write("a\nb\r\nc") }
      p File.binread(path)
      File.open(path, "w", newline: :cr) { |f| f.write("a\nb") }
      p File.binread(path)
      File.open(path, "w", newline: :lf) { |f| f.write("a\r\nb\rc") }
      p File.binread(path)
      File.open(path, "w", newline: :universal) { |f| f.write("a\r\nb") }
      p File.binread(path)
      File.open(path, "wt") { |f| f.write("a\r\nb\n") }
      p File.binread(path)
      File.open(path, "w", crlf_newline: true) { |f| f.puts "x"; f.print "y\n"; f << "z\n" }
      p File.binread(path)
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      "a\r\nb\r\r\nc"
      "a\rb"
      "a\nb\nc"
      "a\r\nb"
      "a\r\nb\n"
      "x\r\ny\r\nz\r\n"
    OUT
  end

  it "a write converts with invalid, undef, replace and xml, and writes a UTF-16 byte order mark once" do
    result = zr(<<~'RUBY')
      # A write's conversion takes invalid:, undef:, replace: and xml:, and a
      # UTF-16 or UTF-32 stream writes its byte order mark once.
      path = "/tmp/zr_spec_write_conv.txt"
      def written(path, mode, text, **options)
        File.open(path, mode, **options) { |f| text.is_a?(Array) ? text.each { f.write(_1) } : f.write(text) }
        File.binread(path)
      rescue => e
        e
      end
      p written(path, "w:us-ascii", "é", undef: :replace)
      p written(path, "w:iso-8859-1", "\xff", invalid: :replace)
      p written(path, "w", "<a>&", xml: :text)
      p written(path, "w:us-ascii", "é\"", xml: :attr)
      p written(path, "w:us-ascii", "éa", undef: :replace, replace: "*")
      p written(path, "w:iso-8859-1", "あ")
      p written(path, "w:utf-16", %w[a b])
      p written(path, "w:utf-32le", %w[a b])
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      "?"
      "?"
      "&lt;a&gt;&amp;"
      "\"&#xE9;&quot;\""
      "*a"
      #<Encoding::UndefinedConversionError: U+3042 from UTF-8 to ISO-8859-1>
      "\xFE\xFF\x00a\x00b"
      "a\x00\x00\x00b\x00\x00\x00"
    OUT
  end

  it "bom| and set_encoding_by_bom take the encoding from the byte order mark" do
    result = zr(<<~'RUBY')
      # "bom|" lets the byte order mark give the encoding and takes it out of
      # the stream. set_encoding_by_bom does the same for a binary stream with
      # no encoding of its own, and knows UTF-8, UTF-16 and UTF-32.
      path = "/tmp/zr_spec_bom.txt"
      File.binwrite(path, "\xEF\xBB\xBFhi")
      File.open(path, "r:bom|utf-8") { |f| p [f.read, f.external_encoding] }
      File.binwrite(path, "\xFF\xFEh\x00i\x00")
      File.open(path, "rb:bom|utf-16le:utf-8") { |f| p f.read }
      File.binwrite(path, "\xFE\xFF\x00h")
      File.open(path, "rb:BOM|utf-8") { |f| p [f.read, f.external_encoding] }
      File.binwrite(path, "hi")
      File.open(path, "r:bom|utf-8") { |f| p [f.read, f.external_encoding] }
      File.binwrite(path, "\xEF\xBB\xBFhi")
      File.open(path, "rb") { |f| p [f.set_encoding_by_bom, f.read, f.external_encoding] }
      File.binwrite(path, "\xFF\xFE\x00\x00h\x00\x00\x00")
      File.open(path, "rb") { |f| p [f.set_encoding_by_bom, f.read] }
      File.binwrite(path, "\xEF\xBB\xBFhi")
      File.open(path) { |f| p((f.set_encoding_by_bom rescue $!)) }
      File.open(path, "rb") { |f| f.set_encoding_by_bom; p((f.set_encoding_by_bom rescue $!)) }
      File.open(path, "rb:utf-8") { |f| p((f.set_encoding_by_bom rescue $!)) }
      r, w = IO.pipe
      r.binmode
      w.write("\xFF\xFEa\x00")
      w.close
      p [r.set_encoding_by_bom, r.read]
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      ["hi", #<Encoding:UTF-8>]
      "hi"
      ["h", #<Encoding:UTF-16BE>]
      ["hi", #<Encoding:UTF-8>]
      [#<Encoding:UTF-8>, "hi", #<Encoding:UTF-8>]
      [#<Encoding:UTF-32LE>, "h"]
      #<ArgumentError: ASCII incompatible encoding needs binmode>
      #<ArgumentError: encoding is set to UTF-8 already>
      #<ArgumentError: encoding is set to UTF-8 already>
      [#<Encoding:UTF-16LE>, "a"]
    OUT
  end
end
