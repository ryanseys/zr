# frozen_string_literal: true

# Derived from the C half of ruby's openssl gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ossl_kdf.c: OpenSSL::KDF, PBKDF2, scrypt and HKDF.
module OpenSSL
  Lib.attach_all(
    PKCS5_PBKDF2_HMAC: [%i[buffer int buffer int int pointer int buffer], :int],
    EVP_PBE_scrypt: [%i[buffer size_t buffer size_t uint64 uint64 uint64 uint64 buffer size_t], :int],
    EVP_PKEY_CTX_new_id: [%i[int pointer], :pointer],
    EVP_PKEY_CTX_free: [%i[pointer], :void],
    EVP_PKEY_derive_init: [%i[pointer], :int],
    EVP_PKEY_derive: [%i[pointer buffer buffer], :int],
    EVP_PKEY_CTX_set_hkdf_md: [%i[pointer pointer], :int],
    EVP_PKEY_CTX_set1_hkdf_salt: [%i[pointer buffer int], :int],
    EVP_PKEY_CTX_set1_hkdf_key: [%i[pointer buffer int], :int],
    EVP_PKEY_CTX_add1_hkdf_info: [%i[pointer buffer int], :int]
  )

  module Lib
    EVP_PKEY_HKDF = 1036 # evp.h: NID_hkdf
  end

  module KDF
    class KDFError < OpenSSLError; end

    module_function

    def pbkdf2_hmac(pass, salt:, iterations:, length:, hash:)
      pass = Ossl.string_value(pass)
      salt = Ossl.string_value(salt)
      iterations = Ossl.int(iterations)
      length = Ossl.int(length)
      md, _holder = Ossl.fetch_md(hash)
      out = Lib.buffer(length)
      raise Ossl.error(KDFError, "PKCS5_PBKDF2_HMAC") if Lib.PKCS5_PBKDF2_HMAC(pass, pass.bytesize, salt, salt.bytesize, iterations, md, length, out).zero?

      out
    end

    # scrypt's cost keyword is a capital N, which no Ruby parameter can be.
    def scrypt(pass, **options)
      salt, n, r, p, length = Ossl.keywords(options, :salt, :N, :r, :p, :length)
      pass = Ossl.string_value(pass)
      salt = Ossl.string_value(salt)
      n = Ossl.uint64(n)
      r = Ossl.uint64(r)
      p = Ossl.uint64(p)
      length = Ossl.long(length)
      # rb_str_new refuses a negative size before OpenSSL sees it.
      raise ArgumentError, "negative string size (or size too big)" if length.negative?

      out = Lib.buffer(length)
      # OpenSSL's default of 32 MB, for a zero, is too small: the other
      # parameters bound the memory, and malloc inside OpenSSL fails past it.
      maxmem = Lib::WORD_MASK
      raise Ossl.error(KDFError, "EVP_PBE_scrypt") if Lib.EVP_PBE_scrypt(pass, pass.bytesize, salt, salt.bytesize, n, r, p, maxmem, out, length).zero?

      out
    end

    def hkdf(ikm, salt:, info:, length:, hash:)
      ikm = Ossl.string_value(ikm)
      salt = Ossl.string_value(salt)
      info = Ossl.string_value(info)
      length = Ossl.long(length)
      raise ArgumentError, "length must be non-negative" if length.negative?

      md, _holder = Ossl.fetch_md(hash)
      out = Lib.buffer(length)
      pctx = Lib.EVP_PKEY_CTX_new_id(Lib::EVP_PKEY_HKDF, nil)
      raise Ossl.error(KDFError, "EVP_PKEY_CTX_new_id") if pctx.zero?

      begin
        raise Ossl.error(KDFError, "EVP_PKEY_derive_init") if Lib.EVP_PKEY_derive_init(pctx) <= 0
        raise Ossl.error(KDFError, "EVP_PKEY_CTX_set_hkdf_md") if Lib.EVP_PKEY_CTX_set_hkdf_md(pctx, md) <= 0
        raise Ossl.error(KDFError, "EVP_PKEY_CTX_set_hkdf_salt") if Lib.EVP_PKEY_CTX_set1_hkdf_salt(pctx, salt, salt.bytesize) <= 0
        raise Ossl.error(KDFError, "EVP_PKEY_CTX_set_hkdf_key") if Lib.EVP_PKEY_CTX_set1_hkdf_key(pctx, ikm, ikm.bytesize) <= 0
        raise Ossl.error(KDFError, "EVP_PKEY_CTX_set_hkdf_info") if Lib.EVP_PKEY_CTX_add1_hkdf_info(pctx, info, info.bytesize) <= 0

        size = [length].pack("J")
        raise Ossl.error(KDFError, "EVP_PKEY_derive") if Lib.EVP_PKEY_derive(pctx, out, size) <= 0
      ensure
        Lib.EVP_PKEY_CTX_free(pctx)
      end
      out.byteslice(0, size.unpack1("J"))
    end
  end
end
