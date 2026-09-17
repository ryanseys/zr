# frozen_string_literal: true

# ossl_x509cert.c: OpenSSL::X509::Certificate over X509.
module OpenSSL
  Lib.attach_all(
    X509_new: [[], :pointer],
    d2i_X509_bio: [%i[pointer pointer], :pointer],
    PEM_read_bio_X509: [%i[pointer pointer pointer pointer], :pointer],
    i2d_X509: [%i[pointer buffer], :int],
    PEM_write_bio_X509: [%i[pointer pointer], :int],
    X509_print: [%i[pointer pointer], :int],
    X509_get_version: [%i[pointer], :long],
    X509_set_version: [%i[pointer long], :int],
    X509_get_serialNumber: [%i[pointer], :pointer],
    X509_set_serialNumber: [%i[pointer pointer], :int],
    X509_get0_tbs_sigalg: [%i[pointer], :pointer],
    X509_get_subject_name: [%i[pointer], :pointer],
    X509_set_subject_name: [%i[pointer pointer], :int],
    X509_get_issuer_name: [%i[pointer], :pointer],
    X509_set_issuer_name: [%i[pointer pointer], :int],
    X509_get0_notBefore: [%i[pointer], :pointer],
    X509_set1_notBefore: [%i[pointer pointer], :int],
    X509_get0_notAfter: [%i[pointer], :pointer],
    X509_set1_notAfter: [%i[pointer pointer], :int],
    X509_get_pubkey: [%i[pointer], :pointer],
    X509_set_pubkey: [%i[pointer pointer], :int],
    X509_sign: [%i[pointer pointer pointer], :int],
    X509_verify: [%i[pointer pointer], :int],
    X509_check_private_key: [%i[pointer pointer], :int],
    X509_get_ext_count: [%i[pointer], :int],
    X509_get_ext: [%i[pointer int], :pointer],
    X509_delete_ext: [%i[pointer int], :pointer],
    X509_add_ext: [%i[pointer pointer int], :int],
    X509_cmp: [%i[pointer pointer], :int],
    i2d_re_X509_tbs: [%i[pointer buffer], :int]
  )

  module Lib
    PEM_R_NO_START_LINE = 108 # pemerr.h
  end

  module X509
    class CertificateError < OpenSSLError; end

    class Certificate; end
  end

  module Ossl
    X509_CERT = DataType.new("OpenSSL/X509", X509::Certificate, :X509_free, [RuntimeError, "CERT wasn't initialized!"], alloc: lambda {
      Lib.X509_new.tap { |x509| raise Ossl.error(X509::CertificateError) if x509.zero? }
    })

    class << self
      # ossl_x509_new.
      def x509_new(x509)
        copy = Lib.X509_dup(x509)
        raise error(X509::CertificateError, "X509_dup") if copy.zero?

        X509_CERT.wrap(X509::Certificate, copy)
      end

      # GetX509CertPtr.
      def x509(object) = X509_CERT.fetch(object)

      # DupX509CertPtr.
      def dup_x509(object)
        x509 = X509_CERT.fetch(object)
        Lib.X509_up_ref(x509)
        x509
      end

      # load_chained_certificates_PEM.
      def load_pem_certificates(bio)
        certificate = Lib.PEM_read_bio_X509(bio, nil, nil, nil)
        if certificate.zero?
          clear_error if Lib.ERR_GET_REASON(Lib.ERR_peek_last_error) == Lib::PEM_R_NO_START_LINE
          raise error(X509::CertificateError) unless Lib.ERR_peek_last_error.zero?

          return nil
        end
        certificates = [take_certificate(certificate)]
        until (certificate = Lib.PEM_read_bio_X509(bio, nil, nil, nil)).zero?
          certificates << take_certificate(certificate)
        end
        if Lib.ERR_GET_REASON(Lib.ERR_peek_last_error) == Lib::PEM_R_NO_START_LINE
          clear_error
          return certificates
        end
        return certificates if !Lib.BIO_eof(bio).zero? && Lib.ERR_peek_last_error.zero?

        raise error(X509::CertificateError)
      end

      # load_chained_certificates_append: a Certificate copying
      # `certificate`, which is freed.
      def take_certificate(certificate)
        x509_new(certificate)
      ensure
        Lib.X509_free(certificate)
      end
    end
  end

  module X509
    class Certificate
      def self.load(buffer)
        bio, _buffer = Ossl.obj2bio(buffer)
        begin
          certificate = Lib.d2i_X509_bio(bio, nil)
          return [Ossl.take_certificate(certificate)] unless certificate.zero?

          Ossl.clear_error
          Ossl.bio_reset(bio)
          certificates = Ossl.load_pem_certificates(bio)
          return certificates if certificates

          raise Ossl.error(CertificateError, "Could not detect format of certificate data!")
        ensure
          Lib.BIO_free(bio)
        end
      end

      def initialize(*args)
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..1)" if args.size > 1

        Ossl.check_frozen(self)
        return self if args.empty?

        arg = Ossl.to_der_if_possible(args.first)
        bio, _arg = Ossl.obj2bio(arg)
        x509 = Lib.d2i_X509_bio(bio, nil)
        if x509.zero?
          Ossl.bio_reset(bio)
          x509 = Lib.PEM_read_bio_X509(bio, nil, nil, nil)
        end
        Lib.BIO_free(bio)
        raise Ossl.error(CertificateError, "PEM_read_bio_X509") if x509.zero?

        Ossl::X509_CERT.set(self, x509)
        self
      end

      def initialize_copy(other)
        Ossl.check_frozen(self)
        return self if equal?(other)

        Ossl::X509_CERT.unshare(self, other)
        Ossl::X509_CERT.fetch(self)
        copy = Lib.X509_dup(Ossl::X509_CERT.fetch(other))
        raise Ossl.error(CertificateError) if copy.zero?

        Ossl::X509_CERT.set(self, copy)
        self
      end

      def to_der = Ossl.i2d(:i2d_X509, Ossl.x509(self), CertificateError)

      def to_pem
        x509 = Ossl.x509(self)
        Ossl.bio_output(CertificateError) { |bio| Lib.PEM_write_bio_X509(bio, x509) }
      end
      alias to_s to_pem

      def to_text
        x509 = Ossl.x509(self)
        Ossl.bio_output(CertificateError) { |bio| Lib.X509_print(bio, x509) }
      end

      def version = Lib.X509_get_version(Ossl.x509(self))

      def version=(version)
        raise Ossl.error(CertificateError, "version must be >= 0!") if Ossl.long(version).negative?
        raise Ossl.error(CertificateError) if Lib.X509_set_version(Ossl.x509(self), Ossl.long(version)).zero?

        version
      end

      def signature_algorithm = Ossl.algorithm_name(Lib.X509_get0_tbs_sigalg(Ossl.x509(self)))

      def serial = Ossl.asn1integer_to_num(Lib.X509_get_serialNumber(Ossl.x509(self)))

      def serial=(num)
        x509 = Ossl.x509(self)
        Lib.X509_set_serialNumber(x509, Ossl.num_to_asn1integer(num, Lib.X509_get_serialNumber(x509)))
        num
      end

      def subject
        name = Lib.X509_get_subject_name(Ossl.x509(self))
        raise Ossl.error(CertificateError) if name.zero?

        Ossl.x509name_new(name)
      end

      def subject=(subject)
        x509 = Ossl.x509(self)
        raise Ossl.error(CertificateError) if Lib.X509_set_subject_name(x509, Ossl::X509_NAME.fetch(subject)).zero?

        subject
      end

      def issuer
        name = Lib.X509_get_issuer_name(Ossl.x509(self))
        raise Ossl.error(CertificateError) if name.zero?

        Ossl.x509name_new(name)
      end

      def issuer=(issuer)
        x509 = Ossl.x509(self)
        raise Ossl.error(CertificateError) if Lib.X509_set_issuer_name(x509, Ossl::X509_NAME.fetch(issuer)).zero?

        issuer
      end

      def not_before
        time = Lib.X509_get0_notBefore(Ossl.x509(self))
        raise Ossl.error(CertificateError) if time.zero?

        Ossl.asn1time_to_time(time)
      end

      def not_before=(time)
        x509 = Ossl.x509(self)
        Ossl.set_x509_time(time, CertificateError, "X509_set_notBefore") { |asn1time| Lib.X509_set1_notBefore(x509, asn1time) }
        time
      end

      def not_after
        time = Lib.X509_get0_notAfter(Ossl.x509(self))
        raise Ossl.error(CertificateError) if time.zero?

        Ossl.asn1time_to_time(time)
      end

      def not_after=(time)
        x509 = Ossl.x509(self)
        Ossl.set_x509_time(time, CertificateError, "X509_set_notAfter") { |asn1time| Lib.X509_set1_notAfter(x509, asn1time) }
        time
      end

      def public_key
        pkey = Lib.X509_get_pubkey(Ossl.x509(self))
        raise Ossl.error(CertificateError) if pkey.zero?

        Ossl.pkey_wrap(pkey)
      end

      def public_key=(key)
        x509 = Ossl.x509(self)
        pkey = Ossl.pkey(key)
        Ossl.check_public_key(pkey)
        raise Ossl.error(CertificateError, "X509_set_pubkey") if Lib.X509_set_pubkey(x509, pkey).zero?

        key
      end

      def sign(key, digest)
        pkey = Ossl.private_pkey(key)
        md, _holder = Ossl.optional_md(digest)
        raise Ossl.error(CertificateError, "X509_sign") if Lib.X509_sign(Ossl.x509(self), pkey, md).zero?

        self
      end

      def verify(key)
        x509 = Ossl.x509(self)
        pkey = Ossl.pkey(key)
        Ossl.check_public_key(pkey)
        case Lib.X509_verify(x509, pkey)
        when 1 then true
        when 0
          Ossl.clear_error
          false
        else raise Ossl.error(CertificateError)
        end
      end

      def check_private_key(key)
        pkey = Ossl.private_pkey(key)
        return true unless Lib.X509_check_private_key(Ossl.x509(self), pkey).zero?

        Ossl.clear_error
        false
      end

      def extensions
        x509 = Ossl.x509(self)
        Array.new(Lib.X509_get_ext_count(x509)) { |i| Ossl.x509ext_new(Lib.X509_get_ext(x509, i)) }
      end

      def extensions=(extensions)
        Ossl.check_array(extensions)
        extensions.each { |extension| Ossl.check_kind(extension, Extension) }
        x509 = Ossl.x509(self)
        Lib.X509_get_ext_count(x509).times { Lib.X509_EXTENSION_free(Lib.X509_delete_ext(x509, 0)) }
        extensions.each do |extension|
          raise Ossl.error(CertificateError, "X509_add_ext") if Lib.X509_add_ext(x509, Ossl::X509_EXT.fetch(extension), -1).zero?
        end
        extensions
      end

      def add_extension(extension)
        x509 = Ossl.x509(self)
        raise Ossl.error(CertificateError) if Lib.X509_add_ext(x509, Ossl::X509_EXT.fetch(extension), -1).zero?

        extension
      end

      def ==(other)
        x509 = Ossl.x509(self)
        return false unless other.is_a?(Certificate)

        Lib.X509_cmp(x509, Ossl.x509(other)).zero?
      end

      def tbs_bytes = Ossl.i2d(:i2d_re_X509_tbs, Ossl.x509(self), CertificateError, "i2d_re_X509_tbs")
    end
  end
end
