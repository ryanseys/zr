# frozen_string_literal: true

# ossl_x509revoked.c: OpenSSL::X509::Revoked over X509_REVOKED.
module OpenSSL
  Lib.attach_all(
    X509_REVOKED_new: [[], :pointer],
    X509_REVOKED_dup: [%i[pointer], :pointer],
    X509_REVOKED_get0_serialNumber: [%i[pointer], :pointer],
    X509_REVOKED_set_serialNumber: [%i[pointer pointer], :int],
    X509_REVOKED_get0_revocationDate: [%i[pointer], :pointer],
    X509_REVOKED_set_revocationDate: [%i[pointer pointer], :int],
    X509_REVOKED_get_ext_count: [%i[pointer], :int],
    X509_REVOKED_get_ext: [%i[pointer int], :pointer],
    X509_REVOKED_delete_ext: [%i[pointer int], :pointer],
    X509_REVOKED_add_ext: [%i[pointer pointer int], :int],
    i2d_X509_REVOKED: [%i[pointer buffer], :int]
  )

  module X509
    class RevokedError < OpenSSLError; end

    class Revoked; end
  end

  module Ossl
    X509_REVOKED = DataType.new("OpenSSL/X509/REV", X509::Revoked, :X509_REVOKED_free, [RuntimeError, "REV wasn't initialized!"], alloc: lambda {
      Lib.X509_REVOKED_new.tap { |rev| raise Ossl.error(X509::RevokedError) if rev.zero? }
    })

    class << self
      # ossl_x509revoked_new.
      def x509revoked_new(rev)
        copy = Lib.X509_REVOKED_dup(rev)
        raise error(X509::RevokedError, "X509_REVOKED_dup") if copy.zero?

        X509_REVOKED.wrap(X509::Revoked, copy)
      end

      # DupX509RevokedPtr.
      def dup_x509revoked(object)
        copy = Lib.X509_REVOKED_dup(X509_REVOKED.fetch(object))
        raise error(X509::RevokedError) if copy.zero?

        copy
      end
    end
  end

  module X509
    class Revoked
      def initialize(*) = self

      def initialize_copy(other)
        Ossl.check_frozen(self)
        Ossl::X509_REVOKED.unshare(self, other)
        Ossl::X509_REVOKED.fetch(self)
        copy = Lib.X509_REVOKED_dup(Ossl::X509_REVOKED.fetch(other))
        raise Ossl.error(RevokedError, "X509_REVOKED_dup") if copy.zero?

        Ossl::X509_REVOKED.set(self, copy)
        self
      end

      def serial = Ossl.asn1integer_to_num(Lib.X509_REVOKED_get0_serialNumber(Ossl::X509_REVOKED.fetch(self)))

      def serial=(num)
        rev = Ossl::X509_REVOKED.fetch(self)
        integer = Ossl.num_to_asn1integer(num)
        begin
          raise Ossl.error(RevokedError, "X509_REVOKED_set_serialNumber") if Lib.X509_REVOKED_set_serialNumber(rev, integer).zero?
        ensure
          Lib.ASN1_INTEGER_free(integer)
        end
        num
      end

      def time
        time = Lib.X509_REVOKED_get0_revocationDate(Ossl::X509_REVOKED.fetch(self))
        time.zero? ? nil : Ossl.asn1time_to_time(time)
      end

      def time=(time)
        rev = Ossl::X509_REVOKED.fetch(self)
        Ossl.set_x509_time(time, RevokedError, "X509_REVOKED_set_revocationDate") { |asn1time| Lib.X509_REVOKED_set_revocationDate(rev, asn1time) }
        time
      end

      def extensions
        rev = Ossl::X509_REVOKED.fetch(self)
        Array.new(Lib.X509_REVOKED_get_ext_count(rev)) { |i| Ossl.x509ext_new(Lib.X509_REVOKED_get_ext(rev, i)) }
      end

      def extensions=(extensions)
        Ossl.check_array(extensions)
        extensions.each { |extension| Ossl.check_kind(extension, Extension) }
        rev = Ossl::X509_REVOKED.fetch(self)
        Lib.X509_REVOKED_get_ext_count(rev).times { Lib.X509_EXTENSION_free(Lib.X509_REVOKED_delete_ext(rev, 0)) }
        extensions.each do |extension|
          raise Ossl.error(RevokedError, "X509_REVOKED_add_ext") if Lib.X509_REVOKED_add_ext(rev, Ossl::X509_EXT.fetch(extension), -1).zero?
        end
        extensions
      end

      def add_extension(extension)
        rev = Ossl::X509_REVOKED.fetch(self)
        raise Ossl.error(RevokedError) if Lib.X509_REVOKED_add_ext(rev, Ossl::X509_EXT.fetch(extension), -1).zero?

        extension
      end

      def to_der = Ossl.i2d(:i2d_X509_REVOKED, Ossl::X509_REVOKED.fetch(self), RevokedError, "i2d_X509_REVOKED")
    end
  end
end
