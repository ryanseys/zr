# frozen_string_literal: true

# ossl_pkcs7.c: OpenSSL::PKCS7 over PKCS7, and its SignerInfo and
# RecipientInfo.
module OpenSSL
  Lib.attach_all(
    PKCS7_new: [[], :pointer],
    PKCS7_free: [%i[pointer], :void],
    PKCS7_dup: [%i[pointer], :pointer],
    PKCS7_SIGNER_INFO_new: [[], :pointer],
    PKCS7_SIGNER_INFO_free: [%i[pointer], :void],
    PKCS7_RECIP_INFO_new: [[], :pointer],
    PKCS7_RECIP_INFO_free: [%i[pointer], :void],
    SMIME_read_PKCS7: [%i[pointer buffer], :pointer],
    SMIME_write_PKCS7: [%i[pointer pointer pointer int], :int],
    PKCS7_sign: [%i[pointer pointer pointer pointer int], :pointer],
    PKCS7_encrypt: [%i[pointer pointer pointer int], :pointer],
    d2i_PKCS7_bio: [%i[pointer pointer], :pointer],
    PEM_read_bio_PKCS7: [%i[pointer pointer pointer pointer], :pointer],
    PEM_write_bio_PKCS7: [%i[pointer pointer], :int],
    i2d_PKCS7: [%i[pointer buffer], :int],
    PKCS7_print_ctx: [%i[pointer pointer int pointer], :int],
    PKCS7_set_type: [%i[pointer int], :int],
    PKCS7_ctrl: [%i[pointer int long pointer], :long],
    PKCS7_set_cipher: [%i[pointer pointer], :int],
    PKCS7_add_signer: [%i[pointer pointer], :int],
    PKCS7_get_signer_info: [%i[pointer], :pointer],
    PKCS7_add_recipient_info: [%i[pointer pointer], :int],
    PKCS7_add_certificate: [%i[pointer pointer], :int],
    PKCS7_add_crl: [%i[pointer pointer], :int],
    PKCS7_verify: [%i[pointer pointer pointer pointer pointer int], :int],
    PKCS7_decrypt: [%i[pointer pointer pointer pointer int], :int],
    PKCS7_content_new: [%i[pointer int], :int],
    PKCS7_dataInit: [%i[pointer pointer], :pointer],
    PKCS7_dataFinal: [%i[pointer pointer], :int],
    PKCS7_SIGNER_INFO_set: [%i[pointer pointer pointer pointer], :int],
    PKCS7_get_signed_attribute: [%i[pointer int], :pointer],
    PKCS7_RECIP_INFO_set: [%i[pointer pointer], :int],
    BIO_free_all: [%i[pointer], :void],
    ERR_peek_error: [[], :ulong]
  )

  module Lib
    NID_pkcs7_data = 21 # obj_mac.h
    NID_pkcs7_signed = 22
    NID_pkcs7_enveloped = 23
    NID_pkcs7_signedAndEnveloped = 24
    NID_pkcs7_digest = 25
    NID_pkcs7_encrypted = 26
    NID_pkcs9_signingTime = 52
    PKCS7_OP_SET_DETACHED_SIGNATURE = 1 # pkcs7.h
    PKCS7_OP_GET_DETACHED_SIGNATURE = 2
    BIO_CTRL_FLUSH = 11 # bio.h

    # struct pkcs7_st (pkcs7.h): unsigned char *asn1, long length,
    # int state, int detached, ASN1_OBJECT *type, then the union d.
    PKCS7_TYPE = 24
    PKCS7_D = 32
    # PKCS7_SIGNED and PKCS7_SIGN_ENVELOPE: version, md_algs, cert, crl,
    # signer_info; the latter then enc_data, recipientinfo.
    PKCS7_SIGNED_CERT = 16
    PKCS7_SIGNED_CRL = 24
    PKCS7_SIGN_ENVELOPE_RECIPIENTINFO = 48
    # PKCS7_ENVELOPE: version, recipientinfo, enc_data.
    PKCS7_ENVELOPE_RECIPIENTINFO = 8
    # PKCS7_SIGNER_INFO: version, issuer_and_serial, digest_alg, auth_attr,
    # digest_enc_alg, enc_digest, unauth_attr, pkey.
    PKCS7_SIGNER_INFO_ISSUER_AND_SERIAL = 8
    PKCS7_SIGNER_INFO_PKEY = 56
    # PKCS7_RECIP_INFO: version, issuer_and_serial, key_enc_algor,
    # enc_key, cert.
    PKCS7_RECIP_INFO_ISSUER_AND_SERIAL = 8
    PKCS7_RECIP_INFO_ENC_KEY = 24
    PKCS7_RECIP_INFO_CERT = 32

    # PKCS7_type_is_* (pkcs7.h).
    def self.PKCS7_type(p7) = OBJ_obj2nid(read_pointer(p7 + PKCS7_TYPE))

    # PKCS7_get_detached and PKCS7_set_detached (pkcs7.h).
    def self.PKCS7_get_detached(p7) = PKCS7_ctrl(p7, PKCS7_OP_GET_DETACHED_SIGNATURE, 0, nil)

    def self.PKCS7_set_detached(p7, value) = PKCS7_ctrl(p7, PKCS7_OP_SET_DETACHED_SIGNATURE, value, nil)

    # PKCS7_is_detached (pkcs7.h).
    def self.PKCS7_is_detached(p7) = PKCS7_type(p7) == NID_pkcs7_signed && !PKCS7_get_detached(p7).zero?

    # BIO_flush (bio.h).
    def self.BIO_flush(bio) = RETURNS[:int].(BIO_ctrl(bio, BIO_CTRL_FLUSH, 0, nil))
  end

  class PKCS7
    class PKCS7Error < OpenSSLError; end

    class SignerInfo; end

    class RecipientInfo; end

    Signer = SignerInfo
  end

  module Ossl
    PKCS7_STRUCT = DataType.new("OpenSSL/PKCS7", OpenSSL::PKCS7, :PKCS7_free, [RuntimeError, "PKCS7 wasn't initialized."], create: lambda {
      Lib.PKCS7_new.tap { |p7| raise Ossl.error(OpenSSL::PKCS7::PKCS7Error) if p7.zero? }
    })
    PKCS7_SIGNER = DataType.new("OpenSSL/PKCS7/SIGNER_INFO", OpenSSL::PKCS7::SignerInfo, :PKCS7_SIGNER_INFO_free,
                                [RuntimeError, "PKCS7si wasn't initialized."], create: lambda {
      Lib.PKCS7_SIGNER_INFO_new.tap { |si| raise Ossl.error(OpenSSL::PKCS7::PKCS7Error) if si.zero? }
    })
    PKCS7_RECIPIENT = DataType.new("OpenSSL/PKCS7/RECIP_INFO", OpenSSL::PKCS7::RecipientInfo, :PKCS7_RECIP_INFO_free,
                                   [RuntimeError, "PKCS7ri wasn't initialized."], create: lambda {
      Lib.PKCS7_RECIP_INFO_new.tap { |ri| raise Ossl.error(OpenSSL::PKCS7::PKCS7Error) if ri.zero? }
    })

    PKCS7_TYPES = {
      "signed" => Lib::NID_pkcs7_signed, "data" => Lib::NID_pkcs7_data,
      "signedAndEnveloped" => Lib::NID_pkcs7_signedAndEnveloped, "enveloped" => Lib::NID_pkcs7_enveloped,
      "encrypted" => Lib::NID_pkcs7_encrypted, "digest" => Lib::NID_pkcs7_digest
    }.freeze

    class << self
      def pkcs7(object) = PKCS7_STRUCT.fetch(object)

      # ossl_PKCS7_SIGNER_INFO_dup: a copy that shares the signing key.
      def pkcs7_signer_info_dup(si)
        copy = Lib.ASN1_dup(Lib.function_address(:i2d_PKCS7_SIGNER_INFO), Lib.function_address(:d2i_PKCS7_SIGNER_INFO), si)
        key = Lib.read_pointer(si + Lib::PKCS7_SIGNER_INFO_PKEY)
        if !copy.zero? && !key.zero?
          Lib.EVP_PKEY_up_ref(key)
          Lib.write(copy + Lib::PKCS7_SIGNER_INFO_PKEY, [key].pack("J"))
        end
        copy
      end

      # ossl_PKCS7_RECIP_INFO_dup: a copy that shares the certificate.
      def pkcs7_recip_info_dup(ri)
        copy = Lib.ASN1_dup(Lib.function_address(:i2d_PKCS7_RECIP_INFO), Lib.function_address(:d2i_PKCS7_RECIP_INFO), ri)
        cert = Lib.read_pointer(ri + Lib::PKCS7_RECIP_INFO_CERT)
        if !copy.zero? && !cert.zero?
          if Lib.X509_up_ref(cert).zero?
            Lib.PKCS7_RECIP_INFO_free(copy)
            return 0
          end
          Lib.write(copy + Lib::PKCS7_RECIP_INFO_CERT, [cert].pack("J"))
        end
        copy
      end

      # pkcs7_get_certs and pkcs7_get_crls: the stack at `offset` of a
      # signed or signed-and-enveloped PKCS7, or 0.
      def pkcs7_stack(object, offset)
        p7 = PKCS7_STRUCT.fetch(object)
        case Lib.PKCS7_type(p7)
        when Lib::NID_pkcs7_signed, Lib::NID_pkcs7_signedAndEnveloped
          Lib.read_pointer(Lib.read_pointer(p7 + Lib::PKCS7_D) + offset)
        else 0
        end
      end

      # The issuer and serial of a signer or recipient.
      def issuer_and_serial(info, offset) = Lib.read(Lib.read_pointer(info + offset), 16).unpack("JJ")

      # ossl_pkcs7_add_certificate.
      def pkcs7_add_certificate(object, cert)
        p7 = PKCS7_STRUCT.fetch(object)
        raise error(OpenSSL::PKCS7::PKCS7Error) if Lib.PKCS7_add_certificate(p7, x509(cert)).zero?

        object
      end

      # ossl_pkcs7_add_crl.
      def pkcs7_add_crl(object, crl)
        p7 = PKCS7_STRUCT.fetch(object)
        raise error(OpenSSL::PKCS7::PKCS7Error) if Lib.PKCS7_add_crl(p7, x509crl(crl)).zero?

        object
      end

      # ossl_protect_x509_ary2sk, freeing `bio` when the array is not one of
      # certificates.
      def certificate_stack(certificates, bio)
        return nil if certificates.nil?

        x509_ary2sk(certificates)
      rescue Exception
        Lib.BIO_free(bio) if bio
        raise
      end
    end
  end

  class PKCS7
    def data = @data

    def error_string = @error_string

    def error_string=(error_string)
      @error_string = error_string
    end

    def self.read_smime(arg)
      pkcs7 = Native.allocate(PKCS7)
      bio, _arg = Ossl.obj2bio(arg)
      out = Lib.buffer(8)
      p7 = Lib.SMIME_read_PKCS7(bio, out)
      Lib.BIO_free(bio)
      raise Ossl.error(PKCS7Error, "Could not parse the PKCS7") if p7.zero?

      if Lib.read_pointer(p7 + Lib::PKCS7_D).zero?
        Lib.PKCS7_free(p7)
        raise Ossl.error(PKCS7Error, "No content in PKCS7")
      end
      out = Lib.pointer_at(out)
      data = out.zero? ? nil : Ossl.membio2str(out)
      Ossl::PKCS7_STRUCT.set(pkcs7, p7)
      pkcs7.instance_variable_set(:@data, data)
      pkcs7.instance_variable_set(:@error_string, nil)
      pkcs7
    end

    def self.write_smime(pkcs7, data = nil, flags = nil)
      flags = Ossl.optional_int(flags)
      data = pkcs7.instance_variable_get(:@data) if data.nil?
      p7 = Ossl.pkcs7(pkcs7)
      flags |= DETACHED if !data.nil? && Lib.PKCS7_is_detached(p7)
      bio, _data = data.nil? ? [nil, nil] : Ossl.obj2bio(data)
      out = Lib.BIO_new(Lib.BIO_s_mem)
      if out.zero?
        Lib.BIO_free(bio) if bio
        raise Ossl.error(PKCS7Error)
      end
      if Lib.SMIME_write_PKCS7(out, p7, bio, flags).zero?
        Lib.BIO_free(out)
        Lib.BIO_free(bio) if bio
        raise Ossl.error(PKCS7Error)
      end
      Lib.BIO_free(bio) if bio
      Ossl.membio2str(out)
    end

    def self.sign(cert, key, data, certs = nil, flags = nil)
      x509 = Ossl.x509(cert)
      pkey = Ossl.private_pkey(key)
      flags = Ossl.optional_int(flags)
      pkcs7 = Native.allocate(PKCS7)
      bio, data = Ossl.obj2bio(data)
      stack = Ossl.certificate_stack(certs, bio)
      p7 = Lib.PKCS7_sign(x509, pkey, stack, bio, flags)
      if p7.zero?
        Lib.BIO_free(bio)
        Ossl.free_x509_stack(stack)
        raise Ossl.error(PKCS7Error)
      end
      Ossl::PKCS7_STRUCT.set(pkcs7, p7)
      pkcs7.instance_variable_set(:@data, data)
      pkcs7.instance_variable_set(:@error_string, nil)
      Lib.BIO_free(bio)
      Ossl.free_x509_stack(stack)
      pkcs7
    end

    def self.encrypt(certs, data, cipher = nil, flags = nil)
      raise ArgumentError, "cipher must be specified. Before version 3.3, the default cipher was RC2-40-CBC." if cipher.nil?

      evp_cipher, holder = Ossl.fetch_cipher(cipher)
      flags = Ossl.optional_int(flags)
      pkcs7 = Native.allocate(PKCS7)
      bio, data = Ossl.obj2bio(data)
      stack = Ossl.certificate_stack(certs, bio)
      p7 = Lib.PKCS7_encrypt(stack, bio, evp_cipher, flags)
      if p7.zero?
        Lib.BIO_free(bio)
        Ossl.free_x509_stack(stack)
        raise Ossl.error(PKCS7Error)
      end
      Lib.BIO_free(bio)
      Ossl::PKCS7_STRUCT.set(pkcs7, p7)
      pkcs7.instance_variable_set(:@data, data)
      Native.hidden_set(pkcs7, :cipher_holder, holder)
      Ossl.free_x509_stack(stack)
      pkcs7
    end

    def initialize_copy(other)
      Ossl::PKCS7_STRUCT.unshare(self, other) unless equal?(other)
      Ossl.want_uninitialized(self, Ossl::PKCS7_STRUCT)
      copy = Lib.PKCS7_dup(Ossl.pkcs7(other))
      raise Ossl.error(PKCS7Error, "PKCS7_dup") if copy.zero?

      Ossl::PKCS7_STRUCT.set(self, copy)
      self
    end

    def initialize(*args)
      raise ArgumentError, wrong_arity(args.size, 0..1) if args.size > 1

      Ossl.want_uninitialized(self, Ossl::PKCS7_STRUCT)
      return Ossl::PKCS7_STRUCT.create(self) if args.empty?

      bio, _arg = Ossl.obj2bio(Ossl.to_der_if_possible(args.first))
      p7 = Lib.d2i_PKCS7_bio(bio, nil)
      if p7.zero?
        Ossl.bio_reset(bio)
        p7 = Lib.PEM_read_bio_PKCS7(bio, nil, nil, nil)
      end
      Lib.BIO_free(bio)
      raise Ossl.error(PKCS7Error, "Could not parse the PKCS7") if p7.zero?

      if Lib.read_pointer(p7 + Lib::PKCS7_D).zero?
        Lib.PKCS7_free(p7)
        raise Ossl.error(PKCS7Error, "No content in PKCS7")
      end
      Ossl::PKCS7_STRUCT.set(self, p7)
      @data = nil
      @error_string = nil
      self
    end

    def type=(type)
      p7 = Ossl.pkcs7(self)
      name = type.is_a?(Symbol) ? type.to_s : Ossl.string_value(type)
      nid = Ossl::PKCS7_TYPES.fetch(name) { raise Ossl.error(PKCS7Error, "unknown type \"#{name}\"") }
      raise Ossl.error(PKCS7Error) if Lib.PKCS7_set_type(p7, nid).zero?

      type
    end

    def type
      case Lib.PKCS7_type(Ossl.pkcs7(self))
      when Lib::NID_pkcs7_signed then :signed
      when Lib::NID_pkcs7_encrypted then :encrypted
      when Lib::NID_pkcs7_enveloped then :enveloped
      when Lib::NID_pkcs7_signedAndEnveloped then :signedAndEnveloped
      when Lib::NID_pkcs7_data then :data
      end
    end

    def detached=(flag)
      p7 = Ossl.pkcs7(self)
      raise Ossl.error(PKCS7Error, "must specify a boolean") unless flag == true || flag == false
      raise Ossl.error(PKCS7Error) if Lib.PKCS7_set_detached(p7, flag ? 1 : 0).zero?

      flag
    end

    def detached
      p7 = Ossl.pkcs7(self)
      return false unless Lib.PKCS7_type(p7) == Lib::NID_pkcs7_signed

      !Lib.PKCS7_get_detached(p7).zero?
    end

    def detached? = Lib.PKCS7_is_detached(Ossl.pkcs7(self))

    def cipher=(cipher)
      p7 = Ossl.pkcs7(self)
      evp_cipher, holder = Ossl.fetch_cipher(cipher)
      raise Ossl.error(PKCS7Error, "PKCS7_set_cipher") if Lib.PKCS7_set_cipher(p7, evp_cipher).zero?

      Native.hidden_set(self, :cipher_holder, holder)
      cipher
    end

    def add_signer(signer)
      p7 = Ossl.pkcs7(self)
      copy = Ossl.pkcs7_signer_info_dup(Ossl::PKCS7_SIGNER.fetch(signer))
      raise Ossl.error(PKCS7Error, "PKCS7_SIGNER_INFO_dup") if copy.zero?

      if Lib.PKCS7_add_signer(p7, copy) != 1
        Lib.PKCS7_SIGNER_INFO_free(copy)
        raise Ossl.error(PKCS7Error, "PKCS7_add_signer")
      end
      self
    end

    def signers
      stack = Lib.PKCS7_get_signer_info(Ossl.pkcs7(self))
      Ossl.stack_items(stack).map do |si|
        copy = Ossl.pkcs7_signer_info_dup(si)
        raise Ossl.error(PKCS7Error, "ASN1_dup") if copy.zero?

        Ossl::PKCS7_SIGNER.wrap(SignerInfo, copy)
      end
    end

    def add_recipient(recipient)
      p7 = Ossl.pkcs7(self)
      copy = Ossl.pkcs7_recip_info_dup(Ossl::PKCS7_RECIPIENT.fetch(recipient))
      raise Ossl.error(PKCS7Error, "PKCS7_RECIP_INFO_dup") if copy.zero?

      if Lib.PKCS7_add_recipient_info(p7, copy) != 1
        Lib.PKCS7_RECIP_INFO_free(copy)
        raise Ossl.error(PKCS7Error, "PKCS7_add_recipient_info")
      end
      self
    end

    def recipients
      p7 = Ossl.pkcs7(self)
      offset = case Lib.PKCS7_type(p7)
               when Lib::NID_pkcs7_enveloped then Lib::PKCS7_ENVELOPE_RECIPIENTINFO
               when Lib::NID_pkcs7_signedAndEnveloped then Lib::PKCS7_SIGN_ENVELOPE_RECIPIENTINFO
               end
      stack = offset ? Lib.read_pointer(Lib.read_pointer(p7 + Lib::PKCS7_D) + offset) : 0
      Ossl.stack_items(stack).map do |ri|
        copy = Ossl.pkcs7_recip_info_dup(ri)
        raise Ossl.error(PKCS7Error, "ASN1_dup") if copy.zero?

        Ossl::PKCS7_RECIPIENT.wrap(RecipientInfo, copy)
      end
    end

    def add_certificate(cert) = Ossl.pkcs7_add_certificate(self, cert)

    def certificates=(certificates)
      stack = Ossl.pkcs7_stack(self, Lib::PKCS7_SIGNED_CERT)
      until stack.zero? || (cert = Lib.OPENSSL_sk_pop(stack)).zero?
        Lib.X509_free(cert)
      end
      certificates.each { |cert| Ossl.pkcs7_add_certificate(self, cert) }
      certificates
    end

    def certificates
      stack = Ossl.pkcs7_stack(self, Lib::PKCS7_SIGNED_CERT)
      stack.zero? ? nil : Ossl.x509_sk2ary(stack)
    end

    def add_crl(crl) = Ossl.pkcs7_add_crl(self, crl)

    def crls=(crls)
      stack = Ossl.pkcs7_stack(self, Lib::PKCS7_SIGNED_CRL)
      until stack.zero? || (crl = Lib.OPENSSL_sk_pop(stack)).zero?
        Lib.X509_CRL_free(crl)
      end
      crls.each { |crl| Ossl.pkcs7_add_crl(self, crl) }
      crls
    end

    def crls
      stack = Ossl.pkcs7_stack(self, Lib::PKCS7_SIGNED_CRL)
      stack.zero? ? nil : Ossl.stack_items(stack).map { |crl| Ossl.x509crl_new(crl) }
    end

    def add_data(data)
      p7 = Ossl.pkcs7(self)
      raise Ossl.error(PKCS7Error, "PKCS7_content_new") if Lib.PKCS7_type(p7) == Lib::NID_pkcs7_signed && Lib.PKCS7_content_new(p7, Lib::NID_pkcs7_data).zero?

      bio, data = Ossl.obj2bio(data)
      out = Lib.PKCS7_dataInit(p7, nil)
      if out.zero?
        Lib.BIO_free(bio)
        raise Ossl.error(PKCS7Error, "PKCS7_dataInit")
      end
      chunk = Lib.buffer(4096)
      until (length = Lib.BIO_read(bio, chunk, 4096)) <= 0
        next if Lib.BIO_write(out, chunk, length) == length

        Lib.BIO_free_all(out)
        Lib.BIO_free(bio)
        raise Ossl.error(PKCS7Error, "BIO_write")
      end
      if Lib.BIO_flush(out) <= 0
        Lib.BIO_free_all(out)
        Lib.BIO_free(bio)
        raise Ossl.error(PKCS7Error, "BIO_flush")
      end
      finished = Lib.PKCS7_dataFinal(p7, out)
      Lib.BIO_free_all(out)
      Lib.BIO_free(bio)
      raise Ossl.error(PKCS7Error, "PKCS7_dataFinal") if finished.zero?

      @data = nil
      data
    end
    alias data= add_data

    def verify(certs, store, indata = nil, flags = nil)
      p7 = Ossl.pkcs7(self)
      x509store = Ossl.x509store(store)
      flags = Ossl.optional_int(flags)
      indata = @data if indata.nil?
      bio, = indata.nil? ? [nil, nil] : Ossl.obj2bio(indata)
      stack = Ossl.certificate_stack(certs, bio)
      out = Lib.BIO_new(Lib.BIO_s_mem)
      if out.zero?
        Lib.BIO_free(bio) if bio
        Ossl.free_x509_stack(stack)
        raise Ossl.error(PKCS7Error)
      end
      ok = Lib.PKCS7_verify(p7, stack, x509store, bio, out, flags)
      Lib.BIO_free(bio) if bio
      Ossl.free_x509_stack(stack)
      @data = Ossl.membio2str(out)
      if ok != 1
        message = Lib.ERR_reason_error_string(Lib.ERR_peek_error)
        @error_string = message
        Ossl.clear_error
        return false
      end
      @error_string = nil
      true
    end

    def decrypt(pkey, cert = nil, flags = nil)
      key = Ossl.private_pkey(pkey)
      x509 = cert.nil? ? nil : Ossl.x509(cert)
      flags = Ossl.optional_int(flags)
      p7 = Ossl.pkcs7(self)
      out = Lib.BIO_new(Lib.BIO_s_mem)
      raise Ossl.error(PKCS7Error) if out.zero?

      if Lib.PKCS7_decrypt(p7, key, x509, out, flags).zero?
        Lib.BIO_free(out)
        raise Ossl.error(PKCS7Error)
      end
      Ossl.membio2str(out)
    end

    def to_pem
      p7 = Ossl.pkcs7(self)
      Ossl.bio_output(PKCS7Error) { |bio| Lib.PEM_write_bio_PKCS7(bio, p7) }
    end
    alias to_s to_pem

    def to_der = Ossl.i2d(:i2d_PKCS7, Ossl.pkcs7(self), PKCS7Error)

    def to_text
      p7 = Ossl.pkcs7(self)
      Ossl.bio_output(PKCS7Error) { |bio| Lib.PKCS7_print_ctx(bio, p7, 0, nil) }
    end

    class SignerInfo
      def initialize(cert, key, digest)
        Ossl.want_uninitialized(self, Ossl::PKCS7_SIGNER)
        pkey = Ossl.private_pkey(key)
        x509 = Ossl.x509(cert)
        md, holder = Ossl.fetch_md(digest)
        Ossl::PKCS7_SIGNER.create(self)
        si = Ossl::PKCS7_SIGNER.fetch(self)
        raise Ossl.error(PKCS7Error, "PKCS7_SIGNER_INFO_set") if Lib.PKCS7_SIGNER_INFO_set(si, x509, pkey, md) <= 0

        Native.hidden_set(self, :md_holder, holder)
        self
      end

      def issuer = Ossl.x509name_new(Ossl.issuer_and_serial(Ossl::PKCS7_SIGNER.fetch(self), Lib::PKCS7_SIGNER_INFO_ISSUER_AND_SERIAL)[0])

      def serial = Ossl.asn1integer_to_num(Ossl.issuer_and_serial(Ossl::PKCS7_SIGNER.fetch(self), Lib::PKCS7_SIGNER_INFO_ISSUER_AND_SERIAL)[1])

      def signed_time
        si = Ossl::PKCS7_SIGNER.fetch(self)
        type = Lib.PKCS7_get_signed_attribute(si, Lib::NID_pkcs9_signingTime)
        raise Ossl.error(PKCS7Error) if type.zero?

        # ASN1_TYPE: int type, then the value.
        return nil unless Lib.read_int(type) == Lib::V_ASN1_UTCTIME

        Ossl.asn1time_to_time(Lib.read_pointer(type + 8))
      end
    end

    class RecipientInfo
      def initialize(cert)
        Ossl.want_uninitialized(self, Ossl::PKCS7_RECIPIENT)
        x509 = Ossl.x509(cert)
        Ossl::PKCS7_RECIPIENT.create(self)
        ri = Ossl::PKCS7_RECIPIENT.fetch(self)
        raise Ossl.error(PKCS7Error) if Lib.PKCS7_RECIP_INFO_set(ri, x509) <= 0

        self
      end

      def issuer = Ossl.x509name_new(Ossl.issuer_and_serial(Ossl::PKCS7_RECIPIENT.fetch(self), Lib::PKCS7_RECIP_INFO_ISSUER_AND_SERIAL)[0])

      def serial = Ossl.asn1integer_to_num(Ossl.issuer_and_serial(Ossl::PKCS7_RECIPIENT.fetch(self), Lib::PKCS7_RECIP_INFO_ISSUER_AND_SERIAL)[1])

      def enc_key = Ossl.asn1str_to_str(Lib.read_pointer(Ossl::PKCS7_RECIPIENT.fetch(self) + Lib::PKCS7_RECIP_INFO_ENC_KEY))
    end
  end
end
