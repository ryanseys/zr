# frozen_string_literal: true

# Derived from the C half of ruby's openssl gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ossl_pkey_dsa.c: OpenSSL::PKey::DSA.
module OpenSSL
  Lib.attach_all(
    EVP_PKEY_get0_DSA: [%i[pointer], :pointer],
    DSA_free: [%i[pointer], :void],
    DSA_get0_pqg: [%i[pointer buffer buffer buffer], :void],
    DSA_get0_key: [%i[pointer buffer buffer], :void],
    PEM_ASN1_read_bio: [%i[pointer string pointer pointer pointer pointer], :pointer]
  )

  module Lib
    PEM_STRING_DSA_PUBLIC = "DSA PUBLIC KEY" # pem.h
  end

  module Ossl
    def self.dsa(object) = legacy_key(object, Lib::EVP_PKEY_DSA, "DSA", :EVP_PKEY_get0_DSA)
  end

  module PKey
    class DSA < PKey
      def initialize(*args, &block)
        Ossl.want_uninitialized(self, Ossl::PKEY)
        raise ArgumentError, wrong_arity(args.size, 0..2) if args.size > 2
        raise ArgumentError, "OpenSSL::PKey::DSA.new cannot be called without arguments; pkeys are immutable with OpenSSL 3.0" if args.empty?

        arg, pass = args
        pass = Ossl.pem_password_value(pass)
        arg = Ossl.to_der_if_possible(arg)
        bio, _arg = Ossl.obj2bio(arg)
        dsa = Lib.PEM_ASN1_read_bio(Lib.function_address(:d2i_DSAPublicKey), Lib::PEM_STRING_DSA_PUBLIC, bio, nil, nil, nil)
        unless dsa.zero?
          Lib.BIO_free(bio)
          Ossl.assign_legacy(self, Lib::EVP_PKEY_DSA, dsa, :DSA_free, "EVP_PKEY_assign_DSA")
          return self
        end
        Ossl.bio_reset(bio)
        Ossl.with_password(pass, block) { |id| Ossl.read_typed_pkey(self, bio, id, Lib::EVP_PKEY_DSA, "Neither PUB key nor PRIV key") }
        self
      end

      def public? = !Ossl.get0(:DSA_get0_key, Ossl.dsa(self), 2)[0].zero?

      def private?
        dsa = Ossl.dsa(self)
        !Ossl.get0(:DSA_get0_key, dsa, 2)[1].zero? || Native.hidden_get(self, :private) == true
      end

      def export(*args)
        raise ArgumentError, wrong_arity(args.size, 0..2) if args.size > 2

        if Ossl.get0(:DSA_get0_key, Ossl.dsa(self), 2)[1].zero?
          Ossl.pkey_export_spki(self, false)
        else
          Ossl.pkey_export_traditional(self, false, *args)
        end
      end
      alias to_pem export
      alias to_s export

      def to_der
        if Ossl.get0(:DSA_get0_key, Ossl.dsa(self), 2)[1].zero?
          Ossl.pkey_export_spki(self, true)
        else
          Ossl.pkey_export_traditional(self, true)
        end
      end

      def p = Ossl.bn_or_nil(Ossl.get0(:DSA_get0_pqg, Ossl.dsa(self), 3)[0])

      def q = Ossl.bn_or_nil(Ossl.get0(:DSA_get0_pqg, Ossl.dsa(self), 3)[1])

      def g = Ossl.bn_or_nil(Ossl.get0(:DSA_get0_pqg, Ossl.dsa(self), 3)[2])

      def pub_key = Ossl.bn_or_nil(Ossl.get0(:DSA_get0_key, Ossl.dsa(self), 2)[0])

      def priv_key = Ossl.bn_or_nil(Ossl.get0(:DSA_get0_key, Ossl.dsa(self), 2)[1])

      def set_pqg(_p, _q, _g) = raise(PKeyError, "dsa#set_pqg= is incompatible with OpenSSL 3.0")

      def set_key(_pub_key, _priv_key) = raise(PKeyError, "dsa#set_key= is incompatible with OpenSSL 3.0")
    end
  end
end
