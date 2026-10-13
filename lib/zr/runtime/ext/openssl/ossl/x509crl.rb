# frozen_string_literal: true

# ossl_x509crl.c: OpenSSL::X509::CRL over X509_CRL.
module OpenSSL
  Lib.attach_all(
    X509_CRL_new: [[], :pointer],
    X509_CRL_free: [%i[pointer], :void],
    X509_CRL_dup: [%i[pointer], :pointer],
    d2i_X509_CRL_bio: [%i[pointer pointer], :pointer],
    PEM_read_bio_X509_CRL: [%i[pointer pointer pointer pointer], :pointer],
    i2d_X509_CRL_bio: [%i[pointer pointer], :int],
    PEM_write_bio_X509_CRL: [%i[pointer pointer], :int],
    X509_CRL_print: [%i[pointer pointer], :int],
    X509_CRL_get_version: [%i[pointer], :long],
    X509_CRL_set_version: [%i[pointer long], :int],
    X509_CRL_get0_signature: [%i[pointer buffer buffer], :void],
    X509_CRL_get_issuer: [%i[pointer], :pointer],
    X509_CRL_set_issuer_name: [%i[pointer pointer], :int],
    X509_CRL_get0_lastUpdate: [%i[pointer], :pointer],
    X509_CRL_set1_lastUpdate: [%i[pointer pointer], :int],
    X509_CRL_get0_nextUpdate: [%i[pointer], :pointer],
    X509_CRL_set1_nextUpdate: [%i[pointer pointer], :int],
    X509_CRL_get_REVOKED: [%i[pointer], :pointer],
    X509_CRL_add0_revoked: [%i[pointer pointer], :int],
    X509_CRL_get0_by_serial: [%i[pointer buffer pointer], :int],
    X509_CRL_sort: [%i[pointer], :int],
    X509_CRL_sign: [%i[pointer pointer pointer], :int],
    X509_CRL_verify: [%i[pointer pointer], :int],
    X509_CRL_get_ext_count: [%i[pointer], :int],
    X509_CRL_get_ext: [%i[pointer int], :pointer],
    X509_CRL_delete_ext: [%i[pointer int], :pointer],
    X509_CRL_add_ext: [%i[pointer pointer int], :int],
    X509_REVOKED_free: [%i[pointer], :void]
  )

  module X509
    class CRLError < OpenSSLError; end

    class CRL; end
  end

  module Ossl
    X509_CRL = DataType.new("OpenSSL/X509/CRL", X509::CRL, :X509_CRL_free, [RuntimeError, "CRL wasn't initialized!"], alloc: lambda {
      Lib.X509_CRL_new.tap { |crl| raise Ossl.error(X509::CRLError) if crl.zero? }
    })

    class << self
      # GetX509CRLPtr.
      def x509crl(object) = X509_CRL.fetch(object)

      # ossl_x509crl_new.
      def x509crl_new(crl)
        copy = Lib.X509_CRL_dup(crl)
        raise error(X509::CRLError, "X509_CRL_dup") if copy.zero?

        X509_CRL.wrap(X509::CRL, copy)
      end

      # X509_CRL_add0_revoked over a copy of `revoked`'s struct, then
      # X509_CRL_sort.
      def x509crl_add_revoked(crl, revoked)
        rev = dup_x509revoked(revoked)
        if Lib.X509_CRL_add0_revoked(crl, rev).zero?
          Lib.X509_REVOKED_free(rev)
          raise error(X509::CRLError, "X509_CRL_add0_revoked")
        end
      end
    end
  end

  module X509
    class CRL
      def initialize(*args)
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..1)" if args.size > 1

        Ossl.check_frozen(self)
        return self if args.empty?

        bio, _arg = Ossl.obj2bio(Ossl.to_der_if_possible(args.first))
        crl = Lib.d2i_X509_CRL_bio(bio, nil)
        if crl.zero?
          Ossl.bio_reset(bio)
          crl = Lib.PEM_read_bio_X509_CRL(bio, nil, nil, nil)
        end
        Lib.BIO_free(bio)
        raise Ossl.error(CRLError, "PEM_read_bio_X509_CRL") if crl.zero?

        Ossl::X509_CRL.set(self, crl)
        self
      end

      def initialize_copy(other)
        Ossl.check_frozen(self)
        return self if equal?(other)

        Ossl::X509_CRL.unshare(self, other)
        Ossl::X509_CRL.fetch(self)
        copy = Lib.X509_CRL_dup(Ossl::X509_CRL.fetch(other))
        raise Ossl.error(CRLError) if copy.zero?

        Ossl::X509_CRL.set(self, copy)
        self
      end

      def version = Lib.X509_CRL_get_version(Ossl.x509crl(self))

      def version=(version)
        raise Ossl.error(CRLError, "version must be >= 0!") if Ossl.long(version).negative?
        raise Ossl.error(CRLError) if Lib.X509_CRL_set_version(Ossl.x509crl(self), Ossl.long(version)).zero?

        version
      end

      def signature_algorithm
        algor = Lib.buffer(8)
        Lib.X509_CRL_get0_signature(Ossl.x509crl(self), nil, algor)
        Ossl.algorithm_name(Lib.pointer_at(algor))
      end

      def issuer = Ossl.x509name_new(Lib.X509_CRL_get_issuer(Ossl.x509crl(self)))

      def issuer=(issuer)
        crl = Ossl.x509crl(self)
        raise Ossl.error(CRLError) if Lib.X509_CRL_set_issuer_name(crl, Ossl::X509_NAME.fetch(issuer)).zero?

        issuer
      end

      def last_update
        time = Lib.X509_CRL_get0_lastUpdate(Ossl.x509crl(self))
        time.zero? ? nil : Ossl.asn1time_to_time(time)
      end

      def last_update=(time)
        crl = Ossl.x509crl(self)
        Ossl.set_x509_time(time, CRLError, "X509_CRL_set_lastUpdate") { |asn1time| Lib.X509_CRL_set1_lastUpdate(crl, asn1time) }
        time
      end

      def next_update
        time = Lib.X509_CRL_get0_nextUpdate(Ossl.x509crl(self))
        time.zero? ? nil : Ossl.asn1time_to_time(time)
      end

      def next_update=(time)
        crl = Ossl.x509crl(self)
        Ossl.set_x509_time(time, CRLError, "X509_CRL_set_nextUpdate") { |asn1time| Lib.X509_CRL_set1_nextUpdate(crl, asn1time) }
        time
      end

      def revoked = Ossl.stack_items(Lib.X509_CRL_get_REVOKED(Ossl.x509crl(self))).map { |rev| Ossl.x509revoked_new(rev) }

      # The revoked entry of the serial number `serial`, a copy that
      # outlives the CRL, or nil.
      def by_serial(serial)
        crl = Ossl.x509crl(self)
        number = Ossl.num_to_asn1integer(serial)
        found = Lib.buffer(8)
        begin
          return nil if Lib.X509_CRL_get0_by_serial(crl, found, number).zero?
        ensure
          Lib.ASN1_INTEGER_free(number)
        end
        Ossl.x509revoked_new(Lib.pointer_at(found))
      end

      def revoked=(revoked)
        Ossl.check_array(revoked)
        revoked.each { |rev| Ossl.check_kind(rev, Revoked) }
        crl = Ossl.x509crl(self)
        stack = Lib.X509_CRL_get_REVOKED(crl)
        until stack.zero? || (rev = Lib.OPENSSL_sk_pop(stack)).zero?
          Lib.X509_REVOKED_free(rev)
        end
        revoked.each { |rev| Ossl.x509crl_add_revoked(crl, rev) }
        Lib.X509_CRL_sort(crl)
        revoked
      end

      def add_revoked(revoked)
        crl = Ossl.x509crl(self)
        Ossl.x509crl_add_revoked(crl, revoked)
        Lib.X509_CRL_sort(crl)
        revoked
      end

      def sign(key, digest)
        crl = Ossl.x509crl(self)
        pkey = Ossl.private_pkey(key)
        md, _holder = Ossl.optional_md(digest)
        raise Ossl.error(CRLError, "X509_CRL_sign") if Lib.X509_CRL_sign(crl, pkey, md).zero?

        self
      end

      def verify(key)
        crl = Ossl.x509crl(self)
        pkey = Ossl.pkey(key)
        Ossl.check_public_key(pkey)
        case Lib.X509_CRL_verify(crl, pkey)
        when 1 then true
        when 0
          Ossl.clear_error
          false
        else raise Ossl.error(CRLError)
        end
      end

      def to_der
        crl = Ossl.x509crl(self)
        Ossl.bio_output(CRLError) { |bio| Lib.i2d_X509_CRL_bio(bio, crl) }
      end

      def to_pem
        crl = Ossl.x509crl(self)
        Ossl.bio_output(CRLError) { |bio| Lib.PEM_write_bio_X509_CRL(bio, crl) }
      end
      alias to_s to_pem

      def to_text
        crl = Ossl.x509crl(self)
        Ossl.bio_output(CRLError) { |bio| Lib.X509_CRL_print(bio, crl) }
      end

      def extensions
        crl = Ossl.x509crl(self)
        Array.new(Lib.X509_CRL_get_ext_count(crl)) { |i| Ossl.x509ext_new(Lib.X509_CRL_get_ext(crl, i)) }
      end

      def extensions=(extensions)
        Ossl.check_array(extensions)
        extensions.each { |extension| Ossl.check_kind(extension, Extension) }
        crl = Ossl.x509crl(self)
        Lib.X509_CRL_get_ext_count(crl).times { Lib.X509_EXTENSION_free(Lib.X509_CRL_delete_ext(crl, 0)) }
        extensions.each do |extension|
          raise Ossl.error(CRLError, "X509_CRL_add_ext") if Lib.X509_CRL_add_ext(crl, Ossl::X509_EXT.fetch(extension), -1).zero?
        end
        extensions
      end

      def add_extension(extension)
        crl = Ossl.x509crl(self)
        raise Ossl.error(CRLError) if Lib.X509_CRL_add_ext(crl, Ossl::X509_EXT.fetch(extension), -1).zero?

        extension
      end
    end
  end
end
