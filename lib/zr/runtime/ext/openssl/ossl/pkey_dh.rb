# frozen_string_literal: true

# Derived from the C half of ruby's openssl gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ossl_pkey_dh.c: OpenSSL::PKey::DH.
module OpenSSL
  Lib.attach_all(
    EVP_PKEY_get0_DH: [%i[pointer], :pointer],
    DH_free: [%i[pointer], :void],
    DH_get0_pqg: [%i[pointer buffer buffer buffer], :void],
    DH_get0_key: [%i[pointer buffer buffer], :void],
    DH_get0_engine: [%i[pointer], :pointer],
    ASN1_d2i_bio: [%i[pointer pointer pointer pointer], :pointer],
    PEM_write_bio_DHparams: [%i[pointer pointer], :int],
    i2d_DHparams: [%i[pointer buffer], :int]
  )

  module Lib
    # d2i_DHparams_bio (dh.h).
    def self.d2i_DHparams_bio(bio, out) = ASN1_d2i_bio(function_address(:DH_new), function_address(:d2i_DHparams), bio, out)
  end

  module Ossl
    def self.dh(object) = legacy_key(object, Lib::EVP_PKEY_DH, "DH", :EVP_PKEY_get0_DH)
  end

  module PKey
    class DH < PKey
      def initialize(*args)
        Ossl.want_uninitialized(self, Ossl::PKEY)
        raise ArgumentError, wrong_arity(args.size, 0..1) if args.size > 1
        raise ArgumentError, "OpenSSL::PKey::DH.new cannot be called without arguments; pkeys are immutable with OpenSSL 3.0" if args.empty?

        arg = Ossl.to_der_if_possible(args.first)
        bio, _arg = Ossl.obj2bio(arg)
        dh = Lib.d2i_DHparams_bio(bio, nil)
        unless dh.zero?
          Lib.BIO_free(bio)
          Ossl.assign_legacy(self, Lib::EVP_PKEY_DH, dh, :DH_free, "EVP_PKEY_assign_DH")
          return self
        end
        Ossl.bio_reset(bio)
        Ossl.with_password(nil, nil) { |id| Ossl.read_typed_pkey(self, bio, id, Lib::EVP_PKEY_DH, "could not parse pkey") }
        self
      end

      def public? = !Ossl.get0(:DH_get0_key, Ossl.dh(self), 2)[0].zero?

      def private?
        dh = Ossl.dh(self)
        engine = Lib.respond_to?(:DH_get0_engine) ? Lib.DH_get0_engine(dh) : 0
        !Ossl.get0(:DH_get0_key, dh, 2)[1].zero? || !engine.zero?
      end

      def export
        dh = Ossl.dh(self)
        bio = Lib.BIO_new(Lib.BIO_s_mem)
        raise Ossl.error(PKeyError) if bio.zero?

        if Lib.PEM_write_bio_DHparams(bio, dh).zero?
          Lib.BIO_free(bio)
          raise Ossl.error(PKeyError)
        end
        Ossl.membio2str(bio)
      end
      alias to_pem export
      alias to_s export

      def to_der
        dh = Ossl.dh(self)
        length = Lib.i2d_DHparams(dh, nil)
        raise Ossl.error(PKeyError) if length <= 0

        out = Lib.buffer(length)
        raise Ossl.error(PKeyError) if Lib.i2d_DHparams(dh, [Native.address(out)].pack("J")).negative?

        out
      end

      def params_ok?
        ctx = Lib.EVP_PKEY_CTX_new(Ossl.pkey(self), nil)
        raise Ossl.error(PKeyError, "EVP_PKEY_CTX_new") if ctx.zero?

        answer = Ossl.with_pkey_ctx(ctx) { Lib.EVP_PKEY_param_check(ctx) }
        return true if answer == 1

        Ossl.clear_error
        false
      end

      def p = Ossl.bn_or_nil(Ossl.get0(:DH_get0_pqg, Ossl.dh(self), 3)[0])

      def q = Ossl.bn_or_nil(Ossl.get0(:DH_get0_pqg, Ossl.dh(self), 3)[1])

      def g = Ossl.bn_or_nil(Ossl.get0(:DH_get0_pqg, Ossl.dh(self), 3)[2])

      def pub_key = Ossl.bn_or_nil(Ossl.get0(:DH_get0_key, Ossl.dh(self), 2)[0])

      def priv_key = Ossl.bn_or_nil(Ossl.get0(:DH_get0_key, Ossl.dh(self), 2)[1])

      def set_pqg(_p, _q, _g) = raise(PKeyError, "dh#set_pqg= is incompatible with OpenSSL 3.0")

      def set_key(_pub_key, _priv_key) = raise(PKeyError, "dh#set_key= is incompatible with OpenSSL 3.0")
    end
  end
end
