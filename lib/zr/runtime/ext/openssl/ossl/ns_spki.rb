# frozen_string_literal: true

# ossl_ns_spki.c: OpenSSL::Netscape::SPKI over NETSCAPE_SPKI.
module OpenSSL
  Lib.attach_all(
    NETSCAPE_SPKI_new: [[], :pointer],
    NETSCAPE_SPKI_free: [%i[pointer], :void],
    NETSCAPE_SPKI_b64_decode: [%i[buffer int], :pointer],
    NETSCAPE_SPKI_b64_encode: [%i[pointer], :pointer],
    d2i_NETSCAPE_SPKI: [%i[pointer buffer long], :pointer],
    i2d_NETSCAPE_SPKI: [%i[pointer buffer], :int],
    NETSCAPE_SPKI_print: [%i[pointer pointer], :int],
    NETSCAPE_SPKI_get_pubkey: [%i[pointer], :pointer],
    NETSCAPE_SPKI_set_pubkey: [%i[pointer pointer], :int],
    NETSCAPE_SPKI_sign: [%i[pointer pointer pointer], :int],
    NETSCAPE_SPKI_verify: [%i[pointer pointer], :int]
  )

  module Netscape
    class SPKIError < OpenSSLError; end

    class SPKI; end
  end

  module Ossl
    SPKI = DataType.new("OpenSSL/NETSCAPE_SPKI", Netscape::SPKI, :NETSCAPE_SPKI_free, [RuntimeError, "SPKI wasn't initialized!"], create: lambda {
      Lib.NETSCAPE_SPKI_new.tap { |spki| raise Ossl.error(Netscape::SPKIError) if spki.zero? }
    })

    # spki->spkac->challenge (x509.h: NETSCAPE_SPKI starts with its
    # NETSCAPE_SPKAC, whose second field is the challenge).
    def self.spki_challenge(spki) = Lib.read_pointer(Lib.read_pointer(spki) + 8)
  end

  module Netscape
    class SPKI
      def initialize(*args)
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..1)" if args.size > 1

        Ossl.want_uninitialized(self, Ossl::SPKI)
        return Ossl::SPKI.create(self) if args.empty?

        buffer = Ossl.string_value(args.first)
        spki = Lib.NETSCAPE_SPKI_b64_decode(buffer, buffer.bytesize)
        if spki.zero?
          Ossl.clear_error
          spki = Ossl.d2i(:d2i_NETSCAPE_SPKI, buffer)
          raise Ossl.error(SPKIError, "d2i_NETSCAPE_SPKI") if spki.zero?
        end
        Ossl::SPKI.set(self, spki)
        self
      end

      def to_der = Ossl.i2d(:i2d_NETSCAPE_SPKI, Ossl::SPKI.fetch(self), SPKIError, "i2d_NETSCAPE_SPKI")

      def to_pem
        text = Lib.NETSCAPE_SPKI_b64_encode(Ossl::SPKI.fetch(self))
        raise Ossl.error(SPKIError) if text.zero?

        begin
          Lib.string(text)
        ensure
          Lib.OPENSSL_free(text)
        end
      end
      alias to_s to_pem

      def to_text
        spki = Ossl::SPKI.fetch(self)
        Ossl.bio_output(SPKIError) { |bio| Lib.NETSCAPE_SPKI_print(bio, spki) }
      end

      def public_key
        pkey = Lib.NETSCAPE_SPKI_get_pubkey(Ossl::SPKI.fetch(self))
        raise Ossl.error(SPKIError) if pkey.zero?

        Ossl.pkey_wrap(pkey)
      end

      def public_key=(key)
        spki = Ossl::SPKI.fetch(self)
        pkey = Ossl.pkey(key)
        Ossl.check_public_key(pkey)
        raise Ossl.error(SPKIError, "NETSCAPE_SPKI_set_pubkey") if Lib.NETSCAPE_SPKI_set_pubkey(spki, pkey).zero?

        key
      end

      def sign(key, digest)
        pkey = Ossl.private_pkey(key)
        md, _holder = Ossl.fetch_md(digest)
        raise Ossl.error(SPKIError, "NETSCAPE_SPKI_sign") if Lib.NETSCAPE_SPKI_sign(Ossl::SPKI.fetch(self), pkey, md).zero?

        self
      end

      def verify(key)
        spki = Ossl::SPKI.fetch(self)
        pkey = Ossl.pkey(key)
        Ossl.check_public_key(pkey)
        case Lib.NETSCAPE_SPKI_verify(spki, pkey)
        when 0
          Ossl.clear_error
          false
        when 1 then true
        else raise Ossl.error(SPKIError, "NETSCAPE_SPKI_verify")
        end
      end

      def challenge
        challenge = Ossl.spki_challenge(Ossl::SPKI.fetch(self))
        return "".b if Lib.ASN1_STRING_length(challenge) <= 0

        Ossl.asn1str_to_str(challenge)
      end

      def challenge=(challenge)
        challenge = Ossl.string_value(challenge)
        spki = Ossl::SPKI.fetch(self)
        raise Ossl.error(SPKIError) if Lib.ASN1_STRING_set(Ossl.spki_challenge(spki), challenge, challenge.bytesize).zero?

        challenge
      end
    end
  end
end
