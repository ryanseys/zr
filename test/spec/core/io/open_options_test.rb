# frozen_string_literal: true

require "spec_helper"

describe "IO: open options" do
  it "an open checks mode, perm, textmode, binmode, decorators and binmode for wide encodings" do
    result = zr(<<~'RUBY')
      # The options of an open are checked as rb_io_extract_modeenc checks
      # them: each of mode, perm, textmode and binmode once, no decorator in
      # binary mode, and a reader of an ASCII-incompatible encoding in binary
      # mode unless it converts.
      path = "/tmp/zr_spec_open_options.txt"
      File.write(path, "x")
      def opened(*args, **options)
        File.open(*args, **options) { |f| f.read.size }
      rescue => e
        e
      end
      p opened(path, "rb", newline: :universal)
      p opened(path, "rt", binmode: true)
      p opened(path, binmode: true, textmode: true)
      p opened(path, "rb", binmode: true)
      p opened(path, "rt", textmode: true)
      p opened(path, "r", mode: "r")
      p opened(path, "r", 0644, perm: 0600)
      p opened(path, mode: "r", flags: File::RDONLY)
      p opened(path, "w", flags: File::EXCL)
      p opened(path, "r", newline: :bogus)
      p opened(path, "r", invalid: :bogus)
      p opened(path, "r", xml: :bogus)
      p opened(path, "r:utf-16le")
      p((File.read(path, encoding: "utf-16le") rescue $!))
      p File.read(path, mode: "r:utf-8:-")
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT'
      #<ArgumentError: newline decorator with binary mode>
      #<ArgumentError: both textmode and binmode specified>
      #<ArgumentError: both textmode and binmode specified>
      #<ArgumentError: binmode specified twice>
      #<ArgumentError: textmode specified twice>
      #<ArgumentError: mode specified twice>
      #<ArgumentError: perm specified twice>
      1
      #<Errno::EEXIST: File exists @ rb_sysopen - /tmp/zr_spec_open_options.txt>
      #<ArgumentError: unexpected value for newline option: bogus>
      #<ArgumentError: unknown value for invalid character option>
      #<ArgumentError: unexpected value for xml option: bogus>
      #<ArgumentError: ASCII incompatible encoding needs binmode>
      #<ArgumentError: ASCII incompatible encoding needs binmode>
      "x"
    OUT
  end

  it "a mode string and set_encoding read their encodings as parse_mode_enc does" do
    result = zr(<<~'RUBY')
      # A mode string names its encodings as parse_mode_enc reads them, split
      # at the last colon: a name that matches nothing warns and is ignored,
      # and nothing converts from binary. set_encoding reads a spec string
      # the same way, and raises for a name given on its own.
      path = "/tmp/zr_spec_mode_enc.txt"
      File.write(path, "x")
      File.open(path, "r:utf-8:") { |f| p [f.external_encoding, f.internal_encoding] }
      File.open(path, "r:-") { |f| p f.external_encoding }
      File.open(path, "r::utf-8") { |f| p [f.external_encoding, f.internal_encoding] }
      File.open(path, "r:binary:utf-8") { |f| p f.internal_encoding }
      File.open(path) do |f|
        f.set_encoding("bogus")
        p f.external_encoding
        f.set_encoding("utf-8:bogus")
        p f.internal_encoding
        f.set_encoding("bom|utf-8")
        p f.external_encoding
        f.set_encoding("binary:utf-8")
        p f.internal_encoding
        p((f.set_encoding("utf-16le") rescue $!))
        p((f.set_encoding rescue $!))
        p((f.set_encoding(nil, "utf-8") rescue $!))
        p((f.set_encoding(1, 2, 3) rescue $!))
        p((f.set_encoding("bogus", "utf-8") rescue $!))
      end
      File.delete(path)
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      [#<Encoding:UTF-8>, nil]
      #<Encoding:UTF-8>
      [#<Encoding:UTF-8>, nil]
      nil
      #<Encoding:UTF-8>
      nil
      #<Encoding:UTF-8>
      nil
      #<ArgumentError: ASCII incompatible encoding needs binmode>
      #<ArgumentError: wrong number of arguments (given 0, expected 1..2)>
      #<TypeError: no implicit conversion of nil into String>
      #<ArgumentError: wrong number of arguments (given 3, expected 1..2)>
      #<File:/tmp/zr_spec_mode_enc.txt>
    OUT
      core/io/open_options_test.rb:7: warning: Unsupported encoding  ignored
      core/io/open_options_test.rb:8: warning: Unsupported encoding - ignored
      core/io/open_options_test.rb:9: warning: Unsupported encoding :utf-8 ignored
      core/io/open_options_test.rb:12: warning: Unsupported encoding bogus ignored
      core/io/open_options_test.rb:14: warning: Unsupported encoding bogus ignored
      core/io/open_options_test.rb:24: warning: Unsupported encoding bogus ignored
    ERR
  end

  it "IO.pipe and IO.popen take the encodings and conversion options of an open" do
    result = zr(<<~'RUBY')
      # IO.pipe and IO.popen take the encodings and conversion options that an
      # open takes; popen gives the rest to spawn.
      r, w = IO.pipe("utf-8", "iso-8859-1", invalid: :replace, replace: "?")
      w.write("a\xffb")
      w.close
      p r.read
      IO.popen("printf '\\351'", "r:iso-8859-1") { |io| p [io.read, io.external_encoding] }
      IO.popen("printf '\\351'", "rb") { |io| p io.read.encoding }
      IO.popen("printf 'x'", external_encoding: "binary") { |io| p io.read.encoding }
      IO.popen(["printf", "y"], mode: "rb") { |io| p [io.read, io.binmode?] }
      r, w = IO.pipe(binmode: true)
      p [r.binmode?, w.binmode?, r.external_encoding]
    RUBY

    _(result).must_answer <<~'OUT'
      "a?b"
      ["\xE9", #<Encoding:ISO-8859-1>]
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:BINARY (ASCII-8BIT)>
      ["y", true]
      [true, true, #<Encoding:BINARY (ASCII-8BIT)>]
    OUT
  end

  it "set_encoding with two encodings warns for an unknown name and converts nothing between one encoding and itself" do
    result = zr(<<~'RUBY')
      # set_encoding with two arguments warns for a name that matches nothing,
      # converts nothing between one encoding and itself or from binary, and
      # takes the conversion options.
      File.write("/tmp/zr_spec_set_encoding.txt", "x")
      File.open("/tmp/zr_spec_set_encoding.txt") do |f|
        [["iso-8859-1", "-"], ["binary", "utf-8"], [Encoding::UTF_8, Encoding::UTF_8], ["euc-jp", "utf-8"], ["bogus", "bogus2"], ["utf-8", "bogus"], [Encoding::EUC_JP, "utf-8"], ["euc-jp", nil], [nil, nil], [Encoding::BINARY]].each do |args|
          r = (f.set_encoding(*args) rescue $!)
          p [args, r.is_a?(Exception) ? r : [f.external_encoding, f.internal_encoding]]
        end
        f.set_encoding("iso-8859-1", "utf-8", invalid: :replace)
        p [f.external_encoding, f.internal_encoding]
        p((f.set_encoding("utf-8", invalid: :bogus) rescue $!))
      end
      File.delete("/tmp/zr_spec_set_encoding.txt")
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      [["iso-8859-1", "-"], [#<Encoding:ISO-8859-1>, nil]]
      [["binary", "utf-8"], [#<Encoding:BINARY (ASCII-8BIT)>, nil]]
      [[#<Encoding:UTF-8>, #<Encoding:UTF-8>], [#<Encoding:UTF-8>, nil]]
      [["euc-jp", "utf-8"], [#<Encoding:EUC-JP>, #<Encoding:UTF-8>]]
      [["bogus", "bogus2"], [#<Encoding:UTF-8>, nil]]
      [["utf-8", "bogus"], [#<Encoding:UTF-8>, #<Encoding:UTF-8>]]
      [[#<Encoding:EUC-JP>, "utf-8"], [#<Encoding:EUC-JP>, #<Encoding:UTF-8>]]
      [["euc-jp", nil], [#<Encoding:EUC-JP>, nil]]
      [[nil, nil], [#<Encoding:UTF-8>, nil]]
      [[#<Encoding:BINARY (ASCII-8BIT)>], [#<Encoding:BINARY (ASCII-8BIT)>, nil]]
      [#<Encoding:ISO-8859-1>, #<Encoding:UTF-8>]
      #<ArgumentError: unknown value for invalid character option>
    OUT
      core/io/open_options_test.rb:7: warning: Unsupported encoding bogus ignored
      core/io/open_options_test.rb:7: warning: Unsupported encoding bogus2 ignored
      core/io/open_options_test.rb:7: warning: Unsupported encoding bogus ignored
    ERR
  end
end
