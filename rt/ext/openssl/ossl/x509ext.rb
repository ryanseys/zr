# frozen_string_literal: true

# ossl_x509ext.c: OpenSSL::X509::Extension over X509_EXTENSION, and
# ExtensionFactory over X509V3_CTX.
module OpenSSL
  Lib.attach_all(
    X509_EXTENSION_new: [[], :pointer],
    X509_EXTENSION_free: [%i[pointer], :void],
    X509_EXTENSION_dup: [%i[pointer], :pointer],
    d2i_X509_EXTENSION: [%i[buffer buffer long], :pointer],
    i2d_X509_EXTENSION: [%i[pointer buffer], :int],
    X509_EXTENSION_set_object: [%i[pointer pointer], :int],
    X509_EXTENSION_set_data: [%i[pointer pointer], :int],
    X509_EXTENSION_set_critical: [%i[pointer int], :int],
    X509_EXTENSION_get_object: [%i[pointer], :pointer],
    X509_EXTENSION_get_data: [%i[pointer], :pointer],
    X509_EXTENSION_get_critical: [%i[pointer], :int],
    X509V3_EXT_print: [%i[pointer pointer ulong int], :int],
    ASN1_STRING_print: [%i[pointer pointer], :int],
    ASN1_OCTET_STRING_new: [[], :pointer],
    ASN1_OCTET_STRING_set: [%i[pointer buffer int], :int],
    ASN1_OCTET_STRING_free: [%i[pointer], :void],
    X509V3_set_ctx: [%i[pointer pointer pointer pointer pointer int], :void],
    X509V3_set_nconf: [%i[pointer pointer], :void],
    X509V3_EXT_nconf: [%i[pointer pointer string string], :pointer],
    OBJ_ln2nid: [%i[string], :int],
    CRYPTO_malloc: [%i[size_t string int], :pointer]
  )

  module Lib
    # struct v3_ext_ctx (x509v3.h): int flags, then X509 *issuer_cert,
    # X509 *subject_cert, X509_REQ *subject_req, X509_CRL *crl,
    # X509V3_CONF_METHOD *db_meth, void *db, EVP_PKEY *issuer_pkey.
    X509V3_CTX_SIZE = 64
    X509V3_CTX_ISSUER_CERT = 8
    X509V3_CTX_SUBJECT_CERT = 16
    X509V3_CTX_SUBJECT_REQ = 24
    X509V3_CTX_CRL = 32
    X509V3_CTX_DB = 48

    # X509V3_set_ctx_nodb (x509v3.h): ctx->db = NULL.
    def self.X509V3_set_ctx_nodb(ctx) = Native.write(ctx + X509V3_CTX_DB, [0].pack("J"))
  end

  module X509
    class ExtensionError < OpenSSLError; end

    class ExtensionFactory; end

    class Extension; end
  end

  module Ossl
    X509_EXT = DataType.new("OpenSSL/X509/EXTENSION", X509::Extension, :X509_EXTENSION_free, [RuntimeError, "EXT wasn't initialized!"], alloc: lambda {
      Lib.X509_EXTENSION_new.tap { |ext| raise Ossl.error(X509::ExtensionError) if ext.zero? }
    })
    X509_EXT_FACTORY = DataType.new("OpenSSL/X509/EXTENSION/Factory", X509::ExtensionFactory, :OPENSSL_free, [RuntimeError, "CTX wasn't initialized!"], alloc: lambda {
      ctx = Lib.CRYPTO_malloc(Lib::X509V3_CTX_SIZE, "", 0)
      raise RuntimeError, "CTX wasn't allocated!" if ctx.zero?

      Lib.X509V3_set_ctx(ctx, nil, nil, nil, nil, 0)
      ctx
    })

    class << self
      # ossl_x509ext_new.
      def x509ext_new(ext)
        copy = Lib.X509_EXTENSION_dup(ext)
        raise error(X509::ExtensionError, "X509_EXTENSION_dup") if copy.zero?

        X509_EXT.wrap(X509::Extension, copy)
      end

      # The factory's context, and the certificate, request or CRL it
      # reads, which the factory keeps in an instance variable so the
      # struct stays alive while the context points at it.
      def x509ext_factory_set(factory, ivar, offset, object, pointer)
        ctx = X509_EXT_FACTORY.fetch(factory)
        factory.instance_variable_set(ivar, object)
        Lib.write(ctx + offset, [pointer].pack("J"))
        object
      end
    end
  end

  module X509
    class ExtensionFactory
      def issuer_certificate = @issuer_certificate
      def subject_certificate = @subject_certificate
      def subject_request = @subject_request
      def crl = @crl
      def config = @config

      def config=(config)
        @config = config
      end

      def initialize(issuer_cert = nil, subject_cert = nil, subject_req = nil, crl = nil)
        Ossl::X509_EXT_FACTORY.fetch(self)
        @config = nil unless instance_variable_defined?(:@config)
        self.issuer_certificate = issuer_cert unless issuer_cert.nil?
        self.subject_certificate = subject_cert unless subject_cert.nil?
        self.subject_request = subject_req unless subject_req.nil?
        self.crl = crl unless crl.nil?
        self
      end

      def issuer_certificate=(cert)
        Ossl.x509ext_factory_set(self, :@issuer_certificate, Lib::X509V3_CTX_ISSUER_CERT, cert, Ossl.x509(cert))
      end

      def subject_certificate=(cert)
        Ossl.x509ext_factory_set(self, :@subject_certificate, Lib::X509V3_CTX_SUBJECT_CERT, cert, Ossl.x509(cert))
      end

      def subject_request=(req)
        Ossl.x509ext_factory_set(self, :@subject_request, Lib::X509V3_CTX_SUBJECT_REQ, req, Ossl.x509req(req))
      end

      def crl=(crl)
        Ossl.x509ext_factory_set(self, :@crl, Lib::X509V3_CTX_CRL, crl, Ossl.x509crl(crl))
      end

      def create_ext(oid, value, critical = nil)
        value = Ossl.string_value(value)
        critical = false if critical.nil?
        oid_name = Ossl.cstring_value(oid)
        nid = Lib.OBJ_ln2nid(oid_name)
        oid_name = Lib.string(Lib.OBJ_nid2sn(nid)) unless nid == Lib::NID_undef
        text = (critical ? "critical," : "").b + value
        Ossl.cstring_value(text)
        ctx = Ossl::X509_EXT_FACTORY.fetch(self)
        @config = nil unless instance_variable_defined?(:@config)
        conf = @config.nil? ? nil : Ossl::CONFIG.fetch(@config)
        Lib.X509V3_set_nconf(ctx, conf)
        ext = Lib.X509V3_EXT_nconf(conf, ctx, oid_name, text)
        Lib.X509V3_set_ctx_nodb(ctx)
        raise Ossl.error(ExtensionError, "#{oid} = #{text}") if ext.zero?

        Ossl::X509_EXT.wrap(Extension, ext)
      end
    end

    class Extension
      def initialize(*args)
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..3)" unless args.size.between?(1, 3)

        Ossl::X509_EXT.fetch(self)
        oid, value, critical = args
        if args.size == 1
          der = Ossl.string_value(Ossl.to_der_if_possible(oid))
          holder = [Ossl::X509_EXT.take(self)].pack("J")
          decoded = Lib.d2i_X509_EXTENSION(holder, [Native.address(der)].pack("J"), der.bytesize)
          Ossl::X509_EXT.set(self, Lib.pointer_at(holder))
          raise Ossl.error(ExtensionError) if decoded.zero?

          return self
        end
        self.oid = oid
        self.value = value
        self.critical = critical if args.size > 2
        self
      end

      def initialize_copy(other)
        Ossl.check_frozen(self)
        Ossl::X509_EXT.unshare(self, other)
        Ossl::X509_EXT.fetch(self)
        copy = Lib.X509_EXTENSION_dup(Ossl::X509_EXT.fetch(other))
        raise Ossl.error(ExtensionError, "X509_EXTENSION_dup") if copy.zero?

        Ossl::X509_EXT.set(self, copy)
        self
      end

      def oid=(oid)
        ext = Ossl::X509_EXT.fetch(self)
        object = Lib.OBJ_txt2obj(Ossl.cstring_value(oid), 0)
        raise Ossl.error(ExtensionError, "OBJ_txt2obj") if object.zero?

        begin
          raise Ossl.error(ExtensionError, "X509_EXTENSION_set_object") if Lib.X509_EXTENSION_set_object(ext, object).zero?
        ensure
          Lib.ASN1_OBJECT_free(object)
        end
        oid
      end

      def value=(data)
        ext = Ossl::X509_EXT.fetch(self)
        data = Ossl.string_value(Ossl.to_der_if_possible(data))
        octets = Lib.ASN1_OCTET_STRING_new
        raise Ossl.error(ExtensionError, "ASN1_OCTET_STRING_new") if octets.zero?

        begin
          raise Ossl.error(ExtensionError, "ASN1_OCTET_STRING_set") if Lib.ASN1_OCTET_STRING_set(octets, data, data.bytesize).zero?
          raise Ossl.error(ExtensionError, "X509_EXTENSION_set_data") if Lib.X509_EXTENSION_set_data(ext, octets).zero?
        ensure
          Lib.ASN1_OCTET_STRING_free(octets)
        end
        data
      end

      def critical=(flag)
        Lib.X509_EXTENSION_set_critical(Ossl::X509_EXT.fetch(self), flag ? 1 : 0)
        flag
      end

      def oid = Ossl.asn1obj_to_string(Lib.X509_EXTENSION_get_object(Ossl::X509_EXT.fetch(self)))

      def value
        ext = Ossl::X509_EXT.fetch(self)
        Ossl.bio_output(ExtensionError) do |bio|
          Lib.ASN1_STRING_print(bio, Lib.X509_EXTENSION_get_data(ext)) if Lib.X509V3_EXT_print(bio, ext, 0, 0).zero?
          true
        end
      end

      def value_der
        data = Lib.X509_EXTENSION_get_data(Ossl::X509_EXT.fetch(self))
        raise Ossl.error(ExtensionError) if data.zero?

        Ossl.asn1str_to_str(data)
      end

      def critical? = !Lib.X509_EXTENSION_get_critical(Ossl::X509_EXT.fetch(self)).zero?

      def to_der = Ossl.i2d(:i2d_X509_EXTENSION, Ossl::X509_EXT.fetch(self), ExtensionError)
    end
  end
end
