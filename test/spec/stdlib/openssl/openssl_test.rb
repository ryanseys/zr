# frozen_string_literal: true

require "spec_helper"

describe "OpenSSL programs" do
  it "asn1 values encode and decode as der" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # OpenSSL::ASN1 over the host's libssl: values encode to the DER ruby
      # writes, decode back to the same classes, and malformed input raises
      # ASN1Error.

      require "openssl"

      include OpenSSL

      def show(value, depth = 0)
        text = case value.value
               when Array then ""
               when OpenSSL::BN then " #{value.value.to_i}"
               else " #{value.value.inspect}"
               end
        puts "#{"  " * depth}#{value.class.name.split("::").last} tag=#{value.tag} class=#{value.tag_class}#{text}"
        value.value.each { |child| show(child, depth + 1) } if value.value.is_a?(Array)
      end

      seq = ASN1::Sequence([
        ASN1::Integer(-129),
        ASN1::Integer(2**100),
        ASN1::Boolean(true),
        ASN1::Null(nil),
        ASN1::OctetString("\x00\xffbytes".b),
        ASN1::UTF8String("héllo"),
        ASN1::PrintableString("Printable"),
        ASN1::IA5String("ia5@example.com"),
        ASN1::ObjectId("sha256WithRSAEncryption"),
        ASN1::ObjectId("1.2.3.4.5"),
        ASN1::UTCTime(Time.utc(2026, 9, 17, 12, 30, 45)),
        ASN1::GeneralizedTime(Time.utc(2051, 1, 2, 3, 4, 5)),
        ASN1::BitString("\xA0".b).tap { |b| b.unused_bits = 5 },
        ASN1::Enumerated(3),
        ASN1::Set([ASN1::Integer(2), ASN1::Integer(1)]),
        ASN1::Integer(7, 0, :IMPLICIT),
        ASN1::UTF8String("explicit", 1, :EXPLICIT),
        ASN1::ASN1Data.new("private", 2, :PRIVATE),
      ])
      der = seq.to_der
      puts der.unpack1("H*")
      decoded = ASN1.decode(der)
      show(decoded)
      p decoded.to_der == der
      p decoded.value[8].sn, decoded.value[8].ln, decoded.value[8].oid, decoded.value[9].oid
      p ASN1::ObjectId("1.2.3.4.5") == ASN1::ObjectId("1.2.3.4.5")
      p ASN1::Set([ASN1::Integer(2), ASN1::Integer(1)]).to_der.unpack1("H*")

      puts "-- traverse --"
      ASN1.traverse(ASN1::Sequence([ASN1::Integer(1), ASN1::OctetString("x")]).to_der) do |depth, offset, header_len, length, constructed, tag_class, tag|
        p [depth, offset, header_len, length, constructed, tag_class, tag]
      end
      p ASN1.decode_all(ASN1::Integer(1).to_der + ASN1::Boolean(false).to_der).map { |v| v.value.is_a?(OpenSSL::BN) ? v.value.to_i : v.value }

      puts "-- indefinite length --"
      indefinite = ASN1::Sequence.new([ASN1::Integer(1), ASN1::EndOfContent.new])
      indefinite.indefinite_length = true
      p indefinite.to_der.unpack1("H*"), ASN1.decode(indefinite.to_der).indefinite_length

      puts "-- errors --"
      ["\x02\x05\x01".b, "\x30\x80\x02\x01\x01".b, "\x06\x00".b, "".b].each do |bad|
        ASN1.decode(bad)
        puts "decoded #{bad.unpack1("H*")}"
      rescue ASN1::ASN1Error => e
        puts "ASN1Error #{e.message}"
      end
      begin
        ASN1::ObjectId("not an oid").to_der
      rescue ASN1::ASN1Error => e
        puts "ASN1Error #{e.message}"
      end
      begin
        ASN1::Integer("x").to_der
      rescue TypeError => e
        puts "TypeError #{e.message}"
      end

    RUBY

    _(result).must_answer "30819d0202ff7f020d100000000000000000000000000101ff0500040700ff62797465730c0668c3a96c6c6f13095072696e7461626c65160f696135406578616d706c652e636f6d06092a864886f70d01010b06042a030405170d3236303931373132333034355a180f32303531303130323033303430355a030205a00a01033106020102020101800107a10a0c086578706c69636974c20770726976617465\nSequence tag=16 class=UNIVERSAL\n  Integer tag=2 class=UNIVERSAL -129\n  Integer tag=2 class=UNIVERSAL 1267650600228229401496703205376\n  Boolean tag=1 class=UNIVERSAL true\n  Null tag=5 class=UNIVERSAL nil\n  OctetString tag=4 class=UNIVERSAL \"\\x00\\xFFbytes\"\n  UTF8String tag=12 class=UNIVERSAL \"h\\xC3\\xA9llo\"\n  PrintableString tag=19 class=UNIVERSAL \"Printable\"\n  IA5String tag=22 class=UNIVERSAL \"ia5@example.com\"\n  ObjectId tag=6 class=UNIVERSAL \"RSA-SHA256\"\n  ObjectId tag=6 class=UNIVERSAL \"1.2.3.4.5\"\n  UTCTime tag=23 class=UNIVERSAL 2026-09-17 12:30:45 UTC\n  GeneralizedTime tag=24 class=UNIVERSAL 2051-01-02 03:04:05 UTC\n  BitString tag=3 class=UNIVERSAL \"\\xA0\"\n  Enumerated tag=10 class=UNIVERSAL 3\n  Set tag=17 class=UNIVERSAL\n    Integer tag=2 class=UNIVERSAL 2\n    Integer tag=2 class=UNIVERSAL 1\n  ASN1Data tag=0 class=CONTEXT_SPECIFIC \"\\a\"\n  ASN1Data tag=1 class=CONTEXT_SPECIFIC\n    UTF8String tag=12 class=UNIVERSAL \"explicit\"\n  ASN1Data tag=2 class=PRIVATE \"private\"\ntrue\n\"RSA-SHA256\"\n\"sha256WithRSAEncryption\"\n\"1.2.840.113549.1.1.11\"\n\"1.2.3.4.5\"\ntrue\n\"3106020102020101\"\n-- traverse --\n[0, 0, 2, 6, true, :UNIVERSAL, 16]\n[1, 2, 2, 1, false, :UNIVERSAL, 2]\n[1, 5, 2, 1, false, :UNIVERSAL, 4]\n[1, false]\n-- indefinite length --\n\"30800201010000\"\ntrue\n-- errors --\nASN1Error too long\nASN1Error EOC missing in indefinite length encoding\nASN1Error d2i_ASN1_OBJECT: invalid object encoding\nASN1Error too small\nASN1Error invalid OBJECT ID not an oid: first num too large\nTypeError Cannot convert into OpenSSL::BN\n"
  end

  it "certificate chain verifies through a store" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # X509 over the host's libssl: a root and a leaf made here, a CSR, a CRL
      # that revokes a second leaf, and a Store that verifies the chain at a
      # fixed time.

      require "openssl"

      def name(cn) = OpenSSL::X509::Name.parse("/C=CA/O=ze0/CN=#{cn}")

      def certificate(serial, subject, issuer, key, signer, extensions)
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = serial
        cert.subject = subject
        cert.issuer = (issuer || cert).subject
        cert.public_key = key
        cert.not_before = Time.utc(2026, 1, 1)
        cert.not_after = Time.utc(2036, 1, 1)
        factory = OpenSSL::X509::ExtensionFactory.new
        factory.subject_certificate = cert
        factory.issuer_certificate = issuer || cert
        extensions.each { |oid, value, critical| cert.add_extension(factory.create_extension(oid, value, critical)) }
        cert.sign(signer, "SHA256")
      end

      root_key = OpenSSL::PKey::EC.generate("prime256v1")
      leaf_key = OpenSSL::PKey::EC.generate("prime256v1")
      root = certificate(1, name("root"), nil, root_key, root_key,
                         [["basicConstraints", "CA:TRUE", true], ["keyUsage", "keyCertSign, cRLSign", true],
                          ["subjectKeyIdentifier", "hash", false]])
      leaf = certificate(2, name("example.com"), root, leaf_key, root_key,
                         [["basicConstraints", "CA:FALSE", true], ["subjectAltName", "DNS:example.com, DNS:*.example.org", false],
                          ["authorityKeyIdentifier", "keyid:always", false]])
      revoked = certificate(3, name("revoked"), root, leaf_key, root_key, [])

      puts "-- certificates --"
      [root, leaf].each do |cert|
        puts cert.subject.to_s, cert.issuer.to_s(OpenSSL::X509::Name::RFC2253), cert.serial, cert.version
        puts cert.not_before.inspect, cert.not_after.inspect, cert.signature_algorithm
        cert.extensions.each { |ext| puts "  #{ext.oid} critical=#{ext.critical?}" }
      end
      p leaf.verify(root_key), leaf.verify(leaf_key), root.check_private_key(root_key)
      p OpenSSL::X509::Certificate.new(leaf.to_pem) == leaf, OpenSSL::X509::Certificate.new(leaf.to_der).to_der == leaf.to_der
      p OpenSSL::SSL.verify_certificate_identity(leaf, "example.com"), OpenSSL::SSL.verify_certificate_identity(leaf, "a.example.org"),
        OpenSSL::SSL.verify_certificate_identity(leaf, "example.net")
      p OpenSSL::X509::Certificate.load(root.to_pem + leaf.to_pem).map { |c| c.serial.to_i }

      puts "-- request --"
      req = OpenSSL::X509::Request.new
      req.version = 0
      req.subject = name("csr")
      req.public_key = leaf_key
      req.add_attribute(OpenSSL::X509::Attribute.new("challengePassword", OpenSSL::ASN1::Set([OpenSSL::ASN1::UTF8String("pw")])))
      req.sign(leaf_key, "SHA256")
      req = OpenSSL::X509::Request.new(req.to_pem)
      p req.subject.to_a.map(&:first), req.verify(leaf_key), req.verify(root_key), req.attributes.map(&:oid)

      puts "-- crl --"
      crl = OpenSSL::X509::CRL.new
      crl.version = 1
      crl.issuer = root.subject
      crl.last_update = Time.utc(2026, 2, 1)
      crl.next_update = Time.utc(2027, 2, 1)
      entry = OpenSSL::X509::Revoked.new
      entry.serial = revoked.serial
      entry.time = Time.utc(2026, 1, 15)
      entry.add_extension(OpenSSL::X509::Extension.new("CRLReason", OpenSSL::ASN1::Enumerated(1)))
      crl.add_revoked(entry)
      crl.sign(root_key, "SHA256")
      crl = OpenSSL::X509::CRL.new(crl.to_der)
      p crl.revoked.map { |r| [r.serial.to_i, r.time, r.extensions.map(&:value)] }, crl.verify(root_key), crl.issuer == root.subject

      puts "-- store --"
      store = OpenSSL::X509::Store.new
      store.add_cert(root)
      store.time = Time.utc(2026, 6, 1)
      p store.verify(leaf), store.error, store.error_string
      p store.verify(root)
      ctx = OpenSSL::X509::StoreContext.new(store, leaf)
      p ctx.verify, ctx.chain.map { |c| c.subject.to_s }
      store.add_crl(crl)
      store.flags = OpenSSL::X509::V_FLAG_CRL_CHECK
      p store.verify(revoked), store.error == OpenSSL::X509::V_ERR_CERT_REVOKED, store.error_string
      p store.verify(leaf)
      seen = []
      p store.verify(leaf) { |ok, c| seen << [ok, c.error_depth]; ok }, seen
      expired = OpenSSL::X509::Store.new
      expired.add_cert(root)
      expired.time = Time.utc(2040, 1, 1)
      p expired.verify(leaf), expired.error == OpenSSL::X509::V_ERR_CERT_HAS_EXPIRED

    RUBY

    _(result).must_answer "-- certificates --\n/C=CA/O=ze0/CN=root\nCN=root,O=ze0,C=CA\n1\n2\n2026-01-01 00:00:00 UTC\n2036-01-01 00:00:00 UTC\necdsa-with-SHA256\n  basicConstraints critical=true\n  keyUsage critical=true\n  subjectKeyIdentifier critical=false\n/C=CA/O=ze0/CN=example.com\nCN=root,O=ze0,C=CA\n2\n2\n2026-01-01 00:00:00 UTC\n2036-01-01 00:00:00 UTC\necdsa-with-SHA256\n  basicConstraints critical=true\n  subjectAltName critical=false\n  authorityKeyIdentifier critical=false\ntrue\nfalse\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\n[1, 2]\n-- request --\n[\"C\", \"O\", \"CN\"]\ntrue\nfalse\n[\"challengePassword\"]\n-- crl --\n[[3, 2026-01-15 00:00:00 UTC, [\"Key Compromise\"]]]\ntrue\ntrue\n-- store --\ntrue\n0\n\"ok\"\ntrue\ntrue\n[\"/C=CA/O=ze0/CN=example.com\", \"/C=CA/O=ze0/CN=root\"]\nfalse\ntrue\n\"certificate revoked\"\ntrue\ntrue\n[[true, 1], [true, 0]]\nfalse\ntrue\n"
  end

  it "https keepalive request completes" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # `OpenSSL::Buffering#read_nonblock` is aliased to `readpartial`, and that
      # alias breaks its contract in three ways. The consequence is that an HTTPS
      # request over a KEEP-ALIVE connection never returns -- not a timeout, a hang.
      #
      # The three divergences, which the module header in
      # `ext/openssl/ssl/buffering.rs` already admits to:
      #
      #   1. it BLOCKS. `readpartial` waits for a byte; `read_nonblock` must answer
      #      `:wait_readable` at once when none is ready.
      #   2. it ignores `exception: false`, so the end of the stream raises EOFError
      #      where CRuby answers `nil`.
      #   3. it ignores the output-buffer argument, so it returns a fresh String
      #      where CRuby fills and returns the caller's own object.
      #
      # `Net::BufferedIO#rbuf_fill` (net/protocol.rb) is built on exactly that
      # contract:
      #
      #   case rv = @io.read_nonblock(BUFSIZE, tmp, exception: false)
      #   when String then ...
      #   when :wait_readable then io.wait_readable(@read_timeout) or raise ReadTimeout
      #   when nil then raise EOFError
      #   end while true
      #
      # With `Connection: close` the peer closes, the blocking read returns, and the
      # program finishes by accident. With keep-alive nothing closes, so the read
      # never returns and `@read_timeout` never applies. Measured against
      # rubygems.org: `Connection: close` answers 200; keep-alive hangs forever.
      #
      # Plain `IO`, `TCPSocket` and `Socket` all answer the contract correctly, so
      # they are the reference. Fixing this means splitting `read_nonblock` from
      # `readpartial`: a real non-blocking read (the descriptor is blocking today,
      # so it needs `O_NONBLOCK` around the call or an `SSL_pending` check first),
      # the `:wait_readable` and `nil` answers, and the output buffer honoured.
      #
      # The module mixes into any object supplying the `sys*` primitives, which is
      # what lets this run with no socket and no network. That reaches divergences
      # 2 and 3 directly, and proves the first by omission: zeo never calls
      # `sysread_nonblock` at all, because its `read_nonblock` IS `readpartial`.
      #
      # Blocks the gem probe's port to ruby, which fetches over HTTPS.

      require "openssl"

      # `read_nonblock` delegates to `sysread_nonblock` and reads `@rbuffer`, so a
      # mix-in supplies both.
      class Feed
        include OpenSSL::Buffering

        def initialize(chunks)
          @chunks = chunks
          @rbuffer = +""
          @eof = false
          @sync = true
        end

        def sysread_nonblock(maxlen, buf = nil, exception: true)
          if @chunks.empty?
            return nil unless exception

            raise EOFError, "end of file reached"
          end
          got = @chunks.shift
          return got unless got.nil?
          return :wait_readable unless exception

          raise IO::WaitReadable
        ensure
          if got.is_a?(String) && buf
            buf.replace(got)
          end
        end

        def sysread(maxlen, buf = nil) = sysread_nonblock(maxlen, buf)
        def syswrite(s) = s.bytesize
        def sysclose = nil
      end

      io = Feed.new(["ab"])
      buf = +"seed"

      rv = io.read_nonblock(16, buf, exception: false)
      puts "data:  #{rv.inspect} reused_outbuf=#{rv.equal?(buf)}"

      rv = io.read_nonblock(16, buf, exception: false)
      puts "eof:   #{rv.inspect}"

      begin
        io.read_nonblock(16)
        puts "raise: no exception"
      rescue EOFError => e
        puts "raise: #{e.class}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      data:  "ab" reused_outbuf=false
      eof:   nil
      raise: EOFError
    OUT
  end

  it "keys sign derive and export through the library" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # PKey over the host's libssl: Ed25519 from fixed bytes answers fixed
      # signatures; RSA, EC, DSA and DH keys generate, sign, derive and export,
      # and read back what they wrote, with and without a passphrase.

      require "openssl"

      puts "-- ed25519 --"
      seed = ["9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"].pack("H*")
      ed = OpenSSL::PKey.new_raw_private_key("ED25519", seed)
      p ed.oid, ed.raw_public_key.unpack1("H*"), ed.raw_private_key == seed
      signature = ed.sign(nil, "")
      p signature.unpack1("H*"), ed.verify(nil, signature, ""), ed.verify(nil, signature, "x")
      pub = OpenSSL::PKey.read(ed.public_to_der)
      p pub.oid, pub.public_to_pem == ed.public_to_pem, pub.verify(nil, signature, "")
      p OpenSSL::PKey.new_raw_public_key("ED25519", ed.raw_public_key).compare?(ed)

      puts "-- rsa --"
      rsa = OpenSSL::PKey::RSA.new(2048)
      p rsa.n.num_bits, rsa.e.to_i, rsa.private?, rsa.public?
      data = "the data to sign"
      sig = rsa.sign("SHA256", data)
      p sig.bytesize, rsa.verify("SHA256", sig, data), rsa.public_key.verify("SHA256", sig, data + "!")
      pss = rsa.sign_pss("SHA256", data, salt_length: :max, mgf1_hash: "SHA256")
      p rsa.verify_pss("SHA256", pss, data, salt_length: :auto, mgf1_hash: "SHA256")
      cipher = rsa.public_encrypt("secret", OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
      p rsa.private_decrypt(cipher, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
      p rsa.encrypt("secret", "rsa_padding_mode" => "oaep").then { |c| rsa.decrypt(c, "rsa_padding_mode" => "oaep") }
      pem = rsa.export(OpenSSL::Cipher.new("aes-256-cbc"), "passphrase")
      p pem.lines.first.chomp, pem.include?("ENCRYPTED")
      p OpenSSL::PKey::RSA.new(pem, "passphrase").to_der == rsa.to_der
      p OpenSSL::PKey.read(rsa.private_to_pem("aes-128-cbc", "pw"), "pw").to_der == rsa.to_der
      begin
        OpenSSL::PKey.read(pem, "wrong")
      rescue OpenSSL::PKey::PKeyError => e
        puts "PKeyError #{e.message.start_with?("Could not parse PKey")}"
      end
      p OpenSSL::PKey.read(pem) { "passphrase" }.n == rsa.n
      p OpenSSL::PKey::RSA.new(rsa.public_key.to_pem).private?, rsa.params.keys.sort

      puts "-- ec --"
      ec = OpenSSL::PKey::EC.generate("secp384r1")
      p ec.group.curve_name, ec.group.degree, ec.private?, ec.public_key.on_curve?
      sig = ec.sign("SHA384", data)
      p ec.verify("SHA384", sig, data), ec.dsa_verify_asn1(OpenSSL::Digest.digest("SHA384", data), ec.dsa_sign_asn1(OpenSSL::Digest.digest("SHA384", data)))
      peer = OpenSSL::PKey::EC.generate("secp384r1")
      p ec.derive(OpenSSL::PKey.read(peer.public_to_der)) == peer.derive(OpenSSL::PKey.read(ec.public_to_der))
      p OpenSSL::PKey::EC.new(ec.to_pem).private_key == ec.private_key
      point = ec.public_key
      p point.to_octet_string(:compressed).bytesize, point.to_octet_string(:uncompressed).bytesize
      p OpenSSL::PKey::EC::Point.new(ec.group, point.to_bn) == point
      p point.mul(2) == point.add(point), ec.group.generator.mul(ec.private_key) == point
      p OpenSSL::PKey::EC.builtin_curves.map(&:first).include?("prime256v1")

      puts "-- dsa and dh --"
      dsa = OpenSSL::PKey.generate_key(OpenSSL::PKey.generate_parameters("DSA", "dsa_paramgen_bits" => 1024))
      p dsa.class, dsa.p.num_bits, dsa.verify("SHA256", dsa.sign("SHA256", data), data)
      dh_params = OpenSSL::PKey.read(<<~PEM)
        -----BEGIN DH PARAMETERS-----
        MIIBCAKCAQEA//////////+t+FRYortKmq/cViAnPTzx2LnFg84tNpWp4TZBFGQz
        +8yTnc4kmz75fS/jY2MMddj2gbICrsRhetPfHtXV/WVhJDP1H18GbtCFY2VVPe0a
        87VXE15/V8k1mE8McODmi3fipona8+/och3xWKE2rec1MKzKT0g6eXq8CrGCsyT7
        YdEIqUuyyOP7uWrat2DX9GgdT0Kj3jlN9K5W7edjcrsZCwenyO4KbXCeAvzhzffi
        7MA0BM0oNC9hkXL+nOmFg/+OTxIy7vKBg8P+OxtMb61zO7X8vC7CIAXFjvGDfRaD
        ssbzSibBsu/6iGtCOGEoXJf//////////wIBAg==
        -----END DH PARAMETERS-----
      PEM
      alice = OpenSSL::PKey.generate_key(dh_params)
      bob = OpenSSL::PKey.generate_key(dh_params)
      p alice.p.num_bits, alice.params_ok?, alice.compute_key(bob.pub_key) == bob.compute_key(alice.pub_key)
      p alice.derive(bob) == bob.derive(alice), OpenSSL::PKey::DH.new(dh_params.to_pem).p == dh_params.p

    RUBY

    _(result).must_answer <<~'OUT'
      -- ed25519 --
      "ED25519"
      "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
      true
      "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
      true
      false
      "ED25519"
      true
      true
      true
      -- rsa --
      2048
      65537
      true
      true
      256
      true
      false
      true
      "secret"
      "secret"
      "-----BEGIN RSA PRIVATE KEY-----"
      true
      true
      true
      PKeyError true
      true
      false
      ["d", "dmp1", "dmq1", "e", "iqmp", "n", "p", "q"]
      -- ec --
      "secp384r1"
      384
      true
      true
      true
      true
      true
      true
      49
      97
      true
      true
      true
      true
      -- dsa and dh --
      OpenSSL::PKey::DSA
      1024
      true
      2048
      true
      true
      true
      true
    OUT
  end

  it "ocsp response answers its request" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # OCSP over the host's libssl: a request for two certificates with a
      # nonce, a responder that answers one good and one revoked, and a client
      # that verifies the response, matches the nonce and reads each status.

      require "openssl"

      def certificate(cn, key, serial, issuer = nil, issuer_key = key, extensions = [])
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = serial
        cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
        cert.issuer = issuer ? issuer.subject : cert.subject
        cert.public_key = key
        cert.not_before = Time.utc(2026, 1, 1)
        cert.not_after = Time.utc(2036, 1, 1)
        factory = OpenSSL::X509::ExtensionFactory.new(issuer || cert, cert)
        extensions.each { |oid, value| cert.add_extension(factory.create_extension(oid, value)) }
        cert.sign(issuer_key, "SHA256")
      end

      ca_key = OpenSSL::PKey::EC.generate("prime256v1")
      ca = certificate("ca", ca_key, 1, nil, ca_key, [["basicConstraints", "CA:TRUE"]])
      responder_key = OpenSSL::PKey::EC.generate("prime256v1")
      responder = certificate("responder", responder_key, 2, ca, ca_key, [["extendedKeyUsage", "OCSPSigning"]])
      good = certificate("good", OpenSSL::PKey::EC.generate("prime256v1"), 10, ca, ca_key)
      revoked = certificate("revoked", OpenSSL::PKey::EC.generate("prime256v1"), 11, ca, ca_key)

      puts "-- request --"
      good_id = OpenSSL::OCSP::CertificateId.new(good, ca, OpenSSL::Digest.new("SHA256"))
      revoked_id = OpenSSL::OCSP::CertificateId.new(revoked, ca)
      p good_id.serial.to_i, good_id.hash_algorithm, revoked_id.hash_algorithm, good_id.issuer_name_hash.bytesize
      p good_id.cmp(OpenSSL::OCSP::CertificateId.new(good_id.to_der)), good_id.cmp_issuer(revoked_id), good_id.cmp(revoked_id)
      request = OpenSSL::OCSP::Request.new
      request.add_certid(good_id)
      request.add_certid(revoked_id)
      request.add_nonce("0123456789abcdef")
      request = OpenSSL::OCSP::Request.new(request.to_der)
      p request.certid.map { |id| id.serial.to_i }, request.signed?
      signed = request.dup
      signed.sign(responder, responder_key, [ca])
      store = OpenSSL::X509::Store.new
      store.add_cert(ca)
      p signed.signed?, signed.verify([], store), request.verify([], store)

      puts "-- response --"
      basic = OpenSSL::OCSP::BasicResponse.new
      basic.copy_nonce(request)
      basic.add_status(good_id, OpenSSL::OCSP::V_CERTSTATUS_GOOD, nil, nil, Time.utc(2026, 9, 1), Time.utc(2035, 9, 1), [])
      basic.add_status(revoked_id, OpenSSL::OCSP::V_CERTSTATUS_REVOKED, OpenSSL::OCSP::REVOKED_STATUS_KEYCOMPROMISE,
                       Time.utc(2026, 8, 1), Time.utc(2026, 9, 1), nil, nil)
      basic.sign(responder, responder_key, [responder])
      response = OpenSSL::OCSP::Response.create(OpenSSL::OCSP::RESPONSE_STATUS_SUCCESSFUL, basic)
      response = OpenSSL::OCSP::Response.new(response.to_der)
      p response.status, response.status_string

      puts "-- client --"
      basic = response.basic
      p request.check_nonce(basic), OpenSSL::OCSP::Request.new.check_nonce(basic), basic.verify([], store)
      basic.status.each do |id, status, reason, revoked_at, this_update, next_update, extensions|
        p [id.serial.to_i, status, reason, revoked_at, this_update, next_update, extensions]
      end
      single = basic.find_response(revoked_id)
      p single.cert_status, single.revocation_reason, single.revocation_time, single.this_update, single.next_update
      p single.check_validity, single.certid.cmp(revoked_id), basic.responses.size
      p basic.find_response(OpenSSL::OCSP::CertificateId.new(responder, ca))
      begin
        basic.find_response(good_id).revocation_reason
      rescue OpenSSL::OCSP::OCSPError => e
        puts "OCSPError #{e.message}"
      end
      p OpenSSL::OCSP::Response.create(OpenSSL::OCSP::RESPONSE_STATUS_TRYLATER, nil).then { |r| [r.status_string, r.basic] }

    RUBY

    _(result).must_answer <<~'OUT'
      -- request --
      10
      "sha256"
      "sha1"
      64
      true
      false
      false
      [10, 11]
      false
      true
      true
      false
      -- response --
      0
      "successful"
      -- client --
      1
      3
      true
      [10, 0, -1, nil, 2026-09-01 00:00:00 UTC, 2035-09-01 00:00:00 UTC, []]
      [11, 1, 1, 2026-08-01 00:00:00 UTC, 2026-09-01 00:00:00 UTC, nil, []]
      1
      1
      2026-08-01 00:00:00 UTC
      2026-09-01 00:00:00 UTC
      nil
      true
      true
      2
      nil
      OCSPError certificate is not revoked
      ["trylater", nil]
    OUT
  end

  it "openssl bn" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # OpenSSL::BN over the vendored libcrypto BIGNUM. BN#inspect is the plain
      # object form (address-bearing), so the golden prints values through
      # to_i/to_s, never p on a BN itself.
      require "openssl"

      puts "-- construction --"
      b = OpenSSL::BN.new(255)
      p b.class
      p b.to_i
      p OpenSSL::BN.new("255").to_i
      p OpenSSL::BN.new("ff", 16).to_i
      p OpenSSL::BN.new(-42).to_i
      p OpenSSL::BN.new(b).to_i
      p (OpenSSL::BN.new(2)**OpenSSL::BN.new(130)).to_i
      p 255.to_bn.class
      p 255.to_bn == b
      p b.to_bn.equal?(b)
      begin
        OpenSSL::BN.new("zz")
      rescue => e
        p e.class
      end

      puts "-- encodings --"
      p b.to_s
      p b.to_s(16)
      p b.to_s(2).bytesize
      p OpenSSL::BN.new(65537).to_s(0).unpack1("H*")
      p OpenSSL::BN.new(OpenSSL::BN.new(65537).to_s(0), 0).to_i
      p OpenSSL::BN.new(OpenSSL::BN.new(65537).to_s(2), 2).to_i

      puts "-- arithmetic --"
      p (b + OpenSSL::BN.new(1)).to_i
      p (b - 5).to_i
      p (b * OpenSSL::BN.new(2)).to_i
      q, r = b / OpenSSL::BN.new(4)
      p [q.to_i, r.to_i]
      p (b % OpenSSL::BN.new(7)).to_i
      p (OpenSSL::BN.new(3)**OpenSSL::BN.new(4)).to_i
      p (b << 4).to_i
      p (b >> 4).to_i
      p b.sqr.to_i
      p b.mod_exp(OpenSSL::BN.new(3), OpenSSL::BN.new(100)).to_i
      p b.mod_add(OpenSSL::BN.new(10), OpenSSL::BN.new(100)).to_i
      p b.mod_sub(OpenSSL::BN.new(10), OpenSSL::BN.new(100)).to_i
      p b.mod_mul(OpenSSL::BN.new(10), OpenSSL::BN.new(100)).to_i
      p b.mod_inverse(OpenSSL::BN.new(7)).to_i
      p b.gcd(OpenSSL::BN.new(100)).to_i
      begin
        OpenSSL::BN.new(10).mod_inverse(OpenSSL::BN.new(2))
      rescue => e
        p e.class
      end
      p 5 + OpenSSL::BN.new(10)

      puts "-- predicates + comparison --"
      p b.num_bits
      p b.num_bytes
      p b.zero?
      p b.one?
      p b.odd?
      p OpenSSL::BN.new(0).zero?
      p OpenSSL::BN.new(1).one?
      p b == OpenSSL::BN.new(255)
      p b == 255
      p (b <=> OpenSSL::BN.new(300))
      p b.cmp(OpenSSL::BN.new(300))
      p b.ucmp(OpenSSL::BN.new(-300))
      p b < OpenSSL::BN.new(300)   # Comparable, via the gem's Ruby half
      p OpenSSL::BN.new(97).prime?
      p OpenSSL::BN.new(100).prime?
      p b.bit_set?(0)
      p b.bit_set?(8)
      c = b.dup
      c.set_bit!(8)
      p c.to_i
      p b.to_i
      p OpenSSL::BN.new(255).hash == OpenSSL::BN.new(255).hash

      puts "-- randomness contracts --"
      p OpenSSL::BN.rand(64).num_bits <= 64
      p OpenSSL::BN.rand_range(OpenSSL::BN.new(100)) < 100
      p OpenSSL::BN.generate_prime(32).prime?

    RUBY

    _(result).must_answer <<~'OUT'
      -- construction --
      OpenSSL::BN
      255
      255
      255
      -42
      255
      1361129467683753853853498429727072845824
      OpenSSL::BN
      true
      true
      OpenSSL::BNError
      -- encodings --
      "255"
      "FF"
      1
      "00000003010001"
      65537
      65537
      -- arithmetic --
      256
      250
      510
      [63, 3]
      3
      81
      4080
      15
      65025
      75
      65
      45
      50
      5
      5
      OpenSSL::BNError
      15
      -- predicates + comparison --
      8
      1
      false
      false
      true
      true
      true
      true
      true
      -1
      -1
      -1
      true
      true
      false
      true
      false
      511
      255
      true
      -- randomness contracts --
      true
      true
      true
    OUT
  end

  it "openssl buffering" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # `OpenSSL::Buffering` is a real module, mixed into SSLSocket, that supplies
      # the whole read/write surface over the receiver's `sysread`/`syswrite`/
      # `sysclose`. It used to be implemented straight onto SSLSocket, so the module
      # could not be named, reopened, or asked about its ancestry.
      require "openssl"
      require "socket"

      puts "-- the module --"
      p OpenSSL::Buffering.instance_of?(Module)
      p OpenSSL::Buffering::BLOCK_SIZE
      p OpenSSL::Buffering.include?(Enumerable)

      puts "-- who owns what --"
      p OpenSSL::SSL::SSLSocket.include?(OpenSSL::Buffering)
      p OpenSSL::SSL::SSLSocket.include?(OpenSSL::SSL::SocketForwarder)
      p OpenSSL::SSL::SSLSocket.ancestors.include?(Enumerable)
      %i[gets read readpartial puts print each_line ungetc eof? sync].each do |m|
        p [m, OpenSSL::SSL::SSLSocket.instance_method(m).owner]
      end
      %i[sysread syswrite sysclose connect hostname context].each do |m|
        p [m, OpenSSL::SSL::SSLSocket.instance_method(m).owner]
      end
      %i[addr peeraddr fileno closed? getsockopt].each do |m|
        p [m, OpenSSL::SSL::SSLSocket.instance_method(m).owner]
      end

      puts "-- an unconnected socket carries the buffering ivars --"
      srv = TCPServer.new("127.0.0.1", 0)
      sock = TCPSocket.new("127.0.0.1", srv.addr[1])
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      p ssl.instance_variables.sort
      p ssl.instance_variable_get(:@io).equal?(sock)
      p ssl.sync
      sock.close
      srv.close

      # The module knows nothing about TLS, so anything answering the three
      # unbuffered primitives can mix it in. This is the whole surface, driven off
      # a String rather than a socket.
      class Tape
        include OpenSSL::Buffering

        # The module's own `initialize` seeds these from an `@io`; a Tape has none,
        # so it seeds them itself.
        def initialize(text)
          @tape = text.dup
          @written = +""
          @rbuffer = +""
          @eof = false
          @sync = true
        end

        attr_reader :written

        def sysread(len = 16384, buf = nil)
          raise EOFError, "end of file reached" if @tape.empty?
          @tape.slice!(0, len)
        end

        def syswrite(s)
          @written << s.to_s
          s.to_s.bytesize
        end

        def sysclose
          @tape = +""
          :closed
        end
      end

      puts "-- reading --"
      p Tape.new("one\ntwo\nthree\n").gets
      p Tape.new("one\ntwo\nthree\n").readlines
      p Tape.new("one\ntwo\nthree\n").read
      p Tape.new("abcdef").read(3)
      p Tape.new("abcdef").readpartial(2)
      p Tape.new("abc").getc
      p Tape.new("abc").getbyte
      p Tape.new("").gets
      p Tape.new("").read
      p Tape.new("").eof?
      p Tape.new("x").eof?

      puts "-- line by line --"
      lines = []
      Tape.new("a\nb\nc\n").each_line { |l| lines << l }
      p lines
      bytes = []
      Tape.new("hi").each_byte { |b| bytes << b }
      p bytes

      puts "-- pushback --"
      t = Tape.new("bcdef")
      p t.getc
      t.ungetc("a")
      p t.read

      puts "-- end of stream --"
      t = Tape.new("only")
      p t.read
      begin
        t.readpartial(4)
      rescue EOFError => e
        p [:readpartial, e.class]
      end
      begin
        Tape.new("").readline
      rescue EOFError => e
        p [:readline, e.class]
      end
      begin
        Tape.new("").readchar
      rescue EOFError => e
        p [:readchar, e.class]
      end

      puts "-- writing --"
      t = Tape.new("")
      p t.write("ab", "cd")
      t.print("ef")
      t.puts("gh")
      t.printf("%03d", 7)
      t << "!"
      p t.written
      p t.flush.equal?(t)
      p Tape.new("").close

    RUBY

    _(result).must_answer <<~'OUT'
      -- the module --
      true
      16384
      true
      -- who owns what --
      true
      true
      true
      [:gets, OpenSSL::Buffering]
      [:read, OpenSSL::Buffering]
      [:readpartial, OpenSSL::Buffering]
      [:puts, OpenSSL::Buffering]
      [:print, OpenSSL::Buffering]
      [:each_line, OpenSSL::Buffering]
      [:ungetc, OpenSSL::Buffering]
      [:eof?, OpenSSL::Buffering]
      [:sync, OpenSSL::Buffering]
      [:sysread, OpenSSL::SSL::SSLSocket]
      [:syswrite, OpenSSL::SSL::SSLSocket]
      [:sysclose, OpenSSL::SSL::SSLSocket]
      [:connect, OpenSSL::SSL::SSLSocket]
      [:hostname, OpenSSL::SSL::SSLSocket]
      [:context, OpenSSL::SSL::SSLSocket]
      [:addr, OpenSSL::SSL::SocketForwarder]
      [:peeraddr, OpenSSL::SSL::SocketForwarder]
      [:fileno, OpenSSL::SSL::SocketForwarder]
      [:closed?, OpenSSL::SSL::SocketForwarder]
      [:getsockopt, OpenSSL::SSL::SocketForwarder]
      -- an unconnected socket carries the buffering ivars --
      [:@context, :@eof, :@io, :@rbuffer, :@sync]
      true
      true
      -- reading --
      "one\n"
      ["one\n", "two\n", "three\n"]
      "one\ntwo\nthree\n"
      "abc"
      "ab"
      "a"
      97
      nil
      ""
      true
      false
      -- line by line --
      ["a\n", "b\n", "c\n"]
      [104, 105]
      -- pushback --
      "b"
      "acdef"
      -- end of stream --
      "only"
      [:readpartial, EOFError]
      [:readline, EOFError]
      [:readchar, EOFError]
      -- writing --
      4
      "abcdefgh\n007!"
      true
      :closed
    OUT
  end

  it "openssl cipher" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # OpenSSL::Cipher over the vendored libcrypto EVP. Legacy-provider names
      # (RC4, BF-CBC) fail at new under OpenSSL 3, in zeo as under CRuby.
      require "openssl"

      puts "-- metadata --"
      c = OpenSSL::Cipher.new("AES-256-CBC")
      p c.class
      p c.name
      p c.key_len
      p c.iv_len
      p c.block_size
      p c.authenticated?
      p OpenSSL::Cipher.new("aes-256-cbc").name
      p OpenSSL::Cipher.new("chacha20-poly1305").name
      p OpenSSL::Cipher.new("aes-256-gcm").authenticated?
      p OpenSSL::Cipher.ciphers.size > 20
      p OpenSSL::Cipher.ciphers.include?("aes-256-cbc")
      p OpenSSL::Cipher.ciphers.include?("AES-256-CBC")

      puts "-- cbc round trip --"
      key = "\x01".b * 32
      iv  = "\x02".b * 16
      c.encrypt
      c.key = key
      c.iv = iv
      ct = c.update("secret message!!") + c.final
      p ct.unpack1("H*")
      p ct.encoding
      d = OpenSSL::Cipher.new("AES-256-CBC")
      d.decrypt
      d.key = key
      d.iv = iv
      p d.update(ct) + d.final

      puts "-- ctr --"
      c3 = OpenSSL::Cipher.new("AES-128-CTR")
      c3.encrypt
      c3.key = "\x03".b * 16
      c3.iv = "\x04".b * 16
      p (c3.update("stream me") + c3.final).unpack1("H*")

      puts "-- gcm --"
      g = OpenSSL::Cipher.new("aes-256-gcm")
      g.encrypt
      g.key = key
      g.iv_len = 12
      g.iv = "\x05".b * 12
      g.auth_data = "aad"
      gct = g.update("authenticated!") + g.final
      tag = g.auth_tag
      p gct.unpack1("H*")
      p tag.bytesize
      p tag.unpack1("H*")
      gd = OpenSSL::Cipher.new("aes-256-gcm")
      gd.decrypt
      gd.key = key
      gd.iv = "\x05".b * 12
      gd.auth_tag = tag
      gd.auth_data = "aad"
      p gd.update(gct) + gd.final
      bd = OpenSSL::Cipher.new("aes-256-gcm")
      bd.decrypt
      bd.key = key
      bd.iv = "\x05".b * 12
      bd.auth_tag = tag.succ
      bd.auth_data = "aad"
      begin
        bd.update(gct) + bd.final
      rescue => e
        p [e.class, e.message]
      end

      puts "-- chacha20-poly1305 --"
      ch = OpenSSL::Cipher.new("chacha20-poly1305")
      ch.encrypt
      ch.key = key
      ch.iv = "\x06".b * 12
      ch.auth_data = ""
      cct = ch.update("chacha!") + ch.final
      p cct.unpack1("H*")
      p ch.auth_tag.unpack1("H*")

      puts "-- padding + errors --"
      np = OpenSSL::Cipher.new("AES-256-CBC")
      np.encrypt
      np.key = key
      np.iv = iv
      np.padding = 0
      p (np.update("0123456789abcdef") + np.final).unpack1("H*")
      begin
        np2 = OpenSSL::Cipher.new("AES-256-CBC")
        np2.encrypt
        np2.key = key
        np2.iv = iv
        np2.padding = 0
        np2.update("short") + np2.final
      rescue => e
        p [e.class, e.message]
      end
      begin
        OpenSSL::Cipher.new("NOPE-CIPHER")
      rescue => e
        p e.class
      end
      begin
        x = OpenSSL::Cipher.new("AES-256-CBC")
        x.encrypt
        x.key = "\x01".b * 16
      rescue => e
        p [e.class, e.message]
      end
      begin
        y = OpenSSL::Cipher.new("AES-256-CBC")
        y.decrypt
        y.key = key
        y.iv = iv
        y.update("x" * 16) + y.final
      rescue => e
        p [e.class, e.message]
      end
      begin
        z = OpenSSL::Cipher.new("AES-256-CBC")
        z.update("no key set")
      rescue => e
        p [e.class, e.message]
      end
      # RC4/BF live in OpenSSL 3's legacy provider, so `new` fails on both
      # runtimes. (Camellia/IDEA/SEED are additionally absent from zeo's vendored
      # build -- a documented divergence, so they are not exercised here.)
      %w[DES-EDE3-CBC RC4 BF-CBC aes-192-cbc].each do |n|
        begin
          OpenSSL::Cipher.new(n)
          puts "#{n}: ok"
        rescue OpenSSL::Cipher::CipherError
          puts "#{n}: CipherError"
        end
      end

      puts "-- reset + random + keyivgen --"
      r = OpenSSL::Cipher.new("AES-256-CBC")
      r.encrypt
      r.key = key
      r.iv = iv
      a1 = r.update("hello") + r.final
      r.reset
      r.iv = iv
      a2 = r.update("hello") + r.final
      p a1 == a2
      rk = OpenSSL::Cipher.new("aes-128-ctr")
      rk.encrypt
      p rk.random_key.bytesize
      p rk.random_iv.bytesize
      kv = OpenSSL::Cipher.new("aes-256-cbc")
      kv.encrypt
      kv.pkcs5_keyivgen("passphrase")
      e1 = kv.update("hello") + kv.final
      kv2 = OpenSSL::Cipher.new("aes-256-cbc")
      kv2.decrypt
      kv2.pkcs5_keyivgen("passphrase")
      p kv2.update(e1) + kv2.final
      p e1.unpack1("H*")

    RUBY

    _(result).must_answer <<~'OUT'
      -- metadata --
      OpenSSL::Cipher
      "AES-256-CBC"
      32
      16
      16
      false
      "AES-256-CBC"
      "ChaCha20-Poly1305"
      true
      true
      true
      false
      -- cbc round trip --
      "dd872cd9b22f5fa7870b7956830f7fd54ca58dc33e4a670c35a8d4283b614b61"
      #<Encoding:BINARY (ASCII-8BIT)>
      "secret message!!"
      -- ctr --
      "9d19f8e0ce7d836aca"
      -- gcm --
      "60d7955d07dc47ee167b0cf9a5b2"
      16
      "39d27b49f0fe0083133a2c2aa919ffd8"
      "authenticated!"
      [OpenSSL::Cipher::AuthTagError, "AEAD authentication tag verification failed"]
      -- chacha20-poly1305 --
      "5072c3b04c904c"
      "b5b0bf561a5de6d1a3b286aa1e794116"
      -- padding + errors --
      "2e87d243c361cf658497b59d01f0aa40"
      [OpenSSL::Cipher::CipherError, "cipher final failed: wrong final block length"]
      OpenSSL::Cipher::CipherError
      [ArgumentError, "key must be 32 bytes"]
      [OpenSSL::Cipher::CipherError, "cipher final failed: bad decrypt"]
      [OpenSSL::Cipher::CipherError, "key not set"]
      DES-EDE3-CBC: ok
      RC4: CipherError
      BF-CBC: CipherError
      aes-192-cbc: ok
      -- reset + random + keyivgen --
      true
      16
      16
      "hello"
      "433c20b132743669c4445b7a32c745da"
    OUT
  end

  it "openssl digest hmac kdf" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # OpenSSL tier 1: versions, Digest, HMAC, KDF, Random, secure compares.
      # Library version STRINGS are build-specific (zeo vendors its own OpenSSL
      # 3.x), so the golden prints shape checks, never the raw strings.
      require "openssl"

      puts "-- versions --"
      p OpenSSL::VERSION
      p OpenSSL::OPENSSL_VERSION.start_with?("OpenSSL 3.")
      p OpenSSL::OPENSSL_LIBRARY_VERSION.start_with?("OpenSSL 3.")
      p OpenSSL::OPENSSL_VERSION_NUMBER >= 0x30000000

      puts "-- digest --"
      d = OpenSSL::Digest.new("SHA256")
      p d.class
      p d.name
      p d.hexdigest("abc")
      d2 = OpenSSL::Digest::SHA256.new
      d2 << "a"
      d2.update("bc")
      p d2.hexdigest
      p d2.hexdigest # peek does not consume
      p d2.digest.bytesize
      p d2.digest_length
      p d2.block_length
      d2.reset
      p d2.hexdigest == OpenSSL::Digest::SHA256.new.hexdigest
      p OpenSSL::Digest::SHA256.hexdigest("abc")
      p OpenSSL::Digest::SHA256.digest("abc").bytesize
      p OpenSSL::Digest::SHA1.hexdigest("abc")
      p OpenSSL::Digest::MD5.hexdigest("abc")
      p OpenSSL::Digest.hexdigest("SHA1", "abc")
      p OpenSSL::Digest.digest("MD5", "abc").bytesize
      p OpenSSL::Digest.new("sha256").name
      p OpenSSL::Digest::SHA256.new("abc").hexdigest
      p [OpenSSL::Digest::MD5.new.digest_length, OpenSSL::Digest::SHA1.new.digest_length,
         OpenSSL::Digest::SHA384.new.digest_length, OpenSSL::Digest::SHA512.new.digest_length]
      seeded = OpenSSL::Digest.new("SHA512", "hello ")
      seeded << "world"
      p seeded.hexdigest == OpenSSL::Digest::SHA512.hexdigest("hello world")
      begin
        OpenSSL::Digest.new("NOPE")
      rescue => e
        p e.class
        p e.class.ancestors.include?(OpenSSL::OpenSSLError)
      end

      puts "-- hmac --"
      p OpenSSL::HMAC.hexdigest("SHA256", "key", "The quick brown fox")
      p OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "key", "The quick brown fox")
      p OpenSSL::HMAC.digest("SHA1", "key", "data").bytesize
      p OpenSSL::HMAC.base64digest("SHA256", "key", "data")
      h = OpenSSL::HMAC.new("key", "SHA256")
      p h.class
      h << "The quick "
      h.update("brown fox")
      p h.hexdigest
      p h.digest.bytesize
      p h.to_s == h.hexdigest
      h2 = OpenSSL::HMAC.new("key", OpenSSL::Digest.new("SHA256"))
      h2.update("The quick brown fox")
      p h2.hexdigest == h.hexdigest
      p h == h2
      h.reset
      h.update("x")
      p h.hexdigest == OpenSSL::HMAC.hexdigest("SHA256", "key", "x")
      begin
        OpenSSL::HMAC.new("key", "NOPE")
      rescue => e
        p e.class
      end

      puts "-- kdf --"
      p OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1000,
                                 length: 32, hash: "SHA256").unpack1("H*")
      p OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1,
                                 length: 20, hash: OpenSSL::Digest.new("SHA1")).unpack1("H*")
      p OpenSSL::KDF.hkdf("ikm", salt: "salt", info: "info", length: 32, hash: "SHA256").unpack1("H*")
      p OpenSSL::KDF.hkdf("ikm", salt: "", info: "", length: 16, hash: "SHA256").unpack1("H*")
      p OpenSSL::KDF.scrypt("password", salt: "salt", N: 1024, r: 8, p: 16, length: 16).unpack1("H*")
      begin
        OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1000, length: 32)
      rescue => e
        p [e.class, e.message]
      end
      p OpenSSL::KDF::KDFError.superclass
      p OpenSSL::PKCS5.pbkdf2_hmac("password", "salt", 1000, 32, "SHA256") ==
        OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1000, length: 32, hash: "SHA256")

      puts "-- random + compares --"
      p OpenSSL::Random.random_bytes(16).bytesize
      p OpenSSL::Random.random_bytes(16).encoding
      p OpenSSL.secure_compare("a" * 40, "a" * 40)
      p OpenSSL.secure_compare("secret", "secreT")
      p OpenSSL.fixed_length_secure_compare("abc", "abc")
      begin
        OpenSSL.fixed_length_secure_compare("abc", "abcd")
      rescue => e
        p [e.class, e.message]
      end

      puts "-- exception hierarchy --"
      p OpenSSL::OpenSSLError.superclass
      p OpenSSL::Digest::DigestError.superclass
      p OpenSSL::BNError.superclass
      p OpenSSL::Cipher::CipherError.superclass
      p OpenSSL::Cipher::AuthTagError.superclass
      p OpenSSL::SSL::SSLError.superclass
      begin
        OpenSSL::Digest.new("NOPE")
      rescue OpenSSL::OpenSSLError => e
        puts "caught as OpenSSLError"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      -- versions --
      "4.0.2"
      true
      true
      true
      -- digest --
      OpenSSL::Digest
      "SHA256"
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      32
      32
      64
      true
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      32
      "a9993e364706816aba3e25717850c26c9cd0d89d"
      "900150983cd24fb0d6963f7d28e17f72"
      "a9993e364706816aba3e25717850c26c9cd0d89d"
      16
      "SHA256"
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      [16, 20, 48, 64]
      true
      OpenSSL::Digest::DigestError
      true
      -- hmac --
      "203d1e5cedd2d18f8c5a3beff0bd9c1ebcb97097dfcb288c46b00c9227fde2c0"
      "203d1e5cedd2d18f8c5a3beff0bd9c1ebcb97097dfcb288c46b00c9227fde2c0"
      20
      "UDH+PZicbRU3oBP6bnOdojRj/a7DtwE32Cjjas4iG9A="
      OpenSSL::HMAC
      "203d1e5cedd2d18f8c5a3beff0bd9c1ebcb97097dfcb288c46b00c9227fde2c0"
      32
      true
      true
      true
      true
      OpenSSL::Digest::DigestError
      -- kdf --
      "632c2812e46d4604102ba7618e9d6d7d2f8128f6266b4a03264d2a0460b7dcb3"
      "0c60c80f961f0e71f3a9b524af6012062fe037a6"
      "fe8f9615d2374c0d17f77d1aeaf408c2e75fe0466073d0def23c733e2f862dfd"
      "d58e7c1c4394984eb3ca168ff7b709d4"
      "1effd93afcf2b28964026631bf4362b0"
      [ArgumentError, "missing keyword: :hash"]
      OpenSSL::OpenSSLError
      true
      -- random + compares --
      16
      #<Encoding:BINARY (ASCII-8BIT)>
      true
      false
      true
      [ArgumentError, "inputs must be of equal length"]
      -- exception hierarchy --
      StandardError
      OpenSSL::OpenSSLError
      OpenSSL::OpenSSLError
      OpenSSL::OpenSSLError
      OpenSSL::Cipher::CipherError
      OpenSSL::OpenSSLError
      caught as OpenSSLError
    OUT
  end

  it "openssl secure compare" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      require "openssl"

      # Constant-time string comparison, length-independent: true iff equal.
      p OpenSSL.secure_compare("s3cr3t-token", "s3cr3t-token")
      p OpenSSL.secure_compare("s3cr3t-token", "s3cr3t-tokeX")
      p OpenSSL.secure_compare("short", "much longer value")

      # fixed_length_secure_compare demands equal-length inputs.
      p OpenSSL.fixed_length_secure_compare("0123456789abcdef", "0123456789abcdef")
      p OpenSSL.fixed_length_secure_compare("0123456789abcdef", "0123456789abcdeX")
      begin
        OpenSSL.fixed_length_secure_compare("abc", "abcd")
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      false
      ArgumentError: inputs must be of equal length
    OUT
  end

  it "openssl ssl surface" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # OpenSSL::SSL's offline surface: constants, context configuration, and an
      # unconnected SSLSocket. A real handshake needs a network peer, so it is not
      # exercised here (the suite stays hermetic).
      require "openssl"
      require "socket"

      puts "-- constants --"
      p OpenSSL::SSL::VERIFY_NONE
      p OpenSSL::SSL::VERIFY_PEER
      p OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
      p OpenSSL::SSL::TLS1_2_VERSION
      p OpenSSL::SSL::TLS1_3_VERSION
      p OpenSSL::SSL::OP_NO_COMPRESSION.is_a?(Integer)
      p OpenSSL::X509::V_OK
      p OpenSSL::X509::V_ERR_CERT_HAS_EXPIRED
      p OpenSSL::X509::V_ERR_HOSTNAME_MISMATCH

      puts "-- context defaults --"
      ctx = OpenSSL::SSL::SSLContext.new
      p ctx.class
      p ctx.verify_mode
      p ctx.verify_hostname
      p ctx.ca_file
      p ctx.session_cache_mode
      ctx.set_params
      p ctx.verify_mode
      p ctx.verify_hostname
      p ctx.cert_store.class

      puts "-- context overrides --"
      c2 = OpenSSL::SSL::SSLContext.new
      c2.set_params(verify_mode: OpenSSL::SSL::VERIFY_NONE)
      p c2.verify_mode
      p c2.verify_hostname
      c3 = OpenSSL::SSL::SSLContext.new
      c3.verify_mode = OpenSSL::SSL::VERIFY_PEER
      c3.verify_hostname = true
      c3.ca_file = "/nonexistent-bundle.pem"
      c3.min_version = OpenSSL::SSL::TLS1_2_VERSION
      c3.max_version = OpenSSL::SSL::TLS1_3_VERSION
      p c3.verify_mode
      p c3.verify_hostname
      p c3.ca_file

      puts "-- store --"
      st = OpenSSL::X509::Store.new
      p st.class
      p st.set_default_paths.equal?(st)

      puts "-- unconnected socket --"
      srv = TCPServer.new("127.0.0.1", 0)
      port = srv.addr[1]
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock, c2)
      p ssl.class
      p ssl.sync_close
      ssl.sync_close = true
      p ssl.sync_close
      p ssl.hostname
      ssl.hostname = "example.com"
      p ssl.hostname
      p ssl.state
      p ssl.io.equal?(sock)
      p ssl.to_io.equal?(sock)
      p ssl.context.equal?(c2)
      sock.close
      srv.close

      puts "-- errors --"
      p OpenSSL::SSL::SSLError.superclass
      p OpenSSL::SSL::SSLError.ancestors.include?(OpenSSL::OpenSSLError)
      p OpenSSL::X509::Certificate.superclass

    RUBY

    _(result).must_answer <<~'OUT'
      -- constants --
      0
      1
      2
      771
      772
      true
      0
      10
      62
      -- context defaults --
      OpenSSL::SSL::SSLContext
      0
      false
      nil
      2
      1
      true
      OpenSSL::X509::Store
      -- context overrides --
      0
      true
      1
      true
      "/nonexistent-bundle.pem"
      -- store --
      OpenSSL::X509::Store
      false
      -- unconnected socket --
      OpenSSL::SSL::SSLSocket
      nil
      true
      nil
      "example.com"
      "PINIT"
      true
      true
      true
      -- errors --
      OpenSSL::OpenSSLError
      true
      Object
    OUT
  end

  it "openssl tls client" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # The client-TLS surface that needs no network peer: an SSLSocket over an
      # unconnected socket answers its configuration and forwards the
      # descriptor-level family to the socket underneath, and the RFC 6125
      # hostname matcher (post_connection_check's core) is exercised through
      # OpenSSL::SSL.verify_certificate_identity's own rules on a live handshake
      # elsewhere. A real handshake is deliberately NOT here -- the suite is
      # hermetic.
      require "openssl"
      require "socket"

      srv = TCPServer.new("127.0.0.1", 0)
      port = srv.addr[1]
      sock = TCPSocket.new("127.0.0.1", port)

      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_NONE)
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)

      puts "-- identity --"
      p ssl.class
      p ssl.state
      p ssl.io.equal?(sock)
      p ssl.to_io.equal?(sock)
      p ssl.context.equal?(ctx)

      puts "-- forwarded to the socket --"
      p ssl.closed?
      p ssl.fileno == sock.fileno
      p ssl.peeraddr[1] == port
      p ssl.addr[0]
      p ssl.local_address.ip_address

      puts "-- session cache constants --"
      C = OpenSSL::SSL::SSLContext
      p [C::SESSION_CACHE_OFF, C::SESSION_CACHE_CLIENT, C::SESSION_CACHE_SERVER,
         C::SESSION_CACHE_BOTH]
      p [C::SESSION_CACHE_NO_AUTO_CLEAR, C::SESSION_CACHE_NO_INTERNAL_LOOKUP,
         C::SESSION_CACHE_NO_INTERNAL_STORE, C::SESSION_CACHE_NO_INTERNAL]
      ctx.session_cache_mode = C::SESSION_CACHE_CLIENT | C::SESSION_CACHE_NO_INTERNAL_STORE
      p ctx.session_cache_mode

      puts "-- before the handshake --"
      p ssl.peer_cert
      begin
        ssl.post_connection_check("example.com")
      rescue => e
        p [e.class, e.message]
      end

      ssl.sync_close = true
      ssl.close
      p sock.closed?
      srv.close

    RUBY

    _(result).must_answer <<~'OUT'
      -- identity --
      OpenSSL::SSL::SSLSocket
      "PINIT"
      true
      true
      true
      -- forwarded to the socket --
      false
      true
      true
      "AF_INET"
      "127.0.0.1"
      -- session cache constants --
      [0, 1, 2, 3]
      [128, 256, 512, 768]
      513
      -- before the handshake --
      nil
      [OpenSSL::SSL::SSLError, "Peer verification enabled, but no certificate received."]
      true
    OUT
  end

  it "pkcs7 and pkcs12 sign encrypt and bundle" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # PKCS7 and PKCS12 over the host's libssl: a signed message verifies
      # against its signer, detached or attached; an enveloped message opens
      # with the recipient's key; a PKCS12 bundle round-trips its key, its
      # certificate and its chain under a passphrase.

      require "openssl"

      def certificate(cn, key, serial, issuer = nil, issuer_key = key)
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = serial
        cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
        cert.issuer = issuer ? issuer.subject : cert.subject
        cert.public_key = key
        cert.not_before = Time.now - 3600
        cert.not_after = Time.now + 3600
        factory = OpenSSL::X509::ExtensionFactory.new(issuer || cert, cert)
        cert.add_extension(factory.create_extension("basicConstraints", issuer ? "CA:FALSE" : "CA:TRUE", true))
        cert.add_extension(factory.create_extension("keyUsage", issuer ? "digitalSignature, keyEncipherment" : "keyCertSign", true))
        cert.sign(issuer_key, "SHA256")
      end

      ca_key = OpenSSL::PKey::RSA.new(2048)
      ca = certificate("ca", ca_key, 1)
      key = OpenSSL::PKey::RSA.new(2048)
      cert = certificate("signer", key, 2, ca, ca_key)
      store = OpenSSL::X509::Store.new
      store.add_cert(ca)
      data = "a message to sign\n"

      puts "-- signed --"
      p7 = OpenSSL::PKCS7.sign(cert, key, data, [ca], OpenSSL::PKCS7::BINARY)
      p p7.type, p7.detached?, p7.certificates.map { |c| c.subject.to_s }
      p p7.signers.map { |s| [s.issuer.to_s, s.serial.to_i] }
      p7 = OpenSSL::PKCS7.new(p7.to_der)
      p p7.verify([], store, nil, OpenSSL::PKCS7::BINARY), p7.data, p7.error_string
      p OpenSSL::PKCS7.new(p7.to_pem).verify([cert], store, nil, OpenSSL::PKCS7::NOVERIFY)
      p OpenSSL::PKCS7.new(p7.to_der).verify([], OpenSSL::X509::Store.new, nil, OpenSSL::PKCS7::BINARY)
      detached = OpenSSL::PKCS7.sign(cert, key, data, [], OpenSSL::PKCS7::DETACHED | OpenSSL::PKCS7::BINARY)
      p detached.detached?, detached.data
      p detached.verify([], store, data, OpenSSL::PKCS7::BINARY), detached.verify([], store, "tampered", OpenSSL::PKCS7::BINARY)
      smime = OpenSSL::PKCS7.write_smime(detached, data, OpenSSL::PKCS7::DETACHED | OpenSSL::PKCS7::BINARY)
      p smime.lines.first.chomp, OpenSSL::PKCS7.read_smime(smime).verify([], store, data, OpenSSL::PKCS7::BINARY)

      puts "-- enveloped --"
      enveloped = OpenSSL::PKCS7.encrypt([cert], data, OpenSSL::Cipher.new("AES-256-CBC"), OpenSSL::PKCS7::BINARY)
      p enveloped.type, enveloped.recipients.map { |r| r.serial.to_i }
      p OpenSSL::PKCS7.new(enveloped.to_der).decrypt(key, cert)
      begin
        enveloped.decrypt(ca_key, ca)
      rescue OpenSSL::PKCS7::PKCS7Error
        puts "PKCS7Error"
      end

      puts "-- pkcs12 --"
      p12 = OpenSSL::PKCS12.create("passphrase", "friendly", key, cert, [ca])
      parsed = OpenSSL::PKCS12.new(p12.to_der, "passphrase")
      p parsed.key.to_der == key.to_der, parsed.certificate == cert, parsed.ca_certs.map(&:subject).map(&:to_s)
      begin
        OpenSSL::PKCS12.new(p12.to_der, "wrong")
      rescue OpenSSL::PKCS12::PKCS12Error
        puts "PKCS12Error"
      end
      bare = OpenSSL::PKCS12.create(nil, nil, key, cert, nil, nil, nil, nil, nil, nil)
      p OpenSSL::PKCS12.new(bare.to_der).certificate == cert

    RUBY

    _(result).must_answer <<~'OUT'
      -- signed --
      :signed
      false
      ["/CN=signer", "/CN=ca"]
      [["/CN=ca", 2]]
      true
      "a message to sign\n"
      nil
      true
      false
      true
      "a message to sign\n"
      true
      false
      "MIME-Version: 1.0"
      true
      -- enveloped --
      :enveloped
      [2]
      "a message to sign\n"
      PKCS7Error
      -- pkcs12 --
      true
      true
      ["/CN=ca"]
      PKCS12Error
      true
    OUT
  end

  it "subclass of a native type wraps one" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # A user class inheriting a native type has no struct of its own: its instances
      # wrap the real native value as a payload and carry their own ivars beside it.
      # `Queue` has a real empty form, so `super()` builds one; nothing in the IO
      # family does -- no descriptor, peer or algorithm can be conjured -- so those
      # subclasses seat the real payload through `super`, which is the whole reason
      # gems subclass them.
      #
      # actionpool's `Queue < ::Queue`, kgio's `Kgio::Pipe < IO`, dalli's
      # `TCP < TCPSocket`, and the `SSLSocket < OpenSSL::SSL::SSLSocket` that bunny,
      # dalli and mongo each write -- the largest single subclassing bucket in the
      # gem corpus.

      require "socket"
      require "openssl"
      require "tmpdir"

      # A real empty form: `super()` builds the queue, and the subclass adds an ivar
      # on top of the inherited behaviour.
      class Jobs < ::Queue
        def initialize(name)
          super()
          @name = name
        end

        attr_reader :name

        def push_all(*xs) = xs.each { |x| push(x) }
      end

      q = Jobs.new("work")
      q.push_all(1, 2, 3)
      p q.name
      p q.size
      p q.pop
      p q.class
      p q.is_a?(Queue)
      p Jobs.superclass
      p Jobs.ancestors.take(3)

      # The `File` shape: the payload arrives through `super`, and every inherited
      # method reads it. `IO.sysopen` hands over a descriptor nobody else owns.
      class Tagged < IO
        def initialize(fd, tag)
          super(fd)
          @tag = tag
        end

        attr_reader :tag

        def first_line = "#{@tag}: #{gets}"
      end

      Dir.mktmpdir do |dir|
        path = File.join(dir, "log")
        File.write(path, "alpha\nbeta\n")
        io = Tagged.new(IO.sysopen(path), :note)
        p io.class
        p io.tag
        p io.is_a?(IO)
        p io.first_line
        p io.read
        io.close
        p io.closed?
      end

      p Tagged.superclass

      # Deeper in the same family: the payload root is the NEAREST native ancestor,
      # so a `TCPSocket` subclass is a TCPSocket, not the `IO` four links above it.
      class Named < TCPSocket
        def initialize(host, port, name)
          super(host, port)
          @name = name
        end

        attr_reader :name
      end

      p Named.superclass
      p Named.ancestors.include?(IO)
      p Named.instance_method(:name).owner

      # A socket wrapper, and a cipher: both named at construction, both the same
      # shape.
      class Wrapped < OpenSSL::SSL::SSLSocket
        def wrapped? = true
      end

      p Wrapped.superclass
      p Wrapped.new.wrapped? rescue p :needs_a_socket

      class Loud < OpenSSL::Cipher
        def shout = "LOUD"
      end

      p Loud.superclass
      c = Loud.new("aes-256-cbc")
      p c.class
      p c.shout
      p c.name
      p c.is_a?(OpenSSL::Cipher)

      class Named2 < OpenSSL::Digest
        def label = "#{name} digest"
      end

      d = Named2.new("SHA256")
      p Named2.superclass
      p d.class
      p d.label
      p d.hexdigest("abc")

      # `Fiber` is `Thread`'s shape: the block IS the body, so `super(&block)` is the
      # only way to seat one. hexapdf's `FiberWithLength` records a length it knows
      # before the fiber runs.
      class Measured < Fiber
        def initialize(length, &block)
          super(&block)
          @length = length || -1
        end

        attr_reader :length
      end

      f = Measured.new(3) { Fiber.yield(:a); Fiber.yield(:b); :done }
      p Measured.superclass
      p f.class
      p f.length
      p f.resume
      p f.resume
      p f.resume
      p f.alive?

    RUBY

    _(result).must_answer <<~'OUT'
      "work"
      3
      1
      Jobs
      true
      Thread::Queue
      [Jobs, Thread::Queue, Object]
      Tagged
      :note
      true
      "note: alpha\n"
      "beta\n"
      true
      IO
      TCPSocket
      true
      Named
      OpenSSL::SSL::SSLSocket
      :needs_a_socket
      OpenSSL::Cipher
      Loud
      "LOUD"
      "AES-256-CBC"
      true
      OpenSSL::Digest
      Named2
      "SHA256 digest"
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      Fiber
      Measured
      3
      :a
      :b
      :done
      false
    OUT
  end

  it "timestamp authority stamps and verifies" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # OpenSSL::Timestamp over the host's libssl: a request for a SHA-256
      # imprint, a factory that answers it with a token from a TSA certificate,
      # and a verification of that token against the request and a store.

      require "openssl"

      def certificate(cn, key, serial, issuer, issuer_key, extensions)
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = serial
        cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
        cert.issuer = issuer ? issuer.subject : cert.subject
        cert.public_key = key
        cert.not_before = Time.utc(2026, 1, 1)
        cert.not_after = Time.utc(2036, 1, 1)
        factory = OpenSSL::X509::ExtensionFactory.new(issuer || cert, cert)
        extensions.each { |oid, value, critical| cert.add_extension(factory.create_extension(oid, value, critical)) }
        cert.sign(issuer_key, "SHA256")
      end

      ca_key = OpenSSL::PKey::RSA.new(2048)
      ca = certificate("root", ca_key, 1, nil, ca_key, [["basicConstraints", "CA:TRUE", true], ["keyUsage", "keyCertSign, cRLSign", true]])
      tsa_key = OpenSSL::PKey::RSA.new(2048)
      tsa = certificate("tsa", tsa_key, 2, ca, ca_key, [["extendedKeyUsage", "timeStamping", true]])
      plain = certificate("plain", tsa_key, 3, ca, ca_key, [])

      puts "-- request --"
      data = "the document"
      request = OpenSSL::Timestamp::Request.new
      p request.version, request.cert_requested?, request.nonce, request.policy_id
      request.algorithm = "SHA256"
      request.message_imprint = OpenSSL::Digest.digest("SHA256", data)
      request.policy_id = "1.2.3.4.5"
      request.nonce = 42
      request.cert_requested = true
      request = OpenSSL::Timestamp::Request.new(request.to_der)
      p request.algorithm, request.message_imprint.bytesize, request.policy_id, request.nonce.to_i, request.cert_requested?
      begin
        OpenSSL::Timestamp::Request.new.to_der
      rescue OpenSSL::Timestamp::TimestampError => e
        puts "TimestampError #{e.message}"
      end

      puts "-- factory --"
      factory = OpenSSL::Timestamp::Factory.new
      factory.gen_time = Time.utc(2026, 9, 17, 8, 0, 0)
      factory.serial_number = 7
      factory.allowed_digests = ["sha256", "sha512"]
      factory.default_policy_id = "1.2.3.4.6"
      factory.additional_certs = [ca]
      response = factory.create_timestamp(tsa_key, tsa, request)
      response = OpenSSL::Timestamp::Response.new(response.to_der)
      p response.status.to_i, response.failure_info, response.status_text
      info = response.token_info
      p info.version, info.policy_id, info.algorithm, info.serial_number.to_i, info.gen_time, info.ordering, info.nonce.to_i
      p info.message_imprint == request.message_imprint, response.tsa_certificate.subject.to_s, response.token.type
      p OpenSSL::Timestamp::TokenInfo.new(info.to_der).serial_number.to_i

      puts "-- verify --"
      store = OpenSSL::X509::Store.new
      store.add_cert(ca)
      store.time = Time.utc(2026, 9, 17)
      p response.verify(request, store, [tsa]).equal?(response)
      other = OpenSSL::Timestamp::Request.new(request.to_der)
      other.message_imprint = OpenSSL::Digest.digest("SHA256", "another document")
      begin
        response.verify(other, store)
      rescue OpenSSL::Timestamp::TimestampError => e
        puts "TimestampError #{e.message.start_with?("TS_RESP_verify_response")}"
      end

      puts "-- refusals --"
      begin
        factory.create_timestamp(tsa_key, plain, request)
      rescue OpenSSL::Timestamp::TimestampError => e
        puts "TimestampError #{e.message}"
      end
      factory.serial_number = nil
      begin
        factory.create_timestamp(tsa_key, tsa, request)
      rescue OpenSSL::Timestamp::TimestampError => e
        puts "TimestampError #{e.message}"
      end
      factory.serial_number = 8
      factory.allowed_digests = ["sha1"]
      rejected = factory.create_timestamp(tsa_key, tsa, request)
      p rejected.status.to_i, rejected.failure_info, rejected.status_text, rejected.token

    RUBY

    _(result).must_answer <<~'OUT'
      -- request --
      1
      true
      nil
      nil
      "SHA256"
      32
      "1.2.3.4.5"
      42
      true
      TimestampError Message imprint missing algorithm
      -- factory --
      0
      nil
      []
      1
      "1.2.3.4.5"
      "SHA256"
      7
      2026-09-17 08:00:00 UTC
      false
      42
      true
      "/CN=tsa"
      :signed
      7
      -- verify --
      true
      TimestampError true
      -- refusals --
      TimestampError Certificate does not contain the timestamping extension: invalid signer certificate purpose
      TimestampError @serial_number must be set.
      2
      :BAD_ALG
      ["Message digest algorithm is not supported."]
      nil
    OUT
  end

  it "tls handshake completes over loopback" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY')
      # SSL over the host's libssl: a server and a client in one process over
      # 127.0.0.1, with a certificate made here. The client verifies the peer
      # and its host name, both sides pick ALPN "h2", and lines echo both ways;
      # a second connection resumes the first session, and a client that trusts
      # nothing fails verification.

      require "openssl"
      require "socket"

      key = OpenSSL::PKey::EC.generate("prime256v1")
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=localhost")
      cert.public_key = key
      cert.not_before = Time.now - 3600
      cert.not_after = Time.now + 3600
      factory = OpenSSL::X509::ExtensionFactory.new(cert, cert)
      cert.add_extension(factory.create_extension("subjectAltName", "DNS:localhost, IP:127.0.0.1"))
      cert.add_extension(factory.create_extension("basicConstraints", "CA:TRUE", true))
      cert.sign(key, "SHA256")

      server_ctx = OpenSSL::SSL::SSLContext.new
      server_ctx.cert = cert
      server_ctx.key = key
      server_ctx.min_version = OpenSSL::SSL::TLS1_2_VERSION
      server_ctx.alpn_protocols = %w[h2 http/1.1]
      server_ctx.alpn_select_cb = ->(protocols) { protocols.include?("h2") ? "h2" : protocols.first }
      server_ctx.session_id_context = "ze0"
      server_names = []
      server_ctx.servername_cb = proc { |_ssl, name| server_names << name; nil }

      tcp = TCPServer.new("127.0.0.1", 0)
      server = OpenSSL::SSL::SSLServer.new(tcp, server_ctx)
      port = tcp.addr[1]

      acceptor = Thread.new do
        3.times.map do
          ssl = server.accept
          while (line = ssl.gets)
            ssl.puts(line.upcase)
          end
          ssl.close
          :served
        rescue OpenSSL::SSL::SSLError => e
          "server: #{e.class}"
        end
      end

      def connect(port, ctx, session = nil)
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        ssl.hostname = "localhost"
        ssl.session = session if session
        ssl.sync_close = true
        ssl.connect
        ssl
      end

      store = OpenSSL::X509::Store.new
      store.add_cert(cert)
      client_ctx = OpenSSL::SSL::SSLContext.new
      client_ctx.cert_store = store
      client_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      client_ctx.verify_hostname = true
      client_ctx.alpn_protocols = %w[h2 http/1.1]
      new_sessions = 0
      client_ctx.session_cache_mode = OpenSSL::SSL::SSLContext::SESSION_CACHE_CLIENT
      client_ctx.session_new_cb = proc { new_sessions += 1 }

      ssl = connect(port, client_ctx)
      p ssl.alpn_protocol, ssl.verify_result == OpenSSL::X509::V_OK, ssl.peer_cert.subject.to_s
      p ssl.peer_cert_chain.size, ssl.cipher.first.start_with?("TLS_"), ssl.ssl_version.start_with?("TLS")
      ssl.puts "hello"
      ssl.write "world\n"
      p ssl.gets, ssl.readpartial(100)
      ssl.puts "bye"
      p ssl.read(4)
      ssl.post_connection_check("localhost")
      begin
        ssl.post_connection_check("example.com")
      rescue OpenSSL::SSL::SSLError => e
        puts "SSLError #{e.message}"
      end
      session = ssl.session
      ssl.close
      p ssl.closed?

      ssl = connect(port, client_ctx, session)
      ssl.puts "again"
      p ssl.gets
      ssl.close

      untrusting = OpenSSL::SSL::SSLContext.new
      untrusting.cert_store = OpenSSL::X509::Store.new
      untrusting.verify_mode = OpenSSL::SSL::VERIFY_PEER
      begin
        connect(port, untrusting)
      rescue OpenSSL::SSL::SSLError => e
        puts "SSLError #{e.message.include?("certificate verify failed")}"
      end

      p acceptor.value.map { |v| v.is_a?(String) ? v.split(":").first : v }
      p server_names.uniq, new_sessions.positive?
      server.close

    RUBY

    _(result).must_answer <<~'OUT'
      "h2"
      true
      "/CN=localhost"
      1
      true
      true
      "HELLO\n"
      "WORLD\n"
      "BYE\n"
      SSLError hostname "example.com" does not match the server certificate
      true
      "AGAIN\n"
      SSLError true
      [:served, :served, "server"]
      ["localhost"]
      true
    OUT
  end

  it "yaml loads and entropy draws run concurrently under the armed gvl" do
    skip "needs libssl" unless Ze0::Spec.need?("libssl")

    result = ze0(<<~'RUBY', env: {"ZEO_GVL" => "1"})
      # The ext tail of the sweep: two threads Psych-load the same file
      # while a third draws OS entropy, all in ZEO_GVL=1 mode.


      require "yaml"
      require "openssl"
      y = File.join(ENV["TMPDIR"] || "/tmp", "zeo_yaml_probe_#{Process.pid}.yml")
      File.write(y, "name: zeo\ncount: 3\n")
      loads = 2.times.map { Thread.new { YAML.load_file(y) } }
      entropy = Thread.new { OpenSSL::Random.random_bytes(16) }
      docs = loads.map(&:value)
      p docs[0]["name"]
      p docs[1]["count"]
      p entropy.value.bytesize
      File.delete(y)

    RUBY

    _(result).must_answer <<~'OUT'
      "zeo"
      3
      16
    OUT
  end
end
