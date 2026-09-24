# frozen_string_literal: true

require "spec_helper"

describe "Base64 programs" do
  it "encode64 wraps at sixty characters, strict_encode64 does not, and every decoder is the inverse" do
    result = zr(<<~'RUBY')
      require "base64"

      puts Base64.encode64("hello world")
      puts Base64.encode64("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
      puts Base64.strict_encode64("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
      puts Base64.decode64(Base64.encode64("round trip"))
      puts Base64.urlsafe_encode64("ab")
      puts Base64.urlsafe_decode64("YWI")
      puts Base64.strict_decode64("aGVsbG8=")
    RUBY

    _(result).must_answer <<~'OUT'
      aGVsbG8gd29ybGQ=
      YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFh
      YWFhYWE=
      YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE=
      round trip
      YWI=
      ab
      hello
    OUT
  end

  it "feature with no ruby half falls through to the static ext table" do
    result = zr(<<~'RUBY')
      # A feature with no Ruby half falls through to the static-ext table, which is
      # the ordinary case for most extensions.

      require "base64"
      p Base64.encode64("hi")
    RUBY

    _(result).must_answer "\"aGk=\\n\"\n"
  end

  it "gated constant appears at its require" do
    result = zr(<<~'RUBY')
      # A require-gated builtin's CONSTANT does not exist until its `require` runs.
      # zeo registers the class for the whole program (a feature no file requires
      # registers nothing at all), and `HirNode::FeatureLoaded` reveals it at the
      # require's own line -- so `defined?` and a bare reference ask instead of
      # folding, exactly as they already did for a class defined under a guard zeo
      # cannot decide.

      p Object.const_defined?(:Base64)
      p defined?(Base64)
      begin
        Base64
      rescue NameError => e
        puts e.message
      end

      require "base64"

      p Object.const_defined?(:Base64)
      p defined?(Base64)
      p Base64.encode64("hi")

      # A method written above the require reads the constant when it RUNS.
      def probe = defined?(Zlib) ? "yes" : "no"
      p probe
      require "zlib"
      p probe
      p Zlib::Deflate.is_a?(Class)

      # A feature ruby loads before line 1 needs no require at all.
      p defined?(Monitor)
      p defined?(Set)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      nil
      uninitialized constant Base64
      true
      "constant"
      "aGk=\n"
      "no"
      "yes"
      true
      "constant"
      "constant"
    OUT
  end

  it "in tree base64 over two args raises argument error at runtime" do
    result = zr(<<~'RUBY')
      # The in-tree Base64 ext checks arity at runtime (a rescuable
      # ArgumentError) via `arity!`.

      require "base64"
      begin
        Base64.encode64("a", "b")
      rescue ArgumentError
        puts "argerr"
      end
    RUBY

    _(result).must_answer "argerr\n"
  end

  it "pack base64" do
    result = zr(<<~'RUBY')
      # Array#pack base64 ("m") and quoted-printable ("M") directives.

      # m0: single base64 string, "=" padding, no line breaks
      p ["hi"].pack("m0")
      p ["hello world"].pack("m0")
      p [""].pack("m0")
      p ["a"].pack("m0")
      p ["ab"].pack("m0")
      p ["abc"].pack("m0")

      # bare m: base64 with a trailing newline; wraps every 45 input bytes (60 cols)
      p ["hi"].pack("m")
      p ["hello world"].pack("m")
      p ["Base64 quickly wraps Matz's joyful Ruby gems in vivid hex for the wire."].pack("m")

      # binary input with an embedded NUL must survive (byte length, not strlen)
      p ["a\x00b".dup].pack("m0")

      # M: quoted-printable, 72-col soft wrap
      p ["hello"].pack("M")
      p ["caf\xC3\xA9".dup].pack("M")
      p ["x=y"].pack("M")
      # CRuby's M is NOT strict RFC 2045: trailing space/tab is emitted literally (not
      # =20/=09), and the soft wrap fires only once a line exceeds the limit (n > line,
      # so a full 72-char line stays unwrapped). These lock that byte-for-byte parity.
      p ["abc   "].pack("M")             # trailing spaces kept literal
      p ["a\t"].pack("M")                # trailing tab kept literal
      p [("A" * 72)].pack("M")           # exactly 72: no soft wrap
      p [("A" * 73)].pack("M")           # 73: still one line, wrap is > not >=
      p [("x" * 80)].pack("M")           # wraps after 72
      p ["ab   "].pack("M10")            # explicit column count

      # poly-array receiver (routed through a param to defeat const-folding)
      def via_poly(a) = a.pack("m0")
      p via_poly(["hi", 1])
    RUBY

    _(result).must_answer <<~'OUT'
      "aGk="
      "aGVsbG8gd29ybGQ="
      ""
      "YQ=="
      "YWI="
      "YWJj"
      "aGk=\n"
      "aGVsbG8gd29ybGQ=\n"
      "QmFzZTY0IHF1aWNrbHkgd3JhcHMgTWF0eidzIGpveWZ1bCBSdWJ5IGdlbXMg\naW4gdml2aWQgaGV4IGZvciB0aGUgd2lyZS4=\n"
      "YQBi"
      "hello=\n"
      "caf=C3=A9=\n"
      "x=3Dy=\n"
      "abc   =\n"
      "a\t=\n"
      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n"
      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n"
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=\nxxxxxxx=\n"
      "ab   =\n"
      "aGk="
    OUT
  end

  it "pack base64 count controls wrapping" do
    result = zr(<<~'RUBY')
      # `m0` is one unbroken run with no trailing newline (RFC 4648); a bare `m`
      # wraps at 45 input bytes / 60 columns with a trailing newline; empty
      # input yields "" for both.

      p ["hello world"].pack("m0")
      p [""].pack("m0")
      p ["a\x00b".dup].pack("m0")
      p ["hi"].pack("m")
      p [""].pack("m")
      p [("A" * 50)].pack("m")
    RUBY

    _(result).must_answer <<~'OUT'
      "aGVsbG8gd29ybGQ="
      ""
      "YQBi"
      "aGk=\n"
      ""
      "QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFB\nQUFBQUE=\n"
    OUT
  end

  it "random seed range base64 pad" do
    result = zr(<<~'RUBY')
      # Random.new auto-seeding (two instances differ), Random#rand(Range), and
      # Base64.urlsafe_encode64's padding: keyword.
      require "base64"

      a = Random.new
      b = Random.new
      p(a.rand(1_000_000) != b.rand(1_000_000))   # true

      def rr(r); Random.new(5).rand(r); end
      v = rr(1..6)
      p v.class                                    # Integer
      p v >= 1 && v <= 6                           # true
      w = rr(10...12)
      p w >= 10 && w <= 11                         # true
      # a seeded instance is reproducible
      p Random.new(7).rand(1000) == Random.new(7).rand(1000)  # true
      begin
        rr(6..1)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end

      def enc(x); Base64.urlsafe_encode64(x, padding: false); end
      def encp(x); Base64.urlsafe_encode64(x); end
      p enc("1")          # "MQ"
      p encp("1")         # "MQ=="
      p enc("ab")         # "YWI"
      p encp("ab")        # "YWI="
      p enc("abc")        # "YWJj" (no padding to strip)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      Integer
      true
      true
      true
      ArgumentError: invalid argument - 6..1
      "MQ"
      "MQ=="
      "YWI"
      "YWI="
      "YWJj"
    OUT
  end

  it "require of a builtin feature works from any position" do
    result = zr(<<~'RUBY')
      # A `require` of a natively-provided feature is a compile-time act, so it
      # works from any position -- and it has CRuby's real return value, true the
      # first time and false thereafter (`load.c:1413`).

      p(require "digest")
      p(require "digest")
      if 1 > 0
        require "json"
      end
      def load_it
        require "set"
        "ok"
      end
      p load_it
      require "base64" if false
      require "zlib" rescue nil
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      "ok"
      done
    OUT
  end

  it "require positions and paths" do
    result = zr(<<~'RUBY')
      # `require` behaviors that follow from CRuby's load.c, in the two places
      # zeo's compile-time resolver used to reject outright.

      # 1. A `require` of a feature the runtime already provides natively works from
      #    ANY position -- inside a conditional, a method body, or a value position.
      #    There is nothing to splice: the whole effect is activating a built-in, and
      #    that is a compile-time act. CRuby answers true the first time a feature
      #    loads and false thereafter (load.c:1413), so the call has a real value.
      first = require "digest"
      again = require "digest"
      p first
      p again

      if 1 > 0
        require "json"
      end

      def load_it
        require "set"
        "ok"
      end
      p load_it

      # 2. Because the require is an ordinary expression now, a trailing modifier
      #    attaches to it instead of stranding the parser.
      require "base64" if false
      require "zlib" rescue nil
      puts "modifiers ok"

      # 3. `require "time"` and `require "io/console"` name no gated constant here --
      #    Time and IO are always-on -- so both are accepted no-ops.
      require "time"
      p Time.at(0).utc.year

      # 4. A reentrant lock from `require "monitor"`. The distinguishing property
      #    against Mutex is exactly re-entrancy: the owner may enter again, and the
      #    lock only releases at the outermost exit.
      require "monitor"
      mon = Monitor.new
      mon.synchronize do
        mon.synchronize { p mon.mon_owned? }
        p mon.mon_locked?
      end
      p mon.mon_locked?
      p mon.synchronize { 21 * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      "ok"
      modifiers ok
      1970
      true
      true
      false
      42
    OUT
  end

  it "sp crypto basic" do
    result = zr(<<~'RUBY')
      # Ported from spinel's bundled sp_crypto.c FFI surface. Those C symbols are
      # spinel-private, so the port keeps the same deterministic vectors through
      # Ruby's own primitives: HMAC-SHA256 built from Digest::SHA256 (RFC 2104
      # construction), Base64URL via the base64 stdlib, PBKDF2 with one iteration
      # (HMAC(password, salt || 0x00000001)), and core Random bytes for the random
      # leg.
      #
      #   - HMAC-SHA256 against RFC 4231's "Jefe" test case; the hex vector is
      #     5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843.
      #   - Base64URL round-trip on a 5-byte input (5 % 3 == 2, so the tail emits
      #     3 chars and no padding).
      #   - PBKDF2-HMAC-SHA256 with a single iteration.
      #   - Random b64url returns the right length for the requested byte count
      #     and doesn't compare-equal across calls.
      require "digest"
      require "base64"

      def hmac_sha256(key, msg)
        block = 64
        key = Digest::SHA256.digest(key) if key.bytesize > block
        key = key + "\0" * (block - key.bytesize)
        ipad = key.bytes.map { |b| b ^ 0x36 }.pack("C*")
        opad = key.bytes.map { |b| b ^ 0x5c }.pack("C*")
        Digest::SHA256.digest(opad + Digest::SHA256.digest(ipad + msg))
      end

      def b64url(bytes)
        Base64.urlsafe_encode64(bytes).delete("=")
      end

      key = "Jefe"
      msg = "what do ya want for nothing?"
      puts hmac_sha256(key, msg).unpack1("H*")

      # Base64URL round-trip; should print "aGVsbG8" then "hello".
      enc = b64url("hello")
      puts enc
      puts Base64.urlsafe_decode64(enc)

      # PBKDF2 with iters=1 is HMAC(password, salt||0x00000001). The expected
      # 43-char b64url is a stable property of the salt+password+1 input.
      puts b64url(hmac_sha256("password", "salt" + [1].pack("N")))

      # Random: two calls of the same size must differ (probability of collision
      # on 16 bytes is 2^-128). Print the length and the inequality result so the
      # .expected stays deterministic.
      rng = Random.new
      r1 = b64url(rng.bytes(16))
      r2 = b64url(rng.bytes(16))
      puts r1.length
      puts(r1 == r2 ? "same" : "diff")
    RUBY

    _(result).must_answer <<~'OUT'
      5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
      aGVsbG8
      hello
      Eg-2z_z4syxD5yJSVsT4N6hlSMkszDVICAWYfLcL4Xs
      22
      diff
    OUT
  end

  it "sp crypto sha1" do
    result = zr(<<~'RUBY')
      # Ported from spinel's bundled sp_crypto.c SHA-1 FFI surface. Those C
      # symbols are spinel-private, so the port keeps the same deterministic
      # vectors through Digest::SHA1 + Base64.
      #
      # SHA-1 is a legacy hash, only kept for the WebSocket handshake (RFC 6455
      # 1.3 explicitly requires it for Sec-WebSocket-Accept). The two FIPS-180
      # sample vectors and the RFC 6455 1.3 example are deterministic, so this
      # test stays tight.
      require "digest"
      require "base64"

      # FIPS-180-4 standard vectors.
      puts Digest::SHA1.hexdigest("abc")        # a9993e36...
      puts Digest::SHA1.hexdigest("")           # da39a3ee...

      # RFC 6455 1.3 worked example: Sec-WebSocket-Accept is the base64 of the
      # SHA-1 of the handshake key + the fixed GUID.
      GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
      puts Base64.strict_encode64(Digest::SHA1.digest("dGhlIHNhbXBsZSBub25jZQ==" + GUID))
    RUBY

    _(result).must_answer <<~'OUT'
      a9993e364706816aba3e25717850c26c9cd0d89d
      da39a3ee5e6b4b0d3255bfef95601890afd80709
      s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
    OUT
  end

  it "nil and a boolean in an Integer slot raise with the from-nil wording" do
    result = zr(<<~'RUBY')
      # CRuby's argument-conversion TypeErrors, message included.
      #
      # Four rules, each spelled where CRuby spells it: a `Check_Type` message
      # (`wrong argument type X (expected Y)`) names `nil`/`true`/`false` as the
      # VALUE rather than the class; `rb_num2long` says "no implicit conversion
      # from nil to integer" where `rb_to_int` says "of nil into Integer";
      # `StringScanner`'s pattern slot reads with `StringValue`, so its refusal
      # is the STRING conversion's; and a rounding digit count, a radix and a
      # random seed are conversions, never arithmetic coercions.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # CRuby's argument validation at builtin boundaries: a compile-time-known
      # nil / true / false (or wrong-classed scalar) entering a String- or
      # Integer-typed slot raises CRuby's TypeError, wording included, where the
      # slot's zero ("" / 0) used to stand in silently. The slots CRuby itself
      # accepts nil in keep working.

      # nil / bool into Integer slots ("from nil to integer" wording)

      begin
        p([10, 20, 30].take(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p([10, 20, 30].rotate(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p([10, 20, 30].delete_at(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p([10, 20, 30].each_cons(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p((1..9).first(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p("ab" * nil)
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p("ab".center(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(3.4.round(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(5.to_s(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(Integer("5", nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(:abc[nil])
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p([1, 2].fill(0, false))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion of false into Integer"]
    OUT
  end

  it "an rb_to_int slot raises with the of-nil wording instead" do
    result = zr(<<~'RUBY')
      # CRuby's argument-conversion TypeErrors, message included.
      #
      # Four rules, each spelled where CRuby spells it: a `Check_Type` message
      # (`wrong argument type X (expected Y)`) names `nil`/`true`/`false` as the
      # VALUE rather than the class; `rb_num2long` says "no implicit conversion
      # from nil to integer" where `rb_to_int` says "of nil into Integer";
      # `StringScanner`'s pattern slot reads with `StringValue`, so its refusal
      # is the STRING conversion's; and a rounding digit count, a radix and a
      # random seed are conversions, never arithmetic coercions.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # CRuby's argument validation at builtin boundaries: a compile-time-known
      # nil / true / false (or wrong-classed scalar) entering a String- or
      # Integer-typed slot raises CRuby's TypeError, wording included, where the
      # slot's zero ("" / 0) used to stand in silently. The slots CRuby itself
      # accepts nil in keep working.

      # rb_to_int slots ("of nil into Integer" wording)
      begin
        p(5.digits(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(5[nil])
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(Random.srand(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "no implicit conversion of nil into Integer"]
      [TypeError, "no implicit conversion of nil into Integer"]
      [TypeError, "no implicit conversion of nil into Integer"]
    OUT
  end

  it "nil, a boolean and a wrong class in a String slot each raise" do
    result = zr(<<~'RUBY')
      # CRuby's argument-conversion TypeErrors, message included.
      #
      # Four rules, each spelled where CRuby spells it: a `Check_Type` message
      # (`wrong argument type X (expected Y)`) names `nil`/`true`/`false` as the
      # VALUE rather than the class; `rb_num2long` says "no implicit conversion
      # from nil to integer" where `rb_to_int` says "of nil into Integer";
      # `StringScanner`'s pattern slot reads with `StringValue`, so its refusal
      # is the STRING conversion's; and a rounding digit count, a radix and a
      # random seed are conversions, never arithmetic coercions.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # CRuby's argument validation at builtin boundaries: a compile-time-known
      # nil / true / false (or wrong-classed scalar) entering a String- or
      # Integer-typed slot raises CRuby's TypeError, wording included, where the
      # slot's zero ("" / 0) used to stand in silently. The slots CRuby itself
      # accepts nil in keep working.

      # nil / bool / wrong class into String slots
      begin
        p(File.join("a", nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p("hello".include?(true))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p("ab".delete_prefix(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(Regexp.new(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p([1].pack(1))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(File.path(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "no implicit conversion of nil into String"]
      [TypeError, "no implicit conversion of true into String"]
      [TypeError, "no implicit conversion of nil into String"]
      [TypeError, "no implicit conversion of nil into String"]
      [TypeError, "no implicit conversion of Integer into String"]
      [TypeError, "no implicit conversion of nil into String"]
    OUT
  end

  it "a slot expecting a pattern raises with the wrong-argument-type wording" do
    result = zr(<<~'RUBY')
      # CRuby's argument-conversion TypeErrors, message included.
      #
      # Four rules, each spelled where CRuby spells it: a `Check_Type` message
      # (`wrong argument type X (expected Y)`) names `nil`/`true`/`false` as the
      # VALUE rather than the class; `rb_num2long` says "no implicit conversion
      # from nil to integer" where `rb_to_int` says "of nil into Integer";
      # `StringScanner`'s pattern slot reads with `StringValue`, so its refusal
      # is the STRING conversion's; and a rounding digit count, a radix and a
      # random seed are conversions, never arithmetic coercions.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # CRuby's argument validation at builtin boundaries: a compile-time-known
      # nil / true / false (or wrong-classed scalar) entering a String- or
      # Integer-typed slot raises CRuby's TypeError, wording included, where the
      # slot's zero ("" / 0) used to stand in silently. The slots CRuby itself
      # accepts nil in keep working.

      # the regexp-expected pattern family
      begin
        p("ab".match(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p("ab".sub(nil, "x"))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p("ab".scan(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p("ab".match?(false))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p("ab".gsub(true, "x"))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "wrong argument type nil (expected Regexp)"]
      [TypeError, "wrong argument type nil (expected Regexp)"]
      [TypeError, "wrong argument type nil (expected Regexp)"]
      [TypeError, "wrong argument type false (expected Regexp)"]
      [TypeError, "wrong argument type true (expected Regexp)"]
    OUT
  end

  it "the Array-operand slots raise for an operand they cannot convert" do
    result = zr(<<~'RUBY')
      # CRuby's argument-conversion TypeErrors, message included.
      #
      # Four rules, each spelled where CRuby spells it: a `Check_Type` message
      # (`wrong argument type X (expected Y)`) names `nil`/`true`/`false` as the
      # VALUE rather than the class; `rb_num2long` says "no implicit conversion
      # from nil to integer" where `rb_to_int` says "of nil into Integer";
      # `StringScanner`'s pattern slot reads with `StringValue`, so its refusal
      # is the STRING conversion's; and a rounding digit count, a radix and a
      # random seed are conversions, never arithmetic coercions.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # CRuby's argument validation at builtin boundaries: a compile-time-known
      # nil / true / false (or wrong-classed scalar) entering a String- or
      # Integer-typed slot raises CRuby's TypeError, wording included, where the
      # slot's zero ("" / 0) used to stand in silently. The slots CRuby itself
      # accepts nil in keep working.

      # the Array-operand family
      begin
        p([1, 2].concat(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p([1, 2].product(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "no implicit conversion of nil into Array"]
      [TypeError, "no implicit conversion of nil into Array"]
    OUT
  end

  it "a MatchData index raises for a value it cannot convert" do
    result = zr(<<~'RUBY')
      # CRuby's argument-conversion TypeErrors, message included.
      #
      # Four rules, each spelled where CRuby spells it: a `Check_Type` message
      # (`wrong argument type X (expected Y)`) names `nil`/`true`/`false` as the
      # VALUE rather than the class; `rb_num2long` says "no implicit conversion
      # from nil to integer" where `rb_to_int` says "of nil into Integer";
      # `StringScanner`'s pattern slot reads with `StringValue`, so its refusal
      # is the STRING conversion's; and a rounding digit count, a radix and a
      # random seed are conversions, never arithmetic coercions.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # CRuby's argument validation at builtin boundaries: a compile-time-known
      # nil / true / false (or wrong-classed scalar) entering a String- or
      # Integer-typed slot raises CRuby's TypeError, wording included, where the
      # slot's zero ("" / 0) used to stand in silently. The slots CRuby itself
      # accepts nil in keep working.

      # MatchData indexes
      m = /a(b)/.match("ab")
      begin
        p(m[nil])
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(m[false])
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "no implicit conversion from nil to integer"]
      [TypeError, "no implicit conversion of false into Integer"]
    OUT
  end

  it "the native bindings and the module functions check their slots too" do
    result = zr(<<~'RUBY')
      # CRuby's argument-conversion TypeErrors, message included.
      #
      # Four rules, each spelled where CRuby spells it: a `Check_Type` message
      # (`wrong argument type X (expected Y)`) names `nil`/`true`/`false` as the
      # VALUE rather than the class; `rb_num2long` says "no implicit conversion
      # from nil to integer" where `rb_to_int` says "of nil into Integer";
      # `StringScanner`'s pattern slot reads with `StringValue`, so its refusal
      # is the STRING conversion's; and a rounding digit count, a radix and a
      # random seed are conversions, never arithmetic coercions.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # CRuby's argument validation at builtin boundaries: a compile-time-known
      # nil / true / false (or wrong-classed scalar) entering a String- or
      # Integer-typed slot raises CRuby's TypeError, wording included, where the
      # slot's zero ("" / 0) used to stand in silently. The slots CRuby itself
      # accepts nil in keep working.

      # native bindings and module functions
      require "json"
      require "base64"
      require "strscan"
      begin
        p(JSON.parse(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(Base64.encode64(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(StringScanner.new("ab").scan(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(Random.new(2).bytes(nil))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "no implicit conversion of nil into String"]
      [TypeError, "no implicit conversion of nil into String"]
      [TypeError, "no implicit conversion of nil into String"]
      [TypeError, "no implicit conversion of nil into Integer"]
    OUT
  end

  it "a slot where CRuby accepts nil goes on accepting it" do
    result = zr(<<~'RUBY')
      # CRuby's argument-conversion TypeErrors, message included.
      #
      # Four rules, each spelled where CRuby spells it: a `Check_Type` message
      # (`wrong argument type X (expected Y)`) names `nil`/`true`/`false` as the
      # VALUE rather than the class; `rb_num2long` says "no implicit conversion
      # from nil to integer" where `rb_to_int` says "of nil into Integer";
      # `StringScanner`'s pattern slot reads with `StringValue`, so its refusal
      # is the STRING conversion's; and a rounding digit count, a radix and a
      # random seed are conversions, never arithmetic coercions.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # CRuby's argument validation at builtin boundaries: a compile-time-known
      # nil / true / false (or wrong-classed scalar) entering a String- or
      # Integer-typed slot raises CRuby's TypeError, wording included, where the
      # slot's zero ("" / 0) used to stand in silently. The slots CRuby itself
      # accepts nil in keep working.

      # slots where CRuby accepts nil stay accepting
      p "a b".split(nil)
      p "ab\n".chomp(nil)
      p [1, [2]].flatten(nil)
      p [1, 2].fill(0, nil)
      p(/a/.match(nil))
      p(/a/ =~ nil)
      p("ab" =~ nil)
      ENV["SPINEL_C3_T"] = "v"
      ENV["SPINEL_C3_T"] = nil
      p ENV["SPINEL_C3_T"].nil?

    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      "ab\n"
      [1, 2]
      [0, 0]
      nil
      nil
      nil
      true
    OUT
  end

  it "a named-capture match against a nil subject, and fill's negative length, each answer" do
    result = zr(<<~'RUBY')
      # CRuby's argument-conversion TypeErrors, message included.
      #
      # Four rules, each spelled where CRuby spells it: a `Check_Type` message
      # (`wrong argument type X (expected Y)`) names `nil`/`true`/`false` as the
      # VALUE rather than the class; `rb_num2long` says "no implicit conversion
      # from nil to integer" where `rb_to_int` says "of nil into Integer";
      # `StringScanner`'s pattern slot reads with `StringValue`, so its refusal
      # is the STRING conversion's; and a rounding digit count, a radix and a
      # random seed are conversions, never arithmetic coercions.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # CRuby's argument validation at builtin boundaries: a compile-time-known
      # nil / true / false (or wrong-classed scalar) entering a String- or
      # Integer-typed slot raises CRuby's TypeError, wording included, where the
      # slot's zero ("" / 0) used to stand in silently. The slots CRuby itself
      # accepts nil in keep working.

      # review-found edges: named-capture =~ nil subject; fill's nil length is "to
      # the end"; a boolean =~ operand is NoMethodError; File.read's nil length
      def parse_kv(line)
        if /(?<k>\w+)=(?<v>\w+)/ =~ line
          [k, v]
        end
      end
      p parse_kv("a=1")
      p parse_kv(nil)
      p [1, 2, 3].fill(9, 1, nil)
      begin
        p("ab" =~ true)
      rescue NoMethodError => e
        p [e.class, e.message]
      end
      File.write("sac-frd.txt", "hello")
      begin
        p File.read("sac-frd.txt", nil)
      ensure
        File.delete("sac-frd.txt")
      end

    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "1"]
      nil
      [1, 9, 9]
      [NoMethodError, "undefined method '=~' for true"]
      "hello"
    OUT
  end

  it "super(nil) into a builtin exception keeps CRuby's class-named message" do
    result = zr(<<~'RUBY')
      # CRuby's argument-conversion TypeErrors, message included.
      #
      # Four rules, each spelled where CRuby spells it: a `Check_Type` message
      # (`wrong argument type X (expected Y)`) names `nil`/`true`/`false` as the
      # VALUE rather than the class; `rb_num2long` says "no implicit conversion
      # from nil to integer" where `rb_to_int` says "of nil into Integer";
      # `StringScanner`'s pattern slot reads with `StringValue`, so its refusal
      # is the STRING conversion's; and a rounding digit count, a radix and a
      # random seed are conversions, never arithmetic coercions.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # CRuby's argument validation at builtin boundaries: a compile-time-known
      # nil / true / false (or wrong-classed scalar) entering a String- or
      # Integer-typed slot raises CRuby's TypeError, wording included, where the
      # slot's zero ("" / 0) used to stand in silently. The slots CRuby itself
      # accepts nil in keep working.

      # super(nil) into a builtin exception keeps CRuby's class-name default
      class ConvE < StandardError
        def initialize; super(nil); end
      end
      p ConvE.new.message
    RUBY

    _(result).must_answer <<~'OUT'
      "ConvE"
    OUT
  end
end
