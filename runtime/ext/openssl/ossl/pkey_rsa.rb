# frozen_string_literal: true

# ossl_pkey_rsa.c: OpenSSL::PKey::RSA.
module OpenSSL
  Lib.attach_all(
    EVP_PKEY_assign: [%i[pointer int pointer], :int],
    EVP_PKEY_get0_RSA: [%i[pointer], :pointer],
    RSA_free: [%i[pointer], :void],
    RSA_get0_key: [%i[pointer buffer buffer buffer], :void],
    RSA_get0_factors: [%i[pointer buffer buffer], :void],
    RSA_get0_crt_params: [%i[pointer buffer buffer buffer], :void],
    d2i_RSAPublicKey_bio: [%i[pointer pointer], :pointer],
    PEM_read_bio_RSAPublicKey: [%i[pointer pointer pointer pointer], :pointer],
    EVP_PKEY_CTX_set_rsa_padding: [%i[pointer int], :int],
    EVP_PKEY_CTX_set_rsa_pss_saltlen: [%i[pointer int], :int],
    EVP_PKEY_CTX_set_rsa_mgf1_md: [%i[pointer pointer], :int],
    EVP_DigestVerifyUpdate: [%i[pointer buffer size_t], :int],
    EVP_DigestVerifyFinal: [%i[pointer buffer size_t], :int]
  )

  module Lib
    RSA_PKCS1_PSS_PADDING = 6 # rsa.h
  end

  module Ossl
    class << self
      # The addresses a get0 function writes into its out-parameters,
      # the key's struct first.
      def get0(function, object, count)
        outs = Array.new(count) { Lib.buffer(8) }
        Lib.public_send(function, object, *outs)
        outs.map { |out| Lib.pointer_at(out) }
      end

      # OSSL_PKEY_BN_DEF_GETTER0's answer: a BN copying `bn`, or nil.
      def bn_or_nil(bn) = bn.zero? ? nil : bn_new(bn)

      # The EVP_PKEY of `object` when its type is `type`, as the Get
      # macros of each key type check it; `name` names the type.
      def typed_pkey(object, type, name)
        pkey = PKEY.fetch(object)
        raise error(RuntimeError, "THIS IS NOT A #{name}!") if Lib.EVP_PKEY_get_base_id(pkey) != type

        pkey
      end

      # The legacy key struct a key type's Get macro takes from the
      # EVP_PKEY with `get0`.
      def legacy_key(object, type, name, get0)
        key = Lib.public_send(get0, typed_pkey(object, type, name))
        raise error(PKey::PKeyError, "failed to get #{name} from EVP_PKEY") if key.zero?

        key
      end

      def rsa(object) = legacy_key(object, Lib::EVP_PKEY_RSA, "RSA", :EVP_PKEY_get0_RSA)

      # The `legacy:` label of each key type's initialize: `key` assigned
      # to a new EVP_PKEY that `object` owns.
      def assign_legacy(object, type, key, free, name)
        pkey = Lib.EVP_PKEY_new
        if pkey.zero? || Lib.EVP_PKEY_assign(pkey, type, key) != 1
          Lib.EVP_PKEY_free(pkey) unless pkey.zero?
          Lib.public_send(free, key)
          raise error(PKey::PKeyError, name)
        end
        PKEY.set(object, pkey)
      end

      # The generic read of a key type's initialize: `bio` decoded as any
      # key, which must be of `type`.
      def read_typed_pkey(object, bio, password, type, message)
        pkey = pkey_read_generic(bio, password)
        Lib.BIO_free(bio)
        raise error(PKey::PKeyError, message) if pkey.nil?

        found = Lib.EVP_PKEY_get_base_id(pkey)
        if found != type
          Lib.EVP_PKEY_free(pkey)
          raise PKey::PKeyError, "incorrect pkey type: #{Lib.string(Lib.OBJ_nid2sn(found))}"
        end
        PKEY.set(object, pkey)
      end

      # can_export_rsaprivatekey: whether every part of an RSA private key
      # is there to write.
      def rsa_private_exportable?(object)
        rsa = rsa(object)
        parts = get0(:RSA_get0_key, rsa, 3) + get0(:RSA_get0_factors, rsa, 2) + get0(:RSA_get0_crt_params, rsa, 3)
        parts.none?(&:zero?)
      end

      # A salt length of sign_pss and verify_pss: `named` maps the
      # symbols it takes, anything else is an int.
      def pss_salt_length(value, named)
        named.fetch(value) { int(value) }
      end
    end
  end

  module PKey
    class RSA < PKey
      def initialize(*args, &block)
        raise TypeError, "pkey already initialized" if Ossl::PKEY.get(self)
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2
        raise ArgumentError, "OpenSSL::PKey::RSA.new cannot be called without arguments; pkeys are immutable with OpenSSL 3.0" if args.empty?

        arg, pass = args
        pass = Ossl.pem_password_value(pass)
        arg = Ossl.to_der_if_possible(arg)
        bio, _arg = Ossl.obj2bio(arg)
        rsa = Lib.d2i_RSAPublicKey_bio(bio, nil)
        if rsa.zero?
          Ossl.bio_reset(bio)
          rsa = Lib.PEM_read_bio_RSAPublicKey(bio, nil, nil, nil)
        end
        unless rsa.zero?
          Lib.BIO_free(bio)
          Ossl.assign_legacy(self, Lib::EVP_PKEY_RSA, rsa, :RSA_free, "EVP_PKEY_assign_RSA")
          return self
        end
        Ossl.bio_reset(bio)
        Ossl.with_password(pass, block) { |id| Ossl.read_typed_pkey(self, bio, id, Lib::EVP_PKEY_RSA, "Neither PUB key nor PRIV key") }
        self
      end

      def public?
        Ossl.rsa(self)
        true
      end

      def private?
        rsa = Ossl.rsa(self)
        _, e, d = Ossl.get0(:RSA_get0_key, rsa, 3)
        (!e.zero? && !d.zero?) || Native.hidden_get(self, :private) == true
      end

      def export(*args)
        if Ossl.rsa_private_exportable?(self)
          raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

          Ossl.pkey_export_traditional(self, false, *args)
        else
          Ossl.pkey_export_spki(self, false)
        end
      end
      alias to_pem export
      alias to_s export

      def to_der = Ossl.rsa_private_exportable?(self) ? Ossl.pkey_export_traditional(self, true) : Ossl.pkey_export_spki(self, true)

      def sign_pss(digest, data, salt_length:, mgf1_hash:)
        salt_length = Ossl.pss_salt_length(salt_length, max: -2, digest: -1)
        mgf1md, _mgf1_holder = Ossl.fetch_md(mgf1_hash)
        pkey = Ossl.private_pkey(self)
        size = Lib.EVP_PKEY_get_size(pkey)
        md, _holder = Ossl.fetch_md(digest)
        data = Ossl.string_value(data)
        signature = Lib.buffer(size)
        length = [size].pack("J")
        ctx = Lib.EVP_MD_CTX_new
        begin
          pctx = Lib.buffer(8)
          ok = !ctx.zero? &&
               Lib.EVP_DigestSignInit(ctx, pctx, md, nil, pkey) == 1 &&
               Lib.EVP_PKEY_CTX_set_rsa_padding(Lib.pointer_at(pctx), Lib::RSA_PKCS1_PSS_PADDING) == 1 &&
               Lib.EVP_PKEY_CTX_set_rsa_pss_saltlen(Lib.pointer_at(pctx), salt_length) == 1 &&
               Lib.EVP_PKEY_CTX_set_rsa_mgf1_md(Lib.pointer_at(pctx), mgf1md) == 1 &&
               Lib.EVP_DigestSignUpdate(ctx, data, data.bytesize) == 1 &&
               Lib.EVP_DigestSignFinal(ctx, signature, length) == 1
          raise Ossl.error(PKeyError) unless ok
        ensure
          Lib.EVP_MD_CTX_free(ctx)
        end
        signature.byteslice(0, length.unpack1("J"))
      end

      def verify_pss(digest, signature, data, salt_length:, mgf1_hash:)
        salt_length = Ossl.pss_salt_length(salt_length, auto: -2, digest: -1)
        mgf1md, _mgf1_holder = Ossl.fetch_md(mgf1_hash)
        pkey = Ossl.pkey(self)
        md, _holder = Ossl.fetch_md(digest)
        signature = Ossl.string_value(signature)
        data = Ossl.string_value(data)
        ctx = Lib.EVP_MD_CTX_new
        begin
          pctx = Lib.buffer(8)
          ok = !ctx.zero? &&
               Lib.EVP_DigestVerifyInit(ctx, pctx, md, nil, pkey) == 1 &&
               Lib.EVP_PKEY_CTX_set_rsa_padding(Lib.pointer_at(pctx), Lib::RSA_PKCS1_PSS_PADDING) == 1 &&
               Lib.EVP_PKEY_CTX_set_rsa_pss_saltlen(Lib.pointer_at(pctx), salt_length) == 1 &&
               Lib.EVP_PKEY_CTX_set_rsa_mgf1_md(Lib.pointer_at(pctx), mgf1md) == 1 &&
               Lib.EVP_DigestVerifyUpdate(ctx, data, data.bytesize) == 1
          raise Ossl.error(PKeyError) unless ok

          result = Lib.EVP_DigestVerifyFinal(ctx, signature, signature.bytesize)
        ensure
          Lib.EVP_MD_CTX_free(ctx)
        end
        case result
        when 0
          Ossl.clear_error
          false
        when 1 then true
        else raise Ossl.error(PKeyError, "EVP_DigestVerifyFinal")
        end
      end

      def n = Ossl.bn_or_nil(Ossl.get0(:RSA_get0_key, Ossl.rsa(self), 3)[0])

      def e = Ossl.bn_or_nil(Ossl.get0(:RSA_get0_key, Ossl.rsa(self), 3)[1])

      def d = Ossl.bn_or_nil(Ossl.get0(:RSA_get0_key, Ossl.rsa(self), 3)[2])

      def p = Ossl.bn_or_nil(Ossl.get0(:RSA_get0_factors, Ossl.rsa(self), 2)[0])

      def q = Ossl.bn_or_nil(Ossl.get0(:RSA_get0_factors, Ossl.rsa(self), 2)[1])

      def dmp1 = Ossl.bn_or_nil(Ossl.get0(:RSA_get0_crt_params, Ossl.rsa(self), 3)[0])

      def dmq1 = Ossl.bn_or_nil(Ossl.get0(:RSA_get0_crt_params, Ossl.rsa(self), 3)[1])

      def iqmp = Ossl.bn_or_nil(Ossl.get0(:RSA_get0_crt_params, Ossl.rsa(self), 3)[2])

      def set_key(_n, _e, _d) = raise(PKeyError, "rsa#set_key= is incompatible with OpenSSL 3.0")

      def set_factors(_p, _q) = raise(PKeyError, "rsa#set_factors= is incompatible with OpenSSL 3.0")

      def set_crt_params(_dmp1, _dmq1, _iqmp) = raise(PKeyError, "rsa#set_crt_params= is incompatible with OpenSSL 3.0")
    end
  end
end
