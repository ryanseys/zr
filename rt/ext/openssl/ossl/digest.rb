# frozen_string_literal: true

# ossl_digest.c: OpenSSL::Digest over EVP_MD_CTX.
module OpenSSL
  Lib.attach_all(
    EVP_MD_CTX_new: [[], :pointer],
    EVP_MD_CTX_free: [%i[pointer], :void],
    EVP_MD_CTX_copy: [%i[pointer pointer], :int],
    EVP_MD_CTX_get0_md: [%i[pointer], :pointer],
    EVP_MD_CTX_get_size_ex: [%i[pointer], :int],
    EVP_MD_get_size: [%i[pointer], :int],
    EVP_MD_get_block_size: [%i[pointer], :int],
    EVP_MD_get0_name: [%i[pointer], :string],
    EVP_MD_up_ref: [%i[pointer], :int],
    EVP_MD_free: [%i[pointer], :void],
    EVP_MD_fetch: [%i[pointer string string], :pointer],
    EVP_get_digestbyname: [%i[string], :pointer],
    EVP_DigestInit_ex: [%i[pointer pointer pointer], :int],
    EVP_DigestUpdate: [%i[pointer buffer size_t], :int],
    EVP_DigestFinal_ex: [%i[pointer buffer pointer], :int],
    OBJ_txt2obj: [%i[string int], :pointer],
    OBJ_obj2nid: [%i[pointer], :int],
    OBJ_nid2sn: [%i[int], :pointer],
    ASN1_OBJECT_free: [%i[pointer], :void]
  )

  module Lib
    OBJ_NAME_TYPE_MD_METH = 0x01 # objects.h

    # EVP_MD_CTX_size (evp.h): the output length, which an XOF's context
    # sets where the library knows how.
    def self.EVP_MD_CTX_size(ctx)
      respond_to?(:EVP_MD_CTX_get_size_ex) ? EVP_MD_CTX_get_size_ex(ctx) : EVP_MD_get_size(EVP_MD_CTX_get0_md(ctx))
    end

    # EVP_MD_CTX_block_size (evp.h).
    def self.EVP_MD_CTX_block_size(ctx) = EVP_MD_get_block_size(EVP_MD_CTX_get0_md(ctx))

    # EVP_get_digestbyobj (evp.h).
    def self.EVP_get_digestbyobj(oid) = EVP_get_digestbyname(OBJ_nid2sn(OBJ_obj2nid(oid)))
  end

  class Digest < ::Digest::Class
    class DigestError < OpenSSLError; end
  end

  module Ossl
    DIGEST = DataType.new("OpenSSL/Digest", Digest, :EVP_MD_CTX_free, [RuntimeError, "Digest CTX wasn't initialized!"])

    class << self
      # ossl_evp_md_fetch: the EVP_MD `object` names (a Digest, or an
      # algorithm's name or OID), and the handle that keeps a fetched one
      # alive while the caller uses it.
      def fetch_md(object)
        if object.is_a?(Digest)
          md = Lib.EVP_MD_CTX_get0_md(DIGEST.fetch(object))
          raise error(Digest::DigestError, "EVP_MD_up_ref") if Lib.EVP_MD_up_ref(md) != 1

          return [md, Handle.new(md, :EVP_MD_free)]
        end

        name = cstring_value(object)
        md = Lib.EVP_get_digestbyname(name)
        if md.zero?
          oid = Lib.OBJ_txt2obj(name, 0)
          md = Lib.EVP_get_digestbyobj(oid)
          Lib.ASN1_OBJECT_free(oid)
        end
        holder = nil
        if md.zero?
          clear_error
          md = Lib.EVP_MD_fetch(nil, name, nil)
          holder = Handle.new(md, :EVP_MD_free) unless md.zero?
        end
        raise error(Digest::DigestError, "unsupported digest algorithm: #{object}") if md.zero?

        [md, holder]
      end
    end
  end

  class Digest
    def self.digests = Ossl.names(Lib::OBJ_NAME_TYPE_MD_METH)

    private def digests = Digest.digests

    def initialize(type, data = nil)
      md, holder = Ossl.fetch_md(type)
      data = Ossl.string_value(data) unless data.nil?
      ctx = Ossl::DIGEST.get(self) || Ossl::DIGEST.set(self, Lib.EVP_MD_CTX_new)
      raise Ossl.error(DigestError, "EVP_MD_CTX_new") if ctx.zero?
      raise Ossl.error(DigestError, "Digest initialization failed") if Lib.EVP_DigestInit_ex(ctx, md, nil) != 1

      Native.hidden_set(self, :md_holder, holder)
      data.nil? ? self : update(data)
    end

    def initialize_copy(other)
      Ossl.check_frozen(self)
      return self if equal?(other)

      Ossl::DIGEST.unshare(self, other)
      ctx = Ossl::DIGEST.get(self) || Ossl::DIGEST.set(self, Lib.EVP_MD_CTX_new)
      raise Ossl.error(DigestError, "EVP_MD_CTX_new") if ctx.zero?
      raise Ossl.error(DigestError) if Lib.EVP_MD_CTX_copy(ctx, Ossl::DIGEST.fetch(other)) != 1

      self
    end

    def reset
      ctx = Ossl::DIGEST.fetch(self)
      raise Ossl.error(DigestError, "Digest initialization failed.") if Lib.EVP_DigestInit_ex(ctx, Lib.EVP_MD_CTX_get0_md(ctx), nil) != 1

      self
    end

    def update(data)
      data = Ossl.string_value(data)
      raise Ossl.error(DigestError, "EVP_DigestUpdate") if Lib.EVP_DigestUpdate(Ossl::DIGEST.fetch(self), data, data.bytesize) != 1

      self
    end
    alias << update

    def digest_length = Lib.EVP_MD_CTX_size(Ossl::DIGEST.fetch(self))

    def block_length = Lib.EVP_MD_CTX_block_size(Ossl::DIGEST.fetch(self))

    def name = Lib.EVP_MD_get0_name(Lib.EVP_MD_CTX_get0_md(Ossl::DIGEST.fetch(self)))

    private

    def finish
      ctx = Ossl::DIGEST.fetch(self)
      out = Lib.buffer(Lib.EVP_MD_CTX_size(ctx))
      raise Ossl.error(DigestError, "EVP_DigestFinal_ex") if Lib.EVP_DigestFinal_ex(ctx, out, nil) != 1

      out
    end
  end
end
