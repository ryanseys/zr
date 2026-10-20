# frozen_string_literal: true

# Derived from the C half of ruby's openssl gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ossl_hmac.c: OpenSSL::HMAC over an EVP_MD_CTX signing with an HMAC key.
module OpenSSL
  Lib.attach_all(
    EVP_PKEY_new_raw_private_key: [%i[int pointer buffer size_t], :pointer],
    EVP_PKEY_free: [%i[pointer], :void],
    EVP_DigestSignInit: [%i[pointer pointer pointer pointer pointer], :int],
    EVP_DigestSignUpdate: [%i[pointer buffer size_t], :int],
    EVP_DigestSignFinal: [%i[pointer buffer buffer], :int],
    EVP_MD_CTX_get_pkey_ctx: [%i[pointer], :pointer],
    EVP_PKEY_CTX_get0_pkey: [%i[pointer], :pointer]
  )

  module Lib
    EVP_PKEY_HMAC = 855 # evp.h: NID_hmac
    EVP_MAX_MD_SIZE = 64 # evp.h
  end

  class HMACError < OpenSSLError; end

  class HMAC; end

  module Ossl
    HMAC_CTX = DataType.new("OpenSSL/HMAC", OpenSSL::HMAC, :EVP_MD_CTX_free, [RuntimeError, "HMAC wasn't initialized"], alloc: lambda {
      Lib.EVP_MD_CTX_new.tap { |ctx| raise Ossl.error(HMACError, "EVP_MD_CTX") if ctx.zero? }
    })

    # GetHMAC.
    def self.hmac_ctx(hmac) = HMAC_CTX.fetch(hmac)
  end

  class HMAC
    def initialize(key, digest)
      ctx = Ossl.hmac_ctx(self)
      key = Ossl.string_value(key)
      md, holder = Ossl.fetch_md(digest)
      pkey = Lib.EVP_PKEY_new_raw_private_key(Lib::EVP_PKEY_HMAC, nil, key, key.bytesize)
      raise Ossl.error(HMACError, "EVP_PKEY_new_raw_private_key") if pkey.zero?

      begin
        raise Ossl.error(HMACError, "EVP_DigestSignInit") if Lib.EVP_DigestSignInit(ctx, nil, md, nil, pkey) != 1
      ensure
        # The context keeps its own reference.
        Lib.EVP_PKEY_free(pkey)
      end
      Native.hidden_set(self, :md_holder, holder)
      self
    end

    def initialize_copy(other)
      Ossl.check_frozen(self)
      return self if equal?(other)

      Ossl::HMAC_CTX.unshare(self, other)
      raise Ossl.error(HMACError, "EVP_MD_CTX_copy") if Lib.EVP_MD_CTX_copy(Ossl.hmac_ctx(self), Ossl.hmac_ctx(other)) != 1

      self
    end

    def reset
      ctx = Ossl.hmac_ctx(self)
      pkey = Lib.EVP_PKEY_CTX_get0_pkey(Lib.EVP_MD_CTX_get_pkey_ctx(ctx))
      raise Ossl.error(HMACError, "EVP_DigestSignInit") if Lib.EVP_DigestSignInit(ctx, nil, Lib.EVP_MD_CTX_get0_md(ctx), nil, pkey) != 1

      self
    end

    def update(data)
      data = Ossl.string_value(data)
      raise Ossl.error(HMACError, "EVP_DigestSignUpdate") if Lib.EVP_DigestSignUpdate(Ossl.hmac_ctx(self), data, data.bytesize) != 1

      self
    end
    alias << update

    def digest
      out = Lib.buffer(Lib::EVP_MAX_MD_SIZE)
      length = [Lib::EVP_MAX_MD_SIZE].pack("J")
      raise Ossl.error(HMACError, "EVP_DigestSignFinal") if Lib.EVP_DigestSignFinal(Ossl.hmac_ctx(self), out, length) != 1

      out.byteslice(0, length.unpack1("J"))
    end

    def hexdigest = digest.unpack1("H*").force_encoding(Encoding::BINARY)
    alias inspect hexdigest
    alias to_s hexdigest
  end
end
