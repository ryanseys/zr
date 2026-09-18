# frozen_string_literal: true

require "spec_helper"

describe "Digest programs" do
  it "big5 and euc jp encode exactly" do
    result = ze0(<<~'RUBY')
      # The WHOLE encode repertoire of the two families whose WHATWG table
      # disagrees with CRuby's, as a count and a checksum.
      #
      # zeo's multi-byte mapping comes from encoding_rs, and its Big5 maps MORE
      # than CRuby (the HKSCS-adjacent region, Cyrillic included) while its EUC-JP
      # is decode-only for JIS X 0212, which CRuby reaches through the SS3 plane.
      # `enc/mb_encode_delta.rs` carries the difference -- 1,161 + 175 denied
      # scalars and 414 + 6,072 allowed ones, generated from ruby by
      # `tools/mb_encode_delta.rb`.
      #
      # A checksum rather than 27,000 rows: the point is that NOTHING moved, and
      # a diff of one row is as much a failure as a diff of a thousand. The named
      # rows below are what tells you WHICH direction moved when it does -- one
      # per reason the delta exists.
      #
      # The DECODE direction has no delta and needs none; it already agreed.

      require "digest"

      %w[Big5 EUC-JP].each do |enc|
        ok = []
        # Bounded at U+2FFFF rather than U+10FFFF: neither family maps anything
        # above it, so the tail is a million iterations that answer nothing --
        # and the whole sweep runs twice, once per engine, on every suite run.
        (0..0x2FFFF).each do |cp|
          next if cp.between?(0xD800, 0xDFFF)
          s = begin
            cp.chr(Encoding::UTF_8)
          rescue RangeError
            next
          end
          begin
            ok << "#{cp}:#{s.encode(enc).unpack1('H*')}"
          rescue Encoding::UndefinedConversionError
          end
        end
        puts "#{enc}\t#{ok.size}\t#{Digest::SHA256.hexdigest(ok.join(','))[0, 16]}"
      end

      def show(name)
        puts "#{name}\t#{yield}"
      rescue Exception => e
        puts "#{name}\t#{e.class}"
      end

      # Big5 DENIES what WHATWG maps.
      show("big5 cyrillic") { "Ж".encode("Big5").unpack1("H*") }
      # Big5 ALLOWS what WHATWG does not.
      show("big5 ok") { "中".encode("Big5").unpack1("H*") }
      # EUC-JP reaches JIS X 0212 through SS3.
      show("euc jis0212") { "é".encode("EUC-JP").unpack1("H*") }
      show("euc roundtrip") { "é".encode("EUC-JP").encode("UTF-8") == "é" }
      show("euc kana") { "あ".encode("EUC-JP").unpack1("H*") }
      show("euc ascii") { "a".encode("EUC-JP").unpack1("H*") }

      # DECODE is untouched, in both families.
      show("big5 decode") { "\xa4\xa4".dup.force_encoding("Big5").encode("UTF-8") }
      show("euc decode") { "\xa4\xa2".dup.force_encoding("EUC-JP").encode("UTF-8") }
      show("euc decode ss3") { "\x8f\xab\xb1".dup.force_encoding("EUC-JP").encode("UTF-8") }
    RUBY

    _(result).must_answer <<~'OUT'
      Big5	14029	5e276003a8f8676f
      EUC-JP	13137	9be5fe3c47147a0e
      big5 cyrillic	Encoding::UndefinedConversionError
      big5 ok	a4a4
      euc jis0212	8fabb1
      euc roundtrip	true
      euc kana	a4a2
      euc ascii	61
      big5 decode	中
      euc decode	あ
      euc decode ss3	é
    OUT
  end

  it "byte read keeps its bytes" do
    result = ze0(<<~'RUBY', files: fixtures("every_byte.bin"))
      # `readpartial`, `sysread`, `read(n, buf)` and `pread` answer BYTES.
      #
      # Each of them used to route the bytes through `String::from_utf8_lossy`,
      # which replaces every byte no character claims with a three-byte U+FFFD --
      # so a 100-byte read answered 136 bytes of something else, and the answer was
      # tagged UTF-8 rather than ASCII-8BIT.
      #
      # rubygems digests each member of a `.gem` through `readpartial(16384, buf)`,
      # so every downloaded gem failed its SHA256 checksum and nothing could be
      # installed. Nothing else caught it because a text file has no such bytes.

      require "digest"

      PATH = File.expand_path("../../fixtures/every_byte.bin", __dir__)

      def show(label, s)
        puts "#{label}\tbytesize=#{s.bytesize}\tsize=#{s.size}\tenc=#{s.encoding}\t#{Digest::SHA256.hexdigest(s)[0, 16]}"
      end

      File.open(PATH, "rb") { |io| show "read(n)", io.read(200) }
      File.open(PATH, "rb") { |io| show "readpartial(n)", io.readpartial(200) }
      File.open(PATH, "rb") { |io| show "sysread(n)", io.sysread(200) }
      File.open(PATH, "rb") { |io| show "pread", io.pread(200, 0) }

      # The output-buffer forms fill the caller's own String and answer it.
      File.open(PATH, "rb") do |io|
        buf = String.new(capacity: 16_384, encoding: Encoding::BINARY)
        r = io.readpartial(200, buf)
        show "readpartial(n, buf)", buf
        puts "same object\t#{r.equal?(buf)}"
      end

      File.open(PATH, "rb") do |io|
        buf = +""
        io.read(200, buf)
        show "read(n, buf)", buf
      end

      File.open(PATH, "rb") do |io|
        buf = +""
        io.pread(200, 0, buf)
        show "pread(n, off, buf)", buf
      end

      # A short read stops at the end rather than over-reading.
      File.open(PATH, "rb") { |io| show "read past end", io.read(10_000) }

      # Reading the whole file in chunks reproduces it exactly, which is the
      # property rubygems' checksum depends on.
      digest = Digest::SHA256.new
      File.open(PATH, "rb") do |io|
        buf = String.new(capacity: 64, encoding: Encoding::BINARY)
        until io.eof?
          io.readpartial(64, buf)
          digest << buf
        end
      end
      puts "chunked\t#{digest.hexdigest == Digest::SHA256.file(PATH).hexdigest}"
    RUBY

    _(result).must_answer <<~'OUT'
      read(n)	bytesize=200	size=200	enc=ASCII-8BIT	1901da1c9f699b48
      readpartial(n)	bytesize=200	size=200	enc=ASCII-8BIT	1901da1c9f699b48
      sysread(n)	bytesize=200	size=200	enc=ASCII-8BIT	1901da1c9f699b48
      pread	bytesize=200	size=200	enc=ASCII-8BIT	1901da1c9f699b48
      readpartial(n, buf)	bytesize=200	size=200	enc=ASCII-8BIT	1901da1c9f699b48
      same object	true
      read(n, buf)	bytesize=200	size=200	enc=UTF-8	1901da1c9f699b48
      pread(n, off, buf)	bytesize=200	size=200	enc=UTF-8	1901da1c9f699b48
      read past end	bytesize=1024	size=1024	enc=ASCII-8BIT	785b0751fc2c53dc
      chunked	true
    OUT
  end

  it "SHA2 refuses an unsupported bit length, and inspect carries the current hexdigest" do
    result = ze0(<<~'RUBY')
      # Digest rows beyond the (matching) core: `Digest::SHA2` (the
      # bit-length-parameterized class) is absent, `Digest::SHA256.file` is
      # absent, and #inspect embeds the current hexdigest. (Found by the
      # 2026-08-24 probe sweep.)
      require "digest"
      require "tempfile"
      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { Digest::SHA2.new(384).hexdigest("x").length }
      show { Digest::SHA2.new(224) }
      show { Tempfile.create("dg") { |f| f.write("filedata"); f.flush; Digest::SHA256.file(f.path).hexdigest == Digest::SHA256.hexdigest("filedata") } }
      show { d = Digest::MD5.new; d << "a"; d.inspect.include?(d.hexdigest) }
    RUBY

    _(result).must_answer <<~'OUT'
      96
      ArgumentError: unsupported bit length: 224
      true
      true
    OUT
  end

  it "a bang form answers the current digest and puts the instance back to empty" do
    result = ze0(<<~'RUBY')
      # `Digest::Instance`'s three bang forms answer the current digest and then put
      # the instance back to empty; the plain forms leave it alone. rubygems reaches
      # `hexdigest!` for every file it unpacks, so `zeo gem install` needed them.

      require "digest"

      d = Digest::SHA256.new
      d << "abc"
      p d.hexdigest!
      p d.hexdigest

      d << "abc"
      p d.digest!.bytesize
      p d.digest.bytesize

      d << "abc"
      p d.base64digest!
      p d.base64digest

      # The instance half of `file`, which answers self so a chain reads left to right.
      File.write("digest_bang_probe.txt", "abc")
      p Digest::SHA256.new.file("digest_bang_probe.txt").hexdigest
      File.unlink("digest_bang_probe.txt")

      p Digest::SHA256.new.respond_to?(:hexdigest!)
    RUBY

    _(result).must_answer <<~'OUT'
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      32
      32
      "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0="
      "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      true
    OUT
  end

  it "the class form, << and update, and base64digest all answer what ruby answers" do
    result = ze0(<<~'RUBY')
      require "digest"
      puts Digest::SHA256.hexdigest("abc")
      puts Digest::MD5.hexdigest("")
      d = Digest::SHA256.new
      d << "a"; d.update("bc")
      puts d.hexdigest
      puts Digest::SHA256.base64digest("abc")
    RUBY

    _(result).must_answer <<~'OUT'
      ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
      d41d8cd98f00b204e9800998ecf8427e
      ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
      ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=
    OUT
  end

  it "the ancestry runs Base, Class and Instance, and .file reads a whole file" do
    result = ze0(<<~'RUBY')
      require "digest"
      def show(l); print l, ": "; p(yield); rescue Exception => e; puts "#{e.class}: #{e.message}"; end
      show("ancestors") { Digest::MD5.ancestors.first(5) }
      show("sha2 superclass") { Digest::SHA2.superclass }
      show("sha384 superclass") { Digest::SHA384.superclass }
      show("version") { Digest::VERSION }
      show("class file") do
        d = Digest::SHA256.file(__FILE__)
        [d.class, d.hexdigest == Digest::SHA256.hexdigest(File.binread(__FILE__))]
      end
      show("base64digest") { Digest::SHA256.base64digest("abc") }
      show("inst base64digest") { Digest::SHA1.new.base64digest("abc") }
      show("bang") { d = Digest::SHA256.new; d << "ab"; [d.base64digest!, d.hexdigest] }
      show("file owner") { Digest::MD5.instance_method(:file).owner }
      show("Digest fn") { Digest(:SHA256).equal?(Digest::SHA256) }
      show("Digest nope") { Digest(:NOPE) }
      show("require nope") { require "digest/nope" }
      show("require sha2") { require "digest/sha2" }
      show("hexencode") { Digest.hexencode("ab") }
      show("instance module") { Digest::Instance.instance_of?(Module) }
      show("class includes") { Digest::Class.include?(Digest::Instance) }
    RUBY

    _(result).must_answer <<~'OUT'
      ancestors: [Digest::MD5, Digest::Base, Digest::Class, Digest::Instance, Object]
      sha2 superclass: Digest::Class
      sha384 superclass: Digest::Base
      version: "3.2.1"
      class file: [Digest::SHA256, true]
      base64digest: "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0="
      inst base64digest: "qZk+NkcGgWq6PiVxeFDCbJzQ2J0="
      bang: ["+44g/C5MPySMYMOb1lLzwTRymLuXe4tNWQO4UFViBgM=", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"]
      file owner: Digest::Instance
      Digest fn: true
      Digest nope: LoadError: library not found for class Digest::NOPE -- digest/nope
      require nope: LoadError: cannot load such file -- digest/nope
      require sha2: false
      hexencode: "6162"
      instance module: true
      class includes: true
    OUT
  end

  it "digest_length and block_length answer per algorithm, and == takes a Digest or a String" do
    result = ze0(<<~'RUBY')
      require "digest"

      # Digest output and internal block sizes.
      p Digest::MD5.new.digest_length
      p Digest::SHA1.new.digest_length
      p Digest::SHA256.new.digest_length
      p Digest::SHA512.new.digest_length
      p Digest::SHA256.new.block_length
      p Digest::SHA512.new.block_length

      # == compares by raw digest (another Digest) or hexdigest (a String).
      a = Digest::SHA256.new; a.update("hello")
      b = Digest::SHA256.new; b.update("hello")
      p(a == b)
      p(a == Digest::SHA256.hexdigest("hello"))
      p(a == "not the digest")

      # Digest.hexencode hex-encodes bytes without hashing.
      p Digest.hexencode("Hi!")
    RUBY

    _(result).must_answer <<~'OUT'
      16
      20
      32
      64
      64
      128
      true
      true
      false
      "486921"
    OUT
  end

  it "the extension links, so native code in the binary computes the hash" do
    result = ze0(<<~'RUBY')
      # The digest extension links: the hash is computed by native code in the
      # binary.
      require "digest"
      puts Digest::SHA256.hexdigest("zeo")
      puts Digest::MD5.hexdigest("")
      d = Digest::SHA1.new
      d << "a"
      d << "b"
      puts d.hexdigest
    RUBY

    _(result).must_answer <<~'OUT'
      3d6780af3250f8de07aa3b0b6daccc970b0692d73e566d957e8152f570e3609a
      d41d8cd98f00b204e9800998ecf8427e
      da23614e02469a0d7c7bd1bdab5c9c474b1904dc
    OUT
  end

  it "kernel digest names an algorithm" do
    result = ze0(<<~'RUBY')
      # `Digest(name)` -- the function-shaped algorithm lookup CRuby defines in
      # `digest.rb` as a private method of `Object`. It is not a nicety: `pstore`
      # picks its checksum with `%w[SHA512 ... MD5].each { break Digest(algo)
      # rescue LoadError }`, so both the answer and the LoadError are load-bearing.
      #
      # zeo had no such row at all, and `require "pstore"` died in the class body.

      require "digest"

      p Digest(:SHA512)
      p Digest(:SHA256)
      p Digest(:SHA1)
      p Digest(:MD5)
      p Digest("SHA384")
      p Digest(:SHA512).hexdigest("zeo")

      # The `rescue LoadError` pstore leans on -- a name with no class behind it.
      begin
        Digest(:NOPE)
      rescue LoadError => e
        puts e.message
      end

      # It answers a class object, so the constant and the call agree.
      p Digest(:SHA256).equal?(Digest::SHA256)

      # `name.to_sym` is what CRuby writes, so a non-name is a NoMethodError.
      begin
        Digest(42)
      rescue NoMethodError => e
        puts e.message
      end

      # Private, exactly as ruby has it: no explicit receiver.
      begin
        Object.new.Digest(:MD5)
      rescue NoMethodError => e
        puts e.message.split(" for ").first
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Digest::SHA512
      Digest::SHA256
      Digest::SHA1
      Digest::MD5
      Digest::SHA384
      "95a0220cf5fa53d9f9d51559e034f4e75bc34653b5af0fd8517881e95d86d3a7b7c759a825abff954ef8f787c10aaf24d46dc6e6ac22c5395c782296b7518eec"
      library not found for class Digest::NOPE -- digest/nope
      true
      undefined method 'to_sym' for an instance of Integer
      private method 'Digest' called
    OUT
  end

  it "require value" do
    result = ze0(<<~'RUBY')
      # What a `require` answers, and where one may stand. Each line pins CRuby's
      # answer: true when this require is what loaded the library, false when it
      # was already there -- including `require "rational"`/"complex", the default
      # gems folded into core, which answer false. (Imported from spinel.)
      r1 = require 'stringio'
      p r1
      p r1.class
      p require('stringio')
      p require('set')
      p require('rational')
      p require('complex')
      p require('thread')

      # a value in condition position, and the modifier forms
      if require 'strscan'
        puts "loaded strscan"
      else
        puts "strscan was already there"
      end
      puts "not reloaded" unless require 'strscan'
      p((require('pathname') ? "y" : "n"))
      p (require 'stringio' rescue nil)

      # indented, and inside a method body: the library still loads, at the top
      if 1 > 0
        require 'forwardable'
      end

      def in_body
        require 'digest'
        "body ok"
      end
      p in_body

      # the libraries all actually work
      p StringIO.new("hi").read
      p StringScanner.new("ab").scan(/a/)
      p Pathname.new("/tmp").to_s
      p Set.new([1, 2, 2]).size
      p Rational(1, 2) + Rational(1, 3)
      p Complex(1, 2) * Complex(3, 4)

      # the word inside a string or a heredoc is not a require
      src = <<~RB
        require 'no_such_library_at_all'
      RB
      p src.strip.length
      p "require 'also_not_real'".length
      # require 'not_this_one_either'
    RUBY

    _(result).must_answer <<~'OUT'
      true
      TrueClass
      false
      false
      false
      false
      false
      loaded strscan
      not reloaded
      "y"
      false
      "body ok"
      "hi"
      "a"
      "/tmp"
      2
      (5/6)
      (-5+10i)
      32
      23
    OUT
  end

  it "subclass class digest reaches its own override" do
    result = ze0(<<~'RUBY')
      # Digest::Class.hexdigest sends `digest` to the class it was called on,
      # so a subclass that redefines the class method `digest` is reached,
      # as OpenSSL::Digest.hexdigest("SHA1", data) needs. A class method the
      # core library sends by name went to the core's own row whenever the
      # receiver was a class's singleton class.
      require "digest"

      class Tagged < Digest::Class
        def initialize(tag = "none")
          super()
          @tag = tag
        end

        def digest(data) = "#{@tag}:#{data}"

        def self.digest(tag, data)
          super(data, tag)
        end
      end

      p Tagged.digest("sha", "abc")
      p Tagged.hexdigest("sha", "abc")
      p Digest::SHA256.hexdigest("abc")[0, 16]

      class Plain < Digest::Class
        def digest(data) = data.reverse
      end
      p Plain.hexdigest("abc")

    RUBY

    _(result).must_answer <<~'OUT'
      "sha:abc"
      "7368613a616263"
      "ba7816bf8f01cfea"
      "636261"
    OUT
  end

  it "subclass of any native class" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # Every built-in CLASS can be subclassed. zeo used to keep an opt-in
      # allowlist of "payload roots", so a gem subclassing a native class nobody
      # had added got a compile error naming zeo rather than a program -- eleven
      # gems on `OpenSSL::X509::Certificate` alone. The list is a DENYLIST now
      # (`zeo_abi::NOT_PAYLOAD_ROOTS`): a built-in whose subclass is a different
      # native shape says so, and everything else is a payload wrapper.
      #
      # What made the default safe is that both halves it needs are generic. A
      # root with no empty form keeps a `nil` payload and the subclass's own
      # `initialize` seats the real one through `super` (the `File` shape), and a
      # root with no constructor at all answers instead of panicking.
      require "openssl"
      require "digest"
      require "zlib"

      class Cert < OpenSSL::X509::Certificate
        def label = "cert"
      end
      p [Cert.new.label, Cert.superclass, Cert.new.is_a?(OpenSSL::X509::Certificate)]

      class Fingerprint < Digest::MD5
        def label = "md5"
      end
      p [Fingerprint.new.label, Fingerprint.new.is_a?(Digest::MD5)]

      class Squeezer < Zlib::Deflate
        def label = "deflate"
      end
      p [Squeezer.new.label, Squeezer.superclass]

      # A root with no argument-free form: the definition registers, and the
      # subclass's own `initialize` seats the payload through `super`.
      class Signer < OpenSSL::HMAC
        def initialize(key)
          super(key, OpenSSL::Digest.new("SHA256"))
        end

        def label = "hmac"
      end
      signer = Signer.new("secret")
      p [signer.label, signer.is_a?(OpenSSL::HMAC), signer.update("x").hexdigest.length]

      # A subclass that seats its payload through `super` gets the real thing, and
      # the inherited methods run against it.
      class Loud < String
        def initialize(text)
          super(text.upcase)
        end

        def label = "loud"
      end
      loud = Loud.new("hi")
      p [loud, loud.label, loud.length, loud.class, loud.is_a?(String)]

      # The denylist's own shapes still behave the way each of them must.
      class Point < Struct.new(:x, :y); end
      p [Point.new(1, 2).x, Point.superclass.superclass]

      class Tally < Integer; end
      p Tally.superclass

      # ...and the two superclasses ruby ITSELF refuses, refused with ruby's own
      # message rather than a compile error naming zeo.
      begin
        class WantsClass < Class
        end
      rescue TypeError => e
        p [e.class, e.message]
      end
      begin
        class WantsModule < Comparable
        end
      rescue TypeError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      ["cert", OpenSSL::X509::Certificate, true]
      ["md5", true]
      ["deflate", Zlib::Deflate]
      ["hmac", true, 64]
      ["HI", "loud", 2, Loud, true]
      [1, Struct]
      Integer
      [TypeError, "can't make subclass of Class"]
      [TypeError, "superclass must be an instance of Class (given an instance of Module)"]
    OUT
  end
end
